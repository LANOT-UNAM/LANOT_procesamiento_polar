#!/bin/bash
#SBATCH --job-name=acspo_p2g
#SBATCH --output=/var/log/lanot/polares/cspp-edr/slurm_acspo_%j.out
#SBATCH --error=/var/log/lanot/polares/cspp-edr/slurm_acspo_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=01:30:00
#SBATCH --partition=normal
# ==============================================================================
# LANOT - UNAM | ACSPO SST v3.0 + Renderizado Polar2Grid
# ==============================================================================
#
# Level 1 (SDR de VIIRS) → SST ACSPO (.nc) → GeoTIFF
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue procesada con éxito, avisa y no hace nada. Una pasada se identifica
# por satélite, fecha y hora de inicio (p. ej. j01_d20260811_t194733;
# ver pasadas.sh).
#
# Ancillary dinámico: ACSPO lo descarga solo y lo guarda en subdirectorios por
# día dentro de su caché. Ese caché es EXCLUSIVO de ACSPO: aunque su formato se
# parezca al de CSPP SDR, son archivos distintos (GFS a 1 grado) y mezclarlos
# ensucia ambos.
#
# Este script solo genera los .nc. El GeoTIFF y la vista de la SST salen de
# run_polar2grid_edr.sh, que es el renderizador único de Level 2: ahí están las
# rejillas de config/grid.yaml, las paletas y la separación geotiff/ ÷ vistas/.
#
# Uso:
#   ./run_acspo_edr.sh              # la pasada más reciente pendiente
#   ./run_acspo_edr.sh --force      # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   ACSPO_SDR_IN     Entrada Level 1  (def. /data/output/jpss/level1/viirs)
#   ACSPO_OUT        Salida .nc       (def. /data/output/jpss/level2/acspo)
#   ACSPO_STATE_DIR  Marcadores .done (def. /data/output/jpss/state/cspp-acspo)
#   ACSPO_CACHE      Caché dinámico   (def. /data/ancillary/acspo)
#   ACSPO_CONTAINER  Imagen .sif      (def. /opt/containers/cspp_acspo_edr_v3.0.sif)
#   ACSPO_WORK_BASE  Raíz de staging  (def. /data/tmp)
#   ACSPO_LOG_BASE   Raíz de logs     (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_ACSPO="${ACSPO_CONTAINER:-/opt/containers/cspp_acspo_edr_v3.0.sif}"

INPUT_SDR_DIR="${ACSPO_SDR_IN:-/data/output/jpss/level1/viirs}"
OUTPUT_ACSPO_DIR="${ACSPO_OUT:-/data/output/jpss/level2/acspo}"
STATE_DIR="${ACSPO_STATE_DIR:-/data/output/jpss/state/cspp-acspo}"
HOST_CACHE="${ACSPO_CACHE:-/data/ancillary/acspo}"

WORK_BASE="${ACSPO_WORK_BASE:-/data/tmp}"
LOG_DIR="${ACSPO_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

CORES="${SLURM_CPUS_PER_TASK:-16}"
JOB_ID="${SLURM_JOB_ID:-$$}"

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0                Procesa la pasada más reciente de $INPUT_SDR_DIR
  $0 --force        Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force      Ignora el marcador de procesado
  -p, --pasada     Pasada concreta en vez de la más reciente: la clave completa
                   (j01_d20260813_t191402) o cualquier trozo que la identifique
  -h, --help       Muestra esta ayuda

Las vistas de la SST las genera run_polar2grid_edr.sh.

Pasadas disponibles en $INPUT_SDR_DIR:
$(listar_pasadas "$INPUT_SDR_DIR" GMTCO 2>/dev/null | cut -d' ' -f1 | sed 's/^/  /' || true)
EOF
}

# Qué es una pasada y cómo se elige: por tiempo, no por órbita (ver pasadas.sh).
# Fija CLAVE, SAT, FECHA y la ventana VENTANA_INI – VENTANA_FIN.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/pasadas.sh"

formato_duracion() {
    local s="$1"
    if [ "$s" -ge 3600 ]; then
        printf '%dh %dm %ds' $((s / 3600)) $(((s % 3600) / 60)) $((s % 60))
    elif [ "$s" -ge 60 ]; then
        printf '%dm %ds' $((s / 60)) $((s % 60))
    else
        printf '%ds' "$s"
    fi
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================

FORCE=0
PASADA=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)   FORCE=1 ;;
        -h|--help)    uso; exit 0 ;;
        -p|--pasada)
            if [ $# -lt 2 ]; then
                echo "ERROR: --pasada necesita un valor" >&2
                exit 1
            fi
            PASADA="$2"
            shift
            ;;
        *)
            echo "ERROR: Argumento no reconocido: $1" >&2
            uso >&2
            exit 1
            ;;
    esac
    shift
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')
STAGING_DIR="${WORK_BASE}/acspo_staging_${JOB_ID}"
WORK_DIR="${WORK_BASE}/acspo_work_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$INPUT_SDR_DIR" ]; then
    echo "ERROR: Directorio de SDR no encontrado: $INPUT_SDR_DIR" >&2
    exit 1
