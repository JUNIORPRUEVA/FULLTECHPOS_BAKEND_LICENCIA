-- Add customer business role (rol_negocio)

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS rol_negocio text;
