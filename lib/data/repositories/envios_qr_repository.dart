import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_tables.dart';
import '../../core/errors/rpe_exception.dart';
import '../models/envio_qr.dart';
import '../supabase/supabase_client_provider.dart';

class EnviosQrRepository {
  EnviosQrRepository(this._client);

  final SupabaseClient _client;

  Future<List<EnvioQr>> listarPorRegistrado(String registradoId) async {
    final rows = await conErroresRpe(
      () => _client
          .from(SupabaseTables.enviosQr)
          .select()
          .eq('registrado_id', registradoId)
          .order('created_at', ascending: false)
          .limit(5),
    );
    return rows.map(EnvioQr.fromMap).toList();
  }
}

final enviosQrRepositoryProvider = Provider<EnviosQrRepository>((ref) {
  return EnviosQrRepository(ref.watch(supabaseClientProvider));
});
