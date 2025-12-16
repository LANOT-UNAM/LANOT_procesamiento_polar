#!/bin/bash
################################################################################
# Script: procesar_cadena_completa.sh
# Propósito: Orquestador de procesamiento para satélites modernos NPP/JPSS
# Autor: LANOT - UNAM
# Ubicación: ~lanotadm/bin/procesar_cadena_completa.sh
#
# Descripción:
#   Este script coordina la cadena completa de procesamiento de datos de
#   satélites modernos (NPP, NOAA-20, NOAA-21) utilizando tres contenedores
#   especializados de Apptainer:
#
#   PASO 1: RT-STPS v7.0    -> Convierte RAW a Level 0 (RDR files)
#   PASO 2: CSPP SDR v4.1   -> Convierte Level 0 a Level 1 (SDR files)
#   PASO 3: Polar2Grid v3.1 -> Genera imágenes GeoTIFF desde Level 1
#
# Uso:
#   ./procesar_cadena_completa.sh <archivo_raw>
#
# Ejemplo:
#   ./procesar_cadena_completa.sh /data/raw/chain2-20251216_123045.raw
#
# Logs:
#   Cada contenedor genera su propio log en /var/log/lanot/polares/
################################################################################

set -euo pipefail  # Modo estricto: abortar en errores, variables no definidas o fallos en pipelines

# ============================================================================
# CONFIGURACIÓN DEL SISTEMA
# ============================================================================

# --- Contenedores (según plan sección 1.1) ---
CONTAINER_RT_STPS="/opt/containers/rt_stps_7.0.sif"
CONTAINER_CSPP_SDR="/opt/containers/cspp_sdr_v4.1.sif"
CONTAINER_CSPP_NUCAPS="/opt/containers/cspp_nucaps_v1.0.sif" # Placeholder para el nuevo contenedor L2
CONTAINER_POLAR2GRID="/opt/containers/polar2grid_v3.1.sif"

# --- Directorios del sistema anfitrión (host) ---
# Configuraciones de RT-STPS (XMLs de satélites)
HOST_CONFIG_DIR="/data/opt/RT-STPS/rt-stps/config"

# Archivo de segundos intercalares (crítico para RT-STPS)
HOST_LEAPSEC="/data/ancillary/common/leapsec.dat"

# Datos auxiliares (LUTs, coeficientes, etc.)
HOST_ANCILLARY="/data/ancillary"

# --- Directorios de salida ---
DIR_L0="/data/products/level0"              # Archivos RDR (Raw Data Records)
DIR_L1="/data/products/level1"              # Archivos SDR (Sensor Data Records)
DIR_L2="/data/products/level2"              # Archivos de Nivel 2 (NUCAPS, etc.)
DIR_IMAGENES="/data/products/geotiff"       # Imágenes finales en formato GeoTIFF

# --- Directorios de logs (según plan sección 1.1) ---
LOG_BASE="/var/log/lanot/polares"
LOG_RT_STPS="${LOG_BASE}/rt-stps"
LOG_CSPP_SDR="${LOG_BASE}/cspp-sdr"
LOG_CSPP_NUCAPS="${LOG_BASE}/cspp-nucaps"
LOG_POLAR2GRID="${LOG_BASE}/polar2grid"

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

echo "=============================================================================="
echo "[$TIMESTAMP] INICIO PROCESAMIENTO: $FILENAME"
echo "=============================================================================="

# ============================================================================
# DETECCIÓN DE SATÉLITE Y CONFIGURACIÓN
# ============================================================================
# Los archivos RAW contienen identificadores que permiten determinar qué
# satélite generó los datos. Cada satélite requiere un archivo XML específico
# para la configuración de RT-STPS.

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
# PASO 1: RAW → LEVEL 0 (RT-STPS v7.0)
# ============================================================================
# Propósito: Decodificar datos crudos del downlink satelital a formato RDR
# Entrada:  Archivo RAW (binario, protocolo CCSDS)
# Salida:   Archivos HDF5 con datos científicos organizados (RDR - Raw Data Records)
# Duración: ~2-5 minutos

