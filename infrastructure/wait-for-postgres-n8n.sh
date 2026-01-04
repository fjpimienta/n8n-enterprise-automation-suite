#!/bin/sh
set -e
echo "Esperando que PostgreSQL esté listo en $DB_POSTGRESDB_HOST:$DB_POSTGRESDB_PORT..."
timeout=60
until pg_isready -h "$DB_POSTGRESDB_HOST" -p "$DB_POSTGRESDB_PORT" -U "$DB_POSTGRESDB_USER" > /dev/null 2>&1; do
  echo "PostgreSQL no listo. Esperando 1 segundo..."
  sleep 1
  timeout=$((timeout - 1))
  if [ $timeout -eq 0 ]; then
    echo "PostgreSQL no respondió en 60s. Abortando."
    exit 1
  fi
done
echo "PostgreSQL listo. Iniciando n8n..."
exec n8n
