import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:transworld_nexus/data/supabase/omitir_api_key_en_bearer_client.dart';

class _CapturaClient extends BaseClient {
  BaseRequest? ultimo;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    ultimo = request;
    return StreamedResponse(const Stream.empty(), 200);
  }
}

void main() {
  test('esApiKeyNuevaSupabase reconoce publishable y secret', () {
    expect(esApiKeyNuevaSupabase('sb_publishable_abc'), isTrue);
    expect(esApiKeyNuevaSupabase('sb_secret_xyz'), isTrue);
    expect(
      esApiKeyNuevaSupabase('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'),
      isFalse,
    );
  });

  test('saca Authorization si el Bearer es una publishable', () async {
    final inner = _CapturaClient();
    final client = OmitirApiKeyEnBearerClient(inner);
    final request = Request(
      'GET',
      Uri.parse('https://example.com/auth/v1/token'),
    );
    request.headers['Authorization'] = 'Bearer sb_publishable_abc';
    request.headers['apikey'] = 'sb_publishable_abc';

    await client.send(request);

    expect(inner.ultimo!.headers.containsKey('Authorization'), isFalse);
    expect(inner.ultimo!.headers['apikey'], 'sb_publishable_abc');
  });

  test('conserva el JWT de sesión', () async {
    final inner = _CapturaClient();
    final client = OmitirApiKeyEnBearerClient(inner);
    const jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.signature';
    final request = Request(
      'GET',
      Uri.parse('https://example.com/rest/v1/eventos'),
    );
    request.headers['Authorization'] = 'Bearer $jwt';
    request.headers['apikey'] = 'sb_publishable_abc';

    await client.send(request);

    expect(inner.ultimo!.headers['Authorization'], 'Bearer $jwt');
  });
}
