import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/customer.dart';
import '../services/customers_service.dart';
import '../widgets/customer_detail_drawer.dart';
import '../widgets/customer_list_item.dart';

/// Página de clientes rediseñada con estilo premium
class CustomersPage extends StatefulWidget {
  final String? initialCustomerId;

  const CustomersPage({super.key, this.initialCustomerId});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  late final CustomersService _service;
  late Future<List<Customer>> _future;
  final _searchCtrl = TextEditingController();
  Customer? _selected;
  String _query = '';
  String _licenseFilter = 'TODOS';
  bool _initialSelectionDone = false;

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1000;

  @override
  void initState() {
    super.initState();
    _service = CustomersService(sessionManager: context.read<SessionManager>());
    _future = _service.listCustomers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialSelectionDone && widget.initialCustomerId != null) {
      _initialSelectionDone = true;
      _future.then((customers) {
        if (!mounted) return;
        final found = customers.where(
          (c) => c.id == widget.initialCustomerId,
        ).firstOrNull;
        if (found != null) {
          setState(() => _selected = found);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _selected = null;
      _future = _service.listCustomers();
    });
  }

  Future<void> _deleteCustomerConfirmed(Customer c) async {
    await _service.deleteCustomer(c.id);
    if (!mounted) return;
    setState(() => _selected = null);
    _refresh();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cliente eliminado')));
  }

  List<Customer> _filtered(List<Customer> all) {
    var out = all;
    if (_licenseFilter != 'TODOS') {
      out = out.where((c) {
        final status = (c.licenseStatus ?? '').toUpperCase();
        final commercial = (c.commercialStatus ?? '').toUpperCase();
        if (_licenseFilter == 'COMPRARON') return c.hasFullLicense;
        if (_licenseFilter == 'NO_COMPRARON') return !c.hasFullLicense;
        if (_licenseFilter == 'SOLO_DEMO') {
          return commercial == 'DEMO_ACTIVA' || commercial == 'SOLO_DEMO';
        }
        if (_licenseFilter == 'CLIENTE_ACTIVO') return commercial == 'CLIENTE_ACTIVO';
        if (_licenseFilter == 'CLIENTE_VENCIDO') return commercial == 'CLIENTE_VENCIDO';
        if (_licenseFilter == 'CLIENTE_BLOQUEADO') return commercial == 'CLIENTE_BLOQUEADO';
        if (_licenseFilter == 'SIN_LICENCIA') return !c.hasLicense;
        if (_licenseFilter == 'ACTIVA') return status == 'ACTIVA';
        if (_licenseFilter == 'VENCIDA') return status == 'VENCIDA';
        if (_licenseFilter == 'BLOQUEADA') return status == 'BLOQUEADA';
        if (_licenseFilter == 'PENDIENTE') return status == 'PENDIENTE';
        return true;
      }).toList();
    }

    if (_query.isEmpty) return out;
    final q = _query.toLowerCase();
    return out.where((c) {
      return c.nombreNegocio.toLowerCase().contains(q) ||
          (c.contactoNombre?.toLowerCase().contains(q) ?? false) ||
          (c.contactoTelefono?.contains(q) ?? false) ||
          (c.contactoEmail?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _deleteCustomer(Customer c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text(
          '¿Eliminar a "${c.nombreNegocio}"? Esta acción no se puede deshacer.',
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
    try {
      await _deleteCustomerConfirmed(c);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _openDetailMobile(Customer customer) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog.fullscreen(
        child: CustomerDetailDrawer(
          customer: customer,
          width: double.infinity,
          onClose: () => Navigator.of(context).pop(),
          onDelete: () {
            if (!mounted) return;
            Navigator.of(context).pop();
            setState(() => _selected = null);
            _refresh();
          },
          onUpdated: _refresh,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<List<Customer>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView(message: 'Cargando clientes...');
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final all = snapshot.data ?? [];
          final filtered = _filtered(all);

          return Row(
            children: [
              // List panel
              Expanded(
                child: Column(
                  children: [
                    // Toolbar premium
                    _buildToolbar(filtered.length),
                    // List
                    Expanded(
                      child: filtered.isEmpty
                          ? EmptyState(
                              title: _query.isEmpty
                                  ? 'Sin clientes'
                                  : 'Sin resultados',
                              subtitle: _query.isEmpty
                                  ? 'Aún no hay clientes registrados'
                                  : 'Intenta con otra búsqueda',
                              icon: Icons.people_outline_rounded,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: filtered.length,
                              separatorBuilder: (context, _) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (_, i) {
                                final c = filtered[i];
                                return CustomerListItem(
                                  customer: c,
                                  isSelected: _selected?.id == c.id,
                                  onTap: () async {
                                    if (_isDesktop) {
                                      setState(() => _selected = c);
                                    } else {
                                      setState(() => _selected = c);
                                      await _openDetailMobile(c);
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              // Detail panel (desktop)
              if (_isDesktop && _selected != null)
                CustomerDetailDrawer(
                  key: ValueKey(_selected!.id),
                  customer: _selected!,
                  onClose: () => setState(() => _selected = null),
                  onDelete: () {
                    if (!mounted) return;
                    setState(() => _selected = null);
                    _refresh();
                  },
                  onUpdated: _refresh,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar(int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          bottom: BorderSide(color: AppColors.border),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Search
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar cliente...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    borderSide: BorderSide(
                      color: AppColors.border.withOpacity(0.7),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
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
          const SizedBox(width: AppSpacing.sm),
          // Filter
          PopupMenuButton<String>(
            tooltip: 'Filtro licencia',
            onSelected: (v) => setState(() => _licenseFilter = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'TODOS',
                child: Text('Todos los clientes'),
              ),
              PopupMenuItem(
                value: 'COMPRARON',
                child: Text('Compraron'),
              ),
              PopupMenuItem(
                value: 'NO_COMPRARON',
                child: Text('No compraron'),
              ),
              PopupMenuItem(
                value: 'SOLO_DEMO',
                child: Text('Solo demo'),
              ),
              PopupMenuItem(
                value: 'CLIENTE_ACTIVO',
                child: Text('Cliente activo'),
              ),
              PopupMenuItem(
                value: 'CLIENTE_VENCIDO',
                child: Text('Cliente vencido'),
              ),
              PopupMenuItem(
                value: 'CLIENTE_BLOQUEADO',
                child: Text('Cliente bloqueado'),
              ),
              PopupMenuItem(
                value: 'ACTIVA',
                child: Text('Licencia activa'),
              ),
              PopupMenuItem(
                value: 'VENCIDA',
                child: Text('Licencia vencida'),
              ),
              PopupMenuItem(
                value: 'BLOQUEADA',
                child: Text('Licencia bloqueada'),
              ),
              PopupMenuItem(
                value: 'PENDIENTE',
                child: Text('Licencia pendiente'),
              ),
              PopupMenuItem(
                value: 'SIN_LICENCIA',
                child: Text('Sin licencia'),
              ),
            ],
            icon: const Icon(Icons.filter_list_rounded, size: 20),
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppColors.border),
            ),
          ),
          const SizedBox(width: 4),
          // Refresh
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _refresh,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
