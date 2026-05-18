import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
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

enum ResourceActionMethod { post, put, patch, delete }

enum ResourceFormFieldType { text, number, multiline, boolean, select }

class ResourceFormField {
  final String key;
  final String label;
  final ResourceFormFieldType type;
  final bool required;
  final List<ResourceFilterOption> options;
  final Object? defaultValue;

  const ResourceFormField({
    required this.key,
    required this.label,
    this.type = ResourceFormFieldType.text,
    this.required = false,
    this.options = const [],
    this.defaultValue,
  });
}

class ResourceAction {
  final String label;
  final IconData icon;
  final ResourceActionMethod method;
  final String path;
  final List<ResourceFormField> fields;
  final bool destructive;

  const ResourceAction({
    required this.label,
    required this.icon,
    required this.method,
    required this.path,
    this.fields = const [],
    this.destructive = false,
  });
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
  final ResourceAction? createAction;
  final List<ResourceAction> rowActions;

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
    this.createAction,
    this.rowActions = const [],
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
    Map<String, dynamic> data;
    try {
      data = await _client.get(path);
    } on ApiException catch (error) {
      if (error.statusCode == 500) return [];
      rethrow;
    }
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

  Future<Map<String, dynamic>?> getLicenseConfig() async {
    final data = await _client.get('/api/admin/license-config');
    final config = data['config'];
    if (config is Map<String, dynamic>) return config;
    return null;
  }

  Future<Map<String, dynamic>?> updateLicenseConfig(
    Map<String, dynamic> body,
  ) async {
    final data = await _client.put('/api/admin/license-config', body);
    final config = data['config'];
    if (config is Map<String, dynamic>) return config;
    return null;
  }

  Future<void> runAction(
    ResourceAction action,
    Map<String, dynamic>? row,
    Map<String, dynamic> body,
  ) async {
    final path = _resolvePath(action.path, row);
    switch (action.method) {
      case ResourceActionMethod.post:
        await _client.post(path, body);
        break;
      case ResourceActionMethod.put:
        await _client.put(path, body);
        break;
      case ResourceActionMethod.patch:
        await _client.patch(path, body);
        break;
      case ResourceActionMethod.delete:
        await _client.delete(path);
        break;
    }
  }

  String _resolvePath(String path, Map<String, dynamic>? row) {
    if (row == null) return path;
    var out = path;
    for (final entry in row.entries) {
      out = out.replaceAll(
        ':${entry.key}',
        Uri.encodeComponent('${entry.value}'),
      );
    }
    return out;
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

  Future<void> _runAction(
    ResourceAction action, {
    Map<String, dynamic>? row,
  }) async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ResourceActionDialog(action: action, row: row),
    );
    if (body == null) return;

    try {
      await _service.runAction(action, row, body);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${action.label} completado')));
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    }
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
                      onCreate: widget.config.createAction == null
                          ? null
                          : () => _runAction(widget.config.createAction!),
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
                                        actions: widget.config.rowActions,
                                        onAction: (action) =>
                                            _runAction(action, row: row),
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
                  actions: widget.config.rowActions,
                  onAction: (action) => _runAction(action, row: _selected!),
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

class CloudLicenseConfigPage extends StatefulWidget {
  const CloudLicenseConfigPage({super.key});

  @override
  State<CloudLicenseConfigPage> createState() => _CloudLicenseConfigPageState();
}

class _CloudLicenseConfigPageState extends State<CloudLicenseConfigPage> {
  late final CloudAdminService _service;
  late Future<Map<String, dynamic>?> _future;
  final _demoDaysCtrl = TextEditingController();
  final _demoDevicesCtrl = TextEditingController();
  final _fullDaysCtrl = TextEditingController();
  final _fullDevicesCtrl = TextEditingController();
  bool _loadedControllers = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _service = CloudAdminService(
      sessionManager: context.read<SessionManager>(),
    );
    _future = _service.getLicenseConfig();
  }

