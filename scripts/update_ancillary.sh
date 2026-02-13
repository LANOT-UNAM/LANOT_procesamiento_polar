#!/bin/bash
# ==============================================================================
# ACTUALIZADOR AUTOMÁTICO DE DATOS ANCILIARES (CSPP SDR)
# Descarga TLE, Actitud y Efemérides para el día en curso.
# ==============================================================================

# 1. CONFIGURACIÓN
# ------------------------------------------------------------------------------
SIF_CONTAINER="/opt/containers/cspp_sdr_v4.1.sif"
HOST_ANCILLARY="/data/ancillary"
HOST_CACHE="/data/opt/SDR_4_1/anc"  # Ruta donde el contenedor puede escribir temporales
LOG_FILE="/var/log/lanot/polares/cspp-sdr/update_ancillary.log"

# Fecha actual formato YYYYMMDD
FECHA_HOY=$(date +%Y%m%d)

# Asegurar que existe directorio de logs
mkdir -p $(dirname "$LOG_FILE")

echo "========================================================" >> "$LOG_FILE"
echo "Iniciando actualización: $(date)" >> "$LOG_FILE"
echo "Objetivo: $FECHA_HOY" >> "$LOG_FILE"

# 2. EJECUCIÓN DE LA DESCARGA
# ------------------------------------------------------------------------------
# Usamos los mismos Binds críticos que descubrimos hoy:
# - Montamos /ancillary para guardar los datos finales.
# - Montamos /opt/cspp_sdr/anc para que pueda escribir en la caché interna.
# - Usamos la variable de entorno para forzar la salida.

apptainer exec \
    --bind "$HOST_ANCILLARY":/ancillary \
    --bind "$HOST_CACHE":/opt/cspp_sdr/anc \
    --env CSPP_DYNAMIC_ANCIL_DIR=/ancillary \
    "$SIF_CONTAINER" \
    /opt/cspp_sdr/bin/sdr_ancillary.sh -t "$FECHA_HOY" -a cache \
    >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Descarga exitosa." >> "$LOG_FILE"
else
    echo "❌ Error en la descarga. Código: $EXIT_CODE" >> "$LOG_FILE"
fi

# 3. LIMPIEZA (OPCIONAL PERO RECOMENDADO)
# ------------------------------------------------------------------------------
# Borra archivos de ancillary más viejos de 15 días para ahorrar espacio
echo "Limpiando archivos antiguos (>15 días)..." >> "$LOG_FILE"
find "$HOST_ANCILLARY" -type f -mtime +15 -delete >> "$LOG_FILE" 2>&1

echo "Fin del proceso: $(date)" >> "$LOG_FILE"
echo "========================================================" >> "$LOG_FILE"


