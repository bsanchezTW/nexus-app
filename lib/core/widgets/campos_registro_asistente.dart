import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../utils/registro_asistente.dart';
import 'app_modals.dart';
import 'form_sections.dart';

/// Aplica [formatear] al texto cuando el campo pierde el foco.
class FormatoAlSalir extends StatelessWidget {
  const FormatoAlSalir({
    super.key,
    required this.controller,
    required this.formatear,
    required this.child,
  });

  final TextEditingController controller;
  final String Function(String value) formatear;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) return;
        final siguiente = formatear(controller.text);
        if (siguiente != controller.text) {
          controller.text = siguiente;
        }
      },
      child: child,
    );
  }
}

void aplicarFormatosRegistroAsistente({
  required TextEditingController nombre,
  required TextEditingController email,
  required TextEditingController empresa,
  required TextEditingController cargo,
  required TextEditingController telefono,
  required PaisTelefono pais,
  TextEditingController? rut,
  TextEditingController? patente,
}) {
  nombre.text = formatearNombreCompleto(nombre.text);
  email.text = formatearEmail(email.text);
  empresa.text = formatearEmpresa(empresa.text);
  cargo.text = formatearCargo(cargo.text);
  telefono.text = formatearTelefonoNacional(telefono.text, pais);
  if (rut != null) {
    rut.text = pais.iso == 'CL' ? formatearRut(rut.text) : rut.text.trim();
  }
  if (patente != null) patente.text = formatearPatente(patente.text);
}

/// Campos compartidos del alta de un asistente (registro interno y público).
class CamposRegistroAsistente extends StatelessWidget {
  const CamposRegistroAsistente({
    super.key,
    required this.nombreController,
    required this.emailController,
    required this.empresaController,
    required this.cargoController,
    required this.telefonoController,
    required this.pais,
    required this.onPaisChanged,
    this.enabled = true,
    this.mostrarCertificacion = false,
    this.rutController,
    this.patenteController,
  });

