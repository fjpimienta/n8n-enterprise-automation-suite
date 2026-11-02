FROM node:25-alpine

WORKDIR /app
COPY app/package.json app/package-lock.json ./
RUN npm ci --omit=dev

COPY app .

EXPOSE 3000

CMD ["node", "server.js"]
