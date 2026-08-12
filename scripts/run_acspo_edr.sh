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
#
# Level 1 (SDR de VIIRS) → SST ACSPO (.nc) → GeoTIFF
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue procesada con éxito, avisa y no hace nada. Una pasada se identifica
# por satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
#
# Ancillary dinámico: ACSPO lo descarga solo y lo guarda en subdirectorios por
# día dentro de su caché. Ese caché es EXCLUSIVO de ACSPO: aunque su formato se
# parezca al de CSPP SDR, son archivos distintos (GFS a 1 grado) y mezclarlos
# ensucia ambos.
#
# El marcador cubre la generación de los .nc de ACSPO, que es la parte cara. Si
# falla el renderizado posterior, el script sale con error pero el marcador ya
# está escrito: corrige y vuelve a renderizar, o usa --force para rehacer todo.
#
# Uso:
#   ./run_acspo_edr.sh              # la pasada más reciente pendiente
#   ./run_acspo_edr.sh --no-render  # solo genera los .nc, sin GeoTIFF
#   ./run_acspo_edr.sh --force      # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   ACSPO_SDR_IN     Entrada Level 1  (def. /data/output/jpss/level1/viirs)
#   ACSPO_OUT        Salida .nc       (def. /data/output/jpss/level2/acspo)
#   ACSPO_IMG_OUT    Salida GeoTIFF   (def. /data/output/jpss/vistas/acspo)
#   ACSPO_STATE_DIR  Marcadores .done (def. /data/output/jpss/state/cspp-acspo)
#   ACSPO_CACHE      Caché dinámico   (def. /data/ancillary/acspo)
#   ACSPO_CONTAINER  Imagen .sif      (def. /opt/containers/cspp_acspo_edr_v3.0.sif)
#   P2G_CONTAINER    Imagen Polar2Grid(def. /opt/containers/polar2grid_v3.2.sif)
#   ACSPO_WORK_BASE  Raíz de staging  (def. /data/output/jpss/tmp)
#   ACSPO_LOG_BASE   Raíz de logs     (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_ACSPO="${ACSPO_CONTAINER:-/opt/containers/cspp_acspo_edr_v3.0.sif}"
SIF_P2G="${P2G_CONTAINER:-/opt/containers/polar2grid_v3.2.sif}"

INPUT_SDR_DIR="${ACSPO_SDR_IN:-/data/output/jpss/level1/viirs}"
OUTPUT_ACSPO_DIR="${ACSPO_OUT:-/data/output/jpss/level2/acspo}"
OUTPUT_IMG_DIR="${ACSPO_IMG_OUT:-/data/output/jpss/vistas/acspo}"
STATE_DIR="${ACSPO_STATE_DIR:-/data/output/jpss/state/cspp-acspo}"
HOST_CACHE="${ACSPO_CACHE:-/data/ancillary/acspo}"

WORK_BASE="${ACSPO_WORK_BASE:-/data/output/jpss/tmp}"
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
  $0 --no-render    Genera los .nc de ACSPO sin renderizar GeoTIFF
  $0 --force        Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force      Ignora el marcador de procesado
      --no-render  Omite el paso de Polar2Grid
  -h, --help       Muestra esta ayuda
EOF
}

# GMTCO_j01_d20260811_t1947330_e1948557_b45236_c2026...h5 -> j01_d20260811_b45236
clave_de_pasada() {
    local nombre sat fecha orbita
    nombre=$(basename "$1")
    IFS='_' read -r _ sat fecha _ _ orbita _ <<< "$nombre"
    if [[ "$fecha" != d* ]] || [[ "$orbita" != b* ]]; then
        return 1
    fi
    echo "${sat}_${fecha}_${orbita}"
}

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
RENDER=1

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)   FORCE=1 ;;
        --no-render)  RENDER=0 ;;
        -h|--help)    uso; exit 0 ;;
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

ULTIMO_GMTCO=$(find "$INPUT_SDR_DIR" -maxdepth 1 -name 'GMTCO*.h5' \
                    -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$ULTIMO_GMTCO" ]; then
    echo "No hay SDR que procesar en $INPUT_SDR_DIR (no se ven archivos GMTCO*)."
    exit 0
fi

if ! CLAVE=$(clave_de_pasada "$ULTIMO_GMTCO"); then
    echo "ERROR: No se pudo derivar la pasada del nombre: $(basename "$ULTIMO_GMTCO")" >&2
    exit 1
fi

IFS='_' read -r SAT FECHA ORBITA <<< "$CLAVE"

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

if [ "$RENDER" -eq 1 ] && [ ! -f "$SIF_P2G" ]; then
    echo "ERROR: Contenedor de Polar2Grid no encontrado: $SIF_P2G" >&2
    echo "       Usa --no-render si solo quieres los .nc." >&2
    exit 1
fi

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================

mkdir -p "$STAGING_DIR" "$WORK_DIR/dynamic" "$OUTPUT_ACSPO_DIR" "$OUTPUT_IMG_DIR" \
         "$HOST_CACHE" "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$STAGING_DIR" "$WORK_DIR"' EXIT

ln -sf "$INPUT_SDR_DIR"/*_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5 "$STAGING_DIR"/ 2>/dev/null || true

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

echo "✅ ACSPO: $NC_COUNT productos de la pasada $CLAVE ($DURACION)" | tee -a "$LOG_FILE"

if [ "$RENDER" -eq 0 ]; then
    echo "   Renderizado omitido (--no-render). Marcador: $MARKER" | tee -a "$LOG_FILE"
    exit 0
fi

# ==============================================================================
# PASO 2: RENDERIZADO CON POLAR2GRID
# ==============================================================================

LATEST_NC=$(find "$OUTPUT_ACSPO_DIR" -maxdepth 1 -name '*.nc' -newer "$REF_FILE" \
                 -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

echo ">>> Renderizando $(basename "$LATEST_NC") con Polar2Grid..." | tee -a "$LOG_FILE"

RENDER_CODE=0
apptainer exec \
    -B "${OUTPUT_ACSPO_DIR}":/input_nc \
    -B "${OUTPUT_IMG_DIR}":/output_img \
    -B "${WORK_DIR}":/work_p2g \
    "${SIF_P2G}" \
    bash -c "
        cd /output_img
        polar2grid.sh -v -r acspo -w geotiff -p sst --grid-coverage=0.0 \
            -f /input_nc/$(basename "$LATEST_NC")
    " >> "$LOG_FILE" 2>&1 || RENDER_CODE=$?

TIF_COUNT=$(find "$OUTPUT_IMG_DIR" -maxdepth 1 -name '*.tif' -newer "$REF_FILE" 2>/dev/null | wc -l)

if [ $RENDER_CODE -ne 0 ] || [ "$TIF_COUNT" -eq 0 ]; then
    echo "❌ ERROR: El renderizado falló (código $RENDER_CODE, $TIF_COUNT imágenes)" | tee -a "$LOG_FILE"
    echo "   Los .nc de ACSPO sí se generaron y el marcador ya está escrito."        | tee -a "$LOG_FILE"
    echo "   Corrige y vuelve a renderizar, o usa --force para rehacer todo."        | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                               | tee -a "$LOG_FILE"
    exit 1
fi

echo "✅ ÉXITO: $NC_COUNT productos y $TIF_COUNT imágenes de la pasada $CLAVE" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"
