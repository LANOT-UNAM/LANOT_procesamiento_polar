#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Visualización de productos Nivel 2 con Polar2Grid v3.2
# ==============================================================================
#
# Level 2 (atmosphere, LSR) + Level 1 (DNB) → GeoTIFF
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue renderizada con éxito, avisa y no hace nada. Una pasada se
# identifica por satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
#
# Se generan tres conjuntos de vistas, cada uno independiente: si uno falla, se
# reporta y los otros siguen. Basta con que alguno produzca imágenes para dar la
# pasada por renderizada.
#
# Satpy es sensible a los nombres: los SDR se enlazan quitándoles el sufijo
# _cspp_dev, que impide el match de sus expresiones regulares.
#
# Uso:
#   ./run_polar2grid_edr.sh            # la pasada más reciente pendiente
#   ./run_polar2grid_edr.sh --force    # re-renderiza aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   P2G_SDR_IN     Entrada Level 1   (def. /data/output/jpss/level1/viirs)
#   P2G_EDR_IN     Entrada atmosphere(def. /data/output/jpss/level2/atmosphere)
#   P2G_LSR_IN     Entrada LSR       (def. /data/output/jpss/level2/lsr)
#   P2G_VISTAS     Raíz de vistas    (def. /data/output/jpss/vistas)
#   P2G_STATE_DIR  Marcadores .done  (def. /data/output/jpss/state/polar2grid)
#   P2G_CONTAINER  Imagen .sif       (def. /opt/containers/polar2grid_v3.2.sif)
#   P2G_WORK_BASE  Raíz de staging   (def. /data/output/jpss/tmp)
#   P2G_LOG_BASE   Raíz de logs      (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_P2G="${P2G_CONTAINER:-/opt/containers/polar2grid_v3.2.sif}"

HOST_SDR_IN="${P2G_SDR_IN:-/data/output/jpss/level1/viirs}"
HOST_EDR_IN="${P2G_EDR_IN:-/data/output/jpss/level2/atmosphere}"
HOST_LSR_IN="${P2G_LSR_IN:-/data/output/jpss/level2/lsr}"

VISTAS="${P2G_VISTAS:-/data/output/jpss/vistas}"
HOST_IMG_OUT="$VISTAS/atmos"
HOST_LSR_IMG_OUT="$VISTAS/lsr"
HOST_DNB_IMG_OUT="$VISTAS/dnb"

STATE_DIR="${P2G_STATE_DIR:-/data/output/jpss/state/polar2grid}"
WORK_BASE="${P2G_WORK_BASE:-/data/output/jpss/tmp}"
LOG_DIR="${P2G_LOG_BASE:-/var/log/lanot/polares}/polar2grid"

JOB_ID="${SLURM_JOB_ID:-$$}"

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0             Renderiza la pasada más reciente de $HOST_SDR_IN
  $0 --force     Re-renderiza aunque ya exista el marcador

Opciones:
  -f, --force   Ignora el marcador de renderizado
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

# Enlaza en $1 los productos de $2 que corresponden a los gránulos de la pasada.
# Los .nc de Nivel 2 no llevan órbita: se emparejan por el sello temporal, que
# concatena fecha y hora de inicio del gránulo (GMTCO d20260811 + t1947330 ->
# s202608111947330). Imprime cuántos enlazó.
enlazar_por_granulo() {
    local destino="$1" origen="$2" patron="$3" enlazados=0 g nombre fecha tiempo sello

    for g in "$STAGING_SDR"/GMTCO_*.h5; do
        [ -e "$g" ] || continue
        nombre=$(basename "$g")
        IFS='_' read -r _ _ fecha tiempo _ <<< "$nombre"
        sello="s${fecha#d}${tiempo#t}"

        if compgen -G "$origen/${patron}*${sello}*.nc" > /dev/null; then
            ln -sf "$origen"/"${patron}"*"${sello}"*.nc "$destino"/
            enlazados=$((enlazados + 1))
        fi
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
HOST_WORK="${WORK_BASE}/p2g_work_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$HOST_SDR_IN" ]; then
    echo "ERROR: Directorio de SDR no encontrado: $HOST_SDR_IN" >&2
    exit 1
fi

