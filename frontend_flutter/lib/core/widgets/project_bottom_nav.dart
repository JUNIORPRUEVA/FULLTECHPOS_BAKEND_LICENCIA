import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Item de la barra de navegación inferior de un proyecto.
class ProjectNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const ProjectNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// Barra inferior de las consolas de proyecto.
///
/// En project mode cada proyecto se comporta como una app independiente: su
/// consola usa esta barra inferior en lugar de la navegación general de Appyra.
/// Es deliberadamente pequeña y sin dependencias para poder reutilizarla en
/// otros proyectos.
class ProjectBottomNav extends StatelessWidget {
  final List<ProjectNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Color de acento del proyecto (por defecto el primario de Appyra).
  final Color accent;

  const ProjectBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.accent = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var index = 0; index < items.length; index++)
                Expanded(
                  child: _ProjectNavButton(
                    item: items[index],
                    selected: index == currentIndex,
                    accent: accent,
                    onTap: () => onTap(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectNavButton extends StatelessWidget {
  final ProjectNavItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ProjectNavButton({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : AppColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                height: 30,
                width: selected ? 56 : 40,
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  size: 21,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
