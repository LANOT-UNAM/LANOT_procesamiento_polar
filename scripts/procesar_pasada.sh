#!/bin/bash
# ==============================================================================
# procesar_pasada.sh — encadena los doce run_*.sh de una pasada.
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
#          ├─ nivel 2: ATMOS · ACSPO · FIRE · FLOOD · OMPS · HEAP · P2G_L1
#          │     └─ nivel 3: LSR · CRYO            (necesitan ATMOS)
#          │          └─ nivel 4: P2G_EDR          (rinde todo lo anterior)
#
# Tres a la vez y no cinco: tahan tiene 64 CPU y los hilos que ya pide cada
# script suman ~48 con tres simultáneas; con cinco pedirían ~72 y pelearían.
#
# UN FALLO NO DETIENE LA CADENA: si ATMOS cae, por ejemplo, las ramas que no
# dependen de él siguen. Cada etapa se invoca con `|| codigo=$?`, que es la
# forma correcta bajo set -e. (Aquí decía que LSR falla en toda pasada
# nocturna. No es así: de noche termina bien y escribe sus .nc sin un solo
# píxel válido, y es vestir() quien los descarta — tahan, 2026-09-22.)
#
# Variables de entorno: las de los doce run_*.sh se respetan tal cual, y este
# script lee las mismas *_STATE_DIR para poder leer los marcadores.
#   MAX_PARALELO   Etapas simultáneas por nivel (def. 3)
#   LOCK_FILE      Candado global (def. /data/tmp/lanot_polares.lock)
#   CADENA_LOG_BASE Logs (def. /var/log/lanot/polares/cadena)
#   SCRIPTS_DIR    De dónde salen los run_*.sh (def. junto a este script)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SCRIPT_DIR}"

MAX_PARALELO="${MAX_PARALELO:-3}"
LOCK_FILE="${LOCK_FILE:-/data/tmp/lanot_polares.lock}"
# "cadena" y no "orquestador": este directorio lo comparten los tres scripts
# de coordinación —recibe.sh, este y barrer_pendientes.sh—, y lo que tienen en
# común no es orquestar sino operar sobre la cadena entera. Las carpetas
# hermanas se llaman como el software de su etapa (rt-stps, cspp-sdr,
# polar2grid); ésta, como el nivel al que trabaja.
CADENA_LOG_BASE="${CADENA_LOG_BASE:-/var/log/lanot/polares/cadena}"

ESTADO="${ESTADO_BASE:-/data/output/jpss/state}"
LEVEL0="${RTSTPS_OUTPUT_DIR:-/data/output/jpss/level0}"
LEVEL1_VIIRS="${SDR_LEVEL1_VIIRS:-${SDR_OUTPUT_BASE:-/data/output/jpss/level1}/viirs}"
# Los mismos que leen run_omps_edr.sh y run_heap_edr.sh: de aquí sale qué pasada
# de esos instrumentos corresponde a la de VIIRS (ver pasada_por_traslape).
LEVEL1_OMPS="${OMPS_SDR_IN:-${SDR_OUTPUT_BASE:-/data/output/jpss/level1}/omps}"
LEVEL1_CRIS="${HEAP_CRIS_IN:-${SDR_OUTPUT_BASE:-/data/output/jpss/level1}/cris}"

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
DIR_HEAP="${HEAP_STATE_DIR:-$ESTADO/cspp-heap}"
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

# Etapas que no se lanzan porque su instrumento no dejó datos para esta pasada
# (OMPS de noche, por ejemplo), con el motivo. No son fallos.
declare -A SIN_DATOS=()

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
# órbita según el instrumento (b45236 en VIIRS, b45237 en OMPS). Lo mismo vale
# para HEAP, cuya pasada la fija CrIS. Antes se les pasaba la clave truncada
# (j01_d20260922) y cada run_*.sh la resolvía contra su directorio, pero eso
# aborta en cuanto hay dos pasadas del mismo satélite el mismo día —la segunda
# de cada día, en operación— y no distingue "no hay OMPS" de "no encontré la
# pasada". Ahora se empareja por TIEMPO: la pasada del otro instrumento es la
# que se traslapa con la ventana de VIIRS.

