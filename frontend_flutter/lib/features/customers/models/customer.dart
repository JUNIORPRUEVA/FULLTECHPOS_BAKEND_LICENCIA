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
    );
  }

  String get displayName =>
      contactoNombre?.isNotEmpty == true ? contactoNombre! : nombreNegocio;
}
