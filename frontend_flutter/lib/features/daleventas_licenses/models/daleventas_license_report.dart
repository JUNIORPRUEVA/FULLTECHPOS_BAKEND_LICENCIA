import 'daleventas_company_license.dart';

/// Clasificación de una empresa dentro del reporte de DaleVentas.
///
/// Es una clasificación **de lectura**: no altera el estado real de la licencia
/// ni escribe nada en el backend. Solo ordena lo que ya devuelve la API para
/// poder mostrar el resumen del proyecto.
enum DaleVentasReportStatus {
  /// Licencia de pago vigente.
  active,

  /// Licencia de pago vigente pero que vence en los próximos días.
  expiring,

  /// Licencia vencida (incluye la que venció por fecha aunque siga marcada
  /// como activa en el backend).
  expired,

  /// Prueba (demo/trial) todavía utilizable.
  demo,

  /// Prueba (demo/trial) ya vencida.
  demoExpired,

  /// Licencia bloqueada por el administrador.
  blocked,

  /// Cualquier otro estado no contemplado.
  other,
}

/// Fila del reporte: una empresa concreta con su estado ya clasificado.
class DaleVentasReportLine {
  final String companyId;
  final String companyName;
  final DaleVentasReportStatus status;

  /// Etiqueta legible del estado ("Activa", "Vencida", "Demo activa", ...).
  final String statusLabel;

  /// Días restantes (>0 vigente, 0 vence hoy, <0 vencida). `null` si no hay
  /// fecha de expiración disponible.
  final int? daysRemaining;

  final DateTime? endsAt;
  final String planLabel;
  final bool isUsable;

  const DaleVentasReportLine({
    required this.companyId,
    required this.companyName,
    required this.status,
    required this.statusLabel,
    required this.daysRemaining,
    required this.endsAt,
    required this.planLabel,
    required this.isUsable,
  });
}

/// Resumen de licencias de un proyecto, calculado en memoria.
///
/// Es lógica pura (sin red, sin base de datos) para poder verificarla con
/// tests y para que la pestaña "Reporte" no dependa de endpoints nuevos.
class DaleVentasLicenseReport {
  final int total;

  /// Licencia de pago vigente (no vence en el corto plazo).
  final int active;

  /// Vigente pero vence dentro de la ventana de aviso.
  final int expiringSoon;

  /// Vencidas (cualquier origen).
  final int expired;

  /// Pruebas (demo/trial) utilizables.
  final int demoActive;

  /// Pruebas (demo/trial) vencidas.
  final int demoExpired;

  /// Bloqueadas.
  final int blocked;

  /// Otros estados.
  final int other;

  /// Empresas que en algún momento activaron la licencia (estado comercial).
  final int purchased;

  /// Empresas en demo según el estado comercial.
  final int inDemo;

  /// Empresas interesadas o contactadas.
  final int interested;

  /// Empresas perdidas.
  final int lost;

  /// Empresas con seguimiento agendado.
  final int followUp;

  /// Empresas con licencia utilizable ahora mismo (cualquier tipo).
  final int usable;

  /// Cantidad de empresas por plan comercial (etiqueta → total).
  final Map<String, int> planCounts;

  /// Empresas que requieren atención, ordenadas por urgencia
  /// (vencidas → por vencer → bloqueadas).
  final List<DaleVentasReportLine> attention;

  /// Ventana de aviso, en días, para "por vencer".
  static const int expiringWindowDays = 30;

  const DaleVentasLicenseReport({
    required this.total,
    required this.active,
    required this.expiringSoon,
    required this.expired,
    required this.demoActive,
    required this.demoExpired,
    required this.blocked,
    required this.other,
    required this.purchased,
    required this.inDemo,
    required this.interested,
    required this.lost,
    required this.followUp,
    required this.usable,
    required this.planCounts,
    required this.attention,
  });

  /// Pruebas (demo/trial) contabilizadas en total.
  int get demoTotal => demoActive + demoExpired;

  /// Licencias de pago vigentes (sin contar las que vencen pronto).
  int get payingActive => active + expiringSoon;

  /// Empresas sin licencia utilizable en este momento.
  int get notUsable => total - usable;

  /// Porcentaje (0..1) de empresas con licencia utilizable.
  double get usableRatio => total <= 0 ? 0 : (usable / total).clamp(0, 1);

