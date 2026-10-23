import 'dart:developer' as developer;
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/version_utils.dart';
import '../../../data/models/github_release.dart';
import '../../../data/repositories/github_release_repository.dart';
import 'apk_downloader.dart';
import 'apk_installer.dart';
import 'update_platform.dart';
import 'windows_installer.dart';

/// Información de una actualización disponible.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.installedVersion,
    required this.remoteVersion,
    required this.releaseName,
    required this.notes,
    required this.asset,
    required this.tagName,
  });

  final String installedVersion;
  final String remoteVersion;
  final String releaseName;
  final String notes;
  final GitHubReleaseAsset asset;
  final String tagName;

  String get formattedSize => formatBytes(asset.size);
}

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  awaitingInstallPermission,
  downloading,
  verifying,
  installing,
  failed,
}

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.info,
    this.progress = 0,
    this.errorMessage,
    this.needsInstallPermission = false,
    this.downloadedFilePath,
  });

  final UpdateStatus status;
  final AppUpdateInfo? info;
  final double progress;
  final String? errorMessage;
  final bool needsInstallPermission;
  final String? downloadedFilePath;

  bool get isBusy =>
      status == UpdateStatus.checking ||
      status == UpdateStatus.downloading ||
      status == UpdateStatus.verifying ||
      status == UpdateStatus.installing;

  /// Hay una versión nueva sin instalar: disponible, bajándose o con un
  /// intento fallido. Sigue siendo `true` durante un re-check (el `info` se
  /// conserva), así el aviso del inicio no parpadea al volver a la app.
  bool get hasPendingUpdate =>
      info != null &&
      status != UpdateStatus.idle &&
      status != UpdateStatus.upToDate;

  UpdateState copyWith({
    UpdateStatus? status,
    AppUpdateInfo? info,
    double? progress,
    String? errorMessage,
    bool? needsInstallPermission,
    String? downloadedFilePath,
    bool clearError = false,
    bool clearInfo = false,
    bool clearDownloaded = false,
  }) {
    return UpdateState(
      status: status ?? this.status,
      info: clearInfo ? null : (info ?? this.info),
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      needsInstallPermission:
          needsInstallPermission ?? this.needsInstallPermission,
      downloadedFilePath: clearDownloaded
          ? null
          : (downloadedFilePath ?? this.downloadedFilePath),
    );
  }
}

enum UpdateInstallOutcome {
  launched,
  permissionRequired,
  unsupportedPlatform,
  failed,
}

class UpdateInstallResult {
  const UpdateInstallResult(this.outcome, {this.message});

  final UpdateInstallOutcome outcome;
  final String? message;
}

const _prefsLastRateLimitMs = 'ota_last_rate_limit_ms';
const _rateLimitBackoff = Duration(hours: 1);

/// Evita martillar GitHub si el usuario cambia de app muy seguido.
const _resumeMinInterval = Duration(seconds: 30);

/// Resultado de un check OTA (distingue skip vs al día vs disponible).
class UpdateCheckOutcome {
  const UpdateCheckOutcome._({required this.performed, this.info});

  const UpdateCheckOutcome.skipped() : this._(performed: false);

  const UpdateCheckOutcome.upToDate() : this._(performed: true);

  const UpdateCheckOutcome.available(AppUpdateInfo info)
    : this._(performed: true, info: info);

  /// `false` si no se consultó la red (debounce, sesión, backoff, etc.).
  final bool performed;
  final AppUpdateInfo? info;

  bool get hasUpdate => info != null;
}

/// Orquesta check → diálogo → descarga → verify → install.
class UpdateService {
  UpdateService({
    required this._source,
    required this._prefs,
    ApkDownloader? downloader,
    ApkInstaller? apkInstaller,
    WindowsInstaller? windowsInstaller,
  }) : _downloader = downloader ?? ApkDownloader(),
       _apkInstaller = apkInstaller ?? ApkInstaller(),
       _windowsInstaller = windowsInstaller ?? WindowsInstaller();

