import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../models/license.dart';

class LicenseListItem extends StatelessWidget {
  final License license;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const LicenseListItem({
    super.key,
    required this.license,
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
        _buildIcon(34, 16),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _buildTextContent()),
        const SizedBox(width: 8),
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
            _buildIcon(42, 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                license.displayProjectName,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildEditButton(),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: AppColors.textMuted,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildMetaWrap(),
      ],
    );
  }

  Widget _buildTextContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                license.displayProjectName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (license.status != null) StatusBadge.fromString(license.status!),
          ],
        ),
        const SizedBox(height: 2),
        _buildMetaLine(),
      ],
    );
  }

  Widget _buildMetaLine() {
    final dateFmt = DateFormat('dd/MM/yyyy');
    return Row(
      children: [
        Text(
          license.shortKey,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontFamily: 'monospace',
          ),
        ),
        if (license.customerName != null) ...[
          const Text(
            ' · ',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          Flexible(
            child: Text(
              license.customerName!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (license.licenseType != null) ...[
          const Text(
            ' · ',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          Text(
            license.licenseType!,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (license.maxDevices != null) ...[
          const Text(
            ' · ',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          Text(
            '${license.maxDevices} disp.',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
        if (license.expiresAt != null) ...[
          const Text(
            ' · ',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          Text(
            'Vence ${dateFmt.format(license.expiresAt!.toLocal())}',
            style: TextStyle(
              fontSize: 11,
              color: license.isExpired ? AppColors.error : AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetaWrap() {
    final dateFmt = DateFormat('dd/MM/yyyy');
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Pill(label: license.shortKey, monospace: true),
        if (license.status != null) StatusBadge.fromString(license.status!),
        if (license.licenseType != null) _Pill(label: license.licenseType!),
        if (license.customerName != null) _Pill(label: license.customerName!),
        if (license.maxDevices != null)
          _Pill(label: '${license.maxDevices} dispositivos'),
        if (license.expiresAt != null)
          _Pill(
            label: 'Vence ${dateFmt.format(license.expiresAt!.toLocal())}',
            color: license.isExpired
                ? AppColors.error
                : AppColors.textSecondary,
          ),
      ],
    );
  }

  Widget _buildIcon(double size, double iconSize) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.vpn_key_rounded,
        size: iconSize,
        color: isSelected ? Colors.white : AppColors.textMuted,
      ),
    );
  }

  Widget _buildEditButton() {
    return IconButton(
      onPressed: onEdit,
      tooltip: 'Editar licencia',
      icon: const Icon(Icons.edit_outlined, size: 18),
      color: AppColors.primary,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool monospace;

  const _Pill({
    required this.label,
    this.color = AppColors.textSecondary,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontFamily: monospace ? 'monospace' : null,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
