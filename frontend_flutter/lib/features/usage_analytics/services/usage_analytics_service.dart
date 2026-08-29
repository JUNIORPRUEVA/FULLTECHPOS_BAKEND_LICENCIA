import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../models/usage_analytics.dart';

class UsageAnalyticsService {
  final ApiClient _client;

  UsageAnalyticsService({required SessionManager sessionManager})
    : _client = ApiClient(sessionManager: sessionManager);

  Future<UsageDashboardData> getDashboard({
    String? projectCode,
    String? appCode,
    String? status,
    String? from,
    String? to,
    int page = 1,
    int limit = 50,
  }) async {
    final query = _buildQuery({
      'project_code': projectCode,
      'app_code': appCode,
      'status': status,
      'from': from,
      'to': to,
      'page': page,
      'limit': limit,
    });

    final overviewData = await _client.get('/api/admin/usage/overview$query');
    final accountsData = await _client.get('/api/admin/usage/accounts$query');

    return UsageDashboardData(
      overview: UsageOverview.fromJson(
        overviewData['overview'] as Map<String, dynamic>? ?? const {},
      ),
      accounts: UsageAccountsResult(
        page: _int(accountsData['page']),
        limit: _int(accountsData['limit']),
        total: _int(accountsData['total']),
        accounts: (accountsData['accounts'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(UsageAccount.fromJson)
            .toList(),
      ),
    );
  }

  String _buildQuery(Map<String, Object?> values) {
    final params = <String, String>{};
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      params[entry.key] = text;
    }
    if (params.isEmpty) return '';
    return '?${Uri(queryParameters: params).query}';
  }
}

int _int(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
