-- 004_create_pos_tables.sql
-- Tablas espejo en PostgreSQL para sincronización (basadas en SQLite detectado en Flutter).
-- Regla: NO rompe licencias; solo crea tablas nuevas.
-- Regla multi-empresa: todas las tablas de negocio incluyen company_id + timestamps + is_deleted.
-- Nota: en SQLite muchas PK son INTEGER AUTOINCREMENT. En nube usamos PK compuesta (company_id, id)
-- para permitir upsert por id local. (Si se requiere sync multi-dispositivo real, conviene migrar a UUIDs locales.
-- Se deja este enfoque por compatibilidad con el esquema existente.)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Helper: trigger para updated_at
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- app_config
CREATE TABLE IF NOT EXISTS app_config (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  key text NOT NULL,
  value text NOT NULL,
  updated_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, key)
);

-- clients
CREATE TABLE IF NOT EXISTS clients (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  nombre text NOT NULL,
  telefono text,
  direccion text,
  rnc text,
  cedula text,
  is_active boolean NOT NULL DEFAULT true,
  has_credit boolean NOT NULL DEFAULT false,
  deleted_at_ms bigint,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id)
);
CREATE INDEX IF NOT EXISTS idx_clients_company_id ON clients(company_id);

-- categories
CREATE TABLE IF NOT EXISTS categories (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  deleted_at_ms bigint,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id)
);

-- suppliers
CREATE TABLE IF NOT EXISTS suppliers (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  name text NOT NULL,
  phone text,
  note text,
  is_active boolean NOT NULL DEFAULT true,
  deleted_at_ms bigint,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id)
);

-- products
CREATE TABLE IF NOT EXISTS products (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  image_path text,
  category_id bigint,
  supplier_id bigint,
  purchase_price double precision NOT NULL DEFAULT 0.0,
  sale_price double precision NOT NULL DEFAULT 0.0,
  stock double precision NOT NULL DEFAULT 0.0,
  stock_min double precision NOT NULL DEFAULT 0.0,
  is_active boolean NOT NULL DEFAULT true,
  deleted_at_ms bigint,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  UNIQUE (company_id, code),
  FOREIGN KEY (company_id, category_id) REFERENCES categories(company_id, id),
  FOREIGN KEY (company_id, supplier_id) REFERENCES suppliers(company_id, id)
);

-- stock_movements
CREATE TABLE IF NOT EXISTS stock_movements (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  product_id bigint NOT NULL,
  type text NOT NULL,
  quantity double precision NOT NULL,
  note text,
  user_id bigint,
  created_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, product_id) REFERENCES products(company_id, id)
);

-- compras_ordenes
CREATE TABLE IF NOT EXISTS compras_ordenes (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  supplier_id bigint NOT NULL,
  status text NOT NULL DEFAULT 'PENDIENTE',
  subtotal double precision NOT NULL DEFAULT 0,
  tax_rate double precision NOT NULL DEFAULT 0,
  tax_amount double precision NOT NULL DEFAULT 0,
  total double precision NOT NULL DEFAULT 0,
  is_auto boolean NOT NULL DEFAULT false,
  notes text,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  received_at_ms bigint,
  purchase_date_ms bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, supplier_id) REFERENCES suppliers(company_id, id)
);

-- compras_detalle
CREATE TABLE IF NOT EXISTS compras_detalle (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  order_id bigint NOT NULL,
  product_id bigint NOT NULL,
  qty double precision NOT NULL,
  unit_cost double precision NOT NULL,
  total_line double precision NOT NULL,
  created_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, order_id) REFERENCES compras_ordenes(company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, product_id) REFERENCES products(company_id, id)
);

-- business_info
CREATE TABLE IF NOT EXISTS business_info (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  name text NOT NULL,
  phone text,
  address text,
  rnc text,
  slogan text,
  updated_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id)
);

-- app_settings
CREATE TABLE IF NOT EXISTS app_settings (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  itbis_enabled_default boolean NOT NULL DEFAULT true,
  itbis_rate double precision NOT NULL DEFAULT 0.18,
  ticket_size text NOT NULL DEFAULT '80mm',
  updated_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id)
);

