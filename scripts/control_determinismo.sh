#!/bin/bash
# ==============================================================================
# control_determinismo.sh — ¿ACSPO, Active Fire y MiRS dan lo mismo dos veces?
#
# La prueba de dos turnos del 2026-10-14 dio 9 GeoTIFF distintos de 132 entre la
# fase en serie y la encimada, todos de estos tres EDR, con los mismos SDR y el
# mismo GFS (docs/estado_y_pendientes.md, "2026-10-16"). Ahí cambiaban dos cosas
# a la vez —otra corrida y otra concurrencia—, así que no se supo cuál era. Esto
# es el control: la MISMA pasada, dos veces seguidas, en serie y sin nada más
# corriendo, y comparar los .nc.
#
#   · Si difieren, el algoritmo no es determinista (hilos, orden de suma) y la
#     diferencia del 14 no era de la prueba: los comparadores tienen que
#     tolerarla en estos tres, y CLAUDE.md deja de decir que los .nc de CSPP
#     son reproducibles sin esa salvedad.
#   · Si salen idénticos, la del 14 sí vino de encimar, y hay que buscar qué
#     comparten dos corridas a la vez (cachés de ACSPO, máscaras de Fire).
#
# Con --un-hilo agrega un segundo par, a un solo hilo (SLURM_CPUS_PER_TASK=1):
# si a un hilo salen iguales y con varios no, la causa es el paralelismo. Fire
# no tiene control de hilos en run_active_fire_edr.sh, así que ahí no cambia.
#
# Solo se compara el CONTENIDO de las variables (h5diff, dataset por dataset):
# los atributos de fecha cambian siempre y no cuentan. No hace falta pasar por
# GeoTIFF: el 2026-10-16 se vio que la diferencia ya está en los .nc.
#
# La entrada es la de producción (level1, solo lectura) y los cachés de
# ancillary también, porque son lo que usa la operación; todo lo que se escribe
# va a <base>. Por eso corre como lanotadm, el dueño de los cachés, y desde
# /opt/lanot/polares. Mientras dura toma el candado de producción: una pasada
# que llegue en ese rato sale en 75 y la recoge barrer_pendientes.sh.
#
# Hora apropiada: fuera de los racimos de JPSS (07–09 y 19–21 UTC, 01–03 y
# 13–15 en tahan) y de sus reintentos (hasta ~1 h después). Dura ~20 min, el
# doble con --un-hilo. Por ejemplo:
#
#   cd / && echo /opt/lanot/polares/scripts/control_determinismo.sh \
#       | sudo -u lanotadm at 10:00
#
# El `cd /` no es adorno: `at` guarda el directorio desde el que se programa y
# entra ahí antes de ejecutar nada. Desde el clon, en un /home/<persona> con
# 700, lanotadm no puede entrar y el trabajo muere en el primer segundo; el
# aviso iría por correo, y tahan no tiene `mail`, así que no queda rastro. Así
# se perdió la corrida del 2026-11-04.
#
# El informe queda en <base>/informe.txt.
#
# Uso:
#   control_determinismo.sh [opciones] [PASADA ...]
#
#   PASADA   Clave o trozo de una pasada de level1/viirs (j01_d20261103_t090400,
#            "t0904"). Sin ninguna, la más reciente de NOAA-20 y la de NOAA-21.
#            El 2026-10-14 la SST y MiRS difirieron en NPP, pero NPP ya no se
#            recibe (noviembre de 2026); Fire difirió en los tres satélites. Una
#            pasada vieja de NPP se puede pedir aquí si sus SDR siguen en level1.
#
# Opciones:
#   -b, --base DIR   Árbol de la prueba (def. /data/tmp/control_determinismo_<sello>)
#       --un-hilo    Agrega un par a un solo hilo
#   -e, --espera MIN Si hay una pasada de producción en curso, cuánto esperarla
#                    antes de rendirse (def. 60)
#   -h, --help
#
# Variables de entorno:
#   LOCK_PRODUCCION  Candado de la operación (def. /data/tmp/lanot_polares.lock)
#   LEVEL1           Raíz de los SDR          (def. /data/output/jpss/level1)
#   PRUEBA_USUARIO   Usuario exigido (def. lanotadm; vacío para no exigir)
#   H5DIFF           Comparador (def. h5diff)
#   SCRIPTS_DIR      De dónde salen los run_*.sh (def. junto a este script)
#
# Sale en 0 si todos los pares salieron idénticos en datos; en 1 si alguno
# difiere o alguna corrida falló; en 2 si no pudo empezar.
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SCRIPT_DIR}"
LOCK_PRODUCCION="${LOCK_PRODUCCION:-/data/tmp/lanot_polares.lock}"
LEVEL1="${LEVEL1:-/data/output/jpss/level1}"
PRUEBA_USUARIO="${PRUEBA_USUARIO-lanotadm}"
H5DIFF="${H5DIFF:-h5diff}"

