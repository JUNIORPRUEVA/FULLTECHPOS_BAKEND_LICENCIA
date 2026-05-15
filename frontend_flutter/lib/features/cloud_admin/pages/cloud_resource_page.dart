import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/status_badge.dart';

class ResourceField {
  final String key;
  final String label;
  final bool badge;

  const ResourceField(this.key, this.label, {this.badge = false});
}

class ResourceFilterOption {
  final String label;
  final String? value;

  const ResourceFilterOption(this.label, this.value);
}

class CloudResourceConfig {
  final String title;
  final IconData icon;
  final String endpoint;
  final String listKey;
  final List<ResourceField> fields;
  final List<ResourceField> detailFields;
  final List<String> searchKeys;
  final String? filterParam;
  final List<ResourceFilterOption> filterOptions;

  const CloudResourceConfig({
    required this.title,
    required this.icon,
    required this.endpoint,
    required this.listKey,
    required this.fields,
    required this.detailFields,
    required this.searchKeys,
    this.filterParam,
    this.filterOptions = const [],
  });
}

class CloudAdminService {
  final ApiClient _client;

  CloudAdminService({required SessionManager sessionManager})
    : _client = ApiClient(sessionManager: sessionManager);

  Future<List<Map<String, dynamic>>> list(
    CloudResourceConfig config, {
    String? filterValue,
  }) async {
    final query = <String, String>{'limit': '100', 'offset': '0'};
    if (config.filterParam != null && filterValue != null) {
      query[config.filterParam!] = filterValue;
    }

    final path = Uri(path: config.endpoint, queryParameters: query).toString();
    final data = await _client.get(path);
    final list =
        data[config.listKey] as List<dynamic>? ??
        data['data'] as List<dynamic>? ??
        [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>?> getSettings() async {
    final data = await _client.get('/api/admin/store-settings');
    final settings = data['settings'];
    if (settings is Map<String, dynamic>) return settings;
    return null;
  }

  Future<Map<String, dynamic>?> updateSettings(
    Map<String, dynamic> body,
  ) async {
    final data = await _client.put('/api/admin/store-settings', body);
    final settings = data['settings'];
    if (settings is Map<String, dynamic>) return settings;
    return null;
  }
}

class CloudResourcePage extends StatefulWidget {
  final CloudResourceConfig config;

  const CloudResourcePage({super.key, required this.config});

  @override
  State<CloudResourcePage> createState() => _CloudResourcePageState();
}

class _CloudResourcePageState extends State<CloudResourcePage> {
  late final CloudAdminService _service;
  late Future<List<Map<String, dynamic>>> _future;
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _filterValue;
  Map<String, dynamic>? _selected;

  bool get _isDesktop => MediaQuery.of(context).size.width >= 1000;

  @override
  void initState() {
    super.initState();
    _service = CloudAdminService(
      sessionManager: context.read<SessionManager>(),
    );
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return _service.list(widget.config, filterValue: _filterValue);
  }

  void _refresh() {
    setState(() {
      _selected = null;
      _future = _load();
    });
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> rows) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return rows.where((row) {
      return widget.config.searchKeys.any((key) {
        final value = _formatValue(row[key]).toLowerCase();
        return value.contains(query);
      });
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return LoadingView(
              message: 'Cargando ${widget.config.title.toLowerCase()}...',
            );
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final rows = _filtered(snapshot.data ?? []);
          return Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _Toolbar(
                      searchCtrl: _searchCtrl,
                      query: _query,
                      filterValue: _filterValue,
                      config: widget.config,
                      onSearchChanged: (value) =>
                          setState(() => _query = value),
                      onFilterChanged: (value) {
                        setState(() {
                          _filterValue = value;
                          _selected = null;
                          _future = _load();
                        });
                      },
                      onRefresh: _refresh,
                    ),
                    _CountBar(count: rows.length, label: widget.config.title),
                    Expanded(
                      child: rows.isEmpty
                          ? EmptyState(
                              title: _query.isEmpty
                                  ? 'Sin datos'
                                  : 'Sin resultados',
                              subtitle: _query.isEmpty
                                  ? 'No hay registros disponibles en la nube'
                                  : 'Intenta con otra búsqueda',
                              icon: widget.config.icon,
                            )
                          : _ResourceList(
                              rows: rows,
                              fields: widget.config.fields,
                              selected: _selected,
                              onSelected: (row) async {
                                setState(() => _selected = row);
                                if (!_isDesktop) {
                                  await showDialog<void>(
                                    context: context,
                                    builder: (_) => Dialog.fullscreen(
                                      child: _DetailPanel(
                                        title: widget.config.title,
                                        row: row,
                                        fields: widget.config.detailFields,
                                        onClose: () => Navigator.pop(context),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                    ),
                  ],
                ),
              ),
              if (_isDesktop && _selected != null)
                _DetailPanel(
                  title: widget.config.title,
                  row: _selected!,
                  fields: widget.config.detailFields,
                  onClose: () => setState(() => _selected = null),
                ),
            ],
          );
        },
      ),
    );
  }
}

class CloudStoreSettingsPage extends StatefulWidget {
  const CloudStoreSettingsPage({super.key});

