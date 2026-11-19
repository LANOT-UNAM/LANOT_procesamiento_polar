#!/bin/bash
# ==============================================================================
# LANOT - UNAM | CSPP HEAP v3.0 para METOP-B/C (Level 1 → sondeos NUCAPS)
# ==============================================================================
#
# IASI 1C + AMSU-A + MHS de una pasada → perfiles NUCAPS, con el mismo bundle
# de HEAP que la rama JPSS (run_heap_edr.sh) y su mismo criterio de éxito.
#
# Sustituye a referencia/metop/cspp_nucaps_metop.sh, que corre HEAP 2.0 en tsom03
# y que tiene los dos vicios de siempre: marcador de un solo valor por satélite
# (lastm1amsua), escrito antes de procesar, y entrada "el AMSU-A más reciente".
# Además procesa TODO lo que stratus deja en su entrada, y como stratus deja dos
# IASI 1C por pasada de METOP-C (OPS-LRS corre dos veces en metop2.sh), cada
# gránulo de METOP-C sale dos veces.
#
# Por qué es un script aparte y no una rama de run_heap_edr.sh: allá el trabajo
# difícil es EMPAREJAR —CrIS y ATMS llegan en gránulos sueltos, con órbitas
# distintas, y se cruzan por traslape de intervalos con margen—. Aquí no hay
# nada que emparejar: los tres insumos salen del MISMO crudo, uno por
# instrumento, y run_metop_l1.sh ya los listó en su manifiesto (<crudo>.l1).
# HEAP parte él solo el IASI de pasada entera en gránulos de 22–23 MDR (-m M_…:
# prefiere el centro de la pasada).
#
# Comparte con run_heap_edr.sh lo que no se puede separar: el bundle en el host
# (ESCRIBIBLE: airsb103.exe abre fort.40 dentro), su candado, el caché de GFS
# en /data/ancillary/heap y la regla de que sin NUCAPS-EDR no hubo sondeo.
#
# La unidad de trabajo es el crudo, como en run_metop_l1.sh.
#
# Uso:
#   ./run_heap_metop.sh                   # el crudo más reciente con L1 y sin sondeo
#   ./run_heap_metop.sh <crudo>           # uno en concreto (nombre o ruta)
#   ./run_heap_metop.sh --force [crudo]   # aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   METOP_OUTPUT_DIR  Level 1 de METOP      (def. /data/output/metop/level1)
#   METOP_STATE_DIR   Manifiestos .l1       (def. /data/output/metop/state/aapp)
#   HEAP_METOP_OUT    Salida .nc            (def. /data/output/metop/level2/sounder)
#   HEAP_METOP_STATE  Marcadores .done      (def. /data/output/metop/state/cspp-heap)
#   HEAP_CONTAINER    Imagen .sif           (def. /opt/containers/cspp_heap_v3.0.sif)
#   HEAP_HOME_HOST    Bundle en el host     (def. /data/opt/CSPP_HEAP_3_0)
#   HEAP_CACHE        Caché de GFS          (def. /data/ancillary/heap)
#   HEAP_WORK_BASE    Raíz de trabajo       (def. /data/tmp)
#   HEAP_LOG_BASE     Raíz de logs          (def. /var/log/lanot/polares)
#   HEAP_ESPERA       Espera por el candado del bundle, en s (def. 3600)
#   HEAP_SALIDA       Cadena de -o          (def. RO, como en JPSS)
#   HEAP_OPTS         Banderas extra para run_heap.bash
#
# ==============================================================================

set -euo pipefail

SIF_HEAP="${HEAP_CONTAINER:-/opt/containers/cspp_heap_v3.0.sif}"
HOST_HEAP_HOME="${HEAP_HOME_HOST:-/data/opt/CSPP_HEAP_3_0}"
HOST_CACHE="${HEAP_CACHE:-/data/ancillary/heap}"

