import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';

import '../../../core/router/refresh_on_visible.dart';
import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mascara_contacto.dart';
import '../../../core/utils/registro_asistente.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/campos_registro_asistente.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/form_sections.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/selector_imagen.dart';
import '../../../data/models/lead.dart';
import '../../../data/models/lead_write_result.dart';
import '../../../data/models/lead_prefill.dart';
import '../../../data/offline/pending_photo_store.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../data/repositories/leads_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../externo/providers/externo_dashboard_provider.dart';
import '../lead_comentario_flujo.dart';
import '../providers/capturador_providers.dart';
import '../widgets/foto_lead_identidad.dart';

enum _CampoVoz { nombre, empresa, cargo, email, descripcion }

/// Un campo de contacto queda bloqueado solo si el QR trajo el dato y el rol no
/// puede verlo. En captura manual (sin dato) se escribe con normalidad.
bool _contactoBloqueado(String? prefill, bool puedeVerContacto) {
  return !puedeVerContacto && prefill != null;
}

String? _sinVacios(String valor) {
  final texto = valor.trim();
  return texto.isEmpty ? null : texto;
}

class CrearLeadScreen extends ConsumerStatefulWidget {
  const CrearLeadScreen({
    super.key,
    required this.eventoId,
    this.prefill,
    this.eventoRegistroId,
  });

  final String eventoId;
  final LeadPrefill? prefill;

  /// Evento de registro de origen (flujo QR). Tras guardar se hace pop
  /// al escáner en lugar de reemplazar el stack.
  final String? eventoRegistroId;

  @override
  ConsumerState<CrearLeadScreen> createState() => _CrearLeadScreenState();
}

class _CrearLeadScreenState extends ConsumerState<CrearLeadScreen> {
  static const _uuid = Uuid();
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _empresaController = TextEditingController();
  final _cargoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _descripcionController = TextEditingController();
  PaisTelefono _paisTelefono = kPaisTelefonoChile;
  PaisTelefono _paisTelefonoEvento = kPaisTelefonoChile;
  bool _paisTelefonoEventoInicializado = false;
  bool _telefonoTienePaisExplicito = false;

  final _speech = stt.SpeechToText();
  bool _speechDisponible = false;
  _CampoVoz? _escuchandoCampo;

  /// Foto ya comprimida, todavía en memoria. Se sube (o se deja en disco, si
  /// no hay red) recién al guardar el lead.
  Uint8List? _fotoBytes;
  String? _leadGuardadoPendienteFotoId;

  bool _guardando = false;
  bool _accesoValidado = false;

  /// Contacto que trajo el QR. Quien no puede ver el contacto lo edita con la
  /// máscara a la vista, así que al guardar se envía este valor y no el texto
  /// del campo. Si el QR no trajo nada, el campo queda libre para escribirlo.
  String? _emailPrefill;
  String? _telefonoPrefill;

  /// `null` hasta la primera sincronización, para que el primer valor del rol
  /// siempre se aplique.
  bool? _contactoEnmascarado;

  /// `null` = junction aún cargando; set vacío = sin autorización usable.
  Set<String>? _idsPermitidosExterno() {
    final autorizados = ref.read(externoEventosAutorizadosIdsProvider);
    if (autorizados == null) return null;
    if (autorizados.isNotEmpty) return autorizados;
    final activo = ref.read(externoEventoIdProvider);
    if (activo == null || activo.isEmpty) return {};
    return {activo};
  }

