import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../models/billing_models.dart';
import '../services/billing_service.dart';

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  late final BillingService _service;
  late Future<_SubscriptionsData> _future;

  @override
  void initState() {
    super.initState();
    _service = BillingService(sessionManager: context.read<SessionManager>());
    _future = _load();
  }

  Future<_SubscriptionsData> _load() async {
    final license = await _service.getLicense();
    final data = await _service.getSubscriptions();
    return _SubscriptionsData(
      license: license,
      subscriptions: data.subscriptions,
      history: data.history,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SubscriptionsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView(message: 'Sincronizando licencia...');
        }
        if (snapshot.hasError) {
          return ErrorView(
            message: '${snapshot.error}',
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _future = _load());
            await _future;
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _LicenseSummary(license: data.license),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Mis suscripciones',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              if (data.subscriptions.isEmpty)
                const _EmptyPanel(text: 'No tienes suscripciones registradas.')
              else
                ...data.subscriptions.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _SubscriptionTile(subscription: item),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Historial de pagos',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              if (data.history.isEmpty)
                const _EmptyPanel(text: 'Todavía no hay pagos registrados.')
              else
                _PaymentHistory(items: data.history),
            ],
          ),
        );
      },
    );
  }
}

class _SubscriptionsData {
  final LicenseState license;
  final List<BillingSubscription> subscriptions;
  final List<PaymentHistoryItem> history;

  const _SubscriptionsData({
    required this.license,
    required this.subscriptions,
    required this.history,
  });
}

class _LicenseSummary extends StatelessWidget {
  final LicenseState license;

  const _LicenseSummary({required this.license});

  @override
  Widget build(BuildContext context) {
    final blocked = license.isBlocked;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: blocked ? AppColors.errorLight : AppColors.successLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: blocked
              ? AppColors.error.withOpacity(.25)
              : AppColors.success.withOpacity(.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            blocked ? Icons.lock_outline_rounded : Icons.verified_user_outlined,
            color: blocked ? AppColors.error : AppColors.success,
            size: 32,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Estado de licencia',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    StatusBadge.fromString(license.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  blocked
                      ? 'Tu licencia está inactiva, realiza un pago para continuar.'
                      : 'Tu licencia está activa y las funciones premium están disponibles.',
                  style: TextStyle(
                    color: blocked ? AppColors.error : AppColors.success,
                  ),
                ),
                if (license.planName != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Plan: ${license.planName}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  final BillingSubscription subscription;

  const _SubscriptionTile({required this.subscription});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.subscriptions_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subscription.planName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  subscription.nextPayment == null
                      ? 'Sin próximo pago registrado'
                      : 'Próximo pago: ${dateFormat.format(subscription.nextPayment!.toLocal())}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          StatusBadge.fromString(subscription.status),
        ],
      ),
    );
  }
}

class _PaymentHistory extends StatelessWidget {
  final List<PaymentHistoryItem> items;

  const _PaymentHistory({required this.items});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items.map((item) {
          return ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text('${item.currency} ${item.amount.toStringAsFixed(2)}'),
            subtitle: Text(
              item.paidAt == null
                  ? 'Fecha pendiente'
                  : dateFormat.format(item.paidAt!.toLocal()),
            ),
            trailing: StatusBadge.fromString(item.status),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final String text;

  const _EmptyPanel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}
