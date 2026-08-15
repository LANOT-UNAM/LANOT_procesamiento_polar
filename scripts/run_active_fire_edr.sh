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
# Level 1 (SDR de VIIRS) → detección de incendios (AF*.nc)
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue procesada con éxito, avisa y no hace nada. Una pasada se identifica
# por satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
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
#   FIRE_WORK_BASE  Raíz de staging  (def. /data/tmp)
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
                (j01_d20260813_b45264) o cualquier trozo que la identifique
  -h, --help    Muestra esta ayuda

Pasadas disponibles en $INPUT_SDR_DIR:
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
    find "$INPUT_SDR_DIR" -maxdepth 1 -name 'GMTCO*.h5' -printf '%f\n' 2>/dev/null |
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
        ULTIMO_GMTCO=$(find "$INPUT_SDR_DIR" -maxdepth 1 -name 'GMTCO*.h5' \
                            -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        return 0
    fi

    # --pasada acepta la clave completa o cualquier trozo que la identifique:
    # "j01_d20260813_b45264", "d20260813" o hasta "45264". Se resuelve contra las
    # pasadas que de verdad estén en el directorio, así que un valor ambiguo o
    # inexistente se caza aquí y no a media corrida.
    mapfile -t coinciden < <(claves_disponibles | grep -F -- "$PASADA" || true)

    if [ "${#coinciden[@]}" -eq 0 ]; then
        echo "ERROR: Ninguna pasada de $INPUT_SDR_DIR coincide con '$PASADA'" >&2
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
    ULTIMO_GMTCO=$(find "$INPUT_SDR_DIR" -maxdepth 1 -name "GMTCO_${sat}_${fecha}_*_${orbita}_*.h5" \
                        | sort | head -1)
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

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$INPUT_SDR_DIR" ]; then
    echo "ERROR: Directorio de SDR no encontrado: $INPUT_SDR_DIR" >&2
    exit 1
fi

resolver_pasada || exit 1

if [ -z "$ULTIMO_GMTCO" ]; then
    echo "No hay SDR que procesar en $INPUT_SDR_DIR (no se ven archivos GMTCO*)."
    exit 0
fi

if ! CLAVE=$(clave_de_pasada "$ULTIMO_GMTCO"); then
    echo "ERROR: No se pudo derivar la pasada del nombre: $(basename "$ULTIMO_GMTCO")" >&2
    exit 1
fi

IFS='_' read -r SAT FECHA ORBITA <<< "$CLAVE"

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

ln -sf "$INPUT_SDR_DIR"/*_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5 "$STAGING_DIR"/ 2>/dev/null || true

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
# --pwd /output_data: el ejecutable escribe en el directorio actual.

REF_FILE=$(mktemp -t fire_ref_XXXXXX)
trap 'rm -rf "$STAGING_DIR" "$REF_FILE"' EXIT

EXIT_CODE=0
apptainer exec \
    --env LC_ALL=C \
    --env CSPP_ACTIVE_FIRE_CACHE_DIR=/cache \
    -B "${STAGING_DIR}":/input_data \
    -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}" \
    -B "${OUTPUT_DIR}":/output_data \
    -B "${HOST_CACHE}":/cache \
    --pwd /output_data \
    "${SIF_IMAGE}" \
    /bin/bash -c "source ${ENV_SCRIPT} && ${EXEC_SCRIPT} -v /input_data" \
    >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP Active Fire falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                         | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN DE PRODUCTOS
# ==============================================================================

NC_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 -name '*.nc' -newer "$REF_FILE" 2>/dev/null | wc -l)

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: Active Fire terminó sin error pero no generó productos." | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                       | tee -a "$LOG_FILE"
    exit 1
fi

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "sdr:       $SDR_COUNT archivos de entrada"
    echo "productos: $NC_COUNT archivos .nc"
    echo "duracion:  $DURACION"
    echo "salida:    $OUTPUT_DIR"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE en $OUTPUT_DIR ($DURACION)" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"
