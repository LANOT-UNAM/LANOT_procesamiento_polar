#!/bin/bash
################################################################################
# Script: run_sdr.sh
# Propósito: Procesamiento CSPP SDR v4.1.1 (Level 0 → Level 1), LUTs externos
# Autor: LANOT - UNAM
#
# Descripción:
#   Calibra y geolocaliza un RDR generado por RT-STPS. Sin argumentos toma el
#   RDR más reciente del sensor por omisión (VIIRS) que haya en level0,
#   ignorando los que aún se están escribiendo. Si esa entrada ya fue procesada
#   con éxito, avisa y no hace nada.
#
#   Se considera exitoso solo si CSPP sale con código 0 Y genera al menos un
#   archivo en la carpeta del sensor: con una entrada inservible puede terminar
#   en 0 sin producir nada (comportamiento verificado en RT-STPS).
#
# Uso:
#   ./run_sdr.sh                     # el RDR de VIIRS más reciente pendiente
#   ./run_sdr.sh --sensor cris       # idem, pero de CrIS
#   ./run_sdr.sh --sensor omps_nm    # OMPS Nadir Mapper (omps_np para el Profiler)
#   ./run_sdr.sh <archivo_rdr>       # un archivo específico (sensor por nombre)
#   ./run_sdr.sh --force [rdr]       # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   SDR_INPUT_DIR     Entrada Level 0  (def. /data/output/jpss/level0)
#   SDR_STATE_DIR     Marcadores .done (def. /data/output/jpss/state/cspp-sdr)
#   SDR_OUTPUT_BASE   Salida Level 1   (def. /data/output/jpss/level1)
#   SDR_WORK_BASE     Raíz de trabajo  (def. /data/tmp)
#   SDR_MIN_AGE_MIN   Edad mínima (min)(def. 1)
#   SDR_LOG_BASE      Raíz de logs     (def. /var/log/lanot/polares)
#   SDR_CONTAINER     Imagen .sif      (def. /opt/containers/cspp_sdr_v4.1.1.sif)
#   SDR_STATIC_BASE   LUTs estáticos   (def. /data/opt/SDR_4_1)
#   SDR_DYNAMIC       Ancillary TLE/GFS(def. /data/ancillary)
#   SDR_OPTS          Banderas de CSPP (def. según el sensor, ver detectar_sensor)
#
################################################################################

set -euo pipefail  # Modo estricto: abortar en errores

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

SIF_CSPP="${SDR_CONTAINER:-/opt/containers/cspp_sdr_v4.1.1.sif}"

# Datos estáticos (LUTs por instrumento) y dinámicos (TLE/GFS diarios)
HOST_STATIC_BASE="${SDR_STATIC_BASE:-/data/opt/SDR_4_1}"
HOST_DYNAMIC="${SDR_DYNAMIC:-/data/ancillary}"

# Entrada: los RDR que deja RT-STPS
INPUT_DIR="${SDR_INPUT_DIR:-/data/output/jpss/level0}"

# Salida: se crea una carpeta por sensor
BASE_OUTPUT="${SDR_OUTPUT_BASE:-/data/output/jpss/level1}"

# Raíz de los directorios de trabajo (uno por corrida, ver más abajo)
WORK_BASE="${SDR_WORK_BASE:-/data/tmp}"

# Marcadores de procesamiento exitoso (fuente de verdad de "ya procesado")
STATE_DIR="${SDR_STATE_DIR:-/data/output/jpss/state/cspp-sdr}"

# Edad mínima de un RDR para considerarlo completo
MIN_AGE_MIN="${SDR_MIN_AGE_MIN:-1}"

# Logs
LOG_BASE="${SDR_LOG_BASE:-/var/log/lanot/polares}"
LOG_DIR="${LOG_BASE}/cspp-sdr"

# Hilos de procesamiento (respeta la asignación de Slurm si la hay)
CORES="${SLURM_CPUS_PER_TASK:-20}"

