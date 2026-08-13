#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Visualización de productos Nivel 2 con Polar2Grid v3.2
# ==============================================================================
#
# Level 2 (atmosphere, LSR) → GeoTIFF de datos + vistas decoradas
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue renderizada con éxito, avisa y no hace nada. Una pasada se
# identifica por satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
#
# Cada conjunto (ATMOS, LSR) es independiente: si uno falla, se reporta y el
# otro sigue. Basta con que alguno produzca imágenes para dar la pasada por
# renderizada.
#
# Dos etapas por conjunto, según la regla de la cadena: Polar2Grid remuestrea
# UNA vez (swath → rejilla) y entrega GeoTIFF de datos; lo visual sale de
# LANOT_tools. Aquí los productos llegan sin paleta, así que la vista la hace
# geotiff2view recoloreando con un CPT. El Level 1 (bandas, DNB, RGB) está en
# run_polar2grid_l1.sh.
#
# Los SDR se enlazan con su nombre original: ver la nota del staging sobre el
# sufijo _cspp_dev, que Satpy EXIGE y no estorba.
#
# Uso:
#   ./run_polar2grid_edr.sh            # la pasada más reciente pendiente
#   ./run_polar2grid_edr.sh --force    # re-renderiza aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   P2G_SDR_IN      Entrada Level 1   (def. /data/output/jpss/level1/viirs)
#   P2G_EDR_IN      Entrada atmosphere(def. /data/output/jpss/level2/atmosphere)
#   P2G_LSR_IN      Entrada LSR       (def. /data/output/jpss/level2/lsr)
#   P2G_ACSPO_IN    Entrada ACSPO/SST (def. /data/output/jpss/level2/acspo)
#   P2G_GEOTIFF     Raíz de GeoTIFF   (def. /data/output/jpss/geotiff)
#   P2G_VISTAS      Raíz de vistas    (def. /data/output/jpss/vistas)
#   P2G_STATE_DIR   Marcadores .done  (def. /data/output/jpss/state/polar2grid)
#   P2G_CONTAINER   Imagen .sif       (def. …/polar2grid_v3.2-mapdrawer.sif)
#   P2G_GRID_CONFIG Rejillas propias  (def. <repo>/config/grid.yaml)
#   P2G_GRID        Rejilla a usar    (def. wgs84_geo_750m)
#   P2G_WORK_BASE   Raíz de staging   (def. /data/tmp)
#   P2G_LOG_BASE    Raíz de logs      (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

# La imagen tiene que ser la variante -mapdrawer: la simple trae Polar2Grid pero
# no geotiff2view ni mapdrawer, así que no podría decorar nada.
SIF_P2G="${P2G_CONTAINER:-/opt/containers/polar2grid_v3.2-mapdrawer.sif}"

HOST_SDR_IN="${P2G_SDR_IN:-/data/output/jpss/level1/viirs}"
HOST_EDR_IN="${P2G_EDR_IN:-/data/output/jpss/level2/atmosphere}"
HOST_LSR_IN="${P2G_LSR_IN:-/data/output/jpss/level2/lsr}"
HOST_ACSPO_IN="${P2G_ACSPO_IN:-/data/output/jpss/level2/acspo}"

# Los datos (GeoTIFF) y las vistas (JPG) van en árboles distintos
GEOTIFF="${P2G_GEOTIFF:-/data/output/jpss/geotiff}"
HOST_TIF_OUT="$GEOTIFF/atmos"
HOST_LSR_TIF_OUT="$GEOTIFF/lsr"
HOST_LSR_RGB_TIF_OUT="$GEOTIFF/lsr_rgb"
HOST_ACSPO_TIF_OUT="$GEOTIFF/acspo"

VISTAS="${P2G_VISTAS:-/data/output/jpss/vistas}"
HOST_IMG_OUT="$VISTAS/atmos"
HOST_LSR_IMG_OUT="$VISTAS/lsr"
HOST_LSR_RGB_IMG_OUT="$VISTAS/lsr_rgb"
HOST_ACSPO_IMG_OUT="$VISTAS/acspo"

# El contenedor trae la rejilla de fábrica, no las nuestras: hay que pasarle
# config/grid.yaml con --grid-configs o remuestrearía a una rejilla dinámica
# distinta en cada pasada.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRID_CONFIG="${P2G_GRID_CONFIG:-$SCRIPT_DIR/../config/grid.yaml}"
GRID="${P2G_GRID:-wgs84_geo_750m}"

