#!/bin/bash
# backup_docker_n8n.sh
# Backup de n8n + MongoDB + docker-compose.yml y envío a SFTP

# --- CONFIGURACIÓN ---
BACKUP_DIR="/var/lib/psa/dumps/docker_backups"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Nombres de volúmenes Docker
N8N_VOLUME="n8n-compose_n8n_data"
MONGO_VOLUME="mongodb_data"

# Carpeta de docker-compose
COMPOSE_DIR="/var/www/vhosts/hosting3m.com/n8n.hosting3m.com/n8n-compose"

# Datos SFTP
SFTP_USER="acc725120992"
SFTP_HOST="access764970042.webspace-data.io"
SFTP_PATH="/_ServerHosting3m"

# Email de notificación
EMAIL="fjpimienta@gmail.com"

# --- CREAR CARPETA LOCAL ---
mkdir -p $BACKUP_DIR

# --- BACKUP VOLÚMENES ---
echo "[INFO] Haciendo backup de volúmenes Docker..."
docker run --rm -v $N8N_VOLUME:/data -v $BACKUP_DIR:/backup busybox tar czvf /backup/n8n_data_$TIMESTAMP.tar.gz /data
docker run --rm -v $MONGO_VOLUME:/data -v $BACKUP_DIR:/backup busybox tar czvf /backup/mongodb_data_$TIMESTAMP.tar.gz /data

# --- BACKUP docker-compose.yml y scripts ---
echo "[INFO] Haciendo backup de docker-compose..."
tar czvf $BACKUP_DIR/docker_compose_$TIMESTAMP.tar.gz -C $COMPOSE_DIR .

# --- VERIFICAR BACKUPS ---
echo "[INFO] Verificando backups..."
ls -lh $BACKUP_DIR

# --- SUBIR A SFTP ---
echo "[INFO] Subiendo backups a SFTP..."
sftp $SFTP_USER@$SFTP_HOST <<EOF
mkdir $SFTP_PATH 2>/dev/null
put $BACKUP_DIR/*
bye
EOF

# --- EMAIL DE NOTIFICACIÓN ---
echo "Backup Docker n8n completado en $TIMESTAMP" | mail -s "Backup n8n completado" $EMAIL

echo "[INFO] Backup completado."
