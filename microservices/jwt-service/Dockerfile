FROM node:22-alpine

# Crear carpeta app
WORKDIR /usr/src/app

# Copy package manifests before installing dependencies
COPY package.json package-lock.json ./

RUN npm ci --omit=dev

# Copiar el resto del código
COPY . .

# Exponer puerto que usará el servicio (ejemplo 4000)
EXPOSE 4000

# Comando para iniciar la app
CMD ["node", "index.js"]
