#!/bin/bash
################################################################################
# Script: recibe.sh
# Propósito: Despachador de archivos RAW de satélites polares
# Autor: LANOT - UNAM
# Ubicación: /opt/lanot/polares/scripts/recibe.sh
#
#   La recepción lo invoca por ssh en esta ruta, sin enlace en ~lanotadm/bin:
#   /home/lanotadm/bin/recibe.sh es el de la cadena vieja, en stratus
#   (docs/plan_operacion_datawork.md, 0.1 y 0.4).
#
# Descripción:
#   Lo invoca la recepción cuando llega un crudo nuevo. Pregunta a
#   config/cadenas.tsv qué satélite es y:
#
#   - JPSS (NPP, NOAA-20, NOAA-21): lanza procesar_pasada.sh en segundo plano
#   - lo que atiende otro sistema (Aqua, METOP): lo registra y sale en 0. Esos
#     crudos los sigue enrutando el recibe.sh de stratus, que no se toca
#   - una cadena que no esté en la tabla: aviso visible y sale en 0. Puede ser
#     que TeraScan haya reasignado cadenas, como el 2026-09-21
#
# Uso:
#   ./recibe.sh <crudo>
#
#   Con ruta, tal cual. Con el nombre solo —como lo manda la recepción—, se
#   busca en el buzón (RTSTPS_INPUT_DIR, def. /datawork/input/polar/raw).
#
# Ejemplo:
#   ./recibe.sh chain2-1_pass11                     # NOAA-20 -> procesar_pasada.sh
#   ./recibe.sh /datawork/input/polar/raw/chain5-2_pass42   # Aqua -> no es de aquí
################################################################################

set -u  # Abortar si hay variables no definidas

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

# Directorio centralizado de logs (según plan de migración sección 1.1)
LOG_DIR="${CADENA_LOG_BASE:-/var/log/lanot/polares/cadena}"
LOG_FILE="${LOG_DIR}/$(date '+%Y%m%d')_recibe.log"

# Sin esto, el primer `tee -a` del script fallaba en un servidor recién montado.
mkdir -p "$LOG_DIR" 2>/dev/null || true

# El script de la pasada se resuelve desde la ubicación de ESTE script, no con
# una ruta fija: así la cadena se encuentra a sí misma se invoque desde donde se
# invoque.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SCRIPT_MODERNO="${SCRIPT_MODERNO:-$SCRIPT_DIR/procesar_pasada.sh}"
INPUT_DIR="${RTSTPS_INPUT_DIR:-/datawork/input/polar/raw}"

source "$SCRIPT_DIR/cadenas.sh"

# ============================================================================
# VALIDACIÓN DE ENTRADA
# ============================================================================

if [ -z "${1:-}" ]; then
    echo "ERROR: Falta argumento obligatorio" >&2
    echo "Uso: $0 <archivo_raw>" >&2
    exit 1
fi

RAW_FILE="$1"
[[ "$RAW_FILE" == */* ]] || RAW_FILE="$INPUT_DIR/$RAW_FILE"

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
# ENRUTAMIENTO
# ============================================================================

CODIGO_CADENA=0
SAT_INFO="$(consultar_cadena "$RAW_FILE" 2>>"$LOG_FILE")" || CODIGO_CADENA=$?
SATELITE="${SAT_INFO% *}"

case "$CODIGO_CADENA" in
    0)
        echo "[$(marca)] SATÉLITE: $SATELITE -> procesar_pasada.sh" >> "$LOG_FILE"

        # En segundo plano: quien llama no espera a que termine la pasada. La
        # pasada escribe su propio log en este mismo directorio; aquí solo cae
        # lo que salga antes de que lo abra (un error de sintaxis, un script
        # que no está), que de otro modo se perdería sin rastro.
        nohup "$SCRIPT_MODERNO" "$RAW_FILE" < /dev/null >> "$LOG_FILE" 2>&1 &

        echo "[$(marca)] Proceso lanzado: PID=$!" >> "$LOG_FILE"
        ;;
    1)
        echo "[$(marca)] SATÉLITE: $SATELITE -> no es de esta cadena; nada que hacer" >> "$LOG_FILE"
        ;;
    2)
        # Sale en 0: el crudo no es un error de quien llama. Pero que se vea,
        # porque lo más probable es que TeraScan haya reasignado cadenas.
        echo "[$(marca)] AVISO: $FILENAME no está en $CADENAS_TSV; no se procesa." \
             "¿Cambiaron las cadenas de TeraScan? Comparar con lspass." | tee -a "$LOG_FILE" >&2
        ;;
    *)
        echo "[$(marca)] ERROR: no se pudo consultar $CADENAS_TSV" | tee -a "$LOG_FILE" >&2
        exit 1
        ;;
esac

echo "[$(marca)] Enrutamiento completado para $FILENAME" >> "$LOG_FILE"
exit 0
