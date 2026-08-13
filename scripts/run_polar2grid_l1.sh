#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Visualización de Level 1 (VIIRS) con Polar2Grid v3.2
# ==============================================================================
#
# Level 1 / SDR → GeoTIFF de datos + vistas decoradas (DNB y RGB)
#
# Sustituye a referencia/cspp_1_ptog.sh, que es lo que corre hoy en el servidor
# viejo. Sin argumentos toma la PASADA más reciente del directorio de SDR y, si
# ya fue renderizada con éxito, avisa y no hace nada. Una pasada se identifica
# por satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
#
# Regla de la cadena: Polar2Grid remuestrea UNA vez por conjunto de bandas —que
# es la parte cara— y entrega GeoTIFF; lo visual sale de LANOT_tools. De ahí las
# cuatro llamadas y no más:
#
#   1. bandas M + ángulos + radiancias   float32   wgs84_geo_750m
#   2. bandas I + ángulos + radiancias   float32   wgs84_geo_375m
#   3. DNB (cinco algoritmos) + ángulos  float32   wgs84_geo_750m
#   4. RGB true_color / false_color      8 bits    wgs84_geo_750m
#
# El script viejo hace cinco llamadas porque remuestrea el DNB dos veces: una en
# float32 y otra realzada a 8 bits. No hace falta: adaptive_dnb, dynamic_dnb,
# hncc_dnb e histogram_dnb son productos que CALCULA Satpy, así que el algoritmo
# ya está aplicado dentro de los valores float32 y lo único que agrega la
# segunda pasada es el escalado a 8 bits, que es justo lo que hace geotiff2view.
#
# Los RGB sí se componen en Polar2Grid: geotiff2view sabe apilar tres GeoTIFF,
# pero sin corrección de Rayleigh ni afilado por razón con I01, y eso se nota en
# el producto más visible de todos. Como P2G ya los entrega como imagen, solo
# hay que vestirlos, y de eso se encarga mapdrawer sin recolorear.
#
# Los SDR se enlazan con su nombre original: ver la nota del staging sobre el
# sufijo _cspp_dev, que Satpy EXIGE y no estorba.
#
# Uso:
#   ./run_polar2grid_l1.sh            # la pasada más reciente pendiente
#   ./run_polar2grid_l1.sh --force    # re-renderiza aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   L1G_SDR_IN      Entrada Level 1   (def. /data/output/jpss/level1/viirs)
#   L1G_GEOTIFF     Raíz de GeoTIFF   (def. /data/output/jpss/geotiff)
#   L1G_VISTAS      Raíz de vistas    (def. /data/output/jpss/vistas)
#   L1G_STATE_DIR   Marcadores .done  (def. …/state/polar2grid_l1)
#   L1G_CONTAINER   Imagen .sif       (def. …/polar2grid_v3.2-mapdrawer.sif)
#   L1G_GRID_CONFIG Rejillas propias  (def. <repo>/config/grid.yaml)
#   L1G_GRID_750    Rejilla M/DNB/RGB (def. wgs84_geo_750m)
#   L1G_GRID_375    Rejilla bandas I  (def. wgs84_geo_375m)
#   L1G_WORKERS     Hilos de P2G      (def. SLURM_CPUS_PER_TASK o 20)
#   L1G_WORK_BASE   Raíz de staging   (def. /data/tmp)
#   L1G_LOG_BASE    Raíz de logs      (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

# La imagen tiene que ser la variante -mapdrawer: la simple trae Polar2Grid pero
# no geotiff2view ni mapdrawer, así que no podría decorar nada.
SIF_P2G="${L1G_CONTAINER:-/opt/containers/polar2grid_v3.2-mapdrawer.sif}"

HOST_SDR_IN="${L1G_SDR_IN:-/data/output/jpss/level1/viirs}"

