#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Generación Nivel 2 Atmosphere EDR v1.0
# ==============================================================================

SIF_ATMOS="/opt/containers/cspp_atmos_edr_v1.0.sif"

# Rutas en Lustre
HOST_STATIC="/data/opt/CSPP_ATMOS_1_0/anc/static"
HOST_ANC="/data/ancillary" 
HOST_SDR_IN="/data/output/jpss/level1/viirs"
HOST_EDR_OUT="/data/output/jpss/level2/atmosphere"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOST_WORK="/data/tmp/atmos_work_$TIMESTAMP"
mkdir -p "$HOST_WORK" "$HOST_EDR_OUT"

LOG_DIR="/var/log/lanot/polares/cspp-edr"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/atmos_edr_$TIMESTAMP.log"

echo "=== INICIANDO PROCESAMIENTO ATMOSPHERE EDR v1.0 ===" | tee -a "$LOG_FILE"

apptainer exec \
    --bind "$HOST_SDR_IN:/input_sdr" \
    --bind "$HOST_EDR_OUT:/output_edr" \
    --bind "$HOST_STATIC:/opt/CSPP_ATMOS_1_0/anc/static" \
    --bind "$HOST_ANC:/opt/CSPP_ATMOS_1_0/anc/cache" \
    --bind "$HOST_WORK:/work" \
    "$SIF_ATMOS" /bin/bash -c "
        export CSPP_VIIRS_ATMOS_HOME=/opt/CSPP_ATMOS_1_0
        export CSPP_DYNAMIC_ANCIL_DIR=\$CSPP_VIIRS_ATMOS_HOME/anc/cache
        export PATH=\$CSPP_VIIRS_ATMOS_HOME/bin:\$PATH
        export HDF5_USE_FILE_LOCKING=FALSE
        
        # Verificación del montaje de Config
        if [ ! -d \"/opt/CSPP_ATMOS_1_0/anc/static/Config\" ]; then
            echo '❌ FATAL: El contenedor no ve la carpeta Config.'
            exit 1
        fi
        
        echo '--- Ejecutando algoritmos Enterprise ---'
        # Procesamiento en la carpeta de trabajo
        viirs_atmos.sh -v -l -W /work -p 20 /input_sdr
        
        echo '--- Trasladando resultados (NetCDF) a Lustre ---'
        # Movemos todos los productos generados al directorio final
        mv /work/*.nc /output_edr/ 2>/dev/null
    " >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ ÉXITO: Productos generados en $HOST_EDR_OUT" | tee -a "$LOG_FILE"
    # Ahora sí podemos activar la limpieza segura del temporal
    rm -rf "$HOST_WORK"
else
    echo "❌ ERROR: Revisa el log en $LOG_FILE" | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi
