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
# Solo toma los crudos que config/cadenas.tsv asigna a esta cadena, y los
# marcadores cuentan solo si son más nuevos que el crudo: la antena recicla los
# nombres, y un chain2-1_pass11 de hoy no es el de hace cinco días.
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
#   MAX_INTENTOS       Antes de rendirse (def. 3; vale para crudos y pasadas)
#   BARRIDO_LOCK       Candado propio    (def. /data/tmp/lanot_barrido.lock)
#   SCRIPTS_DIR        De dónde sale procesar_pasada.sh (def. junto a este script)
#   CADENAS_TSV        Cadena → satélite (def. <scripts>/../config/cadenas.tsv)
#   ESTADO_BASE        Marcadores de las etapas (def. /data/output/jpss/state)
#   REINTENTO_HORAS    Hasta qué antigüedad se retoma una pasada (def. 24)
#   REINTENTO_ESPERA_MIN  Mínimo entre intentos de una pasada (def. 60)
#   REINTENTOS_POR_BARRIDO  Pasadas retomadas por tic (def. 1)
#   METOP_STATE_DIR    Marcadores de la rama METOP (def. /data/output/metop/state/aapp)
#
# SEGUNDA TAREA: retomar pasadas con ATMOS, LSR o CRYO sin marcador. Un crudo
# procesado tiene su .done aunque alguna etapa haya fallado —procesar_pasada.sh
# sigue con las demás—, así que la primera parte nunca vuelve sobre él. El caso
# que lo motivó es de todos los días: una pasada después de las 09 o las 21 UTC
# necesita un ciclo del GFS que se publica media hora después de que llega (ver
# run_atmos_edr.sh), y sin ATMOS caen también LSR y CRYO. Se retoma con
# 'procesar_pasada.sh --clave', que salta lo que ya tiene marcador y vuelve a
# renderizar si algo nuevo salió. Solo las que pasaron ya por la cadena (tienen
# marcador de p2g_l1), con espera entre intentos para dar tiempo a que se
# publique lo que falta, y pocas por tic para no retrasar las pasadas nuevas.
#
# TERCERA TAREA: los crudos de la rama METOP (código 4 de consultar_cadena), con
# las mismas reglas que los de JPSS —orden cronológico, marcador más nuevo que el
# crudo, MAX_INTENTOS y .fallido— pero con procesar_metop.sh (Level 1 y AVHRR) y
# los marcadores del Level 1, en state/aapp. Un AVHRR que falle no se reintenta
# desde aquí, como el render de JPSS. Van después de los de JPSS y no los esperan: AAPP tiene su propio
# candado, y run_metop_l1.sh sale en 75 si está tomado (METOP_ESPERA_MIN=0, para
# que el barrido no se quede una hora esperando).
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
RUN_METOP="$SCRIPTS_DIR/procesar_metop.sh"
STATE_METOP="${METOP_STATE_DIR:-/data/output/metop/state/aapp}"

# Los mismos marcadores que lee procesar_pasada.sh, con las mismas variables.
ESTADO="${ESTADO_BASE:-/data/output/jpss/state}"
DIR_P2G_L1="${L1G_STATE_DIR:-$ESTADO/polar2grid_l1}"
DIR_ATMOS="${ATMOS_STATE_DIR:-$ESTADO/cspp-atmos}"
DIR_LSR="${LSR_STATE_DIR:-$ESTADO/cspp-lsr}"
DIR_CRYO="${CRYO_STATE_DIR:-$ESTADO/cspp-cryo}"
DIR_REINTENTOS="$ESTADO/reintentos"
REINTENTO_HORAS="${REINTENTO_HORAS:-24}"
REINTENTO_ESPERA_MIN="${REINTENTO_ESPERA_MIN:-60}"
REINTENTOS_POR_BARRIDO="${REINTENTOS_POR_BARRIDO:-1}"

