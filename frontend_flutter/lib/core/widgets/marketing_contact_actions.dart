import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'external_url_opener.dart';

class MarketingContact {
  final String businessName;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? licenseStatus;
  final String? productName;
  final String? licenseLabel;
  final DateTime? expiresAt;

  const MarketingContact({
    required this.businessName,
    this.contactName,
    this.phone,
    this.email,
    this.licenseStatus,
    this.productName,
    this.licenseLabel,
    this.expiresAt,
  });

  String get displayName {
    final name = contactName?.trim();
    return name != null && name.isNotEmpty ? name : businessName;
  }

  String get cleanPhone => _cleanWhatsAppPhone(phone);

  bool get hasWhatsApp => cleanPhone.isNotEmpty;
}

class MarketingWhatsAppButton extends StatelessWidget {
  final MarketingContact contact;
  final bool dense;

  const MarketingWhatsAppButton({
    super.key,
    required this.contact,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'WhatsApp',
      onPressed: () => showMarketingContactDialog(context, contact),
      icon: const Icon(Icons.chat_outlined),
      color: AppColors.success,
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints.tightFor(
        width: dense ? 34 : 38,
        height: dense ? 34 : 38,
      ),
      padding: EdgeInsets.zero,
    );
  }
}

class MarketingContactPanel extends StatelessWidget {
  final MarketingContact contact;

