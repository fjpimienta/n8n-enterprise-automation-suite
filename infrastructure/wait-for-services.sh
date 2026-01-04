#!/bin/sh
set -e
TIMEOUT=${SERVICES_TIMEOUT:-60}

# Esperar a PostgreSQL
echo "Esperando que PostgreSQL esté listo en $DB_POSTGRESDB_HOST:$DB_POSTGRESDB_PORT..."
until pg_isready -h "$DB_POSTGRESDB_HOST" -p "$DB_POSTGRESDB_PORT" -U "$DB_POSTGRESDB_USER" > /dev/null 2>&1; do
  echo "PostgreSQL no listo. Esperando 1 segundo..."
  sleep 1
  TIMEOUT=$((TIMEOUT - 1))
  if [ $TIMEOUT -eq 0 ]; then
    echo "PostgreSQL no respondió en ${SERVICES_TIMEOUT}s. Abortando."
    exit 1
  fi
done
echo "PostgreSQL listo."

echo "Iniciando n8n..."
exec n8n