# Del nombre de un SDR saca su intervalo como "AAAAMMDDHHMMSS AAAAMMDDHHMMSS".
# La misma que run_heap_edr.sh: si el fin es menor que el inicio, el archivo
# cruzó la medianoche. Las comparaciones van con [ ] y no con [[ ]]: los sellos
# de antes de las 10:00 UTC empiezan con cero y [[ ]] los tomaría por octales.
intervalo_de() {
    local nombre fecha tini tfin fecha_fin
    nombre=$(basename "$1")
    IFS='_' read -r _ _ fecha tini tfin _ <<< "$nombre"
    if [[ "$fecha" != d* ]] || [[ "$tini" != t* ]] || [[ "$tfin" != e* ]]; then
        return 1
    fi
    fecha="${fecha#d}"; tini="${tini#t}"; tfin="${tfin#e}"
    if [ "$tfin" -lt "$tini" ]; then
        fecha_fin=$(date -u -d "${fecha} +1 day" +%Y%m%d)
    else
        fecha_fin="$fecha"
    fi
    echo "${fecha}${tini:0:6} ${fecha_fin}${tfin:0:6}"
}

# La ventana de la pasada de VIIRS: el inicio más temprano y el fin más tardío de
# TODOS sus GMTCO, no los de uno representativo, porque en level1 conviven
# archivos agregados y por gránulo (ver run_heap_edr.sh, ventana_de_pasada).
# Imprime "INI FIN"; código 1 si no hay ninguno.
ventana_viirs() {
    local sat fecha orbita f ini fin v_ini="" v_fin=""
    IFS='_' read -r sat fecha orbita <<< "$1"
    shopt -s nullglob
    for f in "$LEVEL1_VIIRS"/GMTCO_"${sat}"_"${fecha}"_*_"${orbita}"_*.h5; do
        read -r ini fin < <(intervalo_de "$f") || continue
        if [ -z "$v_ini" ] || [ "$ini" -lt "$v_ini" ]; then v_ini="$ini"; fi
        if [ -z "$v_fin" ] || [ "$fin" -gt "$v_fin" ]; then v_fin="$fin"; fi
    done
    shopt -u nullglob
    [ -n "$v_ini" ] || return 1
    echo "$v_ini $v_fin"
}

# pasada_por_traslape <dir> <prefijo> <sat> <ini> <fin>
#
# La clave de la pasada del otro instrumento cuya geolocalización (<prefijo>:
# GOTCO de OMPS, GCRSO de CrIS) se traslapa con la ventana. Del mismo satélite:
# NPP y NOAA-20 pasan con ~20 minutos de diferencia. Se miran la fecha de la
# ventana y sus vecinas, porque un archivo puede empezar del otro lado de la
# medianoche.
#
# Si se traslapan varias claves —la órbita cambia al cruzar el ecuador hacia el
# norte, y puede hacerlo a media pasada— gana la que más archivos aporta, y se
# avisa en stderr. Código 1 si no hay ninguna: el instrumento no dejó datos.
pasada_por_traslape() {
    local dir="$1" prefijo="$2" sat="$3" v_ini="$4" v_fin="$5"
    local d f ini fin clave mejor="" n_mejor=0
    local -A cuenta=()
    shopt -s nullglob
    for d in $(date -u -d "${v_ini:0:8} -1 day" +%Y%m%d) "${v_ini:0:8}" \
             $(date -u -d "${v_ini:0:8} +1 day" +%Y%m%d); do
        for f in "$dir"/"${prefijo}"_"${sat}"_d"${d}"_*.h5; do
            read -r ini fin < <(intervalo_de "$f") || continue
            [ "$ini" -le "$v_fin" ] && [ "$fin" -ge "$v_ini" ] || continue
            clave="$(clave_de_pasada "$(basename "$f")")" || continue
            cuenta[$clave]=$(( ${cuenta[$clave]:-0} + 1 ))
        done
    done
    shopt -u nullglob
    for clave in "${!cuenta[@]}"; do
        if [ "${cuenta[$clave]}" -gt "$n_mejor" ]; then
            mejor="$clave"; n_mejor="${cuenta[$clave]}"
        fi
    done
    [ -n "$mejor" ] || return 1
    if [ "${#cuenta[@]}" -gt 1 ]; then
        echo "  ⚠ $prefijo: se traslapan ${#cuenta[@]} pasadas (${!cuenta[*]}); se toma $mejor" >&2
    fi
    echo "$mejor"
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
#   etiqueta <TAB> script <TAB> arg...
# El marcador se mira antes y después para distinguir "corrió y produjo" de "ya
# estaba hecho", que por código de salida son indistinguibles: los doce
# devuelven 0 en los dos casos. NO viaja en la tarea: lo resuelve marcador_de a
# partir de la etiqueta, y por eso las dos tomas de mtime miran forzosamente el
# mismo archivo. Cuando el marcador viajaba en la tarea, el nombre vigilado y el
# que el script escribe podían diferir —con OMPS diferían siempre— y el resumen
# reportaba "ya estaba" para una etapa que acababa de trabajar.

correr_tarea() {
    local tarea="$1" salida="$2"
    local etiqueta marcador script
    local -a campos args

    IFS=$'\t' read -r -a campos <<< "$tarea"
    etiqueta="${campos[0]}"
    script="${campos[1]}"
    args=("${campos[@]:2}")
    marcador="$(marcador_de "$etiqueta")"

    {
        if [ -n "${SIN_DATOS[$etiqueta]:-}" ]; then
            echo "--- $etiqueta: no se lanza, ${SIN_DATOS[$etiqueta]}"
            exit 0
        fi
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
        marcador="$(marcador_de "$etiqueta")"
        salida="$TRABAJO/$etiqueta.log"

        # Sello del marcador ANTES, para saber después si esta corrida lo tocó.
        # La misma función que al cosechar: si las dos tomas no resuelven el
        # mismo nombre, la comparación no dice nada.
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
        if [ -n "${SIN_DATOS[$etiqueta]:-}" ]; then
            RES_MARCADOR+=("sin-datos")
        elif [ "$DRY_RUN" -eq 1 ]; then
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
        omps)     echo "$DIR_OMPS/$CLAVE_OMPS.done"         ;;
        heap)     echo "$DIR_HEAP/$CLAVE_HEAP.done"         ;;
        lsr)      echo "$DIR_LSR/$CLAVE.done"                ;;
        cryo)     echo "$DIR_CRYO/$CLAVE.done"               ;;
        p2g_l1)   echo "$DIR_P2G_L1/$CLAVE.done"             ;;
        p2g_edr)  echo "$DIR_P2G_EDR/$CLAVE.done"            ;;
        *)        echo ""                                    ;;
    esac
}

