class UsageOverview {
  final int activeToday;
  final int active7Days;
  final int inactive15Days;
  final int inactive30Days;
  final int activeSeconds;
  final int eventsCount;
  final int sessionsCount;
  final int devicesCount;

  const UsageOverview({
    required this.activeToday,
    required this.active7Days,
    required this.inactive15Days,
    required this.inactive30Days,
    required this.activeSeconds,
    required this.eventsCount,
    required this.sessionsCount,
    required this.devicesCount,
  });

  factory UsageOverview.fromJson(Map<String, dynamic> json) {
    return UsageOverview(
      activeToday: _int(json['active_today']),
      active7Days: _int(json['active_7_days']),
      inactive15Days: _int(json['inactive_15_days']),
      inactive30Days: _int(json['inactive_30_days']),
      activeSeconds: _int(json['active_seconds']),
      eventsCount: _int(json['events_count']),
      sessionsCount: _int(json['sessions_count']),
      devicesCount: _int(json['devices_count']),
    );
  }

  static const empty = UsageOverview(
    activeToday: 0,
    active7Days: 0,
    inactive15Days: 0,
    inactive30Days: 0,
    activeSeconds: 0,
    eventsCount: 0,
    sessionsCount: 0,
    devicesCount: 0,
  );
}

class UsageAccount {
  final String? licenseId;
  final String? licenseKey;
  final String? licenseStatus;
  final DateTime? licenseExpiresAt;
  final String? customerId;
  final String? businessId;
  final String customerName;
  final String? customerEmail;
  final String? projectId;
  final String? projectCode;
  final String? projectName;
  final String appCode;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;
  final String? appVersion;
  final int activeSeconds;
  final int sessionsCount;
  final int eventsCount;
  final int devicesCount;
  final String usageStatus;
  final Map<String, dynamic> metrics;

  const UsageAccount({
    required this.customerName,
    required this.appCode,
    required this.activeSeconds,
    required this.sessionsCount,
    required this.eventsCount,
    required this.devicesCount,
    required this.usageStatus,
    this.metrics = const {},
    this.licenseId,
    this.licenseKey,
    this.licenseStatus,
    this.licenseExpiresAt,
    this.customerId,
    this.businessId,
    this.customerEmail,
    this.projectId,
    this.projectCode,
    this.projectName,
    this.firstSeenAt,
    this.lastSeenAt,
    this.appVersion,
  });

  factory UsageAccount.fromJson(Map<String, dynamic> json) {
    return UsageAccount(
      licenseId: _string(json['license_id']),
      licenseKey: _string(json['license_key']),
      licenseStatus: _string(json['license_status']),
      licenseExpiresAt: _date(json['license_expires_at']),
      customerId: _string(json['customer_id']),
      businessId: _string(json['business_id']),
      customerName: _string(json['customer_name']) ?? 'Cliente sin nombre',
      customerEmail: _string(json['customer_email']),
      projectId: _string(json['project_id']),
      projectCode: _string(json['project_code']),
      projectName: _string(json['project_name']),
      appCode: _string(json['app_code']) ?? 'UNKNOWN',
      firstSeenAt: _date(json['first_seen_at']),
      lastSeenAt: _date(json['last_seen_at']),
      appVersion: _string(json['app_version']),
      activeSeconds: _int(json['active_seconds']),
      sessionsCount: _int(json['sessions_count']),
      eventsCount: _int(json['events_count']),
      devicesCount: _int(json['devices_count']),
      usageStatus: _string(json['usage_status']) ?? 'NEVER_USED',
      metrics: _map(json['last_metrics'] ?? json['metrics']),
    );
  }

  String? metricString(String key) {
    final value = metrics[key];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  int metricInt(String key) => _int(metrics[key]);

  String get statusLabel {
    switch (usageStatus) {
      case 'USING_NOW':
        return 'Usando ahora';
      case 'ACTIVE_TODAY':
        return 'Activo hoy';
      case 'ACTIVE_WEEK':
        return 'Activo semana';
      case 'ACTIVE_RECENT':
        return 'Activo reciente';
      case 'INACTIVE_15_DAYS':
        return 'Inactivo 15 dias';
      case 'INACTIVE_30_DAYS':
        return 'Inactivo 30 dias';
      case 'NEVER_USED':
        return 'Nunca usado';
      default:
        return usageStatus;
    }
  }

  bool get isRisk =>
      usageStatus == 'INACTIVE_15_DAYS' ||
      usageStatus == 'INACTIVE_30_DAYS' ||
      usageStatus == 'NEVER_USED';
}

class UsageAccountsResult {
  final int page;
  final int limit;
  final int total;
  final List<UsageAccount> accounts;

  const UsageAccountsResult({
    required this.page,
    required this.limit,
    required this.total,
    required this.accounts,
  });
}

class UsageDashboardData {
  final UsageOverview overview;
  final UsageAccountsResult accounts;

  const UsageDashboardData({required this.overview, required this.accounts});
}

int _int(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

String? _string(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
