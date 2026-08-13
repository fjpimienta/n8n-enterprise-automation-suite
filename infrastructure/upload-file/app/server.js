const express = require('express');
const multer = require('multer');
const path = require('path');
const crypto = require('crypto');
const fs = require('fs');
const jwt = require('jsonwebtoken');
require('dotenv').config();

const app = express();

// Reuses the SAME JWT_SECRET and INTERNAL_SECRET as n8n-jwt-service.
// These must be set to the identical values in both containers' env --
// that's what lets upload-service validate tokens LOCALLY (no network
// call back to jwt-service on every request), which is the whole point
// of using JWT instead of opaque session tokens.
const JWT_SECRET = process.env.JWT_SECRET;
const INTERNAL_SECRET = process.env.INTERNAL_SECRET;

if (!JWT_SECRET || !INTERNAL_SECRET) {
    console.error('FATAL: JWT_SECRET and/or INTERNAL_SECRET environment variables are not set. Refusing to start.');
    process.exit(1);
}

// Two-tier trust, mirroring jwt-service's own /generate-token pattern:
//   1. A real user JWT (Authorization: Bearer <token>) -- signed by
//      jwt-service, verified here with the shared secret.
//   2. The internal service secret (x-internal-secret header) -- for
//      trusted backend callers (n8n workflows) that act without a
//      logged-in user.
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

// NOTE: this route now requires the same auth as uploads (see app.use
// below). Files are no longer publicly readable by anyone with the URL --
// callers must present a valid JWT (Angular's core-auth interceptor
// already does this automatically for HttpClient requests) or the
// internal secret (n8n workflows). Plain <img src="..."> tags and
// pasted links (e.g. into WhatsApp) will no longer work without an
// authenticated request -- this is intentional for documents containing
// identification data.
app.use('/uploads', requireAuth, express.static('uploads'));

const storage = multer.diskStorage({
    destination: './uploads',
    filename: (req, file, cb) => {
        // Cryptographically random filename -- not sequential/guessable.
        const randomName = crypto.randomBytes(32).toString('hex');
        cb(null, randomName + path.extname(file.originalname));
    }
});

const upload = multer({
    storage,
    limits: { fileSize: 25 * 1024 * 1024 } // 25MB cap -- adjust if real documents exceed this
});

app.get('/', (req, res) => {
    res.send('Servicio de carga activo.');
});

app.post('/upload', requireAuth, upload.single('file'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

    // Compute SHA-256 server-side so the hash is authoritative, not
    // something the caller could supply incorrectly.
    const filePath = path.join('./uploads', req.file.filename);
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
