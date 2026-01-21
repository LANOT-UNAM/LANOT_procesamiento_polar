#!/bin/bash
# ==============================================================================
# SCRIPT MODULAR: Procesamiento CSPP SDR (Level 0 -> Level 1)
# Autor: LANOT - UNAM
# ==============================================================================

# 1. VALIDACIÓN DE ENTRADA
if [ -z "$1" ]; then
    echo "Error: Debes indicar el archivo RDR de entrada."
    exit 1
fi

INPUT_FILE=$(realpath "$1")
INPUT_DIR=$(dirname "$INPUT_FILE")
FILENAME=$(basename "$INPUT_FILE")

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: El archivo $INPUT_FILE no existe."
    exit 1
fi

# 2. CONFIGURACIÓN DE INFRAESTRUCTURA
SIF_CSPP="/opt/containers/cspp_sdr_v4.1.sif"
HOST_STATIC="/data/opt/SDR_4_1"
HOST_DYNAMIC="/data/ancillary"
BASE_OUTPUT="/data/output/jpss/level1"

# Configuración de Logs
LOG_DIR="/var/log/lanot/polares/cspp-sdr"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 3. DETECCIÓN DE SENSOR Y COMANDO (MEJORADA CON WILDCARDS)
# El orden importa: Buscamos patrones específicos primero.
case "$FILENAME" in
    *RVIIRS*|*RVIRS*)
        SENSOR="viirs"
        EXEC_CMD="/opt/cspp_sdr/bin/viirs_sdr.sh"
        # VIIRS usa flag explícito -a
        CMD_ARGS="-p 8 -a /ancillary /input/$FILENAME"
        ;;
    *RCRIS*)
        SENSOR="cris"
        EXEC_CMD="/opt/cspp_sdr/bin/cris_sdr.sh"
        CMD_ARGS="-p 8 /input/$FILENAME"
        ;;
    *ROMPS*|*RONPS*)
        SENSOR="omps"
        EXEC_CMD="/opt/cspp_sdr/bin/omps_sdr.sh"
        CMD_ARGS="-p 8 /input/$FILENAME"
        ;;
    *RATMS*|*RNSCA*) 
        # ATMS al final para evitar falsos positivos con archivos híbridos RNSCA-RVIRS
        SENSOR="atms"
        EXEC_CMD="/opt/cspp_sdr/bin/atms_sdr.sh"
        CMD_ARGS="-p 8 /input/$FILENAME"
        ;;
    *)
        echo "Error: Sensor no reconocido en $FILENAME"
        exit 1
        ;;
esac

# Definir nombre del archivo Log específico
LOG_FILE="${LOG_DIR}/${TIMESTAMP}_${SENSOR}_$(basename "$FILENAME" .h5).log"

# 4. PREPARAR SALIDA
OUTPUT_DIR="$BASE_OUTPUT/$SENSOR"
mkdir -p "$OUTPUT_DIR"

echo "=== PROCESANDO $SENSOR ==="
echo "Entrada: $FILENAME"
echo "Salida:  $OUTPUT_DIR"
echo "Log:     $LOG_FILE"

# 5. BINDS
BIND_ARGS="--bind $INPUT_DIR:/input --bind $OUTPUT_DIR:/output --bind $HOST_DYNAMIC:/ancillary"

add_bind_if_exists() {
    if [ -d "$1" ]; then BIND_ARGS="$BIND_ARGS --bind $1:$2"; fi
}

add_bind_if_exists "$HOST_STATIC/viirs/luts"  "/opt/cspp_sdr/viirs/luts"
add_bind_if_exists "$HOST_STATIC/viirs/tiles" "/opt/cspp_sdr/viirs/tiles"
add_bind_if_exists "$HOST_STATIC/atms/luts"   "/opt/cspp_sdr/atms/luts"
add_bind_if_exists "$HOST_STATIC/cris/luts"   "/opt/cspp_sdr/cris/luts"
add_bind_if_exists "$HOST_STATIC/omps/luts"   "/opt/cspp_sdr/omps/luts"
add_bind_if_exists "$HOST_STATIC/anc"         "/opt/cspp_sdr/anc"

# 6. EJECUCIÓN CON REDIRECCIÓN A LOG
# Usamos 'tee' si quieres verlo en pantalla Y guardar, 
# o solo redirección '>' para guardar en silencio (recomendado para producción).
# Aquí guardamos en silencio para mantener la terminal limpia.

apptainer exec $BIND_ARGS "$SIF_CSPP" /bin/bash -c "
    set -e
    cd /output
    
    # Variable necesaria para ATMS/CrIS (no afecta a VIIRS)
    export CSPP_DYNAMIC_ANCIL_DIR=/ancillary
    
    echo '--- Inicio de Procesamiento: $(date) ---'
    echo 'Comando: $EXEC_CMD $CMD_ARGS'
    
    $EXEC_CMD $CMD_ARGS
    
    echo '--- Fin de Procesamiento: $(date) ---'
" > "$LOG_FILE" 2>&1

EXIT_CODE=$?

# 7. ANÁLISIS DE RESULTADOS
# Buscamos errores fatales en el log generado
if grep -q "Traceback" "$LOG_FILE" || grep -q "did not complete without errors" "$LOG_FILE"; then
    echo "❌ FALLA CRÍTICA: Se detectaron errores en el log."
    echo "Revisa los detalles: tail -n 20 $LOG_FILE"
    exit 1
elif [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Éxito: Procesamiento finalizado correctamente."
    exit 0
else
    echo "❌ Falla: El contenedor terminó con código de error $EXIT_CODE"
    echo "Revisa: $LOG_FILE"
    exit $EXIT_CODE
fi
