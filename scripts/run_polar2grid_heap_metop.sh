#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Sondeos NUCAPS de METOP a GeoTIFF, vistas y Skew-T (Polar2Grid v3.2)
# ==============================================================================
#
# NUCAPS-EDR de IASI + AMSU-A + MHS (run_heap_metop.sh) → temperatura en 850,
# 700 y 500 hPa y de piel, en GeoTIFF y en vista, más un Skew-T por estación de
# config/sitios_skewt.tsv.
#
# Es la sección de sondeos de run_polar2grid_edr.sh —lector nucaps, rejilla de
# 5 km, paletas de rango fijo, la misma decoración con -s 1 y los mismos sitios
# de Skew-T— para que una vista de METOP y una de NOAA-20/21 se puedan poner
# lado a lado. Va aparte por lo mismo que run_polar2grid_mirs_metop.sh: allá la
# unidad es la pasada de VIIRS, aquí el crudo. Las paletas se repiten aquí: si
# cambian allá, cambiar aquí.
#
# Lo único que no es igual que en JPSS es que Polar2Grid no lee los NUCAPS de
# METOP tal como salen. HEAP llama a la dimensión de los perfiles
# Number_of_Dice, y el lector nucaps de Satpy (3.2) solo convierte en "y"
# number_of_FORs y Number_of_CrIS_FORs: con la de METOP, el remuestreo muere con
# "coordinate Time has dimensions ('Number_of_Dice',), but these are not a
# subset of the DataArray dimensions ('y', 'x')" (tahan, 2026-11-27). Por eso se
# copian los NUCAPS-EDR a un staging y ahí se renombra la dimensión a
# Number_of_CrIS_FORs, con el netCDF4 del bundle de Polar2Grid. Es solo el
# nombre: datos y atributos no se tocan, y los originales tampoco. Al pasar a
# Polar2Grid 3.3, ver si su Satpy ya conoce Number_of_Dice y quitar el paso.
# skewt no lo necesita (indexa por posición), pero lee las mismas copias.
#
# Qué NUCAPS-EDR son del crudo: los del mismo satélite cuyo inicio cae en la
# ventana del IASI 1C del manifiesto (IASI_xxx_1C_M0x_<inicio>Z_<fin>Z_…).
# HEAP no los nombra por crudo, y run_heap_metop.sh no los lista en su
# marcador. Si un gránulo salió dos veces (HEAP repetido con --force), se toma
# el de creación más reciente, como el staging de LSR con los JRR.
#
# El marcador va por la hora del primer gránulo y no por crudo —
# <m01|m03>_s<AAAAMMDDhhmmss>.done—, porque es la hora que Polar2Grid pone en
# el nombre del GeoTIFF (metopc_amsua-iasi-mhs_…_20261127_161648_…) y así
# publicar_dataservice.sh lo encuentra sin buscar. Adentro dice de qué crudo
# salió.
#
# Polar2Grid nombra los archivos con el platform_name del NetCDF, m01 o m03, que
# no está en su tabla de alias; se renombran a metopb_/metopc_, como los de
# AVHRR y MiRS de METOP, antes de vestir.
#
# Uso:
#   ./run_polar2grid_heap_metop.sh                 # el crudo más reciente con sondeo y sin render
#   ./run_polar2grid_heap_metop.sh <crudo>         # uno en concreto (nombre o ruta)
#   ./run_polar2grid_heap_metop.sh --force [crudo] # aunque ya tenga marcador
#
# Código de salida: 0 si salieron los GeoTIFF (una vista o un Skew-T fallido se
# cuenta en el marcador, pero no tumba el render, como en MiRS); 1 si no.
#
# Variables de entorno (para pruebas o rutas alternas):
#   HEAP_METOP_OUT      Entrada (NUCAPS-EDR)  (def. /data/output/metop/level2/sounder)
#   HEAP_METOP_STATE    Marcadores de HEAP    (def. /data/output/metop/state/cspp-heap)
#   METOP_STATE_DIR     Manifiestos .l1       (def. /data/output/metop/state/aapp)
#   HEAP_METOP_GEOTIFF  GeoTIFF               (def. /data/output/metop/geotiff/sounder)
#   HEAP_METOP_VISTAS   Vistas (y skewt/)     (def. /data/output/metop/vistas/sounder)
#   HEAP_METOP_P2G_STATE Marcadores .done     (def. /data/output/metop/state/polar2grid_heap)
#   HEAP_METOP_P2G_LOG  Raíz de logs          (def. /var/log/lanot/polares)
#   P2G_WORK_BASE       Raíz del staging      (def. /data/tmp)
#   P2G_CONTAINER       Imagen .sif           (def. /opt/containers/polar2grid_v3.2-mapdrawer.sif)
#   P2G_GRID_CONFIG     Rejillas propias      (def. <repo>/config/grid.yaml)
#   P2G_GRID_5KM        Rejilla               (def. wgs84_geo_5km)
#   P2G_COLORTABLES     Paletas del host      (def. /usr/local/share/lanot/colortables)
#   P2G_SITIOS_SKEWT    Sitios de Skew-T      (def. <repo>/config/sitios_skewt.tsv)
#
# ==============================================================================

