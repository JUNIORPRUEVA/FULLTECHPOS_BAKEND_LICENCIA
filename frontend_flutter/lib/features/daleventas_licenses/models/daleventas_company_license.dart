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
  final DaleVentasCommercialProfile? commercial;
  final DaleVentasEffectiveEntitlements? effectiveEntitlements;

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
    this.commercial,
    this.effectiveEntitlements,
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
    final commercial = json['commercial'] as Map<String, dynamic>?;
    final effectiveEntitlements =
        json['effectiveEntitlements'] as Map<String, dynamic>?;

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
      commercial: commercial == null
          ? null
          : DaleVentasCommercialProfile.fromJson(commercial),
      effectiveEntitlements: effectiveEntitlements == null
          ? null
          : DaleVentasEffectiveEntitlements.fromJson(effectiveEntitlements),
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
      commercial: commercial,
      effectiveEntitlements: effectiveEntitlements,
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
    final commercialCode = commercialPlanCode;
    if (commercialCode == 'BASIC' ||
        commercialCode == 'BUSINESS' ||
        commercialCode == 'PRO') {
      return commercialCode;
    }
    final cleaned = (plan ?? '').trim().toUpperCase();
    if (cleaned == 'ENTERPRISE') return 'ENTERPRISE';
    return 'STANDARD';
  }

  String get commercialPlanCode {
    final snapshot = commercial?.planCodeSnapshot?.trim().toUpperCase() ?? '';
    if (snapshot.isNotEmpty) return snapshot;
    final classification =
        commercial?.planClassification.trim().toUpperCase() ?? '';
    if (classification == 'CUSTOM') return 'CUSTOM';
    return 'LEGACY';
  }

  String get commercialPlanLabel {
    final snapshot = commercial?.planNameSnapshot?.trim();
    if (snapshot != null && snapshot.isNotEmpty) return snapshot;
    switch (commercialPlanCode) {
      case 'BASIC':
        return 'Básico';
      case 'BUSINESS':
        return 'Negocio';
      case 'PRO':
        return 'Pro';
      case 'CUSTOM':
        return 'Custom';
      default:
        return 'Legacy/Custom';
    }
  }

  String get commercialStatusLabel {
    switch ((commercial?.commercialStatus ?? 'DEMO').toUpperCase()) {
      case 'CONTACTED':
        return 'Contactado';
      case 'INTERESTED':
        return 'Interesado';
      case 'PURCHASED':
        return 'Compró';
      case 'ACTIVE_CUSTOMER':
        return 'Cliente activo';
      case 'RENEWAL_DUE':
        return 'Por renovar';
      case 'EXPIRED':
        return 'Vencido';
      case 'LOST':
        return 'Perdido';
      default:
        return 'Demo';
    }
  }

  bool get hasCommercialOverride =>
      commercial?.overrideExpirationDate != null ||
      commercial?.overrideExtraDays != null ||
      commercial?.overrideMaxUsers != null ||
      commercial?.overrideMaxProducts != null ||
      commercial?.overrideMaxWarehouses != null ||
      commercial?.overrideMaxDevices != null;

  String get planLabel {
    if (commercial != null) return commercialPlanLabel;
    final label = licenseTypeLabel?.trim();
    if (label != null && label.isNotEmpty && !isTrial) return label;
    if (isTrial) return 'Plan demo';
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

class DaleVentasCommercialProfile {
  final String id;
  final String externalCompanyId;
  final String commercialStatus;
  final String planClassification;
  final String? planCodeSnapshot;
  final String? planNameSnapshot;
  final String? currencySnapshot;
  final String? monthlyEquivalentPriceSnapshot;
  final int? minimumBillingMonthsSnapshot;
  final String? minimumPaymentSnapshot;
  final DateTime? planAssignedAt;
  final DateTime? overrideExpirationDate;
  final int? overrideExtraDays;
  final int? overrideMaxUsers;
  final int? overrideMaxProducts;
  final int? overrideMaxWarehouses;
  final int? overrideMaxDevices;
  final String? overrideNotes;
  final String? leadSource;
  final DateTime? nextFollowUpAt;
  final String? commercialNotes;

  const DaleVentasCommercialProfile({
    required this.id,
    required this.externalCompanyId,
    required this.commercialStatus,
    required this.planClassification,
    this.planCodeSnapshot,
    this.planNameSnapshot,
    this.currencySnapshot,
    this.monthlyEquivalentPriceSnapshot,
    this.minimumBillingMonthsSnapshot,
    this.minimumPaymentSnapshot,
    this.planAssignedAt,
    this.overrideExpirationDate,
    this.overrideExtraDays,
    this.overrideMaxUsers,
    this.overrideMaxProducts,
    this.overrideMaxWarehouses,
    this.overrideMaxDevices,
    this.overrideNotes,
    this.leadSource,
    this.nextFollowUpAt,
    this.commercialNotes,
  });

  factory DaleVentasCommercialProfile.fromJson(Map<String, dynamic> json) {
    return DaleVentasCommercialProfile(
      id: json['id']?.toString() ?? '',
      externalCompanyId: json['external_company_id']?.toString() ?? '',
      commercialStatus:
          json['commercial_status']?.toString().toUpperCase() ?? 'DEMO',
      planClassification:
          json['plan_classification']?.toString().toUpperCase() ?? 'LEGACY',
      planCodeSnapshot: _string(json['plan_code_snapshot']),
      planNameSnapshot: _string(json['plan_name_snapshot']),
      currencySnapshot: _string(json['currency_snapshot']),
      monthlyEquivalentPriceSnapshot: _string(
        json['monthly_equivalent_price_snapshot'],
      ),
      minimumBillingMonthsSnapshot: _nullableInt(
        json['minimum_billing_months_snapshot'],
      ),
      minimumPaymentSnapshot: _string(json['minimum_payment_snapshot']),
      planAssignedAt: _date(json['plan_assigned_at']),
      overrideExpirationDate: _date(json['override_expiration_date']),
      overrideExtraDays: _nullableInt(json['override_extra_days']),
      overrideMaxUsers: _nullableInt(json['override_max_users']),
      overrideMaxProducts: _nullableInt(json['override_max_products']),
      overrideMaxWarehouses: _nullableInt(json['override_max_warehouses']),
      overrideMaxDevices: _nullableInt(json['override_max_devices']),
      overrideNotes: _string(json['override_notes']),
      leadSource: _string(json['lead_source']),
      nextFollowUpAt: _date(json['next_follow_up_at']),
      commercialNotes: _string(json['commercial_notes']),
    );
  }
}

class DaleVentasEffectiveEntitlements {
  final int? maxUsers;
  final int? maxProducts;
  final int? maxWarehouses;
  final int? maxDevices;
  final DateTime? expirationDate;
  final int? extraDays;
  final Map<String, String> sources;

  const DaleVentasEffectiveEntitlements({
    this.maxUsers,
    this.maxProducts,
    this.maxWarehouses,
    this.maxDevices,
    this.expirationDate,
    this.extraDays,
    this.sources = const {},
  });

  factory DaleVentasEffectiveEntitlements.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'] as Map<String, dynamic>? ?? const {};
    return DaleVentasEffectiveEntitlements(
      maxUsers: _nullableInt(json['maxUsers']),
      maxProducts: _nullableInt(json['maxProducts']),
      maxWarehouses: _nullableInt(json['maxWarehouses']),
      maxDevices: _nullableInt(json['maxDevices']),
      expirationDate: _date(json['expirationDate']),
      extraDays: _nullableInt(json['extraDays']),
      sources: rawSources.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      ),
    );
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

int? _nullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

String? _string(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
