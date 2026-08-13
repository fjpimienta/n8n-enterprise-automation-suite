const express = require('express');
const multer = require('multer');
const path = require('path');
const crypto = require('crypto');
const fs = require('fs');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit'); //[cite: 1]
require('dotenv').config();

const app = express();

// Configuración del limitador de tasa para prevenir ataques de fuerza bruta y denegación de servicio
const apiLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutos
    max: 100, // Límite de 100 solicitudes por IP
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Demasiadas solicitudes desde esta IP, intente más tarde.' }
});

const JWT_SECRET = process.env.JWT_SECRET; //[cite: 1]
const INTERNAL_SECRET = process.env.INTERNAL_SECRET; //[cite: 1]

if (!JWT_SECRET || !INTERNAL_SECRET) {
    console.error('FATAL: JWT_SECRET and/or INTERNAL_SECRET environment variables are not set. Refusing to start.'); //[cite: 1]
    process.exit(1); //[cite: 1]
}

function requireAuth(req, res, next) {
    const internalSecret = req.headers['x-internal-secret']; //[cite: 1]
    if (internalSecret && internalSecret === INTERNAL_SECRET) { //[cite: 1]
        req.auth = { type: 'internal' }; //[cite: 1]
        return next(); //[cite: 1]
    }

    const authHeader = req.headers.authorization; //[cite: 1]
    if (authHeader) { //[cite: 1]
        const token = authHeader.split(' ')[1]; //[cite: 1]
        try {
            const decoded = jwt.verify(token, JWT_SECRET); //[cite: 1]
            req.auth = { type: 'user', user: decoded.user, id_company: decoded.id_company, role: decoded.role }; //[cite: 1]
            return next(); //[cite: 1]
        } catch (err) {
            return res.status(401).json({ error: 'Invalid or expired token' }); //[cite: 1]
        }
    }

    return res.status(401).json({ error: 'Unauthorized: provide a valid JWT or the internal service secret' }); //[cite: 1]
}

// Aplicación de rate limiting y autenticación en la ruta estática protegida
app.use('/uploads', apiLimiter, requireAuth, express.static('uploads')); //[cite: 1]

const storage = multer.diskStorage({
    destination: './uploads', //[cite: 1]
    filename: (req, file, cb) => {
        const randomName = crypto.randomBytes(32).toString('hex'); //[cite: 1]
        // Sanitización estricta de la extensión para evitar entradas maliciosas
        const safeExt = path.extname(file.originalname).toLowerCase().replace(/[^a-z0-9.]/g, '');
        cb(null, randomName + safeExt);
    }
});

const upload = multer({
    storage, //[cite: 1]
    limits: { fileSize: 25 * 1024 * 1024 } //[cite: 1]
});

app.get('/', apiLimiter, (req, res) => { //[cite: 1]
    res.send('Servicio de carga activo.'); //[cite: 1]
});

// Aplicación de rate limiting en la ruta protegida de subida de archivos
app.post('/upload', apiLimiter, requireAuth, upload.single('file'), (req, res) => { //[cite: 1]
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' }); //[cite: 1]

    const filePath = path.join('./uploads', req.file.filename); //[cite: 1]
    const fileBuffer = fs.readFileSync(filePath); //[cite: 1]
    const sha256Hash = crypto.createHash('sha256').update(fileBuffer).digest('hex'); //[cite: 1]

    res.json({
        status: 'SUCCESS', //[cite: 1]
        filename: req.file.filename, //[cite: 1]
        original_name: req.file.originalname, //[cite: 1]
        mime_type: req.file.mimetype, //[cite: 1]
        size_bytes: req.file.size, //[cite: 1]
        sha256_hash: sha256Hash, //[cite: 1]
        uploaded_by: req.auth.type === 'user' ? req.auth.user : 'internal-service', //[cite: 1]
        url: `https://upload.hosting3m.com/uploads/${req.file.filename}` //[cite: 1]
    });
});

app.listen(3000, '0.0.0.0', () => console.log('Server running on port 3000')); //[cite: 1]