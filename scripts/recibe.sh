#!/bin/bash
################################################################################
# Script: recibe.sh
# Propósito: Despachador de archivos RAW de satélites polares
# Autor: LANOT - UNAM
# Ubicación: ~lanotadm/bin/recibe.sh
#
# Descripción:
#   Este script es llamado automáticamente cuando el sistema de antena recibe
#   un nuevo archivo RAW. Analiza el nombre del archivo para identificar el
#   satélite y lo enruta a la cadena de procesamiento correspondiente:
#
#   - Satélites MODERNOS (NPP, NOAA-20, NOAA-21): Nueva arquitectura con contenedores
#   - Satélites LEGACY (NOAA-15/18/19, METOP): Cadena antigua sin cambios
#
# Uso: 
#   ./recibe.sh <archivo_raw>
#
# Ejemplo:
#   ./recibe.sh /data/raw/chain2-20251216_123045.raw  # -> Contenedores (NPP)
#   ./recibe.sh /data/raw/chain4-20251216_140000.raw  # -> Legacy (NOAA-18)
################################################################################

set -u  # Abortar si hay variables no definidas

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

# Directorio centralizado de logs (según plan de migración sección 1.1)
LOG_DIR="/var/log/lanot/polares/orquestador"
LOG_FILE="${LOG_DIR}/$(date '+%Y%m%d')_recibe.log"

# Scripts de procesamiento
SCRIPT_MODERNO="/home/lanotadm/bin/procesar_cadena_completa.sh"
SCRIPT_NOAA_LEGACY="/home/lanotadm/bin/noaa2"
SCRIPT_METOP_LEGACY="/home/lanotadm/bin/metop2.sh"

# ============================================================================
# VALIDACIÓN DE ENTRADA
# ============================================================================

if [ -z "${1:-}" ]; then
    echo "ERROR: Falta argumento obligatorio" >&2
    echo "Uso: $0 <archivo_raw>" >&2
    exit 1
fi

RAW_FILE="$1"
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

# Verificar que el archivo existe
if [ ! -f "$RAW_FILE" ]; then
    echo "[$TIMESTAMP] ERROR: Archivo no encontrado: $RAW_FILE" | tee -a "$LOG_FILE" >&2
    exit 1
fi

FILENAME=$(basename "$RAW_FILE")
echo "[$TIMESTAMP] RECIBIDO: $FILENAME" >> "$LOG_FILE"

# ============================================================================
# LÓGICA DE ENRUTAMIENTO
# ============================================================================

# ----------------------------------------
# CASO 1: SATÉLITES MODERNOS (Arquitectura con contenedores)
# ----------------------------------------
# Patrones: chain2-* (NPP/Suomi-NPP) o chain6-* (NOAA-20/21, JPSS-1/2)
#
if [[ $FILENAME =~ ^chain[26]- ]]; then
    echo "[$TIMESTAMP] TIPO: Satélite moderno (NPP/JPSS) -> Procesamiento con contenedores" >> "$LOG_FILE"
    
    # Ejecutar orquestador de contenedores en background
    # El operador &> redirige stdout y stderr al log específico
    nohup "$SCRIPT_MODERNO" "$RAW_FILE" \
          &> "${LOG_DIR}/$(date '+%Y%m%d_%H%M%S')_${FILENAME}.log" &
    
    PROCESO_PID=$!
    echo "[$TIMESTAMP] Proceso lanzado: PID=$PROCESO_PID" >> "$LOG_FILE"

# ----------------------------------------
# CASO 2: SATÉLITES LEGACY NOAA (Cadena antigua sin cambios)
# ----------------------------------------
# Patrones: chain4-* (NOAA-15, NOAA-18, NOAA-19)
# Nota: Este flujo se ejecuta vía SSH en servidor remoto tsom03
#
elif [[ $FILENAME =~ ^chain4- ]]; then
    echo "[$TIMESTAMP] TIPO: NOAA Legacy (15/18/19) -> Procesamiento remoto en tsom03" >> "$LOG_FILE"
    
    # Mantener flujo original vía SSH (sin modificaciones)
    ssh tsom03 nohup "$SCRIPT_NOAA_LEGACY" "$RAW_FILE" \
        &> /home/lanotadm/log/${FILENAME}.log &
    
    echo "[$TIMESTAMP] Proceso delegado a tsom03" >> "$LOG_FILE"

# ----------------------------------------
# CASO 3: SATÉLITES METOP (Cadena antigua sin cambios)
# ----------------------------------------
# Patrones: chain5-* (METOP-A, METOP-B, METOP-C)
#
elif [[ $FILENAME =~ ^chain5- ]]; then
    echo "[$TIMESTAMP] TIPO: METOP Legacy -> Procesamiento local (sin contenedores)" >> "$LOG_FILE"
    
    nohup "$SCRIPT_METOP_LEGACY" "$RAW_FILE" \
        &> /home/lanotadm/log/${FILENAME}.log &
    
    PROCESO_PID=$!
    echo "[$TIMESTAMP] Proceso lanzado: PID=$PROCESO_PID" >> "$LOG_FILE"

# ----------------------------------------
# CASO 4: SATÉLITE NO RECONOCIDO
# ----------------------------------------
else
    echo "[$TIMESTAMP] ERROR: Patrón de archivo no reconocido: $FILENAME" | tee -a "$LOG_FILE" >&2
    echo "[$TIMESTAMP] Patrones válidos: chain2-*, chain4-*, chain5-*, chain6-*" >> "$LOG_FILE"
    exit 1
fi

echo "[$TIMESTAMP] Enrutamiento completado para $FILENAME" >> "$LOG_FILE"
exit 0