set -euo pipefail

SIF_P2G="${P2G_CONTAINER:-/opt/containers/polar2grid_v3.2-mapdrawer.sif}"

HOST_IN="${HEAP_METOP_OUT:-/data/output/metop/level2/sounder}"
STATE_HEAP="${HEAP_METOP_STATE:-/data/output/metop/state/cspp-heap}"
STATE_L1="${METOP_STATE_DIR:-/data/output/metop/state/aapp}"
OUT_TIF="${HEAP_METOP_GEOTIFF:-/data/output/metop/geotiff/sounder}"
OUT_JPG="${HEAP_METOP_VISTAS:-/data/output/metop/vistas/sounder}"
OUT_SKEWT="$OUT_JPG/skewt"
STATE_DIR="${HEAP_METOP_P2G_STATE:-/data/output/metop/state/polar2grid_heap}"
LOG_DIR="${HEAP_METOP_P2G_LOG:-/var/log/lanot/polares}/polar2grid"
WORK_BASE="${P2G_WORK_BASE:-/data/tmp}"

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
GRID_CONFIG="${P2G_GRID_CONFIG:-$SCRIPT_DIR/../config/grid.yaml}"
GRID_5KM="${P2G_GRID_5KM:-wgs84_geo_5km}"
SITIOS_SKEWT="${P2G_SITIOS_SKEWT:-$SCRIPT_DIR/../config/sitios_skewt.tsv}"

COLORTABLES="${P2G_COLORTABLES:-/usr/local/share/lanot/colortables}"
BIND_CPT=()
[ -d "$COLORTABLES" ] && BIND_CPT=(--bind "$COLORTABLES:/usr/local/share/lanot/colortables:ro")

# El intérprete del bundle de Polar2Grid: es el que trae netCDF4.
PY_P2G=/opt/polar2grid/libexec/python_runtime/bin/python3

# Las de sondeos en run_polar2grid_edr.sh (PALETAS). Las cuatro van con -b:
# ninguna está en CPT_CON_NODATA_PROPIO de allá.
PALETAS=(
    "Skin_Temperature:nucaps_skin_temp.cpt"
    "Temperature_853mb:nucaps_temp_850.cpt"
    "Temperature_707mb:nucaps_temp_700.cpt"
    "Temperature_497mb:nucaps_temp_500.cpt"
)
SOUNDER_DATOS="Temperature_853mb Temperature_707mb Temperature_497mb Skin_Temperature"

# La de run_polar2grid_edr.sh con el -s 1 de los productos de 5 km, igual que
# run_polar2grid_mirs_metop.sh.
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
  $0                  El crudo más reciente con sondeo y sin render
  $0 <crudo>          Uno en concreto
  $0 --force [crudo]  Aunque ya tenga marcador

Requiere que run_heap_metop.sh haya terminado con marcador para ese crudo.
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