echo ""
echo "------------------------------------------------------------------------------"
echo "[$TIMESTAMP] PASO 1/4: RT-STPS - Decodificación RAW → Level 0"
echo "------------------------------------------------------------------------------"

# Crear directorio temporal para configuración modificada
WORK_DIR=$(mktemp -d -t rt_stps_XXXXXX)
trap "rm -rf $WORK_DIR" EXIT  # Limpieza automática al salir

# Crear directorios de salida si no existen
mkdir -p "$DIR_L0"

# --- Preparar archivo de configuración XML ---
# El XML original contiene rutas hardcodeadas que debemos adaptar para el contenedor
# Copiamos el XML del satélite y modificamos la ruta de salida
cp "$HOST_CONFIG_DIR/$XML_TARGET" "$WORK_DIR/config_temp.xml"
sed -i 's|<dest>.*</dest>|<dest>/output</dest>|g' "$WORK_DIR/config_temp.xml"

echo "[$TIMESTAMP] Ejecutando RT-STPS en contenedor..."
echo "  - Input:  $INPUT_FILE"
echo "  - Output: $DIR_L0"
echo "  - Config: $XML_TARGET"

LOG_FILE_RTSTPS="${LOG_RT_STPS}/${TIMESTAMP_FILE}_${SATELLITE}.log"

# --- Ejecución del contenedor ---
# --bind: Monta directorios del host dentro del contenedor
#   - INPUT_DIR  → /input           (lectura del RAW)
#   - DIR_L0     → /output          (escritura de RDRs)
#   - WORK_DIR   → /config_bind     (configuración temporal)
#   - LEAPSEC    → /opt/rt-stps/... (archivo crítico para timestamps)
apptainer exec \
    --bind "$INPUT_DIR":/input \
    --bind "$DIR_L0":/output \
    --bind "$WORK_DIR":/config_bind \
    --bind "$HOST_LEAPSEC":/opt/rt-stps/leapsec.dat \
    "$CONTAINER_RT_STPS" \
    /bin/bash -c "cd /opt/rt-stps && ./bin/batch.sh /config_bind/config_temp.xml /input/$FILENAME" \
    &> "$LOG_FILE_RTSTPS"

# Verificar éxito del procesamiento
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] ERROR: RT-STPS falló. Revise log: $LOG_FILE_RTSTPS" >&2
    exit 1
fi

# Contar archivos RDR generados
RDR_COUNT=$(find "$DIR_L0" -name "*.h5" -newer "$INPUT_FILE" | wc -l)
echo "[$TIMESTAMP] RT-STPS completado exitosamente. Archivos RDR generados: $RDR_COUNT"
echo "[$TIMESTAMP] Log guardado en: $LOG_FILE_RTSTPS"

# ============================================================================
# PASO 2: LEVEL 0 → LEVEL 1 (CSPP SDR v4.1)
# ============================================================================
# Propósito: Aplicar calibración radiométrica, geolocalización y correcciones
# Entrada:  Archivos RDR (Level 0)
# Salida:   Archivos SDR (Sensor Data Records) - datos calibrados listos para análisis
# Duración: ~5-10 minutos

echo ""
echo "------------------------------------------------------------------------------"
echo "[$TIMESTAMP] PASO 2/4: CSPP SDR - Calibración Level 0 → Level 1"
echo "------------------------------------------------------------------------------"

# Identificar el archivo RDR más reciente (el que acabamos de generar)
# Nota: RT-STPS puede generar múltiples RDRs por pasada, procesamos el principal
LATEST_RDR=$(find "$DIR_L0" -name "*.h5" -newer "$INPUT_FILE" -type f | sort | head -1)

if [ -z "$LATEST_RDR" ]; then
    echo "[$TIMESTAMP] ERROR: No se encontró archivo RDR generado por RT-STPS" >&2
    exit 1
