import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:appyra_admin/core/auth/session_manager.dart';
import 'package:appyra_admin/features/daleventas_licenses/models/daleventas_company_license.dart';
import 'package:appyra_admin/features/daleventas_licenses/pages/daleventas_project_shell.dart';
import 'package:appyra_admin/features/daleventas_licenses/services/daleventas_license_service.dart';
import 'package:appyra_admin/features/usage_analytics/models/usage_analytics.dart';
import 'package:appyra_admin/features/usage_analytics/services/usage_analytics_service.dart';

/// Licencias de prueba: 2 activas (una por vencer), 1 vencida, 2 demos y
/// 1 bloqueada.
List<DaleVentasCompanyLicense> _licenses() {
  final now = DateTime.now();
  DaleVentasCompanyLicense build({
    required String id,
    required String name,
    required String status,
    bool usable = true,
    int daysRemaining = 30,
    DateTime? endsAt,
    String commercialStatus = 'DEMO',
  }) {
    return DaleVentasCompanyLicense(
      companyId: id,
      companyName: name,
      status: status,
      isUsable: usable,
      daysRemaining: daysRemaining,
      maxUsers: 3,
      maxProducts: 300,
      usersUsed: 1,
      productsUsed: 5,
      licenseExpiresAt: endsAt,
      commercial: DaleVentasCommercialProfile(
        id: 'p-$id',
        externalCompanyId: id,
        commercialStatus: commercialStatus,
        planClassification: 'STANDARD',
      ),
    );
  }

  return <DaleVentasCompanyLicense>[
    build(
      id: '1',
      name: 'Panadería Central',
      status: 'ACTIVE',
      daysRemaining: 180,
      endsAt: now.add(const Duration(days: 180)),
      commercialStatus: 'PURCHASED',
    ),
    build(
      id: '2',
      name: 'Mini Market El Sol',
      status: 'ACTIVE',
      daysRemaining: 5,
      endsAt: now.add(const Duration(days: 5)),
      commercialStatus: 'PURCHASED',
    ),
    build(
      id: '3',
      name: 'Ferretería López',
      status: 'EXPIRED',
      usable: false,
      daysRemaining: -4,
      endsAt: now.subtract(const Duration(days: 4)),
      commercialStatus: 'LOST',
    ),
    build(id: '4', name: 'Farmacia Nueva', status: 'TRIAL'),
    build(
      id: '5',
      name: 'Bodega Sur',
      status: 'TRIAL',
      usable: false,
      daysRemaining: -1,
      endsAt: now.subtract(const Duration(days: 1)),
    ),
    build(id: '6', name: 'Licorería 24h', status: 'BLOCKED', usable: false),
  ];
}

class _FakeLicenseService extends DaleVentasLicenseService {
  _FakeLicenseService() : super(sessionManager: SessionManager());

  @override
  Future<DaleVentasLicensePageResult> listCompanies({
    int page = 1,
    int limit = 50,
    String query = '',
    String status = '',
    String plan = '',
  }) async {
    final items = _licenses();
    return DaleVentasLicensePageResult(
      page: 1,
      limit: limit,
      total: items.length,
      items: items,
    );
  }
}

class _FakeUsageService extends UsageAnalyticsService {
  _FakeUsageService() : super(sessionManager: SessionManager());

  @override
  Future<UsageDashboardData> getDashboard({
    String? projectCode,
    String? appCode,
    String? status,
    String? from,
    String? to,
    int page = 1,
    int limit = 50,
  }) async {
    return const UsageDashboardData(
      overview: UsageOverview(
        activeToday: 12,
        active7Days: 30,
        inactive15Days: 4,
        inactive30Days: 2,
        activeSeconds: 7200,
        eventsCount: 900,
        sessionsCount: 45,
        devicesCount: 18,
      ),
      accounts: UsageAccountsResult(page: 1, limit: 50, total: 0, accounts: []),
    );
  }
}