# Sensor por omisión al buscar automáticamente
SENSOR_BUSCADO="viirs"

# ============================================================================
# FUNCIONES
# ============================================================================

# Expresa una cantidad de segundos en forma legible (2h 5m 9s / 7m 30s / 12s)
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

uso() {
    cat <<EOF
Uso:
  $0                    Procesa el RDR de VIIRS más reciente de $INPUT_DIR
  $0 --sensor <nombre>  Igual, pero de otro: atms, cris, omps_nm u omps_np
  $0 <archivo_rdr>      Procesa un archivo específico (el sensor se deduce
                        del nombre; --sensor se ignora en este caso)
  $0 --force [rdr]      Reprocesa aunque ya exista el marcador

Opciones:
  -s, --sensor  Sensor a buscar cuando no se indica archivo (def. viirs).
                OMPS son dos instrumentos con RDR distintos y el manual exige
                una llamada por cada uno: omps_nm (Nadir Mapper, ROTCS) y
                omps_np (Nadir Profiler, RONPS). Los dos escriben en level1/omps.
  -f, --force   Ignora el marcador de procesado y vuelve a calibrar
  -h, --help    Muestra esta ayuda
EOF
}

# Identifica el sensor a partir del nombre del RDR. Imprime
# "<clave> <sensor> <script_de_cspp> <banderas>" y devuelve 1 si no lo reconoce.
#
# La CLAVE es lo que se busca con --sensor y el SENSOR es lo que determina las
# rutas (LUTs en <static>/<sensor>/luts, salida en level1/<sensor>). Casi
# siempre coinciden; OMPS es la excepción, porque son dos instrumentos con RDR
# distintos —Nadir Mapper (ROTCS) y Nadir Profiler (RONPS)— que comparten LUTs
# y directorio de salida. Hacen falta claves separadas porque el manual (§7.1)
# exige una llamada por instrumento, y porque con una sola clave la
# autoselección tomaría el más reciente de los dos y se detendría en su
# marcador sin procesar nunca el otro.
#
# El sensor lo da SIEMPRE el RDR de ciencia (RVIRS/RATMS/RCRIS/ROTCS/RONPS).
# RNSCA no es un sensor: es el spacecraft diary (efemérides y actitud) que
# RT-STPS adjunta a todos (RNSCA-RVIRS, RATMS-RNSCA, RCRIS-RNSCA, RNSCA-ROTCS),
# así que no puede usarse para distinguirlos — hacerlo mandaba los RDR de CrIS
# a atms_sdr.sh.
#
# Las banderas no son iguales para los tres drivers: adl_atms_sdr.py no acepta
# -g (verificado en tahan, 2026-08-13), solo viirs_sdr.sh lo entiende.
#
# CrIS y ATMS van sin -a porque para ellos no sirve de nada: cris_sdr.sh y
# atms_sdr.sh declaran AGGREGATE_OPT pero nunca lo usan, se limitan a
# reenviar "$@" al driver de Python, donde 'aggregate' ya viene en True.
# Verificado en tahan el 2026-08-13 con un A/B sobre la misma pasada: con -a y
# sin -a salen exactamente los mismos SCRIF/GCRSO agregados.
#
# La salida sale agregada, entonces, y así le sirve a HEAP, que de todos modos
# desagrega la entrada antes de procesar (manual HEAP §4, run_heap.bash).
detectar_sensor() {
    local nombre="$1"

    #     clave    sensor  script         banderas
    case "$nombre" in
        *RVIIRS*|*RVIRS*) echo "viirs   viirs viirs_sdr.sh -a -g" ;;
        *RATMS*)          echo "atms    atms  atms_sdr.sh"        ;;
        *RCRIS*)          echo "cris    cris  cris_sdr.sh"        ;;
        *ROTCS*)          echo "omps_nm omps  omps_sdr.sh"        ;;
        *RONPS*)          echo "omps_np omps  omps_sdr.sh"        ;;
        *) return 1 ;;
    esac
}

