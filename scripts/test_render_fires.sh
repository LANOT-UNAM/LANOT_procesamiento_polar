#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Renderizado de confidence_cat (Active Fire) - FIX FINAL
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
echo " INFO: Limpiando y preparando staging..."

# 1. Enlaces simbólicos de TODO lo necesario
# SDR: Geolocalización y Bandas (I05 y M07 son las que usa Active Fire)
ln -sf ${INPUT_SDR_DIR}/GMTCO_j01*.h5 ${STAGING_DIR}/
ln -sf ${INPUT_SDR_DIR}/GITCO_j01*.h5 ${STAGING_DIR}/
ln -sf ${INPUT_SDR_DIR}/SVI05_j01*.h5 ${STAGING_DIR}/
ln -sf ${INPUT_SDR_DIR}/SVM07_j01*.h5 ${STAGING_DIR}/
ln -sf ${INPUT_SDR_DIR}/SVM13_j01*.h5 ${STAGING_DIR}/

# EDR: Tus resultados de Active Fire
ln -sf ${INPUT_EDR_DIR}/AFIMG_j01*.nc ${STAGING_DIR}/

# 2. RENOMBRADO AGRESIVO:
# Satpy NO acepta '_cspp_dev' en los archivos EDR ni en las bandas de datos.
echo " INFO: Eliminando sufijos que bloquean a Polar2Grid..."
cd "${STAGING_DIR}"
for f in *; do
    if [[ "$f" == *"_cspp_dev"* ]]; then
        new_name=$(echo "$f" | sed 's/_cspp_dev//')
        mv "$f" "$new_name"
    fi
done
cd - > /dev/null

# Verificación rápida en el terminal antes de lanzar P2G
echo " INFO: Archivos listos en staging: $(ls ${STAGING_DIR} | head -n 3)"

# ==============================================================================
# 3. Ejecución de Polar2Grid
# ==============================================================================
# Usamos -p confidence_cat y forzamos ambos lectores.
# Importante: Incluimos los binds de las rutas originales para los enlaces simbólicos.

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
# rm -rf "${STAGING_DIR}"  # Descomenta esto cuando confirmes que funciona

echo "================================================================="
echo " INFO: Proceso finalizado. Código: ${EXIT_CODE}"
echo "================================================================="