# Minutos de tolerancia al emparejar productos con la ventana de la pasada
MARGEN_MIN="${P2G_MARGEN_MIN:-10}"

STATE_DIR="${P2G_STATE_DIR:-/data/output/jpss/state/polar2grid}"
WORK_BASE="${P2G_WORK_BASE:-/data/tmp}"
LOG_DIR="${P2G_LOG_BASE:-/var/log/lanot/polares}/polar2grid"

JOB_ID="${SLURM_JOB_ID:-$$}"

# Paleta por producto para geotiff2view: se toma la primera clave que aparezca
# en el nombre del GeoTIFF. Los CPT se resuelven dentro del contenedor, en
# /usr/local/share/lanot/colortables, así que va el basename a secas.
#
# OJO: estos CPT se hicieron para las variables de CLAVR-x y los JRR-* traen
# otros nombres y rangos, así que el emparejamiento es tentativo. Un producto
# sin paleta no genera vista y no es error — se anota en el log y se sigue.
# Completar tras ver los nombres reales que escribe Polar2Grid.
PALETAS=(
    "sst:sst.cpt"
    "CldTopTemp:cld_temp_acha.cpt"
    "CldTopHght:cld_height_acha.cpt"
    "CldBaseHght:cld_height_acha.cpt"
    "CldTopPres:cld_top_press.cpt"
    "CldEmiss:cld_emiss.cpt"
    "CloudPhase:phase.cpt"
    "CloudType:cloud_type.cpt"
    "AOD550:aod550.cpt"
)

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

# Imprime el CPT que le toca a un GeoTIFF, o devuelve 1 si no hay ninguno.
paleta_de() {
    local nombre="$1" par
    for par in "${PALETAS[@]}"; do
        case "$nombre" in
            *"${par%%:*}"*) echo "${par#*:}"; return 0 ;;
        esac
    done
    return 1
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

# Calcula la ventana temporal de la pasada a partir del SDR agregado:
#   GMTCO_j01_d20260811_t1947330_e2003097_b45236_... -> 202608111947330 .. 202608112003097
ventana_de_pasada() {
    local nombre fecha tini tfin
    nombre=$(basename "$1")
    IFS='_' read -r _ _ fecha tini tfin _ <<< "$nombre"

    FECHA_NUM="${fecha#d}"
    VENTANA_INI="${FECHA_NUM}${tini#t}"; VENTANA_INI="${VENTANA_INI:0:14}"

    # Si la hora final es menor que la inicial, la pasada cruzó la medianoche
    if [ "${tfin#e}" -lt "${tini#t}" ]; then
        FECHA_SIG=$(date -u -d "${FECHA_NUM} +1 day" +%Y%m%d)
    else
        FECHA_SIG="$FECHA_NUM"
    fi

    VENTANA_FIN="${FECHA_SIG}${tfin#e}"; VENTANA_FIN="${VENTANA_FIN:0:14}"

    # Margen a ambos lados. Hace falta porque no todos los productos fechan
    # igual: el .nc de ACSPO de esta misma pasada sale como 20260811194400,
    # 3.5 minutos ANTES del primer gránulo (t1947330), y sin margen quedaba
    # fuera. Es seguro: dos pasadas consecutivas sobre la estación están
    # separadas ~100 minutos, así que ningún margen razonable las confunde.
    VENTANA_INI=$(desplazar_sello "$VENTANA_INI" "-$MARGEN_MIN")
    VENTANA_FIN=$(desplazar_sello "$VENTANA_FIN" "+$MARGEN_MIN")
}

# Suma o resta minutos a un sello AAAAMMDDHHMMSS.
# Se pasa por epoch a propósito: con "$s $minutos minutes", date lee un "-10"
# pegado a la hora como huso horario y devuelve otro día.
desplazar_sello() {
    local s="$1" minutos="$2" base
    base=$(date -u -d "${s:0:4}-${s:4:2}-${s:6:2} ${s:8:2}:${s:10:2}:${s:12:2} UTC" +%s)
    date -u -d "@$((base + minutos * 60))" +%Y%m%d%H%M%S
}

