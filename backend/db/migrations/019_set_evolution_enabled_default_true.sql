-- 019_set_evolution_enabled_default_true.sql
-- Asegura que Evolution quede activo por defecto

BEGIN;

ALTER TABLE evolution_config
  ALTER COLUMN enabled SET DEFAULT true;

UPDATE evolution_config
SET enabled = true,
    updated_at = now()
WHERE id = '00000000-0000-0000-0000-000000000001'::uuid
  AND enabled = false;

COMMIT;
