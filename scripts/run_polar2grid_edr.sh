#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Visualización de productos Nivel 2 con Polar2Grid v3.2
# ==============================================================================
#
# Level 2 (atmosphere, LSR, ACSPO, Active Fire) → GeoTIFF de datos + vistas
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue renderizada con éxito, avisa y no hace nada. Una pasada se
# identifica por satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
#
# Cada conjunto (ATMOS, LSR, ACSPO, FIRE) es independiente: si uno falla, se
# reporta y los otros siguen. Basta con que alguno produzca imágenes para dar la pasada por
# renderizada.
#
# Dos etapas por conjunto, según la regla de la cadena: Polar2Grid remuestrea
# UNA vez (swath → rejilla) y entrega GeoTIFF de datos; lo visual sale de
# LANOT_tools. Aquí los productos llegan sin paleta, así que la vista la hace
# geotiff2view recoloreando con un CPT. El Level 1 (bandas, DNB, RGB) está en
# run_polar2grid_l1.sh.
#
# AQUÍ NO SE HACEN RGB. Se hacían —true_color_surf y false_color_surf, con el
# lector viirs_edr sobre los SurfRefl_* de LSR— pero salían casi idénticos a los
# true_color / false_color que run_polar2grid_l1.sh compone con viirs_sdr sobre
# los SDR, porque TOA con corrección de Rayleigh ≈ reflectancia de superficie. Se
# decidió el 2026-08-14 quedarse con los de Level 1, que están siempre
# disponibles: los de superficie dependen de que corra LSR, y LSR depende de
# ATMOS. Para recuperarlos: polar2grid.sh -r viirs_edr -p true_color_surf
# false_color_surf, sin --dtype float32 (un RGB no se puede guardar así), y
# vestirlos con mapdrawer en vez de recolorearlos — vestir() ya sabe hacerlo.
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
#   P2G_FIRE_IN     Entrada incendios (def. /data/output/jpss/level2/fires)
#   P2G_FLOOD_TIF   GeoTIFF de flood  (def. /data/output/jpss/geotiff/flood)
#   P2G_GEOTIFF     Raíz de GeoTIFF   (def. /data/output/jpss/geotiff)
#   P2G_VISTAS      Raíz de vistas    (def. /data/output/jpss/vistas)
#   P2G_STATE_DIR   Marcadores .done  (def. /data/output/jpss/state/polar2grid)
#   P2G_CONTAINER   Imagen .sif       (def. …/polar2grid_v3.2-mapdrawer.sif)
#   P2G_GRID_CONFIG Rejillas propias  (def. <repo>/config/grid.yaml)
#   P2G_GRID        Rejilla a usar    (def. wgs84_geo_750m)
#   P2G_GRID_375    Rejilla incendios (def. wgs84_geo_375m)
#   P2G_WORK_BASE   Raíz de staging   (def. /data/tmp)
#   P2G_COLORTABLES Paletas del host  (def. /usr/local/share/lanot/colortables)
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
HOST_FIRE_IN="${P2G_FIRE_IN:-/data/output/jpss/level2/fires}"
# Flood es el caso raro: su GeoTIFF NO lo hace Polar2Grid sino el convertidor
# del propio bundle de CSPP, en run_flood_edr.sh, porque el lector
# viirs_edr_flood es para el formato HDF de la v1.x. Aquí solo se viste.
HOST_FLOOD_TIF_IN="${P2G_FLOOD_TIF:-/data/output/jpss/geotiff/flood}"

# Los datos (GeoTIFF) y las vistas (JPG) van en árboles distintos
GEOTIFF="${P2G_GEOTIFF:-/data/output/jpss/geotiff}"
HOST_TIF_OUT="$GEOTIFF/atmos"
HOST_LSR_TIF_OUT="$GEOTIFF/lsr"
HOST_ACSPO_TIF_OUT="$GEOTIFF/acspo"
HOST_FIRE_TIF_OUT="$GEOTIFF/fire"

VISTAS="${P2G_VISTAS:-/data/output/jpss/vistas}"
HOST_IMG_OUT="$VISTAS/atmos"
HOST_LSR_IMG_OUT="$VISTAS/lsr"
HOST_ACSPO_IMG_OUT="$VISTAS/acspo"
HOST_FIRE_IMG_OUT="$VISTAS/fire"
HOST_FLOOD_IMG_OUT="$VISTAS/flood"

