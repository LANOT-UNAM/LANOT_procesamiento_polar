#!/bin/bash
#SBATCH --job-name=cspp_cryo_edr
#SBATCH --output=logs/cryo_%j.out
#SBATCH --error=logs/cryo_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --partition=normal
# ==============================================================================
# LANOT - UNAM | CSPP VIIRS Cryosphere EDR v1.0
# ==============================================================================
#
# Level 1 (SDR de VIIRS) + Level 2 atmosphere → productos de criósfera
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue procesada con éxito, avisa y no hace nada. Una pasada se identifica
# por satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
#
# Requiere de ATMOS los productos Cloud Mask y Cloud Height de la misma pasada
# (manual §2: "CSPP CRYO also requires two VIIRS Atmosphere EDR products").
# No usa ancillary dinámico.
#
# Uso:
#   ./run_cryo_edr.sh            # la pasada más reciente pendiente
#   ./run_cryo_edr.sh --force    # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   CRYO_SDR_IN     Entrada Level 1   (def. /data/output/jpss/level1/viirs)
#   CRYO_ATMOS_IN   Entrada atmosphere(def. /data/output/jpss/level2/atmosphere)
#   CRYO_OUT        Salida            (def. /data/output/jpss/level2/cryosphere)
#   CRYO_STATE_DIR  Marcadores .done  (def. /data/output/jpss/state/cspp-cryo)
#   CRYO_CONTAINER  Imagen .sif       (def. /opt/containers/cspp_cryo_edr_v1.0.sif)
#   CRYO_WORK_BASE  Raíz de staging   (def. /data/output/jpss/tmp)
#   CRYO_LOG_BASE   Raíz de logs      (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_IMAGE="${CRYO_CONTAINER:-/opt/containers/cspp_cryo_edr_v1.0.sif}"

INPUT_SDR_DIR="${CRYO_SDR_IN:-/data/output/jpss/level1/viirs}"
INPUT_ATMOS_DIR="${CRYO_ATMOS_IN:-/data/output/jpss/level2/atmosphere}"
OUTPUT_CRYO_DIR="${CRYO_OUT:-/data/output/jpss/level2/cryosphere}"
STATE_DIR="${CRYO_STATE_DIR:-/data/output/jpss/state/cspp-cryo}"

WORK_BASE="${CRYO_WORK_BASE:-/data/output/jpss/tmp}"
LOG_DIR="${CRYO_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

CORES="${SLURM_CPUS_PER_TASK:-8}"
JOB_ID="${SLURM_JOB_ID:-$$}"

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0             Procesa la pasada más reciente de $INPUT_SDR_DIR
  $0 --force     Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force   Ignora el marcador de procesado
  -h, --help    Muestra esta ayuda
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

# Enlaza Cloud Mask y Cloud Height de los gránulos de la pasada. Los JRR-* no
# llevan número de órbita: se emparejan por el sello temporal, que concatena
# fecha y hora de inicio del gránulo (GMTCO d20260811 + t1947330 ->
# JRR s202608111947330).
enlazar_atmos() {
    local destino="$1" origen="$2" enlazados=0 g nombre fecha tiempo sello prod

    for g in "$destino"/GMTCO_*.h5; do
        [ -e "$g" ] || continue
        nombre=$(basename "$g")
        IFS='_' read -r _ _ fecha tiempo _ <<< "$nombre"
        sello="s${fecha#d}${tiempo#t}"

        for prod in JRR-CloudMask JRR-CloudHeight; do
            if compgen -G "$origen/${prod}*${sello}*.nc" > /dev/null; then
                ln -sf "$origen"/"${prod}"*"${sello}"*.nc "$destino"/
                enlazados=$((enlazados + 1))
            fi
        done
    done

    echo "$enlazados"
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================

FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        -h|--help)  uso; exit 0 ;;
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
STAGING_DIR="${WORK_BASE}/cryo_staging_${JOB_ID}"

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

echo "=== CSPP VIIRS Cryosphere v1.0 | pasada $CLAVE ==="

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

if [ ! -f "$SIF_IMAGE" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_IMAGE" >&2
    exit 1
fi

if [ ! -d "$INPUT_ATMOS_DIR" ]; then
    echo "ERROR: Directorio de productos ATMOS no encontrado: $INPUT_ATMOS_DIR" >&2
    echo "       CRYO necesita Cloud Mask y Cloud Height: corre run_atmos_edr.sh antes." >&2
    exit 1
fi

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================

mkdir -p "$STAGING_DIR" "$OUTPUT_CRYO_DIR" "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$STAGING_DIR"' EXIT

# CRYO solo necesita las bandas M y su geolocalización
ln -sf "$INPUT_SDR_DIR"/SVM*_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5 "$STAGING_DIR"/ 2>/dev/null || true
ln -sf "$INPUT_SDR_DIR"/GMTCO_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5 "$STAGING_DIR"/ 2>/dev/null || true

SDR_COUNT=$(find "$STAGING_DIR" -name '*.h5' | wc -l)

if [ "$SDR_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR de la pasada $CLAVE" >&2
    exit 1
fi

PRODUCTOS_ATMOS=$(enlazar_atmos "$STAGING_DIR" "$INPUT_ATMOS_DIR")

if [ "$PRODUCTOS_ATMOS" -eq 0 ]; then
    echo "ERROR: No hay Cloud Mask / Cloud Height para la pasada $CLAVE en $INPUT_ATMOS_DIR" >&2
    echo "       Corre run_atmos_edr.sh para esa pasada antes que CRYO." >&2
    exit 1
fi

LOG_FILE="$LOG_DIR/cryo_edr_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR:      $SDR_COUNT archivos (SVM* + GMTCO*)"        | tee -a "$LOG_FILE"
echo "  ATMOS:    $PRODUCTOS_ATMOS productos enlazados"       | tee -a "$LOG_FILE"
echo "  Salida:   $OUTPUT_CRYO_DIR"                           | tee -a "$LOG_FILE"
echo "  Hilos:    $CORES"                                     | tee -a "$LOG_FILE"

# ==============================================================================
# EJECUCIÓN
# ==============================================================================
# viirs_cryo.sh escribe los resultados en el directorio actual, por eso el
# --pwd /output_data.

REF_FILE=$(mktemp -t cryo_edr_ref_XXXXXX)
trap 'rm -rf "$STAGING_DIR" "$REF_FILE"' EXIT

EXIT_CODE=0
apptainer exec \
    --env LC_ALL=C \
    --env CSPP_VIIRS_CRYO_HOME=/opt/cspp_cryo \
    -B "${STAGING_DIR}":/input_data \
    -B "${OUTPUT_CRYO_DIR}":/output_data \
    -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}" \
    -B "${INPUT_ATMOS_DIR}":"${INPUT_ATMOS_DIR}" \
    --pwd /output_data \
    "${SIF_IMAGE}" \
    /opt/cspp_cryo/bin/viirs_cryo.sh -p "${CORES}" /input_data \
    >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP CRYO falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                  | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN DE PRODUCTOS
# ==============================================================================

NC_COUNT=$(find "$OUTPUT_CRYO_DIR" -maxdepth 1 -name '*.nc' -newer "$REF_FILE" 2>/dev/null | wc -l)

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: CSPP CRYO terminó sin error pero no generó productos." | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                     | tee -a "$LOG_FILE"
    exit 1
fi

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "sdr:       $SDR_COUNT archivos de entrada"
    echo "productos: $NC_COUNT archivos .nc"
    echo "duracion:  $DURACION"
    echo "salida:    $OUTPUT_CRYO_DIR"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE en $OUTPUT_CRYO_DIR ($DURACION)" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"
