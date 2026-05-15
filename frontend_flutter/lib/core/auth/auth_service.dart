import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../auth/session_manager.dart';
import '../../features/auth/models/admin_user.dart';

class AuthService extends ChangeNotifier {
  final SessionManager _sessionManager;
  late final ApiClient _apiClient;

  bool _isInitialized = false;
  bool _isLoggedIn = false;
  AdminUser? _currentUser;

  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _isLoggedIn;
  AdminUser? get currentUser => _currentUser;
  String get username => _currentUser?.username ?? 'Admin';

  AuthService({required SessionManager sessionManager})
      : _sessionManager = sessionManager {
    _apiClient = ApiClient(sessionManager: sessionManager);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_sessionManager.hasSession) {
      try {
        final data = await _apiClient.get('/api/verify-session');
        if (data['success'] == true) {
          _isLoggedIn = true;
          _currentUser = AdminUser(
            username: data['username'] as String? ?? 'Admin',
          );
        } else {
          await _sessionManager.clearSession();
        }
      } on ApiException catch (e) {
        if (e.isUnauthorized || e.isForbidden) {
          await _sessionManager.clearSession();
        } else {
          // Transient error — keep session alive
          _isLoggedIn = true;
          _currentUser = AdminUser(username: 'Admin');
        }
      } catch (_) {
        // Transient error — keep session alive
        _isLoggedIn = true;
        _currentUser = AdminUser(username: 'Admin');
      }
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final data = await _apiClient.postNoAuth('/api/login', {
      'username': username,
      'password': password,
    });

    if (data['success'] == true) {
      final sessionId = data['sessionId'] as String?;
      if (sessionId == null || sessionId.isEmpty) {
        throw const ApiException('Sesión inválida recibida del servidor');
      }
      await _sessionManager.setSession(sessionId);
      _isLoggedIn = true;
      _currentUser = AdminUser(username: username);
      notifyListeners();
    } else {
      throw ApiException(
        data['message'] as String? ?? 'Credenciales inválidas',
        statusCode: 401,
      );
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.post('/api/logout', {});
    } catch (_) {
      // Ignore logout errors
    }
    await _sessionManager.clearSession();
    _isLoggedIn = false;
    _currentUser = null;
    notifyListeners();
  }
}
