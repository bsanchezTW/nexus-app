import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/offline_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/password_policy.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/tw_skeletons.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../core/widgets/selector_imagen.dart';
import '../../../data/models/lead.dart';
import '../../../data/models/perfil.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/storage_cleanup_service.dart';
import '../../../data/repositories/storage_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/perfil_providers.dart';
import '../widgets/perfil_expandable_section.dart';
import '../../../core/widgets/espera_bloqueante.dart';

class MiPerfilScreen extends StatelessWidget {
  const MiPerfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // El externo llega aquí desde su foto en la cabecera: es su propia ficha,
    // no una pantalla del shell interno. Lo que se recorta son los indicadores
    // de operaciones que él no realiza (ver [_KpiSection]).
    return const _MiPerfilBody();
  }
}

class _MiPerfilBody extends ConsumerStatefulWidget {
  const _MiPerfilBody();

  @override
  ConsumerState<_MiPerfilBody> createState() => _MiPerfilBodyState();
}

class _MiPerfilBodyState extends ConsumerState<_MiPerfilBody> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _leadsExpandido = false;
  bool _datosExpandido = false;
  bool _nombreCargado = false;
  bool _guardando = false;
  bool _subiendoFoto = false;
  bool _mostrarPassword = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Los datos de cuenta viven solo en el servidor: nombre, foto y contraseña
  /// no tienen copia local ni cola. Guardarlos sin red dejaría al usuario
  /// creyendo que cambió su contraseña cuando la vieja sigue siendo la válida.
  bool _exigirRed() => requireOnline(context, ref);

  Future<void> _guardarDatos() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_exigirRed()) return;

    // En blanco significa "no cambiar la contraseña".
    final nuevaPassword = _passwordController.text;

    setState(() => _guardando = true);
    await conEspera(context, () async {
      try {
        final auth = ref.read(authRepositoryProvider);
        // Primero la contraseña: es el paso que más suele fallar (Supabase
        // rechaza repetir la actual), así un error no deja el nombre a medias.
        if (nuevaPassword.isNotEmpty) {
          // `forzarNuevaContrasena` además limpia `cambiar_pass`, para que el
          // router no vuelva a exigir /recrear-pass a quien acaba de elegirla.
          await auth.forzarNuevaContrasena(nuevaPassword);
          _passwordController.clear();
        }
        await auth.actualizarNombrePropio(_nombreController.text.trim());
        ref.invalidate(currentPerfilProvider);
        if (mounted) {
          showAppSnackBar(
            context,
            nuevaPassword.isEmpty
                ? 'Nombre actualizado.'
                : 'Datos y contraseña actualizados.',
          );
        }
      } on AuthException catch (e) {
        if (mounted) showAppSnackBar(context, e.message, isError: true);
      } on PostgrestException catch (e) {
        if (mounted) showAppSnackBar(context, e.message, isError: true);
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
    });
  }

  Future<void> _cambiarFoto() async {
    if (_subiendoFoto) return;
    if (!_exigirRed()) return;

    final bytes = await elegirImagenComprimida(
      context,
      recorteProporcion: kProporcionFotoLead,
      tituloRecorte: 'Recortar foto de perfil',
    );
    if (bytes == null || !mounted) return;

    setState(() => _subiendoFoto = true);
    try {
      final auth = ref.read(authRepositoryProvider);
      final userId = auth.currentUserId;
      if (userId == null) {
        throw Exception('No hay sesión activa.');
      }

      final url = await ref
          .read(storageRepositoryProvider)
          .subirFotoPerfil(bytes, userId);
      await auth.actualizarFotoPropia(url);
      await ref.read(storageCleanupServiceProvider).drenar();
      ref.invalidate(currentPerfilProvider);
      await ref.read(currentPerfilProvider.future);

      if (mounted) {
        showAppSnackBar(context, 'Foto de perfil actualizada.');
      }
    } on PostgrestException catch (e) {
      if (mounted) showAppSnackBar(context, e.message, isError: true);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfilAsync = ref.watch(currentPerfilProvider);
    final statsAsync = ref.watch(miPerfilStatsProvider);
    final leadsAsync = ref.watch(misLeadsProvider);
    final email =
        ref.watch(authRepositoryProvider).emailSesionActual ?? 'Sin correo';

    return AppScaffold(
      title: 'Mi Perfil',
      body: perfilAsync.when(
        loading: () => ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: AppSpacing.form,
          children: const [
            TwRowSkeleton(leading: TwSkeletonLeading.avatar, conPildora: true),
            SizedBox(height: AppSpacing.sectionGap),
            TwSectionLabelSkeleton(top: 0, ancho: 70),
            TwKpiRowSkeleton(),
            SizedBox(height: 12),
            TwKpiRowSkeleton(),
            SizedBox(height: AppSpacing.sectionGap),
            TwActionTileSkeleton(),
            SizedBox(height: 12),
            TwActionTileSkeleton(anchoTitulo: 0.5),
          ],
        ),
        error: (e, _) => ErrorView(
          message: 'No se pudo cargar tu perfil.',
          onRetry: () => ref.invalidate(currentPerfilProvider),
        ),
        data: (perfil) {
          if (perfil == null) {
            return const EmptyStateView(
              icon: Icons.person_off_outlined,
              message: 'No se encontró tu perfil.',
            );
          }

          if (!_nombreCargado) {
            _nombreController.text = perfil.nombreCompleto;
            _nombreCargado = true;
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => refrescarLecturas(
              ref,
              context: context,
              invalidar: () {
                ref.invalidate(currentPerfilProvider);
                ref.invalidate(miPerfilStatsProvider);
                ref.invalidate(misLeadsProvider);
              },
              pendientes: () => [
                ref.read(currentPerfilProvider.future),
                ref.read(miPerfilStatsProvider.future),
                ref.read(misLeadsProvider.future),
              ],
            ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: AppSpacing.form,
              children: [
                _PerfilHeader(
                  perfil: perfil,
                  email: email,
                  subiendoFoto: _subiendoFoto,
                  onCambiarFoto: _cambiarFoto,
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                const SectionLabel('Resumen'),
                const SizedBox(height: 12),
                _KpiSection(statsAsync: statsAsync),
                const SizedBox(height: AppSpacing.sectionGap),
                PerfilExpandableSection(
                  icon: Symbols.group_rounded,
                  title: 'Detalle de Leads Capturados',
                  subtitle: leadsAsync.maybeWhen(
                    data: (leads) => leads.isEmpty
                        ? 'Sin registros'
                        : '${leads.length} lead${leads.length == 1 ? '' : 's'}',
                    orElse: () => null,
                  ),
                  expanded: _leadsExpandido,
                  onToggle: () =>
                      setState(() => _leadsExpandido = !_leadsExpandido),
                  child: _LeadsDetalle(leadsAsync: leadsAsync),
                ),
                const SizedBox(height: 12),
                PerfilExpandableSection(
                  icon: Symbols.badge_rounded,
                  title: 'Mis Datos de Usuario',
                  subtitle: 'Nombre, correo, contraseña y tipo de cuenta',
                  expanded: _datosExpandido,
                  onToggle: () =>
                      setState(() => _datosExpandido = !_datosExpandido),
                  child: _DatosUsuarioForm(
                    formKey: _formKey,
                    nombreController: _nombreController,
                    passwordController: _passwordController,
                    email: email,
                    rolLabel: perfil.rol.label,
                    guardando: _guardando,
                    mostrarPassword: _mostrarPassword,
                    onToggleMostrarPassword: () =>
                        setState(() => _mostrarPassword = !_mostrarPassword),
                    onGuardar: _guardarDatos,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PerfilHeader extends StatelessWidget {
  const _PerfilHeader({
    required this.perfil,
    required this.email,
    required this.subiendoFoto,
    required this.onCambiarFoto,
  });

  final Perfil perfil;
  final String email;
  final bool subiendoFoto;
  final VoidCallback onCambiarFoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadowRest,
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AvatarPerfil(
                nombre: perfil.nombreCompleto,
                fotoUrl: perfil.fotoUrl,
                size: 52,
                index: 0,
                mostrarLapiz: !subiendoFoto,
                onTap: subiendoFoto ? null : onCambiarFoto,
              ),
              if (subiendoFoto)
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  perfil.nombreCompleto,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                StatusChip(
                  label: perfil.rol.label,
                  variant: StatusChipVariant.navy,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiSection extends ConsumerWidget {
  const _KpiSection({required this.statsAsync});

  final AsyncValue<MiPerfilStats> statsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statsAsync.when(
      loading: () => const Column(
        children: [
          TwKpiRowSkeleton(),
          SizedBox(height: 12),
          TwKpiRowSkeleton(),
        ],
      ),
      error: (e, _) => ErrorView(
        message: 'No se pudieron cargar los indicadores.',
        onRetry: () => ref.invalidate(miPerfilStatsProvider),
      ),
      data: (stats) {
        // El externo no registra asistentes, no acredita y no crea eventos:
        // mostrarle esos indicadores en cero parece un error suyo, no una
        // capacidad que no tiene.
        final soloLeads =
            ref.watch(currentPerfilProvider).valueOrNull?.isExterno ?? false;
        final cards = <_KpiCardData>[
          _KpiCardData(
            value: '${stats.leadsCapturados}',
            label: 'Leads capturados',
            icon: Symbols.person_search_rounded,
            tint: AppColors.tintNavy,
            iconColor: AppColors.primary,
          ),
          if (!soloLeads) ...[
            _KpiCardData(
              value: '${stats.asistentesRegistrados}',
              label: 'Asist. registrados',
              icon: Symbols.group_rounded,
              tint: AppColors.successTint,
              iconColor: AppColors.success,
            ),
            _KpiCardData(
              value: '${stats.acreditaciones}',
              label: 'Acreditaciones',
              icon: Symbols.verified_rounded,
              tint: AppColors.successTint,
              iconColor: AppColors.success,
              // Única tarjeta con detalle propio: abre el listado de a quién
              // acreditó esta persona, seccionado por evento.
              onTap: () => context.push(RoutePaths.misAcreditados),
            ),
            _KpiCardData(
              value: '${stats.eventosCreados}',
              label: 'Eventos creados',
              icon: Symbols.calendar_month_rounded,
              tint: AppColors.warningTint,
              iconColor: AppColors.warning,
            ),
          ],
        ];

        // Rejilla de dos columnas que tolera un número impar de tarjetas: el
        // externo solo ve una y antes esto indexaba cuatro fijas.
        final filas = (cards.length / 2).ceil();
        return Column(
          children: [
            for (var row = 0; row < filas; row++) ...[
              if (row > 0) const SizedBox(height: 12),
              Row(
                children: [
                  for (var col = 0; col < 2; col++) ...[
                    if (col > 0) const SizedBox(width: 12),
                    Expanded(
                      child: row * 2 + col < cards.length
                          ? cards[row * 2 + col].build()
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Datos de una tarjeta del resumen. Antes era una tupla posicional de cinco
/// campos; con el `onTap` de "Acreditaciones" indexarlos por `$1..$5` dejaba de
/// leerse.
class _KpiCardData {
  const _KpiCardData({
    required this.value,
    required this.label,
    required this.icon,
    required this.tint,
    required this.iconColor,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final VoidCallback? onTap;

  StatCard build() => StatCard(
    value: value,
    label: label,
    icon: icon,
    tint: tint,
    iconColor: iconColor,
    onTap: onTap,
  );
}

class _LeadsDetalle extends ConsumerWidget {
  const _LeadsDetalle({required this.leadsAsync});

  final AsyncValue<List<Lead>> leadsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return leadsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: TwListSkeleton(leading: TwSkeletonLeading.avatar, filas: 3),
      ),
      error: (e, _) => ErrorView(
        message: 'No se pudieron cargar tus leads.',
        onRetry: () => ref.invalidate(misLeadsProvider),
      ),
      data: (leads) {
        if (leads.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: EmptyStateView(
              icon: Icons.person_off_outlined,
              message: 'Aún no has capturado leads.',
            ),
          );
        }

        return Column(
          children: [
            for (var i = 0; i < leads.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _LeadResumenTile(lead: leads[i], index: i),
            ],
          ],
        );
      },
    );
  }
}

class _LeadResumenTile extends StatelessWidget {
  const _LeadResumenTile({required this.lead, required this.index});

  final Lead lead;
  final int index;

  @override
  Widget build(BuildContext context) {
    final empresa = (lead.empresa == null || lead.empresa!.trim().isEmpty)
        ? 'Sin empresa'
        : lead.empresa!.trim();
    final createdAt = lead.createdAt?.toLocal();
    final fecha = createdAt == null
        ? '—'
        : DateFormat('dd/MM/yyyy').format(createdAt);
    final hora = createdAt == null
        ? '—'
        : DateFormat('HH:mm').format(createdAt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          AvatarInitials(name: lead.nombreCompleto, size: 40, index: index),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lead.nombreCompleto,
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
                  empresa,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$fecha · $hora',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DatosUsuarioForm extends StatelessWidget {
  const _DatosUsuarioForm({
    required this.formKey,
    required this.nombreController,
    required this.passwordController,
    required this.email,
    required this.rolLabel,
    required this.guardando,
    required this.mostrarPassword,
    required this.onToggleMostrarPassword,
    required this.onGuardar,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nombreController;
  final TextEditingController passwordController;
  final String email;
  final String rolLabel;
  final bool guardando;
  final bool mostrarPassword;
  final VoidCallback onToggleMostrarPassword;
  final VoidCallback onGuardar;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FieldLabel('Nombre'),
          const SizedBox(height: 6),
          TextFormField(
            controller: nombreController,
            enabled: !guardando,
            decoration: const InputDecoration(hintText: 'Tu nombre completo'),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Correo electrónico'),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: email,
            readOnly: true,
            enableInteractiveSelection: true,
            decoration: twReadOnlyDecoration(
              hintText: 'Correo de la cuenta',
              helperText:
                  'El correo pertenece a tu cuenta y no se puede cambiar.',
            ),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Contraseña'),
          const SizedBox(height: 6),
          TextFormField(
            controller: passwordController,
            enabled: !guardando,
            obscureText: !mostrarPassword,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Escribe una nueva contraseña',
              helperText:
                  'Déjalo en blanco para mantener la actual. $kPasswordHelperText',
              helperMaxLines: 3,
              // El mismo ojo que el login, no un IconButton con ripple.
              //
              // `suffixIcon` no respeta el `contentPadding` del tema, así que
              // sin este relleno el icono queda pegado al borde del campo. Los
              // 14 px son los mismos que separan el texto del borde.
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: TwPasswordEye(
                  visible: mostrarPassword,
                  onTap: guardando ? null : onToggleMostrarPassword,
                ),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 52,
              ),
            ),
            // Vacío = no se cambia la contraseña; con contenido, debe ser fuerte.
            validator: (v) =>
                (v == null || v.isEmpty) ? null : validarContrasenaFuerte(v),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Tipo de usuario'),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: rolLabel,
            readOnly: true,
            decoration: twReadOnlyDecoration(hintText: 'Rol'),
          ),
          const SizedBox(height: 18),
          PrimaryGradientButton(
            label: 'Guardar cambios',
            loading: guardando,
            onPressed: guardando ? null : onGuardar,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
  }
}
