# [TABLAS LOCALES DETECTADAS] (SQLite - Flutter)

Fuente (NO inventado):
- `C:\Users\PC\Desktop\nilkas\lib\core\db\tables.dart`
- `C:\Users\PC\Desktop\nilkas\lib\core\db\app_db.dart` (`_createFullSchema` + migraciones)

> Nota: `pawn` y `services` están declaradas en `DbTables` pero **no hay ningún `CREATE TABLE`** en `app_db.dart` para ellas, así que **no se consideran tablas existentes**.

## Tablas de negocio (SE SINCRONIZAN por defecto)

- tabla: app_config
  - columnas: key TEXT (PK), value TEXT NOT NULL, updated_at_ms INTEGER NOT NULL
  - comentario: configuración general (key/value). Por defecto incluida (si luego se decide que es “solo local”, se puede excluir por configuración de sync).

- tabla: clients
  - columnas: id INTEGER PK AUTOINCREMENT, nombre TEXT NOT NULL, telefono TEXT, direccion TEXT, rnc TEXT, cedula TEXT, is_active INTEGER NOT NULL DEFAULT 1, has_credit INTEGER NOT NULL DEFAULT 0, deleted_at_ms INTEGER, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL

- tabla: categories
  - columnas: id INTEGER PK AUTOINCREMENT, name TEXT NOT NULL, is_active INTEGER NOT NULL DEFAULT 1, deleted_at_ms INTEGER, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL

- tabla: suppliers
  - columnas: id INTEGER PK AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, note TEXT, is_active INTEGER NOT NULL DEFAULT 1, deleted_at_ms INTEGER, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL

- tabla: products
  - columnas: id INTEGER PK AUTOINCREMENT, code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, image_path TEXT, category_id INTEGER, supplier_id INTEGER, purchase_price REAL NOT NULL DEFAULT 0.0, sale_price REAL NOT NULL DEFAULT 0.0, stock REAL NOT NULL DEFAULT 0.0, stock_min REAL NOT NULL DEFAULT 0.0, is_active INTEGER NOT NULL DEFAULT 1, deleted_at_ms INTEGER, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL
  - relaciones: category_id -> categories(id), supplier_id -> suppliers(id)

- tabla: stock_movements
  - columnas (full schema): id INTEGER PK AUTOINCREMENT, product_id INTEGER NOT NULL, type TEXT NOT NULL, quantity REAL NOT NULL, note TEXT, created_at_ms INTEGER NOT NULL
  - migración v20 agrega: user_id INTEGER (opcional)
  - relaciones: product_id -> products(id)

- tabla: compras_ordenes
  - columnas: id INTEGER PK AUTOINCREMENT, supplier_id INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'PENDIENTE', subtotal REAL NOT NULL DEFAULT 0, tax_rate REAL NOT NULL DEFAULT 0, tax_amount REAL NOT NULL DEFAULT 0, total REAL NOT NULL DEFAULT 0, is_auto INTEGER NOT NULL DEFAULT 0, notes TEXT, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL, received_at_ms INTEGER, purchase_date_ms INTEGER
  - relaciones: supplier_id -> suppliers(id)

- tabla: compras_detalle
  - columnas: id INTEGER PK AUTOINCREMENT, order_id INTEGER NOT NULL, product_id INTEGER NOT NULL, qty REAL NOT NULL, unit_cost REAL NOT NULL, total_line REAL NOT NULL, created_at_ms INTEGER NOT NULL
  - relaciones: order_id -> compras_ordenes(id) ON DELETE CASCADE, product_id -> products(id)

- tabla: business_info
  - columnas: id INTEGER PK AUTOINCREMENT, name TEXT NOT NULL DEFAULT 'LOS NIL KAS', phone TEXT, address TEXT, rnc TEXT, slogan TEXT, updated_at_ms INTEGER NOT NULL

- tabla: app_settings
  - columnas: id INTEGER PK AUTOINCREMENT, itbis_enabled_default INTEGER NOT NULL DEFAULT 1, itbis_rate REAL NOT NULL DEFAULT 0.18, ticket_size TEXT NOT NULL DEFAULT '80mm', updated_at_ms INTEGER NOT NULL

- tabla: ncf_books
  - columnas: id INTEGER PK AUTOINCREMENT, type TEXT NOT NULL, series TEXT, from_n INTEGER NOT NULL, to_n INTEGER NOT NULL, next_n INTEGER NOT NULL, is_active INTEGER NOT NULL DEFAULT 1, expires_at_ms INTEGER, note TEXT, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL, deleted_at_ms INTEGER

- tabla: customers_ncf_usage
  - columnas: id INTEGER PK AUTOINCREMENT, sale_id INTEGER NOT NULL, ncf_book_id INTEGER NOT NULL, ncf_full TEXT NOT NULL UNIQUE, created_at_ms INTEGER NOT NULL
  - relaciones: sale_id -> sales(id), ncf_book_id -> ncf_books(id)