# Del marcador salen la duración y los conteos, sin tener que tocar los doce
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
    local etiqueta="$1" script="$2"; shift 2
    local s
    s="$(printf '%s\t%s' "$etiqueta" "$script")"
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
TRABAJO="$(mktemp -d "${TMPDIR:-/tmp}/cadena_${SELLO}_XXXX")"
trap 'rm -rf "$TRABAJO"' EXIT

mkdir -p "$CADENA_LOG_BASE" 2>/dev/null || true
ETIQUETA_LOG="${CLAVE_PEDIDA:-$(basename "${RAW:-sin_raw}")}"
LOG="$CADENA_LOG_BASE/${SELLO}_${ETIQUETA_LOG}.log"

# Todo lo que sigue va al log, y además a la terminal si hay una. Sin terminal
# —lanzado por recibe.sh o por el barrido— va SOLO al log: tee repetiría todo en
# la salida heredada, y recibe.sh la mandaba a un archivo con este mismo nombre
# (mismo sello, mismo crudo), así que dos escritores se pisaban y el log salía
# con bloques repetidos y líneas cortadas (tahan, 2026-09-22). Si el directorio
# de log no se puede escribir se sigue sin log, que es preferible a no procesar.
if : > "$LOG" 2>/dev/null; then
    if [ -t 1 ]; then
        exec > >(tee -a "$LOG") 2>&1
    else
        exec >> "$LOG" 2>&1
    fi
else
    LOG="(sin log: no se pudo escribir en $CADENA_LOG_BASE)"
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
CLAVE_HEAP=""

# ==============================================================================
# RT-STPS Y SDR  (solo si se entró por un RAW)
# ==============================================================================

