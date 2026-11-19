#!/bin/bash
# ==============================================================================
# LANOT - UNAM | AVHRR de METOP a GeoTIFF y vistas, con Polar2Grid v3.2
# ==============================================================================
#
# Level 1 de AVHRR (hrpt_M0x_*.l1b de AAPP) → GeoTIFF de datos + vistas.
#
# Sustituye a dos piezas de la cadena vieja, que hoy van en dos servidores:
#   - el polar2grid.sh de referencia/metop/metop2.sh (stratus), que deja los
#     GeoTIFF float32 de las cinco bandas en avhrr/level1 y avhrr/vistas, y de
#     ahí a /dataservice/noaa-metop;
#   - crea_vistas_metop.sh de LANOT_tools (kawak), que viste esos GeoTIFF: una
#     vista por banda, las térmicas con la escala invertida, y un RGB 1-2-3a.
# Aquí las dos cosas van juntas, como en run_polar2grid_l1.sh: Polar2Grid
# remuestrea UNA vez y lo visual sale de LANOT_tools. La decoración es la de las
# vistas de VIIRS, que es la de crea_vistas_metop.sh más la caja detrás de la
# fecha y el recorte al sur de 11° N.
#
# La rejilla es wgs84_geo_1000m y el método nearest, como en stratus, para que
# los GeoTIFF que se publiquen sean los mismos. Polar2Grid usaría ewa por
# omisión para AVHRR.
#
# La unidad de trabajo es el archivo hrpt: uno por pasada (AAPP_RUN_METOP lo
# nombra hrpt_<sat>_<AAAAMMDD>_<HHMM>_<órbita>.l1b).
#
# Uso:
#   ./run_polar2grid_avhrr.sh                  # el hrpt más reciente pendiente
#   ./run_polar2grid_avhrr.sh <hrpt.l1b>       # uno en concreto
#   ./run_polar2grid_avhrr.sh --force [hrpt]   # aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   AVHRR_L1_IN       Entrada (hrpt_*.l1b)  (def. /data/output/metop/level1/avhrr)
#   AVHRR_GEOTIFF     GeoTIFF               (def. /data/output/metop/geotiff/avhrr)
#   AVHRR_VISTAS      Vistas                (def. /data/output/metop/vistas/avhrr)
#   AVHRR_STATE_DIR   Marcadores .done      (def. /data/output/metop/state/polar2grid_avhrr)
#   AVHRR_CONTAINER   Imagen .sif           (def. …/polar2grid_v3.2-mapdrawer.sif)
#   AVHRR_GRID_CONFIG Rejillas propias      (def. <repo>/config/grid.yaml)
#   AVHRR_GRID        Rejilla               (def. wgs84_geo_1000m)
#   AVHRR_WORKERS     Hilos de P2G          (def. SLURM_CPUS_PER_TASK o 20)
#   AVHRR_COLORTABLES Paletas del host      (def. /usr/local/share/lanot/colortables)
#   AVHRR_LOG_BASE    Raíz de logs          (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_P2G="${AVHRR_CONTAINER:-/opt/containers/polar2grid_v3.2-mapdrawer.sif}"
HOST_L1="${AVHRR_L1_IN:-/data/output/metop/level1/avhrr}"
OUT_TIF="${AVHRR_GEOTIFF:-/data/output/metop/geotiff/avhrr}"
OUT_JPG="${AVHRR_VISTAS:-/data/output/metop/vistas/avhrr}"
STATE_DIR="${AVHRR_STATE_DIR:-/data/output/metop/state/polar2grid_avhrr}"
LOG_DIR="${AVHRR_LOG_BASE:-/var/log/lanot/polares}/polar2grid"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRID_CONFIG="${AVHRR_GRID_CONFIG:-$SCRIPT_DIR/../config/grid.yaml}"
GRID="${AVHRR_GRID:-wgs84_geo_1000m}"
WORKERS="${AVHRR_WORKERS:-${SLURM_CPUS_PER_TASK:-20}}"

COLORTABLES="${AVHRR_COLORTABLES:-/usr/local/share/lanot/colortables}"
BIND_CPT=()
[ -d "$COLORTABLES" ] && BIND_CPT=(--bind "$COLORTABLES:/usr/local/share/lanot/colortables:ro")

