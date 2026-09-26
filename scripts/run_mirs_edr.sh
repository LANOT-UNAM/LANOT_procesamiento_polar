#!/bin/bash
#SBATCH --job-name=mirs_edr
#SBATCH --cpus-per-task=8
#SBATCH --output=/var/log/lanot/polares/cspp-edr/slurm_mirs_%j.log
# ==============================================================================
# LANOT - UNAM | CSPP MiRS v4.0 (Level 1 → Level 2, microondas de ATMS)
# ==============================================================================
#
# SDR de ATMS → NPR-MIRS-IMG (lluvia, agua precipitable, agua líquida de nube,
# temperatura de piel, las 22 temperaturas de brillo con corrección de limbo) y
# NPR-MIRS-SND (perfiles de temperatura y humedad, sobre mar y tierra).
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR de
# ATMS y, si ya fue procesada con éxito, avisa y no hace nada. Una pasada se
# identifica por satélite, fecha y hora de inicio (p. ej. j02_d20260926_t082141;
# ver pasadas.sh).
#
# A diferencia de HEAP, que también come ATMS:
#   - Solo necesita ATMS, y de los TRES tipos: SATMS (radiancia), TATMS
#     (temperatura de antena) y GATMO (geolocalización). HEAP no usa SATMS.
#   - Soporta los tres satélites, NPP incluido.
#   - El bundle va entero en el .sif: no escribe en su árbol (probado en tahan
#     el 2026-09-26 con el bundle montado de solo lectura).
#   - Agrega él mismo los gránulos: sale UN par IMG/SND por pasada, sin importar
#     si en level1/atms la pasada está en gránulos o agregada.
#
# Ancillary: solo la tasa de nevada (SFR) usa GFS, y en México no interesa, así
# que corre con --noSFR -l y no descarga nada: no hay cron de precarga ni poda.
# PERO el driver exige un caché escribible de todos modos (-d), y el de omisión
# ($CSPP_MIRS_HOME/anc/cache) cae dentro de la imagen, de solo lectura. Por eso
# se monta $HOST_CACHE en /anc aunque se quede vacío.
#
# Reprocesar DUPLICA productos: el nombre lleva el campo de creación (_c…), como
# los JRR-* de ATMOS. Quien los lea tiene que quedarse con el más reciente.
#
# Uso:
#   ./run_mirs_edr.sh            # la pasada más reciente pendiente
#   ./run_mirs_edr.sh --force    # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   MIRS_SDR_IN      Entrada Level 1  (def. /data/output/jpss/level1/atms)
#   MIRS_OUT         Salida .nc       (def. /data/output/jpss/level2/mirs)
#   MIRS_STATE_DIR   Marcadores .done (def. /data/output/jpss/state/cspp-mirs)
#   MIRS_CACHE       Caché que exige  (def. /data/ancillary/mirs)
#   MIRS_CONTAINER   Imagen .sif      (def. /opt/containers/cspp_mirs_v4.0.sif)
#   MIRS_WORK_BASE   Raíz de trabajo  (def. /data/tmp)
#   MIRS_LOG_BASE    Raíz de logs     (def. /var/log/lanot/polares)
#   MIRS_OPTS        Banderas para run_mirs.bash (def. --noSFR -l)
#
# ==============================================================================

set -euo pipefail

SIF_MIRS="${MIRS_CONTAINER:-/opt/containers/cspp_mirs_v4.0.sif}"

HOST_SDR_IN="${MIRS_SDR_IN:-/data/output/jpss/level1/atms}"
HOST_EDR_OUT="${MIRS_OUT:-/data/output/jpss/level2/mirs}"
STATE_DIR="${MIRS_STATE_DIR:-/data/output/jpss/state/cspp-mirs}"
HOST_CACHE="${MIRS_CACHE:-/data/ancillary/mirs}"

WORK_BASE="${MIRS_WORK_BASE:-/data/tmp}"
LOG_DIR="${MIRS_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

MIRS_OPTS="${MIRS_OPTS:---noSFR -l}"

# 8 procesos: la pasada de prueba tardó 1m45s y 5.6 GB de RAM con -p 8
NPROCS="${SLURM_CPUS_PER_TASK:-8}"
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
                (j02_d20260926_t082141) o cualquier trozo que la identifique
  -h, --help    Muestra esta ayuda

Requiere que run_sdr.sh haya corrido para ATMS:
  scripts/run_sdr.sh --sensor atms

Pasadas disponibles en $HOST_SDR_IN:
$(listar_pasadas "$HOST_SDR_IN" GATMO 2>/dev/null | cut -d' ' -f1 | sed 's/^/  /' || true)
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

# Staging y directorio de trabajo son HERMANOS, no anidados: el driver poda lo
# que crea bajo -W al terminar (inputs/, bigendian/, processed_gfs/), y un
# staging dentro de /work quedaría expuesto a esa limpieza.
HOST_WORK="${WORK_BASE}/mirs_work_${JOB_ID}"
STAGING_DIR="${WORK_BASE}/mirs_staging_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$HOST_SDR_IN" ]; then
    echo "ERROR: Directorio de SDR de ATMS no encontrado: $HOST_SDR_IN" >&2
    echo "       Corre antes: run_sdr.sh --sensor atms" >&2
    exit 1
fi

resolver_pasada "$HOST_SDR_IN" GATMO "$PASADA" || exit 1

if [ -z "$CLAVE" ]; then
    echo "No hay SDR de ATMS que procesar en $HOST_SDR_IN (no se ven archivos GATMO*)."
    exit 0
fi

echo "=============================================================================="
echo "CSPP MiRS v4.0 | pasada $CLAVE"
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

