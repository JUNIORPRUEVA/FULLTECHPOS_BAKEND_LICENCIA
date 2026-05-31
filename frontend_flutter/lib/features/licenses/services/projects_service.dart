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
}