  final TextEditingController nombreController;
  final TextEditingController emailController;
  final TextEditingController empresaController;
  final TextEditingController cargoController;
  final TextEditingController telefonoController;
  final PaisTelefono pais;
  final ValueChanged<PaisTelefono> onPaisChanged;
  final bool enabled;
  final bool mostrarCertificacion;
  final TextEditingController? rutController;
  final TextEditingController? patenteController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormSection(
          icon: Symbols.person_rounded,
          title: 'Datos del asistente',
          subtitle: 'El código QR llega a este correo y teléfono.',
          children: [
            FormLabeledField(
              label: 'Nombre completo',
              child: FormatoAlSalir(
                controller: nombreController,
                formatear: formatearNombreCompleto,
                child: TextFormField(
                  controller: nombreController,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Ej. Ana Rojas'),
                  validator: validarNombreCompleto,
                ),
              ),
            ),
            FormLabeledField(
              label: 'Correo',
              child: FormatoAlSalir(
                controller: emailController,
                formatear: formatearEmail,
                child: TextFormField(
                  controller: emailController,
                  enabled: enabled,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: const [LowerCaseTextFormatter()],
                  decoration: const InputDecoration(
                    hintText: 'correo@empresa.com',
                  ),
                  validator: validarEmailRegistro,
                ),
              ),
            ),
            FormLabeledField(
              label: 'Teléfono',
              child: CampoTelefonoInternacional(
                controller: telefonoController,
                pais: pais,
                onPaisChanged: onPaisChanged,
                enabled: enabled,
                labelText: null,
              ),
            ),
          ],
        ),
        const SizedBox(height: FormSection.gap),
        FormSection(
          icon: Symbols.business_center_rounded,
          title: 'Empresa',
          children: [
            FormLabeledField(
              label: 'Empresa',
              child: FormatoAlSalir(
                controller: empresaController,
                formatear: formatearEmpresa,
                child: TextFormField(
                  controller: empresaController,
                  enabled: enabled,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Ej. Transworld'),
                  validator: validarEmpresa,
                ),
              ),
            ),
            FormLabeledField(
              label: 'Cargo',
              child: FormatoAlSalir(
                controller: cargoController,
                formatear: formatearCargo,
                child: TextFormField(
                  controller: cargoController,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Ej. Jefe de proyectos',
                  ),
                  validator: validarCargo,
                ),
              ),
            ),
          ],
        ),
        if (mostrarCertificacion) ...[
          const SizedBox(height: FormSection.gap),
          FormSection(
            icon: Symbols.workspace_premium_rounded,
            title: 'Certificación',
            subtitle: 'Este evento entrega certificado.',
            children: [
              FormFieldRow(
                minWidth: 280,
                left: FormLabeledField(
                  label: pais.iso == 'CL' ? 'RUT' : 'RUT / RUC',
                  child: FormatoAlSalir(
                    controller: rutController!,
                    formatear: (v) =>
                        pais.iso == 'CL' ? formatearRut(v) : v.trim(),
                    child: TextFormField(
                      controller: rutController,
                      enabled: enabled,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: '12.345.678-9',
                      ),
                      validator: (v) =>
                          validarRut(v, esChile: pais.iso == 'CL'),
                    ),
                  ),
                ),
                right: FormLabeledField(
                  label: 'Patente',
                  child: FormatoAlSalir(
                    controller: patenteController!,
                    formatear: formatearPatente,
                    child: TextFormField(
                      controller: patenteController,
                      enabled: enabled,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(hintText: 'ABCD12'),
                      validator: validarPatente,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Impide escribir más dígitos nacionales que [PaisTelefono.maxDigitos].
/// Cuenta solo dígitos (espacios y `+` no ocupan cupo) y, si se pega el
/// número con código de país, recorta el tramo nacional.
class _LimiteDigitosTelefonoFormatter extends TextInputFormatter {
  const _LimiteDigitosTelefonoFormatter(this.pais);

  final PaisTelefono pais;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final nacionales = extraerDigitosNacionales(newValue.text, pais);
    final escritos = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (nacionales.length <= pais.maxDigitos &&
        escritos.length <= pais.maxDigitos) {
      return newValue;
    }
    final recortado = nacionales.length <= pais.maxDigitos
        ? nacionales
        : nacionales.substring(0, pais.maxDigitos);
    return TextEditingValue(
      text: recortado,
      selection: TextSelection.collapsed(offset: recortado.length),
    );
  }
}

class LowerCaseTextFormatter extends TextInputFormatter {
  const LowerCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lower = newValue.text.toLowerCase();
    if (lower == newValue.text) return newValue;
    return newValue.copyWith(text: lower, composing: TextRange.empty);
  }
}

class CampoTelefonoInternacional extends StatelessWidget {
  const CampoTelefonoInternacional({
    super.key,
    required this.controller,
    required this.pais,
    required this.onPaisChanged,
    this.enabled = true,
    this.requerido = true,
    this.labelText = 'Teléfono',
  });

  final TextEditingController controller;
  final PaisTelefono pais;
  final ValueChanged<PaisTelefono> onPaisChanged;
  final bool enabled;
  final bool requerido;
  final String? labelText;

  @override
  Widget build(BuildContext context) {
    return FormatoAlSalir(
      controller: controller,
      formatear: (value) => formatearTelefonoNacional(value, pais),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          _LimiteDigitosTelefonoFormatter(pais),
        ],
        decoration: InputDecoration(
          labelText: labelText,
          hintText: pais.hint,
          prefixIcon: _PrefijoPais(
            pais: pais,
            enabled: enabled,
            onTap: () => _elegirPais(context),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
        ),
        validator: (value) =>
            validarTelefono(value, pais, requerido: requerido),
      ),
    );
  }

  Future<void> _elegirPais(BuildContext context) async {
    if (!enabled) return;
    final elegido = await showAppModalBottomSheet<PaisTelefono>(
      context: context,
      isScrollControlled: true,
      // Sin arrastre: la hoja es una lista larga con buscador y el gesto de
      // scroll cerca del borde superior la cerraba a media búsqueda. Se sale
      // tocando fuera o eligiendo un país.
      enableDrag: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.header),
        ),
      ),
      builder: (ctx) => _SelectorPaisSheet(seleccionado: pais),
    );
    if (elegido == null || elegido.iso == pais.iso) return;
    final nacionales = extraerDigitosNacionales(controller.text, pais);
    controller.text = formatearTelefonoNacional(nacionales, elegido);
    onPaisChanged(elegido);
  }
}

class _PrefijoPais extends StatelessWidget {
  const _PrefijoPais({
    required this.pais,
    required this.enabled,
    required this.onTap,
  });

  final PaisTelefono pais;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pais.bandera, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(
              pais.etiquetaCodigo,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            Icon(
              Symbols.expand_more_rounded,
              size: 18,
              color: enabled ? AppColors.textSecondary : AppColors.placeholder,
            ),
            const SizedBox(width: 4),
            Container(width: 1, height: 22, color: AppColors.border),
          ],
        ),
      ),
    );
  }
}

class _SelectorPaisSheet extends StatefulWidget {
  const _SelectorPaisSheet({required this.seleccionado});

  final PaisTelefono seleccionado;

  @override
  State<_SelectorPaisSheet> createState() => _SelectorPaisSheetState();
}

class _SelectorPaisSheetState extends State<_SelectorPaisSheet> {
  final _busqueda = TextEditingController();

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _busqueda.text.trim().toLowerCase();
    final filtrados = kPaisesTelefono.where((p) {
      if (query.isEmpty) return true;
      return p.nombre.toLowerCase().contains(query) ||
          p.dialCode.contains(query) ||
          p.iso.toLowerCase().contains(query);
    }).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            const Padding(
              // El aire de arriba lo daba el drag handle, ya retirado.
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Código de país',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _busqueda,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar país o código',
                  prefixIcon: Icon(Symbols.search_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: filtrados.length,
                itemBuilder: (context, index) {
                  final pais = filtrados[index];
                  final activo = pais.iso == widget.seleccionado.iso;
                  return ListTile(
                    leading: Text(
                      pais.bandera,
                      style: const TextStyle(fontSize: 22),
                    ),
                    title: Text(pais.nombre),
                    trailing: Text(
                      pais.etiquetaCodigo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    selected: activo,
                    onTap: () => Navigator.pop(context, pais),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
