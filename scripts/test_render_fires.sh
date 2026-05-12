#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Renderizado de Confidence Category (Active Fire)
# ==============================================================================

# --- Configuración de Rutas ---
SIF_P2G="/opt/containers/polar2grid_v3.2.sif"
INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
INPUT_EDR_DIR="/data/output/jpss/level2/fires"
OUTPUT_IMG_DIR="/data/output/jpss/vistas/active_fire_test"

JOB_ID=${SLURM_JOB_ID:-$$}
STAGING_DIR="/data/output/jpss/tmp/p2g_fire_staging_${JOB_ID}"

mkdir -p "${OUTPUT_IMG_DIR}" "${STAGING_DIR}"

echo "================================================================="
echo " INFO: Preparando archivos para confidence_cat..."

# 1. Crear enlaces simbólicos
ln -sf ${INPUT_SDR_DIR}/GMTCO_j01* ${STAGING_DIR}/
ln -sf ${INPUT_SDR_DIR}/GITCO_j01* ${STAGING_DIR}/
ln -sf ${INPUT_EDR_DIR}/AFIMG_j01* ${STAGING_DIR}/

# 2. CRÍTICO: Renombrar para que el lector reconozca los archivos
# Quitamos el sufijo '_cspp_dev' de los enlaces simbólicos en staging
echo " INFO: Renombrando archivos en staging..."
for f in ${STAGING_DIR}/AFIMG_j01*.nc; do 
    mv "$f" "${f//_cspp_dev/}" 2>/dev/null
done

# ==============================================================================
# 3. Ejecución de Polar2Grid
# ==============================================================================
# Usamos el producto 'confidence_cat' como indica el manual.
# Nota: Si 'viirs_edr_active_fires' falla, se puede probar 'viirs_active_fire'

apptainer exec \
    --env LC_ALL=C \
    -B "${STAGING_DIR}":/input_data \
    -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}" \
    -B "${INPUT_EDR_DIR}":"${INPUT_EDR_DIR}" \
    -B "${OUTPUT_IMG_DIR}":/output_data \
    "${SIF_P2G}" \
    polar2grid.sh \
    -r viirs_sdr viirs_edr_active_fires \
    -w geotiff \
    -p confidence_cat \
    --grid-configs /opt/polar2grid/grids.conf \
    -g mx_1000 \
    -f /input_data \
    -vv

EXIT_CODE=$?

# ==============================================================================
# 4. Limpieza
# ==============================================================================
rm -rf "${STAGING_DIR}"

echo "================================================================="
echo " INFO: Proceso finalizado. Código: ${EXIT_CODE}"
echo "================================================================="
