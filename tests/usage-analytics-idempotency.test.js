const test = require('node:test');
const assert = require('node:assert/strict');
const { mock } = require('node:test');

const { pool } = require('../backend/db/pool');
const usageAnalyticsModel = require('../backend/models/usageAnalyticsModel');
const usageAnalyticsService = require('../backend/services/usageAnalyticsService');

function canonicalEvent(overrides = {}) {
  return {
    eventId: '11111111-1111-4111-8111-111111111111',
    schemaVersion: 1,
    companyId: 'company-a',
    business_id: 'company-a',
    app_code: 'DALEVENTAS_POS',
    project_code: 'DALEVENTAS_POS',
    device_id: 'daleventas-api-company-a',
    eventType: 'PRODUCT_CREATED',
    occurredAt: '2026-09-07T05:00:00.000Z',
    entityType: 'product',
    entityId: 'product-a',
    feature: 'PRODUCTS',
    metadata: { privacy: 'minimal_activity_metadata' },
    ...overrides
  };
}

test('batch ingest acknowledges duplicate event ids without double aggregation', async () => {
  const client = {
    query: mock.fn(async () => ({ rows: [] })),
    release: mock.fn()
  };
  mock.method(pool, 'connect', async () => client);
  mock.method(usageAnalyticsModel, 'resolveUsageContext', async () => ({}));

  let inserted = false;
  mock.method(usageAnalyticsModel, 'insertUsageEvent', async (event) => {
    const duplicate = inserted;
    inserted = true;
    return {
      duplicate,
      subjectKey: `business:${event.business_id}`,
      row: {
        id: 'usage-row-a',
        event_id: event.event_id,
        received_at: '2026-09-07T05:00:01.000Z'
      }
    };
  });
  const daily = mock.method(usageAnalyticsModel, 'upsertDailyStats', async () => {});
  const feature = mock.method(usageAnalyticsModel, 'upsertFeatureStats', async () => {});

  const result = await usageAnalyticsService.ingestBatch(
    { events: [canonicalEvent(), canonicalEvent()] },
    { req: { headers: {}, ip: '127.0.0.1' } }
  );

  assert.equal(result.ok, true);
  assert.equal(result.accepted, 2);
  assert.equal(result.usage[0].duplicate, false);
  assert.equal(result.usage[1].duplicate, true);
  assert.equal(daily.mock.callCount(), 1);
  assert.equal(feature.mock.callCount(), 1);
  assert.equal(client.release.mock.callCount(), 1);
});

test('canonical event validation requires schema version and allowlisted type', async () => {
  await assert.rejects(
    usageAnalyticsService.ingest(canonicalEvent({ schemaVersion: 2 }), {
      req: { headers: {} }
    }),
    /schemaVersion no soportado/
  );

  await assert.rejects(
    usageAnalyticsService.ingest(canonicalEvent({ eventType: 'FULL_SALE_PAYLOAD' }), {
      req: { headers: {} }
    }),
    /eventType no soportado/
  );
});

test('canonical ingest preserves client platform and device metadata for reports', async () => {
  const client = {
    query: mock.fn(async () => ({ rows: [] })),
    release: mock.fn()
  };
  let capturedEvent = null;
  mock.method(pool, 'connect', async () => client);
  mock.method(usageAnalyticsModel, 'resolveUsageContext', async (event) => ({
    business_id: event.business_id
  }));
  mock.method(usageAnalyticsModel, 'insertUsageEvent', async (event) => {
    capturedEvent = event;
    return {
      duplicate: false,
      subjectKey: `business:${event.business_id}`,
      row: {
        id: 'usage-row-device',
        event_id: event.event_id,
        received_at: '2026-09-07T05:00:01.000Z'
      }
    };
  });
  mock.method(usageAnalyticsModel, 'upsertDailyStats', async () => {});
  mock.method(usageAnalyticsModel, 'upsertFeatureStats', async () => {});

  await usageAnalyticsService.ingest(
    canonicalEvent({
      eventType: 'MODULE_USED',
      platform: 'pwa',
      device_name: 'Chrome',
      device_type: 'web',
      app_version: undefined,
      metadata: {
        app_version: '1.0.5+124',
        device_name: 'Chrome',
        privacy: 'minimal_activity_metadata'
      }
    }),
    { req: { headers: {}, ip: '127.0.0.1' } }
  );

  assert.equal(capturedEvent.platform, 'pwa');
  assert.equal(capturedEvent.device_name, 'Chrome');
  assert.equal(capturedEvent.device_type, 'web');
  assert.equal(capturedEvent.app_version, '1.0.5+124');
});

