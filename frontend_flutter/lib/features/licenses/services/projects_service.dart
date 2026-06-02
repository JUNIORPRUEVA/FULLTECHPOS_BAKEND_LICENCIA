import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../models/project.dart';

class ProjectsService {
  final ApiClient _client;

  ProjectsService({required SessionManager sessionManager})
      : _client = ApiClient(sessionManager: sessionManager);

  Future<List<Project>> listProjects() async {
    final data = await _client.get('/api/admin/projects');
    final list = data['projects'] as List<dynamic>? ?? [];
    return list
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Project> getProjectById(String id) async {
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
  }) async {
    final data = await _client.patch(
      '/api/admin/projects/$projectId',
      {
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
      },
    );
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
    final data = await _client.patch(
      '/api/admin/projects/$projectId/billing-settings',
      {
        'monthly_price': monthlyPrice,
        'currency': currency,
        'demo_days': demoDays,
        'min_purchase_months': minPurchaseMonths,
        'is_paid_project': isPaidProject,
        'allow_demo': allowDemo,
        'is_active': isActive,
      },
    );
    return Project.fromJson(data['project'] as Map<String, dynamic>? ?? data);
  }
}