# Los NUCAPS-EDR de un crudo, uno por gránulo (el de creación más reciente),
# ordenados por hora de inicio. Rellena MISION, SATELITE y EDRS; devuelve 1 con
# un mensaje si el manifiesto no deja saber la ventana.
edr_del_crudo() {
    local crudo="$1" iasi ini fin f n s c
    local -A elegido=() creacion=()
    iasi=$(grep -m1 -E '^iasi/IASI_xxx_1C_M0[13]_[0-9]{14}Z_[0-9]{14}Z' "$STATE_L1/$crudo.l1" 2>/dev/null || true)
    if [ -z "$iasi" ]; then
        echo "ERROR: el manifiesto $STATE_L1/$crudo.l1 no trae el IASI 1C: no se sabe la ventana" >&2
        return 1
    fi
    [[ "$(basename "$iasi")" =~ _M0([13])_([0-9]{14})Z_([0-9]{14})Z ]]
    case "${BASH_REMATCH[1]}" in
        1) MISION=m01; SATELITE=Metop-B; SAT_P2G=metopb ;;
        3) MISION=m03; SATELITE=Metop-C; SAT_P2G=metopc ;;
    esac
    ini="${BASH_REMATCH[2]}"; fin="${BASH_REMATCH[3]}"
    for f in "$HOST_IN"/NUCAPS-EDR_*_"${MISION}"_s*_e*_c*.nc; do
        [ -e "$f" ] || continue
        n=$(basename "$f")
        [[ "$n" =~ _s([0-9]{14})[0-9]*_e[0-9]+_c([0-9]+)\.nc$ ]] || continue
        s="${BASH_REMATCH[1]}"; c="${BASH_REMATCH[2]}"
        [[ ! "$s" < "$ini" && ! "$s" > "$fin" ]] || continue
        if [ -z "${creacion[$s]:-}" ] || [[ "$c" > "${creacion[$s]}" ]]; then
            creacion[$s]="$c"; elegido[$s]="$f"
        fi
    done
    EDRS=()
    for s in $(printf '%s\n' "${!elegido[@]}" | sort); do
        EDRS+=("${elegido[$s]}")
    done
    return 0
}

# ==============================================================================
# ARGUMENTOS Y SELECCIÓN
# ==============================================================================

FORCE=0
CRUDO=""
while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        -h|--help)  uso; exit 0 ;;
        -*) echo "ERROR: Opción desconocida: $1" >&2; uso >&2; exit 1 ;;
        *)
            [ -z "$CRUDO" ] || { echo "ERROR: Solo se admite un crudo por ejecución" >&2; exit 1; }
            CRUDO="$(basename "$1")"
            ;;
    esac
    shift
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')
cd / || exit 1

MISION=""; SATELITE=""; SAT_P2G=""; EDRS=()

# Clave del render: satélite y hora del primer gránulo, la del nombre del GeoTIFF.
clave_de() { local s; s=$(basename "$1" | grep -oE '_s[0-9]{14}' | head -1); echo "${MISION}${s}"; }

