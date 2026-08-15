#!/bin/bash
# ==============================================================================
# procesar_pasada.sh — encadena los once run_*.sh de una pasada.
#
# Hasta ahora el encadenamiento era un humano: ningún run_*.sh invoca a otro y
# las dependencias solo existían como mensajes de error dirigidos al operador.
# Esto es esa pieza.
#
#   ./procesar_pasada.sh <raw>              desde el RAW de la antena
#   ./procesar_pasada.sh --clave <clave>    reprocesa una pasada ya ingerida
#   ./procesar_pasada.sh --dry-run <raw>    imprime el grafo, no ejecuta nada
#
# El grafo, con barreras entre niveles y hasta tres etapas a la vez:
#
#   RT-STPS(raw)
#     └─ nivel 1: SDR de cada RDR que RT-STPS haya producido
#          ├─ nivel 2: ATMOS · ACSPO · FIRE · FLOOD · OMPS · P2G_L1
#          │     └─ nivel 3: LSR · CRYO            (necesitan ATMOS)
#          │          └─ nivel 4: P2G_EDR          (rinde todo lo anterior)
#
# Tres a la vez y no cinco: tahan tiene 64 CPU y los hilos que ya pide cada
# script suman ~48 con tres simultáneas; con cinco pedirían ~72 y pelearían.
#
# UN FALLO NO DETIENE LA CADENA. LSR falla en toda pasada nocturna —no hay
# reflectancia de superficie sin sol— y eso no puede detener a las demás. Cada
# etapa se invoca con `|| codigo=$?`, que es la forma correcta bajo set -e.
#
# Variables de entorno: las de los once run_*.sh se respetan tal cual, y este
# script lee las mismas *_STATE_DIR para poder leer los marcadores.
#   MAX_PARALELO   Etapas simultáneas por nivel (def. 3)
#   LOCK_FILE      Candado global (def. /data/tmp/lanot_polares.lock)
#   ORQ_LOG_BASE   Logs (def. /var/log/lanot/polares/orquestador)
#   SCRIPTS_DIR    De dónde salen los run_*.sh (def. junto a este script)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SCRIPT_DIR}"

MAX_PARALELO="${MAX_PARALELO:-3}"
LOCK_FILE="${LOCK_FILE:-/data/tmp/lanot_polares.lock}"
ORQ_LOG_BASE="${ORQ_LOG_BASE:-/var/log/lanot/polares/orquestador}"

ESTADO="${ESTADO_BASE:-/data/output/jpss/state}"
LEVEL0="${RTSTPS_OUTPUT_DIR:-/data/output/jpss/level0}"
LEVEL1_VIIRS="${SDR_LEVEL1_VIIRS:-${SDR_OUTPUT_BASE:-/data/output/jpss/level1}/viirs}"

# Marcadores: cada etapa escribe el suyo, y de ahí sale el resumen. Se leen las
# mismas variables que usan los run_*.sh para que un ambiente de prueba que las
# redefina siga siendo coherente.
DIR_RTSTPS="${RTSTPS_STATE_DIR:-$ESTADO/rt-stps}"
DIR_SDR="${SDR_STATE_DIR:-$ESTADO/cspp-sdr}"
DIR_ATMOS="${ATMOS_STATE_DIR:-$ESTADO/cspp-atmos}"
DIR_ACSPO="${ACSPO_STATE_DIR:-$ESTADO/cspp-acspo}"
DIR_FIRE="${FIRE_STATE_DIR:-$ESTADO/cspp-active-fire}"
DIR_FLOOD="${FLOOD_STATE_DIR:-$ESTADO/cspp-flood}"
DIR_OMPS="${OMPS_STATE_DIR:-$ESTADO/cspp-omps}"
DIR_LSR="${LSR_STATE_DIR:-$ESTADO/cspp-lsr}"
DIR_CRYO="${CRYO_STATE_DIR:-$ESTADO/cspp-cryo}"
DIR_P2G_L1="${L1G_STATE_DIR:-$ESTADO/polar2grid_l1}"
DIR_P2G_EDR="${P2G_STATE_DIR:-$ESTADO/polar2grid}"

