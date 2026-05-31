import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../models/license.dart';

class LicenseDetailPanel extends StatelessWidget {
  final License license;
  final VoidCallback onClose;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onBlock;
  final Future<void> Function()? onUnblock;
  final Future<void> Function()? onActivate;
  final Future<void> Function(int days)? onExtend;
  final Future<void> Function()? onDelete;
  final VoidCallback? onViewCustomer;

  const LicenseDetailPanel({
    super.key,
    required this.license,
    required this.onClose,
    this.onEdit,
    this.onBlock,
    this.onUnblock,
    this.onActivate,
    this.onExtend,
    this.onDelete,
    this.onViewCustomer,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');

    return Container(
      width: AppSpacing.detailPanelWidth,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: AppSpacing.appBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Detalle de licencia',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (license.status != null)
                  StatusBadge.fromString(license.status!),
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onClose,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Key section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.cardRadius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'License Key',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          license.licenseKey ?? '—',
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Cliente section
                  if (license.customerName != null || license.customerId != null)
                    _Section(title: 'Cliente', rows: [
                      if (license.customerName != null)
                        _Row('Nombre', license.customerName!),
                      if (license.customerId != null)
                        _Row('ID', license.customerId!, mono: true),
                    ]),
                  if (onViewCustomer != null && license.customerId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onViewCustomer,
                          icon: const Icon(Icons.person_outline_rounded, size: 16),
                          label: const Text('Ir al cliente'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  // Details
                  _Section(title: 'Información', rows: [
                    if (license.projectName != null)
                      _Row('Sistema', license.projectName!),
                    if (license.licenseType != null)
                      _Row('Tipo', license.licenseType!),
                    if (license.businessId != null)
                      _Row('Business ID', license.businessId!, mono: true),
                    if (license.maxDevices != null)
                      _Row('Máx. dispositivos', license.maxDevices!.toString()),
                    if (license.expiresAt != null)
                      _Row(
                        'Vencimiento',
                        dateFmt.format(license.expiresAt!.toLocal()),
                        highlight: license.isExpired,
                      ),
                    if (license.createdAt != null)
                      _Row('Creada',
                          dateFmt.format(license.createdAt!.toLocal())),
                    if (license.isDemo == true) _Row('Demo', 'Sí'),
                    if (license.notes != null && license.notes!.isNotEmpty)
                      _Row('Notas', license.notes!),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  // Actions
                  const Text(
                    'Acciones',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (onActivate != null)
                    _ActionBtn(
                      label: 'Activar manual',
                      icon: Icons.check_circle_outline_rounded,
                      color: AppColors.success,
                      onTap: onActivate!,
                    ),
                  if (onEdit != null)
                    _ActionBtn(
                      label: 'Editar licencia',
                      icon: Icons.edit_outlined,
                      color: AppColors.primary,
                      onTap: onEdit!,
                    ),
                  if (onBlock != null)
                    _ActionBtn(
                      label: 'Bloquear',
                      icon: Icons.block_rounded,
                      color: AppColors.warning,
                      onTap: onBlock!,
                    ),
                  if (onUnblock != null)
                    _ActionBtn(
                      label: 'Desbloquear',
                      icon: Icons.lock_open_outlined,
                      color: AppColors.primary,
                      onTap: onUnblock!,
                    ),
                  if (onExtend != null)
                    _ActionBtn(
                      label: 'Extender 30 días',
                      icon: Icons.calendar_month_outlined,
                      color: AppColors.info,
                      onTap: () => onExtend!(30),
                    ),
                  if (onDelete != null)
                    _ActionBtn(
                      label: 'Eliminar licencia',
                      icon: Icons.delete_outline_rounded,
                      color: AppColors.error,
                      onTap: onDelete!,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;

  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Column(
            children: rows.asMap().entries.map((e) {
              return Column(
                children: [
                  e.value,
                  if (e.key < rows.length - 1) const Divider(height: 1),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final bool highlight;

  const _Row(this.label, this.value, {this.mono = false, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: highlight ? AppColors.error : AppColors.textPrimary,
                fontFamily: mono ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Future<void> Function() onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _loading
          ? null
          : () async {
              setState(() => _loading = true);
              try {
                await widget.onTap();
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            },
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 10,
        ),
        child: Row(
          children: [
            if (_loading)
              SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: widget.color),
              )
            else
              Icon(widget.icon, size: 16, color: widget.color),
            const SizedBox(width: AppSpacing.sm),
            Text(
              widget.label,
              style: TextStyle(fontSize: 13, color: widget.color),
            ),
          ],
        ),
      ),
    );
  }
}
