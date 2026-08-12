#!/bin/bash
#SBATCH --job-name=cspp_lsr_edr
#SBATCH --output=logs/lsr_%j.out
#SBATCH --error=logs/lsr_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --partition=normal
# ==============================================================================
# LANOT - UNAM | CSPP Land Surface Reflectance (LSR) EDR v2.0
# ==============================================================================
#
# Level 1 (SDR de VIIRS) + Level 2 atmosphere → SurfRefl_*.nc
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue procesada con éxito, avisa y no hace nada. Una pasada se identifica
# por satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
#
# LSR no usa ancillary dinámico (manual §1.5: "No dynamic ancillary data inputs
# are required"), así que no depende de la red.
#
# Uso:
#   ./run_lsr_edr.sh            # la pasada más reciente pendiente
#   ./run_lsr_edr.sh --force    # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   LSR_SDR_IN     Entrada Level 1   (def. /data/output/jpss/level1/viirs)
#   LSR_ATMOS_IN   Entrada atmosphere(def. /data/output/jpss/level2/atmosphere)
#   LSR_OUT        Salida            (def. /data/output/jpss/level2/lsr)
#   LSR_STATE_DIR  Marcadores .done  (def. /data/output/jpss/state/cspp-lsr)
#   LSR_CONTAINER  Imagen .sif       (def. /opt/containers/cspp_lsr_edr_v2.0.sif)
#   LSR_WORK_BASE  Raíz de staging   (def. /data/output/jpss/tmp)
#   LSR_LOG_BASE   Raíz de logs      (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_IMAGE="${LSR_CONTAINER:-/opt/containers/cspp_lsr_edr_v2.0.sif}"

INPUT_SDR_DIR="${LSR_SDR_IN:-/data/output/jpss/level1/viirs}"
INPUT_ATMOS_DIR="${LSR_ATMOS_IN:-/data/output/jpss/level2/atmosphere}"
OUTPUT_LSR_DIR="${LSR_OUT:-/data/output/jpss/level2/lsr}"
STATE_DIR="${LSR_STATE_DIR:-/data/output/jpss/state/cspp-lsr}"

WORK_BASE="${LSR_WORK_BASE:-/data/output/jpss/tmp}"
LOG_DIR="${LSR_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

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
  -f, --force          Ignora el marcador de procesado
  -k, --keep-staging   Conserva el directorio de enlaces, para diagnosticar
                       qué vio realmente el contenedor
  -h, --help           Muestra esta ayuda
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

# Calcula la ventana temporal de la pasada a partir del SDR agregado:
#   GMTCO_j01_d20260811_t1947330_e2003097_b45236_... -> 202608111947330 .. 202608112003097
# Deja el resultado en VENTANA_INI, VENTANA_FIN y las fechas a considerar.
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
}

# Devuelve el sello temporal de un producto como AAAAMMDDHHMMSS, o código 1 si
# no lo reconoce. En Level 2 conviven dos convenciones:
#   JRR-CloudMask_v3r2_j01_s202608111947330_e...    -> fecha + hora + décimas
#   NOAA20_VIIRS_750M_2026223_1947_33_NWP_GFS-INTP  -> año + día juliano + HHMM_SS
sello_de_archivo() {
    local nombre="$1" s anio doy fecha

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
de_otro_satelite() {
    case "$SAT" in
        j01) echo "$1" | grep -qiE "j02|noaa21|npp" ;;
        j02) echo "$1" | grep -qiE "j01|noaa20|npp" ;;
        npp) echo "$1" | grep -qiE "j01|noaa20|j02|noaa21" ;;
        *)   return 1 ;;
    esac
}

# Enlaza un archivo en el staging. Se prefiere el enlace DURO: algunas
# herramientas recorren la entrada con "find -type f", que no encuentra enlaces
# simbólicos (son -type l), y entonces reportan que no hay archivos aunque estén
# a la vista. El enlace duro es indistinguible de un archivo normal y no cuesta
# espacio. Si origen y destino están en sistemas de archivos distintos, no se
# puede, y se recurre al simbólico.
enlazar() {
    ln -f "$1" "$2" 2>/dev/null || ln -sf "$1" "$2"
}

