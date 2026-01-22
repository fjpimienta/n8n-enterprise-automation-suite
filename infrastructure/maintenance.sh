#!/bin/bash

# ==============================================================================
# SCRIPT DE MANTENIMIENTO SEGURO N8N
# ==============================================================================
# Este script libera espacio en disco eliminando:
# 1. Backups de base de datos antiguos (Mantiene los últimos 5)
# 2. Caché de compilación de Docker (Basura de builds)
# 3. Imágenes y contenedores DETENIDOS (No toca lo que está corriendo)
# ==============================================================================

# Directorio donde se guardan los backups (Ajustado a tu ruta real)
BACKUP_DIR="/opt/n8n/data/backups"
# Cuántos backups recientes conservar
KEEP_BACKUPS=5

echo "=============================================="
echo "🧹 INICIANDO MANTENIMIENTO DEL SERVIDOR"
echo "📅 Fecha: $(date)"
echo "=============================================="

# ------------------------------------------------------------------------------
# 1. LIMPIEZA DE BACKUPS ANTIGUOS
# ------------------------------------------------------------------------------
echo ""
echo "🗄️  1. VERIFICANDO BACKUPS ANTIGUOS..."

if [ -d "$BACKUP_DIR" ]; then
    # Cuenta cuántos archivos hay
    COUNT=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l)
    
    if [ "$COUNT" -gt "$KEEP_BACKUPS" ]; then
        echo "   -> Se encontraron $COUNT backups. Se conservarán los últimos $KEEP_BACKUPS."
        # Lista por fecha (antiguos al final), salta los primeros N, y borra el resto
        ls -tp "$BACKUP_DIR"/*.tar.gz | grep -v '/$' | tail -n +$(($KEEP_BACKUPS + 1)) | xargs -I {} rm -- "{}"
        echo "   ✅ Backups antiguos eliminados."
    else
        echo "   -> Solo hay $COUNT backups. No es necesario borrar nada."
    fi
else
    echo "   ⚠️ El directorio de backups no existe o está vacío."
fi

# ------------------------------------------------------------------------------
# 2. LIMPIEZA DE DOCKER (Modo Seguro)
# ------------------------------------------------------------------------------
echo ""
echo "🐳 2. LIMPIANDO SISTEMA DOCKER..."

# A. Limpiar caché de compilación (Lo que nos ocupaba 46GB hoy)
# Esto es 100% seguro, solo borra archivos temporales de 'docker build'
echo "   -> Eliminando caché de compilación (Build Cache)..."
docker builder prune -a -f

# B. Limpieza del sistema (Imágenes huérfanas, contenedores detenidos, redes sin uso)
# NOTA: No usamos '-a' aquí por seguridad máxima, solo borramos lo que es basura confirmada.
echo "   -> Eliminando recursos huérfanos (System Prune)..."
docker system prune -f

# ------------------------------------------------------------------------------
# 3. REPORTE FINAL
# ------------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "✨ MANTENIMIENTO COMPLETADO"
echo "=============================================="
echo "📊 USO DE DISCO ACTUAL:"
df -h / | grep /
echo ""
