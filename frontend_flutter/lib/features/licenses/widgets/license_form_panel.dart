import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../customers/models/customer.dart';
import '../models/project.dart';

class LicenseFormValues {
  final String customerId;
  final String tipo;
  final int diasValidez;
  final String? projectId;
  final String? projectCode;
  final String? projectName;
  final String? notas;
  final bool autoActivate;
  final int? maxDevices;

  const LicenseFormValues({
    required this.customerId,
    required this.tipo,
    required this.diasValidez,
    this.projectId,
    this.projectCode,
    this.projectName,
    this.notas,
    required this.autoActivate,
    this.maxDevices,
  });
}

class LicenseFormPanel extends StatefulWidget {
  final List<Customer> customers;
  final List<Project> projects;
  final bool loading;
  final bool projectsLoading;
  final Future<void> Function(LicenseFormValues values) onSubmit;
  final VoidCallback onClose;
  final LicenseFormValues? initialValues;
  final String title;
  final String submitLabel;

  const LicenseFormPanel({
    super.key,
    required this.customers,
    required this.projects,
    required this.loading,
    this.projectsLoading = false,
    required this.onSubmit,
    required this.onClose,
    this.initialValues,
    this.title = 'Crear licencia',
    this.submitLabel = 'Crear licencia',
  });

  @override
  State<LicenseFormPanel> createState() => _LicenseFormPanelState();
}

class _LicenseFormPanelState extends State<LicenseFormPanel> {
  final _formKey = GlobalKey<FormState>();
  final _diasCtrl = TextEditingController(text: '30');
  final _notasCtrl = TextEditingController();

  String? _selectedCustomerId;
  String? _selectedProjectId;
  String _tipo = 'FULL';
  bool _autoActivate = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValues;
    if (initial != null) {
      _selectedCustomerId = initial.customerId;
      _selectedProjectId = initial.projectId;
      _tipo = initial.tipo;
      _diasCtrl.text = initial.diasValidez.toString();
      _notasCtrl.text = initial.notas ?? '';
      _autoActivate = initial.autoActivate;
    }
  }

  @override
  void dispose() {
    _diasCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Project? get _selectedProject {
    if (_selectedProjectId == null) return null;
    try {
      return widget.projects.firstWhere((p) => p.id == _selectedProjectId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCustomerId == null || _selectedCustomerId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un cliente')),
      );
      return;
    }

    if (_selectedProjectId == null || _selectedProjectId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un proyecto')),
      );
      return;
    }

    final project = _selectedProject;
    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El proyecto seleccionado no es válido')),
      );
      return;
    }

    final dias = int.tryParse(_diasCtrl.text.trim()) ?? 0;
    if (dias <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Los días de validez deben ser mayores a 0')),
      );
      return;
    }

    await widget.onSubmit(
      LicenseFormValues(
        customerId: _selectedCustomerId!,
        projectId: project.id,
        projectCode: project.code,
        projectName: project.name,
        tipo: _tipo,
        diasValidez: dias,
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
        autoActivate: _autoActivate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.loading || widget.projectsLoading;

    return Container(
      width: AppSpacing.detailPanelWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: AppSpacing.appBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: widget.onClose,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          // Form body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Cliente selector
                    const Text(
                      'Cliente',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCustomerId,
                      isExpanded: true,
                      items: widget.customers
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(
                                '${c.nombreNegocio} (${c.id.substring(0, 8)})',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged:
                          isDisabled ? null : (v) => setState(() => _selectedCustomerId = v),
                      decoration: const InputDecoration(
                        hintText: 'Selecciona cliente',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Proyecto selector
                    const Text(
                      'Proyecto',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedProjectId,
                      isExpanded: true,
                      items: widget.projects
                          .where((p) => p.isActive)
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                p.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: isDisabled
                          ? null
                          : (v) => setState(() => _selectedProjectId = v),
                      decoration: const InputDecoration(
                        hintText: 'Selecciona proyecto',
                      ),
                    ),
                    if (widget.projectsLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Cargando proyectos...',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Mostrar código del proyecto seleccionado (solo lectura)
                    if (_selectedProject != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Código: ${_selectedProject!.code}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),

                    // Tipo selector
                    const Text(
                      'Tipo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: _tipo,
                      items: () {
                        const baseItems = [
                          DropdownMenuItem(value: 'FULL', child: Text('FULL')),
                          DropdownMenuItem(value: 'DEMO', child: Text('DEMO')),
                        ];
                        // Si _tipo no está en la lista base, lo agregamos para evitar el error de aserción
                        if (_tipo != 'FULL' && _tipo != 'DEMO') {
                          return [
                            ...baseItems,
                            DropdownMenuItem(
                              value: _tipo,
                              child: Text(_tipo),
                            ),
                          ];
                        }
                        return baseItems;
                      }(),
                      onChanged:
                          isDisabled ? null : (v) => setState(() => _tipo = v ?? 'FULL'),
                      decoration: const InputDecoration(),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Días de validez
                    AppTextField(
                      label: 'Días de validez',
                      hint: '30',
                      controller: _diasCtrl,
                      keyboardType: TextInputType.number,
                      enabled: !isDisabled,
                      validator: (v) {
                        final d = int.tryParse((v ?? '').trim());
                        if (d == null || d <= 0) {
                          return 'Ingresa un número válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Notas
                    AppTextField(
                      label: 'Notas (opcional)',
                      hint: 'Observaciones de la licencia',
                      controller: _notasCtrl,
                      enabled: !isDisabled,
                      maxLines: 3,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Auto activar
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _autoActivate,
                      onChanged:
                          isDisabled ? null : (v) => setState(() => _autoActivate = v ?? true),
                      title: const Text(
                        'Activar automáticamente',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Botón submit
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        label: widget.submitLabel,
                        loading: widget.loading,
                        onPressed: _submit,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
