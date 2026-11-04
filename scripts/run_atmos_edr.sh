#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Generación Nivel 2 Atmosphere EDR v1.0
# ==============================================================================
#
# Level 1 (SDR de VIIRS) → Level 2 atmosférico (JRR-*.nc)
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue procesada con éxito, avisa y no hace nada. Una pasada se identifica
# por satélite, fecha y hora de inicio (p. ej. j01_d20260811_t194733), datos que
# vienen en el nombre de los propios SDR (ver pasadas.sh).
#
# Requiere todas las bandas de la pasada (SVM*, SVI*, SVDNB, GDNBO, GITCO,
# GMTCO), tal como las deja run_sdr.sh. Se enlazan en un directorio de staging
# para procesar una pasada a la vez, aunque level1 tenga varias acumuladas.
#
# Ancillary dinámico: primero solo el caché (bandera -l), que precarga
# update_atmos_ancillary.sh desde cron. Si la corrida queda incompleta por falta
# de ancillary, se descarta y se repite dejando que CSPP baje lo que falte; si
# aun así falta, la etapa falla SIN marcador y sin productos a medias, para que
# barrer_pendientes.sh la retome. --download se salta el primer intento. El
# caché es EXCLUSIVO de ATMOS: ~6 GB diarios sueltos en la raíz, sin
# subdirectorios, podados por delete_old_anc.sh. No compartirlo con el de CSPP
# SDR, que sí usa subdirectorios por día (2026_01_02_002/).
#
# Uso:
#   ./run_atmos_edr.sh                 # la pasada más reciente pendiente
#   ./run_atmos_edr.sh --download      # descarga sin probar antes el caché
#   ./run_atmos_edr.sh --force         # reprocesa aunque ya tenga marcador
#
# Antes de todo eso, si el ciclo del GFS que cubre la pasada todavía no puede
# estar publicado, no se intenta: sale en 75 (EX_TEMPFAIL) sin tocar nada, y
# barrer_pendientes.sh la retoma una hora después. Es el caso de cada mañana:
# una pasada que acaba después de las 09 UTC necesita el ciclo 06Z, que sale
# hacia las 09:30, y la cadena la procesa a los pocos minutos de recibirla.
# Intentarla de todos modos costaba dos corridas de ATMOS, un fallo en el
# resumen y un atmos_work_* (más un lsr_work_*) conservados sin nada que ver.
#
# Variables de entorno (para pruebas o rutas alternas):
#   ATMOS_SDR_IN     Entrada Level 1  (def. /data/output/jpss/level1/viirs)
#   ATMOS_OUT        Salida Level 2   (def. /data/output/jpss/level2/atmos)
#   ATMOS_STATE_DIR  Marcadores .done (def. /data/output/jpss/state/cspp-atmos)
#   ATMOS_CACHE      Caché dinámico   (def. /data/ancillary/atmos)
#   ATMOS_STATIC     Ancillary fijo   (def. /data/opt/CSPP_ATMOS_1_0/anc/static)
#   ATMOS_CONTAINER  Imagen .sif      (def. /opt/containers/cspp_atmos_edr_v1.0.sif)
#   ATMOS_WORK_BASE  Raíz de trabajo  (def. /data/tmp)
#   ATMOS_LOG_BASE   Raíz de logs     (def. /var/log/lanot/polares)
#   ATMOS_GFS_LATENCIA_MIN  Desde el inicio de un ciclo del GFS hasta que se da
#                    por publicado, si no está en el caché (def. 225; 0 desactiva
#                    la espera)
#
# ==============================================================================

set -euo pipefail

SIF_ATMOS="${ATMOS_CONTAINER:-/opt/containers/cspp_atmos_edr_v1.0.sif}"

HOST_STATIC="${ATMOS_STATIC:-/data/opt/CSPP_ATMOS_1_0/anc/static}"
HOST_CACHE="${ATMOS_CACHE:-/data/ancillary/atmos}"
HOST_SDR_IN="${ATMOS_SDR_IN:-/data/output/jpss/level1/viirs}"
HOST_EDR_OUT="${ATMOS_OUT:-/data/output/jpss/level2/atmos}"
STATE_DIR="${ATMOS_STATE_DIR:-/data/output/jpss/state/cspp-atmos}"

WORK_BASE="${ATMOS_WORK_BASE:-/data/tmp}"
LOG_DIR="${ATMOS_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

