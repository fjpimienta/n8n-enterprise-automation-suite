#!/bin/bash
echo "🚀 Iniciando despliegue de n8n Suite..."

# Traer cambios de GitHub
git pull origin main

# Entrar a infraestructura y actualizar contenedores
cd infrastructure
docker compose up -d --build

echo "✅ Sistema actualizado y corriendo."
cd ..
