#!/bin/bash
#SBATCH --job-name=cspp_active_fire
#SBATCH --output=/var/log/lanot/polares/cspp-edr/slurm_fire_%j.out
#SBATCH --error=/var/log/lanot/polares/cspp-edr/slurm_fire_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --partition=normal
# ==============================================================================
# LANOT - UNAM | CSPP VIIRS Active Fire v2.1
# ==============================================================================
#
# Level 1 (SDR de VIIRS) → detección de incendios, en las dos resoluciones:
#
#   AFIMG_*.nc   banda I, 375 m. Confianza por categoría: 7, 8, 9 (baja,
#                nominal, alta). Es lo que hace el driver por omisión.
#   AFMOD_*.nc   banda M, 750 m. Confianza en porcentaje, 0-100. Solo sale con
#                -M, en una corrida aparte (manual §3): hasta el 2026-10-23 no
#                se pedía y la cadena solo tenía la de 375 m.
#
# Las dos corridas van en directorios de trabajo propios bajo /data/tmp y solo
# los .nc pasan a la salida. Antes el pwd era la salida, y el driver dejaba ahí
# sus NOAA_AFIMG_*.log y cspp_active_fire_noaa.*.log (2144 desde mayo).
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue procesada con éxito, avisa y no hace nada. Una pasada se identifica
# por satélite, fecha y hora de inicio (p. ej. j01_d20260811_t194733;
# ver pasadas.sh).
#
# No usa ancillary dinámico descargado, pero sí genera máscaras de tierra/agua
# granuladas para la región procesada. Se guardan en un caché persistente
# (CSPP_ACTIVE_FIRE_CACHE_DIR) para no rehacerlas en cada pasada.
#
# Uso:
#   ./run_active_fire_edr.sh            # la pasada más reciente pendiente
#   ./run_active_fire_edr.sh --force    # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   FIRE_SDR_IN     Entrada Level 1  (def. /data/output/jpss/level1/viirs)
#   FIRE_OUT        Salida           (def. /data/output/jpss/level2/fires)
#   FIRE_STATE_DIR  Marcadores .done (def. /data/output/jpss/state/cspp-active-fire)
#   FIRE_CACHE      Máscaras tierra/agua (def. /data/ancillary/active_fire_cache)
#   FIRE_CONTAINER  Imagen .sif      (def. /opt/containers/cspp_active_fire_edr_v2.1.sif)
#   FIRE_WORK_BASE  Raíz de staging y trabajo (def. /data/tmp)
#   FIRE_LOG_BASE   Raíz de logs     (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_IMAGE="${FIRE_CONTAINER:-/opt/containers/cspp_active_fire_edr_v2.1.sif}"

INPUT_SDR_DIR="${FIRE_SDR_IN:-/data/output/jpss/level1/viirs}"
OUTPUT_DIR="${FIRE_OUT:-/data/output/jpss/level2/fires}"
STATE_DIR="${FIRE_STATE_DIR:-/data/output/jpss/state/cspp-active-fire}"
HOST_CACHE="${FIRE_CACHE:-/data/ancillary/active_fire_cache}"

WORK_BASE="${FIRE_WORK_BASE:-/data/tmp}"
LOG_DIR="${FIRE_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

CONTAINER_HOME="/opt/cspp-active-fire-noaa_2.1"
ENV_SCRIPT="${CONTAINER_HOME}/cspp_active_fire_noaa_env.sh"
EXEC_SCRIPT="${CONTAINER_HOME}/bin/cspp_active_fire_noaa.sh"

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
  -p, --pasada  Pasada concreta en vez de la más reciente: la clave completa
                (j01_d20260813_t191402) o cualquier trozo que la identifique
  -h, --help    Muestra esta ayuda

Pasadas disponibles en $INPUT_SDR_DIR:
$(listar_pasadas "$INPUT_SDR_DIR" GMTCO 2>/dev/null | cut -d' ' -f1 | sed 's/^/  /' || true)
EOF
}

# Qué es una pasada y cómo se elige: por tiempo, no por órbita (ver pasadas.sh).
# Fija CLAVE, SAT, FECHA y la ventana VENTANA_INI – VENTANA_FIN.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/pasadas.sh"

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
STAGING_DIR="${WORK_BASE}/fire_staging_${JOB_ID}"
WORK_DIR="${WORK_BASE}/fire_work_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$INPUT_SDR_DIR" ]; then
    echo "ERROR: Directorio de SDR no encontrado: $INPUT_SDR_DIR" >&2
    exit 1
fi

resolver_pasada "$INPUT_SDR_DIR" GMTCO "$PASADA" || exit 1

if [ -z "$CLAVE" ]; then
    echo "No hay SDR que procesar en $INPUT_SDR_DIR (no se ven archivos GMTCO*)."
    exit 0
fi

echo "=== CSPP Active Fire v2.1 | pasada $CLAVE ==="

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
# VALIDACIÓN Y STAGING
# ==============================================================================

