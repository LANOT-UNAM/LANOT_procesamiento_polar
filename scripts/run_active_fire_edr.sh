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
# LANOT - UNAM | CSPP Active Fire v2.1 (Ajustado a Manual)
# ==============================================================================

INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
OUTPUT_DIR="/data/output/jpss/level2/fires"
SIF_IMAGE="/opt/containers/cspp_active_fire_edr.sif"

# Rutas internas según lo verificado
CONTAINER_HOME="/opt/cspp-active-fire-noaa_2.1"
ENV_SCRIPT="${CONTAINER_HOME}/cspp_active_fire_noaa_env.sh"
EXEC_SCRIPT="${CONTAINER_HOME}/bin/cspp_active_fire_noaa.sh"

JOB_ID=${SLURM_JOB_ID:-$$}
STAGING_DIR="/data/output/jpss/tmp/fire_staging_${JOB_ID}"

# Crear carpetas necesarias
mkdir -p "${OUTPUT_DIR}" "${STAGING_DIR}" logs

echo "================================================================="
echo " INFO: Iniciando CSPP Active Fire v2.1 a las $(date)"
echo " INFO: Plataforma: ${1:-j01}"

# 1. Preparar staging (enlaces simbólicos)
ln -sf ${INPUT_SDR_DIR}/* ${STAGING_DIR}/ 2>/dev/null

# 2. Definir plataforma
SAT_PLATFORM=${1:-"j01"}

# ==============================================================================
# Ejecución con Apptainer
# ==============================================================================
# --pwd /output_data : Obliga al software a ver /output_data como el "directorio actual"
# /input_data        : Se pasa como último argumento posicional (sin -i)

apptainer exec \
    --env LC_ALL=C \
    -B "${STAGING_DIR}":/input_data \
    -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}" \
    -B "${OUTPUT_DIR}":/output_data \
    -B "/data/output/jpss":"/data/output/jpss" \
    --pwd /output_data \
    "${SIF_IMAGE}" \
    /bin/bash -c "source ${ENV_SCRIPT} && ${EXEC_SCRIPT} -p ${SAT_PLATFORM} -v /input_data"

EXIT_CODE=$?

# ==============================================================================
# Limpieza
# ==============================================================================
echo "================================================================="
echo " INFO: Limpiando staging..."
rm -rf "${STAGING_DIR}"
echo " INFO: Fin del proceso. Código de salida: ${EXIT_CODE}"
echo "================================================================="
