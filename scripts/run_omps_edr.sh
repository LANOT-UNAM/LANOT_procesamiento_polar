#!/bin/bash
#SBATCH --job-name=omps_edr
#SBATCH --cpus-per-task=2
#SBATCH --output=/var/log/lanot/polares/cspp-edr/slurm_omps_%j.log
# ==============================================================================
# LANOT - UNAM | CSPP OMPS EDR v1.0 (Level 1 → Level 2, ozono)
# ==============================================================================
#
# SDR de OMPS → V8TOz (columna total de ozono, unidades Dobson) y V8PRO (perfil
# de ozono en 21 capas).
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR de
# OMPS y, si ya fue procesada con éxito, avisa y no hace nada. Una pasada se
# identifica por satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
#
# Los dos instrumentos, según el manual §1.4:
#   V8TOz  necesita SOLO el Nadir Mapper     (SOMTC* + GOTCO*)
#   V8PRO  necesita Nadir Mapper Y Profiler  (+ SOMPS* + GONPO*)
# Por eso el staging enlaza los cuatro tipos y, si faltan los del Profiler, la
# corrida sigue: sale V8TOz y se avisa que no hubo V8PRO.
#
# Solo se procesan gránulos DIURNOS: ambos algoritmos miden radiancia
# ultravioleta retrodispersada, así que en la parte nocturna de la pasada no hay
# nada que recuperar y el driver los omite en silencio.
#
# A diferencia de ATMOS y ACSPO, **no hay ancillary dinámico**: no hay caché que
# refrescar ni cron de precarga (manual §1.4).
#
# Uso:
#   ./run_omps_edr.sh            # la pasada más reciente pendiente
#   ./run_omps_edr.sh --force    # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   OMPS_SDR_IN      Entrada Level 1  (def. /data/output/jpss/level1/omps)
#   OMPS_OUT         Salida .nc       (def. /data/output/jpss/level2/omps)
#   OMPS_STATE_DIR   Marcadores .done (def. /data/output/jpss/state/cspp-omps)
#   OMPS_CONTAINER   Imagen .sif      (def. /opt/containers/cspp_omps_l2_v1.0.sif)
#   OMPS_WORK_BASE   Raíz de trabajo  (def. /data/tmp)
#   OMPS_LOG_BASE    Raíz de logs     (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_OMPS="${OMPS_CONTAINER:-/opt/containers/cspp_omps_l2_v1.0.sif}"

HOST_SDR_IN="${OMPS_SDR_IN:-/data/output/jpss/level1/omps}"
HOST_EDR_OUT="${OMPS_OUT:-/data/output/jpss/level2/omps}"
STATE_DIR="${OMPS_STATE_DIR:-/data/output/jpss/state/cspp-omps}"

WORK_BASE="${OMPS_WORK_BASE:-/data/tmp}"
LOG_DIR="${OMPS_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

JOB_ID="${SLURM_JOB_ID:-$$}"

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0             Procesa la pasada más reciente de $HOST_SDR_IN
  $0 --force     Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force   Ignora el marcador de procesado
  -h, --help    Muestra esta ayuda

Requiere que run_sdr.sh haya corrido para los DOS instrumentos:
  scripts/run_sdr.sh --sensor omps_nm
  scripts/run_sdr.sh --sensor omps_np
EOF
}

# GOTCO_j01_d20260811_t1948528_e2002357_b45236_c2026...h5 -> j01_d20260811_b45236
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
HOST_WORK="${WORK_BASE}/omps_work_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$HOST_SDR_IN" ]; then
    echo "ERROR: Directorio de SDR de OMPS no encontrado: $HOST_SDR_IN" >&2
    echo "       Corre antes: run_sdr.sh --sensor omps_nm" >&2
    exit 1
fi