FORCE=0
DRY_RUN=0
CLAVE_PEDIDA=""
RAW=""

# Resultados, para el resumen final. Índices paralelos.
RES_ETAPA=()
RES_CODIGO=()
RES_MARCADOR=()

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0 <raw>                 Cadena completa desde un RAW de la antena
  $0 --clave <clave>       Reprocesa una pasada ya ingerida (desde Level 2)
  $0 --dry-run <raw>       Imprime el grafo y los comandos, sin ejecutar

Opciones:
  -c, --clave <clave>   Pasada concreta: j01_d20260814_b45273
  -f, --force           Se propaga a todas las etapas
  -n, --dry-run
  -h, --help

Con --clave se salta RT-STPS y SDR: la pasada ya está en Level 1. Es la forma
de rehacer Level 2 y los renderizados sin volver a decodificar.
EOF
}

ahora() { date '+%Y-%m-%d %H:%M:%S'; }

titulo() {
    echo ""
    echo "=============================================================================="
    echo "  $*"
    echo "=============================================================================="
}

# GMTCO_j01_d20260814_t0923110_..._b45273_... -> j01_d20260814_b45273
clave_de_pasada() {
    local n="$1" sat fecha orbita
    sat="$(echo    "$n" | grep -oE '_(npp|j01|j02)_'   | head -1 | tr -d _)"
    fecha="$(echo  "$n" | grep -oE '_d[0-9]{8}_'       | head -1 | tr -d _)"
    orbita="$(echo "$n" | grep -oE '_b[0-9]{5,6}_'     | head -1 | tr -d _)"
    [ -n "$sat" ] && [ -n "$fecha" ] && [ -n "$orbita" ] || return 1
    echo "${sat}_${fecha}_${orbita}"
}

# La clave de OMPS no puede ser la de VIIRS: el mismo sobrevuelo lleva otra
# órbita según el instrumento (b45236 en VIIRS, b45237 en OMPS). Se le pasa la
# clave truncada, que el -p de los run_*.sh resuelve contra las pasadas que de
# verdad estén en su directorio.
clave_truncada() {
    echo "${1%_b*}"
}

# Igual que detectar_sensor de run_sdr.sh:145-149. Está duplicado a propósito:
# la alternativa es llamar a run_sdr.sh y no poder distinguir "esto no es un RDR
# de ciencia" de "esto falló". RNSCA a secas es el spacecraft diary, no un
# sensor, y aparece en el mismo directorio.
clave_sensor() {
    case "$1" in
        *RVIIRS*|*RVIRS*) echo viirs   ;;
        *RATMS*)          echo atms    ;;
        *RCRIS*)          echo cris    ;;
        *ROTCS*)          echo omps_nm ;;
        *RONPS*)          echo omps_np ;;
        *)                return 1     ;;
    esac
}

# ------------------------------------------------------------------ ejecución
#
# Una tarea es una cadena con campos separados por tabulador:
#   etiqueta <TAB> marcador <TAB> script <TAB> arg...
# El marcador se mira antes y después para distinguir "corrió y produjo" de "ya
# estaba hecho", que por código de salida son indistinguibles: los once
# devuelven 0 en los dos casos.

correr_tarea() {
    local tarea="$1" salida="$2"
    local etiqueta marcador script
    local -a campos args

    IFS=$'\t' read -r -a campos <<< "$tarea"
    etiqueta="${campos[0]}"
    marcador="${campos[1]}"
    script="${campos[2]}"
    args=("${campos[@]:3}")

    {
        echo "--- $etiqueta: $(basename "$script") ${args[*]}"
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "    [dry-run] $script ${args[*]}"
            echo "    [dry-run] marcador: $marcador"
            exit 0
        fi
        "$script" "${args[@]}"
    } > "$salida" 2>&1
}

