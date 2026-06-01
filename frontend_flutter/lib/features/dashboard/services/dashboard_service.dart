import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';

class DashboardStats {
  final int totalCustomers;
  final int totalLicenses;
  final int activeLicenses;
  final int expiredLicenses;
  final int pendingLicenses;
  final int blockedLicenses;
  final int totalProjects;
  final int totalPayments;
  final int pendingPayments;
  final int completedPayments;

  const DashboardStats({
    this.totalCustomers = 0,
    this.totalLicenses = 0,
    this.activeLicenses = 0,
    this.expiredLicenses = 0,
    this.pendingLicenses = 0,
    this.blockedLicenses = 0,
    this.totalProjects = 0,
    this.totalPayments = 0,
    this.pendingPayments = 0,
    this.completedPayments = 0,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;

    int _nestedInt(Map<String, dynamic>? parent, String key) {
      if (parent == null) return 0;
      final val = parent[key];
      if (val == null) return 0;
      if (val is int) return val;
      if (val is Map) return _toInt(val['total']);
      return _toInt(val);
    }

    final customers = data['customers'] as Map<String, dynamic>?;
    final licenses = data['licenses'] as Map<String, dynamic>?;
    final projects = data['projects'] as Map<String, dynamic>?;
    final payments = data['payments'] as Map<String, dynamic>?;

    return DashboardStats(
      totalCustomers: _nestedInt(customers, 'total'),
      totalLicenses: _nestedInt(licenses, 'total'),
      activeLicenses: _nestedInt(licenses, 'active'),
      expiredLicenses: _nestedInt(licenses, 'expired'),
      pendingLicenses: _nestedInt(licenses, 'pending'),
      blockedLicenses: _nestedInt(licenses, 'blocked'),
      totalProjects: _nestedInt(projects, 'total'),
      totalPayments: _nestedInt(payments, 'total'),
      pendingPayments: _nestedInt(payments, 'pending'),
      completedPayments: _nestedInt(payments, 'completed'),
    );
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    return int.tryParse(v.toString()) ?? 0;
  }
}

class DashboardService {
  final ApiClient _client;

  DashboardService({required SessionManager sessionManager})
      : _client = ApiClient(sessionManager: sessionManager);

  Future<DashboardStats> getDashboard() async {
    try {
      final data = await _client.get('/api/admin/dashboard-stats');
      return DashboardStats.fromJson(data);
    } catch (e) {
      // If the new endpoint fails, try the old one as fallback
      try {
        final data = await _client.get('/api/admin/saas-dashboard');
        return DashboardStats.fromJson(data);
      } catch (_) {
        // If both fail, return empty stats
        return const DashboardStats();
      }
    }
  }
}
