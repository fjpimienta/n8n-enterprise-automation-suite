#!/bin/bash

# --- CONFIGURACIÓN ---
INFRA_PATH="/var/www/vhosts/hosting3m.com/n8n.hosting3m.com/n8n-compose/infrastructure"
DATA_PATH="/opt/n8n/data/postgres_db_backup"
BACKUP_PATH="/opt/n8n/data/backups"
DATE=$(date +%Y-%m-%d_%H%M%S)

# Crear carpeta de backups si no existe
mkdir -p $BACKUP_PATH

echo "📦 1. CREANDO BACKUP DE SEGURIDAD..."
# Comprimimos la carpeta de la base de datos antes de tocar nada
tar -cvzf $BACKUP_PATH/db_backup_$DATE.tar.gz $DATA_PATH > /dev/null

if [ $? -eq 0 ]; then
    echo "✅ Backup guardado en: $BACKUP_PATH/db_backup_$DATE.tar.gz"
else
    echo "❌ ERROR: El backup falló. No se procederá con la actualización."
    exit 1
fi

echo "📥 2. DESCARGANDO ÚLTIMA IMAGEN BASE..."
docker pull node:20-bookworm-slim

echo "🏗️ 3. RECONSTRUYENDO IMAGEN PERSONALIZADA (Dockerfile.n8n)..."
cd $INFRA_PATH
docker compose build --no-cache

# $? captura el código de salida del comando anterior. Si no es 0, hubo error.
if [ $? -ne 0 ]; then
    echo "❌ ERROR CRÍTICO: La imagen no se pudo construir."
    echo "🛑 El proceso se detiene aquí. Tu producción NO ha sido tocada."
    exit 1
fi
# -----------------------------

echo "🔄 4. REINICIANDO SERVICIOS..."
# En lugar de 'down' (que borra todo), usamos 'up -d' 
# Esto descarga el contenedor viejo y levanta el nuevo en segundos.
docker compose up -d

echo "🧹 5. LIMPIEZA DE BACKUPS ANTIGUOS (Mantenemos los últimos 5)..."
ls -1tr $BACKUP_PATH/db_backup_*.tar.gz | head -n -5 | xargs -d '\n' rm -f -- 2>/dev/null

echo "✨ PROCESO FINALIZADO"
docker compose ps
