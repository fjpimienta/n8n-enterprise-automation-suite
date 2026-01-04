#!/bin/bash
# Ruta donde se guardarán los backups
BACKUP_DIR="/var/backups/n8n"
FECHA=$(date +"%Y-%m-%d_%H-%M-%S")

mkdir -p "$BACKUP_DIR"

echo "📦 Creando backup de volumen n8n-compose_n8n_data..."
docker run --rm \
  -v n8n-compose_n8n_data:/data \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf /backup/n8n_backup_$FECHA.tar.gz -C /data .

echo "✅ Backup completado: $BACKUP_DIR/n8n_backup_$FECHA.tar.gz"
