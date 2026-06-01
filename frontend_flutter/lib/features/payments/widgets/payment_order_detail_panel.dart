import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/status_badge.dart';
import '../models/license_payment_order.dart';
import '../services/license_payments_service.dart';

class PaymentOrderDetailPanel extends StatefulWidget {
  final LicensePaymentOrder order;
  final LicensePaymentsService service;
  final VoidCallback onUpdated;

  const PaymentOrderDetailPanel({
    super.key,
    required this.order,
    required this.service,
    required this.onUpdated,
  });

  @override
  State<PaymentOrderDetailPanel> createState() =>
      _PaymentOrderDetailPanelState();
}

class _PaymentOrderDetailPanelState extends State<PaymentOrderDetailPanel> {
  LicensePaymentOrder? _order;
  bool _loading = false;
  bool _capturing = false;
  String? _error;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final order = await widget.service.getPaymentOrderDetail(_order!.id);
      setState(() {
        _order = order;
        _loading = false;
      });
      widget.onUpdated();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _capturePayment() async {
    if (_order!.providerOrderId == null) return;

    setState(() {
      _capturing = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final result = await widget.service.capturePayPalOrder(
        paypalOrderId: _order!.providerOrderId!,
        paymentOrderId: _order!.id,
      );
      setState(() {
        _capturing = false;
        _successMessage = result['message'] as String? ??
            'Pago capturado correctamente';
      });
      await _refresh();
    } catch (e) {
      setState(() {
        _capturing = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E293B),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF334155)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Detalle de orden de pago',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final order = _order!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status badge
        Row(
          children: [
            StatusBadge.fromString(_statusLabel(order.status)),
            const Spacer(),
            Text(
              'ID: ${order.id.substring(0, 8)}...',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Info sections
        _section('Cliente', [
          _infoRow('Nombre', order.customerName ?? '—'),
          _infoRow('ID', order.customerId.substring(0, 8) + '...'),
        ]),
        const SizedBox(height: 12),

        _section('Proyecto', [
          _infoRow('Nombre', order.projectName ?? '—'),
          _infoRow('Código', order.projectCode ?? '—'),
        ]),
        const SizedBox(height: 12),

        _section('Detalles del pago', [
          _infoRow('Meses', '${order.months} meses'),
          _infoRow('Precio mensual',
              '${order.monthlyPrice.toStringAsFixed(2)} ${order.currency}'),
          _infoRow('Total',
              '${order.totalAmount.toStringAsFixed(2)} ${order.currency}',
              bold: true),
          _infoRow('Moneda', order.currency),
          _infoRow('Proveedor', order.provider.toUpperCase()),
        ]),
        const SizedBox(height: 12),

        _section('Proveedor', [
          _infoRow('Order ID', order.providerOrderId ?? '—'),
          _infoRow('Capture ID', order.providerCaptureId ?? '—'),
          if (order.checkoutUrl != null)
            _infoRow('Checkout URL', order.checkoutUrl!, isUrl: true),
        ]),
        const SizedBox(height: 12),

        _section('Fechas', [
          _infoRow('Creada', _formatDate(order.createdAt)),
          _infoRow('Actualizada', _formatDate(order.updatedAt)),
          if (order.paidAt != null)
            _infoRow('Pagada', _formatDate(order.paidAt!)),
        ]),
        const SizedBox(height: 16),

        // Messages
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),

        if (_successMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_successMessage!,
                style: const TextStyle(color: Colors.green, fontSize: 12)),
          ),

        // Actions
        if (order.isPending && order.providerOrderId != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _capturing ? null : _capturePayment,
              icon: _capturing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: Text(_capturing
                  ? 'Capturando pago...'
                  : 'Capturar pago PayPal'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

        if (order.isPending && order.checkoutUrl != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: order.checkoutUrl!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Link copiado al portapapeles'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copiar link de pago'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF334155)),
              ),
            ),
          ),
        ],

        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _refresh,
            child: const Text('Refrescar'),
          ),
        ),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value,
      {bool bold = false, bool isUrl = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isUrl ? Colors.lightBlue : Colors.white,
                fontSize: 12,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return 'Pendiente';
      case 'APPROVED':
        return 'Aprobado';
      case 'PAID':
        return 'Pagado';
      case 'FAILED':
        return 'Fallido';
      case 'CANCELLED':
        return 'Cancelado';
      default:
        return status;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}