# El contenedor trae la rejilla de fábrica, no las nuestras: hay que pasarle
# config/grid.yaml con --grid-configs o remuestrearía a una rejilla dinámica
# distinta en cada pasada.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRID_CONFIG="${P2G_GRID_CONFIG:-$SCRIPT_DIR/../config/grid.yaml}"
GRID="${P2G_GRID:-wgs84_geo_750m}"
# Los AFIMG de Active Fire son de banda I: van a 375 m, no a los 750 del resto.
GRID_375="${P2G_GRID_375:-wgs84_geo_375m}"

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
#
# CloudLayer NO lleva paleta a propósito: es una máscara de bits (una capa de vuelo por bit,
# valid_range 0..62), así que sus valores son combinaciones y no una escala.
PALETAS=(
    "sst:sst.cpt"
    "CldTopTemp:cld_temp_acha.cpt"
    "CldTopHght:cld_height_acha.cpt"
    "CldBaseHght:cld_height_acha.cpt"
    "CldTopPres:cld_top_press.cpt"
    "CldEmiss:cld_emiss.cpt"
    "CloudPhase:phase.cpt"
    # cloud_type_jrr.cpt y no cloud_type.cpt: el producto JRR declara
    # valid_range 0-8 y el de CLAVR-x llega a 12, así que la paleta de trece
    # clases anunciaría cuatro categorías que aquí no pueden ocurrir. La de
    # CLAVR-x se conserva intacta porque la usa la cadena vieja.
    "CloudType:cloud_type_jrr.cpt"
    "AOD550:aod550.cpt"
    "Total_Cloud_Fraction:cloud_fraction.cpt"
    "NDVI:ndvi.cpt"
    "EVI:evi.cpt"
    "confidence_cat:viirs_confidence_cat.cpt"
)

# Las paletas viven dentro de la imagen: install.sh las copia al compilar. Si
# el host tiene el directorio, se monta encima, para que agregar un CPT no
# obligue a recompilar el contenedor. Es el mismo criterio que con los LUTs de
# CSPP: binarios en la imagen, lo que cambia en el host.
COLORTABLES="${P2G_COLORTABLES:-/usr/local/share/lanot/colortables}"
BIND_CPT=()
[ -d "$COLORTABLES" ] && BIND_CPT=(--bind "$COLORTABLES:/usr/local/share/lanot/colortables:ro")

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
  -p, --pasada  Pasada concreta en vez de la más reciente: la clave completa
                (j01_d20260813_b45264) o cualquier trozo que la identifique
  -h, --help    Muestra esta ayuda

Pasadas disponibles en $HOST_SDR_IN:
$(claves_disponibles 2>/dev/null | sed 's/^/  /' || true)
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

# Las pasadas que hay en el directorio de entrada, una por línea y sin repetir.
claves_disponibles() {
    find "$HOST_SDR_IN" -maxdepth 1 -name 'GMTCO*.h5' -printf '%f\n' 2>/dev/null |
        while IFS= read -r nombre; do
            clave_de_pasada "$nombre" || true
        done | sort -u
}

