class BillingPlan {
  final String id;
  final String name;
  final String type;
  final double price;
  final String currency;
  final List<String> benefits;

  const BillingPlan({
    required this.id,
    required this.name,
    required this.type,
    required this.price,
    required this.currency,
    required this.benefits,
  });

  bool get isRecurring => type == 'mensual' || type == 'anual';
  bool get isPermanent => type == 'permanente';

  factory BillingPlan.fromJson(Map<String, dynamic> json) {
    return BillingPlan(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? json['nombre'] ?? 'Plan'}',
      type: '${json['type'] ?? json['tipo'] ?? ''}'.toLowerCase(),
      price: _toDouble(json['price'] ?? json['precio']),
      currency: '${json['currency'] ?? json['moneda'] ?? 'USD'}',
      benefits:
          (json['benefits'] as List?)
              ?.map((item) => '$item')
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
    );
  }
}

class BillingSubscription {
  final String id;
  final String planName;
  final String status;
  final DateTime? nextPayment;
  final String? paypalSubscriptionId;

  const BillingSubscription({
    required this.id,
    required this.planName,
    required this.status,
    this.nextPayment,
    this.paypalSubscriptionId,
  });

  factory BillingSubscription.fromJson(Map<String, dynamic> json) {
    return BillingSubscription(
      id: '${json['id'] ?? ''}',
      planName: '${json['plan_name'] ?? json['nombre'] ?? 'Plan'}',
      status: '${json['estado'] ?? json['status'] ?? 'pendiente'}',
      nextPayment: _toDate(json['proximo_pago'] ?? json['next_payment_date']),
      paypalSubscriptionId: json['paypal_subscription_id'] == null
          ? null
          : '${json['paypal_subscription_id']}',
    );
  }
}

class PaymentHistoryItem {
  final String id;
  final String status;
  final double amount;
  final String currency;
  final DateTime? paidAt;

  const PaymentHistoryItem({
    required this.id,
    required this.status,
    required this.amount,
    required this.currency,
    this.paidAt,
  });

  factory PaymentHistoryItem.fromJson(Map<String, dynamic> json) {
    return PaymentHistoryItem(
      id: '${json['id'] ?? json['paypal_payment_id'] ?? json['paypal_order_id'] ?? ''}',
      status: '${json['estado'] ?? json['status'] ?? 'pendiente'}',
      amount: _toDouble(json['monto'] ?? json['amount']),
      currency: '${json['moneda'] ?? json['currency'] ?? 'USD'}',
      paidAt: _toDate(json['fecha_pago'] ?? json['created_at']),
    );
  }
}

class LicenseState {
  final String status;
  final bool premiumEnabled;
  final String? planName;
  final DateTime? expiresAt;

  const LicenseState({
    required this.status,
    required this.premiumEnabled,
    this.planName,
    this.expiresAt,
  });

  bool get isBlocked =>
      !premiumEnabled || status == 'BLOQUEADA' || status == 'VENCIDA';

  factory LicenseState.fromJson(Map<String, dynamic> json) {
    final license = json['license'] is Map<String, dynamic>
        ? json['license'] as Map<String, dynamic>
        : <String, dynamic>{};
    return LicenseState(
      status:
          '${json['status'] ?? json['estado'] ?? license['estado'] ?? 'VENCIDA'}'
              .toUpperCase(),
      premiumEnabled: json['premium_enabled'] == true,
      planName: license['plan_name'] == null ? null : '${license['plan_name']}',
      expiresAt: _toDate(license['fecha_expiracion']),
    );
  }
}

class CheckoutResult {
  final String approvalUrl;
  final String? orderId;
  final String? subscriptionId;

  const CheckoutResult({
    required this.approvalUrl,
    this.orderId,
    this.subscriptionId,
  });

  factory CheckoutResult.fromJson(Map<String, dynamic> json) {
    return CheckoutResult(
      approvalUrl: '${json['approval_url'] ?? ''}',
      orderId: json['paypal_order_id'] == null
          ? null
          : '${json['paypal_order_id']}',
      subscriptionId: json['paypal_subscription_id'] == null
          ? null
          : '${json['paypal_subscription_id']}',
    );
  }
}

class PaymentStatus {
  final String status;
  final bool paid;

  const PaymentStatus({required this.status, required this.paid});

  factory PaymentStatus.fromJson(Map<String, dynamic> json) {
    return PaymentStatus(
      status: '${json['estado'] ?? json['status'] ?? 'pendiente'}',
      paid: json['paid'] == true,
    );
  }
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

DateTime? _toDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse('$value');
}
