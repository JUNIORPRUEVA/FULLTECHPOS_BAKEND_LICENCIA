import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../models/license.dart';

class LicensesService {
  final ApiClient _client;
  final SessionManager _sessionManager;

  LicensesService({required SessionManager sessionManager})
      : _sessionManager = sessionManager,
        _client = ApiClient(sessionManager: sessionManager);

  Future<void> _ensureInit() => _sessionManager.init();

  Future<List<License>> listLicenses({int page = 1, int limit = 50}) async {
    await _ensureInit();
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
    await _ensureInit();
    final data = await _client.get('/api/admin/licenses/$id');
    final lic = data['license'] as Map<String, dynamic>? ?? data;
    return License.fromJson(lic);
  }

  Future<License> createLicense(Map<String, dynamic> body) async {
    await _ensureInit();
    final data = await _client.post('/api/admin/licenses', body);
    final lic = data['license'] as Map<String, dynamic>? ?? data;
    return License.fromJson(lic);
  }

  Future<License> updateLicense(String id, Map<String, dynamic> body) async {
    await _ensureInit();
    final data = await _client.patch('/api/admin/licenses/$id', body);
    final lic = data['license'] as Map<String, dynamic>? ?? data;
    return License.fromJson(lic);
  }

  Future<void> deleteLicense(String id) async {
    await _ensureInit();
    await _client.delete('/api/admin/licenses/$id');
  }

  Future<void> blockLicense(String id) async {
    await _ensureInit();
    await _client.patch('/api/admin/licenses/$id/bloquear', {});
  }

  Future<void> unblockLicense(String id) async {
    await _ensureInit();
    await _client.patch('/api/admin/licenses/$id/desbloquear', {});
  }

  Future<void> activateManual(String id) async {
    await _ensureInit();
    await _client.patch('/api/admin/licenses/$id/activar-manual', {});
  }

  /// Activate a license using the dedicated activation endpoint.
  /// POST /api/admin/licenses/{id}/activate
  /// Throws ApiException with the backend message on failure.
  Future<void> activateLicense(String id) async {
    await _ensureInit();
    await _client.post('/api/admin/licenses/$id/activate', {});
  }

  Future<void> extendDays(String id, int days) async {
    await _ensureInit();
    await _client.patch('/api/admin/licenses/$id/extender-dias', {'dias': days});
  }

  /// Descarga el archivo de licencia activo (firmado) listo para usar en FULLPOS.
  /// El archivo se genera con device_id=null para que sirva en cualquier PC.
  /// Retorna el contenido JSON del archivo de licencia.
  Future<Map<String, dynamic>> downloadLicenseFile(String id) async {
    await _ensureInit();
    // Usamos ensure_active=true para activar automáticamente si está pendiente
    // y download=1 para obtener el archivo como descarga
    final data = await _client.get(
      '/api/admin/licenses/$id/license-file?ensure_active=true&download=1',
    );
    return data;
  }
}