  final UpdateSource _source;
  final SharedPreferences _prefs;
  final ApkDownloader _downloader;
  final ApkInstaller _apkInstaller;
  final WindowsInstaller _windowsInstaller;

  bool _checkedThisSession = false;
  DateTime? _lastAutoCheckAt;

  /// Consulta GitHub Releases y decide si hay update.
  ///
  /// [force]: ignora debounce, sesión y backoff (check manual).
  /// [onResume]: ignora debounce de 6h y flag de sesión; respeta backoff
  /// y un intervalo mínimo corto entre checks automáticos.
  Future<UpdateCheckOutcome> checkForUpdates({
    bool force = false,
    bool manual = false,
    bool onResume = false,
  }) async {
    if (!otaUpdatesSupported) {
      return const UpdateCheckOutcome.skipped();
    }

    if (!force) {
      if (_isInRateLimitBackoff()) {
        developer.log('OTA: backoff por rate limit.', name: 'UpdateService');
        return const UpdateCheckOutcome.skipped();
      }
      if (onResume) {
        if (!_shouldCheckOnResume()) {
          developer.log(
            'OTA: resume demasiado seguido (<${_resumeMinInterval.inSeconds}s).',
            name: 'UpdateService',
          );
          return const UpdateCheckOutcome.skipped();
        }
      } else {
        // Al abrir home: una consulta por sesión (sin debounce de 6h).
        if (_checkedThisSession) {
          developer.log(
            'OTA: ya se consultó en esta sesión.',
            name: 'UpdateService',
          );
          return const UpdateCheckOutcome.skipped();
        }
      }
    }

    _checkedThisSession = true;
    _lastAutoCheckAt = DateTime.now();

    try {
      final forWindows = otaResolvesWindowsAsset;
      final release = await _source.fetchLatestWithAsset(
        forWindows: forWindows,
      );

      if (release.prerelease) {
        developer.log(
          'OTA: latest es prerelease; se ignora en canal stable.',
          name: 'UpdateService',
        );
        return const UpdateCheckOutcome.upToDate();
      }

      final remote = tryParseVersion(release.tagName);
      if (remote == null) {
        developer.log(
          'OTA: tag no SemVer (${release.tagName}).',
          name: 'UpdateService',
        );
        return const UpdateCheckOutcome.upToDate();
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final installed = tryParseVersion(packageInfo.version);
      if (installed == null) {
        developer.log(
          'OTA: versión instalada inválida (${packageInfo.version}).',
          name: 'UpdateService',
        );
        return const UpdateCheckOutcome.upToDate();
      }

      if (!isRemoteNewer(installed, remote)) {
        developer.log(
          'OTA: al día ($installed >= $remote).',
          name: 'UpdateService',
        );
        return const UpdateCheckOutcome.upToDate();
      }

      final asset = release.resolveNexusAsset(forWindows: forWindows);
      if (asset == null || asset.browserDownloadUrl.isEmpty) {
        final listed = release.assets
            .map((a) => a.name)
            .where((n) => n.isNotEmpty)
            .join(', ');
        developer.log(
          'OTA: Release sin asset RegisPro (${forWindows ? 'Windows' : 'Android'}). '
          'Assets: ${listed.isEmpty ? '(ninguno)' : listed}',
          name: 'UpdateService',
        );
        if (manual) {
          final tag = stripVersionPrefix(release.tagName);
          final expected = forWindows
              ? 'windows-regispro-v$tag.zip'
              : 'android-regispro-v$tag.apk';
          final suffix = listed.isEmpty ? '' : ' Archivos publicados: $listed.';
          throw GitHubReleaseException(
            forWindows
                ? 'La última Release no incluye un paquete Windows de RegisPro '
                      '(se esperaba $expected).$suffix'
                : 'La última Release no incluye un APK de RegisPro '
                      '(se esperaba $expected).$suffix',
          );
        }
        return const UpdateCheckOutcome.upToDate();
      }

      // Ninguna actualización es obligatoria: el inicio la avisa con una
      // tarjeta y se instala desde Actualizaciones cuando el usuario quiera.
      return UpdateCheckOutcome.available(
        AppUpdateInfo(
          installedVersion: installed.toString(),
          remoteVersion: remote.toString(),
          releaseName: release.name.isNotEmpty
              ? release.name
              : 'RegisPro v${remote.toString()}',
          notes: release.notesForDisplay,
          asset: asset,
          tagName: release.tagName,
        ),
      );
    } on GitHubReleaseException catch (e) {
      if (e.isRateLimited) {
        await _prefs.setInt(
          _prefsLastRateLimitMs,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      developer.log('OTA check falló: $e', name: 'UpdateService');
      if (manual) rethrow;
      return const UpdateCheckOutcome.skipped();
    } catch (e, st) {
      developer.log(
        'OTA check inesperado: $e',
        name: 'UpdateService',
        stackTrace: st,
      );
      if (manual) rethrow;
      return const UpdateCheckOutcome.skipped();
    }
  }

  Future<File> downloadUpdate(
    AppUpdateInfo info, {
    void Function(double progress)? onProgress,
  }) {
    return _downloader.download(
      url: info.asset.browserDownloadUrl,
      fileName: info.asset.name,
      onProgress: onProgress,
    );
  }

  void cancelDownload() => _downloader.cancel();

  Future<bool> verifyDownload(File file, AppUpdateInfo info) async {
    final expected = info.asset.sha256Hex;
    if (expected == null) {
      developer.log(
        'OTA: Release sin digest SHA-256; se permite instalar (política v1).',
        name: 'UpdateService',
      );
      return true;
    }
    final ok = await verifyApkSha256(file, expected);
    if (!ok) {
      try {
        await file.delete();
      } catch (_) {}
    }
    return ok;
  }

  Future<UpdateInstallResult> install(File file, {AppUpdateInfo? info}) async {
    if (Platform.isAndroid) {
      final result = await _apkInstaller.install(file);
      return UpdateInstallResult(
        _mapApkOutcome(result.outcome),
        message: result.message,
      );
    }
    if (Platform.isWindows) {
      final result = await _windowsInstaller.install(
        file,
        remoteVersion: info?.remoteVersion,
      );
      return UpdateInstallResult(
        _mapWindowsOutcome(result.outcome),
        message: result.message,
      );
    }
    return UpdateInstallResult(
      UpdateInstallOutcome.unsupportedPlatform,
      message: otaUnsupportedMessage,
    );
  }

  Future<bool> hasInstallPermission() => _apkInstaller.hasInstallPermission();

  Future<bool> ensureInstallPermission() =>
      _apkInstaller.ensureInstallPermission();

  Future<bool> openInstallSettings() => _apkInstaller.openInstallSettings();

  UpdateInstallOutcome _mapApkOutcome(ApkInstallOutcome outcome) {
    switch (outcome) {
      case ApkInstallOutcome.launched:
        return UpdateInstallOutcome.launched;
      case ApkInstallOutcome.permissionRequired:
        return UpdateInstallOutcome.permissionRequired;
      case ApkInstallOutcome.unsupportedPlatform:
        return UpdateInstallOutcome.unsupportedPlatform;
      case ApkInstallOutcome.failed:
        return UpdateInstallOutcome.failed;
    }
  }

  UpdateInstallOutcome _mapWindowsOutcome(WindowsInstallOutcome outcome) {
    switch (outcome) {
      case WindowsInstallOutcome.launched:
        return UpdateInstallOutcome.launched;
      case WindowsInstallOutcome.unsupportedPlatform:
        return UpdateInstallOutcome.unsupportedPlatform;
      case WindowsInstallOutcome.failed:
        return UpdateInstallOutcome.failed;
    }
  }

  bool _shouldCheckOnResume() {
    final last = _lastAutoCheckAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _resumeMinInterval;
  }

  bool _isInRateLimitBackoff() {
    final last = _prefs.getInt(_prefsLastRateLimitMs);
    if (last == null) return false;
    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(last),
    );
    return elapsed < _rateLimitBackoff;
  }

  /// Expone comparación pura para tests.
  static bool wouldUpdate({
    required Version installed,
    required Version remote,
  }) => isRemoteNewer(installed, remote);
}
