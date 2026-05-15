import 'package:flutter/material.dart';
import '../layout/responsive_layout.dart';
import '../theme/app_colors.dart';
import '../widgets/app_sidebar.dart';

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

  @override
  Widget build(BuildContext context) {
    final isDesktop = ResponsiveLayout.showSidebarInline(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: isDesktop
          ? null
          : Drawer(
              width: 240,
              shape: const RoundedRectangleBorder(),
              child: AppSidebar(
                currentRoute: widget.currentRoute,
                onItemTap: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
            ),
      body: Row(
        children: [
          // Sidebar inline on desktop
          if (isDesktop)
            AppSidebar(currentRoute: widget.currentRoute),
          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar
                Container(
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                      bottom: BorderSide(color: AppColors.border),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      if (!isDesktop)
                        IconButton(
                          icon: const Icon(Icons.menu_rounded, size: 20),
                          onPressed: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                          color: const Color(0xFF64748B),
                          tooltip: 'Menú',
                        ),
                      if (!isDesktop) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.pageTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Page content
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
