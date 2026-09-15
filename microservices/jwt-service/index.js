const express = require('express');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();

app.set('trust proxy', 1);

app.use(express.json());
app.use(cors({
  origin: ['https://hosting3m.com', 'https://cattle.hosting3m.com'],
  methods: ['POST'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

// Limiter para la ruta de login (protege contra fuerza bruta)
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutos
  max: 20,
  message: { error: 'Demasiados intentos de login. Intente más tarde.' },
  standardHeaders: true,
  legacyHeaders: false,
});

// LIMITADOR M2M (High-Ceiling)
const verifyLimiter = rateLimit({
  windowMs: 1 * 60 * 1000, // 1 minuto
  max: 10000,
  message: { error: 'Rate limit de seguridad M2M excedido.' },
  standardHeaders: true,
  legacyHeaders: false,
});

const JWT_SECRET = process.env.JWT_SECRET;
const INTERNAL_SECRET = process.env.INTERNAL_SECRET;

if (!JWT_SECRET || !INTERNAL_SECRET) {
  console.error('FATAL: JWT_SECRET and/or INTERNAL_SECRET environment variables are not set. Refusing to start.');
  process.exit(1);
}

console.log("Intentando conectar a DB con:");
console.log("Host:", process.env.n8n_host);
console.log("User:", process.env.n8n_user);
console.log("database:", process.env.n8n_hosting3m_db);
console.log(`port: ${process.env.port_db}`);

const pool = new Pool({
  user: process.env.n8n_user,
  host: process.env.n8n_host,
  database: process.env.n8n_hosting3m_db,
  password: process.env.n8n_pass,
  port: process.env.port_db,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

// Captura defensiva de errores en el pool para evitar caídas de sockets e interrupción de servicio
pool.on('error', (err) => {
  console.error('Unexpected error on idle PostgreSQL client', err);
});

// ENDPOINT DE GENERACIÓN
app.post('/generate-token', loginLimiter, async (req, res) => {
  const { user, pass, system_id, id_company, internal_secret } = req.body;

  if (internal_secret !== INTERNAL_SECRET) {
    return res.status(403).json({ error: 'Unauthorized' });
  }

  // Guard Clause: Validación defensiva de parámetros requeridos
  if (!user || typeof user !== 'string' || !pass || typeof pass !== 'string') {
    return res.status(400).json({ 
      status: 'error', 
      message: 'Usuario y contraseña son requeridos y deben ser válidos.' 
    });
  }

  try {
    const query = `
      SELECT 
        u.names, 
        u.password, 
        uc.role, 
        uc.id_company,
        c.company_name,
        c.industry
      FROM users u
      INNER JOIN user_companies uc ON u.email = uc.email
      INNER JOIN companys c ON uc.id_company = c.id_company
      WHERE u.email = $1 AND uc.is_active = true
    `;
    const result = await pool.query(query, [user]);

    if (result.rows.length === 0) {
      return res.status(404).json({ status: 'error', message: 'User not found or no companies assigned' });
    }

    const { password: dbHash, names } = result.rows[0];
    let isMatch = false;

    // Verificación segura evitando valores null en el hash de la base de datos
    if (dbHash && typeof dbHash === 'string' && dbHash.startsWith('$2')) {
      isMatch = await bcrypt.compare(pass, dbHash);
    }
    
    if (!isMatch && dbHash) {
      const inputHash = crypto.createHash('sha256').update(pass).digest('hex');
      isMatch = (inputHash === dbHash);
    }

    if (!isMatch) {
      return res.status(401).json({ status: 'error', message: 'Invalid credentials' });
    }

    const authorizedCompanies = result.rows.map(row => ({
      id_company: row.id_company,
      company_name: row.company_name,
      role: row.role,
      industry: row.industry
    }));

    // El usuario NO ha enviado una empresa y tiene MÁS DE 1 asignada
    if (authorizedCompanies.length > 1 && (id_company === undefined || id_company === null || id_company === '')) {
      return res.json({
        status: "select_company",
        message: "Múltiples empresas detectadas",
        data: {
          companies: authorizedCompanies
        }
      });
    }

    // El usuario seleccionó una empresa o solo tiene 1 disponible
    const selectedCompanyId = (id_company !== undefined && id_company !== null && id_company !== '') 
      ? Number(id_company) 
      : authorizedCompanies[0].id_company;

    const companyData = authorizedCompanies.find(c => c.id_company === selectedCompanyId);

    if (!companyData) {
      return res.status(403).json({ status: 'error', message: 'No tienes permisos de acceso para esta empresa.' });
    }

    const token = jwt.sign(
      {
        user,
        name: names,
        id_company: companyData.id_company,
        role: companyData.role,
        system_id: system_id || 'unknown'
      },
      JWT_SECRET,
      { expiresIn: '8h' }
    );

    return res.json({
      status: "success",
      message: "Autenticación exitosa",
      data: {
        token: token,
        role: companyData.role,
        id_company: companyData.id_company,
        company: companyData
      }
    });

  } catch (err) {
    console.error('Error interno en /generate-token:', err);
    res.status(500).json({ status: 'error', message: 'Database error' });
  }
});

// ENDPOINT DE VERIFICACIÓN
app.post('/verify-token', verifyLimiter, (req, res) => {
  const internalSecret = req.headers['internal_secret'];
  if (internalSecret !== INTERNAL_SECRET) {
    return res.status(403).json({ valid: false, error: 'Unauthorized: invalid internal secret' });
  }

  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ valid: false, error: 'No token provided' });

  const token = authHeader.split(' ')[1];

  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) return res.status(401).json({ valid: false, error: 'Invalid token' });

    res.json({
      valid: true,
      user: decoded.user,
      role: decoded.role,
      id_company: decoded.id_company
    });
  });
});

const PORT = 4000;
app.listen(PORT, () => {
  console.log(`JWT service listening on port ${PORT}`);
});