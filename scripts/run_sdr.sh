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
SIF_CSPP="/opt/containers/cspp_sdr_v4.1.sif"

HOST_STATIC="/data/opt/SDR_4_1"       # Base de datos estáticos
HOST_DYNAMIC="/data/ancillary"        # Datos dinámicos diarios
BASE_OUTPUT="/data/output/jpss/level1" # Raíz de salida

# 3. DETECCIÓN DE SENSOR Y COMANDO
# Usamos rutas absolutas al binario para evitar problemas de PATH
case "$FILENAME" in
    RVIIRS*)
        SENSOR="viirs"
        EXEC_CMD="/opt/cspp_sdr/bin/viirs_sdr.sh"
        ;;
    RNSCA*|RATMS*) 
        SENSOR="atms"
        EXEC_CMD="/opt/cspp_sdr/bin/atms_sdr.sh"
        ;;
    RCRIS*)
        SENSOR="cris"
        EXEC_CMD="/opt/cspp_sdr/bin/cris_sdr.sh"
        ;;
    ROMPS*)
        SENSOR="omps"
        EXEC_CMD="/opt/cspp_sdr/bin/omps_sdr.sh"
        ;;
    *)
        echo "Error: Sensor no reconocido en $FILENAME"
        exit 1
        ;;
esac

# 4. CARPETA DE SALIDA (Plana, sin fechas)
OUTPUT_DIR="$BASE_OUTPUT/$SENSOR"
mkdir -p "$OUTPUT_DIR"

echo "=== PROCESANDO $SENSOR ==="
echo "Entrada: $FILENAME"
echo "Salida:  $OUTPUT_DIR"

# 5. CONSTRUCCIÓN INTELIGENTE DE BINDS
BIND_ARGS="--bind $INPUT_DIR:/input --bind $OUTPUT_DIR:/output --bind $HOST_DYNAMIC:/ancillary"

add_bind_if_exists() {
    local HOST_PATH="$1"
    local CONT_PATH="$2"
    if [ -d "$HOST_PATH" ]; then
        BIND_ARGS="$BIND_ARGS --bind $HOST_PATH:$CONT_PATH"
    fi
}

# Inyección de datos estáticos (Solo si existen en el Host)
add_bind_if_exists "$HOST_STATIC/viirs/luts"  "/opt/cspp_sdr/viirs/luts"
add_bind_if_exists "$HOST_STATIC/viirs/tiles" "/opt/cspp_sdr/viirs/tiles"
add_bind_if_exists "$HOST_STATIC/atms/luts"   "/opt/cspp_sdr/atms/luts"
add_bind_if_exists "$HOST_STATIC/cris/luts"   "/opt/cspp_sdr/cris/luts"
add_bind_if_exists "$HOST_STATIC/omps/luts"   "/opt/cspp_sdr/omps/luts"
add_bind_if_exists "$HOST_STATIC/anc"         "/opt/cspp_sdr/anc"

# 6. EJECUCIÓN (MODIFICADO)
# CAMBIO CLAVE 1: Eliminamos '-o /output'.
# CAMBIO CLAVE 2: Hacemos 'cd /output' antes de ejecutar.
# CAMBIO CLAVE 3: Agregamos 'set -e' para que cualquier error interno corte el proceso.

apptainer exec $BIND_ARGS \
    "$SIF_CSPP" \
    /bin/bash -c "
        set -e  # Abortar si algo falla
        cd /output
        
        # Ejecutamos sin el flag -o, escribirá en el directorio actual (/output)
        # Nota: quitamos -p 8 temporalmente para ATMS ya que el error sugería 
        # conflictos, pero CSPP suele aceptarlo. Si falla de nuevo, quita '-p 8'.
        $EXEC_CMD -p 8 -a /ancillary /input/$FILENAME
    "

# Capturar código de salida de Apptainer
RETVAL=$?

if [ $RETVAL -eq 0 ]; then
    echo "✅ Éxito: Archivos generados en $OUTPUT_DIR"
    # Opcional: Listar lo generado para confirmar
    ls -lh "$OUTPUT_DIR" | head -n 5
else
    echo "❌ Falla Crítica: El proceso $SENSOR terminó con código de error $RETVAL"
    exit $RETVAL
fi

