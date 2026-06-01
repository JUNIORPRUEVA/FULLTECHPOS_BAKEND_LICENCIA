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
  String? _activeView; // null = detail, 'licenses', 'license_detail', 'create_license'
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

  // ============================================================
  // BOTÓN: VER LICENCIAS
  // ============================================================
  Future<void> _viewLicenses() async {
    setState(() {
      _loadingLicenses = true;
      _errorLicenses = null;
      _activeView = 'licenses';
      _selectedLicense = null;
    });

    try {
      final licenses = await _customerService.getCustomerLicenses(_currentCustomer!.id);
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

  // ============================================================
  // BOTÓN: CREAR LICENCIA
  // ============================================================
  Future<void> _createLicense() async {
    setState(() {
      _projectsLoading = true;
      _activeView = 'create_license';
    });

    try {
      final projects = await _projectsService.listProjects();
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
      await _licensesService.createLicense({
        'customer_id': values.customerId,
        'project_id': values.projectId,
        'tipo': values.tipo,
        'dias_validez': values.diasValidez,
        'notas': values.notas,
        'auto_activate': values.autoActivate,
      });

      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licencia creada correctamente')),
        );
        // Refrescar cliente y volver a vista de licencias
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

  // ============================================================
  // BOTÓN: ASIGNAR BUSINESS ID
  // ============================================================
  Future<void> _assignBusinessId() async {
    final customer = _currentCustomer!;
    final hasBusinessId = customer.businessId != null && customer.businessId!.isNotEmpty;

    if (hasBusinessId) {
      // Ya tiene Business ID, preguntar si regenerar
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
                        Clipboard.setData(ClipboardData(text: customer.businessId!));
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
        final msg = result['message'] as String? ?? 'Business ID asignado correctamente';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        await _refreshCustomer();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ============================================================
  // BOTÓN: TOKEN RESET
  // ============================================================
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
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: token));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Token copiado al portapapeles')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al generar token: $e')),
        );
      }
    }
  }

  // ============================================================
  // BOTÓN: EDITAR CLIENTE
  // ============================================================
  Future<void> _editCustomer() async {
    final customer = _currentCustomer!;
    final nameCtrl = TextEditingController(text: customer.nombreNegocio);
    final contactNameCtrl = TextEditingController(text: customer.contactoNombre ?? '');
    final phoneCtrl = TextEditingController(text: customer.contactoTelefono ?? '');
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
                  decoration: const InputDecoration(labelText: 'Nombre del negocio'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: contactNameCtrl,
                  decoration: const InputDecoration(labelText: 'Contacto'),
                ),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
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
                  'contacto_nombre': contactNameCtrl.text.trim().isEmpty ? null : contactNameCtrl.text.trim(),
                  'contacto_telefono': phoneCtrl.text.trim(),
                  'contacto_email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                  'rol_negocio': roleCtrl.text.trim().isEmpty ? null : roleCtrl.text.trim(),
                });
                Navigator.pop(ctx, true);
              } catch (e) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
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

  // ============================================================
  // BOTÓN: VISTA COMPLETA
  // ============================================================
  Future<void> _viewFullDetail() async {
    final customer = _currentCustomer!;

    // Cargar licencias y pagos para mostrar en vista completa
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
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Vista completa del cliente',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Datos generales
                      _fullSection('Datos generales', [
                        _fullRow('Negocio', customer.nombreNegocio),
                        if (customer.contactoNombre != null) _fullRow('Contacto', customer.contactoNombre!),
                        if (customer.contactoTelefono != null) _fullRow('Teléfono', customer.contactoTelefono!),
                        if (customer.contactoEmail != null) _fullRow('Email', customer.contactoEmail!),
                        if (customer.rolNegocio != null) _fullRow('Rol', customer.rolNegocio!),
                        _fullRow('Client ID', customer.id, mono: true),
                        _fullRow('Business ID', customer.businessId ?? '—', mono: true),
                        if (customer.createdAt != null)
                          _fullRow('Registro', DateFormat('dd/MM/yyyy HH:mm').format(customer.createdAt!.toLocal())),
                      ]),
                      const SizedBox(height: 16),
                      // 2. Licencias
                      _fullSection('Licencias (${licenses.length})', [
                        if (licenses.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Sin licencias registradas', style: TextStyle(color: AppColors.textMuted)),
                          )
                        else
                          ...licenses.map((l) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${l.displayProjectName} - ${l.shortKey}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (l.status != null) StatusBadge.fromString(l.status!),
                              ],
                            ),
                          )),
                      ]),
                      const SizedBox(height: 16),
                      // 3. Pagos
                      _fullSection('Pagos (${payments.length})', [
                        if (payments.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Sin pagos registrados', style: TextStyle(color: AppColors.textMuted)),
                          )
                        else
                          ...payments.map((p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '${p['id']?.toString().substring(0, 8) ?? '—'} - \$${p['amount'] ?? '0'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          )),
                      ]),
                      if (loadError != null) ...[
                        const SizedBox(height: 16),
                        Text(loadError, style: const TextStyle(color: AppColors.error, fontSize: 12)),
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
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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

  // ============================================================
  // BOTÓN: ELIMINAR CLIENTE (mejorado con validación)
  // ============================================================
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
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Si el cliente tiene licencias activas o pagos asociados, no se podrá eliminar.',
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
            child: const Text('Eliminar', style: TextStyle(color: AppColors.error)),
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
        // Mostrar mensaje amigable si es 409
        if (errorMsg.contains('409') || errorMsg.contains('licencia(s) activa(s)') || errorMsg.contains('pago(s) asociado(s)')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg.contains('licencia') ? errorMsg : 'No se puede eliminar: el cliente tiene datos asociados'),
              backgroundColor: AppColors.warning,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  // ============================================================
  // ACCIONES DE LICENCIA (desde detalle de licencia)
  // ============================================================
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al activar: $e')),
        );
      }
    }
  }

  Future<void> _blockLicense(License license) async {
    setState(() => _loadingAction = true);
    try {
      await _licensesService.blockLicense(license.id);
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licencia bloqueada')),
        );
        await _viewLicenses();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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
          const SnackBar(content: Text('Licencia desbloqueada')),
        );
        await _viewLicenses();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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
        await _viewLicenses();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar', style: TextStyle(color: AppColors.error))),
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
          const SnackBar(content: Text('Licencia eliminada')),
        );
        await _viewLicenses();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAction = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          // Content
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
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
    if (_activeView == 'licenses') {
      return _buildLicensesView();
    }
    if (_activeView == 'license_detail' && _selectedLicense != null) {
      return _buildLicenseDetailView();
    }
    if (_activeView == 'create_license') {
      return _buildCreateLicenseView();
    }
    return _buildDetailView();
  }

  // ============================================================
  // VISTA: DETALLE DEL CLIENTE
  // ============================================================
  Widget _buildDetailView() {
    final customer = _currentCustomer!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  _initial,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Estado general badge
          Center(
            child: StatusBadge.fromString(
              customer.hasActiveLicense
                  ? 'Activa'
                  : customer.hasLicense
                      ? (customer.licenseStatus ?? 'Inactiva')
                      : 'Sin licencia',
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Información del cliente
          _detailSection('Información del cliente', [
            _detailRow('Negocio', customer.nombreNegocio),
            if (customer.contactoNombre != null) _detailRow('Contacto', customer.contactoNombre!),
            if (customer.contactoTelefono != null) _detailRow('Teléfono', customer.contactoTelefono!),
            if (customer.contactoEmail != null) _detailRow('Email', customer.contactoEmail!),
            if (customer.rolNegocio != null) _detailRow('Rol', customer.rolNegocio!),
          ]),
          const SizedBox(height: AppSpacing.md),

          // Licencia principal
          _detailSection('Licencia principal', [
            _detailRow('Estado', customer.hasActiveLicense ? 'Activa' : customer.hasLicense ? (customer.licenseStatus ?? 'Inactiva') : 'Sin licencia'),
            if (customer.licenseTipo != null) _detailRow('Tipo', customer.licenseTipo!),
          ]),
          if (customer.hasActiveLicense)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                    SizedBox(width: AppSpacing.sm),
                    Text('Licencia activa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),

          // IDs del sistema
          _detailSection('IDs del sistema', [
            _IdRow(label: 'Client ID', value: customer.id),
            _IdRow(
              label: 'Business ID',
              value: customer.businessId ?? '—',
              onCopy: customer.businessId != null ? () => Clipboard.setData(ClipboardData(text: customer.businessId!)) : null,
            ),
            if (customer.createdAt != null)
              _detailRow('Registro', DateFormat('dd/MM/yyyy HH:mm').format(customer.createdAt!.toLocal())),
          ]),
          const SizedBox(height: AppSpacing.lg),

          // Acciones principales
          const Text('Acciones', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: AppSpacing.sm),

          _actionBtn('Crear licencia', Icons.add_circle_outline_rounded, AppColors.primary, _createLicense),
          _actionBtn('Ver licencias', Icons.vpn_key_outlined, AppColors.info, _viewLicenses),
          _actionBtn('Asignar Business ID', Icons.link_rounded, AppColors.textSecondary, _assignBusinessId),
          _actionBtn('Token reset', Icons.restart_alt_rounded, AppColors.textSecondary, _resetToken),
          _actionBtn('Editar cliente', Icons.edit_outlined, AppColors.primary, _editCustomer),
          _actionBtn('Vista completa', Icons.open_in_new_rounded, AppColors.textSecondary, _viewFullDetail),
          if (widget.onDelete != null)
            _actionBtn('Eliminar cliente', Icons.delete_outline_rounded, AppColors.error, _deleteCustomer, isDestructive: true),
        ],
      ),
    );
  }

  // ============================================================
  // VISTA: LICENCIAS DEL CLIENTE
  // ============================================================
  Widget _buildLicensesView() {
    if (_loadingLicenses) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorLicenses != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.error),
              const SizedBox(height: 8),
              Text(_errorLicenses!, style: const TextStyle(color: AppColors.error, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _viewLicenses, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    if (_licenses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.vpn_key_off_rounded, size: 40, color: AppColors.textMuted),
              const SizedBox(height: 8),
              const Text(
                'Este cliente no tiene licencias todavía.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _createLicense,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Crear licencia'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _licenses.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final license = _licenses[i];
        final dateFmt = DateFormat('dd/MM/yyyy');
        return InkWell(
          onTap: () {
            setState(() {
              _selectedLicense = license;
              _activeView = 'license_detail';
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: _selectedLicense?.id == license.id ? AppColors.primaryLight : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _selectedLicense?.id == license.id ? AppColors.primary : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.vpn_key_rounded, size: 16, color: _selectedLicense?.id == license.id ? Colors.white : AppColors.textMuted),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              license.displayProjectName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (license.status != null) StatusBadge.fromString(license.status!),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            license.shortKey,
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace'),
                          ),
                          if (license.expiresAt != null) ...[
                            const Text(' · ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            Text(
                              'Vence ${dateFmt.format(license.expiresAt!.toLocal())}',
                              style: TextStyle(
                                fontSize: 11,
                                color: license.isExpired ? AppColors.error : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // VISTA: DETALLE DE LICENCIA
  // ============================================================
  Widget _buildLicenseDetailView() {
    final license = _selectedLicense!;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // License Key
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('License Key', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        if (license.licenseKey != null) {
                          Clipboard.setData(ClipboardData(text: license.licenseKey!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('License key copiada')),
                          );
                        }
                      },
                      child: const Icon(Icons.copy_rounded, size: 14, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  license.licenseKey ?? '—',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Información
          _detailSection('Información', [
            if (license.customerName != null) _detailRow('Cliente', license.customerName!),
            _detailRow('Sistema', license.displayProjectName),
            if (license.licenseType != null) _detailRow('Tipo', license.licenseType!),
            if (license.status != null) _detailRow('Estado', license.status!),
            if (license.activatedAt != null) _detailRow('Inicio', dateFmt.format(license.activatedAt!.toLocal())),
            if (license.expiresAt != null)
              _detailRow('Vencimiento', dateFmt.format(license.expiresAt!.toLocal()), highlight: license.isExpired),
            if (license.expiresAt != null)
              _detailRow('Días restantes', _daysRemainingText(license.expiresAt!), highlight: _isExpired(license.expiresAt!)),
            if (license.maxDevices != null) _detailRow('Máx. dispositivos', license.maxDevices!.toString()),
            if (license.createdAt != null) _detailRow('Creada', dateFmt.format(license.createdAt!.toLocal())),
            if (license.notes != null && license.notes!.isNotEmpty) _detailRow('Notas', license.notes!),
          ]),
          const SizedBox(height: AppSpacing.lg),

          // Acciones
          const Text('Acciones', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: AppSpacing.sm),

          if (license.canActivate)
            _actionBtn('Activar licencia', Icons.check_circle_outline_rounded, AppColors.success, () => _activateLicense(license)),
          if (!license.isBlocked && !license.isPending)
            _actionBtn('Bloquear', Icons.block_rounded, AppColors.warning, () => _blockLicense(license)),
          if (license.isBlocked)
            _actionBtn('Desbloquear', Icons.lock_open_outlined, AppColors.primary, () => _unblockLicense(license)),
          _actionBtn('Extender 30 días', Icons.calendar_month_outlined, AppColors.info, () => _extendLicense(license, 30)),
          _actionBtn('Eliminar licencia', Icons.delete_outline_rounded, AppColors.error, () => _deleteLicense(license), isDestructive: true),
        ],
      ),
    );
  }

  // ============================================================
  // VISTA: CREAR LICENCIA
  // ============================================================
  Widget _buildCreateLicenseView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Crear licencia para ${_currentCustomer!.nombreNegocio}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.md),
          LicenseFormPanel(
            customers: [_currentCustomer!],
            projects: _projects,
            loading: _loadingAction,
            projectsLoading: _projectsLoading,
            onSubmit: _submitCreateLicense,
            onClose: () => setState(() => _activeView = null),
            initialValues: LicenseFormValues(
              customerId: _currentCustomer!.id,
              tipo: 'FULL',
              diasValidez: 30,
              autoActivate: true,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================
  Widget _detailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value, {bool mono = false, bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: highlight ? AppColors.error : AppColors.textPrimary,
                fontFamily: mono ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _daysRemainingText(DateTime expiresAt) {
    final days = expiresAt.difference(DateTime.now()).inDays;
    if (days < 0) return 'Vencida';
    if (days == 0) return 'Hoy';
    return '$days días';
  }

  bool _isExpired(DateTime expiresAt) {
    return expiresAt.isBefore(DateTime.now());
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap, {bool isDestructive = false}) {
    final effectiveColor = isDestructive ? AppColors.error : color;
    return InkWell(
      onTap: _loadingAction ? null : onTap,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
        child: Row(
          children: [
            if (_loadingAction)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(icon, size: 16, color: effectiveColor),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: TextStyle(fontSize: 13, color: effectiveColor)),
          ],
        ),
      ),
    );
  }
}

class _IdRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const _IdRow({required this.label, required this.value, this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onCopy != null)
            InkWell(
              onTap: onCopy,
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.copy_rounded, size: 14, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
