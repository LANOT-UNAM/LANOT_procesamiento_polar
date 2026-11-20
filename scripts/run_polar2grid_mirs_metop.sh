#!/bin/bash
# ==============================================================================
# LANOT - UNAM | MiRS de METOP a GeoTIFF y vistas, con Polar2Grid v3.2
# ==============================================================================
#
# NPR-MIRS-IMG de AMSU-A + MHS (run_mirs_metop.sh) → GeoTIFF de datos + vistas.
#
# Es la misma sección de MiRS de run_polar2grid_edr.sh —rejilla de 5 km,
# paletas de rango fijo, la misma decoración y el mismo -s 1—, para que una
# vista de METOP y una de NOAA-20/21 se puedan poner lado a lado. Va aparte
# porque run_polar2grid_edr.sh es el renderizador de la PASADA de JPSS (su
# ventana sale de los SDR de VIIRS), y aquí la unidad es el archivo IMG de un
# crudo, como el hrpt en run_polar2grid_avhrr.sh. Las paletas se repiten aquí
# en dos líneas: si cambian allá, cambiar aquí (generar_catalogo.py --verificar
# compara las del catálogo contra las de run_polar2grid_edr.sh).
#
# Productos: lluvia, agua precipitable, agua líquida de nube, temperatura de
# piel y dos canales de dispersión por hielo, 89 y 157 GHz. Vista solo de
# lluvia y agua precipitable, como en JPSS. La de hielo convectivo de JPSS es a
# 165 GHz (ATMS); el equivalente de MHS es 157 GHz, que necesita su entrada en
# product_map de LANOT_tools antes de llevar vista: por ahora es dato.
#
# Uso:
#   ./run_polar2grid_mirs_metop.sh                 # el IMG más reciente sin marcador
#   ./run_polar2grid_mirs_metop.sh <IMG.nc>        # uno en concreto
#   ./run_polar2grid_mirs_metop.sh --force [IMG]   # aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   MIRS_METOP_IN       Entrada (IMG)         (def. /data/output/metop/level2/mirs)
#   MIRS_METOP_GEOTIFF  GeoTIFF               (def. /data/output/metop/geotiff/mirs)
#   MIRS_METOP_VISTAS   Vistas                (def. /data/output/metop/vistas/mirs)
#   MIRS_METOP_P2G_STATE Marcadores .done     (def. /data/output/metop/state/polar2grid_mirs)
#   MIRS_METOP_P2G_LOG  Raíz de logs          (def. /var/log/lanot/polares)
#   P2G_CONTAINER       Imagen .sif           (def. /opt/containers/polar2grid_v3.2-mapdrawer.sif)
#   P2G_GRID_CONFIG     Rejillas propias      (def. <repo>/config/grid.yaml)
#   P2G_GRID_5KM        Rejilla               (def. wgs84_geo_5km)
#   P2G_COLORTABLES     Paletas del host      (def. /usr/local/share/lanot/colortables)
#
# ==============================================================================

set -euo pipefail

SIF_P2G="${P2G_CONTAINER:-/opt/containers/polar2grid_v3.2-mapdrawer.sif}"

HOST_IN="${MIRS_METOP_IN:-/data/output/metop/level2/mirs}"
OUT_TIF="${MIRS_METOP_GEOTIFF:-/data/output/metop/geotiff/mirs}"
OUT_JPG="${MIRS_METOP_VISTAS:-/data/output/metop/vistas/mirs}"
STATE_DIR="${MIRS_METOP_P2G_STATE:-/data/output/metop/state/polar2grid_mirs}"
LOG_DIR="${MIRS_METOP_P2G_LOG:-/var/log/lanot/polares}/polar2grid"

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
GRID_CONFIG="${P2G_GRID_CONFIG:-$SCRIPT_DIR/../config/grid.yaml}"
GRID_5KM="${P2G_GRID_5KM:-wgs84_geo_5km}"

COLORTABLES="${P2G_COLORTABLES:-/usr/local/share/lanot/colortables}"
BIND_CPT=()
[ -d "$COLORTABLES" ] && BIND_CPT=(--bind "$COLORTABLES:/usr/local/share/lanot/colortables:ro")

