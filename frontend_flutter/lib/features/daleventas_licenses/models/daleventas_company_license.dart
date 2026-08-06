class DaleVentasCompanyLicense {
  final String companyId;
  final String companyName;
  final String? slug;
  final String? plan;
  final String status;
  final String? rawStatus;
  final bool isUsable;
  final String? blockReason;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final DateTime? licenseActivatedAt;
  final DateTime? licenseExpiresAt;
  final DateTime? licenseBlockedAt;
  final String? licenseKey;
  final String? notes;
  final int daysRemaining;
  final int maxUsers;
  final int maxProducts;
  final int usersUsed;
  final int productsUsed;
  final List<DaleVentasLicenseAuditLog> auditLogs;

  const DaleVentasCompanyLicense({
    required this.companyId,
    required this.companyName,
    required this.status,
    required this.isUsable,
    required this.daysRemaining,
    required this.maxUsers,
    required this.maxProducts,
    required this.usersUsed,
    required this.productsUsed,
    this.slug,
    this.plan,
    this.rawStatus,
    this.blockReason,
    this.trialStartedAt,
    this.trialEndsAt,
    this.licenseActivatedAt,
    this.licenseExpiresAt,
    this.licenseBlockedAt,
    this.licenseKey,
    this.notes,
    this.auditLogs = const [],
  });

  factory DaleVentasCompanyLicense.fromJson(Map<String, dynamic> json) {
    final limits = json['limits'] as Map<String, dynamic>? ?? const {};
    final usage = json['usage'] as Map<String, dynamic>? ?? const {};
    final logs = json['auditLogs'] as List<dynamic>? ?? const [];

    return DaleVentasCompanyLicense(
      companyId: json['companyId']?.toString() ?? '',
      companyName: json['companyName']?.toString() ?? 'Empresa sin nombre',
      slug: json['slug']?.toString(),
      plan: json['plan']?.toString(),
      status: (json['status']?.toString() ?? 'TRIAL').toUpperCase(),
      rawStatus: json['rawStatus']?.toString(),
      isUsable: json['isUsable'] == true,
      blockReason: json['blockReason']?.toString(),
      trialStartedAt: _date(json['trialStartedAt']),
      trialEndsAt: _date(json['trialEndsAt']),
      licenseActivatedAt: _date(json['licenseActivatedAt']),
      licenseExpiresAt: _date(json['licenseExpiresAt']),
      licenseBlockedAt: _date(json['licenseBlockedAt']),
      licenseKey: json['licenseKey']?.toString(),
      notes: json['notes']?.toString(),
      daysRemaining: _int(json['daysRemaining']),
      maxUsers: _int(limits['maxUsers'], fallback: 2),
      maxProducts: _int(limits['maxProducts'], fallback: 100),
      usersUsed: _int(usage['users']),
      productsUsed: _int(usage['products']),
      auditLogs: logs
          .whereType<Map<String, dynamic>>()
          .map(DaleVentasLicenseAuditLog.fromJson)
          .toList(),
    );
  }

  DaleVentasCompanyLicense copyWith({
    int? maxUsers,
    int? maxProducts,
    String? notes,
    DateTime? licenseExpiresAt,
    String? licenseKey,
  }) {
    return DaleVentasCompanyLicense(
      companyId: companyId,
      companyName: companyName,
      status: status,
      isUsable: isUsable,
      daysRemaining: daysRemaining,
      maxUsers: maxUsers ?? this.maxUsers,
      maxProducts: maxProducts ?? this.maxProducts,
      usersUsed: usersUsed,
      productsUsed: productsUsed,
      slug: slug,
      plan: plan,
      rawStatus: rawStatus,
      blockReason: blockReason,
      trialStartedAt: trialStartedAt,
      trialEndsAt: trialEndsAt,
      licenseActivatedAt: licenseActivatedAt,
      licenseExpiresAt: licenseExpiresAt ?? this.licenseExpiresAt,
      licenseBlockedAt: licenseBlockedAt,
      licenseKey: licenseKey ?? this.licenseKey,
      notes: notes ?? this.notes,
      auditLogs: auditLogs,
    );
  }

  double get usersRatio =>
      maxUsers <= 0 ? 0 : (usersUsed / maxUsers).clamp(0, 1);
  double get productsRatio =>
      maxProducts <= 0 ? 0 : (productsUsed / maxProducts).clamp(0, 1);
  bool get isBlocked => status == 'BLOCKED';
  bool get isExpired => status == 'EXPIRED';
  bool get isTrial => status == 'TRIAL';
  bool get isActive => status == 'ACTIVE';
  String get planLabel => (plan ?? '').trim().isEmpty ? 'Plan basico' : plan!;
  String get policyLabel => '7 dias gratis · 2 usuarios · 100 productos';
}

class DaleVentasLicenseAuditLog {
  final String id;
  final String action;
  final String? actorEmail;
  final String? reason;
  final DateTime? createdAt;

  const DaleVentasLicenseAuditLog({
    required this.id,
    required this.action,
    this.actorEmail,
    this.reason,
    this.createdAt,
  });

  factory DaleVentasLicenseAuditLog.fromJson(Map<String, dynamic> json) {
    return DaleVentasLicenseAuditLog(
      id: json['id']?.toString() ?? '',
      action: json['action']?.toString() ?? 'license.update',
      actorEmail: json['actorEmail']?.toString(),
      reason: json['reason']?.toString(),
      createdAt: _date(json['createdAt']),
    );
  }
}

DateTime? _date(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int _int(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  return int.tryParse(value.toString()) ?? fallback;
}
