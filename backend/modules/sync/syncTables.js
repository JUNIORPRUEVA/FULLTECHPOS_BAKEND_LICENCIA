// Central registry of syncable tables.
// Keep this explicit (no guessing at runtime), to avoid writing arbitrary client-provided keys into SQL.

// Columns here are the BUSINESS columns we accept from the client.
// Server-managed columns: company_id, created_at, updated_at, is_deleted.

const SYNC_TABLES = [
  {
    name: 'clients',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'nombre',
      'telefono',
      'direccion',
      'rnc',
      'cedula',
      'is_active',
      'has_credit',
      'deleted_at_ms',
      'created_at_ms',
      'updated_at_ms'
    ]
  },
  {
    name: 'categories',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['name', 'is_active', 'deleted_at_ms', 'created_at_ms', 'updated_at_ms']
  },
  {
    name: 'suppliers',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['name', 'phone', 'note', 'is_active', 'deleted_at_ms', 'created_at_ms', 'updated_at_ms']
  },
  {
    name: 'products',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'code',
      'name',
      'image_path',
      'category_id',
      'supplier_id',
      'purchase_price',
      'sale_price',
      'stock',
      'stock_min',
      'is_active',
      'deleted_at_ms',
      'created_at_ms',
      'updated_at_ms'
    ]
  },
  {
    name: 'stock_movements',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['product_id', 'type', 'quantity', 'note', 'user_id', 'created_at_ms']
  },
  {
    name: 'compras_ordenes',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'supplier_id',
      'status',
      'subtotal',
      'tax_rate',
      'tax_amount',
      'total',
      'is_auto',
      'notes',
      'created_at_ms',
      'updated_at_ms',
      'received_at_ms',
      'purchase_date_ms'
    ]
  },
  {
    name: 'compras_detalle',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['order_id', 'product_id', 'qty', 'unit_cost', 'total_line', 'created_at_ms']
  },
  {
    name: 'business_info',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['name', 'phone', 'address', 'rnc', 'slogan', 'updated_at_ms']
  },
  {
    name: 'app_settings',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['itbis_enabled_default', 'itbis_rate', 'ticket_size', 'updated_at_ms']
  },
  {
    name: 'ncf_books',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'type',
      'series',
      'from_n',
      'to_n',
      'next_n',
      'is_active',
      'expires_at_ms',
      'note',
      'created_at_ms',
      'updated_at_ms',
      'deleted_at_ms'
    ]
  },
  {
    name: 'customers_ncf_usage',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['sale_id', 'ncf_book_id', 'ncf_full', 'created_at_ms']
  },
  {
    name: 'users',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'username',
      'pin',
      'role',
      'is_active',
      'created_at_ms',
      'updated_at_ms',
      'deleted_at_ms',
      'display_name',
      'permissions',
      'password_hash'
    ]
  },
  {
    name: 'cash_sessions',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'opened_by_user_id',
      'user_name',
      'opened_at_ms',
      'initial_amount',
      'closing_amount',
      'expected_cash',
      'difference',
      'closed_at_ms',
      'closed_by_user_id',
      'note',
      'status'
    ]
  },
  {
    name: 'cash_movements',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['session_id', 'type', 'amount', 'note', 'created_at_ms', 'reason', 'user_id']
  },
  {
    name: 'sales',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'local_code',
      'kind',
      'status',
      'customer_id',
      'customer_name_snapshot',
      'customer_phone_snapshot',
      'customer_rnc_snapshot',
      'itbis_enabled',
      'itbis_rate',
      'discount_total',
      'subtotal',
      'itbis_amount',
      'total',
      'payment_method',
      'paid_amount',
      'change_amount',
      'fiscal_enabled',
      'ncf_full',
      'ncf_type',
      'session_id',
      'cash_session_id',
      'created_at_ms',
      'updated_at_ms',
      'deleted_at_ms'
    ]
  },
  {
    name: 'sale_items',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'sale_id',
      'product_id',
      'product_code_snapshot',
      'product_name_snapshot',
      'qty',
      'unit_price',
      'purchase_price_snapshot',
      'discount_line',
      'total_line',
      'created_at_ms'
    ]
  },
  {
    name: 'returns',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['original_sale_id', 'return_sale_id', 'note', 'created_at_ms']
  },
  {
    name: 'return_items',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['return_id', 'sale_item_id', 'product_id', 'description', 'qty', 'price', 'total']
  },
  {
    name: 'credit_payments',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['sale_id', 'client_id', 'amount', 'method', 'note', 'created_at_ms', 'user_id']
  },
  {
    name: 'loans',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'client_id',
      'type',
      'principal',
      'interest_rate',
      'interest_mode',
      'frequency',
      'installments_count',
      'start_date_ms',
      'total_due',
      'balance',
      'late_fee',
      'status',
      'note',
      'created_at_ms',
      'updated_at_ms',
      'deleted_at_ms'
    ]
  },
  {
    name: 'loan_collaterals',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['loan_id', 'description', 'estimated_value', 'serial', 'condition']
  },
  {
    name: 'loan_installments',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['loan_id', 'number', 'due_date_ms', 'amount_due', 'amount_paid', 'status']
  },
  {
    name: 'loan_payments',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: ['loan_id', 'paid_at_ms', 'amount', 'method', 'note']
  },
  {
    name: 'pos_tickets',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'ticket_name',
      'user_id',
      'client_id',
      'itbis_enabled',
      'itbis_rate',
      'discount_total',
      'created_at_ms',
      'updated_at_ms'
    ]
  },
  {
    name: 'pos_ticket_items',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'ticket_id',
      'product_id',
      'product_code_snapshot',
      'product_name_snapshot',
      'description',
      'qty',
      'price',
      'cost',
      'discount_line',
      'total_line'
    ]
  },
  {
    name: 'quotes',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'client_id',
      'user_id',
      'ticket_name',
      'subtotal',
      'itbis_enabled',
      'itbis_rate',
      'itbis_amount',
      'discount_total',
      'total',
      'status',
      'notes',
      'created_at_ms',
      'updated_at_ms'
    ]
  },
  {
    name: 'quote_items',
    idColumn: 'id',
    updatedAtColumn: 'updated_at',
    businessColumns: [
      'quote_id',
      'product_id',
      'product_code_snapshot',
      'product_name_snapshot',
      'description',
      'qty',
      'unit_price',
      'price',
      'cost',
      'discount_line',
      'total_line'
    ]
  },
  // app_config/printer_settings are intentionally excluded from sync endpoints by default.
];

module.exports = { SYNC_TABLES };
