#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Generación Nivel 2 Atmosphere EDR v1.0
# ==============================================================================

# 1. CONFIGURACIÓN DE RUTAS EN EL HOST
# ------------------------------------------------------------------------------
SIF_ATMOS="/opt/containers/cspp_atmos_edr_v1.0.sif"

# Rutas en Lustre
HOST_STATIC="/data/opt/CSPP_ATMOS_1_0/anc/static"
HOST_ANC="/data/ancillary" 
HOST_SDR_IN="/data/output/jpss/level1/viirs"
HOST_EDR_OUT="/data/output/jpss/level2/atmosphere"

# Directorio de trabajo temporal
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOST_WORK="/data/tmp/atmos_work_$TIMESTAMP"
mkdir -p "$HOST_WORK" "$HOST_EDR_OUT"

# Logs
LOG_DIR="/var/log/lanot/polares/cspp-edr"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/atmos_edr_$TIMESTAMP.log"

echo "=== INICIANDO PROCESAMIENTO ATMOSPHERE EDR v1.0 ===" | tee -a "$LOG_FILE"

# 2. EJECUCIÓN
# ------------------------------------------------------------------------------
apptainer exec \
    --bind "$HOST_SDR_IN:/input_sdr" \
    --bind "$HOST_EDR_OUT:/output_edr" \
    --bind "$HOST_STATIC:/opt/cspp_atmos_edr/static" \
    --bind "$HOST_ANC:/opt/cspp_atmos_edr/ancillary" \
    --bind "$HOST_WORK:/work" \
    "$SIF_ATMOS" /bin/bash -c "
        # Variables de entorno manuales para el motor Enterprise
        export CSPP_VIIRS_ATMOS_HOME=/opt/cspp_atmos_edr
        export PATH=\$CSPP_VIIRS_ATMOS_HOME/bin:\$PATH
        export HDF5_USE_FILE_LOCKING=FALSE
        
        # Nos movemos a la carpeta de salida montada para que los resultados queden ahí
        cd /output_edr
        
        echo '--- Ejecutando viirs_atmos.sh ---'
        
        # SINTAXIS SEGÚN HELP: viirs_atmos.sh [opciones] <directorio_entrada>
        # -W: Directorio de trabajo
        # -p: Número de procesadores (ajustar según capacidad del servidor)
        viirs_atmos.sh -v -l -W /work -p 20 /input_sdr
    " >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

# 3. FINALIZACIÓN
# ------------------------------------------------------------------------------
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ ÉXITO: Productos generados en $HOST_EDR_OUT" | tee -a "$LOG_FILE"
    # rm -rf "$HOST_WORK" # Descomentar para limpiar temporales automáticamente
else
    echo "❌ ERROR: El procesamiento falló. Revisa el log en:" | tee -a "$LOG_FILE"
    echo "   $LOG_FILE" | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi
