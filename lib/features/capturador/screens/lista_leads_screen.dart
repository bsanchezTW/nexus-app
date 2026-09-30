import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/router/refresh_on_visible.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mascara_contacto.dart';
import '../../../core/utils/registro_asistente.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/campos_registro_asistente.dart';
import '../../../core/widgets/collapsing_nav.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/form_sections.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/selector_imagen.dart';
import '../../../data/models/lead.dart';
import '../../../data/models/lead_write_result.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/offline/pending_photo_store.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../data/repositories/leads_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../lead_comentario_flujo.dart';
import '../providers/capturador_providers.dart';
import '../widgets/avatar_lead.dart';
import '../widgets/foto_lead_identidad.dart';
import '../../../data/repositories/storage_cleanup_service.dart';

enum _FiltroLead { todos, mios, deOtros }

class ListaLeadsScreen extends ConsumerStatefulWidget {
  const ListaLeadsScreen({super.key, required this.eventoId, this.desdeEvento});

  final String eventoId;
  final String? desdeEvento;

  @override
  ConsumerState<ListaLeadsScreen> createState() => _ListaLeadsScreenState();
}

class _ListaLeadsScreenState extends ConsumerState<ListaLeadsScreen>
    with RefreshOnVisible {
  @override
  String get refreshWhenLocation => RoutePaths.verLeads(widget.eventoId);

  @override
  void onBecomeVisible() {
    ref.invalidate(leadsPorEventoProvider(widget.eventoId));
  }

  static const _filtroLabels = {
    _FiltroLead.todos: 'Todos',
    _FiltroLead.mios: 'Mis leads',
    _FiltroLead.deOtros: 'De otros',
  };

  final _busquedaController = TextEditingController();
  _FiltroLead _filtro = _FiltroLead.todos;
  String _busqueda = '';
  Timer? _debounce;

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
        onChanged: (value) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 300), () {
            if (mounted) {
              setState(() => _busqueda = value.trim().toLowerCase());
            }
          });
        },
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar lead…',
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

  List<Lead> _filtrarLeads(
    List<Lead> leads, {
    required bool canViewAllLeads,
    required bool puedeVerContacto,
    String? perfilId,
  }) {
    return leads.where((lead) {
      if (!canViewAllLeads && lead.perfilId != perfilId) return false;
      if (canViewAllLeads &&
          _filtro == _FiltroLead.mios &&
          (perfilId == null || lead.perfilId != perfilId)) {
        return false;
      }
      if (canViewAllLeads &&
          _filtro == _FiltroLead.deOtros &&
          perfilId != null &&
          lead.perfilId == perfilId) {
        return false;
      }
      if (_busqueda.isEmpty) return true;

      // Sin permiso para ver el contacto tampoco se busca por email: si no, el
      // correo oculto se podría reconstruir por tanteo.
      return lead.nombreCompleto.toLowerCase().contains(_busqueda) ||
          (lead.empresa ?? '').toLowerCase().contains(_busqueda) ||
          (puedeVerContacto &&
              (lead.email ?? '').toLowerCase().contains(_busqueda));
    }).toList();
  }

  void _actualizarLeads() {
    ref.invalidate(leadsPorEventoProvider(widget.eventoId));
  }

  Widget _buildPinnedControls({required bool canViewAllLeads}) {
    return Column(
      children: [
        SizedBox(height: 48, child: _buildSearchField()),
        if (canViewAllLeads) ...[
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
                    final filtro = _filtroLabels.entries
                        .firstWhere((entry) => entry.value == label)
                        .key;
                    setState(() => _filtro = filtro);
                  },
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHeader({int? total, int? mios, bool canViewAllLeads = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          canViewAllLeads ? 'Leads' : 'Mis leads',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 2),
        Text(
          total == null
              ? 'Leads capturados del evento'
              : canViewAllLeads
              ? '$total ${total == 1 ? 'lead' : 'leads'} · $mios míos'
              : '$total ${total == 1 ? 'lead propio' : 'leads propios'}',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final leadsAsync = ref.watch(leadsPorEventoProvider(widget.eventoId));
    final perfilId = ref.watch(currentPerfilProvider).valueOrNull?.id;
    final canViewAllLeads = ref.watch(canViewAllLeadsProvider);
    final puedeVerContacto = ref.watch(canViewContactDataProvider);

    final filtrados = leadsAsync.maybeWhen(
      data: (leads) => _filtrarLeads(
        leads,
        canViewAllLeads: canViewAllLeads,
        puedeVerContacto: puedeVerContacto,
        perfilId: perfilId,
      ),
      orElse: () => const <Lead>[],
    );
    final listaVacia = leadsAsync.hasValue && filtrados.isEmpty;

    return CollapsingScrollScaffold(
      title: canViewAllLeads ? 'Leads' : 'Mis leads',
      alwaysShowActions: true,
      overlayLeading: CollapsingNavButton(
        icon: Symbols.arrow_back_rounded,
        tooltip: 'Volver',
        onTap: () => volverAtras(context),
      ),
      pinnedContent: _buildPinnedControls(canViewAllLeads: canViewAllLeads),
      pinnedContentHeight: canViewAllLeads ? 112 : 60,
      scrollResetToken: '$_busqueda|$_filtro',
      lockScroll: listaVacia,
      onRefresh: () async => _actualizarLeads(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: leadsAsync.when(
              skipLoadingOnReload: true,
              loading: () => _buildHeader(canViewAllLeads: canViewAllLeads),
              error: (_, _) => _buildHeader(canViewAllLeads: canViewAllLeads),
              data: (leads) => _buildHeader(
                total: leads.length,
                mios: perfilId == null
                    ? 0
                    : leads.where((lead) => lead.perfilId == perfilId).length,
                canViewAllLeads: canViewAllLeads,
              ),
            ),
          ),
        ),
        ...leadsAsync.when(
          skipLoadingOnReload: true,
          loading: () => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: LoadingView(),
            ),
          ],
          error: (_, _) => [
            SliverFillRemaining(
              child: ErrorView(
                message: 'No se pudieron cargar los leads.',
                onRetry: () =>
                    ref.invalidate(leadsPorEventoProvider(widget.eventoId)),
              ),
            ),
          ],
          data: (leads) {
            final filtrados = _filtrarLeads(
              leads,
              canViewAllLeads: canViewAllLeads,
              puedeVerContacto: puedeVerContacto,
              perfilId: perfilId,
            );

            if (leads.isEmpty) {
              return [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateView(
                    icon: Icons.person_off_outlined,
                    message: 'Aún no hay leads capturados en este evento.',
                    onRefresh: _actualizarLeads,
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
                    message: 'No hay leads con estos filtros.',
                    onRefresh: _actualizarLeads,
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
                  itemBuilder: (context, index) => _LeadTile(
                    eventoId: widget.eventoId,
                    desdeEvento: widget.desdeEvento,
                    lead: filtrados[index],
                    index: index,
                    puedeVerContacto: puedeVerContacto,
                  ),
                ),
              ),
            ];
          },
        ),
      ],
    );
  }
}