# La pasada la define la geolocalización del Nadir Mapper: es el insumo mínimo,
# porque sin ella no hay ni V8TOz.
ULTIMO_GOTCO=$(find "$HOST_SDR_IN" -maxdepth 1 -name 'GOTCO*.h5' \
                    -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$ULTIMO_GOTCO" ]; then
    echo "No hay SDR de OMPS que procesar en $HOST_SDR_IN (no se ven archivos GOTCO*)."
    exit 0
fi

if ! CLAVE=$(clave_de_pasada "$ULTIMO_GOTCO"); then
    echo "ERROR: No se pudo derivar la pasada del nombre: $(basename "$ULTIMO_GOTCO")" >&2
    exit 1
fi

IFS='_' read -r SAT FECHA ORBITA <<< "$CLAVE"

echo "=============================================================================="
echo "CSPP OMPS EDR v1.0 | pasada $CLAVE"
echo "=============================================================================="

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

if [ ! -f "$SIF_OMPS" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_OMPS" >&2
    exit 1
fi

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================
# El driver recibe un directorio y procesa todo lo que encuentre, así que se
# enlaza únicamente lo de esta pasada.

STAGING_DIR="${HOST_WORK}/input"

mkdir -p "$STAGING_DIR" "$HOST_EDR_OUT" "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$HOST_WORK"' EXIT

NM_COUNT=0
NP_COUNT=0

for prefijo in SOMTC GOTCO; do
    for f in "$HOST_SDR_IN"/${prefijo}_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5; do
        [ -e "$f" ] || continue
        ln -sf "$f" "$STAGING_DIR/"
        NM_COUNT=$((NM_COUNT + 1))
    done
done

for prefijo in SOMPS GONPO; do
    for f in "$HOST_SDR_IN"/${prefijo}_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5; do
        [ -e "$f" ] || continue
        ln -sf "$f" "$STAGING_DIR/"
        NP_COUNT=$((NP_COUNT + 1))
    done
done

if [ "$NM_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR del Nadir Mapper de la pasada $CLAVE" >&2
    echo "       Sin SOMTC/GOTCO no hay V8TOz. Corre: run_sdr.sh --sensor omps_nm" >&2
    exit 1
fi

LOG_FILE="$LOG_DIR/omps_${TIMESTAMP}_${CLAVE}.log"

echo "  Nadir Mapper:   $NM_COUNT archivos" | tee -a "$LOG_FILE"
echo "  Nadir Profiler: $NP_COUNT archivos" | tee -a "$LOG_FILE"
echo "  Salida:         $HOST_EDR_OUT"      | tee -a "$LOG_FILE"

if [ "$NP_COUNT" -eq 0 ]; then
    echo "  ⚠ Sin SDR del Nadir Profiler: saldrá V8TOz pero no V8PRO" | tee -a "$LOG_FILE"
    echo "    (para tenerlo: run_sdr.sh --sensor omps_np)"             | tee -a "$LOG_FILE"
fi

# ==============================================================================
# PROCESAMIENTO
# ==============================================================================
# El manual pide directorio de trabajo limpio en cada ejecución, y con -W los
# productos quedan ahí en vez de en el pwd. Como HOST_WORK nace vacío y se
# descarta al final, ambas cosas se cumplen solas.

echo "" | tee -a "$LOG_FILE"
echo ">>> Ejecutando omps_l2.sh..." | tee -a "$LOG_FILE"

EXIT_CODE=0
apptainer exec \
    --bind "$STAGING_DIR:/input" \
    --bind "$HOST_WORK:/work" \
    "$SIF_OMPS" /bin/bash -c "
        export HDF5_USE_FILE_LOCKING=FALSE
        export LC_ALL=C
        source \$CSPP_OMPS_L2_HOME/omps_l2_env.sh
        omps_l2.sh -v -W /work /input
    " >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP OMPS EDR falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                     | tee -a "$LOG_FILE"
    echo "   El directorio de trabajo se conserva: $HOST_WORK"             | tee -a "$LOG_FILE"
    trap - EXIT
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN Y ENTREGA
# ==============================================================================
# El código de salida no basta: estos drivers pueden terminar en 0 sin producir
# nada. Como el directorio de trabajo nace vacío, basta con contar lo que hay.

mapfile -t PRODUCTOS < <(find "$HOST_WORK" -maxdepth 1 -type f -name '*.nc' | sort)
NC_COUNT=${#PRODUCTOS[@]}

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: OMPS terminó sin error pero no generó productos."     | tee -a "$LOG_FILE"
    echo "   Causa típica: la pasada es nocturna y no hay retrievals."    | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                    | tee -a "$LOG_FILE"
    echo "   El directorio de trabajo se conserva: $HOST_WORK"            | tee -a "$LOG_FILE"
    trap - EXIT
    exit 1
fi

TOZ_COUNT=$(printf '%s\n' "${PRODUCTOS[@]}" | grep -c 'V8TOZ' || true)
PRO_COUNT=$(printf '%s\n' "${PRODUCTOS[@]}" | grep -c 'V8PRO' || true)

mv "${PRODUCTOS[@]}" "$HOST_EDR_OUT/"

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "sdr:       $NM_COUNT del Nadir Mapper, $NP_COUNT del Nadir Profiler"
    echo "v8toz:     $TOZ_COUNT archivos"
    echo "v8pro:     $PRO_COUNT archivos"
    echo "duracion:  $DURACION"
    echo "salida:    $HOST_EDR_OUT"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "" | tee -a "$LOG_FILE"
echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE (V8TOz $TOZ_COUNT, V8PRO $PRO_COUNT) en $DURACION" | tee -a "$LOG_FILE"
echo "   Salida:   $HOST_EDR_OUT" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER"       | tee -a "$LOG_FILE"
