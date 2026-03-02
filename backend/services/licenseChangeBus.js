const { EventEmitter } = require('events');

const emitter = new EventEmitter();
// This is a long-lived process; avoid MaxListeners warnings.
emitter.setMaxListeners(0);

function normalizeBusinessId(businessId) {
  const v = String(businessId || '').trim();
  return v ? v : '';
}

function eventNameForBusiness(businessId) {
  const id = normalizeBusinessId(businessId);
  return id ? `business:${id}` : '';
}

function emitBusinessLicenseChanged(businessId, { reason = 'unknown', licenseId = null } = {}) {
  const eventName = eventNameForBusiness(businessId);
  if (!eventName) return;
  emitter.emit(eventName, {
    business_id: normalizeBusinessId(businessId),
    reason: String(reason || 'unknown'),
    license_id: licenseId ? String(licenseId) : null,
    ts: new Date().toISOString(),
  });
}

function onBusinessLicenseChanged(businessId, handler) {
  const eventName = eventNameForBusiness(businessId);
  if (!eventName) return () => {};
  emitter.on(eventName, handler);
  return () => {
    emitter.off(eventName, handler);
  };
}

module.exports = {
  emitBusinessLicenseChanged,
  onBusinessLicenseChanged,
};