class _LeadTile extends StatelessWidget {
  const _LeadTile({
    required this.eventoId,
    required this.lead,
    required this.index,
    required this.puedeVerContacto,
    this.desdeEvento,
  });

  final String eventoId;
  final String? desdeEvento;
  final Lead lead;
  final int index;
  final bool puedeVerContacto;

  @override
  Widget build(BuildContext context) {
    final vendedor = lead.vendedorNombre;
    final pendiente = lead.pendienteDeSincronizar;
    final subtitulo = [
      lead.empresa,
      puedeVerContacto ? lead.email : enmascararEmail(lead.email),
    ].where((s) => s != null && s.isNotEmpty).join(' · ');

    return Pressable(
      onTap: () => context.push(
        RoutePaths.detalleLead(eventoId, lead.id, desdeEvento: desdeEvento),
      ),
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
            AvatarLead(lead: lead, size: 44, index: index),
            const SizedBox(width: 13),
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
                  if (subtitulo.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (vendedor != null && vendedor.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      vendedor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                  if (pendiente) ...[
                    const SizedBox(height: 6),
                    const StatusChip(
                      label: 'Pendiente de sincronizar',
                      variant: StatusChipVariant.warning,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Symbols.chevron_right_rounded,
              color: AppColors.chevronMuted,
            ),
          ],
        ),
      ),
    );
  }
}

String? _sinVacios(String? valor) {
  final texto = valor?.trim() ?? '';
  return texto.isEmpty ? null : texto;
}

