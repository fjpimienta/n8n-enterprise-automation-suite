const express = require('express');
const multer = require('multer');
const path = require('path');
const crypto = require('crypto');
const fs = require('fs');
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
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

const JWT_SECRET = process.env.JWT_SECRET;
const INTERNAL_SECRET = process.env.INTERNAL_SECRET;

if (!JWT_SECRET || !INTERNAL_SECRET) {
    console.error('FATAL: JWT_SECRET and/or INTERNAL_SECRET environment variables are not set. Refusing to start.');
    process.exit(1);
}

function requireAuth(req, res, next) {
    const internalSecret = req.headers['x-internal-secret'];
    if (internalSecret && internalSecret === INTERNAL_SECRET) {
        req.auth = { type: 'internal' };
        return next();
    }

    const authHeader = req.headers.authorization;
    if (authHeader) {
        const token = authHeader.split(' ')[1];
        try {
            const decoded = jwt.verify(token, JWT_SECRET);
            req.auth = { type: 'user', user: decoded.user, id_company: decoded.id_company, role: decoded.role };
            return next();
        } catch (err) {
            return res.status(401).json({ error: 'Invalid or expired token' });
        }
    }

    return res.status(401).json({ error: 'Unauthorized: provide a valid JWT or the internal service secret' });
}

// Aplicación de rate limiting y autenticación en la ruta estática protegida
app.use('/uploads', apiLimiter, requireAuth, express.static('uploads'));

const storage = multer.diskStorage({
    destination: './uploads',
    filename: (req, file, cb) => {
        const randomName = crypto.randomBytes(32).toString('hex');
        // Sanitización estricta de la extensión para evitar entradas maliciosas
        const safeExt = path.extname(file.originalname).toLowerCase().replace(/[^a-z0-9.]/g, '');
        cb(null, randomName + safeExt);
    }
});

const upload = multer({
    storage,
    limits: { fileSize: 25 * 1024 * 1024 }
});

app.get('/', apiLimiter, (req, res) => {
    res.send('Servicio de carga activo.');
});

// Aplicación de rate limiting en la ruta protegida de subida de archivos
app.post('/upload', apiLimiter, requireAuth, upload.single('file'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

    // 1. Definir la ruta raíz autorizada de manera absoluta
    const UPLOAD_DIR = path.resolve(process.cwd(), 'uploads');

    // 2. Construir y normalizar la ruta del archivo solicitado
    const filePath = path.resolve(UPLOAD_DIR, req.file.filename);

    // 3. Boundary Check: Validación estricta requerida por CodeQL
    if (!filePath.startsWith(UPLOAD_DIR)) {
        return res.status(403).json({ error: 'Forbidden: Path Traversal detected' });
    }

    // 4. Ejecución segura de lectura en disco
    const fileBuffer = fs.readFileSync(filePath);
    const sha256Hash = crypto.createHash('sha256').update(fileBuffer).digest('hex');

    res.json({
        status: 'SUCCESS',
        filename: req.file.filename,
        original_name: req.file.originalname,
        mime_type: req.file.mimetype,
        size_bytes: req.file.size,
        sha256_hash: sha256Hash,
        uploaded_by: req.auth.type === 'user' ? req.auth.user : 'internal-service',
        url: `https://upload.hosting3m.com/uploads/${req.file.filename}`
    });
});

app.listen(3000, '0.0.0.0', () => console.log('Server running on port 3000'));
