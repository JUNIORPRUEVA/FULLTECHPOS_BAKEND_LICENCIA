import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../auth/auth_service.dart';
import '../config/navigation_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

// ═══════════════════════════════════════════════════════════════
// MODELO DE ITEM DEL SIDEBAR
// ═══════════════════════════════════════════════════════════════

/// Categoría de visibilidad de un item de navegación.
///
/// Ver `docs/APPYRA_PROJECT_MODE.md`.
enum SidebarItemCategory {
  /// Navegación general de Appyra (siempre visible).
  general,

  /// Funcionalidad global preservada pero fuera del flujo normal en project
  /// mode (p. ej. el Panel global). NO es legacy: no está retirada.
  hiddenInProjectMode,

  /// Módulo global retirado de la navegación (LEGACY / HIDDEN). Su lógica
  /// sigue en el código y se moverá dentro de cada proyecto.
  legacyHidden,
}

class AppSidebarItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;

  /// Visibilidad del item en la navegación ([SidebarItemCategory]).
  ///
  /// Un item oculto conserva su ruta, pantalla, servicio y endpoints; solo
  /// deja de aparecer en la navegación general de Appyra.
  final SidebarItemCategory category;

  const AppSidebarItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
    this.category = SidebarItemCategory.general,
  });
}

/// Item del sidebar que puede tener sub-opciones (flyout)
class AppSidebarGroupItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final List<AppSidebarItem> children;

  /// Visibilidad del grupo en la navegación ([SidebarItemCategory]).
  final SidebarItemCategory category;

  const AppSidebarGroupItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.children,
    this.category = SidebarItemCategory.general,
  });
}

/// Registro completo de navegación de Appyra.
///
/// Este registro NO se recorta: refleja todos los módulos existentes para que
/// la navegación legacy pueda reactivarse con `LEGACY_MODULES_VISIBLE=true`.
/// Lo que se renderiza es [visibleSidebarItems].
const List<dynamic> sidebarItems = [
  // ── Global preservado, fuera del flujo normal en project mode ──
  // El Panel global NO se borra: ruta, pantalla, servicio y métricas siguen
  // intactos. Solo deja de mostrarse en la navegación normal.
  AppSidebarItem(
    label: 'Panel',
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard_rounded,
    route: '/admin/panel',
    category: SidebarItemCategory.hiddenInProjectMode,
  ),

  // ── Navegación principal de Appyra ────────────────────────────
  AppSidebarItem(
    label: 'Proyectos',
    icon: Icons.folder_copy_outlined,
    activeIcon: Icons.folder_copy_rounded,
    route: '/admin/proyectos',
  ),

  // ── Módulos LEGACY / HIDDEN ───────────────────────────────────
  // Ocultos por defecto. No borrar: rutas, pantallas, servicios, endpoints y
  // tablas siguen intactos (ver `docs/APPYRA_PROJECT_MODE.md`).
  AppSidebarGroupItem(
    label: 'Clientes',
    icon: Icons.people_outline_rounded,
    activeIcon: Icons.people_rounded,
    category: SidebarItemCategory.legacyHidden,
    children: [
      AppSidebarItem(
        label: 'Lista de Clientes',
        icon: Icons.list_alt_outlined,
        activeIcon: Icons.list_alt_rounded,
        route: '/admin/clientes',
        category: SidebarItemCategory.legacyHidden,
      ),
    ],
  ),
  AppSidebarItem(
    label: 'Licencias',
    icon: Icons.vpn_key_outlined,
    activeIcon: Icons.vpn_key_rounded,
    route: '/admin/licencias',
    category: SidebarItemCategory.legacyHidden,
  ),
  AppSidebarItem(
    label: 'DaleVentas Cloud',
    icon: Icons.cloud_done_outlined,
    activeIcon: Icons.cloud_done_rounded,
    route: '/admin/daleventas-licencias',
    category: SidebarItemCategory.legacyHidden,
  ),
  AppSidebarItem(
    label: 'Uso del sistema',
    icon: Icons.query_stats_outlined,
    activeIcon: Icons.query_stats_rounded,
    route: '/admin/uso',
    category: SidebarItemCategory.legacyHidden,
  ),
  AppSidebarItem(
    label: 'Pagos',
    icon: Icons.payments_outlined,
    activeIcon: Icons.payments_rounded,
    route: '/admin/pagos',
    category: SidebarItemCategory.legacyHidden,
  ),
];

