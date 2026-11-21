#!/bin/bash
# ==============================================================================
# archivar.sh — archivo a largo plazo en /depot de lo que la cadena no puede
# regenerar: crudos, ancillary, productos chicos de nivel 2, vistas, logs y el
# software de cada versión.
#
# Para cron, diario, después de que limpiar.sh haya hecho lo suyo y lejos de las
# tandas de pasadas (07-09 y 19-21 UTC). 05:30 CST son las 11:30 UTC:
#
#   30 5 * * * flock -n /data/tmp/archivar.lock /opt/lanot/polares/scripts/archivar.sh >> /var/log/lanot/polares/cadena/archivar.log 2>&1
#
# Qué se archiva y por qué está en config/archivo.tsv. Aquí solo está cómo.
#
# Sustituye a almacena_polar_raw.sh y almacena_polar.sh, del cron de lanotadm en
# stratus. De almacena_polar.sh 3.4 se conserva lo que estaba bien: tars por día y
# por semana juliana, y "solo cuenta lo que de verdad quedó dentro". Cambia:
#
#   - No borra los originales: de eso se encarga limpiar.sh con su retención.
#   - Nunca reescribe ni anexa a un tar. Lo que llegue tarde va a una parte nueva
#     (<prefijo>-<AAAAJJJ>.2.tar). Un tar que se escribió y se verificó no se
#     vuelve a tocar, y en Lustre anexar obliga a releer el archivo entero.
#   - Cada parte lleva al lado un índice (.idx) con sus miembros. Saber qué falta
#     es leer los índices, no listar tars de decenas de GB; y encontrar un archivo
#     en el archivo es un grep sobre ellos.
#   - Escribe en un temporal, verifica que la lista de miembros sea exactamente la
#     esperada, y solo entonces lo pone en su nombre definitivo.
#   - Antes de escribir comprueba que en /depot quede la reserva
#     (ARCHIVO_RESERVA_GB): estaba al 96 % el 2026-11-21.
#   - El día de un archivo es el de su mtime, en UTC: nunca se escapa uno por un
#     nombre que no se supo leer.
#
# Recuperar: localizar con  grep -l NOMBRE /depot/polar/<destino>/*/*/*.idx
# y extraer con  tar -xf <tar> MIEMBRO  (o tar -I zstd -xf, para los .tar.zst).
#
# Códigos de salida: 0 todo bien, 1 algún error (el resto de las series sigue).
#
# Variables de entorno:
#   ARCHIVO_TSV         Tabla              (def. <scripts>/../config/archivo.tsv)
#   ARCHIVO_RAIZ        Raíz del archivo   (def. /depot/polar)
#   ARCHIVO_MONTAJE     Punto de montaje   (def. /depot) — se exige montado
#   ARCHIVO_DESFASE     Días antes de archivar un día (def. 2)
#   ARCHIVO_VENTANA     Días hacia atrás que se revisan (def. 10)
#   ARCHIVO_RESERVA_GB  Espacio libre mínimo a dejar en el montaje (def. 2000)
#   ARCHIVO_ZSTD        Compresor          (def. "zstd -T4 -3")
#   ARCHIVO_LOCK        Candado            (def. /data/tmp/archivar.lock)
# ==============================================================================

set -uo pipefail
export TZ=UTC LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TSV="${ARCHIVO_TSV:-$SCRIPT_DIR/../config/archivo.tsv}"
RAIZ="${ARCHIVO_RAIZ:-/depot/polar}"
MONTAJE="${ARCHIVO_MONTAJE:-/depot}"
DESFASE="${ARCHIVO_DESFASE:-2}"
VENTANA="${ARCHIVO_VENTANA:-10}"
RESERVA_GB="${ARCHIVO_RESERVA_GB:-2000}"
ZSTD="${ARCHIVO_ZSTD:-zstd -T4 -3}"
LOCK="${ARCHIVO_LOCK:-/data/tmp/archivar.lock}"

# Al fondo de la cola de disco y de CPU. Se reejecuta una sola vez.
if [ -z "${_ARCHIVAR_IONICE:-}" ] && command -v ionice >/dev/null; then
    export _ARCHIVAR_IONICE=1
    exec ionice -c3 nice -n 19 "$0" "$@"
fi