# Deja en ULTIMO_GMTCO un archivo representativo de la pasada: el más reciente si
# no se pidió ninguna, o el primer gránulo de la que se pida con --pasada. De ahí
# salen la clave y, donde aplica, la ventana temporal con la que se emparejan los
# productos que no llevan órbita en el nombre.
resolver_pasada() {
    local coinciden sat fecha orbita

    if [ -z "$PASADA" ]; then
        ULTIMO_GMTCO=$(find "$HOST_SDR_IN" -maxdepth 1 -name 'GMTCO*.h5' \
                            -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        return 0
    fi

    # --pasada acepta la clave completa o cualquier trozo que la identifique:
    # "j01_d20260813_b45264", "d20260813" o hasta "45264". Se resuelve contra las
    # pasadas que de verdad estén en el directorio, así que un valor ambiguo o
    # inexistente se caza aquí y no a media corrida.
    mapfile -t coinciden < <(claves_disponibles | grep -F -- "$PASADA" || true)

    if [ "${#coinciden[@]}" -eq 0 ]; then
        echo "ERROR: Ninguna pasada de $HOST_SDR_IN coincide con '$PASADA'" >&2
        echo "       Disponibles:" >&2
        claves_disponibles | sed 's/^/         /' >&2
        return 1
    fi

    if [ "${#coinciden[@]}" -gt 1 ]; then
        echo "ERROR: '$PASADA' coincide con más de una pasada; hay que ser más específico:" >&2
        printf '         %s\n' "${coinciden[@]}" >&2
        return 1
    fi

    IFS='_' read -r sat fecha orbita <<< "${coinciden[0]}"
    ULTIMO_GMTCO=$(find "$HOST_SDR_IN" -maxdepth 1 -name "GMTCO_${sat}_${fecha}_*_${orbita}_*.h5" \
                        | sort | head -1)
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
# no lo reconoce. En Level 2 conviven cuatro convenciones:
#   JRR-CloudMask_v3r2_j01_s202608111947330_e...    -> fecha + hora + décimas
#   NOAA20_VIIRS_750M_2026223_1947_33_NWP_GFS-INTP  -> año + día juliano + HHMM_SS
#   20260811194733-CSPP-L2P_GHRSST-SSTsubskin-…     -> ACSPO, al principio y sin separadores
#   AFIMG_j01_d20260813_t1911067_e1912312_b45264_…  -> Active Fire, la de los SDR
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

    # Convención de los SDR, que es la que usan también los AFIMG de Active
    # Fire: fecha tras _d y hora tras _t, con décimas al final. No casa con la
    # de arriba porque entre la fecha y la hora hay "_t" y no dígitos.
    s=$(echo "$nombre" | grep -oE "_d(${FECHA_NUM}|${FECHA_SIG})_t[0-9]{7}_" | head -1 || true)
    if [ -n "$s" ]; then
        s="${s#_d}"; s="${s%_}"                 # 20260813_t1911067
        s="${s%%_*}${s#*_t}"                    # 202608131911067
        echo "${s:0:14}"                        # se descartan las décimas
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
# El código de satélite tal como lo escribe Polar2Grid en sus salidas: noaa20 y
# no j01. run_flood_edr.sh nombra su .tif con esta misma forma —comparten árbol y
# filtro—, así que las dos definiciones tienen que moverse juntas.
sat_polar2grid() {
    case "$1" in
        npp) echo npp    ;;
        j01) echo noaa20 ;;
        j02) echo noaa21 ;;
        *)   echo "$1"   ;;
    esac
}

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
        # El campo de creación va seguido de "." en los JRR-* pero de "_cspp_dev"
        # en los AFIMG, así que se recorta por los dígitos y no por lo que sigue.
        clave=$(echo "$nombre" | sed -E 's/_c[0-9]{6,}/_c/')
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
PASADA=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        -h|--help)  uso; exit 0 ;;
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
HOST_WORK="${WORK_BASE}/p2g_work_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$HOST_SDR_IN" ]; then
    echo "ERROR: Directorio de SDR no encontrado: $HOST_SDR_IN" >&2
    exit 1
fi

resolver_pasada || exit 1

if [ -z "$ULTIMO_GMTCO" ]; then
    echo "No hay SDR que renderizar en $HOST_SDR_IN (no se ven archivos GMTCO*)."
    exit 0
fi

if ! CLAVE=$(clave_de_pasada "$ULTIMO_GMTCO"); then
    echo "ERROR: No se pudo derivar la pasada del nombre: $(basename "$ULTIMO_GMTCO")" >&2
    exit 1
fi

IFS='_' read -r SAT FECHA ORBITA <<< "$CLAVE"
SAT_VISTA=$(sat_polar2grid "$SAT")

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
STAGING_FIRE="${HOST_WORK}/fire_links"