# consultar_cadena: qué crudos son de esta cadena (config/cadenas.tsv).
source "$SCRIPT_DIR/cadenas.sh"

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

    # Solo lo que config/cadenas.tsv asigna a la rama JPSS. Sin el filtro, un
    # crudo de Aqua o METOP iría a RT-STPS, que lo rechaza, y a los tres
    # intentos quedaría .fallido: todos los días, por cada pasada ajena. Los de
    # METOP (código 4) tienen su sección abajo.
    consultar_cadena "$raw" > /dev/null 2>&1 || continue

    # La antena RECICLA los nombres, así que un marcador solo vale si es más
    # nuevo que el crudo, como en run_rt_stps.sh. Si el crudo es más nuevo, es
    # otro sobrevuelo: los marcadores del anterior se borran, o un .done viejo
    # lo saltaría y un .fallido bloquearía su ranura para siempre.
    for m in done fallido intentos; do
        if [ -f "$STATE_DIR/$base.$m" ] && [ "$raw" -nt "$STATE_DIR/$base.$m" ]; then
            [ "$DRY_RUN" -eq 1 ] || rm -f "$STATE_DIR/$base.$m"
        fi
    done

    [ ! -f "$STATE_DIR/$base.done" ]    || [ "$raw" -nt "$STATE_DIR/$base.done" ]    || continue
    [ ! -f "$STATE_DIR/$base.fallido" ] || [ "$raw" -nt "$STATE_DIR/$base.fallido" ] || continue

    pendientes=$((pendientes + 1))

    intentos=0
    [ ! -f "$STATE_DIR/$base.intentos" ] || [ "$raw" -nt "$STATE_DIR/$base.intentos" ] || intentos="$(cat "$STATE_DIR/$base.intentos" 2>/dev/null || echo 0)"

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

# ------------------------------------------------------------------------------
# Pasadas a medias: ATMOS, LSR o CRYO sin marcador (ver la cabecera).
# ------------------------------------------------------------------------------

# Minutos desde la última modificación de un archivo.
edad_min() { echo $(( ( $(date +%s) - $(stat -c %Y "$1") ) / 60 )); }

falta_nivel3() {
    [ ! -f "$DIR_ATMOS/$1.done" ] || [ ! -f "$DIR_LSR/$1.done" ] || [ ! -f "$DIR_CRYO/$1.done" ]
}

retomadas=0
[ "$DRY_RUN" -eq 1 ] || mkdir -p "$DIR_REINTENTOS" 2>/dev/null || true

if [ "$ocupado" -eq 0 ] && [ -d "$DIR_P2G_L1" ]; then
    while IFS= read -r m; do
        clave="$(basename "$m" .done)"
        falta_nivel3 "$clave" || continue
        [ ! -f "$DIR_REINTENTOS/$clave.fallido" ] || continue

        # La espera cuenta desde el último intento, o desde que la pasada
        # terminó su primera vuelta si todavía no hubo ninguno.
        ref="$m"
        [ ! -f "$DIR_REINTENTOS/$clave.intentos" ] || ref="$DIR_REINTENTOS/$clave.intentos"
        [ "$(edad_min "$ref")" -ge "$REINTENTO_ESPERA_MIN" ] || continue

        intentos="$(cat "$DIR_REINTENTOS/$clave.intentos" 2>/dev/null || echo 0)"
        faltan=""
        [ -f "$DIR_ATMOS/$clave.done" ] || faltan="$faltan atmos"
        [ -f "$DIR_LSR/$clave.done" ]   || faltan="$faltan lsr"
        [ -f "$DIR_CRYO/$clave.done" ]  || faltan="$faltan cryo"

        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  [dry-run] pasada $clave, falta:$faltan (intentos: $intentos)"
            continue
        fi
        [ "$retomadas" -lt "$REINTENTOS_POR_BARRIDO" ] || break

        echo "  ↻ pasada $clave, falta:$faltan (intento $((intentos + 1)) de $MAX_INTENTOS)"
        codigo=0
        "$PROCESAR_PASADA" --clave "$clave" || codigo=$?

        if [ "$codigo" -eq "$CODIGO_OCUPADO" ]; then
            echo "    ~ había otra pasada en curso; no cuenta como intento"
            break
        fi
        retomadas=$((retomadas + 1))

        if ! falta_nivel3 "$clave"; then
            rm -f "$DIR_REINTENTOS/$clave.intentos"
            echo "    ✓ completa"
            continue
        fi

        intentos=$((intentos + 1))
        echo "$intentos" > "$DIR_REINTENTOS/$clave.intentos"
        echo "    ✗ sigue incompleta (código $codigo)"
        if [ "$intentos" -ge "$MAX_INTENTOS" ]; then
            {
                echo "rendido:  $(date '+%Y-%m-%d %H:%M:%S')"
                echo "intentos: $intentos"
                echo "faltan:  $faltan"
            } > "$DIR_REINTENTOS/$clave.fallido"
            echo "    ⚠ se deja de intentar: $DIR_REINTENTOS/$clave.fallido"
        fi
    done < <(find "$DIR_P2G_L1" -maxdepth 1 -name '*.done' -mmin "-$((REINTENTO_HORAS * 60))" \
                  -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-)
