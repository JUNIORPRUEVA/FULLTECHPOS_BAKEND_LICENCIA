import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../models/project.dart';
import '../models/project_profile.dart';

class ProjectsService {
  final ApiClient _client;
  final SessionManager _sessionManager;

  ProjectsService({required SessionManager sessionManager})
    : _sessionManager = sessionManager,
      _client = ApiClient(sessionManager: sessionManager);

  /// Inicializa el SessionManager si no lo está.
  Future<void> _ensureInit() => _sessionManager.init();

  Future<List<Project>> listProjects() async {
    await _ensureInit();
    final data = await _client.get('/api/admin/projects');
    final list = data['projects'] as List<dynamic>? ?? [];
    return list
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .where((project) => project.code.toUpperCase() != 'DEFAULT')
        .toList();
  }

  Future<Project> getProjectById(String id) async {
    await _ensureInit();
    final data = await _client.get('/api/admin/projects/$id');
    return Project.fromJson(data['project'] as Map<String, dynamic>? ?? data);
  }

  Future<Project> updateProject({
    required String projectId,
    required String name,
    required String code,
    String? description,
    required double monthlyPrice,
    required String currency,
    required int demoDays,
    required int minPurchaseMonths,
    required bool isPaidProject,
    required bool allowDemo,
    required bool isActive,
    required ProjectProfile profile,
  }) async {
    await _ensureInit();
    final data = await _client.patch('/api/admin/projects/$projectId', {
      'name': name,
      'code': code,
      'description': description,
      'monthly_price': monthlyPrice,
      'currency': currency,
      'demo_days': demoDays,
      'min_purchase_months': minPurchaseMonths,
      'is_paid_project': isPaidProject,
      'allow_demo': allowDemo,
      'is_active': isActive,
      'product_profile': profile.toJson(),
    });
    return Project.fromJson(data['project'] as Map<String, dynamic>? ?? data);
  }

  Future<Project> updateBillingSettings({
    required String projectId,
    required double monthlyPrice,
    required String currency,
    required int demoDays,
    required int minPurchaseMonths,
    required bool isPaidProject,
    required bool allowDemo,
    required bool isActive,
  }) async {
    await _ensureInit();
    final data = await _client
        .patch('/api/admin/projects/$projectId/billing-settings', {
          'monthly_price': monthlyPrice,
          'currency': currency,
          'demo_days': demoDays,
          'min_purchase_months': minPurchaseMonths,
          'is_paid_project': isPaidProject,
          'allow_demo': allowDemo,
          'is_active': isActive,
        });
    return Project.fromJson(data['project'] as Map<String, dynamic>? ?? data);
  }
}
