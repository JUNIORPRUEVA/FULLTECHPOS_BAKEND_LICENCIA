import 'package:flutter_test/flutter_test.dart';

import 'package:appyra_admin/core/config/appyra_projects.dart';
import 'package:appyra_admin/core/config/navigation_config.dart';

void main() {
  group('Appyra projects — registro de project mode', () {
    test('DaleVentas POS es el único proyecto visible', () {
      expect(AppyraProjects.projectModeVisible, hasLength(1));
      expect(AppyraProjects.daleventas.code, 'DALEVENTAS');
      expect(AppyraProjects.daleventas.name, 'DaleVentas POS');
    });

    test('el nombre comercial no usa marcas antiguas', () {
      final name = AppyraProjects.daleventas.name;
      expect(name, isNot(contains('Cloud')));
      expect(name, isNot(contains('FULLPOS')));
      expect(name.toLowerCase(), isNot(equals('fullpos')));
    });

    test('la visibilidad se decide por code, nunca por nombre', () {
      expect(AppyraProjects.isVisibleInProjectMode('DALEVENTAS'), isTrue);
      expect(AppyraProjects.isVisibleInProjectMode(' daleventas '), isTrue);

      expect(AppyraProjects.isVisibleInProjectMode('FULLPOS'), isFalse);
      expect(AppyraProjects.isVisibleInProjectMode('FullPos'), isFalse);
      expect(AppyraProjects.isVisibleInProjectMode('FULLCREDIT'), isFalse);
      expect(AppyraProjects.isVisibleInProjectMode('DEFAULT'), isFalse);
      expect(AppyraProjects.isVisibleInProjectMode('DaleVentas POS'), isFalse);
      expect(AppyraProjects.isVisibleInProjectMode(null), isFalse);
      expect(AppyraProjects.isVisibleInProjectMode(''), isFalse);
    });

    test('los proyectos legacy quedan preservados pero ocultos', () {
      expect(
        AppyraProjects.legacyProjectCodes,
        containsAll(<String>['DEFAULT', 'FULLPOS', 'FULLCREDIT']),
      );

      for (final code in AppyraProjects.legacyProjectCodes) {
        expect(AppyraProjects.isHiddenLegacyProject(code), isTrue);
        expect(AppyraProjects.isVisibleInProjectMode(code), isFalse);
        expect(
          AppyraProjects.projectModeVisibleCodes,
          isNot(contains(code)),
          reason: 'Un proyecto legacy no debe reaparecer en la lista visible',
        );
      }

      // El proyecto activo nunca se clasifica como legacy
      expect(AppyraProjects.isHiddenLegacyProject('DALEVENTAS'), isFalse);
    });

    test('definitionFor resuelve el nombre comercial del proyecto', () {
      expect(
        AppyraProjects.definitionFor('daleventas')?.name,
        AppyraProjects.daleventas.name,
      );
      expect(AppyraProjects.definitionFor('FULLPOS'), isNull);
      expect(AppyraProjects.definitionFor(null), isNull);
    });

    test('cada proyecto visible abre la consola existente y está activo', () {
      expect(AppyraProjects.daleventas.route, '/admin/daleventas-licencias');
      for (final project in AppyraProjects.projectModeVisible) {
        expect(project.route, startsWith('/admin/'));
        expect(project.route, isNotEmpty);
        expect(project.isActive, isTrue);
      }
    });

    test('project mode está activo por defecto (lista filtrada)', () {
      // El filtro de la pantalla Proyectos solo se relaja con el modo clásico.
      expect(NavigationConfig.showLegacyModules, isFalse);
    });
  });
}