# Imprime la ruta del RDR más reciente del sensor buscado que tenga al menos
# MIN_AGE_MIN minutos de antigüedad. Devuelve 1 si no hay ninguno.
seleccionar_rdr_mas_reciente() {
    local candidato info clave

    while IFS= read -r candidato; do
        if info=$(detectar_sensor "$(basename "$candidato")"); then
            read -r clave _ <<< "$info"
            if [ "$clave" = "$SENSOR_BUSCADO" ]; then
                echo "$candidato"
                return 0
            fi
        fi
    done < <(find "$INPUT_DIR" -maxdepth 1 -type f -name '*.h5' -mmin "+${MIN_AGE_MIN}" \
                  -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    return 1
}

# ============================================================================
# ARGUMENTOS
# ============================================================================

FORCE=0
INPUT_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)
            FORCE=1
            ;;
        -s|--sensor)
            if [ -z "${2:-}" ]; then
                echo "ERROR: --sensor requiere un nombre (viirs, atms, cris, omps_nm, omps_np)" >&2
                exit 1
            fi
            SENSOR_BUSCADO="$2"
            shift
            ;;
        -h|--help)
            uso
            exit 0
            ;;
        -*)
            echo "ERROR: Opción desconocida: $1" >&2
            uso >&2
            exit 1
            ;;
        *)
            if [ -n "$INPUT_FILE" ]; then
                echo "ERROR: Solo se admite un archivo RDR por ejecución" >&2
                exit 1
            fi
            INPUT_FILE="$1"
            ;;
    esac
    shift
done

case "$SENSOR_BUSCADO" in
    viirs|atms|cris|omps_nm|omps_np) ;;
    *)
        echo "ERROR: Sensor no soportado: $SENSOR_BUSCADO" >&2
        echo "       Usa viirs, atms, cris, omps_nm u omps_np" >&2
        exit 1
        ;;
esac

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP_FILE=$(date '+%Y%m%d_%H%M%S')
START_EPOCH=$(date '+%s')

# ============================================================================
# SELECCIÓN DEL ARCHIVO A PROCESAR
# ============================================================================

if [ -n "$INPUT_FILE" ]; then
    if [ ! -f "$INPUT_FILE" ]; then
        echo "ERROR: Archivo no encontrado: $INPUT_FILE" >&2
        exit 1
    fi
    INPUT_FILE=$(realpath "$INPUT_FILE")
else
    if [ ! -d "$INPUT_DIR" ]; then
        echo "ERROR: Directorio de entrada no encontrado: $INPUT_DIR" >&2
        exit 1
    fi

    echo "[$TIMESTAMP] Buscando el RDR de $SENSOR_BUSCADO más reciente en: $INPUT_DIR"

    if ! INPUT_FILE=$(seleccionar_rdr_mas_reciente); then
        echo "[$TIMESTAMP] No hay RDR de $SENSOR_BUSCADO pendientes."
        echo "              (se ignoran los modificados en los últimos"
        echo "               ${MIN_AGE_MIN} min, que pueden estar incompletos)"
        exit 0
    fi

    INPUT_FILE=$(realpath "$INPUT_FILE")
fi

FILENAME=$(basename "$INPUT_FILE")
INPUT_DIR_REAL=$(dirname "$INPUT_FILE")

echo "=============================================================================="
echo "[$TIMESTAMP] PROCESAMIENTO CSPP SDR: $FILENAME"
echo "=============================================================================="

# ============================================================================
# DETECCIÓN DE SENSOR
# ============================================================================

if ! SENSOR_INFO=$(detectar_sensor "$FILENAME"); then
    echo "[$TIMESTAMP] ERROR: Sensor no identificado en el nombre: $FILENAME" >&2
    echo "Patrones esperados: RVIIRS/RVIRS (viirs), RATMS (atms), RCRIS (cris)," >&2
    echo "ROTCS (omps_nm), RONPS (omps_np)." >&2
    echo "RNSCA por sí solo es el spacecraft diary, no un RDR de ciencia." >&2
    exit 1