mkdir -p "$STAGING_SDR" "$STAGING_EDR" "$STAGING_LSR" "$STAGING_ACSPO" "$STAGING_FIRE" \
         "$HOST_TIF_OUT" "$HOST_LSR_TIF_OUT" "$HOST_ACSPO_TIF_OUT" "$HOST_FIRE_TIF_OUT" \
         "$HOST_IMG_OUT" "$HOST_LSR_IMG_OUT" "$HOST_ACSPO_IMG_OUT" "$HOST_FIRE_IMG_OUT" \
         "$HOST_FLOOD_TIF_IN" "$HOST_FLOOD_IMG_OUT" \
         "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$HOST_WORK"' EXIT

# Los montajes son los mismos para toda invocación del contenedor, sean las
# llamadas a Polar2Grid o las de LANOT_tools archivo por archivo. Se arman una
# vez, aquí, porque dependen de los directorios de staging que acaban de
# definirse.
BINDS_P2G=(
    "${BIND_CPT[@]}"
    --bind "$STAGING_SDR:/input_sdr"
    --bind "$STAGING_EDR:/input_edr"
    --bind "$STAGING_LSR:/input_lsr"
    --bind "$STAGING_ACSPO:/input_acspo"
    --bind "$STAGING_FIRE:/input_fire"
    --bind "$HOST_SDR_IN:$HOST_SDR_IN"
    --bind "$HOST_EDR_IN:$HOST_EDR_IN"
    --bind "$HOST_LSR_IN:$HOST_LSR_IN"
    --bind "$HOST_ACSPO_IN:$HOST_ACSPO_IN"
    --bind "$HOST_FIRE_IN:$HOST_FIRE_IN"
    --bind "$GRID_CONFIG:/config/grid.yaml:ro"
    --bind "$HOST_TIF_OUT:/output_tif"
    --bind "$HOST_LSR_TIF_OUT:/output_lsr_tif"
    --bind "$HOST_ACSPO_TIF_OUT:/output_acspo_tif"
    --bind "$HOST_FIRE_TIF_OUT:/output_fire_tif"
    --bind "$HOST_FLOOD_TIF_IN:/output_flood_tif"
    --bind "$HOST_IMG_OUT:/output_img"
    --bind "$HOST_LSR_IMG_OUT:/output_lsr_img"
    --bind "$HOST_ACSPO_IMG_OUT:/output_acspo_img"
    --bind "$HOST_FIRE_IMG_OUT:/output_fire_img"
    --bind "$HOST_FLOOD_IMG_OUT:/output_flood_img"
    --bind "$HOST_WORK:/work"
)

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
FIRE_COUNT=0
[ -d "$HOST_EDR_IN" ] && EDR_COUNT=$(enlazar_en_ventana "$STAGING_EDR" "$HOST_EDR_IN" "JRR-")
[ -d "$HOST_LSR_IN" ] && LSR_COUNT=$(enlazar_en_ventana "$STAGING_LSR" "$HOST_LSR_IN" "SurfRefl_")
# Los .nc de ACSPO empiezan con el sello temporal, no con un prefijo de producto
[ -d "$HOST_ACSPO_IN" ] && ACSPO_COUNT=$(enlazar_en_ventana "$STAGING_ACSPO" "$HOST_ACSPO_IN" "")
# Los AFIMG se emparejan por ventana y NO por órbita: la órbita cambia a media
# pasada (b45264 en el primer gránulo del 2026-08-13 y b45265 en los siguientes),
# así que un glob por órbita dejaría fuera parte de los gránulos.
[ -d "$HOST_FIRE_IN" ] && FIRE_COUNT=$(enlazar_en_ventana "$STAGING_FIRE" "$HOST_FIRE_IN" "AFIMG_")

LOG_FILE="$LOG_DIR/p2g_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR:      $SDR_COUNT archivos"                  | tee -a "$LOG_FILE"
echo "  ATMOS:    $EDR_COUNT productos en la ventana"    | tee -a "$LOG_FILE"
echo "  LSR:      $LSR_COUNT productos en la ventana"    | tee -a "$LOG_FILE"
echo "  ACSPO:    $ACSPO_COUNT productos en la ventana"  | tee -a "$LOG_FILE"
echo "  FIRE:     $FIRE_COUNT productos en la ventana"   | tee -a "$LOG_FILE"

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
    apptainer exec "${BINDS_P2G[@]}" \
        "$SIF_P2G" /bin/bash -c "$*" >> "$LOG_FILE" 2>&1 || codigo=$?

    if [ $codigo -ne 0 ]; then
        echo "  ⚠ $etiqueta falló (código $codigo)" | tee -a "$LOG_FILE"
    fi

    return 0
}

