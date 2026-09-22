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
#   que aún se están escribiendo y los que no son JPSS (config/cadenas.tsv). Si
#   esa pasada ya fue procesada con éxito, avisa y no hace nada.
#
# Uso:
#   ./run_rt_stps.sh                  # el RAW más reciente pendiente
#   ./run_rt_stps.sh <archivo_raw>    # un archivo específico
#   ./run_rt_stps.sh --force [raw]    # reprocesa aunque ya tenga marcador
#
#   Se considera exitoso solo si RT-STPS sale con código 0 Y genera al menos un
#   RDR: con un RAW corrupto termina en 0 sin decodificar nada.
#
# Variables de entorno (para pruebas o rutas alternas):
#   RTSTPS_INPUT_DIR    Buzón de RAW      (def. /datawork/input/polar/raw)
#   RTSTPS_STATE_DIR    Marcadores .done  (def. /data/output/jpss/state/rt-stps)
#   RTSTPS_OUTPUT_DIR   Salida Level 0    (def. /data/output/jpss/level0)
#   RTSTPS_MIN_AGE_MIN  Edad mínima (min) (def. 1)
#   RTSTPS_LOG_BASE     Raíz de logs      (def. /var/log/lanot/polares)
#   RTSTPS_CONTAINER    Imagen .sif       (def. /opt/containers/rt_stps_7.0.sif)
#   RTSTPS_CONFIG_DIR   XMLs de RT-STPS   (def. /data/opt/RT-STPS/rt-stps/config)
#   RTSTPS_LEAPSEC      leapsec.dat       (def. /data/ancillary/common/leapsec.dat)
#   CADENAS_TSV         Cadena → satélite (def. <scripts>/../config/cadenas.tsv)
#
################################################################################

set -euo pipefail  # Modo estricto: abortar en errores

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

# Contenedor RT-STPS
CONTAINER_RT_STPS="${RTSTPS_CONTAINER:-/opt/containers/rt_stps_7.0.sif}"

# Directorios del sistema
HOST_CONFIG_DIR="${RTSTPS_CONFIG_DIR:-/data/opt/RT-STPS/rt-stps/config}"
HOST_LEAPSEC="${RTSTPS_LEAPSEC:-/data/ancillary/common/leapsec.dat}"

# Buzón de archivos RAW de la antena (compartido con las cadenas legacy)
INPUT_DIR="${RTSTPS_INPUT_DIR:-/datawork/input/polar/raw}"

# Marcadores de procesamiento exitoso (fuente de verdad de "ya procesado")
STATE_DIR="${RTSTPS_STATE_DIR:-/data/output/jpss/state/rt-stps}"

# Edad mínima de un RAW para considerarlo completo (la antena puede estar
# escribiéndolo todavía)
MIN_AGE_MIN="${RTSTPS_MIN_AGE_MIN:-1}"

# Directorio de salida
DIR_L0="${RTSTPS_OUTPUT_DIR:-/data/output/jpss/level0}"

# Directorio de logs
LOG_BASE="${RTSTPS_LOG_BASE:-/var/log/lanot/polares}"
LOG_RT_STPS="${LOG_BASE}/rt-stps"

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
  $0                  Procesa el RAW más reciente de $INPUT_DIR
  $0 <archivo_raw>    Procesa un archivo específico
  $0 --force [raw]    Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force   Ignora el marcador de procesado y vuelve a decodificar
  -h, --help    Muestra esta ayuda
EOF
}

# Qué satélite es cada crudo lo decide config/cadenas.tsv, la misma tabla que
# leen recibe.sh y el barrido. consultar_cadena imprime "<SATELITE> <xml>" y
# devuelve 0 solo si el crudo es de esta cadena.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/cadenas.sh"

