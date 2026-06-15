import 'package:appyra_admin/features/licenses/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project profile parses and serializes rich documentation', () {
    final project = Project.fromJson({
      'id': 'project-id',
      'code': 'FULLCREDIT',
      'name': 'FULLCREDIT',
      'is_active': true,
      'product_profile': {
        'tagline': 'Control de préstamos',
        'overview': 'Descripción completa',
        'platforms': ['Android'],
        'benefits': ['Cartera organizada'],
        'modules': [
          {
            'title': 'Préstamos',
            'description': 'Crea planes de pago',
            'icon': 'loans',
          },
        ],
        'workflows': [
          {
            'title': 'Crear préstamo',
            'description': 'Proceso principal',
            'steps': ['Seleccionar cliente', 'Confirmar cuotas'],
          },
        ],
      },
    });

    expect(project.profile.tagline, 'Control de préstamos');
    expect(project.profile.platforms, ['Android']);
    expect(project.profile.modules.single.title, 'Préstamos');
    expect(project.profile.workflows.single.steps, hasLength(2));

    final serialized = project.toJson()['product_profile'];
    expect(serialized['benefits'], ['Cartera organizada']);
    expect(serialized['modules'][0]['icon'], 'loans');
  });

  test('project profile tolerates missing or malformed optional content', () {
    final project = Project.fromJson({
      'id': 'project-id',
      'code': 'DEFAULT',
      'name': 'Default',
      'product_profile': {'modules': 'invalid'},
    });

    expect(project.profile.isEmpty, isTrue);
    expect(project.profile.modules, isEmpty);
    expect(project.profile.gallery, isEmpty);
  });
}
