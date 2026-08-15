#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Podado del caché de ancillary dinámico de CSPP HEAP
# ==============================================================================
#
# Borra del caché de HEAP los directorios de días que ya pasaron de N días.
#
# A diferencia de update_atmos_ancillary.sh, este script NO descarga nada: el
# driver de HEAP baja por su cuenta (con lftp) los pronósticos GFS que le
# falten al arrancar, y run_heap_edr.sh lo deja hacerlo. Lo que HEAP no trae es
# lo contrario: el manual (§1.6.3) dice literalmente que esos datos "no se
# eliminan automáticamente" y que el usuario tiene que purgarlos. De eso se
# encarga esto.
#
# El caché es el de HEAP y solo el de HEAP. Cada software tiene el suyo, y
# apuntar un podador al directorio equivocado se lleva por delante el ancillary
# de otra etapa: por eso aquí hay dos guardas —el nombre tiene que casar el
# patrón de día de §1.6.3, y el caché no puede ser la raíz /data/ancillary—
# y no un rm -rf sobre lo que sea que haya dentro.
#
# La estructura es la que describe §1.6.3: un directorio por día, con la forma
#
#   yyyy_mm_dd_jdy      p. ej. 2026_08_11_223
#
# Cron sugerido (crontab de lanotadm). Semanal basta: el GFS de un día son unos
# pocos GB y el podado es idempotente.
#
#   40 3 * * 0 /opt/lanot/polares/scripts/update_heap_ancillary.sh
#
# Uso:
#   ./update_heap_ancillary.sh              # poda de verdad
#   ./update_heap_ancillary.sh --dry-run    # dice qué borraría, sin borrar
#
# Variables de entorno (para pruebas o rutas alternas):
#   HEAP_CACHE            Caché a podar  (def. /data/ancillary/heap)
#   HEAP_RETENCION_DIAS   Antigüedad     (def. 14)
#   HEAP_LOG_BASE         Raíz de logs   (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

HOST_CACHE="${HEAP_CACHE:-/data/ancillary/heap}"
RETENCION="${HEAP_RETENCION_DIAS:-14}"
LOG_DIR="${HEAP_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "ERROR: Argumento no reconocido: $1" >&2
            exit 1
            ;;
    esac
    shift
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')

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
# GUARDAS
# ==============================================================================
# Antes de borrar nada: que el caché exista y que no sea la raíz compartida.
# /data/ancillary cuelga de sí el caché de SDR (subdirectorios por día con OTRO
# formato), el de ACSPO y el de ATMOS; podar ahí se los llevaría todos.

if [ ! -d "$HOST_CACHE" ]; then
    echo "ERROR: Caché no encontrado: $HOST_CACHE" >&2
    exit 1
fi

CACHE_REAL=$(readlink -f "$HOST_CACHE")

case "$CACHE_REAL" in
    /|/data|/data/ancillary)
        echo "ERROR: $HOST_CACHE apunta a $CACHE_REAL, que es un caché compartido." >&2
        echo "       Este script solo poda el caché propio de HEAP." >&2
        exit 1
        ;;
esac

if ! [[ "$RETENCION" =~ ^[0-9]+$ ]]; then
    echo "ERROR: HEAP_RETENCION_DIAS debe ser un entero, no '$RETENCION'" >&2
    exit 1
fi

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/heap_ancillary_${TIMESTAMP}.log"

echo "=== PODANDO EL CACHÉ DE ANCILLARY DE HEAP: $(date) ===" | tee -a "$LOG_FILE"
echo "  Caché:      $CACHE_REAL"                             | tee -a "$LOG_FILE"
echo "  Retención:  $RETENCION días"                         | tee -a "$LOG_FILE"

ANTES=$(du -sh "$CACHE_REAL" 2>/dev/null | cut -f1)

# ==============================================================================
# PODADO
# ==============================================================================
# El patrón es el de §1.6.3, no un comodín: solo se toca lo que tiene forma de
# directorio de día de HEAP. Cualquier otra cosa que alguien haya dejado ahí
# —notas, un tarball a medio bajar— sobrevive.

mapfile -t CANDIDATOS < <(find "$CACHE_REAL" -mindepth 1 -maxdepth 1 -type d \
                               -name '20[0-9][0-9]_[0-1][0-9]_[0-3][0-9]_[0-3][0-9][0-9]' \
                               -mtime +"$RETENCION" | sort)

BORRADOS=0

if [ "${#CANDIDATOS[@]}" -eq 0 ]; then
    echo "  Nada que podar: ningún día pasa de $RETENCION días." | tee -a "$LOG_FILE"
else
    for d in "${CANDIDATOS[@]}"; do
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  [dry-run] se borraría $(basename "$d") ($(du -sh "$d" | cut -f1))" | tee -a "$LOG_FILE"
        else
            echo "  borrando $(basename "$d") ($(du -sh "$d" | cut -f1))" | tee -a "$LOG_FILE"
            rm -rf "$d"
        fi
        BORRADOS=$((BORRADOS + 1))
    done
fi

DESPUES=$(du -sh "$CACHE_REAL" 2>/dev/null | cut -f1)
DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))
QUEDAN=$(find "$CACHE_REAL" -mindepth 1 -maxdepth 1 -type d \
              -name '20[0-9][0-9]_[0-1][0-9]_[0-3][0-9]_[0-3][0-9][0-9]' | wc -l)

if [ "$DRY_RUN" -eq 1 ]; then
    echo "✅ [dry-run] $BORRADOS días se borrarían; quedan $QUEDAN en total ($DESPUES) en $DURACION" | tee -a "$LOG_FILE"
else
    echo "✅ ÉXITO: $BORRADOS días borrados; quedan $QUEDAN ($ANTES → $DESPUES) en $DURACION" | tee -a "$LOG_FILE"
fi

# Los logs de esta tarea son pequeños pero se acumulan
find "$LOG_DIR" -name "heap_ancillary_*.log" -mtime +30 -delete
