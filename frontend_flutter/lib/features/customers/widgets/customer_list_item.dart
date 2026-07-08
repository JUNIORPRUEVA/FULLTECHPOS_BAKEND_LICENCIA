import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../models/customer.dart';

class CustomerListItem extends StatelessWidget {
  final Customer customer;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const CustomerListItem({
    super.key,
    required this.customer,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(isMobile ? 14 : 0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(isMobile ? 14 : 0),
          border: isMobile
              ? Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                )
              : null,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : AppSpacing.md,
          vertical: isMobile ? 12 : 8,
        ),
        child: isMobile ? _buildMobileContent() : _buildDesktopContent(),
      ),
    );
  }

  Widget _buildDesktopContent() {
    return Row(
      children: [
        _buildAvatar(36, 13),
        const SizedBox(width: AppSpacing.sm),
        Expanded(flex: 3, child: _buildMainText()),
        const SizedBox(width: AppSpacing.sm),
        Expanded(flex: 3, child: _buildContactLine()),
        const SizedBox(width: AppSpacing.sm),
        _buildLicenseCounts(),
        const SizedBox(width: 6),
        StatusBadge.fromString(customer.displayCommercialStatus),
        if (customer.hasLicense || customer.hasActiveLicense) ...[
          const SizedBox(width: 6),
          StatusBadge.fromString(customer.displayLicenseStatus),
        ],
        const SizedBox(width: 4),
        _buildEditButton(),
      ],
    );
  }

  Widget _buildMobileContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildAvatar(42, 15),
            const SizedBox(width: 12),
            Expanded(child: _buildMainText(nameSize: 14.5, phoneSize: 12.5)),
            _buildEditButton(),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: AppColors.textMuted,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildContactLine(),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildLicenseCounts(),
            if (customer.hasBusinessId) _buildBusinessIdBadge(),
            StatusBadge.fromString(customer.displayCommercialStatus),
            if (customer.hasLicense || customer.hasActiveLicense)
              StatusBadge.fromString(customer.displayLicenseStatus),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatar(double size, double fontSize) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          _initial,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMainText({double nameSize = 13, double phoneSize = 12}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          customer.nombreNegocio,
          style: TextStyle(
            fontSize: nameSize,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        if (customer.contactoNombre != null) ...[
          const SizedBox(height: 3),
          Text(
            customer.contactoNombre!,
            style: TextStyle(
              fontSize: phoneSize,
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildContactLine() {
    final parts = [
      if (customer.contactoTelefono?.trim().isNotEmpty == true)
        customer.contactoTelefono!.trim(),
      if (customer.contactoEmail?.trim().isNotEmpty == true)
        customer.contactoEmail!.trim(),
      if (customer.rolNegocio?.trim().isNotEmpty == true)
        customer.rolNegocio!.trim(),
    ];
    return Text(
      parts.isEmpty ? 'Sin contacto registrado' : parts.join('  ·  '),
      style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildLicenseCounts() {
    return _MiniInfo(
      icon: Icons.workspace_premium_outlined,
      label:
          '${customer.fullLicenseCount} full / ${customer.demoLicenseCount} demo',
    );
  }

  Widget _buildEditButton() {
    return IconButton(
      onPressed: onEdit,
      tooltip: 'Editar cliente',
      icon: const Icon(Icons.edit_outlined, size: 18),
      color: AppColors.primary,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildBusinessIdBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    );
  }

  String get _initial {
    final name = customer.nombreNegocio.trim();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _MiniInfo extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniInfo({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
