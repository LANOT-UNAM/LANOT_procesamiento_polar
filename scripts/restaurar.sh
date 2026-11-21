#!/bin/bash
# ==============================================================================
# restaurar.sh — saca del archivo de /depot lo que dejó archivar.sh.
#
# Lo inverso de archivar.sh: busca en los índices (.idx) los miembros que
# cumplan un patrón en un intervalo de días y los extrae a un directorio, con
# sus rutas relativas y su mtime. Los cachés de ancillary quedan así con la
# misma forma que en /data/ancillary, listos para montarse en un run_*.sh.
#
#   restaurar.sh -s ancillary -d 2026-11-16 -a 2026-11-17 -o /data/tmp/x/anc
#   restaurar.sh -s raw -d 2026-09-28 -a 2026-09-29 -p '^(\./)?chain1-10_pass10' -o /data/tmp/x/raw
#   restaurar.sh -s jpss/level2/mirs -d 2026-11-14 -p 'j02_.*s20261114' -o /tmp/mirs
#   restaurar.sh -s software/ancillary --instantanea 2026-09-28 -o /data/tmp/x/anc
#
# Los crudos de antes de archivar.sh son los .tgz diarios de almacena_polar_raw.sh
# (stratus), sin índice: raw/<año>/<semana>/<AAAAJJJ>-polar.tgz. Para esos se
# lista el .tgz entero (~1.5 min por 12 GB) y la lista se guarda en el destino
# para no repetirlo. Ojo: cada uno guarda las 24 h previas a su corrida de las
# 00:01 UTC con el reloj del servidor, así que una pasada puede estar en el del
# día siguiente: pedir un intervalo de dos días.
#
# Con --instantanea FECHA, para las series del modo "instantanea" (software/…):
# extrae, de cada elemento, la versión más reciente que no sea posterior a FECHA.
#
# Códigos de salida: 0 extrajo algo, 1 error, 3 no encontró nada.
#
# Variables de entorno:
#   ARCHIVO_RAIZ   Raíz del archivo (def. /depot/polar)
# ==============================================================================

set -uo pipefail
export TZ=UTC LC_ALL=C

RAIZ="${ARCHIVO_RAIZ:-/depot/polar}"
SERIE=""; DESDE=""; HASTA=""; PATRON="."; SALIDA=""; INSTANTANEA=""; DRY_RUN=0

uso() {
    sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
    cat <<EOF

Opciones:
  -s, --serie DESTINO     Columna "destino" de config/archivo.tsv (raw, ancillary,
                          jpss/level2/atmos, software/ancillary, …)
  -d, --desde AAAA-MM-DD  -a, --hasta AAAA-MM-DD (def. = desde)
  -p, --patron ERE        Sobre la ruta del miembro (def. todo)
  -o, --salida DIR        A dónde extraer
      --instantanea FECHA Para series de instantáneas
  -n, --verificar         Solo lista lo que extraería
  -h, --help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -s|--serie)   SERIE="${2:?}"; shift ;;
        -d|--desde)   DESDE="${2:?}"; shift ;;
        -a|--hasta)   HASTA="${2:?}"; shift ;;
        -p|--patron)  PATRON="${2:?}"; shift ;;
        -o|--salida)  SALIDA="${2:?}"; shift ;;
        --instantanea) INSTANTANEA="${2:?}"; shift ;;
        -n|--verificar) DRY_RUN=1 ;;
        -h|--help) uso; exit 0 ;;
        *) echo "Opción desconocida: $1" >&2; exit 1 ;;
    esac
    shift
done

[ -n "$SERIE" ] || { echo "❌ Falta --serie" >&2; exit 1; }
[ -n "$SALIDA" ] || [ "$DRY_RUN" -eq 1 ] || { echo "❌ Falta --salida" >&2; exit 1; }
[ -d "$RAIZ/$SERIE" ] || { echo "❌ No existe $RAIZ/$SERIE" >&2; exit 1; }
[ "$DRY_RUN" -eq 1 ] || mkdir -p "$SALIDA" || exit 1

lee() { case "$1" in *.zst) echo "-I zstd" ;; *.tgz|*.gz) echo "-z" ;; *) echo "" ;; esac; }

EXTRAIDOS=0