# Devuelve el sello temporal de un producto como AAAAMMDDHHMMSS, o código 1 si
# no lo reconoce. En Level 2 conviven tres convenciones:
#   JRR-CloudMask_v3r2_j01_s202608111947330_e...    -> fecha + hora + décimas
#   NOAA20_VIIRS_750M_2026223_1947_33_NWP_GFS-INTP  -> año + día juliano + HHMM_SS
#   20260811194733-CSPP-L2P_GHRSST-SSTsubskin-…     -> ACSPO, al principio y sin separadores
sello_de_archivo() {
    local nombre="$1" s anio doy fecha

    # Convención de ACSPO: 14 dígitos al inicio del nombre. Va primero porque es
    # la más específica; las otras dos exigen 7 dígitos tras la fecha y aquí solo
    # hay 6 antes del guion, así que no se pisan.
    s=$(echo "$nombre" | grep -oE "^(${FECHA_NUM}|${FECHA_SIG})[0-9]{6}" | head -1 || true)
    if [ -n "$s" ]; then
        echo "$s"
        return 0
    fi

    # Convención con fecha calendario
    s=$(echo "$nombre" | grep -oE "(${FECHA_NUM}|${FECHA_SIG})[0-9]{7}" | head -1 || true)
    if [ -n "$s" ]; then
        echo "${s:0:14}"   # se descartan las décimas de segundo
        return 0
    fi

    # Convención con día juliano
    s=$(echo "$nombre" | grep -oE "_[0-9]{7}_[0-9]{4}_[0-9]{2}_" | head -1 || true)
    if [ -n "$s" ]; then
        s="${s#_}"; s="${s%_}"
        anio="${s:0:4}"; doy="${s:4:3}"
        fecha=$(date -u -d "${anio}-01-01 +$((10#$doy - 1)) days" +%Y%m%d)
        echo "${fecha}${s:8:4}${s:13:2}"
        return 0
    fi

    return 1
}

# Rechaza un archivo si nombra explícitamente a OTRO satélite. Si no reconoce
# ninguno, no estorba: la ventana temporal ya filtra.
#
# El mismo satélite aparece con varios nombres según el producto: j01 en los
# SDR, NOAA20 en los VIIRS_750M de ATMOS, n20 en los de Flood y N20 en ACSPO.
de_otro_satelite() {
    case "$SAT" in
        j01) echo "$1" | grep -qiE "j02|noaa21|n21|npp" ;;
        j02) echo "$1" | grep -qiE "j01|noaa20|n20|npp" ;;
        npp) echo "$1" | grep -qiE "j01|noaa20|n20|j02|noaa21|n21" ;;
        *)   return 1 ;;
    esac
}

# Enlaza en $1 los productos $3 de $2 cuyo sello temporal cae dentro de la
# ventana de la pasada. No se puede emparejar gránulo por gránulo: los SDR
# llegan agregados (un archivo por banda para toda la pasada, con un solo
# GMTCO), mientras que los productos de Level 2 son por gránulo.
enlazar() {
    ln -f "$1" "$2" 2>/dev/null || ln -sf "$1" "$2"
}