test('canonical ingest accepts the complete DaleVentas LIC-2.1 event catalog', async () => {
  const client = {
    query: mock.fn(async () => ({ rows: [] })),
    release: mock.fn()
  };
  mock.method(pool, 'connect', async () => client);
  mock.method(usageAnalyticsModel, 'resolveUsageContext', async (event) => ({
    business_id: event.business_id
  }));
  mock.method(usageAnalyticsModel, 'insertUsageEvent', async (event) => ({
    duplicate: false,
    subjectKey: `business:${event.business_id}`,
    row: {
      id: `row-${event.event_type}`,
      event_id: event.event_id,
      received_at: '2026-09-07T05:00:01.000Z'
    }
  }));
  const daily = mock.method(usageAnalyticsModel, 'upsertDailyStats', async () => {});
  const feature = mock.method(usageAnalyticsModel, 'upsertFeatureStats', async () => {});
  const types = [
    'SALE_COMPLETED',
    'SALE_CANCELLED',
    'QUOTATION_CREATED',
    'QUOTATION_UPDATED',
    'QUOTATION_CONVERTED_TO_SALE',
    'CASH_SESSION_OPENED',
    'CASH_SESSION_CLOSED',
    'CUSTOMER_CREATED',
    'WAREHOUSE_CREATED',
    'WAREHOUSE_DEACTIVATED',
    'INVENTORY_ADJUSTED',
    'STOCK_RECEIVED',
    'WAREHOUSE_TRANSFER_COMPLETED',
    'PURCHASE_ORDER_CREATED',
    'PURCHASE_ORDER_UPDATED',
    'PURCHASE_ORDER_APPROVED',
    'PURCHASE_ORDER_SENT',
    'PURCHASE_ORDER_CANCELLED',
    'PURCHASE_ORDER_DELETED',
    'PURCHASE_ORDER_RECEIVED',
    'PURCHASE_INVOICE_CREATED',
    'PURCHASE_INVOICE_DELETED'
  ];

  const result = await usageAnalyticsService.ingestBatch(
    {
      events: types.map((eventType, index) =>
        canonicalEvent({
          eventId: `11111111-1111-4111-8111-${String(index + 2).padStart(12, '0')}`,
          eventType,
          entityType: eventType.toLowerCase(),
          entityId: `entity-${index + 1}`,
          feature: eventType.startsWith('QUOTATION')
            ? 'QUOTATIONS'
            : eventType.startsWith('CASH')
              ? 'CASH'
              : eventType.includes('WAREHOUSE')
                ? 'WAREHOUSES'
                : eventType.includes('INVENTORY') || eventType === 'STOCK_RECEIVED'
                  ? 'INVENTORY'
                  : eventType.startsWith('PURCHASE')
                    ? 'PURCHASES'
                    : eventType === 'CUSTOMER_CREATED'
                      ? 'CUSTOMERS'
                      : 'SALES'
        })
      )
    },
    { req: { headers: {}, ip: '127.0.0.1' } }
  );

  assert.equal(result.ok, true);
  assert.equal(result.accepted, types.length);
  assert.equal(daily.mock.callCount(), types.length);
  assert.equal(feature.mock.callCount(), types.length);
});
