import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';

class DashboardStats {
  final int totalCustomers;
  final int totalCompanies;
  final int totalLicenses;
  final int activeLicenses;
  final int expiredLicenses;
  final int blockedLicenses;
  final int pendingLicenses;
  final int demoLicenses;
  final int fullLicenses;
  final int totalProducts;
  final int publishedProducts;
  final int draftProducts;
  final int archivedProducts;
  final int totalPlans;
  final int activePlans;
  final int totalProjects;
  final int totalActivations;
  final int activeActivations;
  final int revokedActivations;
  final int activeSubscriptions;
  final int expiredSubscriptions;
  final int suspendedSubscriptions;
  final int totalSubscriptions;
  final int pendingPayments;
  final double paymentsCollectedThisMonth;
  final double monthlyRevenueEstimate;

  const DashboardStats({
    this.totalCustomers = 0,
    this.totalCompanies = 0,
    this.totalLicenses = 0,
    this.activeLicenses = 0,
    this.expiredLicenses = 0,
    this.blockedLicenses = 0,
    this.pendingLicenses = 0,
    this.demoLicenses = 0,
    this.fullLicenses = 0,
    this.totalProducts = 0,
    this.publishedProducts = 0,
    this.draftProducts = 0,
    this.archivedProducts = 0,
    this.totalPlans = 0,
    this.activePlans = 0,
    this.totalProjects = 0,
    this.totalActivations = 0,
    this.activeActivations = 0,
    this.revokedActivations = 0,
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
      totalCustomers: _toInt(data['total_customers']),
      totalCompanies: _toInt(data['total_companies']),
      totalLicenses: _toInt(data['total_licenses']),
      activeLicenses: _toInt(data['active_licenses']),
      expiredLicenses: _toInt(data['expired_licenses']),
      blockedLicenses: _toInt(data['blocked_licenses']),
      pendingLicenses: _toInt(data['pending_licenses']),
      demoLicenses: _toInt(data['demo_licenses']),
      fullLicenses: _toInt(data['full_licenses']),
      totalProducts: _toInt(data['total_products']),
      publishedProducts: _toInt(data['published_products']),
      draftProducts: _toInt(data['draft_products']),
      archivedProducts: _toInt(data['archived_products']),
      totalPlans: _toInt(data['total_plans']),
      activePlans: _toInt(data['active_plans']),
      totalProjects: _toInt(data['total_projects']),
      totalActivations: _toInt(data['total_activations']),
      activeActivations: _toInt(data['active_activations']),
      revokedActivations: _toInt(data['revoked_activations']),
      activeSubscriptions: _toInt(data['active_subscriptions']),
      expiredSubscriptions: _toInt(data['expired_subscriptions']),
      suspendedSubscriptions: _toInt(data['suspended_subscriptions']),
      totalSubscriptions: _toInt(data['total_subscriptions']),
      pendingPayments: _toInt(data['pending_payments']),
      paymentsCollectedThisMonth: _toDouble(
        data['payments_collected_this_month'],
      ),
      monthlyRevenueEstimate: _toDouble(data['monthly_revenue_estimate']),
    );
  }

