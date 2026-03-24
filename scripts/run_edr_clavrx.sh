#!/bin/bash
# ==============================================================================
# SCRIPT MODULAR: Procesamiento CSPP EDR - Exclusivo CLAVRx
# ==============================================================================

# 1. VALIDACIÓN DE ENTRADA (Estructura diaria YYYY MM DD)
#if [ "$#" -ne 3 ]; then
#    echo "Error: Faltan argumentos."
#    echo "Uso: $0 <YYYY> <MM> <DD>"
#    echo "Ejemplo: $0 2026 03 24"
#    exit 1
#fi

#YEAR=$1
#MONTH=$2
#DAY=$3
timestamp=$(date +"%Y%m%d_%H%M")

# 2. VARIABLES GLOBALES
# Rutas base en tu sistema Lustre
INPUT_DIR="/data/output/jpss/level1/viirs"

# Contenedor y recursos estáticos
SIF_CSPP="/opt/containers/cspp_edr_clavrx.sif" 
STATIC_DIR="/opt/contenedores/CSPP/CLAVRx_3_0/static"

# Directorios de salida
BASE_OUTPUT="/data/output/jpss/level2/viirs"
OUTPUT_DIR_CLAVRX="$BASE_OUTPUT/clouds"
LOG_FILE="clavrx_out_${timestamp}.log"

# NUEVO: Directorio temporal de trabajo en el host (con permisos de escritura)
HOST_TMP_DIR="/data/tmp/clavrx_work_${timestamp}"

# Crear directorio de salida dinámico si no existe
mkdir -p "$OUTPUT_DIR_CLAVRX"
mkdir -p "$HOST_TMP_DIR"

# 3. EJECUCIÓN CON MONTAJE SELECTIVO
echo "Iniciando procesamiento CLAVRx para la fecha: $timestamp" > "$LOG_FILE"

# Ejecución de CLAVRx
echo "--- Ejecutando CLAVRx ---" | tee -a "$LOG_FILE"
apptainer exec \
    --bind "$INPUT_DIR":/input \
    --bind "$OUTPUT_DIR_CLAVRX":/output \
    --bind "$STATIC_DIR":/opt/CLAVRx_3_0/static \
    --bind "$HOST_TMP_DIR":/opt/proc \
    "$SIF_CSPP" /bin/bash -c "
        export WORKDIR=/opt/proc
        export CSPP_CLAVRX_HOME=/opt/CLAVRx_3_0
        source \$CSPP_CLAVRX_HOME/env/set_clavrx_env.sh
        cd \$WORKDIR
        # La bandera -x indica que no se debe des-agregar (aplica solo para VIIRS)
        run_clavrx.sh -x 3 /input \$WORKDIR /output
    " >> "$LOG_FILE" 2>&1

EXIT_CODE_CLAVRX=$?

# 4. VERIFICACIÓN
if [ $EXIT_CODE_CLAVRX -eq 0 ]; then
    echo "✅ Éxito: Procesamiento CLAVRx finalizado. Revisa el log en $LOG_FILE"
else
    echo "❌ FALLA CRÍTICA en CLAVRx: Revisa el log en $LOG_FILE"
    echo "Código de salida CLAVRx: $EXIT_CODE_CLAVRX"
    tail -n 15 "$LOG_FILE"
    exit 1
fi