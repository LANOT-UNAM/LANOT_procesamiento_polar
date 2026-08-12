#!/bin/bash
################################################################################
# Script: run_rt_stps.sh
# Propósito: Procesamiento con RT-STPS únicamente (RAW → Level 0)
# Autor: LANOT - UNAM
#
# Descripción:
#   Ejecuta el primer paso de la cadena: conversión de archivos RAW a Level 0
#   (RDR) usando el contenedor RT-STPS v7.0.
#
#   Sin argumentos toma el RAW más reciente del buzón de antena, ignorando los
#   que aún se están escribiendo y los de satélites legacy (chain4/chain5). Si
#   esa pasada ya fue procesada con éxito, avisa y no hace nada.
#
# Uso:
#   ./run_rt_stps.sh                  # el RAW más reciente pendiente
#   ./run_rt_stps.sh <archivo_raw>    # un archivo específico
#   ./run_rt_stps.sh --force [raw]    # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   RTSTPS_INPUT_DIR    Buzón de RAW      (def. /datawork/input/polar/raw)
#   RTSTPS_STATE_DIR    Marcadores .done  (def. /data/output/jpss/state/rt-stps)
#   RTSTPS_MIN_AGE_MIN  Edad mínima (min) (def. 1)
#
################################################################################

set -euo pipefail  # Modo estricto: abortar en errores

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

# Contenedor RT-STPS
CONTAINER_RT_STPS="/opt/containers/rt_stps_7.0.sif"

# Directorios del sistema
HOST_CONFIG_DIR="/data/opt/RT-STPS/rt-stps/config"
HOST_LEAPSEC="/data/ancillary/common/leapsec.dat"

# Buzón de archivos RAW de la antena (compartido con las cadenas legacy)
INPUT_DIR="${RTSTPS_INPUT_DIR:-/datawork/input/polar/raw}"

# Marcadores de procesamiento exitoso (fuente de verdad de "ya procesado")
STATE_DIR="${RTSTPS_STATE_DIR:-/data/output/jpss/state/rt-stps}"

# Edad mínima de un RAW para considerarlo completo (la antena puede estar
# escribiéndolo todavía)
MIN_AGE_MIN="${RTSTPS_MIN_AGE_MIN:-1}"

# Directorio de salida
DIR_L0="/data/output/jpss/level0"

# Directorio de logs
LOG_BASE="/var/log/lanot/polares"
LOG_RT_STPS="${LOG_BASE}/rt-stps"

# ============================================================================
# FUNCIONES
# ============================================================================

uso() {
    cat <<EOF
Uso:
  $0                  Procesa el RAW más reciente de $INPUT_DIR
  $0 <archivo_raw>    Procesa un archivo específico
  $0 --force [raw]    Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force   Ignora el marcador de procesado y vuelve a decodificar
  -h, --help    Muestra esta ayuda
EOF
}

# Identifica el satélite a partir del nombre del archivo.
# Imprime "<SATELITE> <archivo_xml>" y devuelve 1 si no es un satélite moderno
# (chain4 = NOAA legacy y chain5 = METOP no los procesa RT-STPS).
detectar_satelite() {
    local nombre="$1"

    if [[ "$nombre" =~ chain2 ]] || [[ "$nombre" =~ npp ]]; then
        echo "NPP npp.xml"
    elif [[ "$nombre" =~ chain6 ]] || [[ "$nombre" =~ j01 ]] || [[ "$nombre" =~ noaa20 ]]; then
        echo "NOAA-20 jpss1.xml"
    elif [[ "$nombre" =~ j02 ]] || [[ "$nombre" =~ noaa21 ]]; then
        echo "NOAA-21 jpss2.xml"
    else
        return 1
    fi
}

