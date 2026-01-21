#!/bin/bash
# ==============================================================================
# SCRIPT MODULAR: Procesamiento CSPP SDR (Instalación Completa vía Bind)
# ==============================================================================

# 1. VALIDACIÓN DE ENTRADA
if [ -z "$1" ]; then
    echo "Error: Debes indicar el archivo RDR de entrada."
    exit 1
fi

INPUT_FILE=$(realpath "$1")
INPUT_DIR=$(dirname "$INPUT_FILE")
FILENAME=$(basename "$INPUT_FILE")

# 2. CONFIGURACIÓN DE RUTAS
SIF_CSPP="/opt/containers/cspp_sdr_v4.1.sif"
HOST_STATIC="/data/opt/SDR_4_1"       # Tu carpeta con LUTs, DB y Scripts
HOST_DYNAMIC="/data/ancillary"        # Datos TLE/GFS diarios
BASE_OUTPUT="/data/output/jpss/level1"

# Logs
LOG_DIR="/var/log/lanot/polares/cspp-sdr"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 3. DETECCIÓN DE SENSOR
case "$FILENAME" in
    *RVIIRS*|*RVIRS*) SENSOR="viirs" ; EXEC_CMD="/opt/cspp_sdr/bin/viirs_sdr.sh" ;;
    *RNSCA*|*RATMS*)  SENSOR="atms"  ; EXEC_CMD="/opt/cspp_sdr/bin/atms_sdr.sh"  ;;
    *RCRIS*)          SENSOR="cris"  ; EXEC_CMD="/opt/cspp_sdr/bin/cris_sdr.sh"  ;;
    *) echo "Error: Sensor no identificado"; exit 1 ;;
esac

OUTPUT_DIR="$BASE_OUTPUT/$SENSOR"
mkdir -p "$OUTPUT_DIR"

LOG_FILE="$LOG_DIR/${TIMESTAMP}_${SENSOR}_${FILENAME}.log"

echo "=== PROCESANDO $SENSOR ==="
echo "Entrada: $FILENAME"
echo "Salida:  $OUTPUT_DIR"

# 4. EJECUCIÓN CON MONTAJE INTEGRAL
# Montamos toda la carpeta de datos estáticos sobre /opt/cspp_sdr 
# para que el software encuentre su DB y archivos 'shipped_luts'.
apptainer exec \
    --bind "$INPUT_DIR":/input \
    --bind "$OUTPUT_DIR":/output \
    --bind "$HOST_DYNAMIC":/ancillary \
    --bind "$HOST_STATIC":/opt/cspp_sdr \
    "$SIF_CSPP" /bin/bash -c "
        export CSPP_SDR_HOME=/opt/cspp_sdr
        export CSPP_DYNAMIC_ANCIL_DIR=/ancillary
        # Ejecutamos usando la ruta interna montada
        $EXEC_CMD -p 8 -a /ancillary -o /output /input/$FILENAME
    " > "$LOG_FILE" 2>&1

EXIT_CODE=$?

# 5. VERIFICACIÓN
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Éxito: Procesamiento finalizado."
else
    echo "❌ FALLA CRÍTICA: Revisa el log en $LOG_FILE"
    tail -n 15 "$LOG_FILE"
    exit $EXIT_CODE
fi

