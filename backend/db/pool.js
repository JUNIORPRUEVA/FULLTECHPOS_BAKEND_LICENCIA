const { Pool } = require('pg');

function createPool() {
  const connectionString = process.env.DATABASE_URL;
  const sslMode = process.env.PGSSLMODE || process.env.PG_SSLMODE || '';

  // Soportar DATABASE_URL o PG* variables
  const pool = new Pool(
    connectionString
      ? {
          connectionString,
          // Si tu Postgres usa SSL (ej. proveedores cloud), activa SSL con env PGSSLMODE=require
          ssl:
            String(sslMode).toLowerCase() === 'require'
              ? { rejectUnauthorized: false }
              : undefined
        }
      : {
          host: process.env.PGHOST || process.env.PG_HOST,
          port: (process.env.PGPORT || process.env.PG_PORT) ? Number(process.env.PGPORT || process.env.PG_PORT) : undefined,
          user: process.env.PGUSER || process.env.PG_USER,
          password: process.env.PGPASSWORD || process.env.PG_PASSWORD,
          database: process.env.PGDATABASE || process.env.PG_DATABASE,
          ssl:
            String(sslMode).toLowerCase() === 'require'
              ? { rejectUnauthorized: false }
              : undefined
        }
  );

  return pool;
}

const pool = createPool();

// Compat: soporta ambos estilos de importación en el código:
//   const pool = require('../db/pool')
//   const { pool } = require('../db/pool')
module.exports = pool;
module.exports.pool = pool;

