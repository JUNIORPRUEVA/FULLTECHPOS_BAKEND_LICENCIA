/// Appyra navigation mode configuration.
///
/// Appyra runs in **project mode**: every product (DaleVentas, FullPOS,
/// FullCredit, ...) is managed inside `Proyectos`, and only truly global
/// capabilities stay in the general navigation.
///
/// The modules that used to be global top-level entries are classified as
/// LEGACY / HIDDEN, and the global Panel is kept out of the normal flow
/// without being marked as legacy. Hiding is a navigation-only concern:
/// - routes, screens, services, API clients and backend endpoints stay intact;
/// - database tables, columns, migrations and data are untouched;
/// - every hidden screen keeps working through its direct route.
///
/// See `docs/APPYRA_PROJECT_MODE.md` for the full audit and the recovery path.
class NavigationConfig {
  NavigationConfig._();

  /// Compile-time switch that re-enables the legacy (global) sidebar entries.
  ///
  /// - Default `false` → legacy modules are hidden (Appyra project mode).
  /// - Re-enable without touching code:
  ///   `flutter run --dart-define=LEGACY_MODULES_VISIBLE=true`
  ///   `flutter build web --release --dart-define=LEGACY_MODULES_VISIBLE=true`
  ///
  /// This flag only controls visibility in the sidebar. It never enables or
  /// disables business logic, permissions or API calls.
  static const bool legacyModulesVisible = bool.fromEnvironment(
    'LEGACY_MODULES_VISIBLE',
    defaultValue: false,
  );

  /// `true` cuando los módulos legacy deben volver a renderizarse.
  static bool get showLegacyModules => legacyModulesVisible;

  /// Ruta inicial del administrador en project mode.
  ///
  /// Se usa después del login, al terminar el splash y como destino del botón
  /// "volver" de las pantallas que ya no tienen entrada en la navegación.
  /// El Panel global (`/admin/panel`) sigue declarado y accesible por URL,
  /// pero deja de ser el destino por defecto.
  static const String homeRoute = '/admin/proyectos';
}