DRY_RUN=0
SOLO=""
DESDE=""
HASTA=""

uso() {
    cat <<EOF
Uso:
  $0                     Archiva los días cerrados de la ventana
  $0 --verificar         Solo dice qué archivaría y cuánto pesa

Opciones:
  -n, --verificar, --dry-run
  -s, --solo S1[,S2…]    Solo esas series (columna "serie" de la tabla)
  -d, --desde AAAA-MM-DD Primer día (def. hoy − $VENTANA). Para rellenar hacia atrás
  -a, --hasta AAAA-MM-DD Último día (def. hoy − $DESFASE). Nunca hoy: no está cerrado
  -h, --help

Tabla: $TSV
Raíz:  $RAIZ
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--verificar|--dry-run) DRY_RUN=1 ;;
        -s|--solo)  SOLO="${2:?falta la serie}"; shift ;;
        -d|--desde) DESDE="${2:?falta la fecha}"; shift ;;
        -a|--hasta) HASTA="${2:?falta la fecha}"; shift ;;
        -h|--help)  uso; exit 0 ;;
        *) echo "Opción desconocida: $1" >&2; uso >&2; exit 1 ;;
    esac
    shift
done

HOY=$(date +%F)
[ -n "$DESDE" ] || DESDE=$(date -d "$HOY -$VENTANA days" +%F)
[ -n "$HASTA" ] || HASTA=$(date -d "$HOY -$DESFASE days" +%F)
for f in "$DESDE" "$HASTA"; do
    date -d "$f" +%F >/dev/null 2>&1 || { echo "❌ Fecha inválida: $f" >&2; exit 1; }
done
if [[ ! "$HASTA" < "$HOY" ]]; then
    echo "❌ --hasta $HASTA: el día de hoy ($HOY) todavía no está cerrado" >&2; exit 1
fi
if [[ "$HASTA" < "$DESDE" ]]; then
    echo "❌ --hasta $HASTA es anterior a --desde $DESDE" >&2; exit 1
fi

[ -f "$TSV" ] || { echo "❌ No existe la tabla $TSV" >&2; exit 1; }

# Candado propio, además del flock del cron: una corrida a mano no debe pisarse
# con la del cron.
if [ "$DRY_RUN" -eq 0 ]; then
    exec 9>"$LOCK" || { echo "❌ No se pudo abrir el candado $LOCK" >&2; exit 1; }
    flock -n 9 || { echo "⏭  Otra corrida de archivar.sh tiene el candado $LOCK"; exit 0; }
fi

if ! mountpoint -q "$MONTAJE"; then
    echo "❌ $MONTAJE no está montado: no se archiva nada" >&2; exit 1
fi
if [ "$DRY_RUN" -eq 0 ] && [ ! -w "$RAIZ" ]; then
    echo "❌ Sin permiso de escritura en $RAIZ" >&2; exit 1
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/archivar.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

INICIO=$(date +%s)
ERRORES=0
TOTAL_PARTES=0
TOTAL_ARCHIVOS=0
TOTAL_BYTES=0

# ------------------------------------------------------------------------------
libre_gb() { df -P --block-size=1G "$MONTAJE" | awk 'NR==2 {print $4}'; }

echo "=============================================================================="
echo "[$(date '+%F %T')] archivar.sh — días $DESDE a $HASTA$( [ "$DRY_RUN" -eq 1 ] && echo ' (verificar: no se escribe nada)')"
echo "  Raíz: $RAIZ · libres en $MONTAJE: $(libre_gb) GB · reserva: $RESERVA_GB GB"
echo "=============================================================================="

gb() { awk -v b="$1" 'BEGIN { printf "%.2f", b / 1e9 }'; }

# ¿Cabe? Deja RESERVA_GB libres después de escribir.
cabe() {
    local bytes="$1" libre
    libre=$(libre_gb)
    awk -v b="$bytes" -v l="$libre" -v r="$RESERVA_GB" 'BEGIN { exit !(l - b / 2^30 >= r) }'
}