  @override
  void dispose() {
    _demoDaysCtrl.dispose();
    _demoDevicesCtrl.dispose();
    _fullDaysCtrl.dispose();
    _fullDevicesCtrl.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic>? config) {
    if (_loadedControllers || config == null) return;
    _demoDaysCtrl.text = _plainValue(config['demo_dias_validez']);
    _demoDevicesCtrl.text = _plainValue(config['demo_max_dispositivos']);
    _fullDaysCtrl.text = _plainValue(config['full_dias_validez']);
    _fullDevicesCtrl.text = _plainValue(config['full_max_dispositivos']);
    _loadedControllers = true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.updateLicenseConfig({
        'demo_dias_validez': int.tryParse(_demoDaysCtrl.text.trim()),
        'demo_max_dispositivos': int.tryParse(_demoDevicesCtrl.text.trim()),
        'full_dias_validez': int.tryParse(_fullDaysCtrl.text.trim()),
        'full_max_dispositivos': int.tryParse(_fullDevicesCtrl.text.trim()),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración de licencias guardada')),
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
                  _future = _service.getLicenseConfig();
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
                        'Valores predeterminados de licencias',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _SettingsField(
                        label: 'Días demo',
                        controller: _demoDaysCtrl,
                        keyboardType: TextInputType.number,
                      ),
                      _SettingsField(
                        label: 'Dispositivos demo',
                        controller: _demoDevicesCtrl,
                        keyboardType: TextInputType.number,
                      ),
                      _SettingsField(
                        label: 'Días full',
                        controller: _fullDaysCtrl,
                        keyboardType: TextInputType.number,
                      ),
                      _SettingsField(
                        label: 'Dispositivos full',
                        controller: _fullDevicesCtrl,
                        keyboardType: TextInputType.number,
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
                              : const Icon(Icons.save_outlined, size: 18),
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
  final VoidCallback? onCreate;

  const _Toolbar({
    required this.searchCtrl,
    required this.query,
    required this.filterValue,
    required this.config,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onRefresh,
    this.onCreate,
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
          if (onCreate != null) ...[
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              icon: const Icon(Icons.add_rounded, size: 18),
              onPressed: onCreate,
              tooltip: 'Crear',
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
  final List<ResourceAction> actions;
  final ValueChanged<ResourceAction>? onAction;
  final VoidCallback onClose;

  const _DetailPanel({
    required this.title,
    required this.row,
    required this.fields,
    this.actions = const [],
    this.onAction,
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
              itemCount: fields.length + (actions.isEmpty ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, index) {
                if (index == 0 && actions.isNotEmpty) {
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: actions.map((action) {
                      final color = action.destructive
                          ? AppColors.error
                          : AppColors.primary;
                      return OutlinedButton.icon(
                        onPressed: onAction == null
                            ? null
                            : () => onAction!(action),
                        icon: Icon(action.icon, size: 16, color: color),
                        label: Text(action.label),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: color,
                          side: BorderSide(color: color.withValues(alpha: .45)),
                        ),
                      );
                    }).toList(),
                  );
                }

                final fieldIndex = actions.isEmpty ? index : index - 1;
                final field = fields[fieldIndex];
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

class _ResourceActionDialog extends StatefulWidget {
  final ResourceAction action;
  final Map<String, dynamic>? row;

  const _ResourceActionDialog({required this.action, this.row});

  @override
  State<_ResourceActionDialog> createState() => _ResourceActionDialogState();
}

class _ResourceActionDialogState extends State<_ResourceActionDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _boolValues = {};
  final Map<String, String?> _selectValues = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.action.fields) {
      final initial = widget.row?[field.key] ?? field.defaultValue;
      switch (field.type) {
        case ResourceFormFieldType.boolean:
          _boolValues[field.key] =
              initial == true || initial.toString() == 'true';
          break;
        case ResourceFormFieldType.select:
          _selectValues[field.key] = initial?.toString();
          break;
        case ResourceFormFieldType.text:
        case ResourceFormFieldType.number:
        case ResourceFormFieldType.multiline:
          _controllers[field.key] = TextEditingController(
            text: _plainValue(initial),
          );
          break;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final body = <String, dynamic>{};
    for (final field in widget.action.fields) {
      switch (field.type) {
        case ResourceFormFieldType.boolean:
          body[field.key] = _boolValues[field.key] ?? false;
          break;
        case ResourceFormFieldType.select:
          final value = _selectValues[field.key];
          if (value != null && value.isNotEmpty) body[field.key] = value;
          break;
        case ResourceFormFieldType.number:
          final raw = _controllers[field.key]?.text.trim() ?? '';
          if (raw.isNotEmpty) body[field.key] = num.tryParse(raw) ?? raw;
          break;
        case ResourceFormFieldType.text:
        case ResourceFormFieldType.multiline:
          final raw = _controllers[field.key]?.text.trim() ?? '';
          if (raw.isNotEmpty) body[field.key] = raw;
          break;
      }
    }
    Navigator.pop(context, body);
  }

  @override
  Widget build(BuildContext context) {
    final hasFields = widget.action.fields.isNotEmpty;
    return AlertDialog(
      title: Text(widget.action.label),
      content: SizedBox(
        width: 420,
        child: hasFields
            ? Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.action.fields.map(_buildField).toList(),
                  ),
                ),
              )
            : Text(
                widget.action.destructive
                    ? 'Esta acción no se puede deshacer.'
                    : 'Confirma para continuar.',
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          style: widget.action.destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.error)
              : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }

  Widget _buildField(ResourceFormField field) {
    switch (field.type) {
      case ResourceFormFieldType.boolean:
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          value: _boolValues[field.key] ?? false,
          onChanged: (value) => setState(() {
            _boolValues[field.key] = value ?? false;
          }),
        );
      case ResourceFormFieldType.select:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Builder(builder: (ctx) {
            final items = <DropdownMenuItem<String>>[];
            final seen = <String>{};
            for (final option in field.options) {
              if (option.value == null) continue;
              if (seen.contains(option.value)) continue;
              seen.add(option.value!);
              items.add(DropdownMenuItem<String>(value: option.value, child: Text(option.label)));
            }

            final current = _selectValues[field.key];
            final safeInitial = items.any((it) => it.value == current) ? current : null;

            return DropdownButtonFormField<String>(
              initialValue: safeInitial,
              decoration: InputDecoration(labelText: field.label),
              validator: field.required
                  ? (value) => value == null || value.isEmpty ? 'Requerido' : null
                  : null,
              items: items,
              onChanged: (value) => _selectValues[field.key] = value,
            );
          }),
        );
      case ResourceFormFieldType.text:
      case ResourceFormFieldType.number:
      case ResourceFormFieldType.multiline:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: TextFormField(
            controller: _controllers[field.key],
            maxLines: field.type == ResourceFormFieldType.multiline ? 4 : 1,
            keyboardType: field.type == ResourceFormFieldType.number
                ? TextInputType.number
                : TextInputType.text,
            decoration: InputDecoration(labelText: field.label),
            validator: field.required
                ? (value) =>
                      value == null || value.trim().isEmpty ? 'Requerido' : null
                : null,
          ),
        );
    }
  }
}

class _SettingsField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType? keyboardType;

  const _SettingsField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
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

String _plainValue(Object? value) {
  if (value == null) return '';
  final text = value.toString().trim();
  return text == '—' ? '' : text;
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
  createAction: ResourceAction(
    label: 'Crear producto',
    icon: Icons.add_rounded,
    method: ResourceActionMethod.post,
    path: '/api/admin/products',
    fields: [
      ResourceFormField(key: 'slug', label: 'Slug', required: true),
      ResourceFormField(key: 'name', label: 'Nombre', required: true),
      ResourceFormField(key: 'summary', label: 'Resumen'),
      ResourceFormField(
        key: 'description',
        label: 'Descripción',
        type: ResourceFormFieldType.multiline,
      ),
      ResourceFormField(key: 'price_text', label: 'Precio texto'),
      ResourceFormField(
        key: 'price_amount',
        label: 'Precio monto',
        type: ResourceFormFieldType.number,
      ),
      ResourceFormField(key: 'currency', label: 'Moneda', defaultValue: 'DOP'),
      ResourceFormField(
        key: 'status',
        label: 'Estado',
        type: ResourceFormFieldType.select,
        defaultValue: 'draft',
        options: [
          ResourceFilterOption('Borrador', 'draft'),
          ResourceFilterOption('Publicado', 'published'),
          ResourceFilterOption('Archivado', 'archived'),
        ],
      ),
      ResourceFormField(
        key: 'featured',
        label: 'Destacado',
        type: ResourceFormFieldType.boolean,
      ),
    ],
  ),
  rowActions: [
    ResourceAction(
      label: 'Editar',
      icon: Icons.edit_outlined,
      method: ResourceActionMethod.put,
      path: '/api/admin/products/:id',
      fields: [
        ResourceFormField(key: 'slug', label: 'Slug'),
        ResourceFormField(key: 'name', label: 'Nombre'),
        ResourceFormField(key: 'summary', label: 'Resumen'),
        ResourceFormField(
          key: 'description',
          label: 'Descripción',
          type: ResourceFormFieldType.multiline,
        ),
        ResourceFormField(key: 'price_text', label: 'Precio texto'),
        ResourceFormField(
          key: 'price_amount',
          label: 'Precio monto',
          type: ResourceFormFieldType.number,
        ),
        ResourceFormField(key: 'currency', label: 'Moneda'),
        ResourceFormField(
          key: 'featured',
          label: 'Destacado',
          type: ResourceFormFieldType.boolean,
        ),
      ],
    ),
    ResourceAction(
      label: 'Cambiar estado',
      icon: Icons.swap_horiz_rounded,
      method: ResourceActionMethod.put,
      path: '/api/admin/products/:id/status',
      fields: [
        ResourceFormField(
          key: 'status',
          label: 'Estado',
          type: ResourceFormFieldType.select,
          required: true,
          options: [
            ResourceFilterOption('Borrador', 'draft'),
            ResourceFilterOption('Publicado', 'published'),
            ResourceFilterOption('Archivado', 'archived'),
          ],
        ),
      ],
    ),
    ResourceAction(
      label: 'Agregar video',
      icon: Icons.video_call_outlined,
      method: ResourceActionMethod.post,
      path: '/api/admin/products/:id/media/video-link',
      fields: [
        ResourceFormField(key: 'url', label: 'URL del video', required: true),
        ResourceFormField(
          key: 'sort_order',
          label: 'Orden',
          type: ResourceFormFieldType.number,
          defaultValue: 0,
        ),
      ],
    ),
    ResourceAction(
      label: 'Eliminar',
      icon: Icons.delete_outline_rounded,
      method: ResourceActionMethod.delete,
      path: '/api/admin/products/:id',
      destructive: true,
    ),
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
  createAction: ResourceAction(
    label: 'Crear plan',
    icon: Icons.add_rounded,
    method: ResourceActionMethod.post,
    path: '/api/admin/product-plans',
    fields: [
      ResourceFormField(key: 'code', label: 'Código', required: true),
      ResourceFormField(key: 'name', label: 'Nombre', required: true),
      ResourceFormField(key: 'product_id', label: 'Producto ID'),
      ResourceFormField(key: 'project_id', label: 'Proyecto ID'),
      ResourceFormField(
        key: 'billing_period',
        label: 'Periodo',
        type: ResourceFormFieldType.select,
        required: true,
        options: [
          ResourceFilterOption('Prueba', 'trial'),
          ResourceFilterOption('Mensual', 'monthly'),
          ResourceFilterOption('Anual', 'annual'),
          ResourceFilterOption('De por vida', 'lifetime'),
        ],
      ),
      ResourceFormField(
        key: 'price_amount',
        label: 'Precio',
        type: ResourceFormFieldType.number,
        required: true,
      ),
      ResourceFormField(key: 'currency', label: 'Moneda', defaultValue: 'DOP'),
      ResourceFormField(
        key: 'device_limit',
        label: 'Límite dispositivos',
        type: ResourceFormFieldType.number,
      ),
      ResourceFormField(
        key: 'company_limit',
        label: 'Límite compañías',
        type: ResourceFormFieldType.number,
      ),
      ResourceFormField(
        key: 'default_grace_days',
        label: 'Días gracia',
        type: ResourceFormFieldType.number,
      ),
      ResourceFormField(
        key: 'trial_days',
        label: 'Días prueba',
        type: ResourceFormFieldType.number,
      ),
      ResourceFormField(
        key: 'is_active',
        label: 'Activo',
        type: ResourceFormFieldType.boolean,
        defaultValue: true,
      ),
    ],
  ),
  rowActions: [
    ResourceAction(
      label: 'Editar',
      icon: Icons.edit_outlined,
      method: ResourceActionMethod.patch,
      path: '/api/admin/product-plans/:id',
      fields: [
        ResourceFormField(key: 'code', label: 'Código'),
        ResourceFormField(key: 'name', label: 'Nombre'),
        ResourceFormField(
          key: 'billing_period',
          label: 'Periodo',
          type: ResourceFormFieldType.select,
          options: [
            ResourceFilterOption('Prueba', 'trial'),
            ResourceFilterOption('Mensual', 'monthly'),
            ResourceFilterOption('Anual', 'annual'),
            ResourceFilterOption('De por vida', 'lifetime'),
          ],
        ),
        ResourceFormField(
          key: 'price_amount',
          label: 'Precio',
          type: ResourceFormFieldType.number,
        ),
        ResourceFormField(key: 'currency', label: 'Moneda'),
        ResourceFormField(
          key: 'device_limit',
          label: 'Límite dispositivos',
          type: ResourceFormFieldType.number,
        ),
        ResourceFormField(
          key: 'default_grace_days',
          label: 'Días gracia',
          type: ResourceFormFieldType.number,
        ),
        ResourceFormField(
          key: 'trial_days',
          label: 'Días prueba',
          type: ResourceFormFieldType.number,
        ),
        ResourceFormField(
          key: 'is_active',
          label: 'Activo',
          type: ResourceFormFieldType.boolean,
        ),
      ],
    ),
    ResourceAction(
      label: 'Habilitar',
      icon: Icons.check_circle_outline_rounded,
      method: ResourceActionMethod.patch,
      path: '/api/admin/product-plans/:id/enable',
    ),
    ResourceAction(
      label: 'Deshabilitar',
      icon: Icons.pause_circle_outline_rounded,
      method: ResourceActionMethod.patch,
      path: '/api/admin/product-plans/:id/disable',
    ),
    ResourceAction(
      label: 'Sincronizar PayPal',
      icon: Icons.sync_rounded,
      method: ResourceActionMethod.post,
      path: '/api/admin/product-plans/:id/sync-paypal',
    ),
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
    ResourceField('paypal_product_id', 'PayPal Product ID'),
    ResourceField('paypal_plan_id', 'PayPal Plan ID'),
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
  createAction: ResourceAction(
    label: 'Crear suscripción',
    icon: Icons.add_rounded,
    method: ResourceActionMethod.post,
    path: '/api/admin/subscriptions',
    fields: [
      ResourceFormField(
        key: 'company_id',
        label: 'Compañía ID',
        required: true,
      ),
      ResourceFormField(key: 'plan_id', label: 'Plan ID', required: true),
      ResourceFormField(key: 'product_id', label: 'Producto ID'),
      ResourceFormField(key: 'project_id', label: 'Proyecto ID'),
      ResourceFormField(
        key: 'status',
        label: 'Estado',
        type: ResourceFormFieldType.select,
        options: [
          ResourceFilterOption('Prueba', 'trial'),
          ResourceFilterOption('Activa', 'active'),
          ResourceFilterOption('Pago pendiente', 'past_due'),
          ResourceFilterOption('Suspendida', 'suspended'),
          ResourceFilterOption('Cancelada', 'cancelled'),
          ResourceFilterOption('Expirada', 'expired'),
          ResourceFilterOption('De por vida', 'lifetime'),
        ],
      ),
      ResourceFormField(key: 'start_date', label: 'Inicio ISO'),
      ResourceFormField(key: 'end_date', label: 'Fin ISO'),
      ResourceFormField(
        key: 'notes',
        label: 'Notas',
        type: ResourceFormFieldType.multiline,
      ),
    ],
  ),
  rowActions: [
    ResourceAction(
      label: 'Cambiar estado',
      icon: Icons.swap_horiz_rounded,
      method: ResourceActionMethod.patch,
      path: '/api/admin/subscriptions/:id/status',
      fields: [
        ResourceFormField(
          key: 'status',
          label: 'Estado',
          type: ResourceFormFieldType.select,
          required: true,
          options: [
            ResourceFilterOption('Activa', 'active'),
            ResourceFilterOption('Pago pendiente', 'past_due'),
            ResourceFilterOption('Suspendida', 'suspended'),
            ResourceFilterOption('Cancelada', 'cancelled'),
            ResourceFilterOption('Expirada', 'expired'),
            ResourceFilterOption('De por vida', 'lifetime'),
          ],
        ),
        ResourceFormField(
          key: 'notes',
          label: 'Notas',
          type: ResourceFormFieldType.multiline,
        ),
      ],
    ),
    ResourceAction(
      label: 'Extender',
      icon: Icons.more_time_rounded,
      method: ResourceActionMethod.patch,
      path: '/api/admin/subscriptions/:id/extend',
      fields: [
        ResourceFormField(
          key: 'days',
          label: 'Días a extender',
          type: ResourceFormFieldType.number,
          required: true,
        ),
      ],
    ),
    ResourceAction(
      label: 'Suspender',
      icon: Icons.pause_circle_outline_rounded,
      method: ResourceActionMethod.patch,
      path: '/api/admin/subscriptions/:id/suspend',
    ),
    ResourceAction(
      label: 'Cancelar',
      icon: Icons.cancel_outlined,
      method: ResourceActionMethod.patch,
      path: '/api/admin/subscriptions/:id/cancel',
      destructive: true,
    ),
  ],
  searchKeys: [
    'company_name',
    'plan_name',
    'product_name',
    'status',
    'paypal_subscription_id',
  ],
  fields: [
    ResourceField('company_name', 'Compañía'),
    ResourceField('plan_name', 'Plan'),
    ResourceField('product_name', 'Producto'),
    ResourceField('status', 'Estado', badge: true),
    ResourceField('next_payment_date', 'Próximo pago'),
    ResourceField('paypal_subscription_id', 'PayPal'),
  ],
  detailFields: [
    ResourceField('id', 'ID'),
    ResourceField('company_name', 'Compañía'),
    ResourceField('plan_name', 'Plan'),
    ResourceField('product_name', 'Producto'),
    ResourceField('project_name', 'Proyecto'),
    ResourceField('status', 'Estado'),
    ResourceField('paypal_subscription_id', 'PayPal Subscription ID'),
    ResourceField('start_date', 'Inicio'),
    ResourceField('end_date', 'Fin'),
    ResourceField('next_payment_date', 'Próximo pago'),
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
  createAction: ResourceAction(
    label: 'Registrar pago',
    icon: Icons.add_card_rounded,
    method: ResourceActionMethod.post,
    path: '/api/admin/payments',
    fields: [
      ResourceFormField(
        key: 'subscription_id',
        label: 'Suscripción ID',
        required: true,
      ),
      ResourceFormField(
        key: 'amount',
        label: 'Monto',
        type: ResourceFormFieldType.number,
        required: true,
      ),
      ResourceFormField(key: 'currency', label: 'Moneda', defaultValue: 'DOP'),
      ResourceFormField(
        key: 'payment_method',
        label: 'Método',
        type: ResourceFormFieldType.select,
        defaultValue: 'manual',
        options: [
          ResourceFilterOption('Manual', 'manual'),
          ResourceFilterOption('Efectivo', 'cash'),
          ResourceFilterOption('Transferencia', 'transfer'),
          ResourceFilterOption('Tarjeta', 'card'),
          ResourceFilterOption('PayPal', 'paypal'),
          ResourceFilterOption('Otro', 'other'),
        ],
      ),
      ResourceFormField(
        key: 'status',
        label: 'Estado',
        type: ResourceFormFieldType.select,
        defaultValue: 'paid',
        options: [
          ResourceFilterOption('Pagado', 'paid'),
          ResourceFilterOption('Pendiente', 'pending'),
          ResourceFilterOption('Fallido', 'failed'),
          ResourceFilterOption('Reembolsado', 'refunded'),
          ResourceFilterOption('Cancelado', 'cancelled'),
        ],
      ),
      ResourceFormField(key: 'reference', label: 'Referencia'),
      ResourceFormField(key: 'license_id', label: 'Licencia ID'),
      ResourceFormField(
        key: 'notes',
        label: 'Notas',
        type: ResourceFormFieldType.multiline,
      ),
    ],
  ),
  searchKeys: [
    'company_name',
    'product_name',
    'reference',
    'status',
    'paypal_order_id',
    'paypal_capture_id',
    'paypal_subscription_id',
  ],
  fields: [
    ResourceField('company_name', 'Compañía'),
    ResourceField('product_name', 'Producto'),
    ResourceField('amount', 'Monto'),
    ResourceField('status', 'Estado', badge: true),
    ResourceField('payment_method', 'Método'),
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
    ResourceField('payment_method', 'Método'),
    ResourceField('reference', 'Referencia'),
    ResourceField('paypal_order_id', 'PayPal Order ID'),
    ResourceField('paypal_capture_id', 'PayPal Capture/Sale ID'),
    ResourceField('paypal_subscription_id', 'PayPal Subscription ID'),
    ResourceField('subscription_status', 'Estado suscripción'),
    ResourceField('license_key', 'Licencia'),
    ResourceField('paid_at', 'Pagado'),
    ResourceField('recorded_at', 'Registrado'),
  ],
);

const activationResourceConfig = CloudResourceConfig(
  title: 'Activaciones',
  icon: Icons.devices_other_outlined,
  endpoint: '/api/admin/activations',
  listKey: 'activations',
  filterParam: 'status',
  filterOptions: [
    ResourceFilterOption('Todas', null),
    ResourceFilterOption('Activas', 'ACTIVE'),
    ResourceFilterOption('Bloqueadas', 'BLOCKED'),
    ResourceFilterOption('Revocadas', 'REVOKED'),
  ],
  searchKeys: [
    'customer_name',
    'license_key',
    'device_id',
    'device_name',
    'device_type',
    'status',
    'ip_address',
  ],
  fields: [
    ResourceField('customer_name', 'Cliente'),
    ResourceField('license_key', 'Licencia'),
    ResourceField('device_name', 'Dispositivo'),
    ResourceField('created_at', 'Fecha activación'),
    ResourceField('last_seen_at', 'Última conexión'),
    ResourceField('status', 'Estado', badge: true),
    ResourceField('ip_address', 'IP'),
  ],
  detailFields: [
    ResourceField('id', 'ID'),
    ResourceField('customer_name', 'Cliente'),
    ResourceField('customer_email', 'Email cliente'),
    ResourceField('license_id', 'Licencia ID'),
    ResourceField('license_key', 'Licencia'),
    ResourceField('device_id', 'Dispositivo'),
    ResourceField('device_name', 'Nombre dispositivo'),
    ResourceField('device_type', 'Tipo dispositivo'),
    ResourceField('ip_address', 'IP'),
    ResourceField('status', 'Estado'),
    ResourceField('license_status', 'Estado licencia'),
    ResourceField('subscription_status', 'Estado suscripción'),
    ResourceField('plan_name', 'Plan'),
    ResourceField('created_at', 'Fecha activación'),
    ResourceField('last_seen_at', 'Última conexión'),
  ],
  rowActions: [
    ResourceAction(
      label: 'Bloquear',
      icon: Icons.lock_outline_rounded,
      method: ResourceActionMethod.post,
      path: '/api/admin/activations/:id/block',
      destructive: true,
    ),
    ResourceAction(
      label: 'Revocar',
      icon: Icons.block_rounded,
      method: ResourceActionMethod.post,
      path: '/api/admin/activations/:id/revoke',
      destructive: true,
    ),
  ],
);

const projectResourceConfig = CloudResourceConfig(
  title: 'Proyectos',
  icon: Icons.folder_copy_outlined,
  endpoint: '/api/admin/projects',
  listKey: 'projects',
  searchKeys: ['code', 'name', 'description'],
  fields: [
    ResourceField('code', 'Código'),
    ResourceField('name', 'Nombre'),
    ResourceField('description', 'Descripción'),
    ResourceField('created_at', 'Creado'),
  ],
  detailFields: [
    ResourceField('id', 'ID'),
    ResourceField('code', 'Código'),
    ResourceField('name', 'Nombre'),
    ResourceField('description', 'Descripción'),
    ResourceField('created_at', 'Creado'),
    ResourceField('updated_at', 'Actualizado'),
  ],
  createAction: ResourceAction(
    label: 'Crear proyecto',
    icon: Icons.create_new_folder_outlined,
    method: ResourceActionMethod.post,
    path: '/api/admin/projects',
    fields: [
      ResourceFormField(key: 'code', label: 'Código', required: true),
      ResourceFormField(key: 'name', label: 'Nombre', required: true),
      ResourceFormField(
        key: 'description',
        label: 'Descripción',
        type: ResourceFormFieldType.multiline,
      ),
    ],
  ),
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
  createAction: ResourceAction(
    label: 'Crear usuario',
    icon: Icons.person_add_alt_rounded,
    method: ResourceActionMethod.post,
    path: '/api/admin/platform-users',
    fields: [
      ResourceFormField(key: 'email', label: 'Email', required: true),
      ResourceFormField(key: 'display_name', label: 'Nombre'),
      ResourceFormField(key: 'phone', label: 'Teléfono'),
      ResourceFormField(
        key: 'user_type',
        label: 'Tipo',
        type: ResourceFormFieldType.select,
        defaultValue: 'admin',
        options: [
          ResourceFilterOption('Admin', 'admin'),
          ResourceFilterOption('Operador', 'operator'),
          ResourceFilterOption('Soporte', 'support'),
        ],
      ),
      ResourceFormField(
        key: 'status',
        label: 'Estado',
        type: ResourceFormFieldType.select,
        defaultValue: 'active',
        options: [
          ResourceFilterOption('Activo', 'active'),
          ResourceFilterOption('Invitado', 'invited'),
          ResourceFilterOption('Suspendido', 'suspended'),
        ],
      ),
    ],
  ),
  rowActions: [
    ResourceAction(
      label: 'Asignar rol',
      icon: Icons.verified_user_outlined,
      method: ResourceActionMethod.post,
      path: '/api/admin/platform-users/:id/roles',
      fields: [
        ResourceFormField(key: 'role_id', label: 'Rol ID', required: true),
        ResourceFormField(key: 'company_id', label: 'Compañía ID'),
      ],
    ),
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
