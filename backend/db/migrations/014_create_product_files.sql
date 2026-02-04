-- 014_create_product_files.sql
-- Downloadable files/links per platform.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS product_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  platform text NOT NULL,
  file_type text NOT NULL,
  display_name text NOT NULL,
  version text NULL,
  url text NOT NULL,
  storage_path text NULL,
  size_bytes bigint NULL,
  checksum_sha256 text NULL,
  is_active boolean NOT NULL DEFAULT true,
  requires_license boolean NOT NULL DEFAULT false,
  uploaded_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ck_product_files_platform CHECK (
    platform IN ('android','windows','pwa','web','manual','other')
  ),
  CONSTRAINT ck_product_files_type CHECK (
    file_type IN ('apk','aab','exe','msi','zip','pdf','url','other')
  )
);

CREATE INDEX IF NOT EXISTS idx_product_files_product_id ON product_files(product_id);
CREATE INDEX IF NOT EXISTS idx_product_files_platform ON product_files(platform);

COMMIT;
