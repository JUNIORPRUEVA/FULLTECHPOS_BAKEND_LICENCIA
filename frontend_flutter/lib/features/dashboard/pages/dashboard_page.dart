import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/error_view.dart';
import '../services/dashboard_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardService _service;
  late Future<DashboardStats> _future;

  @override
  void initState() {
    super.initState();
    _service = DashboardService(sessionManager: context.read<SessionManager>());
    _future = _service.getDashboard();
  }

  void _refresh() {
    setState(() => _future = _service.getDashboard());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<DashboardStats>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView(message: 'Cargando panel...');
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final stats = snapshot.data!;
          return _DashboardContent(stats: stats, onRefresh: _refresh);
        },
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final DashboardStats stats;
  final VoidCallback onRefresh;

  const _DashboardContent({required this.stats, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 10 : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats grid
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 800
                  ? 4
                  : 2;
              return _StatsGrid(columns: columns, stats: stats);
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          // License breakdown section
          _SectionTitle(title: 'Licencias'),
          const SizedBox(height: AppSpacing.sm),
          _MetricBreakdown(
            rows: [
              _MetricRow(
                'Total licencias',
                stats.totalLicenses,
                AppColors.textPrimary,
              ),
              _MetricRow('Activas', stats.activeLicenses, AppColors.success),
              _MetricRow(
                'Pendientes',
                stats.pendingLicenses,
                AppColors.warning,
              ),
              _MetricRow('Vencidas', stats.expiredLicenses, AppColors.error),
              _MetricRow('Bloqueadas', stats.blockedLicenses, AppColors.error),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Payments section
          _SectionTitle(title: 'Pagos'),
          const SizedBox(height: AppSpacing.sm),
          _MetricBreakdown(
            rows: [
              _MetricRow(
                'Total pagos',
                stats.totalPayments,
                AppColors.textPrimary,
              ),
              _MetricRow(
                'Completados',
                stats.completedPayments,
                AppColors.success,
              ),
              if (stats.pendingPayments > 0)
                _MetricRow(
                  'Pendientes',
                  stats.pendingPayments,
                  AppColors.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final int columns;
  final DashboardStats stats;

  const _StatsGrid({required this.columns, required this.stats});

  @override
  Widget build(BuildContext context) {
    final cards = <_StatCardData>[
      _StatCardData(
        title: 'Clientes',
        value: stats.totalCustomers.toString(),
        icon: Icons.people_outline_rounded,
        color: AppColors.primary,
        route: '/admin/clientes',
      ),
      _StatCardData(
        title: 'Licencias',
        value: stats.totalLicenses.toString(),
        icon: Icons.vpn_key_outlined,
        color: AppColors.success,
        route: '/admin/licencias',
      ),
      _StatCardData(
        title: 'Licencias activas',
        value: stats.activeLicenses.toString(),
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.success,
        route: '/admin/licencias',
      ),
      _StatCardData(
        title: 'Licencias vencidas',
        value: stats.expiredLicenses.toString(),
        icon: Icons.error_outline_rounded,
        color: AppColors.error,
        route: '/admin/licencias',
      ),
      _StatCardData(
        title: 'Licencias pendientes',
        value: stats.pendingLicenses.toString(),
        icon: Icons.schedule_outlined,
        color: AppColors.warning,
        route: '/admin/licencias',
      ),
      _StatCardData(
        title: 'Proyectos',
        value: stats.totalProjects.toString(),
        icon: Icons.folder_copy_outlined,
        color: AppColors.primary,
        route: '/admin/proyectos',
      ),
      _StatCardData(
        title: 'Pagos registrados',
        value: stats.totalPayments.toString(),
        icon: Icons.payments_outlined,
        color: AppColors.success,
        route: '/admin/pagos',
      ),
    ];

    // Only show pending payments card if there are pending payments
    if (stats.pendingPayments > 0) {
      cards.add(
        _StatCardData(
          title: 'Pagos pendientes',
          value: stats.pendingPayments.toString(),
          icon: Icons.pending_actions_outlined,
          color: AppColors.warning,
          route: '/admin/pagos',
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: isMobile ? 10 : AppSpacing.md,
            mainAxisSpacing: isMobile ? 10 : AppSpacing.md,
            childAspectRatio: isMobile ? 3.2 : 2.8,
          ),
          itemCount: cards.length,
          itemBuilder: (_, i) => _StatCard(data: cards[i]),
        );
      },
    );
  }
}

class _StatCardData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String route;
  const _StatCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.route,
  });
}

class _StatCard extends StatelessWidget {
  final _StatCardData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final radius = BorderRadius.circular(isMobile ? 12 : AppSpacing.cardRadius);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      elevation: 0,
      child: InkWell(
        onTap: () => context.go(data.route),
        borderRadius: radius,
        child: Ink(
          padding: EdgeInsets.all(isMobile ? 10 : 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: radius,
            boxShadow: isMobile
                ? null
                : [
                    BoxShadow(
                      color: AppColors.shadowSm,
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                width: isMobile ? 24 : 34,
                height: isMobile ? 24 : 34,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  data.icon,
                  size: isMobile ? 14 : 18,
                  color: data.color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.value,
                      style: TextStyle(
                        fontSize: isMobile ? 15 : 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      data.title,
                      style: TextStyle(
                        fontSize: isMobile ? 10.5 : 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricRow {
  final String label;
  final int value;
  final Color color;

  const _MetricRow(this.label, this.value, this.color);
}

class _MetricBreakdown extends StatelessWidget {
  final List<_MetricRow> rows;

  const _MetricBreakdown({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: rows.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: row.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        row.label,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      row.value.toString(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: row.color,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < rows.length - 1) const Divider(height: 1),
            ],
          );
        }).toList(),
      ),
    );
  }
}
