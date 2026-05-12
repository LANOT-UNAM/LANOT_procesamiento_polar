#!/bin/bash
#SBATCH --job-name=cspp_acspo_edr
#SBATCH --output=logs/acspo_%j.out
#SBATCH --error=logs/acspo_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --partition=normal

# ==============================================================================
# LANOT - UNAM | Generación Nivel 2 ACSPO SST v3.0
# ==============================================================================

# Configuración de Rutas (Ajustadas a tu jerarquía de Lustre)
INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
OUTPUT_ACSPO_DIR="/data/output/jpss/level2/acspo"
HOST_ANC="/data/ancillary"

SIF_IMAGE="/opt/containers/cspp_acspo_v3.0.sif"

# Directorio temporal de staging y trabajo
JOB_ID=${SLURM_JOB_ID:-$$}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STAGING_DIR="/data/output/jpss/tmp/acspo_staging_${JOB_ID}_${TIMESTAMP}"
WORK_DIR="/data/output/jpss/tmp/acspo_work_${JOB_ID}_${TIMESTAMP}"
CORES=${SLURM_CPUS_PER_TASK:-16}

# ==============================================================================
# Preparación del entorno y Staging
# ==============================================================================
mkdir -p "${OUTPUT_ACSPO_DIR}"
mkdir -p "${STAGING_DIR}"
mkdir -p "${WORK_DIR}"
mkdir -p logs

echo "================================================================="
echo " Iniciando CSPP ACSPO v3.0 (SST)"
echo " Preparando enlaces simbólicos en directorio de staging temporal..."

# Enlazamos los SDR de la prueba actual
# NOTA: ACSPO v3 requiere los archivos M-bands (SVM*) y el de terreno GMTCO*
ln -s ${INPUT_SDR_DIR}/* ${STAGING_DIR}/

echo " Staging completado en: ${STAGING_DIR}"
echo " Cores asignados: ${CORES}"
echo "================================================================="

# ==============================================================================
# Ejecución con Apptainer
# ==============================================================================
# Opciones de ACSPO utilizadas:
# -p: Número de hilos de CPU (Por defecto 4, máximo 24)
# -w: Directorio de trabajo temporal
# -O: Directorio de salida final
# -d: Directorio caché dinámico (GRIBs y CMC)
# -m: Modo de salida (usamos 'gds' para no generar el formato legacy interno de NOAA)

apptainer exec \
    --env LC_ALL=C \
    --env CSPP_ACSPO_HOME=/opt/acspo_sst_v3 \
    -B "${STAGING_DIR}":/input_sdr \
    -B "${OUTPUT_ACSPO_DIR}":/output_data \
    -B "${WORK_DIR}":/work_data \
    -B "${HOST_ANC}":"/opt/acspo_sst_v3/viirs/input/anc/ancil_download" \
    "${SIF_IMAGE}" \
    /opt/acspo_sst_v3/run_acspo_viirs_v3.sh \
        -p ${CORES} \
        -w /work_data \
        -O /output_data \
        -d /opt/acspo_sst_v3/viirs/input/anc/ancil_download \
        -m gds \
        /input_sdr

EXIT_CODE=$?

# ==============================================================================
# Limpieza del entorno
# ==============================================================================
echo " Limpiando directorios temporales..."
rm -rf "${STAGING_DIR}"
rm -rf "${WORK_DIR}"

echo "================================================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo " Procesamiento completado exitosamente a las $(date)"
else
    echo " ERROR: El procesamiento falló con el código de salida $EXIT_CODE a las $(date)"
fi
exit $EXIT_CODE
