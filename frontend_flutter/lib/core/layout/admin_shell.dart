import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app_shell_actions.dart';
import '../layout/responsive_layout.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_bar_account_menu.dart';
import '../widgets/app_sidebar.dart';

/// AdminShell rediseñado con sidebar colapsable y layout premium
class AdminShell extends StatefulWidget {
  final Widget child;
  final String currentRoute;
  final String pageTitle;

  const AdminShell({
    super.key,
    required this.child,
    required this.currentRoute,
    required this.pageTitle,
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<AppSidebarState> _sidebarKey = GlobalKey<AppSidebarState>();
  final AppShellActionsController _actionsController =
      AppShellActionsController();

  @override
  void didUpdateWidget(covariant AdminShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRoute != widget.currentRoute) {
      _actionsController.clear();
    }
  }

  @override
  void dispose() {
    _actionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.showSidebarInline(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: isDesktop
          ? null
          : Drawer(
              width: MediaQuery.sizeOf(
                context,
              ).width.clamp(300.0, 360.0).toDouble(),
              shape: const RoundedRectangleBorder(),
              backgroundColor: AppColors.sidebarBg,
              child: AppSidebar(
                key: _sidebarKey,
                currentRoute: widget.currentRoute,
                forceExpanded: true,
                mobile: true,
                onItemTap: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
            ),
      body: SafeArea(
        top: !isDesktop,
        bottom: !isDesktop,
        child: isDesktop
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    children: [
                      const SizedBox(width: AppSpacing.sidebarCollapsedWidth),
                      Expanded(child: _buildMainContent(isDesktop)),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: AppSidebar(
                      key: _sidebarKey,
                      currentRoute: widget.currentRoute,
                    ),
                  ),
                ],
              )
            : Row(children: [Expanded(child: _buildMainContent(isDesktop))]),
      ),
    );
  }

  Widget _buildMainContent(bool isDesktop) {
    return Column(
      children: [
        _buildTopBar(isDesktop),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isDesktop ? 0 : AppSpacing.sm),
            child: AppShellActionsScope(
              controller: _actionsController,
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(bool isDesktop) {
    final canGoBack = context.canPop();
    return Container(
      height: isDesktop ? AppSpacing.appBarHeight : 66,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 14),
      child: Row(
        children: [
          // Back button (mobile) - cuando hay historial de navegación
          if (!isDesktop && canGoBack)
            Material(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: _safePop,
                borderRadius: BorderRadius.circular(14),
                child: const SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 24,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          // Menu button (mobile) - cuando NO hay historial
          if (!isDesktop && !canGoBack)
            Material(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                borderRadius: BorderRadius.circular(14),
                child: const SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(
                    Icons.menu_rounded,
                    size: 24,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          if (!isDesktop) const SizedBox(width: 12),

          // Sidebar toggle (desktop)
          if (isDesktop)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _sidebarKey.currentState?.toggle(),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.menu_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          if (isDesktop) const SizedBox(width: 12),

          // Page title + subtitle (mobile)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.pageTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!isDesktop && widget.pageTitle == 'Panel')
                  Text(
                    'Resumen general del sistema',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Menú de tres puntos con acciones de la página
          _PageActionsMenu(actionsController: _actionsController),
          const SizedBox(width: 4),
          const AppBarAccountMenu(),
        ],
      ),
    );
  }

  void _safePop() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    if (context.canPop()) {
      try {
        context.pop();
      } catch (_) {
        context.go('/admin/dashboard');
      }
      return;
    }
    context.go('/admin/dashboard');
  }
}

/// Widget que muestra el menú de tres puntos con las acciones de la página
class _PageActionsMenu extends StatefulWidget {
  final AppShellActionsController actionsController;

  const _PageActionsMenu({required this.actionsController});

  @override
  State<_PageActionsMenu> createState() => _PageActionsMenuState();
}

class _PageActionsMenuState extends State<_PageActionsMenu> {
  List<AppShellAction> _actions = [];

  @override
  void initState() {
    super.initState();
    widget.actionsController.addListener(_onActionsChanged);
    _actions = List.from(widget.actionsController.actions);
  }

  @override
  void didUpdateWidget(covariant _PageActionsMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionsController != widget.actionsController) {
      oldWidget.actionsController.removeListener(_onActionsChanged);
      widget.actionsController.addListener(_onActionsChanged);
      _actions = List.from(widget.actionsController.actions);
    }
  }

  @override
  void dispose() {
    widget.actionsController.removeListener(_onActionsChanged);
    super.dispose();
  }

  void _onActionsChanged() {
    // Usar addPostFrameCallback para evitar llamar setState durante el build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _actions = List.from(widget.actionsController.actions);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_actions.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<int>(
      tooltip: 'Opciones',
      icon: const Icon(
        Icons.more_vert_rounded,
        size: 22,
        color: AppColors.textSecondary,
      ),
      onSelected: (index) {
        if (index >= 0 && index < _actions.length) {
          _actions[index].onTap();
        }
      },
      itemBuilder: (context) {
        return List.generate(_actions.length, (index) {
          final action = _actions[index];
          return PopupMenuItem<int>(
            value: index,
            child: Row(
              children: [
                Icon(action.icon, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Text(
                  action.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          );
        });
      },
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
    );
  }
}
