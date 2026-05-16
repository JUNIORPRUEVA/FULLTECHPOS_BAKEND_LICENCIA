import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum StatusType {
  active,
  inactive,
  expired,
  demo,
  trial,
  suspended,
  pastDue,
  unknown,
}

class StatusBadge extends StatelessWidget {
  final String label;
  final StatusType type;

  const StatusBadge({super.key, required this.label, required this.type});

  factory StatusBadge.fromString(String status) {
    final normalized = status.toLowerCase().trim();
    StatusType type;
    switch (normalized) {
      case 'active':
      case 'activa':
      case 'activo':
        type = StatusType.active;
        break;
      case 'inactive':
      case 'inactiva':
      case 'inactivo':
        type = StatusType.inactive;
        break;
      case 'expired':
      case 'vencida':
      case 'vencido':
        type = StatusType.expired;
        break;
      case 'blocked':
      case 'bloqueada':
      case 'bloqueado':
        type = StatusType.suspended;
        break;
      case 'demo':
        type = StatusType.demo;
        break;
      case 'trial':
        type = StatusType.trial;
        break;
      case 'suspended':
      case 'suspendida':
      case 'suspendido':
        type = StatusType.suspended;
        break;
      case 'past_due':
      case 'pastdue':
        type = StatusType.pastDue;
        break;
      default:
        type = StatusType.unknown;
    }
    return StatusBadge(label: status, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.$2,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  (Color, Color) _colors() {
    switch (type) {
      case StatusType.active:
        return (AppColors.successLight, AppColors.success);
      case StatusType.inactive:
        return (AppColors.surfaceVariant, AppColors.textSecondary);
      case StatusType.expired:
        return (AppColors.errorLight, AppColors.error);
      case StatusType.demo:
        return (AppColors.infoLight, AppColors.info);
      case StatusType.trial:
        return (AppColors.infoLight, AppColors.info);
      case StatusType.suspended:
        return (AppColors.warningLight, AppColors.warning);
      case StatusType.pastDue:
        return (AppColors.warningLight, AppColors.warning);
      case StatusType.unknown:
        return (AppColors.surfaceVariant, AppColors.textMuted);
    }
  }
}