fi

# La última variable de 'read' recoge el resto de la línea: las banderas
read -r CLAVE_SENSOR SENSOR EXEC_CMD OPTS_SENSOR <<< "$SENSOR_INFO"
OPTS_SENSOR="${SDR_OPTS:-$OPTS_SENSOR}"

OUTPUT_DIR="$BASE_OUTPUT/$SENSOR"

echo "[$TIMESTAMP] Sensor detectado: $CLAVE_SENSOR ($EXEC_CMD)"
echo "[$TIMESTAMP] Salida:           $OUTPUT_DIR"

# ============================================================================
# ¿YA FUE PROCESADO?
# ============================================================================
# El marcador se escribe únicamente cuando CSPP termina con éxito y produce
# archivos, así que una pasada fallida se reintenta sola.

MARKER="${STATE_DIR}/${FILENAME}.done"

if [ -f "$MARKER" ] && [ "$FORCE" -eq 0 ]; then
    echo ""
    echo "ℹ  $FILENAME ya fue procesado:"
    while IFS= read -r linea; do
        echo "   $linea"
    done < "$MARKER"
    echo ""
    echo "   No hay nada que hacer. Usa --force para reprocesarlo."
    exit 0
fi

if [ -f "$MARKER" ]; then
    echo "[$TIMESTAMP] --force: se reprocesa a pesar del marcador existente"
fi

# ============================================================================
# VALIDACIÓN DEL AMBIENTE
# ============================================================================
# Se valida hasta aquí a propósito: primero se decide si hay trabajo que hacer,
# y solo entonces se exige que el entorno de procesamiento esté completo.

