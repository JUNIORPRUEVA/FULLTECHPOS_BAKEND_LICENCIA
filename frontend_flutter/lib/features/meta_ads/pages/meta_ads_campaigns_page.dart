import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_view.dart';
import '../services/meta_ads_service.dart';

class MetaAdsCampaignsPage extends StatefulWidget {
  const MetaAdsCampaignsPage({super.key});

  @override
  State<MetaAdsCampaignsPage> createState() => _MetaAdsCampaignsPageState();
}

class _MetaAdsCampaignsPageState extends State<MetaAdsCampaignsPage> {
  late final MetaAdsService _service;
  late Future<MetaAdsConfig> _future;

  final _campaignNameCtrl = TextEditingController();
  final _messageCtrl = TextEditingController(
    text: 'Escribenos por WhatsApp para mas informacion.',
  );
  final _budgetCtrl = TextEditingController(text: '500');
  final _countriesCtrl = TextEditingController(text: 'DO');
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _service = MetaAdsService(sessionManager: context.read<SessionManager>());
    _future = _service.getConfig();
  }

  @override
  void dispose() {
    _campaignNameCtrl.dispose();
    _messageCtrl.dispose();
    _budgetCtrl.dispose();
    _countriesCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = _service.getConfig();
    });
  }

  Future<void> _openConfigDialog(MetaAdsConfig config) async {
    final tokenCtrl = TextEditingController();
    final adAccountCtrl = TextEditingController(text: config.adAccountId);
    final phoneCtrl = TextEditingController(text: config.whatsappPhoneNumberId);
    final wabaCtrl = TextEditingController(
      text: config.whatsappBusinessAccountId,
    );
    final appIdCtrl = TextEditingController(text: config.adsAppId);
    final appSecretCtrl = TextEditingController();

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          var saving = false;
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              return AlertDialog(
                title: const Text('Configuracion Meta Ads'),
                content: SingleChildScrollView(
                  child: SizedBox(
                    width: 520,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DialogField(
                          label: 'Token Meta Ads',
                          controller: tokenCtrl,
                          hint: 'Pega aqui el nuevo token',
                          obscureText: true,
                        ),
                        _DialogField(
                          label: 'Ad Account ID',
                          controller: adAccountCtrl,
                          hint: 'act_123456789',
                        ),
                        _DialogField(
                          label: 'WhatsApp Phone Number ID',
                          controller: phoneCtrl,
                        ),
                        _DialogField(
                          label: 'WhatsApp Business Account ID',
                          controller: wabaCtrl,
                        ),
                        _DialogField(label: 'App ID', controller: appIdCtrl),
                        _DialogField(
                          label: 'App Secret',
                          controller: appSecretCtrl,
                          hint: 'Pega aqui el nuevo secret',
                          obscureText: true,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Seguridad: los tokens se guardan en backend y solo se muestran enmascarados.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            setDialogState(() => saving = true);
                            try {
                              await _service.updateConfig({
                                if (tokenCtrl.text.trim().isNotEmpty)
                                  'meta_ads_access_token': tokenCtrl.text
                                      .trim(),
                                'meta_ad_account_id': adAccountCtrl.text.trim(),
                                'meta_whatsapp_phone_number_id': phoneCtrl.text
                                    .trim(),
                                'meta_whatsapp_business_account_id': wabaCtrl
                                    .text
                                    .trim(),
                                'meta_ads_app_id': appIdCtrl.text.trim(),
                                if (appSecretCtrl.text.trim().isNotEmpty)
                                  'meta_ads_app_secret': appSecretCtrl.text
                                      .trim(),
                              });
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (error) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('Error: $error')),
                                );
                                setDialogState(() => saving = false);
                              }
                            }
                          },
                    child: Text(saving ? 'Guardando...' : 'Guardar'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (saved == true) {
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Configuracion Meta Ads guardada')),
          );
        }
      }
    } finally {
      tokenCtrl.dispose();
      adAccountCtrl.dispose();
      phoneCtrl.dispose();
      wabaCtrl.dispose();
      appIdCtrl.dispose();
      appSecretCtrl.dispose();
    }
  }

  Future<void> _testConnection() async {
    try {
      final result = await _service.testConnection();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Resultado: Probar conexion Meta Ads'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.ok
                        ? 'Conexion general: OK'
                        : 'Conexion general: con errores',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: result.ok ? AppColors.success : AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Token usado: ${result.tokenMasked}'),
                  const SizedBox(height: 12),
                  for (final check in result.checks)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            check.ok
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: check.ok
                                ? AppColors.success
                                : AppColors.error,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${check.key}: ${check.details}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (result.warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Warnings',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    for (final warning in result.warnings)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '- $warning',
                          style: const TextStyle(color: AppColors.warning),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    }
  }

  Future<void> _createCampaign(MetaAdsConfig config) async {
    setState(() => _creating = true);
    try {
      final countries = _countriesCtrl.text
          .split(',')
          .map((e) => e.trim().toUpperCase())
          .where((e) => e.isNotEmpty)
          .toList();

      final result = await _service.createCampaign({
        'name': _campaignNameCtrl.text.trim(),
        'message': _messageCtrl.text.trim(),
        'daily_budget': int.tryParse(_budgetCtrl.text.trim()) ?? 500,
        'countries': countries,
        'ad_account_id': config.adAccountId,
        'whatsapp_phone_number_id': config.whatsappPhoneNumberId,
      });

      if (!mounted) return;
      final warnings = (result['warnings'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList();

      final campaignId =
          ((result['campaign'] as Map<String, dynamic>? ?? const {})['id'] ??
                  '')
              .toString();
      final adsetId =
          ((result['adset'] as Map<String, dynamic>? ?? const {})['id'] ?? '')
              .toString();
      final creativeId =
          ((result['creative'] as Map<String, dynamic>? ?? const {})['id'] ??
                  '')
              .toString();
      final adId =
          ((result['ad'] as Map<String, dynamic>? ?? const {})['id'] ?? '')
              .toString();

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Campana creada'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Campaign ID: $campaignId'),
                Text('Ad Set ID: $adsetId'),
                Text('Creative ID: $creativeId'),
                Text('Ad ID: $adId'),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Warnings:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final warning in warnings) Text('- $warning'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creando campana: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<MetaAdsConfig>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingView(message: 'Cargando Meta Ads...');
          }
          if (snapshot.hasError) {
            return ErrorView(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final config = snapshot.data ?? const MetaAdsConfig();
          final tokenStatus = config.hasAdsAccessToken
              ? 'Meta Ads configurado ✅'
              : 'Meta Ads faltante ⚠️';

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Publicidad / Campanas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text('Destino: WhatsApp FullTech'),
                    const SizedBox(height: 2),
                    const Text('Numero: +1 829-534-4286'),
                    const SizedBox(height: 2),
                    Text('Token: $tokenStatus'),
                    if (config.adsAccessTokenMasked.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Token enmascarado: ${config.adsAccessTokenMasked}'),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _openConfigDialog(config),
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          label: const Text('Configuracion Meta Ads'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _testConnection,
                          icon: const Icon(
                            Icons.health_and_safety_outlined,
                            size: 18,
                          ),
                          label: const Text('Probar conexion Meta Ads'),
                        ),
                        IconButton(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Actualizar',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Crear campana real',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _FormField(label: 'Nombre', controller: _campaignNameCtrl),
                    _FormField(label: 'Mensaje', controller: _messageCtrl),
                    _FormField(
                      label: 'Presupuesto diario (minor units)',
                      controller: _budgetCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    _FormField(
                      label: 'Paises (CSV)',
                      controller: _countriesCtrl,
                      hint: 'DO,US',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _creating
                            ? null
                            : () => _createCampaign(config),
                        icon: _creating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.campaign_outlined, size: 18),
                        label: Text(_creating ? 'Creando...' : 'Crear campana'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Regla: publicaciones organicas usan META_ACCESS_TOKEN, campanas usan META_ADS_ACCESS_TOKEN (prioridad).',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscureText;

  const _DialogField({
    required this.label,
    required this.controller,
    this.hint,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            obscureText: obscureText,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? hint;

  const _FormField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