if [ ! -f "$SIF_IMAGE" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_IMAGE" >&2
    exit 1
fi

mkdir -p "$STAGING_DIR" "$OUTPUT_DIR" "$HOST_CACHE" "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$STAGING_DIR"' EXIT

while IFS= read -r f; do
    ln -sf "$f" "$STAGING_DIR"/
done < <(archivos_de_pasada "$INPUT_SDR_DIR" '*')

SDR_COUNT=$(find "$STAGING_DIR" -name '*.h5' | wc -l)

if [ "$SDR_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR de la pasada $CLAVE" >&2
    exit 1
fi

LOG_FILE="$LOG_DIR/active_fire_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR:     $SDR_COUNT archivos"  | tee -a "$LOG_FILE"
echo "  Salida:  $OUTPUT_DIR"          | tee -a "$LOG_FILE"
echo "  Caché:   $HOST_CACHE"          | tee -a "$LOG_FILE"

# ==============================================================================
# EJECUCIÓN
# ==============================================================================
# Dos corridas: la de banda I (por omisión) y la de banda M (-M). Cada una en su
# propio directorio de trabajo, que es el pwd: ahí deja el driver los .nc y sus
# logs. Los .nc se mueven a la salida; lo demás se va con el directorio si todo
# salió bien, y se queda para depurar si no.

REF_FILE=$(mktemp -t fire_ref_XXXXXX)
trap 'rm -rf "$STAGING_DIR" "$REF_FILE"' EXIT

mkdir -p "$WORK_DIR/img" "$WORK_DIR/mod"

# correr_fire <subdirectorio> <etiqueta> [opciones del driver]
# Deja en CODIGO_<etiqueta> el código de salida y en N_<etiqueta> los .nc movidos.
correr_fire() {
    local sub="$1" etiqueta="$2"; shift 2
    local codigo=0 n

    echo "--- $etiqueta ${*:-} --- $(date +%H:%M:%S)" >> "$LOG_FILE"
    apptainer exec \
        --env LC_ALL=C \
        --env CSPP_ACTIVE_FIRE_CACHE_DIR=/cache \
        -B "${STAGING_DIR}":/input_data \
        -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}" \
        -B "${WORK_DIR}/${sub}":/work \
        -B "${HOST_CACHE}":/cache \
        --pwd /work \
        "${SIF_IMAGE}" \
        /bin/bash -c "source ${ENV_SCRIPT} && ${EXEC_SCRIPT} -v $* /input_data" \
        >> "$LOG_FILE" 2>&1 || codigo=$?

    n=0
    while IFS= read -r -d '' f; do
        mv -f "$f" "$OUTPUT_DIR"/ && n=$((n + 1))
    done < <(find "$WORK_DIR/$sub" -maxdepth 1 -name "${etiqueta}_*.nc" -print0)

    printf -v "CODIGO_${etiqueta}" '%s' "$codigo"
    printf -v "N_${etiqueta}" '%s' "$n"
}

correr_fire img AFIMG
correr_fire mod AFMOD -M

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

# ==============================================================================
# VERIFICACIÓN DE PRODUCTOS
# ==============================================================================
# Cada resolución tiene que haber terminado en 0 Y producido algo: el código de
# salida solo no basta (ver CLAUDE.md, "Estado"). Si una falla, la etapa falla
# y no se escribe el marcador, aunque lo de la otra ya esté en la salida: al
# reintentar se rehacen las dos, y el duplicado de la que salió bien lo absorbe
# run_polar2grid_edr.sh, que enlaza el _c<creación> más reciente de cada gránulo.

FALLO=0
for etiqueta in AFIMG AFMOD; do
    codigo_var="CODIGO_${etiqueta}"; n_var="N_${etiqueta}"
    if [ "${!codigo_var}" -ne 0 ]; then
        echo "❌ ERROR: $etiqueta falló (código ${!codigo_var})" | tee -a "$LOG_FILE"
        FALLO=1
    elif [ "${!n_var}" -eq 0 ]; then
        echo "❌ ERROR: $etiqueta terminó sin error pero no generó productos" | tee -a "$LOG_FILE"
        FALLO=1
    fi
done

if [ "$FALLO" -ne 0 ]; then
    echo "   Tras $DURACION. Revisa el log: $LOG_FILE"   | tee -a "$LOG_FILE"
    echo "   Directorio de trabajo conservado: $WORK_DIR" | tee -a "$LOG_FILE"
    exit 1
fi

rm -rf "$WORK_DIR"
NC_COUNT=$((N_AFIMG + N_AFMOD))

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "sdr:       $SDR_COUNT archivos de entrada"
    echo "productos: $NC_COUNT archivos .nc ($N_AFIMG AFIMG, $N_AFMOD AFMOD)"
    echo "duracion:  $DURACION"
    echo "salida:    $OUTPUT_DIR"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE ($N_AFIMG AFIMG, $N_AFMOD AFMOD) en $OUTPUT_DIR ($DURACION)" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"
