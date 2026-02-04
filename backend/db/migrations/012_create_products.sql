-- 012_create_products.sql
-- Products/projects that are sold publicly.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL,
  name text NOT NULL,
  summary text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  price_text text NULL,
  price_amount numeric(12,2) NULL,
  currency text NOT NULL DEFAULT 'DOP',
  status text NOT NULL DEFAULT 'draft',
  featured boolean NOT NULL DEFAULT false,
  tags text[] NOT NULL DEFAULT '{}'::text[],
  categories text[] NOT NULL DEFAULT '{}'::text[],
  platforms text[] NOT NULL DEFAULT '{}'::text[],
  system_requirements text NULL,
  contact_whatsapp text NULL,
  contact_email text NULL,
  seo_title text NULL,
  seo_description text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_products_slug UNIQUE (slug),
  CONSTRAINT ck_products_status CHECK (status IN ('draft','published','archived'))
);

CREATE INDEX IF NOT EXISTS idx_products_status ON products(status);
CREATE INDEX IF NOT EXISTS idx_products_featured ON products(featured);

COMMIT;
