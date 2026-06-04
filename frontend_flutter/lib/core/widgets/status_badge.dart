import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Badge de estado premium rediseñado
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
  final bool pill;

  const StatusBadge({
    super.key,
    required this.label,
    required this.type,
    this.pill = false,
  });

  factory StatusBadge.fromString(String status, {bool pill = false}) {
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
    return StatusBadge(label: status, type: type, pill: pill);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(pill ? 20 : AppSpacing.badgeRadius),
        border: Border.all(color: colors.$2.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.$2,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.$2,
              letterSpacing: 0.2,
            ),
          ),
        ],
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