Widget _shell({Widget? licensesTab}) {
  return MaterialApp(
    home: DaleVentasProjectShell(
      licenseService: _FakeLicenseService(),
      usageService: _FakeUsageService(),
      licensesTab:
          licensesTab ?? const Scaffold(body: Text('CONSOLA LICENCIAS')),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpPhoneShell(
    WidgetTester tester, {
    Widget? licensesTab,
  }) async {
    // Tamaño realista de móvil (no se puede usar setSurfaceSize aquí).
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell(licensesTab: licensesTab));
    await tester.pumpAndSettle();
  }

  group('Consola del proyecto DaleVentas', () {
    testWidgets('abre en Reporte y muestra la barra inferior con 3 secciones', (
      tester,
    ) async {
      await pumpPhoneShell(tester);

      // Barra inferior de la mini-app
      expect(find.text('Reporte'), findsOneWidget);
      expect(find.text('Licencias'), findsOneWidget);
      expect(find.text('Boletín'), findsOneWidget);

      // Identidad del proyecto en la cabecera degradada del reporte
      expect(find.textContaining('DaleVentas POS'), findsOneWidget);
      // Reporte NO tiene barra de aplicación: solo el botón flotante de volver
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
      expect(find.text('Reporte de licencias'), findsOneWidget);
      // Sin desplazar: no hay barra compacta
      expect(find.byKey(const ValueKey('report-compact-bar')), findsNothing);

      // Resumen de licencias (primera pantalla)
      expect(find.text('Empresas'), findsOneWidget);
      expect(find.text('registradas'), findsOneWidget);
      expect(find.text('Licencias de pago'), findsOneWidget);
      expect(find.text('Por vencer'), findsWidgets);
      expect(find.text('Vencidas'), findsWidgets);
      expect(find.text('Pruebas (demo)'), findsOneWidget);
      expect(find.text('Bloqueadas'), findsOneWidget);

      // Secciones siguientes (hay que desplazarse en pantalla de móvil)
      for (final label in <String>[
        'Estado comercial',
        'Licencias por plan',
        'Actividad de uso',
        'Atención requerida',
      ]) {
        await tester.scrollUntilVisible(find.text(label), 260, maxScrolls: 40);
        expect(find.text(label), findsOneWidget);
      }

      // Los clientes con problemas aparecen listados
      await tester.scrollUntilVisible(
        find.text('Ferretería López'),
        220,
        maxScrolls: 40,
      );
      expect(find.text('Mini Market El Sol'), findsOneWidget);
      expect(find.text('Bloqueada'), findsOneWidget);

      // Al desplazar aparece la barra compacta (el botón ya no se solapa)
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('report-compact-bar')), findsOneWidget);
    });

    testWidgets('cambia de sección y actualiza la cabecera', (tester) async {
      await pumpPhoneShell(tester);

      await tester.tap(find.text('Licencias'));
      await tester.pumpAndSettle();
      // Barra limpia: título de la sección + botón de volver
      expect(find.text('DaleVentasPOS Licencias'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.text('CONSOLA LICENCIAS'), findsOneWidget);

      await tester.tap(find.text('Boletín'));
      await tester.pumpAndSettle();
      expect(find.text('Boletín del proyecto'), findsNWidgets(2));
      expect(find.text('Nueva publicación'), findsOneWidget);
      expect(find.text('El boletín está vacío'), findsOneWidget);

      // La pestaña de Licencias sigue montada (no se recarga al volver).
      expect(
        find.text('CONSOLA LICENCIAS', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('el boletín publica un aviso y lo conserva', (tester) async {
      await pumpPhoneShell(tester);
      await tester.tap(find.text('Boletín'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novedad'));
      await tester.pump();
      await tester.enterText(
        find.byType(TextFormField).last,
        'Se actualizó el precio del plan Negocio.',
      );
      await tester.tap(find.text('Publicar en el boletín'));
      await tester.pumpAndSettle();

      expect(find.text('Novedad'), findsWidgets);
      expect(
        find.text('Se actualizó el precio del plan Negocio.'),
        findsOneWidget,
      );
      expect(find.text('1 aviso'), findsOneWidget);
    });

    testWidgets('el botón atrás vuelve a la lista de proyectos', (
      tester,
    ) async {
      var exited = false;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: DaleVentasProjectShell(
            licenseService: _FakeLicenseService(),
            usageService: _FakeUsageService(),
            licensesTab: const Scaffold(body: Text('CONSOLA LICENCIAS')),
            onExit: () => exited = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      expect(exited, isTrue);
    });
  });
}
