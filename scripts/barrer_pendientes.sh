#!/bin/bash
# ==============================================================================
# barrer_pendientes.sh — recoge los RAW que se quedaron sin procesar.
#
# Para cron, cada 15 minutos:
#   */15 * * * * /opt/lanot/polares/scripts/barrer_pendientes.sh
#
# Existe por dos motivos que se refuerzan:
#
#   1. Los run_*.sh no miran hacia atrás. Si el ancla más reciente ya tiene
#      marcador, salen con 0 sin revisar las anteriores, así que una pasada que
#      falle se queda sin procesar para siempre.
#   2. El candado de procesar_pasada.sh hace que una pasada que llegue mientras
#      hay otra en curso se descarte. No se pierde: la recoge este barrido.
#
# Los RAW se pasan en ORDEN CRONOLÓGICO, porque procesar el más reciente primero
# dejaría al anterior esperando otro ciclo sin ninguna razón.
#
# Un RAW corrupto no se puede reintentar eternamente: RT-STPS termina en 0 con un
# RAW corrupto sin decodificar nada, así que el reintento saldría gratis y sin
# fin. Se cuenta en <raw>.intentos y al llegar a MAX_INTENTOS se escribe
# <raw>.fallido y se deja de intentar. Ese archivo es lo que hay que mirar.
#
# Dos cosas protegen ese contador de subir por razones que no son fallos:
#
#   - El barrido toma SU PROPIO candado, distinto del de la pasada. Un barrido
#     largo —una tanda de RAW atrasados puede durar más que el intervalo de
#     cron— no se solapa consigo mismo.
#   - Si aun así procesar_pasada.sh encuentra tomado el candado de la pasada (porque
#     alguien la lanzó a mano), devuelve 75 y eso NO cuenta como intento. Con
#     salida 0 y sin marcador sería indistinguible de un fallo, y tres choques
#     de candado bastarían para marcar .fallido un RAW bueno.
#
# Variables de entorno:
#   RTSTPS_INPUT_DIR   Buzón de RAW      (def. /datawork/input/polar/raw)
#   RTSTPS_STATE_DIR   Marcadores        (def. /data/output/jpss/state/rt-stps)
#   RTSTPS_MIN_AGE_MIN Edad mínima (min) (def. 1)
#   MAX_INTENTOS       Antes de rendirse (def. 3)
#   BARRIDO_LOCK       Candado propio    (def. /data/tmp/lanot_barrido.lock)
#   SCRIPTS_DIR        De dónde sale procesar_pasada.sh (def. junto a este script)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SCRIPT_DIR}"

INPUT_DIR="${RTSTPS_INPUT_DIR:-/datawork/input/polar/raw}"
STATE_DIR="${RTSTPS_STATE_DIR:-/data/output/jpss/state/rt-stps}"
MIN_AGE_MIN="${RTSTPS_MIN_AGE_MIN:-1}"
MAX_INTENTOS="${MAX_INTENTOS:-3}"
BARRIDO_LOCK="${BARRIDO_LOCK:-/data/tmp/lanot_barrido.lock}"

PROCESAR_PASADA="$SCRIPTS_DIR/procesar_pasada.sh"

# El que devuelve procesar_pasada.sh cuando el candado de la pasada está tomado.
CODIGO_OCUPADO=75

DRY_RUN=0

uso() {
    cat <<EOF
Uso:
  $0              Procesa los RAW pendientes, del más viejo al más nuevo
  $0 --dry-run    Solo dice cuáles recogería

Opciones:
  -n, --dry-run
  -h, --help

Buzón:       $INPUT_DIR
Marcadores:  $STATE_DIR
Reintentos:  $MAX_INTENTOS antes de marcar .fallido
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)    uso; exit 0 ;;
        *)
            echo "ERROR: Argumento no reconocido: $1" >&2
            uso >&2
            exit 1
            ;;
    esac
    shift
done

if [ ! -d "$INPUT_DIR" ]; then
    echo "ERROR: no existe el buzón de RAW: $INPUT_DIR" >&2
    exit 1
fi
if [ ! -x "$PROCESAR_PASADA" ]; then
    echo "ERROR: no está procesar_pasada.sh: $PROCESAR_PASADA" >&2
    exit 1
fi

mkdir -p "$STATE_DIR" 2>/dev/null || true

# Candado propio: un barrido largo no debe solaparse con el siguiente tic de
# cron. Sin esto, dos barridos competirían por el candado de la pasada y el
# perdedor gastaría intentos sin llegar a procesar nada.
if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$BARRIDO_LOCK")" 2>/dev/null || true
    exec 8>"$BARRIDO_LOCK"
    if ! flock -n 8; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ya hay un barrido en curso; nada que hacer."
        exit 0
    fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Barrido de $INPUT_DIR"

pendientes=0
procesados=0
rendidos=0
ocupado=0

# Del más viejo al más nuevo. El filtro de edad es el mismo que usa
# run_rt_stps.sh: un RAW que todavía se está escribiendo no se toca.
while IFS= read -r raw; do
    base="$(basename "$raw")"

    [ ! -f "$STATE_DIR/$base.done" ]    || continue
    [ ! -f "$STATE_DIR/$base.fallido" ] || continue

    pendientes=$((pendientes + 1))

    intentos=0
    [ ! -f "$STATE_DIR/$base.intentos" ] || intentos="$(cat "$STATE_DIR/$base.intentos" 2>/dev/null || echo 0)"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] $base (intentos: $intentos)"
        continue
    fi

    echo "  → $base (intento $((intentos + 1)) de $MAX_INTENTOS)"
    codigo=0
    "$PROCESAR_PASADA" "$raw" || codigo=$?

    # Contención de candado: ni éxito ni fallo. No se cuenta el intento y se
    # corta el barrido, porque lo que viene detrás va a chocar igual.
    if [ "$codigo" -eq "$CODIGO_OCUPADO" ]; then
        echo "    ~ había otra pasada en curso; no cuenta como intento"
        ocupado=1
        break
    fi

    intentos=$((intentos + 1))
    echo "$intentos" > "$STATE_DIR/$base.intentos"

    if [ -f "$STATE_DIR/$base.done" ]; then
        # Salió bien: el contador ya no hace falta.
        rm -f "$STATE_DIR/$base.intentos"
        procesados=$((procesados + 1))
        echo "    ✓ procesado"
        continue
    fi

    echo "    ✗ sigue sin marcador (código $codigo)"
    if [ "$intentos" -ge "$MAX_INTENTOS" ]; then
        {
            echo "rendido:  $(date '+%Y-%m-%d %H:%M:%S')"
            echo "intentos: $intentos"
            echo "codigo:   $codigo del último intento"
            echo "raw:      $raw"
        } > "$STATE_DIR/$base.fallido"
        rendidos=$((rendidos + 1))
        echo "    ⚠ se deja de intentar: $STATE_DIR/$base.fallido"
    fi

done < <(find "$INPUT_DIR" -maxdepth 1 -type f -mmin "+${MIN_AGE_MIN}" \
              -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-)

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pendientes vistos: $pendientes · procesados: $procesados · rendidos: $rendidos"
[ "$ocupado" -eq 0 ] || echo "El barrido se cortó: había una pasada en curso. Se retoma al siguiente tic."

if [ "$rendidos" -gt 0 ]; then
    echo "Hay RAW marcados .fallido en $STATE_DIR; requieren revisión a mano."
    exit 1
fi
exit 0