/// Sub-opciones de la sección "Configuración" (alcance global de Appyra).
const List<AppSidebarItem> settingsSidebarItems = [
  AppSidebarItem(
    label: 'Usuarios',
    icon: Icons.admin_panel_settings_outlined,
    activeIcon: Icons.admin_panel_settings_rounded,
    route: '/admin/usuarios',
  ),
];

SidebarItemCategory _categoryOf(Object item) {
  if (item is AppSidebarGroupItem) return item.category;
  if (item is AppSidebarItem) return item.category;
  return SidebarItemCategory.general;
}

/// `true` cuando el item/grupo está clasificado como LEGACY / HIDDEN.
bool isLegacySidebarItem(Object item) =>
    _categoryOf(item) == SidebarItemCategory.legacyHidden;

/// `true` cuando el item está preservado pero oculto en project mode.
bool isProjectModeHiddenSidebarItem(Object item) =>
    _categoryOf(item) == SidebarItemCategory.hiddenInProjectMode;

/// Navegación principal que debe renderizarse según el modo actual de Appyra.
///
/// - project mode (por defecto): solo [SidebarItemCategory.general].
/// - `LEGACY_MODULES_VISIBLE=true`: registro completo (Panel + legacy).
List<dynamic> get visibleSidebarItems => NavigationConfig.showLegacyModules
    ? sidebarItems
    : sidebarItems
          .where((item) => _categoryOf(item) == SidebarItemCategory.general)
          .toList();

/// Sub-opciones de "Configuración" que deben renderizarse.
List<AppSidebarItem> get visibleSettingsSidebarItems =>
    NavigationConfig.showLegacyModules
    ? settingsSidebarItems
    : settingsSidebarItems
          .where((item) => item.category == SidebarItemCategory.general)
          .toList();

/// Rutas de los módulos legacy ocultos (independiente del flag).
///
/// Documenta/verifica que las rutas siguen declaradas aunque no se naveguen.
List<String> get legacySidebarRoutes {
  final routes = <String>[];
  for (final item in sidebarItems) {
    if (item is AppSidebarGroupItem) {
      routes.addAll(
        item.children
            .where((c) => c.category == SidebarItemCategory.legacyHidden)
            .map((c) => c.route),
      );
    } else if (item is AppSidebarItem &&
        item.category == SidebarItemCategory.legacyHidden) {
      routes.add(item.route);
    }
  }
  routes.addAll(
    settingsSidebarItems
        .where((i) => i.category == SidebarItemCategory.legacyHidden)
        .map((i) => i.route),
  );
  return routes;
}

/// Rutas preservadas pero ocultas en project mode (p. ej. el Panel global).
List<String> get projectModeHiddenSidebarRoutes {
  final routes = <String>[];
  for (final item in sidebarItems) {
    if (item is AppSidebarGroupItem) {
      if (item.category == SidebarItemCategory.hiddenInProjectMode) {
        routes.addAll(item.children.map((c) => c.route));
      }
    } else if (item is AppSidebarItem &&
        item.category == SidebarItemCategory.hiddenInProjectMode) {
      routes.add(item.route);
    }
  }
  routes.addAll(
    settingsSidebarItems
        .where((i) => i.category == SidebarItemCategory.hiddenInProjectMode)
        .map((i) => i.route),
  );
  return routes;
}

// ═══════════════════════════════════════════════════════════════
// SIDEBAR PRINCIPAL COLAPSABLE
// ═══════════════════════════════════════════════════════════════
class AppSidebar extends StatefulWidget {
  final String currentRoute;
  final VoidCallback? onItemTap;
  final bool forceExpanded;
  final bool mobile;

