#!/bin/bash
# ==============================================================================
# SCRIPT MODULAR: Procesamiento CSPP EDR 
# ==============================================================================

# 1. VALIDACIÓN DE ENTRADA
#if [ -z "$1" ]; then
#    echo "Error: Debes indicar el archivo RDR de entrada."
#    exit 1
#fi

SIF_CSPP="/opt/containers/cspp_edr.sif"
INPUT_DIR="/data/output/jpss/level1/viirs"
BASE_OUTPUT="/data/output/jpss/level2/viirs"
STATIC_DIR="/opt/contenedores/CSPP/CLAVRx_3_0/static"
OUTPUT_DIR_FLOOD="$BASE_OUTPUT/flood"
OUTPUT_DIR_CLAVRX="$BASE_OUTPUT/clouds"
LOG_FILE="out.log"

# 4. EJECUCIÓN CON MONTAJE SELECTIVO

# Flood
apptainer exec \
    --bind "$INPUT_DIR":/input \
    --bind "$OUTPUT_DIR_FLOOD":/output \
    "$SIF_CSPP" /bin/bash -c "
        export CSPP_VIIRS_FLOOD_HOME=/opt/cspp_viirs_flood_detection_2.0
        source \$CSPP_VIIRS_FLOOD_HOME/cspp_viirs_flood_env.sh                      
        cd /output
        cspp_viirs_flood.sh -n 20 /input
    " > "$LOG_FILE" 2>&1

EXIT_CODE_FLOOD=$?

# Clarvrx
apptainer exec \
    --bind "$INPUT_DIR":/input \
    --bind "$OUTPUT_DIR_CLAVRX":/output \
    --bind "$STATIC_DIR":/opt/CLAVRx_3_0/static \ 
    "$SIF_CSPP" /bin/bash -c "
		export WORKDIR=/opt/proc
		export CSPP_CLAVRX_HOME=/opt/CLAVRx_3_0
        source \$CSPP_CLAVRX_HOME/env/set_clavrx_env.sh
        cd \$WORKDIR
        run_clavrx.sh -x 3 /input /workdir /output
    " > "$LOG_FILE" 2>&1

EXIT_CODE_FLOOD=$?



# 5. VERIFICACIÓN
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Éxito: Procesamiento finalizado. Revisa el log en $LOG_FILE"
else
    echo "❌ FALLA CRÍTICA: Revisa el log en $LOG_FILE"
    tail -n 15 "$LOG_FILE"
    exit $EXIT_CODE
fi
