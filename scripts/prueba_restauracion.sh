#!/bin/bash
# ==============================================================================
# prueba_restauracion.sh — regenera una pasada vieja desde el archivo de /depot,
# en un árbol aislado, y dice si alcanzó con lo archivado.
#
# Es la prueba del criterio de config/archivo.tsv: que crudos + ancillary +
# software bastan para volver a producir cualquier producto
# (docs/estado_y_pendientes.md, "2026-11-21: el archivo en /depot"). Tiene dos
# modos, según de dónde salga el ancillary:
#
#   --anc depot    (def.) Todo de /depot: el ancillary del día de la pasada y
#                  del anterior (ciclos de GFS de la víspera), más la instantánea
#                  de lo fijo (LUTs, leapsec, cachés de ACSPO). Los cachés se
#                  listan antes y después: si un driver bajó algo, el archivo NO
#                  alcanzó, y la prueba falla aunque la pasada salga bien.
#   --anc externo  Para fechas de antes de archivar.sh (Polo, Rachel): cachés
#                  vacíos y que cada driver baje lo suyo. SSEC conserva el
#                  ancillary histórico de CSPP (jpssdb.ssec.wisc.edu, cspp_v_4_0
#                  para SDR y cspp_v_2_0 para ATMOS y HEAP; verificado el
#                  2026-11-21 para el 28 de septiembre). Lo fijo sale del
#                  /data/ancillary de hoy: las LUTs se acumulan y CSPP elige por
#                  fecha de validez. Prueba que la pasada se puede reconstruir;
#                  lo que se descargó queda contado en el informe.
#
# Los crudos salen siempre de /depot, con restaurar.sh: de los tar de
# archivar.sh o, si son de antes, de los .tgz de stratus (listarlos tarda).
# La pasada corre con procesar_pasada.sh completo, en un árbol bajo /data/tmp
# armado con arbol_aislado.sh, con su propio candado: el de producción no se
# toma, pero se espera a que esté libre para no competir por la RAM (ATMOS).
#
# Tiene que correr como lanotadm: ACSPO monta acspo_wisdom y acspo_histogram de
# producción con ruta fija, y HEAP toma el candado junto a su bundle. Desde
# /opt/lanot/polares, como prueba_dos_turnos.sh, fuera de los racimos de JPSS
# (07–09 y 19–21 UTC). Por ejemplo, Polo en NOAA-21 y NOAA-20:
#
#   echo '/opt/lanot/polares/scripts/prueba_restauracion.sh --anc externo \
#         -f 2026-09-28 chain1-10_pass10 chain2-9_pass19' | sudo -u lanotadm at 23:30
#
# El informe queda en <base>/informe.txt; el árbol, para inspeccionarlo.
#
# Uso:
#   prueba_restauracion.sh [opciones] -f AAAA-MM-DD CRUDO [CRUDO…]
#
#   CRUDO   nombre en el buzón sin el sello de recepción: chain1-10_pass10
#
# Opciones:
#   -f, --fecha AAAA-MM-DD  Día UTC de la pasada (obligatorio)
#       --anc depot|externo De dónde sale el ancillary (def. depot)
#   -b, --base DIR          Árbol (def. /data/tmp/prueba_restauracion_<sello>)
#   -e, --espera MIN        Cuánto esperar a una pasada de producción (def. 60)
#       --sin-comparar      No comparar con los productos originales
#   -h, --help
#
# Variables de entorno:
#   LOCK_PRODUCCION    (def. /data/tmp/lanot_polares.lock)
#   SALIDA_PRODUCCION  Para comparar y detectar fugas (def. /data/output/jpss)
#   ANC_PRODUCCION     Lo fijo del modo externo (def. /data/ancillary)
#   PRUEBA_USUARIO     Usuario exigido (def. lanotadm; vacío para no exigir)
#   PRUEBA_MIN_GB      Espacio libre mínimo en /data/tmp (def. 150)
#   ARCHIVO_RAIZ       (def. /depot/polar)
#
# Sale en 0 si todas las pasadas terminan bien, nada cayó en producción y (modo
# depot) no se bajó nada; en 1 si no; en 2 si no pudo empezar.
# ==============================================================================

set -uo pipefail
export TZ=UTC LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_PRODUCCION="${LOCK_PRODUCCION:-/data/tmp/lanot_polares.lock}"
SALIDA_PRODUCCION="${SALIDA_PRODUCCION:-/data/output/jpss}"
ANC_PRODUCCION="${ANC_PRODUCCION:-/data/ancillary}"
PRUEBA_USUARIO="${PRUEBA_USUARIO-lanotadm}"
PRUEBA_MIN_GB="${PRUEBA_MIN_GB:-150}"
export ARCHIVO_RAIZ="${ARCHIVO_RAIZ:-/depot/polar}"