# Los datos (GeoTIFF) y las vistas (JPG) van en árboles distintos
GEOTIFF="${L1G_GEOTIFF:-/data/output/jpss/geotiff}"
OUT_M="$GEOTIFF/m_bands"
OUT_I="$GEOTIFF/i_bands"
OUT_DNB="$GEOTIFF/dnb"
OUT_RGB="$GEOTIFF/rgb"

VISTAS="${L1G_VISTAS:-/data/output/jpss/vistas}"
VISTA_DNB="$VISTAS/dnb"
VISTA_RGB="$VISTAS/rgb"

# El contenedor trae la rejilla de fábrica, no las nuestras: hay que pasarle
# config/grid.yaml con --grid-configs o remuestrearía a una rejilla dinámica
# distinta en cada pasada.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRID_CONFIG="${L1G_GRID_CONFIG:-$SCRIPT_DIR/../config/grid.yaml}"
GRID_750="${L1G_GRID_750:-wgs84_geo_750m}"
GRID_375="${L1G_GRID_375:-wgs84_geo_375m}"

WORKERS="${L1G_WORKERS:-${SLURM_CPUS_PER_TASK:-20}}"

STATE_DIR="${L1G_STATE_DIR:-/data/output/jpss/state/polar2grid_l1}"
WORK_BASE="${L1G_WORK_BASE:-/data/tmp}"
LOG_DIR="${L1G_LOG_BASE:-/var/log/lanot/polares}/polar2grid"

JOB_ID="${SLURM_JOB_ID:-$$}"

# Argumentos de decoración validados en producción (LANOT_tools,
# crea_vistas_viirs.sh:96-118)
DECORACION=(
    --layer "COUNTRIES:yellow:0.0005"
    --layer "MEXSTATES:yellow:0.0005"
    --logo-pos 0
    --logo-size 0.2
    --font-size 0.025
    --timestamp-pos 1
    --font-color white
    -s 0.5
    -j
    --lat-south 11
)

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
HOST_WORK="${WORK_BASE}/p2g_l1_work_${JOB_ID}"

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

echo "=== POLAR2GRID v3.2 | Level 1 | pasada $CLAVE ==="

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

# ==============================================================================
# VALIDACIÓN DEL AMBIENTE
# ==============================================================================