fi
[ "$retomadas" -eq 0 ] || echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pasadas retomadas: $retomadas"

# ------------------------------------------------------------------------------
# Rama METOP (ver la cabecera, tercera tarea).
# ------------------------------------------------------------------------------

es_de_metop() {
    local codigo=0
    consultar_cadena "$1" > /dev/null 2>&1 || codigo=$?
    [ "$codigo" -eq 4 ]
}

m_pendientes=0
m_procesados=0
m_rendidos=0

if [ ! -x "$RUN_METOP" ]; then
    echo "  ⚠ no está procesar_metop.sh ($RUN_METOP): no se barren los crudos de METOP"
else
    [ "$DRY_RUN" -eq 1 ] || mkdir -p "$STATE_METOP" 2>/dev/null || true

    while IFS= read -r raw; do
        es_de_metop "$raw" || continue
        base="$(basename "$raw")"

        for m in done fallido intentos; do
            if [ -f "$STATE_METOP/$base.$m" ] && [ "$raw" -nt "$STATE_METOP/$base.$m" ]; then
                [ "$DRY_RUN" -eq 1 ] || rm -f "$STATE_METOP/$base.$m"
            fi
        done
        [ ! -f "$STATE_METOP/$base.done" ]    || [ "$raw" -nt "$STATE_METOP/$base.done" ]    || continue
        [ ! -f "$STATE_METOP/$base.fallido" ] || [ "$raw" -nt "$STATE_METOP/$base.fallido" ] || continue

        m_pendientes=$((m_pendientes + 1))
        intentos=0
        [ ! -f "$STATE_METOP/$base.intentos" ] || [ "$raw" -nt "$STATE_METOP/$base.intentos" ] || intentos="$(cat "$STATE_METOP/$base.intentos" 2>/dev/null || echo 0)"

        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  [dry-run] METOP $base (intentos: $intentos)"
            continue
        fi

        echo "  → METOP $base (intento $((intentos + 1)) de $MAX_INTENTOS)"
        codigo=0
        METOP_ESPERA_MIN=0 METOP_STATE_DIR="$STATE_METOP" "$RUN_METOP" "$raw" || codigo=$?

        if [ "$codigo" -eq "$CODIGO_OCUPADO" ]; then
            echo "    ~ había otra corrida de AAPP en curso; no cuenta como intento"
            break
        fi

        intentos=$((intentos + 1))
        echo "$intentos" > "$STATE_METOP/$base.intentos"

        if [ -f "$STATE_METOP/$base.done" ] && [ "$STATE_METOP/$base.done" -nt "$raw" ]; then
            rm -f "$STATE_METOP/$base.intentos"
            m_procesados=$((m_procesados + 1))
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
            } > "$STATE_METOP/$base.fallido"
            m_rendidos=$((m_rendidos + 1))
            echo "    ⚠ se deja de intentar: $STATE_METOP/$base.fallido"
        fi
    done < <(find "$INPUT_DIR" -maxdepth 1 -type f -mmin "+${MIN_AGE_MIN}" \
                  -printf '%T@ %p\n' 2>/dev/null | sort -n | cut -d' ' -f2-)

    [ "$m_pendientes" -eq 0 ] || echo "[$(date '+%Y-%m-%d %H:%M:%S')] METOP · pendientes vistos: $m_pendientes · procesados: $m_procesados · rendidos: $m_rendidos"
fi

if [ "$rendidos" -gt 0 ]; then
    echo "Hay RAW marcados .fallido en $STATE_DIR; requieren revisión a mano."
fi
if [ "$m_rendidos" -gt 0 ]; then
    echo "Hay crudos de METOP marcados .fallido en $STATE_METOP; requieren revisión a mano."
fi
[ "$rendidos" -eq 0 ] && [ "$m_rendidos" -eq 0 ] || exit 1
exit 0