# Enlaza los productos de $2 cuyo sello temporal cae dentro de la ventana de la
# pasada. No se puede emparejar gránulo por gránulo: los SDR llegan agregados
# (un archivo por banda para toda la pasada, con un solo GMTCO), mientras que
# los productos de Level 2 son por gránulo. El sello de cada producto lo
# normaliza sello_de_archivo(), que entiende las dos convenciones de nombres.
enlazar_en_ventana() {
    local destino="$1" origen="$2" enlazados=0 f nombre sello

    shopt -s nullglob
    for f in "$origen"/*.nc; do
        nombre=$(basename "$f")
        de_otro_satelite "$nombre" && continue
        sello=$(sello_de_archivo "$nombre") || continue

        if [ "$sello" -ge "$VENTANA_INI" ] && [ "$sello" -le "$VENTANA_FIN" ]; then
            enlazar "$f" "$destino"/
            enlazados=$((enlazados + 1))
        fi
    done
    shopt -u nullglob

    echo "$enlazados"
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================

FORCE=0
KEEP=0

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)      FORCE=1 ;;
        -k|--keep-staging) KEEP=1 ;;
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
STAGING_DIR="${WORK_BASE}/lsr_staging_${JOB_ID}"

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

echo "=== CSPP LSR v2.0 | pasada $CLAVE ==="

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
    echo "       LSR necesita los JRR-* de la misma pasada: corre run_atmos_edr.sh antes." >&2
    exit 1
fi

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================

mkdir -p "$STAGING_DIR" "$OUTPUT_LSR_DIR" "$LOG_DIR" "$STATE_DIR"
limpiar() {
    if [ "$KEEP" -eq 1 ]; then
        echo "--keep-staging: se conserva $STAGING_DIR"
        rm -f "${REF_FILE:-}"
    else
        rm -rf "$STAGING_DIR" "${REF_FILE:-}"
    fi
}
trap limpiar EXIT

shopt -s nullglob
for f in "$INPUT_SDR_DIR"/*_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5; do
    enlazar "$f" "$STAGING_DIR"/
done
shopt -u nullglob

SDR_COUNT=$(find "$STAGING_DIR" -name '*.h5' | wc -l)

if [ "$SDR_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR de la pasada $CLAVE" >&2
    exit 1
fi

ventana_de_pasada "$ULTIMO_GMTCO"
GRANULOS_ATMOS=$(enlazar_en_ventana "$STAGING_DIR" "$INPUT_ATMOS_DIR")

if [ "$GRANULOS_ATMOS" -eq 0 ]; then
    echo "ERROR: No hay productos de ATMOS para la pasada $CLAVE en $INPUT_ATMOS_DIR" >&2
    echo "       Corre run_atmos_edr.sh para esa pasada antes que LSR." >&2
    exit 1
fi

LOG_FILE="$LOG_DIR/lsr_edr_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR:      $SDR_COUNT archivos"                       | tee -a "$LOG_FILE"
echo "  ATMOS:    $GRANULOS_ATMOS productos en $VENTANA_INI-$VENTANA_FIN" | tee -a "$LOG_FILE"
echo "  Salida:   $OUTPUT_LSR_DIR"                           | tee -a "$LOG_FILE"
echo "  Hilos:    $CORES"                                    | tee -a "$LOG_FILE"

# ==============================================================================
# EJECUCIÓN
# ==============================================================================

REF_FILE=$(mktemp -t lsr_edr_ref_XXXXXX)

EXIT_CODE=0
apptainer exec \
    --env LC_ALL=C \
    --env CSPP_VIIRS_LSR_V2_HOME=/opt/cspp-surf_refl \
    -B "${STAGING_DIR}":/input_data \
    -B "${OUTPUT_LSR_DIR}":/output_data \
    -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}" \
    -B "${INPUT_ATMOS_DIR}":"${INPUT_ATMOS_DIR}" \
    "${SIF_IMAGE}" \
    /opt/cspp-surf_refl/run_cspp_lsr_v2.sh -o /output_data -p "${CORES}" /input_data \
    >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP LSR falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                 | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN DE PRODUCTOS
# ==============================================================================

NC_COUNT=$(find "$OUTPUT_LSR_DIR" -maxdepth 1 -name '*.nc' -newer "$REF_FILE" 2>/dev/null | wc -l)

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: CSPP LSR terminó sin error pero no generó productos." | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                    | tee -a "$LOG_FILE"
    exit 1
fi

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "sdr:       $SDR_COUNT archivos de entrada"
    echo "productos: $NC_COUNT archivos .nc"
    echo "duracion:  $DURACION"
    echo "salida:    $OUTPUT_LSR_DIR"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE en $OUTPUT_LSR_DIR ($DURACION)" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"
