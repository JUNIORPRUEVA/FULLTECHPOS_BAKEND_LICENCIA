import 'project_profile.dart';

class Project {
  final String id;
  final String code;
  final String name;
  final String? description;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Campos de facturación / licencias
  final double monthlyPrice;
  final String currency;
  final int demoDays;
  final int minPurchaseMonths;
  final bool isPaidProject;
  final bool allowDemo;
  final ProjectProfile profile;

  const Project({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.monthlyPrice = 0,
    this.currency = 'USD',
    this.demoDays = 5,
    this.minPurchaseMonths = 3,
    this.isPaidProject = true,
    this.allowDemo = true,
    this.profile = const ProjectProfile(),
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      isActive: json['is_active'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      monthlyPrice: _parseDouble(json['monthly_price']),
      currency: json['currency'] as String? ?? 'USD',
      demoDays: _parseInt(json['demo_days'], 5),
      minPurchaseMonths: _parseInt(json['min_purchase_months'], 3),
      isPaidProject: json['is_paid_project'] == true,
      allowDemo: json['allow_demo'] == true,
      profile: ProjectProfile.fromJson(json['product_profile']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'description': description,
      'is_active': isActive,
      'monthly_price': monthlyPrice,
      'currency': currency,
      'demo_days': demoDays,
      'min_purchase_months': minPurchaseMonths,
      'is_paid_project': isPaidProject,
      'allow_demo': allowDemo,
      'product_profile': profile.toJson(),
    };
  }

  String get displayName => '$name ($code)';

  Project copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? monthlyPrice,
    String? currency,
    int? demoDays,
    int? minPurchaseMonths,
    bool? isPaidProject,
    bool? allowDemo,
    ProjectProfile? profile,
  }) {
    return Project(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      currency: currency ?? this.currency,
      demoDays: demoDays ?? this.demoDays,
      minPurchaseMonths: minPurchaseMonths ?? this.minPurchaseMonths,
      isPaidProject: isPaidProject ?? this.isPaidProject,
      allowDemo: allowDemo ?? this.allowDemo,
      profile: profile ?? this.profile,
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static int _parseInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? defaultValue;
  }
}