CORES="${SLURM_CPUS_PER_TASK:-20}"
GFS_LATENCIA_MIN="${ATMOS_GFS_LATENCIA_MIN:-225}"
CODIGO_POSPUESTO=75

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0                Procesa la pasada más reciente de $HOST_SDR_IN
  $0 --download     Permite descargar ancillary dinámico al vuelo
  $0 --force        Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force     Ignora el marcador de procesado
  -p, --pasada    Pasada concreta en vez de la más reciente: la clave completa
                  (j01_d20260813_t191402) o cualquier trozo que la identifique
      --download  Descarga desde el primer intento, sin probar antes el caché
  -h, --help      Muestra esta ayuda

Pasadas disponibles en $HOST_SDR_IN:
$(listar_pasadas "$HOST_SDR_IN" GMTCO 2>/dev/null | cut -d' ' -f1 | sed 's/^/  /' || true)
EOF
}

# Qué es una pasada y cómo se elige: por tiempo, no por órbita (ver pasadas.sh).
# Fija CLAVE, SAT, FECHA y la ventana VENTANA_INI – VENTANA_FIN.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/pasadas.sh"

# gfs_pendiente: ¿falta un ciclo del GFS que todavía no puede estar publicado?
#
# Cada gránulo necesita el GFS válido a las horas sinópticas (múltiplos de 3)
# que lo encierran, y atmos-anc solo baja los pronósticos f003, f006 y f009 de
# cada ciclo (00, 06, 12, 18Z). Una hora válida V la cubren, entonces:
#   V = 06, 12, 18, 00  → el ciclo de 6 h antes (f006)
#   V = 03, 09, 15, 21  → el de 3 h antes (f003) o el de 9 h antes (f009)
# Un candidato sirve si su archivo ya está en el caché, o si ya pasó
# GFS_LATENCIA_MIN desde que arrancó el ciclo: entonces está publicado y el
# segundo intento, descargando, lo trae. Si para alguna V ningún candidato
# sirve, escribe en FALTA_GFS los ciclos que se esperan y devuelve 0.
FALTA_GFS=""
gfs_pendiente() {
    local ahora ini fin v h c f dia hh cubierta esperados
    [ "$GFS_LATENCIA_MIN" -gt 0 ] || return 1
    ahora=$(date -u +%s)
    ini=$(date -u -d "${VENTANA_INI:0:8} ${VENTANA_INI:8:2}:${VENTANA_INI:10:2}:${VENTANA_INI:12:2}" +%s)
    fin=$(date -u -d "${VENTANA_FIN:0:8} ${VENTANA_FIN:8:2}:${VENTANA_FIN:10:2}:${VENTANA_FIN:12:2}" +%s)
    FALTA_GFS=""
    for (( v = ini - ini % 10800; v < fin + 10800; v += 10800 )); do
        cubierta=0; esperados=""
        for h in 3 6 9; do
            c=$(( v - h * 3600 ))
            [ $(( c % 21600 )) -eq 0 ] || continue
            dia=$(date -u -d "@$c" +%Y%m%d); hh=$(date -u -d "@$c" +%H)
            f=$(printf 'f%03d' "$h")
            if compgen -G "$HOST_CACHE/gfs.t${hh}z.pgrb2.*.${f}.${dia}*" > /dev/null \
               || [ "$ahora" -ge $(( c + GFS_LATENCIA_MIN * 60 )) ]; then
                cubierta=1; break
            fi
            esperados="${esperados:+$esperados o }${hh}Z del ${dia} ($f)"
        done
        [ "$cubierta" -eq 1 ] || FALTA_GFS="$FALTA_GFS $esperados;"
    done
    [ -n "$FALTA_GFS" ]
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

FORCE=0
DOWNLOAD=0
PASADA=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)  FORCE=1 ;;
        --download)  DOWNLOAD=1 ;;
        -h|--help)   uso; exit 0 ;;
        -p|--pasada)
            if [ $# -lt 2 ]; then
                echo "ERROR: --pasada necesita un valor" >&2
                exit 1
            fi
            PASADA="$2"
            shift
            ;;
        *)
            echo "ERROR: Argumento no reconocido: $1" >&2
            uso >&2
            exit 1
            ;;
    esac
    shift
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')
HOST_WORK="${WORK_BASE}/atmos_work_${TIMESTAMP}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$HOST_SDR_IN" ]; then
    echo "ERROR: Directorio de SDR no encontrado: $HOST_SDR_IN" >&2
    exit 1
