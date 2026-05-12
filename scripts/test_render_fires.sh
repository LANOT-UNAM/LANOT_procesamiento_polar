#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Fix Final: Renderizado de confidence_cat
# ==============================================================================

SIF_P2G="/opt/containers/polar2grid_v3.2.sif"
INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
INPUT_EDR_DIR="/data/output/jpss/level2/fires"
OUTPUT_IMG_DIR="/data/output/jpss/vistas/active_fire_test"

JOB_ID=${SLURM_JOB_ID:-$$}
STAGING_DIR="/data/output/jpss/tmp/p2g_fire_staging_${JOB_ID}"

mkdir -p "${OUTPUT_IMG_DIR}" "${STAGING_DIR}"

echo "================================================================="
echo " INFO: Preparando staging con corrección de mayúsculas (j01 -> J01)"

# 1. Enlaces simbólicos de los archivos necesarios
ln -sf ${INPUT_SDR_DIR}/GMTCO_j01*.h5 ${STAGING_DIR}/
ln -sf ${INPUT_SDR_DIR}/GITCO_j01*.h5 ${STAGING_DIR}/
ln -sf ${INPUT_SDR_DIR}/SVI05_j01*.h5 ${STAGING_DIR}/
ln -sf ${INPUT_EDR_DIR}/AFIMG_j01*.nc ${STAGING_DIR}/

# 2. RENOMBRADO AGRESIVO Y CAMBIO DE CASE
# Satpy es muy sensible: 'j01' (minúscula) a menudo no hace match con el regex.
echo " INFO: Normalizando nombres para Satpy..."
cd "${STAGING_DIR}"
for f in *; do
    # 1. Quitar el sufijo _cspp_dev
    new_name=$(echo "$f" | sed 's/_cspp_dev//')
    # 2. Cambiar j01 por J01 (Mayúscula)
    new_name=$(echo "$new_name" | sed 's/j01/J01/')
    
    if [ "$f" != "$new_name" ]; then
        mv "$f" "$new_name"
    fi
done
cd - > /dev/null

echo " INFO: Archivos normalizados (ejemplo): $(ls ${STAGING_DIR} | grep GMTCO | head -n 1)"

# ==============================================================================
# 3. Ejecución de Polar2Grid
# ==============================================================================
# Intentaremos con el lector 'viirs_active_fire' que es el alias común en P2G v3
# Si falla, el log nos dirá si el problema es el lector o el producto.

apptainer exec \
    --env LC_ALL=C \
    -B "${STAGING_DIR}":/input_data \
    -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}" \
    -B "${INPUT_EDR_DIR}":"${INPUT_EDR_DIR}" \
    -B "${OUTPUT_IMG_DIR}":/output_data \
    "${SIF_P2G}" \
    polar2grid.sh \
    -r viirs_sdr viirs_active_fire \
    -w geotiff \
    -p confidence_cat \
    --grid-configs /opt/polar2grid/grids.conf \
    -g mx_1000 \
    -f /input_data \
    -vv

EXIT_CODE=$?

echo "================================================================="
echo " INFO: Proceso finalizado con código: ${EXIT_CODE}"
echo "================================================================="
