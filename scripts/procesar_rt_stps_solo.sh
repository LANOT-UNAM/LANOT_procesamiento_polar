#!/bin/bash
################################################################################
# Script: procesar_rt_stps_solo.sh
# Propósito: Procesamiento con RT-STPS únicamente (RAW → Level 0)
# Autor: LANOT - UNAM
#
# Descripción:
#   Script simplificado que ejecuta únicamente el primer paso de la cadena:
#   conversión de archivos RAW a Level 0 (RDR) usando el contenedor RT-STPS v7.0
#
# Uso:
#   ./procesar_rt_stps_solo.sh <archivo_raw>
#
# Ejemplo:
#   ./procesar_rt_stps_solo.sh /datawork/input/polar/raw/chain2-20251216_123045.raw
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

# Directorio de salida
DIR_L0="/data/output/level0"

# Directorio de logs
LOG_BASE="/var/log/lanot/polares"
LOG_RT_STPS="${LOG_BASE}/rt-stps"

# ============================================================================
# VALIDACIÓN DE ENTRADA
# ============================================================================

if [ -z "${1:-}" ]; then
    echo "ERROR: Falta argumento obligatorio" >&2
    echo "Uso: $0 <archivo_raw>" >&2
    exit 1
fi

INPUT_FILE=$(realpath "$1")
INPUT_DIR=$(dirname "$INPUT_FILE")
FILENAME=$(basename "$INPUT_FILE")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP_FILE=$(date '+%Y%m%d_%H%M%S')

# Verificar que el archivo existe
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Archivo no encontrado: $INPUT_FILE" >&2
    exit 1
fi

# Verificar que el contenedor existe
if [ ! -f "$CONTAINER_RT_STPS" ]; then
    echo "ERROR: Contenedor no encontrado: $CONTAINER_RT_STPS" >&2
    exit 1
fi

echo "=============================================================================="
echo "[$TIMESTAMP] PROCESAMIENTO RT-STPS: $FILENAME"
echo "=============================================================================="

# ============================================================================
# DETECCIÓN DE SATÉLITE
# ============================================================================

if [[ "$FILENAME" =~ chain2 ]] || [[ "$FILENAME" =~ npp ]]; then
    SATELLITE="NPP"
    XML_TARGET="npp.xml"
    echo "[$TIMESTAMP] Satélite detectado: Suomi-NPP"
    
elif [[ "$FILENAME" =~ chain6 ]] || [[ "$FILENAME" =~ j01 ]] || [[ "$FILENAME" =~ noaa20 ]]; then
    SATELLITE="NOAA-20"
    XML_TARGET="jpss1.xml"
    echo "[$TIMESTAMP] Satélite detectado: NOAA-20 (JPSS-1)"
    
elif [[ "$FILENAME" =~ j02 ]] || [[ "$FILENAME" =~ noaa21 ]]; then
    SATELLITE="NOAA-21"
    XML_TARGET="jpss2.xml"
    echo "[$TIMESTAMP] Satélite detectado: NOAA-21 (JPSS-2)"
    
else
    echo "[$TIMESTAMP] ERROR: No se pudo identificar el satélite desde el nombre: $FILENAME" >&2
    echo "Patrones esperados: chain2/npp, chain6/j01/noaa20, j02/noaa21" >&2
    exit 1
fi

echo "[$TIMESTAMP] Configuración XML: $XML_TARGET"

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
if [ ! -f "$HOST_CONFIG_DIR/$XML_TARGET" ]; then
    echo "ERROR: No se encontró el archivo de configuración: $HOST_CONFIG_DIR/$XML_TARGET" >&2
    exit 1
fi

cp "$HOST_CONFIG_DIR/$XML_TARGET" "$WORK_DIR/config_temp.xml"

# Reemplazar todas las referencias a directorios de datos con /output
sed -i 's|<dest>.*</dest>|<dest>/output</dest>|g' "$WORK_DIR/config_temp.xml"
sed -i 's|<outputPath>.*</outputPath>|<outputPath>/output</outputPath>|g' "$WORK_DIR/config_temp.xml"
sed -i 's|<directory>.*</directory>|<directory>/output</directory>|g' "$WORK_DIR/config_temp.xml"
# Reemplazar cualquier referencia a ../data o rutas absolutas
sed -i 's|\.\./data|/output|g' "$WORK_DIR/config_temp.xml"
sed -i 's|/opt/rt-stps/data|/output|g' "$WORK_DIR/config_temp.xml"

echo "[$TIMESTAMP] Ejecutando RT-STPS en contenedor..."
echo "  - Input:  $INPUT_FILE"
echo "  - Output: $DIR_L0"
echo "  - Config: $XML_TARGET"

LOG_FILE="${LOG_RT_STPS}/${TIMESTAMP_FILE}_${SATELLITE}.log"

# --- Ejecución del contenedor ---
# Monta directorios del host dentro del contenedor:
#   - INPUT_DIR  → /input           (lectura del RAW)
#   - DIR_L0     → /output          (escritura de RDRs)
#   - WORK_DIR   → /config_bind     (configuración temporal)
#   - LEAPSEC    → /opt/rt-stps/... (segundos intercalares)

echo ""
echo "Comando a ejecutar:"
echo "  apptainer exec \\"
echo "    --bind $INPUT_DIR:/input \\"
echo "    --bind $DIR_L0:/output \\"
echo "    --bind $WORK_DIR:/config_bind \\"
echo "    --bind $HOST_LEAPSEC:/opt/rt-stps/leapsec.dat \\"
echo "    $CONTAINER_RT_STPS \\"
echo "    /bin/bash -c 'cd /opt/rt-stps && ./bin/batch.sh /config_bind/config_temp.xml /input/$FILENAME'"
echo ""

# Ejecutar y capturar salida tanto en pantalla como en log
apptainer exec \
    --bind "$INPUT_DIR":/input \
    --bind "$DIR_L0":/output \
    --bind "$WORK_DIR":/config_bind \
    --bind "$HOST_LEAPSEC":/opt/rt-stps/leapsec.dat \
    "$CONTAINER_RT_STPS" \
    /bin/bash -c "cd /opt/rt-stps && ./bin/batch.sh /config_bind/config_temp.xml /input/$FILENAME" \
    2>&1 | tee "$LOG_FILE"

# Capturar el código de salida del pipeline
APPTAINER_EXIT_CODE=${PIPESTATUS[0]}

# Verificar éxito del procesamiento
if [ $APPTAINER_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "[$TIMESTAMP] ERROR: RT-STPS falló con código $APPTAINER_EXIT_CODE" >&2
    echo "[$TIMESTAMP] Revise log: $LOG_FILE" >&2
    exit 1
fi

echo ""
echo "[$TIMESTAMP] RT-STPS completado exitosamente"

# Contar archivos RDR generados
RDR_COUNT=$(find "$DIR_L0" -name "*.h5" -newer "$INPUT_FILE" 2>/dev/null | wc -l)

echo ""
echo "=============================================================================="
echo "[$TIMESTAMP] PROCESAMIENTO COMPLETADO EXITOSAMENTE"
echo "=============================================================================="
echo "  Satélite:         $SATELLITE"
echo "  Archivos RDR:     $RDR_COUNT"
echo "  Directorio L0:    $DIR_L0"
echo "  Log:              $LOG_FILE"
echo "=============================================================================="

# Listar archivos generados
if [ $RDR_COUNT -gt 0 ]; then
    echo ""
    echo "Archivos RDR generados:"
    find "$DIR_L0" -name "*.h5" -newer "$INPUT_FILE" -exec basename {} \;
fi

exit 0
