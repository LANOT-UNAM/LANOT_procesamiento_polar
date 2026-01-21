#!/bin/bash
# ==============================================================================
# SCRIPT MODULAR: Procesamiento CSPP SDR (Level 0 -> Level 1)
# Uso: ./run_sdr.sh /ruta/completa/al/archivo_RDR.h5
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
SIF_CSPP="/opt/lanot/contenedores/cspp_sdr_v4.1.sif"
HOST_STATIC="/data/opt/SDR_4_1"       # Base de datos estáticos
HOST_DYNAMIC="/data/ancillary"        # Datos dinámicos diarios
BASE_OUTPUT="/data/output/jpss/level1" # Ajustado a tu estructura JPSS

# 3. DETECCIÓN DE SENSOR
case "$FILENAME" in
    RVIIRS*) SENSOR="viirs"; EXEC_CMD="viirs_sdr.sh" ;;
    RNSCA*)  SENSOR="atms";  EXEC_CMD="atms_sdr.sh"  ;; # ATMS
    RATMS*)  SENSOR="atms";  EXEC_CMD="atms_sdr.sh"  ;; # Variante nombre
    RCRIS*)  SENSOR="cris";  EXEC_CMD="cris_sdr.sh"  ;;
    ROMPS*)  SENSOR="omps";  EXEC_CMD="omps_sdr.sh"  ;;
    *) echo "Error: Sensor no reconocido en $FILENAME"; exit 1 ;;
esac

# 4. CARPETA DE SALIDA
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
OUTPUT_DIR="$BASE_OUTPUT/$SENSOR/$YEAR/$MONTH/$DAY"
mkdir -p "$OUTPUT_DIR"

echo "=== PROCESANDO $SENSOR ==="
echo "Entrada: $FILENAME"
echo "Salida:  $OUTPUT_DIR"

# 5. CONSTRUCCIÓN INTELIGENTE DE BINDS
# Empezamos con los binds obligatorios (Input, Output, Ancillary)
BIND_ARGS="--bind $INPUT_DIR:/input --bind $OUTPUT_DIR:/output --bind $HOST_DYNAMIC:/ancillary"

# Función para agregar bind si la carpeta existe en el host
add_bind_if_exists() {
    local HOST_PATH="$1"
    local CONT_PATH="$2"
    if [ -d "$HOST_PATH" ]; then
        BIND_ARGS="$BIND_ARGS --bind $HOST_PATH:$CONT_PATH"
    fi
}

# Verificamos e inyectamos solo lo que existe en tu servidor
# VIIRS (Estos sí deberían existir si instalaste LUTS y Tiles)
add_bind_if_exists "$HOST_STATIC/viirs/luts"  "/opt/cspp_sdr/viirs/luts"
add_bind_if_exists "$HOST_STATIC/viirs/tiles" "/opt/cspp_sdr/viirs/tiles"

# ATMS / CrIS / OMPS (Solo se montan si existen, si no, usan lo interno del contenedor)
add_bind_if_exists "$HOST_STATIC/atms/luts"   "/opt/cspp_sdr/atms/luts"
add_bind_if_exists "$HOST_STATIC/cris/luts"   "/opt/cspp_sdr/cris/luts"
add_bind_if_exists "$HOST_STATIC/omps/luts"   "/opt/cspp_sdr/omps/luts"

# Ancillary Estático (Stray Light / Cache)
add_bind_if_exists "$HOST_STATIC/anc"         "/opt/cspp_sdr/anc"

# 6. EJECUCIÓN
# Nota: $BIND_ARGS se expande aquí con todas las rutas válidas
apptainer exec $BIND_ARGS \
    "$SIF_CSPP" \
    /bin/bash -c "
        $EXEC_CMD -p 8 -a /ancillary -o /output /input/$FILENAME
    "

RETVAL=$?
if [ $RETVAL -eq 0 ]; then
    echo "Éxito: Procesamiento finalizado."
else
    echo "Falla: El proceso $SENSOR terminó con error ($RETVAL)"
    exit $RETVAL
fi

