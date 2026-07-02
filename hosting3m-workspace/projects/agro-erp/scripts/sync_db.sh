#!/bin/bash

set -e

DB_CONTAINER_NAME="n8n-enterprise-db"
DB_USER="n8n_user"
DB_NAME="hosting3m_db"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

mkdir -p "$PROJECT_DIR/database/seeds"

echo "⏳ Sincronizando repositorio con la base de datos..."

docker exec -t "$DB_CONTAINER_NAME" pg_dump \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  --schema-only \
  --no-owner \
  --no-privileges \
  --exclude-table='*backup*' \
  > "$PROJECT_DIR/database/schema.sql"

echo "✅ Estructura exportada."

docker exec -t "$DB_CONTAINER_NAME" pg_dump \
  -U "$DB_USER" \
  -d "$DB_NAME" \
  --table=crud_models \
  --data-only \
  --inserts \
  --column-inserts \
  > "$PROJECT_DIR/database/seeds/crud_models_seed.sql"

echo "✅ CRUD Models exportados."