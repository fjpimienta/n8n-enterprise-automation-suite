# Imagen base ligera
FROM node:18-alpine

# Instalar dependencias para Puppeteer/Chromium
RUN apk add --no-cache \
  chromium \
  nss \
  freetype \
  harfbuzz \
  ca-certificates \
  ttf-freefont \
  --repository=http://dl-cdn.alpinelinux.org/alpine/v3.19/main

# Establecer directorio de trabajo
WORKDIR /app

# Copiar package.json primero para aprovechar caché de Docker
COPY package*.json ./

# Instalar SOLO dependencias de producción
RUN npm install --production && npm cache clean --force

# Copiar el resto del código
COPY . .

# Variables de entorno por defecto
ENV PORT=3001
ENV NODE_ENV=production
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
# Para Puppeteer en Alpine

# Exponer puerto
EXPOSE 3001

# Comando de inicio
CMD ["node", "index.js"]
