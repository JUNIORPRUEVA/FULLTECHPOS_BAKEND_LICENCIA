class License {
  final String id;
  final String? licenseKey;
  final String? status;
  final String? customerId;
  final String? customerName;
  final String? businessId;
  final String? projectId;
  final String? projectName;
  final String? licenseType;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final bool? isDemo;
  final String? notes;
  final int? maxDevices;
  final Map<String, dynamic>? raw;

  const License({
    required this.id,
    this.licenseKey,
    this.status,
    this.customerId,
    this.customerName,
    this.businessId,
    this.projectId,
    this.projectName,
    this.licenseType,
    this.expiresAt,
    this.createdAt,
    this.isDemo,
    this.notes,
    this.maxDevices,
    this.raw,
  });

  factory License.fromJson(Map<String, dynamic> json) {
    return License(
      id: json['id']?.toString() ?? '',
      licenseKey: json['license_key'] as String? ?? json['key'] as String?,
      status: json['status'] as String?,
      customerId: json['customer_id']?.toString(),
      customerName: json['nombre_negocio'] as String? ?? json['customer_name'] as String?,
      businessId: json['business_id']?.toString(),
      projectId: json['project_id']?.toString(),
      projectName: json['project_name'] as String?,
      licenseType: json['license_type'] as String? ?? json['type'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      isDemo: json['is_demo'] as bool?,
      notes: json['notes'] as String?,
      maxDevices: json['max_devices'] != null
          ? int.tryParse(json['max_devices'].toString())
          : null,
      raw: json,
    );
  }

  String get shortKey {
    if (licenseKey == null || licenseKey!.isEmpty) return '—';
    final k = licenseKey!;
    if (k.length <= 12) return k;
    return '${k.substring(0, 8)}...${k.substring(k.length - 4)}';
  }

  bool get isActive => status?.toLowerCase() == 'active' ||
      status?.toLowerCase() == 'activa';
  bool get isExpired => status?.toLowerCase() == 'expired' ||
      status?.toLowerCase() == 'vencida';
}
