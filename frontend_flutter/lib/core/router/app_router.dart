import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/pages/login_page.dart';
import '../../features/customers/pages/customers_page.dart';
import '../../features/dashboard/pages/dashboard_page.dart';
import '../../features/licenses/pages/licenses_page.dart';
import '../../features/cloud_admin/pages/cloud_resource_page.dart';
import '../auth/auth_service.dart';
import '../layout/admin_shell.dart';
import '../widgets/loading_view.dart';

class AppRouter {
  AppRouter._();

  static GoRouter build(AuthService authService) {
    return GoRouter(
      initialLocation: '/login',
      refreshListenable: authService,
      redirect: (context, state) {
        final path = state.uri.path;

        if (!authService.isInitialized) {
          return path == '/splash' ? null : '/splash';
        }

        final isLogin = path == '/login';
        final isSplash = path == '/splash';

        if (!authService.isLoggedIn) {
          return isLogin ? null : '/login';
        }

        if (isLogin || isSplash) return '/admin/panel';
        return null;
      },
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) =>
              const Scaffold(body: LoadingView(message: 'Validando sesión...')),
        ),
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
        ShellRoute(
          builder: (context, state, child) => AdminShell(
            currentRoute: state.uri.path,
            pageTitle: _titleForRoute(state.uri.path),
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/admin/panel',
              builder: (context, state) => const DashboardPage(),
            ),
            GoRoute(
              path: '/admin/clientes',
              builder: (context, state) {
                final customerId = state.uri.queryParameters['customerId'];
                return CustomersPage(initialCustomerId: customerId);
              },
            ),
            GoRoute(
              path: '/admin/licencias',
              builder: (context, state) => const LicensesPage(),
            ),
            GoRoute(
              path: '/admin/configuracion-licencias',
              builder: (context, state) => const CloudLicenseConfigPage(),
            ),
            GoRoute(
              path: '/admin/activaciones',
              builder: (context, state) =>
                  const CloudResourcePage(config: activationResourceConfig),
            ),
            GoRoute(
              path: '/admin/proyectos',
              builder: (context, state) =>
                  const CloudResourcePage(config: projectResourceConfig),
            ),
            GoRoute(
              path: '/admin/productos',
              builder: (context, state) =>
                  const CloudResourcePage(config: productResourceConfig),
            ),
            GoRoute(
              path: '/admin/usuarios',
              builder: (context, state) =>
                  const CloudResourcePage(config: userResourceConfig),
            ),
            GoRoute(
              path: '/admin/configuracion-tienda',
              builder: (context, state) => const CloudStoreSettingsPage(),
            ),
          ],
        ),
      ],
    );
  }

  static String _titleForRoute(String route) {
    switch (route) {
      case '/admin/panel':
        return 'Panel';
      case '/admin/clientes':
        return 'Clientes';
      case '/admin/licencias':
        return 'Licencias';
      case '/admin/configuracion-licencias':
        return 'Configuración licencias';
      case '/admin/activaciones':
        return 'Activaciones';
      case '/admin/proyectos':
        return 'Proyectos';
      case '/admin/productos':
        return 'Productos';
      case '/admin/usuarios':
        return 'Usuarios del sistema';
      case '/admin/configuracion-tienda':
        return 'Configuración tienda';
      default:
        return 'Appyra Admin';
    }
  }
}
