const express = require('express');
const multer = require('multer');
const path = require('path');

const app = express();

// Servir la carpeta uploads para que las imágenes sean públicas
app.use('/uploads', express.static('uploads'));

const storage = multer.diskStorage({
    destination: './uploads',
    filename: (req, file, cb) => {
        // Mantener la extensión original
        cb(null, Date.now() + path.extname(file.originalname));
    }
});

const upload = multer({ storage });

app.get('/', (req, res) => {
    res.send('Servicio de carga activo.');
});

// Ruta de subida que devuelve JSON
app.post('/upload', upload.single('file'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

    res.json({
        status: 'SUCCESS',
        filename: req.file.filename,
        url: `https://upload.hosting3m.com/uploads/${req.file.filename}`
    });
});

app.listen(3000, '0.0.0.0', () => console.log('Server running on port 3000'));