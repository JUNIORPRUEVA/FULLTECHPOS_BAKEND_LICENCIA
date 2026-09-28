import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Barra superior de las consolas de proyecto: limpia y mínima.
///
/// Solo el botón de volver, el nombre de la sección y, opcionalmente, un
/// único widget de acciones a la derecha. Sin iconos decorativos ni etiquetas
/// extra: la identidad del proyecto vive en el contenido, no en la barra.
class ProjectAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  /// Acción(es) a la derecha (por ejemplo un menú de opciones).
  final Widget? trailing;

  const ProjectAppBar({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 54,
          padding: const EdgeInsets.only(left: 4, right: 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowSm,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 4),
              _BackIconButton(onPressed: onBack),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón de volver circular y flotante.
///
/// Se usa cuando la pantalla **no tiene barra**: se apoya sobre el degradado
/// de la cabecera y la propia pantalla lo desvanece al desplazarse.
class ProjectFloatingBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const ProjectFloatingBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: const Color(0x331A56DB),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x1A1A56DB)),
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            size: 20,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _BackIconButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackIconButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Volver a proyectos',
      icon: const Icon(Icons.arrow_back_rounded, size: 22),
      color: AppColors.textPrimary,
      splashRadius: 20,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
    );
  }
}