fi

RDR_BASENAME=$(basename "$LATEST_RDR")
mkdir -p "$DIR_L1"

echo "[$TIMESTAMP] Ejecutando CSPP SDR en contenedor..."
echo "  - Input:  $RDR_BASENAME"
echo "  - Output: $DIR_L1"
echo "  - Threads: 12 (ajustar según CPU disponible)"

LOG_FILE_CSPP="${LOG_CSPP_SDR}/${TIMESTAMP_FILE}_${SATELLITE}.log"

# --- Ejecución del contenedor ---
# Opciones de viirs_sdr.sh:
#   -p 12         : Usar 12 hilos paralelos (ajustar según hardware)
#   -a /ancillary : Ruta a datos auxiliares (LUTs, coeficientes)
#   -o /output    : Directorio de salida
apptainer exec \
    --bind "$DIR_L0":/input \
    --bind "$DIR_L1":/output \
    --bind "$HOST_ANCILLARY":/ancillary \
    "$CONTAINER_CSPP_SDR" \
    viirs_sdr.sh -p 12 -a /ancillary -o /output "/input/$RDR_BASENAME" \
    &> "$LOG_FILE_CSPP"

# Verificar éxito del procesamiento
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] ERROR: CSPP SDR falló. Revise log: $LOG_FILE_CSPP" >&2
    exit 1
fi

# Contar archivos SDR generados
SDR_COUNT=$(find "$DIR_L1" -name "SV*.h5" -newer "$LATEST_RDR" | wc -l)
echo "[$TIMESTAMP] CSPP SDR completado exitosamente. Archivos SDR generados: $SDR_COUNT"
echo "[$TIMESTAMP] Log guardado en: $LOG_FILE_CSPP"

# --- PASO 2.1 (Opcional): Procesamiento ATMS SDR ---
# El script antiguo procesaba todos los instrumentos. Aquí replicamos para ATMS.
LATEST_RDR_ATMS=$(find "$DIR_L0" -name "RATMS*.h5" -newer "$INPUT_FILE" -type f | sort | head -1)

if [ -n "$LATEST_RDR_ATMS" ]; then
    echo ""
    echo "------------------------------------------------------------------------------"
    echo "[$TIMESTAMP] PASO 2.1/4: CSPP SDR (ATMS) - Calibración Level 0 → Level 1"
    echo "------------------------------------------------------------------------------"
    
    RDR_BASENAME_ATMS=$(basename "$LATEST_RDR_ATMS")
    LOG_FILE_CSPP_ATMS="${LOG_CSPP_SDR}/${TIMESTAMP_FILE}_${SATELLITE}_ATMS.log"

    echo "[$TIMESTAMP] Ejecutando ATMS SDR en contenedor..."
    echo "  - Input:  $RDR_BASENAME_ATMS"
    echo "  - Output: $DIR_L1"

    apptainer exec \
        --bind "$DIR_L0":/input \
        --bind "$DIR_L1":/output \
        --bind "$HOST_ANCILLARY":/ancillary \
        "$CONTAINER_CSPP_SDR" \
        atms_sdr.sh -p 12 -a /ancillary -o /output "/input/$RDR_BASENAME_ATMS" \
        &> "$LOG_FILE_CSPP_ATMS"

    if [ $? -ne 0 ]; then
        echo "[$TIMESTAMP] ADVERTENCIA: CSPP SDR (ATMS) falló. Revise log: $LOG_FILE_CSPP_ATMS" >&2
        # No salimos con error, consideramos VIIRS como el principal
    else
        SDR_COUNT_ATMS=$(find "$DIR_L1" -name "SATMS*.h5" -newer "$LATEST_RDR_ATMS" | wc -l)
        echo "[$TIMESTAMP] ATMS SDR completado. Archivos generados: $SDR_COUNT_ATMS"
    fi
fi