# Corre UNA herramienta de LANOT_tools sobre UN archivo y devuelve su código de
# salida tal cual. Es lo que permite leer el código por archivo: antes las
# órdenes de toda una sección se concatenaban en una sola cadena para un único
# `bash -c`, y el código del conjunto era el de la ÚLTIMA orden — el de las demás
# se perdía. Con geotiff2view distinguiendo "sin datos válidos" (3) de "falló"
# (1), ese código es justo lo que hay que leer.
#
# De paso desaparece la cadena de órdenes con comillas anidadas: los argumentos
# viajan como arreglo, sin que nada tenga que sobrevivir a dos niveles de
# entrecomillado. Esa cadena ya costó una corrida en run_flood_edr.sh.
#
# Cuesta un arranque de contenedor por archivo en vez de uno por sección —unos
# 20-25 por pasada, del orden de 15 s— y solo aplica a las vistas: las llamadas a
# Polar2Grid, que son las caras, siguen siendo una por sección.
en_contenedor_uno() {
    local codigo=0
    apptainer exec "${BINDS_P2G[@]}" "$SIF_P2G" "$@" >> "$LOG_FILE" 2>&1 || codigo=$?
    return $codigo
}

# --- Etapa 1: remuestreo a la rejilla, una sola vez por conjunto ---

# Las tres llamadas van con P2G_DATOS: aquí todo es dato de una banda. P2G_COMUN
# queda separado porque es lo que necesitaría un RGB, que no se puede guardar en
# float32 — hoy no se pide ninguno, ver la nota del encabezado.
P2G_COMUN="--grid-configs /config/grid.yaml -g $GRID --method nearest"
P2G_DATOS="$P2G_COMUN --dtype float32 --no-enhance"
# Incendios llevan su propia cadena porque van a otra rejilla: los AFIMG son
# de banda I. --no-enhance no es opcional aquí — confidence_cat es CATEGÓRICO
# (los valores literales 7, 8 y 9) y viirs_confidence_cat.cpt es una paleta
# discreta que los usa como índice; si Polar2Grid los realza a 0-255, la
# correspondencia se rompe y la leyenda miente.
P2G_FIRE_DATOS="--grid-configs /config/grid.yaml -g $GRID_375 --method nearest --dtype float32 --no-enhance"

if [ "$EDR_COUNT" -gt 0 ]; then
    # Los siete primeros son los que entregaba la lista por omisión, o sea que
    # enumerarlos no cambia nada; el octavo es la ganancia.
    #
    # CloudType NO está en el catálogo de Polar2Grid para este lector: es un
    # "producto no estándar de Satpy", de los que `--list-products` **oculta** y
    # solo enseña `--list-products-all` (con un `*` delante, que es marca y no
    # parte del nombre). Se pide igual y funciona — verificado en tahan el
    # 2026-08-14—, pero como no está en el catálogo no entra por omisión, y por
    # eso hay que enumerar: pasar -p reemplaza la lista por omisión, no la
    # extiende.
    #
    # Si resulta que la vista de tipo de nube no la usa nadie, basta quitar
    # CloudType de esta línea; lo demás sigue igual.
    ATMOS_DATOS="AOD550 CldBaseHght CldTopHght CldTopTemp CloudLayer CloudPhase"
    ATMOS_DATOS="$ATMOS_DATOS Total_Cloud_Fraction CloudType"

    en_contenedor "Productos atmosféricos (EDR)" \
        "cd /output_tif && polar2grid.sh -v -r viirs_edr -w geotiff -p $ATMOS_DATOS $P2G_DATOS -f /input_edr/JRR-*.nc /input_sdr/GMTCO*.h5"
else
    echo "  ⚠ Sin productos de ATMOS para esta pasada: se omite ese renderizado" | tee -a "$LOG_FILE"
fi

