FROM node:20-alpine

ENV NODE_ENV=production
WORKDIR /usr/src/app

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY lib ./lib
COPY src ./src

# STORAGE_ROOT must be a mounted volume owned by uid 1000 (node); see README
ENV PORT=4100
EXPOSE 4100
USER node

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4100/health || exit 1

CMD ["node", "src/index.js"]