# --- PASO 2.2 (Opcional): Procesamiento CrIS SDR ---
LATEST_RDR_CRIS=$(find "$DIR_L0" -name "RCRIS*.h5" -newer "$INPUT_FILE" -type f | sort | head -1)

if [ -n "$LATEST_RDR_CRIS" ]; then
    echo ""
    echo "------------------------------------------------------------------------------"
    echo "[$TIMESTAMP] PASO 2.2/4: CSPP SDR (CrIS) - Calibración Level 0 → Level 1"
    echo "------------------------------------------------------------------------------"
    
    RDR_BASENAME_CRIS=$(basename "$LATEST_RDR_CRIS")
    LOG_FILE_CSPP_CRIS="${LOG_CSPP_SDR}/${TIMESTAMP_FILE}_${SATELLITE}_CrIS.log"

    echo "[$TIMESTAMP] Ejecutando CrIS SDR en contenedor..."
    echo "  - Input:  $RDR_BASENAME_CRIS"
    echo "  - Output: $DIR_L1"

    # Las vistas rápidas ahora las genera Polar2Grid en el paso 3.
    apptainer exec \
        --bind "$DIR_L0":/input \
        --bind "$DIR_L1":/output \
        --bind "$HOST_ANCILLARY":/ancillary \
        "$CONTAINER_CSPP_SDR" \
        cris_sdr.sh -p 12 -a /ancillary -o /output "/input/$RDR_BASENAME_CRIS" \
        &> "$LOG_FILE_CSPP_CRIS"

    if [ $? -ne 0 ]; then
        echo "[$TIMESTAMP] ADVERTENCIA: CSPP SDR (CrIS) falló. Revise log: $LOG_FILE_CSPP_CRIS" >&2
    else
        SDR_COUNT_CRIS=$(find "$DIR_L1" -name "SCRIS*.h5" -newer "$LATEST_RDR_CRIS" | wc -l)
        echo "[$TIMESTAMP] CrIS SDR completado. Archivos generados: $SDR_COUNT_CRIS"
    fi
fi

# --- PASO 2.3 (Opcional): Procesamiento OMPS SDR (TC y NP) ---
LATEST_RDR_OMPS_TC=$(find "$DIR_L0" -name "RNSCA-ROTCS*.h5" -newer "$INPUT_FILE" -type f | sort | head -1)
LATEST_RDR_OMPS_NP=$(find "$DIR_L0" -name "RNSCA-RONPS*.h5" -newer "$INPUT_FILE" -type f | sort | head -1)

if [ -n "$LATEST_RDR_OMPS_TC" ] || [ -n "$LATEST_RDR_OMPS_NP" ]; then
    echo ""
    echo "------------------------------------------------------------------------------"
    echo "[$TIMESTAMP] PASO 2.3/4: CSPP SDR (OMPS) - Calibración Level 0 → Level 1"
    echo "------------------------------------------------------------------------------"
    
    LOG_FILE_CSPP_OMPS="${LOG_CSPP_SDR}/${TIMESTAMP_FILE}_${SATELLITE}_OMPS.log"

    # Procesar OMPS Total Column (TC) si existe
    if [ -n "$LATEST_RDR_OMPS_TC" ]; then
        RDR_BASENAME_OMPS_TC=$(basename "$LATEST_RDR_OMPS_TC")
        echo "[$TIMESTAMP] Ejecutando OMPS SDR (Total Column) en contenedor..."
        echo "  - Input:  $RDR_BASENAME_OMPS_TC"
        
        apptainer exec \
            --bind "$DIR_L0":/input --bind "$DIR_L1":/output --bind "$HOST_ANCILLARY":/ancillary \
            "$CONTAINER_CSPP_SDR" \
            omps_sdr.sh -p 12 -a /ancillary -o /output "/input/$RDR_BASENAME_OMPS_TC" \
            &>> "$LOG_FILE_CSPP_OMPS"
        
        if [ $? -eq 0 ]; then
            SDR_COUNT_OMPS_TC=$(find "$DIR_L1" -name "SOMPS-TC*.h5" -newer "$LATEST_RDR_OMPS_TC" | wc -l)
            echo "[$TIMESTAMP] OMPS SDR (TC) completado. Archivos generados: $SDR_COUNT_OMPS_TC"
        else
            echo "[$TIMESTAMP] ADVERTENCIA: CSPP SDR (OMPS TC) falló. Revise log: $LOG_FILE_CSPP_OMPS" >&2
        fi
    fi

    # Procesar OMPS Nadir Profile (NP) si existe
    if [ -n "$LATEST_RDR_OMPS_NP" ]; then
        RDR_BASENAME_OMPS_NP=$(basename "$LATEST_RDR_OMPS_NP")
        echo "[$TIMESTAMP] Ejecutando OMPS SDR (Nadir Profile) en contenedor..."
        echo "  - Input:  $RDR_BASENAME_OMPS_NP"

        apptainer exec \
            --bind "$DIR_L0":/input --bind "$DIR_L1":/output --bind "$HOST_ANCILLARY":/ancillary \
            "$CONTAINER_CSPP_SDR" \
            omps_sdr.sh -p 12 -a /ancillary -o /output "/input/$RDR_BASENAME_OMPS_NP" \
            &>> "$LOG_FILE_CSPP_OMPS"
    fi
