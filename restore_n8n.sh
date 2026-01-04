#!/bin/bash
BACKUP_FILE="/var/backups/n8n/n8n_backup_2025-08-15_12-30-00.tar.gz"

echo "🛠 Restaurando backup en volumen n8n-compose_n8n_data..."
docker run --rm \
  -v n8n-compose_n8n_data:/data \
  -v $(dirname "$BACKUP_FILE"):/backup \
  alpine sh -c "rm -rf /data/* && tar xzf /backup/$(basename "$BACKUP_FILE") -C /data"

echo "✅ Restauración completada."
