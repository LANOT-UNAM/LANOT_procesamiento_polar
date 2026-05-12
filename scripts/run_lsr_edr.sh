#!/bin/bash
#SBATCH --job-name=cspp_lsr_edr
#SBATCH --output=logs/lsr_%j.out
#SBATCH --error=logs/lsr_%j.err
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
OUTPUT_LSR_DIR="/data/output/jpss/level2/lsr"

SIF_IMAGE="/opt/containers/cspp_lsr_edr_v2.0.sif"

# Directorio temporal de staging
JOB_ID=${SLURM_JOB_ID:-$$}
STAGING_DIR="/data/output/jpss/tmp/lsr_staging_${JOB_ID}"
CORES=${SLURM_CPUS_PER_TASK:-8}

# ==============================================================================
# Preparación del entorno y Staging
# ==============================================================================
mkdir -p "${OUTPUT_LSR_DIR}"
mkdir -p "${STAGING_DIR}"
mkdir -p logs

echo "================================================================="
echo " Iniciando CSPP LSR v2.0 - Prueba de una sola pasada"
echo " Preparando enlaces simbólicos en directorio de staging temporal..."

# Enlazamos los SDR y ATMOS EDR de la prueba actual
ln -s ${INPUT_SDR_DIR}/* ${STAGING_DIR}/
ln -s ${INPUT_ATMOS_DIR}/* ${STAGING_DIR}/

echo " Staging completado en: ${STAGING_DIR}"
echo " Cores asignados: ${CORES}"
echo "================================================================="

# ==============================================================================
# Ejecución con Apptainer
# ==============================================================================
# Invocamos la ruta absoluta del script encontrada dentro del contenedor
apptainer exec \
    --env LC_ALL=C \
    --env CSPP_VIIRS_LSR_V2_HOME=/opt/cspp-surf_refl \
    -B "${STAGING_DIR}":/input_data \
    -B "${OUTPUT_LSR_DIR}":/output_data \
    -B "/data/output/jpss":"/data/output/jpss" \
    "${SIF_IMAGE}" \
    /opt/cspp-surf_refl/run_cspp_lsr_v2.sh -o /output_data -p ${CORES} /input_data

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

exit $EXIT_CODE