# Lo que el ancillary tiene de fijo (archivo.tsv, fila ancillary-fijo)
FIJO="incoming_luts common acspo_wisdom acspo_histogram SDR_4_1_DB"

FECHA=""; MODO_ANC="depot"; BASE=""; ESPERA_MIN=60; COMPARAR=1
CRUDOS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -f|--fecha)   FECHA="${2:?}"; shift 2 ;;
        --anc)        MODO_ANC="${2:?}"; shift 2 ;;
        -b|--base)    BASE="${2:?}"; shift 2 ;;
        -e|--espera)  ESPERA_MIN="${2:?}"; shift 2 ;;
        --sin-comparar) COMPARAR=0; shift ;;
        -h|--help)    sed -n '3,63p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)           echo "Opción desconocida: $1" >&2; exit 2 ;;
        *)            CRUDOS+=("$1"); shift ;;
    esac
done

fallo_inicio() { echo "❌ $*" >&2; exit 2; }
[ -n "$FECHA" ] || fallo_inicio "Falta --fecha"
date -d "$FECHA" >/dev/null 2>&1 || fallo_inicio "Fecha inválida: $FECHA"
[ "${#CRUDOS[@]}" -gt 0 ] || fallo_inicio "Falta al menos un crudo"
case "$MODO_ANC" in depot|externo) ;; *) fallo_inicio "--anc es depot o externo" ;; esac
if [ -n "$PRUEBA_USUARIO" ] && [ "$(id -un)" != "$PRUEBA_USUARIO" ]; then
    fallo_inicio "Hay que correrla como $PRUEBA_USUARIO (ver la cabecera)"
fi
for s in restaurar.sh arbol_aislado.sh procesar_pasada.sh; do
    [ -f "$SCRIPT_DIR/$s" ] || fallo_inicio "Falta $SCRIPT_DIR/$s"
done
mountpoint -q /depot || fallo_inicio "/depot no está montado"

SELLO=$(date +%Y%m%dT%H%M%SZ)
BASE="${BASE:-/data/tmp/prueba_restauracion_$SELLO}"
mkdir -p "$BASE" || fallo_inicio "No se pudo crear $BASE"
libre=$(df -P --block-size=1G "$BASE" | awk 'NR==2 {print $4}')
[ "$libre" -ge "$PRUEBA_MIN_GB" ] || fallo_inicio "Solo $libre GB libres en $BASE (mínimo $PRUEBA_MIN_GB)"

INFORME="$BASE/informe.txt"
exec > >(tee -a "$INFORME") 2>&1

# shellcheck source=arbol_aislado.sh
source "$SCRIPT_DIR/arbol_aislado.sh"

h=$(date +%H)
case "$h" in 07|08|09|19|20|21) echo "⚠ Son las $h UTC, en un racimo de JPSS: la pasada de producción tiene prioridad y esto va a esperar o a estorbar." ;; esac

echo "=============================================================================="
echo "PRUEBA DE RESTAURACIÓN · $(date '+%F %T') UTC"
echo "  Pasada:     ${CRUDOS[*]} del $FECHA"
echo "  Ancillary:  $MODO_ANC"
echo "  Árbol:      $BASE"
echo "  Código:     $SCRIPT_DIR ($(head -1 "$SCRIPT_DIR/../VERSION" 2>/dev/null || git -C "$SCRIPT_DIR" log --oneline -1 2>/dev/null))"
echo "=============================================================================="

# ------------------------------------------------------------------------------
echo; echo "--- 1. Crudos, de $ARCHIVO_RAIZ/raw"
# Un día por carpeta: TeraScan recicla los nombres (chain1-10_pass10 vuelve a
# salir días después), y extraer dos días al mismo lugar dejaría el segundo
# encima del primero. Se queda el primero cuyo mtime caiga en la fecha pedida
# (con media hora de gracia: una pasada que empieza a las 23:50 cierra al otro día).
SIG=$(date -d "$FECHA +1 day" +%F)
patron="^(\./)?($(IFS='|'; echo "${CRUDOS[*]}"))(_[0-9]{8}T[0-9]{6})?$"
for d in "$FECHA" "$SIG"; do
    "$SCRIPT_DIR/restaurar.sh" -s raw -d "$d" -p "$patron" -o "$BASE/raw/$d"
    [ $? -le 1 ] || true     # 3 = nada ese día, que es normal
