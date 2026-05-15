import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/session_manager.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class App extends StatelessWidget {
  final SessionManager sessionManager;

  const App({super.key, required this.sessionManager});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SessionManager>.value(value: sessionManager),
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(sessionManager: sessionManager),
        ),
      ],
      child: Consumer<AuthService>(
        builder: (context, authService, _) {
          final router = AppRouter.build(authService);
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: 'Appyra Admin',
            theme: AppTheme.light,
            routerConfig: router,
          );
        },
      ),
    );
  }
}