if [ -n "$RAW" ]; then
    ejecutar_nivel "RT-STPS" \
        "$(armar_tarea rt_stps "$SCRIPTS_DIR/run_rt_stps.sh" "$RAW")"

    # Los RDR que acaba de producir. Se nombran explícitamente en vez de dejar
    # que run_sdr.sh autoseleccione: su filtro de edad mínima (1 min) haría que
    # no viera nada recién salido de RT-STPS y saliera en 0 sin hacer nada.
    TAREAS_SDR=()
    if [ "$DRY_RUN" -eq 1 ]; then
        echo ""
        echo "  [dry-run] aquí se buscarían los RDR nuevos en $LEVEL0"
        TAREAS_SDR=("$(armar_tarea sdr_EJEMPLO.h5 \
                                   "$SCRIPTS_DIR/run_sdr.sh" "$LEVEL0/EJEMPLO.h5")")
    else
        while IFS= read -r rdr; do
            base="$(basename "$rdr")"
            clave_sensor "$base" >/dev/null || continue
            TAREAS_SDR+=("$(armar_tarea "sdr_$base" \
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

# OMPS y HEAP, por traslape con la ventana de VIIRS (ver pasada_por_traslape).
# Sin traslape la etapa no se lanza: no es un fallo sino que no hay datos. OMPS
# de noche es el caso de todos los días —sus sensores nadir miden luz solar
# retrodispersada y el crudo no trae ni un paquete (NOAA-21, 2026-09-22)—; sin
# CrIS, lo más probable es que su SDR no haya corrido.
echo ""
echo "  Pasada:      $CLAVE"
if [ "$DRY_RUN" -eq 1 ] && [ -z "$CLAVE_PEDIDA" ]; then
    CLAVE_OMPS="j01_dAAAAMMDD_bNNNNN"
    CLAVE_HEAP="j01_dAAAAMMDD_bNNNNN"
elif ! VENTANA="$(ventana_viirs "$CLAVE")"; then
    echo "  ⚠ Sin GMTCO de $CLAVE en $LEVEL1_VIIRS: no se puede emparejar OMPS ni HEAP"
    SIN_DATOS[omps]="sin ventana de VIIRS para emparejar"
    SIN_DATOS[heap]="sin ventana de VIIRS para emparejar"
else
    read -r V_INI V_FIN <<< "$VENTANA"
    SAT_PASADA="${CLAVE%%_*}"
    echo "  Ventana:     $V_INI – $V_FIN"
    if CLAVE_OMPS="$(pasada_por_traslape "$LEVEL1_OMPS" GOTCO "$SAT_PASADA" "$V_INI" "$V_FIN")"; then
        echo "  Clave OMPS:  $CLAVE_OMPS  (otra órbita para el mismo sobrevuelo)"
    else
        SIN_DATOS[omps]="sin SDR de OMPS en la ventana (de noche no hay: miden luz solar)"
        echo "  Clave OMPS:  —  ${SIN_DATOS[omps]}"
    fi
    if CLAVE_HEAP="$(pasada_por_traslape "$LEVEL1_CRIS" GCRSO "$SAT_PASADA" "$V_INI" "$V_FIN")"; then
        echo "  Clave HEAP:  $CLAVE_HEAP  (la fija CrIS, no VIIRS)"
    else
        SIN_DATOS[heap]="sin SDR de CrIS en la ventana"
        echo "  Clave HEAP:  —  ${SIN_DATOS[heap]}"
    fi
fi

# ==============================================================================
# NIVELES 2, 3 Y 4
# ==============================================================================

tarea() {
    # etiqueta, script, clave
    armar_tarea "$1" "$SCRIPTS_DIR/$2" -p "$3"
}

ejecutar_nivel "Nivel 2 — Level 2 y renderizado de Level 1" \
    "$(tarea atmos  run_atmos_edr.sh       "$CLAVE")" \
    "$(tarea acspo  run_acspo_edr.sh       "$CLAVE")" \
    "$(tarea fire   run_active_fire_edr.sh "$CLAVE")" \
    "$(tarea flood  run_flood_edr.sh       "$CLAVE")" \
    "$(tarea omps   run_omps_edr.sh        "$CLAVE_OMPS")" \
    "$(tarea heap   run_heap_edr.sh        "$CLAVE_HEAP")" \
    "$(tarea p2g_l1 run_polar2grid_l1.sh   "$CLAVE")"

# HEAP vuelve a la cadena el 2026-08-29. Estuvo fuera doce días porque no
# producía NUCAPS-EDR, y aquello se atribuyó al build de CSPP: era nuestro. El
# bundle iba dentro del .sif y su árbol de instalación tiene que ser escribible
# —airsb103.exe abre 'fort.40' ahí dentro—, así que la recuperación moría y con
# ella los conversores a NetCDF, siempre con código 0. Ahora el bundle se
# despliega en /data/opt (preparar_servidor.sh, fase 7) y se monta.
#
# Probado de punta a punta sobre j01_d20260829_b45492: 14 NUCAPS-EDR en 1m 57s,
# y el renderizado entrega los cuatro sondeos con su vista. Va en el nivel 2
# porque solo necesita SDR; el nivel 4 (p2g_edr) es el que los consume.

ejecutar_nivel "Nivel 3 — los que necesitan ATMOS" \
    "$(tarea lsr  run_lsr_edr.sh  "$CLAVE")" \
    "$(tarea cryo run_cryo_edr.sh "$CLAVE")"

ejecutar_nivel "Nivel 4 — renderizado de Level 2" \
    "$(tarea p2g_edr run_polar2grid_edr.sh "$CLAVE")"

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
    elif [ "$marcador" = "sin-datos" ]; then
        estado="sin datos"; dur=""; prod="${SIN_DATOS[$etapa]}"
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
fi
echo "  Log de la pasada: $LOG"

exit 0
