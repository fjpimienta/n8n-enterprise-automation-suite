const express = require('express');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const bcrypt = require('bcrypt');
require('dotenv').config();
const rateLimit = require('express-rate-limit');

const app = express();
app.use(express.json());
app.use(cors({ 
  origin: 'https://hosting3m.com',
  methods: ['POST'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

// Limiter para la ruta de login (protege contra fuerza bruta)
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutos
  max: 10, // Máximo 10 intentos por IP
  message: { error: 'Demasiados intentos de login. Intente más tarde.' },
  standardHeaders: true, // Envía headers con info de rate limit
  legacyHeaders: false,
});

const JWT_SECRET = process.env.JWT_SECRET;
const INTERNAL_SECRET = process.env.INTERNAL_SECRET;

const { Pool } = require('pg');

console.log("Intentando conectar a DB con:");
console.log("Host:", process.env.n8n_host);
console.log("User:", process.env.n8n_user);
console.log("database:", process.env.n8n_hosting3m_db);
console.log(`port: ${process.env.port_db}`);

// Configuración de la DB (usa tus variables de entorno)
const pool = new Pool({
  user: process.env.n8n_user,
  host: process.env.n8n_host,
  database: process.env.n8n_hosting3m_db,
  password: process.env.n8n_pass,
  port: process.env.port_db,
});

// ENDPOINT DE GENERACIÓN
app.post('/generate-token', loginLimiter, async (req, res) => {
  const { user, pass, internal_secret } = req.body;

  // LOGS DE DEBUG (Añade estas líneas)
  console.log(`Intento de login para: ${user}`);
  console.log(`¿Llegó contraseña?: ${pass ? 'SÍ (longitud: ' + pass.length + ')' : 'NO'}`);
  console.log(`Internal Secret recibido: ${internal_secret}`);  
  
  if (internal_secret !== INTERNAL_SECRET) {
    return res.status(403).json({ error: 'Unauthorized' });
  }

  try {
    const query = 'SELECT role, password, id_company, names FROM users WHERE email = $1 LIMIT 1';
    const result = await pool.query(query, [user]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const { role, password: dbHash, id_company, names } = result.rows[0];

    /**
     * MEJOR PRÁCTICA: Transición a Bcrypt
     * Intentamos comparar con bcrypt. Si falla (porque la clave está en texto plano),
     * comparamos texto plano directamente. Esto permite que tus usuarios actuales entren
     * y puedas actualizar sus claves después.
     */
    // Intentamos comparar con Bcrypt
    let isMatch = false;
    
    // Verificamos si dbHash parece un hash de bcrypt (empieza con $2)
    if (dbHash && dbHash.startsWith('$2')) {
      isMatch = await bcrypt.compare(pass, dbHash);
    }
    
    // Si no hubo match con bcrypt, probamos con texto plano (Fallback)
    if (!isMatch) {
      isMatch = (pass === dbHash);
    }

    if (!isMatch) { 
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // FIRMAMOS EL TOKEN con el "Scope" completo
    const token = jwt.sign(
      { 
        user, 
        role, 
        id_company,
        name: names // Útil para mostrar en el frontend
      }, 
      JWT_SECRET, 
      { expiresIn: '8h' } 
    );
    
    res.json({ token, role, id_company });

  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Database error' });
  }
});

// ENDPOINT DE VERIFICACIÓN (Asegúrate de devolver el id_company)
app.post('/verify-token', (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader) return res.status(401).json({ valid: false, error: 'No token provided' });

  const token = authHeader.split(' ')[1];

  jwt.verify(token, JWT_SECRET, (err, decoded) => {
    if (err) return res.status(401).json({ valid: false, error: 'Invalid token' });
    
    // Devolvemos TODO el contenido decodificado para que n8n lo use
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