if [ ! -f "$SIF_MIRS" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_MIRS" >&2
    exit 1
fi

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================
# El driver exige un solo satélite por directorio y procesa todo lo que
# encuentre, así que se enlaza únicamente lo de esta pasada. Los enlaces apuntan
# a $HOST_SDR_IN, que por eso se monta más abajo sobre sí mismo: sin ese bind el
# contenedor ve los nombres pero no los archivos (ver run_omps_edr.sh).

mkdir -p "$STAGING_DIR" "$HOST_WORK" "$HOST_EDR_OUT" "$LOG_DIR" "$STATE_DIR" "$HOST_CACHE"
trap 'rm -rf "$HOST_WORK" "$STAGING_DIR"' EXIT

declare -A CUENTA=()
for prefijo in SATMS TATMS GATMO; do
    CUENTA[$prefijo]=0
    while IFS= read -r f; do
        ln -sf "$f" "$STAGING_DIR/"
        CUENTA[$prefijo]=$((CUENTA[$prefijo] + 1))
    done < <(archivos_de_pasada "$HOST_SDR_IN" "$prefijo")
done

LOG_FILE="$LOG_DIR/mirs_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR: SATMS ${CUENTA[SATMS]}, TATMS ${CUENTA[TATMS]}, GATMO ${CUENTA[GATMO]}" | tee -a "$LOG_FILE"
echo "  Salida: $HOST_EDR_OUT" | tee -a "$LOG_FILE"

# Los tres son obligatorios (manual §1.5). Sin SATMS, que HEAP no necesita, es
# fácil que falte sin que nadie lo haya notado.
for prefijo in SATMS TATMS GATMO; do
    if [ "${CUENTA[$prefijo]}" -eq 0 ]; then
        echo "ERROR: No se enlazó ningún $prefijo de la pasada $CLAVE" | tee -a "$LOG_FILE" >&2
        echo "       MiRS necesita SATMS, TATMS y GATMO." | tee -a "$LOG_FILE" >&2
        exit 1
    fi
done

if [ "${CUENTA[SATMS]}" -ne "${CUENTA[GATMO]}" ] || [ "${CUENTA[TATMS]}" -ne "${CUENTA[GATMO]}" ]; then
    echo "  ⚠ Cuentas desiguales entre SATMS, TATMS y GATMO: se sigue, pero pueden" | tee -a "$LOG_FILE"
    echo "    faltar gránulos en la salida" | tee -a "$LOG_FILE"
fi

# ==============================================================================
# PROCESAMIENTO
# ==============================================================================
# HOST_WORK nace vacío, así que el driver empieza siempre con directorio limpio:
# si encuentra el subdirectorio de preproceso de la pasada, se niega a correr
# ("Already processed or duplicate granules"). Los productos los deja en -W, y
# --pwd /work da un pwd escribible, que todo apptainer exec necesita.

echo "" | tee -a "$LOG_FILE"
echo ">>> Ejecutando run_mirs.bash ($NPROCS procesos, $MIRS_OPTS)..." | tee -a "$LOG_FILE"

EXIT_CODE=0
apptainer exec \
    --bind "$STAGING_DIR:/input" \
    --bind "$HOST_SDR_IN:$HOST_SDR_IN" \
    --bind "$HOST_WORK:/work" \
    --bind "$HOST_CACHE:/anc" \
    --pwd /work \
    "$SIF_MIRS" /bin/bash -c "
        export HDF5_USE_FILE_LOCKING=FALSE
        export LC_ALL=C
        source \$CSPP_MIRS_HOME/cspp_mirs_env.sh
        run_mirs.bash $MIRS_OPTS -p $NPROCS -d /anc -W /work /input
    " >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP MiRS falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR"                  | tee -a "$LOG_FILE"
    trap - EXIT
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN Y ENTREGA
# ==============================================================================
# El código de salida no basta. Se exigen LOS DOS productos, no "más de cero":
# el driver escribe IMG y SND juntos, y uno sin el otro es una corrida rota.

mapfile -t PRODUCTOS < <(find "$HOST_WORK" -maxdepth 1 -type f -name 'NPR-MIRS-*.nc' | sort)
IMG_COUNT=$(printf '%s\n' "${PRODUCTOS[@]}" | grep -c 'NPR-MIRS-IMG' || true)
SND_COUNT=$(printf '%s\n' "${PRODUCTOS[@]}" | grep -c 'NPR-MIRS-SND' || true)

if [ "$IMG_COUNT" -eq 0 ] || [ "$SND_COUNT" -eq 0 ]; then
    echo "❌ ERROR: MiRS terminó sin error pero no dejó el par IMG/SND" | tee -a "$LOG_FILE"
    echo "   (IMG $IMG_COUNT, SND $SND_COUNT)"                          | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                  | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR"                    | tee -a "$LOG_FILE"
    trap - EXIT
    exit 1
fi

mv "${PRODUCTOS[@]}" "$HOST_EDR_OUT/"

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "sdr:       SATMS ${CUENTA[SATMS]}, TATMS ${CUENTA[TATMS]}, GATMO ${CUENTA[GATMO]}"
    echo "img:       $IMG_COUNT archivos"
    echo "snd:       $SND_COUNT archivos"
    echo "duracion:  $DURACION"
    echo "salida:    $HOST_EDR_OUT"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "" | tee -a "$LOG_FILE"
echo "✅ ÉXITO: pasada $CLAVE (IMG $IMG_COUNT, SND $SND_COUNT) en $DURACION" | tee -a "$LOG_FILE"
echo "   Salida:   $HOST_EDR_OUT" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER"       | tee -a "$LOG_FILE"
