#!/bin/bash
# ==============================================================================
# SCRIPT: Actualización Diaria de LUTs y Ancillary (CSPP SDR v4.1.1)
# ==============================================================================

# 1. CONFIGURACIÓN DE RUTAS
SIF_CSPP="/opt/containers/cspp_sdr_v4.1.1.sif"
HOST_STATIC_BASE="/data/opt/SDR_4_1"
HOST_DYNAMIC="/data/ancillary"

# Directorio de logs
LOG_DIR="/var/log/lanot/polares/cspp-sdr"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/update_daily_${TIMESTAMP}.log"

echo "=== INICIANDO ACTUALIZACIÓN DIARIA: $(date) ===" | tee -a "$LOG_FILE"

# 2. EJECUCIÓN DEL PROCESO DE ACTUALIZACIÓN
apptainer exec \
    --bind "$HOST_DYNAMIC:/ancillary" \
    --bind "$HOST_STATIC_BASE/anc:/opt/SDR_4_1/anc" \
    --bind "$HOST_STATIC_BASE/viirs/luts:/opt/SDR_4_1/viirs/luts" \
    --bind "$HOST_STATIC_BASE/atms/luts:/opt/SDR_4_1/atms/luts" \
    --bind "$HOST_STATIC_BASE/cris/luts:/opt/SDR_4_1/cris/luts" \
    --bind "$HOST_STATIC_BASE/omps/luts:/opt/SDR_4_1/omps/luts" \
    "$SIF_CSPP" /bin/bash -c "
        export CSPP_SDR_HOME=/opt/cspp_sdr
        export CSPP_DYNAMIC_ANCIL_DIR=/ancillary
        export HDF5_USE_FILE_LOCKING=FALSE
        
        # Cargar entorno oficial
        source \$CSPP_SDR_HOME/cspp_sdr_env.sh
        
        echo '--- [1/2] Actualizando LUTs de calibración (sdr_luts.sh) ---'
        sdr_luts.sh
        
        echo '--- [2/2] Actualizando Datos Ancilares y TLE (sdr_ancillary.sh) ---'
        sdr_ancillary.sh
    " >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

# 3. VERIFICACIÓN FINAL
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ ÉXITO: Los LUTs y datos ancilares han sido actualizados." | tee -a "$LOG_FILE"
    find "$LOG_DIR" -name "update_daily_*.log" -mtime +30 -delete
else
    echo "❌ ERROR: La actualización falló. Revisa el log detallado en:" | tee -a "$LOG_FILE"
    echo "   $LOG_FILE" | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi
