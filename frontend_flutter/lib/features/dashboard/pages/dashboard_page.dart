import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/error_view.dart';
import '../services/dashboard_service.dart';
import 'package:intl/intl.dart';

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
    final currencyFmt = NumberFormat.currency(locale: 'es', symbol: '\$');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panel',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Resumen general del sistema',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: onRefresh,
                color: AppColors.textSecondary,
                tooltip: 'Actualizar',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Stats grid
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 800
                  ? 4
                  : constraints.maxWidth > 500
                  ? 2
                  : 1;
              return _StatsGrid(
                columns: columns,
                stats: stats,
                currencyFmt: currencyFmt,
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
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
              _MetricRow('Demo', stats.demoLicenses, AppColors.primary),
              _MetricRow('Full', stats.fullLicenses, AppColors.success),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionTitle(title: 'Productos y proyectos'),
          const SizedBox(height: AppSpacing.sm),
          _MetricBreakdown(
            rows: [
              _MetricRow(
                'Productos app',
                stats.totalProducts,
                AppColors.textPrimary,
              ),
              _MetricRow(
                'Publicados',
                stats.publishedProducts,
                AppColors.success,
              ),
              _MetricRow('Borradores', stats.draftProducts, AppColors.warning),
              _MetricRow('Archivados', stats.archivedProducts, AppColors.error),
              _MetricRow('Planes', stats.totalPlans, AppColors.primary),
              _MetricRow(
                'Planes activos',
                stats.activePlans,
                AppColors.success,
              ),
              _MetricRow('Proyectos', stats.totalProjects, AppColors.primary),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionTitle(title: 'Activaciones'),
          const SizedBox(height: AppSpacing.sm),
          _MetricBreakdown(
            rows: [
              _MetricRow(
                'Total activaciones',
                stats.totalActivations,
                AppColors.textPrimary,
              ),
              _MetricRow('Activas', stats.activeActivations, AppColors.success),
              _MetricRow(
                'Revocadas',
                stats.revokedActivations,
                AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionTitle(title: 'Estado de suscripciones'),
          const SizedBox(height: AppSpacing.sm),
          _SubscriptionBreakdown(stats: stats),
          const SizedBox(height: AppSpacing.lg),
          // Financial summary
          _SectionTitle(title: 'Resumen financiero'),
          const SizedBox(height: AppSpacing.sm),
          _FinancialSummary(stats: stats, currencyFmt: currencyFmt),
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
  final NumberFormat currencyFmt;

  const _StatsGrid({
    required this.columns,
    required this.stats,
    required this.currencyFmt,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCardData(
        title: 'Clientes',
        value: stats.totalCustomers.toString(),
        icon: Icons.people_outline_rounded,
        color: AppColors.primary,
      ),
      _StatCardData(
        title: 'Licencias',
        value: stats.totalLicenses.toString(),
        icon: Icons.vpn_key_outlined,
        color: AppColors.success,
      ),
      _StatCardData(
        title: 'Licencias activas',
        value: stats.activeLicenses.toString(),
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.success,
      ),
      _StatCardData(
        title: 'Productos app',
        value: stats.totalProducts.toString(),
        icon: Icons.inventory_2_outlined,
        color: AppColors.primary,
      ),
      _StatCardData(
        title: 'Planes',
        value: stats.totalPlans.toString(),
        icon: Icons.layers_outlined,
        color: AppColors.primary,
      ),
      _StatCardData(
        title: 'Proyectos',
        value: stats.totalProjects.toString(),
        icon: Icons.folder_copy_outlined,
        color: AppColors.primary,
      ),
      _StatCardData(
        title: 'Activaciones',
        value: stats.totalActivations.toString(),
        icon: Icons.devices_other_outlined,
        color: AppColors.warning,
      ),
      _StatCardData(
        title: 'Suscripciones',
        value: stats.totalSubscriptions.toString(),
        icon: Icons.subscriptions_outlined,
        color: AppColors.success,
      ),
      _StatCardData(
        title: 'Pagos pendientes',
        value: stats.pendingPayments.toString(),
        icon: Icons.pending_actions_outlined,
        color: AppColors.warning,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 2.4,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => _StatCard(data: cards[i]),
    );
  }
}

class _StatCardData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _StatCard extends StatelessWidget {
  final _StatCardData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(data.icon, size: 18, color: data.color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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

class _SubscriptionBreakdown extends StatelessWidget {
  final DashboardStats stats;
  const _SubscriptionBreakdown({required this.stats});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Total suscripciones', stats.totalSubscriptions, AppColors.textPrimary),
      ('Activas', stats.activeSubscriptions, AppColors.success),
      ('Vencidas', stats.expiredSubscriptions, AppColors.error),
      ('Suspendidas', stats.suspendedSubscriptions, AppColors.warning),
    ];

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
                        color: row.$3,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        row.$1,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      row.$2.toString(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: row.$3,
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

class _FinancialSummary extends StatelessWidget {
  final DashboardStats stats;
  final NumberFormat currencyFmt;

  const _FinancialSummary({required this.stats, required this.currencyFmt});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Recaudado este mes',
        stats.paymentsCollectedThisMonth > 0
            ? currencyFmt.format(stats.paymentsCollectedThisMonth)
            : 'No disponible',
      ),
      (
        'Estimado mensual',
        stats.monthlyRevenueEstimate > 0
            ? currencyFmt.format(stats.monthlyRevenueEstimate)
            : 'No disponible',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.$1,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      item.$2,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < items.length - 1) const Divider(height: 1),
            ],
          );
        }).toList(),
      ),
    );
  }
}
