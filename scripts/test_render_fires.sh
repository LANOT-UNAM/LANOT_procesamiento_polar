#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Renderizado de Confidence Category (Active Fire) - FIX TOTAL
# ==============================================================================

SIF_P2G="/opt/containers/polar2grid_v3.2.sif"
INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
INPUT_EDR_DIR="/data/output/jpss/level2/fires"
OUTPUT_IMG_DIR="/data/output/jpss/vistas/active_fire_test"

JOB_ID=${SLURM_JOB_ID:-$$}
STAGING_DIR="/data/output/jpss/tmp/p2g_fire_staging_${JOB_ID}"

mkdir -p "${OUTPUT_IMG_DIR}" "${STAGING_DIR}"

echo "================================================================="
echo " INFO: Preparando staging con limpieza de nombres..."

# 1. Enlazamos TODO (SDR y EDR)
ln -sf ${INPUT_SDR_DIR}/* ${STAGING_DIR}/
ln -sf ${INPUT_EDR_DIR}/AFIMG_j01*.nc ${STAGING_DIR}/

# 2. LIMPIEZA CRÍTICA: Quitar '_cspp_dev' de TODOS los archivos (h5 y nc)
# Esto es vital para que viirs_sdr vea las bandas y viirs_edr_active_fires vea los fuegos
echo " INFO: Eliminando sufijos _cspp_dev en el staging..."
cd "${STAGING_DIR}"
for f in *_cspp_dev*; do
    mv "$f" "${f//_cspp_dev/}" 2>/dev/null
done
cd - > /dev/null

# ==============================================================================
# 3. Ejecución de Polar2Grid
# ==============================================================================
# Probaremos con el lector 'viirs_edr_active_fires'
# Si falla, intenta cambiarlo por 'viirs_active_fire' (sin el 'edr_')

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
if [ $EXIT_CODE -eq 0 ]; then
    echo " INFO: Renderizado exitoso."
else
    echo " ERROR: El renderizado volvió a fallar."
fi
echo "================================================================="
