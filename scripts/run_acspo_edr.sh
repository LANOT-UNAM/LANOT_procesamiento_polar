#!/bin/bash
#SBATCH --job-name=acspo_p2g
#SBATCH --output=logs/acspo_p2g_%j.out
#SBATCH --error=logs/acspo_p2g_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=01:30:00
#SBATCH --partition=normal

# ==============================================================================
# LANOT - UNAM | ACSPO SST v3.0 + Renderizado Polar2Grid
# ==============================================================================

# Rutas de Software e Imágenes SIF
SIF_ACSPO="/opt/containers/cspp_acspo_edr_v3.0.sif"
SIF_P2G="/opt/containers/polar2grid_v3.2.sif"

# Rutas de Datos
INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
OUTPUT_ACSPO_DIR="/data/output/jpss/level2/acspo"
OUTPUT_IMG_DIR="/data/output/jpss/vistas/acspo"
HOST_ANC="/data/ancillary"

# Directorios Temporales
JOB_ID=${SLURM_JOB_ID:-$$}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STAGING_DIR="/data/output/jpss/tmp/acspo_staging_${JOB_ID}"
WORK_DIR="/data/output/jpss/tmp/acspo_work_${JOB_ID}"
CORES=${SLURM_CPUS_PER_TASK:-16}

mkdir -p "${OUTPUT_ACSPO_DIR}" "${OUTPUT_IMG_DIR}" "${STAGING_DIR}" "${WORK_DIR}" "${WORK_DIR}/dynamic" logs

# --- 1. PREPARACIÓN (STAGING) ---
ln -s ${INPUT_SDR_DIR}/* ${STAGING_DIR}/

# --- 2. EJECUCIÓN ACSPO (Generación de NetCDF) ---
echo ">>> Iniciando ACSPO v3.0..."
apptainer exec \
    --env LC_ALL=C --env CSPP_ACSPO_HOME=/opt/acspo_sst_v3 \
    -B "${STAGING_DIR}":/input_sdr \
    -B "${OUTPUT_ACSPO_DIR}":/output_data \
    -B "${WORK_DIR}":/work_data \
    -B "${HOST_ANC}":"/opt/acspo_sst_v3/viirs/input/anc/ancil_download" \
    -B "/data/ancillary/acspo_wisdom":"/opt/acspo_sst_v3/viirs/input/sst_wisdom" \
    -B "/data/ancillary/acspo_histogram":"/opt/acspo_sst_v3/viirs/input/sst_histogram" \
    -B "${WORK_DIR}/dynamic":"/opt/acspo_sst_v3/viirs/input/anc/dynamic" \
    -B "/data/output/jpss":"/data/output/jpss" \
    "${SIF_ACSPO}" \
    /opt/acspo_sst_v3/run_acspo_viirs_v3.sh -p ${CORES} -w /work_data -o /output_data -d /opt/acspo_sst_v3/viirs/input/anc/ancil_download -m gds /input_sdr

if [ $? -ne 0 ]; then echo "ERROR en ACSPO"; exit 1; fi

# --- 3. RENDERIZADO CON POLAR2GRID ---
echo ">>> Iniciando Renderizado con Polar2Grid..."

# Identificamos el archivo NetCDF generado por ACSPO
LATEST_NC=$(ls -t "${OUTPUT_ACSPO_DIR}"/*.nc | head -1)

if [ -z "$LATEST_NC" ]; then
    echo "ERROR: No se encontró el archivo NetCDF en ${OUTPUT_ACSPO_DIR}"
    exit 1
fi

apptainer exec \
    -B "${OUTPUT_ACSPO_DIR}":/input_nc \
    -B "${OUTPUT_IMG_DIR}":/output_img \
    -B "${WORK_DIR}":/work_p2g \
    "${SIF_P2G}" \
    bash -c "
        cd /output_img
        # Usando el lector 'acspo' y el producto 'sst' según los ejemplos
        polar2grid.sh -v -r acspo \
            -w geotiff \
            -p sst \
            --grid-coverage=0.0 \
            -f /input_nc/$(basename ${LATEST_NC})
    "

# --- 4. LIMPIEZA ---
rm -rf "${STAGING_DIR}" "${WORK_DIR}"
echo "================================================================="
echo " Procesamiento y Renderizado completado: $(date)"
