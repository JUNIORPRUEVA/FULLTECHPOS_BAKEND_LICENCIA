import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/config/app_config.dart';
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

  /// Descarga el archivo de licencia activo (firmado) listo para usar en cualquier proyecto.
  /// El archivo se genera con device_id=null para que sirva en cualquier PC.
  /// Retorna el contenido JSON del archivo de licencia.
  Future<Map<String, dynamic>> downloadLicenseFile(String id) async {
    await _ensureInit();
    debugPrint('[LICENSE_FILE_DOWNLOAD] licenseId: $id');
    debugPrint('[LICENSE_FILE_DOWNLOAD] endpoint: /api/admin/licenses/$id/license-file?ensure_active=true&download=1');
    try {
      final data = await _client.get(
        '/api/admin/licenses/$id/license-file?ensure_active=true&download=1',
      );
      debugPrint('[LICENSE_FILE_DOWNLOAD] SUCCESS: data keys = ${data.keys}');
      return data;
    } catch (e) {
      debugPrint('[LICENSE_FILE_DOWNLOAD] ERROR: $e');
      rethrow;
    }
  }

  /// Descarga el archivo de licencia como http.Response crudo (para guardar con file_picker en desktop).
  /// Usa http.get directamente para obtener la respuesta completa incluyendo headers.
  Future<http.Response> downloadLicenseFileRaw(String id) async {
    await _ensureInit();
    final uri = Uri.parse('${AppConfig.baseUrl}/api/admin/licenses/$id/license-file?ensure_active=true&download=1');
    debugPrint('[LICENSE_FILE_DOWNLOAD_RAW] uri: $uri');
    final sessionId = _sessionManager.sessionId;
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (sessionId != null) {
      headers['x-session-id'] = sessionId;
    }
    try {
      final response = await http.get(uri, headers: headers).timeout(AppConfig.requestTimeout);
      debugPrint('[LICENSE_FILE_DOWNLOAD_RAW] status: ${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      debugPrint('[LICENSE_FILE_DOWNLOAD_RAW] ERROR body: ${response.body}');
      throw ApiException(
        'Error al descargar archivo de licencia (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('[LICENSE_FILE_DOWNLOAD_RAW] ERROR: $e');
      rethrow;
    }
  }
}
