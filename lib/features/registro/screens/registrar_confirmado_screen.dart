import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/network/offline_guard.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/utils/registro_asistente.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/campos_registro_asistente.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/tw_toast.dart';
import '../../../data/models/registrado.dart';
import '../../../data/models/resultado_envio_qr.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../registrados/providers/registrados_providers.dart';

/// Registro manual de un asistente. **Requiere conexión**, a diferencia de
/// acreditar o capturar un lead, que sí se encolan.
///
/// El alta comprueba el duplicado de correo contra la base y dispara el envío
/// del QR por email y SMS: encolarla daría por registrada a una persona
/// que quizá ya existe y que además se quedaría sin su QR. Sin red se avisa
/// y no se guarda nada.
class RegistrarConfirmadoScreen extends ConsumerStatefulWidget {
  const RegistrarConfirmadoScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  ConsumerState<RegistrarConfirmadoScreen> createState() =>
      _RegistrarConfirmadoScreenState();
}

class _RegistrarConfirmadoScreenState
    extends ConsumerState<RegistrarConfirmadoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _empresaController = TextEditingController();
  final _cargoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _rutController = TextEditingController();
  final _patenteController = TextEditingController();
  PaisTelefono _pais = kPaisTelefonoChile;
  PaisTelefono _paisEvento = kPaisTelefonoChile;
  bool _paisInicializado = false;
  bool _acreditarAhora = false;
  bool _guardando = false;
  bool _autovalidar = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _empresaController.dispose();
    _cargoController.dispose();
    _telefonoController.dispose();
    _rutController.dispose();
    _patenteController.dispose();
    super.dispose();
  }

  void _inicializarPais(String? paisEvento) {
    if (_paisInicializado) return;
    _paisEvento = paisTelefonoPorPaisEvento(paisEvento);
    _pais = _paisEvento;
    _paisInicializado = true;
  }

  Future<void> _guardar({
    required bool requiereCertificacion,
    required String nombreEvento,
  }) async {
    if (_guardando) return;
    _guardando = true;

    aplicarFormatosRegistroAsistente(
      nombre: _nombreController,
      email: _emailController,
      empresa: _empresaController,
      cargo: _cargoController,
      telefono: _telefonoController,
      pais: _pais,
      rut: requiereCertificacion ? _rutController : null,
      patente: requiereCertificacion ? _patenteController : null,
    );

    if (!(_formKey.currentState?.validate() ?? false)) {
      _guardando = false;
      if (mounted) setState(() => _autovalidar = true);
      return;
    }

    if (!mounted) {
      _guardando = false;
      return;
    }
    setState(() => _autovalidar = true);

    final email = formatearEmail(_emailController.text);
    final userId = ref.read(currentPerfilProvider).valueOrNull?.id;

    if (!requireOnline(context, ref)) {
      _guardando = false;
      return;
    }

    final evento = ref.read(eventoByIdProvider(widget.eventoId)).valueOrNull;
    if (evento != null && evento.yaOcurrio) {
      _guardando = false;
      if (mounted) TwToast.info(context, kMensajeEventoFinalizado);
      return;
    }

    try {
      final yaExiste = await ref
          .read(registradosRepositoryProvider)
          .existeEmailEnEvento(widget.eventoId, email);
      if (yaExiste) {
        throw Exception(kMensajeEmailDuplicado);
      }

      final registrado = Registrado(
        id: '',
        eventoId: widget.eventoId,
        nombreCompleto: formatearNombreCompleto(_nombreController.text),
        email: email,
        acreditado: _acreditarAhora,
        rut: requiereCertificacion ? formatearRut(_rutController.text) : null,
        patente: requiereCertificacion
            ? formatearPatente(_patenteController.text)
            : null,
        empresa: formatearEmpresa(_empresaController.text),
        cargo: formatearCargo(_cargoController.text),
        telefono: telefonoInternacional(_telefonoController.text, _pais),
        ingresadoPor: userId,
      );

      ResultadoEnvioQr? envio;
      final repo = ref.read(registradosRepositoryProvider);
      final creado = await repo.crear(registrado);
      try {
        envio = await repo.enviarQr(
          creado,
          nombreEvento: nombreEvento,
          canales: CanalesEnvioQr.ambos,
        );
      } catch (e) {
        debugPrint('enviar-qr tras registro manual falló: $e');
      }

      ref.invalidate(registradosPorEventoProvider(widget.eventoId));

      if (mounted) {
        final mensaje = _mensajeRegistroQr(email: email, envio: envio);
        final algunEnvio =
            envio != null && (envio.email.enviado || envio.sms.enviado);
        final algunFallo =
            envio == null || envio.email.fallido || envio.sms.fallido;
        showAppSnackBar(context, mensaje, isError: !algunEnvio && algunFallo);
        _formKey.currentState!.reset();
        _nombreController.clear();
        _emailController.clear();
        _empresaController.clear();
        _cargoController.clear();
        _telefonoController.clear();
        _rutController.clear();
        _patenteController.clear();
        setState(() {
          _acreditarAhora = false;
          _pais = _paisEvento;
          _autovalidar = false;
        });
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventoAsync = ref.watch(eventoByIdProvider(widget.eventoId));

    return AppScaffold(
      title: 'Registrar asistente',
      onWillPop: () => confirmDiscardCreate(context),
      body: eventoAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            const ErrorView(message: 'No se pudo cargar el evento.'),
        data: (evento) {
          _inicializarPais(evento.pais);
          final requiereCertificacion = evento.certificacionCapacitacion;
          return SingleChildScrollView(
            padding: AppSpacing.form,
            child: Form(
              key: _formKey,
              autovalidateMode: _autovalidar
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _InfoRegistroCard(),
                  CamposRegistroAsistente(
                    nombreController: _nombreController,
                    emailController: _emailController,
                    empresaController: _empresaController,
                    cargoController: _cargoController,
                    telefonoController: _telefonoController,
                    pais: _pais,
                    onPaisChanged: (pais) => setState(() => _pais = pais),
                    enabled: !_guardando,
                    mostrarCertificacion: requiereCertificacion,
                    rutController: _rutController,
                    patenteController: _patenteController,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _ToggleRow(
                    title: 'Acreditar de inmediato',
                    subtitle: 'Marca al asistente como acreditado al guardar',
                    value: _acreditarAhora,
                    onChanged: _guardando
                        ? (_) {}
                        : (v) => setState(() => _acreditarAhora = v),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryGradientButton(
                    label: 'Guardar registro',
                    loading: _guardando,
                    onPressed: _guardando
                        ? null
                        : () => _guardar(
                            requiereCertificacion: requiereCertificacion,
                            nombreEvento: evento.nombre,
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InfoRegistroCard extends StatelessWidget {
  const _InfoRegistroCard();

  static const mensaje =
      'Completa los datos del asistente. Al guardar se enviará el código QR '
      'al correo indicado.';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: TwColors.surfaceTint,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Symbols.info_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          NexusToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

String _mensajeRegistroQr({
  required String email,
  required ResultadoEnvioQr? envio,
}) {
  if (envio == null) {
    return 'Registrado con éxito, pero no se pudo enviar el QR.';
  }
  final mail = envio.email;
  final sms = envio.sms;

  if (mail.enviado && sms.enviado) {
    return 'Registrado con éxito. QR enviado por email y SMS.';
  }
  if (mail.enviado && sms.omitido && sms.reason == 'sin_telefono') {
    return 'Registrado con éxito. QR enviado a $email. SMS omitido: sin teléfono.';
  }
  if (mail.enviado && sms.fallido) {
    return 'Registrado con éxito. QR enviado a $email, pero no se pudo enviar por SMS.';
  }
  if (mail.enviado) {
    return 'Registrado con éxito. QR enviado a $email.';
  }
  if (sms.enviado && mail.fallido) {
    return 'Registrado con éxito. QR enviado por SMS, pero no se pudo enviar por email.';
  }
  if (sms.enviado) {
    return 'Registrado con éxito. QR enviado por SMS.';
  }
  if (mail.fallido || sms.fallido) {
    return 'Registrado con éxito, pero no se pudo enviar el QR.';
  }
  return 'Registrado con éxito.';
}
