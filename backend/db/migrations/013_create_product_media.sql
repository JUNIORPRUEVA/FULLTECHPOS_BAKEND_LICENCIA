-- 013_create_product_media.sql
-- Product media: logo, cover, gallery, video link, og image.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS product_media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  kind text NOT NULL,
  url text NOT NULL,
  storage_path text NULL,
  mime text NULL,
  size_bytes bigint NULL,
  width int NULL,
  height int NULL,
  sort_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ck_product_media_kind CHECK (
    kind IN (
      'logo',
      'cover_image',
      'cover_video',
      'gallery_image',
      'og_image'
    )
  )
);

CREATE INDEX IF NOT EXISTS idx_product_media_product_id ON product_media(product_id);
CREATE INDEX IF NOT EXISTS idx_product_media_kind ON product_media(kind);
CREATE INDEX IF NOT EXISTS idx_product_media_sort_order ON product_media(product_id, sort_order);

COMMIT;
