import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../customers/models/customer.dart';
import '../../customers/services/customers_service.dart';
import '../models/license.dart';
import '../services/licenses_service.dart';
import '../widgets/license_detail_panel.dart';
import '../widgets/license_form_panel.dart';
import '../widgets/license_list_item.dart';

class LicensesPage extends StatefulWidget {
  const LicensesPage({super.key});

  @override
  State<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<LicensesPage> {
  late final LicensesService _licensesService;
  late final CustomersService _customersService;

  late Future<List<License>> _licensesFuture;
  List<Customer> _customers = [];

  final _searchCtrl = TextEditingController();
  String _query = '';
  String _estadoFiltro = 'TODAS';
  License? _selected;

  bool _showCreatePanel = false;
  bool _creating = false;

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1000;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionManager>();
    _licensesService = LicensesService(sessionManager: session);
    _customersService = CustomersService(sessionManager: session);
    _licensesFuture = _licensesService.listLicenses();
    _loadCustomers();
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
            (l.licenseType ?? '').toLowerCase().contains(q);
      }).toList();
    }

    return out;
  }

  Future<void> _createLicense(LicenseFormValues values) async {
    setState(() => _creating = true);
    try {
      final body = {
        'customer_id': values.customerId,
        'tipo': values.tipo,
        'dias_validez': values.diasValidez,
        'max_dispositivos': 1,
        'auto_activate': values.autoActivate,
      };
      if (values.projectCode != null) body['project_code'] = values.projectCode!;
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

  Future<void> _deleteSelected() async {
    final selected = _selected;
    if (selected == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar licencia'),
        content: const Text('¿Eliminar esta licencia? Esta acción no se puede deshacer.'),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _openDetailMobile(License license) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog.fullscreen(
        child: LicenseDetailPanel(
          license: license,
          onClose: () => Navigator.of(context).pop(),
          onActivate: () => _licensesService.activateManual(license.id),
          onBlock: () => _licensesService.blockLicense(license.id),
          onUnblock: () => _licensesService.unblockLicense(license.id),
          onExtend: (d) => _licensesService.extendDays(license.id, d),
          onDelete: () async {
            Navigator.of(context).pop();
            await _deleteSelected();
          },
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
            return ErrorView(message: snapshot.error.toString(), onRetry: _refresh);
          }

          final all = snapshot.data ?? [];
          final licenses = _filtered(all);

          return Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        border: Border(bottom: BorderSide(color: AppColors.border)),
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
                                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(color: AppColors.primary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          IconButton(
                            icon: const Icon(Icons.more_vert_rounded, size: 18),
                            tooltip: 'Filtros',
                            onPressed: () async {
                              final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                              final selected = await showMenu<String>(
                                context: context,
                                position: RelativeRect.fromRect(
                                  Rect.fromLTWH(overlay.size.width - 160, 100, 100, 100),
                                  Offset.zero & overlay.size,
                                ),
                                items: const [
                                  PopupMenuItem(value: 'TODAS', child: Text('Todas')),
                                  PopupMenuItem(value: 'ACTIVA', child: Text('Activa')),
                                  PopupMenuItem(value: 'PENDIENTE', child: Text('Inactiva/Pendiente')),
                                  PopupMenuItem(value: 'VENCIDA', child: Text('Vencida')),
                                  PopupMenuItem(value: 'DEMO', child: Text('Demo')),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
                      color: AppColors.surfaceVariant,
                      child: Row(
                        children: [
                          Text(
                            '${licenses.length} licencia${licenses.length != 1 ? 's' : ''}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Filtro: ${_estadoFiltro == 'TODAS' ? 'Todas' : _estadoFiltro}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: licenses.isEmpty
                          ? const EmptyState(
                              title: 'Sin licencias',
                              subtitle: 'No hay licencias para mostrar',
                              icon: Icons.vpn_key_off_rounded,
                            )
                          : ListView.separated(
                              itemCount: licenses.length,
                              separatorBuilder: (context, _) => const Divider(height: 1),
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
              if (_isDesktop && _showCreatePanel)
                LicenseFormPanel(
                  customers: _customers,
                  loading: _creating,
                  onSubmit: _createLicense,
                  onClose: () => setState(() => _showCreatePanel = false),
                ),
              if (_isDesktop && !_showCreatePanel && _selected != null)
                LicenseDetailPanel(
                  key: ValueKey(_selected!.id),
                  license: _selected!,
                  onClose: () => setState(() => _selected = null),
                  onActivate: () => _actionAndRefresh(
                    () => _licensesService.activateManual(_selected!.id),
                  ),
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
                ),
            ],
          );
        },
      ),
    );
  }
}
