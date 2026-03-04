#!/bin/bash
# ==============================================================================
# SCRIPT MODULAR: Procesamiento CSPP EDR 
# ==============================================================================

# 1. VALIDACIÓN DE ENTRADA
if [ -z "$1" ]; then
    echo "Error: Debes indicar el archivo RDR de entrada."
    exit 1
fi

SIF_CSPP="/opt/containers/cspp_edr.sif"

BASE_OUTPUT="/data/output/jpss/level2"
OUTPUT_DIR="$BASE_OUTPUT/flood"
SENSOR="viirs"

# 4. EJECUCIÓN CON MONTAJE SELECTIVO
apptainer exec \
    --bind "$INPUT_DIR":/input \
    --bind "$OUTPUT_DIR":/output \
    "$SIF_CSPP" /bin/bash -c "
        export HDF5_USE_FILE_LOCKING=FALSE
        export CSPP_VIIRS_FLOOD_HOME=/opt/cspp_viirs_flood_detection_2.0
        # Forzamos la carga del entorno si existe, silenciando errores si no
        [ -f $CSPP_VIIRS_FLOOD_HOME/cspp_viirs_flood_env.sh ] && source $CSPP_VIIRS_FLOOD_HOME/cspp_viirs_flood_env.sh                
        
        # CRÍTICO: Entrar a la carpeta de salida porque ahí se guardarán los SDR
        cd /output
                
	cspp_viirs_flood.sh -n 20 $OUTPUT_DIR
    " > "$LOG_FILE" 2>&1

EXIT_CODE=$?

# 5. VERIFICACIÓN
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Éxito: Procesamiento finalizado. Revisa el log en $LOG_FILE"
else
    echo "❌ FALLA CRÍTICA: Revisa el log en $LOG_FILE"
    tail -n 15 "$LOG_FILE"
    exit $EXIT_CODE
fi