  @override
  void initState() {
    super.initState();
    _aplicarPrefill();
    _sincronizarMascaraContacto(
      puedeVerContacto: ref.read(canViewContactDataProvider),
    );
    _initSpeech();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _validarAccesoExterno(),
    );
  }

  void _validarAccesoExterno() {
    if (!mounted || _accesoValidado) return;
    final perfil = ref.read(currentPerfilProvider).valueOrNull;
    if (perfil == null || !perfil.isExterno) {
      _accesoValidado = true;
      return;
    }

    final eventoReg = widget.eventoRegistroId;
    final permitidos = _idsPermitidosExterno();
    if (permitidos == null) {
      return; // reintentará vía ref.listen en build
    }

    final ok =
        eventoReg != null &&
        eventoReg.isNotEmpty &&
        permitidos.contains(eventoReg);

    _accesoValidado = true;
    if (ok) return;

    final activo = ref.read(externoEventoIdProvider);
    final destino = activo != null && activo.isNotEmpty
        ? RoutePaths.externoEvento(activo)
        : RoutePaths.eventoFinalizado;
    context.go(destino);
  }

  void _aplicarPrefill() {
    final prefill = widget.prefill;
    if (prefill == null) return;
    if (prefill.nombreCompleto != null) {
      _nombreController.text = prefill.nombreCompleto!;
    }
    if (prefill.empresa != null) {
      _empresaController.text = prefill.empresa!;
    }
    if (prefill.cargo != null) {
      _cargoController.text = prefill.cargo!;
    }
    if (prefill.telefono != null) {
      _telefonoPrefill = prefill.telefono;
      final detectado = detectarPaisTelefono(prefill.telefono);
      if (detectado != null) {
        _paisTelefono = detectado;
        _telefonoTienePaisExplicito = true;
      }
      _telefonoController.text = formatearTelefonoNacional(
        prefill.telefono!,
        _paisTelefono,
      );
    }
    if (prefill.email != null) {
      _emailPrefill = prefill.email;
      _emailController.text = prefill.email!;
    }
  }

  /// Cambia el contacto precargado entre su valor real y la máscara. Se llama
  /// también cuando el rol se resuelve después del primer frame, así un
  /// administrador nunca queda con la máscara puesta.
  void _sincronizarMascaraContacto({required bool puedeVerContacto}) {
    if (_contactoEnmascarado == !puedeVerContacto) return;
    _contactoEnmascarado = !puedeVerContacto;

    final email = _emailPrefill;
    if (email != null) {
      _emailController.text = puedeVerContacto ? email : enmascararEmail(email);
    }
    final telefono = _telefonoPrefill;
    if (telefono != null) {
      _telefonoController.text = puedeVerContacto
          ? formatearTelefonoNacional(telefono, _paisTelefono)
          : enmascararTelefono(telefono);
    }
  }

  void _inicializarPaisTelefonoEvento(String? paisEvento) {
    if (_paisTelefonoEventoInicializado) return;
    _paisTelefonoEvento = paisTelefonoPorPaisEvento(paisEvento);
    _paisTelefonoEventoInicializado = true;
    if (_telefonoTienePaisExplicito) return;
    _paisTelefono = _paisTelefonoEvento;
    if (_contactoEnmascarado != true) {
      _telefonoController.text = formatearTelefonoNacional(
        _telefonoPrefill ?? _telefonoController.text,
        _paisTelefono,
      );
    }
  }

  Future<void> _initSpeech() async {
    final ok = await _speech.initialize(
      onError: (_) {
        if (mounted) setState(() => _escuchandoCampo = null);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _escuchandoCampo = null);
        }
      },
    );
    if (mounted) setState(() => _speechDisponible = ok);
  }

  @override
  void dispose() {
    _speech.stop();
    _nombreController.dispose();
    _empresaController.dispose();
    _cargoController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  TextEditingController _controllerDe(_CampoVoz campo) {
    return switch (campo) {
      _CampoVoz.nombre => _nombreController,
      _CampoVoz.empresa => _empresaController,
      _CampoVoz.cargo => _cargoController,
      _CampoVoz.email => _emailController,
      _CampoVoz.descripcion => _descripcionController,
    };
  }

  Future<void> _toggleVoz(_CampoVoz campo) async {
    if (!_speechDisponible) {
      showAppSnackBar(
        context,
        'El dictado por voz no está disponible en este dispositivo.',
        isError: true,
      );
      return;
    }

    if (_escuchandoCampo == campo) {
      await _speech.stop();
      setState(() => _escuchandoCampo = null);
      return;
    }

    if (_escuchandoCampo != null) {
      await _speech.stop();
    }

    setState(() => _escuchandoCampo = campo);
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(localeId: 'es_ES'),
      onResult: (result) {
        final texto = result.recognizedWords.trim();
        if (texto.isEmpty) return;
        _controllerDe(campo).text = texto;
        _controllerDe(campo).selection = TextSelection.fromPosition(
          TextPosition(offset: texto.length),
        );
      },
    );
  }

  void _limpiarFormulario() {
    FocusManager.instance.primaryFocus?.unfocus();
    _formKey.currentState?.reset();
    _nombreController.clear();
    _empresaController.clear();
    _cargoController.clear();
    _telefonoController.clear();
    _emailController.clear();
    _descripcionController.clear();
    // Sin esto la captura en cadena arrastraría el contacto del lead anterior.
    _emailPrefill = null;
    _telefonoPrefill = null;
    _telefonoTienePaisExplicito = false;
    _paisTelefono = _paisTelefonoEvento;
    // Tras guardar se sigue capturando en cadena: si la foto no se limpia,
    // el siguiente lead se llevaría la del anterior.
    _fotoBytes = null;
    _leadGuardadoPendienteFotoId = null;
  }

  String? _telefonoAGuardar({required bool puedeVerContacto}) {
    if (_contactoBloqueado(_telefonoPrefill, puedeVerContacto)) {
      return _telefonoPrefill;
    }
    if (_sinVacios(_telefonoController.text) == null) return null;
    return telefonoInternacional(_telefonoController.text, _paisTelefono);
  }

  String? _emailAGuardar({required bool puedeVerContacto}) {
    if (_contactoBloqueado(_emailPrefill, puedeVerContacto)) {
      final email = _emailPrefill;
      return email == null ? null : formatearEmail(email);
    }
    if (_sinVacios(_emailController.text) == null) return null;
    return formatearEmail(_emailController.text);
  }

  Future<void> _elegirFoto() async {
    final bytes = await elegirImagenComprimida(
      context,
      recorteProporcion: kProporcionFotoLead,
    );
    if (bytes == null || !mounted) return;
    setState(() => _fotoBytes = bytes);
  }

  /// Conserva la foto localmente hasta que el servidor confirme la fila. Así
  /// un duplicado nunca deja archivos huérfanos en Storage.
  Future<List<String>> _resolverFotos({required bool isOnline}) async {
    final bytes = _fotoBytes;
    if (bytes == null) return const [];

    final store = ref.read(pendingPhotoStoreProvider);
    if (store.disponible) return [await store.guardar(bytes)];

    // Web no tiene disco persistente. En línea se conserva el flujo seguro:
    // el repositorio crea primero la fila y recién después sube estos bytes.
    if (isOnline) return const [];
    return const [];
  }

  Future<void> _finalizarFlujoGuardado() async {
    final eventoRegistroId = widget.eventoRegistroId;
    if (eventoRegistroId != null) {
      if (context.canPop()) {
        volverAtras(context);
      } else {
        context.go(RoutePaths.acreditarQr(eventoRegistroId));
      }
      return;
    }

    final agregarOtro = await confirmDialog(
      context,
      title: 'Lead guardado',
      message: '¿Quieres agregar otro lead?',
      confirmLabel: 'Agregar otro',
      cancelLabel: 'No, salir',
      barrierDismissible: false,
    );
    if (!mounted) return;

    if (agregarOtro) {
      _limpiarFormulario();
      setState(() {});
      return;
    }

    if (context.canPop()) {
      volverAtras(context);
    } else {
      context.go(RoutePaths.usarEventoLead(widget.eventoId));
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_escuchandoCampo != null) {
      await _speech.stop();
      setState(() => _escuchandoCampo = null);
    }

    setState(() => _guardando = true);
    final isOnline = ref.read(isOnlineProvider);
    final perfil = ref.read(currentPerfilProvider).valueOrNull;
    final userId = perfil?.id;
    final puedeVerContacto = perfil?.canViewContactData ?? false;
    Lead? leadPreparado;
    List<String> fotosPreparadas = const [];

    try {
      final pendienteFotoId = _leadGuardadoPendienteFotoId;
      final bytesPendientes = _fotoBytes;
      if (pendienteFotoId != null && bytesPendientes != null) {
        try {
          await ref
              .read(leadsRepositoryProvider)
              .adjuntarFotoBytes(pendienteFotoId, bytesPendientes);
          _leadGuardadoPendienteFotoId = null;
          if (mounted) {
            showAppSnackBar(context, 'Lead y foto guardados.');
            await _finalizarFlujoGuardado();
          }
        } catch (_) {
          if (mounted) {
            showAppSnackBar(
              context,
              'Lead guardado; foto pendiente, reintenta',
              isError: true,
            );
          }
        }
        return;
      }

      if (userId == null || userId.isEmpty) {
        throw Exception(
          'No se pudo identificar al usuario capturador. Intenta de nuevo.',
        );
      }
      if (perfil?.isExterno == true) {
        final eventoReg = widget.eventoRegistroId;
        final permitidos = _idsPermitidosExterno();
        if (permitidos == null) {
          throw Exception(
            'Aún se están cargando tus eventos autorizados. Intenta de nuevo.',
          );
        }
        if (eventoReg == null || !permitidos.contains(eventoReg)) {
          throw Exception(
            'No estás autorizado para capturar leads en este evento.',
          );
        }
      }

      // En web no hay dónde dejar la foto esperando a que vuelva la red, así
      // que el lead se guarda sin ella y hay que decirlo.
      final fotoDescartada =
          _fotoBytes != null &&
          !isOnline &&
          !ref.read(pendingPhotoStoreProvider).disponible;
      final fotos = await _resolverFotos(isOnline: isOnline);
      fotosPreparadas = fotos;

      final lead = Lead(
        id: '',
        eventoId: widget.eventoId,
        nombreCompleto: _nombreController.text.trim(),
        empresa: _empresaController.text.trim(),
        cargo: _cargoController.text.trim().isEmpty
            ? null
            : _cargoController.text.trim(),
        // Un campo bloqueado muestra la máscara: el valor que se guarda es el
        // que trajo el QR.
        telefono: _telefonoAGuardar(puedeVerContacto: puedeVerContacto),
        email: _emailAGuardar(puedeVerContacto: puedeVerContacto),
        descripcion: _descripcionController.text.trim().isEmpty
            ? null
            : _descripcionController.text.trim(),
        fotosUrls: fotos,
        perfilId: userId,
      );
      leadPreparado = lead;

      LeadWriteResult? result;
      var fotoPendienteDeSync = false;
      if (isOnline) {
        try {
          result = await ref.read(leadsRepositoryProvider).crear(lead);
        } on LeadPhotoPendingException catch (error) {
          result = error.result;
          await ref
              .read(syncQueueServiceProvider.notifier)
              .enqueueUpdate(
                table: SupabaseTables.leads,
                entityId: error.result.leadId,
                changes: {'fotos_urls': error.fotosPendientes},
              );
          fotoPendienteDeSync = true;
        }
      } else {
        await ref
            .read(syncQueueServiceProvider.notifier)
            .enqueueInsert(
              table: SupabaseTables.leads,
              payload: {
                ...lead.toInsertMap(),
                '_requested_lead_id': _uuid.v4(),
              },
            );
      }

      ref.invalidate(leadsPorEventoProvider(widget.eventoId));
      if (perfil?.isExterno == true) {
        ref.invalidate(externoDashboardProvider);
      }

      if (mounted) {
        if (result?.esDuplicado == true) {
          final store = ref.read(pendingPhotoStoreProvider);
          for (final foto in fotos.where(esFotoLocal)) {
            await store.borrar(foto);
          }
          if (!mounted) return;
          await ofrecerComentarLeadDuplicado(
            context,
            ref,
            eventoId: widget.eventoId,
            leadId: result!.leadId,
            mensajeDuplicado: result.mensajeDuplicado,
            desdeEvento: widget.eventoRegistroId,
          );
          return;
        }
        if (result?.guardado == true &&
            _fotoBytes != null &&
            fotos.isEmpty &&
            isOnline) {
          try {
            await ref
                .read(leadsRepositoryProvider)
                .adjuntarFotoBytes(result!.leadId, _fotoBytes!);
          } catch (_) {
            if (!mounted) return;
            _leadGuardadoPendienteFotoId = result!.leadId;
            showAppSnackBar(
              context,
              'Lead guardado; foto pendiente, reintenta',
              isError: true,
            );
            return;
          }
        }
        if (!mounted) return;
        showAppSnackBar(context, switch ((isOnline, fotoDescartada)) {
          (true, _) when fotoPendienteDeSync =>
            'Lead guardado. La foto se sincronizará automáticamente.',
          (true, _) => 'Lead guardado.',
          (false, true) =>
            'Guardado en modo local, pero sin la foto: se necesita '
                'conexión para adjuntarla.',
          (false, false) => 'Guardado, se sincronizará cuando estés conectado.',
        }, isError: fotoDescartada);
        await _finalizarFlujoGuardado();
      }
    } catch (e) {
      if (isOnline && leadPreparado != null && isNetworkTransportError(e)) {
        try {
          await ref
              .read(syncQueueServiceProvider.notifier)
              .enqueueInsert(
                table: SupabaseTables.leads,
                payload: {
                  ...leadPreparado.toInsertMap(),
                  '_requested_lead_id': _uuid.v4(),
                },
              );
          ref.invalidate(leadsPorEventoProvider(widget.eventoId));
          if (mounted) {
            showAppSnackBar(
              context,
              'Sin conexión real. El lead quedó guardado localmente.',
            );
            await _finalizarFlujoGuardado();
          }
          return;
        } catch (_) {
          // Continúa al error original y limpia marcadores sin referencia.
        }
      }
      final store = ref.read(pendingPhotoStoreProvider);
      for (final foto in fotosPreparadas.where(esFotoLocal)) {
        await store.borrar(foto);
      }
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

  /// Micrófono de dictado. Sobre la card navy el rojo de "grabando" no se
  /// distingue, así que ahí se usa la lima del brand.
  Widget? _botonVoz(_CampoVoz campo, {bool sobreNavy = false}) {
    if (!_speechDisponible) return null;
    final escuchando = _escuchandoCampo == campo;
    return IconButton(
      tooltip: escuchando ? 'Detener dictado' : 'Dictar',
      onPressed: _guardando ? null : () => _toggleVoz(campo),
      icon: Icon(
        escuchando ? Icons.mic : Icons.mic_none_outlined,
        color: sobreNavy
            ? (escuchando ? AppColors.accent : Colors.white)
            : (escuchando ? AppColors.danger : AppColors.primary),
      ),
    );
  }

  Widget _campoTexto({
    required String label,
    required TextEditingController controller,
    required String hintText,
    _CampoVoz? campoVoz,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool opcional = false,
    bool protegido = false,
    bool autocorrect = true,
    bool enableSuggestions = true,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final escuchando = campoVoz != null && _escuchandoCampo == campoVoz;
    final sufijo = protegido
        ? const Icon(
            Symbols.lock_rounded,
            size: 18,
            color: AppColors.textTertiary,
          )
        : (campoVoz == null ? null : _botonVoz(campoVoz));
    return FormLabeledField(
      label: label,
      opcional: opcional,
      ayuda: protegido
          ? 'Solo visible para administradores y organizadores'
          : null,
      child: TextFormField(
        controller: controller,
        enabled: !escuchando && !_guardando,
        readOnly: protegido,
        keyboardType: keyboardType,
        minLines: maxLines > 1 ? 3 : null,
        maxLines: maxLines,
        validator: validator,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        inputFormatters: inputFormatters,
        textCapitalization: keyboardType == null
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        decoration:
            (protegido
                    ? twReadOnlyDecoration(hintText: hintText)
                    : InputDecoration(hintText: hintText))
                .copyWith(alignLabelWithHint: maxLines > 1, suffixIcon: sufijo),
      ),
    );
  }

  bool get _hayDatos =>
      [
        _nombreController,
        _empresaController,
        _cargoController,
        _descripcionController,
      ].any((c) => c.text.trim().isNotEmpty) ||
      (_emailPrefill == null && _emailController.text.trim().isNotEmpty) ||
      (_telefonoPrefill == null &&
          _telefonoController.text.trim().isNotEmpty) ||
      _fotoBytes != null;

  @override
  Widget build(BuildContext context) {
    ref.listen(externoEventosAutorizadosIdsProvider, (_, _) {
      if (!_accesoValidado) _validarAccesoExterno();
    });
    // El perfil puede resolverse después del primer frame: al llegar el rol se
    // repinta el contacto precargado con o sin máscara.
    ref.listen(canViewContactDataProvider, (_, puedeVerContacto) {
      if (!mounted) return;
      setState(
        () => _sincronizarMascaraContacto(puedeVerContacto: puedeVerContacto),
      );
    });

    final eventoAsync = ref.watch(eventoLeadByIdProvider(widget.eventoId));
    final evento = eventoAsync.valueOrNull;
    if (evento != null) _inicializarPaisTelefonoEvento(evento.pais);
    final puedeVerContacto = ref.watch(canViewContactDataProvider);
    final emailBloqueado = _contactoBloqueado(_emailPrefill, puedeVerContacto);
    final telefonoBloqueado = _contactoBloqueado(
      _telefonoPrefill,
      puedeVerContacto,
    );

    return AppScaffold(
      titleWidget: eventoAsync.when(
        data: (e) =>
            Text('Capturar · ${e.nombre}', overflow: TextOverflow.ellipsis),
        loading: () => const Text('Capturar lead'),
        error: (_, _) => const Text('Capturar lead'),
      ),
      onWillPop: () => confirmDiscardCreate(context, hayDatos: _hayDatos),
      bottomBar: FormActionBar(
        label: 'Guardar lead',
        loading: _guardando,
        onPressed: _guardando ? null : _guardar,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          TwSpacing.screenH,
          2,
          TwSpacing.screenH,
          28,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListenableBuilder(
                listenable: _emailController,
                builder: (context, _) {
                  return PersonaIdentityBanner(
                    nombre: _nombreController.text,
                    email: _emailController.text,
                    nombreController: _nombreController,
                    nombreHint: 'Ej. María González',
                    nombreEnabled:
                        !_guardando && _escuchandoCampo != _CampoVoz.nombre,
                    nombreValidator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                    nombreSuffix: _botonVoz(_CampoVoz.nombre, sobreNavy: true),
                    leading: FotoLeadAvatar(
                      bytes: _fotoBytes,
                      enabled: !_guardando,
                      onElegir: _elegirFoto,
                      onQuitar: _fotoBytes == null
                          ? null
                          : () => setState(() => _fotoBytes = null),
                    ),
                  );
                },
              ),
              const SizedBox(height: FormSection.gap),
              FormSection(
                icon: Symbols.business_center_rounded,
                title: 'Empresa',
                children: [
                  _campoTexto(
                    label: 'Empresa',
                    controller: _empresaController,
                    hintText: 'Ej. Transworld',
                    campoVoz: _CampoVoz.empresa,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Escribe la empresa.'
                        : null,
                  ),
                  _campoTexto(
                    label: 'Cargo',
                    controller: _cargoController,
                    hintText: 'Ej. Gerente comercial',
                    campoVoz: _CampoVoz.cargo,
                    opcional: true,
                  ),
                ],
              ),
              const SizedBox(height: FormSection.gap),
              FormSection(
                icon: Symbols.contact_phone_rounded,
                title: 'Contacto',
                children: [
                  if (telefonoBloqueado)
                    _campoTexto(
                      label: 'Teléfono',
                      controller: _telefonoController,
                      hintText: 'Contacto protegido',
                      keyboardType: TextInputType.phone,
                      protegido: true,
                    )
                  else
                    FormLabeledField(
                      label: 'Teléfono',
                      opcional: true,
                      child: CampoTelefonoInternacional(
                        controller: _telefonoController,
                        pais: _paisTelefono,
                        onPaisChanged: (pais) =>
                            setState(() => _paisTelefono = pais),
                        enabled: !_guardando,
                        requerido: false,
                        labelText: null,
                      ),
                    ),
                  _campoTexto(
                    label: 'Correo',
                    controller: _emailController,
                    hintText: 'correo@empresa.com',
                    campoVoz: emailBloqueado ? null : _CampoVoz.email,
                    keyboardType: TextInputType.emailAddress,
                    validator: emailBloqueado ? null : validarEmailRegistro,
                    protegido: emailBloqueado,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: const [LowerCaseTextFormatter()],
                  ),
                ],
              ),
              const SizedBox(height: FormSection.gap),
              FormSection(
                icon: Symbols.sticky_note_2_rounded,
                title: 'Notas',
                children: [
                  _campoTexto(
                    label: 'Descripción',
                    controller: _descripcionController,
                    hintText: 'Qué le interesa, próximos pasos…',
                    campoVoz: _CampoVoz.descripcion,
                    keyboardType: TextInputType.multiline,
                    maxLines: 5,
                    opcional: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