if [ ! -f "$SIF_CSPP" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_CSPP" >&2
    exit 1
fi

for dir in "$HOST_DYNAMIC" "$HOST_STATIC_BASE/anc" "$HOST_STATIC_BASE/$SENSOR/luts"; do
    if [ ! -d "$dir" ]; then
        echo "ERROR: Directorio de datos auxiliares no encontrado: $dir" >&2
        echo "       Revisa preparar_servidor.sh --verificar y update_sdr_daily.sh" >&2
        exit 1
    fi
done

# ============================================================================
# PROCESAMIENTO: LEVEL 0 → LEVEL 1 (CSPP SDR v4.1.1)
# ============================================================================

echo ""
echo "------------------------------------------------------------------------------"
echo "[$TIMESTAMP] CSPP SDR - Calibración Level 0 → Level 1"
echo "------------------------------------------------------------------------------"

mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

LOG_FILE="$LOG_DIR/${TIMESTAMP_FILE}_${SENSOR}_${FILENAME}.log"

# Directorio de trabajo propio y vacío para esta corrida. NO se puede usar el
# de salida como pwd: los drivers agregan todo lo que encuentran ahí, así que
# los productos de la pasada anterior entran a la agregación, nagg no logra
# cerrar el hueco entre ambas series ("no more fill granule available") y la
# limpieza final se lleva las dos — el directorio queda vacío aunque el log
# diga 'Completed without problems'. El manual lo pide explícitamente para los
# tres drivers (§§4.1, 5.1, 6.1: "All files should be removed from the work
# directory before each execution"). Verificado en tahan el 2026-08-13.
HOST_WORK="${WORK_BASE}/sdr_work_${SENSOR}_${TIMESTAMP_FILE}_${SLURM_JOB_ID:-$$}"
mkdir -p "$HOST_WORK"

echo "[$TIMESTAMP] Procesando con CSPP SDR ($CORES hilos)..."

# --- Preparación de montajes (binds) dinámicos ---
BIND_OPTS=(
    --bind "$INPUT_DIR_REAL:/input"
    --bind "$HOST_WORK:/work"
    --bind "$HOST_DYNAMIC:/ancillary"
    --bind "$HOST_STATIC_BASE/anc:/opt/SDR_4_1/anc"
    --bind "$HOST_STATIC_BASE/$SENSOR/luts:/opt/SDR_4_1/$SENSOR/luts"
)

# El '|| EXIT_CODE=$?' es indispensable: sin él, 'set -e' abortaría el script
# antes de poder informar cuál es el log que hay que revisar.
EXIT_CODE=0
apptainer exec "${BIND_OPTS[@]}" "$SIF_CSPP" /bin/bash -c "
    export HDF5_USE_FILE_LOCKING=FALSE
    export CSPP_SDR_HOME=/opt/cspp_sdr
    export CSPP_DYNAMIC_ANCIL_DIR=/ancillary

    # Carga el entorno oficial de CSPP
    source \$CSPP_SDR_HOME/cspp_sdr_env.sh

    # CRÍTICO: los drivers de CSPP trabajan en el pwd
    cd /work

    echo '--- Iniciando CSPP SDR para $SENSOR ---'
    $EXEC_CMD -p $CORES $OPTS_SENSOR /input/$FILENAME
" > "$LOG_FILE" 2>&1 || EXIT_CODE=$?

# CSPP tarda minutos: de aquí en adelante los mensajes llevan la hora real, no
# la del arranque del script.
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "[$TIMESTAMP] ERROR: CSPP SDR falló (código $EXIT_CODE)" >&2
    echo "[$TIMESTAMP] Ver log: $LOG_FILE" >&2
    echo "[$TIMESTAMP] El directorio de trabajo se conserva: $HOST_WORK" >&2
    echo "[$TIMESTAMP] No se escribió el marcador: el archivo se reintentará." >&2
    exit $EXIT_CODE
fi

# Los productos finales quedan en la raíz del directorio de trabajo; los
# subdirectorios por gránulo son intermedios y CSPP los borra al terminar.
# Como el directorio nace vacío en cada corrida, basta contar: ya no hace falta
# comparar contra una marca de tiempo.
mapfile -t PRODUCTOS < <(find "$HOST_WORK" -maxdepth 1 -type f -name '*.h5' | sort)
SDR_COUNT=${#PRODUCTOS[@]}

# El código de salida no basta como criterio de éxito: estas herramientas
# pueden terminar en 0 sin haber producido nada.
if [ "$SDR_COUNT" -eq 0 ]; then
    echo "[$TIMESTAMP] ERROR: CSPP SDR terminó sin error pero no generó archivos." >&2
    echo "[$TIMESTAMP] Revisa el RDR de entrada y los LUTs: $FILENAME" >&2
    echo "[$TIMESTAMP] Ver log: $LOG_FILE" >&2
    echo "[$TIMESTAMP] El directorio de trabajo se conserva: $HOST_WORK" >&2
    echo "[$TIMESTAMP] No se escribió el marcador: el archivo se reintentará." >&2
    exit 1
fi

# Entrega: los productos se mueven a level1/<sensor> y el directorio de trabajo
# se descarta, de modo que la próxima corrida vuelva a empezar en limpio.
mv "${PRODUCTOS[@]}" "$OUTPUT_DIR/"
rm -rf "$HOST_WORK"

# ============================================================================
# MARCADOR DE PROCESAMIENTO EXITOSO
# ============================================================================

mkdir -p "$STATE_DIR"
{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "sensor:    $SENSOR"
    echo "sdr:       $SDR_COUNT archivos"
    echo "salida:    $OUTPUT_DIR"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo ""
echo "=============================================================================="
echo "[$TIMESTAMP] PROCESAMIENTO COMPLETADO"
echo "=============================================================================="
echo "  Sensor:        $SENSOR"
echo "  Archivos SDR:  $SDR_COUNT archivos .h5"
echo "  Duración:      $DURACION"
echo "  Salida:        $OUTPUT_DIR"
echo "  Log:           $LOG_FILE"
echo "  Marcador:      $MARKER"
echo "=============================================================================="

exit 0
