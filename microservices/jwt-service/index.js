const express = require('express');
const jwt = require('jsonwebtoken');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(express.json());
app.use(cors({ 
  origin: 'https://hosting3m.com',
  methods: ['POST'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

const JWT_SECRET = process.env.JWT_SECRET;
const INTERNAL_SECRET = process.env.INTERNAL_SECRET;

const { Pool } = require('pg');

console.log("Intentando conectar a DB con:");
console.log("Host:", process.env.n8n_host);
console.log("User:", process.env.n8n_user);
console.log("database:", process.env.n8n_hosting3m_db);

// Configuración de la DB (usa tus variables de entorno)
const pool = new Pool({
  user: process.env.n8n_user,
  host: process.env.n8n_host,
  database: process.env.n8n_hosting3m_db,
  password: process.env.n8n_pass,
  port: process.env.port_db,
});

// ENDPOINT DE GENERACIÓN
app.post('/generate-token', async (req, res) => {
  const { user, internal_secret } = req.body;
  
  // 1. Validación de seguridad básica
  if (internal_secret !== process.env.INTERNAL_SECRET) {
    return res.status(403).json({ error: 'Unauthorized' });
  }

  try {
    // 2. Consulta a la base de datos para obtener el rol
    // Asumiendo que tienes una tabla 'users' con columnas 'email' y 'role'
    const query = 'SELECT role FROM users WHERE email = $1 LIMIT 1';
    const result = await pool.query(query, [user]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found in database' });
    }

    const userRole = result.rows[0].role;

    // 3. El token ahora lleva el ROL real de la DB
    const token = jwt.sign({ user, role: userRole }, JWT_SECRET, { expiresIn: '1h' });
    
    res.json({ token, role: userRole });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Database error' });
  }
});

// ENDPOINT DE VERIFICACIÓN
app.post('/verify-token', (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ valid: false, error: 'No token provided' });

  const token = authHeader.split(' ')[1]; // Extrae el token del Bearer

  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) {
      return res.status(401).json({ valid: false, error: 'Invalid or expired token' });
    }
    // Si es válido, devolvemos los datos del usuario decodificados
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