  @override
  State<CloudStoreSettingsPage> createState() => _CloudStoreSettingsPageState();
}

class _CloudStoreSettingsPageState extends State<CloudStoreSettingsPage> {
  late final CloudAdminService _service;
  late Future<Map<String, dynamic>?> _future;
  final _brandCtrl = TextEditingController();
  final _logoCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _loadedControllers = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _service = CloudAdminService(
      sessionManager: context.read<SessionManager>(),
    );
    _future = _service.getSettings();
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _logoCtrl.dispose();
    _whatsappCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic>? settings) {
    if (_loadedControllers || settings == null) return;
    _brandCtrl.text = _formatValue(settings['brand_name']);
    _logoCtrl.text = _formatValue(settings['logo_url']);
    _whatsappCtrl.text = _formatValue(settings['whatsapp']);
    _emailCtrl.text = _formatValue(settings['email']);
    _addressCtrl.text = _formatValue(settings['address']);
    _loadedControllers = true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.updateSettings({
        'brand_name': _brandCtrl.text.trim(),
        'logo_url': _logoCtrl.text.trim(),
        'whatsapp': _whatsappCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración guardada en la nube')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView(message: 'Cargando configuración...');
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  _loadedControllers = false;
                  _future = _service.getSettings();
                });
              },
            );
          }
          _hydrate(snapshot.data);

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 720),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Datos públicos de la tienda',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _SettingsField(label: 'Marca', controller: _brandCtrl),
                      _SettingsField(label: 'Logo URL', controller: _logoCtrl),
                      _SettingsField(
                        label: 'WhatsApp',
                        controller: _whatsappCtrl,
                      ),
                      _SettingsField(label: 'Email', controller: _emailCtrl),
                      _SettingsField(
                        label: 'Dirección',
                        controller: _addressCtrl,
                        maxLines: 3,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 18,
                                ),
                          label: Text(_saving ? 'Guardando...' : 'Guardar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String query;
  final String? filterValue;
  final CloudResourceConfig config;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onFilterChanged;
  final VoidCallback onRefresh;

  const _Toolbar({
    required this.searchCtrl,
    required this.query,
    required this.filterValue,
    required this.config,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: searchCtrl,
                onChanged: onSearchChanged,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar',
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () {
                            searchCtrl.clear();
                            onSearchChanged('');
                          },
                        ),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
            ),
          ),
          if (config.filterOptions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            PopupMenuButton<String?>(
              tooltip: 'Filtro',
              onSelected: onFilterChanged,
              itemBuilder: (_) => config.filterOptions
                  .map(
                    (option) => PopupMenuItem<String?>(
                      value: option.value,
                      child: Text(option.label),
                    ),
                  )
                  .toList(),
              icon: const Icon(Icons.filter_list_rounded, size: 18),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            onPressed: onRefresh,
            color: AppColors.textSecondary,
            tooltip: 'Actualizar',
          ),
        ],
      ),
    );
  }
}