if [ -z "$CRUDO" ]; then
    while IFS= read -r m; do
        c="$(basename "$m" .done)"
        edr_del_crudo "$c" 2>/dev/null || continue
        [ "${#EDRS[@]}" -gt 0 ] || continue
        k="$STATE_DIR/$(clave_de "${EDRS[0]}").done"
        if [ "$FORCE" -eq 1 ] || [ ! -f "$k" ] || [ "$m" -nt "$k" ]; then
            CRUDO="$c"
            break
        fi
    done < <(find "$STATE_HEAP" -maxdepth 1 -name '*.done' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
    if [ -z "$CRUDO" ]; then
        echo "No hay sondeos de METOP pendientes de render en $STATE_HEAP."
        exit 0
    fi
fi

MARKER_HEAP="$STATE_HEAP/$CRUDO.done"
if [ ! -f "$MARKER_HEAP" ]; then
    echo "ERROR: $CRUDO no tiene sondeo terminado (falta $MARKER_HEAP)." >&2
    echo "       Corre antes: run_heap_metop.sh $CRUDO" >&2
    exit 1
fi

edr_del_crudo "$CRUDO" || exit 1
if [ "${#EDRS[@]}" -eq 0 ]; then
    echo "ERROR: $CRUDO tiene marcador de HEAP pero no hay NUCAPS-EDR de $MISION en la ventana de su IASI" >&2
    echo "       en $HOST_IN (¿lo borró la retención?)." >&2
    exit 1
fi
CLAVE="$(clave_de "${EDRS[0]}")"

echo "=== POLAR2GRID v3.2 | Sondeos NUCAPS | $SATELITE | $CRUDO ($CLAVE, ${#EDRS[@]} gránulos) ==="

MARKER="$STATE_DIR/$CLAVE.done"
if [ -f "$MARKER" ] && [ "$MARKER" -nt "$MARKER_HEAP" ] && [ "$FORCE" -eq 0 ]; then
    echo ""
    echo "ℹ  $CRUDO ya fue renderizado:"
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

mkdir -p "$OUT_TIF" "$OUT_JPG" "$OUT_SKEWT" "$STATE_DIR" "$LOG_DIR"
LOG_FILE="$LOG_DIR/p2g_heap_metop_${TIMESTAMP}_${CRUDO}.log"

# p2g_staging_…: el prefijo que limpiar.sh poda en /data/tmp (retencion.tsv).
STAGING="$WORK_BASE/p2g_staging_heap_metop_${CLAVE}_$$"
mkdir -p "$STAGING"
REF_FILE="$STAGING/.inicio"
touch "$REF_FILE"
# Se conserva si algo falla, para depurar; se borra al final si todo salió.
trap 'echo "   Se conserva el staging: $STAGING" >&2' EXIT

cp -p "${EDRS[@]}" "$STAGING"/

BINDS=(
    "${BIND_CPT[@]}"
    --bind "$STAGING":/input_sounder
    --bind "$GRID_CONFIG":/config/grid.yaml:ro
    --bind "$OUT_TIF":/output_tif
    --bind "$OUT_JPG":/output_jpg
    --bind "$OUT_SKEWT":/output_skewt
)

en_contenedor_uno() {
    local codigo=0
    apptainer exec "${BINDS[@]}" "$SIF_P2G" "$@" >> "$LOG_FILE" 2>&1 || codigo=$?
    return $codigo
}

{
    echo "crudo:    $CRUDO"
    echo "clave:    $CLAVE"
    printf 'entrada:  %s\n' "${EDRS[@]}"
} >> "$LOG_FILE"

# ==============================================================================
# ETAPA 0: LA DIMENSIÓN QUE SATPY NO CONOCE
# ==============================================================================

echo "--- Number_of_Dice → Number_of_CrIS_FORs ---" >> "$LOG_FILE"
CODIGO=0
en_contenedor_uno "$PY_P2G" -c '
import glob, sys, netCDF4
n = 0
for f in sorted(glob.glob("/input_sounder/NUCAPS-EDR*.nc")):
    with netCDF4.Dataset(f, "a") as d:
        if "Number_of_Dice" in d.dimensions:
            d.renameDimension("Number_of_Dice", "Number_of_CrIS_FORs")
            n += 1
print(f"renombrada en {n} archivos")
' || CODIGO=$?
if [ "$CODIGO" -ne 0 ]; then
    echo "❌ ERROR: no se pudo renombrar la dimensión de los NUCAPS-EDR (código $CODIGO). Ver $LOG_FILE" | tee -a "$LOG_FILE" >&2
    exit 1
fi

# ==============================================================================
# ETAPA 1: REMUESTREO
# ==============================================================================
# -p obligatorio y sin --method, como en JPSS (ver allí por qué; la máscara de
# calidad se queda puesta).

echo "  Rejilla: $GRID_5KM" | tee -a "$LOG_FILE"
echo "--- polar2grid.sh ---" >> "$LOG_FILE"
CODIGO_P2G=0
en_contenedor_uno /bin/bash -c "cd /output_tif && polar2grid.sh -r nucaps -w geotiff -p $SOUNDER_DATOS --grid-configs /config/grid.yaml -g $GRID_5KM --dtype float32 --no-enhance -f /input_sounder/NUCAPS-EDR*.nc" \
    || CODIGO_P2G=$?

find "$OUT_TIF" -maxdepth 1 -name '*.log' -newer "$REF_FILE" -delete 2>/dev/null || true

# m01_/m03_ → metopb_/metopc_. mv conserva el mtime: siguen siendo "de esta corrida".
while IFS= read -r -d '' tif; do
    nombre="$(basename "$tif")"
    mv -f "$tif" "$OUT_TIF/${SAT_P2G}_${nombre#*_}"
done < <(find "$OUT_TIF" -maxdepth 1 -type f -name "${MISION}_*.tif" -newer "$REF_FILE" -print0)

mapfile -t TIFS < <(find "$OUT_TIF" -maxdepth 1 -name "${SAT_P2G}_*.tif" -newer "$REF_FILE" -printf '%f\n' | sort)

if [ "$CODIGO_P2G" -ne 0 ] || [ ${#TIFS[@]} -eq 0 ]; then
    echo "❌ ERROR: Polar2Grid (código $CODIGO_P2G) dejó ${#TIFS[@]} GeoTIFF. Ver $LOG_FILE" | tee -a "$LOG_FILE" >&2
    exit 1
fi

# ==============================================================================
# ETAPA 2: VISTAS
# ==============================================================================
# Una llamada por archivo para leer el código de geotiff2view (3 = sin un píxel
# válido: no es fallo y no se publica una imagen vacía).

GENERADAS=0; VACIAS=0; FALLIDAS=0
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

# ==============================================================================
# ETAPA 3: SKEW-T
# ==============================================================================
# Como en run_polar2grid_edr.sh: el FOR más cercano a cada estación en todos los
# gránulos de la pasada; 3 es "fuera de la franja o perfil rechazado por
# NUCAPS", que es lo normal para la mayoría de los sitios en cada pasada.

SKEWT_OK=0; SKEWT_SIN=0; SKEWT_ERR=0
if [ -f "$SITIOS_SKEWT" ]; then
    echo "--- Skew-T ---" >> "$LOG_FILE"
    mapfile -t NUCAPS_PASADA < <(find "$STAGING" -maxdepth 1 -name 'NUCAPS-EDR*.nc' -printf '/input_sounder/%f\n' | sort)
    s="${CLAVE#*_s}"
    while IFS=$'\t' read -r omm clave lat lon nombre; do
        [[ "$omm" =~ ^[0-9]+$ ]] || continue
        codigo=0
        # < /dev/null: si no, apptainer se come el resto de la tabla de sitios.
        en_contenedor_uno skewt "${NUCAPS_PASADA[@]}" --lat "$lat" --lon "$lon" \
            --title "$SATELITE · $nombre ($omm)" \
            -o "/output_skewt/${SAT_P2G}_amsua-iasi-mhs_skewt_${omm}_${clave}_${s:0:8}_${s:8:6}.svg" \
            < /dev/null || codigo=$?
        case "$codigo" in
            0) SKEWT_OK=$((SKEWT_OK + 1)) ;;
            3) SKEWT_SIN=$((SKEWT_SIN + 1)) ;;
            *) SKEWT_ERR=$((SKEWT_ERR + 1))
               echo "  ⚠ Skew-T de $nombre falló (código $codigo)" | tee -a "$LOG_FILE" ;;
        esac
    done < "$SITIOS_SKEWT"
