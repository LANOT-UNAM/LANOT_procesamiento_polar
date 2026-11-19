#!/bin/bash
# ==============================================================================
# procesar_metop.sh — una pasada de METOP-B/C, del crudo a lo que se publica.
#
# Es el procesar_pasada.sh de la rama METOP, y mucho más corto:
#
#   1. run_metop_l1.sh          crudo → Level 1 (AMSU-A, MHS, AVHRR, IASI)
#   2. run_polar2grid_avhrr.sh  AVHRR → GeoTIFF y vistas
#   3. run_heap_metop.sh        IASI + AMSU-A + MHS → sondeos NUCAPS
#
# El 2 y el 3 corren solo si el 1 dejó marcador, y sobre los archivos que dice
# su manifiesto (<crudo>.l1), no sobre "el más reciente": con dos pasadas
# seguidas, la autoselección podría tomar los de la otra. Van en serie aunque no
# dependan uno del otro: el AVHRR tarda ~20 s y HEAP ~1 min.
#
# Lo invocan recibe.sh (rama metop de config/cadenas.tsv) y barrer_pendientes.sh.
#
# Código de salida: el de run_metop_l1.sh, que es lo que el barrido necesita
# para contar intentos (75 = candado de AAPP tomado, no cuenta). Un fallo del
# render se informa y no cambia el código: el Level 1 ya está y su marcador
# también, como en procesar_pasada.sh una etapa de nivel 2 no deshace el SDR.
#
# Uso:
#   ./procesar_metop.sh <crudo>
#
# Variables de entorno: las de run_metop_l1.sh (METOP_*) y las de
# run_polar2grid_avhrr.sh (AVHRR_*) se heredan tal cual.
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
RUN_L1="${SCRIPT_RUN_METOP_L1:-$SCRIPT_DIR/run_metop_l1.sh}"
RUN_AVHRR="${SCRIPT_RUN_AVHRR:-$SCRIPT_DIR/run_polar2grid_avhrr.sh}"
RUN_HEAP="${SCRIPT_RUN_HEAP_METOP:-$SCRIPT_DIR/run_heap_metop.sh}"
STATE_L1="${METOP_STATE_DIR:-/data/output/metop/state/aapp}"
DIR_L1="${METOP_OUTPUT_DIR:-/data/output/metop/level1}"

if [ -z "${1:-}" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    [ -n "${1:-}" ] && exit 0 || exit 1
fi
CRUDO="$1"
BASE="$(basename "$CRUDO")"

marca() { date '+%Y-%m-%d %H:%M:%S'; }
inicio=$(date +%s)

echo "[$(marca)] === procesar_metop.sh: $BASE ==="

# --- 1. Level 1 ---------------------------------------------------------------
CODIGO_L1=0
"$RUN_L1" "$CRUDO" || CODIGO_L1=$?

MARKER="$STATE_L1/$BASE.done"
MANIFIESTO="$STATE_L1/$BASE.l1"

if [ "$CODIGO_L1" -ne 0 ] || [ ! -f "$MARKER" ]; then
    echo "[$(marca)] Level 1 sin marcador (código $CODIGO_L1): no se sigue."
    exit "$CODIGO_L1"
fi

# --- 2. AVHRR -----------------------------------------------------------------
HRPT=""
[ -f "$MANIFIESTO" ] && HRPT="$(grep -m1 -E '^avhrr/hrpt_M0[13]_.*\.l1b$' "$MANIFIESTO" || true)"

ESTADO_AVHRR="no corrió"
if [ -z "$HRPT" ]; then
    echo "[$(marca)] ⚠ el manifiesto $MANIFIESTO no trae un hrpt: no hay AVHRR que renderizar"
    ESTADO_AVHRR="sin hrpt en el manifiesto"
else
    c=0
    "$RUN_AVHRR" "$DIR_L1/$HRPT" || c=$?
    if [ "$c" -eq 0 ]; then ESTADO_AVHRR="ok"; else ESTADO_AVHRR="FALLÓ (código $c)"; fi
fi

# --- 3. Sondeos ----------------------------------------------------------------
c=0
"$RUN_HEAP" "$BASE" || c=$?
case $c in
    0)  ESTADO_HEAP="ok" ;;
    75) ESTADO_HEAP="pospuesto (candado de HEAP tomado)" ;;
    *)  ESTADO_HEAP="FALLÓ (código $c)" ;;
esac

echo ""
echo "[$(marca)] === $BASE: Level 1 ok · AVHRR $ESTADO_AVHRR · sondeos $ESTADO_HEAP · $(( $(date +%s) - inicio )) s ==="
exit 0
