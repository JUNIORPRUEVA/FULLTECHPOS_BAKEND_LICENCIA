const { pool } = require('../db/pool');

async function getSettings() {
  const res = await pool.query('SELECT * FROM store_settings WHERE id = 1');
  return res.rows[0] || null;
}

async function updateSettings(patch) {
  const brand_name = patch.brand_name;
  const logo_url = patch.logo_url;
  const whatsapp = patch.whatsapp;
  const email = patch.email;
  const address = patch.address;
  const socials = patch.socials;
  const theme = patch.theme;

  const res = await pool.query(
    `UPDATE store_settings
     SET brand_name = COALESCE($1, brand_name),
         logo_url = COALESCE($2, logo_url),
         whatsapp = COALESCE($3, whatsapp),
         email = COALESCE($4, email),
         address = COALESCE($5, address),
         socials = COALESCE($6, socials),
         theme = COALESCE($7, theme),
         updated_at = now()
     WHERE id = 1
     RETURNING *`,
    [
      brand_name ?? null,
      logo_url ?? null,
      whatsapp ?? null,
      email ?? null,
      address ?? null,
      socials ?? null,
      theme ?? null
    ]
  );
  return res.rows[0] || null;
}

module.exports = {
  getSettings,
  updateSettings
};
