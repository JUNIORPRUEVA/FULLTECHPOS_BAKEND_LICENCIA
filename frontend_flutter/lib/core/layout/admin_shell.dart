import 'package:flutter/material.dart';
import '../layout/responsive_layout.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.showSidebarInline(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: isDesktop
          ? null
          : Drawer(
              width: AppSpacing.sidebarExpandedWidth,
              shape: const RoundedRectangleBorder(),
              child: AppSidebar(
                key: _sidebarKey,
                currentRoute: widget.currentRoute,
                onItemTap: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
            ),
      body: Row(
        children: [
          // Sidebar inline on desktop
          if (isDesktop)
            AppSidebar(
              key: _sidebarKey,
              currentRoute: widget.currentRoute,
            ),
          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar premium
                _buildTopBar(isDesktop),
                // Page content
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDesktop) {
    return Container(
      height: AppSpacing.appBarHeight,
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Menu button (mobile)
          if (!isDesktop)
            IconButton(
              icon: const Icon(Icons.menu_rounded, size: 20),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              color: AppColors.textSecondary,
              tooltip: 'Menú',
            ),
          if (!isDesktop) const SizedBox(width: 8),

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

          // Page title
          Expanded(
            child: Text(
              widget.pageTitle,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
