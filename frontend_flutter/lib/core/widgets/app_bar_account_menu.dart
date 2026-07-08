import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../auth/auth_service.dart';
import '../auth/session_manager.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

enum CashRegisterState { open, closed }

enum FullposMenuAction {
  settings,
  logout,
}

class AppBarAccountMenu extends StatefulWidget {
  const AppBarAccountMenu({super.key});

  @override
  State<AppBarAccountMenu> createState() => _AppBarAccountMenuState();
}

class _AppBarAccountMenuState extends State<AppBarAccountMenu> {
  Future<AppBarAccountMenuData>? _dataFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dataFuture ??= _loadData();
  }

  Future<AppBarAccountMenuData> _loadData() async {
    final sessionManager = context.read<SessionManager>();
    final auth = context.read<AuthService>();
    final apiClient = ApiClient(sessionManager: sessionManager);

    var companyName = 'Appyra';
    try {
      final response = await apiClient.get('/api/admin/store-settings');
      final settings = response['settings'];
      if (settings is Map<String, dynamic>) {
        final brandName = _normalizeText(settings['brand_name']);
        if (brandName.isNotEmpty) {
          companyName = brandName;
        }
      }
    } catch (_) {
      // Safe fallback when store settings are unavailable.
    }

    final userName = auth.username.trim().isEmpty
        ? 'Usuario Appyra'
        : auth.username.trim();

    return AppBarAccountMenuData(
      companyName: companyName,
      userName: userName,
      roleLabel: 'Administrador',
      userStatusLabel: 'Administrador',
      cashRegisterLabel: 'Caja principal',
      cashRegisterState: CashRegisterState.open,
    );
  }

  String _normalizeText(Object? value) => (value?.toString() ?? '').trim();

  Future<void> _handleAction(
    BuildContext context,
    FullposMenuAction action,
  ) async {
    switch (action) {
      case FullposMenuAction.settings:
        _showComingSoon(context, 'Configuracion estara disponible pronto.');
      case FullposMenuAction.logout:
        await _confirmLogout(context);
    }
  }

  void _showComingSoon(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cerrar sesion'),
          content: const Text('Estas seguro que deseas cerrar sesion?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Salir'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      if (!mounted) return;
      final auth = this.context.read<AuthService>();
      await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final showChip = screenWidth >= 920;
    final compactChip = screenWidth >= 760 && screenWidth < 920;
    final showName = screenWidth >= 760;

    return FutureBuilder<AppBarAccountMenuData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ??
            const AppBarAccountMenuData(
              companyName: 'Appyra',
              userName: 'Usuario Appyra',
              roleLabel: 'Administrador',
              userStatusLabel: 'Administrador',
              cashRegisterLabel: 'Caja principal',
              cashRegisterState: CashRegisterState.open,
            );

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showChip || compactChip) ...[
              CashRegisterStatusChip(
                label: data.cashRegisterLabel,
                state: data.cashRegisterState,
                compact: compactChip,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            FullposUserMenu(
              data: data,
              showName: showName,
              onSelected: (action) => _handleAction(context, action),
            ),
          ],
        );
      },
    );
  }
}

class CashRegisterStatusChip extends StatelessWidget {
  final String label;
  final CashRegisterState state;
  final bool compact;

  const CashRegisterStatusChip({
    super.key,
    required this.label,
    required this.state,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isOpen = state == CashRegisterState.open;
    final text = compact
        ? (isOpen ? 'Abierta' : 'Cerrada')
        : '$label - ${isOpen ? 'Abierta' : 'Cerrada'}';

    return Container(
      height: 36,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: isOpen
            ? AppColors.primaryLight.withValues(alpha: 0.95)
            : AppColors.errorLight.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isOpen
              ? AppColors.primary.withValues(alpha: 0.14)
              : AppColors.error.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: isOpen
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              isOpen ? Icons.point_of_sale_rounded : Icons.lock_clock_rounded,
              size: 11,
              color: isOpen ? AppColors.primary : AppColors.error,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: isOpen ? AppColors.primaryDark : AppColors.error,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class FullposUserMenu extends StatelessWidget {
  final AppBarAccountMenuData data;
  final bool showName;
  final ValueChanged<FullposMenuAction> onSelected;

  const FullposUserMenu({
    super.key,
    required this.data,
    required this.showName,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final menuWidth = math.min(math.max(280.0, screenWidth - 24), 328.0);

    return PopupMenuButton<FullposMenuAction>(
      tooltip: 'Cuenta',
      onSelected: onSelected,
      offset: const Offset(0, 12),
      position: PopupMenuPosition.under,
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      constraints: BoxConstraints(
        minWidth: menuWidth,
        maxWidth: menuWidth,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      itemBuilder: (context) {
        return [
          PopupMenuItem<FullposMenuAction>(
            enabled: false,
            height: 0,
            padding: EdgeInsets.zero,
            child: _AccountMenuHeader(
              width: menuWidth,
              data: data,
            ),
          ),
          const PopupMenuDivider(height: 10),
          _menuItem(
            value: FullposMenuAction.settings,
            icon: Icons.settings_outlined,
            label: 'Configuracion',
          ),
          const PopupMenuDivider(height: 14),
          _menuItem(
            value: FullposMenuAction.logout,
            icon: Icons.logout_rounded,
            label: 'Cerrar sesion',
            isDestructive: true,
          ),
        ];
      },
      child: _UserMenuButton(
        userName: data.userName,
        userStatusLabel: data.userStatusLabel,
        initials: _buildInitials(data.userName),
        showName: showName,
      ),
    );
  }

  PopupMenuItem<FullposMenuAction> _menuItem({
    required FullposMenuAction value,
    required IconData icon,
    required String label,
    bool isDestructive = false,
  }) {
    final iconColor = isDestructive ? AppColors.error : AppColors.textSecondary;
    final textColor = isDestructive ? AppColors.error : AppColors.textPrimary;

    return PopupMenuItem<FullposMenuAction>(
      value: value,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildInitials(String input) {
    final parts = input
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'AP';
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}

class _UserMenuButton extends StatelessWidget {
  final String userName;
  final String userStatusLabel;
  final String initials;
  final bool showName;

  const _UserMenuButton({
    required this.userName,
    required this.userStatusLabel,
    required this.initials,
    required this.showName,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowSm,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.info],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showName) ...[
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 146),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                      Text(
                        userStatusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 6),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountMenuHeader extends StatelessWidget {
  final double width;
  final AppBarAccountMenuData data;

  const _AccountMenuHeader({
    required this.width,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF7FBFF), Color(0xFFFFFFFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.companyName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                data.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${data.userStatusLabel} / ${data.roleLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppBarAccountMenuData {
  final String companyName;
  final String userName;
  final String roleLabel;
  final String userStatusLabel;
  final String cashRegisterLabel;
  final CashRegisterState cashRegisterState;

  const AppBarAccountMenuData({
    required this.companyName,
    required this.userName,
    required this.roleLabel,
    required this.userStatusLabel,
    required this.cashRegisterLabel,
    required this.cashRegisterState,
  });
}
