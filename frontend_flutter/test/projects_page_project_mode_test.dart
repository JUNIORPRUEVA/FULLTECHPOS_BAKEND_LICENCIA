import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:appyra_admin/core/auth/session_manager.dart';
import 'package:appyra_admin/features/licenses/models/project.dart';
import 'package:appyra_admin/features/licenses/services/projects_service.dart';
import 'package:appyra_admin/features/projects/pages/projects_page.dart';

/// Servicio falso: devuelve los proyectos del escenario sin tocar la red.
class _FakeProjectsService extends ProjectsService {
  _FakeProjectsService(this._projects)
    : super(sessionManager: SessionManager());

  final List<Project> _projects;

  @override
  Future<List<Project>> listProjects() async => List<Project>.of(_projects);
}

/// Servicio falso que simula un fallo de red/API.
class _ThrowingProjectsService extends ProjectsService {
  _ThrowingProjectsService() : super(sessionManager: SessionManager());

  @override
  Future<List<Project>> listProjects() async =>
      throw Exception('network unavailable');
}

Project _project(String id, String code, String name) =>
    Project(id: id, code: code, name: name, isActive: true);

/// Escenario equivalente a la base actual: proyectos legacy + el activo.
final List<Project> _databaseProjects = <Project>[
  _project('id-default', 'DEFAULT', 'Default Project'),
  _project('id-fullpos', 'FULLPOS', 'FULLPOS'),
  _project('id-fullcredit', 'FULLCREDIT', 'FULLCREDIT'),
  _project('id-daleventas', 'DALEVENTAS', 'DaleVentas POS'),
];

/// Escenario real de producción hoy: NO existe fila DALEVENTAS.
final List<Project> _databaseProjectsWithoutDaleventas = <Project>[
  _project('id-default', 'DEFAULT', 'Default Project'),
  _project('id-fullpos', 'FULLPOS', 'FULLPOS'),
  _project('id-fullcredit', 'FULLCREDIT', 'FULLCREDIT'),
];

Future<void> _pumpProjectsPage(
  WidgetTester tester,
  List<Project> projects,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProjectsPage(service: _FakeProjectsService(projects)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Router real con la ruta existente de la consola de DaleVentas.
GoRouter _previewRouter(List<Project> projects) {
  return GoRouter(
    initialLocation: '/admin/proyectos',
    routes: [
      GoRoute(
        path: '/admin/proyectos',
        builder: (context, state) => Scaffold(
          body: ProjectsPage(service: _FakeProjectsService(projects)),
        ),
      ),
      GoRoute(
        path: '/admin/daleventas-licencias',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('CONSOLA DALEVENTAS'))),
      ),
    ],
  );
}

void _expectOnlyDaleVentasCard(WidgetTester tester) {
  expect(find.text('DaleVentas POS'), findsOneWidget);
  expect(find.text('Código: DALEVENTAS'), findsOneWidget);
  expect(find.text('Estado:'), findsOneWidget);
  expect(find.text('Activo'), findsOneWidget);
  expect(find.text('1 proyecto'), findsOneWidget);
  expect(find.text('Administrar proyecto'), findsOneWidget);

  // Los proyectos legacy no aparecen
  expect(find.text('FULLPOS'), findsNothing);
  expect(find.text('Código: FULLPOS'), findsNothing);
  expect(find.text('FULLCREDIT'), findsNothing);
  expect(find.text('Código: FULLCREDIT'), findsNothing);
  expect(find.text('Default Project'), findsNothing);
  expect(find.text('Código: DEFAULT'), findsNothing);
}

void main() {
  group('Appyra projects — pantalla Proyectos en project mode', () {
    testWidgets('con fila DALEVENTAS en la base: 1 proyecto visible', (
      tester,
    ) async {
      await _pumpProjectsPage(tester, _databaseProjects);

      _expectOnlyDaleVentasCard(tester);
      // Con fila real, se habilita la edición del proyecto
      expect(find.byTooltip('Editar proyecto'), findsOneWidget);
      expect(find.text('4 proyectos'), findsNothing);
    });

    testWidgets('sin fila DALEVENTAS: la tarjeta igual aparece (Activo)', (
      tester,
    ) async {
      await _pumpProjectsPage(tester, _databaseProjectsWithoutDaleventas);

      _expectOnlyDaleVentasCard(tester);

      // El mensaje de "no provisionado" ya no existe en el flujo normal
      expect(find.textContaining('no está provisionado'), findsNothing);
      // Sin fila real no hay edición, pero sí acceso a la consola
      expect(find.byTooltip('Editar proyecto'), findsNothing);
      expect(find.text('Administrar proyecto'), findsOneWidget);
    });

    testWidgets('si la API falla, la entrada al proyecto sigue visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProjectsPage(service: _ThrowingProjectsService()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      _expectOnlyDaleVentasCard(tester);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('"Administrar proyecto" abre la consola existente', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: _previewRouter(_databaseProjects)),
      );
      await tester.pumpAndSettle();

      expect(find.text('CONSOLA DALEVENTAS'), findsNothing);
      await tester.tap(find.text('Administrar proyecto'));
      await tester.pumpAndSettle();

      // Navega a la ruta real de la consola de DaleVentas (sin pantallas nuevas)
      expect(find.text('CONSOLA DALEVENTAS'), findsOneWidget);
      expect(find.text('DaleVentas POS'), findsNothing);
    });
  });
}
