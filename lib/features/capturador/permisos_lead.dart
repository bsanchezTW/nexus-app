import '../../data/models/evento_lead.dart';
import '../../data/models/lead.dart';
import '../../data/models/perfil.dart';

/// Gracia tras el último día de la actividad: cubre capturas sin red que
/// suben tarde y correcciones del día siguiente.
const Duration graciaEdicionLeadsPropios = Duration(hours: 24);

/// Momento en que el capturador deja de ver completos y de tocar sus leads:
/// fin del último día de la actividad (hora del teléfono) más
/// [graciaEdicionLeadsPropios].
DateTime cierreLeadsPropios(EventoLead actividad) {
  final fin = actividad.fechaFin;
  final finDelUltimoDia = DateTime(fin.year, fin.month, fin.day + 1);
  return finDelUltimoDia.add(graciaEdicionLeadsPropios);
}

/// Qué puede hacer el perfil en sesión con un lead concreto.
class PermisosLead {
  const PermisosLead({
    required this.verContacto,
    required this.editar,
    required this.eliminar,
  });

  static const ninguno = PermisosLead(
    verContacto: false,
    editar: false,
    eliminar: false,
  );

  /// Correo y teléfono sin máscara.
  final bool verContacto;
  final bool editar;
  final bool eliminar;
}

/// Regla única de acceso a un lead, aplicada en la app.
///
/// - Admin y organizador: ven el contacto y editan cualquier lead; borrar
///   sigue siendo solo del admin.
/// - El resto, con **sus** leads y mientras la actividad no cierre (ver
///   [cierreLeadsPropios]): ve el contacto completo, edita y borra.
/// - Leads ajenos, o propios tras el cierre: contacto enmascarado y solo
///   lectura.
///
/// [actividad] nula (todavía no resuelta) se trata como cerrada: es preferible
/// mostrar un instante de menos que exponer un contacto ajeno.
PermisosLead permisosLead({
  required Perfil? perfil,
  required Lead lead,
  required EventoLead? actividad,
  DateTime? ahora,
}) {
  if (perfil == null) return PermisosLead.ninguno;
  if (perfil.canEditAnyLead) {
    return PermisosLead(
      verContacto: perfil.canViewContactData,
      editar: true,
      eliminar: perfil.isAdmin,
    );
  }
  final propio = lead.perfilId == perfil.id;
  final abierta =
      actividad != null &&
      (ahora ?? DateTime.now()).isBefore(cierreLeadsPropios(actividad));
  if (!propio || !abierta) return PermisosLead.ninguno;
  return const PermisosLead(verContacto: true, editar: true, eliminar: true);
}
