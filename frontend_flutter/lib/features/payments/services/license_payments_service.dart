import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../models/license_payment_order.dart';

class LicensePaymentsService {
  final ApiClient _client;

  LicensePaymentsService({required SessionManager sessionManager})
      : _client = ApiClient(sessionManager: sessionManager);

  /// Lista órdenes de pago
  Future<Map<String, dynamic>> listPaymentOrders({
    int page = 1,
    int limit = 20,
    String? status,
    String? projectId,
    String? customerId,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (projectId != null && projectId.isNotEmpty) {
      params['project_id'] = projectId;
    }
    if (customerId != null && customerId.isNotEmpty) {
      params['customer_id'] = customerId;
    }

    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final data = await _client.get('/api/admin/license-payments?$queryString');
    final orders = (data['orders'] as List?)
            ?.map((o) => LicensePaymentOrder.fromJson(o as Map<String, dynamic>))
            .toList() ??
        [];

    return {
      'orders': orders,
      'total': data['total'] ?? 0,
      'page': data['page'] ?? page,
      'limit': data['limit'] ?? limit,
    };
  }

  /// Obtiene detalle de una orden
  Future<LicensePaymentOrder> getPaymentOrderDetail(String orderId) async {
    final data = await _client.get('/api/admin/license-payments/$orderId');
    final order = data['order'] as Map<String, dynamic>? ?? data;
    return LicensePaymentOrder.fromJson(order);
  }

  /// Crea una orden de pago PayPal
  Future<Map<String, dynamic>> createPayPalOrder({
    required String customerId,
    required String projectId,
    required int months,
    String? licenseId,
  }) async {
    final body = <String, dynamic>{
      'customer_id': customerId,
      'project_id': projectId,
      'months': months,
    };
    if (licenseId != null) body['license_id'] = licenseId;

    return await _client.post(
        '/api/admin/license-payments/create-paypal-order', body);
  }

  /// Captura una orden de PayPal aprobada
  Future<Map<String, dynamic>> capturePayPalOrder({
    required String paypalOrderId,
    String? paymentOrderId,
  }) async {
    final body = <String, dynamic>{
      'paypal_order_id': paypalOrderId,
    };
    if (paymentOrderId != null) body['payment_order_id'] = paymentOrderId;

    return await _client.post(
        '/api/admin/license-payments/capture-paypal-order', body);
  }

  /// Crea una licencia demo
  Future<Map<String, dynamic>> createDemoLicense({
    required String customerId,
    required String projectId,
    int maxDevices = 1,
    String? notas,
  }) async {
    final body = <String, dynamic>{
      'customer_id': customerId,
      'project_id': projectId,
      'max_dispositivos': maxDevices,
    };
    if (notas != null) body['notas'] = notas;

    return await _client.post('/api/admin/licenses/demo', body);
  }
}