# Extrae de <tar> los miembros listados en <lista>.
extraer() {
    local tar_="$1" lista="$2" n
    n=$(wc -l < "$lista")
    [ "$n" -gt 0 ] || return 0
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  $tar_: $n miembros"; sed 's/^/    /' "$lista" | head -5
        [ "$n" -le 5 ] || echo "    …"
        EXTRAIDOS=$((EXTRAIDOS + n)); return 0
    fi
    echo "  $tar_: $n miembros"
    # shellcheck disable=SC2046
    if tar $(lee "$tar_") -xf "$tar_" -C "$SALIDA" --no-recursion --verbatim-files-from -T "$lista"; then
        EXTRAIDOS=$((EXTRAIDOS + n))
    else
        echo "  ❌ falló la extracción de $tar_" >&2; return 1
    fi
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ERR=0

if [ -n "$INSTANTANEA" ]; then
    lim=$(date -d "$INSTANTANEA" +%Y%m%d) || exit 1
    # <elemento>.<AAAAMMDD>[.ext]: la versión más reciente ≤ lim de cada elemento
    for f in "$RAIZ/$SERIE"/*; do
        b=$(basename "$f")
        [[ "$b" =~ ^(.+)\.([0-9]{8})(\..+)?$ ]] || continue
        [[ "$b" == *.idx ]] && continue
        printf '%s\t%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$f"
    done | awk -F'\t' -v l="$lim" '$2 <= l && $2 >= m[$1] { m[$1] = $2; f[$1] = $3 } END { for (k in f) print f[k] }' |
    sort > "$TMP/versiones"
    [ -s "$TMP/versiones" ] || { echo "Sin versiones anteriores a $INSTANTANEA en $RAIZ/$SERIE"; exit 3; }
    while read -r f; do
        if [[ "$f" == *.tar* ]]; then
            tar $(lee "$f") -tf "$f" | grep -E -- "$PATRON" > "$TMP/l" || true
            extraer "$f" "$TMP/l" || ERR=1
        else
            echo "  $f"
            [ "$DRY_RUN" -eq 1 ] || cp --preserve=timestamps "$f" "$SALIDA/" || ERR=1
            EXTRAIDOS=$((EXTRAIDOS + 1))
        fi
    done < "$TMP/versiones"
else
    [ -n "$DESDE" ] || { echo "❌ Falta --desde" >&2; exit 1; }
    [ -n "$HASTA" ] || HASTA="$DESDE"
    prefijo=${SERIE//\//.}
    dia="$DESDE"
    while [[ ! "$dia" > "$HASTA" ]]; do
        anio=${dia:0:4}; jjj=$(date -d "$dia" +%j)
        sem=$(printf "%02d" $(( 10#$jjj / 7 + 1 )))
        dir="$RAIZ/$SERIE/$anio/$sem"
        encontrado=0
        # Lo de archivar.sh: cada parte con su índice
        for idx in "$dir/$prefijo-$anio$jjj".idx "$dir/$prefijo-$anio$jjj".*.idx; do
            [ -f "$idx" ] || continue
            encontrado=1
            base="${idx%.idx}"
            tar_=$(ls "$base".tar "$base".tar.zst 2>/dev/null | head -1)
            [ -n "$tar_" ] || { echo "  ❌ índice sin tar: $idx" >&2; ERR=1; continue; }
            grep -E -- "$PATRON" "$idx" > "$TMP/l" || true
            extraer "$tar_" "$TMP/l" || ERR=1
        done
        # Lo de stratus, sin índice: se lista una vez y se guarda la lista
        tgz="$dir/$anio$jjj-polar.tgz"
        if [ "$encontrado" -eq 0 ] && [ "$SERIE" = "raw" ] && [ -f "$tgz" ]; then
            cache="${SALIDA:-$TMP}/.listado-$anio$jjj"
            if [ ! -s "$cache" ]; then
                echo "  listando $tgz (sin índice; tarda)…"
                tar -tzf "$tgz" > "$cache" || { echo "  ❌ no se pudo listar $tgz" >&2; ERR=1; }
            fi
            grep -E -- "$PATRON" "$cache" > "$TMP/l" || true
            extraer "$tgz" "$TMP/l" || ERR=1
        fi
        dia=$(date -d "$dia +1 day" +%F)
    done
fi

echo "Extraídos: $EXTRAIDOS$( [ "$DRY_RUN" -eq 1 ] && echo ' (verificar)')${SALIDA:+ en $SALIDA}"
[ "$ERR" -eq 0 ] || exit 1
[ "$EXTRAIDOS" -gt 0 ] || exit 3
exit 0