InputDecoration _decoracionProtegida() {
  return twReadOnlyDecoration(
    hintText: 'Contacto protegido',
    suffixIcon: const Icon(
      Symbols.lock_rounded,
      size: 18,
      color: AppColors.textTertiary,
    ),
  );
}

class DetalleLeadScreen extends ConsumerStatefulWidget {
  const DetalleLeadScreen({
    super.key,
    required this.eventoId,
    required this.leadId,
    this.desdeEvento,
  });

  final String eventoId;
  final String leadId;
  final String? desdeEvento;

  @override
  ConsumerState<DetalleLeadScreen> createState() => _DetalleLeadScreenState();
}

class _DetalleLeadScreenState extends ConsumerState<DetalleLeadScreen> {
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
  bool _cargado = false;
  bool _guardando = false;

  /// Lo que hay guardado hoy en `fotos_urls`: una URL pública, o un marcador
  /// `local_foto://` si se capturó sin conexión y aún no se sube.
  List<String> _fotos = const [];

  /// Foto nueva ya comprimida y todavía sin subir. Tiene prioridad sobre
  /// [_fotos] al pintar y al guardar.
  Uint8List? _fotoNueva;

  String _nombre0 = '';
  String _empresa0 = '';
  String _cargo0 = '';
  String _telefono0 = '';
  String _email0 = '';
  String _descripcion0 = '';
  List<String> _fotos0 = const [];

  /// Contacto tal como está guardado. Quien no puede verlo edita el formulario
  /// con la máscara a la vista, así que al guardar se reenvía este valor y no
  /// el texto del campo.
  String? _emailGuardado;
  String? _telefonoGuardado;

