import 'package:flutter_test/flutter_test.dart';

import 'package:appyra_admin/features/daleventas_licenses/models/daleventas_company_license.dart';
import 'package:appyra_admin/features/daleventas_licenses/models/daleventas_license_report.dart';

final DateTime _now = DateTime(2026, 9, 27, 12);

DaleVentasCompanyLicense _company({
  required String id,
  required String name,
  required String status,
  bool usable = true,
  int daysRemaining = 10,
  DateTime? endsAt,
  String? commercialStatus,
  DateTime? nextFollowUpAt,
  String? planName,
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
    productsUsed: 10,
    licenseExpiresAt: endsAt,
    commercial: commercialStatus == null && planName == null
        ? null
        : DaleVentasCommercialProfile(
            id: 'p-$id',
            externalCompanyId: id,
            commercialStatus: commercialStatus ?? 'DEMO',
            planClassification: 'STANDARD',
            planCodeSnapshot: planName == null ? null : 'BUSINESS',
            planNameSnapshot: planName,
            nextFollowUpAt: nextFollowUpAt,
          ),
  );
}

void main() {
  group('DaleVentasLicenseReport — resumen de licencias', () {
    test('clasifica activas, por vencer, vencidas, pruebas y bloqueadas', () {
      final report =
          DaleVentasLicenseReport.fromCompanies(<DaleVentasCompanyLicense>[
            _company(
              id: '1',
              name: 'Activa lejana',
              status: 'ACTIVE',
              endsAt: _now.add(const Duration(days: 120)),
            ),
            _company(
              id: '2',
              name: 'Activa por vencer',
              status: 'ACTIVE',
              endsAt: _now.add(const Duration(days: 7)),
            ),
            _company(
              id: '3',
              name: 'Vencida',
              status: 'EXPIRED',
              usable: false,
              daysRemaining: -5,
            ),
            _company(
              id: '4',
              name: 'Demo viva',
              status: 'TRIAL',
              endsAt: _now.add(const Duration(days: 3)),
            ),
            _company(
              id: '5',
              name: 'Demo vencida',
              status: 'TRIAL',
              usable: false,
              endsAt: _now.subtract(const Duration(days: 2)),
            ),
            _company(
              id: '6',
              name: 'Bloqueada',
              status: 'BLOCKED',
              usable: false,
            ),
          ], now: _now);

      expect(report.total, 6);
      expect(report.active, 1);
      // Una activa que vence en 7 días se cuenta como "por vencer", no como activa
      expect(report.expiringSoon, 1);
      expect(report.payingActive, 2);
      expect(report.expired, 1);
      expect(report.demoActive, 1);
      expect(report.demoExpired, 1);
      expect(report.demoTotal, 2);
      expect(report.blocked, 1);
      // Utilizables: activa lejana, activa por vencer y demo viva.
      expect(report.usable, 3);
      expect(report.notUsable, 3);
    });

    test(
      'una licencia marcada activa pero con fecha pasada cuenta vencida',
      () {
        final report =
            DaleVentasLicenseReport.fromCompanies(<DaleVentasCompanyLicense>[
              _company(
                id: '1',
                name: 'Tarde',
                status: 'ACTIVE',
                endsAt: _now.subtract(const Duration(days: 3)),
              ),
            ], now: _now);

        expect(report.expired, 1);
        expect(report.active, 0);
      },
    );

    test(
      'cuenta el estado comercial (compraron, demo, interesados, seguimiento)',
      () {
        final report =
            DaleVentasLicenseReport.fromCompanies(<DaleVentasCompanyLicense>[
              _company(
                id: '1',
                name: 'Cliente',
                status: 'ACTIVE',
                commercialStatus: 'PURCHASED',
              ),
              _company(
                id: '2',
                name: 'En demo',
                status: 'TRIAL',
                commercialStatus: 'DEMO',
              ),
              _company(
                id: '3',
                name: 'Interesado',
                status: 'TRIAL',
                commercialStatus: 'INTERESTED',
              ),
              _company(
                id: '4',
                name: 'Perdido',
                status: 'EXPIRED',
                usable: false,
                commercialStatus: 'LOST',
              ),
              _company(
                id: '5',
                name: 'Con seguimiento',
                status: 'TRIAL',
                commercialStatus: 'DEMO',
                nextFollowUpAt: _now.add(const Duration(days: 2)),
              ),
            ], now: _now);

        expect(report.purchased, 1);
        expect(report.inDemo, 2);
        expect(report.interested, 1);
        expect(report.lost, 1);
        expect(report.followUp, 1);
      },
    );

    test('la lista de atención va por urgencia: vencidas, demos vencidas, '
        'por vencer y bloqueadas', () {
      final report =
          DaleVentasLicenseReport.fromCompanies(<DaleVentasCompanyLicense>[
            _company(
              id: 'blocked',
              name: 'Bloqueada',
              status: 'BLOCKED',
              usable: false,
            ),
            _company(
              id: 'soon',
              name: 'Por vencer',
              status: 'ACTIVE',
              endsAt: _now.add(const Duration(days: 10)),
            ),
            _company(
              id: 'expired',
              name: 'Vencida',
              status: 'EXPIRED',
              usable: false,
            ),
            _company(
              id: 'demo',
              name: 'Demo vencida',
              status: 'TRIAL',
              usable: false,
              endsAt: _now.subtract(const Duration(days: 1)),
            ),
          ], now: _now);

      expect(report.attention.map((line) => line.companyId).toList(), <String>[
        'expired',
        'demo',
        'soon',
        'blocked',
      ]);
      expect(report.attention.first.statusLabel, 'Vencida');
      expect(report.attention[2].statusLabel, 'Por vencer');
      expect(report.attention[3].statusLabel, 'Bloqueada');
    });

    test('limita el tamaño de la lista de atención', () {
      final report = DaleVentasLicenseReport.fromCompanies(
        <DaleVentasCompanyLicense>[
          for (var index = 0; index < 30; index++)
            _company(
              id: 'e$index',
              name: 'Empresa $index',
              status: 'EXPIRED',
              usable: false,
            ),
        ],
        now: _now,
        attentionLimit: 5,
      );

      expect(report.total, 30);
      expect(report.expired, 30);
      expect(report.attention.length, 5);
    });

    test('sin empresas no hay nada que reportar', () {
      final report = DaleVentasLicenseReport.fromCompanies(
        const <DaleVentasCompanyLicense>[],
        now: _now,
      );

      expect(report.total, 0);
      expect(report.usableRatio, 0);
      expect(report.attention, isEmpty);
      expect(report.planCounts, isEmpty);
    });

    test('agrupa por plan comercial sin inventar planes', () {
      final report =
          DaleVentasLicenseReport.fromCompanies(<DaleVentasCompanyLicense>[
            _company(
              id: '1',
              name: 'A',
              status: 'ACTIVE',
              commercialStatus: 'PURCHASED',
              planName: 'Negocio',
            ),
            _company(
              id: '2',
              name: 'B',
              status: 'ACTIVE',
              commercialStatus: 'PURCHASED',
              planName: 'Negocio',
            ),
            _company(id: '3', name: 'C', status: 'TRIAL'),
          ], now: _now);

      expect(report.planCounts['Negocio'], 2);
      expect(report.planCounts['Prueba (sin plan)'], 1);
    });
  });
}
