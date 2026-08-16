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
  String _status = 'ACTIVE';
  String _planFilter = 'ENTERPRISE';
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
            setState(() {
              _showSearch = !_showSearch;
            });
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
    return _service
        .listCompanies(
          query: _searchCtrl.text,
          status: _status,
          plan: _planFilter,
          limit: 80,
        )
        .then(_applyPlanFilter);
  }

  DaleVentasLicensePageResult _applyPlanFilter(
    DaleVentasLicensePageResult result,
  ) {
    if (_planFilter == 'TODOS') return result;
    final filtered = result.items
        .where((company) => company.planCode == _planFilter)
        .toList();
    return DaleVentasLicensePageResult(
      page: result.page,
      limit: result.limit,
      total: filtered.length,
      items: filtered,
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
          setState(() {
            _selected = matches.first;
          });
        } else if (mounted) {
          setState(() {
            _selected = result.items.isEmpty ? null : result.items.first;
          });
        }
      }
      return result;
    });
    if (mounted) {
      setState(() {
        _future = next;
      });
    }
  }

  Future<void> _openDetail(DaleVentasCompanyLicense company) async {
    final detail = await _service.getCompany(company.companyId);
    if (!mounted) return;
    if (_isDesktop) {
      setState(() {
        _selected = detail;
      });
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useSafeArea: true,
        builder: (_) => _MobileDetailSheet(
          company: detail,
          onChanged: (updated) {
            setState(() {
              _selected = updated;
            });
            _refresh(silent: true);
          },
          onDeleted: (companyId) {
            setState(() {
              if (_selected?.companyId == companyId) _selected = null;
            });
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
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: EdgeInsets.all(mobile ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            searchCtrl: _searchCtrl,
            searchFocus: _searchFocus,
            status: _status,
            planFilter: _planFilter,
            showSearch: _showSearch || _isDesktop,
            onStatusChanged: (value) {
              setState(() {
                _status = value;
              });
              _refresh();
            },
            onPlanChanged: (value) {
              setState(() {
                _planFilter = value;
                _selected = null;
              });
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
                  final currentSelected = _selected;
                  final selected = currentSelected == null
                      ? companies.first
                      : companies.firstWhere(
                          (item) => item.companyId == currentSelected.companyId,
                          orElse: () => companies.first,
                        );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: 440,
                        child: _CompanyRail(
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
                            setState(() {
                              _selected = updated;
                            });
                            _refresh(silent: true);
                          },
                          onDeleted: (companyId) {
                            setState(() {
                              if (_selected?.companyId == companyId) {
                                _selected = null;
                              }
                            });
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
  final String planFilter;
  final bool showSearch;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onPlanChanged;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;

  const _Header({
    required this.searchCtrl,
    required this.searchFocus,
    required this.status,
    required this.planFilter,
    required this.showSearch,
    required this.onStatusChanged,
    required this.onPlanChanged,
    required this.onSearch,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final chips = [
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
    ];
    final planChips = [
      _StatusChip(
        label: 'Todos los planes',
        value: 'TODOS',
        selected: planFilter == 'TODOS',
        onTap: onPlanChanged,
      ),
      _StatusChip(
        label: 'Plan basico',
        value: 'STANDARD',
        selected: planFilter == 'STANDARD',
        onTap: onPlanChanged,
      ),
      _StatusChip(
        label: 'Plan enterprise',
        value: 'ENTERPRISE',
        selected: planFilter == 'ENTERPRISE',
        onTap: onPlanChanged,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HorizontalChipList(chips: chips),
              const SizedBox(height: AppSpacing.sm),
              _HorizontalChipList(chips: planChips),
            ],
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...chips,
              const SizedBox(width: AppSpacing.sm),
              ...planChips,
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

class _HorizontalChipList extends StatelessWidget {
  final List<Widget> chips;

  const _HorizontalChipList({required this.chips});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) => chips[index],
      ),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
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

class _CompanyRail extends StatelessWidget {
  final List<DaleVentasCompanyLicense> companies;
  final String? selectedId;
  final ValueChanged<DaleVentasCompanyLicense> onTap;

  const _CompanyRail({
    required this.companies,
    required this.onTap,
    this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    final limited = companies.where((company) {
      return company.usersUsed >= company.maxUsers ||
          company.productsUsed >= company.maxProducts;
    }).length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(
                      AppSpacing.buttonRadius,
                    ),
                  ),
                  child: const Icon(
                    Icons.business_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Empresas cloud',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${companies.length} empresas · Control por empresa · $limited con limite alcanzado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: _CompanyList(
                companies: companies,
                selectedId: selectedId,
                onTap: onTap,
              ),
            ),
          ),
        ],
      ),
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
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final overLimit =
        company.usersUsed >= company.maxUsers ||
        company.productsUsed >= company.maxProducts;
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(mobile ? AppSpacing.md : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : overLimit
                  ? AppColors.warning.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: mobile ? 6 : 8,
                    height: mobile ? 44 : 38,
                    decoration: BoxDecoration(
                      color: overLimit ? AppColors.warning : AppColors.primary,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          company.companyName,
                          maxLines: mobile ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${company.planLabel} · ${company.slug ?? company.companyId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusPill(status: company.status),
                ],
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
  final ValueChanged<String> onDeleted;

  const _LicenseControlPanel({
    super.key,
    required this.company,
    required this.service,
    required this.onChanged,
    required this.onDeleted,
  });

  @override
  State<_LicenseControlPanel> createState() => _LicenseControlPanelState();
}

class _LicenseControlPanelState extends State<_LicenseControlPanel> {
  late final TextEditingController _maxUsersCtrl;
  late final TextEditingController _maxProductsCtrl;
  late final TextEditingController _durationDaysCtrl;
  late final TextEditingController _expiresCtrl;
  late final TextEditingController _companyNameCtrl;
  late final TextEditingController _taxIdCtrl;
  late final TextEditingController _businessPhoneCtrl;
  late final TextEditingController _businessAddressCtrl;
  late final TextEditingController _businessTypeCtrl;
  late final TextEditingController _responsibleNameCtrl;
  late final TextEditingController _responsibleEmailCtrl;
  late final TextEditingController _responsibleWhatsappCtrl;
  late final TextEditingController _notesCtrl;
  late String _planCode;
  bool _busy = false;
  bool _syncingExpirationFields = false;

  @override
  void initState() {
    super.initState();
    _maxUsersCtrl = TextEditingController(
      text: widget.company.maxUsers.toString(),
    );
    _maxProductsCtrl = TextEditingController(
      text: widget.company.maxProducts.toString(),
    );
    _durationDaysCtrl = TextEditingController(
      text: _daysUntilInput(widget.company.licenseExpiresAt),
    );
    _expiresCtrl = TextEditingController(
      text: _dateInput(widget.company.licenseExpiresAt),
    );
    _companyNameCtrl = TextEditingController(
      text: widget.company.account.businessName ?? widget.company.companyName,
    );
    _taxIdCtrl = TextEditingController(
      text: widget.company.account.taxId ?? '',
    );
    _businessPhoneCtrl = TextEditingController(
      text: widget.company.account.businessPhone ?? '',
    );
    _businessAddressCtrl = TextEditingController(
      text: widget.company.account.businessAddress ?? '',
    );
    _businessTypeCtrl = TextEditingController(
      text: widget.company.account.businessType ?? '',
    );
    _responsibleNameCtrl = TextEditingController(
      text: widget.company.account.responsibleName ?? '',
    );
    _responsibleEmailCtrl = TextEditingController(
      text: widget.company.account.responsibleEmail ?? '',
    );
    _responsibleWhatsappCtrl = TextEditingController(
      text:
          widget.company.account.responsibleWhatsapp ??
          widget.company.account.businessPhone ??
          '',
    );
    _notesCtrl = TextEditingController(text: widget.company.notes ?? '');
    _planCode = widget.company.planCode;
    _durationDaysCtrl.addListener(_syncExpiresFromDays);
    _expiresCtrl.addListener(_syncDaysFromExpires);
  }

  @override
  void didUpdateWidget(covariant _LicenseControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company.companyId == widget.company.companyId) return;
    _maxUsersCtrl.text = widget.company.maxUsers.toString();
    _maxProductsCtrl.text = widget.company.maxProducts.toString();
    _setExpirationFields(widget.company.licenseExpiresAt);
    _syncAccountFields();
    _notesCtrl.text = widget.company.notes ?? '';
    _planCode = widget.company.planCode;
  }

  @override
  void dispose() {
    _maxUsersCtrl.dispose();
    _maxProductsCtrl.dispose();
    _durationDaysCtrl.dispose();
    _expiresCtrl.dispose();
    _companyNameCtrl.dispose();
    _taxIdCtrl.dispose();
    _businessPhoneCtrl.dispose();
    _businessAddressCtrl.dispose();
    _businessTypeCtrl.dispose();
    _responsibleNameCtrl.dispose();
    _responsibleEmailCtrl.dispose();
    _responsibleWhatsappCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _syncAccountFields() {
    final account = widget.company.account;
    _companyNameCtrl.text = account.businessName ?? widget.company.companyName;
    _taxIdCtrl.text = account.taxId ?? '';
    _businessPhoneCtrl.text = account.businessPhone ?? '';
    _businessAddressCtrl.text = account.businessAddress ?? '';
    _businessTypeCtrl.text = account.businessType ?? '';
    _responsibleNameCtrl.text = account.responsibleName ?? '';
    _responsibleEmailCtrl.text = account.responsibleEmail ?? '';
    _responsibleWhatsappCtrl.text =
        account.responsibleWhatsapp ?? account.businessPhone ?? '';
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime? _parseExpiresInput() {
    final text = _expiresCtrl.text.trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  void _setExpirationFields(DateTime? date) {
    _syncingExpirationFields = true;
    _expiresCtrl.text = _dateInput(date);
    _durationDaysCtrl.text = _daysUntilInput(date);
    _syncingExpirationFields = false;
  }

  void _syncExpiresFromDays() {
    if (_syncingExpirationFields) return;
    final text = _durationDaysCtrl.text.trim();
    _syncingExpirationFields = true;
    if (text.isEmpty) {
      _expiresCtrl.text = '';
    } else {
      final days = int.tryParse(text);
      if (days != null) {
        _expiresCtrl.text = _dateInput(_today.add(Duration(days: days)));
      }
    }
    _syncingExpirationFields = false;
  }

  void _syncDaysFromExpires() {
    if (_syncingExpirationFields) return;
    final date = _parseExpiresInput();
    _syncingExpirationFields = true;
    _durationDaysCtrl.text = date == null
        ? ''
        : date.difference(_today).inDays.toString();
    _syncingExpirationFields = false;
  }

  void _adjustDuration(int delta) {
    final current =
        int.tryParse(_durationDaysCtrl.text.trim()) ??
        (_parseExpiresInput()?.difference(_today).inDays ?? 0);
    final next = current + delta;
    _durationDaysCtrl.text = next.toString();
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

  Future<void> _runPermanentDelete() async {
    setState(() => _busy = true);
    try {
      await widget.service.permanentlyDeleteCompanyLicense(
        widget.company.companyId,
      );
      if (!mounted) return;
      widget.onDeleted(widget.company.companyId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Licencia eliminada completamente.')),
      );
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
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
      'plan': _planCode,
      'maxUsers':
          int.tryParse(_maxUsersCtrl.text.trim()) ?? widget.company.maxUsers,
      'maxProducts':
          int.tryParse(_maxProductsCtrl.text.trim()) ??
          widget.company.maxProducts,
      'expiresAt': _expiresCtrl.text.trim().isEmpty
          ? null
          : _expiresCtrl.text.trim(),
      'companyName': _companyNameCtrl.text.trim(),
      'businessName': _companyNameCtrl.text.trim(),
      'taxId': _taxIdCtrl.text.trim(),
      'businessPhone': _businessPhoneCtrl.text.trim(),
      'businessAddress': _businessAddressCtrl.text.trim(),
      'businessType': _businessTypeCtrl.text.trim(),
      'responsibleName': _responsibleNameCtrl.text.trim(),
      'responsibleEmail': _responsibleEmailCtrl.text.trim(),
      'responsibleWhatsapp': _responsibleWhatsappCtrl.text.trim(),
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

  Future<bool> _confirmPermanentDelete() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Eliminar completamente'),
              content: Text(
                'Esto borrara la empresa, licencia, sesiones y datos asociados de ${widget.company.companyName}. ¿Estas seguro?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Eliminar todo'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final company = widget.company;
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
          mobile ? 18 : AppSpacing.cardRadius,
        ),
        border: mobile ? null : Border.all(color: AppColors.border),
      ),
      child: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            mobile ? AppSpacing.md : AppSpacing.lg,
            mobile ? AppSpacing.sm : AppSpacing.lg,
            mobile ? AppSpacing.md : AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Container(
              padding: EdgeInsets.all(mobile ? AppSpacing.md : AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: mobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _CompanyIcon(size: 42),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                company.companyName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _StatusPill(status: company.status),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        SelectableText(
                          '${company.planLabel} · ${company.policyLabel}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        _CompanyIcon(size: 46),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                company.companyName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              SelectableText(
                                '${company.planLabel} · ${company.policyLabel}',
                                maxLines: 1,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        _StatusPill(status: company.status),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final tileWidth = width >= 760
                    ? (width - AppSpacing.sm * 3) / 4
                    : width >= 520
                    ? (width - AppSpacing.sm) / 2
                    : width;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: tileWidth,
                      child: _MetricTile(
                        icon: Icons.timer_outlined,
                        label: 'Prueba restante',
                        value: '${company.daysRemaining} dias',
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _MetricTile(
                        icon: Icons.group_outlined,
                        label: 'Usuarios',
                        value: '${company.usersUsed}/${company.maxUsers}',
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _MetricTile(
                        icon: Icons.inventory_2_outlined,
                        label: 'Productos',
                        value: '${company.productsUsed}/${company.maxProducts}',
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _MetricTile(
                        icon: Icons.lock_open_rounded,
                        label: 'Acceso',
                        value: company.isUsable ? 'Permitido' : 'Bloqueado',
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            _PlanNotice(company: company),
            const SizedBox(height: AppSpacing.md),
            _SectionPanel(
              title: 'Vigencia y alcance',
              icon: Icons.event_available_outlined,
              child: _LicenseTermsSummary(company: company),
            ),
            const SizedBox(height: AppSpacing.md),
            _SectionPanel(
              title: 'Cuenta y contacto',
              icon: Icons.badge_outlined,
              child: _AccountSummary(company: company),
            ),
            const SizedBox(height: AppSpacing.md),
            _SectionPanel(
              title: 'Datos de empresa y dueño',
              icon: Icons.edit_note_rounded,
              child: _EditableAccountFields(
                companyNameCtrl: _companyNameCtrl,
                taxIdCtrl: _taxIdCtrl,
                businessPhoneCtrl: _businessPhoneCtrl,
                businessAddressCtrl: _businessAddressCtrl,
                businessTypeCtrl: _businessTypeCtrl,
                responsibleNameCtrl: _responsibleNameCtrl,
                responsibleEmailCtrl: _responsibleEmailCtrl,
                responsibleWhatsappCtrl: _responsibleWhatsappCtrl,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _SectionPanel(
              title: 'Consumo actual',
              icon: Icons.insert_chart_outlined_rounded,
              child: Column(
                children: [
                  _UsageLine(
                    icon: Icons.group_outlined,
                    label: 'Usuarios activos',
                    used: company.usersUsed,
                    max: company.maxUsers,
                    value: company.usersRatio,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _UsageLine(
                    icon: Icons.inventory_2_outlined,
                    label: 'Productos registrados',
                    used: company.productsUsed,
                    max: company.maxProducts,
                    value: company.productsRatio,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _SectionPanel(
              title: 'Control de licencia',
              icon: Icons.tune_rounded,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _planCode,
                    decoration: _input('Tipo de licencia'),
                    items: const [
                      DropdownMenuItem(
                        value: 'STANDARD',
                        child: Text('Plan basico'),
                      ),
                      DropdownMenuItem(
                        value: 'ENTERPRISE',
                        child: Text('Plan enterprise'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _planCode = value;
                        if (value == 'STANDARD') {
                          final users = int.tryParse(_maxUsersCtrl.text) ?? 0;
                          final products =
                              int.tryParse(_maxProductsCtrl.text) ?? 0;
                          if (users <= 0) _maxUsersCtrl.text = '2';
                          if (products <= 0) _maxProductsCtrl.text = '100';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                        _NumberField(
                          controller: _durationDaysCtrl,
                          label: 'Tiempo en dias',
                        ),
                        _ExpirationDateField(controller: _expiresCtrl),
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
                        children: [
                          for (var index = 0; index < fields.length; index++)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: index == fields.length - 1
                                      ? 0
                                      : AppSpacing.md,
                                ),
                                child: fields[index],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DurationAdjustments(onAdjust: _adjustDuration),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _notesCtrl,
                    minLines: 3,
                    maxLines: 5,
                    decoration: _input('Notas internas'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _SectionPanel(
              title: 'Acciones',
              icon: Icons.admin_panel_settings_rounded,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fullWidth = constraints.maxWidth < 520;
                  Widget action(Widget child) => fullWidth
                      ? SizedBox(width: double.infinity, child: child)
                      : child;
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      action(
                        FilledButton.icon(
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                      ),
                      action(
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
                      ),
                      action(
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
                      ),
                      action(
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
                      ),
                      action(
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.55),
                            ),
                          ),
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const Text('Eliminar completamente'),
                          onPressed: () async {
                            if (await _confirmPermanentDelete()) {
                              await _runPermanentDelete();
                            }
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            if ((company.blockReason ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                company.blockReason!,
                style: const TextStyle(color: AppColors.error),
              ),
            ],
            if (company.auditLogs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _SectionPanel(
                title: 'Historial',
                icon: Icons.history_rounded,
                child: Column(
                  children: company.auditLogs
                      .take(8)
                      .map((log) => _AuditRow(log: log))
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionPanel({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _CompanyIcon extends StatelessWidget {
  final double size;

  const _CompanyIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.cloud_done_rounded, color: AppColors.primary),
    );
  }
}

class _AccountSummary extends StatelessWidget {
  final DaleVentasCompanyLicense company;

  const _AccountSummary({required this.company});

  @override
  Widget build(BuildContext context) {
    final account = company.account;
    final items = [
      _InfoItem(
        icon: Icons.storefront_outlined,
        label: 'Negocio',
        value: account.businessName ?? company.companyName,
      ),
      _InfoItem(
        icon: Icons.person_outline_rounded,
        label: 'Responsable',
        value: account.responsibleName ?? 'Sin responsable registrado',
      ),
      _InfoItem(
        icon: Icons.phone_outlined,
        label: 'WhatsApp',
        value:
            account.responsibleWhatsapp ??
            account.businessPhone ??
            'Sin WhatsApp registrado',
      ),
      _InfoItem(
        icon: Icons.mail_outline_rounded,
        label: 'Correo',
        value: account.responsibleEmail ?? 'Sin correo registrado',
      ),
      _InfoItem(
        icon: Icons.receipt_long_outlined,
        label: 'RNC / Cedula',
        value: account.taxId ?? 'No registrado',
      ),
      _InfoItem(
        icon: Icons.location_on_outlined,
        label: 'Direccion',
        value: account.businessAddress ?? 'Sin direccion registrada',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: items
              .map((item) => SizedBox(width: width, child: item))
              .toList(),
        );
      },
    );
  }
}

class _EditableAccountFields extends StatefulWidget {
  final TextEditingController companyNameCtrl;
  final TextEditingController taxIdCtrl;
  final TextEditingController businessPhoneCtrl;
  final TextEditingController businessAddressCtrl;
  final TextEditingController businessTypeCtrl;
  final TextEditingController responsibleNameCtrl;
  final TextEditingController responsibleEmailCtrl;
  final TextEditingController responsibleWhatsappCtrl;

  const _EditableAccountFields({
    required this.companyNameCtrl,
    required this.taxIdCtrl,
    required this.businessPhoneCtrl,
    required this.businessAddressCtrl,
    required this.businessTypeCtrl,
    required this.responsibleNameCtrl,
    required this.responsibleEmailCtrl,
    required this.responsibleWhatsappCtrl,
  });

  @override
  State<_EditableAccountFields> createState() => _EditableAccountFieldsState();
}

class _EditableAccountFieldsState extends State<_EditableAccountFields> {
  final Set<String> _editableFields = <String>{};

  Future<void> _enableField(String fieldId, String label) async {
    if (_editableFields.contains(fieldId)) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Editar dato'),
            content: Text(
              '¿Estas seguro que quieres editar "$label"? Cambiar este dato puede afectar la informacion de la licencia.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Editar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _editableFields.add(fieldId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fields = [
      _ConfirmEditableField(
        fieldId: 'companyName',
        label: 'Nombre de empresa',
        controller: widget.companyNameCtrl,
        editable: _editableFields.contains('companyName'),
        onEnable: _enableField,
        textCapitalization: TextCapitalization.words,
      ),
      _ConfirmEditableField(
        fieldId: 'responsibleName',
        label: 'Nombre del dueño',
        controller: widget.responsibleNameCtrl,
        editable: _editableFields.contains('responsibleName'),
        onEnable: _enableField,
        textCapitalization: TextCapitalization.words,
      ),
      _ConfirmEditableField(
        fieldId: 'responsibleWhatsapp',
        label: 'WhatsApp del dueño',
        controller: widget.responsibleWhatsappCtrl,
        editable: _editableFields.contains('responsibleWhatsapp'),
        onEnable: _enableField,
        keyboardType: TextInputType.phone,
      ),
      _ConfirmEditableField(
        fieldId: 'responsibleEmail',
        label: 'Correo del dueño',
        controller: widget.responsibleEmailCtrl,
        editable: _editableFields.contains('responsibleEmail'),
        onEnable: _enableField,
        keyboardType: TextInputType.emailAddress,
      ),
      _ConfirmEditableField(
        fieldId: 'taxId',
        label: 'RNC / Cedula',
        controller: widget.taxIdCtrl,
        editable: _editableFields.contains('taxId'),
        onEnable: _enableField,
        keyboardType: TextInputType.text,
      ),
      _ConfirmEditableField(
        fieldId: 'businessPhone',
        label: 'Telefono del negocio',
        controller: widget.businessPhoneCtrl,
        editable: _editableFields.contains('businessPhone'),
        onEnable: _enableField,
        keyboardType: TextInputType.phone,
      ),
      _ConfirmEditableField(
        fieldId: 'businessAddress',
        label: 'Direccion',
        controller: widget.businessAddressCtrl,
        editable: _editableFields.contains('businessAddress'),
        onEnable: _enableField,
        textCapitalization: TextCapitalization.sentences,
      ),
      _ConfirmEditableField(
        fieldId: 'businessType',
        label: 'Tipo de negocio',
        controller: widget.businessTypeCtrl,
        editable: _editableFields.contains('businessType'),
        onEnable: _enableField,
        textCapitalization: TextCapitalization.sentences,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.md,
          children: fields
              .map((field) => SizedBox(width: width, child: field))
              .toList(),
        );
      },
    );
  }
}

class _ConfirmEditableField extends StatelessWidget {
  final String fieldId;
  final String label;
  final TextEditingController controller;
  final bool editable;
  final Future<void> Function(String fieldId, String label) onEnable;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  const _ConfirmEditableField({
    required this.fieldId,
    required this.label,
    required this.controller,
    required this.editable,
    required this.onEnable,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: !editable,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onTap: editable ? null : () => onEnable(fieldId, label),
      decoration: _input(label).copyWith(
        suffixIcon: IconButton(
          tooltip: editable ? 'Campo editable' : 'Habilitar edicion',
          icon: Icon(
            editable ? Icons.lock_open_rounded : Icons.edit_rounded,
            color: editable ? AppColors.success : AppColors.textSecondary,
          ),
          onPressed: editable ? null : () => onEnable(fieldId, label),
        ),
      ),
    );
  }
}

class _LicenseTermsSummary extends StatelessWidget {
  final DaleVentasCompanyLicense company;

  const _LicenseTermsSummary({required this.company});

  @override
  Widget build(BuildContext context) {
    final items = [
      _InfoItem(
        icon: Icons.workspace_premium_outlined,
        label: 'Tipo de licencia',
        value: company.planLabel,
      ),
      _InfoItem(
        icon: Icons.calendar_today_outlined,
        label: 'Inicio',
        value: _fmtDateOnly(company.startsAt),
      ),
      _InfoItem(
        icon: Icons.event_busy_outlined,
        label: 'Finaliza',
        value: _fmtDateOnly(company.endsAt),
      ),
      _InfoItem(
        icon: Icons.rule_folder_outlined,
        label: 'Alcance contratado',
        value:
            '${company.maxUsers} usuarios · ${company.maxProducts} productos',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: items
              .map((item) => SizedBox(width: width, child: item))
              .toList(),
        );
      },
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  maxLines: 2,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanNotice extends StatelessWidget {
  final DaleVentasCompanyLicense company;

  const _PlanNotice({required this.company});

  @override
  Widget build(BuildContext context) {
    final color = company.isUsable ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_outlined, color: color, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company.planLabel,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  company.policyLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileDetailSheet extends StatelessWidget {
  final DaleVentasCompanyLicense company;
  final DaleVentasLicenseService service;
  final ValueChanged<DaleVentasCompanyLicense> onChanged;
  final ValueChanged<String> onDeleted;

  const _MobileDetailSheet({
    required this.company,
    required this.service,
    required this.onChanged,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: ColoredBox(
        color: AppColors.surface,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.94,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: _LicenseControlPanel(
                  company: company,
                  service: service,
                  onChanged: onChanged,
                  onDeleted: onDeleted,
                ),
              ),
            ],
          ),
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

class _ExpirationDateField extends StatelessWidget {
  final TextEditingController controller;

  const _ExpirationDateField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: _input('Vence el', hint: '2026-12-31'),
    );
  }
}

class _DurationAdjustments extends StatelessWidget {
  final ValueChanged<int> onAdjust;

  const _DurationAdjustments({required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          _DurationChip(label: '-30 dias', delta: -30, onAdjust: onAdjust),
          _DurationChip(label: '-7 dias', delta: -7, onAdjust: onAdjust),
          _DurationChip(label: '+7 dias', delta: 7, onAdjust: onAdjust),
          _DurationChip(label: '+30 dias', delta: 30, onAdjust: onAdjust),
        ],
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  final String label;
  final int delta;
  final ValueChanged<int> onAdjust;

  const _DurationChip({
    required this.label,
    required this.delta,
    required this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => onAdjust(delta),
      child: Text(label),
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

String _daysUntilInput(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  final expires = DateTime(local.year, local.month, local.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return expires.difference(today).inDays.toString();
}

String _fmtDateOnly(DateTime? date) {
  if (date == null) return 'Sin fecha definida';
  return DateFormat('dd/MM/yyyy').format(date.toLocal());
}

String _fmtDateTime(DateTime? date) {
  if (date == null) return '';
  return DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
}