# Las de MiRS en run_polar2grid_edr.sh (PALETAS). Las dos van con -b: ninguna
# está en CPT_CON_NODATA_PROPIO de allá.
PALETAS=(
    "rain_rate:mirs_rain_rate.cpt"
    "_tpw_:mirs_tpw.cpt"
)

# La de run_polar2grid_edr.sh, con el -s 1 que allá llevan los productos de 5 km
# (a la mitad, la barra de color no se lee).
DECORACION=(
    --layer "COUNTRIES:yellow:0.0005"
    --layer "MEXSTATES:yellow:0.0005"
    --logo-pos 0
    --logo-size 0.2
    --font-size 0.025
    --timestamp-pos 1
    --font-color white
    --font-bg black
    -j
    --lat-south 11
    -s 1
)

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0                El IMG más reciente de $HOST_IN sin marcador
  $0 <IMG.nc>       Uno en concreto
  $0 --force [IMG]  Aunque ya tenga marcador
EOF
}

formato_duracion() {
    local s="$1"
    if [ "$s" -ge 60 ]; then printf '%dm %ds' $((s / 60)) $((s % 60)); else printf '%ds' "$s"; fi
}

paleta_de() {
    local nombre="$1" par
    for par in "${PALETAS[@]}"; do
        if [[ "$nombre" == *"${par%%:*}"* ]]; then
            echo "${par#*:}"
            return 0
        fi
    done
    return 1
}

# ==============================================================================
# ARGUMENTOS Y SELECCIÓN
# ==============================================================================

FORCE=0
IMG=""
while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        -h|--help)  uso; exit 0 ;;
        -*) echo "ERROR: Opción desconocida: $1" >&2; uso >&2; exit 1 ;;
        *)
            [ -z "$IMG" ] || { echo "ERROR: Solo se admite un IMG por ejecución" >&2; exit 1; }
            IMG="$1"
            ;;
    esac
    shift
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')

if [ -n "$IMG" ]; then
    [ -f "$IMG" ] || { echo "ERROR: Archivo no encontrado: $IMG" >&2; exit 1; }
    IMG=$(realpath "$IMG")
else
    while IFS= read -r f; do
        if [ "$FORCE" -eq 1 ] || [ ! -f "$STATE_DIR/$(basename "$f").done" ]; then
            IMG="$f"; break
        fi
    done < <(find "$HOST_IN" -maxdepth 1 -type f -name 'NPR-MIRS-IMG_*_ma[13]_*.nc' \
                  -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
    if [ -z "$IMG" ]; then
        echo "No hay MiRS de METOP pendiente en $HOST_IN."
        exit 0
    fi
fi

cd / || exit 1

NOMBRE=$(basename "$IMG")
case "$NOMBRE" in
    NPR-MIRS-IMG_*_ma1_*) SATELITE=METOP-B ;;
    NPR-MIRS-IMG_*_ma3_*) SATELITE=METOP-C ;;
    *) echo "ERROR: $NOMBRE no es un NPR-MIRS-IMG de METOP-B (ma1) o METOP-C (ma3)" >&2; exit 1 ;;
esac

echo "=== POLAR2GRID v3.2 | MiRS | $SATELITE | $NOMBRE ==="

MARKER="$STATE_DIR/$NOMBRE.done"
if [ -f "$MARKER" ] && [ "$MARKER" -nt "$IMG" ] && [ "$FORCE" -eq 0 ]; then
    echo ""
    echo "ℹ  $NOMBRE ya fue renderizado:"
    sed 's/^/   /' "$MARKER"
    echo ""
    echo "   No hay nada que hacer. Usa --force para repetirlo."
    exit 0
fi

# ==============================================================================
# VALIDACIÓN DEL AMBIENTE
# ==============================================================================

[ -f "$SIF_P2G" ] || { echo "ERROR: Contenedor no encontrado: $SIF_P2G" >&2; exit 1; }
[ -f "$GRID_CONFIG" ] || { echo "ERROR: No se encontró la definición de rejillas: $GRID_CONFIG" >&2; exit 1; }
GRID_CONFIG=$(realpath "$GRID_CONFIG")

mkdir -p "$OUT_TIF" "$OUT_JPG" "$STATE_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/p2g_mirs_metop_${TIMESTAMP}_${NOMBRE%.nc}.log"