# Imprime la ruta del RAW más reciente del buzón que sea de un satélite moderno
# y tenga al menos MIN_AGE_MIN minutos de antigüedad. Devuelve 1 si no hay.
seleccionar_raw_mas_reciente() {
    local candidato

    while IFS= read -r candidato; do
        if consultar_cadena "$candidato" > /dev/null 2>&1; then
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
START_EPOCH=$(date '+%s')

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
        echo "              (se ignoran los que no son JPSS según $CADENAS_TSV"
        echo "               y los modificados en los"
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

CODIGO_CADENA=0
SAT_INFO=$(consultar_cadena "$INPUT_FILE") || CODIGO_CADENA=$?
case "$CODIGO_CADENA" in
    0) ;;
    1)
        echo "[$TIMESTAMP] ERROR: $FILENAME es de ${SAT_INFO% *}, que no procesa RT-STPS." >&2
        exit 1
        ;;
    *)
        echo "[$TIMESTAMP] ERROR: No se pudo identificar el satélite de: $FILENAME" >&2
        echo "Su cadena no está en $CADENAS_TSV (o el nombre no es chainN-…)." >&2
        exit 1
        ;;
esac

read -r SATELLITE XML_TARGET <<< "$SAT_INFO"

echo "[$TIMESTAMP] Satélite detectado: $SATELLITE"
echo "[$TIMESTAMP] Configuración XML: $XML_TARGET"

# ============================================================================
# ¿YA FUE PROCESADO?
# ============================================================================
# El marcador se escribe únicamente cuando RT-STPS termina con éxito, así que
# una pasada fallida se reintenta sola en la siguiente ejecución.
#
# Y se exige además que sea MÁS NUEVO que el crudo, porque la antena RECICLA los
# nombres: en operación el crudo nuevo sobrescribe al anterior, dando por hecho
# que ése ya se consumió. Con la comprobación por sola existencia, el segundo
# 'chain6-9_pass59' —otro sobrevuelo, mismo nombre— se saltaría en silencio
# contra el marcador del primero, y la pasada se perdería sin que nada lo
# reporte como error. Es el único eslabón expuesto a esto: de RDR en adelante los
# nombres llevan fecha, hora y órbita, y de Level 2 en adelante la clave es
# satélite + fecha + órbita. Ninguno se recicla; el del crudo sí.
#
# Efecto secundario útil en desarrollo: basta sobrescribir el crudo para que se
# reprocese, sin --force.

MARKER="${STATE_DIR}/${FILENAME}.done"

if [ -f "$MARKER" ] && [ "$MARKER" -nt "$INPUT_FILE" ] && [ "$FORCE" -eq 0 ]; then
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

# Referencia para contar únicamente los RDR de esta corrida. No sirve el mtime
# del RAW: si es viejo (o se reprocesa con --force), la cuenta arrastraría los
# RDR de todas las pasadas posteriores.
# Nota: 'find -newer' exige mtime estrictamente mayor y el reloj puede dar el
# mismo sello a dos escrituras inmediatas, así que una corrida instantánea
# contaría 0. No afecta a RT-STPS (tarda minutos) y falla del lado seguro: en
# el peor caso se reintenta, nunca se marca por error como procesado.
REF_FILE="${WORK_DIR}/.inicio"
touch "$REF_FILE"

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

# RT-STPS tarda minutos: de aquí en adelante los mensajes llevan la hora real,
# no la del arranque del script.
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

# Verificar éxito del procesamiento
if [ $APPTAINER_EXIT_CODE -ne 0 ]; then
    echo "[$TIMESTAMP] ERROR: RT-STPS falló (código $APPTAINER_EXIT_CODE)" >&2
    echo "[$TIMESTAMP] Ver log: $LOG_FILE" >&2
    echo "[$TIMESTAMP] No se escribió el marcador: el archivo se reintentará." >&2
    exit 1
fi

# Contar los archivos RDR generados en esta corrida
RDR_COUNT=$(find "$DIR_L0" -name "*.h5" -newer "$REF_FILE" 2>/dev/null | wc -l)

# RT-STPS termina con código 0 aunque el RAW sea basura y no decodifique nada
# (verificado en tahan el 2026-08-12), así que el código de salida por sí solo
# no basta como criterio de éxito.
if [ "$RDR_COUNT" -eq 0 ]; then
    echo "[$TIMESTAMP] ERROR: RT-STPS terminó sin error pero no generó ningún RDR." >&2
    echo "[$TIMESTAMP] El RAW puede estar corrupto o incompleto: $FILENAME" >&2
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
echo "  Duración:      $DURACION"
echo "  Log:           $LOG_FILE"
echo "  Marcador:      $MARKER"
echo "=============================================================================="

exit 0
