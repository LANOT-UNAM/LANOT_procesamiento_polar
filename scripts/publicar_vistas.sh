#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Publicación de las vistas como galería web
# ==============================================================================
#
# vistas/ → una carpeta autocontenida, lista para copiar a un servidor web.
#
# Reproduce el árbol de categorías tal cual está en /data/output/jpss/vistas
# (dnb, rgb, atmos, …) y le agrega, por categoría, una página con las
# miniaturas; cada imagen lleva su ficha —producto, satélite, fecha, paleta— y
# un enlace para descargarla a tamaño completo.
#
# La carpeta se COPIA A MANO al servidor web, así que el resultado es portátil:
# copias reales de los JPG (nunca enlaces simbólicos, que no sobreviven al
# copiado), rutas relativas y ningún recurso externo. Un `scp -r` a cualquier
# docroot la deja funcionando, y `file://` sirve para revisarla antes.
#
# El trabajo lo hace publicar_vistas.py DENTRO del contenedor de Polar2Grid,
# que es donde viven las tres cosas que hacen falta: Pillow para las
# miniaturas, `metadata` para fichar cada imagen por su nombre y
# `colorpalettetable` para leer el rango de la paleta. Nada que instalar en el
# host, y —lo que importa— el pie de foto sale de la MISMA tabla product_map y
# del MISMO CPT con los que se rotuló y coloreó la imagen, así que el HTML y el
# JPG no se pueden contradecir.
#
# No lleva marcador .done, a diferencia de los doce run_*.sh: esto no es una
# etapa de la cadena sino una herramienta de mano, y republicar es el caso
# normal —se adelanta la galería con lo que haya y se rehace cuando termina la
# pasada—, no la excepción.
#
# Uso:
#   ./publicar_vistas.sh                 # las 2 pasadas más recientes
#   ./publicar_vistas.sh --dry-run       # qué publicaría, sin escribir nada
#   ./publicar_vistas.sh --force         # rehace un destino que ya existe
#   ./publicar_vistas.sh --ultimas 3
#   ./publicar_vistas.sh --pasada 20260817_08
#
# Variables de entorno (para pruebas o rutas alternas):
#   PUB_VISTAS       Raíz de vistas    (def. /data/output/jpss/vistas)
#   PUB_DESTINO      Carpeta de salida (def. /data/publicacion/vistas_AAAAMMDD)
#   PUB_CONTAINER    Imagen .sif       (def. …/polar2grid_v3.2-mapdrawer.sif)
#   PUB_COLORTABLES  Paletas del host  (def. /usr/local/share/lanot/colortables)
#   PUB_MINIATURA    Lado de miniatura (def. 480)
#   PUB_HUECO_MIN    Corte entre pasadas, en minutos (def. 45)
#   PUB_TZ           Horas respecto de UTC para la hora local (def. -6)
#   PUB_LOG_BASE     Raíz de logs      (def. /var/log/lanot/polares)
#   LOCK_FILE        Candado de la cadena (def. /data/tmp/lanot_polares.lock)
#
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SIF_P2G="${PUB_CONTAINER:-/opt/containers/polar2grid_v3.2-mapdrawer.sif}"
VISTAS="${PUB_VISTAS:-/data/output/jpss/vistas}"
COLORTABLES="${PUB_COLORTABLES:-/usr/local/share/lanot/colortables}"
MINIATURA="${PUB_MINIATURA:-480}"
HUECO_MIN="${PUB_HUECO_MIN:-45}"
TZ_OFFSET="${PUB_TZ:--6}"
LOG_DIR="${PUB_LOG_BASE:-/var/log/lanot/polares}/publicacion"

# El mismo candado y el mismo valor por omisión que procesar_pasada.sh:42, para
# que un ambiente de prueba que lo redefina siga siendo coherente.
LOCK_FILE="${LOCK_FILE:-/data/tmp/lanot_polares.lock}"

DESTINO="${PUB_DESTINO:-}"
FORCE=0
DRY_RUN=0
ARGS_PY=()

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0                     Publica las 2 pasadas más recientes de $VISTAS
  $0 --dry-run           Enseña qué publicaría y no escribe nada
  $0 --force             Rehace el destino aunque ya exista

Opciones:
  -n, --dry-run     No escribe nada; tampoco exige que la cadena esté quieta
  -f, --force       Rehace un destino existente y salta el candado de la cadena
  -d, --destino DIR Carpeta de salida (def. /data/publicacion/vistas_AAAAMMDD)
  -h, --help        Muestra esta ayuda

Se reenvían a publicar_vistas.py, que las documenta con --help:
  --ultimas N       Cuántas pasadas, de la más reciente hacia atrás (def. 2)
  --pasada AAAAMMDD_HH  Fija una pasada por prefijo de sello; repetible
  --hueco-min N     Minutos de hueco que separan dos pasadas (def. $HUECO_MIN)
  --miniatura N     Lado mayor de las miniaturas (def. $MINIATURA)
  --tz-offset H     Horas respecto de UTC (def. $TZ_OFFSET)
EOF
}