  const MarketingContactPanel({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.campaign_outlined, size: 18, color: AppColors.primary),
              SizedBox(width: AppSpacing.sm),
              Text(
                'Marketing y seguimiento',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: () => showMarketingContactDialog(context, contact),
                icon: const Icon(Icons.chat_outlined, size: 17),
                label: const Text('WhatsApp'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyTemplate(context, contact),
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: const Text('Copiar mensaje'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> showMarketingContactDialog(
  BuildContext context,
  MarketingContact contact,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _MarketingMessageDialog(contact: contact),
  );
}

Future<void> _copyTemplate(
  BuildContext context,
  MarketingContact contact,
) async {
  await Clipboard.setData(
    ClipboardData(
      text: _buildMarketingMessage(contact, _MarketingTemplate.checkIn),
    ),
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Mensaje copiado')));
}

class _MarketingMessageDialog extends StatefulWidget {
  final MarketingContact contact;

  const _MarketingMessageDialog({required this.contact});

  @override
  State<_MarketingMessageDialog> createState() =>
      _MarketingMessageDialogState();
}

class _MarketingMessageDialogState extends State<_MarketingMessageDialog> {
  late final TextEditingController _messageCtrl;
  _MarketingTemplate _template = _MarketingTemplate.checkIn;

  @override
  void initState() {
    super.initState();
    _messageCtrl = TextEditingController(
      text: _buildMarketingMessage(widget.contact, _template),
    );
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  void _setTemplate(_MarketingTemplate template) {
    setState(() {
      _template = template;
      _messageCtrl.text = _buildMarketingMessage(widget.contact, template);
    });
  }

  Future<void> _copyMessage() async {
    await Clipboard.setData(ClipboardData(text: _messageCtrl.text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mensaje copiado')));
  }

  Future<void> _sendWhatsApp() async {
    final message = _messageCtrl.text.trim();
    if (message.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: message));
    final phone = widget.contact.cleanPhone;
    final url = phone.isEmpty
        ? 'https://web.whatsapp.com/send?text=${Uri.encodeComponent(message)}'
        : 'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';
    final uri = Uri.parse(url);

    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException catch (e) {
      debugPrint('No se pudo abrir WhatsApp con url_launcher: ${e.message}');
    } catch (e) {
      debugPrint('No se pudo abrir WhatsApp: $e');
    }
    if (!launched) {
      launched = await openExternalUrl(url);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched
              ? 'Mensaje copiado y WhatsApp abierto'
              : 'Mensaje copiado. No se pudo abrir WhatsApp',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contact = widget.contact;
    return AlertDialog(
      title: const Text('Marketing y seguimiento'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ContactHeader(contact: contact),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<_MarketingTemplate>(
              initialValue: _template,
              decoration: const InputDecoration(
                labelText: 'Plantilla',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: _MarketingTemplate.checkIn,
                  child: Text('Seguimiento'),
                ),
                DropdownMenuItem(
                  value: _MarketingTemplate.renewal,
                  child: Text('Renovacion'),
                ),
                DropdownMenuItem(
                  value: _MarketingTemplate.demo,
                  child: Text('Demo a venta'),
                ),
                DropdownMenuItem(
                  value: _MarketingTemplate.support,
                  child: Text('Soporte'),
                ),
                DropdownMenuItem(
                  value: _MarketingTemplate.custom,
                  child: Text('Personalizado'),
                ),
              ],
              onChanged: (value) {
                if (value != null) _setTemplate(value);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _messageCtrl,
              minLines: 6,
              maxLines: 9,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Mensaje',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_template != _MarketingTemplate.custom) {
                  setState(() => _template = _MarketingTemplate.custom);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        OutlinedButton.icon(
          onPressed: _copyMessage,
          icon: const Icon(Icons.copy_rounded, size: 17),
          label: const Text('Copiar'),
        ),
        FilledButton.icon(
          onPressed: _sendWhatsApp,
          icon: const Icon(Icons.chat_outlined, size: 17),
          label: const Text('WhatsApp'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ContactHeader extends StatelessWidget {
  final MarketingContact contact;

  const _ContactHeader({required this.contact});

  @override
  Widget build(BuildContext context) {
    final phone = contact.phone?.trim();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.person_pin_circle_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.businessName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  [
                    if (contact.contactName?.trim().isNotEmpty == true)
                      contact.contactName!.trim(),
                    if (phone != null && phone.isNotEmpty) phone,
                    if (contact.licenseStatus?.trim().isNotEmpty == true)
                      contact.licenseStatus!.trim(),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _MarketingTemplate { checkIn, renewal, demo, support, custom }

String _buildMarketingMessage(
  MarketingContact contact,
  _MarketingTemplate template,
) {
  final name = contact.displayName;
  final business = contact.businessName;
  final product = contact.productName?.trim().isNotEmpty == true
      ? contact.productName!.trim()
      : 'la app';
  final status = contact.licenseStatus?.trim();
  final expires = _formatDate(contact.expiresAt);

  switch (template) {
    case _MarketingTemplate.renewal:
      return 'Hola $name, te escribo de Appyra para dar seguimiento a $business. '
          'Tu licencia de $product ${expires == null ? 'necesita revision' : 'vence el $expires'}. '
          'Puedo ayudarte con la renovacion para que el servicio siga activo sin interrupciones.';
    case _MarketingTemplate.demo:
      return 'Hola $name, espero que todo vaya bien con $business. '
          'Queria saber como les ha ido probando $product y si ya desean activar la licencia completa.';
    case _MarketingTemplate.support:
      return 'Hola $name, soy de Appyra. '
          'Estoy dando seguimiento a $business para confirmar que $product este funcionando correctamente. '
          'Si tienes alguna duda o necesitas soporte, me escribes por aqui.';
    case _MarketingTemplate.custom:
    case _MarketingTemplate.checkIn:
      return 'Hola $name, soy de Appyra. '
          'Queria saber como va $business con $product'
          '${status == null || status.isEmpty ? '' : ' (estado: $status)'}. '
          'Quedo atento para ayudarte con cualquier cosa.';
  }
}

String _cleanWhatsAppPhone(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return '';
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('00')) digits = digits.substring(2);
  if (digits.length == 10 &&
      (digits.startsWith('809') ||
          digits.startsWith('829') ||
          digits.startsWith('849'))) {
    digits = '1$digits';
  }
  return digits;
}

String? _formatDate(DateTime? value) {
  if (value == null) return null;
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year}';
}
