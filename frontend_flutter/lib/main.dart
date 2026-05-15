import 'package:flutter/material.dart';
import 'app.dart';
import 'core/auth/session_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sessionManager = SessionManager();
  await sessionManager.init();
  runApp(App(sessionManager: sessionManager));
}