if [ "$LSR_COUNT" -gt 0 ]; then
    # Los SurfRefl traen su propia geolocalización, no necesitan GMTCO.
    #
    # Los catorce nombres van explícitos, y no se pide el conjunto por omisión,
    # porque ese incluye las dos composiciones RGB de superficie
    # (true_color_surf / false_color_surf) y un RGB no se puede guardar en
    # float32: aborta con "Image must be in 'L' mode for floating point geotiff
    # saving", y con ello se pierden también los que ya se habían remuestreado
    # (verificado en tahan el 2026-08-13: murió tras escribir 3 de 14).
    # Polar2Grid no tiene forma de excluir productos, así que hay que enumerar.
    LSR_DATOS="surf_refl_i01 surf_refl_i02 surf_refl_i03"
    LSR_DATOS="$LSR_DATOS surf_refl_m01 surf_refl_m02 surf_refl_m03 surf_refl_m04 surf_refl_m05"
    LSR_DATOS="$LSR_DATOS surf_refl_m07 surf_refl_m08 surf_refl_m10 surf_refl_m11 NDVI EVI"

    en_contenedor "Productos de superficie (LSR)" \
        "cd /output_lsr_tif && polar2grid.sh -v -r viirs_edr -w geotiff -p $LSR_DATOS $P2G_DATOS -f /input_lsr/SurfRefl_*.nc"
else
    echo "  ⚠ Sin productos de LSR para esta pasada: se omite ese renderizado" | tee -a "$LOG_FILE"
fi

if [ "$ACSPO_COUNT" -gt 0 ]; then
    # --grid-coverage=0.0 porque la SST solo cubre mar: en una pasada con poco
    # océano dentro de la rejilla, el umbral por omisión descartaría la imagen.
    #
    # Va con P2G_DATOS, no con P2G_COMUN: la SST es dato de una banda, como los
    # JRR-* y los surf_refl_*, no una composición RGB. Con P2G_COMUN salía una
    # imagen realzada de 8 bits con el sin-dato en un canal alfa que
    # geotiff2view no lee —solo abre la banda 1—, así que la máscara de NoData
    # quedaba vacía, la línea B del CPT nunca se aplicaba y todo el relleno caía
    # al índice 0 de la rampa: el fondo rosa de 268 K (verificado en tahan el
    # 2026-08-14 con gdalinfo: "Type=Byte" en las dos bandas, sin NoData Value).
    en_contenedor "SST (ACSPO)" \
        "cd /output_acspo_tif && polar2grid.sh -v -r acspo -w geotiff -p sst --grid-coverage=0.0 $P2G_DATOS -f /input_acspo/*.nc"
else
    echo "  ⚠ Sin productos de ACSPO para esta pasada: se omite ese renderizado" | tee -a "$LOG_FILE"
fi

if [ "$FIRE_COUNT" -gt 0 ]; then
    # Los AFIMG se bastan solos: traen su propia geolocalización y no hay que
    # montarles SDR (verificado con --list-products el 2026-08-14). Por eso
    # tampoco aplica aquí nada de lo del sufijo _cspp_dev ni del j01/J01:
    # eso solo estorbaba cuando se metía el lector viirs_sdr en la misma
    # llamada, que es lo que hacía referencia/test_render_fires.sh.
    #
    # --grid-coverage=0.0 por la misma razón que la SST: los píxeles de fuego
    # cubren una fracción minúscula de la rejilla y el umbral por omisión
    # descartaría la imagen entera.
    #
    # De los tres productos disponibles solo confidence_cat tiene paleta; T4
    # (temperatura de brillo a 4 um) y power (potencia radiativa, MW) salen
    # como GeoTIFF sin vista, que es el comportamiento correcto.
    en_contenedor "Incendios (Active Fire)" \
        "cd /output_fire_tif && polar2grid.sh -v -r viirs_edr_active_fires -w geotiff -p confidence_cat T4 power --grid-coverage=0.0 $P2G_FIRE_DATOS -f /input_fire/AFIMG_*.nc"
else
    echo "  ⚠ Sin productos de Active Fire para esta pasada: se omite ese renderizado" | tee -a "$LOG_FILE"
fi

# --- Etapa 2: vistas decoradas a partir de los GeoTIFF recién escritos ---
# Los productos llegan sin paleta, así que recolorea geotiff2view. Un producto
# sin CPT no genera vista y no es error.