-- ncf_books
CREATE TABLE IF NOT EXISTS ncf_books (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  type text NOT NULL,
  series text,
  from_n bigint NOT NULL,
  to_n bigint NOT NULL,
  next_n bigint NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  expires_at_ms bigint,
  note text,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  deleted_at_ms bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id)
);

-- users (local users; nube tendrá pos_users también)
CREATE TABLE IF NOT EXISTS users (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  username text NOT NULL,
  pin text,
  role text NOT NULL DEFAULT 'admin',
  is_active boolean NOT NULL DEFAULT true,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  deleted_at_ms bigint,
  display_name text,
  permissions text,
  password_hash text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  UNIQUE (company_id, username)
);

-- cash_sessions
CREATE TABLE IF NOT EXISTS cash_sessions (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  opened_by_user_id bigint NOT NULL,
  user_name text NOT NULL DEFAULT 'admin',
  opened_at_ms bigint NOT NULL,
  initial_amount double precision NOT NULL DEFAULT 0,
  closing_amount double precision,
  expected_cash double precision,
  difference double precision,
  closed_at_ms bigint,
  closed_by_user_id bigint,
  note text,
  status text NOT NULL DEFAULT 'OPEN',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, opened_by_user_id) REFERENCES users(company_id, id),
  FOREIGN KEY (company_id, closed_by_user_id) REFERENCES users(company_id, id)
);

-- cash_movements
CREATE TABLE IF NOT EXISTS cash_movements (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  session_id bigint NOT NULL,
  type text NOT NULL,
  amount double precision NOT NULL,
  note text,
  created_at_ms bigint NOT NULL,
  reason text NOT NULL DEFAULT 'Movimiento de caja',
  user_id bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, session_id) REFERENCES cash_sessions(company_id, id)
);

-- sales
CREATE TABLE IF NOT EXISTS sales (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  local_code text NOT NULL,
  kind text NOT NULL,
  status text NOT NULL DEFAULT 'completed',
  customer_id bigint,
  customer_name_snapshot text,
  customer_phone_snapshot text,
  customer_rnc_snapshot text,
  itbis_enabled boolean NOT NULL DEFAULT true,
  itbis_rate double precision NOT NULL DEFAULT 0.18,
  discount_total double precision NOT NULL DEFAULT 0,
  subtotal double precision NOT NULL DEFAULT 0,
  itbis_amount double precision NOT NULL DEFAULT 0,
  total double precision NOT NULL DEFAULT 0,
  payment_method text,
  paid_amount double precision NOT NULL DEFAULT 0,
  change_amount double precision NOT NULL DEFAULT 0,
  fiscal_enabled boolean NOT NULL DEFAULT false,
  ncf_full text,
  ncf_type text,
  session_id bigint,
  cash_session_id bigint,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  deleted_at_ms bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  UNIQUE (company_id, local_code),
  UNIQUE (company_id, ncf_full),
  FOREIGN KEY (company_id, customer_id) REFERENCES clients(company_id, id),
  FOREIGN KEY (company_id, session_id) REFERENCES cash_sessions(company_id, id),
  FOREIGN KEY (company_id, cash_session_id) REFERENCES cash_sessions(company_id, id)
);

-- customers_ncf_usage
-- Nota: esta tabla referencia sales, por lo que debe crearse DESPUÉS de sales.
CREATE TABLE IF NOT EXISTS customers_ncf_usage (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  sale_id bigint NOT NULL,
  ncf_book_id bigint NOT NULL,
  ncf_full text NOT NULL,
  created_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  UNIQUE (company_id, ncf_full),
  FOREIGN KEY (company_id, sale_id) REFERENCES sales(company_id, id),
  FOREIGN KEY (company_id, ncf_book_id) REFERENCES ncf_books(company_id, id)
);

