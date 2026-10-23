#!/bin/bash
# ==============================================================================
# limpiar.sh — retención de productos, temporales y marcadores de la cadena.
#
# Para cron, diario, lejos de las tandas de pasadas (07-09 y 19-21 UTC). 11:30 CST
# son las 17:30 UTC:
#
#   30 11 * * * /opt/lanot/polares/scripts/limpiar.sh >> /var/log/lanot/polares/cadena/limpiar.log 2>&1
#
# Qué se conserva y cuánto está en config/retencion.tsv, con el porqué de cada
# modo. Aquí solo está cómo se borra.
#
# Corre con ionice -c3 (solo cuando el disco está ocioso) y nice 19: /data son
# discos giratorios que ya leen lento, y una pasada en curso tiene prioridad.
#
# La PRIMERA vez hay varios TB atrasados. No soltarlos de un golpe: correr a mano
# con --margen, bajando poco a poco, y mirar antes con --verificar:
#
#   limpiar.sh --verificar
#   limpiar.sh --margen 21     # lo que pase de días+21
#   limpiar.sh --margen 14
#   …
#   limpiar.sh                 # y ya el cron
#
# Variables de entorno:
#   RETENCION_TSV     Tabla        (def. <scripts>/../config/retencion.tsv)
#   RTSTPS_INPUT_DIR  Buzón de RAW (def. /datawork/input/polar/raw)
#   LIMPIAR_LOCK      Candado      (def. /data/tmp/limpiar.lock)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TSV="${RETENCION_TSV:-$SCRIPT_DIR/../config/retencion.tsv}"
BUZON="${RTSTPS_INPUT_DIR:-/datawork/input/polar/raw}"
LOCK="${LIMPIAR_LOCK:-/data/tmp/limpiar.lock}"

# Al fondo de la cola de disco y de CPU. Se reejecuta una sola vez.
if [ -z "${_LIMPIAR_IONICE:-}" ] && command -v ionice >/dev/null; then
    export _LIMPIAR_IONICE=1
    exec ionice -c3 nice -n 19 "$0" "$@"
fi

DRY_RUN=0
MARGEN=0

uso() {
    cat <<EOF
Uso:
  $0                 Borra lo que pase de la retención de config/retencion.tsv
  $0 --verificar     Solo dice qué borraría y cuánto pesa

Opciones:
  -n, --verificar, --dry-run
  -m, --margen N     Suma N días a cada fila (para la primera vez, por tandas)
  -h, --help

Tabla: $TSV
Buzón: $BUZON
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--verificar|--dry-run) DRY_RUN=1 ;;
        -m|--margen)
            MARGEN="${2:-}"
            [[ "$MARGEN" =~ ^[0-9]+$ ]] || { echo "❌ --margen pide un entero" >&2; exit 2; }
            shift ;;
        -h|--help) uso; exit 0 ;;
        *) echo "❌ Opción desconocida: $1" >&2; uso >&2; exit 2 ;;
    esac
    shift
done

[ -r "$TSV" ] || { echo "❌ No se puede leer $TSV" >&2; exit 1; }

# Un solo limpiar a la vez: la primera pasada por tandas puede durar horas.
exec 9>"$LOCK" || { echo "❌ No se puede abrir el candado $LOCK" >&2; exit 1; }
flock -n 9 || { echo "[$(date '+%F %T')] Ya hay otro limpiar.sh corriendo; se sale."; exit 0; }

# ------------------------------------------------------------------------------

total_n=0
total_b=0

# Suma "<bytes>\n" de la entrada estándar; devuelve "n bytes".
contar() { awk '{n++; s+=$1} END{printf "%d %d\n", n, s}'; }

gb() { awk -v b="$1" 'BEGIN{printf "%.1f GB", b/1e9}'; }

informar() {   # ruta modo días n bytes
    printf '  %-34s %-15s %4s d  %8d  %s\n' "$1" "$2" "$3" "$4" "$(gb "$5")"
    total_n=$((total_n + $4))
    total_b=$((total_b + $5))
}

# Solo estas raíces. Una fila con otra ruta —un error de dedo, una variable
# vacía— se rechaza en vez de borrar.
ruta_permitida() {
    case "$1" in
        /data/tmp|/data/ancillary) return 0 ;;
        /data/output/jpss/?*)      [[ "$1" != *..* ]] ;;
        *) return 1 ;;
    esac
}

limpiar_archivos() {   # ruta minutos
    local r
    r=$(find "$1" -type f -mmin "+$2" -printf '%s\n' 2>/dev/null | contar)
    [ "$DRY_RUN" -eq 1 ] || find "$1" -type f -mmin "+$2" -delete 2>/dev/null
    echo "$r"
}

