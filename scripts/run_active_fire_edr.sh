#!/bin/bash
#SBATCH --job-name=cspp_active_fire
#SBATCH --output=logs/fire_%j.out
#SBATCH --error=logs/fire_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --partition=normal

# ==============================================================================
# LANOT - UNAM | CSPP Active Fire v2.1 (Versión Final de Producción)
# ==============================================================================

# --- Configuración de Rutas ---
INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
OUTPUT_DIR="/data/output/jpss/level2/fires"
SIF_IMAGE="/opt/containers/cspp_active_fire_edr_v2.1.sif"

# Rutas internas del contenedor
CONTAINER_HOME="/opt/cspp-active-fire-noaa_2.1"
ENV_SCRIPT="${CONTAINER_HOME}/cspp_active_fire_noaa_env.sh"
EXEC_SCRIPT="${CONTAINER_HOME}/bin/cspp_active_fire_noaa.sh"

# Staging temporal
JOB_ID=${SLURM_JOB_ID:-$$}
STAGING_DIR="/data/output/jpss/tmp/fire_staging_${JOB_ID}"

# Preparación
mkdir -p "${OUTPUT_DIR}" "${STAGING_DIR}" logs

echo "================================================================="
echo " INFO: Iniciando CSPP Active Fire v2.1 a las $(date)"
echo " INFO: Staging en: ${STAGING_DIR}"

# 1. Crear enlaces simbólicos (usamos -f para refrescar)
ln -sf ${INPUT_SDR_DIR}/* ${STAGING_DIR}/ 2>/dev/null

# ==============================================================================
# 2. Ejecución con Apptainer
# ==============================================================================
# --pwd /output_data : Direcciona la salida al volumen montado
# /input_data        : Argumento posicional (carpeta de entrada)

apptainer exec \
    --env LC_ALL=C \
    -B "${STAGING_DIR}":/input_data \
    -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}" \
    -B "${OUTPUT_DIR}":/output_data \
    -B "/data/output/jpss":"/data/output/jpss" \
    --pwd /output_data \
    "${SIF_IMAGE}" \
    /bin/bash -c "source ${ENV_SCRIPT} && ${EXEC_SCRIPT} -v /input_data"

EXIT_CODE=$?

# ==============================================================================
# 3. Limpieza
# ==============================================================================
# Opcional: Podrías mover los logs generados dentro de /output_data a /logs
# mv ${OUTPUT_DIR}/*.log logs/ 2>/dev/null

echo "================================================================="
echo " INFO: Limpiando staging..."
rm -rf "${STAGING_DIR}"
echo " INFO: Fin del proceso. Código de salida: ${EXIT_CODE}"
echo "================================================================="