# La de run_polar2grid_l1.sh (ver ahí el porqué de --font-bg y --lat-south).
DECORACION=(
    --layer "COUNTRIES:yellow:0.0005"
    --layer "MEXSTATES:yellow:0.0005"
    --logo-pos 0
    --logo-size 0.2
    --font-size 0.025
    --timestamp-pos 1
    --font-color white
    --font-bg black
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
  $0                  El hrpt más reciente de $HOST_L1 sin marcador
  $0 <hrpt.l1b>       Uno en concreto
  $0 --force [hrpt]   Aunque ya tenga marcador

Opciones:
  -f, --force   Ignora el marcador
  -h, --help    Muestra esta ayuda
EOF
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
HRPT=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        -h|--help)  uso; exit 0 ;;
        -*)
            echo "ERROR: Opción desconocida: $1" >&2
            uso >&2
            exit 1
            ;;
        *)
            if [ -n "$HRPT" ]; then
                echo "ERROR: Solo se admite un hrpt por ejecución" >&2
                exit 1
            fi
            HRPT="$1"
            ;;
    esac
    shift
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')

# ==============================================================================
# SELECCIÓN
# ==============================================================================

if [ -n "$HRPT" ]; then
    if [ ! -f "$HRPT" ]; then
        echo "ERROR: Archivo no encontrado: $HRPT" >&2
        exit 1
    fi
    HRPT=$(realpath "$HRPT")
else
    if [ ! -d "$HOST_L1" ]; then
        echo "ERROR: Directorio de entrada no encontrado: $HOST_L1" >&2
        exit 1
    fi
    HRPT=""
    while IFS= read -r f; do
        if [ "$FORCE" -eq 1 ] || [ ! -f "$STATE_DIR/$(basename "$f").done" ]; then
            HRPT="$f"
            break
        fi
    done < <(find "$HOST_L1" -maxdepth 1 -type f -name 'hrpt_M0[13]_*.l1b' \
                  -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
    if [ -z "$HRPT" ]; then
        echo "No hay AVHRR pendiente en $HOST_L1."
        exit 0
    fi
fi

NOMBRE=$(basename "$HRPT")
case "$NOMBRE" in
    hrpt_M01_*) SATELITE=METOP-B ;;
    hrpt_M03_*) SATELITE=METOP-C ;;
    *)
        echo "ERROR: $NOMBRE no tiene la forma hrpt_M01_… o hrpt_M03_… de AAPP" >&2
        exit 1
        ;;
esac

echo "=== POLAR2GRID v3.2 | AVHRR | $SATELITE | $NOMBRE ==="

# ==============================================================================
# ¿YA ESTÁ?
# ==============================================================================
# Como en run_metop_l1.sh, el marcador tiene que ser más nuevo que la entrada:
# un hrpt reprocesado (run_metop_l1.sh --force) deja el mismo nombre.

MARKER="$STATE_DIR/$NOMBRE.done"

if [ -f "$MARKER" ] && [ "$MARKER" -nt "$HRPT" ] && [ "$FORCE" -eq 0 ]; then
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

