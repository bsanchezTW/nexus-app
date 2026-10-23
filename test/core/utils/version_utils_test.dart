import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:transworld_nexus/core/utils/version_utils.dart';
import 'package:transworld_nexus/data/models/github_release.dart';

void main() {
  group('version_utils', () {
    test('stripVersionPrefix quita v/V', () {
      expect(stripVersionPrefix('v1.2.3'), '1.2.3');
      expect(stripVersionPrefix('V2.0.0'), '2.0.0');
      expect(stripVersionPrefix('1.0.0'), '1.0.0');
    });

    test('compara 2.0.9 < 2.0.10 correctamente', () {
      final a = tryParseVersion('2.0.9')!;
      final b = tryParseVersion('v2.0.10')!;
      expect(isRemoteNewer(a, b), isTrue);
      expect(isRemoteNewer(b, a), isFalse);
    });

    test('compara 1.9.0 < 1.10.0', () {
      expect(
        isRemoteNewer(Version.parse('1.9.0'), Version.parse('1.10.0')),
        isTrue,
      );
    });

    test('tryParseVersion acepta build de pubspec', () {
      expect(tryParseVersion('1.6.8+27')?.major, 1);
      expect(tryParseVersion('1.6.8+27')?.minor, 6);
      expect(tryParseVersion('1.6.8+27')?.patch, 8);
    });

    test('tryParseVersion rechaza tags inválidos', () {
      expect(tryParseVersion('latest'), isNull);
      expect(tryParseVersion(''), isNull);
      expect(tryParseVersion(null), isNull);
    });

    test('releaseNotesForDisplay limpia marcador', () {
      expect(
        releaseNotesForDisplay('Hola\n[FORCE_UPDATE]\nMundo'),
        'Hola\n\nMundo',
      );
    });

    test('parseSha256Digest acepta formato GitHub', () {
      const hex =
          'f31bcce2c190b84d61014bc93a67b76030230449f121c602494725159fadaa77';
      expect(parseSha256Digest('sha256:$hex'), hex);
      expect(parseSha256Digest(hex), hex);
      expect(parseSha256Digest('sha256:abc'), isNull);
      expect(parseSha256Digest(null), isNull);
    });

    test('formatBytes', () {
      expect(formatBytes(500), '500 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(80 * 1024 * 1024), '80.0 MB');
    });
  });

  group('GitHubRelease.resolveNexusApk', () {
    test('elige asset regispro exacto por tag', () {
      final release = GitHubRelease.fromJson({
        'tag_name': 'v1.2.0',
        'name': 'RegisPro 1.2.0',
        'body': 'notes',
        'prerelease': false,
        'assets': [
          {
            'name': 'android-regispro-v1.1.apk',
            'size': 10,
            'browser_download_url': 'https://example.com/old.apk',
          },
          {
            'name': 'android-regispro-v1.2.0.apk',
            'size': 20,
            'browser_download_url': 'https://example.com/new.apk',
            'digest':
                'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          },
        ],
      });

      final apk = release.resolveNexusApk();
      expect(apk?.name, 'android-regispro-v1.2.0.apk');
      expect(apk?.sha256Hex, startsWith('aaaa'));
    });

    test('si no hay match exacto, elige el apk más grande', () {
      final release = GitHubRelease.fromJson({
        'tag_name': 'v1.1.0',
        'name': 'RegisPro',
        'body': '[FORCE_UPDATE]',
        'prerelease': false,
        'assets': [
          {
            'name': 'android-regispro-v1.1.apk',
            'size': 100,
            'browser_download_url': 'https://example.com/a.apk',
          },
          {
            'name': 'android-regispro-arm64.apk',
            'size': 200,
            'browser_download_url': 'https://example.com/b.apk',
          },
        ],
      });

      expect(release.resolveNexusApk()?.name, 'android-regispro-arm64.apk');
    });

    test('sin APK retorna null', () {
      final release = GitHubRelease.fromJson({
        'tag_name': 'v1.0.0',
        'name': 'x',
        'body': '',
        'prerelease': false,
        'assets': [
          {
            'name': 'notes.txt',
            'size': 1,
            'browser_download_url': 'https://example.com/notes.txt',
          },
        ],
      });
      expect(release.resolveNexusApk(), isNull);
    });
  });
}
