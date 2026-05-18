import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../models/customer.dart';

class CustomersService {
  final ApiClient _client;

  CustomersService({required SessionManager sessionManager})
      : _client = ApiClient(sessionManager: sessionManager);

  Future<List<Customer>> listCustomers({int page = 1, int limit = 50}) async {
    final data = await _client
        .get('/api/admin/customers?page=$page&limit=$limit');
    final list = data['customers'] as List<dynamic>? ?? [];
    return list
        .map((e) => Customer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Customer> getCustomer(String id) async {
    final data = await _client.get('/api/admin/customers/$id');
    final customer =
        data['customer'] as Map<String, dynamic>? ?? data;
    return Customer.fromJson(customer);
  }

  Future<Customer> createCustomer(Map<String, dynamic> body) async {
    final data = await _client.post('/api/admin/customers', body);
    return Customer.fromJson(
        data['customer'] as Map<String, dynamic>? ?? data);
  }

  Future<Customer> updateCustomer(String id, Map<String, dynamic> body) async {
    final data = await _client.put('/api/admin/customers/$id', body);
    return Customer.fromJson(
        data['customer'] as Map<String, dynamic>? ?? data);
  }

  Future<void> deleteCustomer(String id) async {
    await _client.delete('/api/admin/customers/$id');
  }

  Future<void> setBusinessId(String id, String businessId) async {
    await _client.put(
        '/api/admin/customers/$id/business_id', {'business_id': businessId});
  }
}