class _CountBar extends StatelessWidget {
  final int count;
  final String label;

  const _CountBar({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      color: AppColors.surfaceVariant,
      child: Row(
        children: [
          Text(
            '$count registro${count == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ResourceList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final List<ResourceField> fields;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onSelected;

  const _ResourceList({
    required this.rows,
    required this.fields,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = rows[index];
        final isSelected = selected != null && selected!['id'] == row['id'];
        return Material(
          color: isSelected ? AppColors.primaryLight : AppColors.surface,
          child: InkWell(
            onTap: () => onSelected(row),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 720) {
                    return _MobileRow(row: row, fields: fields);
                  }
                  return _DesktopRow(row: row, fields: fields);
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<ResourceField> fields;

  const _DesktopRow({required this.row, required this.fields});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: fields.map((field) {
        return Expanded(
          flex: field == fields.first ? 2 : 1,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: _FieldValue(field: field, value: row[field.key]),
          ),
        );
      }).toList(),
    );
  }
}

class _MobileRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<ResourceField> fields;

  const _MobileRow({required this.row, required this.fields});

  @override
  Widget build(BuildContext context) {
    final primary = fields.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldValue(field: primary, value: row[primary.key], emphasize: true),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: fields.skip(1).take(4).map((field) {
            return Text(
              '${field.label}: ${_formatValue(row[field.key])}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _FieldValue extends StatelessWidget {
  final ResourceField field;
  final Object? value;
  final bool emphasize;

  const _FieldValue({
    required this.field,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = _formatValue(value);
    if (field.badge && text != '—') {
      return Align(
        alignment: Alignment.centerLeft,
        child: StatusBadge.fromString(text),
      );
    }
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: emphasize ? 14 : 13,
        fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
        color: emphasize ? AppColors.textPrimary : AppColors.textSecondary,
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  final String title;
  final Map<String, dynamic> row;
  final List<ResourceField> fields;
  final VoidCallback onClose;

  const _DetailPanel({
    required this.title,
    required this.row,
    required this.fields,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.detailPanelWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: fields.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, index) {
                final field = fields[index];
                final value = _formatValue(row[field.key]);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SelectableText(
                      value,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;

  const _SettingsField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          ),
        ),
      ),
    );
  }
}

String _formatValue(Object? value) {
  if (value == null) return '—';
  if (value is bool) return value ? 'activo' : 'inactivo';
  if (value is num) return NumberFormat.decimalPattern('es_DO').format(value);
  if (value is DateTime) return DateFormat('dd/MM/yyyy HH:mm').format(value);
  if (value is List) {
    if (value.isEmpty) return '—';
    return value.map(_formatValue).join(', ');
  }
  if (value is Map) {
    if (value.isEmpty) return '—';
    return value.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
  }
  final text = value.toString().trim();
  if (text.isEmpty) return '—';
  final date = DateTime.tryParse(text);
  if (date != null && (text.contains('T') || text.contains('-'))) {
    return DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
  }
  return text;
}

const productResourceConfig = CloudResourceConfig(
  title: 'Productos',
  icon: Icons.inventory_2_outlined,
  endpoint: '/api/admin/products',
  listKey: 'products',
  filterParam: 'status',
  filterOptions: [
    ResourceFilterOption('Todos', null),
    ResourceFilterOption('Publicados', 'published'),
    ResourceFilterOption('Borradores', 'draft'),
    ResourceFilterOption('Archivados', 'archived'),
  ],
  searchKeys: ['name', 'slug', 'summary', 'status'],
  fields: [
    ResourceField('name', 'Producto'),
    ResourceField('slug', 'Slug'),
    ResourceField('status', 'Estado', badge: true),
    ResourceField('price_text', 'Precio'),
    ResourceField('updated_at', 'Actualizado'),
  ],
  detailFields: [
    ResourceField('id', 'ID'),
    ResourceField('name', 'Producto'),
    ResourceField('slug', 'Slug'),
    ResourceField('summary', 'Resumen'),
    ResourceField('description', 'Descripción'),
    ResourceField('status', 'Estado'),
    ResourceField('featured', 'Destacado'),
    ResourceField('price_text', 'Precio texto'),
    ResourceField('price_amount', 'Precio monto'),
    ResourceField('currency', 'Moneda'),
    ResourceField('tags', 'Etiquetas'),
    ResourceField('platforms', 'Plataformas'),
    ResourceField('created_at', 'Creado'),
    ResourceField('updated_at', 'Actualizado'),
  ],
);

const planResourceConfig = CloudResourceConfig(
  title: 'Planes',
  icon: Icons.layers_outlined,
  endpoint: '/api/admin/product-plans',
  listKey: 'plans',
  filterParam: 'is_active',
  filterOptions: [
    ResourceFilterOption('Todos', null),
    ResourceFilterOption('Activos', 'true'),
    ResourceFilterOption('Inactivos', 'false'),
  ],
  searchKeys: ['name', 'code', 'product_name', 'project_name'],
  fields: [
    ResourceField('name', 'Plan'),
    ResourceField('code', 'Código'),
    ResourceField('product_name', 'Producto'),
    ResourceField('billing_period', 'Periodo'),
    ResourceField('is_active', 'Estado', badge: true),
  ],
  detailFields: [
    ResourceField('id', 'ID'),
    ResourceField('name', 'Plan'),
    ResourceField('code', 'Código'),
    ResourceField('product_name', 'Producto'),
    ResourceField('project_name', 'Proyecto'),
    ResourceField('billing_period', 'Periodo'),
    ResourceField('price_amount', 'Precio'),
    ResourceField('currency', 'Moneda'),
    ResourceField('device_limit', 'Límite dispositivos'),
    ResourceField('company_limit', 'Límite compañías'),
    ResourceField('default_grace_days', 'Días gracia'),
    ResourceField('trial_days', 'Días prueba'),
    ResourceField('is_active', 'Activo'),
    ResourceField('updated_at', 'Actualizado'),
  ],
);

const subscriptionResourceConfig = CloudResourceConfig(
  title: 'Suscripciones',
  icon: Icons.subscriptions_outlined,
  endpoint: '/api/admin/subscriptions',
  listKey: 'subscriptions',
  filterParam: 'status',
  filterOptions: [
    ResourceFilterOption('Todas', null),
    ResourceFilterOption('Activas', 'active'),
    ResourceFilterOption('En prueba', 'trialing'),
    ResourceFilterOption('Pago pendiente', 'past_due'),
    ResourceFilterOption('Suspendidas', 'suspended'),
    ResourceFilterOption('Canceladas', 'cancelled'),
  ],
  searchKeys: ['company_name', 'plan_name', 'product_name', 'status'],
  fields: [
    ResourceField('company_name', 'Compañía'),
    ResourceField('plan_name', 'Plan'),
    ResourceField('product_name', 'Producto'),
    ResourceField('status', 'Estado', badge: true),
    ResourceField('end_date', 'Fin'),
  ],
  detailFields: [
    ResourceField('id', 'ID'),
    ResourceField('company_name', 'Compañía'),
    ResourceField('plan_name', 'Plan'),
    ResourceField('product_name', 'Producto'),
    ResourceField('project_name', 'Proyecto'),
    ResourceField('status', 'Estado'),
    ResourceField('start_date', 'Inicio'),
    ResourceField('end_date', 'Fin'),
    ResourceField('grace_until', 'Gracia hasta'),
    ResourceField('cancelled_at', 'Cancelada'),
    ResourceField('suspended_at', 'Suspendida'),
    ResourceField('updated_at', 'Actualizada'),
  ],
);

const paymentResourceConfig = CloudResourceConfig(
  title: 'Pagos',
  icon: Icons.payments_outlined,
  endpoint: '/api/admin/payments',
  listKey: 'payments',
  filterParam: 'status',
  filterOptions: [
    ResourceFilterOption('Todos', null),
    ResourceFilterOption('Pagados', 'paid'),
    ResourceFilterOption('Pendientes', 'pending'),
    ResourceFilterOption('Fallidos', 'failed'),
    ResourceFilterOption('Reembolsados', 'refunded'),
  ],
  searchKeys: ['company_name', 'product_name', 'reference', 'status'],
  fields: [
    ResourceField('company_name', 'Compañía'),
    ResourceField('product_name', 'Producto'),
    ResourceField('amount', 'Monto'),
    ResourceField('status', 'Estado', badge: true),
    ResourceField('paid_at', 'Pagado'),
  ],
  detailFields: [
    ResourceField('id', 'ID'),
    ResourceField('company_name', 'Compañía'),
    ResourceField('subscription_id', 'Suscripción'),
    ResourceField('product_name', 'Producto'),
    ResourceField('amount', 'Monto'),
    ResourceField('currency', 'Moneda'),
    ResourceField('status', 'Estado'),
    ResourceField('method', 'Método'),
    ResourceField('reference', 'Referencia'),
    ResourceField('paid_at', 'Pagado'),
    ResourceField('recorded_at', 'Registrado'),
  ],
);

const auditResourceConfig = CloudResourceConfig(
  title: 'Registros de auditoría',
  icon: Icons.manage_search_rounded,
  endpoint: '/api/admin/audit-logs',
  listKey: 'logs',
  searchKeys: ['action', 'target_type', 'actor_email', 'company_name'],
  fields: [
    ResourceField('action', 'Acción'),
    ResourceField('target_type', 'Destino'),
    ResourceField('actor_email', 'Usuario'),
    ResourceField('company_name', 'Compañía'),
    ResourceField('created_at', 'Fecha'),
  ],
  detailFields: [
    ResourceField('id', 'ID'),
    ResourceField('action', 'Acción'),
    ResourceField('target_type', 'Destino'),
    ResourceField('target_id', 'Destino ID'),
    ResourceField('actor_type', 'Actor tipo'),
    ResourceField('actor_email', 'Actor'),
    ResourceField('company_name', 'Compañía'),
    ResourceField('before_data', 'Antes'),
    ResourceField('after_data', 'Después'),
    ResourceField('created_at', 'Fecha'),
  ],
);

const userResourceConfig = CloudResourceConfig(
  title: 'Usuarios del sistema',
  icon: Icons.admin_panel_settings_outlined,
  endpoint: '/api/admin/platform-users',
  listKey: 'users',
  filterParam: 'status',
  filterOptions: [
    ResourceFilterOption('Todos', null),
    ResourceFilterOption('Activos', 'active'),
    ResourceFilterOption('Invitados', 'invited'),
    ResourceFilterOption('Suspendidos', 'suspended'),
  ],
  searchKeys: ['email', 'full_name', 'user_type', 'status'],
  fields: [
    ResourceField('email', 'Email'),
    ResourceField('full_name', 'Nombre'),
    ResourceField('user_type', 'Tipo'),
    ResourceField('status', 'Estado', badge: true),
    ResourceField('created_at', 'Creado'),
  ],
  detailFields: [
    ResourceField('id', 'ID'),
    ResourceField('email', 'Email'),
    ResourceField('full_name', 'Nombre'),
    ResourceField('user_type', 'Tipo'),
    ResourceField('status', 'Estado'),
    ResourceField('last_login_at', 'Último acceso'),
    ResourceField('created_at', 'Creado'),
    ResourceField('updated_at', 'Actualizado'),
  ],
);