-- sale_items
CREATE TABLE IF NOT EXISTS sale_items (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  sale_id bigint NOT NULL,
  product_id bigint,
  product_code_snapshot text NOT NULL,
  product_name_snapshot text NOT NULL,
  qty double precision NOT NULL,
  unit_price double precision NOT NULL,
  purchase_price_snapshot double precision NOT NULL DEFAULT 0,
  discount_line double precision NOT NULL DEFAULT 0,
  total_line double precision NOT NULL,
  created_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, sale_id) REFERENCES sales(company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, product_id) REFERENCES products(company_id, id)
);

-- returns
CREATE TABLE IF NOT EXISTS returns (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  original_sale_id bigint NOT NULL,
  return_sale_id bigint NOT NULL,
  note text,
  created_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, original_sale_id) REFERENCES sales(company_id, id),
  FOREIGN KEY (company_id, return_sale_id) REFERENCES sales(company_id, id)
);

-- return_items
CREATE TABLE IF NOT EXISTS return_items (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  return_id bigint NOT NULL,
  sale_item_id bigint,
  product_id bigint,
  description text NOT NULL,
  qty double precision NOT NULL,
  price double precision NOT NULL,
  total double precision NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, return_id) REFERENCES returns(company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, sale_item_id) REFERENCES sale_items(company_id, id),
  FOREIGN KEY (company_id, product_id) REFERENCES products(company_id, id)
);

-- credit_payments
CREATE TABLE IF NOT EXISTS credit_payments (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  sale_id bigint NOT NULL,
  client_id bigint NOT NULL,
  amount double precision NOT NULL,
  method text NOT NULL DEFAULT 'cash',
  note text,
  created_at_ms bigint NOT NULL,
  user_id bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, sale_id) REFERENCES sales(company_id, id),
  FOREIGN KEY (company_id, client_id) REFERENCES clients(company_id, id),
  FOREIGN KEY (company_id, user_id) REFERENCES users(company_id, id)
);

-- loans
CREATE TABLE IF NOT EXISTS loans (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  client_id bigint NOT NULL,
  type text NOT NULL,
  principal double precision NOT NULL,
  interest_rate double precision NOT NULL,
  interest_mode text NOT NULL,
  frequency text NOT NULL,
  installments_count bigint NOT NULL,
  start_date_ms bigint NOT NULL,
  total_due double precision NOT NULL,
  balance double precision NOT NULL,
  late_fee double precision DEFAULT 0,
  status text NOT NULL,
  note text,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  deleted_at_ms bigint,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, client_id) REFERENCES clients(company_id, id)
);

-- loan_collaterals
CREATE TABLE IF NOT EXISTS loan_collaterals (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  loan_id bigint NOT NULL,
  description text NOT NULL,
  estimated_value double precision,
  serial text,
  condition text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, loan_id) REFERENCES loans(company_id, id) ON DELETE CASCADE
);

-- loan_installments
CREATE TABLE IF NOT EXISTS loan_installments (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  loan_id bigint NOT NULL,
  number bigint NOT NULL,
  due_date_ms bigint NOT NULL,
  amount_due double precision NOT NULL,
  amount_paid double precision NOT NULL DEFAULT 0,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, loan_id) REFERENCES loans(company_id, id) ON DELETE CASCADE
);

-- loan_payments
CREATE TABLE IF NOT EXISTS loan_payments (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  loan_id bigint NOT NULL,
  paid_at_ms bigint NOT NULL,
  amount double precision NOT NULL,
  method text NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, loan_id) REFERENCES loans(company_id, id) ON DELETE CASCADE
);

-- pos_tickets
CREATE TABLE IF NOT EXISTS pos_tickets (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  ticket_name text NOT NULL,
  user_id bigint,
  client_id bigint,
  itbis_enabled boolean NOT NULL DEFAULT true,
  itbis_rate double precision NOT NULL DEFAULT 0.18,
  discount_total double precision NOT NULL DEFAULT 0,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, user_id) REFERENCES users(company_id, id),
  FOREIGN KEY (company_id, client_id) REFERENCES clients(company_id, id)
);

