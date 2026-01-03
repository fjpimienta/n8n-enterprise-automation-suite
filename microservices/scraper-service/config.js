module.exports = {
  PORT: process.env.PORT || 3001,
  // Usamos un User-Agent de Chrome en Windows para máxima compatibilidad
  USER_AGENT: process.env.USER_AGENT ||
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
};
