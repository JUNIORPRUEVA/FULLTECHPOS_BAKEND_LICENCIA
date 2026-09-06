import 'package:flutter/material.dart';
import 'app.dart';
import 'core/auth/session_manager.dart';
import 'core/config/app_config.dart';
import 'core/debug/runtime_diagnostics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('APPYRA API BASE URL: ${AppConfig.baseUrl}');
  debugPrint('APPYRA ENVIRONMENT: ${AppConfig.environmentName}');
  debugPrint('APPYRA BUILD VERSION: ${AppConfig.appVersion}');
  debugPrint('APPYRA EXECUTABLE: ${runningExecutablePath()}');
  final sessionManager = SessionManager();
  await sessionManager.init();
  runApp(App(sessionManager: sessionManager));
}
