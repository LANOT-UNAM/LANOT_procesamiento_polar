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
# LANOT - UNAM | CSPP Active Fire v2.1 (Apptainer)
# ==============================================================================

# --- Rutas de Datos y Software ---
INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
OUTPUT_DIR="/data/output/jpss/level2/fires"
SIF_IMAGE="/opt/containers/cspp_active_fire_edr.sif"

# --- Directorio Temporal (Staging) ---
# Siguiendo tu lógica de usar el JOB_ID de SLURM o el PID del proceso
JOB_ID=${SLURM_JOB_ID:-$$}
STAGING_DIR="/data/output/jpss/tmp/fire_staging_${JOB_ID}"
CORES=${SLURM_CPUS_PER_TASK:-8}

# --- Preparación del Entorno ---
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${STAGING_DIR}"
mkdir -p logs

echo "================================================================="
echo " Iniciando CSPP Active Fire v2.1 a las $(date)"
echo " Preparando staging en: ${STAGING_DIR}"

# Enlazamos los SDR necesarios (M-Bands, I-Bands y Geometrías GMTCO/GITCO)
# Usamos enlaces simbólicos para no duplicar datos
ln -s ${INPUT_SDR_DIR}/* ${STAGING_DIR}/

echo " Cores asignados: ${CORES}"
echo "================================================================="

# ==============================================================================
# Ejecución con Apptainer
# ==============================================================================
# -B "${STAGING_DIR}":/input_data  -> Donde están los SDRs
# -B "${OUTPUT_DIR}":/output_data  -> Donde caerán los NetCDF/ASCII
# --env CSPP_ACTIVE_FIRE_HOME      -> Ruta base interna definida en el .def

apptainer exec \
    --env LC_ALL=C \
    --env CSPP_ACTIVE_FIRE_HOME=/opt/cspp_active_fire \
    -B "${STAGING_DIR}":/input_data \
    -B "${OUTPUT_DIR}":/output_data \
    -B "/data/output/jpss":"/data/output/jpss" \
    "${SIF_IMAGE}" \
    /opt/cspp_active_fire/cspp_active_fire_noaa.sh \
    -i /input_data \
    -o /output_data \
    "$@"

EXIT_CODE=$?

# ==============================================================================
# Limpieza
# ==============================================================================
echo "================================================================="
echo " Limpiando directorio de staging..."
rm -rf "${STAGING_DIR}"

if [ $EXIT_CODE -eq 0 ]; then
    echo " Procesamiento completado exitosamente: $(date)"
else
    echo " ERROR: El proceso falló con código ${EXIT_CODE}"
fi
echo "================================================================="

exit $EXIT_CODE
