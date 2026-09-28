import 'package:flutter/material.dart';

import '../../../core/config/appyra_projects.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../../licenses/models/project.dart';

/// Tarjeta de un proyecto en project mode.
///
/// Se construye desde el registro central ([AppyraProjectDefinition]) y su
/// acción principal abre la administración **existente** del proyecto
/// ([AppyraProjectDefinition.route]): no crea pantallas nuevas ni duplica la
/// consola.
///
/// Si además existe una fila en `projects` ([project]) se habilita la edición
/// del proyecto; si no existe, la tarjeta funciona igual (la entrada del
/// proyecto en project mode no depende de la tabla `projects`).
class ProjectModeCard extends StatelessWidget {
  final AppyraProjectDefinition definition;

  /// Fila real de `projects` con el mismo `code`, si existe.
  final Project? project;

  /// Acción principal: abre la administración existente del proyecto.
  final VoidCallback onManage;

  /// Acción secundaria de edición (solo si hay fila real).
  final VoidCallback? onEdit;

  const ProjectModeCard({
    super.key,
    required this.definition,
    required this.onManage,
    this.project,
    this.onEdit,
  });

  bool get _isActive => project?.isActive ?? definition.isActive;

  /// Monograma del proyecto (2 letras) para la marca de la tarjeta.
  String get _monogram {
    final code = definition.code.trim();
    if (code.length >= 2) return code.substring(0, 2).toUpperCase();
    return definition.name.isEmpty
        ? 'AP'
        : definition.name.substring(0, 1).toUpperCase();
  }

  /// Texto corto de presentación (tagline del producto o descripción).
  String? get _tagline {
    final profile = project?.profile;
    final tagline = profile?.tagline.trim();
    if (tagline != null && tagline.isNotEmpty) return tagline;
    final description = project?.description?.trim();
    if (description != null && description.isNotEmpty) return description;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x101A56DB),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHead(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusRow(),
                  ..._buildTagline(),
                  ..._buildFacts(),
                  const SizedBox(height: AppSpacing.md),
                  _ProjectPrimaryButton(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Administrar proyecto',
                    onPressed: onManage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHead() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primarySoft, AppColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2E1A56DB),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _monogram,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.tag_rounded,
                      size: 12,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Código: ${definition.code}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              onPressed: onEdit,
              tooltip: 'Editar proyecto',
              icon: const Icon(Icons.edit_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              color: AppColors.primary,
            ),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        const Text(
          'Estado:',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
        StatusBadge(
          label: _isActive ? 'Activo' : 'Inactivo',
          type: _isActive ? StatusType.active : StatusType.inactive,
        ),
      ],
    );
  }

  List<Widget> _buildTagline() {
    final tagline = _tagline;
    if (tagline == null) return const [];
    return [
      const SizedBox(height: 12),
      Text(
        tagline,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      ),
    ];
  }

  /// Datos comerciales del proyecto (solo si existe la fila real).
  List<Widget> _buildFacts() {
    final row = project;
    if (row == null) return const [];

    final facts = <Widget>[];
    if (row.isPaidProject && row.monthlyPrice > 0) {
      facts.add(
        _FactChip(
          icon: Icons.payments_outlined,
          label: _priceLabel(row),
          color: AppColors.success,
        ),
      );
    }
    if (row.allowDemo && row.demoDays > 0) {
      facts.add(
        _FactChip(
          icon: Icons.science_outlined,
          label: '${row.demoDays} días de prueba',
          color: AppColors.info,
        ),
      );
    }
    if (row.minPurchaseMonths > 1) {
      facts.add(
        _FactChip(
          icon: Icons.event_repeat_outlined,
          label: 'Mínimo ${row.minPurchaseMonths} meses',
          color: AppColors.warning,
        ),
      );
    }

    if (facts.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: facts),
    ];
  }

  String _priceLabel(Project row) {
    final amount = row.monthlyPrice;
    final text = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return '${row.currency == 'USD' ? '\$' : '${row.currency} '}$text / mes';
  }
}

class _FactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _FactChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón principal de la tarjeta (degradado de marca).
class _ProjectPrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ProjectPrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2E1A56DB),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
