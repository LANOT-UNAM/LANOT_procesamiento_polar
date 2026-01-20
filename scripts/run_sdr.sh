#!/bin/bash
# ==============================================================================
# SCRIPT MODULAR: Procesamiento CSPP SDR (Level 0 -> Level 1)
# Uso: ./run_sdr.sh /ruta/completa/al/archivo_RDR.h5
# ==============================================================================

# 1. VALIDACIÓN DE ENTRADA
if [ -z "$1" ]; then
    echo "Error: Debes indicar el archivo RDR de entrada."
    echo "Uso: $0 <path_to_RDR_file>"
    exit 1
fi

INPUT_FILE=$(realpath "$1")
INPUT_DIR=$(dirname "$INPUT_FILE")
FILENAME=$(basename "$INPUT_FILE")

# Validar que existe
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: El archivo $INPUT_FILE no existe."
    exit 1
fi

# 2. CONFIGURACIÓN DE INFRAESTRUCTURA (RUTAS FIJAS)
SIF_CSPP="/opt/lanot/contenedores/cspp_sdr_v4.1.sif"
HOST_STATIC="/data/opt/SDR_4_1"       # Donde están tus LUTs y Tiles estáticos
HOST_DYNAMIC="/data/ancillary"        # Donde están los TLEs y GFS diarios
BASE_OUTPUT="/data/output/jpss/level1"     # Raíz de la salida Level 1

# 3. LÓGICA DE DETECCIÓN DE SENSOR Y RUTA DE SALIDA
# RT-STPS nombra los archivos iniciando con un código de sensor.
# RVIIRS = VIIRS, RNSCA = ATMS, RCRIS = CrIS, ROMPS = OMPS.

case "$FILENAME" in
    RVIIRS*)
        SENSOR="viirs"
        EXEC_CMD="viirs_sdr.sh"
        ;;
    RNSCA*) # ATMS suele usar RNSCA o RATMS dependiendo de la versión RT-STPS
        SENSOR="atms"
        EXEC_CMD="atms_sdr.sh"
        ;;
    RCRIS*)
        SENSOR="cris"
        EXEC_CMD="cris_sdr.sh"
        ;;
    ROMPS*)
        SENSOR="omps"
        EXEC_CMD="omps_sdr.sh"
        ;;
    *)
        echo "Error: No se reconoce el sensor en el nombre del archivo: $FILENAME"
        exit 1
        ;;
esac

# 4. DEFINICIÓN DE CARPETA DE SALIDA ESPECÍFICA
# Estructura: /data/output/level1/<sensor>/<año>/<mes>/<dia>
# Extraemos la fecha del nombre del archivo o del sistema (aquí uso fecha actual por simplicidad operativa)
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)

OUTPUT_DIR="$BASE_OUTPUT/$SENSOR/$YEAR/$MONTH/$DAY"
mkdir -p "$OUTPUT_DIR"

echo "=== PROCESANDO $SENSOR ==="
echo "Entrada: $FILENAME"
echo "Salida:  $OUTPUT_DIR"

# 5. EJECUCIÓN DEL CONTENEDOR
# Nota: Usamos los binds estáticos que definimos anteriormente.

apptainer exec \
    --bind "$INPUT_DIR":/input \
    --bind "$OUTPUT_DIR":/output \
    --bind "$HOST_DYNAMIC":/ancillary \
    \
    --bind "$HOST_STATIC/viirs/luts":/opt/cspp_sdr/viirs/luts \
    --bind "$HOST_STATIC/viirs/tiles":/opt/cspp_sdr/viirs/tiles \
    --bind "$HOST_STATIC/atms/luts":/opt/cspp_sdr/atms/luts \
    --bind "$HOST_STATIC/cris/luts":/opt/cspp_sdr/cris/luts \
    --bind "$HOST_STATIC/omps/luts":/opt/cspp_sdr/omps/luts \
    --bind "$HOST_STATIC/anc":/opt/cspp_sdr/anc \
    \
    "$SIF_CSPP" \
    /bin/bash -c "
        # -p define hilos (cores). Ajustar según servidor.
        $EXEC_CMD -p 8 -a /ancillary -o /output /input/$FILENAME
    "

RETVAL=$?
if [ $RETVAL -eq 0 ]; then
    echo "Éxito: Archivos generados en $OUTPUT_DIR"
else
    echo "Falla: El proceso $SENSOR terminó con error ($RETVAL)"
    exit $RETVAL
fi

