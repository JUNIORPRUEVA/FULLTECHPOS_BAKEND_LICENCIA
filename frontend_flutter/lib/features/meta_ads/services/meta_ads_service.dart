import '../../../core/api/api_client.dart';
import '../../../core/auth/session_manager.dart';

class MetaAdsConfig {
  final String adAccountId;
  final String whatsappPhoneNumberId;
  final String whatsappBusinessAccountId;
  final String adsAppId;
  final String adsAccessTokenMasked;
  final String adsAppSecretMasked;
  final bool hasAdsAccessToken;
  final bool hasAdsAppSecret;

  const MetaAdsConfig({
    this.adAccountId = '',
    this.whatsappPhoneNumberId = '',
    this.whatsappBusinessAccountId = '',
    this.adsAppId = '',
    this.adsAccessTokenMasked = '',
    this.adsAppSecretMasked = '',
    this.hasAdsAccessToken = false,
    this.hasAdsAppSecret = false,
  });

  factory MetaAdsConfig.fromJson(Map<String, dynamic> json) {
    return MetaAdsConfig(
      adAccountId: (json['ad_account_id'] ?? '').toString(),
      whatsappPhoneNumberId: (json['whatsapp_phone_number_id'] ?? '')
          .toString(),
      whatsappBusinessAccountId: (json['whatsapp_business_account_id'] ?? '')
          .toString(),
      adsAppId: (json['ads_app_id'] ?? '').toString(),
      adsAccessTokenMasked: (json['ads_access_token_masked'] ?? '').toString(),
      adsAppSecretMasked: (json['ads_app_secret_masked'] ?? '').toString(),
      hasAdsAccessToken: json['has_ads_access_token'] == true,
      hasAdsAppSecret: json['has_ads_app_secret'] == true,
    );
  }
}

class MetaAdsCheckItem {
  final String key;
  final bool ok;
  final String details;

  const MetaAdsCheckItem({
    required this.key,
    required this.ok,
    required this.details,
  });

  factory MetaAdsCheckItem.fromJson(Map<String, dynamic> json) {
    return MetaAdsCheckItem(
      key: (json['key'] ?? '').toString(),
      ok: json['ok'] == true,
      details: (json['details'] ?? '').toString(),
    );
  }
}

class MetaAdsCheckResult {
  final bool ok;
  final String tokenSource;
  final String tokenMasked;
  final List<MetaAdsCheckItem> checks;
  final List<String> warnings;

  const MetaAdsCheckResult({
    required this.ok,
    required this.tokenSource,
    required this.tokenMasked,
    required this.checks,
    required this.warnings,
  });

  factory MetaAdsCheckResult.fromJson(Map<String, dynamic> json) {
    final checksRaw = json['checks'] as List<dynamic>? ?? const [];
    final warningsRaw = json['warnings'] as List<dynamic>? ?? const [];
    return MetaAdsCheckResult(
      ok: json['ok'] == true,
      tokenSource: (json['token_source'] ?? '').toString(),
      tokenMasked: (json['token_masked'] ?? '').toString(),
      checks: checksRaw
          .whereType<Map<String, dynamic>>()
          .map(MetaAdsCheckItem.fromJson)
          .toList(),
      warnings: warningsRaw.map((e) => e.toString()).toList(),
    );
  }
}

class MetaAdsService {
  final ApiClient _client;

  MetaAdsService({required SessionManager sessionManager})
    : _client = ApiClient(sessionManager: sessionManager);

  Future<MetaAdsConfig> getConfig() async {
    final data = await _client.get('/api/admin/meta-ads/config');
    final config = data['config'] as Map<String, dynamic>? ?? data;
    return MetaAdsConfig.fromJson(config);
  }

  Future<MetaAdsConfig> updateConfig(Map<String, dynamic> payload) async {
    final data = await _client.put('/api/admin/meta-ads/config', payload);
    final config = data['config'] as Map<String, dynamic>? ?? data;
    return MetaAdsConfig.fromJson(config);
  }

  Future<MetaAdsCheckResult> testConnection() async {
    final data = await _client.post('/api/admin/meta-ads/test-connection', {});
    return MetaAdsCheckResult.fromJson(data);
  }

  Future<Map<String, dynamic>> createCampaign(Map<String, dynamic> payload) {
    return _client.post('/api/admin/meta-ads/campaigns', payload);
  }
}