SELLO=$(date '+%Y%m%d_%H%M%S')
BASE=""
UN_HILO=0
ESPERA_MIN=60
PEDIDAS=()

uso() { sed -n '/^# Uso:/,/^# Sale en 0/p' "$0" | sed 's/^# \{0,1\}//'; }
ahora() { date '+%Y-%m-%d %H:%M:%S'; }

while [ $# -gt 0 ]; do
    case "$1" in
        -b|--base)   BASE="$2"; shift 2 ;;
        --un-hilo)   UN_HILO=1; shift ;;
        -e|--espera) ESPERA_MIN="$2"; shift 2 ;;
        -h|--help)   uso; exit 0 ;;
        -*)          echo "Opción desconocida: $1" >&2; uso >&2; exit 2 ;;
        *)           PEDIDAS+=("$1"); shift ;;
    esac
done
BASE="${BASE:-/data/tmp/control_determinismo_$SELLO}"

source "$SCRIPTS_DIR/pasadas.sh"

# ==============================================================================
# ANTES DE EMPEZAR
# ==============================================================================

if [ -n "$PRUEBA_USUARIO" ] && [ "$(id -un)" != "$PRUEBA_USUARIO" ]; then
    echo "❌ Hay que correrlo como $PRUEBA_USUARIO (dueño de los cachés de ancillary):" >&2
    echo "   cd / && echo $0 | sudo -u $PRUEBA_USUARIO at <hora>" >&2
    exit 2
fi
if ! command -v "$H5DIFF" > /dev/null; then
    echo "❌ No se encuentra $H5DIFF; sin él no hay comparación (H5DIFF=<ruta>)." >&2
    exit 2
fi
for s in run_acspo_edr.sh run_active_fire_edr.sh run_mirs_edr.sh; do
    [ -x "$SCRIPTS_DIR/$s" ] || { echo "❌ Falta $SCRIPTS_DIR/$s" >&2; exit 2; }
done

# Las pasadas: clave de VIIRS (ACSPO, Fire) y la de ATMS que la traslapa (MiRS).
CLAVES=(); CLAVES_MIRS=()
agregar_pasada() {
    local pedido="$1" cm
    if ! resolver_pasada "$LEVEL1/viirs" GMTCO "$pedido" || [ -z "$CLAVE" ]; then
        echo "❌ No se encontró en $LEVEL1/viirs la pasada: ${pedido:-(la más reciente)}" >&2
        exit 2
    fi
    cm="$(pasada_que_traslapa "$LEVEL1/atms" GATMO "$SAT" "$VENTANA_INI" "$VENTANA_FIN" 2>/dev/null)" || cm=""
    CLAVES+=("$CLAVE"); CLAVES_MIRS+=("$cm")
}
if [ "${#PEDIDAS[@]}" -eq 0 ]; then
    for sat in j01 j02; do
        ultima="$(listar_pasadas "$LEVEL1/viirs" GMTCO | awk -v s="$sat" 'index($1, s "_") == 1 { k = $1 } END { print k }')"
        [ -n "$ultima" ] && PEDIDAS+=("$ultima")
    done
