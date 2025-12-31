const syncService = require('./sync.service');

function getHeaders(req) {
  return {
    licenseKey: req.headers['x-license-key'],
    deviceId: req.headers['x-device-id']
  };
}

async function push(req, res) {
  try {
    const { licenseKey, deviceId } = getHeaders(req);

    const { licenseId, companyId } = await syncService.validateLicenseAndResolveCompany(
      licenseKey,
      deviceId
    );

    const tables = req.body?.tables || {};
    const lastSyncAt = req.body?.last_sync_at || null;

    const summary = { ok: true, company_id: companyId, tables: {} };

    for (const [tableName, records] of Object.entries(tables)) {
      const result = await syncService.upsertRecords({
        companyId,
        tableName,
        records: Array.isArray(records) ? records : []
      });
      summary.tables[tableName] = result;
    }

    await syncService.logSync({
      companyId,
      licenseId,
      deviceId,
      direction: 'PUSH',
      lastSyncAt,
      summary
    });

    return res.json(summary);
  } catch (e) {
    const status = e.status || 500;
    return res.status(status).json({
      ok: false,
      code: e.code || 'ERROR',
      message: e.message || 'Error interno'
    });
  }
}

async function pull(req, res) {
  try {
    const { licenseKey, deviceId } = getHeaders(req);

    const { licenseId, companyId } = await syncService.validateLicenseAndResolveCompany(
      licenseKey,
      deviceId
    );

    const lastSyncAt = req.query?.last_sync_at || req.query?.last_sync_at || null;

    const data = await syncService.pullUpdates({ companyId, lastSyncAt });

    const payload = {
      ok: true,
      server_time: data.server_time,
      tables: data.tables
    };

    await syncService.logSync({
      companyId,
      licenseId,
      deviceId,
      direction: 'PULL',
      lastSyncAt,
      summary: { ok: true, tables: Object.keys(data.tables) }
    });

    return res.json(payload);
  } catch (e) {
    const status = e.status || 500;
    return res.status(status).json({
      ok: false,
      code: e.code || 'ERROR',
      message: e.message || 'Error interno'
    });
  }
}

module.exports = { push, pull };
