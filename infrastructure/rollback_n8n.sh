#!/bin/bash

# --- CONFIGURACIÓN ---
INFRA_PATH="/var/www/vhosts/hosting3m.com/n8n.hosting3m.com/n8n-compose/infrastructure"
DATA_PATH="/opt/n8n/data/postgres_db_backup"
BACKUP_PATH="/opt/n8n/data/backups"

echo "⚠️ INICIANDO ROLLBACK DE EMERGENCIA..."

# 1. Buscar el backup más reciente
LATEST_BACKUP=$(ls -1t $BACKUP_PATH/db_backup_*.tar.gz 2>/dev/null | head -n 1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ ERROR: No se encontró ningún archivo de backup en $BACKUP_PATH"
    exit 1
fi

echo "📂 Backup detectado: $LATEST_BACKUP"
read -p "¿Estás seguro de que quieres restaurar este backup? (s/n): " confirm
if [[ $confirm != [sS] ]]; then
    echo "Abortado por el usuario."
    exit 1
fi

echo "🛑 1. DETENIENDO CONTENEDORES..."
cd $INFRA_PATH
docker compose down

echo "🗑️ 2. LIMPIANDO DATOS ACTUALES..."
# IMPORTANTE: Solo borramos el contenido de la carpeta de la base de datos
rm -rf $DATA_PATH/*

echo "📦 3. RESTAURANDO BACKUP..."
# Extraemos el backup. Como se creó con la ruta absoluta, se restaura en su sitio.
tar -xvzf $LATEST_BACKUP -C /

echo "🚀 4. LEVANTANDO SERVICIOS..."
# Levantamos con la configuración anterior
docker compose up -d

echo "✅ ROLLBACK FINALIZADO."
echo "Por favor, verifica el acceso a n8n en tu navegador."
docker compose ps
