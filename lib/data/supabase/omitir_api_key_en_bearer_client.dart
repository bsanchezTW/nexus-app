import 'package:http/http.dart';

/// `sb_publishable_…` / `sb_secret_…` no son JWT: no pueden ir en
/// `Authorization: Bearer`. El SDK Dart todavía las pone ahí cuando no hay
/// sesión (login y formulario público).
bool esApiKeyNuevaSupabase(String key) =>
    key.startsWith('sb_publishable_') || key.startsWith('sb_secret_');

String? bearerDeAuthorization(String? header) {
  if (header == null || header.isEmpty) return null;
  return header.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
}

/// Quita `Authorization` si el token es una API key nueva.
class OmitirApiKeyEnBearerClient extends BaseClient {
  OmitirApiKeyEnBearerClient([Client? inner]) : _inner = inner ?? Client();

  final Client _inner;

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    final auth =
        request.headers['Authorization'] ?? request.headers['authorization'];
    final token = bearerDeAuthorization(auth);
    if (token != null && esApiKeyNuevaSupabase(token)) {
      request.headers.remove('Authorization');
      request.headers.remove('authorization');
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
