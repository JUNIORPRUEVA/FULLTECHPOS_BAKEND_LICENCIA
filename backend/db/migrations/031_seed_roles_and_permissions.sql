-- 031_seed_roles_and_permissions.sql
-- Seed base platform roles and permissions

BEGIN;

-- ROLES
INSERT INTO roles (code, name, description, scope_type) VALUES
  ('owner', 'Owner', 'Platform owner - full control', 'platform'),
  ('admin', 'Administrator', 'Platform administrator - manage all resources', 'platform'),
  ('support', 'Support', 'Support staff - read-only and support operations', 'platform'),
  ('billing_manager', 'Billing Manager', 'Manage payments and subscriptions', 'platform'),
  ('client_owner', 'Company Owner', 'Company owner - manage their subscription and team', 'company'),
  ('client_user', 'Company User', 'Company user - limited access', 'company')
ON CONFLICT (code) DO NOTHING;

-- PERMISSIONS
INSERT INTO permissions (code, name, description, resource, action) VALUES
  -- Company permissions
  ('companies.read', 'Read Companies', 'View company information', 'companies', 'read'),
  ('companies.manage', 'Manage Companies', 'Create, update, delete companies', 'companies', 'manage'),
  
  -- Product permissions
  ('products.read', 'Read Products', 'View product catalog', 'products', 'read'),
  ('products.manage', 'Manage Products', 'Create, update, delete products', 'products', 'manage'),
  
  -- Plan permissions
  ('plans.manage', 'Manage Plans', 'Create, update, delete pricing plans', 'plans', 'manage'),
  
  -- Subscription permissions
  ('subscriptions.read', 'Read Subscriptions', 'View subscriptions', 'subscriptions', 'read'),
  ('subscriptions.manage', 'Manage Subscriptions', 'Create, update, cancel subscriptions', 'subscriptions', 'manage'),
  
  -- Payment permissions
  ('payments.read', 'Read Payments', 'View payment records', 'payments', 'read'),
  ('payments.manage', 'Manage Payments', 'Record, refund, approve payments', 'payments', 'manage'),
  
  -- License permissions
  ('licenses.read', 'Read Licenses', 'View license records', 'licenses', 'read'),
  ('licenses.manage', 'Manage Licenses', 'Issue, block, extend licenses', 'licenses', 'manage'),
  
  -- User permissions
  ('users.manage', 'Manage Users', 'Create, update, delete users and roles', 'users', 'manage'),
  
  -- Audit permissions
  ('audit_logs.read', 'Read Audit Logs', 'View audit trail', 'audit_logs', 'read'),
  
  -- Settings permissions
  ('settings.manage', 'Manage Settings', 'Configure platform settings', 'settings', 'manage')
ON CONFLICT (code) DO NOTHING;

-- Assign permissions to roles (basic role-permission mapping)
-- This is a simplified version - in production you'd want a full role_permissions junction table
-- For now we'll just ensure the data exists; application code will check these permissions

COMMIT;
