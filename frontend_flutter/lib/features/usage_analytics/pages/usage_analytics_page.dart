import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../licenses/models/project.dart';
import '../../licenses/services/projects_service.dart';
import '../models/usage_analytics.dart';
import '../services/usage_analytics_service.dart';

class UsageAnalyticsPage extends StatefulWidget {
  const UsageAnalyticsPage({super.key});

  @override
  State<UsageAnalyticsPage> createState() => _UsageAnalyticsPageState();
}

class _UsageAnalyticsPageState extends State<UsageAnalyticsPage> {
  late final UsageAnalyticsService _service;
  late final ProjectsService _projectsService;
  late Future<UsageDashboardData> _future;

  List<Project> _projects = [];
  bool _projectsLoading = false;
  String? _projectCode;
  String? _appCode;
  String? _status;

  static const _apps = ['FULLPOS', 'FULLCREDIT', 'DALEVENTAS_POS'];
  static const _statuses = [
    'USING_NOW',
    'ACTIVE_TODAY',
    'ACTIVE_WEEK',
    'INACTIVE_15_DAYS',
    'INACTIVE_30_DAYS',
    'NEVER_USED',
  ];

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionManager>();
    _service = UsageAnalyticsService(sessionManager: session);
    _projectsService = ProjectsService(sessionManager: session);
    _future = _load();
    _loadProjects();
  }

  Future<UsageDashboardData> _load() {
    return _service.getDashboard(
      projectCode: _projectCode,
      appCode: _appCode,
      status: _status,
      limit: 100,
    );
  }

  Future<void> _loadProjects() async {
    setState(() => _projectsLoading = true);
    try {
      final projects = await _projectsService.listProjects();
      projects.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (mounted) {
        setState(() {
          _projects = projects;
          _projectsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _projectsLoading = false);
    }
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  void _clearFilters() {
    setState(() {
      _projectCode = null;
      _appCode = null;
      _status = null;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<UsageDashboardData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView(message: 'Cargando uso del sistema...');
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final data = snapshot.data!;
          return _UsageAnalyticsContent(
            data: data,
            projects: _projects,
            projectsLoading: _projectsLoading,
            projectCode: _projectCode,
            appCode: _appCode,
            status: _status,
            apps: _apps,
            statuses: _statuses,
            onProjectChanged: (value) {
              setState(() {
                _projectCode = value;
                _future = _load();
              });
            },
            onAppChanged: (value) {
              setState(() {
                _appCode = value;
                _future = _load();
              });
            },
            onStatusChanged: (value) {
              setState(() {
                _status = value;
                _future = _load();
              });
            },
            onClear: _clearFilters,
            onRefresh: _refresh,
          );
        },
      ),
    );
  }
}

class _UsageAnalyticsContent extends StatelessWidget {
  final UsageDashboardData data;
  final List<Project> projects;
  final bool projectsLoading;
  final String? projectCode;
  final String? appCode;
  final String? status;
  final List<String> apps;
  final List<String> statuses;
  final ValueChanged<String?> onProjectChanged;
  final ValueChanged<String?> onAppChanged;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onClear;
  final VoidCallback onRefresh;

  const _UsageAnalyticsContent({
    required this.data,
    required this.projects,
    required this.projectsLoading,
    required this.projectCode,
    required this.appCode,
    required this.status,
    required this.apps,
    required this.statuses,
    required this.onProjectChanged,
    required this.onAppChanged,
    required this.onStatusChanged,
    required this.onClear,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isMobile ? 10 : AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(onRefresh: onRefresh),
            const SizedBox(height: AppSpacing.md),
            _FiltersBar(
              projects: projects,
              projectsLoading: projectsLoading,
              projectCode: projectCode,
              appCode: appCode,
              status: status,
              apps: apps,
              statuses: statuses,
              onProjectChanged: onProjectChanged,
              onAppChanged: onAppChanged,
              onStatusChanged: onStatusChanged,
              onClear: onClear,
            ),
            const SizedBox(height: AppSpacing.md),
            _OverviewGrid(overview: data.overview),
            const SizedBox(height: AppSpacing.md),
            _AccountsPanel(result: data.accounts),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onRefresh;

  const _Header({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Uso del sistema',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Actividad real por proyecto, cliente, licencia y app.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Actualizar',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final List<Project> projects;
  final bool projectsLoading;
  final String? projectCode;
  final String? appCode;
  final String? status;
  final List<String> apps;
  final List<String> statuses;
  final ValueChanged<String?> onProjectChanged;
  final ValueChanged<String?> onAppChanged;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onClear;

  const _FiltersBar({
    required this.projects,
    required this.projectsLoading,
    required this.projectCode,
    required this.appCode,
    required this.status,
    required this.apps,
    required this.statuses,
    required this.onProjectChanged,
    required this.onAppChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                initialValue: projectCode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Proyecto',
                  prefixIcon: Icon(Icons.folder_copy_outlined),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ...projects.map(
                    (project) => DropdownMenuItem(
                      value: project.code,
                      child: Text(
                        project.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: projectsLoading ? null : onProjectChanged,
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: appCode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'App',
                  prefixIcon: Icon(Icons.apps_rounded),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas')),
                  ...apps.map(
                    (app) => DropdownMenuItem(value: app, child: Text(app)),
                  ),
                ],
                onChanged: onAppChanged,
              ),
            ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                initialValue: status,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Estado de uso',
                  prefixIcon: Icon(Icons.signal_cellular_alt_rounded),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos')),
                  ...statuses.map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(_statusLabel(status)),
                    ),
                  ),
                ],
                onChanged: onStatusChanged,
              ),
            ),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Limpiar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  final UsageOverview overview;

  const _OverviewGrid({required this.overview});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _MetricCardData(
        'Usando hoy',
        overview.activeToday.toString(),
        Icons.today_outlined,
        AppColors.success,
      ),
      _MetricCardData(
        'Ultimos 7 dias',
        overview.active7Days.toString(),
        Icons.date_range_rounded,
        AppColors.primary,
      ),
      _MetricCardData(
        'Riesgo 15 dias',
        overview.inactive15Days.toString(),
        Icons.warning_amber_rounded,
        AppColors.warning,
      ),
      _MetricCardData(
        'Riesgo 30 dias',
        overview.inactive30Days.toString(),
        Icons.report_gmailerrorred_rounded,
        AppColors.error,
      ),
      _MetricCardData(
        'Horas registradas',
        _hours(overview.activeSeconds),
        Icons.timer_outlined,
        AppColors.info,
      ),
      _MetricCardData(
        'Dispositivos',
        overview.devicesCount.toString(),
        Icons.devices_other_outlined,
        AppColors.textSecondary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1100
            ? 6
            : constraints.maxWidth > 760
            ? 3
            : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: constraints.maxWidth < 520 ? 1.55 : 1.8,
          ),
          itemCount: cards.length,
          itemBuilder: (_, index) => _MetricCard(data: cards[index]),
        );
      },
    );
  }
}