# $5 herramienta, $6 ERE opcional: solo se viste lo que haga match. Sirve para
# dejar fuera lo que es dato y no imagen.
#
# $7 solo-nuevos (1 por omisión): normalmente se viste únicamente lo que escribió
# ESTA corrida, contra REF_FILE. Flood es la excepción — su GeoTIFF lo produjo
# run_flood_edr.sh minutos antes, así que es más viejo que REF_FILE y con el
# filtro nunca se vestiría. Ahí se pasa 0 y quien acota la pasada es el ERE.
vestir() {
    local etiqueta="$1" dir_tif="$2" montaje_tif="$3" montaje_img="$4"
    local herramienta="${5:-geotiff2view}" filtro="${6:-.}" solo_nuevos="${7:-1}"
    # Paleta para la barra de color de mapdrawer, opcional. Va como parámetro y
    # NO en DECORACION, que es compartido: la rama de mapdrawer también se
    # conserva para los RGB de superficie retirados, y ésos no llevan barra.
    local cpt_barra="${8:-}"
    local tif nombre cpt codigo
    local generadas=0 vacias=0 fallidas=0
    local -a criterio=() orden=()
    [ "$solo_nuevos" -eq 1 ] && criterio=(-newer "$REF_FILE")

    echo "--- $etiqueta ---" >> "$LOG_FILE"

    while IFS= read -r tif; do
        nombre=$(basename "$tif")

        if [ "$herramienta" = "mapdrawer" ]; then
            # Ya es imagen: solo se viste, no se recolorea
            orden=(mapdrawer "$montaje_tif/$nombre" "${DECORACION[@]}")
            # mapdrawer busca la paleta de la barra en tres lugares, por
            # prioridad: el tag de texto 'colormap' del TIFF, el --cpt externo, y
            # el colormap nativo. El de flood tiene colormap nativo, así que sin
            # --cpt saldría una barra con las 256 entradas —70 de ellas negro de
            # relleno—, sin etiquetas y numerada 0-255. El --cpt gana sobre el
            # nativo, que es justo lo que hace falta.
            [ -n "$cpt_barra" ] && orden+=(--cpt "$cpt_barra" --colorbar)
        else
            if ! cpt=$(paleta_de "$nombre"); then
                echo "  · sin paleta, no se genera vista: $nombre" >> "$LOG_FILE"
                continue
            fi
            orden=(geotiff2view "$montaje_tif/$nombre" -b -p "$cpt" "${DECORACION[@]}")
        fi
        orden+=(-o "$montaje_img/${nombre%.*}.jpg")

        codigo=0
        en_contenedor_uno "${orden[@]}" || codigo=$?

        # El 3 lo emite geotiff2view cuando el GeoTIFF no tiene un solo píxel
        # válido. No es un fallo: hay productos que salen vacíos en una pasada
        # —el EVI del 2026-08-13— y publicar un JPG en negro es peor que no
        # publicar nada. mapdrawer no usa ese código; si algún día lo devolviera,
        # se contaría aquí como vacío, que es lo más parecido.
        case $codigo in
            0) generadas=$((generadas + 1)) ;;
            3) echo "  · sin datos válidos, no se genera vista: $nombre" | tee -a "$LOG_FILE"
               vacias=$((vacias + 1)) ;;
            *) echo "  ⚠ no se pudo vestir: $nombre (código $codigo)" | tee -a "$LOG_FILE"
               fallidas=$((fallidas + 1)) ;;
        esac
    done < <(find "$dir_tif" -maxdepth 1 -name '*.tif' "${criterio[@]}" 2>/dev/null \
                  | grep -E "$filtro" | sort)

    if [ $((generadas + vacias + fallidas)) -eq 0 ]; then
        # Puede ser que el filtro dejara fuera todo (son datos, no imágenes) o
        # que ningún producto tenga CPT. El detalle queda arriba, en el log.
        echo "  ⚠ $etiqueta: nada que vestir" | tee -a "$LOG_FILE"
        return 0
    fi

    echo "  $etiqueta: generadas $generadas, sin datos $vacias, con error $fallidas" >> "$LOG_FILE"
    return 0
}