fi

resolver_pasada "$INPUT_SDR_DIR" GMTCO "$PASADA" || exit 1

if [ -z "$CLAVE" ]; then
    echo "No hay SDR que procesar en $INPUT_SDR_DIR (no se ven archivos GMTCO*)."
    exit 0
fi

echo "=== ACSPO SST v3.0 | pasada $CLAVE ==="

# ==============================================================================
# ¿YA FUE PROCESADA?
# ==============================================================================

MARKER="${STATE_DIR}/${CLAVE}.done"

if [ -f "$MARKER" ] && [ "$FORCE" -eq 0 ]; then
    echo ""
    echo "ℹ  La pasada $CLAVE ya fue procesada:"
    while IFS= read -r linea; do
        echo "   $linea"
    done < "$MARKER"
    echo ""
    echo "   No hay nada que hacer. Usa --force para reprocesarla."
    exit 0
fi

if [ -f "$MARKER" ]; then
    echo "--force: se reprocesa a pesar del marcador existente"
fi

# ==============================================================================
# VALIDACIÓN DEL AMBIENTE
# ==============================================================================

if [ ! -f "$SIF_ACSPO" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_ACSPO" >&2
    exit 1
fi

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================

mkdir -p "$STAGING_DIR" "$WORK_DIR/dynamic" "$OUTPUT_ACSPO_DIR" \
         "$HOST_CACHE" "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$STAGING_DIR" "$WORK_DIR"' EXIT

while IFS= read -r f; do
    ln -sf "$f" "$STAGING_DIR"/
done < <(archivos_de_pasada "$INPUT_SDR_DIR" '*')

SDR_COUNT=$(find "$STAGING_DIR" -name '*.h5' | wc -l)

if [ "$SDR_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR de la pasada $CLAVE" >&2
    exit 1
fi

LOG_FILE="$LOG_DIR/acspo_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR:     $SDR_COUNT archivos"    | tee -a "$LOG_FILE"
echo "  Salida:  $OUTPUT_ACSPO_DIR"      | tee -a "$LOG_FILE"
echo "  Caché:   $HOST_CACHE"            | tee -a "$LOG_FILE"
echo "  Hilos:   $CORES"                 | tee -a "$LOG_FILE"

# ==============================================================================
# PASO 1: GENERACIÓN DE SST (ACSPO)
# ==============================================================================

REF_FILE=$(mktemp -t acspo_ref_XXXXXX)
trap 'rm -rf "$STAGING_DIR" "$WORK_DIR" "$REF_FILE"' EXIT

echo ">>> Iniciando ACSPO v3.0..." | tee -a "$LOG_FILE"

EXIT_CODE=0
apptainer exec \
    --env LC_ALL=C --env CSPP_ACSPO_HOME=/opt/acspo_sst_v3 \
    -B "${STAGING_DIR}":/input_sdr \
    -B "${OUTPUT_ACSPO_DIR}":/output_data \
    -B "${WORK_DIR}":/work_data \
    -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}" \
    -B "${HOST_CACHE}":"/opt/acspo_sst_v3/viirs/input/anc/ancil_download" \
    -B "/data/ancillary/acspo_wisdom":"/opt/acspo_sst_v3/viirs/input/sst_wisdom" \
    -B "/data/ancillary/acspo_histogram":"/opt/acspo_sst_v3/viirs/input/sst_histogram" \
    -B "${WORK_DIR}/dynamic":"/opt/acspo_sst_v3/viirs/input/anc/dynamic" \
    "${SIF_ACSPO}" \
    /opt/acspo_sst_v3/run_acspo_viirs_v3.sh -p "${CORES}" -w /work_data -o /output_data \
        -d /opt/acspo_sst_v3/viirs/input/anc/ancil_download -m gds /input_sdr \
    >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: ACSPO falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                              | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

NC_COUNT=$(find "$OUTPUT_ACSPO_DIR" -maxdepth 1 -name '*.nc' -newer "$REF_FILE" 2>/dev/null | wc -l)

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: ACSPO terminó sin error pero no generó productos."  | tee -a "$LOG_FILE"
    echo "   Causa típica: falta ancillary dinámico en $HOST_CACHE"     | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                  | tee -a "$LOG_FILE"
    exit 1
fi

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "sdr:       $SDR_COUNT archivos de entrada"
    echo "productos: $NC_COUNT archivos .nc"
    echo "duracion:  $DURACION"
    echo "salida:    $OUTPUT_ACSPO_DIR"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE ($DURACION)" | tee -a "$LOG_FILE"
echo "   Salida:   $OUTPUT_ACSPO_DIR"                               | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER"                                         | tee -a "$LOG_FILE"
echo "   Las vistas de la SST las genera run_polar2grid_edr.sh"     | tee -a "$LOG_FILE"