  const AppSidebar({
    super.key,
    required this.currentRoute,
    this.onItemTap,
    this.forceExpanded = false,
    this.mobile = false,
  });

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
    // Inicia colapsado por defecto (no se llama a forward)
    _widthAnim = Tween<double>(
      begin: AppSpacing.sidebarCollapsedWidth,
      end: AppSpacing.sidebarExpandedWidth,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOutCubic));
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
    final opacityAnim = widget.forceExpanded
        ? const AlwaysStoppedAnimation<double>(1)
        : _opacityAnim;
    return AnimatedBuilder(
      animation: _widthAnim,
      builder: (context, child) {
        final currentWidth = widget.forceExpanded
            ? AppSpacing.sidebarExpandedWidth
            : _widthAnim.value;
        final effectiveExpanded =
            widget.forceExpanded ||
            (_expanded && currentWidth >= AppSpacing.sidebarExpandedWidth - 24);
        return MouseRegion(
          onEnter: (_) {
            if (!widget.forceExpanded) expand();
          },
          onExit: (_) {
            if (!widget.forceExpanded) collapse();
          },
          child: Container(
            width: widget.forceExpanded ? double.infinity : currentWidth,
            decoration: const BoxDecoration(
              color: AppColors.sidebarBg,
              border: Border(right: BorderSide(color: AppColors.sidebarBorder)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 18,
                  offset: Offset(8, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // ── Header con toggle ──
                _buildHeader(effectiveExpanded),
                // ── Navegación principal (scrolleable) ──
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      ...visibleSidebarItems.map((item) {
                        if (item is AppSidebarGroupItem) {
                          return _SidebarGroupTile(
                            group: item,
                            currentRoute: widget.currentRoute,
                            expanded: effectiveExpanded,
                            mobile: widget.mobile,
                            opacityAnim: opacityAnim,
                            onItemTap: widget.onItemTap,
                          );
                        }
                        final sidebarItem = item as AppSidebarItem;
                        final isActive = widget.currentRoute.startsWith(
                          sidebarItem.route,
                        );
                        return _SidebarTile(
                          item: sidebarItem,
                          isActive: isActive,
                          expanded: effectiveExpanded,
                          mobile: widget.mobile,
                          opacityAnim: opacityAnim,
                          onTap: () {
                            widget.onItemTap?.call();
                            context.go(sidebarItem.route);
                          },
                        );
                      }),
                    ],
                  ),
                ),
                // ── Configuración (anclada al fondo del sidebar) ──
                if (visibleSettingsSidebarItems.isNotEmpty)
                  _SettingsSection(
                    currentRoute: widget.currentRoute,
                    expanded: effectiveExpanded,
                    mobile: widget.mobile,
                    opacityAnim: opacityAnim,
                    onItemTap: widget.onItemTap,
                  ),
                // ── Footer ──
                _buildFooter(effectiveExpanded),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool effectiveExpanded) {
    return Container(
      height: widget.mobile ? 78 : AppSpacing.appBarHeight,
      padding: EdgeInsets.symmetric(
        horizontal: effectiveExpanded ? (widget.mobile ? 20 : 16) : 0,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.sidebarBorder)),
      ),
      child: Row(
        mainAxisAlignment: effectiveExpanded
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.center,
        children: [
          if (effectiveExpanded) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  color: AppColors.sidebarActive,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  'Appyra',
                  style: TextStyle(
                    color: AppColors.sidebarActiveText,
                    fontSize: widget.mobile ? 18 : 15,
                    fontWeight: FontWeight.w700,
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
          if (_expanded && !widget.forceExpanded)
            _ToggleButton(expanded: _expanded, onTap: toggle),
        ],
      ),
    );
  }

  Widget _buildFooter(bool effectiveExpanded) {
    final auth = context.read<AuthService>();
    return Container(
      padding: EdgeInsets.all(
        effectiveExpanded ? (widget.mobile ? 16 : 12) : 8,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.sidebarBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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
                (auth.username.isNotEmpty ? auth.username[0] : 'U')
                    .toUpperCase(),
                style: const TextStyle(
                  color: AppColors.sidebarActiveText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (effectiveExpanded) ...[
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
          ],
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
              content: const Text('¿Estás seguro que deseas cerrar sesión?'),
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
// FLYOUT OVERLAY (menú emergente reutilizable)
// ═══════════════════════════════════════════════════════════════
class _FlyoutOverlay extends StatelessWidget {
  final Widget child;

  const _FlyoutOverlay({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      color: AppColors.sidebarBg,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 220),
        child: child,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TILE DE GRUPO CON FLYOUT (para sidebar colapsado)
// ═══════════════════════════════════════════════════════════════
class _SidebarGroupTile extends StatefulWidget {
  final AppSidebarGroupItem group;
  final String currentRoute;
  final bool expanded;
  final bool mobile;
  final Animation<double> opacityAnim;
  final VoidCallback? onItemTap;

  const _SidebarGroupTile({
    required this.group,
    required this.currentRoute,
    required this.expanded,
    this.mobile = false,
    required this.opacityAnim,
    this.onItemTap,
  });

  @override
  State<_SidebarGroupTile> createState() => _SidebarGroupTileState();
}

class _SidebarGroupTileState extends State<_SidebarGroupTile> {
  bool _hovered = false;
  bool _groupExpanded = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  bool get _hasActiveChild => widget.group.children.any(
    (item) => widget.currentRoute.startsWith(item.route),
  );

  @override
  void initState() {
    super.initState();
    _groupExpanded = _hasActiveChild;
  }

  @override
  void didUpdateWidget(covariant _SidebarGroupTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRoute != widget.currentRoute && _hasActiveChild) {
      _groupExpanded = true;
    }
    if (!oldWidget.expanded && widget.expanded && _hovered) {
      _groupExpanded = true;
    }
    if (oldWidget.expanded && !widget.expanded && !_hasActiveChild) {
      _groupExpanded = false;
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showFlyout(BuildContext context) {
    _removeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Fondo transparente para capturar taps y cerrar
          GestureDetector(
            onTap: () => _removeOverlay(),
            child: Container(color: Colors.transparent),
          ),
          // Flyout posicionado con CompositedTransformFollower
          Positioned(
            left: AppSpacing.sidebarCollapsedWidth + 4,
            top: _getTilePosition(context),
            child: _FlyoutOverlay(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header del flyout
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.sidebarActive.withOpacity(0.1),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.group.activeIcon,
                          size: 16,
                          color: AppColors.sidebarActiveText,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.group.label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.sidebarActiveText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Opciones del grupo
                  ...widget.group.children.map((item) {
                    final isChildActive = widget.currentRoute.startsWith(
                      item.route,
                    );
                    return _FlyoutItem(
                      item: item,
                      isActive: isChildActive,
                      onTap: () {
                        _removeOverlay();
                        widget.onItemTap?.call();
                        context.go(item.route);
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  double _getTilePosition(BuildContext context) {
    // Obtenemos la posición del RenderBox de este widget
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      return position.dy;
    }
    // Fallback: cálculo estimado
    final index = sidebarItems.indexOf(widget.group);
    return 56.0 + 8.0 + (index * 48.0);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _hasActiveChild;
    final showChildren = widget.expanded && (_groupExpanded || _hasActiveChild);
    final bg = isActive
        ? AppColors.sidebarActive
        : _hovered
        ? AppColors.sidebarHover
        : Colors.transparent;
    final fg = isActive
        ? AppColors.sidebarActiveText
        : widget.mobile
        ? const Color(0xFFE2E8F0)
        : AppColors.sidebarText;
    final iconColor = isActive
        ? AppColors.sidebarIconActive
        : AppColors.sidebarIcon;

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          setState(() {
            _hovered = true;
            if (widget.expanded) _groupExpanded = true;
          });
        },
        onExit: (_) {
          setState(() {
            _hovered = false;
            if (!_hasActiveChild) _groupExpanded = false;
          });
        },
        child: Column(
          children: [
            GestureDetector(
              onTap: () {
                if (widget.mobile && widget.group.children.length == 1) {
                  final child = widget.group.children.first;
                  widget.onItemTap?.call();
                  context.go(child.route);
                  return;
                }
                if (widget.expanded) {
                  setState(() => _groupExpanded = !_groupExpanded);
                } else {
                  _showFlyout(context);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                padding: EdgeInsets.symmetric(
                  horizontal: widget.expanded ? (widget.mobile ? 16 : 12) : 0,
                  vertical: widget.mobile ? 14 : 10,
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
                      isActive ? widget.group.activeIcon : widget.group.icon,
                      size: widget.mobile ? 22 : 18,
                      color: iconColor,
                    ),
                    if (widget.expanded) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FadeTransition(
                          opacity: widget.opacityAnim,
                          child: Text(
                            widget.group.label,
                            style: TextStyle(
                              fontSize: widget.mobile ? 15 : 13,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: fg,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (!widget.mobile || widget.group.children.length > 1)
                        Icon(
                          showChildren
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
            if (widget.expanded)
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 140),
                crossFadeState: showChildren
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Column(
                  children: widget.group.children.map((item) {
                    final isChildActive = widget.currentRoute.startsWith(
                      item.route,
                    );
                    return _SidebarTile(
                      item: item,
                      isActive: isChildActive,
                      expanded: widget.expanded,
                      mobile: widget.mobile,
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
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ITEM DE FLYOUT (submenú emergente)
// ═══════════════════════════════════════════════════════════════
class _FlyoutItem extends StatefulWidget {
  final AppSidebarItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _FlyoutItem({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_FlyoutItem> createState() => _FlyoutItemState();
}

class _FlyoutItemState extends State<_FlyoutItem> {
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            children: [
              Icon(
                widget.isActive ? widget.item.activeIcon : widget.item.icon,
                size: 16,
                color: iconColor,
              ),
              const SizedBox(width: 10),
              Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: widget.isActive
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SECCIÓN CONFIGURACIÓN (colapsable con flyout)
// ═══════════════════════════════════════════════════════════════
class _SettingsSection extends StatefulWidget {
  final String currentRoute;
  final bool expanded;
  final bool mobile;
  final Animation<double> opacityAnim;
  final VoidCallback? onItemTap;

  const _SettingsSection({
    required this.currentRoute,
    required this.expanded,
    this.mobile = false,
    required this.opacityAnim,
    this.onItemTap,
  });

  @override
  State<_SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<_SettingsSection> {
  bool _settingsExpanded = false;
  bool _hovered = false;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  bool get _hasActiveChild => visibleSettingsSidebarItems.any(
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
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showFlyout(BuildContext context) {
    _removeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: () => _removeOverlay(),
            child: Container(color: Colors.transparent),
          ),
          Positioned(
            left: AppSpacing.sidebarCollapsedWidth + 4,
            top: _getTilePosition(context),
            child: _FlyoutOverlay(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header del flyout
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.sidebarActive.withOpacity(0.1),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.settings_outlined,
                          size: 16,
                          color: AppColors.sidebarActiveText,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Configuración',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.sidebarActiveText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Opciones
                  ...visibleSettingsSidebarItems.map((item) {
                    final isChildActive = widget.currentRoute.startsWith(
                      item.route,
                    );
                    return _FlyoutItem(
                      item: item,
                      isActive: isChildActive,
                      onTap: () {
                        _removeOverlay();
                        widget.onItemTap?.call();
                        context.go(item.route);
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  double _getTilePosition(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      return position.dy;
    }
    return MediaQuery.of(context).size.height - 200;
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
        : widget.mobile
        ? const Color(0xFFE2E8F0)
        : AppColors.sidebarText;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Column(
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
                } else {
                  _showFlyout(context);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                padding: EdgeInsets.symmetric(
                  horizontal: widget.expanded ? (widget.mobile ? 16 : 12) : 0,
                  vertical: widget.mobile ? 14 : 10,
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
                      size: widget.mobile ? 22 : 18,
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
                              fontSize: widget.mobile ? 15 : 13,
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
                children: visibleSettingsSidebarItems.map((item) {
                  final isChildActive = widget.currentRoute.startsWith(
                    item.route,
                  );
                  return _SidebarTile(
                    item: item,
                    isActive: isChildActive,
                    expanded: widget.expanded,
                    mobile: widget.mobile,
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
      ),
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
  final bool mobile;
  final Animation<double> opacityAnim;
  final double indent;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.isActive,
    required this.expanded,
    this.mobile = false,
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
        : widget.mobile
        ? const Color(0xFFE2E8F0)
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
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding:
              EdgeInsets.symmetric(
                horizontal: widget.expanded ? (widget.mobile ? 16 : 12) : 0,
                vertical: widget.mobile ? 14 : 10,
              ).copyWith(
                left: widget.expanded
                    ? (widget.mobile ? 16 : 12) + widget.indent
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
                size: widget.mobile ? 22 : 18,
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
                        fontSize: widget.mobile ? 15 : 13,
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
