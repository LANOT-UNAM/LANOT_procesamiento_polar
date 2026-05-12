#!/bin/bash
#SBATCH --job-name=cspp_cryo_edr
#SBATCH --output=logs/cryo_%j.out
#SBATCH --error=logs/cryo_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --partition=normal

# ==============================================================================
# Configuración de Rutas 
# ==============================================================================
INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
INPUT_ATMOS_DIR="/data/output/jpss/level2/atmosphere"
OUTPUT_CRYO_DIR="/data/output/jpss/level2/cryosphere"

SIF_IMAGE="/opt/containers/cspp_cryo_edr_v1.0.sif"

# Directorio temporal de staging (donde se juntan SDR y ATMOS)
JOB_ID=${SLURM_JOB_ID:-$$}
STAGING_DIR="/data/output/jpss/tmp/cryo_staging_${JOB_ID}"
CORES=${SLURM_CPUS_PER_TASK:-8}

# ==============================================================================
# Preparación del entorno y Staging
# ==============================================================================
mkdir -p "${OUTPUT_CRYO_DIR}"
mkdir -p "${STAGING_DIR}"
mkdir -p logs

echo "================================================================="
echo " Iniciando CSPP VIIRS Cryosphere EDR v1.0"
echo " Preparando enlaces simbólicos en directorio de staging temporal..."

# Enlazamos los SDR (SVM* y GMTCO*)
ln -s ${INPUT_SDR_DIR}/SVM* ${STAGING_DIR}/ 2>/dev/null
ln -s ${INPUT_SDR_DIR}/GMTCO* ${STAGING_DIR}/ 2>/dev/null

# Enlazamos los ATMOS EDR (Cloud Mask y Cloud Height)
ln -s ${INPUT_ATMOS_DIR}/JRR-CloudMask* ${STAGING_DIR}/ 2>/dev/null
ln -s ${INPUT_ATMOS_DIR}/JRR-CloudHeight* ${STAGING_DIR}/ 2>/dev/null

echo " Staging completado en: ${STAGING_DIR}"
echo " Cores asignados: ${CORES}"
echo "================================================================="

# ==============================================================================
# Ejecución con Apptainer
# ==============================================================================
# Nota: viirs_cryo.sh escribe los resultados en el directorio actual (pwd).
# Por eso usamos --pwd /output_data para que caigan directamente en el destino.

apptainer exec \
    --env LC_ALL=C \
    --env CSPP_VIIRS_CRYO_HOME=/opt/cspp_cryo \
    -B "${STAGING_DIR}":/input_data \
    -B "${OUTPUT_CRYO_DIR}":/output_data \
    -B "/data/output/jpss":"/data/output/jpss" \
    --pwd /output_data \
    "${SIF_IMAGE}" \
    /opt/cspp_cryo/bin/viirs_cryo.sh -p ${CORES} /input_data

EXIT_CODE=$?

# ==============================================================================
# Limpieza del entorno
# ==============================================================================
echo " Limpiando directorio de staging temporal..."
rm -rf "${STAGING_DIR}"

echo "================================================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo " Procesamiento completado exitosamente a las $(date)"
else
    echo " ERROR: El procesamiento falló con el código de salida $EXIT_CODE"
fi
echo "================================================================="