# La fecha del JPG más reciente, para nombrar el destino. Sale del sello que
# Polar2Grid pone en el nombre y no del mtime: el nombre dice cuándo se observó
# la escena, que es lo que identifica a la galería; el mtime, cuándo se
# renderizó, que cambia si se reprocesa.
fecha_mas_reciente() {
    find "$VISTAS" -mindepth 2 -maxdepth 2 -name '*.jpg' -printf '%f\n' 2>/dev/null |
        grep -oE '_[0-9]{8}_[0-9]{6}_' | tr -d '_' | sort -r | head -1 | cut -c1-8
}

formato_duracion() {
    local s="$1"
    if [ "$s" -ge 3600 ]; then
        printf '%dh %dm %ds' $((s / 3600)) $(((s % 3600) / 60)) $((s % 60))
    elif [ "$s" -ge 60 ]; then
        printf '%dm %ds' $((s / 60)) $((s % 60))
    else
        printf '%ds' "$s"
    fi
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================
# Lo que no reconozca esta envoltura se reenvía tal cual al .py, para no tener
# que duplicar aquí cada bandera suya.

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)    uso; exit 0 ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -f|--force)   FORCE=1; shift ;;
        -d|--destino)
            [ $# -ge 2 ] || { echo "ERROR: --destino necesita un directorio" >&2; exit 1; }
            DESTINO="$2"; shift 2 ;;
        *) ARGS_PY+=("$1"); shift ;;
    esac
done

# ==============================================================================
# VALIDACIÓN
# ==============================================================================

if [ ! -d "$VISTAS" ]; then
    echo "ERROR: No existe el árbol de vistas: $VISTAS" >&2
    exit 1
fi

if [ ! -f "$SIF_P2G" ]; then
    echo "ERROR: No se encuentra el contenedor: $SIF_P2G" >&2
    echo "       Se puede apuntar a otro con PUB_CONTAINER." >&2
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/publicar_vistas.py" ]; then
    echo "ERROR: Falta $SCRIPT_DIR/publicar_vistas.py, que es quien hace el trabajo." >&2
    exit 1
fi

