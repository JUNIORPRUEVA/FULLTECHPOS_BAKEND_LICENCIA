import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/navigation_config.dart';
import '../../../core/layout/app_shell_actions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/project_app_bar.dart';
import '../../../core/widgets/project_bottom_nav.dart';
import '../../usage_analytics/services/usage_analytics_service.dart';
import '../services/daleventas_license_service.dart';
import 'daleventas_bulletin_tab.dart';
import 'daleventas_licenses_page.dart';
import 'daleventas_report_tab.dart';

/// Consola del proyecto DaleVentas.
///
/// Al entrar en el proyecto se abandona la navegación general de Appyra: la
/// consola se presenta como una app independiente con su propia cabecera y su
/// propia barra inferior de tres secciones:
///
/// 1. **Reporte** — informe de todas las licencias (activas, por vencer,
///    vencidas, pruebas y actividad).
/// 2. **Licencias** — la consola de licencias existente (sin cambios).
/// 3. **Boletín** — avisos y novedades del proyecto.
class DaleVentasProjectShell extends StatefulWidget {
  /// Servicios inyectables (tests / verificación visual).
  final DaleVentasLicenseService? licenseService;
  final UsageAnalyticsService? usageService;

  /// Pestaña de licencias reemplazable (tests).
  final Widget? licensesTab;

  /// Acción de salida del proyecto. Por defecto vuelve a la lista de proyectos.
  final VoidCallback? onExit;

  const DaleVentasProjectShell({
    super.key,
    this.licenseService,
    this.usageService,
    this.licensesTab,
    this.onExit,
  });

  @override
  State<DaleVentasProjectShell> createState() => _DaleVentasProjectShellState();
}

class _DaleVentasProjectShellState extends State<DaleVentasProjectShell> {
  static const List<String> _tabTitles = <String>[
    'Reporte de licencias',
    'DaleVentasPOS Licencias',
    'Boletín del proyecto',
  ];

  static const List<ProjectNavItem> _navItems = <ProjectNavItem>[
    ProjectNavItem(
      icon: Icons.insert_chart_outlined_rounded,
      activeIcon: Icons.insert_chart_rounded,
      label: 'Reporte',
    ),
    ProjectNavItem(
      icon: Icons.vpn_key_outlined,
      activeIcon: Icons.vpn_key_rounded,
      label: 'Licencias',
    ),
    ProjectNavItem(
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign_rounded,
      label: 'Boletín',
    ),
  ];

  int _index = 0;

  /// Pestañas ya construidas: el resto no se monta hasta que se visita, para
  /// no cargar datos de más al abrir el proyecto.
  final Map<int, Widget> _tabs = <int, Widget>{};

  /// Acciones que publica la pestaña activa (p. ej. Buscar/Filtros de
  /// Licencias): se muestran en la cabecera del proyecto.
  final AppShellActionsController _actions = AppShellActionsController();

  @override
  void initState() {
    super.initState();
    _tabAt(0);
  }

  @override
  void dispose() {
    _actions.dispose();
    super.dispose();
  }

  String get _title => _tabTitles[_index];

  /// Reporte trae su propio encabezado (degradado) y no necesita barra:
  /// en esa pestaña solo se muestra el botón de volver, flotando.
  bool get _headerVisible => _index != 0;

  Widget _tabAt(int index) {
    return _tabs.putIfAbsent(index, () {
      switch (index) {
        case 0:
          return DaleVentasReportTab(
            licenseService: widget.licenseService,
            usageService: widget.usageService,
            onOpenCompany: (_) => _select(1),
            onExit: _exit,
          );
        case 1:
          return widget.licensesTab ?? const DaleVentasLicensesPage();
        default:
          return const DaleVentasBulletinTab();
      }
    });
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() {
      // Al visitarla, la pestaña queda montada (mantiene su estado y sus datos).
      _tabAt(index);
      _index = index;
    });
  }

  void _exit() {
    FocusScope.of(context).unfocus();
    final onExit = widget.onExit;
    if (onExit != null) {
      onExit();
      return;
    }
    context.go(NavigationConfig.homeRoute);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // El proyecto se comporta como una app aparte: el gesto/botón atrás
      // vuelve a la lista de proyectos en vez de cerrar Appyra.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _exit();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: AppShellActionsScope(
          controller: _actions,
          child: Column(
            children: [
              if (_headerVisible)
                ProjectAppBar(
                  title: _title,
                  onBack: _exit,
                  trailing: _ProjectActionsMenu(
                    actionsController: _actions,
                    enabled: _index == 1,
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    for (var index = 0; index < _navItems.length; index++)
                      _tabs[index] ?? const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: ProjectBottomNav(
          items: _navItems,
          currentIndex: _index,
          onTap: _select,
        ),
      ),
    );
  }
}

/// Menú de acciones de la pestaña activa (Buscar, Filtros, ...).
///
/// La consola del proyecto reemplaza la barra general de Appyra, así que las
/// acciones que la pantalla publica se ofrecen aquí. Si la pestaña no publica
/// ninguna acción, el menú no ocupa espacio.
class _ProjectActionsMenu extends StatefulWidget {
  final AppShellActionsController actionsController;

  /// `false` cuando la pestaña activa no es la que publicó las acciones: así
  /// un menú de otra sección no aparece donde no corresponde.
  final bool enabled;

  const _ProjectActionsMenu({
    required this.actionsController,
    this.enabled = true,
  });

  @override
  State<_ProjectActionsMenu> createState() => _ProjectActionsMenuState();
}

class _ProjectActionsMenuState extends State<_ProjectActionsMenu> {
  List<AppShellAction> _actions = const [];

  @override
  void initState() {
    super.initState();
    _actions = List<AppShellAction>.of(widget.actionsController.actions);
    widget.actionsController.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.actionsController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    // addPostFrameCallback: el controlador puede notificar durante el build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(
        () => _actions = List<AppShellAction>.of(
          widget.actionsController.actions,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _actions.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<int>(
      tooltip: 'Acciones',
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: AppColors.textSecondary,
      ),
      onSelected: (index) {
        if (index >= 0 && index < _actions.length) {
          _actions[index].onTap();
        }
      },
      itemBuilder: (context) => List<AppShellAction>.of(_actions)
          .asMap()
          .entries
          .map(
            (entry) => PopupMenuItem<int>(
              value: entry.key,
              child: Row(
                children: [
                  Icon(
                    entry.value.icon,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    entry.value.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
    );
  }
}
