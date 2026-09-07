import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/layout/app_shell_actions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/marketing_contact_actions.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../models/daleventas_company_license.dart';
import '../services/daleventas_license_service.dart';
import '../../usage_analytics/models/usage_analytics.dart';
import '../../usage_analytics/services/usage_analytics_service.dart';

class DaleVentasLicensesPage extends StatefulWidget {
  const DaleVentasLicensesPage({super.key});

  @override
  State<DaleVentasLicensesPage> createState() => _DaleVentasLicensesPageState();
}

class _DaleVentasLicensesPageState extends State<DaleVentasLicensesPage> {
  late final DaleVentasLicenseService _service;
  late final UsageAnalyticsService _usageService;
  late Future<DaleVentasLicensePageResult> _future;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _pollTimer;

  DaleVentasCompanyLicense? _selected;
  String _status = 'DEMO_ACTIVE';
  String _planFilter = 'TODOS';
  final bool _showSearch = false;
  AppShellActionsController? _shellActionsController;
  bool? _shellActionsMobile;
  Map<String, UsageAccount> _usageByCompany = {};
  DaleVentasLicensePageResult? _lastResult;

  bool get _isDesktop => MediaQuery.sizeOf(context).width >= 1020;

  @override
  void initState() {
    super.initState();
    _service = DaleVentasLicenseService(
      sessionManager: context.read<SessionManager>(),
    );
    _usageService = UsageAnalyticsService(
      sessionManager: context.read<SessionManager>(),
    );
    _future = _load().then(_rememberResult);
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
          onTap: _openSearchOverlay,
        ),
        AppShellAction(
          icon: Icons.tune_rounded,
          label: 'Filtros',
          onTap: _openFilterPanel,
        ),
      ]);
    });
  }

  Future<DaleVentasLicensePageResult> _load() async {
    final bridgeStatus = _technicalStatusFilter(_status);
    final result = await _service
        .listCompanies(
          query: _searchCtrl.text,
          status: bridgeStatus,
          plan: '',
          limit: 80,
        )
        .then(_applyCommercialFilters);

    try {
      final usage = await _usageService.getDashboard(
        appCode: 'DALEVENTAS_POS',
        limit: 200,
      );
      _usageByCompany = _indexUsage(usage.accounts.accounts);
    } catch (_) {
      _usageByCompany = {};
    }

    return result;
  }

  DaleVentasLicensePageResult _rememberResult(
    DaleVentasLicensePageResult result,
  ) {
    _lastResult = result;
    return result;
  }

  Map<String, UsageAccount> _indexUsage(List<UsageAccount> accounts) {
    final map = <String, UsageAccount>{};
    for (final account in accounts) {
      final keys = [
        account.businessId,
        account.customerId,
        account.licenseId,
        account.licenseKey,
        account.customerName,
        account.metricString('business_name'),
        account.metricString('business_slug'),
      ];
      for (final key in keys) {
        final normalized = _usageKey(key);
        if (normalized != null) map[normalized] = account;
      }
    }
    return map;
  }

  UsageAccount? _usageFor(DaleVentasCompanyLicense company) {
    final keys = [
      company.companyId,
      company.slug,
      company.licenseKey,
      company.companyName,
      company.account.businessName,
    ];
    for (final key in keys) {
      final normalized = _usageKey(key);
      if (normalized != null && _usageByCompany.containsKey(normalized)) {
        return _usageByCompany[normalized];
      }
    }
    return null;
  }

  String _technicalStatusFilter(String value) {
    if (value == 'DEMO_ACTIVE') return 'ACTIVE';
    const technical = {'TRIAL', 'ACTIVE', 'BLOCKED', 'EXPIRED'};
    return technical.contains(value) ? value : '';
  }

  DaleVentasLicensePageResult _applyCommercialFilters(
    DaleVentasLicensePageResult result,
  ) {
    var filtered = result.items;

    if (_status == 'DEMO_ACTIVE') {
      filtered = filtered
          .where(
            (company) =>
                (company.commercial?.commercialStatus ?? 'DEMO') == 'DEMO',
          )
          .toList();
    } else if (_status == 'DEMO') {
      filtered = filtered
          .where(
            (company) =>
                (company.commercial?.commercialStatus ?? 'DEMO') == 'DEMO',
          )
          .toList();
    } else if (_status == 'COMPRARON') {
      filtered = filtered.where((company) {
        final status = company.commercial?.commercialStatus ?? '';
        return status == 'PURCHASED' ||
            status == 'ACTIVE_CUSTOMER' ||
            status == 'RENEWAL_DUE';
      }).toList();
    } else if (_status == 'SEGUIMIENTO') {
      filtered = filtered
          .where((company) => company.commercial?.nextFollowUpAt != null)
          .toList();
    } else if (_status == 'POR_VENCER') {
      filtered = filtered.where((company) {
        final endsAt = company.endsAt;
        if (endsAt == null) return false;
        final days = endsAt.difference(DateTime.now()).inDays;
        return days >= 0 && days <= 30;
      }).toList();
    } else if (_status == 'ACTIVE_CUSTOMER') {
      filtered = filtered
          .where(
            (company) =>
                company.commercial?.commercialStatus == 'ACTIVE_CUSTOMER',
          )
          .toList();
    }

    if (_planFilter != 'TODOS') {
      filtered = filtered.where((company) {
        final code = company.commercialPlanCode;
        if (_planFilter == 'LEGACY') {
          return code == 'LEGACY' || code == 'CUSTOM';
        }
        return code == _planFilter;
      }).toList();
    }

    filtered = [...filtered]..sort(_compareNewestCompanyFirst);

    return DaleVentasLicensePageResult(
      page: result.page,
      limit: result.limit,
      total: filtered.length,
      items: filtered,
    );
  }

  void _refresh({bool silent = false}) {
    final next = _load()
        .then((result) {
          _rememberResult(result);
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
        })
        .catchError((error) {
          final cached = _lastResult;
          if (silent && cached != null) return cached;
          throw error;
        });
    if (mounted) {
      setState(() {
        _future = next;
      });
    }
  }

  int _compareNewestCompanyFirst(
    DaleVentasCompanyLicense a,
    DaleVentasCompanyLicense b,
  ) {
    final bDate = b.startsAt ?? b.licenseActivatedAt ?? b.trialStartedAt;
    final aDate = a.startsAt ?? a.licenseActivatedAt ?? a.trialStartedAt;
    if (aDate == null && bDate == null) {
      return a.companyName.compareTo(b.companyName);
    }
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  }

  void _replaceCompany(DaleVentasCompanyLicense updated) {
    final current = _lastResult;
    if (current == null) {
      _selected = updated;
      return;
    }
    final items =
        current.items
            .map((item) => item.companyId == updated.companyId ? updated : item)
            .toList()
          ..sort(_compareNewestCompanyFirst);
    final next = DaleVentasLicensePageResult(
      page: current.page,
      limit: current.limit,
      total: current.total,
      items: items,
    );
    _lastResult = next;
    setState(() {
      _selected = updated;
      _future = Future.value(next);
    });
  }

  void _removeCompany(String companyId) {
    final current = _lastResult;
    if (current == null) return;
    final items = current.items
        .where((item) => item.companyId != companyId)
        .toList();
    final next = DaleVentasLicensePageResult(
      page: current.page,
      limit: current.limit,
      total: items.length,
      items: items,
    );
    _lastResult = next;
    setState(() {
      if (_selected?.companyId == companyId) _selected = null;
      _future = Future.value(next);
    });
  }

  Future<void> _runCompanyListAction(
    Future<DaleVentasCompanyLicense> Function() action, {
    String successMessage = 'Empresa actualizada.',
  }) async {
    try {
      final updated = await action();
      if (!mounted) return;
      _replaceCompany(updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException ? error.message : error.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _handleCompanyAction(
    DaleVentasCompanyLicense company,
    String action,
  ) async {
    switch (action) {
      case 'detail':
        await _openDetail(company);
        return;
      case 'plan':
        await _openPlanActionSheet(company);
        return;
      case 'date':
        await _openDateActionSheet(company);
        return;
      case 'limits':
        await _openLimitsActionSheet(company);
        return;
      case 'activate':
        await _runCompanyListAction(
          () => _service.activateCompany(
            company.companyId,
            _licenseBody(company),
          ),
          successMessage: 'Licencia activada.',
        );
        return;
      case 'danger':
        await _openDangerActionSheet(company);
        return;
    }
  }

  Map<String, dynamic> _licenseBody(DaleVentasCompanyLicense company) {
    return {
      'plan': company.planCode,
      'maxUsers': company.maxUsers,
      'maxProducts': company.maxProducts,
      'expiresAt': company.endsAt?.toIso8601String(),
      'companyName': company.companyName,
      'businessName': company.account.businessName ?? company.companyName,
      'taxId': company.account.taxId,
      'businessPhone': company.account.businessPhone,
      'businessAddress': company.account.businessAddress,
      'businessType': company.account.businessType,
      'responsibleName': company.account.responsibleName,
      'responsibleEmail': company.account.responsibleEmail,
      'responsibleWhatsapp': company.account.responsibleWhatsapp,
      'notes': company.notes,
    };
  }

  Future<void> _openFilterPanel() async {
    var draftStatus = _status;
    var draftPlan = _planFilter;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar filtros',
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: const Duration(milliseconds: 230),
      pageBuilder: (context, animation, secondaryAnimation) {
        final width = MediaQuery.sizeOf(context).width;
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: AppColors.surface,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(22),
            ),
            child: SafeArea(
              left: false,
              child: SizedBox(
                width: width.clamp(300.0, 390.0).toDouble(),
                height: double.infinity,
                child: StatefulBuilder(
                  builder: (context, setPanelState) {
                    return _FilterDrawerContent(
                      status: draftStatus,
                      planFilter: draftPlan,
                      searchCtrl: _searchCtrl,
                      searchFocus: _searchFocus,
                      onStatusChanged: (value) {
                        setPanelState(() => draftStatus = value);
                      },
                      onPlanChanged: (value) {
                        setPanelState(() => draftPlan = value);
                      },
                      onClose: () => Navigator.of(context).pop(),
                      onReset: () {
                        setPanelState(() {
                          draftStatus = 'TODOS';
                          draftPlan = 'TODOS';
                          _searchCtrl.clear();
                        });
                      },
                      onApply: () {
                        setState(() {
                          _status = draftStatus;
                          _planFilter = draftPlan;
                          _selected = null;
                        });
                        Navigator.of(context).pop();
                        _refresh();
                      },
                      onRefresh: () {
                        Navigator.of(context).pop();
                        _refresh();
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  Future<void> _openSearchOverlay() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar búsqueda',
      barrierColor: Colors.black.withValues(alpha: 0.08),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Container(
                height: 84,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) {
                          Navigator.of(context).pop();
                          _refresh();
                        },
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: IconButton(
                            tooltip: 'Buscar',
                            onPressed: () {
                              Navigator.of(context).pop();
                              _refresh();
                            },
                            icon: const Icon(Icons.arrow_forward_rounded),
                          ),
                          hintText: 'Buscar empresa, slug o licencia',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  Future<void> _openPlanActionSheet(DaleVentasCompanyLicense company) async {
    var selectedPlan = company.commercialPlanCode;
    if (selectedPlan != 'BASIC' &&
        selectedPlan != 'BUSINESS' &&
        selectedPlan != 'PRO') {
      selectedPlan = 'BASIC';
    }
    var selectedStatus = company.commercial?.commercialStatus ?? 'DEMO';
    var saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return _ActionSheetFrame(
            title: 'Cambiar plan',
            icon: Icons.workspace_premium_outlined,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PlanPicker(
                  selectedPlan: selectedPlan,
                  onChanged: (value) =>
                      setSheetState(() => selectedPlan = value),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: _input('Estado comercial'),
                  items: const [
                    DropdownMenuItem(value: 'DEMO', child: Text('Demo')),
                    DropdownMenuItem(
                      value: 'CONTACTED',
                      child: Text('Contactado'),
                    ),
                    DropdownMenuItem(
                      value: 'INTERESTED',
                      child: Text('Interesado'),
                    ),
                    DropdownMenuItem(value: 'PURCHASED', child: Text('Compró')),
                    DropdownMenuItem(
                      value: 'ACTIVE_CUSTOMER',
                      child: Text('Cliente activo'),
                    ),
                    DropdownMenuItem(
                      value: 'RENEWAL_DUE',
                      child: Text('Por renovar'),
                    ),
                    DropdownMenuItem(value: 'EXPIRED', child: Text('Vencido')),
                    DropdownMenuItem(value: 'LOST', child: Text('Perdido')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setSheetState(() => selectedStatus = value);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            setSheetState(() => saving = true);
                            await _runCompanyListAction(
                              () => _service.assignCommercialPlan(
                                company.companyId,
                                planCode: selectedPlan,
                                commercialStatus: selectedStatus,
                              ),
                              successMessage: 'Plan actualizado.',
                            );
                            if (context.mounted) Navigator.of(context).pop();
                          },
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Guardar plan'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openDateActionSheet(DaleVentasCompanyLicense company) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final currentDays = _remainingDays(company);
    final daysCtrl = TextEditingController(text: currentDays?.toString() ?? '');
    final dateCtrl = TextEditingController(text: _dateInput(company.endsAt));
    var saving = false;

    void syncDateFromDays() {
      final days = int.tryParse(daysCtrl.text.trim());
      if (days == null) return;
      dateCtrl.text = _dateInput(start.add(Duration(days: days)));
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return _ActionSheetFrame(
            title: 'Cambiar fecha',
            icon: Icons.event_available_outlined,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: daysCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setSheetState(syncDateFromDays),
                  decoration: _input('Días restantes'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: dateCtrl,
                  keyboardType: TextInputType.datetime,
                  decoration: _input('Vence el'),
                ),
                const SizedBox(height: AppSpacing.sm),
                _DurationAdjustments(
                  onAdjust: (delta) {
                    final current = int.tryParse(daysCtrl.text.trim()) ?? 0;
                    daysCtrl.text = (current + delta).toString();
                    setSheetState(syncDateFromDays);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            setSheetState(() => saving = true);
                            await _runCompanyListAction(
                              () => _service.updateCommercialOverrides(
                                company.companyId,
                                {
                                  'expirationDate': _nullableText(
                                    dateCtrl.text,
                                  ),
                                  'extraDays': _nullableIntInput(daysCtrl.text),
                                  'reason':
                                      'Fecha ajustada desde listado móvil',
                                },
                              ),
                              successMessage: 'Fecha actualizada.',
                            );
                            if (context.mounted) Navigator.of(context).pop();
                          },
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Guardar fecha'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      daysCtrl.dispose();
      dateCtrl.dispose();
    });
  }

  Future<void> _openLimitsActionSheet(DaleVentasCompanyLicense company) async {
    final usersCtrl = TextEditingController(text: company.maxUsers.toString());
    final productsCtrl = TextEditingController(
      text: company.maxProducts.toString(),
    );
    final warehousesCtrl = TextEditingController(
      text: company.commercial?.overrideMaxWarehouses?.toString() ?? '',
    );
    final devicesCtrl = TextEditingController(
      text: company.commercial?.overrideMaxDevices?.toString() ?? '',
    );
    var saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return _ActionSheetFrame(
            title: 'Editar límites',
            icon: Icons.tune_rounded,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NumberField(
                  controller: usersCtrl,
                  label: 'Usuarios permitidos',
                ),
                const SizedBox(height: AppSpacing.md),
                _NumberField(
                  controller: productsCtrl,
                  label: 'Productos permitidos',
                ),
                const SizedBox(height: AppSpacing.md),
                _NumberField(
                  controller: warehousesCtrl,
                  label: 'Almacenes permitidos',
                ),
                const SizedBox(height: AppSpacing.md),
                _NumberField(
                  controller: devicesCtrl,
                  label: 'Dispositivos permitidos',
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            setSheetState(() => saving = true);
                            await _runCompanyListAction(
                              () => _service.updateCommercialOverrides(
                                company.companyId,
                                {
                                  'maxUsers': _nullableIntInput(usersCtrl.text),
                                  'maxProducts': _nullableIntInput(
                                    productsCtrl.text,
                                  ),
                                  'maxWarehouses': _nullableIntInput(
                                    warehousesCtrl.text,
                                  ),
                                  'maxDevices': _nullableIntInput(
                                    devicesCtrl.text,
                                  ),
                                  'reason':
                                      'Límites ajustados desde listado móvil',
                                },
                              ),
                              successMessage: 'Límites actualizados.',
                            );
                            if (context.mounted) Navigator.of(context).pop();
                          },
                    icon: saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: const Text('Guardar límites'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      usersCtrl.dispose();
      productsCtrl.dispose();
      warehousesCtrl.dispose();
      devicesCtrl.dispose();
    });
  }

  Future<void> _openDangerActionSheet(DaleVentasCompanyLicense company) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => _ActionSheetFrame(
        title: 'Eliminar o bloquear',
        icon: Icons.warning_amber_rounded,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _runCompanyListAction(
                    () => _service.blockCompany(
                      company.companyId,
                      _licenseBody(company),
                    ),
                    successMessage: 'Licencia bloqueada.',
                  );
                },
                icon: const Icon(Icons.block_rounded),
                label: const Text('Bloquear licencia'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _runCompanyListAction(
                    () => _service.deleteCompanyLicense(company.companyId),
                    successMessage: 'Licencia eliminada.',
                  );
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Eliminar licencia'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.5),
                  ),
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(this.context);
                  Navigator.of(context).pop();
                  try {
                    await _service.permanentlyDeleteCompanyLicense(
                      company.companyId,
                    );
                    if (!mounted) return;
                    _removeCompany(company.companyId);
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Licencia eliminada completamente.'),
                      ),
                    );
                  } catch (error) {
                    if (!mounted) return;
                    final message = error is ApiException
                        ? error.message
                        : error.toString();
                    messenger.showSnackBar(SnackBar(content: Text(message)));
                  }
                },
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('Eliminar completamente'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(DaleVentasCompanyLicense company) async {
    final detail = await _service.getCompany(company.companyId);
    if (!mounted) return;
    if (_isDesktop) {
      setState(() {
        _selected = detail;
      });
    } else {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Detalle',
        barrierColor: AppColors.surface,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, animation, secondaryAnimation) => _MobileDetailSheet(
          company: detail,
          usage: _usageFor(detail),
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
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncShellActions();
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final showHeader = !mobile;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        mobile ? AppSpacing.md : AppSpacing.lg,
        mobile ? AppSpacing.xs : AppSpacing.lg,
        mobile ? AppSpacing.md : AppSpacing.lg,
        mobile ? AppSpacing.md : AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            _Header(
              searchCtrl: _searchCtrl,
              searchFocus: _searchFocus,
              status: _status,
              planFilter: _planFilter,
              showSearch: _showSearch || _isDesktop,
              showFilters: true,
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
          ],
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
                          usageFor: _usageFor,
                          onTap: _openDetail,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _LicenseControlPanel(
                          key: ValueKey(selected.companyId),
                          company: selected,
                          usage: _usageFor(selected),
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
                return _CompanyList(
                  companies: companies,
                  usageFor: _usageFor,
                  onTap: _openDetail,
                  onAction: _handleCompanyAction,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChoice {
  final String label;
  final String value;

  const _FilterChoice(this.label, this.value);
}

const _statusFilterChoices = [
  _FilterChoice('Demo activos', 'DEMO_ACTIVE'),
  _FilterChoice('Todos', 'TODOS'),
  _FilterChoice('Demo', 'DEMO'),
  _FilterChoice('Compraron', 'COMPRARON'),
  _FilterChoice('Activos', 'ACTIVE'),
  _FilterChoice('Por vencer', 'POR_VENCER'),
  _FilterChoice('Vencidos', 'EXPIRED'),
  _FilterChoice('Bloqueados', 'BLOCKED'),
  _FilterChoice('Seguimiento', 'SEGUIMIENTO'),
];

const _planFilterChoices = [
  _FilterChoice('Todos los planes', 'TODOS'),
  _FilterChoice('Básico', 'BASIC'),
  _FilterChoice('Negocio', 'BUSINESS'),
  _FilterChoice('Pro', 'PRO'),
  _FilterChoice('Legacy/Custom', 'LEGACY'),
];

class _Header extends StatelessWidget {
  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final String status;
  final String planFilter;
  final bool showSearch;
  final bool showFilters;
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
    required this.showFilters,
    required this.onStatusChanged,
    required this.onPlanChanged,
    required this.onSearch,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final chips = _statusFilterChoices
        .map(
          (choice) => _StatusChip(
            label: choice.label,
            value: choice.value,
            selected: status == choice.value,
            onTap: onStatusChanged,
          ),
        )
        .toList();
    final planChips = _planFilterChoices
        .map(
          (choice) => _StatusChip(
            label: choice.label,
            value: choice.value,
            selected: planFilter == choice.value,
            onTap: onPlanChanged,
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showFilters && compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HorizontalChipList(chips: chips),
              const SizedBox(height: AppSpacing.sm),
              _HorizontalChipList(chips: planChips),
            ],
          )
        else if (showFilters)
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
          if (showFilters) const SizedBox(height: AppSpacing.md),
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

class _FilterDrawerContent extends StatelessWidget {
  final String status;
  final String planFilter;
  final TextEditingController searchCtrl;
  final FocusNode searchFocus;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onPlanChanged;
  final VoidCallback onClose;
  final VoidCallback onReset;
  final VoidCallback onApply;
  final VoidCallback onRefresh;

  const _FilterDrawerContent({
    required this.status,
    required this.planFilter,
    required this.searchCtrl,
    required this.searchFocus,
    required this.onStatusChanged,
    required this.onPlanChanged,
    required this.onClose,
    required this.onReset,
    required this.onApply,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filtros',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Ordena la vista de empresas',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              TextField(
                controller: searchCtrl,
                focusNode: searchFocus,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onApply(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Buscar empresa o licencia',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _FilterSection(
                title: 'Estado comercial',
                icon: Icons.flag_outlined,
                children: _statusFilterChoices
                    .map(
                      (choice) => _FilterDrawerChip(
                        label: choice.label,
                        selected: status == choice.value,
                        onTap: () => onStatusChanged(choice.value),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: AppSpacing.lg),
              _FilterSection(
                title: 'Plan',
                icon: Icons.workspace_premium_outlined,
                children: _planFilterChoices
                    .map(
                      (choice) => _FilterDrawerChip(
                        label: choice.label,
                        selected: planFilter == choice.value,
                        onTap: () => onPlanChanged(choice.value),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              IconButton.outlined(
                tooltip: 'Recargar',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(onPressed: onReset, child: const Text('Limpiar')),
              const Spacer(),
              FilledButton.icon(
                onPressed: onApply,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Aplicar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _FilterSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: children,
          ),
        ],
      ),
    );
  }
}

class _FilterDrawerChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterDrawerChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryLight : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionSheetFrame extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _ActionSheetFrame({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: AppColors.primary, size: 21),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanPicker extends StatelessWidget {
  final String selectedPlan;
  final ValueChanged<String> onChanged;

  const _PlanPicker({required this.selectedPlan, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const plans = [
      _FilterChoice('Básico', 'BASIC'),
      _FilterChoice('Negocio', 'BUSINESS'),
      _FilterChoice('Pro', 'PRO'),
    ];
    return Column(
      children: plans
          .map(
            (plan) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Material(
                color: selectedPlan == plan.value
                    ? AppColors.primaryLight
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => onChanged(plan.value),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selectedPlan == plan.value
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedPlan == plan.value
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: selectedPlan == plan.value
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            plan.label,
                            style: TextStyle(
                              color: selectedPlan == plan.value
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

MarketingContact _daleVentasMarketingContact(DaleVentasCompanyLicense company) {
  final account = company.account;
  return MarketingContact(
    businessName: account.businessName ?? company.companyName,
    contactName: account.responsibleName,
    phone: account.responsibleWhatsapp ?? account.businessPhone,
    email: account.responsibleEmail,
    licenseStatus: company.planLabel,
    productName: 'DaleVentas POS',
    licenseLabel: company.status,
    expiresAt: company.endsAt,
  );
}

class _CompanyList extends StatelessWidget {
  final List<DaleVentasCompanyLicense> companies;
  final String? selectedId;
  final UsageAccount? Function(DaleVentasCompanyLicense company)? usageFor;
  final ValueChanged<DaleVentasCompanyLicense> onTap;
  final Future<void> Function(DaleVentasCompanyLicense company, String action)?
  onAction;

  const _CompanyList({
    required this.companies,
    required this.onTap,
    this.selectedId,
    this.usageFor,
    this.onAction,
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
          usage: usageFor?.call(company),
          selected: company.companyId == selectedId,
          onTap: () => onTap(company),
          onAction: onAction == null
              ? null
              : (action) => onAction!(company, action),
        );
      },
    );
  }
}

class _CompanyRail extends StatelessWidget {
  final List<DaleVentasCompanyLicense> companies;
  final String? selectedId;
  final UsageAccount? Function(DaleVentasCompanyLicense company) usageFor;
  final ValueChanged<DaleVentasCompanyLicense> onTap;

  const _CompanyRail({
    required this.companies,
    required this.usageFor,
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
                usageFor: usageFor,
                onTap: onTap,
                onAction: null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyCard extends StatefulWidget {
  final DaleVentasCompanyLicense company;
  final UsageAccount? usage;
  final bool selected;
  final VoidCallback onTap;
  final Future<void> Function(String action)? onAction;

  const _CompanyCard({
    required this.company,
    required this.usage,
    required this.selected,
    required this.onTap,
    this.onAction,
  });

  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends State<_CompanyCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final company = widget.company;
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final overLimit =
        company.usersUsed >= company.maxUsers ||
        company.productsUsed >= company.maxProducts;
    final daysColor = _remainingDaysColor(company);
    return Material(
      color: widget.selected ? AppColors.primaryLight : AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.all(mobile ? AppSpacing.sm : AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected
                  ? AppColors.primary
                  : overLimit
                  ? AppColors.warning.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: mobile
              ? _MobileCompanyCardContent(
                  company: company,
                  usage: widget.usage,
                  expanded: _expanded,
                  overLimit: overLimit,
                  daysColor: daysColor,
                  onToggleExpanded: () =>
                      setState(() => _expanded = !_expanded),
                  onAction: widget.onAction ?? (_) async => widget.onTap(),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 4,
                          height: mobile ? 50 : 52,
                          decoration: BoxDecoration(
                            color: overLimit
                                ? AppColors.warning
                                : AppColors.primary,
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
                              const SizedBox(height: AppSpacing.xs),
                              Wrap(
                                spacing: AppSpacing.xs,
                                runSpacing: AppSpacing.xs,
                                children: [
                                  if (_shouldShowListPlanBadge(company))
                                    _CommercialBadge(
                                      label: company.commercialPlanLabel,
                                      color: _commercialPlanColor(
                                        company.commercialPlanCode,
                                      ),
                                      icon: Icons.sell_outlined,
                                    ),
                                  _CommercialBadge(
                                    label: company.commercialStatusLabel,
                                    color: _commercialStatusColor(
                                      company.commercial?.commercialStatus ??
                                          'DEMO',
                                    ),
                                    icon: Icons.track_changes_rounded,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _DaysBadge(company: company, compact: mobile),
                            const SizedBox(height: AppSpacing.xs),
                            _StatusPill(
                              status: company.status,
                              compact: mobile,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        const SizedBox(width: 4 + AppSpacing.sm),
                        SizedBox(
                          width: mobile ? 30 : 34,
                          height: mobile ? 30 : 34,
                          child: MarketingWhatsAppButton(
                            contact: _daleVentasMarketingContact(company),
                            dense: true,
                          ),
                        ),
                        const Spacer(),
                        _CompanyActionButton(
                          compact: mobile,
                          onSelected:
                              widget.onAction ?? (_) async => widget.onTap(),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _CardIconButton(
                          compact: mobile,
                          icon: _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          tooltip: _expanded ? 'Contraer' : 'Expandir',
                          onTap: () => setState(() => _expanded = !_expanded),
                        ),
                      ],
                    ),
                    AnimatedCrossFade(
                      firstChild: const SizedBox(width: double.infinity),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _MiniUsageBar(
                                    icon: Icons.group_outlined,
                                    label: 'Usuarios',
                                    used: company.usersUsed,
                                    max: company.maxUsers,
                                    value: company.usersRatio,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: _MiniUsageBar(
                                    icon: Icons.inventory_2_outlined,
                                    label: 'Productos',
                                    used: company.productsUsed,
                                    max: company.maxProducts,
                                    value: company.productsRatio,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _CompanyUsagePreview(usage: widget.usage),
                          ],
                        ),
                      ),
                      crossFadeState: _expanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 180),
                      sizeCurve: Curves.easeOutCubic,
                    ),
                    Container(
                      height: 2,
                      margin: const EdgeInsets.only(top: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: daysColor.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MobileCompanyCardContent extends StatelessWidget {
  final DaleVentasCompanyLicense company;
  final UsageAccount? usage;
  final bool expanded;
  final bool overLimit;
  final Color daysColor;
  final VoidCallback onToggleExpanded;
  final Future<void> Function(String action) onAction;

  const _MobileCompanyCardContent({
    required this.company,
    required this.usage,
    required this.expanded,
    required this.overLimit,
    required this.daysColor,
    required this.onToggleExpanded,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 76,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (_shouldShowListPlanBadge(company))
                        _CommercialBadge(
                          label: company.commercialPlanLabel,
                          color: _commercialPlanColor(
                            company.commercialPlanCode,
                          ),
                          icon: Icons.sell_outlined,
                          compact: true,
                        ),
                      _CommercialBadge(
                        label: company.commercialStatusLabel,
                        color: _commercialStatusColor(
                          company.commercial?.commercialStatus ?? 'DEMO',
                        ),
                        icon: Icons.track_changes_rounded,
                        compact: true,
                      ),
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: MarketingWhatsAppButton(
                          contact: _daleVentasMarketingContact(company),
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _DaysBadge(company: company, compact: true),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatusPill(status: company.status, compact: true),
                    const SizedBox(width: AppSpacing.xs),
                    _CompanyActionButton(compact: true, onSelected: onAction),
                    const SizedBox(width: AppSpacing.xs),
                    _CardIconButton(
                      compact: true,
                      icon: expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      tooltip: expanded ? 'Contraer' : 'Expandir',
                      onTap: onToggleExpanded,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MiniUsageBar(
                        icon: Icons.group_outlined,
                        label: 'Usuarios',
                        used: company.usersUsed,
                        max: company.maxUsers,
                        value: company.usersRatio,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _MiniUsageBar(
                        icon: Icons.inventory_2_outlined,
                        label: 'Productos',
                        used: company.productsUsed,
                        max: company.maxProducts,
                        value: company.productsRatio,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _CompanyUsagePreview(usage: usage),
              ],
            ),
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
          sizeCurve: Curves.easeOutCubic,
        ),
        Container(
          height: 2,
          margin: const EdgeInsets.only(top: AppSpacing.xs),
          decoration: BoxDecoration(
            color: daysColor.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ],
    );
  }
}

class _CardIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool compact;

  const _CardIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: compact ? 30 : 34,
            height: compact ? 30 : 34,
            child: Icon(
              icon,
              color: AppColors.textSecondary,
              size: compact ? 20 : 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyActionButton extends StatelessWidget {
  final Future<void> Function(String action) onSelected;
  final bool compact;

  const _CompanyActionButton({required this.onSelected, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Acciones',
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'detail',
          child: _CompanyActionMenuItem(
            icon: Icons.open_in_new_rounded,
            label: 'Ver detalle',
          ),
        ),
        PopupMenuItem(
          value: 'plan',
          child: _CompanyActionMenuItem(
            icon: Icons.workspace_premium_outlined,
            label: 'Cambiar plan',
          ),
        ),
        PopupMenuItem(
          value: 'date',
          child: _CompanyActionMenuItem(
            icon: Icons.event_available_outlined,
            label: 'Cambiar fecha',
          ),
        ),
        PopupMenuItem(
          value: 'limits',
          child: _CompanyActionMenuItem(
            icon: Icons.tune_rounded,
            label: 'Editar límites',
          ),
        ),
        PopupMenuItem(
          value: 'activate',
          child: _CompanyActionMenuItem(
            icon: Icons.verified_rounded,
            label: 'Activar',
          ),
        ),
        PopupMenuItem(
          value: 'danger',
          child: _CompanyActionMenuItem(
            icon: Icons.delete_outline_rounded,
            label: 'Eliminar o bloquear',
            destructive: true,
          ),
        ),
      ],
      child: Container(
        width: compact ? 34 : 38,
        height: compact ? 30 : 34,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          color: AppColors.textSecondary,
          size: 22,
        ),
      ),
    );
  }
}

class _CompanyActionMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;

  const _CompanyActionMenuItem({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.error : AppColors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _LicenseControlPanel extends StatefulWidget {
  final DaleVentasCompanyLicense company;
  final UsageAccount? usage;
  final DaleVentasLicenseService service;
  final ValueChanged<DaleVentasCompanyLicense> onChanged;
  final ValueChanged<String> onDeleted;

  const _LicenseControlPanel({
    super.key,
    required this.company,
    required this.usage,
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
  late final TextEditingController _maxWarehousesCtrl;
  late final TextEditingController _maxDevicesCtrl;
  late String _planCode;
  late String _commercialPlanCode;
  late String _commercialStatus;
  bool _busy = false;
  bool _syncingExpirationFields = false;
  late Future<Map<String, dynamic>> _activityFuture;

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
      text: _daysUntilInput(widget.company.endsAt),
    );
    _expiresCtrl = TextEditingController(
      text: _dateInput(widget.company.endsAt),
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
    _maxWarehousesCtrl = TextEditingController();
    _maxDevicesCtrl = TextEditingController();
    _planCode = widget.company.planCode;
    _syncCommercialFields();
    _activityFuture = widget.service.getActivity(widget.company.companyId);
    _durationDaysCtrl.addListener(_syncExpiresFromDays);
    _expiresCtrl.addListener(_syncDaysFromExpires);
  }

  @override
  void didUpdateWidget(covariant _LicenseControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company.companyId == widget.company.companyId) return;
    _maxUsersCtrl.text = widget.company.maxUsers.toString();
    _maxProductsCtrl.text = widget.company.maxProducts.toString();
    _setExpirationFields(widget.company.endsAt);
    _syncAccountFields();
    _notesCtrl.text = widget.company.notes ?? '';
    _planCode = widget.company.planCode;
    _syncCommercialFields();
    _activityFuture = widget.service.getActivity(widget.company.companyId);
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
    _maxWarehousesCtrl.dispose();
    _maxDevicesCtrl.dispose();
    super.dispose();
  }

  void _syncCommercialFields() {
    final commercial = widget.company.commercial;
    _commercialPlanCode = widget.company.commercialPlanCode;
    if (_commercialPlanCode != 'BASIC' &&
        _commercialPlanCode != 'BUSINESS' &&
        _commercialPlanCode != 'PRO') {
      _commercialPlanCode = 'LEGACY';
    }
    _commercialStatus = commercial?.commercialStatus ?? 'DEMO';
    _maxWarehousesCtrl.text =
        commercial?.overrideMaxWarehouses?.toString() ?? '';
    _maxDevicesCtrl.text = commercial?.overrideMaxDevices?.toString() ?? '';
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

  Future<void> _saveCommercialPlanAndLimits() async {
    if (_commercialPlanCode == 'LEGACY') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona Básico, Negocio o Pro.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.assignCommercialPlan(
        widget.company.companyId,
        planCode: _commercialPlanCode,
        commercialStatus: _commercialStatus,
      );
      final updated = await widget.service
          .updateCommercialOverrides(widget.company.companyId, {
            'expirationDate': _nullableText(_expiresCtrl.text),
            'extraDays': _nullableIntInput(_durationDaysCtrl.text),
            'maxUsers': _nullableIntInput(_maxUsersCtrl.text),
            'maxProducts': _nullableIntInput(_maxProductsCtrl.text),
            'maxWarehouses': _nullableIntInput(_maxWarehousesCtrl.text),
            'maxDevices': _nullableIntInput(_maxDevicesCtrl.text),
            'notes': _nullableText(_notesCtrl.text),
            'reason': 'Plan y limites unificados desde Appyra Flutter',
          });
      if (!mounted) return;
      widget.onChanged(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan y límites guardados en Appyra.')),
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

  Widget _buildPlanLicenseSection(DaleVentasCompanyLicense company) {
    return _SectionPanel(
      title: 'Plan y licencia',
      icon: Icons.tune_rounded,
      child: _buildPlanLicenseContent(company),
    );
  }

  Widget _buildPlanLicenseContent(DaleVentasCompanyLicense company) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CommercialSummary(company: company),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 620;
            final selectorWidth = wide
                ? (constraints.maxWidth - AppSpacing.md) / 2
                : constraints.maxWidth;
            final selectors = [
              DropdownButtonFormField<String>(
                initialValue: _commercialPlanCode,
                decoration: _input('Plan'),
                items: const [
                  DropdownMenuItem(
                    value: 'LEGACY',
                    child: Text('Legacy/Custom'),
                  ),
                  DropdownMenuItem(value: 'BASIC', child: Text('Básico')),
                  DropdownMenuItem(value: 'BUSINESS', child: Text('Negocio')),
                  DropdownMenuItem(value: 'PRO', child: Text('Pro')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _commercialPlanCode = value;
                    _planCode = value == 'LEGACY'
                        ? widget.company.planCode
                        : value == 'BASIC'
                        ? 'STANDARD'
                        : 'ENTERPRISE';
                  });
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _commercialStatus,
                decoration: _input('Estado comercial'),
                items: const [
                  DropdownMenuItem(value: 'DEMO', child: Text('Demo')),
                  DropdownMenuItem(
                    value: 'CONTACTED',
                    child: Text('Contactado'),
                  ),
                  DropdownMenuItem(
                    value: 'INTERESTED',
                    child: Text('Interesado'),
                  ),
                  DropdownMenuItem(value: 'PURCHASED', child: Text('Compró')),
                  DropdownMenuItem(
                    value: 'ACTIVE_CUSTOMER',
                    child: Text('Cliente activo'),
                  ),
                  DropdownMenuItem(
                    value: 'RENEWAL_DUE',
                    child: Text('Por renovar'),
                  ),
                  DropdownMenuItem(value: 'EXPIRED', child: Text('Vencido')),
                  DropdownMenuItem(value: 'LOST', child: Text('Perdido')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _commercialStatus = value);
                },
              ),
            ];
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
                controller: _maxWarehousesCtrl,
                label: 'Almacenes permitidos',
              ),
              _NumberField(
                controller: _maxDevicesCtrl,
                label: 'Dispositivos permitidos',
              ),
              _NumberField(
                controller: _durationDaysCtrl,
                label: 'Días restantes',
              ),
              _ExpirationDateField(controller: _expiresCtrl),
            ];
            if (!wide) {
              return Column(
                children:
                    [
                          ...selectors,
                          const SizedBox(height: AppSpacing.md),
                          ...fields,
                        ]
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
            return Column(
              children: [
                Row(
                  children: [
                    for (var index = 0; index < selectors.length; index++)
                      SizedBox(
                        width: selectorWidth,
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: index == selectors.length - 1
                                ? 0
                                : AppSpacing.md,
                          ),
                          child: selectors[index],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: fields
                      .map(
                        (field) => SizedBox(
                          width: (constraints.maxWidth - AppSpacing.md * 2) / 3,
                          child: field,
                        ),
                      )
                      .toList(),
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
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _busy ? null : _saveCommercialPlanAndLimits,
            icon: const Icon(Icons.assignment_turned_in_outlined),
            label: const Text('Guardar plan y límites'),
          ),
        ),
      ],
    );
  }

  List<Widget> _actionButtons({required bool fullWidth}) {
    final company = widget.company;
    Widget action(Widget child) =>
        fullWidth ? SizedBox(width: double.infinity, child: child) : child;
    return [
      action(
        FilledButton.icon(
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: const Text('Aplicar a DaleVentas'),
          onPressed: () => _run(
            () => widget.service.updateCompany(company.companyId, _body()),
          ),
        ),
      ),
      action(
        OutlinedButton.icon(
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Reconciliar uso'),
          onPressed: _busy
              ? null
              : () => _run(
                    () => widget.service.refreshUsage(company.companyId),
                  ),
        ),
      ),
      action(
        OutlinedButton.icon(
          icon: const Icon(Icons.verified_rounded),
          label: const Text('Activar'),
          onPressed: () => _run(
            () => widget.service.activateCompany(company.companyId, _body()),
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
                () => widget.service.blockCompany(company.companyId, _body()),
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
                () => widget.service.deleteCompanyLicense(company.companyId),
              );
            }
          },
        ),
      ),
      action(
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: BorderSide(color: AppColors.error.withValues(alpha: 0.55)),
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
    ];
  }

  Future<void> _openMobileActions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Acciones',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._actionButtons(fullWidth: true).map(
                (button) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: button,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final company = widget.company;
    final mobile = MediaQuery.sizeOf(context).width < 600;
    Widget section({
      required String title,
      required IconData icon,
      required Widget child,
    }) {
      if (!mobile) {
        return _SectionPanel(title: title, icon: icon, child: child);
      }
      return _CollapsibleSectionPanel(title: title, icon: icon, child: child);
    }

    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
          mobile ? 18 : AppSpacing.cardRadius,
        ),
        border: mobile ? null : Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                mobile ? AppSpacing.md : AppSpacing.lg,
                mobile ? AppSpacing.sm : AppSpacing.lg,
                mobile ? AppSpacing.md : AppSpacing.lg,
                mobile ? 96 : AppSpacing.xl,
              ),
              children: [
                if (!mobile) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
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
                              label: 'Días restantes',
                              value: _remainingDaysValue(company),
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
                              value:
                                  '${company.productsUsed}/${company.maxProducts}',
                            ),
                          ),
                          SizedBox(
                            width: tileWidth,
                            child: _MetricTile(
                              icon: Icons.lock_open_rounded,
                              label: 'Acceso',
                              value: company.isUsable
                                  ? 'Permitido'
                                  : 'Bloqueado',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                mobile
                    ? _CollapsibleSectionPanel(
                        title: 'Plan y licencia',
                        icon: Icons.tune_rounded,
                        child: _buildPlanLicenseContent(company),
                      )
                    : _buildPlanLicenseSection(company),
                const SizedBox(height: AppSpacing.md),
                section(
                  title: 'Uso y actividad',
                  icon: Icons.query_stats_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DaleVentasUsageSummary(usage: widget.usage),
                      const SizedBox(height: AppSpacing.md),
                      FutureBuilder<Map<String, dynamic>>(
                        future: _activityFuture,
                        builder: (context, snapshot) {
                          return _DaleVentasActivitySummary(
                            activity: snapshot.data,
                            loading:
                                snapshot.connectionState ==
                                ConnectionState.waiting,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                section(
                  title: 'Cuenta y contacto',
                  icon: Icons.badge_outlined,
                  child: _AccountSummary(company: company),
                ),
                const SizedBox(height: AppSpacing.md),
                section(
                  title: 'Marketing y seguimiento',
                  icon: Icons.campaign_outlined,
                  child: MarketingContactPanel(
                    contact: _daleVentasMarketingContact(company),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                section(
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
                if (!mobile) ...[
                  const SizedBox(height: AppSpacing.md),
                  _SectionPanel(
                    title: 'Acciones',
                    icon: Icons.admin_panel_settings_rounded,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: _actionButtons(
                            fullWidth: constraints.maxWidth < 520,
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if ((company.blockReason ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    company.blockReason!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ],
                if (company.auditLogs.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  section(
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
          if (mobile)
            Positioned(
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: FloatingActionButton.extended(
                onPressed: _busy ? null : _openMobileActions,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('Acciones'),
              ),
            ),
        ],
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
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
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

class _CollapsibleSectionPanel extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _CollapsibleSectionPanel({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  State<_CollapsibleSectionPanel> createState() =>
      _CollapsibleSectionPanelState();
}

class _CollapsibleSectionPanelState extends State<_CollapsibleSectionPanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _expanded
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.border,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        widget.icon,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: widget.child,
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
          ),
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

class _DaysBadge extends StatelessWidget {
  final DaleVentasCompanyLicense company;
  final bool compact;

  const _DaysBadge({required this.company, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = _remainingDaysColor(company);
    return Container(
      constraints: BoxConstraints(minWidth: compact ? 66 : 74),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : AppSpacing.sm,
        vertical: compact ? 4 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _remainingDaysValue(company),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            _remainingDaysCaption(company),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color.withValues(alpha: 0.82),
              fontSize: compact ? 8 : 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniUsageBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final int used;
  final int max;
  final double value;

  const _MiniUsageBar({
    required this.icon,
    required this.label,
    required this.used,
    required this.max,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final danger = max > 0 && used >= max;
    final color = danger ? AppColors.warning : AppColors.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$used/$max',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: value,
            color: color,
            backgroundColor: AppColors.surfaceVariant,
          ),
        ),
      ],
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

class _CommercialSummary extends StatelessWidget {
  final DaleVentasCompanyLicense company;

  const _CommercialSummary({required this.company});

  @override
  Widget build(BuildContext context) {
    final commercial = company.commercial;
    final effective = company.effectiveEntitlements;
    final items = [
      _InfoItem(
        icon: Icons.sell_outlined,
        label: 'Plan comercial',
        value: company.commercialPlanLabel,
      ),
      _InfoItem(
        icon: Icons.track_changes_rounded,
        label: 'Funnel',
        value: company.commercialStatusLabel,
      ),
      _InfoItem(
        icon: Icons.payments_outlined,
        label: 'Pago mínimo',
        value: _commercialPaymentLabel(commercial),
      ),
      _InfoItem(
        icon: Icons.event_repeat_outlined,
        label: 'Próximo seguimiento',
        value: _fmtDateOnly(commercial?.nextFollowUpAt),
      ),
      _InfoItem(
        icon: Icons.group_outlined,
        label: 'Usuarios efectivos',
        value: _entitlementLabel(
          effective?.maxUsers,
          effective?.sources['maxUsers'],
          fallback: company.maxUsers,
        ),
      ),
      _InfoItem(
        icon: Icons.inventory_2_outlined,
        label: 'Productos efectivos',
        value: _entitlementLabel(
          effective?.maxProducts,
          effective?.sources['maxProducts'],
          fallback: company.maxProducts,
        ),
      ),
      _InfoItem(
        icon: Icons.warehouse_outlined,
        label: 'Almacenes',
        value: _unsupportedEntitlementLabel(effective?.maxWarehouses),
      ),
      _InfoItem(
        icon: Icons.devices_other_outlined,
        label: 'Dispositivos',
        value: _unsupportedEntitlementLabel(effective?.maxDevices),
      ),
      _InfoItem(
        icon: Icons.event_available_outlined,
        label: 'Vence efectivo',
        value: effective?.expirationDate == null
            ? _fmtDateOnly(company.endsAt)
            : '${_fmtDateOnly(effective!.expirationDate)} · ${_sourceLabel(effective.sources['expirationDate'])}',
      ),
      _InfoItem(
        icon: company.hasCommercialOverride
            ? Icons.tune_rounded
            : Icons.lock_outline_rounded,
        label: 'Overrides',
        value: company.hasCommercialOverride
            ? 'Tiene ajustes manuales'
            : 'Sin ajustes manuales',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _CommercialBadge(
              label: company.commercialPlanLabel,
              color: _commercialPlanColor(company.commercialPlanCode),
              icon: Icons.sell_outlined,
            ),
            _CommercialBadge(
              label: company.commercialStatusLabel,
              color: _commercialStatusColor(
                commercial?.commercialStatus ?? 'DEMO',
              ),
              icon: Icons.track_changes_rounded,
            ),
            if (company.hasCommercialOverride)
              const _CommercialBadge(
                label: 'Override manual',
                color: AppColors.warning,
                icon: Icons.tune_rounded,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final width =
                (constraints.maxWidth - AppSpacing.sm * (columns - 1)) /
                columns;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: items
                  .map((item) => SizedBox(width: width, child: item))
                  .toList(),
            );
          },
        ),
        if ((commercial?.commercialNotes ?? '').isNotEmpty ||
            (commercial?.overrideNotes ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            commercial?.overrideNotes ?? commercial?.commercialNotes ?? '',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
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

class _DaleVentasUsageSummary extends StatelessWidget {
  final UsageAccount? usage;

  const _DaleVentasUsageSummary({required this.usage});

  @override
  Widget build(BuildContext context) {
    final account = usage;
    final businessItems = [
      _InfoItem(
        icon: Icons.point_of_sale_rounded,
        label: 'Ventas hoy',
        value: '${account?.metricInt('sales_today') ?? 0}',
      ),
      _InfoItem(
        icon: Icons.receipt_long_rounded,
        label: 'Cotizaciones hoy',
        value: '${account?.metricInt('quotes_today') ?? 0}',
      ),
      _InfoItem(
        icon: Icons.calendar_month_rounded,
        label: 'Ventas del mes',
        value: '${account?.metricInt('sales_this_month') ?? 0}',
      ),
      _InfoItem(
        icon: Icons.payments_outlined,
        label: 'Monto mes',
        value: _fmtMetricMoney(account?.metrics['sales_amount_this_month']),
      ),
      _InfoItem(
        icon: Icons.inventory_2_outlined,
        label: 'Inventario',
        value: '${account?.metricInt('products_total') ?? 0}',
      ),
      _InfoItem(
        icon: Icons.extension_outlined,
        label: 'Modulos hoy',
        value: _fmtMetricList(account?.metricString('modules_used_today')),
      ),
    ];
    final items = [
      _InfoItem(
        icon: Icons.online_prediction_rounded,
        label: 'Estado',
        value: _daleUsageStatusLabel(account),
      ),
      _InfoItem(
        icon: Icons.schedule_rounded,
        label: 'Ultimo uso',
        value: _fmtUsageDate(account?.lastSeenAt),
      ),
      _InfoItem(
        icon: Icons.timer_outlined,
        label: 'Tiempo estimado',
        value: _fmtUsageDuration(account?.activeSeconds ?? 0),
      ),
      _InfoItem(
        icon: Icons.devices_other_outlined,
        label: 'Dispositivos',
        value: '${account?.devicesCount ?? 0}',
      ),
      _InfoItem(
        icon: Icons.computer_rounded,
        label: 'Plataforma principal',
        value: _fmtPrimaryPlatform(account),
      ),
      _InfoItem(
        icon: Icons.devices_rounded,
        label: 'Uso por plataforma',
        value: _fmtPlatformBreakdown(account),
      ),
      _InfoItem(
        icon: Icons.login_rounded,
        label: 'Sesiones',
        value: '${account?.sessionsCount ?? 0}',
      ),
      _InfoItem(
        icon: Icons.new_releases_outlined,
        label: 'Version',
        value: account?.appVersion ?? 'Sin version',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UsageAlert(usage: account),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final width =
                (constraints.maxWidth - AppSpacing.sm * (columns - 1)) /
                columns;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: businessItems
                  .map((item) => SizedBox(width: width, child: item))
                  .toList(),
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final width =
                (constraints.maxWidth - AppSpacing.sm * (columns - 1)) /
                columns;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: items
                  .map((item) => SizedBox(width: width, child: item))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _DaleVentasActivitySummary extends StatelessWidget {
  final Map<String, dynamic>? activity;
  final bool loading;

  const _DaleVentasActivitySummary({
    required this.activity,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && activity == null) {
      return const LinearProgressIndicator(minHeight: 3);
    }
    final data = activity ?? const <String, dynamic>{};
    final modules = (data['modules'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .take(8)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 680;
            final width = wide
                ? (constraints.maxWidth - AppSpacing.sm * 2) / 3
                : constraints.maxWidth;
            final items = [
              _InfoItem(
                icon: Icons.bolt_outlined,
                label: 'Ultima actividad',
                value: _fmtDateTime(_dateFromAny(data['last_active_at'])),
              ),
              _InfoItem(
                icon: Icons.point_of_sale_outlined,
                label: 'Ultima venta',
                value: _fmtDateTime(_dateFromAny(data['last_sale_at'])),
              ),
              _InfoItem(
                icon: Icons.request_quote_outlined,
                label: 'Ultima cotizacion',
                value: _fmtDateTime(_dateFromAny(data['last_quotation_at'])),
              ),
              _InfoItem(
                icon: Icons.inventory_outlined,
                label: 'Inventario',
                value: _fmtDateTime(
                  _dateFromAny(data['last_inventory_activity_at']),
                ),
              ),
              _InfoItem(
                icon: Icons.payments_outlined,
                label: 'Caja',
                value: _fmtDateTime(_dateFromAny(data['last_cash_activity_at'])),
              ),
              _InfoItem(
                icon: Icons.people_alt_outlined,
                label: 'Clientes',
                value: _fmtDateTime(
                  _dateFromAny(data['last_customer_activity_at']),
                ),
              ),
              _InfoItem(
                icon: Icons.warehouse_outlined,
                label: 'Almacenes',
                value: _fmtDateTime(
                  _dateFromAny(data['last_warehouse_activity_at']),
                ),
              ),
            ];
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: items
                  .map((item) => SizedBox(width: width, child: item))
                  .toList(),
            );
          },
        ),
        if (modules.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: modules.map((module) {
              return _CommercialBadge(
                label:
                    '${module['feature_code'] ?? 'MODULO'} · ${_fmtDateOnly(_dateFromAny(module['last_used_at']))}',
                color: AppColors.primary,
                icon: Icons.apps_rounded,
                compact: true,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _UsageAlert extends StatelessWidget {
  final UsageAccount? usage;

  const _UsageAlert({required this.usage});

  @override
  Widget build(BuildContext context) {
    final account = usage;
    final status = account?.usageStatus ?? 'NEVER_USED';
    final color = _usageStatusColor(status);
    final title = account == null
        ? 'Sin actividad enviada'
        : _daleUsageStatusLabel(account);
    final detail = account == null
        ? 'DaleVentas POS aun no ha reportado heartbeat para esta empresa.'
        : 'Reporte agregado ${account.eventsCount} · App ${account.appCode}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(_usageStatusIcon(status), color: color, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

class _CompanyUsagePreview extends StatelessWidget {
  final UsageAccount? usage;

  const _CompanyUsagePreview({required this.usage});

  @override
  Widget build(BuildContext context) {
    final account = usage;
    final status = account?.usageStatus ?? 'NEVER_USED';
    final color = _usageStatusColor(status);
    final label = _daleUsageStatusLabel(account);
    final when = account == null
        ? 'Sin reporte'
        : _fmtUsageDate(account.lastSeenAt);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(_usageStatusIcon(status), color: color, size: 15),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '$label · $when',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileDetailSheet extends StatelessWidget {
  final DaleVentasCompanyLicense company;
  final UsageAccount? usage;
  final DaleVentasLicenseService service;
  final ValueChanged<DaleVentasCompanyLicense> onChanged;
  final ValueChanged<String> onDeleted;

  const _MobileDetailSheet({
    required this.company,
    required this.usage,
    required this.service,
    required this.onChanged,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _LicenseControlPanel(
                  company: company,
                  usage: usage,
                  service: service,
                  onChanged: onChanged,
                  onDeleted: onDeleted,
                ),
              ),
              Positioned(
                top: AppSpacing.sm,
                left: AppSpacing.md,
                child: Material(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(16),
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.primary,
                        size: 25,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
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
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
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
  final bool compact;

  const _StatusPill({required this.status, this.compact = false});

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
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : AppSpacing.sm,
        vertical: compact ? 3 : AppSpacing.xs,
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
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }
}

class _CommercialBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool compact;

  const _CommercialBadge({
    required this.label,
    required this.color,
    required this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : AppSpacing.sm,
        vertical: compact ? 3 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.badgeRadius),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: color),
          SizedBox(width: compact ? 4 : AppSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 10 : 11,
            ),
          ),
        ],
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

DateTime? _dateFromAny(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

int? _remainingDays(DaleVentasCompanyLicense company) {
  if (company.daysRemaining != 0) return company.daysRemaining;
  final endsAt = company.endsAt;
  if (endsAt == null) return null;
  final local = endsAt.toLocal();
  final endDay = DateTime(local.year, local.month, local.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return endDay.difference(today).inDays;
}

String _remainingDaysValue(DaleVentasCompanyLicense company) {
  final days = _remainingDays(company);
  if (days == null) return '--';
  if (days < 0) return 'Vencida';
  if (days == 0) return 'Hoy';
  return '$days días';
}

String _remainingDaysCaption(DaleVentasCompanyLicense company) {
  final days = _remainingDays(company);
  if (days == null) return 'sin fecha';
  if (days < 0) return 'expirada';
  if (days == 0) return 'vence hoy';
  return 'restantes';
}

Color _remainingDaysColor(DaleVentasCompanyLicense company) {
  final days = _remainingDays(company);
  if (company.isBlocked) return AppColors.error;
  if (days == null) return AppColors.textSecondary;
  if (days < 0) return AppColors.error;
  if (days <= 7) return AppColors.error;
  if (days <= 30) return AppColors.warning;
  return AppColors.success;
}

bool _shouldShowListPlanBadge(DaleVentasCompanyLicense company) {
  final code = company.commercialPlanCode.trim().toUpperCase();
  return code == 'BASIC' || code == 'BUSINESS' || code == 'PRO';
}

String _commercialPaymentLabel(DaleVentasCommercialProfile? commercial) {
  if (commercial == null) return 'Pendiente de plan';
  final minimum = commercial.minimumPaymentSnapshot;
  final monthly = commercial.monthlyEquivalentPriceSnapshot;
  final months = commercial.minimumBillingMonthsSnapshot;
  if (minimum == null && monthly == null) return 'Legacy/Custom';
  final parts = <String>[];
  if (minimum != null) parts.add('RD\$${_moneyText(minimum)} mínimo');
  if (monthly != null) parts.add('RD\$${_moneyText(monthly)} mensual');
  if (months != null) parts.add('$months meses');
  return parts.join(' · ');
}

String _entitlementLabel(int? value, String? source, {int? fallback}) {
  final resolved = value ?? fallback;
  if (resolved == null) return 'Configurable';
  return '$resolved · ${_sourceLabel(source ?? (value == null ? 'technical' : null))}';
}

String _unsupportedEntitlementLabel(int? value) {
  final prefix = value == null ? 'No aplicado' : '$value comercial';
  return '$prefix - no se aplica en DaleVentas';
}

String _sourceLabel(String? source) {
  switch ((source ?? '').trim()) {
    case 'override':
      return 'override';
    case 'plan_snapshot':
      return 'snapshot';
    case 'technical':
    case 'technical_trial':
      return 'DaleVentas';
    default:
      return 'configurable';
  }
}

String _moneyText(String value) {
  final number = num.tryParse(value);
  if (number == null) return value;
  return NumberFormat('#,##0.##').format(number);
}

String? _nullableText(String value) {
  final text = value.trim();
  return text.isEmpty ? null : text;
}

int? _nullableIntInput(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  return int.tryParse(text);
}

Color _commercialPlanColor(String code) {
  switch (code) {
    case 'BASIC':
      return AppColors.info;
    case 'BUSINESS':
      return AppColors.primary;
    case 'PRO':
      return AppColors.success;
    case 'CUSTOM':
      return AppColors.warning;
    default:
      return AppColors.textSecondary;
  }
}

Color _commercialStatusColor(String status) {
  switch (status) {
    case 'PURCHASED':
    case 'ACTIVE_CUSTOMER':
      return AppColors.success;
    case 'INTERESTED':
    case 'RENEWAL_DUE':
      return AppColors.warning;
    case 'LOST':
    case 'EXPIRED':
      return AppColors.error;
    case 'CONTACTED':
      return AppColors.primary;
    default:
      return AppColors.info;
  }
}

String? _usageKey(String? value) {
  final text = value?.trim().toLowerCase() ?? '';
  return text.isEmpty ? null : text;
}

String _fmtUsageDate(DateTime? date) {
  if (date == null) return 'Sin uso';
  return DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
}

String _fmtUsageDuration(int seconds) {
  if (seconds <= 0) return '0 h';
  if (seconds < 3600) return '${(seconds / 60).round()} min';
  final hours = seconds / 3600;
  return '${hours.toStringAsFixed(hours >= 10 ? 0 : 1)} h';
}

String _fmtMetricMoney(dynamic value) {
  final number = value is num ? value : num.tryParse(value?.toString() ?? '');
  if (number == null || number <= 0) return r'$0.00';
  return NumberFormat.currency(symbol: r'$', decimalDigits: 2).format(number);
}

String _fmtMetricList(String? value) {
  final parts = (value ?? '')
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'Sin modulo hoy';
  return parts.take(3).join(', ');
}

String _fmtPrimaryPlatform(UsageAccount? account) {
  final platform = account?.platformBreakdown.isNotEmpty == true
      ? account!.platformBreakdown.first
      : null;
  if (platform == null) return 'Sin datos';
  final label = _platformLabel(platform.platform);
  final events = platform.eventsCount;
  return events > 0 ? '$label · $events eventos' : label;
}

String _fmtPlatformBreakdown(UsageAccount? account) {
  final items = account?.platformBreakdown ?? const [];
  if (items.isEmpty) return 'Sin datos';
  return items
      .take(3)
      .map((item) {
        final label = _platformLabel(item.platform);
        final devices = item.devicesCount;
        return devices > 0 ? '$label $devices' : label;
      })
      .join(', ');
}

String _platformLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'windows':
      return 'Windows';
    case 'android':
      return 'Android';
    case 'ios':
      return 'iPhone/iPad';
    case 'web':
      return 'Web';
    case 'macos':
      return 'macOS';
    case 'linux':
      return 'Linux';
    case 'unknown_native':
      return 'App nativa';
    case 'api':
      return 'Servidor';
    default:
      return 'Desconocido';
  }
}

String _daleUsageStatusLabel(UsageAccount? account) {
  if (account == null) return 'Sin uso';
  if (account.appVersion?.contains('telemetry') == true ||
      account.metrics.isNotEmpty) {
    switch (account.usageStatus) {
      case 'USING_NOW':
      case 'ACTIVE_TODAY':
        return 'Reporte reciente';
      case 'ACTIVE_WEEK':
      case 'ACTIVE_RECENT':
        return 'Reporte recibido';
      default:
        return account.statusLabel;
    }
  }
  return account.statusLabel;
}

Color _usageStatusColor(String status) {
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

IconData _usageStatusIcon(String status) {
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
      return Icons.query_stats_rounded;
  }
}