# El candado de la cadena. NO basta con que el archivo exista —procesar_pasada.sh
# lo toma con `flock` y el archivo queda ahí para siempre—, así que la
# comprobación es intentar tomarlo. Y se conserva tomado durante la publicación,
# que además impide que arranque una pasada a media copia.
#
# Copiar mientras run_polar2grid_edr.sh todavía escribe JPG produce imágenes
# truncadas que se publican sin que nada falle, que es el peor desenlace
# posible: se ven mal y nadie se entera.
# OJO con la forma: `exec 9>"$LOCK_FILE" 2>/dev/null` sería un error grave, y
# silencioso. `exec` sin orden aplica sus redirecciones AL SHELL ENTERO, así que
# ese 2>/dev/null se quedaría puesto y todos los mensajes de error posteriores
# se irían al vacío: el script seguiría devolviendo el código correcto pero sin
# decir nunca por qué falló. Por eso el descarte de stderr no va aquí, sino que
# se comprueba antes si el directorio del candado se puede escribir.
if [ "$DRY_RUN" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
    DIR_LOCK="$(dirname "$LOCK_FILE")"
    mkdir -p "$DIR_LOCK" 2>/dev/null || true
    if [ -w "$LOCK_FILE" ] || [ -w "$DIR_LOCK" ]; then
        exec 9>"$LOCK_FILE"
        if ! flock -n 9; then
            echo "ERROR: Hay una pasada en curso (candado: $LOCK_FILE)." >&2
            echo "       Publicar ahora copiaría JPG a medio escribir. Espera a que" >&2
            echo "       termine, o usa --dry-run para ver qué hay hasta ahora." >&2
            exit 1
        fi
    fi
fi

# ==============================================================================
# DESTINO
# ==============================================================================

if [ -z "$DESTINO" ]; then
    FECHA=$(fecha_mas_reciente || true)
    if [ -z "$FECHA" ]; then
        echo "ERROR: No hay ningún JPG con sello temporal en $VISTAS," >&2
        echo "       así que no se puede deducir el nombre del destino." >&2
        exit 1
    fi
    DESTINO="/data/publicacion/vistas_$FECHA"
fi

if [ "$DRY_RUN" -eq 0 ] && [ -e "$DESTINO" ]; then
    if [ "$FORCE" -eq 0 ]; then
        echo "ERROR: El destino ya existe: $DESTINO" >&2
        echo "       Con --force se borra y se rehace entero." >&2
        exit 1
    fi
    # Se rehace entero y no se parcha: un destino con miniaturas viejas junto a
    # fichas nuevas es peor que uno viejo y coherente, y rehacer las miniaturas
    # cuesta segundos.
    echo "--- El destino existía; se rehace entero (--force) ---"
    rm -rf "${DESTINO:?}"
fi

# ==============================================================================
# PUBLICACIÓN
# ==============================================================================

INICIO=$(date +%s)
SELLO=$(date '+%Y%m%d_%H%M%S')

if [ "$DRY_RUN" -eq 1 ]; then
    # Sin escribir nada no hay log que escribir: la salida va a la terminal, que
    # es donde la está mirando quien lo corrió.
    exec 2>&1
    apptainer exec \
        --bind "$VISTAS:/vistas:ro" \
        --bind "$SCRIPT_DIR:/publicador:ro" \
        "$SIF_P2G" \
        /opt/lanot-tools/venv/bin/python /publicador/publicar_vistas.py \
        --vistas /vistas \
        --dry-run --hueco-min "$HUECO_MIN" --tz-offset "$TZ_OFFSET" "${ARGS_PY[@]+"${ARGS_PY[@]}"}"
    exit $?
fi

mkdir -p "$LOG_DIR" "$DESTINO"
LOG_FILE="$LOG_DIR/${SELLO}_publicar_$(basename "$DESTINO").log"

echo "=============================================="  | tee -a "$LOG_FILE"
echo " Publicación de vistas — $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo " Vistas:  $VISTAS"                                | tee -a "$LOG_FILE"
echo " Destino: $DESTINO"                               | tee -a "$LOG_FILE"
echo "=============================================="  | tee -a "$LOG_FILE"

# Las paletas viven dentro de la imagen: install.sh de LANOT_tools las copia al
# compilar. Si el host tiene el directorio, se monta encima. Aquí no es un
# detalle cosmético como en los renderizadores: SIN ESTE MONTAJE la nota de la
# paleta se leería de las CPT horneadas en el .sif, que pueden estar atrás de
# las del host —los rangos corregidos el 2026-08-17 se arreglaron sin
# recompilar, justamente porque van montadas—, y la ficha anunciaría un rango
# distinto del que tiene la barra de color impresa en la imagen.
BIND_CPT=()
if [ -d "$COLORTABLES" ]; then
    BIND_CPT=(--bind "$COLORTABLES:/usr/local/share/lanot/colortables:ro")
else
    echo "ℹ  El host no tiene $COLORTABLES; se usan las CPT del contenedor." | tee -a "$LOG_FILE"
fi

# Se invoca el intérprete y el guion directo, sin /bin/bash -c: aquí no hace
# falta hacer `source` de ningún cspp_env.sh ni exportar CSPP_*, así que no hay
# cadena entrecomillada que escapar y la trampa de las comillas no aplica.
#
# Las rutas del contenedor van EXPLÍCITAS aunque coincidan con los valores por
# omisión del .py. Así el guion no depende de que el bind exista, que es lo que
# permite probar el flujo entero con un `apptainer` simulado —uno que traduzca
# los binds a rutas del host y ejecute el python de verdad— sin tocar /data.
CODIGO=0
apptainer exec \
    --bind "$VISTAS:/vistas:ro" \
    --bind "$DESTINO:/publicacion" \
    --bind "$SCRIPT_DIR:/publicador:ro" \
    "${BIND_CPT[@]+"${BIND_CPT[@]}"}" \
    "$SIF_P2G" \
    /opt/lanot-tools/venv/bin/python /publicador/publicar_vistas.py \
    --vistas /vistas --destino /publicacion \
    --colortables /usr/local/share/lanot/colortables \
    --hueco-min "$HUECO_MIN" --tz-offset "$TZ_OFFSET" --miniatura "$MINIATURA" \
    "${ARGS_PY[@]+"${ARGS_PY[@]}"}" 2>&1 | tee -a "$LOG_FILE" || CODIGO=$?

# ==============================================================================
# RESUMEN
# ==============================================================================

DURACION=$(formato_duracion $(($(date +%s) - INICIO)))

if [ "$CODIGO" -ne 0 ]; then
    echo "❌ FALLÓ la publicación (código $CODIGO). Log: $LOG_FILE" | tee -a "$LOG_FILE"
    exit "$CODIGO"
fi

JPG=$(find "$DESTINO" -mindepth 2 -maxdepth 2 -name '*.jpg' | wc -l)
CATEGORIAS=$(find "$DESTINO" -mindepth 1 -maxdepth 1 -type d | wc -l)
PESO=$(du -sh "$DESTINO" 2>/dev/null | cut -f1)

echo "" | tee -a "$LOG_FILE"
echo "✅ ÉXITO: $JPG vistas en $CATEGORIAS categorías ($PESO) en $DURACION" | tee -a "$LOG_FILE"
echo "   $DESTINO" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Una pasada nocturna deja menos vistas que una diurna y eso NO es un fallo del
# publicador: sin sol no hay true_color ni false_color utilizables, LSR falla
# entero —no hay reflectancia de superficie— y con él se van NDVI y EVI. Decirlo
# aquí evita que la diferencia de conteos se lea como archivos perdidos.
echo "ℹ  Si una de las pasadas es nocturna, traerá menos vistas: sin sol no hay" | tee -a "$LOG_FILE"
echo "   RGB ni productos de LSR (NDVI, EVI). Es lo esperado, no un fallo."      | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "   Para revisarla antes de copiarla:" | tee -a "$LOG_FILE"
echo "     cd $DESTINO && python3 -m http.server 8080" | tee -a "$LOG_FILE"
echo "   Log: $LOG_FILE" | tee -a "$LOG_FILE"