- tabla: users
  - columnas: id INTEGER PK AUTOINCREMENT, username TEXT NOT NULL UNIQUE, pin TEXT, role TEXT NOT NULL DEFAULT 'admin', is_active INTEGER NOT NULL DEFAULT 1, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL, deleted_at_ms INTEGER, display_name TEXT, permissions TEXT, password_hash TEXT

- tabla: cash_sessions
  - columnas: id INTEGER PK AUTOINCREMENT, opened_by_user_id INTEGER NOT NULL, user_name TEXT NOT NULL DEFAULT 'admin', opened_at_ms INTEGER NOT NULL, initial_amount REAL NOT NULL DEFAULT 0, closing_amount REAL, expected_cash REAL, difference REAL, closed_at_ms INTEGER, closed_by_user_id INTEGER, note TEXT, status TEXT NOT NULL DEFAULT 'OPEN'
  - relaciones: opened_by_user_id -> users(id), closed_by_user_id -> users(id)

- tabla: cash_movements
  - columnas: id INTEGER PK AUTOINCREMENT, session_id INTEGER NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, note TEXT, created_at_ms INTEGER NOT NULL, reason TEXT NOT NULL DEFAULT 'Movimiento de caja', user_id INTEGER NOT NULL DEFAULT 1
  - relaciones: session_id -> cash_sessions(id)

- tabla: sales
  - columnas: id INTEGER PK AUTOINCREMENT, local_code TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'completed', customer_id INTEGER, customer_name_snapshot TEXT, customer_phone_snapshot TEXT, customer_rnc_snapshot TEXT, itbis_enabled INTEGER NOT NULL DEFAULT 1, itbis_rate REAL NOT NULL DEFAULT 0.18, discount_total REAL NOT NULL DEFAULT 0, subtotal REAL NOT NULL DEFAULT 0, itbis_amount REAL NOT NULL DEFAULT 0, total REAL NOT NULL DEFAULT 0, payment_method TEXT, paid_amount REAL NOT NULL DEFAULT 0, change_amount REAL NOT NULL DEFAULT 0, fiscal_enabled INTEGER NOT NULL DEFAULT 0, ncf_full TEXT UNIQUE, ncf_type TEXT, session_id INTEGER, cash_session_id INTEGER, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL, deleted_at_ms INTEGER
  - relaciones: customer_id -> clients(id), session_id -> cash_sessions(id), cash_session_id -> cash_sessions(id)

- tabla: sale_items
  - columnas: id INTEGER PK AUTOINCREMENT, sale_id INTEGER NOT NULL, product_id INTEGER, product_code_snapshot TEXT NOT NULL, product_name_snapshot TEXT NOT NULL, qty REAL NOT NULL, unit_price REAL NOT NULL, purchase_price_snapshot REAL NOT NULL DEFAULT 0, discount_line REAL NOT NULL DEFAULT 0, total_line REAL NOT NULL, created_at_ms INTEGER NOT NULL
  - relaciones: sale_id -> sales(id), product_id -> products(id)

- tabla: returns
  - columnas: id INTEGER PK AUTOINCREMENT, original_sale_id INTEGER NOT NULL, return_sale_id INTEGER NOT NULL, note TEXT, created_at_ms INTEGER NOT NULL
  - relaciones: original_sale_id -> sales(id), return_sale_id -> sales(id)

- tabla: return_items
  - columnas: id INTEGER PK AUTOINCREMENT, return_id INTEGER NOT NULL, sale_item_id INTEGER, product_id INTEGER, description TEXT NOT NULL, qty REAL NOT NULL, price REAL NOT NULL, total REAL NOT NULL
  - relaciones: return_id -> returns(id) ON DELETE CASCADE, sale_item_id -> sale_items(id), product_id -> products(id)

- tabla: credit_payments
  - columnas: id INTEGER PK AUTOINCREMENT, sale_id INTEGER NOT NULL, client_id INTEGER NOT NULL, amount REAL NOT NULL, method TEXT NOT NULL DEFAULT 'cash', note TEXT, created_at_ms INTEGER NOT NULL, user_id INTEGER
  - relaciones: sale_id -> sales(id), client_id -> clients(id), user_id -> users(id)

- tabla: loans
  - columnas: id INTEGER PK AUTOINCREMENT, client_id INTEGER NOT NULL, type TEXT NOT NULL, principal REAL NOT NULL, interest_rate REAL NOT NULL, interest_mode TEXT NOT NULL, frequency TEXT NOT NULL, installments_count INTEGER NOT NULL, start_date_ms INTEGER NOT NULL, total_due REAL NOT NULL, balance REAL NOT NULL, late_fee REAL DEFAULT 0, status TEXT NOT NULL, note TEXT, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL, deleted_at_ms INTEGER
  - relaciones: client_id -> clients(id)

