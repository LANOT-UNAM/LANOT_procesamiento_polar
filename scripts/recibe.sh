#!/bin/bash
################################################################################
# Script: recibe.sh
# Propósito: Despachador de archivos RAW de satélites polares
# Autor: LANOT - UNAM
# Ubicación: /opt/lanot/polares/scripts/recibe.sh
#
#   La antena invoca una ruta fija, /home/lanotadm/bin/recibe.sh, que es lo
#   único de todo esto que no vive en el repositorio. Se resuelve con un enlace:
#     sudo ln -sf /opt/lanot/polares/scripts/recibe.sh /home/lanotadm/bin/recibe.sh
#
# Descripción:
#   Este script es llamado automáticamente cuando el sistema de antena recibe
#   un nuevo archivo RAW. Analiza el nombre del archivo para identificar el
#   satélite y lo enruta a la cadena de procesamiento correspondiente:
#
#   - Satélites MODERNOS (NPP, NOAA-20, NOAA-21): procesar_pasada.sh, la cadena
#     de contenedores completa
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
LOG_DIR="${ORQ_LOG_BASE:-/var/log/lanot/polares/orquestador}"
LOG_FILE="${LOG_DIR}/$(date '+%Y%m%d')_recibe.log"

# Sin esto, el primer `tee -a` del script fallaba en un servidor recién montado.
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Scripts de procesamiento.
#
# El moderno se resuelve desde la ubicación de ESTE script, no con una ruta fija:
# así el enlace que ve la antena puede apuntar donde sea y la cadena sigue
# encontrándose a sí misma. Los dos legacy sí van con ruta fija, porque viven en
# el servidor viejo y no se tocan.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SCRIPT_MODERNO="${SCRIPT_MODERNO:-$SCRIPT_DIR/procesar_pasada.sh}"
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

# Antes esto se calculaba una vez y se reusaba hasta el mensaje final, así que
# todas las líneas del log salían con la hora de entrada.
marca() { date -u '+%Y-%m-%d %H:%M:%S UTC'; }

# Verificar que el archivo existe
if [ ! -f "$RAW_FILE" ]; then
    echo "[$(marca)] ERROR: Archivo no encontrado: $RAW_FILE" | tee -a "$LOG_FILE" >&2
    exit 1
fi

FILENAME=$(basename "$RAW_FILE")
echo "[$(marca)] RECIBIDO: $FILENAME" >> "$LOG_FILE"

# ============================================================================
# LÓGICA DE ENRUTAMIENTO
# ============================================================================

# ----------------------------------------
# CASO 1: SATÉLITES MODERNOS (Arquitectura con contenedores)
# ----------------------------------------
# Patrones: chain2-* (NPP/Suomi-NPP) o chain6-* (NOAA-20/21, JPSS-1/2)
#
if [[ $FILENAME =~ ^chain[26]- ]]; then
    echo "[$(marca)] TIPO: Satélite moderno (NPP/JPSS) -> Procesamiento con contenedores" >> "$LOG_FILE"
    
    # Ejecutar orquestador de contenedores en background
    # El operador &> redirige stdout y stderr al log específico
    nohup "$SCRIPT_MODERNO" "$RAW_FILE" < /dev/null \
          &> "${LOG_DIR}/$(date '+%Y%m%d_%H%M%S')_${FILENAME}.log" &
    
    PROCESO_PID=$!
    echo "[$(marca)] Proceso lanzado: PID=$PROCESO_PID" >> "$LOG_FILE"

# ----------------------------------------
# CASO 2: SATÉLITES LEGACY NOAA (Cadena antigua sin cambios)
# ----------------------------------------
# Patrones: chain4-* (NOAA-15, NOAA-18, NOAA-19)
# Nota: Este flujo se ejecuta vía SSH en servidor remoto tsom03
#
elif [[ $FILENAME =~ ^chain4- ]]; then
    echo "[$(marca)] TIPO: NOAA Legacy (15/18/19) -> Procesamiento remoto en tsom03" >> "$LOG_FILE"
    
    # Mantener flujo original vía SSH (sin modificaciones)
    ssh tsom03 nohup "$SCRIPT_NOAA_LEGACY" "$RAW_FILE" < /dev/null \
        &> "/home/lanotadm/log/${FILENAME}.log" &
    
    PROCESO_PID=$!
    echo "[$(marca)] Proceso delegado a tsom03: PID=$PROCESO_PID" >> "$LOG_FILE"

# ----------------------------------------
# CASO 3: SATÉLITES METOP (Cadena antigua sin cambios)
# ----------------------------------------
# Patrones: chain5-* (METOP-A, METOP-B, METOP-C)
#
elif [[ $FILENAME =~ ^chain5- ]]; then
    echo "[$(marca)] TIPO: METOP Legacy -> Procesamiento local (sin contenedores)" >> "$LOG_FILE"
    
    nohup "$SCRIPT_METOP_LEGACY" "$RAW_FILE" < /dev/null \
        &> "/home/lanotadm/log/${FILENAME}.log" &
    
    PROCESO_PID=$!
    echo "[$(marca)] Proceso lanzado: PID=$PROCESO_PID" >> "$LOG_FILE"

# ----------------------------------------
# CASO 4: SATÉLITE NO RECONOCIDO
# ----------------------------------------
else
    echo "[$(marca)] ERROR: Patrón de archivo no reconocido: $FILENAME" | tee -a "$LOG_FILE" >&2
    echo "[$(marca)] Patrones válidos: chain2-*, chain4-*, chain5-*, chain6-*" >> "$LOG_FILE"
    exit 1
fi

echo "[$(marca)] Enrutamiento completado para $FILENAME" >> "$LOG_FILE"
exit 0

