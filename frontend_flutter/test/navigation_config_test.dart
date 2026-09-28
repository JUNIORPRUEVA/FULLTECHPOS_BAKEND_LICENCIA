import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:appyra_admin/core/auth/auth_service.dart';
import 'package:appyra_admin/core/auth/session_manager.dart';
import 'package:appyra_admin/core/config/appyra_projects.dart';
import 'package:appyra_admin/core/config/navigation_config.dart';
import 'package:appyra_admin/core/router/app_router.dart';
import 'package:appyra_admin/core/widgets/app_sidebar.dart';

/// Aplana las rutas declaradas en el router (incluye las de `ShellRoute`).
List<String> _collectPaths(RouteBase route, [String parentPrefix = '']) {
  if (route is GoRoute) {
    final path = route.path.startsWith('/')
        ? route.path
        : '$parentPrefix${route.path}';
    return [
      path,
      ...route.routes.expand((child) => _collectPaths(child, path)),
    ];
  }
  if (route is ShellRoute) {
    return route.routes
        .expand((child) => _collectPaths(child, parentPrefix))
        .toList();
  }
  return const <String>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> declaredPaths;

  setUpAll(() {
    final router = AppRouter.build(
      AuthService(sessionManager: SessionManager()),
    );
    declaredPaths = router.configuration.routes
        .expand((route) => _collectPaths(route))
        .toList();
  });

  group('Appyra project mode — navegación', () {
    test('los módulos legacy están ocultos por defecto', () {
      expect(NavigationConfig.legacyModulesVisible, isFalse);
      expect(NavigationConfig.showLegacyModules, isFalse);
    });

    test('la navegación visible es únicamente Proyectos', () {
      final labels = visibleSidebarItems.map<String>((item) {
        if (item is AppSidebarGroupItem) return item.label;
        return (item as AppSidebarItem).label;
      }).toList();

      expect(labels, <String>['Proyectos']);
      expect(labels, isNot(contains('Panel')));
      expect(labels, isNot(contains('DaleVentas Cloud')));
      expect(labels, isNot(contains('Clientes')));
      expect(labels, isNot(contains('Licencias')));
      expect(labels, isNot(contains('Uso del sistema')));
      expect(labels, isNot(contains('Pagos')));
    });

    test('el Panel queda preservado pero oculto en project mode', () {
      final panel = sidebarItems.firstWhere(
        (item) => item is AppSidebarItem && item.label == 'Panel',
      );

      expect(isProjectModeHiddenSidebarItem(panel), isTrue);
      expect(isLegacySidebarItem(panel), isFalse);
      expect(projectModeHiddenSidebarRoutes, <String>['/admin/panel']);
    });

    test('la ruta inicial del administrador es Proyectos', () {
      expect(NavigationConfig.homeRoute, '/admin/proyectos');
      expect(declaredPaths, contains(NavigationConfig.homeRoute));
      // El Panel sigue declarado aunque ya no sea destino ni esté en el sidebar
      expect(declaredPaths, contains('/admin/panel'));
    });

    test('cada proyecto visible abre una ruta declarada en el router', () {
      for (final project in AppyraProjects.projectModeVisible) {
        expect(
          declaredPaths,
          contains(project.route),
          reason:
              'El proyecto ${project.code} debe abrir una ruta real '
              '(${project.route})',
        );
      }
    });

    test('Configuración mantiene sus opciones globales', () {
      expect(visibleSettingsSidebarItems.map((item) => item.label), <String>[
        'Usuarios',
      ]);
    });

    test('los módulos legacy siguen registrados con su ruta', () {
      expect(
        legacySidebarRoutes,
        containsAll(<String>[
          '/admin/clientes',
          '/admin/licencias',
          '/admin/daleventas-licencias',
          '/admin/uso',
          '/admin/pagos',
        ]),
      );
    });

    test('cada ruta legacy sigue declarada en el router', () {
      for (final route in legacySidebarRoutes) {
        expect(
          declaredPaths,
          contains(route),
          reason: 'La ruta legacy $route debe permanecer declarada',
        );
      }
    });

    test('cada item de navegación apunta a una ruta declarada', () {
      final navRoutes = <String>[
        ...sidebarItems.expand((item) {
          if (item is AppSidebarGroupItem) {
            return item.children.map((child) => child.route);
          }
          return <String>[(item as AppSidebarItem).route];
        }),
        ...settingsSidebarItems.map((item) => item.route),
      ];

      for (final route in navRoutes) {
        expect(
          declaredPaths,
          contains(route),
          reason: 'La navegación no debe apuntar a rutas inexistentes ($route)',
        );
      }
    });

    test('el grupo Clientes se clasifica como legacy', () {
      final clientes = sidebarItems.firstWhere(
        (item) => item is AppSidebarGroupItem && item.label == 'Clientes',
      );
      expect(isLegacySidebarItem(clientes), isTrue);
    });
  });

  group('Appyra project mode — sidebar renderizado', () {
    Widget buildSidebar({required bool expanded, String? route}) {
      return ChangeNotifierProvider<AuthService>(
        create: (_) => AuthService(sessionManager: SessionManager()),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: AppSidebar(
                currentRoute: route ?? NavigationConfig.homeRoute,
                forceExpanded: expanded,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('expandido: Proyectos arriba y Configuración anclada al fondo', (
      tester,
    ) async {
      await tester.pumpWidget(buildSidebar(expanded: true));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Proyectos'), findsOneWidget);
      expect(find.text('Configuración'), findsOneWidget);
      // La sección arranca colapsada (Usuarios se despliega al tocarla)
      expect(
        tester
            .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
            .crossFadeState,
        CrossFadeState.showSecond,
      );

      // Panel y módulos legacy fuera de la navegación normal
      expect(find.text('Panel'), findsNothing);
      expect(find.text('Clientes'), findsNothing);
      expect(find.text('Licencias'), findsNothing);
      expect(find.text('DaleVentas Cloud'), findsNothing);
      expect(find.text('Uso del sistema'), findsNothing);
      expect(find.text('Pagos'), findsNothing);

      final sidebarRect = tester.getRect(find.byType(AppSidebar));
      final proyectosBottom = tester.getBottomLeft(find.text('Proyectos')).dy;
      final configTop = tester.getTopLeft(find.text('Configuración')).dy;

      // Configuración NO está justo debajo de Proyectos: está anclada al fondo
      expect(configTop, greaterThan(proyectosBottom + 200));
      expect(configTop, greaterThan(sidebarRect.bottom - 160));

      // Usuarios sigue siendo accesible desde Configuración
      await tester.tap(find.text('Configuración'));
      await tester.pumpAndSettle();
      expect(find.text('Usuarios'), findsOneWidget);
      expect(
        tester
            .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
            .crossFadeState,
        CrossFadeState.showFirst,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('colapsado: icono de Proyectos arriba y Configuración abajo', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSidebar(expanded: false, route: '/admin/panel'),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Colapsado: solo iconos, sin etiquetas
      expect(find.text('Proyectos'), findsNothing);
      expect(find.text('Configuración'), findsNothing);
      expect(find.text('Panel'), findsNothing);

      final proyectosIcon = find.byIcon(Icons.folder_copy_outlined);
      final settingsIcon = find.byIcon(Icons.settings_outlined);
      expect(proyectosIcon, findsOneWidget);
      expect(settingsIcon, findsOneWidget);

      final sidebarRect = tester.getRect(find.byType(AppSidebar));
      expect(
        tester.getCenter(proyectosIcon).dy,
        lessThan(sidebarRect.center.dy),
      );
      expect(
        tester.getBottomLeft(settingsIcon).dy,
        greaterThan(sidebarRect.bottom - 160),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ventana pequeña: sin overflow y Configuración accesible', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final Size size in <Size>[
        const Size(320, 420),
        const Size(320, 260),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(buildSidebar(expanded: true));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Configuración'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byType(ListView), findsOneWidget);
      }
    });
  });
}