if [ ! -f "$SIF_P2G" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_P2G" >&2
    exit 1
fi

if [ ! -f "$GRID_CONFIG" ]; then
    echo "ERROR: No se encontró la definición de rejillas: $GRID_CONFIG" >&2
    echo "       Es config/grid.yaml del repositorio; sin ella Polar2Grid usaría" >&2
    echo "       una rejilla dinámica distinta en cada pasada." >&2
    exit 1
fi
GRID_CONFIG=$(realpath "$GRID_CONFIG")

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================

STAGING_SDR="${HOST_WORK}/sdr_links"

mkdir -p "$STAGING_SDR" \
         "$OUT_M" "$OUT_I" "$OUT_DNB" "$OUT_RGB" \
         "$VISTA_DNB" "$VISTA_RGB" \
         "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$HOST_WORK"' EXIT

# SDR de la pasada, CON su nombre original. El patrón de Satpy para viirs_sdr
# termina en _{source:8s}.h5, un campo obligatorio de 8 caracteres que es
# justamente 'cspp_dev': quitarlo no ayuda al match, lo impide. Verificado en
# tahan el 2026-08-13, cuando el lector rechazó los 28 archivos con
# "No filenames found for reader: viirs_sdr".
for f in "$HOST_SDR_IN"/*_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5; do
    [ -e "$f" ] || continue
    ln -sf "$f" "$STAGING_SDR/"
done

SDR_COUNT=$(find "$STAGING_SDR" -name '*.h5' | wc -l)

if [ "$SDR_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR de la pasada $CLAVE" >&2
    exit 1
fi

LOG_FILE="$LOG_DIR/p2g_l1_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR:      $SDR_COUNT archivos"        | tee -a "$LOG_FILE"
echo "  Rejillas: $GRID_750 / $GRID_375"      | tee -a "$LOG_FILE"
echo "  Hilos:    $WORKERS"                   | tee -a "$LOG_FILE"

REF_FILE=$(mktemp -t p2g_l1_ref_XXXXXX)
trap 'rm -rf "$HOST_WORK" "$REF_FILE"' EXIT

# ==============================================================================
# ETAPA 1: REMUESTREO A LA REJILLA
# ==============================================================================
# Cada bloque es independiente: se registra su código pero no aborta a los demás.

en_contenedor() {
    local etiqueta="$1"; shift
    local codigo=0

    echo "--- $etiqueta ---" >> "$LOG_FILE"
    apptainer exec \
        --bind "$STAGING_SDR:/input_sdr" \
        --bind "$HOST_SDR_IN:$HOST_SDR_IN" \
        --bind "$GRID_CONFIG:/config/grid.yaml:ro" \
        --bind "$OUT_M:/output_m" \
        --bind "$OUT_I:/output_i" \
        --bind "$OUT_DNB:/output_dnb" \
        --bind "$OUT_RGB:/output_rgb" \
        --bind "$VISTA_DNB:/vista_dnb" \
        --bind "$VISTA_RGB:/vista_rgb" \
        --bind "$HOST_WORK:/work" \
        "$SIF_P2G" /bin/bash -c "$*" >> "$LOG_FILE" 2>&1 || codigo=$?

    if [ $codigo -ne 0 ]; then
        echo "  ⚠ $etiqueta falló (código $codigo)" | tee -a "$LOG_FILE"
    fi

    return 0
}

# --no-enhance y float32 porque lo que se guarda son DATOS; el realce visual
# viene después, en la etapa 2.
COMUN="--grid-configs /config/grid.yaml --num-workers $WORKERS --method nearest"
DATOS="$COMUN --dtype float32 --no-enhance"

en_contenedor "Bandas M (750 m)" \
    "cd /output_m && polar2grid.sh -r viirs_sdr -w geotiff --m-bands --m-angle-products --m-rad-products $DATOS -g $GRID_750 -f /input_sdr/*.h5"

en_contenedor "Bandas I (375 m)" \
    "cd /output_i && polar2grid.sh -r viirs_sdr -w geotiff --i-bands --i-angle-products --i-rad-products $DATOS -g $GRID_375 -f /input_sdr/*.h5"

# Los cinco algoritmos DNB en una sola pasada: dynamic_dnb_saturation e
# histogram_dnb solo existían en la segunda llamada del script viejo.
en_contenedor "Day/Night Band (750 m)" \
    "cd /output_dnb && polar2grid.sh -r viirs_sdr -w geotiff -p adaptive_dnb dynamic_dnb dynamic_dnb_saturation histogram_dnb hncc_dnb --dnb-angle-products $DATOS -g $GRID_750 -f /input_sdr/*.h5"

# El RGB sale ya como imagen de 8 bits: aquí no van --dtype ni --no-enhance,
# porque el realce es parte de la composición de Satpy.
en_contenedor "RGB true_color / false_color (750 m)" \
    "cd /output_rgb && polar2grid.sh -r viirs_sdr -w geotiff -p true_color false_color $COMUN -g $GRID_750 -f /input_sdr/*.h5"

# ==============================================================================
# ETAPA 2: VISTAS DECORADAS
# ==============================================================================
# La herramienta depende de lo que entregó Polar2Grid: geotiff2view para los
# GeoTIFF de datos (escala a 8 bits y decora), mapdrawer para los que ya son
# imagen (solo los viste).

# $5 es un ERE opcional: solo se viste lo que haga match. Sirve para dejar
# fuera los productos que son datos y no imágenes.
ordenes_de() {
    local dir_tif="$1" montaje_tif="$2" montaje_img="$3" herramienta="$4" filtro="${5:-.}"
    local tif nombre

    while IFS= read -r tif; do
        nombre=$(basename "$tif")
        echo "$herramienta '$montaje_tif/$nombre' ${DECORACION[*]} -o '$montaje_img/${nombre%.*}.jpg'"
    done < <(find "$dir_tif" -maxdepth 1 -name '*.tif' -newer "$REF_FILE" 2>/dev/null \
                  | grep -E "$filtro" | sort)
}

# El DNB va sin -p: es una imagen en escala de grises, no lleva paleta. El -b
# pinta de color de fondo los NoData en vez de dejarlos transparentes.
#
# Solo se visten los cinco algoritmos. La llamada pide además
# --dnb-angle-products, que son ángulos solares y lunares: datos útiles como
# GeoTIFF, pero no imágenes que tenga sentido decorar con logo y timestamp
# (verificado en tahan el 2026-08-13, cuando salieron 10 vistas en vez de 5).
DNB_VISTAS='adaptive_dnb|dynamic_dnb|histogram_dnb|hncc_dnb'
ORDENES_DNB=$(ordenes_de "$OUT_DNB" /output_dnb /vista_dnb "geotiff2view -b" "$DNB_VISTAS")
if [ -n "$ORDENES_DNB" ]; then
    en_contenedor "Vistas de DNB" "$ORDENES_DNB"
else
    echo "  ⚠ Sin GeoTIFF de DNB que vestir" | tee -a "$LOG_FILE"
fi

# El RGB ya viene realzado por Satpy: mapdrawer no recolorea, solo decora.
ORDENES_RGB=$(ordenes_de "$OUT_RGB" /output_rgb /vista_rgb "mapdrawer")
if [ -n "$ORDENES_RGB" ]; then
    en_contenedor "Vistas de RGB" "$ORDENES_RGB"
else
    echo "  ⚠ Sin GeoTIFF de RGB que vestir" | tee -a "$LOG_FILE"
fi

# ==============================================================================
# VERIFICACIÓN
# ==============================================================================

contar_nuevos() {
    find "$1" -maxdepth 1 -name "$2" -newer "$REF_FILE" 2>/dev/null | wc -l
}

TIF_M=$(contar_nuevos   "$OUT_M"      '*.tif')
TIF_I=$(contar_nuevos   "$OUT_I"      '*.tif')
TIF_DNB=$(contar_nuevos "$OUT_DNB"    '*.tif')
TIF_RGB=$(contar_nuevos "$OUT_RGB"    '*.tif')
JPG_DNB=$(contar_nuevos "$VISTA_DNB"  '*.jpg')
JPG_RGB=$(contar_nuevos "$VISTA_RGB"  '*.jpg')

TIF_TOTAL=$((TIF_M + TIF_I + TIF_DNB + TIF_RGB))
JPG_TOTAL=$((JPG_DNB + JPG_RGB))

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

# El criterio de éxito son los GeoTIFF: son el producto que se publica. Una
# pasada con datos y sin vistas está bien procesada; una sin datos, no.
if [ "$TIF_TOTAL" -eq 0 ]; then
    echo "❌ ERROR: Ningún renderizado produjo GeoTIFF." | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                   | tee -a "$LOG_FILE"
    exit 1
fi

{
    echo "renderizado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:      $CLAVE"
    echo "bandas M:    $TIF_M geotiff"
    echo "bandas I:    $TIF_I geotiff"
    echo "dnb:         $TIF_DNB geotiff, $JPG_DNB vistas"
    echo "rgb:         $TIF_RGB geotiff, $JPG_RGB vistas"
    echo "duracion:    $DURACION"
    echo "log:         $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: pasada $CLAVE — $TIF_TOTAL geotiff (M $TIF_M, I $TIF_I, dnb $TIF_DNB, rgb $TIF_RGB) y $JPG_TOTAL vistas (dnb $JPG_DNB, rgb $JPG_RGB) en $DURACION" | tee -a "$LOG_FILE"
echo "   GeoTIFF:  $GEOTIFF"  | tee -a "$LOG_FILE"
echo "   Vistas:   $VISTAS"   | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER"   | tee -a "$LOG_FILE"