fi

# ============================================================================
# PASO 3: LEVEL 1 → LEVEL 2 (Ej: CSPP NUCAPS)
# ============================================================================
# Propósito: Generar productos de nivel superior a partir de los datos SDR
# Entrada:  Archivos SDR de ATMS y CrIS (Level 1)
# Salida:   Archivos NUCAPS-EDR (Environmental Data Records)
# Duración: ~5-15 minutos

echo ""
echo "------------------------------------------------------------------------------"
echo "[$TIMESTAMP] PASO 3/4: CSPP NUCAPS - Generación de productos Level 2"
echo "------------------------------------------------------------------------------"

mkdir -p "$DIR_L2"

# NUCAPS requiere los SDR de ATMS y CrIS. Buscamos los más recientes.
LATEST_SDR_ATMS=$(find "$DIR_L1" -name "SATMS*.h5" -newer "$INPUT_FILE" -type f | sort | head -1)
LATEST_SDR_CRIS=$(find "$DIR_L1" -name "SCRIS*.h5" -newer "$INPUT_FILE" -type f | sort | head -1)

if [ -n "$LATEST_SDR_ATMS" ] && [ -n "$LATEST_SDR_CRIS" ]; then
    LOG_FILE_NUCAPS="${LOG_CSPP_NUCAPS}/${TIMESTAMP_FILE}_${SATELLITE}.log"
    
    echo "[$TIMESTAMP] Ejecutando NUCAPS en contenedor..."
    echo "  - Input ATMS: $(basename $LATEST_SDR_ATMS)"
    echo "  - Input CrIS: $(basename $LATEST_SDR_CRIS)"
    echo "  - Output: $DIR_L2"

    # El script nucaps.sh necesita las rutas a los archivos SDR de ATMS y CrIS
    apptainer exec \
        --bind "$DIR_L1":/input \
        --bind "$DIR_L2":/output \
        --bind "$HOST_ANCILLARY":/ancillary \
        "$CONTAINER_CSPP_NUCAPS" \
        nucaps.sh -o /output --atms-sdr /input/$(basename $LATEST_SDR_ATMS) --cris-sdr /input/$(basename $LATEST_SDR_CRIS) \
        &> "$LOG_FILE_NUCAPS"

    if [ $? -ne 0 ]; then
        echo "[$TIMESTAMP] ADVERTENCIA: CSPP NUCAPS falló. Revise log: $LOG_FILE_NUCAPS" >&2
    else
        L2_COUNT=$(find "$DIR_L2" -name "NUCAPS-EDR*.h5" -newer "$LATEST_SDR_CRIS" | wc -l)
        echo "[$TIMESTAMP] NUCAPS completado. Archivos generados: $L2_COUNT"
        echo "[$TIMESTAMP] Log guardado en: $LOG_FILE_NUCAPS"
    fi
