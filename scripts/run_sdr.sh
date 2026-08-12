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
#   ./run_sdr.sh <archivo_rdr>       # un archivo específico (sensor por nombre)
#   ./run_sdr.sh --force [rdr]       # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   SDR_INPUT_DIR     Entrada Level 0  (def. /data/output/jpss/level0)
#   SDR_STATE_DIR     Marcadores .done (def. /data/output/jpss/state/cspp-sdr)
#   SDR_OUTPUT_BASE   Salida Level 1   (def. /data/output/jpss/level1)
#   SDR_MIN_AGE_MIN   Edad mínima (min)(def. 1)
#   SDR_LOG_BASE      Raíz de logs     (def. /var/log/lanot/polares)
#   SDR_CONTAINER     Imagen .sif      (def. /opt/containers/cspp_sdr_v4.1.1.sif)
#   SDR_STATIC_BASE   LUTs estáticos   (def. /data/opt/SDR_4_1)
#   SDR_DYNAMIC       Ancillary TLE/GFS(def. /data/ancillary)
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

uso() {
    cat <<EOF
Uso:
  $0                    Procesa el RDR de VIIRS más reciente de $INPUT_DIR
  $0 --sensor <nombre>  Igual, pero de otro sensor: viirs, atms o cris
  $0 <archivo_rdr>      Procesa un archivo específico (el sensor se deduce
                        del nombre; --sensor se ignora en este caso)
  $0 --force [rdr]      Reprocesa aunque ya exista el marcador

Opciones:
  -s, --sensor  Sensor a buscar cuando no se indica archivo (def. viirs)
  -f, --force   Ignora el marcador de procesado y vuelve a calibrar
  -h, --help    Muestra esta ayuda
EOF
}

# Identifica el sensor a partir del nombre del RDR.
# Imprime "<sensor> <script_de_cspp>" y devuelve 1 si no lo reconoce.
# El orden importa: los RDR de VIIRS se llaman RNSCA-RVIRS_*, así que deben
# evaluarse antes que el patrón genérico RNSCA.
detectar_sensor() {
    local nombre="$1"

    case "$nombre" in
        *RVIIRS*|*RVIRS*) echo "viirs viirs_sdr.sh" ;;
        *RNSCA*|*RATMS*)  echo "atms atms_sdr.sh"   ;;
        *RCRIS*)          echo "cris cris_sdr.sh"   ;;
        *) return 1 ;;
    esac
}

# Imprime la ruta del RDR más reciente del sensor buscado que tenga al menos
# MIN_AGE_MIN minutos de antigüedad. Devuelve 1 si no hay ninguno.
seleccionar_rdr_mas_reciente() {
    local candidato info sensor

    while IFS= read -r candidato; do
        if info=$(detectar_sensor "$(basename "$candidato")"); then
            read -r sensor _ <<< "$info"
            if [ "$sensor" = "$SENSOR_BUSCADO" ]; then
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
                echo "ERROR: --sensor requiere un nombre (viirs, atms o cris)" >&2
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
    viirs|atms|cris) ;;
    *)
        echo "ERROR: Sensor no soportado: $SENSOR_BUSCADO (usa viirs, atms o cris)" >&2
        exit 1
        ;;
esac

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP_FILE=$(date '+%Y%m%d_%H%M%S')

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
    echo "Patrones esperados: RVIIRS/RVIRS (viirs), RNSCA/RATMS (atms), RCRIS (cris)" >&2
    exit 1
fi

read -r SENSOR EXEC_CMD <<< "$SENSOR_INFO"

OUTPUT_DIR="$BASE_OUTPUT/$SENSOR"

echo "[$TIMESTAMP] Sensor detectado: $SENSOR ($EXEC_CMD)"
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
        echo "       Revisa deploy_static_data_sdr.sh y update_sdr_daily.sh" >&2
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

# Referencia para contar únicamente lo generado en esta corrida. No sirve el
# mtime del RDR: si es viejo (o se reprocesa con --force), la cuenta arrastraría
# la salida de todas las pasadas posteriores.
# Nota: 'find -newer' exige mtime estrictamente mayor y el reloj puede dar el
# mismo sello a dos escrituras inmediatas, así que una corrida instantánea
# contaría 0. No afecta a CSPP (tarda minutos) y falla del lado seguro: en el
# peor caso se reintenta, nunca se marca por error como procesado.
REF_FILE=$(mktemp -t cspp_sdr_ref_XXXXXX)
trap "rm -f $REF_FILE" EXIT

echo "[$TIMESTAMP] Procesando con CSPP SDR ($CORES hilos)..."

# --- Preparación de montajes (binds) dinámicos ---
BIND_OPTS=(
    --bind "$INPUT_DIR_REAL:/input"
    --bind "$OUTPUT_DIR:/output"
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

    # CRÍTICO: Entrar a la carpeta de salida
    cd /output

    echo '--- Iniciando CSPP SDR para $SENSOR ---'
    $EXEC_CMD -p $CORES -a -g /input/$FILENAME
" > "$LOG_FILE" 2>&1 || EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo "[$TIMESTAMP] ERROR: CSPP SDR falló (código $EXIT_CODE)" >&2
    echo "[$TIMESTAMP] Ver log: $LOG_FILE" >&2
    echo "[$TIMESTAMP] No se escribió el marcador: el archivo se reintentará." >&2
    exit $EXIT_CODE
fi

# Contar los archivos generados en esta corrida
SDR_COUNT=$(find "$OUTPUT_DIR" -name "*.h5" -newer "$REF_FILE" 2>/dev/null | wc -l)

# El código de salida no basta como criterio de éxito: estas herramientas
# pueden terminar en 0 sin haber producido nada.
if [ "$SDR_COUNT" -eq 0 ]; then
    echo "[$TIMESTAMP] ERROR: CSPP SDR terminó sin error pero no generó archivos." >&2
    echo "[$TIMESTAMP] Revisa el RDR de entrada y los LUTs: $FILENAME" >&2
    echo "[$TIMESTAMP] Ver log: $LOG_FILE" >&2
    echo "[$TIMESTAMP] No se escribió el marcador: el archivo se reintentará." >&2
    exit 1
fi

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
echo "  Salida:        $OUTPUT_DIR"
echo "  Log:           $LOG_FILE"
echo "  Marcador:      $MARKER"
echo "=============================================================================="

exit 0