  /// Construye el reporte a partir de las empresas que devuelve la API.
  factory DaleVentasLicenseReport.fromCompanies(
    List<DaleVentasCompanyLicense> companies, {
    DateTime? now,
    int attentionLimit = 12,
  }) {
    final reference = now ?? DateTime.now();

    var active = 0;
    var expiringSoon = 0;
    var expired = 0;
    var demoActive = 0;
    var demoExpired = 0;
    var blocked = 0;
    var other = 0;
    var usable = 0;
    var purchased = 0;
    var inDemo = 0;
    var interested = 0;
    var lost = 0;
    var followUp = 0;

    final planCounts = <String, int>{};
    final lines = <DaleVentasReportLine>[];

    for (final company in companies) {
      final status = classifyStatus(company, reference);
      final days = daysUntilEnd(company, reference);

      switch (status) {
        case DaleVentasReportStatus.active:
          active += 1;
          break;
        case DaleVentasReportStatus.expiring:
          expiringSoon += 1;
          break;
        case DaleVentasReportStatus.expired:
          expired += 1;
          break;
        case DaleVentasReportStatus.demo:
          demoActive += 1;
          break;
        case DaleVentasReportStatus.demoExpired:
          demoExpired += 1;
          break;
        case DaleVentasReportStatus.blocked:
          blocked += 1;
          break;
        case DaleVentasReportStatus.other:
          other += 1;
          break;
      }

      if (company.isUsable) usable += 1;

      final commercialStatus = (company.commercial?.commercialStatus ?? '')
          .toUpperCase();
      switch (commercialStatus) {
        case 'PURCHASED':
        case 'ACTIVE_CUSTOMER':
        case 'RENEWAL_DUE':
          purchased += 1;
          break;
        case 'DEMO':
          inDemo += 1;
          break;
        case 'INTERESTED':
        case 'CONTACTED':
          interested += 1;
          break;
        case 'LOST':
          lost += 1;
          break;
      }

      if (company.commercial?.nextFollowUpAt != null) followUp += 1;

      final plan = planGroupLabel(company);
      planCounts[plan] = (planCounts[plan] ?? 0) + 1;

      if (status == DaleVentasReportStatus.expired ||
          status == DaleVentasReportStatus.expiring ||
          status == DaleVentasReportStatus.blocked ||
          status == DaleVentasReportStatus.demoExpired) {
        lines.add(
          DaleVentasReportLine(
            companyId: company.companyId,
            companyName: company.companyName,
            status: status,
            statusLabel: statusLabelFor(status),
            daysRemaining: days,
            endsAt: company.endsAt,
            planLabel: plan,
            isUsable: company.isUsable,
          ),
        );
      }
    }

    lines.sort(compareAttentionLines);

    return DaleVentasLicenseReport(
      total: companies.length,
      active: active,
      expiringSoon: expiringSoon,
      expired: expired,
      demoActive: demoActive,
      demoExpired: demoExpired,
      blocked: blocked,
      other: other,
      purchased: purchased,
      inDemo: inDemo,
      interested: interested,
      lost: lost,
      followUp: followUp,
      usable: usable,
      planCounts: Map.unmodifiable(planCounts),
      attention: attentionLimit <= 0
          ? const []
          : lines.take(attentionLimit).toList(growable: false),
    );
  }

  /// Clasifica una empresa según su estado técnico y su fecha de expiración.
  static DaleVentasReportStatus classifyStatus(
    DaleVentasCompanyLicense company,
    DateTime now,
  ) {
    if (company.isBlocked) return DaleVentasReportStatus.blocked;
    if (company.isExpired) return DaleVentasReportStatus.expired;
    if (company.isTrial) {
      final days = daysUntilEnd(company, now);
      if (days != null && days < 0) return DaleVentasReportStatus.demoExpired;
      if (!company.isUsable) return DaleVentasReportStatus.demoExpired;
      return DaleVentasReportStatus.demo;
    }
    if (company.isActive) {
      final days = daysUntilEnd(company, now);
      if (days != null && days < 0) return DaleVentasReportStatus.expired;
      if (days != null && days <= expiringWindowDays) {
        return DaleVentasReportStatus.expiring;
      }
      return DaleVentasReportStatus.active;
    }
    return company.isUsable
        ? DaleVentasReportStatus.active
        : DaleVentasReportStatus.other;
  }

  /// Días hasta el fin de la licencia (negativo si ya venció).
  static int? daysUntilEnd(DaleVentasCompanyLicense company, DateTime now) {
    final endsAt = company.endsAt;
    if (endsAt != null) {
      return endsAt.difference(now).inDays;
    }
    if (company.status == 'TRIAL' ||
        company.status == 'ACTIVE' ||
        company.status == 'EXPIRED') {
      return company.daysRemaining;
    }
    return null;
  }

  /// Etiqueta legible de un estado.
  static String statusLabelFor(DaleVentasReportStatus status) {
    switch (status) {
      case DaleVentasReportStatus.active:
        return 'Activa';
      case DaleVentasReportStatus.expiring:
        return 'Por vencer';
      case DaleVentasReportStatus.expired:
        return 'Vencida';
      case DaleVentasReportStatus.demo:
        return 'Demo activa';
      case DaleVentasReportStatus.demoExpired:
        return 'Demo vencida';
      case DaleVentasReportStatus.blocked:
        return 'Bloqueada';
      case DaleVentasReportStatus.other:
        return 'Sin estado';
    }
  }

  /// Grupo de plan usado en el resumen (evita inventar planes inexistentes).
  static String planGroupLabel(DaleVentasCompanyLicense company) {
    if (company.commercial != null) return company.commercialPlanLabel;
    if (company.isTrial) return 'Prueba (sin plan)';
    return 'Sin plan comercial';
  }

  /// Ordena por urgencia: vencidas primero y, dentro de cada grupo, la que
  /// vence antes.
  static int compareAttentionLines(
    DaleVentasReportLine a,
    DaleVentasReportLine b,
  ) {
    final byPriority = _priority(a.status).compareTo(_priority(b.status));
    if (byPriority != 0) return byPriority;
    final aDays = a.daysRemaining ?? 9999;
    final bDays = b.daysRemaining ?? 9999;
    if (aDays != bDays) return aDays.compareTo(bDays);
    return a.companyName.toLowerCase().compareTo(b.companyName.toLowerCase());
  }

  static int _priority(DaleVentasReportStatus status) {
    switch (status) {
      case DaleVentasReportStatus.expired:
        return 0;
      case DaleVentasReportStatus.demoExpired:
        return 1;
      case DaleVentasReportStatus.expiring:
        return 2;
      case DaleVentasReportStatus.blocked:
        return 3;
      default:
        return 4;
    }
  }
}