fi
[ "${#PEDIDAS[@]}" -gt 0 ] || { echo "❌ No hay pasadas de NOAA-20 ni de NOAA-21 en $LEVEL1/viirs" >&2; exit 2; }
for p in "${PEDIDAS[@]}"; do agregar_pasada "$p"; done

mkdir -p "$BASE" || exit 2
INFORME="$BASE/informe.txt"
exec > >(tee -a "$BASE/control.out") 2>&1

echo "=== control_determinismo.sh | $(ahora) | base $BASE"
for i in "${!CLAVES[@]}"; do
    echo "  pasada ${CLAVES[$i]}  (MiRS: ${CLAVES_MIRS[$i]:-sin ATMS en la ventana})"
done

# El candado de producción, para que nada más corra mientras tanto.
exec 9>"$LOCK_PRODUCCION"
if ! flock -w $((ESPERA_MIN * 60)) 9; then
    echo "❌ La operación no soltó su candado en $ESPERA_MIN min; no se empieza." >&2
    exit 2
fi
echo "  candado de producción tomado ($(ahora))"

# ==============================================================================
# LAS CORRIDAS
# ==============================================================================

# correr <variante> <n> <clave> <clave_mirs>: los tres EDR sobre la pasada, en
# serie, con toda la salida en <base>/<variante>_<n>/.
FALLOS=0
correr() {
    local variante="$1" n="$2" clave="$3" clave_mirs="$4"
    local d="$BASE/${variante}_$n" et cod t0
    mkdir -p "$d"/{acspo,fire,mirs,state,tmp,logs}
    for et in acspo fire mirs; do
        [ "$et" != mirs ] || [ -n "$clave_mirs" ] || continue
        t0=$(date +%s); cod=0
        (
            export ACSPO_OUT="$d/acspo" ACSPO_STATE_DIR="$d/state/acspo" ACSPO_WORK_BASE="$d/tmp" ACSPO_LOG_BASE="$d/logs"
            export FIRE_OUT="$d/fire"   FIRE_STATE_DIR="$d/state/fire"   FIRE_WORK_BASE="$d/tmp"  FIRE_LOG_BASE="$d/logs"
            export MIRS_OUT="$d/mirs"   MIRS_STATE_DIR="$d/state/mirs"   MIRS_WORK_BASE="$d/tmp"  MIRS_LOG_BASE="$d/logs"
            export TMPDIR="$d/tmp"
            exec 9>&-     # el candado es de este script, no de los EDR
            [ "$variante" != un_hilo ] || export SLURM_CPUS_PER_TASK=1
            cd /
            case "$et" in
                acspo) exec "$SCRIPTS_DIR/run_acspo_edr.sh"       -p "$clave" ;;
                fire)  exec "$SCRIPTS_DIR/run_active_fire_edr.sh" -p "$clave" ;;
                mirs)  exec "$SCRIPTS_DIR/run_mirs_edr.sh"        -p "$clave_mirs" ;;
            esac
        ) > "$d/$et.out" 2>&1 || cod=$?
        printf '  %-8s %-24s %-5s código %s, %s s\n' "${variante}_$n" "$clave" "$et" "$cod" $(( $(date +%s) - t0 ))
        [ "$cod" -eq 0 ] || FALLOS=$((FALLOS + 1))
    done
}

VARIANTES=(normal)
[ "$UN_HILO" -eq 0 ] || VARIANTES+=(un_hilo)

for v in "${VARIANTES[@]}"; do
    for i in "${!CLAVES[@]}"; do
        for n in 1 2; do
            correr "$v" "$n" "${CLAVES[$i]}" "${CLAVES_MIRS[$i]}"
        done
    done
done

flock -u 9
echo "  candado de producción soltado ($(ahora))"

# ==============================================================================
# LA COMPARACIÓN
# ==============================================================================

# Datasets con diferencias entre dos .nc, "ruta N" por línea. Las líneas de
# atributo no cuentan; un "not comparable" sí, porque es estructura distinta.
diferencias() {
    "$H5DIFF" -r "$1" "$2" 2>&1 | awk '
        /^dataset: /   { d = $2; next }
        /^attribute: / { d = ""; next }
        /differences found/ && d != "" && $1 + 0 > 0 { print d, $1; d = "" }
        /[Nn]ot comparable/ { print "no-comparable:", $0 }'
}

