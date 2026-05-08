#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Generación Nivel 2 Atmosphere EDR v1.0
# ==============================================================================

# 1. CONFIGURACIÓN DE RUTAS EN EL HOST
# ------------------------------------------------------------------------------
SIF_ATMOS="/opt/containers/cspp_atmos_edr_v1.0.sif"

# Nueva ruta simplificada
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

echo "=== PROCESANDO ATMOSPHERE EDR v1.0 ===" | tee -a "$LOG_FILE"
echo "Usando estáticos de: $HOST_STATIC" | tee -a "$LOG_FILE"

# 2. EJECUCIÓN
# ------------------------------------------------------------------------------
# Nota: Montamos HOST_STATIC directamente en la ruta interna que el 
# entorno de SAPF espera para los coeficientes.

apptainer exec \
    --bind "$HOST_SDR_IN:/input_sdr" \
    --bind "$HOST_EDR_OUT:/output_edr" \
    --bind "$HOST_STATIC:/opt/cspp_atmos_edr/static" \
    --bind "$HOST_ANC:/opt/cspp_atmos_edr/ancillary" \
    --bind "$HOST_WORK:/work" \
    "$SIF_ATMOS" /bin/bash -c "
        export CSPP_VIIRS_ATMOS_HOME=/opt/cspp_atmos_edr
        export HDF5_USE_FILE_LOCKING=FALSE
        
        # Nombre correcto según manual: cspp_atmos_env.sh
        source \$CSPP_VIIRS_ATMOS_HOME/cspp_atmos_env.sh
        
        cd /work
        echo '--- Iniciando algoritmos Atmos Enterprise ---'
        
        # Ejecutamos el wrapper que procesa todo
        viirs_atmos_all.bash -s /input_sdr -a /opt/cspp_atmos_edr/ancillary -w /work
        
        # Los archivos generados en /work se mueven a la salida de Lustre
        mv *.h5 /output_edr/
    " >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

# 3. FINALIZACIÓN
# ------------------------------------------------------------------------------
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ ÉXITO: Productos generados en $HOST_EDR_OUT" | tee -a "$LOG_FILE"
    rm -rf "$HOST_WORK"
else
    echo "❌ ERROR: Revisa el log en $LOG_FILE" | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi
