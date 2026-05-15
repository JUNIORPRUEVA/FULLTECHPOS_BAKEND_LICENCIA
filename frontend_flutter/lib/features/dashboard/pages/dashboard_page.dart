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
    _service = DashboardService(
      sessionManager: context.read<SessionManager>(),
    );
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
          // Subscription breakdown
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
        title: 'Total empresas',
        value: stats.totalCompanies.toString(),
        icon: Icons.business_outlined,
        color: AppColors.primary,
      ),
      _StatCardData(
        title: 'Suscripciones activas',
        value: stats.activeSubscriptions.toString(),
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.success,
      ),
      _StatCardData(
        title: 'Suscripciones vencidas',
        value: stats.expiredSubscriptions.toString(),
        icon: Icons.cancel_outlined,
        color: AppColors.error,
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
              if (i < rows.length - 1)
                const Divider(height: 1),
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
            : 'No disponible'
      ),
      (
        'Estimado mensual',
        stats.monthlyRevenueEstimate > 0
            ? currencyFmt.format(stats.monthlyRevenueEstimate)
            : 'No disponible'
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