# Imprime la ruta del RAW más reciente del buzón que sea de un satélite moderno
# y tenga al menos MIN_AGE_MIN minutos de antigüedad. Devuelve 1 si no hay.
seleccionar_raw_mas_reciente() {
    local candidato

    while IFS= read -r candidato; do
        if detectar_satelite "$(basename "$candidato")" > /dev/null; then
            echo "$candidato"
            return 0
        fi
    done < <(find "$INPUT_DIR" -maxdepth 1 -type f -mmin "+${MIN_AGE_MIN}" \
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
                echo "ERROR: Solo se admite un archivo RAW por ejecución" >&2
                exit 1
            fi
            INPUT_FILE="$1"
            ;;
    esac
    shift
done

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP_FILE=$(date '+%Y%m%d_%H%M%S')

# ============================================================================
# SELECCIÓN DEL ARCHIVO A PROCESAR
# ============================================================================

if [ -n "$INPUT_FILE" ]; then
    # Archivo indicado explícitamente
    if [ ! -f "$INPUT_FILE" ]; then
        echo "ERROR: Archivo no encontrado: $INPUT_FILE" >&2
        exit 1
    fi
    INPUT_FILE=$(realpath "$INPUT_FILE")
else
    # Sin argumento: el más reciente del buzón de antena
    if [ ! -d "$INPUT_DIR" ]; then
        echo "ERROR: Directorio de entrada no encontrado: $INPUT_DIR" >&2
        exit 1
    fi

    echo "[$TIMESTAMP] Buscando el RAW más reciente en: $INPUT_DIR"

    if ! INPUT_FILE=$(seleccionar_raw_mas_reciente); then
        echo "[$TIMESTAMP] No hay archivos RAW de satélites modernos pendientes."
        echo "              (se ignoran chain4/chain5 y los modificados en los"
        echo "               últimos ${MIN_AGE_MIN} min, que pueden estar incompletos)"
        exit 0
    fi

    INPUT_FILE=$(realpath "$INPUT_FILE")
fi

FILENAME=$(basename "$INPUT_FILE")
INPUT_DIR_REAL=$(dirname "$INPUT_FILE")

echo "=============================================================================="
echo "[$TIMESTAMP] PROCESAMIENTO RT-STPS: $FILENAME"
echo "=============================================================================="

# ============================================================================
# DETECCIÓN DE SATÉLITE
# ============================================================================

if ! SAT_INFO=$(detectar_satelite "$FILENAME"); then
    echo "[$TIMESTAMP] ERROR: No se pudo identificar el satélite desde el nombre: $FILENAME" >&2
    echo "Patrones esperados: chain2/npp, chain6/j01/noaa20, j02/noaa21" >&2
    echo "Los satélites legacy (chain4 = NOAA 15/18/19, chain5 = METOP) no los procesa RT-STPS." >&2
    exit 1
fi

read -r SATELLITE XML_TARGET <<< "$SAT_INFO"

echo "[$TIMESTAMP] Satélite detectado: $SATELLITE"
echo "[$TIMESTAMP] Configuración XML: $XML_TARGET"

# ============================================================================
# ¿YA FUE PROCESADO?
# ============================================================================
# El marcador se escribe únicamente cuando RT-STPS termina con éxito, así que
# una pasada fallida se reintenta sola en la siguiente ejecución.

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

if [ ! -f "$CONTAINER_RT_STPS" ]; then
    echo "ERROR: Contenedor no encontrado: $CONTAINER_RT_STPS" >&2
    exit 1
fi

if [ ! -f "$HOST_LEAPSEC" ]; then
    echo "ERROR: Archivo leapsec.dat no encontrado: $HOST_LEAPSEC" >&2
    exit 1
fi

if [ ! -s "$HOST_LEAPSEC" ]; then
    echo "ERROR: Archivo leapsec.dat está vacío: $HOST_LEAPSEC" >&2
    exit 1
fi

if [ ! -f "$HOST_CONFIG_DIR/$XML_TARGET" ]; then
    echo "ERROR: No se encontró el archivo de configuración: $HOST_CONFIG_DIR/$XML_TARGET" >&2
    exit 1
fi

# ============================================================================
# PROCESAMIENTO: RAW → LEVEL 0 (RT-STPS v7.0)
# ============================================================================

echo ""
echo "------------------------------------------------------------------------------"
echo "[$TIMESTAMP] RT-STPS - Decodificación RAW → Level 0"
echo "------------------------------------------------------------------------------"

# Crear directorio temporal para configuración modificada
WORK_DIR=$(mktemp -d -t rt_stps_XXXXXX)
trap "rm -rf $WORK_DIR" EXIT  # Limpieza automática al salir

# Crear directorios de salida y logs si no existen
mkdir -p "$DIR_L0"
mkdir -p "$LOG_RT_STPS"

# --- Preparar archivo de configuración XML ---
# Copiar el XML del satélite y modificar la ruta de salida para el contenedor
cp "$HOST_CONFIG_DIR/$XML_TARGET" "$WORK_DIR/config_temp.xml"

# Reemplazar todas las referencias a directorios de datos con /output
sed -i 's|<dest>.*</dest>|<dest>/output</dest>|g' "$WORK_DIR/config_temp.xml"
sed -i 's|<outputPath>.*</outputPath>|<outputPath>/output</outputPath>|g' "$WORK_DIR/config_temp.xml"
sed -i 's|<directory>.*</directory>|<directory>/output</directory>|g' "$WORK_DIR/config_temp.xml"
# Reemplazar cualquier referencia a ../data o rutas absolutas
sed -i 's|\.\./data|/output|g' "$WORK_DIR/config_temp.xml"
sed -i 's|/opt/rt-stps/data|/output|g' "$WORK_DIR/config_temp.xml"

echo "[$TIMESTAMP] Procesando con RT-STPS..."

LOG_FILE="${LOG_RT_STPS}/${TIMESTAMP_FILE}_${SATELLITE}_${FILENAME}.log"

# --- Ejecución del contenedor ---
# El '|| APPTAINER_EXIT_CODE=$?' es indispensable: sin él, 'set -e' abortaría el
# script antes de poder informar cuál es el log que hay que revisar.
APPTAINER_EXIT_CODE=0
apptainer exec \
    --bind "$INPUT_DIR_REAL":/input \
    --bind "$DIR_L0":/output \
    --bind "$WORK_DIR":/config_bind \
    --bind "$HOST_LEAPSEC":/opt/rt-stps/leapsec.dat \
    "$CONTAINER_RT_STPS" \
    /bin/bash -c "cd /opt/rt-stps && ./bin/batch.sh /config_bind/config_temp.xml /input/$FILENAME" \
    > "$LOG_FILE" 2>&1 || APPTAINER_EXIT_CODE=$?

# Verificar éxito del procesamiento
if [ $APPTAINER_EXIT_CODE -ne 0 ]; then
    echo "[$TIMESTAMP] ERROR: RT-STPS falló (código $APPTAINER_EXIT_CODE)" >&2
    echo "[$TIMESTAMP] Ver log: $LOG_FILE" >&2
    echo "[$TIMESTAMP] No se escribió el marcador: el archivo se reintentará." >&2
    exit 1
fi

# Contar archivos RDR generados
RDR_COUNT=$(find "$DIR_L0" -name "*.h5" -newer "$INPUT_FILE" 2>/dev/null | wc -l)

# ============================================================================
# MARCADOR DE PROCESAMIENTO EXITOSO
# ============================================================================

mkdir -p "$STATE_DIR"
{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "satelite:  $SATELLITE"
    echo "rdr:       $RDR_COUNT archivos"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo ""
echo "=============================================================================="
echo "[$TIMESTAMP] PROCESAMIENTO COMPLETADO"
echo "=============================================================================="
echo "  Satélite:      $SATELLITE"
echo "  Archivos RDR:  $RDR_COUNT archivos .h5"
echo "  Log:           $LOG_FILE"
echo "  Marcador:      $MARKER"
echo "=============================================================================="

exit 0