semana() { printf "%02d" $(( 10#$(date -d "$1" +%j) / 7 + 1 )); }

# Opciones de tar para (des)comprimir.
tar_comp() { [ "$1" = "zst" ] && printf -- '-I\n%s\n' "$ZSTD"; }
tar_lee()  { [ "$1" = "zst" ] && printf -- '-I\nzstd\n'; }

# ------------------------------------------------------------------------------
# Una parte del modo "dia": los archivos de <lista> (rutas relativas a <origen>)
# que todavía no estén en ningún índice de ese día.
archivar_dia() {
    local serie="$1" origen="$2" destino="$3" dia="$4" lista="$5" comp="$6"
    local anio jjj sem destdir prefijo base ya nuevos bytes n ext nombre tmp
    anio=${dia:0:4}
    jjj=$(date -d "$dia" +%j)
    sem=$(semana "$dia")
    destdir="$RAIZ/$destino/$anio/$sem"
    prefijo=${destino//\//.}
    base="$prefijo-$anio$jjj"

    ya="$TMP/ya"; nuevos="$TMP/nuevos"
    cat "$destdir/$base".idx "$destdir/$base".*.idx 2>/dev/null | sort -u > "$ya"
    # Solo lo que sigue existiendo: limpiar.sh pudo llevárselo entre el find y aquí.
    sort -u "$lista" | comm -23 - "$ya" | while IFS= read -r m; do
        [ -f "$origen/$m" ] && printf '%s\n' "$m"
    done > "$nuevos"

    n=$(wc -l < "$nuevos")
    [ "$n" -gt 0 ] || return 0

    bytes=$(cd "$origen" && tr '\n' '\0' < "$nuevos" | xargs -0 stat -c %s | awk '{s += $1} END {print s + 0}')

    # Primera parte sin número; las que lleguen tarde, .2, .3…
    ext=".tar"; [ "$comp" = "zst" ] && ext=".tar.zst"
    if ! ls "$destdir/$base".idx >/dev/null 2>&1; then
        nombre="$base"
    else
        local k=2
        while [ -e "$destdir/$base.$k.idx" ]; do k=$((k + 1)); done
        nombre="$base.$k"
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf "  [verificar] %-52s %6d archivos %9s GB\n" "$destino/$anio/$sem/$nombre$ext" "$n" "$(gb "$bytes")"
        TOTAL_PARTES=$((TOTAL_PARTES + 1)); TOTAL_ARCHIVOS=$((TOTAL_ARCHIVOS + n)); TOTAL_BYTES=$((TOTAL_BYTES + bytes))
        return 0
    fi

    if ! cabe "$bytes"; then
        echo "  ❌ $serie $dia: $(gb "$bytes") GB no caben dejando $RESERVA_GB GB libres en $MONTAJE ($(libre_gb) GB)"
        ERRORES=$((ERRORES + 1)); return 1
    fi

    mkdir -p "$destdir" || { echo "  ❌ No se pudo crear $destdir"; ERRORES=$((ERRORES + 1)); return 1; }
    tmp="$destdir/.$nombre$ext.tmp.$$"
    local opc=() lee=()
    mapfile -t opc < <(tar_comp "$comp")
    mapfile -t lee < <(tar_lee "$comp")

    printf "  %-52s %6d archivos %9s GB… " "$destino/$anio/$sem/$nombre$ext" "$n" "$(gb "$bytes")"
    if ! tar "${opc[@]}" -C "$origen" -cf "$tmp" --no-recursion --verbatim-files-from -T "$nuevos" 2> "$TMP/tar.err"; then
        echo "FALLÓ"; sed 's/^/      /' "$TMP/tar.err" | head -5
        rm -f "$tmp"; ERRORES=$((ERRORES + 1)); return 1
    fi
    # Lo que de verdad quedó dentro, contra lo que se pidió.
    if ! tar "${lee[@]}" -tf "$tmp" 2>/dev/null | sort > "$TMP/dentro" \
       || ! cmp -s "$TMP/dentro" "$nuevos"; then
        echo "NO CUADRA: $(wc -l < "$TMP/dentro") miembros de $n; no se guarda"
        rm -f "$tmp"; ERRORES=$((ERRORES + 1)); return 1
    fi
    cp "$nuevos" "$destdir/.$nombre.idx.tmp.$$" \
        && mv "$tmp" "$destdir/$nombre$ext" \
        && mv "$destdir/.$nombre.idx.tmp.$$" "$destdir/$nombre.idx" \
        || { echo "FALLÓ al ponerlo en su lugar"; rm -f "$tmp" "$destdir/.$nombre.idx.tmp.$$"; ERRORES=$((ERRORES + 1)); return 1; }
    echo "ok"
    TOTAL_PARTES=$((TOTAL_PARTES + 1)); TOTAL_ARCHIVOS=$((TOTAL_ARCHIVOS + n)); TOTAL_BYTES=$((TOTAL_BYTES + bytes))
}

# Modos "dia" y "dia_subdirs": un solo find por fila, agrupado por (subdir, día).
serie_dia() {
    local serie="$1" modo="$2" origen="$3" destino="$4" incluir="$5" excluir="$6" comp="$7"
    local filtrado="$TMP/filtrado" clave dia sub
    [ -d "$origen" ] || { echo "  ⚠ $serie: no existe $origen"; return 0; }

    # dia \t subdir \t miembro. ENVIRON y no -v: -v procesaría las '\' de las ERE.
    find "$origen" -type f -printf '%TY-%Tm-%Td\t%P\n' 2>/dev/null |
    INC="$incluir" EXC="$excluir" DESDE="$DESDE" HASTA="$HASTA" MODO="$modo" awk -F'\t' '
        BEGIN { inc = ENVIRON["INC"]; exc = ENVIRON["EXC"] }
        $1 < ENVIRON["DESDE"] || $1 > ENVIRON["HASTA"] { next }
        {
            n = split($2, p, "/"); nombre = p[n]
            if (inc != "-" && nombre !~ inc) next
            if (exc != "-" && $2 ~ exc) next
            if (ENVIRON["MODO"] == "dia_subdirs") {
                if (n < 2) next                       # suelto en la raíz: no es de ningún subdir
                sub_ = p[1]; m = substr($2, length(p[1]) + 2)
            } else { sub_ = "."; m = $2 }
            print $1 "\t" sub_ "\t" m
        }' | sort > "$filtrado"

    if [ ! -s "$filtrado" ]; then
        echo "  $serie: nada en la ventana"; return 0
    fi
    # Sustitución de proceso y no tubería: en una tubería el while corre en una
    # subshell y se perderían los contadores y los errores.
    while IFS=$'\t' read -r dia sub; do
        awk -F'\t' -v d="$dia" -v s="$sub" '$1 == d && $2 == s { print $3 }' "$filtrado" > "$TMP/lista"
        if [ "$sub" = "." ]; then
            archivar_dia "$serie" "$origen" "$destino" "$dia" "$TMP/lista" "$comp"
        else
            archivar_dia "$serie" "$origen/$sub" "$destino/$sub" "$dia" "$TMP/lista" "$comp"
        fi
    done < <(cut -f1,2 "$filtrado" | sort -u)
}

# Modo "instantanea": cada elemento del primer nivel, entero, una vez por versión.
serie_instantanea() {
    local serie="$1" origen="$2" destino="$3" incluir="$4" excluir="$5" comp="$6"
    local destdir="$RAIZ/$destino" e ruta fecha final tmp bytes nuevas=0
    [ -d "$origen" ] || { echo "  ⚠ $serie: no existe $origen"; return 0; }

    for e in $(ls -A "$origen"); do
        ruta="$origen/$e"
        [ "$incluir" = "-" ] || [[ "$e" =~ $incluir ]] || continue
        [ "$excluir" = "-" ] || ! [[ "$e" =~ $excluir ]] || continue
        [[ "$e" == *.lock ]] && continue

        if [ -d "$ruta" ]; then
            # Solo archivos: el mtime de un directorio cambia con cualquier
            # candado que se cree y se borre dentro, y daría versiones falsas.
            fecha=$(find "$ruta" -type f ! -name '*.lock' -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
            [ -n "$fecha" ] || continue
            fecha=$(date -d "@${fecha%.*}" +%Y%m%d)
            final="$e.$fecha.tar"; [ "$comp" = "zst" ] && final="$final.zst"
            bytes=$(du -sb "$ruta" | cut -f1)
        elif [ -f "$ruta" ]; then
            fecha=$(date -d "@$(stat -c %Y "$ruta")" +%Y%m%d)
            if [[ "$e" == *.* ]]; then final="${e%.*}.$fecha.${e##*.}"; else final="$e.$fecha"; fi
            bytes=$(stat -c %s "$ruta")
        else
            continue
        fi
        [ -e "$destdir/$final" ] && continue
        nuevas=$((nuevas + 1))

        if [ "$DRY_RUN" -eq 1 ]; then
            printf "  [verificar] %-52s %9s GB\n" "$destino/$final" "$(gb "$bytes")"
            TOTAL_PARTES=$((TOTAL_PARTES + 1)); TOTAL_BYTES=$((TOTAL_BYTES + bytes)); continue
        fi
        if ! cabe "$bytes"; then
            echo "  ❌ $serie $e: $(gb "$bytes") GB no caben dejando $RESERVA_GB GB libres"
            ERRORES=$((ERRORES + 1)); continue
        fi
        mkdir -p "$destdir"
        tmp="$destdir/.$final.tmp.$$"
        printf "  %-52s %9s GB… " "$destino/$final" "$(gb "$bytes")"
        if [ -d "$ruta" ]; then
            local opc=() lee=()
            mapfile -t opc < <(tar_comp "$comp")
            mapfile -t lee < <(tar_lee "$comp")
            (cd "$origen" && find "$e" | sort) > "$TMP/esperado"
            if tar "${opc[@]}" -C "$origen" -cf "$tmp" "$e" 2> "$TMP/tar.err" \
               && tar "${lee[@]}" -tf "$tmp" 2>/dev/null | sed 's|/$||' | sort > "$TMP/dentro" \
               && cmp -s "$TMP/dentro" "$TMP/esperado"; then
                cp "$TMP/esperado" "$destdir/.$final.idx.tmp.$$" \
                    && mv "$tmp" "$destdir/$final" \
                    && mv "$destdir/.$final.idx.tmp.$$" "$destdir/${final%.tar*}.idx" \
                    && echo "ok" \
                    || { echo "FALLÓ al ponerlo en su lugar"; rm -f "$tmp"; ERRORES=$((ERRORES + 1)); }
            else
                echo "FALLÓ o NO CUADRA"; sed 's/^/      /' "$TMP/tar.err" | head -5
                rm -f "$tmp"; ERRORES=$((ERRORES + 1)); continue
            fi
        else
            if cp --preserve=timestamps "$ruta" "$tmp" && cmp -s "$ruta" "$tmp" && mv "$tmp" "$destdir/$final"; then
                echo "ok"
            else
                echo "FALLÓ"; rm -f "$tmp"; ERRORES=$((ERRORES + 1)); continue
            fi
        fi
        TOTAL_PARTES=$((TOTAL_PARTES + 1)); TOTAL_BYTES=$((TOTAL_BYTES + bytes))
    done
    [ "$nuevas" -gt 0 ] || echo "  $serie: sin versiones nuevas"
}

# ------------------------------------------------------------------------------
while IFS=$'\t' read -r serie modo origen destino incluir excluir comp; do
    [[ -z "$serie" || "$serie" == \#* ]] && continue
    if [ -n "$SOLO" ] && [[ ",$SOLO," != *",$serie,"* ]]; then continue; fi
    echo "--- $serie ($modo): $origen → $RAIZ/$destino"
    case "$modo" in
        dia|dia_subdirs) serie_dia "$serie" "$modo" "$origen" "$destino" "$incluir" "$excluir" "$comp" ;;
        instantanea)     serie_instantanea "$serie" "$origen" "$destino" "$incluir" "$excluir" "$comp" ;;
        *) echo "  ❌ modo desconocido: $modo"; ERRORES=$((ERRORES + 1)) ;;
    esac
done < "$TSV"

DUR=$(( $(date +%s) - INICIO ))
echo "------------------------------------------------------------------------------"
printf "[%s] %s: %d partes, %d archivos, %s GB en %dm %02ds · errores: %d · libres en %s: %s GB\n" \
    "$(date '+%F %T')" "$( [ "$DRY_RUN" -eq 1 ] && echo 'Por archivar' || echo 'Archivado')" \
    "$TOTAL_PARTES" "$TOTAL_ARCHIVOS" "$(gb "$TOTAL_BYTES")" $((DUR / 60)) $((DUR % 60)) \
    "$ERRORES" "$MONTAJE" "$(libre_gb)"
[ "$ERRORES" -eq 0 ]
