import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../models/license.dart';

class LicensesService {
  final ApiClient _client;

  LicensesService({required SessionManager sessionManager})
      : _client = ApiClient(sessionManager: sessionManager);

  Future<List<License>> listLicenses({int page = 1, int limit = 50}) async {
    final data = await _client
        .get('/api/admin/licenses?page=$page&limit=$limit');
    final list = data['licenses'] as List<dynamic>? ??
        data['data'] as List<dynamic>? ??
        [];
    return list
        .map((e) => License.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<License> getLicense(String id) async {
    final data = await _client.get('/api/admin/licenses/$id');
    final lic = data['license'] as Map<String, dynamic>? ?? data;
    return License.fromJson(lic);
  }

  Future<License> createLicense(Map<String, dynamic> body) async {
    final data = await _client.post('/api/admin/licenses', body);
    final lic = data['license'] as Map<String, dynamic>? ?? data;
    return License.fromJson(lic);
  }

  Future<License> updateLicense(String id, Map<String, dynamic> body) async {
    final data = await _client.patch('/api/admin/licenses/$id', body);
    final lic = data['license'] as Map<String, dynamic>? ?? data;
    return License.fromJson(lic);
  }

  Future<void> deleteLicense(String id) async {
    await _client.delete('/api/admin/licenses/$id');
  }

  Future<void> blockLicense(String id) async {
    await _client.patch('/api/admin/licenses/$id/bloquear', {});
  }

  Future<void> unblockLicense(String id) async {
    await _client.patch('/api/admin/licenses/$id/desbloquear', {});
  }

  Future<void> activateManual(String id) async {
    await _client.patch('/api/admin/licenses/$id/activar-manual', {});
  }

  Future<void> extendDays(String id, int days) async {
    await _client.patch('/api/admin/licenses/$id/extender-dias', {'dias': days});
  }
}