fi

# El GMTCO más reciente define la pasada a procesar
resolver_pasada "$HOST_SDR_IN" GMTCO "$PASADA" || exit 1

if [ -z "$CLAVE" ]; then
    echo "No hay SDR que procesar en $HOST_SDR_IN (no se ven archivos GMTCO*)."
    exit 0
fi

echo "=== ATMOSPHERE EDR v1.0 | pasada $CLAVE ==="

# ==============================================================================
# ¿YA FUE PROCESADA?
# ==============================================================================

MARKER="${STATE_DIR}/${CLAVE}.done"

if [ -f "$MARKER" ] && [ "$FORCE" -eq 0 ]; then
    echo ""
    echo "ℹ  La pasada $CLAVE ya fue procesada:"
    while IFS= read -r linea; do
        echo "   $linea"
    done < "$MARKER"
    echo ""
    echo "   No hay nada que hacer. Usa --force para reprocesarla."
    exit 0
fi

if [ -f "$MARKER" ]; then
    echo "--force: se reprocesa a pesar del marcador existente"
fi

# ==============================================================================
# VALIDACIÓN DEL AMBIENTE
# ==============================================================================

if [ ! -f "$SIF_ATMOS" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_ATMOS" >&2
    exit 1
fi

if [ ! -d "$HOST_STATIC/Config" ]; then
    echo "ERROR: Ancillary estático incompleto: falta $HOST_STATIC/Config" >&2
    exit 1
fi

if [ "$DOWNLOAD" -eq 0 ] && [ -z "$(ls -A "$HOST_CACHE" 2>/dev/null)" ]; then
    echo "ERROR: El caché de ancillary está vacío: $HOST_CACHE" >&2
    echo "       Ejecuta update_atmos_ancillary.sh (o usa --download)." >&2
    exit 1
fi

# ==============================================================================
# ¿ESTÁ PUBLICADO EL GFS?
# ==============================================================================

if gfs_pendiente; then
    echo "⏸  POSPUESTO: la pasada $CLAVE ($VENTANA_INI – $VENTANA_FIN UTC) necesita"
    echo "   un ciclo del GFS que todavía no puede estar publicado:${FALTA_GFS%;}"
    echo "   No se intenta. barrer_pendientes.sh la retoma; a mano, más tarde, o con"
    echo "   ATMOS_GFS_LATENCIA_MIN=0 para intentarla de todos modos."
    exit "$CODIGO_POSPUESTO"
fi

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================
# viirs_atmos.sh procesa TODOS los SDR del directorio que se le pase, así que se
# enlaza solo la pasada elegida. Los enlaces apuntan a rutas del host, por eso
# más abajo se monta HOST_SDR_IN en su propia ruta además del staging.

STAGING_DIR="${HOST_WORK}/input_pasada"
mkdir -p "$STAGING_DIR" "$HOST_CACHE" "$HOST_EDR_OUT" "$LOG_DIR" "$STATE_DIR"

while IFS= read -r f; do
    ln -sf "$f" "$STAGING_DIR"/
done < <(archivos_de_pasada "$HOST_SDR_IN" '*')

SDR_COUNT=$(find "$STAGING_DIR" -name '*.h5' | wc -l)

if [ "$SDR_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR de la pasada $CLAVE" >&2
    rm -rf "$HOST_WORK"
    exit 1
fi

LOG_FILE="$LOG_DIR/atmos_edr_${TIMESTAMP}_${CLAVE}.log"

echo "  Entrada: $HOST_SDR_IN ($SDR_COUNT archivos de la pasada)"  | tee -a "$LOG_FILE"
echo "  Salida:  $HOST_EDR_OUT"                                    | tee -a "$LOG_FILE"
echo "  Caché:   $HOST_CACHE"                                      | tee -a "$LOG_FILE"
echo "  Hilos:   $CORES"                                           | tee -a "$LOG_FILE"

# ==============================================================================
# EJECUCIÓN
# ==============================================================================

# Referencia para contar solo lo generado en esta corrida. No sirve el mtime del
# log (se escribe durante toda la ejecución, así que queda más nuevo que los
# productos) ni el del directorio de salida.
REF_FILE=$(mktemp -t atmos_edr_ref_XXXXXX)
trap "rm -f $REF_FILE" EXIT

# Un intento de viirs_atmos.sh sobre la pasada. $1 es la bandera de ancillary:
# -l (solo el caché) o vacía (CSPP baja lo que falte).
# --pwd /work aunque el driver ya reciba -W: la cadena corre desde / —de solo
# lectura dentro del contenedor—, que es como cayó LSR el 2026-09-23 y 24.
correr_atmos() {
    local flag_local="$1"
    apptainer exec \
        --bind "$STAGING_DIR:/input_sdr" \
        --bind "$HOST_SDR_IN:$HOST_SDR_IN" \
        --bind "$HOST_EDR_OUT:/output_edr" \
        --bind "$HOST_STATIC:/opt/CSPP_ATMOS_1_0/anc/static" \
        --bind "$HOST_CACHE:/opt/CSPP_ATMOS_1_0/anc/cache" \
        --bind "$HOST_WORK:/work" \
        --pwd /work \
        "$SIF_ATMOS" /bin/bash -c "
            export CSPP_VIIRS_ATMOS_HOME=/opt/CSPP_ATMOS_1_0
            export CSPP_DYNAMIC_ANCIL_DIR=\$CSPP_VIIRS_ATMOS_HOME/anc/cache
            export PATH=\$CSPP_VIIRS_ATMOS_HOME/bin:\$PATH
            export HDF5_USE_FILE_LOCKING=FALSE

            if [ ! -d \"/opt/CSPP_ATMOS_1_0/anc/static/Config\" ]; then
                echo 'FATAL: El contenedor no ve la carpeta Config.'
                exit 1
            fi

            echo '--- Ejecutando algoritmos Enterprise ---'
            viirs_atmos.sh -v $flag_local -W /work -p $CORES /input_sdr
            RC=\$?

            # El código de salida debe ser el de los algoritmos, no el del traslado:
            # de lo contrario un fallo de proceso queda enmascarado (y al revés).
            if [ \$RC -ne 0 ]; then
                echo \"--- viirs_atmos.sh terminó con código \$RC ---\"
                exit \$RC
            fi

            echo '--- Trasladando resultados (NetCDF) a Lustre ---'
            # find en vez de 'mv /work/*.nc': no falla cuando no hay nada que mover,
            # y así el diagnóstico lo da el conteo de productos, no un glob sin
            # expandir. Tampoco se silencia stderr: si mv falla, queda en el log.
            find /work -maxdepth 1 -name '*.nc' -exec mv -t /output_edr/ {} +
        " >> "$LOG_FILE" 2>&1
}

# ¿Quedó incompleta la corrida por falta de ancillary? Mira solo el tramo del
# log de este intento (desde la línea $1). CSPP termina en 0 aunque falte, y
# remata con "completed M products of N": si M < N y hay un "Failed to find
# files" (GFS) o un "Unable to find" (CMCSST), es eso.
#
# No basta con "no hubo productos". Una pasada que cruza la hora saca los
# gránulos de antes y pierde los de después: NOAA-21 del 2026-09-24 a las
# 08:58 UTC salió con 24 de 96, marcador escrito y etapa en ok.
falto_ancillary() {
    local desde="$1" tramo m n
    tramo="$(tail -n +"$desde" "$LOG_FILE")"
    m="$(echo "$tramo" | grep -oE 'completed [0-9]+ products of [0-9]+' | tail -1 | awk '{print $2}')"
    n="$(echo "$tramo" | grep -oE 'completed [0-9]+ products of [0-9]+' | tail -1 | awk '{print $5}')"
    [ -n "$m" ] && [ -n "$n" ] && [ "$m" -lt "$n" ] || return 1
    # Sin tubería: grep -q sale al primer hallazgo y, con un tramo de cientos de
    # KB, echo muere por SIGPIPE; bajo pipefail eso da 141 y la función decía
    # "no faltó". Así el reintento descargando no corrió nunca (2026-10-01 a 12).
    grep -qE 'Failed to find files|Unable to find' <<< "$tramo"
}

# Deja la pasada como si el intento no hubiera ocurrido: fuera los .nc que
# escribió y los temporales de CSPP, pero no el staging, que va dentro de /work.
# Un parcial en la salida no sirve: el reintento lo duplicaría, y sin reintento
# engañaría a LSR, CRYO y al renderizado con una pasada a medias.
descartar_intento() {
    find "$HOST_EDR_OUT" -maxdepth 1 -name '*.nc' -newer "$REF_FILE" -delete 2>/dev/null || true
    find "$HOST_WORK" -mindepth 1 -maxdepth 1 ! -name "$(basename "$STAGING_DIR")" \
         -exec rm -rf {} + 2>/dev/null || true
}

# Ancillary: primero solo el caché, que precarga el cron; si falta algo, un
# segundo intento dejando que CSPP lo baje. El caso de todos los días: una
# pasada después de las 09 o las 21 UTC pide el GFS válido a las 12 o a las 24,
# y atmos-anc solo baja f003–f009 de cada ciclo, así que la única pareja es la
# del ciclo 06Z (o 18Z), que se publica hacia las 09:30 (21:30) y el cron no
# trae hasta las 12:17 (00:17). Si ni así está, la etapa falla sin marcador y
# barrer_pendientes.sh vuelve sobre la pasada más tarde.
if [ "$DOWNLOAD" -eq 1 ]; then
    FLAGS=("")
    echo "  Ancillary: se descargará lo que falte (--download)" | tee -a "$LOG_FILE"
else
    FLAGS=("-l" "")
    echo "  Ancillary: caché local (precargado por cron); si falta, se descarga" | tee -a "$LOG_FILE"
fi

EXIT_CODE=0
INCOMPLETA=0
for FLAG_LOCAL in "${FLAGS[@]}"; do
    if [ "$FLAG_LOCAL" != "${FLAGS[0]}" ]; then
        echo "⚠  Faltó ancillary en el caché; se descarta el intento y se reintenta descargando" | tee -a "$LOG_FILE"
        descartar_intento
    fi
    DESDE=$(( $(wc -l < "$LOG_FILE") + 1 ))
    EXIT_CODE=0
    correr_atmos "$FLAG_LOCAL" || EXIT_CODE=$?
    INCOMPLETA=0
    [ "$EXIT_CODE" -ne 0 ] || ! falto_ancillary "$DESDE" || INCOMPLETA=1
    [ "$INCOMPLETA" -eq 1 ] || break
done

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP ATMOS falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                   | tee -a "$LOG_FILE"
    echo "   El directorio de trabajo se conserva: $HOST_WORK"           | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

if [ "$INCOMPLETA" -eq 1 ]; then
    # La causa está en el log; el staging son enlaces y no hay nada que depurar.
    descartar_intento
    rm -rf "$HOST_WORK"
    echo "❌ ERROR: falta ancillary dinámico para la pasada $CLAVE, aun descargando." | tee -a "$LOG_FILE"
    echo "   Lo más probable: el ciclo del GFS que la cubre todavía no se publica."   | tee -a "$LOG_FILE"
    echo "   Se descartó lo parcial; barrer_pendientes.sh la reintenta más tarde."    | tee -a "$LOG_FILE"
    echo "   grep -E 'products of|LookForFiles|Unable to find' $LOG_FILE"             | tee -a "$LOG_FILE"
    exit 1
fi

# ==============================================================================
# VERIFICACIÓN DE PRODUCTOS
# ==============================================================================
# CSPP puede terminar con código 0 sin generar nada: si falta ancillary
# dinámico, cada gránulo aborta y el log remata con "0 products of N".

NC_COUNT=$(find "$HOST_EDR_OUT" -maxdepth 1 -name '*.nc' -newer "$REF_FILE" 2>/dev/null | wc -l)

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: CSPP ATMOS terminó sin error pero no generó productos."   | tee -a "$LOG_FILE"
    echo "   Busca en el log la línea 'products of' y los FATAL asociados:"   | tee -a "$LOG_FILE"
    echo "   grep -E 'products of|FATAL|ERROR \\(USR' $LOG_FILE"              | tee -a "$LOG_FILE"
    echo "   Causa típica: falta ancillary dinámico (CMCSST, GFS) para $FECHA" | tee -a "$LOG_FILE"
    echo "   en $HOST_CACHE. Corre update_atmos_ancillary.sh."                | tee -a "$LOG_FILE"
    echo "   El directorio de trabajo se conserva: $HOST_WORK"                | tee -a "$LOG_FILE"
    exit 1
fi

# ==============================================================================
# MARCADOR DE PROCESAMIENTO EXITOSO
# ==============================================================================

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "sdr:       $SDR_COUNT archivos de entrada"
    echo "productos: $NC_COUNT archivos .nc"
    echo "duracion:  $DURACION"
    echo "salida:    $HOST_EDR_OUT"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE en $HOST_EDR_OUT ($DURACION)" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"

# Limpieza segura del temporal, solo cuando hubo productos
rm -rf "$HOST_WORK"