# Lanza un nivel entero en tandas de MAX_PARALELO y espera a que termine.
# La salida de cada etapa va a su propio archivo y se imprime junta al final de
# la tanda: intercalada no se podría leer.
ejecutar_nivel() {
    local nombre_nivel="$1"; shift
    local -a tareas=("$@")
    local -a pids=() etiquetas=() salidas=() marcadores=()
    local tarea etiqueta marcador salida pid codigo i

    [ "${#tareas[@]}" -gt 0 ] || return 0

    titulo "$nombre_nivel  (${#tareas[@]} etapa(s), hasta $MAX_PARALELO a la vez)"

    for tarea in "${tareas[@]}"; do
        etiqueta="$(echo "$tarea" | cut -f1)"
        marcador="$(echo "$tarea" | cut -f2)"
        salida="$TRABAJO/$etiqueta.log"

        # Sello del marcador ANTES, para saber después si esta corrida lo tocó.
        if [ -f "$marcador" ]; then
            marcadores+=("$(stat -c %Y "$marcador" 2>/dev/null || echo 0)")
        else
            marcadores+=("0")
        fi

        correr_tarea "$tarea" "$salida" &
        pids+=("$!")
        etiquetas+=("$etiqueta")
        salidas+=("$salida")
        echo "  → lanzada: $etiqueta"

        if [ "${#pids[@]}" -ge "$MAX_PARALELO" ]; then
            cosechar_tanda
        fi
    done

    cosechar_tanda
}

# Espera la tanda en curso, imprime su salida y anota los resultados.
cosechar_tanda() {
    local i pid codigo etiqueta salida marcador sello_antes sello_ahora

    for i in "${!pids[@]}"; do
        pid="${pids[$i]}"
        etiqueta="${etiquetas[$i]}"
        salida="${salidas[$i]}"
        sello_antes="${marcadores[$i]}"

        codigo=0
        wait "$pid" || codigo=$?

        echo ""
        echo "······ $etiqueta (código $codigo) ······"
        [ ! -f "$salida" ] || cat "$salida"

        RES_ETAPA+=("$etiqueta")
        RES_CODIGO+=("$codigo")

        marcador="$(marcador_de "$etiqueta")"
        sello_ahora=0
        [ ! -f "$marcador" ] || sello_ahora="$(stat -c %Y "$marcador" 2>/dev/null || echo 0)"
        if [ "$DRY_RUN" -eq 1 ]; then
            RES_MARCADOR+=("dry-run")
        elif [ "$sello_ahora" -gt "$sello_antes" ]; then
            RES_MARCADOR+=("$marcador")
        else
            RES_MARCADOR+=("sin-cambio")
        fi
    done

    pids=(); etiquetas=(); salidas=(); marcadores=()
}

# El marcador de una etiqueta, para releerlo al cosechar.
marcador_de() {
    case "$1" in
        rt_stps)  echo "$DIR_RTSTPS/$(basename "$RAW").done" ;;
        sdr_*)    echo "$DIR_SDR/${1#sdr_}.done"             ;;
        atmos)    echo "$DIR_ATMOS/$CLAVE.done"              ;;
        acspo)    echo "$DIR_ACSPO/$CLAVE.done"              ;;
        fire)     echo "$DIR_FIRE/$CLAVE.done"               ;;
        flood)    echo "$DIR_FLOOD/$CLAVE.done"              ;;
        omps)     echo "$DIR_OMPS/$CLAVE_OMPS.done"          ;;
        lsr)      echo "$DIR_LSR/$CLAVE.done"                ;;
        cryo)     echo "$DIR_CRYO/$CLAVE.done"               ;;
        p2g_l1)   echo "$DIR_P2G_L1/$CLAVE.done"             ;;
        p2g_edr)  echo "$DIR_P2G_EDR/$CLAVE.done"            ;;
        *)        echo ""                                    ;;
    esac
}

