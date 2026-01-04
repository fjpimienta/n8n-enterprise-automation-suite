#!/bin/bash
# restore_docker_n8n.sh
# Restaurar n8n + MongoDB + docker-compose.yml desde backups

# --- CONFIGURACIÓN ---
BACKUP_DIR="/var/lib/psa/dumps/docker_backups"  # carpeta donde descargaste los .tar.gz
COMPOSE_DIR="/var/www/vhosts/hosting3m.com/n8n.hosting3m.com/n8n-compose"

# Nombres de volúmenes Docker
N8N_VOLUME="n8n-compose_n8n_data"
MONGO_VOLUME="mongodb_data"

# --- CREAR VOLÚMENES VACÍOS ---
docker volume create $N8N_VOLUME
docker volume create $MONGO_VOLUME

# --- RESTAURAR VOLÚMENES ---
echo "[INFO] Restaurando volúmenes Docker..."
docker run --rm -v $N8N_VOLUME:/data -v $BACKUP_DIR:/backup busybox tar xzvf /backup/n8n_data_*.tar.gz -C /
docker run --rm -v $MONGO_VOLUME:/data -v $BACKUP_DIR:/backup busybox tar xzvf /backup/mongodb_data_*.tar.gz -C /

# --- RESTAURAR docker-compose.yml ---
echo "[INFO] Restaurando docker-compose..."
tar xzvf $BACKUP_DIR/docker_compose_*.tar.gz -C $COMPOSE_DIR

# --- LEVANTAR STACK ---
echo "[INFO] Levantando Docker Compose..."
cd $COMPOSE_DIR
docker compose up -d

echo "[INFO] Restauración completada. n8n debería estar disponible."
