import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../customers/services/customers_service.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/customer.dart';

class CustomerDetailDrawer extends StatelessWidget {
  final Customer customer;
  final VoidCallback onClose;
  final VoidCallback? onDelete;
  final double width;

  const CustomerDetailDrawer({
    super.key,
    required this.customer,
    required this.onClose,
    this.onDelete,
    this.width = AppSpacing.detailPanelWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
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
                Expanded(
                  child: Text(
                    customer.nombreNegocio,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                  // Avatar
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          _initial,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Fields
                  _DetailSection(title: 'Información del cliente', children: [
                    _DetailRow(
                      label: 'Negocio',
                      value: customer.nombreNegocio,
                    ),
                    if (customer.contactoNombre != null)
                      _DetailRow(
                        label: 'Contacto',
                        value: customer.contactoNombre!,
                      ),
                    if (customer.contactoTelefono != null)
                      _DetailRow(
                        label: 'Teléfono',
                        value: customer.contactoTelefono!,
                      ),
                    if (customer.contactoEmail != null)
                      _DetailRow(
                        label: 'Email',
                        value: customer.contactoEmail!,
                      ),
                    if (customer.rolNegocio != null)
                      _DetailRow(
                        label: 'Rol',
                        value: customer.rolNegocio!,
                      ),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  _DetailSection(title: 'IDs del sistema', children: [
                    _DetailRow(
                      label: 'Client ID',
                      value: customer.id,
                      mono: true,
                    ),
                    _DetailRow(
                      label: 'Business ID',
                      value: customer.businessId ?? '—',
                      mono: true,
                    ),
                    if (customer.createdAt != null)
                      _DetailRow(
                        label: 'Registro',
                        value: DateFormat('dd/MM/yyyy HH:mm')
                            .format(customer.createdAt!.toLocal()),
                      ),
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
                  _ActionButton(
                    label: 'Crear licencia',
                    icon: Icons.add_circle_outline_rounded,
                    onTap: () {},
                  ),
                  _ActionButton(
                    label: 'Ver licencias',
                    icon: Icons.vpn_key_outlined,
                    onTap: () {},
                  ),
                  _ActionButton(
                    label: 'Asignar Business ID',
                    icon: Icons.link_rounded,
                    onTap: () {},
                  ),
                  _ActionButton(
                    label: 'Token reset',
                    icon: Icons.restart_alt_rounded,
                    onTap: () {},
                  ),
                  _ActionButton(
                    label: 'Editar cliente',
                    icon: Icons.edit_outlined,
                    onTap: () => _openEditDialog(context),
                  ),
                  _ActionButton(
                    label: 'Vista completa',
                    icon: Icons.open_in_new_rounded,
                    onTap: () {},
                  ),
                  if (onDelete != null)
                    _ActionButton(
                      label: 'Eliminar cliente',
                      icon: Icons.delete_outline_rounded,
                      onTap: onDelete!,
                      isDestructive: true,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _initial {
    final name = customer.nombreNegocio.trim();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _openEditDialog(BuildContext context) async {
    final nameCtrl = TextEditingController(text: customer.nombreNegocio);
    final contactNameCtrl = TextEditingController(text: customer.contactoNombre ?? '');
    final phoneCtrl = TextEditingController(text: customer.contactoTelefono ?? '');
    final emailCtrl = TextEditingController(text: customer.contactoEmail ?? '');
    final roleCtrl = TextEditingController(text: customer.rolNegocio ?? '');

    final formKey = GlobalKey<FormState>();

    final session = Provider.of<SessionManager>(context, listen: false);
    final service = CustomersService(sessionManager: session);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar cliente'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre del negocio'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                TextFormField(controller: contactNameCtrl, decoration: const InputDecoration(labelText: 'Contacto')),
                TextFormField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Teléfono'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null),
                TextFormField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
                TextFormField(controller: roleCtrl, decoration: const InputDecoration(labelText: 'Rol')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await service.updateCustomer(customer.id, {
                  'nombre_negocio': nameCtrl.text.trim(),
                  'contacto_nombre': contactNameCtrl.text.trim().isEmpty ? null : contactNameCtrl.text.trim(),
                  'contacto_telefono': phoneCtrl.text.trim(),
                  'contacto_email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                  'rol_negocio': roleCtrl.text.trim().isEmpty ? null : roleCtrl.text.trim(),
                });
                Navigator.pop(ctx, true);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      // refresh by navigating back to parent or closing drawer then re-open could be handled by caller
      showDialog<void>(context: context, builder: (_) => AlertDialog(title: const Text('Guardado'), content: const Text('Cliente actualizado correctamente.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
    }
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
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
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

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
            width: 90,
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
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
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

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.error : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 10,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.sm),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
