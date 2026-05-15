import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';

class DashboardStats {
  final int totalCompanies;
  final int activeSubscriptions;
  final int expiredSubscriptions;
  final int suspendedSubscriptions;
  final int totalSubscriptions;
  final int pendingPayments;
  final double paymentsCollectedThisMonth;
  final double monthlyRevenueEstimate;

  const DashboardStats({
    this.totalCompanies = 0,
    this.activeSubscriptions = 0,
    this.expiredSubscriptions = 0,
    this.suspendedSubscriptions = 0,
    this.totalSubscriptions = 0,
    this.pendingPayments = 0,
    this.paymentsCollectedThisMonth = 0,
    this.monthlyRevenueEstimate = 0,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return DashboardStats(
      totalCompanies: _toInt(data['total_companies']),
      activeSubscriptions: _toInt(data['active_subscriptions']),
      expiredSubscriptions: _toInt(data['expired_subscriptions']),
      suspendedSubscriptions: _toInt(data['suspended_subscriptions']),
      totalSubscriptions: _toInt(data['total_subscriptions']),
      pendingPayments: _toInt(data['pending_payments']),
      paymentsCollectedThisMonth:
          _toDouble(data['payments_collected_this_month']),
      monthlyRevenueEstimate: _toDouble(data['monthly_revenue_estimate']),
    );
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    return double.tryParse(v.toString()) ?? 0;
  }
}

class DashboardService {
  final ApiClient _client;

  DashboardService({required SessionManager sessionManager})
      : _client = ApiClient(sessionManager: sessionManager);

  Future<DashboardStats> getDashboard() async {
    final data = await _client.get('/api/admin/saas-dashboard');
    return DashboardStats.fromJson(data);
  }
}
