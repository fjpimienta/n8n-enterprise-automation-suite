FROM node:18-alpine

# Crear carpeta app
WORKDIR /usr/src/app

# Copiar package.json y package-lock.json (si tienes)
COPY package*.json ./

# Instalar dependencias
RUN npm cache clean --force && npm install

# Copiar el resto del código
COPY . .

# Exponer puerto que usará el servicio (ejemplo 4000)
EXPOSE 4000

# Comando para iniciar la app
CMD ["node", "index.js"]
