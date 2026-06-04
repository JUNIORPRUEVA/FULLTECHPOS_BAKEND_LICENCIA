import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../models/customer.dart';

class CustomerListItem extends StatelessWidget {
  final Customer customer;
  final bool isSelected;
  final VoidCallback onTap;

  const CustomerListItem({
    super.key,
    required this.customer,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: isSelected ? AppColors.primaryLight : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  _initial,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    customer.nombreNegocio,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (customer.contactoTelefono != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      customer.contactoTelefono!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Business ID indicator
            if (customer.hasBusinessId)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Business ID',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            StatusBadge.fromString(customer.displayCommercialStatus),
            if (customer.hasLicense || customer.hasActiveLicense) ...[
              const SizedBox(width: 6),
              StatusBadge.fromString(customer.displayLicenseStatus),
            ],
          ],
        ),
      ),
    );
  }

  String get _initial {
    final name = customer.nombreNegocio.trim();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