if [ ! -f "$SIF_P2G" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_P2G" >&2
    exit 1
fi
if [ ! -f "$GRID_CONFIG" ]; then
    echo "ERROR: No se encontró la definición de rejillas: $GRID_CONFIG" >&2
    exit 1
fi
GRID_CONFIG=$(realpath "$GRID_CONFIG")

mkdir -p "$OUT_TIF" "$OUT_JPG" "$STATE_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/p2g_avhrr_${TIMESTAMP}_${NOMBRE%.l1b}.log"

# Lo de esta corrida se reconoce contra esta marca: los GeoTIFF de una pasada
# anterior del mismo satélite conviven en el mismo directorio.
REF_FILE=$(mktemp -t p2g_avhrr_ref_XXXXXX)
trap 'rm -f "$REF_FILE"' EXIT

BINDS=(
    "${BIND_CPT[@]}"
    --bind "$(dirname "$HRPT")":/input:ro
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
# Sin -p: los productos por omisión del lector son las seis bandas, y Polar2Grid
# entrega las que haya. De día AVHRR de METOP transmite 3a (1.6 µm) y de noche
# 3b (3.7 µm), así que una pasada trae cinco.

echo "  Rejilla: $GRID · hilos: $WORKERS" | tee -a "$LOG_FILE"
echo "--- polar2grid.sh ---" >> "$LOG_FILE"
CODIGO_P2G=0
en_contenedor_uno /bin/bash -c "cd /output_tif && polar2grid.sh -r avhrr_l1b_aapp -w geotiff --dtype float32 --no-enhance --method nearest --grid-configs /config/grid.yaml -g $GRID --num-workers $WORKERS -f /input/$NOMBRE" \
    || CODIGO_P2G=$?

# Polar2Grid deja su .log en el pwd; lo que dice ya quedó en LOG_FILE.
find "$OUT_TIF" -maxdepth 1 -name '*.log' -newer "$REF_FILE" -delete 2>/dev/null || true

mapfile -t TIFS < <(find "$OUT_TIF" -maxdepth 1 -name '*.tif' -newer "$REF_FILE" -printf '%f\n' | sort)

if [ "$CODIGO_P2G" -ne 0 ] || [ ${#TIFS[@]} -eq 0 ]; then
    echo "❌ ERROR: Polar2Grid (código $CODIGO_P2G) dejó ${#TIFS[@]} GeoTIFF. Ver $LOG_FILE" | tee -a "$LOG_FILE" >&2
    exit 1
fi

# ==============================================================================
# ETAPA 2: VISTAS (crea_vistas_metop.sh)
# ==============================================================================
# Una llamada por archivo, para leer el código de geotiff2view: 3 es "sin un
# píxel válido" —las visibles de una pasada nocturna—, que no es un fallo y no
# debe publicarse como imagen negra.

GENERADAS=0
VACIAS=0
FALLIDAS=0

vestir_uno() {   # entrada (una o tres, separadas por coma), extras...
    local entrada="$1"; shift
    local codigo=0
    en_contenedor_uno geotiff2view "$entrada" "$@" "${DECORACION[@]}" -o /output_jpg/ || codigo=$?
    case $codigo in
        0) GENERADAS=$((GENERADAS + 1)) ;;
        3) echo "  · sin datos válidos, sin vista: ${entrada##*/}" | tee -a "$LOG_FILE"
           VACIAS=$((VACIAS + 1)) ;;
        *) echo "  ⚠ no se pudo vestir: ${entrada##*/} (código $codigo)" | tee -a "$LOG_FILE"
           FALLIDAS=$((FALLIDAS + 1)) ;;
    esac
}

echo "--- vistas ---" >> "$LOG_FILE"
B1="" B2="" B3A=""
for t in "${TIFS[@]}"; do
    case "$t" in
        # Térmicas: invertidas, frío en blanco, como se mira el infrarrojo.
        *_band3b_*|*_band4_*|*_band5_*) vestir_uno "/output_tif/$t" -i ;;
        *_band1_*)  B1="$t";  vestir_uno "/output_tif/$t" ;;
        *_band2_*)  B2="$t";  vestir_uno "/output_tif/$t" ;;
        *_band3a_*) B3A="$t"; vestir_uno "/output_tif/$t" ;;
        *) echo "  · $t: banda que no se viste" >> "$LOG_FILE" ;;
    esac
done

# El RGB 1-2-3a, como el de kawak: geotiff2view apila los tres. Solo de día,
# cuando hay 3a; de noche ni las visibles tienen datos.
RGB="no (falta 3a)"
if [ -n "$B1" ] && [ -n "$B2" ] && [ -n "$B3A" ]; then
    antes=$GENERADAS
    vestir_uno "/output_tif/$B1,/output_tif/$B2,/output_tif/$B3A"
    [ "$GENERADAS" -gt "$antes" ] && RGB="sí" || RGB="no (ver log)"
fi

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

# ==============================================================================
# MARCADOR
# ==============================================================================
# Como en run_polar2grid_l1.sh, el éxito son los GeoTIFF: son lo que se publica.
# Una vista que falló no tumba la pasada, pero se cuenta.

{
    echo "renderizado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "satelite:    $SATELITE"
    echo "geotiff:     ${#TIFS[@]} (${TIFS[*]})"
    echo "vistas:      $GENERADAS generadas, $VACIAS sin datos, $FALLIDAS con error; RGB: $RGB"
    echo "duracion:    $DURACION"
    echo "log:         $LOG_FILE"
} > "$MARKER"

echo "✅ $NOMBRE: ${#TIFS[@]} GeoTIFF, $GENERADAS vistas ($VACIAS sin datos, $FALLIDAS con error; RGB: $RGB) en $DURACION" | tee -a "$LOG_FILE"
echo "   GeoTIFF: $OUT_TIF"  | tee -a "$LOG_FILE"
echo "   Vistas:  $OUT_JPG"  | tee -a "$LOG_FILE"
