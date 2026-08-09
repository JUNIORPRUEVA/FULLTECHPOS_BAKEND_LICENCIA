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
  final DateTime? periodStartedAt;
  final DateTime? periodEndsAt;
  final String? licenseType;
  final String? licenseTypeLabel;
  final String? licenseKey;
  final String? notes;
  final int daysRemaining;
  final int maxUsers;
  final int maxProducts;
  final int usersUsed;
  final int productsUsed;
  final DaleVentasAccountInfo account;
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
    this.account = const DaleVentasAccountInfo(),
    this.slug,
    this.plan,
    this.rawStatus,
    this.blockReason,
    this.trialStartedAt,
    this.trialEndsAt,
    this.licenseActivatedAt,
    this.licenseExpiresAt,
    this.licenseBlockedAt,
    this.periodStartedAt,
    this.periodEndsAt,
    this.licenseType,
    this.licenseTypeLabel,
    this.licenseKey,
    this.notes,
    this.auditLogs = const [],
  });

  factory DaleVentasCompanyLicense.fromJson(Map<String, dynamic> json) {
    final limits = json['limits'] as Map<String, dynamic>? ?? const {};
    final usage = json['usage'] as Map<String, dynamic>? ?? const {};
    final account = json['account'] as Map<String, dynamic>? ?? const {};
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
      periodStartedAt: _date(json['periodStartedAt']),
      periodEndsAt: _date(json['periodEndsAt']),
      licenseType: json['licenseType']?.toString(),
      licenseTypeLabel: json['licenseTypeLabel']?.toString(),
      licenseKey: json['licenseKey']?.toString(),
      notes: json['notes']?.toString(),
      daysRemaining: _int(json['daysRemaining']),
      maxUsers: _int(limits['maxUsers'], fallback: 2),
      maxProducts: _int(limits['maxProducts'], fallback: 100),
      usersUsed: _int(usage['users']),
      productsUsed: _int(usage['products']),
      account: DaleVentasAccountInfo.fromJson(account),
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
      account: account,
      slug: slug,
      plan: plan,
      rawStatus: rawStatus,
      blockReason: blockReason,
      trialStartedAt: trialStartedAt,
      trialEndsAt: trialEndsAt,
      licenseActivatedAt: licenseActivatedAt,
      licenseExpiresAt: licenseExpiresAt ?? this.licenseExpiresAt,
      licenseBlockedAt: licenseBlockedAt,
      periodStartedAt: periodStartedAt,
      periodEndsAt: periodEndsAt,
      licenseType: licenseType,
      licenseTypeLabel: licenseTypeLabel,
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
  String get planCode {
    final cleaned = (plan ?? '').trim().toUpperCase();
    if (cleaned == 'ENTERPRISE') return 'ENTERPRISE';
    return 'STANDARD';
  }

  String get planLabel {
    final label = licenseTypeLabel?.trim();
    if (label != null && label.isNotEmpty && !isTrial) return label;
    if (isTrial) return 'Prueba gratis';
    if (planCode == 'ENTERPRISE') return 'Plan enterprise';
    if (maxUsers > 2 || maxProducts > 100) return 'Plan basico ampliado';
    return 'Plan basico';
  }

  String get policyLabel =>
      '${isTrial ? '7 dias gratis · ' : ''}$maxUsers usuarios · $maxProducts productos';

  DateTime? get startsAt =>
      periodStartedAt ?? licenseActivatedAt ?? trialStartedAt;

  DateTime? get endsAt {
    if (periodEndsAt != null) return periodEndsAt;
    if (isTrial) return trialEndsAt;
    return licenseExpiresAt;
  }
}

class DaleVentasAccountInfo {
  final String? businessName;
  final String? taxId;
  final String? businessPhone;
  final String? businessAddress;
  final String? businessType;
  final String? responsibleName;
  final String? responsibleEmail;
  final String? responsibleWhatsapp;
  final String? responsibleUserId;

  const DaleVentasAccountInfo({
    this.businessName,
    this.taxId,
    this.businessPhone,
    this.businessAddress,
    this.businessType,
    this.responsibleName,
    this.responsibleEmail,
    this.responsibleWhatsapp,
    this.responsibleUserId,
  });

  factory DaleVentasAccountInfo.fromJson(Map<String, dynamic> json) {
    return DaleVentasAccountInfo(
      businessName: _string(json['businessName']),
      taxId: _string(json['taxId']),
      businessPhone: _string(json['businessPhone']),
      businessAddress: _string(json['businessAddress']),
      businessType: _string(json['businessType']),
      responsibleName: _string(json['responsibleName']),
      responsibleEmail: _string(json['responsibleEmail']),
      responsibleWhatsapp: _string(json['responsibleWhatsapp']),
      responsibleUserId: _string(json['responsibleUserId']),
    );
  }
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

String? _string(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
