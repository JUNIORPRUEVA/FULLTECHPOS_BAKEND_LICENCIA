import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/project_app_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../usage_analytics/models/usage_analytics.dart';
import '../../usage_analytics/services/usage_analytics_service.dart';
import '../models/daleventas_company_license.dart';
import '../models/daleventas_license_report.dart';
import '../services/daleventas_license_service.dart';

/// Paquete de datos del reporte: licencias + (opcional) actividad de uso.
class _ReportBundle {
  final List<DaleVentasCompanyLicense> companies;
  final UsageDashboardData? usage;
  final DateTime generatedAt;

  const _ReportBundle({
    required this.companies,
    required this.usage,
    required this.generatedAt,
  });
}

/// Pestaña "Reporte" de la consola del proyecto DaleVentas.
///
/// Muestra un informe legible de todas las licencias del proyecto: cuántos
/// clientes tienen licencia activa, cuántos están vencidos, cuántas pruebas
/// (demo/trial) hay y qué clientes requieren atención. Todo se calcula con los
/// datos que ya expone la API de licencias: no se crean endpoints nuevos ni se
/// modifica ningún dato.
class DaleVentasReportTab extends StatefulWidget {
  /// Servicios inyectables (tests / verificación visual).
  final DaleVentasLicenseService? licenseService;
  final UsageAnalyticsService? usageService;

  /// Acción al tocar un cliente del listado de atención.
  final ValueChanged<String>? onOpenCompany;

  /// Acción del botón de volver (sale del proyecto).
  final VoidCallback? onExit;

  const DaleVentasReportTab({
    super.key,
    this.licenseService,
    this.usageService,
    this.onOpenCompany,
    this.onExit,
  });

  @override
  State<DaleVentasReportTab> createState() => _DaleVentasReportTabState();
}

class _DaleVentasReportTabState extends State<DaleVentasReportTab> {
  late final DaleVentasLicenseService _licenseService;
  late final UsageAnalyticsService _usageService;
  late Future<_ReportBundle> _future;

