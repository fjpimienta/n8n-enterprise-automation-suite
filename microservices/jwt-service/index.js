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

// ENDPOINT DE GENERACIÓN
app.post('/generate-token', (req, res) => {
  const { user, internal_secret } = req.body; // Recibimos el secreto
  
  if (!user) return res.status(400).json({ error: 'User is required' });

  // VALIDACIÓN: Si no es el secreto correcto, rechazamos
  if (internal_secret !== INTERNAL_SECRET) {
    return res.status(403).json({ error: 'Unauthorized: Invalid internal secret' });
  }

  // IMPORTANTE: Definimos el ROL aquí, no en n8n
  const role = user === 'n8n@hosting3m.com' ? 'ADMIN' : 'CUSTOMER';

  const token = jwt.sign({ user, role }, JWT_SECRET, { expiresIn: '1h' });
  res.json({ token, role }); // Devolvemos el rol también para comodidad de n8n
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
