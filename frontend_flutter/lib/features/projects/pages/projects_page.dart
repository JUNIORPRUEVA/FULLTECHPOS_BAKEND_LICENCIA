 import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../../licenses/models/project.dart';
import '../../licenses/services/projects_service.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  final ProjectsService _service = ProjectsService(
    sessionManager: SessionManager(),
  );

  List<Project> _projects = [];
  Project? _selected;
  bool _loading = true;
  String? _error;
  bool _editing = false;
  bool _saving = false;

  // Controladores de edición
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _codeCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _currencyCtrl;
  late TextEditingController _demoDaysCtrl;
  late TextEditingController _minMonthsCtrl;
  bool _isPaid = true;
  bool _allowDemo = true;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _codeCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _priceCtrl = TextEditingController();
    _currencyCtrl = TextEditingController();
    _demoDaysCtrl = TextEditingController();
    _minMonthsCtrl = TextEditingController();
    _loadProjects();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _currencyCtrl.dispose();
    _demoDaysCtrl.dispose();
    _minMonthsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final projects = await _service.listProjects();
      setState(() {
        _projects = projects;
        _loading = false;
        // Re-seleccionar el mismo proyecto si estaba seleccionado
        if (_selected != null) {
          _selected = projects.cast<Project?>().firstWhere(
            (p) => p!.id == _selected!.id,
            orElse: () => null,
          );
        }
      });
    } on UnauthorizedException {
      setState(() => _loading = false);
      // No hacer nada mas: el callback global de AuthService ya limpio la sesion
      // y el router redirigira al login automaticamente.
      return;
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _selectProject(Project project) {
    setState(() {
      _selected = project;
      _editing = false;
    });
  }

  void _startEditing() {
    if (_selected == null) return;
    _nameCtrl.text = _selected!.name;
    _codeCtrl.text = _selected!.code;
    _descCtrl.text = _selected!.description ?? '';
    _priceCtrl.text = _selected!.monthlyPrice.toStringAsFixed(2);
    _currencyCtrl.text = _selected!.currency;
    _demoDaysCtrl.text = _selected!.demoDays.toString();
    _minMonthsCtrl.text = _selected!.minPurchaseMonths.toString();
    _isPaid = _selected!.isPaidProject;
    _allowDemo = _selected!.allowDemo;
    _isActive = _selected!.isActive;
    setState(() {
      _editing = true;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editing = false;
    });
  }

  Future<void> _saveProject() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selected == null) return;

    setState(() => _saving = true);

    try {
      final updated = await _service.updateProject(
        projectId: _selected!.id,
        name: _nameCtrl.text.trim(),
        code: _codeCtrl.text.trim().toUpperCase(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        monthlyPrice: double.tryParse(_priceCtrl.text) ?? 0,
        currency: _currencyCtrl.text.trim().toUpperCase(),
        demoDays: int.tryParse(_demoDaysCtrl.text) ?? 0,
        minPurchaseMonths: int.tryParse(_minMonthsCtrl.text) ?? 1,
        isPaidProject: _isPaid,
        allowDemo: _allowDemo,
        isActive: _isActive,
      );

      setState(() {
        _selected = updated;
        _editing = false;
        _saving = false;
      });

      // Refrescar lista y mantener selección
      await _loadProjects();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Proyecto actualizado correctamente'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on UnauthorizedException {
      // No hacer nada: el callback global de AuthService ya limpio la sesion
      // y el router redirigira al login automaticamente.
      return;
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatCurrency(double amount, String currency) {
    final format = NumberFormat.currency(
      symbol: currency == 'USD' ? '\$' : currency,
      decimalDigits: 2,
    );
    return format.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Lista de proyectos
        Expanded(
          child: _buildProjectList(),
        ),
        // Panel de detalle/edición
        if (_selected != null)
          Container(
            width: AppSpacing.detailPanelWidth,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(left: BorderSide(color: AppColors.border)),
            ),
            child: _editing ? _buildEditPanel() : _buildDetailPanel(),
          ),
      ],
    );
  }

  Widget _buildProjectList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadProjects,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_projects.isEmpty) {
      return const Center(
        child: Text('No hay proyectos', style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header con título
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Text(
                'Proyectos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${_projects.length} proyectos',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        // Lista
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.sm),
            itemCount: _projects.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (_, index) {
              final project = _projects[index];
              final isSelected = _selected?.id == project.id;
              return _ProjectListTile(
                project: project,
                selected: isSelected,
                onTap: () => _selectProject(project),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDetailPanel() {
    final p = _selected!;
    return Column(
      children: [
        // Header
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Detalle del proyecto',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _selected = null),
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
        // Contenido
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              // Botón editar
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _startEditing,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar proyecto'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _detailField('ID', p.id),
              _detailField('Nombre', p.name),
              _detailField('Código', p.code),
              _detailField('Descripción', p.description ?? '—'),
              _detailField(
                'Precio mensual',
                '${_formatCurrency(p.monthlyPrice, p.currency)} / mes',
              ),
              _detailField('Moneda', p.currency),
              _detailField('Días demo', '${p.demoDays} días'),
              _detailField('Meses mínimos', '${p.minPurchaseMonths} meses'),
              _detailField('Requiere pago', p.isPaidProject ? 'Sí' : 'No'),
              _detailField('Permite demo', p.allowDemo ? 'Sí' : 'No'),
              _detailField('Estado', p.isActive ? 'Activo' : 'Inactivo'),
              if (p.createdAt != null)
                _detailField(
                  'Creado',
                  DateFormat('dd/MM/yyyy HH:mm').format(p.createdAt!),
                ),
              if (p.updatedAt != null)
                _detailField(
                  'Actualizado',
                  DateFormat('dd/MM/yyyy HH:mm').format(p.updatedAt!),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditPanel() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Header
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Editar proyecto',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _cancelEditing,
                  tooltip: 'Cancelar',
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          // Formulario
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _buildTextField(
                  controller: _nameCtrl,
                  label: 'Nombre',
                  required: true,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _codeCtrl,
                  label: 'Código',
                  required: true,
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    return null;
                  },
                  onChanged: (v) {
                    _codeCtrl.value = TextEditingValue(
                      text: v.toUpperCase(),
                      selection: TextSelection.collapsed(
                        offset: v.length,
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _descCtrl,
                  label: 'Descripción',
                  maxLines: 3,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _priceCtrl,
                  label: 'Precio mensual',
                  keyboardType: TextInputType.number,
                  required: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    final price = double.tryParse(v);
                    if (price == null || price < 0) return 'Debe ser >= 0';
                    if (_isPaid && price <= 0) return 'Debe ser > 0 si requiere pago';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _currencyCtrl,
                  label: 'Moneda',
                  required: true,
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _demoDaysCtrl,
                  label: 'Días demo',
                  keyboardType: TextInputType.number,
                  required: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    final days = int.tryParse(v);
                    if (days == null || days < 0) return 'Debe ser >= 0';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildTextField(
                  controller: _minMonthsCtrl,
                  label: 'Meses mínimos',
                  keyboardType: TextInputType.number,
                  required: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Requerido';
                    final months = int.tryParse(v);
                    if (months == null || months < 1) return 'Debe ser >= 1';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                // Switches
                _buildSwitch('Requiere pago', _isPaid, (v) {
                  setState(() => _isPaid = v);
                  // Re-validar precio si cambia
                  _formKey.currentState?.validate();
                }),
                const SizedBox(height: AppSpacing.sm),
                _buildSwitch('Permite demo', _allowDemo, (v) {
                  setState(() => _allowDemo = v);
                }),
                const SizedBox(height: AppSpacing.sm),
                _buildSwitch('Activo', _isActive, (v) {
                  setState(() => _isActive = v);
                }),
                const SizedBox(height: AppSpacing.lg),
                // Botones
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _cancelEditing,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _saving ? null : _saveProject,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Guardar cambios'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _ProjectListTile extends StatelessWidget {
  final Project project;
  final bool selected;
  final VoidCallback onTap;

  const _ProjectListTile({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.surface,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nombre y código
            Row(
              children: [
                Expanded(
                  child: Text(
                    project.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                StatusBadge(
                  label: project.isActive ? 'Activo' : 'Inactivo',
                  type: project.isActive ? StatusType.active : StatusType.inactive,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Código: ${project.code}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            // Precio
            Row(
              children: [
                const Icon(Icons.attach_money, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '${project.currency} ${project.monthlyPrice.toStringAsFixed(2)} / mes',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Demo y mínimo
            Row(
              children: [
                const Icon(Icons.free_breakfast_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Demo: ${project.demoDays} días',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.calendar_month_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Mín: ${project.minPurchaseMonths} meses',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Pago
            Row(
              children: [
                Icon(
                  project.isPaidProject ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 14,
                  color: project.isPaidProject ? AppColors.warning : AppColors.success,
                ),
                const SizedBox(width: 4),
                Text(
                  project.isPaidProject ? 'Pago: Sí' : 'Pago: No',
                  style: TextStyle(
                    fontSize: 12,
                    color: project.isPaidProject ? AppColors.warning : AppColors.success,
                  ),
                ),
                if (project.allowDemo) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.science_outlined, size: 14, color: AppColors.info),
                  const SizedBox(width: 4),
                  const Text(
                    'Demo disponible',
                    style: TextStyle(fontSize: 12, color: AppColors.info),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