else
    echo "  ⚠ Sin tabla de sitios ($SITIOS_SKEWT): no se dibujan Skew-T" | tee -a "$LOG_FILE"
fi

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

{
    echo "renderizado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "crudo:       $CRUDO"
    echo "satelite:    $SATELITE"
    echo "granulos:    ${#EDRS[@]}"
    echo "geotiff:     ${#TIFS[@]} (${TIFS[*]})"
    echo "vistas:      $GENERADAS generadas, $VACIAS sin datos, $FALLIDAS con error"
    echo "skewt:       $SKEWT_OK diagramas, $SKEWT_SIN sitios sin sondeo, $SKEWT_ERR con error"
    echo "duracion:    $DURACION"
    echo "log:         $LOG_FILE"
} > "$MARKER"

trap - EXIT
rm -rf "$STAGING"

echo "✅ $CRUDO: ${#TIFS[@]} GeoTIFF, $GENERADAS vistas ($VACIAS sin datos, $FALLIDAS con error), $SKEWT_OK Skew-T ($SKEWT_SIN sitios sin sondeo, $SKEWT_ERR con error) en $DURACION" | tee -a "$LOG_FILE"
echo "   GeoTIFF: $OUT_TIF" | tee -a "$LOG_FILE"
echo "   Vistas:  $OUT_JPG" | tee -a "$LOG_FILE"
