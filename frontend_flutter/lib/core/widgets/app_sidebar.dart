import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class AppSidebarItem {
  final String label;
  final IconData icon;
  final String route;

  const AppSidebarItem({
    required this.label,
    required this.icon,
    required this.route,
  });
}

const List<AppSidebarItem> sidebarItems = [
  AppSidebarItem(
    label: 'Panel',
    icon: Icons.dashboard_outlined,
    route: '/admin/panel',
  ),
  AppSidebarItem(
    label: 'Clientes',
    icon: Icons.people_outline_rounded,
    route: '/admin/clientes',
  ),
  AppSidebarItem(
    label: 'Licencias',
    icon: Icons.vpn_key_outlined,
    route: '/admin/licencias',
  ),
  AppSidebarItem(
    label: 'Activaciones',
    icon: Icons.devices_other_outlined,
    route: '/admin/activaciones',
  ),
  AppSidebarItem(
    label: 'Proyectos',
    icon: Icons.folder_copy_outlined,
    route: '/admin/proyectos',
  ),
  AppSidebarItem(
    label: 'Productos',
    icon: Icons.inventory_2_outlined,
    route: '/admin/productos',
  ),
  AppSidebarItem(
    label: 'Gestión planes',
    icon: Icons.layers_outlined,
    route: '/admin/planes',
  ),
  AppSidebarItem(
    label: 'Suscripciones',
    icon: Icons.subscriptions_outlined,
    route: '/admin/suscripciones',
  ),
  AppSidebarItem(
    label: 'Pagos',
    icon: Icons.payments_outlined,
    route: '/admin/pagos',
  ),
];

const List<AppSidebarItem> settingsSidebarItems = [
  AppSidebarItem(
    label: 'Configuración licencias',
    icon: Icons.tune_rounded,
    route: '/admin/configuracion-licencias',
  ),
  AppSidebarItem(
    label: 'Configuración tienda',
    icon: Icons.store_outlined,
    route: '/admin/configuracion-tienda',
  ),
  AppSidebarItem(
    label: 'Usuarios del sistema',
    icon: Icons.admin_panel_settings_outlined,
    route: '/admin/usuarios',
  ),
];

class AppSidebar extends StatelessWidget {
  final String currentRoute;
  final VoidCallback? onItemTap;

  const AppSidebar({super.key, required this.currentRoute, this.onItemTap});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return Container(
      width: AppSpacing.sidebarWidth,
      color: AppColors.sidebarBg,
      child: Column(
        children: [
          // Header
          Container(
            height: AppSpacing.appBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  color: AppColors.sidebarActive,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text(
                  'Appyra Admin',
                  style: TextStyle(
                    color: AppColors.sidebarActiveText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          // Nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: sidebarItems.map((item) {
                final isActive = currentRoute.startsWith(item.route);
                return _SidebarTile(
                  item: item,
                  isActive: isActive,
                  onTap: () {
                    onItemTap?.call();
                    context.go(item.route);
                  },
                );
              }).toList(),
            ),
          ),
          _SettingsSection(currentRoute: currentRoute, onItemTap: onItemTap),
          // Footer
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_circle_outlined,
                  color: AppColors.sidebarText,
                  size: 18,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    auth.username,
                    style: const TextStyle(
                      color: AppColors.sidebarText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Cerrar sesión'),
                        content: const Text(
                          '¿Estás seguro que deseas cerrar sesión?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Salir'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await context.read<AuthService>().logout();
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.logout_rounded,
                      color: AppColors.sidebarText,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatefulWidget {
  final String currentRoute;
  final VoidCallback? onItemTap;

  const _SettingsSection({required this.currentRoute, this.onItemTap});

  @override
  State<_SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<_SettingsSection> {
  late bool _expanded;
  bool _hovered = false;

  bool get _hasActiveChild => settingsSidebarItems.any(
    (item) => widget.currentRoute.startsWith(item.route),
  );

  @override
  void initState() {
    super.initState();
    _expanded = _hasActiveChild;
  }

  @override
  void didUpdateWidget(covariant _SettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRoute != widget.currentRoute && _hasActiveChild) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _hasActiveChild;
    final bg = isActive
        ? AppColors.sidebarActive
        : _hovered
        ? AppColors.sidebarHover
        : Colors.transparent;
    final fg = isActive ? AppColors.sidebarActiveText : AppColors.sidebarText;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF334155))),
      ),
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Column(
        children: [
          MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 1,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 16, color: fg),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Configuración',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: fg,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 18,
                      color: fg,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 140),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              children: settingsSidebarItems.map((item) {
                final isChildActive = widget.currentRoute.startsWith(
                  item.route,
                );
                return _SidebarTile(
                  item: item,
                  isActive: isChildActive,
                  indent: AppSpacing.lg,
                  onTap: () {
                    widget.onItemTap?.call();
                    context.go(item.route);
                  },
                );
              }).toList(),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  final AppSidebarItem item;
  final bool isActive;
  final VoidCallback onTap;
  final double indent;

  const _SidebarTile({
    required this.item,
    required this.isActive,
    required this.onTap,
    this.indent = 0,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isActive
        ? AppColors.sidebarActive
        : _hovered
        ? AppColors.sidebarHover
        : Colors.transparent;
    final fg = widget.isActive
        ? AppColors.sidebarActiveText
        : AppColors.sidebarText;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 1,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 9,
          ).copyWith(left: AppSpacing.md + widget.indent),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(widget.item.icon, size: 16, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  widget.item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.isActive
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: fg,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
