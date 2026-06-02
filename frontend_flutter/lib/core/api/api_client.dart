import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../auth/session_manager.dart';
import 'api_exception.dart';

/// Excepcion especifica para 401 - sesion expirada o invalida.
/// Las pantallas deben detectar esta excepcion y NO mostrar error con Reintentar.
class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException(this.message);

  @override
  String toString() => message;
}

/// Callback para manejo global de 401 (sesion expirada).
/// Se asigna desde AuthService para limpiar sesion y redirigir al login.
typedef UnauthorizedCallback = void Function(String message);

class ApiClient {
  final SessionManager _sessionManager;

  /// Callback global que se invoca cuando cualquier endpoint devuelve 401.
  /// Se ejecuta SINCRONICAMENTE antes de lanzar la excepcion.
  static UnauthorizedCallback? onUnauthorized;

  ApiClient({required SessionManager sessionManager})
    : _sessionManager = sessionManager;

  Map<String, String> _headers({bool auth = true}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final sessionId = _sessionManager.sessionId;
      if (sessionId != null) {
        headers['x-session-id'] = sessionId;
      }
      if (AppConfig.isDebug) {
        debugPrint('[API] auth header present: ${sessionId != null && sessionId.isNotEmpty}');
      }
    }
    return headers;
  }

  Uri _uri(String path) => Uri.parse('${AppConfig.baseUrl}$path');

  Future<Map<String, dynamic>> get(String path) async {
    final uri = _uri(path);
    if (AppConfig.isDebug) {
      debugPrint('[API] GET $uri');
    }
    try {
      final response = await http
          .get(uri, headers: _headers())
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on UnauthorizedException {
      rethrow;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Error de conexion: $e');
    }
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final uri = _uri(path);
    if (AppConfig.isDebug) {
      debugPrint('[API] POST $uri');
    }
    try {
      final response = await http
          .post(
            uri,
            headers: _headers(auth: auth),
            body: jsonEncode(body),
          )
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on UnauthorizedException {
      rethrow;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Error de conexion: $e');
    }
  }

  Future<Map<String, dynamic>> postNoAuth(
    String path,
    Map<String, dynamic> body,
  ) => post(path, body, auth: false);

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _uri(path);
    if (AppConfig.isDebug) {
      debugPrint('[API] PUT $uri');
    }
    try {
      final response = await http
          .put(uri, headers: _headers(), body: jsonEncode(body))
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on UnauthorizedException {
      rethrow;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Error de conexion: $e');
    }
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _uri(path);
    if (AppConfig.isDebug) {
      debugPrint('[API] PATCH $uri');
    }
    try {
      final response = await http
          .patch(uri, headers: _headers(), body: jsonEncode(body))
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on UnauthorizedException {
      rethrow;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Error de conexion: $e');
    }
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final uri = _uri(path);
    if (AppConfig.isDebug) {
      debugPrint('[API] DELETE $uri');
    }
    try {
      final response = await http
          .delete(uri, headers: _headers())
          .timeout(AppConfig.requestTimeout);
      return _handleResponse(response);
    } on UnauthorizedException {
      rethrow;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Error de conexion: $e');
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    Map<String, dynamic> data = {};
    try {
      if (response.body.isNotEmpty) {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      data = {'message': response.body};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    final message =
        data['message'] as String? ??
        data['error'] as String? ??
        _statusMessage(response.statusCode);

    // Manejo SINCRONICO de 401: ejecutar callback ANTES de lanzar excepcion
    if (response.statusCode == 401) {
      final callback = onUnauthorized;
      if (callback != null) {
        callback(message);
      }
      // Lanzar excepcion especifica para que las pantallas NO muestren Reintentar
      throw UnauthorizedException(message);
    }

    throw ApiException(message, statusCode: response.statusCode, data: data);
  }

  String _statusMessage(int code) {
    switch (code) {
      case 400:
        return 'Solicitud invalida';
      case 401:
        return 'Tu sesion expiro. Inicia sesion nuevamente.';
      case 403:
        return 'No tienes permisos para ver este recurso.';
      case 404:
        return 'Recurso no encontrado';
      case 409:
        return 'Conflicto: el recurso ya existe';
      case 500:
        return 'Error interno del servidor';
      default:
        return 'Error HTTP $code';
    }
  }
}
