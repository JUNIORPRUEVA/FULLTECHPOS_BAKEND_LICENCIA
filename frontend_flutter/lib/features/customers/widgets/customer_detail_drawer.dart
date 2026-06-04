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
  }

  String get _initial {
    final name = (_currentCustomer?.nombreNegocio ?? '').trim();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _refreshCustomer() async {
    try {
      final updated =
          await _customerService.getCustomer(_currentCustomer!.id);
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
      _loadingLicenses = true;
      _errorLicenses = null;
      _activeView = 'licenses';
      _selectedLicense = null;
    });
    try {
      final licenses =
          await _customerService.getCustomerLicenses(_currentCustomer!.id);
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
      projects.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
        await _viewLicenses();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear licencia: $e')),
        );
      }
    }
  }

  Future<void> _assignBusinessId() async {
    final customer = _currentCustomer!;
    final hasBusinessId =
        customer.businessId != null && customer.businessId!.isNotEmpty;

    if (hasBusinessId) {
      final regenerate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Business ID'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Este cliente ya tiene un Business ID asignado:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        customer.businessId!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: customer.businessId!));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Business ID copiado')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('¿Deseas regenerar un nuevo Business ID?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Regenerar'),
            ),
          ],
        ),
      );
      if (regenerate != true) return;
    }

    setState(() => _loadingAction = true);
    try {
      final result = await _customerService.assignBusinessId(
        customer.id,
        force: hasBusinessId,
      );
      if (mounted) {
        setState(() => _loadingAction = false);
        final msg = result['message'] as String? ??
            'Business ID asignado correctamente';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        await _refreshCustomer();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: token));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text('Token copiado al portapapeles')),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editCustomer() async {
    final customer = _currentCustomer!;
    final nameCtrl =
        TextEditingController(text: customer.nombreNegocio);
    final contactNameCtrl =
        TextEditingController(text: customer.contactoNombre ?? '');
    final phoneCtrl =
        TextEditingController(text: customer.contactoTelefono ?? '');
    final emailCtrl =
        TextEditingController(text: customer.contactoEmail ?? '');
    final roleCtrl =
        TextEditingController(text: customer.rolNegocio ?? '');
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
                  decoration:
                      const InputDecoration(labelText: 'Nombre del negocio'),
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
                  'contacto_nombre':
                      contactNameCtrl.text.trim().isEmpty
                          ? null
                          : contactNameCtrl.text.trim(),
                  'contacto_telefono': phoneCtrl.text.trim(),
                  'contacto_email':
                      emailCtrl.text.trim().isEmpty
                          ? null
                          : emailCtrl.text.trim(),
                  'rol_negocio':
                      roleCtrl.text.trim().isEmpty
                          ? null
                          : roleCtrl.text.trim(),
                });
                Navigator.pop(ctx, true);
              } catch (e) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Vista completa del cliente',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
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
                            'Business ID', customer.businessId ?? '—',
                            mono: true),
                        if (customer.createdAt != null)
                          _fullRow(
                              'Registro',
                              DateFormat('dd/MM/yyyy HH:mm')
                                  .format(customer.createdAt!.toLocal())),
                      ]),
                      const SizedBox(height: 16),
                      _fullSection('Licencias (${licenses.length})', [
                        if (licenses.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Sin licencias registradas',
                                style:
                                    TextStyle(color: AppColors.textMuted)),
                          )
                        else
                          ...licenses.map((l) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
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
                              )),
                      ]),
                      const SizedBox(height: 16),
                      _fullSection('Pagos (${payments.length})', [
                        if (payments.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Sin pagos registrados',
                                style:
                                    TextStyle(color: AppColors.textMuted)),
                          )
                        else
                          ...payments.map((p) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  '${p['id']?.toString().substring(0, 8) ?? '—'} - \$${p['amount'] ?? '0'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              )),
                      ]),
                      if (loadError != null) ...[
                        const SizedBox(height: 16),
                        Text(loadError,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 12)),
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
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
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
                    color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Se borrará el cliente junto con sus licencias y datos relacionados.',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.warning),
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
            child: const Text('Eliminar',
                style: TextStyle(color: AppColors.error)),
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
              content: Text(errorMsg.contains('licencia')
                  ? errorMsg
                  : 'No se puede eliminar: el cliente tiene datos asociados'),
              backgroundColor: AppColors.warning,
            ),
          );
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
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
        await _viewLicenses();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al activar: $e')));
      }
    }
  }

  Future<void> _blockLicense(License license) async {
    setState(() => _loadingAction = true);
    try {
      await _licensesService.blockLicense(license.id);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Licencia bloqueada')));
        await _viewLicenses();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _unblockLicense(License license) async {
    setState(() => _loadingAction = true);
    try {
      await _licensesService.unblockLicense(license.id);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Licencia desbloqueada')));
        await _viewLicenses();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
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
            SnackBar(content: Text('Licencia extendida $days días')));
        await _viewLicenses();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteLicense(License license) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar licencia'),
        content: Text('¿Eliminar la licencia "${license.shortKey}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loadingAction = true);
    try {
      await _licensesService.deleteLicense(license.id);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Licencia eliminada')));
        await _viewLicenses();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
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
        border: const Border(
          left: BorderSide(color: AppColors.border),
        ),
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
    final statusText = customer.hasActiveLicense
        ? 'Activa'
        : customer.hasLicense
            ? (customer.licenseStatus ?? 'Inactiva')
            : 'Sin licencia';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar + Estado ──
          Center(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppSpacing.avatarRadius),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      _initial,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  customer.nombreNegocio,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                StatusBadge.fromString(statusText, pill: true),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Información del cliente ──
          _buildInfoCard('Información del cliente', [
            _buildInfoRow(Icons.store_outlined, 'Negocio',
                customer.nombreNegocio),
            if (customer.contactoNombre != null)
              _buildInfoRow(Icons.person_outline, 'Contacto',
                  customer.contactoNombre!),
            if (customer.contactoTelefono != null)
              _buildInfoRow(Icons.phone_outlined, 'Teléfono',
                  customer.contactoTelefono!),
            if (customer.contactoEmail != null)
              _buildInfoRow(
                  Icons.email_outlined, 'Email', customer.contactoEmail!),
            if (customer.rolNegocio != null)
              _buildInfoRow(
                  Icons.category_outlined, 'Rol', customer.rolNegocio!),
          ]),
          const SizedBox(height: 16),

          // ── Licencia principal ──
          _buildInfoCard('Licencia principal', [
            _buildInfoRow(
              Icons.vpn_key_outlined,
              'Estado',
              customer.hasActiveLicense
                  ? 'Activa'
                  : customer.hasLicense
                      ? (customer.licenseStatus ?? 'Inactiva')
                      : 'Sin licencia',
              valueColor: customer.hasActiveLicense
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
            if (customer.licenseTipo != null)
              _buildInfoRow(
                  Icons.category_outlined, 'Tipo', customer.licenseTipo!),
          ]),
          const SizedBox(height: 16),

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
              customer.businessId ?? '—',
              mono: true,
              copyable: customer.businessId != null,
            ),
          ]),
          const SizedBox(height: 24),

          // ── Acciones ──
          _buildActionsSection(),
        ],
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
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
          const SizedBox(height: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
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
              style: TextStyle(
                fontSize: 13,
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
                child: Icon(Icons.copy_rounded, size: 14, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SECCIÓN DE ACCIONES
  // ═══════════════════════════════════════════════════════════════
  Widget _buildActionsSection() {
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
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.vpn_key_outlined,
          label: 'Ver licencias',
          subtitle: 'Gestiona las licencias de este cliente',
          onTap: _viewLicenses,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          icon: Icons.add_circle_outline,
          label: 'Crear licencia',
          subtitle: 'Asigna una nueva licencia al cliente',
          onTap: _createLicense,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          icon: Icons.business_outlined,
          label: 'Asignar Business ID',
          subtitle: 'Genera o regenera el identificador único',
          onTap: _assignBusinessId,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          icon: Icons.edit_outlined,
          label: 'Editar cliente',
          subtitle: 'Modifica los datos del cliente',
          onTap: _editCustomer,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          icon: Icons.open_in_full_outlined,
          label: 'Vista completa',
          subtitle: 'Ver toda la información detallada',
          onTap: _viewFullDetail,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          icon: Icons.refresh_rounded,
          label: 'Reset token',
          subtitle: 'Genera un nuevo token de reset',
          onTap: _resetToken,
        ),
        const SizedBox(height: 16),
        _buildActionButton(
          icon: Icons.delete_outline,
          label: 'Eliminar cliente',
          subtitle: 'Elimina permanentemente este cliente',
          onTap: _deleteCustomer,
          danger: true,
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
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: danger
                        ? AppColors.error.withOpacity(0.1)
                        : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: danger ? AppColors.error : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: danger ? AppColors.error : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: danger ? AppColors.error.withOpacity(0.5) : AppColors.textMuted,
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
            Text(_errorLicenses!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
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
              const Icon(Icons.vpn_key_rounded, size: 16, color: AppColors.textMuted),
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
                      const Icon(Icons.vpn_key_off_outlined, size: 40, color: AppColors.textMuted),
                      const SizedBox(height: 12),
                      const Text(
                        'Sin licencias registradas',
                        style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Crea una licencia para este cliente',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
                  child: const Icon(Icons.vpn_key_rounded, size: 18, color: AppColors.primary),
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
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
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
       
