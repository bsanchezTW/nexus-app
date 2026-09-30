import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/network/offline_guard.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/utils/registro_asistente.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/campos_registro_asistente.dart';
import '../../../core/widgets/form_sections.dart';
import '../../../core/widgets/tw_toast.dart';
import '../../../core/router/route_paths.dart';
import '../../../data/models/resultado_registro.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../subeventos/providers/subeventos_providers.dart';
import '../../subeventos/widgets/selector_subeventos.dart';
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
  final Set<String> _talleres = {};

  /// ¿Hay algo escrito que se perdería al salir?
  bool get _hayDatos =>
      [
        _nombreController,
        _emailController,
        _empresaController,
        _cargoController,
        _telefonoController,
        _rutController,
        _patenteController,
      ].any((c) => c.text.trim().isNotEmpty) ||
      _talleres.isNotEmpty;

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

  Map<String, dynamic> _datosRegistro(bool requiereCertificacion, String email) {
    return {
      'nombre_completo': formatearNombreCompleto(_nombreController.text),
      'email': email,
      'empresa': formatearEmpresa(_empresaController.text),
      'cargo': formatearCargo(_cargoController.text),
      'telefono': telefonoInternacional(_telefonoController.text, _pais),
      if (requiereCertificacion) 'rut': formatearRut(_rutController.text),
      if (requiereCertificacion) 'patente': formatearPatente(_patenteController.text),
    };
  }

  void _inicializarPais(String? paisEvento) {
    if (_paisInicializado) return;
    _paisEvento = paisTelefonoPorPaisEvento(paisEvento);
    _pais = _paisEvento;
    _paisInicializado = true;
  }

  Future<void> _guardar({required bool requiereCertificacion}) async {
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
      final repo = ref.read(registradosRepositoryProvider);
      final resultado = await repo.registrar(
        eventoId: widget.eventoId,
        acreditar: _acreditarAhora,
        subeventoIds: _talleres.toList(),
        datos: _datosRegistro(requiereCertificacion, email),
      );

      if (resultado is RegistroRechazado) {
        if (resultado.motivo == 'email_duplicado' &&
            resultado.registradoIdExistente != null &&
            mounted) {
          final abrir = await confirmDialog(
            context,
            title: 'Correo ya registrado',
            message: 'Esa persona ya está en el evento.',
            confirmLabel: 'Abrir registro existente',
          );
          if (abrir && mounted) {
            context.push(
              RoutePaths.editarRegistrado(
                widget.eventoId,
                resultado.registradoIdExistente!,
              ),
            );
          }
          return;
        }
        if (resultado.motivo == 'subeventos_rechazados' && mounted) {
          if (!resultado.puedeForzar) {
            throw Exception('Hay talleres que no se pudieron inscribir.');
          }
          final forzar = await confirmDialog(
            context,
            title: 'Talleres sin cupo',
            message: 'Algunos talleres están llenos. ¿Registrar en sobrecupo?',
            confirmLabel: 'Registrar',
          );
          if (!forzar || !mounted) return;
          final forzado = await repo.registrar(
            eventoId: widget.eventoId,
            acreditar: _acreditarAhora,
            forzarSobrecupo: true,
            subeventoIds: _talleres.toList(),
            datos: _datosRegistro(requiereCertificacion, email),
          );
          if (forzado is RegistroOk) {
            _avisarRegistro();
            return;
          }
          throw Exception('Hay talleres que no se pudieron inscribir.');
        }
        if (resultado.motivo == 'sin_cupo_evento' &&
            resultado.puedeForzar &&
            mounted) {
          final forzar = await confirmDialog(
            context,
            title: 'Cupo completo',
            message: 'El evento no tiene cupo. ¿Registrar igual en sobrecupo?',
            confirmLabel: 'Registrar',
          );
          if (!forzar || !mounted) return;
          final forzado = await repo.registrar(
            eventoId: widget.eventoId,
            acreditar: _acreditarAhora,
            forzarSobrecupo: true,
            subeventoIds: _talleres.toList(),
            datos: _datosRegistro(requiereCertificacion, email),
          );
          if (forzado is RegistroOk) {
            _avisarRegistro();
            return;
          }
        }
        throw Exception(
          resultado.motivo == 'email_duplicado'
              ? kMensajeEmailDuplicado
              : resultado.motivo == 'sin_cupo_evento'
              ? 'No queda cupo en este evento.'
              : 'No se pudo registrar.',
        );
      }

      _avisarRegistro();
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

  void _avisarRegistro() {
    ref.invalidate(registradosPorEventoProvider(widget.eventoId));
    if (!mounted) return;
    showAppSnackBar(context, 'Confirmación en camino');
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
      _talleres.clear();
      _pais = _paisEvento;
      _autovalidar = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final eventoAsync = ref.watch(eventoByIdProvider(widget.eventoId));
    final evento = eventoAsync.valueOrNull;
    final talleres =
        ref.watch(subeventosPorEventoProvider(widget.eventoId)).valueOrNull ??
        const [];

    return AppScaffold(
      title: 'Registrar asistente',
      onWillPop: () => confirmDiscardCreate(context, hayDatos: _hayDatos),
      bottomBar: evento == null
          ? null
          : FormActionBar(
              label: 'Guardar registro',
              loading: _guardando,
              onPressed: _guardando
                  ? null
                  : () => _guardar(
                      requiereCertificacion: evento.certificacionCapacitacion,
                    ),
            ),
      body: eventoAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            const ErrorView(message: 'No se pudo cargar el evento.'),
        data: (evento) {
          _inicializarPais(evento.pais);
          final requiereCertificacion = evento.certificacionCapacitacion;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              TwSpacing.screenH,
              14,
              TwSpacing.screenH,
              28,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Form(
              key: _formKey,
              autovalidateMode: _autovalidar
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormNotice(
                    'Registro en ${evento.nombre}. Al guardar se envía el '
                    'código QR al correo indicado.',
                  ),
                  const SizedBox(height: FormSection.gap),
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
                  if (talleres.isNotEmpty) ...[
                    const SizedBox(height: FormSection.gap),
                    FormSection(
                      icon: Symbols.co_present_rounded,
                      title: 'Talleres',
                      subtitle: 'Opcional. Inscríbelo en los que asistirá.',
                      children: [
                        SelectorSubeventos(
                          subeventos: talleres,
                          ocupacion: ref
                              .watch(ocupacionEventoProvider(widget.eventoId))
                              .valueOrNull,
                          seleccionados: _talleres,
                          permitirSobrecupo: ref.watch(
                            canCreateContentProvider,
                          ),
                          onChanged: (ids) => setState(() {
                            _talleres
                              ..clear()
                              ..addAll(ids);
                          }),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: FormSection.gap),
                  FormSection(
                    icon: Symbols.verified_rounded,
                    title: 'Acreditación',
                    children: [
                      FormToggleRow(
                        icon: Symbols.how_to_reg_rounded,
                        title: 'Acreditar de inmediato',
                        subtitle: 'Queda con la entrada marcada al guardar.',
                        value: _acreditarAhora,
                        onChanged: _guardando
                            ? null
                            : (v) => setState(() => _acreditarAhora = v),
                      ),
                    ],
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
