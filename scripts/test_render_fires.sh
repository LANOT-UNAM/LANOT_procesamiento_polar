#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Test Render Active Fire (Polar2Grid)
# ==============================================================================

# --- Configuración de Rutas ---
SIF_P2G="/opt/containers/polar2grid_v3.2.sif"
INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
INPUT_EDR_DIR="/data/output/jpss/level2/fires"
OUTPUT_IMG_DIR="/data/output/jpss/vistas/active_fire_test"

# Directorio temporal para agrupar solo lo necesario para este render
JOB_ID=${SLURM_JOB_ID:-$$}
STAGING_DIR="/data/output/jpss/tmp/p2g_fire_staging_${JOB_ID}"

mkdir -p "${OUTPUT_IMG_DIR}" "${STAGING_DIR}"

echo "================================================================="
echo " INFO: Iniciando Renderizado de Prueba (Active Fire)"
echo " INFO: Preparando staging..."

# 1. Enlazamos los SDR (necesarios para el fondo y la geolocalización)
# y los EDR (los archivos AFIMG que acabas de generar)
ln -sf ${INPUT_SDR_DIR}/GMTCO_j01* ${STAGING_DIR}/
ln -sf ${INPUT_SDR_DIR}/GITCO_j01* ${STAGING_DIR}/
ln -sf ${INPUT_SDR_DIR}/SVM07_j01* ${STAGING_DIR}/  # Banda M para contexto
ln -sf ${INPUT_SDR_DIR}/SVI05_j01* ${STAGING_DIR}/  # Banda I térmica (fondo ideal)
ln -sf ${INPUT_EDR_DIR}/AFIMG_j01* ${STAGING_DIR}/  # Tus resultados de Active Fire

# ==============================================================================
# 2. Ejecución de Polar2Grid
# ==============================================================================
# Generaremos dos vistas:
# a) La máscara de fuego pura (fire_mask)
# b) La banda I05 (térmica) para comparar visualmente
# El flag --overlay permite que los puntos de fuego se marquen sobre la imagen

apptainer exec \
    -B "${STAGING_DIR}":/input_data \
    -B "${OUTPUT_IMG_DIR}":/output_data \
    "${SIF_P2G}" \
    polar2grid.sh \
    -r viirs_sdr viirs_edr_active_fires \
    -w geotiff \
    -p fire_mask i05 \
    --grid-configs /opt/polar2grid/grids.conf \
    -g mx_1000 \
    -f /input_data

EXIT_CODE=$?

# ==============================================================================
# 3. Limpieza
# ==============================================================================
rm -rf "${STAGING_DIR}"

echo "================================================================="
echo " INFO: Proceso finalizado. Código: ${EXIT_CODE}"
echo " INFO: Imágenes generadas en: ${OUTPUT_IMG_DIR}"
echo "================================================================="
