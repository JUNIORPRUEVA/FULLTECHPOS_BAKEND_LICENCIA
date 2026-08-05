import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/layout/app_shell_actions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/daleventas_company_license.dart';
import '../services/daleventas_license_service.dart';

class DaleVentasLicensesPage extends StatefulWidget {
  const DaleVentasLicensesPage({super.key});

  @override
  State<DaleVentasLicensesPage> createState() => _DaleVentasLicensesPageState();
}

class _DaleVentasLicensesPageState extends State<DaleVentasLicensesPage> {
  late final DaleVentasLicenseService _service;
  late Future<DaleVentasLicensePageResult> _future;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _pollTimer;

  DaleVentasCompanyLicense? _selected;
  String _status = 'TODAS';
  bool _showSearch = false;
  AppShellActionsController? _shellActionsController;
  bool? _shellActionsMobile;

  bool get _isDesktop => MediaQuery.sizeOf(context).width >= 1020;

  @override
  void initState() {
    super.initState();
    _service = DaleVentasLicenseService(
      sessionManager: context.read<SessionManager>(),
    );
    _future = _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) _refresh(silent: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shellActionsController = AppShellActionsScope.maybeOf(context);
    _syncShellActions();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _shellActionsController?.clear();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _syncShellActions() {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    if (_shellActionsMobile == isMobile) return;
    _shellActionsMobile = isMobile;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _shellActionsController;
      if (controller == null) return;
      if (!isMobile) {
        controller.clear();
        return;
      }
      controller.setActions([
        AppShellAction(
          icon: Icons.search_rounded,
          label: 'Buscar',
          onTap: () {
            setState(() => _showSearch = !_showSearch);
            if (_showSearch) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _searchFocus.requestFocus(),
              );
            }
          },
        ),
        AppShellAction(
          icon: Icons.refresh_rounded,
          label: 'Recargar',
          onTap: _refresh,
        ),
      ]);
    });
  }

  Future<DaleVentasLicensePageResult> _load() {
    return _service.listCompanies(
      query: _searchCtrl.text,
      status: _status,
      limit: 80,
    );
  }

  void _refresh({bool silent = false}) {
    final next = _load().then((result) {
      final selected = _selected;
      if (selected != null) {
        final matches = result.items.where(
          (item) => item.companyId == selected.companyId,
        );
        if (matches.isNotEmpty && mounted) {
          setState(() => _selected = matches.first);
        }
      }
      return result;
    });
    if (mounted) {
      setState(() => _future = next);
    }
  }

  Future<void> _openDetail(DaleVentasCompanyLicense company) async {
    final detail = await _service.getCompany(company.companyId);
    if (!mounted) return;
    if (_isDesktop) {
      setState(() => _selected = detail);
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        useSafeArea: true,
        builder: (_) => _MobileDetailSheet(
          company: detail,
          onChanged: (updated) {
            setState(() => _selected = updated);
            _refresh(silent: true);
          },
          service: _service,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncShellActions();
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            searchCtrl: _searchCtrl,
            searchFocus: _searchFocus,
            status: _status,
            showSearch: _showSearch || _isDesktop,
            onStatusChanged: (value) {
              setState(() => _status = value);
              _refresh();
            },
            onSearch: _refresh,
            onRefresh: _refresh,
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: FutureBuilder<DaleVentasLicensePageResult>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const LoadingView(
                    message: 'Cargando licencias DaleVentas...',
                  );
                }
                if (snapshot.hasError) {
                  final message = snapshot.error is ApiException
                      ? (snapshot.error as ApiException).message
                      : snapshot.error.toString();
                  return ErrorView(message: message, onRetry: _refresh);
                }
                final result = snapshot.data;
                final companies =
                    result?.items ?? const <DaleVentasCompanyLicense>[];
                if (companies.isEmpty) {
                  return EmptyState(
                    icon: Icons.verified_user_outlined,
                    title: 'Sin empresas de DaleVentas',
                    subtitle:
                        'Cuando el backend este conectado, aqui veras las empresas y sus limites.',
                    action: FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Recargar'),
                    ),
                  );
                }
                if (_isDesktop) {
                  final selected = _selected ?? companies.first;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 430,
                        child: _CompanyList(
                          companies: companies,
                          selectedId: selected.companyId,
                          onTap: _openDetail,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _LicenseControlPanel(
                          key: ValueKey(selected.companyId),
                          company: selected,
                          service: _service,
                          onChanged: (updated) {
                            setState(() => _selected = updated);
                            _refresh(silent: true);
                          },
                        ),
                      ),
                    ],
                  );
                }
                return _CompanyList(companies: companies, onTap: _openDetail);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final String status;
  final bool showSearch;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;

  const _Header({
    required this.searchCtrl,
    required this.searchFocus,
    required this.status,
    required this.showSearch,
    required this.onStatusChanged,
    required this.onSearch,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusChip(
              label: 'Todas',
              value: 'TODAS',
              selected: status == 'TODAS',
              onTap: onStatusChanged,
            ),
            _StatusChip(
              label: 'Prueba',
              value: 'TRIAL',
              selected: status == 'TRIAL',
              onTap: onStatusChanged,
            ),
            _StatusChip(
              label: 'Activas',
              value: 'ACTIVE',
              selected: status == 'ACTIVE',
              onTap: onStatusChanged,
            ),
            _StatusChip(
              label: 'Bloqueadas',
              value: 'BLOCKED',
              selected: status == 'BLOCKED',
              onTap: onStatusChanged,
            ),
            _StatusChip(
              label: 'Vencidas',
              value: 'EXPIRED',
              selected: status == 'EXPIRED',
              onTap: onStatusChanged,
            ),
            if (!compact)
              _IconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Recargar',
                onTap: onRefresh,
              ),
          ],
        ),
        if (showSearch) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: searchCtrl,
            focusNode: searchFocus,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                tooltip: 'Buscar',
                onPressed: onSearch,
              ),
              hintText: 'Buscar empresa, slug o licencia',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CompanyList extends StatelessWidget {
  final List<DaleVentasCompanyLicense> companies;
  final String? selectedId;
  final ValueChanged<DaleVentasCompanyLicense> onTap;

  const _CompanyList({
    required this.companies,
    required this.onTap,
    this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: companies.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final company = companies[index];
        return _CompanyCard(
          company: company,
          selected: company.companyId == selectedId,
          onTap: () => onTap(company),
        );
      },
    );
  }
}

