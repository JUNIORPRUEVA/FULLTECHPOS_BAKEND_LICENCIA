import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

// ═══════════════════════════════════════════════════════════════
// MODELO DE ITEM DEL SIDEBAR
// ═══════════════════════════════════════════════════════════════
class AppSidebarItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;

  const AppSidebarItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
  });
}

const List<AppSidebarItem> sidebarItems = [
  AppSidebarItem(
    label: 'Panel',
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard_rounded,
    route: '/admin/panel',
  ),
  AppSidebarItem(
    label: 'Clientes',
    icon: Icons.people_outline_rounded,
    activeIcon: Icons.people_rounded,
    route: '/admin/clientes',
  ),
  AppSidebarItem(
    label: 'Licencias',
    icon: Icons.vpn_key_outlined,
    activeIcon: Icons.vpn_key_rounded,
    route: '/admin/licencias',
  ),
  AppSidebarItem(
    label: 'Proyectos',
    icon: Icons.folder_copy_outlined,
    activeIcon: Icons.folder_copy_rounded,
    route: '/admin/proyectos',
  ),
  AppSidebarItem(
    label: 'Pagos',
    icon: Icons.payments_outlined,
    activeIcon: Icons.payments_rounded,
    route: '/admin/pagos',
  ),
];

const List<AppSidebarItem> settingsSidebarItems = [
  AppSidebarItem(
    label: 'Usuarios',
    icon: Icons.admin_panel_settings_outlined,
    activeIcon: Icons.admin_panel_settings_rounded,
    route: '/admin/usuarios',
  ),
];

// ═══════════════════════════════════════════════════════════════
// SIDEBAR PRINCIPAL COLAPSABLE
// ═══════════════════════════════════════════════════════════════
class AppSidebar extends StatefulWidget {
  final String currentRoute;
  final VoidCallback? onItemTap;

  const AppSidebar({super.key, required this.currentRoute, this.onItemTap});

  @override
  State<AppSidebar> createState() => AppSidebarState();
}

