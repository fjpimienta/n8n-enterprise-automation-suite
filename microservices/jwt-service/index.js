const express = require('express');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const rateLimit = require('express-rate-limit'); // 1. Importar librería
require('dotenv').config();

const app = express();
app.use(express.json());

// --- CONFIGURACIÓN DE RATE LIMITERS ---

// Limite general para verificación (ej. 100 peticiones cada 15 min por IP)
const verifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: { error: 'Demasiadas verificaciones. Intente más tarde.' },
  standardHeaders: true,
  legacyHeaders: false,
});

// Limite estricto para generación (ej. 10 peticiones cada 15 min por IP)
// Esto protege la Base de Datos de ataques de fuerza bruta
const generateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: { error: 'Límite de generación de tokens excedido.' },
  standardHeaders: true,
  legacyHeaders: false,
});

// ---------------------------------------

app.use(cors({
  origin: 'https://hosting3m.com',
  methods: ['POST'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

const JWT_SECRET = process.env.JWT_SECRET;
const INTERNAL_SECRET = process.env.INTERNAL_SECRET;

const { Pool } = require('pg');
const pool = new Pool({
  user: process.env.n8n_user,
  host: process.env.n8n_host,
  database: process.env.n8n_hosting3m_db,
  password: process.env.n8n_pass,
  port: process.env.port_db,
});

// ENDPOINT DE GENERACIÓN
app.post('/generate-token', generateLimiter, async (req, res) => {
  const { user, internal_secret } = req.body;

  if (internal_secret !== process.env.INTERNAL_SECRET) {
    return res.status(403).json({ error: 'Unauthorized' });
  }

  try {
    const query = 'SELECT role FROM users WHERE email = $1 LIMIT 1';
    const result = await pool.query(query, [user]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found in database' });
    }

    const userRole = result.rows[0].role;
    const token = jwt.sign({ user, role: userRole }, JWT_SECRET, { expiresIn: '1h' });

    res.json({ token, role: userRole });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Database error' });
  }
});

// ENDPOINT DE VERIFICACIÓN
app.post('/verify-token', verifyLimiter, (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ valid: false, error: 'No token provided' });

  const token = authHeader.split(' ')[1];

  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) {
      return res.status(401).json({ valid: false, error: 'Invalid or expired token' });
    }
    res.json({
      valid: true,
      user: decoded.user,
      role: decoded.role
    });
  });
});

const PORT = 4000;
app.listen(PORT, () => {
  console.log(`JWT service listening on port ${PORT}`);
});