import '../../core/utils/version_utils.dart';

/// Asset de una GitHub Release (APK u otro).
class GitHubReleaseAsset {
  const GitHubReleaseAsset({
    required this.name,
    required this.size,
    required this.browserDownloadUrl,
    this.digest,
  });

  final String name;
  final int size;
  final String browserDownloadUrl;

  /// Valor crudo de la API (`sha256:...`) o `null`.
  final String? digest;

  String? get sha256Hex => parseSha256Digest(digest);

  bool get isApk => name.toLowerCase().endsWith('.apk');

  bool get isNexusApk {
    final lower = name.toLowerCase();
    return lower.endsWith('.apk') &&
        (lower.startsWith('android-regispro-') ||
            lower.startsWith('android-nexus-'));
  }

  bool get isZip => name.toLowerCase().endsWith('.zip');

  /// Solo el paquete de app (`windows-regispro-v*.zip`), no bootstrap ni otros.
  /// Acepta el prefijo legacy `windows-nexus-` por compatibilidad.
  bool get isNexusWindowsZip {
    final lower = name.toLowerCase();
    return lower.endsWith('.zip') &&
        (lower.startsWith('windows-regispro-') ||
            lower.startsWith('windows-nexus-'));
  }

  factory GitHubReleaseAsset.fromJson(Map<String, dynamic> json) {
    return GitHubReleaseAsset(
      name: json['name'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      browserDownloadUrl: json['browser_download_url'] as String? ?? '',
      digest: json['digest'] as String?,
    );
  }
}

/// Representación tipada de `GET /repos/{owner}/{repo}/releases/latest`.
class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.prerelease,
    required this.assets,
  });

  final String tagName;
  final String name;
  final String body;
  final bool prerelease;
  final List<GitHubReleaseAsset> assets;

  String get notesForDisplay => releaseNotesForDisplay(body);

  /// SemVer derivado de [tagName], o `null` si el tag no es parseable.
  String? get versionString {
    final v = tryParseVersion(tagName);
    return v?.toString();
  }

  /// Resuelve el APK de RegisPro según el contrato del plan.
  ///
  /// 1. Solo assets `android-regispro-*.apk` (o legacy `android-nexus-*.apk`).
  /// 2. Preferir el que coincide con el tag (`android-regispro-vX.Y.Z.apk`).
  /// 3. Si hay varios, el de mayor [GitHubReleaseAsset.size].
  GitHubReleaseAsset? resolveNexusApk() {
    final candidates = assets.where((a) => a.isNexusApk).toList();
    if (candidates.isEmpty) return null;

    final tag = stripVersionPrefix(tagName);
    final preferred = <String>[
      'android-regispro-v$tag.apk',
      'android-nexus-v$tag.apk',
    ];
    for (final exactName in preferred) {
      for (final c in candidates) {
        if (c.name.toLowerCase() == exactName) return c;
      }
    }

    candidates.sort((a, b) => b.size.compareTo(a.size));
    return candidates.first;
  }

  /// Resuelve el ZIP de Windows según el contrato OTA.
  ///
  /// 1. Solo assets `windows-regispro-*.zip` (o legacy `windows-nexus-*.zip`).
  /// 2. Preferir el que coincide con el tag (`windows-regispro-vX.Y.Z.zip`).
  /// 3. Si hay varios, el de mayor [GitHubReleaseAsset.size].
  GitHubReleaseAsset? resolveNexusWindowsZip() {
    final candidates = assets.where((a) => a.isNexusWindowsZip).toList();
    if (candidates.isEmpty) return null;

    final tag = stripVersionPrefix(tagName);
    final preferred = <String>[
      'windows-regispro-v$tag.zip',
      'windows-nexus-v$tag.zip',
    ];
    for (final exactName in preferred) {
      for (final c in candidates) {
        if (c.name.toLowerCase() == exactName) return c;
      }
    }

    candidates.sort((a, b) => b.size.compareTo(a.size));
    return candidates.first;
  }

  /// Asset OTA para la plataforma actual (`android` | `windows`).
  GitHubReleaseAsset? resolveNexusAsset({required bool forWindows}) {
    return forWindows ? resolveNexusWindowsZip() : resolveNexusApk();
  }

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'];
    final assets = <GitHubReleaseAsset>[];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is Map<String, dynamic>) {
          assets.add(GitHubReleaseAsset.fromJson(item));
        } else if (item is Map) {
          assets.add(
            GitHubReleaseAsset.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return GitHubRelease(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      prerelease: json['prerelease'] as bool? ?? false,
      assets: assets,
    );
  }
}