DIR_L1="${METOP_OUTPUT_DIR:-/data/output/metop/level1}"
STATE_L1="${METOP_STATE_DIR:-/data/output/metop/state/aapp}"
HOST_OUT="${HEAP_METOP_OUT:-/data/output/metop/level2/sounder}"
STATE_DIR="${HEAP_METOP_STATE:-/data/output/metop/state/cspp-heap}"

WORK_BASE="${HEAP_WORK_BASE:-/data/tmp}"
LOG_DIR="${HEAP_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

CORES="${SLURM_CPUS_PER_TASK:-4}"
JOB_ID="${SLURM_JOB_ID:-$$}"
ESPERA_CANDADO="${HEAP_ESPERA:-3600}"
SALIDA_HEAP="${HEAP_SALIDA:-RO}"

uso() {
    cat <<EOF
Uso:
  $0                  El crudo más reciente con Level 1 y sin sondeo
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

# ==============================================================================
# SELECCIÓN
# ==============================================================================
# Por el manifiesto del Level 1, no por "el AMSU-A más reciente": así cada
# sondeo sale de los tres archivos de la MISMA pasada.

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
        echo "No hay pasadas de METOP con Level 1 y sin sondeo en $STATE_L1."
        exit 0
    fi
fi

MANIFIESTO="$STATE_L1/$CRUDO.l1"
if [ ! -f "$STATE_L1/$CRUDO.done" ] || [ ! -f "$MANIFIESTO" ]; then
    echo "ERROR: $CRUDO no tiene Level 1 terminado (falta $STATE_L1/$CRUDO.done o su .l1)." >&2
    echo "       Corre antes: run_metop_l1.sh $CRUDO" >&2
    exit 1
fi

# Los tres insumos, del manifiesto. Uno de cada: AAPP_RUN_METOP procesa en modo
# volcado, un archivo por instrumento y pasada.
IASI=$(grep -m1 -E '^iasi/IASI_xxx_1C_M0[13]_' "$MANIFIESTO" || true)
AMSUA=$(grep -m1 -E '^amsua/amsual1b_M0[13]_.*\.l1b$' "$MANIFIESTO" || true)
MHS=$(grep -m1 -E '^mhs/mhsl1b_M0[13]_.*\.l1b$' "$MANIFIESTO" || true)

FALTAN=()
[ -n "$IASI" ]  || FALTAN+=("IASI 1C")
[ -n "$AMSUA" ] || FALTAN+=("AMSU-A l1b")
[ -n "$MHS" ]   || FALTAN+=("MHS l1b")
if [ ${#FALTAN[@]} -gt 0 ]; then
    echo "ERROR: el manifiesto $MANIFIESTO no trae: ${FALTAN[*]}" >&2
    exit 1
fi

case "$(basename "$AMSUA")" in
    amsual1b_M01_*) MISION=m01; SATELITE=METOP-B ;;
    amsual1b_M03_*) MISION=m03; SATELITE=METOP-C ;;
esac

echo "=============================================================================="
echo "CSPP HEAP v3.0 (NUCAPS) | $SATELITE | $CRUDO"
echo "=============================================================================="

MARKER="$STATE_DIR/$CRUDO.done"
if [ -f "$MARKER" ] && [ "$MARKER" -nt "$MANIFIESTO" ] && [ "$FORCE" -eq 0 ]; then
    echo ""
    echo "ℹ  $CRUDO ya tiene sondeo:"
    sed 's/^/   /' "$MARKER"
    echo ""
    echo "   No hay nada que hacer. Usa --force para repetirlo."
    exit 0
fi

# ==============================================================================
# VALIDACIÓN DEL AMBIENTE
# ==============================================================================

if [ ! -x "$HOST_HEAP_HOME/scripts/run_heap.bash" ]; then
    echo "ERROR: No está el bundle de HEAP en el host: $HOST_HEAP_HOME" >&2
    echo "       Despliégalo con: sudo ./scripts/preparar_servidor.sh --solo 7" >&2
    exit 1
fi
if [ ! -f "$SIF_HEAP" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_HEAP" >&2
    exit 1
fi
for f in "$IASI" "$AMSUA" "$MHS"; do
    if [ ! -s "$DIR_L1/$f" ]; then
        echo "ERROR: falta o está vacío $DIR_L1/$f (¿lo borró la retención?)" >&2
        exit 1
    fi
done

# ==============================================================================
# STAGING
# ==============================================================================
# Staging y trabajo HERMANOS (el driver poda lo que cuelga de -w). Enlaces duros
# si se puede —/data/tmp y /data/output están en el mismo sistema de archivos—;
# si no, simbólicos, y para eso se monta además DIR_L1 sobre sí mismo.

HOST_WORK="${WORK_BASE}/heap_work_metop_${JOB_ID}"
STAGING_DIR="${WORK_BASE}/heap_staging_metop_${JOB_ID}"
mkdir -p "$STAGING_DIR" "$HOST_WORK" "$HOST_OUT" "$HOST_CACHE" "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$HOST_WORK" "$STAGING_DIR"' EXIT

for f in "$IASI" "$AMSUA" "$MHS"; do
    ln -f "$DIR_L1/$f" "$STAGING_DIR"/ 2>/dev/null || ln -sf "$DIR_L1/$f" "$STAGING_DIR"/
done

LOG_FILE="$LOG_DIR/heap_metop_${TIMESTAMP}_${CRUDO}.log"
{
    echo "  Misión:  $MISION"
    echo "  IASI:    $(basename "$IASI")"
    echo "  AMSU-A:  $(basename "$AMSUA")"
    echo "  MHS:     $(basename "$MHS")"
    echo "  Caché:   $HOST_CACHE"
    echo "  Salida:  $HOST_OUT"
    echo "  Hilos:   $CORES"
} | tee -a "$LOG_FILE"

# ==============================================================================
# PROCESAMIENTO
# ==============================================================================
# El mismo candado que run_heap_edr.sh: el bundle es uno y escribible.

exec 7>>"$HOST_HEAP_HOME/.candado"
if ! flock -n 7; then
    echo "  Otra corrida de HEAP tiene el bundle; esperando (hasta $((ESPERA_CANDADO / 60)) min)..." | tee -a "$LOG_FILE"
    if ! flock -w "$ESPERA_CANDADO" 7; then
        echo "❌ ERROR: el candado de HEAP no se liberó en $((ESPERA_CANDADO / 60)) min" | tee -a "$LOG_FILE"
        exit 75
    fi
fi

echo ">>> Ejecutando run_heap.bash (misión $MISION, modo M_IRMW)..." | tee -a "$LOG_FILE"

EXIT_CODE=0
apptainer exec \
    --bind "$HOST_HEAP_HOME:/opt/cspp_heap" \
    --bind "$STAGING_DIR:/input" \
    --bind "$DIR_L1:$DIR_L1:ro" \
    --bind "$HOST_WORK:/work" \
    --bind "$HOST_CACHE:/anc" \
    --pwd /work \
    "$SIF_HEAP" /bin/bash -c "
        export HDF5_USE_FILE_LOCKING=FALSE
        export LC_ALL=C
        source \$CSPP_HEAP_HOME/scripts/cspp_heap_env.sh
        run_heap.bash -s $MISION -i /input -m M_IRMW -o $SALIDA_HEAP \
                      -p $CORES -w /work -d /anc ${HEAP_OPTS:-}
    " >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP HEAP falló (código $EXIT_CODE) tras $DURACION. Ver $LOG_FILE" | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR" | tee -a "$LOG_FILE"
    trap - EXIT
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN Y ENTREGA
# ==============================================================================
# Lo mismo que en run_heap_edr.sh, y por lo mismo (ver allí la historia del
# 2026-08-17 y del 29): el wrapper sale en 0 aunque no haya recuperado nada,
# así que se exige NUCAPS-EDR por nombre y familias parejas.

mapfile -t PRODUCTOS < <(find "$HOST_WORK" -maxdepth 1 -type f -name 'NUCAPS-*.nc' | sort)

declare -A FAMILIAS=()
for f in "${PRODUCTOS[@]}"; do
    fam=$(basename "$f"); fam="${fam%%_v*}"
    FAMILIAS[$fam]=$(( ${FAMILIAS[$fam]:-0} + 1 ))
done
RECUPERACION=${FAMILIAS[NUCAPS-EDR]:-0}

listar_familias() {
    local fam
    for fam in $(printf '%s\n' "${!FAMILIAS[@]}" | sort); do
        echo "     $fam: ${FAMILIAS[$fam]}"
    done
}

RESCATE="$LOG_DIR/heap_metop_${TIMESTAMP}_${CRUDO}_cspp"
mapfile -t LOGS_CSPP < <(find "$HOST_WORK" -type f ! -name '*.nc' 2>/dev/null | sort)
if [ "${#LOGS_CSPP[@]}" -gt 0 ]; then
    mkdir -p "$RESCATE"
    cp -p "${LOGS_CSPP[@]}" "$RESCATE"/ 2>/dev/null || true
fi

if [ "$RECUPERACION" -eq 0 ]; then
    echo "❌ ERROR: ${#PRODUCTOS[@]} archivos, pero ningún NUCAPS-EDR: no hubo sondeo." | tee -a "$LOG_FILE"
    listar_familias | tee -a "$LOG_FILE"
    echo "   Lo primero que mirar es lo mismo que en JPSS (run_heap_edr.sh): permisos" | tee -a "$LOG_FILE"
    echo "   de escritura del bundle y el GFS del día en $HOST_CACHE." | tee -a "$LOG_FILE"
    echo "   Para conservar el temporal del driver: HEAP_OPTS='--noclean -v' $0 --force $CRUDO" | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR" | tee -a "$LOG_FILE"
    trap - EXIT
    exit 1
fi

MAX_FAM=0; MIN_FAM=""
for fam in "${!FAMILIAS[@]}"; do
    n=${FAMILIAS[$fam]}
    [ "$n" -le "$MAX_FAM" ] || MAX_FAM=$n
    [ -n "$MIN_FAM" ] && [ "$n" -ge "$MIN_FAM" ] || MIN_FAM=$n
done

mv "${PRODUCTOS[@]}" "$HOST_OUT/"

if [ "$MIN_FAM" -ne "$MAX_FAM" ]; then
    echo "❌ ERROR: HEAP salió a medias: las familias no traen los mismos gránulos." | tee -a "$LOG_FILE"
    listar_familias | tee -a "$LOG_FILE"
    echo "   Lo que salió quedó en $HOST_OUT, sin marcador. Logs de HEAP: $RESCATE" | tee -a "$LOG_FILE"
    exit 1
fi

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "crudo:     $CRUDO"
    echo "satelite:  $SATELITE (misión HEAP $MISION)"
    for fam in $(printf '%s\n' "${!FAMILIAS[@]}" | sort); do
        printf '%-10s %s archivos\n' "$(echo "$fam" | tr 'A-Z' 'a-z'):" "${FAMILIAS[$fam]}"
    done
    echo "duracion:  $DURACION"
    echo "salida:    $HOST_OUT"
    echo "log:       $LOG_FILE"
} > "$MARKER"

DESGLOSE=$(for fam in $(printf '%s\n' "${!FAMILIAS[@]}" | sort); do printf '%s %s, ' "${FAMILIAS[$fam]}" "$fam"; done)
echo "✅ ÉXITO: ${#PRODUCTOS[@]} productos de $CRUDO (${DESGLOSE%, }) en $DURACION" | tee -a "$LOG_FILE"
echo "   Salida:   $HOST_OUT" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER"   | tee -a "$LOG_FILE"
