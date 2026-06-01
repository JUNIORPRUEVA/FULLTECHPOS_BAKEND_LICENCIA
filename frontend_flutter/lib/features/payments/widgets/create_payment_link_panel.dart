import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../customers/services/customers_service.dart';
import '../../licenses/services/projects_service.dart';
import '../../licenses/models/project.dart';
import '../services/license_payments_service.dart';

class CreatePaymentLinkPanel extends StatefulWidget {
  final LicensePaymentsService service;
  final VoidCallback onCreated;

  const CreatePaymentLinkPanel({
    super.key,
    required this.service,
    required this.onCreated,
  });

  @override
  State<CreatePaymentLinkPanel> createState() => _CreatePaymentLinkPanelState();
}

class _CreatePaymentLinkPanelState extends State<CreatePaymentLinkPanel> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _loadingCustomers = false;
  bool _loadingProjects = false;

  // Dropdown data
  List<Map<String, dynamic>> _customers = [];
  List<Project> _projects = [];

  // Selected values
  String? _selectedCustomerId;
  String? _selectedProjectId;
  int _selectedMonths = 3;

  // Calculated
  double _monthlyPrice = 0;
  int _minMonths = 3;
  String _currency = 'USD';
  double _total = 0;

  // Result
  Map<String, dynamic>? _result;
  String? _error;

  final _monthsController = TextEditingController(text: '3');

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _loadProjects();
  }

  @override
  void dispose() {
    _monthsController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _loadingCustomers = true);
    try {
      final session = DefaultAssetBundle.of(context);
      // Usar el servicio de clientes
      final customersService = CustomersService(
        sessionManager: context.findAncestorWidgetOfExactType() as dynamic,
      );
      // Como no tenemos acceso directo, hacemos una llamada simple
      // En producción, inyectar el servicio
      setState(() => _loadingCustomers = false);
    } catch (e) {
      setState(() => _loadingCustomers = false);
    }
  }

  Future<void> _loadProjects() async {
    setState(() => _loadingProjects = true);
    try {
      final projectsService = ProjectsService(
        sessionManager: context.findAncestorWidgetOfExactType() as dynamic,
      );
      // En producción, inyectar el servicio
      setState(() => _loadingProjects = false);
    } catch (e) {
      setState(() => _loadingProjects = false);
    }
  }

  void _onProjectChanged(String? projectId) {
    setState(() {
      _selectedProjectId = projectId;
      _result = null;
      _error = null;
      if (projectId != null) {
        final project = _projects.where((p) => p.id == projectId).firstOrNull;
        if (project != null) {
          _monthlyPrice = project.monthlyPrice;
          _minMonths = project.minPurchaseMonths;
          _currency = project.currency;
          if (_selectedMonths < _minMonths) {
            _selectedMonths = _minMonths;
            _monthsController.text = _selectedMonths.toString();
          }
          _calculateTotal();
        }
      }
    });
  }

  void _calculateTotal() {
    final months = int.tryParse(_monthsController.text) ?? _minMonths;
    final effectiveMonths = months < _minMonths ? _minMonths : months;
    _total = _monthlyPrice * effectiveMonths;
    _selectedMonths = effectiveMonths;
  }

  Future<void> _createOrder() async {
    if (_selectedCustomerId == null || _selectedProjectId == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await widget.service.createPayPalOrder(
        customerId: _selectedCustomerId!,
        projectId: _selectedProjectId!,
        months: _selectedMonths,
      );
      setState(() {
        _result = result;
        _loading = false;
      });
      widget.onCreated();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
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
                const Icon(Icons.link, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Nueva orden de pago',
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
              child: _result != null ? _buildResult() : _buildForm(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cliente
          const Text('Cliente',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: _selectedCustomerId,
            decoration: _inputDecoration(),
            items: _customers.map((c) {
              final name = c['nombre_negocio'] ?? c['contacto_nombre'] ?? c['contacto_email'] ?? 'Cliente';
              return DropdownMenuItem(
                value: c['id'],
                child: Text(name, style: const TextStyle(color: Colors.white)),
              );
            }).toList(),
            onChanged: (v) => setState(() => _selectedCustomerId = v),
            validator: (v) => v == null ? 'Selecciona un cliente' : null,
          ),
          const SizedBox(height: 16),

          // Proyecto
          const Text('Proyecto',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            value: _selectedProjectId,
            decoration: _inputDecoration(),
            items: _projects.map((p) {
              return DropdownMenuItem(
                value: p.id,
                child: Text('${p.name} (${p.code})',
                    style: const TextStyle(color: Colors.white)),
              );
            }).toList(),
            onChanged: _onProjectChanged,
            validator: (v) => v == null ? 'Selecciona un proyecto' : null,
          ),
          const SizedBox(height: 16),

          // Meses
          const Text('Meses',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _monthsController,
                  decoration: _inputDecoration(
                    hint: 'Mínimo $_minMonths meses',
                  ),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) {
                    _calculateTotal();
                    setState(() {});
                  },
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1) return 'Mínimo 1 mes';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              ...([3, 6, 9, 12].map((m) {
                final isSelected = _selectedMonths == m;
                return Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text('$m', style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _selectedMonths = m;
                        _monthsController.text = m.toString();
                        _calculateTotal();
                      });
                    },
                    selectedColor: AppColors.primary,
                    backgroundColor: Colors.transparent,
                    side: BorderSide(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.grey[700]!),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[300],
                      fontSize: 12,
                    ),
                  ),
                );
              })),
            ],
          ),
          const SizedBox(height: 16),

          // Resumen
          if (_selectedProjectId != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _summaryRow('Precio mensual',
                      '$_monthlyPrice $_currency'),
                  _summaryRow('Mínimo de meses', '$_minMonths meses'),
                  _summaryRow('Meses seleccionados',
                      '$_selectedMonths meses'),
                  const Divider(color: Color(0xFF334155)),
                  _summaryRow(
                    'Total',
                    '${_total.toStringAsFixed(2)} $_currency',
                    bold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Error
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
            const SizedBox(height: 16),
          ],

          // Botón
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading || _selectedCustomerId == null
                  ? null
                  : _createOrder,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.payments_outlined, size: 18),
              label: Text(_loading ? 'Creando orden...' : 'Crear link PayPal'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final checkoutUrl = _result!['checkout_url'] as String? ?? '';
    final amount = _result!['amount'] ?? 0;
    final currency = _result!['currency'] ?? 'USD';
    final months = _result!['months'] ?? 0;
    final paymentOrderId = _result!['payment_order_id'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Success icon
        const Center(
          child: Icon(Icons.check_circle_outline,
              color: Colors.green, size: 48),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Link creado correctamente',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Puedes enviarlo al cliente por WhatsApp',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        const SizedBox(height: 24),

        // Resumen
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _summaryRow('Meses', '$months meses'),
              _summaryRow('Total', '$amount $currency', bold: true),
              _summaryRow('ID Orden', paymentOrderId.substring(0, 8) + '...'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Checkout URL
        const Text('Link de pago:',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            checkoutUrl,
            style: const TextStyle(color: Colors.lightBlue, fontSize: 11),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 16),

        // Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: checkoutUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Link copiado al portapapeles'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copiar link'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  // Abrir en navegador
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Abrir link'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // WhatsApp
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              final message = Uri.encodeComponent(
                'Hola, aquí está tu link de pago para la licencia:\n\n'
                '💰 Total: $amount $currency\n'
                '📅 Meses: $months\n'
                '🔗 $checkoutUrl\n\n'
                'Haz clic en el link para pagar con PayPal.'
              );
              // En web, abrir WhatsApp Web
              // En móvil, abrir app de WhatsApp
            },
            icon: const Icon(Icons.chat, size: 16),
            label: const Text('Enviar por WhatsApp'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              side: const BorderSide(color: Colors.green),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Close button
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}