limpiar_entradas() {   # ruta minutos [patrón ERE del nombre]
    local ruta="$1" min="$2" patron="${3:-}" e n=0 b=0 s
    while IFS= read -r -d '' e; do
        [ -n "$patron" ] && ! [[ "${e##*/}" =~ $patron ]] && continue
        s=$(find "$e" -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')
        n=$((n + 1)); b=$((b + s))
        [ "$DRY_RUN" -eq 1 ] || rm -rf -- "$e"
    done < <(find "$ruta" -mindepth 1 -maxdepth 1 ! -name '*.lock' -mmin "+$min" -print0 2>/dev/null)
    echo "$n $b"
}

limpiar_marcadores() {   # ruta minutos
    local r
    r=$(find "$1" -path "$1/rt-stps" -prune -o -type f -mmin "+$2" -printf '%s\n' 2>/dev/null | contar)
    [ "$DRY_RUN" -eq 1 ] || find "$1" -path "$1/rt-stps" -prune -o -type f -mmin "+$2" -delete 2>/dev/null
    echo "$r"
}

# Marcadores de RT-STPS: <raw>.done, .rdr, .intentos, .fallido. Se van cuando su
# RAW ya no está en el buzón. Si el buzón no se ve o está vacío —el NFS de
# /datawork caído—, TODOS los RAW parecerían borrados y esto se llevaría un mes
# de marcadores; al volver el montaje, el barrido reprocesaría el mes entero.
limpiar_marcadores_raw() {   # ruta minutos
    local ruta="$1" min="$2" m raw n=0 b=0
    if [ ! -d "$BUZON" ] || [ -z "$(find "$BUZON" -maxdepth 1 -type f -print -quit 2>/dev/null)" ]; then
        echo "  ⚠ el buzón $BUZON no se ve o está vacío: no se toca $ruta" >&2
        echo "0 0"
        return
    fi
    while IFS= read -r -d '' m; do
        raw="${m##*/}"
        raw="${raw%.*}"
        [ -e "$BUZON/$raw" ] && continue
        n=$((n + 1)); b=$((b + $(stat -c %s "$m")))
        [ "$DRY_RUN" -eq 1 ] || rm -f -- "$m"
    done < <(find "$ruta" -maxdepth 1 -type f -mmin "+$min" \
                  \( -name '*.done' -o -name '*.rdr' -o -name '*.intentos' -o -name '*.fallido' \) -print0 2>/dev/null)
    echo "$n $b"
}

# ------------------------------------------------------------------------------

inicio=$(date +%s)
echo "[$(date '+%F %T')] limpiar.sh$([ "$DRY_RUN" -eq 1 ] && echo ' --verificar')$([ "$MARGEN" -gt 0 ] && echo " --margen $MARGEN")"
printf '  %-34s %-15s %6s  %8s  %s\n' ruta modo días archivos peso

errores=0
while IFS=$'\t' read -r ruta dias modo patron _resto; do
    [[ -z "$ruta" || "$ruta" == \#* ]] && continue
    ruta="${ruta%/}"

    if ! ruta_permitida "$ruta"; then
        echo "  ❌ ruta no permitida, se salta: $ruta" >&2; errores=$((errores + 1)); continue
    fi
    if ! [[ "$dias" =~ ^[0-9]+$ ]] || [ "$dias" -lt 1 ]; then
        echo "  ❌ días inválidos ($dias), se salta: $ruta" >&2; errores=$((errores + 1)); continue
    fi
    [ -d "$ruta" ] || continue

    min=$(( (dias + MARGEN) * 1440 ))
    case "$modo" in
        archivos)       r=$(limpiar_archivos "$ruta" "$min") ;;
        entradas)       r=$(limpiar_entradas "$ruta" "$min" "${patron:-}") ;;
        dias_anc)       r=$(limpiar_entradas "$ruta" "$min" '^[0-9]{4}_[0-9]{2}_[0-9]{2}_[0-9]{3}$') ;;
        marcadores)     r=$(limpiar_marcadores "$ruta" "$min") ;;
        marcadores_raw) r=$(limpiar_marcadores_raw "$ruta" "$min") ;;
        *) echo "  ❌ modo desconocido ($modo), se salta: $ruta" >&2; errores=$((errores + 1)); continue ;;
    esac
    read -r n b <<< "$r"
    informar "$ruta" "$modo" "$((dias + MARGEN))" "$n" "$b"
done < "$TSV"

verbo=$([ "$DRY_RUN" -eq 1 ] && echo "Se borrarían" || echo "Borrados")
echo "[$(date '+%F %T')] $verbo: $total_n archivos o entradas, $(gb "$total_b"), en $(( $(date +%s) - inicio )) s"
[ "$errores" -eq 0 ]