- tabla: loan_collaterals
  - columnas: id INTEGER PK AUTOINCREMENT, loan_id INTEGER NOT NULL, description TEXT NOT NULL, estimated_value REAL, serial TEXT, condition TEXT
  - relaciones: loan_id -> loans(id)

- tabla: loan_installments
  - columnas: id INTEGER PK AUTOINCREMENT, loan_id INTEGER NOT NULL, number INTEGER NOT NULL, due_date_ms INTEGER NOT NULL, amount_due REAL NOT NULL, amount_paid REAL NOT NULL DEFAULT 0, status TEXT NOT NULL
  - relaciones: loan_id -> loans(id)

- tabla: loan_payments
  - columnas: id INTEGER PK AUTOINCREMENT, loan_id INTEGER NOT NULL, paid_at_ms INTEGER NOT NULL, amount REAL NOT NULL, method TEXT NOT NULL, note TEXT
  - relaciones: loan_id -> loans(id)

- tabla: pos_tickets
  - columnas: id INTEGER PK AUTOINCREMENT, ticket_name TEXT NOT NULL, user_id INTEGER, client_id INTEGER, itbis_enabled INTEGER NOT NULL DEFAULT 1, itbis_rate REAL NOT NULL DEFAULT 0.18, discount_total REAL NOT NULL DEFAULT 0, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL
  - relaciones: client_id -> clients(id), user_id -> users(id)

- tabla: pos_ticket_items
  - columnas: id INTEGER PK AUTOINCREMENT, ticket_id INTEGER NOT NULL, product_id INTEGER, product_code_snapshot TEXT NOT NULL, product_name_snapshot TEXT NOT NULL, description TEXT NOT NULL, qty REAL NOT NULL, price REAL NOT NULL, cost REAL NOT NULL DEFAULT 0, discount_line REAL NOT NULL DEFAULT 0, total_line REAL NOT NULL
  - relaciones: ticket_id -> pos_tickets(id) ON DELETE CASCADE, product_id -> products(id)

- tabla: quotes
  - columnas: id INTEGER PK AUTOINCREMENT, client_id INTEGER NOT NULL, user_id INTEGER, ticket_name TEXT, subtotal REAL NOT NULL, itbis_enabled INTEGER NOT NULL DEFAULT 1, itbis_rate REAL NOT NULL DEFAULT 0.18, itbis_amount REAL NOT NULL DEFAULT 0, discount_total REAL NOT NULL DEFAULT 0, total REAL NOT NULL, status TEXT NOT NULL DEFAULT 'OPEN', notes TEXT, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL
  - relaciones: client_id -> clients(id), user_id -> users(id)

- tabla: quote_items
  - columnas: id INTEGER PK AUTOINCREMENT, quote_id INTEGER NOT NULL, product_id INTEGER, product_code_snapshot TEXT, product_name_snapshot TEXT NOT NULL, description TEXT NOT NULL, qty REAL NOT NULL, unit_price REAL NOT NULL DEFAULT 0, price REAL NOT NULL, cost REAL NOT NULL DEFAULT 0, discount_line REAL NOT NULL DEFAULT 0, total_line REAL NOT NULL
  - relaciones: quote_id -> quotes(id) ON DELETE CASCADE, product_id -> products(id)

## Tablas solo locales / configuración UI / dispositivo (NO se sincronizan por defecto)

- tabla: printer_settings
  - columnas: id INTEGER PK AUTOINCREMENT, selected_printer_name TEXT, printer_name TEXT NOT NULL DEFAULT '', paper_width_mm INTEGER NOT NULL DEFAULT 80, chars_per_line INTEGER NOT NULL DEFAULT 48, auto_print_on_payment INTEGER NOT NULL DEFAULT 0, show_itbis INTEGER NOT NULL DEFAULT 1, show_ncf INTEGER NOT NULL DEFAULT 1, show_cashier INTEGER NOT NULL DEFAULT 1, show_client INTEGER NOT NULL DEFAULT 1, show_payment_method INTEGER NOT NULL DEFAULT 1, show_discounts INTEGER NOT NULL DEFAULT 1, show_code INTEGER NOT NULL DEFAULT 1, show_datetime INTEGER NOT NULL DEFAULT 1, header_business_name TEXT DEFAULT 'MI NEGOCIO', header_rnc TEXT, header_address TEXT, header_phone TEXT, footer_message TEXT DEFAULT 'Gracias por su compra', left_margin INTEGER NOT NULL DEFAULT 0, right_margin INTEGER NOT NULL DEFAULT 0, auto_cut INTEGER NOT NULL DEFAULT 1, copies INTEGER NOT NULL DEFAULT 1, header_extra TEXT, itbis_rate REAL NOT NULL DEFAULT 0.18, created_at_ms INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL
  - comentario: típicamente es por dispositivo (impresora), no por empresa.
