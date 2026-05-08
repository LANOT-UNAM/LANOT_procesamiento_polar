#!/bin/bash
# ==============================================================================
# SCRIPT MODULAR: Procesamiento CSPP SDR v4.1.1 (LUTs Externos)
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
# Ajusta "HOST_STATIC_BASE" a la ruta real de tu Lustre donde descomprimiste los datos estáticos
SIF_CSPP="/opt/containers/cspp_sdr_v4.1.1.sif"
HOST_STATIC_BASE="/data/opt/SDR_4_1"  
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
        EXEC_CMD="viirs_sdr.sh" 
        ;;
    *RNSCA*|*RATMS*)  
        SENSOR="atms"  
        EXEC_CMD="atms_sdr.sh"  
        ;;
    *RCRIS*)          
        SENSOR="cris"  
        EXEC_CMD="cris_sdr.sh"  
        ;;
    *) echo "Error: Sensor no identificado en el nombre del archivo"; exit 1 ;;
esac

OUTPUT_DIR="$BASE_OUTPUT/$SENSOR"
mkdir -p "$OUTPUT_DIR"

LOG_FILE="$LOG_DIR/${TIMESTAMP}_${SENSOR}_${FILENAME}.log"

echo "=== PROCESANDO $SENSOR ==="
echo "Entrada: $FILENAME"
echo "Salida:  $OUTPUT_DIR"

# 4. PREPARACIÓN DE MONTAJES (BINDS) DINÁMICOS
# Usamos un arreglo de Bash para añadir binds específicos dependiendo del sensor
BIND_OPTS=(
    --bind "$INPUT_DIR:/input"
    --bind "$OUTPUT_DIR:/output"
    --bind "$HOST_DYNAMIC:/ancillary"
    --bind "$HOST_STATIC_BASE/anc:/opt/SDR_4_1/anc"
    --bind "$HOST_STATIC_BASE/$SENSOR/luts:/opt/SDR_4_1/$SENSOR/luts"
)

# 5. EJECUCIÓN DEL CONTENEDOR
apptainer exec "${BIND_OPTS[@]}" "$SIF_CSPP" /bin/bash -c "
    export HDF5_USE_FILE_LOCKING=FALSE
    export CSPP_SDR_HOME=/opt/cspp_sdr
    export CSPP_DYNAMIC_ANCIL_DIR=/ancillary
    
    # Carga el entorno oficial de CSPP
    source \$CSPP_SDR_HOME/cspp_sdr_env.sh        
    
    # CRÍTICO: Entrar a la carpeta de salida
    cd /output
    
    echo '--- Iniciando CSPP SDR para $SENSOR ---'
    # Usamos la variable \$EXEC_CMD para invocar el script correcto dinámicamente
    $EXEC_CMD -p 20 -a -g /input/$FILENAME
" > "$LOG_FILE" 2>&1

EXIT_CODE=$?

# 6. VERIFICACIÓN
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Éxito: Procesamiento finalizado. Revisa el log en $LOG_FILE"
else
    echo "❌ FALLA CRÍTICA: Revisa el log en $LOG_FILE"
    tail -n 15 "$LOG_FILE"
    exit $EXIT_CODE
fi