vestir "Vistas de ATMOS" "$HOST_TIF_OUT"       /output_tif       /output_img
# De LSR solo se miran los índices de vegetación: los 14 surf_refl_* son
# reflectancias por banda, o sea dato, igual que las bandas M/I de Level 1.
vestir "Vistas de LSR"   "$HOST_LSR_TIF_OUT"   /output_lsr_tif   /output_lsr_img geotiff2view 'NDVI|EVI'
vestir "Vistas de SST"   "$HOST_ACSPO_TIF_OUT" /output_acspo_tif /output_acspo_img
# De incendios solo se viste confidence_cat: T4 y power son dato y no tienen CPT.
vestir "Vistas de incendios" "$HOST_FIRE_TIF_OUT" /output_fire_tif /output_fire_img geotiff2view 'confidence_cat'
# Flood ya viene como imagen: cspp_viirs_flood2tif.sh le pega la paleta flood.ct
# con add_colormap.py, así que solo hay que vestirlo. Es el único usuario que le
# queda a la rama de mapdrawer desde que se retiraron los RGB de superficie.
vestir "Vistas de inundaciones" "$HOST_FLOOD_TIF_IN" /output_flood_tif /output_flood_img \
       mapdrawer "${SAT_VISTA}_viirs_flood_${FECHA#d}_" 0 flood.cpt

# ==============================================================================
# VERIFICACIÓN
# ==============================================================================

contar_nuevos() {
    find "$1" -maxdepth 1 -name "$2" -newer "$REF_FILE" 2>/dev/null | wc -l
}

# Polar2Grid escribe su propio .log en el pwd, que aquí es el directorio de
# productos. Lo que dice ya quedó en $LOG_FILE, así que se descarta para no
# ensuciar el árbol de salida.
find "$HOST_TIF_OUT" "$HOST_LSR_TIF_OUT" "$HOST_ACSPO_TIF_OUT" "$HOST_FIRE_TIF_OUT" \
     -maxdepth 1 -name '*.log' -delete 2>/dev/null || true

TIF_ATMOS=$(contar_nuevos "$HOST_TIF_OUT"       '*.tif')
TIF_LSR=$(contar_nuevos   "$HOST_LSR_TIF_OUT"   '*.tif')
TIF_SST=$(contar_nuevos   "$HOST_ACSPO_TIF_OUT" '*.tif')
TIF_FIRE=$(contar_nuevos  "$HOST_FIRE_TIF_OUT"  '*.tif')
JPG_ATMOS=$(contar_nuevos "$HOST_IMG_OUT"       '*.jpg')
JPG_LSR=$(contar_nuevos   "$HOST_LSR_IMG_OUT"   '*.jpg')
JPG_SST=$(contar_nuevos   "$HOST_ACSPO_IMG_OUT" '*.jpg')
JPG_FIRE=$(contar_nuevos  "$HOST_FIRE_IMG_OUT"  '*.jpg')
JPG_FLOOD=$(contar_nuevos "$HOST_FLOOD_IMG_OUT" '*.jpg')

TIF_TOTAL=$((TIF_ATMOS + TIF_LSR + TIF_SST + TIF_FIRE))
JPG_TOTAL=$((JPG_ATMOS + JPG_LSR + JPG_SST + JPG_FIRE + JPG_FLOOD))

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
    echo "sst:         $TIF_SST geotiff, $JPG_SST vistas"
    echo "fire:        $TIF_FIRE geotiff, $JPG_FIRE vistas"
    echo "flood:       $JPG_FLOOD vistas (el geotiff lo hace run_flood_edr.sh)"
    echo "duracion:    $DURACION"
    echo "log:         $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: pasada $CLAVE — $TIF_TOTAL geotiff (atmos $TIF_ATMOS, lsr $TIF_LSR, sst $TIF_SST, fire $TIF_FIRE) y $JPG_TOTAL vistas (atmos $JPG_ATMOS, lsr $JPG_LSR, sst $JPG_SST, fire $JPG_FIRE, flood $JPG_FLOOD) en $DURACION" | tee -a "$LOG_FILE"
echo "   GeoTIFF:  $GEOTIFF"  | tee -a "$LOG_FILE"
echo "   Vistas:   $VISTAS"   | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER"   | tee -a "$LOG_FILE"
