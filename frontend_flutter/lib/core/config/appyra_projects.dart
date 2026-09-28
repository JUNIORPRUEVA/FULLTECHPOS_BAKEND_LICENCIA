/// Registro central de proyectos de Appyra (project mode).
///
/// Appyra funciona como administrador de múltiples proyectos y **en project
/// mode la pantalla `Proyectos` muestra los proyectos declarados aquí**.
///
/// Importante: la entrada de un proyecto en project mode **no depende de que
/// exista una fila en la tabla `projects`**. DaleVentas hoy es una integración
/// real y operativa (consola de licencias + integración externa) que se expone
/// a través de [AppyraProjectDefinition.route]. Si además existe una fila con
/// el mismo `code`, se reutiliza para habilitar la edición del proyecto.
///
/// Cualquier registro de `projects` que no esté declarado aquí queda
/// clasificado como **HIDDEN_LEGACY_PROJECT**: se preserva en la base de datos,
/// en el código y en sus relaciones (licencias, pagos, trials, analítica), pero
/// no aparece en la experiencia normal.
///
/// Reglas:
/// - La visibilidad se decide por `code` (estable), nunca por `name`.
/// - No se borra, renombra ni desactiva ningún proyecto legacy.
/// - No crear proyectos visibles nuevos ni reactivar legacy sin solicitud
///   expresa del propietario (ver `docs/APPYRA_PROJECT_MODE.md`).
///
/// El modo clásico (`LEGACY_MODULES_VISIBLE=true`) muestra todos los
/// proyectos otra vez, como vía de recuperación.
class AppyraProjectDefinition {
  /// Código estable (= `projects.code`, siempre en mayúsculas).
  final String code;

  /// Nombre comercial que se muestra en la interfaz en project mode.
  final String name;

  /// Ruta existente que abre el proyecto (su consola/administración actual).
  ///
  /// Debe ser una ruta real ya declarada en `AppRouter`: no se duplica
  /// pantalla ni se copia código.
  final String route;

  /// `true` si el proyecto está activo (se muestra como "Activo").
  final bool isActive;

  const AppyraProjectDefinition({
    required this.code,
    required this.name,
    required this.route,
    this.isActive = true,
  });
}

class AppyraProjects {
  AppyraProjects._();

  /// Proyecto real y activo de Appyra en este momento.
  ///
  /// Su administración es la consola existente de licencias de DaleVentas
  /// (antes visible como "DaleVentas Cloud" en el sidebar).
  static const AppyraProjectDefinition daleventas = AppyraProjectDefinition(
    code: 'DALEVENTAS',
    name: 'DaleVentas POS',
    route: '/admin/daleventas-licencias',
  );

  /// Proyectos visibles en la pantalla `Proyectos` (project mode).
  ///
  /// Un proyecto se muestra solo si su `code` está en esta lista, y se abre
  /// con su [AppyraProjectDefinition.route] existente.
  static const List<AppyraProjectDefinition> projectModeVisible =
      <AppyraProjectDefinition>[daleventas];

  /// Proyectos legacy preservados y ocultos (HIDDEN_LEGACY_PROJECT).
  ///
  /// Solo documenta y verifica la clasificación: la regla real de visibilidad
  /// es "lo que no está en [projectModeVisible] queda oculto en project mode".
  static const List<String> legacyProjectCodes = <String>[
    'DEFAULT',
    'FULLPOS',
    'FULLCREDIT',
  ];

  static String normalizeCode(String? code) =>
      (code ?? '').trim().toUpperCase();

  /// Códigos visibles en project mode.
  static Set<String> get projectModeVisibleCodes =>
      projectModeVisible.map((project) => normalizeCode(project.code)).toSet();

  /// `true` si el proyecto debe mostrarse en la pantalla `Proyectos`.
  static bool isVisibleInProjectMode(String? code) =>
      projectModeVisibleCodes.contains(normalizeCode(code));

  /// `true` si el proyecto es legacy y queda oculto en project mode.
  static bool isHiddenLegacyProject(String? code) {
    final normalized = normalizeCode(code);
    if (normalized.isEmpty) return false;
    return legacyProjectCodes.contains(normalized) &&
        !projectModeVisibleCodes.contains(normalized);
  }

  /// Definición registrada para un código (o `null` si no está registrado).
  static AppyraProjectDefinition? definitionFor(String? code) {
    final normalized = normalizeCode(code);
    for (final project in projectModeVisible) {
      if (normalizeCode(project.code) == normalized) return project;
    }
    return null;
  }
}