class _MetricCardData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCardData(this.title, this.value, this.icon, this.color);
}

class _MetricCard extends StatelessWidget {
  final _MetricCardData data;

  const _MetricCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(data.icon, color: data.color, size: 22),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountsPanel extends StatelessWidget {
  final UsageAccountsResult result;

  const _AccountsPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cuentas y negocios',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${result.total} registros',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (result.accounts.isEmpty)
              const EmptyState(
                title: 'Sin datos de uso todavia',
                subtitle:
                    'Cuando una app reporte heartbeat o eventos apareceran aqui.',
                icon: Icons.query_stats_rounded,
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 820) {
                    return Column(
                      children: result.accounts
                          .map((account) => _AccountTile(account: account))
                          .toList(),
                    );
                  }
                  return _AccountsTable(accounts: result.accounts);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountsTable extends StatelessWidget {
  final List<UsageAccount> accounts;

  const _AccountsTable({required this.accounts});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 42,
        dataRowMinHeight: 58,
        dataRowMaxHeight: 68,
        columns: const [
          DataColumn(label: Text('Cliente')),
          DataColumn(label: Text('Proyecto')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Ultimo uso')),
          DataColumn(label: Text('Version')),
          DataColumn(label: Text('Dispositivos')),
          DataColumn(label: Text('Sesiones')),
          DataColumn(label: Text('Tiempo')),
        ],
        rows: accounts.map((account) {
          return DataRow(
            cells: [
              DataCell(_CustomerCell(account: account)),
              DataCell(Text(account.projectCode ?? account.appCode)),
              DataCell(_UsageStatusBadge(account: account)),
              DataCell(Text(_date(account.lastSeenAt))),
              DataCell(Text(account.appVersion ?? '-')),
              DataCell(Text(account.devicesCount.toString())),
              DataCell(Text(account.sessionsCount.toString())),
              DataCell(Text(_hours(account.activeSeconds))),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final UsageAccount account;

  const _AccountTile({required this.account});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _CustomerCell(account: account)),
              _UsageStatusBadge(account: account),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 6,
            children: [
              _MiniMetric(
                icon: Icons.folder_copy_outlined,
                text: account.projectCode ?? account.appCode,
              ),
              _MiniMetric(
                icon: Icons.schedule_rounded,
                text: _date(account.lastSeenAt),
              ),
              _MiniMetric(
                icon: Icons.devices_other_outlined,
                text: '${account.devicesCount} disp.',
              ),
              _MiniMetric(
                icon: Icons.timer_outlined,
                text: _hours(account.activeSeconds),
              ),
              _MiniMetric(
                icon: Icons.new_releases_outlined,
                text: account.appVersion ?? 'Sin version',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerCell extends StatelessWidget {
  final UsageAccount account;

  const _CustomerCell({required this.account});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            account.customerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            account.businessId ??
                account.customerEmail ??
                account.licenseKey ??
                'Sin identificador',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageStatusBadge extends StatelessWidget {
  final UsageAccount account;

  const _UsageStatusBadge({required this.account});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(account.usageStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(account.usageStatus), size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            account.statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniMetric({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'USING_NOW':
      return 'Usando ahora';
    case 'ACTIVE_TODAY':
      return 'Activo hoy';
    case 'ACTIVE_WEEK':
      return 'Activo semana';
    case 'INACTIVE_15_DAYS':
      return 'Inactivo 15 dias';
    case 'INACTIVE_30_DAYS':
      return 'Inactivo 30 dias';
    case 'NEVER_USED':
      return 'Nunca usado';
    default:
      return status;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'USING_NOW':
    case 'ACTIVE_TODAY':
      return AppColors.success;
    case 'ACTIVE_WEEK':
    case 'ACTIVE_RECENT':
      return AppColors.primary;
    case 'INACTIVE_15_DAYS':
      return AppColors.warning;
    case 'INACTIVE_30_DAYS':
    case 'NEVER_USED':
      return AppColors.error;
    default:
      return AppColors.textSecondary;
  }
}

IconData _statusIcon(String status) {
  switch (status) {
    case 'USING_NOW':
      return Icons.online_prediction_rounded;
    case 'ACTIVE_TODAY':
    case 'ACTIVE_WEEK':
    case 'ACTIVE_RECENT':
      return Icons.check_circle_outline_rounded;
    case 'INACTIVE_15_DAYS':
      return Icons.warning_amber_rounded;
    case 'INACTIVE_30_DAYS':
    case 'NEVER_USED':
      return Icons.error_outline_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}

String _hours(int seconds) {
  if (seconds <= 0) return '0 h';
  final hours = seconds / 3600;
  if (hours < 1) return '${(seconds / 60).round()} min';
  return '${hours.toStringAsFixed(hours >= 10 ? 0 : 1)} h';
}

String _date(DateTime? value) {
  if (value == null) return 'Sin uso';
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}