# Del marcador salen la duración y los conteos, sin tener que tocar los once
# scripts. Las claves varían entre ellos, así que se toma todo lo que no sea
# metadato: 'atmos: 7  lsr: 3' o 'productos: 110'.
resumen_de_marcador() {
    local m="$1" linea clave valor conteos=""
    [ -f "$m" ] || return 0
    while IFS= read -r linea; do
        clave="${linea%%:*}"
        valor="$(echo "${linea#*:}" | sed 's/^ *//')"
        case "$clave" in
            procesado|renderizado|pasada|salida|log|duracion|satelite|sensor) ;;
            *) conteos="$conteos $clave=$valor" ;;
        esac
    done < "$m"
    echo "${conteos# }"
}

duracion_de_marcador() {
    [ -f "$1" ] || return 0
    grep -m1 '^duracion:' "$1" 2>/dev/null | sed 's/^duracion: *//'
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)   FORCE=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)    uso; exit 0 ;;
        -c|--clave)
            if [ $# -lt 2 ]; then
                echo "ERROR: --clave necesita un valor" >&2
                exit 1
            fi
            CLAVE_PEDIDA="$2"
            shift
            ;;
        -*)
            echo "ERROR: Opción desconocida: $1" >&2
            uso >&2
            exit 1
            ;;
        *)
            if [ -n "$RAW" ]; then
                echo "ERROR: Solo se acepta un RAW; sobra: $1" >&2
                exit 1
            fi
            RAW="$1"
            ;;
    esac
    shift
done

if [ -z "$RAW" ] && [ -z "$CLAVE_PEDIDA" ]; then
    echo "ERROR: hace falta un RAW o --clave." >&2
    uso >&2
    exit 1
fi
if [ -n "$RAW" ] && [ -n "$CLAVE_PEDIDA" ]; then
    echo "ERROR: --clave y un RAW son excluyentes." >&2
    exit 1
fi

# Arma la cadena de una tarea. --force se añade solo si toca: un
# "${OPT[@]:-}" con el array vacío mete un campo vacío, y ese campo llega al
# run_*.sh como un argumento de más que rechaza por no reconocido.
armar_tarea() {
    local etiqueta="$1" marcador="$2" script="$3"; shift 3
    local s
    s="$(printf '%s\t%s\t%s' "$etiqueta" "$marcador" "$script")"
    local a
    for a in "$@"; do
        s="$s$(printf '\t%s' "$a")"
    done
    [ "$FORCE" -eq 0 ] || s="$s$(printf '\t--force')"
    printf '%s' "$s"
}

# ==============================================================================
# CANDADO
#
# Una pasada a la vez. Si hay otra corriendo, esta se deja pendiente y el barrido
# la recoge.
#
# Sale con 75 (EX_TEMPFAIL), no con 0. No es un fallo, pero tampoco es éxito, y
# la diferencia importa: barrer_pendientes.sh cuenta intentos y se rinde al
# tercero. Con salida 0 y sin marcador, "había otra pasada en curso" sería
# indistinguible de "falló", y bastarían tres choques de candado para marcar
# .fallido un RAW perfectamente bueno.
# ==============================================================================

CODIGO_OCUPADO=75

if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        echo "ℹ  Hay otra pasada en curso (candado: $LOCK_FILE)."
        echo "   Esta queda pendiente; la recoge barrer_pendientes.sh."
        exit "$CODIGO_OCUPADO"
    fi
fi

# ==============================================================================
# PREPARACIÓN
# ==============================================================================

INICIO=$(date +%s)
SELLO=$(date '+%Y%m%d_%H%M%S')
TRABAJO="$(mktemp -d "${TMPDIR:-/tmp}/orquestador_${SELLO}_XXXX")"
trap 'rm -rf "$TRABAJO"' EXIT

mkdir -p "$ORQ_LOG_BASE" 2>/dev/null || true
ETIQUETA_LOG="${CLAVE_PEDIDA:-$(basename "${RAW:-sin_raw}")}"
LOG="$ORQ_LOG_BASE/${SELLO}_${ETIQUETA_LOG}.log"