-- pos_ticket_items
CREATE TABLE IF NOT EXISTS pos_ticket_items (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  ticket_id bigint NOT NULL,
  product_id bigint,
  product_code_snapshot text NOT NULL,
  product_name_snapshot text NOT NULL,
  description text NOT NULL,
  qty double precision NOT NULL,
  price double precision NOT NULL,
  cost double precision NOT NULL DEFAULT 0,
  discount_line double precision NOT NULL DEFAULT 0,
  total_line double precision NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, ticket_id) REFERENCES pos_tickets(company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, product_id) REFERENCES products(company_id, id)
);

-- quotes
CREATE TABLE IF NOT EXISTS quotes (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  client_id bigint NOT NULL,
  user_id bigint,
  ticket_name text,
  subtotal double precision NOT NULL,
  itbis_enabled boolean NOT NULL DEFAULT true,
  itbis_rate double precision NOT NULL DEFAULT 0.18,
  itbis_amount double precision NOT NULL DEFAULT 0,
  discount_total double precision NOT NULL DEFAULT 0,
  total double precision NOT NULL,
  status text NOT NULL DEFAULT 'OPEN',
  notes text,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, client_id) REFERENCES clients(company_id, id),
  FOREIGN KEY (company_id, user_id) REFERENCES users(company_id, id)
);

-- quote_items
CREATE TABLE IF NOT EXISTS quote_items (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  quote_id bigint NOT NULL,
  product_id bigint,
  product_code_snapshot text,
  product_name_snapshot text NOT NULL,
  description text NOT NULL,
  qty double precision NOT NULL,
  unit_price double precision NOT NULL DEFAULT 0,
  price double precision NOT NULL,
  cost double precision NOT NULL DEFAULT 0,
  discount_line double precision NOT NULL DEFAULT 0,
  total_line double precision NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id),
  FOREIGN KEY (company_id, quote_id) REFERENCES quotes(company_id, id) ON DELETE CASCADE,
  FOREIGN KEY (company_id, product_id) REFERENCES products(company_id, id)
);

-- printer_settings (marcada como "solo local" por defecto, pero si se quiere sincronizar está aquí)
CREATE TABLE IF NOT EXISTS printer_settings (
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  id bigint NOT NULL,
  selected_printer_name text,
  printer_name text NOT NULL DEFAULT '',
  paper_width_mm bigint NOT NULL DEFAULT 80,
  chars_per_line bigint NOT NULL DEFAULT 48,
  auto_print_on_payment boolean NOT NULL DEFAULT false,
  show_itbis boolean NOT NULL DEFAULT true,
  show_ncf boolean NOT NULL DEFAULT true,
  show_cashier boolean NOT NULL DEFAULT true,
  show_client boolean NOT NULL DEFAULT true,
  show_payment_method boolean NOT NULL DEFAULT true,
  show_discounts boolean NOT NULL DEFAULT true,
  show_code boolean NOT NULL DEFAULT true,
  show_datetime boolean NOT NULL DEFAULT true,
  header_business_name text,
  header_rnc text,
  header_address text,
  header_phone text,
  footer_message text,
  left_margin bigint NOT NULL DEFAULT 0,
  right_margin bigint NOT NULL DEFAULT 0,
  auto_cut boolean NOT NULL DEFAULT true,
  copies bigint NOT NULL DEFAULT 1,
  header_extra text,
  itbis_rate double precision NOT NULL DEFAULT 0.18,
  created_at_ms bigint NOT NULL,
  updated_at_ms bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY (company_id, id)
);

-- updated_at trigger on all tables that have updated_at
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'app_config','clients','categories','suppliers','products','stock_movements',
    'compras_ordenes','compras_detalle','business_info','app_settings','ncf_books',
    'customers_ncf_usage','users','cash_sessions','cash_movements','sales','sale_items',
    'returns','return_items','credit_payments','loans','loan_collaterals','loan_installments',
    'loan_payments','pos_tickets','pos_ticket_items','quotes','quote_items','printer_settings'
  ]
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_updated_at ON %I;', t, t);
    EXECUTE format('CREATE TRIGGER trg_%s_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at();', t, t);
  END LOOP;
END$$;
