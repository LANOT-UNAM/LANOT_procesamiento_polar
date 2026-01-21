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
HOST_STATIC="/data/opt/SDR_4_1/anc" 
HOST_DYNAMIC="/data/ancillary"        # Datos TLE/GFS diarios
BASE_OUTPUT="/data/output/jpss/level1"

# Logs
LOG_DIR="/var/log/lanot/polares/cspp-sdr"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 3. DETECCIÓN DE SENSOR Y COMANDO
case "$FILENAME" in
    *RVIIRS*|*RVIRS*) 
        SENSOR="viirs" 
        # Ajustamos a la ruta real que vimos en tu lista de archivos
        EXEC_CMD="/opt/cspp_sdr/viirs_sdr.sh" 
        ;;
    *RNSCA*|*RATMS*)  
        SENSOR="atms"  
        EXEC_CMD="/opt/cspp_sdr/atms_sdr.sh"  
        ;;
    *RCRIS*)          
        SENSOR="cris"  
        EXEC_CMD="/opt/cspp_sdr/cris_sdr.sh"  
        ;;
    *) echo "Error: Sensor no identificado"; exit 1 ;;
esac

OUTPUT_DIR="$BASE_OUTPUT/$SENSOR"
mkdir -p "$OUTPUT_DIR"

LOG_FILE="$LOG_DIR/${TIMESTAMP}_${SENSOR}_${FILENAME}.log"

echo "=== PROCESANDO $SENSOR ==="
echo "Entrada: $FILENAME"
echo "Salida:  $OUTPUT_DIR"

# 4. EJECUCIÓN CON MONTAJE SELECTIVO
apptainer exec \
    --bind "$INPUT_DIR":/input \
    --bind "$OUTPUT_DIR":/output \
    --bind "$HOST_DYNAMIC":/ancillary \
    --bind "$HOST_STATIC":/opt/cspp_sdr/anc \
    "$SIF_CSPP" /bin/bash -c "
        export CSPP_SDR_HOME=/opt/cspp_sdr
        export PATH=\$CSPP_SDR_HOME/bin:\$PATH
        export CSPP_DYNAMIC_ANCIL_DIR=/ancillary
        
        # CRÍTICO: Entrar a la carpeta de salida porque ahí se guardarán los SDR
        cd /output
        
        echo '--- Iniciando CSPP SDR ---'
        # Eliminamos el '-o /output' ya que el resultado cae en el dir actual
        viirs_sdr.sh -p 8 -a /ancillary /input/$FILENAME
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

