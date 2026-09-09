import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/registro_asistente.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/campos_registro_asistente.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../data/models/registrado.dart';
import '../../../data/models/resultado_envio_qr.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../eventos/providers/eventos_providers.dart';

/// Formulario público de autoregistro, sin sesión (rol `anon` en Supabase).
///
/// Reemplaza al formulario externo `intranet-transworld-dc.onrender.com`
/// del proyecto legado (fuera de ambos ZIP entregados, ver Sección 17.5 de
/// la auditoría). Al vivir en la misma app Flutter Web, comparte esquema,
/// validaciones y estilo con el resto del sistema, y su alcance queda
/// acotado por la política `rpe_registrados_insert_publico` de
/// `supabase/schema.sql` (solo INSERT, solo si el evento sigue vigente).
class RegistroPublicoScreen extends ConsumerStatefulWidget {
  const RegistroPublicoScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  ConsumerState<RegistroPublicoScreen> createState() =>
      _RegistroPublicoScreenState();
}

class _RegistroPublicoScreenState extends ConsumerState<RegistroPublicoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _empresaController = TextEditingController();
  final _cargoController = TextEditingController();
  final _telefonoController = TextEditingController();
  PaisTelefono _pais = kPaisTelefonoChile;
  bool _paisInicializado = false;
  bool _guardando = false;
  bool _enviado = false;
  bool _autovalidar = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _empresaController.dispose();
    _cargoController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  void _inicializarPais(String? paisEvento) {
    if (_paisInicializado) return;
    _pais = paisTelefonoPorPaisEvento(paisEvento);
    _paisInicializado = true;
  }

  Future<void> _enviar() async {
    if (_guardando || _enviado) return;
    _guardando = true;

    aplicarFormatosRegistroAsistente(
      nombre: _nombreController,
      email: _emailController,
      empresa: _empresaController,
      cargo: _cargoController,
      telefono: _telefonoController,
      pais: _pais,
    );

    if (!(_formKey.currentState?.validate() ?? false)) {
      _guardando = false;
      if (mounted) setState(() => _autovalidar = true);
      return;
    }

    final eventoCargado = ref
        .read(eventoPublicoByIdProvider(widget.eventoId))
        .valueOrNull;
    if (eventoCargado != null && eventoCargado.yaOcurrio) {
      _guardando = false;
      if (mounted) setState(() {});
      return;
    }

    if (!mounted) {
      _guardando = false;
      return;
    }
    setState(() => _autovalidar = true);

    final email = formatearEmail(_emailController.text);
    final registrado = Registrado(
      id: '',
      eventoId: widget.eventoId,
      nombreCompleto: formatearNombreCompleto(_nombreController.text),
      email: email,
      empresa: formatearEmpresa(_empresaController.text),
      cargo: formatearCargo(_cargoController.text),
      telefono: telefonoInternacional(_telefonoController.text, _pais),
      origen: OrigenRegistro.publico,
    );

    try {
      final repo = ref.read(registradosRepositoryPublicoProvider);
      if (ref.read(isOnlineProvider)) {
        final yaExiste = await repo.existeEmailEnEvento(widget.eventoId, email);
        if (yaExiste) {
          throw Exception(kMensajeEmailDuplicado);
        }
        final creado = await repo.crear(registrado);
        try {
          final evento = ref
              .read(eventoPublicoByIdProvider(widget.eventoId))
              .valueOrNull;
          await repo.enviarQr(
            creado,
            nombreEvento: evento?.nombre,
            canales: CanalesEnvioQr.ambos,
          );
        } catch (e) {
          debugPrint('enviar-qr tras registro público falló: $e');
        }
      } else {
        await ref
            .read(syncQueueServiceProvider.notifier)
            .enqueueInsert(
              table: SupabaseTables.registrados,
              payload: registrado.toInsertMap(),
            );
      }
      if (mounted) setState(() => _enviado = true);
    } catch (e) {
      if (mounted) {
        final detalle = e.toString().replaceFirst('Exception: ', '');
        final esDuplicado = detalle == kMensajeEmailDuplicado;
        showAppSnackBar(
          context,
          esDuplicado
              ? kMensajeEmailDuplicado
              : 'No se pudo completar el registro. Intenta de nuevo.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventoAsync = ref.watch(eventoPublicoByIdProvider(widget.eventoId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: AppSpacing.form,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.contentMax,
                    ),
                    child: eventoAsync.when(
                      loading: () => const LoadingView(),
                      error: (e, _) => const ErrorView(
                        message:
                            'Este evento no existe o ya no acepta registros.',
                      ),
                      data: (evento) {
                        _inicializarPais(evento.pais);
                        if (evento.yaOcurrio) {
                          return const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.event_busy_rounded,
                                size: 64,
                                color: AppColors.textSecondary,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Evento finalizado',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Este evento ya no acepta registros.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          );
                        }
                        if (_enviado) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: const BoxDecoration(
                                  color: AppColors.successTint,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Symbols.check_circle_rounded,
                                  color: AppColors.success,
                                  size: 40,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '¡Listo, ${_nombreController.text.trim()}!',
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Tu registro fue recibido. Te enviamos la confirmación por email y SMS.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          );
                        }
                        return Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: AppColors.border),
                            boxShadow: AppColors.shadowLifted,
                          ),
                          child: Form(
                            key: _formKey,
                            autovalidateMode: _autovalidar
                                ? AutovalidateMode.onUserInteraction
                                : AutovalidateMode.disabled,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  evento.nombre,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Completa tus datos para registrarte',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                CamposRegistroAsistente(
                                  nombreController: _nombreController,
                                  emailController: _emailController,
                                  empresaController: _empresaController,
                                  cargoController: _cargoController,
                                  telefonoController: _telefonoController,
                                  pais: _pais,
                                  onPaisChanged: (pais) =>
                                      setState(() => _pais = pais),
                                  enabled: !_guardando,
                                ),
                                const SizedBox(height: 24),
                                PrimaryGradientButton(
                                  label: 'Registrarme',
                                  loading: _guardando,
                                  onPressed: (_guardando || _enviado)
                                      ? null
                                      : _enviar,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
