import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/layout/app_shell_actions.dart';
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
  final _searchFocusNode = FocusNode();
  String _query = '';
  String _estadoFiltro = 'TODAS';
  License? _selected;

  bool _showCreatePanel = false;
  bool _editingLicense = false;
  bool _creating = false;
  AppShellActionsController? _shellActionsController;
  bool? _shellActionsMobile;
  bool _showSearch = false;

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
        final found = licenses
            .where((l) => l.id == widget.initialLicenseId)
            .toList();
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shellActionsController = AppShellActionsScope.maybeOf(context);
    _syncShellActions();
  }

  @override
  void dispose() {
    _shellActionsController?.clear();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _syncShellActions() {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    if (_shellActionsMobile == isMobile) return;
    _shellActionsMobile = isMobile;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _shellActionsController;
      if (controller == null) return;
      if (!isMobile) {
        controller.clear();
        return;
      }
      controller.setActions([
        AppShellAction(
          icon: Icons.search_rounded,
          label: 'Buscar',
          onTap: _toggleSearch,
        ),
        AppShellAction(
          icon: Icons.filter_list_rounded,
          label: 'Filtrar',
          onTap: _showFilterMenu,
        ),
        AppShellAction(
          icon: Icons.refresh_rounded,
          label: 'Recargar',
          onTap: _refresh,
        ),
        AppShellAction(
          icon: Icons.add_rounded,
          label: 'Nueva licencia',
          onTap: _openCreateMobile,
        ),
      ]);
    });
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (_showSearch) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      } else {
        _query = '';
        _searchCtrl.clear();
      }
    });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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

  Future<void> _editLicenseFromList(License license) async {
    if (_isDesktop) {
      _openEditLicense(license);
      return;
    }
    await _openEditMobile(license);
  }

  Future<void> _openEditMobile(License license) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        child: SafeArea(
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
              Navigator.of(ctx).pop();
              setState(() => _selected = license);
              await _updateLicense(values);
            },
            onClose: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateMobile() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        child: SafeArea(
          child: LicenseFormPanel(
            customers: _customers,
            projects: _projects,
            loading: _creating,
            projectsLoading: _projectsLoading,
            onSubmit: (values) async {
              Navigator.of(ctx).pop();
              await _createLicense(values);
            },
            onClose: () => Navigator.of(ctx).pop(),
          ),
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
          '¿Eliminar esta licencia? Esta acción no se puede deshacer.',
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

    if (ok != true) return;

    try {
      await _licensesService.deleteLicense(selected.id);
      if (mounted) {
        setState(() => _selected = null);
        _refresh();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Licencia eliminada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
                    _DialogRow(
                      'Vencimiento',
                      DateFormat(
                        'dd/MM/yyyy',
                      ).format(license.expiresAt!.toLocal()),
                    ),
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
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }

  void _viewCustomer(String customerId) {
    context.go('/admin/clientes?customerId=$customerId');
  }

  /// Descarga el archivo de licencia usando file_picker (Windows/Desktop) o
  /// fallback a descarga directa por API.
  /// El archivo se descarga con extensión .fulllicense.
  Future<void> _downloadLicense(License license) async {
    try {
      debugPrint(
        '[LICENSE_DOWNLOAD] Iniciando descarga para licencia: ${license.id}',
      );

      // Obtener el contenido del archivo de licencia desde el API
      final data = await _licensesService.downloadLicenseFile(license.id);
      if (!mounted) return;

      debugPrint('[LICENSE_DOWNLOAD] Datos recibidos correctamente');

      final content = const JsonEncoder.withIndent('  ').convert(data);

      // Determinar nombre del archivo desde el contenido o generar uno por defecto
      String fileName;
      try {
        final projectCode =
            (data['license']?['project_code'] as String?) ??
            (data['payload']?['project_code'] as String?) ??
            license.projectName?.toUpperCase().replaceAll(' ', '_') ??
            'LICENSE';
        final keyShort = license.shortKey;
        final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
        fileName = '${projectCode}_${keyShort}_$dateStr.fulllicense';
      } catch (_) {
        fileName = 'licencia_${license.shortKey}.fulllicense';
      }

      debugPrint('[LICENSE_DOWNLOAD] Nombre de archivo: $fileName');

      // Usar file_picker para guardar el archivo (funciona en Windows, Linux, macOS)
      // FilePicker.saveFile() es un método estático en file_picker 11.x
      try {
        final outputPath = await FilePicker.saveFile(
          dialogTitle: 'Guardar archivo de licencia',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['fulllicense'],
        );

        if (outputPath == null) {
          debugPrint('[LICENSE_DOWNLOAD] Usuario canceló la descarga');
          return;
        }

        debugPrint('[LICENSE_DOWNLOAD] Guardando en: $outputPath');
        final file = File(outputPath);
        await file.writeAsString(content, flush: true);
        debugPrint('[LICENSE_DOWNLOAD] Archivo guardado exitosamente');
      } catch (pickerError) {
        // Fallback: si file_picker no funciona (web), intentar con descarga directa
        debugPrint(
          '[LICENSE_DOWNLOAD] file_picker falló, usando fallback: $pickerError',
        );

        // Fallback para web: usar descarga directa desde el backend
        try {
          final rawResponse = await _licensesService.downloadLicenseFileRaw(
            license.id,
          );
          debugPrint(
            '[LICENSE_DOWNLOAD] Fallback: respuesta raw status=${rawResponse.statusCode}',
          );

          // Guardar usando file_picker de nuevo con los bytes
          final bytes = rawResponse.bodyBytes;
          final fallbackPath = await FilePicker.saveFile(
            dialogTitle: 'Guardar archivo de licencia',
            fileName: fileName,
            type: FileType.custom,
            allowedExtensions: ['fulllicense'],
          );

          if (fallbackPath != null) {
            final fallbackFile = File(fallbackPath);
            await fallbackFile.writeAsBytes(bytes, flush: true);
            debugPrint(
              '[LICENSE_DOWNLOAD] Fallback: archivo guardado en $fallbackPath',
            );
          } else {
            debugPrint('[LICENSE_DOWNLOAD] Fallback: usuario canceló');
            return;
          }
        } catch (fallbackError) {
          debugPrint(
            '[LICENSE_DOWNLOAD] Fallback también falló: $fallbackError',
          );
          rethrow;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Archivo de licencia descargado correctamente'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('[LICENSE_DOWNLOAD] ERROR: $e');
      debugPrint('[LICENSE_DOWNLOAD] STACK: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al descargar licencia: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openDetailMobile(License license) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog.fullscreen(
        child: SafeArea(
          child: LicenseDetailPanel(
            license: license,
            onClose: () {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
            },
            onEdit: () async {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
              await _openEditMobile(license);
            },
            onActivate: () => _activateLicenseWithConfirmation(license),
            onBlock: () => _licensesService.blockLicense(license.id),
            onUnblock: () => _licensesService.unblockLicense(license.id),
            onExtend: (d) => _licensesService.extendDays(license.id, d),
            onDelete: () async {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
              await _deleteSelected();
            },
            onViewCustomer: license.customerId != null
                ? () {
                    if (Navigator.of(dialogContext).canPop()) {
                      Navigator.of(dialogContext).pop();
                    }
                    _viewCustomer(license.customerId!);
                  }
                : null,
            onDownloadLicense: () => _downloadLicense(license),
          ),
        ),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    _syncShellActions();
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: _openCreateMobile,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.add_rounded, size: 28),
            )
          : null,
      body: FutureBuilder<List<License>>(
        future: _licensesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView(message: 'Cargando licencias...');
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final all = snapshot.data ?? [];
          final licenses = _filtered(all);
          final isMobile = MediaQuery.sizeOf(context).width < 600;

          return Column(
            children: [
              // Search bar inline (solo cuando se activa)
              if (_showSearch && isMobile) _buildSearchBar(),
              // Info bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                color: AppColors.surfaceVariant,
                child: Row(
                  children: [
                    Text(
                      '${licenses.length} licencia${licenses.length != 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Filtro: ${_estadoFiltro == 'TODAS' ? 'Todas' : _estadoFiltro}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // List
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: licenses.isEmpty
                          ? const EmptyState(
                              title: 'Sin licencias',
                              subtitle: 'No hay licencias para mostrar',
                              icon: Icons.vpn_key_off_rounded,
                            )
                          : ListView.separated(
                              padding: EdgeInsets.only(
                                bottom: isMobile ? 28 : 0,
                              ),
                              itemCount: licenses.length,
                              separatorBuilder: (context, _) => Divider(
                                height: isMobile ? 8 : 1,
                                color: isMobile
                                    ? Colors.transparent
                                    : AppColors.border,
                              ),
                              itemBuilder: (_, i) {
                                final license = licenses[i];
                                return LicenseListItem(
                                  license: license,
                                  isSelected: _selected?.id == license.id,
                                  onEdit: () => _editLicenseFromList(license),
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
                          projectCode: _selected!.raw?['project_code']
                              ?.toString(),
                          projectName: _selected!.projectName,
                          tipo: _selected!.licenseType ?? 'FULL',
                          diasValidez:
                              int.tryParse(
                                _selected!.raw?['dias_validez']?.toString() ??
                                    '',
                              ) ??
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
                        onActivate: () =>
                            _activateLicenseWithConfirmation(_selected!),
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
                        onDownloadLicense: () => _downloadLicense(_selected!),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchCtrl,
                focusNode: _searchFocusNode,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Buscar licencia...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleSearch,
              borderRadius: BorderRadius.circular(10),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterMenu() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filtros',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation1, animation2) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final screenWidth = MediaQuery.of(context).size.width;
        final drawerWidth = screenWidth.clamp(280.0, 340.0).toDouble();
        final offset = drawerWidth * (1 - animation.value);
        return Stack(
          children: [
            // Fondo semitransparente
            if (animation.value > 0)
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(color: Colors.black38),
              ),
            // Drawer lateral derecho
            Transform.translate(
              offset: Offset(offset, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: drawerWidth,
                  height: double.infinity,
                  child: Material(
                    color: AppColors.surface,
                    elevation: 8,
                    surfaceTintColor: Colors.transparent,
                    child: SafeArea(
                      child: Column(
                        children: [
                          // Header del drawer
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              border: const Border(
                                bottom: BorderSide(color: AppColors.border),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.filter_list_rounded,
                                  size: 20,
                                  color: AppColors.textPrimary,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Filtrar licencias',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => Navigator.of(context).pop(),
                                    borderRadius: BorderRadius.circular(10),
                                    child: const SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 20,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Lista de filtros
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              children: [
                                _filterTile(
                                  icon: Icons.vpn_key_rounded,
                                  label: 'Todas las licencias',
                                  value: 'TODAS',
                                  selected: _estadoFiltro == 'TODAS',
                                  onTap: () {
                                    setState(() => _estadoFiltro = 'TODAS');
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterSectionTitle(title: 'ESTADO'),
                                _filterTile(
                                  icon: Icons.check_circle_rounded,
                                  label: 'Activa',
                                  value: 'ACTIVA',
                                  selected: _estadoFiltro == 'ACTIVA',
                                  onTap: () {
                                    setState(() => _estadoFiltro = 'ACTIVA');
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.hourglass_empty_rounded,
                                  label: 'Inactiva / Pendiente',
                                  value: 'PENDIENTE',
                                  selected: _estadoFiltro == 'PENDIENTE',
                                  onTap: () {
                                    setState(() => _estadoFiltro = 'PENDIENTE');
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.error_outline_rounded,
                                  label: 'Vencida',
                                  value: 'VENCIDA',
                                  selected: _estadoFiltro == 'VENCIDA',
                                  onTap: () {
                                    setState(() => _estadoFiltro = 'VENCIDA');
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.science_rounded,
                                  label: 'Demo',
                                  value: 'DEMO',
                                  selected: _estadoFiltro == 'DEMO',
                                  onTap: () {
                                    setState(() => _estadoFiltro = 'DEMO');
                                    Navigator.of(context).pop();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Widget para un tile de filtro en el drawer
  Widget _filterTile({
    required IconData icon,
    required String label,
    required String value,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppColors.primaryLight : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Widget para título de sección en el drawer de filtros
  Widget _filterSectionTitle({required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 0.5,
        ),
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
