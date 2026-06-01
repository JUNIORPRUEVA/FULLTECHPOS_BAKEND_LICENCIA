class License {
  final String id;
  final String? licenseKey;
  final String? status;
  final String? customerId;
  final String? customerName;
  final String? businessId;
  final String? projectId;
  final String? projectName;
  final String? projectCode;
  final String? licenseType;
  final DateTime? expiresAt;
  final DateTime? activatedAt;
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
    this.projectCode,
    this.licenseType,
    this.expiresAt,
    this.activatedAt,
    this.createdAt,
    this.isDemo,
    this.notes,
    this.maxDevices,
    this.raw,
  });

  factory License.fromJson(Map<String, dynamic> json) {
    // Normalize status from backend 'estado' field
    String? normalizedStatus;
    final rawStatus = json['estado'] as String? ?? json['status'] as String?;
    if (rawStatus != null) {
      normalizedStatus = rawStatus.toUpperCase();
      // Map common variations
      if (normalizedStatus == 'ACTIVE') normalizedStatus = 'ACTIVA';
      if (normalizedStatus == 'EXPIRED') normalizedStatus = 'VENCIDA';
      if (normalizedStatus == 'PENDING') normalizedStatus = 'PENDIENTE';
      if (normalizedStatus == 'BLOCKED') normalizedStatus = 'BLOQUEADA';
    }

    // If no explicit status, determine from activated_at and expires_at
    if (normalizedStatus == null || normalizedStatus.isEmpty) {
      final activatedAt = json['fecha_inicio'] as String? ?? json['activated_at'] as String?;
      final expiresAt = json['fecha_fin'] as String? ?? json['expires_at'] as String?;
      final blocked = json['bloqueada'] == true || json['blocked'] == true;

      if (blocked) {
        normalizedStatus = 'BLOQUEADA';
      } else if (activatedAt != null) {
        normalizedStatus = 'ACTIVA';
        // Check if expired
        if (expiresAt != null) {
          final expDate = DateTime.tryParse(expiresAt.toString());
          if (expDate != null && expDate.isBefore(DateTime.now())) {
            normalizedStatus = 'VENCIDA';
          }
        }
      } else {
        normalizedStatus = 'PENDIENTE';
      }
    }

    return License(
      id: json['id']?.toString() ?? '',
      licenseKey: json['license_key'] as String? ?? json['key'] as String?,
      status: normalizedStatus,
      customerId: json['customer_id']?.toString(),
      customerName: json['nombre_negocio'] as String? ?? json['customer_name'] as String?,
      businessId: json['business_id']?.toString(),
      projectId: json['project_id']?.toString(),
      projectName: json['project_name'] as String?,
      projectCode: json['project_code'] as String?,
      licenseType: json['license_type'] as String? ?? json['type'] as String? ?? json['tipo'] as String?,
      expiresAt: _parseDate(json['fecha_fin'] as String? ?? json['expires_at'] as String?),
      activatedAt: _parseDate(json['fecha_inicio'] as String? ?? json['activated_at'] as String?),
      createdAt: _parseDate(json['created_at'] as String?),
      isDemo: json['is_demo'] as bool?,
      notes: json['notas'] as String? ?? json['notes'] as String?,
      maxDevices: json['max_dispositivos'] != null
          ? int.tryParse(json['max_dispositivos'].toString())
          : null,
      raw: json,
    );
  }

  static DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    return DateTime.tryParse(dateStr);
  }

  /// Display name for the project associated with this license.
  String get displayProjectName {
    if (projectName != null && projectName!.isNotEmpty && projectName != 'Default Project') {
      return projectName!;
    }
    if (projectCode != null && projectCode!.isNotEmpty) {
      return projectCode!;
    }
    return 'Proyecto no definido';
  }

  /// Shortened license key for display.
  String get shortKey {
    if (licenseKey == null || licenseKey!.isEmpty) return '—';
    final k = licenseKey!;
    if (k.length <= 12) return k;
    return '${k.substring(0, 8)}...${k.substring(k.length - 4)}';
  }

  /// Whether the license is active.
  bool get isActive => status == 'ACTIVA';

  /// Whether the license is expired.
  bool get isExpired => status == 'VENCIDA';

  /// Whether the license is pending.
  bool get isPending => status == 'PENDIENTE';

  /// Whether the license is blocked.
  bool get isBlocked => status == 'BLOQUEADA';

  /// Whether the license can be activated.
  /// Allows activation attempt for pending and expired licenses.
  /// Blocked licenses cannot be activated (must be unblocked first).
  /// The backend will return proper error messages for expired licenses.
  bool get canActivate => !isBlocked && !isActive;
}