done
RAWS=()
for c in "${CRUDOS[@]}"; do
    f=$(find "$BASE/raw" -type f \( -name "$c" -o -name "${c}_*" \) ! -name '.listado-*' \
          -newermt "$FECHA 00:00:00" ! -newermt "$SIG 00:30:00" | sort | head -1)
    [ -n "$f" ] || fallo_inicio "No apareció $c con fecha $FECHA en los crudos del $FECHA y el $SIG"
    echo "  $c → $f ($(du -h "$f" | cut -f1), mtime $(date -r "$f" '+%F %T') UTC)"
    RAWS+=("$f")
done

# ------------------------------------------------------------------------------
echo; echo "--- 2. Ancillary ($MODO_ANC)"
ANC="$BASE/anc"
mkdir -p "$ANC"/{atmos,heap,acspo,mirs,active_fire_cache}
if [ "$MODO_ANC" = "depot" ]; then
    ANT=$(date -d "$FECHA -1 day" +%F)
    "$SCRIPT_DIR/restaurar.sh" -s ancillary -d "$ANT" -a "$SIG" -o "$ANC" \
        || fallo_inicio "No se pudo restaurar el ancillary del $ANT al $SIG"
    # La versión más reciente de lo fijo: las LUTs se acumulan, y CSPP elige
    # por fecha de validez, no por la de la instantánea.
    "$SCRIPT_DIR/restaurar.sh" -s software/ancillary --instantanea "$(date +%F)" -o "$ANC" \
        || fallo_inicio "No hay instantánea de software/ancillary (la fila ancillary-fijo de archivo.tsv tiene que haber corrido)"
else
    for d in $FIJO; do
        [ -e "$ANC_PRODUCCION/$d" ] && cp -a "$ANC_PRODUCCION/$d" "$ANC/"
    done
    echo "  Cachés vacíos; lo fijo, copiado de $ANC_PRODUCCION ($FIJO)"
fi
(cd "$ANC" && find . -type f | sort) > "$BASE/anc_antes.txt"
echo "  $(wc -l < "$BASE/anc_antes.txt") archivos, $(du -sh "$ANC" | cut -f1)"

# ------------------------------------------------------------------------------
echo; echo "--- 3. Esperando a que no haya pasada de producción"
i=0
until flock -n "$LOCK_PRODUCCION" true 2>/dev/null; do
    [ "$i" -lt "$ESPERA_MIN" ] || { echo "❌ La pasada de producción sigue tras $ESPERA_MIN min"; exit 2; }
    [ "$i" -gt 0 ] || echo "  Hay una en curso; esperando (hasta $ESPERA_MIN min)…"
    sleep 60; i=$((i + 1))
done
echo "  Libre."