  @override
  void dispose() {
    _nombreController.dispose();
    _empresaController.dispose();
    _cargoController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  void _precargar(Lead lead, {required bool puedeVerContacto}) {
    if (_cargado) return;
    _cargado = true;
    _emailGuardado = _sinVacios(lead.email);
    _telefonoGuardado = _sinVacios(lead.telefono);
    final paisDetectado = detectarPaisTelefono(_telefonoGuardado);
    if (paisDetectado != null) {
      _paisTelefono = paisDetectado;
      _telefonoTienePaisExplicito = true;
    }
    _nombreController.text = lead.nombreCompleto;
    _empresaController.text = lead.empresa ?? '';
    _cargoController.text = lead.cargo ?? '';
    _telefonoController.text = puedeVerContacto
        ? formatearTelefonoNacional(lead.telefono ?? '', _paisTelefono)
        : enmascararTelefono(lead.telefono);
    _emailController.text = puedeVerContacto
        ? (lead.email ?? '')
        : enmascararEmail(lead.email);
    _descripcionController.text = lead.descripcion ?? '';
    _fotos = lead.fotosUrls;
    _nombre0 = _nombreController.text;
    _empresa0 = _empresaController.text;
    _cargo0 = _cargoController.text;
    _telefono0 = _telefonoController.text;
    _email0 = _emailController.text;
    _descripcion0 = _descripcionController.text;
    _fotos0 = List<String>.from(_fotos);
  }

  void _inicializarPaisTelefonoEvento(
    String? paisEvento, {
    required bool puedeVerContacto,
  }) {
    if (_paisTelefonoEventoInicializado) return;
    _paisTelefonoEvento = paisTelefonoPorPaisEvento(paisEvento);
    _paisTelefonoEventoInicializado = true;
    if (_telefonoTienePaisExplicito) return;
    _paisTelefono = _paisTelefonoEvento;
    if (_cargado && puedeVerContacto) {
      _telefonoController.text = formatearTelefonoNacional(
        _telefonoGuardado ?? _telefonoController.text,
        _paisTelefono,
      );
      _telefono0 = _telefonoController.text;
    }
  }

  bool get _hayCambios {
    if (!_cargado) return false;
    return _nombreController.text != _nombre0 ||
        _empresaController.text != _empresa0 ||
        _cargoController.text != _cargo0 ||
        _telefonoController.text != _telefono0 ||
        _emailController.text != _email0 ||
        _descripcionController.text != _descripcion0 ||
        _fotoNueva != null ||
        !const ListEquality<String>().equals(_fotos, _fotos0);
  }

  String? get _fotoGuardada => _fotos.firstWhereOrNull((u) => !esFotoLocal(u));

  /// Marcador de la foto que todavía vive en disco, si la hay.
  String? get _marcadorPendiente => _fotos.firstWhereOrNull(esFotoLocal);

  Future<void> _elegirFoto() async {
    final bytes = await elegirImagenComprimida(
      context,
      recorteProporcion: kProporcionFotoLead,
    );
    if (bytes == null || !mounted) return;
    setState(() => _fotoNueva = bytes);
  }

  void _quitarFoto() {
    setState(() {
      _fotoNueva = null;
      _fotos = const [];
    });
  }

  /// Devuelve lo que debe quedar en `fotos_urls`. Si no se eligió una foto
  /// nueva se conserva lo que ya había: un marcador `local_foto://` que siga
  /// sin subir lo resuelve el repositorio antes de tocar Supabase.
  Future<List<String>> _resolverFotos({required bool isOnline}) async {
    final nueva = _fotoNueva;
    if (nueva == null) return _fotos;

    final store = ref.read(pendingPhotoStoreProvider);
    if (store.disponible) return [await store.guardar(nueva)];
    return const [];
  }

  /// Borra del disco las fotos pendientes que la edición dejó fuera, para no
  /// acumular archivos que ya nadie referencia.
  Future<void> _borrarFotosLocalesHuerfanas(List<String> finales) async {
    final store = ref.read(pendingPhotoStoreProvider);
    for (final marcador in _fotos.where(esFotoLocal)) {
      if (!finales.contains(marcador)) await store.borrar(marcador);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    final cache = ref.read(offlineReadCacheProvider);

    String? valorOpcional(TextEditingController controller) =>
        _sinVacios(controller.text);

    final puedeVerContacto = ref.read(canViewContactDataProvider);
    final email = puedeVerContacto
        ? valorOpcional(_emailController) == null
              ? null
              : formatearEmail(_emailController.text)
        : _emailGuardado;
    final telefono = puedeVerContacto
        ? valorOpcional(_telefonoController) == null
              ? null
              : telefonoInternacional(_telefonoController.text, _paisTelefono)
        : _telefonoGuardado;
    final isOnline = ref.read(isOnlineProvider);
    var fotosPreparadas = const <String>[];
    Map<String, dynamic>? cambiosPreparados;

    try {
      // Evita que una consulta iniciada antes de guardar termine después y
      // vuelva a escribir la versión anterior sobre la caché de la lista.
      await cache.esperarRevalidaciones();
      final fotoDescartada =
          _fotoNueva != null &&
          !isOnline &&
          !ref.read(pendingPhotoStoreProvider).disponible;
      final fotos = await _resolverFotos(isOnline: isOnline);
      fotosPreparadas = fotos;

      final cambios = <String, dynamic>{
        'nombre_completo': _nombreController.text.trim(),
        'empresa': valorOpcional(_empresaController),
        'cargo': valorOpcional(_cargoController),
        'telefono': telefono,
        'email': email?.toLowerCase(),
        'descripcion': valorOpcional(_descripcionController),
        if (_fotoNueva != null &&
            ref.read(pendingPhotoStoreProvider).disponible)
          'fotos_urls': fotos,
        if (_fotoNueva == null && _fotos.isEmpty)
          'fotos_urls': const <String>[],
      };
      cambiosPreparados = cambios;

      // Un lead que solo existe en la cola todavía no tiene fila en el
      // servidor: su edición se fusiona en el insert pendiente (lo resuelve
      // `enqueueUpdate`) en vez de intentar un UPDATE que fallaría.
      LeadWriteResult? result;
      var fotoPendienteDeSync = false;
      if (isOnline && !esIdSoloLocal(widget.leadId)) {
        try {
          result = await ref
              .read(leadsRepositoryProvider)
              .actualizar(widget.leadId, cambios);
        } on LeadPhotoPendingException catch (error) {
          result = error.result;
          await ref
              .read(syncQueueServiceProvider.notifier)
              .enqueueUpdate(
                table: SupabaseTables.leads,
                entityId: widget.leadId,
                changes: {'fotos_urls': error.fotosPendientes},
              );
          fotoPendienteDeSync = true;
        }
      } else {
        await ref
            .read(syncQueueServiceProvider.notifier)
            .enqueueUpdate(
              table: SupabaseTables.leads,
              entityId: widget.leadId,
              changes: cambios,
            );
      }
      if (result?.esDuplicado == true) {
        final store = ref.read(pendingPhotoStoreProvider);
        for (final foto in fotos.where(esFotoLocal)) {
          if (!_fotos.contains(foto)) await store.borrar(foto);
        }
        if (mounted) {
          await ofrecerComentarLeadDuplicado(
            context,
            ref,
            eventoId: widget.eventoId,
            leadId: result!.leadId,
            mensajeDuplicado: result.mensajeDuplicado,
            desdeEvento: widget.desdeEvento,
          );
        }
        return;
      }

      if (result?.guardado == true &&
          _fotoNueva != null &&
          !ref.read(pendingPhotoStoreProvider).disponible &&
          isOnline) {
        try {
          await ref
              .read(leadsRepositoryProvider)
              .adjuntarFotoBytes(result!.leadId, _fotoNueva!);
        } catch (_) {
          if (mounted) {
            showAppSnackBar(
              context,
              'Cambios guardados; foto pendiente, reintenta',
              isError: true,
            );
          }
          return;
        }
      }
      final cambioFoto =
          _fotoNueva != null ||
          !const ListEquality<String>().equals(_fotos, _fotos0);
      await _borrarFotosLocalesHuerfanas(fotos);
      if (isOnline &&
          result?.guardado == true &&
          !fotoPendienteDeSync &&
          cambioFoto) {
        await ref.read(storageCleanupServiceProvider).drenar();
      }
      final cambiosCache = Map<String, dynamic>.from(cambios);
      // Al subir una foto, el repositorio reemplaza el marcador local por la
      // URL definitiva. Esa URL la incorpora la revalidación; el resto de los
      // campos sí puede publicarse inmediatamente.
      if (isOnline && _fotoNueva != null) {
        cambiosCache.remove('fotos_urls');
      }
      final perfil = await ref.read(currentPerfilProvider.future);
      await publicarCambioEnLecturaCacheada(
        ref,
        tabla: leadsCacheTabla(perfil?.canViewAllLeads ?? false),
        eventoId: widget.eventoId,
        id: widget.leadId,
        cambios: cambiosCache,
        invalidar: () =>
            ref.invalidate(leadsPorEventoProvider(widget.eventoId)),
      );
      if (mounted) {
        showAppSnackBar(
          context,
          fotoPendienteDeSync
              ? 'Cambios guardados. La foto se sincronizará automáticamente.'
              : fotoDescartada
              ? 'Cambios guardados, pero sin la foto: se necesita conexión '
                    'para adjuntarla.'
              : 'Cambios guardados.',
          isError: fotoDescartada,
        );
        volverALista(
          context,
          RoutePaths.verLeads(widget.eventoId, desdeEvento: widget.desdeEvento),
        );
      }
    } catch (e) {
      if (isOnline &&
          cambiosPreparados != null &&
          !esIdSoloLocal(widget.leadId) &&
          isNetworkTransportError(e)) {
        try {
          await ref
              .read(syncQueueServiceProvider.notifier)
              .enqueueUpdate(
                table: SupabaseTables.leads,
                entityId: widget.leadId,
                changes: cambiosPreparados,
              );
          final perfil = await ref.read(currentPerfilProvider.future);
          await publicarCambioEnLecturaCacheada(
            ref,
            tabla: leadsCacheTabla(perfil?.canViewAllLeads ?? false),
            eventoId: widget.eventoId,
            id: widget.leadId,
            cambios: cambiosPreparados,
            invalidar: () =>
                ref.invalidate(leadsPorEventoProvider(widget.eventoId)),
          );
          if (mounted) {
            final fotoNoPersistible =
                _fotoNueva != null &&
                !ref.read(pendingPhotoStoreProvider).disponible;
            showAppSnackBar(
              context,
              fotoNoPersistible
                  ? 'Sin conexión real. Los cambios quedaron guardados '
                        'localmente, pero la foto requiere conexión.'
                  : 'Sin conexión real. Los cambios quedaron guardados '
                        'localmente.',
              isError: fotoNoPersistible,
            );
            volverALista(
              context,
              RoutePaths.verLeads(
                widget.eventoId,
                desdeEvento: widget.desdeEvento,
              ),
            );
          }
          return;
        } catch (_) {
          // Conserva el error de transporte original y limpia la foto nueva.
        }
      }
      final store = ref.read(pendingPhotoStoreProvider);
      for (final foto in fotosPreparadas.where(esFotoLocal)) {
        if (!_fotos.contains(foto)) await store.borrar(foto);
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

  Future<void> _eliminar() async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminar lead',
      message: '¿Eliminar este lead de forma permanente?',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!ok) return;

    try {
      await ref.read(leadsRepositoryProvider).eliminar(widget.leadId);
      // Las fotos del lead ya no tienen fila que las referencie.
      await ref.read(storageCleanupServiceProvider).drenar();
      ref.invalidate(leadsPorEventoProvider(widget.eventoId));
      if (mounted) {
        volverALista(
          context,
          RoutePaths.verLeads(widget.eventoId, desdeEvento: widget.desdeEvento),
        );
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudo eliminar el lead.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Se lee de la lista (que ya trae caché offline y los cambios encolados)
    // en vez de pedir el lead al servidor: así el detalle se abre sin
    // conexión y también sirve para leads que aún no se han sincronizado.
    final leadsAsync = ref.watch(leadsPorEventoProvider(widget.eventoId));
    final esAdmin = ref.watch(isAdminProvider);
    final perfilId = ref.watch(currentPerfilProvider).valueOrNull?.id;
    final puedeEditarCualquiera = ref.watch(canEditAnyLeadProvider);
    final puedeVerContacto = ref.watch(canViewContactDataProvider);
    final eventoCaptura = ref
        .watch(eventoLeadByIdProvider(widget.eventoId))
        .valueOrNull;
    if (eventoCaptura != null) {
      _inicializarPaisTelefonoEvento(
        eventoCaptura.pais,
        puedeVerContacto: puedeVerContacto,
      );
    }
    final esPendiente = esIdSoloLocal(widget.leadId);

    // El lead se resuelve antes del scaffold porque el título y el modo del
    // formulario dependen de quién lo capturó.
    final leadActual = leadsAsync.valueOrNull?.firstWhereOrNull(
      (l) => l.id == widget.leadId,
    );
    final esPropio =
        leadActual != null &&
        perfilId != null &&
        leadActual.perfilId == perfilId;
    final puedeEditar = puedeEditarCualquiera || esPropio;

    return AppScaffold(
      title: puedeEditar ? 'Editar lead' : 'Detalle del lead',
      onWillPop: () => handleFormExit(
        context: context,
        isCreate: false,
        isDirty: puedeEditar && _hayCambios,
        save: _guardar,
      ),
      actions: [
        // Un insert encolado no existe en el servidor: borrarlo desde acá lo
        // dejaría en la cola y reaparecería al sincronizar.
        if (esAdmin && !esPendiente)
          NexusHeaderAction(
            icon: Symbols.delete_outline_rounded,
            tooltip: 'Eliminar lead',
            danger: true,
            onTap: _guardando ? null : _eliminar,
          ),
      ],
      bottomBar: puedeEditar && leadActual != null
          ? FormActionBar(
              label: 'Guardar cambios',
              loading: _guardando,
              onPressed: _guardando ? null : _guardar,
            )
          : null,
      body: leadsAsync.when(
        loading: () => const LoadingView(),
        error: (_, _) => ErrorView(
          message: 'No se pudo cargar el lead.',
          onRetry: () =>
              ref.invalidate(leadsPorEventoProvider(widget.eventoId)),
        ),
        data: (leads) {
          final lead = leads.firstWhereOrNull((l) => l.id == widget.leadId);
          if (lead == null) {
            return const EmptyStateView(
              icon: Symbols.person_off_rounded,
              message: 'No se encontró este lead.',
            );
          }
          _precargar(lead, puedeVerContacto: puedeVerContacto);
          final editable = puedeEditar && !_guardando;

          // Una foto capturada sin conexión vive en disco, no en Storage: se
          // lee por provider para no golpear el archivo en cada rebuild.
          final marcadorPendiente = _marcadorPendiente;
          final bytesPendientes = marcadorPendiente == null
              ? null
              : ref
                    .watch(fotoPendienteBytesProvider(marcadorPendiente))
                    .valueOrNull;
          final fotoGuardada = _fotoGuardada;
          final urlFotoGuardada = fotoGuardada == null
              ? null
              : fotoGuardada.startsWith('leads/')
              ? ref.watch(fotoLeadUrlProvider(fotoGuardada)).valueOrNull
              : fotoGuardada;

          return SingleChildScrollView(
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
                        nombreEnabled: editable,
                        nombreValidator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                        leading: FotoLeadAvatar(
                          bytes: _fotoNueva ?? bytesPendientes,
                          urlExistente: urlFotoGuardada,
                          enabled: editable,
                          onElegir: _elegirFoto,
                          onQuitar:
                              (!puedeEditar ||
                                  (_fotoNueva == null && _fotos.isEmpty))
                              ? null
                              : _quitarFoto,
                        ),
                      );
                    },
                  ),
                  if (_fotoNueva == null && marcadorPendiente != null) ...[
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: StatusChip(
                        label: 'Foto pendiente de subir',
                        variant: StatusChipVariant.warning,
                      ),
                    ),
                  ],
                  if ((lead.vendedorNombre ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'Capturado por ${lead.vendedorNombre}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: FormSection.gap),
                  FormSection(
                    icon: Symbols.business_center_rounded,
                    title: 'Empresa',
                    children: [
                      FormLabeledField(
                        label: 'Empresa',
                        child: TextFormField(
                          controller: _empresaController,
                          enabled: editable,
                          decoration: const InputDecoration(
                            hintText: 'Ej. Transworld',
                          ),
                        ),
                      ),
                      FormLabeledField(
                        label: 'Cargo',
                        opcional: true,
                        child: TextFormField(
                          controller: _cargoController,
                          enabled: editable,
                          decoration: const InputDecoration(
                            hintText: 'Ej. Gerente comercial',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FormSection.gap),
                  FormSection(
                    icon: Symbols.contact_phone_rounded,
                    title: 'Contacto',
                    subtitle: puedeVerContacto
                        ? null
                        : 'Solo visible para administradores y organizadores.',
                    children: [
                      FormLabeledField(
                        label: 'Teléfono',
                        opcional: puedeVerContacto,
                        child: puedeVerContacto
                            ? CampoTelefonoInternacional(
                                controller: _telefonoController,
                                pais: _paisTelefono,
                                onPaisChanged: (pais) =>
                                    setState(() => _paisTelefono = pais),
                                enabled: editable,
                                requerido: false,
                                labelText: null,
                              )
                            : TextFormField(
                                controller: _telefonoController,
                                enabled: editable,
                                readOnly: true,
                                keyboardType: TextInputType.phone,
                                decoration: _decoracionProtegida(),
                              ),
                      ),
                      FormLabeledField(
                        label: 'Correo',
                        child: TextFormField(
                          controller: _emailController,
                          enabled: editable,
                          readOnly: !puedeVerContacto,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: false,
                          inputFormatters: const [LowerCaseTextFormatter()],
                          decoration: puedeVerContacto
                              ? const InputDecoration(
                                  hintText: 'correo@empresa.com',
                                )
                              : _decoracionProtegida(),
                          validator: puedeVerContacto
                              ? validarEmailRegistro
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FormSection.gap),
                  FormSection(
                    icon: Symbols.sticky_note_2_rounded,
                    title: 'Notas',
                    children: [
                      FormLabeledField(
                        label: 'Descripción',
                        opcional: true,
                        child: TextFormField(
                          controller: _descripcionController,
                          enabled: editable,
                          minLines: 3,
                          maxLines: 8,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Qué le interesa, próximos pasos…',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FormSection.gap),
                  Opacity(
                    opacity: esPendiente ? 0.5 : 1,
                    child: TwActionTile(
                      icon: Symbols.chat_rounded,
                      title: 'Comentarios',
                      subtitle: esPendiente
                          ? 'Disponible cuando el lead se sincronice'
                          : 'Seguimiento del equipo sobre este lead',
                      onTap: esPendiente
                          ? () {}
                          : () => irAComentariosLead(
                              context,
                              ref,
                              eventoId: widget.eventoId,
                              leadId: widget.leadId,
                              desdeEvento: widget.desdeEvento,
                            ),
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
