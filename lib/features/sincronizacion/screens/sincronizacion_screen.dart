import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/conexion/estado_conexion.dart';
import '../../../core/conexion/monitor_conexion.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_policy.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../core/widgets/tw_toast.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/offline/snapshot_service.dart';
import '../../../data/offline/sync_coordinator.dart';
import '../../../data/offline/sync_queue_item.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../core/constants/supabase_tables.dart';

/// Estado del modo offline: qué hay pendiente de subir, cuándo fue la última
/// bajada completa y un botón para forzar ambas cosas.
class SincronizacionScreen extends ConsumerWidget {
  const SincronizacionScreen({super.key});

  static String _formatearFecha(DateTime fecha) {
    return DateFormat("d 'de' MMMM, HH:mm", 'es').format(fecha);
  }

  static String _etiquetaTabla(String tabla) => switch (tabla) {
    SupabaseTables.leads => 'Lead',
    SupabaseTables.registrados => 'Acreditación',
    SupabaseTables.inscripcionesSubevento => 'Inscripción a taller',
    _ => tabla,
  };

  /// Primero se sube lo capturado y después se vuelve a bajar: al revés, el
  /// snapshot pisaría con datos del servidor unas listas a las que aún les
  /// falta lo local. La época sube antes de bajar para que el respaldo lea
  /// del servidor y no lo que la pantalla ya tenía.
  Future<void> _sincronizar(BuildContext context, WidgetRef ref) async {
    await ref.read(syncCoordinatorProvider).sincronizarAhora();
    exigirLecturaDelServidor(ref.read(epocaServidorProvider.notifier));
    await ref.read(snapshotServiceProvider.notifier).ejecutar();
    if (!context.mounted) return;

    final errores = ref.read(snapshotServiceProvider).errores;
    final sinSubir = ref
        .read(syncQueueServiceProvider)
        .where((i) => i.status == SyncStatus.failed)
        .length;
    if (errores.isEmpty && sinSubir == 0) {
      TwToast.success(context, 'Sincronización completada.');
    } else {
      final partes = [
        if (sinSubir > 0)
          sinSubir == 1
              ? '1 cambio no se pudo subir'
              : '$sinSubir cambios no se pudieron subir',
        if (errores.isNotEmpty)
          errores.length == 1
              ? '1 parte de la copia local falló'
              : '${errores.length} partes de la copia local fallaron',
      ];
      TwToast.error(
        context,
        'Sincronización incompleta: ${partes.join(' y ')}.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.read(snapshotServiceProvider.notifier).restaurarMetadatosSiHaceFalta();
    final snapshot = ref.watch(snapshotServiceProvider);
    final cola = ref.watch(syncQueueServiceProvider);
    final hayRed = ref.watch(usaServidorProvider);

    final pendientes = cola
        .where(
          (i) =>
              i.status == SyncStatus.pending ||
              i.status == SyncStatus.syncing ||
              i.status == SyncStatus.failed,
        )
        .toList();
    int contar(String tabla) =>
        pendientes.where((i) => i.table == tabla).length;
    final fallidos = pendientes
        .where((i) => i.status == SyncStatus.failed)
        .toList();

    return AppScaffold(
      title: 'Sincronización',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _Estado(
            hayRed: hayRed,
            estado: ref.watch(estadoConexionProvider),
            snapshot: snapshot,
          ),
          const TwSectionLabel('Pendientes de subir'),
          _Contador(
            icono: Symbols.person_search_rounded,
            etiqueta: 'Leads capturados',
            valor: contar(SupabaseTables.leads),
          ),
          const SizedBox(height: 10),
          _Contador(
            icono: Symbols.how_to_reg_rounded,
            etiqueta: 'Acreditaciones',
            valor: contar(SupabaseTables.registrados),
          ),
          const SizedBox(height: 10),
          _Contador(
            icono: Symbols.event_available_rounded,
            etiqueta: 'Inscripciones a talleres',
            valor: contar(SupabaseTables.inscripcionesSubevento),
          ),
          if (fallidos.isNotEmpty) ...[
            const TwSectionLabel('No se pudieron subir'),
            for (final item in fallidos)
              _Incidencia(
                texto:
                    '${_etiquetaTabla(item.table)}: '
                    '${item.lastError ?? 'error desconocido'}'
                    '${item.retries > 1 ? ' (${item.retries} intentos)' : ''}',
              ),
          ],
          if (snapshot.errores.isNotEmpty) ...[
            const TwSectionLabel('Incidencias de la última bajada'),
            for (final error in snapshot.errores) _Incidencia(texto: error),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: snapshot.enCurso || !hayRed
                ? null
                : () => _sincronizar(context, ref),
            icon: snapshot.enCurso
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.sync_rounded),
            label: Text(
              snapshot.enCurso ? 'Sincronizando…' : 'Sincronizar ahora',
            ),
          ),
          if (!hayRed)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Necesitas una conexión estable para sincronizar. Lo capturado '
                'se sube solo en cuanto se estabilice.',
                style: TwText.tileSubtitle,
                textAlign: TextAlign.center,
              ),
            ),
          if (!supportsOfflineCacheAqui)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Esta plataforma trabaja siempre en línea: no guarda una copia '
                'local de los eventos.',
                style: TwText.tileSubtitle,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({
    required this.hayRed,
    required this.estado,
    required this.snapshot,
  });

  final bool hayRed;
  final EstadoConexion estado;
  final SnapshotEstado snapshot;

  @override
  Widget build(BuildContext context) {
    final ultimo = snapshot.ultimoExito;
    final progreso = snapshot.enCurso ? snapshot.progreso : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hayRed ? TwColors.greenTint : TwColors.dangerTint,
        borderRadius: TwRadii.field,
      ),
      child: Row(
        children: [
          Icon(
            hayRed ? Symbols.cloud_done_rounded : Symbols.cloud_off_rounded,
            color: hayRed ? TwColors.greenInk : TwColors.danger,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(switch (estado) {
                  EstadoConexion.verificando ||
                  EstadoConexion.estable => 'Conectado',
                  EstadoConexion.inestable =>
                    'Conexión inestable · modo sin conexión',
                  EstadoConexion.sinInternet => 'Sin conexión',
                  EstadoConexion.sinBackend =>
                    'Base de datos sin respuesta · modo sin conexión',
                }, style: TwText.tileTitle),
                const SizedBox(height: 2),
                Text(
                  ultimo == null
                      ? 'Todavía no se ha descargado una copia local.'
                      : 'Última descarga: '
                            '${SincronizacionScreen._formatearFecha(ultimo)}',
                  style: TwText.tileSubtitle,
                ),
                if (progreso != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Descargando ${progreso.etapa.titulo.toLowerCase()} · '
                    '${(progreso.fraccion * 100).clamp(0, 100).toStringAsFixed(0)} %',
                    style: TwText.tileSubtitle,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: TwRadii.pill,
                    child: LinearProgressIndicator(
                      value: progreso.fraccion > 0 ? progreso.fraccion : null,
                      minHeight: 4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Contador extends StatelessWidget {
  const _Contador({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final int valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 20, color: TwColors.muted),
        const SizedBox(width: 10),
        Expanded(child: Text(etiqueta, style: TwText.tileTitle)),
        Text(
          '$valor',
          style: TwText.tileTitle.copyWith(
            color: valor > 0 ? TwColors.brand700 : TwColors.muted,
          ),
        ),
      ],
    );
  }
}

class _Incidencia extends StatelessWidget {
  const _Incidencia({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.error_rounded, size: 18, color: TwColors.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TwText.errorText)),
        ],
      ),
    );
  }
}
