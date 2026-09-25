import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/refresh_on_visible.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mascara_contacto.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/app_modals.dart';
import '../../../core/widgets/collapsing_nav.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/pressable.dart';
import '../../../data/models/registrado.dart';
import '../../../data/models/resultado_envio_qr.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../data/repositories/envios_qr_repository.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../providers/registrados_providers.dart';

enum _Filtro { todos, acreditados, pendientes }

class VerRegistradosScreen extends ConsumerStatefulWidget {
  const VerRegistradosScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  ConsumerState<VerRegistradosScreen> createState() =>
      _VerRegistradosScreenState();
}

class _VerRegistradosScreenState extends ConsumerState<VerRegistradosScreen>
    with RefreshOnVisible {
  @override
  String get refreshWhenLocation => RoutePaths.verRegistrados(widget.eventoId);

  @override
  void onBecomeVisible() {
    ref.invalidate(registradosPorEventoProvider(widget.eventoId));
  }

  _Filtro _filtro = _Filtro.todos;
  final _busquedaController = TextEditingController();
  String _busqueda = '';
  Timer? _debounce;

  static const _filtroLabels = {
    _Filtro.todos: 'Todos',
    _Filtro.acreditados: 'Acreditados',
    _Filtro.pendientes: 'Pendientes',
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _busquedaController.dispose();
    super.dispose();
  }

  Widget _buildSearchField() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.input),
        boxShadow: AppColors.shadowRest,
      ),
      child: TextField(
        controller: _busquedaController,
        onChanged: (v) {
          if (_debounce?.isActive ?? false) _debounce!.cancel();
          _debounce = Timer(const Duration(milliseconds: 300), () {
            if (mounted) {
              setState(() => _busqueda = v.trim().toLowerCase());
            }
          });
        },
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar registrado…',
          hintStyle: const TextStyle(color: AppColors.placeholder),
          prefixIcon: const Icon(
            Symbols.search_rounded,
            color: AppColors.placeholder,
            size: 20,
          ),
          filled: true,
          fillColor: AppColors.surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: const BorderSide(
              color: AppColors.primaryLight,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  List<Registrado> _filtrarRegistrados(
    List<Registrado> registrados, {
    required bool puedeVerContacto,
  }) {
    return registrados.where((r) {
      if (_filtro == _Filtro.acreditados && !r.acreditado) {
        return false;
      }
      if (_filtro == _Filtro.pendientes && r.acreditado) return false;
      if (_busqueda.isEmpty) return true;
      // Sin permiso para ver el contacto tampoco se busca por email: si no, el
      // correo oculto se podría reconstruir por tanteo.
      return r.nombreCompleto.toLowerCase().contains(_busqueda) ||
          (puedeVerContacto && r.email.toLowerCase().contains(_busqueda));
    }).toList();
  }

  void _actualizarRegistrados() {
    ref.invalidate(registradosPorEventoProvider(widget.eventoId));
  }

  Widget _buildPinnedControls() {
    return Column(
      children: [
        SizedBox(height: 48, child: _buildSearchField()),
        const SizedBox(height: 4),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: FilterChipBar(
                options: _filtroLabels.values.toList(),
                selected: _filtroLabels[_filtro]!,
                onSelected: (label) {
                  final entry = _filtroLabels.entries.firstWhere(
                    (e) => e.value == label,
                  );
                  setState(() => _filtro = entry.key);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final registradosAsync = ref.watch(
      registradosPorEventoProvider(widget.eventoId),
    );
    final puedeVerContacto = ref.watch(canViewContactDataProvider);

    final filtrados = registradosAsync.maybeWhen(
      data: (registrados) =>
          _filtrarRegistrados(registrados, puedeVerContacto: puedeVerContacto),
      orElse: () => const <Registrado>[],
    );
    final listaVacia = registradosAsync.hasValue && filtrados.isEmpty;

    return CollapsingScrollScaffold(
      title: 'Registrados',
      alwaysShowActions: true,
      overlayLeading: CollapsingNavButton(
        icon: Symbols.arrow_back_rounded,
        tooltip: 'Volver',
        onTap: () => volverAtras(context),
      ),
      pinnedContent: _buildPinnedControls(),
      pinnedContentHeight: 112,
      scrollResetToken: '$_busqueda|$_filtro',
      lockScroll: listaVacia,
      onRefresh: () async => _actualizarRegistrados(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: registradosAsync.when(
              skipLoadingOnReload: true,
              loading: () => _buildHeader(),
              error: (_, _) => _buildHeader(),
              data: (registrados) => _buildHeader(
                total: registrados.length,
                acreditados: registrados.where((r) => r.acreditado).length,
              ),
            ),
          ),
        ),
        ...registradosAsync.when(
          skipLoadingOnReload: true,
          loading: () => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: LoadingView(),
            ),
          ],
          error: (e, _) => [
            SliverFillRemaining(
              child: ErrorView(
                message: 'No se pudo cargar la lista.',
                onRetry: () => ref.invalidate(
                  registradosPorEventoProvider(widget.eventoId),
                ),
              ),
            ),
          ],
          data: (registrados) {
            final filtrados = _filtrarRegistrados(
              registrados,
              puedeVerContacto: puedeVerContacto,
            );

            if (registrados.isEmpty) {
              return [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateView(
                    icon: Symbols.group_off_rounded,
                    message: 'Aún no hay asistentes registrados.',
                    onRefresh: _actualizarRegistrados,
                  ),
                ),
              ];
            }
            if (filtrados.isEmpty) {
              return [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateView(
                    icon: Symbols.search_off_rounded,
                    message: 'No hay registrados con estos filtros.',
                    onRefresh: _actualizarRegistrados,
                  ),
                ),
              ];
            }

            return [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverList.separated(
                  itemCount: filtrados.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.cardGap),
                  itemBuilder: (context, index) => _RegistradoTile(
                    registrado: filtrados[index],
                    eventoId: widget.eventoId,
                    index: index,
                  ),
                ),
              ),
            ];
          },
        ),
      ],
    );
  }

  Widget _buildHeader({int? total, int? acreditados}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Registrados', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 2),
        Text(
          total == null
              ? 'Asistentes del evento'
              : '$total ${total == 1 ? 'registrado' : 'registrados'} · '
                    '$acreditados acreditados',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _RegistradoTile extends ConsumerWidget {
  const _RegistradoTile({
    required this.registrado,
    required this.eventoId,
    required this.index,
  });

  final Registrado registrado;
  final String eventoId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puedeVerContacto = ref.watch(canViewContactDataProvider);

    // Siempre se puede abrir: la pantalla de edición lee de esta misma lista
    // y sabe encolar los cambios de una fila que aún no llegó al servidor.
    return Pressable(
      onTap: () =>
          context.push(RoutePaths.editarRegistrado(eventoId, registrado.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.shadowRest,
        ),
        child: Row(
          children: [
            AvatarInitials(
              name: registrado.nombreCompleto,
              size: 42,
              index: index,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    registrado.nombreCompleto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      puedeVerContacto
                          ? registrado.email
                          : enmascararEmail(registrado.email),
                      registrado.empresa,
                    ].where((s) => s != null && s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      StatusChip(
                        label: registrado.acreditado
                            ? 'Acreditado'
                            : 'Pendiente',
                        variant: registrado.acreditado
                            ? StatusChipVariant.success
                            : StatusChipVariant.warning,
                      ),
                      if (registrado.pendienteDeSincronizar)
                        const StatusChip(
                          label: 'Sin sync',
                          variant: StatusChipVariant.danger,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (registrado.emailConfirmacionEnviado ||
                registrado.smsConfirmacionEnviado)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (registrado.emailConfirmacionEnviado)
                    const Padding(
                      padding: EdgeInsets.only(right: 2),
                      child: Tooltip(
                        message: 'QR enviado por email',
                        child: Icon(
                          Symbols.mark_email_read_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  if (registrado.smsConfirmacionEnviado)
                    const Padding(
                      padding: EdgeInsets.only(right: 2),
                      child: Tooltip(
                        message: 'QR enviado por SMS',
                        child: Icon(
                          Symbols.sms_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            // Mismo chip que el botón de acreditar de al lado: antes era un
            // IconButton pelado, con ripple y 48 de alto, y desalineaba la fila.
            Tooltip(
              message: 'Código QR de acreditación',
              child: Pressable(
                scale: 0.9,
                onTap: () => _mostrarQr(context, ref),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.tintNavy,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                  ),
                  child: const Icon(
                    Symbols.qr_code_2_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: registrado.acreditado ? 'Acreditado' : 'Acreditar',
              child: Pressable(
                key: Key('registrado_acreditar_${registrado.id}'),
                scale: 0.9,
                onTap: () => _onTapAcreditar(context, ref),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: registrado.acreditado
                        ? AppColors.successTint
                        : AppColors.tintNavy,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                  ),
                  child: Icon(
                    Symbols.confirmation_number_rounded,
                    size: 20,
                    color: registrado.acreditado
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTapAcreditar(BuildContext context, WidgetRef ref) async {
    if (registrado.acreditado) {
      final quitar = await confirmDialog(
        context,
        title: 'Quitar acreditación',
        message:
            '¿Deseas quitar la acreditación de ${registrado.nombreCompleto}?',
        confirmLabel: 'Quitar',
        destructive: true,
      );
      if (!quitar || !context.mounted) return;

      try {
        await persistirAcreditacion(
          ref,
          registrado: registrado,
          acreditado: false,
          acreditadoPorId: '',
        );
        if (context.mounted) {
          showAppSnackBar(
            context,
            'Se quitó la acreditación de ${registrado.nombreCompleto}.',
          );
        }
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(
            context,
            'No se pudo quitar la acreditación.',
            isError: true,
          );
        }
      }
      return;
    }

    final confirmar = await confirmDialog(
      context,
      title: 'Acreditar asistente',
      message: '¿Deseas acreditar a ${registrado.nombreCompleto}?',
      confirmLabel: 'Acreditar',
    );
    if (!confirmar || !context.mounted) return;

    final userId = ref.read(currentPerfilProvider).valueOrNull?.id;

    try {
      await persistirAcreditacion(
        ref,
        registrado: registrado,
        acreditado: true,
        acreditadoPorId: userId ?? '',
      );
      if (context.mounted) {
        showAppSnackBar(context, '${registrado.nombreCompleto} acreditado.');
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'No se pudo acreditar.', isError: true);
      }
    }
  }

  void _mostrarQr(BuildContext context, WidgetRef ref) {
    showAppModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.header),
        ),
      ),
      builder: (context) =>
          _QrSheet(registrado: registrado, eventoId: eventoId),
    );
  }
}

/// QR de acreditación de un registrado (codifica `registrados.id`, lo que
/// lee `AcreditarQrScreen`). Permite enviarlo por email y SMS vía
/// la Edge Function `enviar-qr`.
class _QrSheet extends ConsumerStatefulWidget {
  const _QrSheet({required this.registrado, required this.eventoId});

  final Registrado registrado;
  final String eventoId;

  @override
  ConsumerState<_QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends ConsumerState<_QrSheet> {
  bool _enviandoEmail = false;
  bool _enviandoSms = false;

  bool get _ocupado => _enviandoEmail || _enviandoSms;

  String _correoVisible({required bool puedeVerContacto}) {
    final correo = widget.registrado.email;
    return puedeVerContacto ? correo : enmascararEmail(correo);
  }

  String _telefonoVisible({required bool puedeVerContacto}) {
    final telefono = widget.registrado.telefono?.trim() ?? '';
    if (telefono.isEmpty) return '';
    return puedeVerContacto ? telefono : enmascararTelefono(telefono);
  }

  Future<void> _regenerar() async {
    if (!requireOnline(context, ref)) return;
    final ok = await confirmDialog(
      context,
      title: 'Regenerar QR',
      message: 'El código anterior dejará de servir. ¿Continuar?',
      confirmLabel: 'Regenerar',
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(registradosRepositoryProvider)
          .regenerarCodigoQr(widget.registrado.id);
      ref.invalidate(registradosPorEventoProvider(widget.eventoId));
      if (mounted) showAppSnackBar(context, 'Nuevo QR en camino');
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<void> _enviar({required String canal}) async {
    if (!requireOnline(context, ref)) return;
    final puedeVerContacto = ref.read(canViewContactDataProvider);
    setState(() {
      if (canal == CanalesEnvioQr.email) {
        _enviandoEmail = true;
      } else {
        _enviandoSms = true;
      }
    });
    try {
      final resultado = await ref
          .read(registradosRepositoryProvider)
          .enviarQr(widget.registrado.id, canales: [canal]);
      ref.invalidate(registradosPorEventoProvider(widget.eventoId));
      if (!mounted) return;
      final canalResultado = canal == CanalesEnvioQr.email
          ? resultado.email
          : resultado.sms;
      _mostrarResultadoCanal(
        resultado: canalResultado,
        canal: canal,
        destinoVisible: canal == CanalesEnvioQr.email
            ? _correoVisible(puedeVerContacto: puedeVerContacto)
            : _telefonoVisible(puedeVerContacto: puedeVerContacto),
      );
    } catch (e) {
      if (mounted) {
        debugPrint('enviar-qr ($canal) falló: $e');
        showAppSnackBar(
          context,
          canal == CanalesEnvioQr.email
              ? 'No se pudo enviar el QR por email. Verifica que la Edge Function enviar-qr esté desplegada.'
              : 'No se pudo enviar el QR por SMS. Verifica créditos SMS de Brevo y que enviar-qr esté desplegada.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _enviandoEmail = false;
          _enviandoSms = false;
        });
      }
    }
  }

  void _mostrarResultadoCanal({
    required ResultadoCanalQr resultado,
    required String canal,
    required String destinoVisible,
  }) {
    if (resultado.enviado) {
      Navigator.of(context).pop();
      final porSms = canal == CanalesEnvioQr.sms;
      showAppSnackBar(
        context,
        porSms
            ? (destinoVisible.isEmpty
                  ? 'QR enviado por SMS.'
                  : 'QR enviado por SMS a $destinoVisible.')
            : 'QR enviado a $destinoVisible.',
      );
      return;
    }
    if (resultado.omitido) {
      final motivo = switch (resultado.reason) {
        'sin_telefono' => 'Este asistente no tiene teléfono.',
        'sin_email' => 'Este asistente no tiene email.',
        'sin_acceso_qr' => 'Este evento no envía QR por SMS.',
        _ => 'No se envió el QR.',
      };
      showAppSnackBar(context, motivo);
      return;
    }
    showAppSnackBar(
      context,
      canal == CanalesEnvioQr.sms
          ? (resultado.mensajeBrevo.isEmpty
                ? 'No se pudo enviar el QR por SMS.'
                : resultado.mensajeBrevo)
          : (resultado.mensajeBrevo.isEmpty
                ? 'No se pudo enviar el QR por email.'
                : resultado.mensajeBrevo),
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isOnlineProvider);
    final puedeVerContacto = ref.watch(canViewContactDataProvider);
    final evento = ref.watch(eventoByIdProvider(widget.eventoId)).valueOrNull;
    final mostrarSms = evento?.accesoQr == true;
    final r = widget.registrado;
    // Un registro que solo existe en la cola local todavía no tiene id real
    // en el servidor: su QR no serviría para acreditar ni para el email. Se
    // mira el id y no la insignia de pendiente, porque una fila ya
    // sincronizada que solo tiene una edición en cola sí tiene QR válido.
    final soloEnLaCola = esIdSoloLocal(r.id);
    final puedeEnviar = isOnline && !soloEnLaCola && !_ocupado;
    final telefono = r.telefono?.trim() ?? '';
    final telefonoVisible = _telefonoVisible(
      puedeVerContacto: puedeVerContacto,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final qrSize = (constraints.maxWidth - AppSpacing.screenH * 2 - 24)
            .clamp(128.0, 200.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                r.nombreCompleto,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                _correoVisible(puedeVerContacto: puedeVerContacto),
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (telefonoVisible.isNotEmpty)
                Text(
                  telefonoVisible,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              const SizedBox(height: 16),
              if (soloEnLaCola)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.warningTint,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'Este registro aún no se sincroniza con el servidor; '
                    'su QR estará disponible cuando vuelva la conexión.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: QrImageView(
                    data: r.codigoQr,
                    size: qrSize,
                    backgroundColor: Colors.white,
                  ),
                ),
              if (ref.watch(canCreateContentProvider) && !soloEnLaCola) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: puedeEnviar ? _regenerar : null,
                  child: const Text('Regenerar QR'),
                ),
              ],
              const SizedBox(height: 8),
              const Text('Envíos'),
              FutureBuilder(
                future: ref
                    .read(enviosQrRepositoryProvider)
                    .listarPorRegistrado(r.id),
                builder: (context, snapshot) {
                  final envios = snapshot.data ?? const [];
                  if (envios.isEmpty) {
                    return const Text('Sin envíos todavía.');
                  }
                  return Column(
                    children: [
                      for (final envio in envios)
                        Text(
                          '${envio.createdAt ?? ''} · ${envio.canales.join(', ')} · ${envio.estado}',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              PrimaryGradientButton(
                label: r.emailConfirmacionEnviado
                    ? 'Reenviar por email'
                    : 'Enviar por email',
                loading: _enviandoEmail,
                onPressed: puedeEnviar
                    ? () => _enviar(canal: CanalesEnvioQr.email)
                    : null,
              ),
              if (mostrarSms) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: (puedeEnviar && telefono.isNotEmpty)
                        ? () => _enviar(canal: CanalesEnvioQr.sms)
                        : null,
                    child: _enviandoSms
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            r.smsConfirmacionEnviado
                                ? 'Reenviar por SMS'
                                : 'Enviar por SMS',
                          ),
                  ),
                ),
                if (telefono.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Este asistente no tiene teléfono.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
              if (!isOnline)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    kMensajeSinConexion,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