enlazar_en_ventana() {
    local destino="$1" origen="$2" patron="$3" enlazados=0 f nombre sello clave
    local -A elegido=()

    shopt -s nullglob
    for f in "$origen"/${patron}*.nc; do
        nombre=$(basename "$f")
        de_otro_satelite "$nombre" && continue
        sello=$(sello_de_archivo "$nombre") || continue
        [ "$sello" -ge "$VENTANA_INI" ] && [ "$sello" -le "$VENTANA_FIN" ] || continue

        # Deduplicación: los JRR-* llevan campo de creación (_c<sello>), así que
        # reprocesar una pasada deja DOS archivos del mismo producto y gránulo.
        # Hay que quedarse con el más reciente, porque LSR deduce cuántos
        # gránulos hay contando los JRR-AOD (cspp_viirs_surface_reflectance.py:313)
        # y luego exige esa misma cantidad de los demás productos. Los duplicados
        # inflan la cuenta y hacen fallar la corrida con un mensaje que culpa a
        # los NWP_GFS-INTP, que no se duplican porque su nombre no lleva _c.
        clave=$(echo "$nombre" | sed -E 's/_c[0-9]+\./_c./')
        if [ -z "${elegido[$clave]:-}" ] || [ "$f" -nt "${elegido[$clave]}" ]; then
            elegido[$clave]="$f"
        fi
    done
    shopt -u nullglob

    for f in "${elegido[@]}"; do
        enlazar "$f" "$destino"/
        enlazados=$((enlazados + 1))
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
STAGING_EDR="${HOST_WORK}/edr_links"
STAGING_LSR="${HOST_WORK}/lsr_links"
STAGING_ACSPO="${HOST_WORK}/acspo_links"

mkdir -p "$STAGING_SDR" "$STAGING_EDR" "$STAGING_LSR" "$STAGING_ACSPO" \
         "$HOST_TIF_OUT" "$HOST_LSR_TIF_OUT" "$HOST_LSR_RGB_TIF_OUT" "$HOST_ACSPO_TIF_OUT" \
         "$HOST_IMG_OUT" "$HOST_LSR_IMG_OUT" "$HOST_LSR_RGB_IMG_OUT" "$HOST_ACSPO_IMG_OUT" \
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

ventana_de_pasada "$ULTIMO_GMTCO"

EDR_COUNT=0
LSR_COUNT=0
ACSPO_COUNT=0
[ -d "$HOST_EDR_IN" ] && EDR_COUNT=$(enlazar_en_ventana "$STAGING_EDR" "$HOST_EDR_IN" "JRR-")
[ -d "$HOST_LSR_IN" ] && LSR_COUNT=$(enlazar_en_ventana "$STAGING_LSR" "$HOST_LSR_IN" "SurfRefl_")
# Los .nc de ACSPO empiezan con el sello temporal, no con un prefijo de producto
[ -d "$HOST_ACSPO_IN" ] && ACSPO_COUNT=$(enlazar_en_ventana "$STAGING_ACSPO" "$HOST_ACSPO_IN" "")

LOG_FILE="$LOG_DIR/p2g_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR:      $SDR_COUNT archivos"                  | tee -a "$LOG_FILE"
echo "  ATMOS:    $EDR_COUNT productos en la ventana"    | tee -a "$LOG_FILE"
echo "  LSR:      $LSR_COUNT productos en la ventana"    | tee -a "$LOG_FILE"
echo "  ACSPO:    $ACSPO_COUNT productos en la ventana"  | tee -a "$LOG_FILE"

REF_FILE=$(mktemp -t p2g_ref_XXXXXX)
trap 'rm -rf "$HOST_WORK" "$REF_FILE"' EXIT

# ==============================================================================
# RENDERIZADO
# ==============================================================================
# Cada bloque es independiente: se registra su código pero no aborta a los demás.

en_contenedor() {
    local etiqueta="$1"; shift
    local codigo=0

    echo "--- $etiqueta ---" >> "$LOG_FILE"
    apptainer exec \
        --bind "$STAGING_SDR:/input_sdr" \
        --bind "$STAGING_EDR:/input_edr" \
        --bind "$STAGING_LSR:/input_lsr" \
        --bind "$STAGING_ACSPO:/input_acspo" \
        --bind "$HOST_SDR_IN:$HOST_SDR_IN" \
        --bind "$HOST_EDR_IN:$HOST_EDR_IN" \
        --bind "$HOST_LSR_IN:$HOST_LSR_IN" \
        --bind "$HOST_ACSPO_IN:$HOST_ACSPO_IN" \
        --bind "$GRID_CONFIG:/config/grid.yaml:ro" \
        --bind "$HOST_TIF_OUT:/output_tif" \
        --bind "$HOST_LSR_TIF_OUT:/output_lsr_tif" \
        --bind "$HOST_LSR_RGB_TIF_OUT:/output_lsr_rgb_tif" \
        --bind "$HOST_ACSPO_TIF_OUT:/output_acspo_tif" \
        --bind "$HOST_IMG_OUT:/output_img" \
        --bind "$HOST_LSR_IMG_OUT:/output_lsr_img" \
        --bind "$HOST_LSR_RGB_IMG_OUT:/output_lsr_rgb_img" \
        --bind "$HOST_ACSPO_IMG_OUT:/output_acspo_img" \
        --bind "$HOST_WORK:/work" \
        "$SIF_P2G" /bin/bash -c "$*" >> "$LOG_FILE" 2>&1 || codigo=$?

    if [ $codigo -ne 0 ]; then
        echo "  ⚠ $etiqueta falló (código $codigo)" | tee -a "$LOG_FILE"
    fi

    return 0
}

# --- Etapa 1: remuestreo a la rejilla, una sola vez por conjunto ---

P2G_COMUN="--grid-configs /config/grid.yaml -g $GRID --method nearest"
P2G_DATOS="$P2G_COMUN --dtype float32 --no-enhance"

if [ "$EDR_COUNT" -gt 0 ]; then
    en_contenedor "Productos atmosféricos (EDR)" \
        "cd /output_tif && polar2grid.sh -v -r viirs_edr -w geotiff $P2G_DATOS -f /input_edr/JRR-*.nc /input_sdr/GMTCO*.h5"
else
    echo "  ⚠ Sin productos de ATMOS para esta pasada: se omite ese renderizado" | tee -a "$LOG_FILE"
fi

if [ "$LSR_COUNT" -gt 0 ]; then
    # Los SurfRefl traen su propia geolocalización, no necesitan GMTCO.
    #
    # Van en dos llamadas porque el conjunto de LSR mezcla las dos naturalezas
    # de la regla: catorce productos de una banda —que son datos— y dos
    # composiciones RGB. Pedirlos juntos con --dtype float32 aborta con
    # "Image must be in 'L' mode for floating point geotiff saving", y con ello
    # se pierden también los que ya se habían remuestreado (verificado en tahan
    # el 2026-08-13: murió tras escribir 3 de 14). Los nombres van explícitos
    # porque Polar2Grid no tiene forma de excluir productos.
    LSR_DATOS="surf_refl_i01 surf_refl_i02 surf_refl_i03"
    LSR_DATOS="$LSR_DATOS surf_refl_m01 surf_refl_m02 surf_refl_m03 surf_refl_m04 surf_refl_m05"
    LSR_DATOS="$LSR_DATOS surf_refl_m07 surf_refl_m08 surf_refl_m10 surf_refl_m11 NDVI EVI"

    en_contenedor "Productos de superficie (LSR)" \
        "cd /output_lsr_tif && polar2grid.sh -v -r viirs_edr -w geotiff -p $LSR_DATOS $P2G_DATOS -f /input_lsr/SurfRefl_*.nc"

    # Los RGB de superficie ya salen como imagen: no llevan float32 ni
    # --no-enhance, y se visten con mapdrawer en vez de recolorearse.
    en_contenedor "RGB de superficie (LSR)" \
        "cd /output_lsr_rgb_tif && polar2grid.sh -v -r viirs_edr -w geotiff -p true_color_surf false_color_surf $P2G_COMUN -f /input_lsr/SurfRefl_*.nc"
else
    echo "  ⚠ Sin productos de LSR para esta pasada: se omite ese renderizado" | tee -a "$LOG_FILE"
fi

if [ "$ACSPO_COUNT" -gt 0 ]; then
    # --grid-coverage=0.0 porque la SST solo cubre mar: en una pasada con poco
    # océano dentro de la rejilla, el umbral por omisión descartaría la imagen.
    en_contenedor "SST (ACSPO)" \
        "cd /output_acspo_tif && polar2grid.sh -v -r acspo -w geotiff -p sst --grid-coverage=0.0 $P2G_COMUN -f /input_acspo/*.nc"
else
    echo "  ⚠ Sin productos de ACSPO para esta pasada: se omite ese renderizado" | tee -a "$LOG_FILE"
fi

# --- Etapa 2: vistas decoradas a partir de los GeoTIFF recién escritos ---
# Los productos llegan sin paleta, así que recolorea geotiff2view. Un producto
# sin CPT no genera vista y no es error.

vestir() {
    local etiqueta="$1" dir_tif="$2" montaje_tif="$3" montaje_img="$4"
    local herramienta="${5:-geotiff2view}"
    local tif nombre cpt ordenes=""

    while IFS= read -r tif; do
        nombre=$(basename "$tif")
        if [ "$herramienta" = "mapdrawer" ]; then
            # Ya es imagen: solo se viste, no se recolorea
            ordenes+="mapdrawer '$montaje_tif/$nombre' ${DECORACION[*]} -o '$montaje_img/${nombre%.*}.jpg'"$'\n'
            continue
        fi
        if ! cpt=$(paleta_de "$nombre"); then
            echo "  · sin paleta, no se genera vista: $nombre" >> "$LOG_FILE"
            continue
        fi
        ordenes+="geotiff2view '$montaje_tif/$nombre' -b -p '$cpt' ${DECORACION[*]} -o '$montaje_img/${nombre%.*}.jpg'"$'\n'
    done < <(find "$dir_tif" -maxdepth 1 -name '*.tif' -newer "$REF_FILE" 2>/dev/null | sort)

    if [ -z "$ordenes" ]; then
        echo "  ⚠ $etiqueta: ningún GeoTIFF con paleta conocida" | tee -a "$LOG_FILE"
        return 0
    fi

    en_contenedor "$etiqueta" "$ordenes"
}

vestir "Vistas de ATMOS" "$HOST_TIF_OUT"       /output_tif       /output_img
vestir "Vistas de LSR"   "$HOST_LSR_TIF_OUT"   /output_lsr_tif   /output_lsr_img
vestir "Vistas de SST"   "$HOST_ACSPO_TIF_OUT" /output_acspo_tif /output_acspo_img
vestir "Vistas RGB de superficie" "$HOST_LSR_RGB_TIF_OUT" /output_lsr_rgb_tif /output_lsr_rgb_img mapdrawer

# ==============================================================================
# VERIFICACIÓN
# ==============================================================================

contar_nuevos() {
    find "$1" -maxdepth 1 -name "$2" -newer "$REF_FILE" 2>/dev/null | wc -l
}

TIF_ATMOS=$(contar_nuevos "$HOST_TIF_OUT"       '*.tif')
TIF_LSR=$(contar_nuevos   "$HOST_LSR_TIF_OUT"   '*.tif')
TIF_LSR_RGB=$(contar_nuevos "$HOST_LSR_RGB_TIF_OUT" '*.tif')
TIF_SST=$(contar_nuevos   "$HOST_ACSPO_TIF_OUT" '*.tif')
JPG_ATMOS=$(contar_nuevos "$HOST_IMG_OUT"       '*.jpg')
JPG_LSR=$(contar_nuevos   "$HOST_LSR_IMG_OUT"   '*.jpg')
JPG_LSR_RGB=$(contar_nuevos "$HOST_LSR_RGB_IMG_OUT" '*.jpg')
JPG_SST=$(contar_nuevos   "$HOST_ACSPO_IMG_OUT" '*.jpg')

TIF_TOTAL=$((TIF_ATMOS + TIF_LSR + TIF_LSR_RGB + TIF_SST))
JPG_TOTAL=$((JPG_ATMOS + JPG_LSR + JPG_LSR_RGB + JPG_SST))

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

# El criterio de éxito son los GeoTIFF: las vistas dependen de que el producto
# tenga CPT, y hoy faltan paletas para varios JRR-*. Una pasada con datos y sin
# vistas está bien procesada; una sin datos, no.
if [ "$TIF_TOTAL" -eq 0 ]; then
    echo "❌ ERROR: Ningún renderizado produjo GeoTIFF." | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                   | tee -a "$LOG_FILE"
    exit 1
fi

{
    echo "renderizado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:      $CLAVE"
    echo "atmos:       $TIF_ATMOS geotiff, $JPG_ATMOS vistas"
    echo "lsr:         $TIF_LSR geotiff, $JPG_LSR vistas"
    echo "lsr rgb:     $TIF_LSR_RGB geotiff, $JPG_LSR_RGB vistas"
    echo "sst:         $TIF_SST geotiff, $JPG_SST vistas"
    echo "duracion:    $DURACION"
    echo "log:         $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: pasada $CLAVE — $TIF_TOTAL geotiff (atmos $TIF_ATMOS, lsr $TIF_LSR, lsr_rgb $TIF_LSR_RGB, sst $TIF_SST) y $JPG_TOTAL vistas (atmos $JPG_ATMOS, lsr $JPG_LSR, lsr_rgb $JPG_LSR_RGB, sst $JPG_SST) en $DURACION" | tee -a "$LOG_FILE"
echo "   GeoTIFF:  $GEOTIFF"  | tee -a "$LOG_FILE"
echo "   Vistas:   $VISTAS"   | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER"   | tee -a "$LOG_FILE"
