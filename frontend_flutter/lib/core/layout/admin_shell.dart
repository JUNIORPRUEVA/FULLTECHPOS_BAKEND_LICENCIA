import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../auth/session_manager.dart';
import '../layout/responsive_layout.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
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
  String? _licenseStatus;
  bool _premiumEnabled = true;

  bool get _isBillingRoute =>
      widget.currentRoute.startsWith('/admin/planes-pago') ||
      widget.currentRoute.startsWith('/admin/mis-suscripciones');

  bool get _shouldBlockPremium =>
      !_isBillingRoute &&
      !_premiumEnabled &&
      (_licenseStatus == 'BLOQUEADA' || _licenseStatus == 'VENCIDA');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLicense());
  }

  @override
  void didUpdateWidget(covariant AdminShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRoute != widget.currentRoute) {
      _syncLicense();
    }
  }

  Future<void> _syncLicense() async {
    try {
      final client = ApiClient(sessionManager: context.read<SessionManager>());
      final data = await client.get('/api/license');
      if (!mounted) return;
      setState(() {
        _licenseStatus = '${data['status'] ?? data['estado'] ?? ''}'
            .toUpperCase();
        _premiumEnabled = data['premium_enabled'] == true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _licenseStatus = null;
        _premiumEnabled = true;
      });
    }
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
          if (isDesktop) AppSidebar(currentRoute: widget.currentRoute),
          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar
                Container(
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
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
                Expanded(
                  child: _shouldBlockPremium
                      ? _PremiumBlockedView(
                          status: _licenseStatus ?? 'BLOQUEADA',
                        )
                      : widget.child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumBlockedView extends StatelessWidget {
  final String status;

  const _PremiumBlockedView({required this.status});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 560,
        margin: const EdgeInsets.all(AppSpacing.lg),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Tu licencia está inactiva, realiza un pago para continuar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Estado actual: $status. Las funciones premium permanecerán deshabilitadas hasta que PayPal confirme el pago.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => context.go('/admin/planes-pago'),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('Ver planes'),
            ),
          ],
        ),
      ),
    );
  }
}
