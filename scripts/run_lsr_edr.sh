#!/bin/bash
#SBATCH --job-name=cspp_lsr_edr
#SBATCH --output=logs/lsr_%j.out
#SBATCH --error=logs/lsr_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8       # Ajusta según los recursos de tu nodo
#SBATCH --mem=32G               # LSR puede requerir buena memoria para pasadas completas
#SBATCH --time=01:00:00
#SBATCH --partition=normal      # Ajusta a tu partición de LANOT

# ==============================================================================
# Configuración de Rutas (Host / Sistema de Archivos Lustre)
# ==============================================================================
# Define aquí tus rutas reales en el clúster
BASE_DIR="/data/opt"

# Rutas a los datos estáticos y auxiliares de LSR (descargados previamente)
LSR_STATIC_DIR="${BASE_DIR}/cspp_lsr_static"
LSR_ANCILLARY_DIR="${BASE_DIR}/cspp_lsr_ancillary"

# Rutas de entrada (archivos SDR de Nivel 1) y salida
INPUT_SDR_DIR="/data/output/jpss/level1/viirs"
OUTPUT_LSR_DIR="/data/output/jpss/level2/lsr"

# Ruta a la imagen del contenedor de Apptainer que construimos
SIF_IMAGE="/opt/containers/cspp_lsr_edr_v2.0.sif"

# ==============================================================================
# Preparación del entorno
# ==============================================================================
# Asegurarnos de que el directorio de salida exista
mkdir -p "${OUTPUT_LSR_DIR}"
mkdir -p logs

echo "================================================================="
echo " Iniciando procesamiento de CSPP LSR v2.0 con Apptainer"
echo " Fecha y Hora: $(date)"
echo " Directorio de Entrada (SDR): ${INPUT_SDR_DIR}"
echo " Directorio de Salida (LSR): ${OUTPUT_LSR_DIR}"
echo "================================================================="

# ==============================================================================
# Ejecución con Apptainer
# ==============================================================================
# Usamos -B (bind) para inyectar los directorios del host al contenedor.
# Las rutas del lado derecho (después de los dos puntos) deben coincidir
# EXACTAMENTE con las que configuramos en la sección %post del archivo .def.

apptainer exec \
    -B "${LSR_STATIC_DIR}":/opt/cspp_lsr/static \
    -B "${LSR_ANCILLARY_DIR}":/opt/cspp_lsr/ancillary \
    -B "${INPUT_SDR_DIR}":/input_data \
    -B "${OUTPUT_LSR_DIR}":/output_data \
    "${SIF_IMAGE}" \
    viirs_lsr.sh -i /input_data -o /output_data

# Nota: El comando interno 'viirs_lsr.sh' ya está en el PATH del contenedor
# gracias al cspp_lsr_env.sh que cargamos en el %environment del .def.

EXIT_CODE=$?

echo "================================================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo " Procesamiento completado exitosamente a las $(date)"
else
    echo " ERROR: El procesamiento falló con el código de salida $EXIT_CODE"
fi
echo "================================================================="

exit $EXIT_CODE
