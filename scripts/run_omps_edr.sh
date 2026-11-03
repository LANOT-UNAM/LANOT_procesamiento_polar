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
# identifica por satélite, fecha y hora de inicio (p. ej. j01_d20260811_t194733;
# ver pasadas.sh).
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
  -p, --pasada  Pasada concreta en vez de la más reciente: la clave completa
                (j01_d20260813_t191402) o cualquier trozo que la identifique
  -h, --help    Muestra esta ayuda

Requiere que run_sdr.sh haya corrido para los DOS instrumentos:
  scripts/run_sdr.sh --sensor omps_nm
  scripts/run_sdr.sh --sensor omps_np

Pasadas disponibles en $HOST_SDR_IN:
$(listar_pasadas "$HOST_SDR_IN" GOTCO 2>/dev/null | cut -d' ' -f1 | sed 's/^/  /' || true)
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

# Staging y directorio de trabajo son HERMANOS, no anidados: el driver borra lo
# que encuentra bajo -W al terminar ("removed dir" en el log), así que un
# staging dentro de /work se lo lleva por delante.
HOST_WORK="${WORK_BASE}/omps_work_${JOB_ID}"
STAGING_DIR="${WORK_BASE}/omps_staging_${JOB_ID}"

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
resolver_pasada "$HOST_SDR_IN" GOTCO "$PASADA" || exit 1

if [ -z "$CLAVE" ]; then
    echo "No hay SDR de OMPS que procesar en $HOST_SDR_IN (no se ven archivos GOTCO*)."
    exit 0
fi

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
# enlaza únicamente lo de esta pasada. Los enlaces apuntan a $HOST_SDR_IN, que
# por eso se monta más abajo sobre sí mismo: sin ese bind el contenedor ve los
# nombres pero no los archivos, y el driver los da por procesados sin abrir
# ninguno (verificado en tahan el 2026-08-13: 39 gránulos "listos" en el mismo
# segundo y "0 products of 20 without errors").

mkdir -p "$STAGING_DIR" "$HOST_WORK" "$HOST_EDR_OUT" "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$HOST_WORK" "$STAGING_DIR"' EXIT

NM_COUNT=0
NP_COUNT=0

for prefijo in SOMTC GOTCO; do
    while IFS= read -r f; do
        ln -sf "$f" "$STAGING_DIR/"
        NM_COUNT=$((NM_COUNT + 1))
    done < <(archivos_de_pasada "$HOST_SDR_IN" "$prefijo")
done

for prefijo in SOMPS GONPO; do
    while IFS= read -r f; do
        ln -sf "$f" "$STAGING_DIR/"
        NP_COUNT=$((NP_COUNT + 1))
    done < <(archivos_de_pasada "$HOST_SDR_IN" "$prefijo")
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
# El manual pide directorio de trabajo limpio en cada ejecución: HOST_WORK nace
# vacío y se descarta al final, así que eso se cumple solo. `omps_l2.sh -h` no
# ofrece opción de salida, y con --pwd /work los productos caen ahí tanto si los
# escribe bajo -W como si los deja en el pwd, que es lo que hacen varios
# ejecutables de CSPP.

echo "" | tee -a "$LOG_FILE"
echo ">>> Ejecutando omps_l2.sh..." | tee -a "$LOG_FILE"

EXIT_CODE=0
apptainer exec \
    --bind "$STAGING_DIR:/input" \
    --bind "$HOST_SDR_IN:$HOST_SDR_IN" \
    --bind "$HOST_WORK:/work" \
    --pwd /work \
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
    echo "   Se conservan $HOST_WORK y $STAGING_DIR"                       | tee -a "$LOG_FILE"
    trap - EXIT
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN Y ENTREGA
# ==============================================================================
# El código de salida no basta: estos drivers pueden terminar en 0 sin producir
# nada. Como el directorio de trabajo nace vacío, basta con contar lo que hay.
# Sin -maxdepth, por si el driver los deja en un subdirectorio de los que crea y
# luego poda; el staging ya no cuelga de aquí, así que no hay qué confundir.

mapfile -t PRODUCTOS < <(find "$HOST_WORK" -type f -name '*.nc' | sort)
NC_COUNT=${#PRODUCTOS[@]}

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: OMPS terminó sin error pero no generó productos."     | tee -a "$LOG_FILE"
    echo "   Busca en el log la línea 'products of':"                     | tee -a "$LOG_FILE"
    echo "   grep -n 'products of' $LOG_FILE"                             | tee -a "$LOG_FILE"
    echo "   Si dice '0 products of N' y los gránulos salen todos con la" | tee -a "$LOG_FILE"
    echo "   misma marca de tiempo, no llegó a abrirlos: revisa que"      | tee -a "$LOG_FILE"
    echo "   $HOST_SDR_IN se vea dentro del contenedor."                  | tee -a "$LOG_FILE"
    echo "   Si tardó de verdad, la pasada puede ser nocturna: ambos"     | tee -a "$LOG_FILE"
    echo "   algoritmos miden radiancia UV y no hay nada que recuperar."  | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                    | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR"                      | tee -a "$LOG_FILE"
    trap - EXIT
    exit 1
fi

TOZ_COUNT=$(printf '%s\n' "${PRODUCTOS[@]}" | grep -c 'V8TOZ' || true)
PRO_COUNT=$(printf '%s\n' "${PRODUCTOS[@]}" | grep -c 'V8PRO' || true)

mv "${PRODUCTOS[@]}" "$HOST_EDR_OUT/"

# Más de 0 no basta: cada algoritmo remata con "completed M products of N". Con
# M < N lo que salió se entrega igual —el barrido no retoma OMPS, así que
# borrarlo sería perderlo—, pero sin marcador, para que el resumen lo cuente.
RC_MN=0
m_de_n "$LOG_FILE" 'completed [0-9]+ products of [0-9]+' 2 5 || RC_MN=$?
if [ "$RC_MN" -eq 1 ]; then
    echo "❌ ERROR: OMPS salió a medias: $M_DE_N_CORTOS productos (V8TOz $TOZ_COUNT, V8PRO $PRO_COUNT)." | tee -a "$LOG_FILE"
    echo "   Lo que salió quedó en $HOST_EDR_OUT, sin marcador."  | tee -a "$LOG_FILE"
    echo "   grep -n 'products of' $LOG_FILE"                    | tee -a "$LOG_FILE"
    exit 1
elif [ "$RC_MN" -eq 2 ]; then
    echo "⚠  El log no trae 'completed M products of N': no se pudo comprobar que salió todo." | tee -a "$LOG_FILE"
fi

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