REF_FILE=$(mktemp -t p2g_mirs_metop_ref_XXXXXX)
trap 'rm -f "$REF_FILE"' EXIT

BINDS=(
    "${BIND_CPT[@]}"
    --bind "$(dirname "$IMG")":/input:ro
    --bind "$GRID_CONFIG":/config/grid.yaml:ro
    --bind "$OUT_TIF":/output_tif
    --bind "$OUT_JPG":/output_jpg
)

en_contenedor_uno() {
    local codigo=0
    apptainer exec "${BINDS[@]}" "$SIF_P2G" "$@" >> "$LOG_FILE" 2>&1 || codigo=$?
    return $codigo
}

# ==============================================================================
# ETAPA 1: REMUESTREO
# ==============================================================================
# -p obligatorio, como en JPSS: por omisión saldrían también nieve, hielo marino
# y tamaño de grano. Sin --method: el ewa del lector, como en JPSS.

MIRS_DATOS="rain_rate tpw clw tskin btemp_89v1 btemp_157v"

echo "  Rejilla: $GRID_5KM" | tee -a "$LOG_FILE"
echo "--- polar2grid.sh ---" >> "$LOG_FILE"
CODIGO_P2G=0
en_contenedor_uno /bin/bash -c "cd /output_tif && polar2grid.sh -r mirs -w geotiff -p $MIRS_DATOS --grid-configs /config/grid.yaml -g $GRID_5KM --dtype float32 --no-enhance -f /input/$NOMBRE" \
    || CODIGO_P2G=$?

find "$OUT_TIF" -maxdepth 1 -name '*.log' -newer "$REF_FILE" -delete 2>/dev/null || true
mapfile -t TIFS < <(find "$OUT_TIF" -maxdepth 1 -name '*.tif' -newer "$REF_FILE" -printf '%f\n' | sort)

if [ "$CODIGO_P2G" -ne 0 ] || [ ${#TIFS[@]} -eq 0 ]; then
    echo "❌ ERROR: Polar2Grid (código $CODIGO_P2G) dejó ${#TIFS[@]} GeoTIFF. Ver $LOG_FILE" | tee -a "$LOG_FILE" >&2
    exit 1
fi

# ==============================================================================
# ETAPA 2: VISTAS
# ==============================================================================
# Una llamada por archivo para leer el código de geotiff2view: 3 es "sin un
# píxel válido" —una pasada sin lluvia sobre la rejilla—, que no es fallo y no
# se publica como imagen vacía.

GENERADAS=0
VACIAS=0
FALLIDAS=0
echo "--- vistas ---" >> "$LOG_FILE"
for t in "${TIFS[@]}"; do
    cpt=$(paleta_de "$t") || continue
    codigo=0
    en_contenedor_uno geotiff2view "/output_tif/$t" -b -p "$cpt" "${DECORACION[@]}" \
        -o "/output_jpg/${t%.tif}.jpg" || codigo=$?
    case $codigo in
        0) GENERADAS=$((GENERADAS + 1)) ;;
        3) echo "  · sin datos válidos, sin vista: $t" | tee -a "$LOG_FILE"; VACIAS=$((VACIAS + 1)) ;;
        *) echo "  ⚠ no se pudo vestir: $t (código $codigo)" | tee -a "$LOG_FILE"; FALLIDAS=$((FALLIDAS + 1)) ;;
    esac
done

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

# El éxito son los GeoTIFF, como en run_polar2grid_avhrr.sh; una vista fallida
# no tumba la pasada, pero se cuenta.
{
    echo "renderizado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "satelite:    $SATELITE"
    echo "geotiff:     ${#TIFS[@]} (${TIFS[*]})"
    echo "vistas:      $GENERADAS generadas, $VACIAS sin datos, $FALLIDAS con error"
    echo "duracion:    $DURACION"
    echo "log:         $LOG_FILE"
} > "$MARKER"

echo "✅ $NOMBRE: ${#TIFS[@]} GeoTIFF, $GENERADAS vistas ($VACIAS sin datos, $FALLIDAS con error) en $DURACION" | tee -a "$LOG_FILE"
echo "   GeoTIFF: $OUT_TIF" | tee -a "$LOG_FILE"
echo "   Vistas:  $OUT_JPG" | tee -a "$LOG_FILE"
