import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/layout/app_shell_actions.dart';
import '../../../core/theme/app_colors.dart';
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
  final _searchFocusNode = FocusNode();
  Customer? _selected;
  String _query = '';
  String _licenseFilter = 'TODOS';
  bool _initialSelectionDone = false;
  bool _showSearch = false;
  AppShellActionsController? _shellActionsController;
  bool? _shellActionsMobile;

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
    _shellActionsController = AppShellActionsScope.maybeOf(context);
    _syncShellActions();
    if (!_initialSelectionDone && widget.initialCustomerId != null) {
      _initialSelectionDone = true;
      _future.then((customers) {
        if (!mounted) return;
        final found = customers
            .where((c) => c.id == widget.initialCustomerId)
            .firstOrNull;
        if (found != null) {
          setState(() => _selected = found);
        }
      });
    }
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

  void _refresh() {
    setState(() {
      _selected = null;
      _future = _service.listCustomers();
    });
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
        if (_licenseFilter == 'CLIENTE_ACTIVO') {
          return commercial == 'CLIENTE_ACTIVO';
        }
        if (_licenseFilter == 'CLIENTE_VENCIDO') {
          return commercial == 'CLIENTE_VENCIDO';
        }
        if (_licenseFilter == 'CLIENTE_BLOQUEADO') {
          return commercial == 'CLIENTE_BLOQUEADO';
        }
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

  Future<void> _editCustomer(Customer customer) async {
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

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
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
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await _service.updateCustomer(customer.id, {
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
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(true);
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      );

      if (ok == true && mounted) {
        setState(() {
          _future = _service.listCustomers();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cliente actualizado correctamente')),
        );
      }
    } finally {
      nameCtrl.dispose();
      contactNameCtrl.dispose();
      phoneCtrl.dispose();
      emailCtrl.dispose();
      roleCtrl.dispose();
    }
  }

  Future<void> _openDetailMobile(Customer customer) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog.fullscreen(
        child: SafeArea(
          child: CustomerDetailDrawer(
            customer: customer,
            width: double.infinity,
            onClose: () {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
            },
            onDelete: () {
              if (!mounted) return;
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
              setState(() => _selected = null);
              _refresh();
            },
            onUpdated: _refresh,
          ),
        ),
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
                                    'Filtrar clientes',
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
                                  icon: Icons.people_rounded,
                                  label: 'Todos los clientes',
                                  value: 'TODOS',
                                  selected: _licenseFilter == 'TODOS',
                                  onTap: () {
                                    setState(() => _licenseFilter = 'TODOS');
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterSectionTitle(title: 'Estado comercial'),
                                _filterTile(
                                  icon: Icons.shopping_cart_rounded,
                                  label: 'Compraron',
                                  value: 'COMPRARON',
                                  selected: _licenseFilter == 'COMPRARON',
                                  onTap: () {
                                    setState(
                                      () => _licenseFilter = 'COMPRARON',
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.shopping_cart_outlined,
                                  label: 'No compraron',
                                  value: 'NO_COMPRARON',
                                  selected: _licenseFilter == 'NO_COMPRARON',
                                  onTap: () {
                                    setState(
                                      () => _licenseFilter = 'NO_COMPRARON',
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.science_rounded,
                                  label: 'Solo demo',
                                  value: 'SOLO_DEMO',
                                  selected: _licenseFilter == 'SOLO_DEMO',
                                  onTap: () {
                                    setState(
                                      () => _licenseFilter = 'SOLO_DEMO',
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.check_circle_rounded,
                                  label: 'Cliente activo',
                                  value: 'CLIENTE_ACTIVO',
                                  selected: _licenseFilter == 'CLIENTE_ACTIVO',
                                  onTap: () {
                                    setState(
                                      () => _licenseFilter = 'CLIENTE_ACTIVO',
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.error_outline_rounded,
                                  label: 'Cliente vencido',
                                  value: 'CLIENTE_VENCIDO',
                                  selected: _licenseFilter == 'CLIENTE_VENCIDO',
                                  onTap: () {
                                    setState(
                                      () => _licenseFilter = 'CLIENTE_VENCIDO',
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.block_rounded,
                                  label: 'Cliente bloqueado',
                                  value: 'CLIENTE_BLOQUEADO',
                                  selected:
                                      _licenseFilter == 'CLIENTE_BLOQUEADO',
                                  onTap: () {
                                    setState(
                                      () =>
                                          _licenseFilter = 'CLIENTE_BLOQUEADO',
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterSectionTitle(
                                  title: 'Estado de licencia',
                                ),
                                _filterTile(
                                  icon: Icons.vpn_key_rounded,
                                  label: 'Licencia activa',
                                  value: 'ACTIVA',
                                  selected: _licenseFilter == 'ACTIVA',
                                  onTap: () {
                                    setState(() => _licenseFilter = 'ACTIVA');
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.vpn_key_off_rounded,
                                  label: 'Licencia vencida',
                                  value: 'VENCIDA',
                                  selected: _licenseFilter == 'VENCIDA',
                                  onTap: () {
                                    setState(() => _licenseFilter = 'VENCIDA');
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.block_rounded,
                                  label: 'Licencia bloqueada',
                                  value: 'BLOQUEADA',
                                  selected: _licenseFilter == 'BLOQUEADA',
                                  onTap: () {
                                    setState(
                                      () => _licenseFilter = 'BLOQUEADA',
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.hourglass_empty_rounded,
                                  label: 'Licencia pendiente',
                                  value: 'PENDIENTE',
                                  selected: _licenseFilter == 'PENDIENTE',
                                  onTap: () {
                                    setState(
                                      () => _licenseFilter = 'PENDIENTE',
                                    );
                                    Navigator.of(context).pop();
                                  },
                                ),
                                _filterTile(
                                  icon: Icons.no_accounts_rounded,
                                  label: 'Sin licencia',
                                  value: 'SIN_LICENCIA',
                                  selected: _licenseFilter == 'SIN_LICENCIA',
                                  onTap: () {
                                    setState(
                                      () => _licenseFilter = 'SIN_LICENCIA',
                                    );
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

  @override
  Widget build(BuildContext context) {
    _syncShellActions();
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
          final isMobile = MediaQuery.sizeOf(context).width < 600;

          return Column(
            children: [
              // Search bar inline (solo cuando se activa)
              if (_showSearch && isMobile) _buildSearchBar(),
              // Content
              Expanded(
                child: Row(
                  children: [
                    // List panel
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
                              padding: EdgeInsets.fromLTRB(
                                isMobile ? 12 : 8,
                                isMobile ? 12 : 8,
                                isMobile ? 12 : 8,
                                isMobile ? 28 : 8,
                              ),
                              itemCount: filtered.length,
                              separatorBuilder: (context, _) =>
                                  SizedBox(height: isMobile ? 10 : 4),
                              itemBuilder: (_, i) {
                                final c = filtered[i];
                                return CustomerListItem(
                                  customer: c,
                                  isSelected: _selected?.id == c.id,
                                  onEdit: () => _editCustomer(c),
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
                ),
              ),
            ],
          );
        },
      ),
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
                  hintText: 'Buscar cliente...',
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
}
