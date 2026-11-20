#!/bin/bash
#SBATCH --job-name=mirs_metop
#SBATCH --cpus-per-task=8
#SBATCH --output=/var/log/lanot/polares/cspp-edr/slurm_mirs_metop_%j.log
# ==============================================================================
# LANOT - UNAM | CSPP MiRS v4.0 para METOP-B/C (AMSU-A + MHS → Level 2)
# ==============================================================================
#
# AMSU-A y MHS 1b de una pasada → NPR-MIRS-IMG (lluvia, agua precipitable, agua
# líquida de nube, temperatura de piel, temperaturas de brillo con corrección
# de limbo) y NPR-MIRS-SND (perfiles), con la misma imagen que la rama JPSS
# (run_mirs_edr.sh). Complementa a ATMS: unas cuatro pasadas más al día sobre
# México, a otras horas. La cadena vieja no lo producía.
#
# Por qué un script aparte, como run_heap_metop.sh: allá la unidad es la pasada
# de SDR, agrupada por tiempo (pasadas.sh); aquí es el crudo, y los dos
# insumos vienen en el manifiesto del Level 1 (<crudo>.l1).
#
# MiRS no lee los .l1b de AAPP tal cual: se le da una copia de trabajo con dos
# ajustes en la cabecera, el código de sitio (LNT → SSE) y la hora del MHS
# alineada con la del AMSU-A. Por qué, en metop_l1b_para_mirs.py.
#
# Resolución: -r HI (la de omisión), AMSU-A interpolado a la huella de MHS,
# ~16 km en nadir. Ancillary: como en JPSS, --noSFR -l, sin descargar nada,
# pero con el caché escribible que el driver exige (-d).
#
# TZ=UTC dentro del contenedor: el campo de creación del nombre (_c…) sale de
# la hora local, y en tahan eso es CST con apariencia de UTC.
#
# Uso:
#   ./run_mirs_metop.sh                   # el crudo más reciente con L1 y sin MiRS
#   ./run_mirs_metop.sh <crudo>           # uno en concreto (nombre o ruta)
#   ./run_mirs_metop.sh --force [crudo]   # aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   METOP_OUTPUT_DIR   Level 1 de METOP      (def. /data/output/metop/level1)
#   METOP_STATE_DIR    Manifiestos .l1       (def. /data/output/metop/state/aapp)
#   MIRS_METOP_OUT     Salida .nc            (def. /data/output/metop/level2/mirs)
#   MIRS_METOP_STATE   Marcadores .done      (def. /data/output/metop/state/cspp-mirs)
#   MIRS_CONTAINER     Imagen .sif           (def. /opt/containers/cspp_mirs_v4.0.sif)
#   MIRS_CACHE         Caché que exige       (def. /data/ancillary/mirs)
#   MIRS_WORK_BASE     Raíz de trabajo       (def. /data/tmp)
#   MIRS_LOG_BASE      Raíz de logs          (def. /var/log/lanot/polares)
#   MIRS_OPTS          Banderas de run_mirs.bash (def. --noSFR -l)
#
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SIF_MIRS="${MIRS_CONTAINER:-/opt/containers/cspp_mirs_v4.0.sif}"
HOST_CACHE="${MIRS_CACHE:-/data/ancillary/mirs}"

DIR_L1="${METOP_OUTPUT_DIR:-/data/output/metop/level1}"
STATE_L1="${METOP_STATE_DIR:-/data/output/metop/state/aapp}"
HOST_OUT="${MIRS_METOP_OUT:-/data/output/metop/level2/mirs}"
STATE_DIR="${MIRS_METOP_STATE:-/data/output/metop/state/cspp-mirs}"

WORK_BASE="${MIRS_WORK_BASE:-/data/tmp}"
LOG_DIR="${MIRS_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"
MIRS_OPTS="${MIRS_OPTS:---noSFR -l}"

# Un solo gránulo por pasada, así que más procesos casi no ayudan; 8 como en
# JPSS (63–86 s por pasada en tahan, 2026-11-20).
NPROCS="${SLURM_CPUS_PER_TASK:-8}"
JOB_ID="${SLURM_JOB_ID:-$$}"

