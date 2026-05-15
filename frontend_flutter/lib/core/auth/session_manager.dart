import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class SessionManager {
  late SharedPreferences _prefs;
  String? _sessionId;

  String? get sessionId => _sessionId;
  bool get hasSession => _sessionId != null && _sessionId!.isNotEmpty;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _sessionId = _prefs.getString(AppConfig.sessionKey);
  }

  Future<void> setSession(String sessionId) async {
    _sessionId = sessionId;
    await _prefs.setString(AppConfig.sessionKey, sessionId);
  }

  Future<void> clearSession() async {
    _sessionId = null;
    await _prefs.remove(AppConfig.sessionKey);
  }
}
