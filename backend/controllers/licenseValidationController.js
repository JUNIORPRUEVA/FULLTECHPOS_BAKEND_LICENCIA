const licenseValidationService = require('../services/licenseValidationService');

async function validate(req, res) {
  try {
    const result = await licenseValidationService.validateLicense(req.body || {}, { req });
    return res.json(result);
  } catch (error) {
    console.error('v2 validate license error:', error);
    return res.status(500).json({
      success: false,
      status: 'invalid',
      can_access: false,
      reason: 'internal_error',
      company: null,
      product: null,
      project: null,
      plan: null,
      subscription: null,
      license: null,
      limits: null,
      server_time: new Date().toISOString(),
      offline_grace_until: null
    });
  }
}

module.exports = {
  validate
};