# Todo lo que sigue va a la vez a la terminal y al log. Si el directorio de log
# no se puede escribir se sigue sin log, que es preferible a no procesar.
if : > "$LOG" 2>/dev/null; then
    exec > >(tee -a "$LOG") 2>&1
else
    LOG="(sin log: no se pudo escribir en $ORQ_LOG_BASE)"
fi

titulo "CADENA POLAR | $(ahora)"
echo "  Entrada:  ${RAW:-(pasada $CLAVE_PEDIDA)}"
echo "  Scripts:  $SCRIPTS_DIR"
echo "  Log:      $LOG"
[ "$DRY_RUN" -eq 0 ] || echo "  MODO DRY-RUN: no se ejecuta nada"

MARCA="$TRABAJO/marca"
touch "$MARCA"

CLAVE=""
CLAVE_OMPS=""

# ==============================================================================
# RT-STPS Y SDR  (solo si se entró por un RAW)
# ==============================================================================

if [ -n "$RAW" ]; then
    ejecutar_nivel "RT-STPS" \
        "$(armar_tarea rt_stps "$DIR_RTSTPS/$(basename "$RAW").done" \
                       "$SCRIPTS_DIR/run_rt_stps.sh" "$RAW")"

    # Los RDR que acaba de producir. Se nombran explícitamente en vez de dejar
    # que run_sdr.sh autoseleccione: su filtro de edad mínima (1 min) haría que
    # no viera nada recién salido de RT-STPS y saliera en 0 sin hacer nada.
    TAREAS_SDR=()
    if [ "$DRY_RUN" -eq 1 ]; then
        echo ""
        echo "  [dry-run] aquí se buscarían los RDR nuevos en $LEVEL0"
        TAREAS_SDR=("$(armar_tarea sdr_EJEMPLO.h5 "$DIR_SDR/EJEMPLO.h5.done" \
                                   "$SCRIPTS_DIR/run_sdr.sh" "$LEVEL0/EJEMPLO.h5")")
    else
        while IFS= read -r rdr; do
            base="$(basename "$rdr")"
            clave_sensor "$base" >/dev/null || continue
            TAREAS_SDR+=("$(armar_tarea "sdr_$base" "$DIR_SDR/$base.done" \
                                        "$SCRIPTS_DIR/run_sdr.sh" "$rdr")")
        done < <(find "$LEVEL0" -maxdepth 1 -type f -name '*.h5' -newer "$MARCA" 2>/dev/null | sort)
    fi

    if [ "${#TAREAS_SDR[@]}" -eq 0 ]; then
        echo ""
        echo "⚠  RT-STPS no dejó ningún RDR de ciencia nuevo en $LEVEL0."
        echo "   La cadena no puede seguir. Revisa $LOG."
        exit 1
    fi

    ejecutar_nivel "Nivel 1 — SDR" "${TAREAS_SDR[@]}"
fi

# ==============================================================================
# LA CLAVE DE LA PASADA
# ==============================================================================

if [ -n "$CLAVE_PEDIDA" ]; then
    CLAVE="$CLAVE_PEDIDA"
elif [ "$DRY_RUN" -eq 1 ]; then
    CLAVE="j01_dAAAAMMDD_bNNNNN"
else
    ANCLA="$(find "$LEVEL1_VIIRS" -maxdepth 1 -type f -name 'GMTCO*.h5' -newer "$MARCA" 2>/dev/null | sort | head -1)"
    if [ -z "$ANCLA" ]; then
        echo ""
        echo "⚠  El SDR de VIIRS no dejó ningún GMTCO nuevo en $LEVEL1_VIIRS."
        echo "   Sin clave de pasada no se puede seguir a Level 2."
        exit 1
    fi
    if ! CLAVE="$(clave_de_pasada "$(basename "$ANCLA")")"; then
        echo "⚠  No se pudo derivar la clave de: $(basename "$ANCLA")" >&2
        exit 1
    fi
fi

CLAVE_OMPS="$(clave_truncada "$CLAVE")"

