class LicensePaymentOrder {
  final String id;
  final String customerId;
  final String projectId;
  final String? licenseId;
  final int months;
  final double monthlyPrice;
  final double totalAmount;
  final String currency;
  final String provider;
  final String? providerOrderId;
  final String? providerCaptureId;
  final String status;
  final String? checkoutUrl;
  final Map<String, dynamic>? rawRequest;
  final Map<String, dynamic>? rawResponse;
  final DateTime? paidAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields
  final String? customerName;
  final String? projectName;
  final String? projectCode;

  LicensePaymentOrder({
    required this.id,
    required this.customerId,
    required this.projectId,
    this.licenseId,
    required this.months,
    required this.monthlyPrice,
    required this.totalAmount,
    required this.currency,
    required this.provider,
    this.providerOrderId,
    this.providerCaptureId,
    required this.status,
    this.checkoutUrl,
    this.rawRequest,
    this.rawResponse,
    this.paidAt,
    required this.createdAt,
    required this.updatedAt,
    this.customerName,
    this.projectName,
    this.projectCode,
  });

  factory LicensePaymentOrder.fromJson(Map<String, dynamic> json) {
    return LicensePaymentOrder(
      id: json['id'] ?? '',
      customerId: json['customer_id'] ?? '',
      projectId: json['project_id'] ?? '',
      licenseId: json['license_id'],
      months: (json['months'] ?? 0) is int
          ? json['months'] as int
          : int.tryParse(json['months']?.toString() ?? '0') ?? 0,
      monthlyPrice: (json['monthly_price'] ?? 0) is double
          ? json['monthly_price'] as double
          : double.tryParse(json['monthly_price']?.toString() ?? '0') ?? 0,
      totalAmount: (json['total_amount'] ?? 0) is double
          ? json['total_amount'] as double
          : double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0,
      currency: json['currency'] ?? 'USD',
      provider: json['provider'] ?? 'paypal',
      providerOrderId: json['provider_order_id'],
      providerCaptureId: json['provider_capture_id'],
      status: json['status'] ?? 'PENDING',
      checkoutUrl: json['checkout_url'],
      rawRequest: json['raw_request'] is Map
          ? Map<String, dynamic>.from(json['raw_request'])
          : null,
      rawResponse: json['raw_response'] is Map
          ? Map<String, dynamic>.from(json['raw_response'])
          : null,
      paidAt: json['paid_at'] != null ? DateTime.tryParse(json['paid_at']) : null,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      customerName: json['customer_name'],
      projectName: json['project_name'],
      projectCode: json['project_code'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customer_id': customerId,
      'project_id': projectId,
      'license_id': licenseId,
      'months': months,
      'monthly_price': monthlyPrice,
      'total_amount': totalAmount,
      'currency': currency,
      'provider': provider,
      'provider_order_id': providerOrderId,
      'provider_capture_id': providerCaptureId,
      'status': status,
      'checkout_url': checkoutUrl,
      'raw_request': rawRequest,
      'raw_response': rawResponse,
      'paid_at': paidAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'customer_name': customerName,
      'project_name': projectName,
      'project_code': projectCode,
    };
  }

  bool get isPaid => status.toUpperCase() == 'PAID';
  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isFailed => status.toUpperCase() == 'FAILED';
  bool get isCancelled => status.toUpperCase() == 'CANCELLED';
  bool get isApproved => status.toUpperCase() == 'APPROVED';
}
