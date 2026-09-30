import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_role.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/utils/password_generator.dart';
import '../../../core/utils/password_policy.dart';
import '../../../core/utils/registro_asistente.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/campos_registro_asistente.dart';
import '../../../core/widgets/form_sections.dart';
import '../../../core/widgets/require_admin.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../providers/usuarios_providers.dart';
import '../widgets/selector_eventos_multiples.dart';
import '../widgets/selector_rol_usuario.dart';

/// Crea un usuario (cualquier rol) desde gestión de administradores.
class NuevoUsuarioScreen extends StatelessWidget {
  const NuevoUsuarioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RequireAdmin(builder: (context) => const _NuevoUsuarioForm());
  }
}

class _NuevoUsuarioForm extends ConsumerStatefulWidget {
  const _NuevoUsuarioForm();

  @override
  ConsumerState<_NuevoUsuarioForm> createState() => _NuevoUsuarioFormState();
}

class _NuevoUsuarioFormState extends ConsumerState<_NuevoUsuarioForm> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  late final TextEditingController _passwordController;

  AppRole? _rol;
  final Set<String> _eventoIds = {};
  bool _intentoGuardar = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController(
      text: generarContrasenaInvitacion(),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _esExterno => _rol == AppRole.externo;
  bool get _asignaEventos => _rol?.requiresEventAssignment ?? false;

  String _textoCompartir({List<String> eventoNombres = const []}) {
    final buffer = StringBuffer()
      ..writeln('Acceso Transworld RegisPro')
      ..writeln('Nombre: ${_nombreController.text.trim()}')
      ..writeln('Email: ${formatearEmail(_emailController.text)}')
      ..writeln('Contraseña: ${_passwordController.text}');
    if (eventoNombres.isNotEmpty) {
      buffer.writeln(
        eventoNombres.length == 1
            ? 'Evento: ${eventoNombres.first}'
            : 'Eventos: ${eventoNombres.join(', ')}',
      );
    }
    return buffer.toString().trimRight();
  }

  Future<void> _compartir({List<String> eventoNombres = const []}) async {
    if (_emailController.text.trim().isEmpty) {
      showAppSnackBar(context, 'Ingresa un email para compartir.');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(text: _textoCompartir(eventoNombres: eventoNombres)),
    );
  }

  Future<void> _guardar() async {
    if (!requireOnline(context, ref)) return;
    setState(() => _intentoGuardar = true);
    if (!_formKey.currentState!.validate()) return;
    if (_rol == null) {
      showAppSnackBar(context, 'Selecciona el tipo de usuario.');
      return;
    }
    if (_esExterno && _eventoIds.isEmpty) {
      showAppSnackBar(context, 'Selecciona al menos un evento.');
      return;
    }

    final router = GoRouter.of(context);
    setState(() => _guardando = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      final email = formatearEmail(_emailController.text);
      _emailController.text = email;
      if (await repo.verificarEmailRegistrado(email)) {
        if (mounted) {
          showAppSnackBar(
            context,
            'El email ya está registrado.',
            isError: true,
          );
        }
        return;
      }

      await repo.crearUsuario(
        nombreCompleto: _nombreController.text.trim(),
        email: email,
        password: _passwordController.text,
        rol: _rol!.value,
        eventoIds: _asignaEventos ? _eventoIds.toList() : null,
      );

      if (mounted) {
        ref.invalidate(usuariosListProvider);
        showAppSnackBar(
          context,
          'Usuario creado. Credenciales enviadas por correo.',
        );
      }
      router.go(RoutePaths.usuarios);
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

  bool get _hayDatos =>
      _nombreController.text.trim().isNotEmpty ||
      _emailController.text.trim().isNotEmpty ||
      _rol != null;

  void _compartirConEventos() {
    final eventos = ref.read(eventosListProvider).valueOrNull ?? [];
    final nombres = eventos
        .where((e) => _eventoIds.contains(e.id))
        .map((e) => e.nombre)
        .toList();
    _compartir(eventoNombres: nombres);
  }

  @override
  Widget build(BuildContext context) {
    final eventosAsync = ref.watch(eventosListProvider);

    return AppScaffold(
      title: 'Nuevo usuario',
      onWillPop: () => confirmDiscardCreate(context, hayDatos: _hayDatos),
      actions: [
        NexusHeaderAction(
          icon: Symbols.share_rounded,
          tooltip: 'Compartir credenciales',
          onTap: _guardando ? null : _compartirConEventos,
        ),
      ],
      bottomBar: FormActionBar(
        label: 'Crear usuario',
        loading: _guardando,
        onPressed: _guardando ? null : _guardar,
      ),
      body: AbsorbPointer(
        absorbing: _guardando,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            TwSpacing.screenH,
            14,
            TwSpacing.screenH,
            28,
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FormNotice(
                  'Al crear la cuenta se envían las credenciales al correo '
                  'del usuario.',
                ),
                const SizedBox(height: FormSection.gap),
                FormSection(
                  icon: Symbols.person_rounded,
                  title: 'Datos de la cuenta',
                  children: [
                    FormLabeledField(
                      label: 'Nombre completo',
                      child: TextFormField(
                        controller: _nombreController,
                        enabled: !_guardando,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'Ej. Juan Pérez',
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Escribe el nombre.'
                            : null,
                      ),
                    ),
                    FormLabeledField(
                      label: 'Correo',
                      child: TextFormField(
                        controller: _emailController,
                        enabled: !_guardando,
                        decoration: const InputDecoration(
                          hintText: 'usuario@empresa.com',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        inputFormatters: const [LowerCaseTextFormatter()],
                        validator: validarEmailRegistro,
                      ),
                    ),
                    FormLabeledField(
                      label: 'Contraseña inicial',
                      ayuda: kPasswordHelperText,
                      child: TextFormField(
                        controller: _passwordController,
                        enabled: !_guardando,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          hintText: 'Autogenerada',
                          suffixIcon: IconButton(
                            tooltip: 'Generar otra',
                            onPressed: _guardando
                                ? null
                                : () => setState(() {
                                    _passwordController.text =
                                        generarContrasenaInvitacion();
                                  }),
                            icon: const Icon(Symbols.refresh_rounded),
                          ),
                        ),
                        validator: validarContrasenaFuerte,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FormSection.gap),
                FormSection(
                  icon: Symbols.shield_person_rounded,
                  title: 'Tipo de usuario',
                  subtitle: 'Define qué puede ver y hacer en la app.',
                  children: [
                    SelectorRolUsuario(
                      roles: AppRole.creatableRoles,
                      value: _rol,
                      error: _intentoGuardar && _rol == null,
                      onChanged: _guardando
                          ? null
                          : (v) => setState(() {
                              _rol = v;
                              if (!v.requiresEventAssignment) {
                                _eventoIds.clear();
                              }
                            }),
                    ),
                    if (_intentoGuardar && _rol == null)
                      const FormNotice(
                        'Elige el tipo de usuario.',
                        error: true,
                      ),
                  ],
                ),
                if (_asignaEventos) ...[
                  const SizedBox(height: FormSection.gap),
                  FormSection(
                    icon: Symbols.event_rounded,
                    title: 'Eventos autorizados',
                    subtitle: _esExterno
                        ? 'Solo verá los eventos que elijas.'
                        : 'Podrá registrar y acreditar en estos eventos.',
                    children: [
                      eventosAsync.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(),
                        ),
                        error: (_, _) => const FormNotice(
                          'No se pudieron cargar los eventos.',
                          error: true,
                        ),
                        data: (eventos) {
                          return SelectorEventosMultiples(
                            eventos: eventos,
                            seleccionados: _eventoIds,
                            enabled: !_guardando,
                            soloActivosDisponibles: _esExterno,
                            emptyHelperText: _esExterno
                                ? 'Selecciona al menos un evento.'
                                : 'Sin eventos asignados: el usuario no podrá operar eventos.',
                            errorText:
                                _esExterno &&
                                    _intentoGuardar &&
                                    _eventoIds.isEmpty
                                ? 'Selecciona al menos un evento'
                                : null,
                            onChanged: (ids) => setState(() {
                              _eventoIds
                                ..clear()
                                ..addAll(ids);
                            }),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
