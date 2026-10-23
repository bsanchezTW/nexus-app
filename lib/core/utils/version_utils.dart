import 'package:pub_semver/pub_semver.dart';

/// Marcador en el body de una GitHub Release que fuerza actualización.
const forceUpdateMarker = '[FORCE_UPDATE]';

/// Quita el prefijo `v`/`V` de un tag GitHub (`v1.2.3` → `1.2.3`).
String stripVersionPrefix(String tagOrVersion) {
  final trimmed = tagOrVersion.trim();
  if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
    return trimmed.substring(1);
  }
  return trimmed;
}

/// Parsea un tag o versión a [Version], o `null` si no es SemVer válido.
Version? tryParseVersion(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    return Version.parse(stripVersionPrefix(raw));
  } on FormatException {
    return null;
  }
}

/// `true` si [remote] es estrictamente mayor que [installed].
bool isRemoteNewer(Version installed, Version remote) => remote > installed;

/// Body limpio para mostrar al usuario. Las releases antiguas traen el
/// marcador de actualización obligatoria, que ya no se respeta: ninguna
/// actualización bloquea la app.
String releaseNotesForDisplay(String? body) {
  if (body == null || body.isEmpty) return '';
  return body
      .replaceAll(forceUpdateMarker, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Extrae el hex SHA-256 desde el campo `digest` de GitHub (`sha256:abc...`).
String? parseSha256Digest(String? digest) {
  if (digest == null || digest.isEmpty) return null;
  final trimmed = digest.trim();
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('sha256:')) {
    final hex = trimmed.substring(7).trim().toLowerCase();
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return hex;
    return null;
  }
  if (RegExp(r'^[0-9a-f]{64}$').hasMatch(lower)) return lower;
  return null;
}

/// Formatea bytes a texto legible (p. ej. `77.0 MB`).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