uso() {
    cat <<EOF
Uso:
  $0                  El crudo más reciente con Level 1 y sin MiRS
  $0 <crudo>          Uno en concreto
  $0 --force [crudo]  Aunque ya tenga marcador

Requiere que run_metop_l1.sh haya terminado con marcador para ese crudo.
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

# A la raíz, como los demás: apptainer necesita poder entrar al directorio
# actual, y desde el clon con "sudo -u lanotadm" no siempre puede.
cd / || exit 1

# ==============================================================================
# SELECCIÓN
# ==============================================================================
# Por el manifiesto del Level 1, como run_heap_metop.sh: los dos insumos de la
# MISMA pasada, no "el más reciente".

if [ -z "$CRUDO" ]; then
    while IFS= read -r m; do
        c="$(basename "$m" .l1)"
        [ -f "$STATE_L1/$c.done" ] || continue
        if [ "$FORCE" -eq 1 ] || [ ! -f "$STATE_DIR/$c.done" ] || [ "$m" -nt "$STATE_DIR/$c.done" ]; then
            CRUDO="$c"
            break
        fi
    done < <(find "$STATE_L1" -maxdepth 1 -name '*.l1' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
    if [ -z "$CRUDO" ]; then
        echo "No hay pasadas de METOP con Level 1 y sin MiRS en $STATE_L1."
        exit 0
    fi
fi

MANIFIESTO="$STATE_L1/$CRUDO.l1"
if [ ! -f "$STATE_L1/$CRUDO.done" ] || [ ! -f "$MANIFIESTO" ]; then
    echo "ERROR: $CRUDO no tiene Level 1 terminado (falta $STATE_L1/$CRUDO.done o su .l1)." >&2
    echo "       Corre antes: run_metop_l1.sh $CRUDO" >&2
    exit 1
fi

AMSUA=$(grep -m1 -E '^amsua/amsual1b_M0[13]_.*\.l1b$' "$MANIFIESTO" || true)
MHS=$(grep -m1 -E '^mhs/mhsl1b_M0[13]_.*\.l1b$' "$MANIFIESTO" || true)

FALTAN=()
[ -n "$AMSUA" ] || FALTAN+=("AMSU-A l1b")
[ -n "$MHS" ]   || FALTAN+=("MHS l1b")
if [ ${#FALTAN[@]} -gt 0 ]; then
    echo "ERROR: el manifiesto $MANIFIESTO no trae: ${FALTAN[*]}" >&2
    exit 1
fi

case "$(basename "$AMSUA")" in
    amsual1b_M01_*) SATELITE=METOP-B ;;
    amsual1b_M03_*) SATELITE=METOP-C ;;
esac

echo "=============================================================================="
echo "CSPP MiRS v4.0 | $SATELITE | $CRUDO"
echo "=============================================================================="

MARKER="$STATE_DIR/$CRUDO.done"
if [ -f "$MARKER" ] && [ "$MARKER" -nt "$MANIFIESTO" ] && [ "$FORCE" -eq 0 ]; then
    echo ""
    echo "ℹ  $CRUDO ya tiene MiRS:"
    sed 's/^/   /' "$MARKER"
    echo ""
    echo "   No hay nada que hacer. Usa --force para repetirlo."
    exit 0
fi

# ==============================================================================
# VALIDACIÓN DEL AMBIENTE
# ==============================================================================

if [ ! -f "$SIF_MIRS" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_MIRS" >&2
    exit 1
fi
for f in "$AMSUA" "$MHS"; do
    if [ ! -s "$DIR_L1/$f" ]; then
        echo "ERROR: falta o está vacío $DIR_L1/$f (¿lo borró la retención?)" >&2
        exit 1
    fi
done

# ==============================================================================
# STAGING
# ==============================================================================
# Copias, no enlaces: llevan la cabecera ajustada. Son chicas (~170 KB y
# ~600 KB). Staging y trabajo HERMANOS: el driver poda lo que cuelga de -W.

HOST_WORK="${WORK_BASE}/mirs_work_metop_${JOB_ID}"
STAGING_DIR="${WORK_BASE}/mirs_staging_metop_${JOB_ID}"
mkdir -p "$STAGING_DIR" "$HOST_WORK" "$HOST_OUT" "$HOST_CACHE" "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$HOST_WORK" "$STAGING_DIR"' EXIT

LOG_FILE="$LOG_DIR/mirs_metop_${TIMESTAMP}_${CRUDO}.log"
{
    echo "  AMSU-A:  $(basename "$AMSUA")"
    echo "  MHS:     $(basename "$MHS")"
    echo "  Salida:  $HOST_OUT"
} | tee -a "$LOG_FILE"

if ! python3 "$SCRIPT_DIR/metop_l1b_para_mirs.py" "$DIR_L1/$AMSUA" "$DIR_L1/$MHS" "$STAGING_DIR" 2>&1 \
        | sed 's/^/  Cabecera /' | tee -a "$LOG_FILE"; then
    echo "❌ ERROR: no se pudo preparar la copia para MiRS. Ver $LOG_FILE" | tee -a "$LOG_FILE"
    exit 1
fi
if [ ! -s "$STAGING_DIR/$(basename "$AMSUA")" ] || [ ! -s "$STAGING_DIR/$(basename "$MHS")" ]; then
    echo "❌ ERROR: metop_l1b_para_mirs.py no dejó las dos copias en $STAGING_DIR" | tee -a "$LOG_FILE"
    exit 1
fi

# ==============================================================================
# PROCESAMIENTO
# ==============================================================================

echo ">>> Ejecutando run_mirs.bash ($NPROCS procesos, $MIRS_OPTS)..." | tee -a "$LOG_FILE"

EXIT_CODE=0
apptainer exec \
    --bind "$STAGING_DIR:/input" \
    --bind "$HOST_WORK:/work" \
    --bind "$HOST_CACHE:/anc" \
    --pwd /work \
    "$SIF_MIRS" /bin/bash -c "
        export HDF5_USE_FILE_LOCKING=FALSE
        export LC_ALL=C
        export TZ=UTC
        source \$CSPP_MIRS_HOME/cspp_mirs_env.sh
        run_mirs.bash $MIRS_OPTS -p $NPROCS -d /anc -W /work /input
    " >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP MiRS falló (código $EXIT_CODE) tras $DURACION. Ver $LOG_FILE" | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR" | tee -a "$LOG_FILE"
    trap - EXIT
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN Y ENTREGA
# ==============================================================================
# El driver sale en 0 aunque no produzca nada ("Normal Completion. Encountered
# some problems"): así salió la primera prueba, con el código de sitio LNT. Se
# exige el par IMG/SND, como en JPSS.

mapfile -t PRODUCTOS < <(find "$HOST_WORK" -maxdepth 1 -type f -name 'NPR-MIRS-*.nc' | sort)
IMG_COUNT=$(printf '%s\n' "${PRODUCTOS[@]}" | grep -c 'NPR-MIRS-IMG' || true)
SND_COUNT=$(printf '%s\n' "${PRODUCTOS[@]}" | grep -c 'NPR-MIRS-SND' || true)

if [ "$IMG_COUNT" -eq 0 ] || [ "$SND_COUNT" -eq 0 ]; then
    echo "❌ ERROR: MiRS terminó sin error pero no dejó el par IMG/SND (IMG $IMG_COUNT, SND $SND_COUNT)" | tee -a "$LOG_FILE"
    echo "   Lo primero que mirar: <trabajo>/M?_*/metop?_logFile.dat. Ver $LOG_FILE" | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR" | tee -a "$LOG_FILE"
    trap - EXIT
    exit 1
fi

mv "${PRODUCTOS[@]}" "$HOST_OUT/"

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "crudo:     $CRUDO"
    echo "satelite:  $SATELITE"
    echo "entrada:   $(basename "$AMSUA") $(basename "$MHS")"
    # Los nombres y no solo la cuenta: procesar_metop.sh renderiza el IMG que
    # diga aquí, no "el más reciente".
    for f in "${PRODUCTOS[@]}"; do
        case "$(basename "$f")" in
            NPR-MIRS-IMG_*) echo "img:       $(basename "$f")" ;;
            NPR-MIRS-SND_*) echo "snd:       $(basename "$f")" ;;
        esac
    done
    echo "duracion:  $DURACION"
    echo "salida:    $HOST_OUT"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: MiRS de $CRUDO (IMG $IMG_COUNT, SND $SND_COUNT) en $DURACION" | tee -a "$LOG_FILE"
echo "   Salida:   $HOST_OUT" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER"   | tee -a "$LOG_FILE"