  /// `true` cuando el contenido ya se desplazó: entonces el botón circular
  /// flotante se sustituye por una barra compacta (sin solapes con el texto).
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _licenseService =
        widget.licenseService ??
        DaleVentasLicenseService(
          sessionManager: context.read<SessionManager>(),
        );
    _usageService =
        widget.usageService ??
        UsageAnalyticsService(sessionManager: context.read<SessionManager>());
    _future = _load();
  }

  Future<_ReportBundle> _load() async {
    final result = await _licenseService.listCompanies(limit: 200);

    UsageDashboardData? usage;
    try {
      usage = await _usageService.getDashboard(limit: 200);
    } catch (_) {
      // La actividad es información complementaria: si falla, el reporte de
      // licencias se sigue mostrando.
      usage = null;
    }

    return _ReportBundle(
      companies: result.items,
      usage: usage,
      generatedAt: DateTime.now(),
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  bool _onScroll(ScrollNotification notification) {
    final scrolled = notification.metrics.pixels > 56;
    if (scrolled == _scrolled) return false;
    // La notificación puede llegar durante el layout: se aplica en el
    // siguiente frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || scrolled == _scrolled) return;
      setState(() => _scrolled = scrolled);
    });
    return false;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // El FutureBuilder muestra el error; el pull-to-refresh no debe romper.
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReportBundle>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(message: 'Generando el reporte...');
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          final message = error is ApiException
              ? error.message
              : error.toString();
          return ErrorView(message: message, onRetry: _reload);
        }

        final bundle = snapshot.data;
        if (bundle == null) {
          return const LoadingView(message: 'Generando el reporte...');
        }

        final report = DaleVentasLicenseReport.fromCompanies(bundle.companies);
        if (report.total == 0) {
          return EmptyState(
            icon: Icons.insights_outlined,
            title: 'Todavía no hay licencias que reportar',
            subtitle:
                'Cuando existan empresas con licencia en DaleVentas, aquí verás '
                'el resumen completo.',
            action: FilledButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Actualizar'),
            ),
          );
        }

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _refresh,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _ReportTopArea(
                      report: report,
                      generatedAt: bundle.generatedAt,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
                      child: Column(
                        children: [
                          _buildKpiGrid(report),
                          const SizedBox(height: 14),
                          _SectionCard(
                            title: 'Estado comercial',
                            icon: Icons.handshake_outlined,
                            subtitle: 'Cómo va la relación con cada empresa',
                            child: Column(
                              children: [
                                _BarRow(
                                  label: 'Ya compraron',
                                  value: report.purchased,
                                  total: report.total,
                                  color: AppColors.success,
                                ),
                                _BarRow(
                                  label: 'En demo',
                                  value: report.inDemo,
                                  total: report.total,
                                  color: AppColors.info,
                                ),
                                _BarRow(
                                  label: 'Interesados / contactados',
                                  value: report.interested,
                                  total: report.total,
                                  color: AppColors.primary,
                                ),
                                _BarRow(
                                  label: 'Con seguimiento agendado',
                                  value: report.followUp,
                                  total: report.total,
                                  color: AppColors.warning,
                                ),
                                _BarRow(
                                  label: 'Perdidos',
                                  value: report.lost,
                                  total: report.total,
                                  color: AppColors.error,
                                  showDivider: false,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          _PlansSection(
                            planCounts: report.planCounts,
                            total: report.total,
                          ),
                          if (bundle.usage != null) ...[
                            const SizedBox(height: 14),
                            _buildActivity(bundle.usage!),
                          ],
                          const SizedBox(height: 14),
                          _buildAttention(report),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Datos de licencias DaleVentas · '
                              '${DateFormat('dd/MM/yyyy HH:mm').format(bundle.generatedAt)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildTopOverlay(),
          ],
        );
      },
    );
  }

  /// Botón de volver sin barra: círculo flotante sobre el degradado y, en
  /// cuanto se desplaza el contenido, una barra compacta que se desvanece
  /// encima (así el botón nunca se solapa con el texto).
  Widget _buildTopOverlay() {
    final onExit = widget.onExit;
    if (onExit == null) return const SizedBox.shrink();
    final topInset = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned(
          left: 12,
          top: topInset + 10,
          child: ProjectFloatingBackButton(onTap: onExit),
        ),
        if (_scrolled)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TweenAnimationBuilder<double>(
              key: const ValueKey('report-compact-bar'),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, -10 * (1 - value)),
                  child: child,
                ),
              ),
              child: ProjectAppBar(
                title: 'Reporte de licencias',
                onBack: onExit,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildKpiGrid(DaleVentasLicenseReport report) {
    final tiles = <Widget>[
      _KpiCard(
        icon: Icons.verified_rounded,
        color: AppColors.success,
        value: report.payingActive,
        label: 'Licencias de pago',
        hint: 'Vigentes ahora',
      ),
      _KpiCard(
        icon: Icons.schedule_rounded,
        color: AppColors.warning,
        value: report.expiringSoon,
        label: 'Por vencer',
        hint: 'Próximos ${DaleVentasLicenseReport.expiringWindowDays} días',
      ),
      _KpiCard(
        icon: Icons.event_busy_rounded,
        color: AppColors.error,
        value: report.expired,
        label: 'Vencidas',
        hint: 'Requieren renovación',
      ),
      _KpiCard(
        icon: Icons.science_rounded,
        color: AppColors.info,
        value: report.demoTotal,
        label: 'Pruebas (demo)',
        hint: '${report.demoActive} activas · ${report.demoExpired} vencidas',
      ),
      _KpiCard(
        icon: Icons.lock_outline_rounded,
        color: AppColors.textSecondary,
        value: report.blocked,
        label: 'Bloqueadas',
        hint: 'Suspendidas a mano',
      ),
      _KpiCard(
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.primary,
        value: report.usable,
        label: 'Utilizables hoy',
        hint: 'Pueden trabajar',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 3 : 2;
        final spacing = 10.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }

  Widget _buildActivity(UsageDashboardData usage) {
    final overview = usage.overview;
    return _SectionCard(
      title: 'Actividad de uso',
      icon: Icons.timeline_rounded,
      subtitle: 'Movimiento real de las instalaciones',
      child: Column(
        children: [
          _MetricRow(
            icon: Icons.bolt_rounded,
            label: 'Activas hoy',
            value: _fmtNumber(overview.activeToday),
            color: AppColors.success,
          ),
          _MetricRow(
            icon: Icons.calendar_view_week_rounded,
            label: 'Activas en 7 días',
            value: _fmtNumber(overview.active7Days),
            color: AppColors.primary,
          ),
          _MetricRow(
            icon: Icons.hourglass_empty_rounded,
            label: 'Sin uso hace 15 días',
            value: _fmtNumber(overview.inactive15Days),
            color: AppColors.warning,
          ),
          _MetricRow(
            icon: Icons.hourglass_disabled_rounded,
            label: 'Sin uso hace 30 días',
            value: _fmtNumber(overview.inactive30Days),
            color: AppColors.error,
          ),
          _MetricRow(
            icon: Icons.devices_rounded,
            label: 'Dispositivos registrados',
            value: _fmtNumber(overview.devicesCount),
            color: AppColors.info,
          ),
          _MetricRow(
            icon: Icons.login_rounded,
            label: 'Sesiones',
            value: _fmtNumber(overview.sessionsCount),
            color: AppColors.primary,
          ),
          _MetricRow(
            icon: Icons.timer_outlined,
            label: 'Tiempo de uso',
            value: _fmtDuration(overview.activeSeconds),
            color: AppColors.textSecondary,
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _buildAttention(DaleVentasLicenseReport report) {
    if (report.attention.isEmpty) {
      return _SectionCard(
        title: 'Atención requerida',
        icon: Icons.notifications_active_outlined,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.verified_rounded,
                size: 18,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Todo en orden: ninguna licencia está vencida, por vencer ni '
                'bloqueada.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _SectionCard(
      title: 'Atención requerida',
      icon: Icons.notifications_active_outlined,
      subtitle:
          '${report.attention.length} '
          '${report.attention.length == 1 ? 'cliente' : 'clientes'} para revisar',
      padded: false,
      child: Column(
        children: [
          for (var index = 0; index < report.attention.length; index++)
            _AttentionTile(
              line: report.attention[index],
              showDivider: index != report.attention.length - 1,
              onTap: widget.onOpenCompany == null
                  ? null
                  : () => widget.onOpenCompany!(
                      report.attention[index].companyId,
                    ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// TARJETAS DEL REPORTE
// ═══════════════════════════════════════════════════════════════

/// Encabezado del reporte.
///
/// Ocupa todo el ancho y se apoya en el borde superior (también detrás de la
/// barra de estado): esta pestaña **no tiene barra de aplicación**, solo el
/// botón de volver que la consola dibuja flotando encima de este degradado.
class _ReportTopArea extends StatelessWidget {
  final DaleVentasLicenseReport report;
  final DateTime generatedAt;

  const _ReportTopArea({required this.report, required this.generatedAt});

  @override
  Widget build(BuildContext context) {
    final percent = (report.usableRatio * 100).round();
    final topInset = MediaQuery.paddingOf(context).top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, topInset + 6, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2B6BF3), AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0, 0.45, 1],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x331A56DB),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // La mitad izquierda queda libre para el botón flotante de volver,
          // por eso el título va centrado.
          const SizedBox(
            height: 44,
            width: double.infinity,
            child: Center(
              child: Text(
                'Reporte de licencias',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          Text(
            'DaleVentas POS · actualizado el '
            '${DateFormat('dd/MM/yyyy HH:mm').format(generatedAt)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  value: '${report.total}',
                  label: 'Empresas',
                  caption: 'registradas',
                ),
              ),
              Container(
                width: 1,
                height: 46,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Colors.white.withValues(alpha: 0.18),
              ),
              Expanded(
                child: _HeroStat(
                  value: '$percent%',
                  label: 'Con licencia',
                  caption: 'utilizable hoy',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final String caption;

  const _HeroStat({
    required this.value,
    required this.label,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        Text(
          caption,
          style: const TextStyle(fontSize: 10.5, color: Colors.white70),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  final String hint;

  const _KpiCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        // Degradado tenue del color del estado: la tarjeta se lee de un vistazo
        // sin perder legibilidad del texto.
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.14),
            color.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 24,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            hint,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget child;
  final bool padded;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.padded = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 9),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: padded
                ? const EdgeInsets.fromLTRB(14, 0, 14, 14)
                : const EdgeInsets.only(bottom: 4),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;
  final bool showDivider;

  const _BarRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: ratio),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOut,
                  builder: (context, animated, _) => LinearProgressIndicator(
                    value: animated,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool showDivider;

  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
      ],
    );
  }
}

class _AttentionTile extends StatelessWidget {
  final DaleVentasReportLine line;
  final bool showDivider;
  final VoidCallback? onTap;

  const _AttentionTile({
    required this.line,
    required this.showDivider,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Fondo tenue acorde con el estado + barra lateral del color del estado:
    // la tarjeta se identifica de un vistazo sin ensuciar la pantalla.
    final accent = _statusAccent(line.status);
    final content = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.10),
            accent.withValues(alpha: 0.02),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 46,
            margin: const EdgeInsets.only(left: 8, right: 8),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${line.planLabel} · ${_fmtEndsAt(line)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          StatusBadge(label: line.statusLabel, type: _badgeType(line.status)),
          const SizedBox(width: 10),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );

    return Column(
      children: [
        if (onTap == null) content else InkWell(onTap: onTap, child: content),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
      ],
    );
  }
}

/// Color fuerte del estado (barra lateral y tinte de fondo).
Color _statusAccent(DaleVentasReportStatus status) {
  switch (status) {
    case DaleVentasReportStatus.active:
      return AppColors.success;
    case DaleVentasReportStatus.expiring:
      return AppColors.warning;
    case DaleVentasReportStatus.expired:
    case DaleVentasReportStatus.demoExpired:
      return AppColors.error;
    case DaleVentasReportStatus.demo:
      return AppColors.info;
    case DaleVentasReportStatus.blocked:
      return AppColors.textSecondary;
    case DaleVentasReportStatus.other:
      return AppColors.textMuted;
  }
}

// ═══════════════════════════════════════════════════════════════
// UTILIDADES
// ═══════════════════════════════════════════════════════════════

/// Sección "Licencias por plan": reparto de empresas por plan comercial.
class _PlansSection extends StatelessWidget {
  final Map<String, int> planCounts;
  final int total;

  const _PlansSection({required this.planCounts, required this.total});

  @override
  Widget build(BuildContext context) {
    final plans = _sortedPlans(planCounts);
    if (plans.isEmpty) {
      return _SectionCard(
        title: 'Licencias por plan',
        icon: Icons.workspace_premium_outlined,
        child: const Text(
          'Todavía no hay planes asignados.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      );
    }

    return _SectionCard(
      title: 'Licencias por plan',
      icon: Icons.workspace_premium_outlined,
      subtitle:
          '${plans.length} ${plans.length == 1 ? 'grupo de plan' : 'grupos de plan'}',
      child: Column(
        children: [
          for (var index = 0; index < plans.length; index++)
            _BarRow(
              label: plans[index].key,
              value: plans[index].value,
              total: total,
              color: _planColor(plans[index].key),
              showDivider: index != plans.length - 1,
            ),
        ],
      ),
    );
  }
}

/// Planes ordenados de mayor a menor cantidad (y alfabéticamente a igualdad).
List<MapEntry<String, int>> _sortedPlans(Map<String, int> counts) {
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      if (byCount != 0) return byCount;
      return a.key.toLowerCase().compareTo(b.key.toLowerCase());
    });
  return entries;
}

/// Color del plan en el resumen (coherente con la consola de licencias).
Color _planColor(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('pro')) return AppColors.success;
  if (normalized.contains('negocio') || normalized.contains('business')) {
    return AppColors.primary;
  }
  if (normalized.contains('básic') || normalized.contains('basic')) {
    return AppColors.info;
  }
  if (normalized.contains('demo') ||
      normalized.contains('prueba') ||
      normalized.contains('trial')) {
    return AppColors.warning;
  }
  return AppColors.textSecondary;
}

StatusType _badgeType(DaleVentasReportStatus status) {
  switch (status) {
    case DaleVentasReportStatus.active:
      return StatusType.active;
    case DaleVentasReportStatus.expiring:
      return StatusType.pastDue;
    case DaleVentasReportStatus.expired:
    case DaleVentasReportStatus.demoExpired:
      return StatusType.expired;
    case DaleVentasReportStatus.demo:
      return StatusType.demo;
    case DaleVentasReportStatus.blocked:
      return StatusType.suspended;
    case DaleVentasReportStatus.other:
      return StatusType.unknown;
  }
}

String _fmtEndsAt(DaleVentasReportLine line) {
  final endsAt = line.endsAt;
  final days = line.daysRemaining;
  final dateText = endsAt == null
      ? 'Sin fecha de vencimiento'
      : 'Vence ${DateFormat('dd/MM/yyyy').format(endsAt.toLocal())}';
  if (days == null) return dateText;
  if (days < 0) return '$dateText · hace ${-days} d';
  if (days == 0) return '$dateText · vence hoy';
  return '$dateText · en $days d';
}

String _fmtNumber(int value) => NumberFormat('#,##0').format(value);

String _fmtDuration(int seconds) {
  if (seconds <= 0) return '0 h';
  if (seconds < 3600) return '${(seconds / 60).round()} min';
  final hours = seconds / 3600;
  if (hours < 24) return '${hours.toStringAsFixed(hours >= 10 ? 0 : 1)} h';
  return '${(hours / 24).toStringAsFixed(1)} días';
}
