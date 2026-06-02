import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class SessionManager {
  SharedPreferences? _prefs;
  String? _sessionId;
  bool _initialized = false;

  String? get sessionId {
    if (!_initialized) {
      // Si no se ha inicializado, lanzar advertencia pero devolver null
      // para no romper el flujo. El init() debe llamarse antes.
    }
    return _sessionId;
  }

  bool get hasSession => _sessionId != null && _sessionId!.isNotEmpty;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _sessionId = _prefs!.getString(AppConfig.sessionKey);
    _initialized = true;
  }

  Future<void> setSession(String sessionId) async {
    await init();
    _sessionId = sessionId;
    await _prefs!.setString(AppConfig.sessionKey, sessionId);
  }

  Future<void> clearSession() async {
    await init();
    _sessionId = null;
    await _prefs!.remove(AppConfig.sessionKey);
  }
}