else
    echo "[$TIMESTAMP] ADVERTENCIA: Saltando paso NUCAPS. No se encontraron archivos SDR de ATMS y/o CrIS."
    L2_COUNT=0
fi

# ============================================================================
# PASO 4: LEVEL 1/2 → IMÁGENES (Polar2Grid v3.1)
# ============================================================================
# Propósito: Generar productos visuales georreferenciados
# Entrada:  Archivos SDR (Level 1)
# Salida:   Imágenes GeoTIFF proyectadas (RGB, False Color, etc.)
# Duración: ~3-7 minutos

echo ""
echo "------------------------------------------------------------------------------"
echo "[$TIMESTAMP] PASO 4/4: Polar2Grid - Generación de imágenes GeoTIFF"
echo "------------------------------------------------------------------------------"

mkdir -p "$DIR_IMAGENES"

echo "[$TIMESTAMP] Ejecutando Polar2Grid en contenedor..."
echo "  - Input:  $DIR_L1"
echo "  - Output: $DIR_IMAGENES"
echo "  - Productos: true_color, false_color"

LOG_FILE_P2G="${LOG_POLAR2GRID}/${TIMESTAMP_FILE}_${SATELLITE}.log"

# --- Ejecución del contenedor ---
# Opciones de polar2grid.sh:
#   -r viirs_sdr           : Lector de datos VIIRS SDR
#   -w geotiff             : Escritor en formato GeoTIFF
#   -p true_color false_color : Productos a generar
#   -g wgs84_fit           : Reproyectar a WGS84 ajustado a datos
#   --no-enhance-false-color : Deshabilitar realce automático (mantener valores originales)
#   -f /input/SV*.h5       : Patrón de archivos de entrada
apptainer exec \
    --bind "$DIR_L1":/input \
    --bind "$DIR_IMAGENES":/output \
    "$CONTAINER_POLAR2GRID" \
    polar2grid.sh \
        -r viirs_sdr \
        -w geotiff \
        -p true_color false_color \
        -g wgs84_fit \
        --no-enhance-false-color \
        -f /input/SV*.h5 \
    &> "$LOG_FILE_P2G"

# Verificar éxito del procesamiento
if [ $? -ne 0 ]; then
    echo "[$TIMESTAMP] ERROR: Polar2Grid falló. Revise log: $LOG_FILE_P2G" >&2
    exit 1
fi

# Contar imágenes generadas
GEOTIFF_COUNT=$(find "$DIR_IMAGENES" -name "*.tif" -newer "$LATEST_RDR" | wc -l)
echo "[$TIMESTAMP] Polar2Grid completado exitosamente. Imágenes generadas: $GEOTIFF_COUNT"
echo "[$TIMESTAMP] Log guardado en: $LOG_FILE_P2G"

# ============================================================================
# FINALIZACIÓN
# ============================================================================
TIMESTAMP_END=$(date '+%Y-%m-%d %H:%M:%S')
echo ""
echo "=============================================================================="
echo "[$TIMESTAMP_END] PROCESAMIENTO COMPLETADO EXITOSAMENTE"
echo "=============================================================================="
echo "Archivo procesado: $FILENAME"
echo "Satélite: $SATELLITE"
echo ""
echo "Resultados:"
echo "  - Level 0 (RDR):  $DIR_L0  ($RDR_COUNT archivos)"
echo "  - Level 1 (SDR):  $DIR_L1  ($SDR_COUNT archivos)"
echo "  - Level 2 (L2):   $DIR_L2  ($L2_COUNT archivos)"
echo "  - GeoTIFF:        $DIR_IMAGENES  ($GEOTIFF_COUNT archivos)"
echo ""
echo "Logs disponibles en: $LOG_BASE"
echo "=============================================================================="

exit 0