echo ""
echo "  Pasada:      $CLAVE"
echo "  Clave OMPS:  $CLAVE_OMPS  (otra órbita para el mismo sobrevuelo)"

# ==============================================================================
# NIVELES 2, 3 Y 4
# ==============================================================================

tarea() {
    # etiqueta, marcador, script, clave
    armar_tarea "$1" "$2" "$SCRIPTS_DIR/$3" -p "$4"
}

ejecutar_nivel "Nivel 2 — Level 2 y renderizado de Level 1" \
    "$(tarea atmos  "$DIR_ATMOS/$CLAVE.done"       run_atmos_edr.sh       "$CLAVE")" \
    "$(tarea acspo  "$DIR_ACSPO/$CLAVE.done"       run_acspo_edr.sh       "$CLAVE")" \
    "$(tarea fire   "$DIR_FIRE/$CLAVE.done"        run_active_fire_edr.sh "$CLAVE")" \
    "$(tarea flood  "$DIR_FLOOD/$CLAVE.done"       run_flood_edr.sh       "$CLAVE")" \
    "$(tarea omps   "$DIR_OMPS/$CLAVE_OMPS.done"   run_omps_edr.sh        "$CLAVE_OMPS")" \
    "$(tarea p2g_l1 "$DIR_P2G_L1/$CLAVE.done"      run_polar2grid_l1.sh   "$CLAVE")"

ejecutar_nivel "Nivel 3 — los que necesitan ATMOS" \
    "$(tarea lsr  "$DIR_LSR/$CLAVE.done"  run_lsr_edr.sh  "$CLAVE")" \
    "$(tarea cryo "$DIR_CRYO/$CLAVE.done" run_cryo_edr.sh "$CLAVE")"

ejecutar_nivel "Nivel 4 — renderizado de Level 2" \
    "$(tarea p2g_edr "$DIR_P2G_EDR/$CLAVE.done" run_polar2grid_edr.sh "$CLAVE")"

# ==============================================================================
# RESUMEN
# ==============================================================================

FIN=$(date +%s)
TOTAL=$((FIN - INICIO))

titulo "RESUMEN | pasada $CLAVE | $((TOTAL / 60))m $((TOTAL % 60))s"

printf '  %-22s %-9s %-10s %s\n' ETAPA RESULTADO DURACIÓN PRODUCTOS
printf '  %-22s %-9s %-10s %s\n' "----------------------" "---------" "----------" "----------"

fallos=0
for i in "${!RES_ETAPA[@]}"; do
    etapa="${RES_ETAPA[$i]}"
    codigo="${RES_CODIGO[$i]}"
    marcador="${RES_MARCADOR[$i]}"

    # Sin tilde a propósito: printf %-9s cuenta bytes, y una tilde descuadra la
    # columna. Como sustantivo, "fallo" es lo correcto aquí de todos modos.
    if [ "$codigo" -ne 0 ]; then
        estado="fallo"
        fallos=$((fallos + 1))
        dur=""
        prod="código $codigo"
    elif [ "$marcador" = "dry-run" ]; then
        estado="dry-run"; dur=""; prod=""
    elif [ "$marcador" = "sin-cambio" ]; then
        # Terminó en 0 pero no tocó su marcador: no había nada que hacer.
        estado="ya estaba"; dur=""; prod=""
    else
        estado="ok"
        dur="$(duracion_de_marcador "$marcador")"
        prod="$(resumen_de_marcador "$marcador")"
    fi
    printf '  %-22s %-9s %-10s %s\n' "$etapa" "$estado" "${dur:--}" "${prod:--}"
done

echo ""
if [ "$fallos" -eq 0 ]; then
    echo "  Todas las etapas terminaron bien."
else
    echo "  Etapas con fallo: $fallos  (las demás siguieron; ver arriba)"
    echo "  Recordatorio: LSR falla en toda pasada nocturna, y es esperado."
fi
echo "  Log del orquestador: $LOG"

exit 0