class _CompanyCard extends StatelessWidget {
  final DaleVentasCompanyLicense company;
  final bool selected;
  final VoidCallback onTap;

  const _CompanyCard({
    required this.company,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      company.companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  _StatusPill(status: company.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                company.slug ?? company.companyId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _UsageLine(
                icon: Icons.group_outlined,
                label: 'Usuarios',
                used: company.usersUsed,
                max: company.maxUsers,
                value: company.usersRatio,
              ),
              const SizedBox(height: AppSpacing.sm),
              _UsageLine(
                icon: Icons.inventory_2_outlined,
                label: 'Productos',
                used: company.productsUsed,
                max: company.maxProducts,
                value: company.productsRatio,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LicenseControlPanel extends StatefulWidget {
  final DaleVentasCompanyLicense company;
  final DaleVentasLicenseService service;
  final ValueChanged<DaleVentasCompanyLicense> onChanged;

  const _LicenseControlPanel({
    super.key,
    required this.company,
    required this.service,
    required this.onChanged,
  });

  @override
  State<_LicenseControlPanel> createState() => _LicenseControlPanelState();
}

class _LicenseControlPanelState extends State<_LicenseControlPanel> {
  late final TextEditingController _maxUsersCtrl;
  late final TextEditingController _maxProductsCtrl;
  late final TextEditingController _expiresCtrl;
  late final TextEditingController _notesCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _maxUsersCtrl = TextEditingController(
      text: widget.company.maxUsers.toString(),
    );
    _maxProductsCtrl = TextEditingController(
      text: widget.company.maxProducts.toString(),
    );
    _expiresCtrl = TextEditingController(
      text: _dateInput(widget.company.licenseExpiresAt),
    );
    _notesCtrl = TextEditingController(text: widget.company.notes ?? '');
  }

  @override
  void dispose() {
    _maxUsersCtrl.dispose();
    _maxProductsCtrl.dispose();
    _expiresCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<DaleVentasCompanyLicense> Function() action) async {
    setState(() => _busy = true);
    try {
      final updated = await action();
      if (!mounted) return;
      widget.onChanged(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Licencia actualizada en DaleVentas.')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException ? error.message : error.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _body() {
    return {
      'maxUsers':
          int.tryParse(_maxUsersCtrl.text.trim()) ?? widget.company.maxUsers,
      'maxProducts':
          int.tryParse(_maxProductsCtrl.text.trim()) ??
          widget.company.maxProducts,
      'expiresAt': _expiresCtrl.text.trim().isEmpty
          ? null
          : _expiresCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
    };
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final company = widget.company;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company.companyName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        company.licenseKey ?? 'Sin llave permanente',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                _StatusPill(status: company.status),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _MetricTile(
                  icon: Icons.timer_outlined,
                  label: 'Dias',
                  value: '${company.daysRemaining}',
                ),
                _MetricTile(
                  icon: Icons.group_outlined,
                  label: 'Usuarios',
                  value: '${company.usersUsed}/${company.maxUsers}',
                ),
                _MetricTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Productos',
                  value: '${company.productsUsed}/${company.maxProducts}',
                ),
                _MetricTile(
                  icon: Icons.lock_open_rounded,
                  label: 'Acceso',
                  value: company.isUsable ? 'Si' : 'No',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _UsageLine(
              icon: Icons.group_outlined,
              label: 'Consumo de usuarios',
              used: company.usersUsed,
              max: company.maxUsers,
              value: company.usersRatio,
            ),
            const SizedBox(height: AppSpacing.md),
            _UsageLine(
              icon: Icons.inventory_2_outlined,
              label: 'Consumo de productos',
              used: company.productsUsed,
              max: company.maxProducts,
              value: company.productsRatio,
            ),
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoCols = constraints.maxWidth >= 620;
                final fields = [
                  _NumberField(
                    controller: _maxUsersCtrl,
                    label: 'Usuarios permitidos',
                  ),
                  _NumberField(
                    controller: _maxProductsCtrl,
                    label: 'Productos permitidos',
                  ),
                  TextField(
                    controller: _expiresCtrl,
                    decoration: _input('Vence el', hint: '2026-12-31'),
                  ),
                ];
                if (!twoCols) {
                  return Column(
                    children: fields
                        .map(
                          (field) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: field,
                          ),
                        )
                        .toList(),
                  );
                }
                return Row(
                  children: fields
                      .map(
                        (field) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              right: AppSpacing.md,
                            ),
                            child: field,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            TextField(
              controller: _notesCtrl,
              minLines: 3,
              maxLines: 5,
              decoration: _input('Notas internas'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Guardar'),
                  onPressed: () => _run(
                    () => widget.service.updateCompany(
                      company.companyId,
                      _body(),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('Activar'),
                  onPressed: () => _run(
                    () => widget.service.activateCompany(
                      company.companyId,
                      _body(),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('Bloquear'),
                  onPressed: () async {
                    if (await _confirm(
                      'Bloquear licencia',
                      'La empresa saldra de la app al instante.',
                    )) {
                      await _run(
                        () => widget.service.blockCompany(
                          company.companyId,
                          _body(),
                        ),
                      );
                    }
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Eliminar licencia'),
                  onPressed: () async {
                    if (await _confirm(
                      'Eliminar licencia',
                      'La empresa quedara bloqueada y sus sesiones seran cerradas.',
                    )) {
                      await _run(
                        () => widget.service.deleteCompanyLicense(
                          company.companyId,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            if ((company.blockReason ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                company.blockReason!,
                style: const TextStyle(color: AppColors.error),
              ),
            ],
            if (company.auditLogs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              const Text(
                'Historial',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...company.auditLogs.take(8).map((log) => _AuditRow(log: log)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MobileDetailSheet extends StatelessWidget {
  final DaleVentasCompanyLicense company;
  final DaleVentasLicenseService service;
  final ValueChanged<DaleVentasCompanyLicense> onChanged;

  const _MobileDetailSheet({
    required this.company,
    required this.service,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.92,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          0,
        ),
        child: _LicenseControlPanel(
          company: company,
          service: service,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _UsageLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final int used;
  final int max;
  final double value;

  const _UsageLine({
    required this.icon,
    required this.label,
    required this.used,
    required this.max,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final danger = max > 0 && used >= max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: danger ? AppColors.error : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Text(
              '$used / $max',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: value,
            backgroundColor: AppColors.surfaceVariant,
            color: danger ? AppColors.error : AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  final DaleVentasLicenseAuditLog log;

  const _AuditRow({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.badgeRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.history_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${log.action} - ${log.actorEmail ?? 'Appyra'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            _fmtDateTime(log.createdAt),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'ACTIVE' => AppColors.success,
      'TRIAL' => AppColors.info,
      'BLOCKED' => AppColors.error,
      'EXPIRED' => AppColors.warning,
      _ => AppColors.textSecondary,
    };
    final label = switch (status) {
      'ACTIVE' => 'Activa',
      'TRIAL' => 'Prueba',
      'BLOCKED' => 'Bloqueada',
      'EXPIRED' => 'Vencida',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.badgeRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final ValueChanged<String> onTap;

  const _StatusChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(value),
      selectedColor: AppColors.primaryLight,
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.badgeRadius),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(onPressed: onTap, icon: Icon(icon)),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _NumberField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: _input(label),
    );
  }
}

InputDecoration _input(String label, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: AppColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
      borderSide: const BorderSide(color: AppColors.border),
    ),
  );
}

String _dateInput(DateTime? date) {
  if (date == null) return '';
  return DateFormat('yyyy-MM-dd').format(date.toLocal());
}

String _fmtDateTime(DateTime? date) {
  if (date == null) return '';
  return DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
}
