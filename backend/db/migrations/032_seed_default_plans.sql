-- 032_seed_default_plans.sql
-- Seed default product plans for existing projects (FULLPOS)

BEGIN;

-- Create default FULLPOS monthly plan if FULLPOS project exists
DO $$
DECLARE
  v_fullpos_project_id uuid;
  v_plan_exists boolean;
BEGIN
  -- Check if projects table exists and FULLPOS project
  IF to_regclass('public.projects') IS NOT NULL THEN
    SELECT id INTO v_fullpos_project_id
    FROM projects
    WHERE code = 'FULLPOS'
    LIMIT 1;
    
    IF v_fullpos_project_id IS NOT NULL THEN
      -- Check if plan already exists
      SELECT EXISTS(
        SELECT 1 FROM product_plans
        WHERE project_id = v_fullpos_project_id AND code = 'fullpos_monthly'
      ) INTO v_plan_exists;
      
      IF NOT v_plan_exists THEN
        INSERT INTO product_plans (
          project_id,
          code,
          name,
          billing_period,
          price_amount,
          currency,
          device_limit,
          company_limit,
          default_grace_days,
          trial_days,
          is_active,
          metadata
        ) VALUES (
          v_fullpos_project_id,
          'fullpos_monthly',
          'FULLPOS Mensual',
          'monthly',
          1000.00,
          'DOP',
          1,
          1,
          3,
          NULL,
          true,
          '{"description": "FULLPOS monthly subscription", "default": true}'
        );
      END IF;
    END IF;
  END IF;
END$$;

COMMIT;
