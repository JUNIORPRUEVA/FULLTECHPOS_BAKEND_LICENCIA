import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../customers/models/customer.dart';

class LicenseFormValues {
  final String customerId;
  final String tipo;
  final int diasValidez;
  final String? projectCode;
  final String? notas;
  final bool autoActivate;

  const LicenseFormValues({
    required this.customerId,
    required this.tipo,
    required this.diasValidez,
    this.projectCode,
    this.notas,
    required this.autoActivate,
  });
}

class LicenseFormPanel extends StatefulWidget {
  final List<Customer> customers;
  final bool loading;
  final Future<void> Function(LicenseFormValues values) onSubmit;
  final VoidCallback onClose;
  final LicenseFormValues? initialValues;
  final String title;
  final String submitLabel;

  const LicenseFormPanel({
    super.key,
    required this.customers,
    required this.loading,
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
  final _projectCodeCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();

  String? _selectedCustomerId;
  String _tipo = 'FULL';
  bool _autoActivate = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValues;
    if (initial != null) {
      _selectedCustomerId = initial.customerId;
      _tipo = initial.tipo;
      _diasCtrl.text = initial.diasValidez.toString();
      _projectCodeCtrl.text = initial.projectCode ?? '';
      _notasCtrl.text = initial.notas ?? '';
      _autoActivate = initial.autoActivate;
    }
  }

  @override
  void dispose() {
    _diasCtrl.dispose();
    _projectCodeCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null || _selectedCustomerId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un cliente')),
      );
      return;
    }

    final dias = int.tryParse(_diasCtrl.text.trim()) ?? 0;
    await widget.onSubmit(
      LicenseFormValues(
        customerId: _selectedCustomerId!,
        tipo: _tipo,
        diasValidez: dias,
        projectCode: _projectCodeCtrl.text.trim().isEmpty
            ? null
            : _projectCodeCtrl.text.trim(),
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
        autoActivate: _autoActivate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.detailPanelWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
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
                      value: _selectedCustomerId,
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
                      onChanged: widget.loading
                          ? null
                          : (v) => setState(() => _selectedCustomerId = v),
                      decoration: const InputDecoration(
                        hintText: 'Selecciona cliente',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
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
                      value: _tipo,
                      items: const [
                        DropdownMenuItem(value: 'FULL', child: Text('FULL')),
                        DropdownMenuItem(value: 'DEMO', child: Text('DEMO')),
                      ],
                      onChanged: widget.loading
                          ? null
                          : (v) => setState(() => _tipo = v ?? 'FULL'),
                      decoration: const InputDecoration(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Días de validez',
                      hint: '30',
                      controller: _diasCtrl,
                      keyboardType: TextInputType.number,
                      enabled: !widget.loading,
                      validator: (v) {
                        final d = int.tryParse((v ?? '').trim());
                        if (d == null || d <= 0) {
                          return 'Ingresa un número válido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Código de proyecto (opcional)',
                      hint: 'FULLPOS',
                      controller: _projectCodeCtrl,
                      enabled: !widget.loading,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      label: 'Notas (opcional)',
                      hint: 'Observaciones de la licencia',
                      controller: _notasCtrl,
                      enabled: !widget.loading,
                      maxLines: 3,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _autoActivate,
                      onChanged: widget.loading
                          ? null
                          : (v) => setState(() => _autoActivate = v ?? true),
                      title: const Text(
                        'Activar automáticamente',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
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
