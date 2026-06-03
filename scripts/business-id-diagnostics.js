const { pool } = require('../backend/db/pool');

async function main() {
  const queries = {
    duplicateBusinessIds: `
      SELECT business_id, COUNT(*)::int AS count
      FROM customers
      WHERE business_id IS NOT NULL AND btrim(business_id) <> ''
      GROUP BY business_id
      HAVING COUNT(*) > 1
      ORDER BY count DESC, business_id ASC
    `,
    nullBusinessIds: `
      SELECT COUNT(*)::int AS count
      FROM customers
      WHERE business_id IS NULL OR btrim(business_id) = ''
    `,
    activeLicensesWithoutBusinessId: `
      SELECT COUNT(*)::int AS count
      FROM licenses l
      JOIN customers c ON c.id = l.customer_id
      WHERE l.estado::text = 'ACTIVA'
        AND (l.fecha_fin IS NULL OR l.fecha_fin >= NOW())
        AND (c.business_id IS NULL OR btrim(c.business_id) = '')
    `,
    legacyBusinessIds: `
      SELECT business_id
      FROM customers
      WHERE business_id IS NOT NULL
        AND btrim(business_id) <> ''
        AND business_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      ORDER BY business_id ASC
      LIMIT 200
    `,
  };

  const result = {};
  for (const [key, sql] of Object.entries(queries)) {
    const queryResult = await pool.query(sql);
    result[key] = queryResult.rows;
  }

  console.log(JSON.stringify(result, null, 2));
}

main()
  .catch((error) => {
    console.error('business-id-diagnostics failed:', error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