class AppSidebarState extends State<AppSidebar>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _animCtrl;
  late Animation<double> _widthAnim;
  late Animation<double> _opacityAnim;

  bool get isExpanded => _expanded;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _widthAnim = Tween<double>(
      begin: AppSpacing.sidebarCollapsedWidth,
      end: AppSpacing.sidebarExpandedWidth,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeInOutCubic,
    ));
    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _animCtrl.forward();
      } else {
        _animCtrl.reverse();
      }
    });
  }

  void expand() {
    if (!_expanded) toggle();
  }

  void collapse() {
    if (_expanded) toggle();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return AnimatedBuilder(
      animation: _widthAnim,
      builder: (context, child) {
        return Container(
          width: _widthAnim.value,
          decoration: const BoxDecoration(
            color: AppColors.sidebarBg,
            border: Border(
              right: BorderSide(color: AppColors.sidebarBorder),
            ),
          ),
          child: Column(
            children: [
              // ── Header con toggle ──
              _buildHeader(),
              // ── Navegación ──
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    ...sidebarItems.map((item) {
                      final isActive =
                          widget.currentRoute.startsWith(item.route);
                      return _SidebarTile(
                        item: item,
                        isActive: isActive,
                        expanded: _expanded,
                        opacityAnim: _opacityAnim,
                        onTap: () {
                          widget.onItemTap?.call();
                          context.go(item.route);
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                    _SettingsSection(
                      currentRoute: widget.currentRoute,
                      expanded: _expanded,
                      opacityAnim: _opacityAnim,
                      onItemTap: widget.onItemTap,
                    ),
                  ],
                ),
              ),
              // ── Footer ──
              _buildFooter(auth),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      height: AppSpacing.appBarHeight,
      padding: EdgeInsets.symmetric(
        horizontal: _expanded ? 16 : 0,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.sidebarBorder),
        ),
      ),
      child: Row(
        mainAxisAlignment:
            _expanded ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
        children: [
          if (_expanded) ...[
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bolt_rounded,
                  color: AppColors.sidebarActive,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  'Appyra',
                  style: TextStyle(
                    color: AppColors.sidebarActiveText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ] else ...[
            const Icon(
              Icons.bolt_rounded,
              color: AppColors.sidebarActive,
              size: 22,
            ),
          ],
          // Toggle button
          if (_expanded)
            _ToggleButton(
              expanded: _expanded,
              onTap: toggle,
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(AuthService auth) {
    return Container(
      padding: EdgeInsets.all(_expanded ? 12 : 8),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.sidebarBorder),
        ),
      ),
      child: _expanded
          ? Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.sidebarActive.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      (auth.username.isNotEmpty
                              ? auth.username[0]
                              : 'U')
                          .toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.sidebarActiveText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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
                _LogoutButton(),
              ],
            )
          : Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.sidebarActive.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      (auth.username.isNotEmpty
                              ? auth.username[0]
                              : 'U')
                          .toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.sidebarActiveText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _LogoutButton(compact: true),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// BOTÓN TOGGLE
// ═══════════════════════════════════════════════════════════════
class _ToggleButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _ToggleButton({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 250),
            child: const Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: AppColors.sidebarText,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// BOTÓN LOGOUT
// ═══════════════════════════════════════════════════════════════
class _LogoutButton extends StatelessWidget {
  final bool compact;

  const _LogoutButton({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
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
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: EdgeInsets.all(compact ? 4 : 6),
          child: Icon(
            Icons.logout_rounded,
            size: compact ? 16 : 18,
            color: AppColors.sidebarText,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN CONFIGURACIÓN (colapsable)
// ═══════════════════════════════════════════════════════════════
class _SettingsSection extends StatefulWidget {
  final String currentRoute;
  final bool expanded;
  final Animation<double> opacityAnim;
  final VoidCallback? onItemTap;

  const _SettingsSection({
    required this.currentRoute,
    required this.expanded,
    required this.opacityAnim,
    this.onItemTap,
  });

  @override
  State<_SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<_SettingsSection> {
  bool _settingsExpanded = false;
  bool _hovered = false;

  bool get _hasActiveChild => settingsSidebarItems.any(
        (item) => widget.currentRoute.startsWith(item.route),
      );

  @override
  void initState() {
    super.initState();
    _settingsExpanded = _hasActiveChild;
  }

  @override
  void didUpdateWidget(covariant _SettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRoute != widget.currentRoute && _hasActiveChild) {
      _settingsExpanded = true;
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
    final fg = isActive
        ? AppColors.sidebarActiveText
        : AppColors.sidebarText;

    return Column(
      children: [
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: AppColors.sidebarBorder,
        ),
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () {
              if (widget.expanded) {
                setState(() => _settingsExpanded = !_settingsExpanded);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: widget.expanded ? 12 : 0,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: widget.expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.settings_outlined,
                    size: 18,
                    color: fg,
                  ),
                  if (widget.expanded) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FadeTransition(
                        opacity: widget.opacityAnim,
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
                    ),
                    Icon(
                      _settingsExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 18,
                      color: fg,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (widget.expanded)
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 140),
            crossFadeState: _settingsExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              children: settingsSidebarItems.map((item) {
                final isChildActive =
                    widget.currentRoute.startsWith(item.route);
                return _SidebarTile(
                  item: item,
                  isActive: isChildActive,
                  expanded: widget.expanded,
                  opacityAnim: widget.opacityAnim,
                  indent: 8,
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TILE DEL SIDEBAR
// ═══════════════════════════════════════════════════════════════
class _SidebarTile extends StatefulWidget {
  final AppSidebarItem item;
  final bool isActive;
  final bool expanded;
  final Animation<double> opacityAnim;
  final double indent;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.isActive,
    required this.expanded,
    required this.opacityAnim,
    this.indent = 0,
    required this.onTap,
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
    final iconColor = widget.isActive
        ? AppColors.sidebarIconActive
        : AppColors.sidebarIcon;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 2,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: widget.expanded ? 12 : 0,
            vertical: 10,
          ).copyWith(
            left: widget.expanded
                ? 12 + widget.indent
                : 0,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: widget.expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                widget.isActive ? widget.item.activeIcon : widget.item.icon,
                size: 18,
                color: iconColor,
              ),
              if (widget.expanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FadeTransition(
                    opacity: widget.opacityAnim,
                    child: Text(
                      widget.item.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: fg,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
