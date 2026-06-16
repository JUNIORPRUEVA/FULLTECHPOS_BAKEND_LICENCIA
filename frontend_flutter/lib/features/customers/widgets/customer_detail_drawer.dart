import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../customers/services/customers_service.dart';
import '../../licenses/models/license.dart';
import '../../licenses/services/licenses_service.dart';
import '../../licenses/services/projects_service.dart';
import '../../licenses/widgets/license_detail_panel.dart';
import '../../licenses/widgets/license_form_panel.dart';
import '../../licenses/models/project.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../models/customer.dart';

/// Panel de detalle derecho rediseñado - más ancho, premium y ejecutivo
class CustomerDetailDrawer extends StatefulWidget {
  final Customer customer;
  final VoidCallback onClose;
  final VoidCallback? onDelete;
  final VoidCallback? onUpdated;
  final double width;

  const CustomerDetailDrawer({
    super.key,
    required this.customer,
    required this.onClose,
    this.onDelete,
    this.onUpdated,
    this.width = AppSpacing.detailPanelWidth,
  });

  @override
  State<CustomerDetailDrawer> createState() => _CustomerDetailDrawerState();
}

class _CustomerDetailDrawerState extends State<CustomerDetailDrawer> {
  late final CustomersService _customerService;
  late final LicensesService _licensesService;
  late final ProjectsService _projectsService;
  Customer? _currentCustomer;
  List<License> _licenses = [];
  bool _loadingLicenses = false;
  bool _loadingAction = false;
  String? _errorLicenses;
  String? _activeView;
  License? _selectedLicense;
  List<Project> _projects = [];
  bool _projectsLoading = false;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionManager>();
    _customerService = CustomersService(sessionManager: session);
    _licensesService = LicensesService(sessionManager: session);
    _projectsService = ProjectsService(sessionManager: session);
    _currentCustomer = widget.customer;
    _loadLicenseHistory();
  }

  Future<void> _refreshCustomer() async {
    try {
      final updated = await _customerService.getCustomer(_currentCustomer!.id);
      if (mounted) {
        setState(() => _currentCustomer = updated);
        widget.onUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al refrescar cliente: $e')),
        );
      }
    }
  }

  Future<void> _viewLicenses() async {
    setState(() {
      _activeView = 'licenses';
      _selectedLicense = null;
    });
    await _loadLicenseHistory();
  }

  Future<void> _loadLicenseHistory() async {
    setState(() {
      _loadingLicenses = true;
      _errorLicenses = null;
    });
    try {
      final licenses = await _customerService.getCustomerLicenses(
        _currentCustomer!.id,
      );
      licenses.sort((a, b) {
        final aDate =
            a.createdAt ??
            a.expiresAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            b.createdAt ??
            b.expiresAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      if (mounted) {
        setState(() {
          _licenses = licenses;
          _loadingLicenses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingLicenses = false;
          _errorLicenses = 'No se pudieron cargar las licencias: $e';
        });
      }
    }
  }

  Future<void> _createLicense() async {
    setState(() {
      _projectsLoading = true;
      _activeView = 'create_license';
    });
    try {
      final projects = await _projectsService.listProjects();
      // Ordenar proyectos por nombre alfabéticamente
      projects.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (mounted) {
        setState(() {
          _projects = projects;
          _projectsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _projectsLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar proyectos: $e')),
        );
      }
    }
  }

  Future<void> _submitCreateLicense(LicenseFormValues values) async {
    setState(() => _loadingAction = true);
    try {
      final body = <String, dynamic>{
        'customer_id': values.customerId,
        'project_id': values.projectId,
        'tipo': values.tipo,
        'dias_validez': values.diasValidez,
        'notas': values.notas,
        'auto_activate': values.autoActivate,
      };
      if (values.maxDevices != null) {
        body['max_dispositivos'] = values.maxDevices;
      }
      await _licensesService.createLicense(body);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licencia creada correctamente')),
        );
        await _refreshCustomer();
        await _loadLicenseHistory();
        if (mounted) {
          setState(() => _activeView = 'licenses');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al crear licencia: $e')));
      }
    }
  }

  Future<void> _assignBusinessId() async {
    final customer = _currentCustomer!;
    final hasBusinessId =
        customer.businessId != null && customer.businessId!.isNotEmpty;
    final replacementBusinessId = await _requestManualBusinessId(
      customer: customer,
      hasBusinessId: hasBusinessId,
    );
    if (replacementBusinessId == null) return;

    setState(() => _loadingAction = true);
    try {
      final result = hasBusinessId
          ? await _customerService.repairBusinessId(
              customerId: customer.id,
              businessId: replacementBusinessId,
              reason: 'Business ID reemplazado manualmente desde APYRA Admin',
            )
          : await _customerService.assignBusinessId(
              customer.id,
              businessId: replacementBusinessId,
            );
      if (mounted) {
        setState(() => _loadingAction = false);
        final msg =
            result['message'] as String? ??
            result['warning'] as String? ??
            (hasBusinessId
                ? 'Business ID cambiado correctamente'
                : 'Business ID asignado correctamente');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        await _refreshCustomer();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _resetToken() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Token reset'),
        content: const Text(
          '¿Seguro que deseas generar un nuevo token de reset para este cliente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generar token'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loadingAction = true);
    try {
      final result = await _customerService.resetToken(_currentCustomer!.id);
      final token = result['token'] as String? ?? '';
      final expiresAt = result['expires_at'] as String? ?? '';
      if (mounted) {
        setState(() => _loadingAction = false);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Token generado'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Token de reset:'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    token,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (expiresAt.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Expira: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(expiresAt).toLocal())}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: token));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Token copiado al portapapeles'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copiar token'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editCustomer() async {
    final customer = _currentCustomer!;
    final nameCtrl = TextEditingController(text: customer.nombreNegocio);
    final contactNameCtrl = TextEditingController(
      text: customer.contactoNombre ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: customer.contactoTelefono ?? '',
    );
    final emailCtrl = TextEditingController(text: customer.contactoEmail ?? '');
    final roleCtrl = TextEditingController(text: customer.rolNegocio ?? '');
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar cliente'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del negocio',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: contactNameCtrl,
                  decoration: const InputDecoration(labelText: 'Contacto'),
                ),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextFormField(
                  controller: roleCtrl,
                  decoration: const InputDecoration(labelText: 'Rol'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await _customerService.updateCustomer(customer.id, {
                  'nombre_negocio': nameCtrl.text.trim(),
                  'contacto_nombre': contactNameCtrl.text.trim().isEmpty
                      ? null
                      : contactNameCtrl.text.trim(),
                  'contacto_telefono': phoneCtrl.text.trim(),
                  'contacto_email': emailCtrl.text.trim().isEmpty
                      ? null
                      : emailCtrl.text.trim(),
                  'rol_negocio': roleCtrl.text.trim().isEmpty
                      ? null
                      : roleCtrl.text.trim(),
                });
                Navigator.pop(ctx, true);
              } catch (e) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cliente actualizado correctamente')),
        );
        await _refreshCustomer();
      }
    }
  }

  Future<void> _viewFullDetail() async {
    final customer = _currentCustomer!;
    List<License> licenses = [];
    List<Map<String, dynamic>> payments = [];
    String? loadError;
    try {
      licenses = await _customerService.getCustomerLicenses(customer.id);
    } catch (_) {}
    try {
      payments = await _customerService.getCustomerPayments(customer.id);
    } catch (_) {}
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: 700,
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Vista completa del cliente',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fullSection('Datos generales', [
                        _fullRow('Negocio', customer.nombreNegocio),
                        if (customer.contactoNombre != null)
                          _fullRow('Contacto', customer.contactoNombre!),
                        if (customer.contactoTelefono != null)
                          _fullRow('Teléfono', customer.contactoTelefono!),
                        if (customer.contactoEmail != null)
                          _fullRow('Email', customer.contactoEmail!),
                        if (customer.rolNegocio != null)
                          _fullRow('Rol', customer.rolNegocio!),
                        _fullRow('Client ID', customer.id, mono: true),
                        _fullRow(
                          'Business ID',
                          customer.businessId ?? '—',
                          mono: true,
                        ),
                        if (customer.createdAt != null)
                          _fullRow(
                            'Registro',
                            DateFormat(
                              'dd/MM/yyyy HH:mm',
                            ).format(customer.createdAt!.toLocal()),
                          ),
                      ]),
                      const SizedBox(height: 16),
                      _fullSection('Licencias (${licenses.length})', [
                        if (licenses.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Sin licencias registradas',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          )
                        else
                          ...licenses.map(
                            (l) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${l.displayProjectName} - ${l.shortKey}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  if (l.status != null)
                                    StatusBadge.fromString(l.status!),
                                ],
                              ),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 16),
                      _fullSection('Pagos (${payments.length})', [
                        if (payments.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Sin pagos registrados',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          )
                        else
                          ...payments.map(
                            (p) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '${p['id']?.toString().substring(0, 8) ?? '—'} - \$${p['amount'] ?? '0'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                      ]),
                      if ((loadError ?? '').isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          loadError!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fullSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _fullRow(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCustomer() async {
    final customer = _currentCustomer!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Eliminar a "${customer.nombreNegocio}"?'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Se borrará el cliente junto con sus licencias y datos relacionados.',
                      style: TextStyle(fontSize: 11, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loadingAction = true);
    try {
      await _customerService.deleteCustomer(customer.id);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cliente eliminado correctamente')),
        );
        widget.onDelete?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        final errorMsg = e.toString();
        if (errorMsg.contains('409') ||
            errorMsg.contains('licencia(s) activa(s)') ||
            errorMsg.contains('pago(s) asociado(s)')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errorMsg.contains('licencia')
                    ? errorMsg
                    : 'No se puede eliminar: el cliente tiene datos asociados',
              ),
              backgroundColor: AppColors.warning,
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _activateLicense(License license) async {
    setState(() => _loadingAction = true);
    try {
      await _licensesService.activateLicense(license.id);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licencia activada correctamente')),
        );
        await _refreshCustomer();
        await _loadLicenseHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al activar: $e')));
      }
    }
  }

  Future<void> _blockLicense(License license) async {
    setState(() => _loadingAction = true);
    try {
      await _licensesService.blockLicense(license.id);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Licencia bloqueada')));
        await _refreshCustomer();
        await _loadLicenseHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _unblockLicense(License license) async {
    setState(() => _loadingAction = true);
    try {
      await _licensesService.unblockLicense(license.id);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Licencia desbloqueada')));
        await _refreshCustomer();
        await _loadLicenseHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _extendLicense(License license, int days) async {
    setState(() => _loadingAction = true);
    try {
      await _licensesService.extendDays(license.id, days);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Licencia extendida $days días')),
        );
        await _refreshCustomer();
        await _loadLicenseHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteLicense(License license) async {
    await _confirmDeleteLicense(license);
  }

  Future<bool> _confirmDeleteLicense(License license) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar licencia'),
        content: Text('¿Eliminar la licencia "${license.shortKey}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    setState(() => _loadingAction = true);
    try {
      await _licensesService.deleteLicense(license.id);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Licencia eliminada')));
        await _refreshCustomer();
        await _loadLicenseHistory();
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return false;
    }
  }

  Future<String?> _requestManualBusinessId({
    required Customer customer,
    required bool hasBusinessId,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BusinessIdRepairDialog(
        currentBusinessId: customer.businessId,
        hasBusinessId: hasBusinessId,
      ),
    );
  }

  Future<void> _ensureProjectsLoaded() async {
    if (_projects.isNotEmpty || _projectsLoading) return;

    setState(() => _projectsLoading = true);
    try {
      final projects = await _projectsService.listProjects();
      projects.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (mounted) {
        setState(() {
          _projects = projects;
          _projectsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _projectsLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar proyectos: $e')),
        );
      }
    }
  }

  Future<bool> _updateLicenseFromValues(
    License license,
    LicenseFormValues values,
  ) async {
    setState(() => _loadingAction = true);
    try {
      final body = <String, dynamic>{
        'customer_id': values.customerId,
        'tipo': values.tipo,
        'dias_validez': values.diasValidez,
      };
      if (values.projectId != null) body['project_id'] = values.projectId;
      if (values.notas != null) body['notas'] = values.notas;

      await _licensesService.updateLicense(license.id, body);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licencia actualizada correctamente')),
        );
        await _refreshCustomer();
        await _loadLicenseHistory();
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar licencia: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _openEditLicenseDialog(License license) async {
    await _ensureProjectsLoaded();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 860,
          height: 760,
          child: LicenseFormPanel(
            customers: [_currentCustomer!],
            projects: _projects,
            loading: _loadingAction,
            projectsLoading: _projectsLoading,
            initialValues: LicenseFormValues(
              customerId: license.customerId ?? _currentCustomer!.id,
              projectId: license.projectId,
              projectCode: license.projectCode,
              projectName: license.projectName,
              tipo: license.licenseType ?? 'FULL',
              diasValidez:
                  int.tryParse(
                    license.raw?['dias_validez']?.toString() ?? '',
                  ) ??
                  30,
              notas: license.notes,
              autoActivate: false,
            ),
            title: 'Editar licencia',
            submitLabel: 'Guardar cambios',
            onSubmit: (values) async {
              final updated = await _updateLicenseFromValues(license, values);
              if (updated && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            onClose: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    );
  }

  Future<void> _openLicenseDialog(License license) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 860,
          height: 780,
          child: LicenseDetailPanel(
            license: license,
            onClose: () => Navigator.of(dialogContext).pop(),
            onEdit: () async {
              Navigator.of(dialogContext).pop();
              await _openEditLicenseDialog(license);
            },
            onActivate: () => _activateLicense(license),
            onBlock: () => _blockLicense(license),
            onUnblock: () => _unblockLicense(license),
            onExtend: (days) => _extendLicense(license, days),
            onDelete: () async {
              final deleted = await _confirmDeleteLicense(license);
              if (deleted && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD PRINCIPAL
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(left: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMd,
            blurRadius: 12,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    String title;
    if (_activeView == 'licenses') {
      title = 'Licencias de ${_currentCustomer!.nombreNegocio}';
    } else if (_activeView == 'license_detail' && _selectedLicense != null) {
      title = 'Detalle de licencia';
    } else if (_activeView == 'create_license') {
      title = 'Crear licencia';
    } else {
      title = _currentCustomer!.nombreNegocio;
    }

    return Container(
      height: AppSpacing.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (_activeView != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              onPressed: () => setState(() {
                if (_activeView == 'license_detail') {
                  _activeView = 'licenses';
                  _selectedLicense = null;
                } else {
                  _activeView = null;
                  _selectedLicense = null;
                }
              }),
              color: AppColors.textSecondary,
            ),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: widget.onClose,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_activeView == 'licenses') return _buildLicensesView();
    if (_activeView == 'license_detail' && _selectedLicense != null) {
      return _buildLicenseDetailView();
    }
    if (_activeView == 'create_license') return _buildCreateLicenseView();
    return _buildDetailView();
  }

  // ═══════════════════════════════════════════════════════════════
  // VISTA: DETALLE DEL CLIENTE (REDISEÑADA)
  // ═══════════════════════════════════════════════════════════════
  Widget _buildDetailView() {
    final customer = _currentCustomer!;
    final statusText = customer.displayLicenseStatus;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        10,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar + Estado ──
          _buildCompactSummary(customer, statusText),
          const SizedBox(height: 8),

          // ── Información del cliente ──
          _buildInfoCard('Información del cliente', [
            if (customer.contactoNombre != null)
              _buildInfoRow(
                Icons.person_outline,
                'Contacto',
                customer.contactoNombre!,
              ),
            if (customer.contactoTelefono != null)
              _buildInfoRow(
                Icons.phone_outlined,
                'Teléfono',
                customer.contactoTelefono!,
              ),
            if (customer.contactoEmail != null)
              _buildInfoRow(
                Icons.email_outlined,
                'Email',
                customer.contactoEmail!,
              ),
            if (customer.rolNegocio != null)
              _buildInfoRow(
                Icons.category_outlined,
                'Rol',
                customer.rolNegocio!,
              ),
          ]),
          const SizedBox(height: 8),

          // ── Licencia principal ──
          const SizedBox(height: 8),

          // ── IDs del sistema ──
          _buildInfoCard('IDs del sistema', [
            _buildInfoRow(
              Icons.fingerprint,
              'Client ID',
              customer.id,
              mono: true,
              copyable: true,
            ),
            _buildInfoRow(
              Icons.business_outlined,
              'Business ID',
              customer.businessId ?? 'No asignado',
              mono: customer.hasBusinessId,
              copyable: customer.hasBusinessId,
            ),
          ]),
          const SizedBox(height: 8),

          // ── Acciones ──
          _buildActionsSection(compact: true),
          const SizedBox(height: 8),

          // ── Historial de licencias ──
          Expanded(child: _buildEmbeddedLicenseHistory()),
        ],
      ),
    );
  }

  Widget _buildCompactSummary(Customer customer, String statusText) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.displayCommercialStatus,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  customer.licenseTipo ?? 'Sin licencia comercial',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge.fromString(statusText, pill: true),
        ],
      ),
    );
  }

  Widget _buildEmbeddedLicenseHistory() {
    final total = _licenses.length;
    final activeCount = _licenses.where((license) => license.isActive).length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Historial de licencias',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$total registro${total == 1 ? '' : 's'} · $activeCount activa${activeCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: OutlinedButton.icon(
                    onPressed: _viewLicenses,
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: const Text('Abrir', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loadingLicenses
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _errorLicenses != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.error,
                            size: 26,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorLicenses!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _loadLicenseHistory,
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _licenses.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.vpn_key_off_outlined,
                            size: 28,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Este cliente aún no tiene licencias registradas.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _createLicense,
                            icon: const Icon(Icons.add_rounded, size: 14),
                            label: const Text('Crear licencia'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                    itemCount: _licenses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) =>
                        _buildEmbeddedLicenseTile(_licenses[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbeddedLicenseTile(License license) {
    final dateLabel = license.expiresAt != null
        ? 'Vence ${DateFormat('dd/MM/yyyy').format(license.expiresAt!.toLocal())}'
        : (license.createdAt != null
              ? 'Creada ${DateFormat('dd/MM/yyyy').format(license.createdAt!.toLocal())}'
              : 'Sin fecha');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openLicenseDialog(license),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowMd.withOpacity(0.06),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  size: 17,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            license.displayProjectName,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (license.status != null)
                          StatusBadge.fromString(license.status!),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${license.licenseType ?? 'LICENCIA'} · ${license.shortKey}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: 0.3,
              ),
            ),
          ),
          ...children,
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    bool mono = false,
    bool copyable = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: valueColor ?? AppColors.textPrimary,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
          if (copyable)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copiado'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: AppColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SECCIÓN DE ACCIONES
  // ═══════════════════════════════════════════════════════════════
  Widget _buildActionsSection({bool compact = false}) {
    final actions = <Widget>[
      _buildActionButton(
        icon: Icons.vpn_key_outlined,
        label: 'Ver licencias',
        subtitle: 'Gestiona las licencias',
        onTap: _viewLicenses,
        compact: compact,
      ),
      _buildActionButton(
        icon: Icons.add_circle_outline,
        label: 'Crear licencia',
        subtitle: 'Asigna una licencia',
        onTap: _createLicense,
        compact: compact,
      ),
      _buildActionButton(
        icon: Icons.business_outlined,
        label: _currentCustomer!.hasBusinessId
            ? 'Cambiar Business ID'
            : 'Asignar Business ID',
        subtitle: _currentCustomer!.hasBusinessId
            ? 'Asigna un ID nuevo'
            : 'Genera el ID del negocio',
        onTap: _assignBusinessId,
        compact: compact,
      ),
      _buildActionButton(
        icon: Icons.edit_outlined,
        label: 'Editar cliente',
        subtitle: 'Modifica los datos',
        onTap: _editCustomer,
        compact: compact,
      ),
      _buildActionButton(
        icon: Icons.open_in_full_outlined,
        label: 'Vista completa',
        subtitle: 'Ver todo el detalle',
        onTap: _viewFullDetail,
        compact: compact,
      ),
      _buildActionButton(
        icon: Icons.refresh_rounded,
        label: 'Reset token',
        subtitle: 'Genera un nuevo token',
        onTap: _resetToken,
        compact: compact,
      ),
      _buildActionButton(
        icon: Icons.delete_outline,
        label: 'Eliminar cliente',
        subtitle: 'Borrado permanente',
        onTap: _deleteCustomer,
        danger: true,
        compact: compact,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Acciones',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        if (compact)
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: actions
                    .map((action) => SizedBox(width: itemWidth, child: action))
                    .toList(),
              );
            },
          )
        else
          Column(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                actions[i],
                if (i != actions.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
    bool compact = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: danger ? AppColors.errorLight : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
          color: danger ? AppColors.error.withOpacity(0.2) : AppColors.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Padding(
            padding: EdgeInsets.all(compact ? 10 : 14),
            child: Row(
              children: [
                Container(
                  width: compact ? 30 : 36,
                  height: compact ? 30 : 36,
                  decoration: BoxDecoration(
                    color: danger
                        ? AppColors.error.withOpacity(0.1)
                        : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: compact ? 16 : 18,
                    color: danger ? AppColors.error : AppColors.primary,
                  ),
                ),
                SizedBox(width: compact ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: compact ? 12 : 13,
                          fontWeight: FontWeight.w600,
                          color: danger
                              ? AppColors.error
                              : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: compact ? 1 : 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: compact ? 10 : 11,
                          color: AppColors.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: compact ? 16 : 18,
                  color: danger
                      ? AppColors.error.withOpacity(0.5)
                      : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // VISTA: LISTA DE LICENCIAS
  // ═══════════════════════════════════════════════════════════════
  Widget _buildLicensesView() {
    if (_loadingLicenses) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_errorLicenses != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32, color: AppColors.error),
            const SizedBox(height: 8),
            Text(
              _errorLicenses!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _viewLicenses,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header con contador
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.vpn_key_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                '${_licenses.length} licencia${_licenses.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 30,
                child: ElevatedButton.icon(
                  onPressed: _createLicense,
                  icon: const Icon(Icons.add_rounded, size: 14),
                  label: const Text('Nueva', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Lista
        Expanded(
          child: _licenses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.vpn_key_off_outlined,
                        size: 40,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Sin licencias registradas',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Crea una licencia para este cliente',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _createLicense,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Crear licencia'),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _licenses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final license = _licenses[i];
                    return _buildLicenseTile(license);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLicenseTile(License license) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedLicense = license;
              _activeView = 'license_detail';
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.vpn_key_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        license.displayProjectName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        license.shortKey,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (license.status != null)
                  StatusBadge.fromString(license.status!),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // VISTA: DETALLE DE LICENCIA
  // ═══════════════════════════════════════════════════════════════
  Widget _buildLicenseDetailView() {
    final license = _selectedLicense!;
    return LicenseDetailPanel(
      license: license,
      onClose: () => setState(() {
        _activeView = 'licenses';
        _selectedLicense = null;
      }),
      onEdit: () => _openEditLicenseDialog(license),
      onActivate: () => _activateLicense(license),
      onBlock: () => _blockLicense(license),
      onUnblock: () => _unblockLicense(license),
      onExtend: (days) => _extendLicense(license, days),
      onDelete: () => _deleteLicense(license),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // VISTA: CREAR LICENCIA
  // ═══════════════════════════════════════════════════════════════
  Widget _buildCreateLicenseView() {
    if (_projectsLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return LicenseFormPanel(
      customers: [_currentCustomer!],
      projects: _projects,
      loading: _loadingAction,
      onSubmit: _submitCreateLicense,
      onClose: () => setState(() {
        _activeView = null;
      }),
    );
  }
}

class _BusinessIdRepairDialog extends StatefulWidget {
  const _BusinessIdRepairDialog({
    required this.currentBusinessId,
    required this.hasBusinessId,
  });

  final String? currentBusinessId;
  final bool hasBusinessId;

  @override
  State<_BusinessIdRepairDialog> createState() =>
      _BusinessIdRepairDialogState();
}

class _BusinessIdRepairDialogState extends State<_BusinessIdRepairDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _reviewing = false;

  String get _newBusinessId => _controller.text.trim();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _reviewing
            ? 'Confirmación final'
            : widget.hasBusinessId
            ? 'Corregir Business ID'
            : 'Asignar Business ID',
      ),
      content: SizedBox(
        width: 520,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _reviewing ? _buildReview() : _buildInput(),
        ),
      ),
      actions: _reviewing ? _reviewActions() : _inputActions(),
    );
  }

  Widget _buildInput() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('business-id-input'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.hasBusinessId) ...[
            const Text('Business ID registrado actualmente:'),
            const SizedBox(height: 6),
            _businessIdValue(widget.currentBusinessId!),
            const SizedBox(height: 16),
          ],
          const Text(
            'Copia el Business ID que aparece en la PC del cliente y '
            'pégalo exactamente aquí:',
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Business ID de la PC',
              hintText: 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx',
              border: OutlineInputBorder(),
            ),
            validator: _validateBusinessId,
          ),
          const SizedBox(height: 12),
          const Text(
            'APYRA no cambiará el ID guardado en la PC. Solo corregirá '
            'el registro del servidor para que ambos coincidan.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildReview() {
    return Column(
      key: const ValueKey('business-id-review'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.hasBusinessId
              ? 'Se corregirá únicamente el Business ID de este cliente en '
                    'APYRA.'
              : 'Se asignará manualmente este Business ID al cliente.',
        ),
        if (widget.hasBusinessId) ...[
          const SizedBox(height: 14),
          const Text('ID actual:'),
          const SizedBox(height: 5),
          _businessIdValue(widget.currentBusinessId!),
        ],
        const SizedBox(height: 14),
        const Text('ID copiado desde la PC:'),
        const SizedBox(height: 5),
        _businessIdValue(_newBusinessId, highlighted: true),
        const SizedBox(height: 14),
        const Text(
          'Verifica carácter por carácter. Esta acción es una reparación '
          'administrativa de última instancia.',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }

  List<Widget> _inputActions() {
    return [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState?.validate() != true) return;
          FocusScope.of(context).unfocus();
          setState(() => _reviewing = true);
        },
        child: const Text('Revisar cambio'),
      ),
    ];
  }

  List<Widget> _reviewActions() {
    return [
      TextButton(
        onPressed: () => setState(() => _reviewing = false),
        child: const Text('Volver'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _newBusinessId),
        child: Text(widget.hasBusinessId ? 'Aplicar corrección' : 'Asignar ID'),
      ),
    ];
  }

  String? _validateBusinessId(String? value) {
    final id = value?.trim() ?? '';
    if (id.isEmpty) return 'Debes escribir el Business ID';
    if (!_isSupportedBusinessId(id)) {
      return 'Formato inválido. Copia el ID completo desde la PC.';
    }
    if (widget.hasBusinessId && id == widget.currentBusinessId!.trim()) {
      return 'Este ID ya está asignado al cliente';
    }
    return null;
  }

  bool _isSupportedBusinessId(String value) {
    final id = value.trim();
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    final legacy = RegExp(r'^BIZ-[0-9A-F]{8,}$', caseSensitive: false);
    return uuidV4.hasMatch(id) || legacy.hasMatch(id);
  }

  Widget _businessIdValue(String value, {bool highlighted = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.primaryLight : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: highlighted ? Border.all(color: AppColors.primary) : null,
      ),
      child: SelectableText(
        value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: highlighted ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
    );
  }
}
