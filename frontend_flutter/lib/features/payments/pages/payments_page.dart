import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/status_badge.dart';
import '../models/license_payment_order.dart';
import '../services/license_payments_service.dart';
import '../widgets/create_payment_link_panel.dart';
import '../widgets/payment_order_detail_panel.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  late LicensePaymentsService _service;
  List<LicensePaymentOrder> _orders = [];
  int _total = 0;
  int _page = 1;
  int _limit = 20;
  bool _loading = true;
  String? _error;
  String? _statusFilter;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionManager>();
    _service = LicensePaymentsService(sessionManager: session);
    _loadOrders();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.listPaymentOrders(
        page: _page,
        limit: _limit,
        status: _statusFilter,
      );
      setState(() {
        _orders = result['orders'] as List<LicensePaymentOrder>;
        _total = result['total'] as int;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _setFilter(String? status) {
    setState(() {
      _statusFilter = status;
      _page = 1;
    });
    _loadOrders();
  }

  void _showCreateLinkPanel() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 500,
          child: CreatePaymentLinkPanel(
            service: _service,
            onCreated: () {
              _loadOrders();
            },
          ),
        ),
      ),
    );
  }

  void _showOrderDetail(LicensePaymentOrder order) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 600,
          child: PaymentOrderDetailPanel(
            order: order,
            service: _service,
            onUpdated: () {
              _loadOrders();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: isMobile
          ? null
          : AppBar(
              title: const Text('Órdenes de pago'),
              backgroundColor: AppColors.surface,
              elevation: 0,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: _showCreateLinkPanel,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Nueva orden de pago'),
                  ),
                ),
              ],
            ),
      body: Column(
        children: [
          if (isMobile)
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: SizedBox(
                height: 42,
                child: ElevatedButton.icon(
                  onPressed: _showCreateLinkPanel,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Nueva orden de pago'),
                ),
              ),
            ),
          _buildFilterBar(),
          Expanded(child: _buildBody()),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final filters = [
      {'label': 'Todos', 'value': null as String?},
      {'label': 'Pendientes', 'value': 'PENDING'},
      {'label': 'Pagados', 'value': 'PAID'},
      {'label': 'Fallidos', 'value': 'FAILED'},
      {'label': 'Cancelados', 'value': 'CANCELLED'},
    ];

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: isMobile
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _buildFilterChips(filters)),
            )
          : Row(
              children: [
                ..._buildFilterChips(filters),
                const Spacer(),
                Text(
                  '$_total órdenes',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _buildFilterChips(List<Map<String, String?>> filters) {
    return filters.map((f) {
      final isActive = _statusFilter == f['value'];
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Text(f['label']!),
          selected: isActive,
          onSelected: (_) => _setFilter(f['value']),
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surface,
          side: BorderSide(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            fontSize: 12,
            color: isActive ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }).toList();
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.red[300], size: 48),
            const SizedBox(height: 16),
            Text(
              'Error al cargar órdenes',
              style: TextStyle(color: Colors.grey[300], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadOrders,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              color: Colors.grey[600],
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'No hay órdenes de pago',
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _statusFilter != null
                  ? 'No hay órdenes con estado $_statusFilter'
                  : 'Crea una nueva orden de pago para comenzar',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showCreateLinkPanel,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Crear orden de pago'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length,
      itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
    );
  }

  Widget _buildOrderCard(LicensePaymentOrder order) {
    final statusBadge = StatusBadge.fromString(_getStatusLabel(order.status));

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showOrderDetail(order),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: _getStatusColor(order.status),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          order.customerName ??
                              'Cliente #${order.customerId.substring(0, 8)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        statusBadge,
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (order.projectName != null) ...[
                          Icon(
                            Icons.folder_outlined,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            order.projectName!,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                        Icon(
                          Icons.calendar_today,
                          size: 12,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${order.months} meses',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.attach_money,
                          size: 12,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${order.totalAmount.toStringAsFixed(2)} ${order.currency}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Creada: ${_formatDate(order.createdAt)}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(Icons.chevron_right, color: Colors.grey[600], size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    final totalPages = (_total / _limit).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: _page > 1
                ? () {
                    setState(() => _page--);
                    _loadOrders();
                  }
                : null,
            color: Colors.grey[400],
          ),
          Text(
            'Página $_page de $totalPages',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: _page < totalPages
                ? () {
                    setState(() => _page++);
                    _loadOrders();
                  }
                : null,
            color: Colors.grey[400],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return Colors.orange;
      case 'APPROVED':
        return Colors.lightBlue;
      case 'PAID':
        return Colors.green;
      case 'FAILED':
        return Colors.red;
      case 'CANCELLED':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
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
