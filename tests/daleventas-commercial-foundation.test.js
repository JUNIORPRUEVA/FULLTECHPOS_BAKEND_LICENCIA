const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const commercialModel = require('../backend/models/daleventasCommercialModel');
const commercialController = require('../backend/controllers/adminDaleventasCommercialController');

test('commercial plan codes match the approved public catalog', () => {
  assert.deepEqual([...commercialModel.PLAN_CODES].sort(), ['BASIC', 'BUSINESS', 'PRO']);
});

test('effective entitlements resolve override, then plan snapshot, then DaleVentas technical values', () => {
  const profile = {
    override_max_users: 8,
    max_users_snapshot: 5,
    technical_max_users: 2,
    override_max_products: null,
    max_products_snapshot: null,
    technical_max_products: 100,
    override_max_warehouses: null,
    max_warehouses_snapshot: 3,
    override_max_devices: null,
    max_devices_snapshot: null,
    override_expiration_date: null,
    technical_license_expires_at: '2026-10-01T00:00:00.000Z',
    technical_trial_ends_at: '2026-09-13T00:00:00.000Z',
    override_extra_days: 4
  };

  const effective = commercialModel.resolveEffectiveEntitlements(profile);

  assert.equal(effective.maxUsers, 8);
  assert.equal(effective.sources.maxUsers, 'override');
  assert.equal(effective.maxProducts, 100);
  assert.equal(effective.sources.maxProducts, 'technical');
  assert.equal(effective.maxWarehouses, 3);
  assert.equal(effective.sources.maxWarehouses, 'plan_snapshot');
  assert.equal(effective.maxDevices, null);
  assert.equal(effective.sources.maxDevices, 'unconfigured');
  assert.equal(effective.expirationDate, '2026-10-01T00:00:00.000Z');
  assert.equal(effective.extraDays, 4);
});

test('commercial migration seeds prices without inventing entitlement limits', () => {
  const sql = fs.readFileSync(
    path.join(__dirname, '../backend/db/migrations/052_create_daleventas_commercial_foundation.sql'),
    'utf8'
  );

  assert.match(sql, /\('BASIC', 'Básico'.*1000\.00, 'DOP', 3, 3000\.00, 7/s);
  assert.match(sql, /\('BUSINESS', 'Negocio'.*1500\.00, 'DOP', 3, 4500\.00, 7/s);
  assert.match(sql, /\('PRO', 'Pro'.*2500\.00, 'DOP', 3, 7500\.00, 7/s);
  assert.match(sql, /max_users int,/);
  assert.match(sql, /max_products int,/);
  assert.match(sql, /max_warehouses int,/);
  assert.match(sql, /max_devices int,/);
  assert.doesNotMatch(sql, /max_users,\s*max_products,\s*max_warehouses,\s*max_devices[\s\S]*VALUES\s*\([^)]*,\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*\d+/);
});

test('filter builder supports the approved primary, plan, expiration, and marketing filters', () => {
  const { where, params } = commercialModel.buildProfileWhere({
    primaryFilter: 'POR_VENCER',
    plan: 'BASIC',
    expiration: '7_DIAS',
    leadSource: 'WEB'
  });

  assert.equal(where.length, 4);
  assert.deepEqual(params, [30, 'BASIC', 'WEB', 7]);
});

test('commercial propagation sends only DaleVentas-supported limits', () => {
  const patch = commercialController._test.supportedLicensePatch(
    {
      plan_code_snapshot: 'PRO',
      effective_entitlements: {
        maxUsers: 6,
        maxProducts: 500,
        maxWarehouses: 4,
        maxDevices: 3,
        expirationDate: '2026-12-31T00:00:00.000Z'
      }
    },
    'Plan actualizado desde Appyra',
    { expiresAt: '2026-12-31T00:00:00.000Z' }
  );

  assert.deepEqual(patch, {
    plan: 'ENTERPRISE',
    maxUsers: 6,
    maxProducts: 500,
    expiresAt: '2026-12-31T00:00:00.000Z',
    notes: 'Plan actualizado desde Appyra'
  });
  assert.equal(Object.hasOwn(patch, 'maxWarehouses'), false);
  assert.equal(Object.hasOwn(patch, 'maxDevices'), false);
});

test('commercial plan assignment does not propagate stale technical expiration', () => {
  const patch = commercialController._test.supportedLicensePatch(
    {
      plan_code_snapshot: 'BASIC',
      effective_entitlements: {
        maxUsers: 2,
        maxProducts: 100,
        expirationDate: '2026-08-17T13:21:01.257Z'
      }
    },
    'Plan actualizado desde Appyra'
  );

  assert.deepEqual(patch, {
    plan: 'STANDARD',
    maxUsers: 2,
    maxProducts: 100,
    notes: 'Plan actualizado desde Appyra'
  });
});

test('commercial expiration override propagates explicit expiration only', () => {
  const patch = commercialController._test.supportedLicensePatch(
    {
      plan_code_snapshot: 'BASIC',
      effective_entitlements: {
        maxUsers: 2,
        maxProducts: 100,
        expirationDate: '2026-08-17T13:21:01.257Z'
      }
    },
    'Fecha ajustada desde Appyra',
    { expiresAt: '2026-11-12' }
  );

  assert.deepEqual(patch, {
    plan: 'STANDARD',
    maxUsers: 2,
    maxProducts: 100,
    expiresAt: '2026-11-12',
    notes: 'Fecha ajustada desde Appyra'
  });
});
