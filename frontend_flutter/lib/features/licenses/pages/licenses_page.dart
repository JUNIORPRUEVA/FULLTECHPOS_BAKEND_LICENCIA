import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/api/api_exception.dart';
import '../../customers/models/customer.dart';
import '../../customers/services/customers_service.dart';
import '../models/license.dart';
import '../models/project.dart';
import '../services/licenses_service.dart';
import '../services/projects_service.dart';
import '../widgets/license_detail_panel.dart';
import '../widgets/license_form_panel.dart';
import '../widgets/license_list_item.dart';

class LicensesPage extends StatefulWidget {
  final String? initialLicenseId;

  const LicensesPage({super.key, this.initialLicenseId});

  @override
  State<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<LicensesPage> {
  late final LicensesService _licensesService;
  late final CustomersService _customersService;
  late final ProjectsService _projectsService;

  late Future<List<License>> _licensesFuture;
  List<Customer> _customers = [];
  List<Project> _projects = [];
  bool _projectsLoading = false;

  final _searchCtrl = TextEditingController();
  String _query = '';
  String _estadoFiltro = 'TODAS';
  License? _selected;

  bool _showCreatePanel = false;
  bool _editingLicense = false;
  bool _creating = false;
  String? _activatingLicenseId;

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1000;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionManager>();
    _licensesService = LicensesService(sessionManager: session);
    _customersService = CustomersService(sessionManager: session);
    _projectsService = ProjectsService(sessionManager: session);
    _licensesFuture = _licensesService.listLicenses().then((licenses) {
      // Si hay un initialLicenseId, seleccionar esa licencia automáticamente
      if (widget.initialLicenseId != null && mounted) {
        final found = licenses.where((l) => l.id == widget.initialLicenseId).toList();
        if (found.isNotEmpty) {
          setState(() => _selected = found.first);
        }
      }
      return licenses;
    });
    _loadCustomers();
    _loadProjects();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await _customersService.listCustomers(limit: 100);
      if (mounted) setState(() => _customers = customers);
    } catch (_) {}
  }

  Future<void> _loadProjects() async {
    setState(() => _projectsLoading = true);
    try {
      final projects = await _projectsService.listProjects();
      if (mounted) {
        setState(() {
          _projects = projects;
          _projectsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _projectsLoading = false);
      debugPrint('Error loading projects: $e');
    }
  }

  void _refresh() {
    setState(() {
      _selected = null;
      _showCreatePanel = false;
      _licensesFuture = _licensesService.listLicenses();
    });
  }

  List<License> _filtered(List<License> all) {
    var out = all;
    if (_estadoFiltro != 'TODAS') {
      out = out.where((l) {
        if (_estadoFiltro == 'DEMO') {
          return (l.licenseType ?? '').toUpperCase() == 'DEMO';
        }
        return (l.status ?? '').toUpperCase() == _estadoFiltro.toUpperCase();
      }).toList();
    }

    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((l) {
        return (l.licenseKey ?? '').toLowerCase().contains(q) ||
            (l.projectName ?? '').toLowerCase().contains(q) ||
            (l.businessId ?? '').toLowerCase().contains(q) ||
            (l.customerId ?? '').toLowerCase().contains(q) ||
            (l.customerName ?? '').toLowerCase().contains(q) ||
            (l.licenseType ?? '').toLowerCase().contains(q);
      }).toList();
    }

    return out;
  }

  Future<void> _createLicense(LicenseFormValues values) async {
    setState(() => _creating = true);
    try {
      final body = <String, dynamic>{
        'customer_id': values.customerId,
        'project_id': values.projectId,
        'tipo': values.tipo,
        'dias_validez': values.diasValidez,
        'max_dispositivos': 1,
        'auto_activate': values.autoActivate,
      };
      if (values.notas != null) body['notas'] = values.notas!;

      await _licensesService.createLicense(body);
      if (mounted) {
        setState(() {
          _creating = false;
          _showCreatePanel = false;
        });
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licencia creada correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _updateLicense(LicenseFormValues values) async {
    final selected = _selected;
    if (selected == null) return;

    setState(() => _creating = true);
    try {
      final body = <String, dynamic>{
        'customer_id': values.customerId,
        'tipo': values.tipo,
        'dias_validez': values.diasValidez,
      };
      if (values.projectId != null) body['project_id'] = values.projectId!;
      if (values.notas != null) body['notas'] = values.notas!;

      await _licensesService.updateLicense(selected.id, body);
      if (mounted) {
        setState(() {
          _creating = false;
          _editingLicense = false;
          _selected = null;
        });
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licencia actualizada correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _openEditLicense(License license) {
    setState(() {
      _selected = license;
      _showCreatePanel = false;
      _editingLicense = true;
    });
  }

  Future<void> _openEditMobile(License license) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        child: LicenseFormPanel(
          customers: _customers,
          projects: _projects,
          loading: _creating,
          projectsLoading: _projectsLoading,
          initialValues: LicenseFormValues(
            customerId: license.customerId ?? '',
            projectId: license.projectId,
            projectCode: license.raw?['project_code']?.toString(),
            projectName: license.projectName,
            tipo: license.licenseType ?? 'FULL',
            diasValidez:
                int.tryParse(license.raw?['dias_validez']?.toString() ?? '') ??
                    30,
            notas: license.notes,
            autoActivate: false,
          ),
          title: 'Editar licencia',
          submitLabel: 'Guardar cambios',
          onSubmit: (values) async {
            Navigator.of(ctx).pop();
            setState(() => _selected = license);
            await _updateLicense(values);
          },
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final selected = _selected;
    if (selected == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar licencia'),
        content: const Text(
            '¿Eliminar esta licencia? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _licensesService.deleteLicense(selected.id);
      if (mounted) {
        setState(() => _selected = null);
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licencia eliminada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _actionAndRefresh(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /// Show activation confirmation dialog and activate the license.
  /// The dialog only returns true/false. Activation happens after dialog closes.
  /// No Navigator.pop() is called on the page context after activation.
  Future<void> _activateLicenseWithConfirmation(License license) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activar licencia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Seguro que deseas activar esta licencia?'),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (license.customerName != null)
                    _DialogRow('Cliente', license.customerName!),
                  _DialogRow('Sistema', license.displayProjectName),
                  _DialogRow('Licencia', license.shortKey),
                  _DialogRow('Estado', license.status ?? '—'),
                  if (license.expiresAt != null)
                    _DialogRow('Vencimiento',
                        DateFormat('dd/MM/yyyy').format(license.expiresAt!.toLocal())),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('Activar licencia'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // Activation happens after dialog closes — no loading dialog needed.
    // This avoids any Navigator.pop() on the page context.
    try {
      setState(() {
        _activatingLicenseId = license.id;
      });

      await _licensesService.activateLicense(license.id);

      if (!mounted) return;

      _refresh();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Licencia activada correctamente'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      String message;
      if (e is ApiException) {
        message = 'No se pudo activar la licencia: ${e.message}';
      } else {
        message = 'No se pudo activar la licencia: $e';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _activatingLicenseId = null;
        });
      }
    }
  }

  void _viewCustomer(String customerId) {
    context.go('/admin/clientes?customerId=$customerId');
  }

  Future<void> _openDetailMobile(License license) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog.fullscreen(
        child: LicenseDetailPanel(
          license: license,
          onClose: () => Navigator.of(context).pop(),
          onEdit: () async {
            Navigator.of(context).pop();
            await _openEditMobile(license);
          },
          onActivate: () => _activateLicenseWithConfirmation(license),
          onBlock: () => _licensesService.blockLicense(license.id),
          onUnblock: () => _licensesService.unblockLicense(license.id),
          onExtend: (d) => _licensesService.extendDays(license.id, d),
          onDelete: () async {
            Navigator.of(context).pop();
            await _deleteSelected();
          },
          onViewCustomer: license.customerId != null
              ? () => _viewCustomer(license.customerId!)
              : null,
        ),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<List<License>>(
        future: _licensesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView(message: 'Cargando licencias...');
          }
          if (snapshot.hasError) {
            return ErrorView(
                message: snapshot.error.toString(), onRetry: _refresh);
          }

          final all = snapshot.data ?? [];
          final licenses = _filtered(all);

          return Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    // Top bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border:
                            Border(bottom: BorderSide(color: AppColors.border)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 34,
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (v) => setState(() => _query = v),
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Buscar licencia...',
                                  prefixIcon:
                                      const Icon(Icons.search_rounded, size: 16),
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                        color: AppColors.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                        color: AppColors.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                        color: AppColors.primary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          IconButton(
                            icon:
                                const Icon(Icons.more_vert_rounded, size: 18),
                            tooltip: 'Filtros',
                            onPressed: () async {
                              final overlay = Overlay.of(context)
                                  .context
                                  .findRenderObject() as RenderBox;
                              final selected = await showMenu<String>(
                                context: context,
                                position: RelativeRect.fromRect(
                                  Rect.fromLTWH(
                                      overlay.size.width - 160, 100, 100, 100),
                                  Offset.zero & overlay.size,
                                ),
                                items: const [
                                  PopupMenuItem(
                                      value: 'TODAS',
                                      child: Text('Todas')),
                                  PopupMenuItem(
                                      value: 'ACTIVA',
                                      child: Text('Activa')),
                                  PopupMenuItem(
                                      value: 'PENDIENTE',
                                      child: Text('Inactiva/Pendiente')),
                                  PopupMenuItem(
                                      value: 'VENCIDA',
                                      child: Text('Vencida')),
                                  PopupMenuItem(
                                      value: 'DEMO', child: Text('Demo')),
                                ],
                              );
                              if (selected != null) {
                                setState(() => _estadoFiltro = selected);
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            onPressed: _refresh,
                            tooltip: 'Actualizar',
                          ),
                          const SizedBox(width: 4),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _selected = null;
                                _showCreatePanel = true;
                              });
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Nueva licencia'),
                          ),
                        ],
                      ),
                    ),
                    // Info bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: 6),
                      color: AppColors.surfaceVariant,
                      child: Row(
                        children: [
                          Text(
                            '${licenses.length} licencia${licenses.length != 1 ? 's' : ''}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Filtro: ${_estadoFiltro == 'TODAS' ? 'Todas' : _estadoFiltro}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    // List
                    Expanded(
                      child: licenses.isEmpty
                          ? const EmptyState(
                              title: 'Sin licencias',
                              subtitle: 'No hay licencias para mostrar',
                              icon: Icons.vpn_key_off_rounded,
                            )
                          : ListView.separated(
                              itemCount: licenses.length,
                              separatorBuilder: (context, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final license = licenses[i];
                                return LicenseListItem(
                                  license: license,
                                  isSelected: _selected?.id == license.id,
                                  onTap: () async {
                                    if (_isDesktop) {
                                      setState(() {
                                        _showCreatePanel = false;
                                        _selected = license;
                                      });
                                    } else {
                                      setState(() => _selected = license);
                                      await _openDetailMobile(license);
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              // Desktop panels
              if (_isDesktop && _showCreatePanel)
                LicenseFormPanel(
                  customers: _customers,
                  projects: _projects,
                  loading: _creating,
                  projectsLoading: _projectsLoading,
                  onSubmit: _createLicense,
                  onClose: () => setState(() => _showCreatePanel = false),
                ),
              if (_isDesktop && _editingLicense && _selected != null)
                LicenseFormPanel(
                  customers: _customers,
                  projects: _projects,
                  loading: _creating,
                  projectsLoading: _projectsLoading,
                  initialValues: LicenseFormValues(
                    customerId: _selected!.customerId ?? '',
                    projectId: _selected!.projectId,
                    projectCode:
                        _selected!.raw?['project_code']?.toString(),
                    projectName: _selected!.projectName,
                    tipo: _selected!.licenseType ?? 'FULL',
                    diasValidez: int.tryParse(
                            _selected!.raw?['dias_validez']?.toString() ??
                                '') ??
                        30,
                    notas: _selected!.notes,
                    autoActivate: false,
                  ),
                  title: 'Editar licencia',
                  submitLabel: 'Guardar cambios',
                  onSubmit: _updateLicense,
                  onClose: () => setState(() => _editingLicense = false),
                ),
              if (_isDesktop &&
                  !_showCreatePanel &&
                  !_editingLicense &&
                  _selected != null)
                LicenseDetailPanel(
                  key: ValueKey(_selected!.id),
                  license: _selected!,
                  onClose: () => setState(() => _selected = null),
                  onEdit: () async {
                    _openEditLicense(_selected!);
                  },
                  onActivate: () => _activateLicenseWithConfirmation(_selected!),
                  onBlock: () => _actionAndRefresh(
                    () => _licensesService.blockLicense(_selected!.id),
                  ),
                  onUnblock: () => _actionAndRefresh(
                    () => _licensesService.unblockLicense(_selected!.id),
                  ),
                  onExtend: (d) => _actionAndRefresh(
                    () => _licensesService.extendDays(_selected!.id, d),
                  ),
                  onDelete: _deleteSelected,
                  onViewCustomer: _selected!.customerId != null
                      ? () => _viewCustomer(_selected!.customerId!)
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Helper widget for dialog rows.
class _DialogRow extends StatelessWidget {
  final String label;
  final String value;

  const _DialogRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