# Nombre sin el sello de creación, para emparejar las dos corridas.
sin_creacion() { sed -E 's/_c[0-9]{8,}//' <<< "$1"; }

# Ancillary dinámico que citan los logs de una corrida (para ver que fue el mismo).
gfs_de() { grep -ahoE 'gfs\.t[0-9]{2}z\.[A-Za-z0-9._]+' "$1"/logs/cspp-edr/*.log 2>/dev/null | sort -u | tr '\n' ' '; }

DISTINTOS=0
{
    echo "Control de determinismo — $(ahora)"
    echo "Base: $BASE"
    echo "Corridas fallidas: $FALLOS"
    for v in "${VARIANTES[@]}"; do
        echo ""
        echo "=== variante $v$( [ "$v" = un_hilo ] && echo ' (SLURM_CPUS_PER_TASK=1)')"
        a="$BASE/${v}_1"; b="$BASE/${v}_2"
        ga="$(gfs_de "$a")"; gb="$(gfs_de "$b")"
        if [ "$ga" = "$gb" ]; then
            echo "  GFS citado: el mismo en las dos (${ga:-ninguno})"
        else
            echo "  ⚠ GFS citado DISTINTO: 1 = $ga | 2 = $gb"
        fi
        for et in acspo fire mirs; do
            declare -A en_b=()
            while IFS= read -r f; do en_b["$(sin_creacion "$(basename "$f")")"]="$f"; done \
                < <(find "$b/$et" -maxdepth 1 -name '*.nc' 2>/dev/null)
            n_a=0; iguales=0; distintos=0; huerfanos=0
            detalle=""
            while IFS= read -r f; do
                n_a=$((n_a + 1))
                k="$(sin_creacion "$(basename "$f")")"
                g="${en_b[$k]:-}"
                if [ -z "$g" ]; then
                    huerfanos=$((huerfanos + 1)); detalle="$detalle\n      solo en 1: $k"; continue
                fi
                unset 'en_b[$k]'
                dif="$(diferencias "$f" "$g")"
                if [ -z "$dif" ]; then
                    iguales=$((iguales + 1))
                else
                    distintos=$((distintos + 1))
                    detalle="$detalle\n      $k:$(head -n 8 <<< "$dif" | sed 's/^/ /' | tr '\n' ';')"
                fi
            done < <(find "$a/$et" -maxdepth 1 -name '*.nc' 2>/dev/null | sort)
            for k in "${!en_b[@]}"; do huerfanos=$((huerfanos + 1)); detalle="$detalle\n      solo en 2: $k"; done
            unset en_b
            DISTINTOS=$((DISTINTOS + distintos + huerfanos))
            marca="✅"; [ $((distintos + huerfanos)) -eq 0 ] || marca="❌"
            printf '  %s %-6s %3d archivos: %3d iguales, %3d distintos, %d sin pareja' \
                "$marca" "$et" "$n_a" "$iguales" "$distintos" "$huerfanos"
            [ -z "$detalle" ] || printf '%b' "$detalle"
            echo ""
        done
    done
    echo ""
    if [ "$FALLOS" -gt 0 ]; then
        echo "VEREDICTO: hubo corridas fallidas; ver <base>/<variante>_<n>/<etapa>.out"
    elif [ "$DISTINTOS" -eq 0 ]; then
        echo "VEREDICTO: idénticos en datos. Lo del 2026-10-14 vino de encimar las pasadas."
    else
        echo "VEREDICTO: difieren corriendo en serie. No es determinista; no era la prueba."
    fi
} > "$INFORME"
# A archivo y no por tubería: con "| tee" el bloque corre en un subshell y
# DISTINTOS se pierde.
cat "$INFORME"

[ "$FALLOS" -eq 0 ] && [ "$DISTINTOS" -eq 0 ]
