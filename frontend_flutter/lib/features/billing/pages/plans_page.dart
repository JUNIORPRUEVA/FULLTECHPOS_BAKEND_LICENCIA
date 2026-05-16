import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/billing_models.dart';
import '../services/billing_service.dart';

class PlansPage extends StatefulWidget {
  const PlansPage({super.key});

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  late final BillingService _service;
  late Future<List<BillingPlan>> _future;
  CheckoutResult? _pendingCheckout;
  String? _message;
  String? _error;
  String? _buyingPlanId;
  bool _checking = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _service = BillingService(sessionManager: context.read<SessionManager>());
    _future = _service.getPlans();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _buy(BillingPlan plan) async {
    setState(() {
      _buyingPlanId = plan.id;
      _error = null;
      _message = null;
    });
    try {
      final checkout = await _service.buyPlan(plan);
      if (checkout.approvalUrl.isEmpty) {
        throw const ApiException('PayPal no devolvió una URL de aprobación');
      }
      final opened = await launchUrl(
        Uri.parse(checkout.approvalUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw const ApiException('No se pudo abrir PayPal');
      setState(() {
        _pendingCheckout = checkout;
        _message =
            'PayPal se abrió en el navegador. Completa el pago y vuelve para verificar.';
      });
      if (checkout.subscriptionId != null) _startPolling();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'No se pudo iniciar el pago: $e');
    } finally {
      if (mounted) setState(() => _buyingPlanId = null);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_pendingCheckout != null && !_checking) _checkPayment(silent: true);
    });
  }

  Future<void> _checkPayment({bool silent = false}) async {
    final checkout = _pendingCheckout;
    if (checkout == null) return;
    setState(() {
      _checking = true;
      if (!silent) _error = null;
    });
    try {
      final status = await _service.confirmCheckout(checkout);
      if (status.paid) {
        _pollTimer?.cancel();
        setState(() {
          _message = 'Pago realizado con éxito. Tu licencia fue actualizada.';
          _pendingCheckout = null;
        });
      } else if (!silent) {
        setState(() => _message = 'El pago todavía está ${status.status}.');
      }
    } on ApiException catch (e) {
      if (!silent) setState(() => _error = e.message);
    } catch (e) {
      if (!silent) setState(() => _error = 'No se pudo verificar el pago: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BillingPlan>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingView(message: 'Cargando planes...');
        }
        if (snapshot.hasError) {
          return ErrorView(
            message: '${snapshot.error}',
            onRetry: () => setState(() => _future = _service.getPlans()),
          );
        }
        final plans = snapshot.data ?? const [];
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _future = _service.getPlans());
            await _future;
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _Header(
                pendingCheckout: _pendingCheckout,
                message: _message,
                error: _error,
                checking: _checking,
                onCheck: () => _checkPayment(),
              ),
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width >= 1100
                      ? 3
                      : width >= 720
                      ? 2
                      : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: plans.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childAspectRatio: columns == 1 ? 1.45 : 0.86,
                    ),
                    itemBuilder: (context, index) => _PlanCard(
                      plan: plans[index],
                      loading: _buyingPlanId == plans[index].id,
                      onBuy: () => _buy(plans[index]),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final CheckoutResult? pendingCheckout;
  final String? message;
  final String? error;
  final bool checking;
  final VoidCallback onCheck;

  const _Header({
    required this.pendingCheckout,
    required this.message,
    required this.error,
    required this.checking,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Planes',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Elige un plan, paga con PayPal y la licencia se sincroniza automáticamente con tu cuenta.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _Notice(
                    text: message!,
                    color: AppColors.info,
                    bg: AppColors.infoLight,
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _Notice(
                    text: error!,
                    color: AppColors.error,
                    bg: AppColors.errorLight,
                  ),
                ],
              ],
            ),
          ),
          if (pendingCheckout != null) ...[
            const SizedBox(width: AppSpacing.md),
            FilledButton.icon(
              onPressed: checking ? null : onCheck,
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined, size: 18),
              label: const Text('Verificar pago'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatefulWidget {
  final BillingPlan plan;
  final bool loading;
  final VoidCallback onBuy;

  const _PlanCard({
    required this.plan,
    required this.loading,
    required this.onBuy,
  });

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(symbol: '${widget.plan.currency} ');
    final period = widget.plan.type == 'mensual'
        ? '/mes'
        : widget.plan.type == 'anual'
        ? '/año'
        : ' único';
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hovered ? AppColors.primary : AppColors.border,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.10),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ]
              : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.plan.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _PlanType(type: widget.plan.type),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    formatter.format(widget.plan.price),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    period,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                children: widget.plan.benefits.isEmpty
                    ? const [_Benefit(text: 'Acceso a funciones premium')]
                    : widget.plan.benefits
                          .map((benefit) => _Benefit(text: benefit))
                          .toList(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.loading ? null : widget.onBuy,
                icon: widget.loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Comprar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final String text;

  const _Benefit({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 17,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanType extends StatelessWidget {
  final String type;

  const _PlanType({required this.type});

  @override
  Widget build(BuildContext context) {
    final label = type == 'mensual'
        ? 'Mensual'
        : type == 'anual'
        ? 'Anual'
        : 'Permanente';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;

  const _Notice({required this.text, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