ULTIMO_GMTCO=$(find "$HOST_SDR_IN" -maxdepth 1 -name 'GMTCO*.h5' \
                    -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$ULTIMO_GMTCO" ]; then
    echo "No hay SDR que renderizar en $HOST_SDR_IN (no se ven archivos GMTCO*)."
    exit 0
fi

if ! CLAVE=$(clave_de_pasada "$ULTIMO_GMTCO"); then
    echo "ERROR: No se pudo derivar la pasada del nombre: $(basename "$ULTIMO_GMTCO")" >&2
    exit 1
fi

IFS='_' read -r SAT FECHA ORBITA <<< "$CLAVE"

echo "=== POLAR2GRID v3.2 | pasada $CLAVE ==="

# ==============================================================================
# ¿YA FUE RENDERIZADA?
# ==============================================================================

MARKER="${STATE_DIR}/${CLAVE}.done"

if [ -f "$MARKER" ] && [ "$FORCE" -eq 0 ]; then
    echo ""
    echo "ℹ  La pasada $CLAVE ya fue renderizada:"
    while IFS= read -r linea; do
        echo "   $linea"
    done < "$MARKER"
    echo ""
    echo "   No hay nada que hacer. Usa --force para re-renderizarla."
    exit 0
fi

if [ -f "$MARKER" ]; then
    echo "--force: se re-renderiza a pesar del marcador existente"
fi

if [ ! -f "$SIF_P2G" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_P2G" >&2
    exit 1
fi

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================

STAGING_SDR="${HOST_WORK}/sdr_links"
STAGING_EDR="${HOST_WORK}/edr_links"
STAGING_LSR="${HOST_WORK}/lsr_links"

mkdir -p "$STAGING_SDR" "$STAGING_EDR" "$STAGING_LSR" \
         "$HOST_IMG_OUT" "$HOST_LSR_IMG_OUT" "$HOST_DNB_IMG_OUT" \
         "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$HOST_WORK"' EXIT

# SDR de la pasada, sin el sufijo _cspp_dev que confunde a Satpy
for f in "$HOST_SDR_IN"/*_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5; do
    [ -e "$f" ] || continue
    ln -sf "$f" "$STAGING_SDR/$(basename "$f" | sed 's/_cspp_dev//')"
done

SDR_COUNT=$(find "$STAGING_SDR" -name '*.h5' | wc -l)

if [ "$SDR_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR de la pasada $CLAVE" >&2
    exit 1
fi

EDR_COUNT=0
LSR_COUNT=0
[ -d "$HOST_EDR_IN" ] && EDR_COUNT=$(enlazar_por_granulo "$STAGING_EDR" "$HOST_EDR_IN" "JRR-")
[ -d "$HOST_LSR_IN" ] && LSR_COUNT=$(enlazar_por_granulo "$STAGING_LSR" "$HOST_LSR_IN" "SurfRefl_")

LOG_FILE="$LOG_DIR/p2g_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR:      $SDR_COUNT archivos"                  | tee -a "$LOG_FILE"
echo "  ATMOS:    $EDR_COUNT gránulos con productos"    | tee -a "$LOG_FILE"
echo "  LSR:      $LSR_COUNT gránulos con productos"    | tee -a "$LOG_FILE"

REF_FILE=$(mktemp -t p2g_ref_XXXXXX)
trap 'rm -rf "$HOST_WORK" "$REF_FILE"' EXIT

# ==============================================================================
# RENDERIZADO
# ==============================================================================
# Cada bloque es independiente: se registra su código pero no aborta a los demás.

renderizar() {
    local etiqueta="$1"; shift
    local codigo=0

    echo "--- $etiqueta ---" >> "$LOG_FILE"
    apptainer exec \
        --bind "$STAGING_SDR:/input_sdr" \
        --bind "$STAGING_EDR:/input_edr" \
        --bind "$STAGING_LSR:/input_lsr" \
        --bind "$HOST_SDR_IN:$HOST_SDR_IN" \
        --bind "$HOST_EDR_IN:$HOST_EDR_IN" \
        --bind "$HOST_LSR_IN:$HOST_LSR_IN" \
        --bind "$HOST_IMG_OUT:/output_img" \
        --bind "$HOST_LSR_IMG_OUT:/output_lsr_img" \
        --bind "$HOST_DNB_IMG_OUT:/output_dnb_img" \
        --bind "$HOST_WORK:/work" \
        "$SIF_P2G" /bin/bash -c "$*" >> "$LOG_FILE" 2>&1 || codigo=$?

    if [ $codigo -ne 0 ]; then
        echo "  ⚠ $etiqueta falló (código $codigo)" | tee -a "$LOG_FILE"
    fi

    return 0
}

if [ "$EDR_COUNT" -gt 0 ]; then
    renderizar "Productos atmosféricos (EDR)" \
        "cd /output_img && polar2grid.sh -v -r viirs_edr -w geotiff -f /input_edr/JRR-*.nc /input_sdr/GMTCO*.h5"
else
    echo "  ⚠ Sin productos de ATMOS para esta pasada: se omite ese renderizado" | tee -a "$LOG_FILE"
fi

if [ "$LSR_COUNT" -gt 0 ]; then
    # Los SurfRefl traen su propia geolocalización, no necesitan GMTCO
    renderizar "Productos de superficie (LSR)" \
        "cd /output_lsr_img && polar2grid.sh -v -r viirs_edr -w geotiff -f /input_lsr/SurfRefl_*.nc"
else
    echo "  ⚠ Sin productos de LSR para esta pasada: se omite ese renderizado" | tee -a "$LOG_FILE"
fi

renderizar "Day/Night Band" \
    "cd /output_dnb_img && polar2grid.sh -v -r viirs_sdr -w geotiff -p dynamic_dnb hncc_dnb -f /input_sdr/SVDNB_*.h5 /input_sdr/GDNBO_*.h5"

# ==============================================================================
# VERIFICACIÓN
# ==============================================================================

TIF_ATMOS=$(find "$HOST_IMG_OUT"     -maxdepth 1 -name '*.tif' -newer "$REF_FILE" 2>/dev/null | wc -l)
TIF_LSR=$(find   "$HOST_LSR_IMG_OUT" -maxdepth 1 -name '*.tif' -newer "$REF_FILE" 2>/dev/null | wc -l)
TIF_DNB=$(find   "$HOST_DNB_IMG_OUT" -maxdepth 1 -name '*.tif' -newer "$REF_FILE" 2>/dev/null | wc -l)
TIF_TOTAL=$((TIF_ATMOS + TIF_LSR + TIF_DNB))

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ "$TIF_TOTAL" -eq 0 ]; then
    echo "❌ ERROR: Ningún renderizado produjo imágenes." | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                    | tee -a "$LOG_FILE"
    exit 1
fi

{
    echo "renderizado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:      $CLAVE"
    echo "atmos:       $TIF_ATMOS imágenes"
    echo "lsr:         $TIF_LSR imágenes"
    echo "dnb:         $TIF_DNB imágenes"
    echo "duracion:    $DURACION"
    echo "log:         $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: $TIF_TOTAL imágenes de la pasada $CLAVE (atmos $TIF_ATMOS, lsr $TIF_LSR, dnb $TIF_DNB) en $DURACION" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"