# ------------------------------------------------------------------------------
echo; echo "--- 4. Procesando"
touch "$BASE/inicio"
RESULTADOS=()
for raw in "${RAWS[@]}"; do
    t0=$(date +%s)
    nombre=$(basename "$raw")
    echo "  $nombre: procesar_pasada.sh… (salida en $BASE/$nombre.out)"
    rc=0
    (
        exportar_arbol "$BASE"
        export SDR_DYNAMIC="$ANC" ATMOS_CACHE="$ANC/atmos" HEAP_CACHE="$ANC/heap" \
               ACSPO_CACHE="$ANC/acspo" MIRS_CACHE="$ANC/mirs" FIRE_CACHE="$ANC/active_fire_cache"
        export LOCK_FILE="$BASE/prueba.lock" TMPDIR="$BASE/tmp"
        [ "$MODO_ANC" = "externo" ] && export ATMOS_DESCARGAR=1
        cd /
        exec "$SCRIPT_DIR/procesar_pasada.sh" "$raw"
    ) > "$BASE/$nombre.out" 2>&1 || rc=$?
    dur=$(( $(date +%s) - t0 ))
    # procesar_pasada.sh sale en 0 aunque fallen etapas: el veredicto está en las
    # últimas líneas de su resumen, no en el código (así pasó por buena la prueba
    # del 2026-11-21 con ATMOS caído)
    resumen=$(grep -h -E "^  (Todas las etapas terminaron bien|Etapas con fallo|Etapas pospuestas)" \
                "$BASE"/logs/cadena/*"$nombre"*.log 2>/dev/null | sed 's/^ *//' | paste -sd ';' -)
    RESULTADOS+=("$nombre|$rc|$dur|$resumen")
    printf "  %s: código %d en %dm %02ds\n    %s\n" "$nombre" "$rc" $((dur / 60)) $((dur % 60)) "${resumen:-(sin resumen en el log de cadena)}"
done

# ------------------------------------------------------------------------------
echo; echo "--- 5. Resultados"
FALLA=0
for r in "${RESULTADOS[@]}"; do
    IFS='|' read -r n rc dur res <<< "$r"
    [ "$rc" -eq 0 ] || FALLA=1
    [[ "$res" == "Todas las etapas terminaron bien." ]] || FALLA=1
done

echo "  Productos en el árbol:"
for d in "$BASE"/output/level1/* "$BASE"/output/level2/* "$BASE"/output/vistas/*; do
    [ -d "$d" ] || continue
    printf "    %-22s %5d archivos\n" "${d#$BASE/output/}" "$(find "$d" -type f | wc -l)"
done

# Lo que los drivers bajaron
(cd "$ANC" && find . -type f | sort) > "$BASE/anc_despues.txt"
comm -13 "$BASE/anc_antes.txt" "$BASE/anc_despues.txt" | grep -v -E '\.lock$' > "$BASE/descargado.txt"
ndesc=$(wc -l < "$BASE/descargado.txt")
echo "  Ancillary descargado durante la prueba: $ndesc archivos"
sed 's/^/    /' "$BASE/descargado.txt" | head -15
if [ "$MODO_ANC" = "depot" ] && [ "$ndesc" -gt 0 ]; then
    echo "  ❌ En modo depot no debió bajarse nada: el archivo NO alcanzó para esta pasada"
    FALLA=1
fi

# Fugas: algo con el sello de estas pasadas que haya caído en producción
mapfile -t sellos < <(find "$BASE/output/level1" -type f -name '*_d????????_t???????_*' 2>/dev/null |
    sed -E 's/.*_d([0-9]{8})_t([0-9]{4}).*/\1 \2/' | sort -u)
fugas=0
for s in "${sellos[@]}"; do
    read -r d hm <<< "$s"
    n=$(find "$SALIDA_PRODUCCION" -newer "$BASE/inicio" -type f \
          \( -name "*_d${d}_t${hm}*" -o -name "*_s${d}${hm}*" \) 2>/dev/null | wc -l)
    fugas=$((fugas + n))
done
echo "  Fugas a $SALIDA_PRODUCCION: $fugas"
[ "$fugas" -eq 0 ] || FALLA=1

# Comparación con los originales, si producción todavía los tiene (14 días)
if [ "$COMPARAR" -eq 1 ] && command -v h5diff >/dev/null; then
    iguales=0; distintos=0; sin_original=0
    : > "$BASE/comparacion.txt"
    while IFS= read -r f; do
        rel=${f#$BASE/output/}; dir=$(dirname "$rel"); b=$(basename "$f")
        # El campo de creación (_c…) cambia en cada corrida: se compara por el resto
        clave=$(sed -E 's/_c[0-9]{8,}[^_.]*//' <<< "$b")
        orig=$(find "$SALIDA_PRODUCCION/$dir" -maxdepth 1 -type f -name "$(sed -E 's/_c[0-9]{8,}[^_.]*/_c*/' <<< "$b")" 2>/dev/null | head -1)
        if [ -z "$orig" ]; then sin_original=$((sin_original + 1)); continue; fi
        # h5diff sale en 1 si hay diferencias; su "not comparable" de NetCDF no cuenta
        if h5diff -q "$f" "$orig" >/dev/null 2>&1 || ! h5diff "$f" "$orig" 2>/dev/null | grep -q -E "differences found"; then
            iguales=$((iguales + 1))
        else
            distintos=$((distintos + 1)); echo "distinto: $rel ↔ $orig" >> "$BASE/comparacion.txt"
        fi
    done < <(find "$BASE/output/level2" -type f \( -name '*.nc' -o -name '*.h5' \) | sort)
    echo "  Contra producción (level2): $iguales iguales, $distintos distintos, $sin_original sin original (retención)"
    [ "$distintos" -eq 0 ] || sed 's/^/    /' "$BASE/comparacion.txt" | head -10
fi

echo "=============================================================================="
if [ "$FALLA" -eq 0 ]; then
    echo "✅ RESTAURACIÓN OK · $(date '+%F %T') UTC · árbol en $BASE"
else
    echo "❌ RESTAURACIÓN CON FALLAS · $(date '+%F %T') UTC · árbol en $BASE"
fi
echo "=============================================================================="
exit "$FALLA"
