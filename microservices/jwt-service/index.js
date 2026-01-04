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

app.post('/generate-token', (req, res) => {
  const { user } = req.body;
  if (!user) {
    return res.status(400).json({ error: 'User is required' });
  }

  const token = jwt.sign({ user }, JWT_SECRET, { expiresIn: '1h' });
  res.json({ token });
});

const PORT = 4000;
app.listen(PORT, () => {
  console.log(`JWT service listening on port ${PORT}`);
});
