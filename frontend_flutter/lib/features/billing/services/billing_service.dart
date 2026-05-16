import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/session_manager.dart';
import '../models/billing_models.dart';

class BillingService {
  final ApiClient _client;

  BillingService({required SessionManager sessionManager})
    : _client = ApiClient(sessionManager: sessionManager);

  Future<List<BillingPlan>> getPlans() async {
    final data = await _getOrEmpty('/api/plans');
    final rows = data['plans'] as List? ?? const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(BillingPlan.fromJson)
        .toList();
  }

  Future<CheckoutResult> buyPlan(BillingPlan plan) async {
    final endpoint = plan.isRecurring
        ? '/api/paypal/create-subscription'
        : '/api/paypal/create-order';
    final data = await _client.post(endpoint, {'plan_id': plan.id});
    return CheckoutResult.fromJson(data);
  }

  Future<PaymentStatus> confirmCheckout(CheckoutResult checkout) async {
    if (checkout.orderId != null) {
      final data = await _client.post('/api/paypal/capture-order', {
        'order_id': checkout.orderId,
      });
      return PaymentStatus.fromJson({
        'status': data['ok'] == true ? 'completado' : data['status'],
        'paid': data['ok'] == true,
      });
    }

    final query =
        'subscription_id=${Uri.encodeQueryComponent(checkout.subscriptionId ?? '')}';
    final data = await _client.get('/api/paypal/status?$query');
    return PaymentStatus.fromJson(data);
  }

  Future<LicenseState> getLicense() async {
    final data = await _getOrEmpty('/api/license');
    return LicenseState.fromJson(data);
  }

  Future<
    ({
      List<BillingSubscription> subscriptions,
      List<PaymentHistoryItem> history,
    })
  >
  getSubscriptions() async {
    final data = await _getOrEmpty('/api/subscriptions');
    final subscriptions = (data['subscriptions'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BillingSubscription.fromJson)
        .toList();
    final history = (data['history'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PaymentHistoryItem.fromJson)
        .toList();
    return (subscriptions: subscriptions, history: history);
  }

  Future<Map<String, dynamic>> _getOrEmpty(String path) async {
    try {
      return await _client.get(path);
    } on ApiException catch (error) {
      if (error.statusCode == 500) return const {};
      rethrow;
    }
  }
}
