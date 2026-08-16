import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../models/daleventas_company_license.dart';

class DaleVentasLicenseService {
  final ApiClient _client;
  final SessionManager _sessionManager;

  DaleVentasLicenseService({required SessionManager sessionManager})
    : _sessionManager = sessionManager,
      _client = ApiClient(sessionManager: sessionManager);

  Future<void> _ensureInit() => _sessionManager.init();

  Future<DaleVentasLicensePageResult> listCompanies({
    int page = 1,
    int limit = 50,
    String query = '',
    String status = '',
    String plan = '',
  }) async {
    await _ensureInit();
    final qs = Uri(
      queryParameters: {
        'page': page.toString(),
        'limit': limit.toString(),
        if (query.trim().isNotEmpty) 'query': query.trim(),
        if (status.trim().isNotEmpty && status != 'TODAS') 'status': status,
        if (plan.trim().isNotEmpty && plan != 'TODOS') 'plan': plan,
      },
    ).query;
    final data = await _client.get(
      '/api/admin/daleventas-licenses/companies?$qs',
    );
    final items = data['items'] as List<dynamic>? ?? const [];
    return DaleVentasLicensePageResult(
      page: _int(data['page'], fallback: page),
      limit: _int(data['limit'], fallback: limit),
      total: _int(data['total'], fallback: items.length),
      items: items
          .whereType<Map<String, dynamic>>()
          .map(DaleVentasCompanyLicense.fromJson)
          .toList(),
    );
  }

  Future<DaleVentasCompanyLicense> getCompany(String companyId) async {
    await _ensureInit();
    final data = await _client.get(
      '/api/admin/daleventas-licenses/companies/$companyId',
    );
    return DaleVentasCompanyLicense.fromJson(data);
  }

  Future<DaleVentasCompanyLicense> updateCompany(
    String companyId,
    Map<String, dynamic> body,
  ) async {
    await _ensureInit();
    final data = await _client.patch(
      '/api/admin/daleventas-licenses/companies/$companyId',
      body,
    );
    return DaleVentasCompanyLicense.fromJson(data);
  }

  Future<DaleVentasCompanyLicense> activateCompany(
    String companyId,
    Map<String, dynamic> body,
  ) async {
    await _ensureInit();
    final data = await _client.post(
      '/api/admin/daleventas-licenses/companies/$companyId/activate',
      body,
    );
    return DaleVentasCompanyLicense.fromJson(data);
  }

  Future<DaleVentasCompanyLicense> blockCompany(
    String companyId,
    Map<String, dynamic> body,
  ) async {
    await _ensureInit();
    final data = await _client.post(
      '/api/admin/daleventas-licenses/companies/$companyId/block',
      body,
    );
    return DaleVentasCompanyLicense.fromJson(data);
  }

  Future<DaleVentasCompanyLicense> deleteCompanyLicense(
    String companyId,
  ) async {
    await _ensureInit();
    final data = await _client.delete(
      '/api/admin/daleventas-licenses/companies/$companyId',
    );
    return DaleVentasCompanyLicense.fromJson(data);
  }

  Future<void> permanentlyDeleteCompanyLicense(String companyId) async {
    await _ensureInit();
    await _client.delete(
      '/api/admin/daleventas-licenses/companies/$companyId/permanent',
    );
  }
}

class DaleVentasLicensePageResult {
  final int page;
  final int limit;
  final int total;
  final List<DaleVentasCompanyLicense> items;

  const DaleVentasLicensePageResult({
    required this.page,
    required this.limit,
    required this.total,
    required this.items,
  });
}

int _int(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? fallback;
}