  DashboardStats copyWith({
    int? totalCustomers,
    int? totalCompanies,
    int? totalLicenses,
    int? activeLicenses,
    int? expiredLicenses,
    int? blockedLicenses,
    int? pendingLicenses,
    int? demoLicenses,
    int? fullLicenses,
    int? totalProducts,
    int? publishedProducts,
    int? draftProducts,
    int? archivedProducts,
    int? totalPlans,
    int? activePlans,
    int? totalProjects,
    int? totalActivations,
    int? activeActivations,
    int? revokedActivations,
    int? activeSubscriptions,
    int? expiredSubscriptions,
    int? suspendedSubscriptions,
    int? totalSubscriptions,
    int? pendingPayments,
    double? paymentsCollectedThisMonth,
    double? monthlyRevenueEstimate,
  }) {
    return DashboardStats(
      totalCustomers: totalCustomers ?? this.totalCustomers,
      totalCompanies: totalCompanies ?? this.totalCompanies,
      totalLicenses: totalLicenses ?? this.totalLicenses,
      activeLicenses: activeLicenses ?? this.activeLicenses,
      expiredLicenses: expiredLicenses ?? this.expiredLicenses,
      blockedLicenses: blockedLicenses ?? this.blockedLicenses,
      pendingLicenses: pendingLicenses ?? this.pendingLicenses,
      demoLicenses: demoLicenses ?? this.demoLicenses,
      fullLicenses: fullLicenses ?? this.fullLicenses,
      totalProducts: totalProducts ?? this.totalProducts,
      publishedProducts: publishedProducts ?? this.publishedProducts,
      draftProducts: draftProducts ?? this.draftProducts,
      archivedProducts: archivedProducts ?? this.archivedProducts,
      totalPlans: totalPlans ?? this.totalPlans,
      activePlans: activePlans ?? this.activePlans,
      totalProjects: totalProjects ?? this.totalProjects,
      totalActivations: totalActivations ?? this.totalActivations,
      activeActivations: activeActivations ?? this.activeActivations,
      revokedActivations: revokedActivations ?? this.revokedActivations,
      activeSubscriptions: activeSubscriptions ?? this.activeSubscriptions,
      expiredSubscriptions: expiredSubscriptions ?? this.expiredSubscriptions,
      suspendedSubscriptions:
          suspendedSubscriptions ?? this.suspendedSubscriptions,
      totalSubscriptions: totalSubscriptions ?? this.totalSubscriptions,
      pendingPayments: pendingPayments ?? this.pendingPayments,
      paymentsCollectedThisMonth:
          paymentsCollectedThisMonth ?? this.paymentsCollectedThisMonth,
      monthlyRevenueEstimate:
          monthlyRevenueEstimate ?? this.monthlyRevenueEstimate,
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
    DashboardStats stats;
    try {
      final data = await _client.get('/api/admin/saas-dashboard');
      stats = DashboardStats.fromJson(data);
    } catch (_) {
      stats = const DashboardStats();
    }

    final results = await Future.wait<int>([
      _total('/api/admin/customers?limit=1', 'customers'),
      _total('/api/admin/licenses?limit=1', 'licenses'),
      _total('/api/admin/licenses?estado=ACTIVA&limit=1', 'licenses'),
      _total('/api/admin/licenses?estado=VENCIDA&limit=1', 'licenses'),
      _total('/api/admin/licenses?estado=BLOQUEADA&limit=1', 'licenses'),
      _total('/api/admin/licenses?estado=PENDIENTE&limit=1', 'licenses'),
      _total('/api/admin/licenses?tipo=DEMO&limit=1', 'licenses'),
      _total('/api/admin/licenses?tipo=FULL&limit=1', 'licenses'),
      _total('/api/admin/products?limit=1', 'products'),
      _total('/api/admin/products?status=published&limit=1', 'products'),
      _total('/api/admin/products?status=draft&limit=1', 'products'),
      _total('/api/admin/products?status=archived&limit=1', 'products'),
      _total('/api/admin/product-plans?limit=1', 'plans'),
      _total('/api/admin/product-plans?is_active=true&limit=1', 'plans'),
      _total('/api/admin/projects', 'projects'),
      _total('/api/admin/activations?limit=1', 'activations'),
      _total('/api/admin/activations?estado=ACTIVA&limit=1', 'activations'),
      _total('/api/admin/activations?estado=REVOCADA&limit=1', 'activations'),
    ]);

    return stats.copyWith(
      totalCustomers: results[0],
      totalCompanies: stats.totalCompanies > 0
          ? stats.totalCompanies
          : results[0],
      totalLicenses: results[1],
      activeLicenses: results[2],
      expiredLicenses: results[3],
      blockedLicenses: results[4],
      pendingLicenses: results[5],
      demoLicenses: results[6],
      fullLicenses: results[7],
      totalProducts: results[8],
      publishedProducts: results[9],
      draftProducts: results[10],
      archivedProducts: results[11],
      totalPlans: results[12],
      activePlans: results[13],
      totalProjects: results[14],
      totalActivations: results[15],
      activeActivations: results[16],
      revokedActivations: results[17],
    );
  }

  Future<int> _total(String path, String listKey) async {
    try {
      final data = await _client.get(path);
      final total = data['total'];
      if (total != null) return DashboardStats._toInt(total);
      final list = data[listKey];
      if (list is List) return list.length;
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
