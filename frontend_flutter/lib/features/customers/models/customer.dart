class Customer {
  final String id;
  final String nombreNegocio;
  final String? contactoNombre;
  final String? contactoTelefono;
  final String? contactoEmail;
  final String? rolNegocio;
  final String? businessId;
  final DateTime? createdAt;
  final String? licenseStatus;
  final String? licenseTipo;
  final bool hasActiveLicense;
  final bool hasLicense;
  final bool hasFullLicense;
  final bool hasActiveFullLicense;
  final bool hasBlockedFullLicense;
  final bool hasDemoLicense;
  final bool hasActiveDemoLicense;
  final int fullLicenseCount;
  final int demoLicenseCount;
  final String? commercialStatus;
  final DateTime? lastFullPurchaseAt;

  const Customer({
    required this.id,
    required this.nombreNegocio,
    this.contactoNombre,
    this.contactoTelefono,
    this.contactoEmail,
    this.rolNegocio,
    this.businessId,
    this.createdAt,
    this.licenseStatus,
    this.licenseTipo,
    this.hasActiveLicense = false,
    this.hasLicense = false,
    this.hasFullLicense = false,
    this.hasActiveFullLicense = false,
    this.hasBlockedFullLicense = false,
    this.hasDemoLicense = false,
    this.hasActiveDemoLicense = false,
    this.fullLicenseCount = 0,
    this.demoLicenseCount = 0,
    this.commercialStatus,
    this.lastFullPurchaseAt,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] as String? ?? '',
      nombreNegocio: json['nombre_negocio'] as String? ?? '—',
      contactoNombre: json['contacto_nombre'] as String?,
      contactoTelefono: json['contacto_telefono'] as String?,
      contactoEmail: json['contacto_email'] as String?,
      rolNegocio: json['rol_negocio'] as String?,
      businessId: json['business_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      licenseStatus: json['license_status'] as String?,
      licenseTipo: json['license_tipo'] as String?,
      hasActiveLicense: json['has_active_license'] == true,
      hasLicense: json['has_license'] == true,
      hasFullLicense: json['has_full_license'] == true,
      hasActiveFullLicense: json['has_active_full_license'] == true,
      hasBlockedFullLicense: json['has_blocked_full_license'] == true,
      hasDemoLicense: json['has_demo_license'] == true,
      hasActiveDemoLicense: json['has_active_demo_license'] == true,
      fullLicenseCount: (json['full_license_count'] as num?)?.toInt() ?? 0,
      demoLicenseCount: (json['demo_license_count'] as num?)?.toInt() ?? 0,
      commercialStatus: json['commercial_status'] as String?,
      lastFullPurchaseAt: json['last_full_purchase_at'] != null
          ? DateTime.tryParse(json['last_full_purchase_at'].toString())
          : null,
    );
  }

  String get displayName =>
      contactoNombre?.isNotEmpty == true ? contactoNombre! : nombreNegocio;

  bool get hasBusinessId => businessId?.trim().isNotEmpty == true;

  String get displayLicenseStatus {
    final status = (licenseStatus ?? '').trim().toUpperCase();
    final tipo = (licenseTipo ?? '').trim().toUpperCase();
    if (hasActiveLicense) return 'ACTIVA';
    if (!hasLicense) return 'SIN LICENCIA';
    if (status == 'VENCIDA' && tipo == 'DEMO') return 'DEMO VENCIDA';
    if (status == 'VENCIDA') return 'SIN LICENCIA ACTIVA';
    if (status == 'BLOQUEADA') return 'BLOQUEADA';
    if (status == 'PENDIENTE') return 'PENDIENTE';
    return status.isEmpty ? 'SIN LICENCIA' : status;
  }

  String get displayCommercialStatus {
    switch ((commercialStatus ?? '').trim().toUpperCase()) {
      case 'CLIENTE_ACTIVO':
        return 'COMPRÓ';
      case 'CLIENTE_BLOQUEADO':
        return 'BLOQUEADO';
      case 'CLIENTE_VENCIDO':
        return 'COMPRÓ Y VENCIÓ';
      case 'DEMO_ACTIVA':
        return 'EN DEMO';
      case 'SOLO_DEMO':
        return 'SOLO DEMO';
      case 'SIN_MOVIMIENTO':
        return 'SIN MOVIMIENTO';
      default:
        if (hasActiveFullLicense) return 'COMPRÓ';
        if (hasFullLicense) return 'COMPRÓ Y VENCIÓ';
        if (hasDemoLicense) return 'SOLO DEMO';
        return 'SIN MOVIMIENTO';
    }
  }
}
