#!/bin/bash
# ==============================================================================
# SCRIPT: Actualización Diaria de LUTs y Ancillary (CSPP SDR v4.1.1)
# ==============================================================================

# 1. CONFIGURACIÓN DE RUTAS
SIF_CSPP="/opt/containers/cspp_sdr_v4.1.1.sif"
HOST_STATIC_BASE="/data/opt/SDR_4_1"
HOST_DYNAMIC="/data/ancillary"

# El caché de ATMOS cuelga del mismo árbol (/data/ancillary/atmos) pero lo
# actualiza update_atmos_ancillary.sh: se excluye de las cuentas para no
# atribuirle a SDR sus ~16 GB.
ANC_ATMOS="$HOST_DYNAMIC/atmos"

# Directorio de logs
LOG_DIR="/var/log/lanot/polares/cspp-sdr"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')
LOG_FILE="$LOG_DIR/update_daily_${TIMESTAMP}.log"

formato_duracion() {
    local s="$1"
    if [ "$s" -ge 3600 ]; then
        printf '%dh %dm %ds' $((s / 3600)) $(((s % 3600) / 60)) $((s % 60))
    elif [ "$s" -ge 60 ]; then
        printf '%dm %ds' $((s / 60)) $((s % 60))
    else
        printf '%ds' "$s"
    fi
}

# Se cuenta por ctime y no por mtime: las descargas conservan la fecha del
# servidor remoto, así que un archivo recién traído puede tener mtime viejo.
contar_nuevos() {
    find "$1" -path "$ANC_ATMOS" -prune -o \
        -type f -newerct "@$START_EPOCH" -print 2>/dev/null | wc -l
}

contar_total() {
    find "$1" -path "$ANC_ATMOS" -prune -o -type f -print 2>/dev/null | wc -l
}

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
DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

# 3. VERIFICACIÓN FINAL
if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: La actualización falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log detallado en: $LOG_FILE" | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

LUTS_NUEVOS=$(contar_nuevos "$HOST_STATIC_BASE")
LUTS_TOTAL=$(contar_total "$HOST_STATIC_BASE")
LUTS_ESPACIO=$(du -sh "$HOST_STATIC_BASE" 2>/dev/null | cut -f1)

ANC_NUEVOS=$(contar_nuevos "$HOST_DYNAMIC")
ANC_TOTAL=$(contar_total "$HOST_DYNAMIC")
ANC_ESPACIO=$(du -sh --exclude=atmos "$HOST_DYNAMIC" 2>/dev/null | cut -f1)

echo "✅ ÉXITO: LUTs y datos ancilares actualizados en $DURACION" | tee -a "$LOG_FILE"
echo "   LUTs:      $LUTS_NUEVOS nuevos de $LUTS_TOTAL archivos, $LUTS_ESPACIO en $HOST_STATIC_BASE" | tee -a "$LOG_FILE"
echo "   Ancillary: $ANC_NUEVOS nuevos de $ANC_TOTAL archivos, $ANC_ESPACIO en $HOST_DYNAMIC" | tee -a "$LOG_FILE"

find "$LOG_DIR" -name "update_daily_*.log" -mtime +30 -delete
