#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Auxiliares de IASI y coeficientes de calibración (rama METOP)
# ==============================================================================
#
# Trae a /data/ancillary/aapp/opsaux los BRD/GRD y demás auxiliares de IASI que
# publica NWP SAF, con el get_aux_files.sh que viaja en aapp_v8.15.sif. Sin
# ellos OPS-LRS no saca IASI, y con unos viejos lo saca con la calibración de
# otro periodo sin avisar: NWP SAF publica versiones nuevas varias veces al año,
# y en stratus la última actualización fue a mano, el 2026-01-15.
#
# get_aux_files.sh baja solo lo que falta: del índice de NWP SAF toma, por tipo
# y satélite, el más reciente que ya esté vigente, más los fijos (CTX, ENG, VER),
# a un .TMP que renombra solo si wget terminó bien. Aun así, después se revisa
# que nada de lo nuevo sea una página HTML: el 2026-08-21 una respuesta así
# sustituyó en stratus los coeficientes visibles de AVHRR (plan_metop.md) y
# nadie se enteró en tres meses.
#
# Toma el candado de run_metop_l1.sh: así no cambian los BRD de IASI a media
# corrida de OPS-LRS.
#
# Y los coeficientes de calibración de AMSU-A, MHS, HIRS y AVHRR que publica
# NWP SAF, en /data/ancillary/aapp/calibration (ver la sección COEFICIENTES:
# cambian, y el 2026-11-18 cambiaban los sondeos). No con get_atovs_cal_files.sh,
# que escribe también en el árbol de la imagen y sustituye sin validar.
#
# Cron sugerido (crontab de lanotadm), semanal y lejos de las pasadas de METOP
# (03–04 y 15–17 UTC). Domingo 12:15 CST = 18:15 UTC:
#
#   15 12 * * 0 /opt/lanot/polares/scripts/update_aapp_ancillary.sh >> /var/log/lanot/polares/cadena/cron.log 2>&1
#
# Uso:
#   ./update_aapp_ancillary.sh              # descarga lo que falte o cambió
#   ./update_aapp_ancillary.sh --dry-run    # dice qué bajaría o cambiaría, sin tocar nada
#
# Variables de entorno (para pruebas o rutas alternas):
#   METOP_CONTAINER   Imagen .sif        (def. /opt/containers/aapp_v8.15.sif)
#   METOP_ANC_DIR     Caché de AAPP      (def. /data/ancillary/aapp)
#   METOP_WORK_BASE   Raíz de trabajo    (def. /data/tmp)
#   METOP_LOG_BASE    Raíz de logs       (def. /var/log/lanot/polares)
#   METOP_ESPERA_MIN  Espera por el candado de AAPP (def. 60)
#
# ==============================================================================

set -euo pipefail

CONTAINER="${METOP_CONTAINER:-/opt/containers/aapp_v8.15.sif}"
ANC_DIR="${METOP_ANC_DIR:-/data/ancillary/aapp}"
OPSAUX="$ANC_DIR/opsaux"
WORK_BASE="${METOP_WORK_BASE:-/data/tmp}"
LOG_DIR="${METOP_LOG_BASE:-/var/log/lanot/polares}/aapp"
ESPERA_MIN="${METOP_ESPERA_MIN:-60}"
CANDADO="${WORK_BASE}/lanot_aapp.lock"   # el mismo de run_metop_l1.sh

DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "ERROR: Argumento no reconocido: $1" >&2
            exit 1
            ;;
    esac
    shift
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')

if [ ! -f "$CONTAINER" ]; then
    echo "ERROR: Contenedor no encontrado: $CONTAINER" >&2
    exit 1
fi

mkdir -p "$OPSAUX" "$LOG_DIR"
LOG_FILE="$LOG_DIR/aapp_ancillary_${TIMESTAMP}.log"

# get_aux_files.sh escribe su índice (index.html, files.txt) en el directorio
# actual: uno propio, que no sea el de nadie más.
WORK_DIR="${WORK_BASE}/aapp_anc_${TIMESTAMP}_$$"
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

exec 9> "$CANDADO"
# Lo comparten lanotadm (operación) y quien pruebe a mano desde el clon: si lo
# crea una persona con su umask, lanotadm ya no puede abrirlo y la siguiente
# pasada muere aquí (pasó con las pruebas del 2026-11-18: quedó de
# aguilars:aguilars, así que ni g+w alcanzaba). Es un archivo vacío: escribible
# para todos no expone nada.
chmod a+rw "$CANDADO" 2>/dev/null || true
if ! flock -n 9; then
    echo "[$(date '+%F %T')] Hay una corrida de AAPP en curso; se espera hasta ${ESPERA_MIN} min..." | tee -a "$LOG_FILE"
    if ! flock -w $((ESPERA_MIN * 60)) 9; then
        echo "ERROR: el candado $CANDADO no se liberó en ${ESPERA_MIN} min." | tee -a "$LOG_FILE" >&2
        exit 75
    fi
fi

echo "=== AUXILIARES DE IASI (OPS-LRS): $(date) ===" | tee -a "$LOG_FILE"
echo "  Destino:  $OPSAUX"                            | tee -a "$LOG_FILE"

# Lo nuevo se reconoce por NOMBRE, no por fecha: wget les pone la fecha de
# modificación del servidor, que puede ser de hace meses.
find "$OPSAUX" -maxdepth 1 -type f -printf '%f\n' | sort > "$WORK_DIR/.antes"
ANTES=$(wc -l < "$WORK_DIR/.antes")

OPCION=""
[ "$DRY_RUN" -eq 0 ] || OPCION="-l"

CODIGO=0
apptainer exec \
    --bind "$OPSAUX":/opsaux \
    --bind "$WORK_DIR":/work \
    --pwd /work \
    "$CONTAINER" \
    /bin/bash -c "get_aux_files.sh $OPCION /opsaux" \
    >> "$LOG_FILE" 2>&1 || CODIGO=$?

ERRORES=()

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Auxiliares de IASI que bajaría (vacío = nada nuevo):" | tee -a "$LOG_FILE"
    grep -v -E '^\s*$|^---|^===' "$LOG_FILE" | grep -E '^IASI_' | sed 's/^/  /' || echo "  (nada)"
    [ "$CODIGO" -eq 0 ] || ERRORES+=("get_aux_files.sh -l salió en $CODIGO")
    NUEVOS=()
elif [ "$CODIGO" -ne 0 ]; then
    # get_aux_files.sh sale en 0 aunque no haya podido leer el índice (no hay
    # 'else' para un index.html vacío), así que el código no basta; pero
    # distinto de 0 sí es un fallo.
    echo "  ⚠ get_aux_files.sh terminó con código $CODIGO" | tee -a "$LOG_FILE"
    ERRORES+=("get_aux_files.sh salió en $CODIGO")
    NUEVOS=()
else
    # --- Lo nuevo: ¿es de verdad un auxiliar de IASI? -------------------------
    # Lo que se sabe malo se aparta a cuarentena/ en vez de borrarse: sirve para
    # ver qué contestó el servidor. Los .TMP que hayan quedado de una descarga
    # cortada se borran (get_aux_files.sh los rehace).
    find "$OPSAUX" -maxdepth 1 -type f -name '*.TMP' -delete

    find "$OPSAUX" -maxdepth 1 -type f -printf '%f\n' | sort > "$WORK_DIR/.despues"
    mapfile -t NUEVOS < <(comm -13 "$WORK_DIR/.antes" "$WORK_DIR/.despues")
    for f in "${NUEVOS[@]}"; do
        inicio=$(head -c 64 "$OPSAUX/$f" | tr -d '\0' | tr '[:upper:]' '[:lower:]')
        if [ ! -s "$OPSAUX/$f" ] || [[ "$inicio" == *"<!doctype"* ]] || [[ "$inicio" == *"<html"* ]]; then
            mkdir -p "$OPSAUX/cuarentena"
            mv "$OPSAUX/$f" "$OPSAUX/cuarentena/"
            echo "  ⚠ $f no es un auxiliar (vacío o HTML): a cuarentena/" | tee -a "$LOG_FILE"
            ERRORES+=("$f apartado")
        else
            echo "  + $f" | tee -a "$LOG_FILE"
        fi
    done

    # Lo que sí tiene que haber al final, por satélite: un BRD y un GRD vigentes.
    for sat in M01 M03; do
        for tipo in BRD GRD; do
            if [ -z "$(find "$OPSAUX" -maxdepth 1 -type f -name "IASI_${tipo}_xx_${sat}_*" -size +0 -print -quit)" ]; then
                ERRORES+=("falta ${tipo}_${sat}")
            fi
        done
    done

    # Que lanotadm pueda escribir aunque esto lo corra otra persona (o root, desde
    # preparar_servidor.sh).
    chmod -R g+rwX "$OPSAUX" 2>/dev/null || true
    echo "  ${#NUEVOS[@]} archivos nuevos ($ANTES → $(find "$OPSAUX" -maxdepth 1 -type f | wc -l))" | tee -a "$LOG_FILE"
fi

# ==============================================================================
# COEFICIENTES DE CALIBRACIÓN DE ATOVS Y AVHRR
# ==============================================================================
# Lo que hace get_atovs_cal_files.sh de NWP SAF, pero solo con lo que en esta
# cadena vive en el host (calibration/, montado sobre la ruta interna; ver
# run_metop_l1.sh) y validando antes de sustituir, que es justo lo que aquel no
# hace: sustituye el local por lo que baje en cuanto difiera.
#
# Que esto cambia y que importa se vio el 2026-11-18: AAPP 8.15 trae el
# amsua_clparams.dat versión 46; stratus tenía la 47 (2025-09-22) y NWP SAF ya
# publica la 48 (2026-07-14). Entre ellas bajan los límites de conteo de AMSU-A1
# en METOP-B y C —los instrumentos derivaron—, y con la 46 nuestro AMSU-A
# rechazaba la calibración de esos canales: los sondeos de HEAP salían con 2 K
# de diferencia en la temperatura de piel (plan_metop.md, "IASI, sin cerrar").
#
# fdf.dat (preproc) y satid.txt (navigation), los otros dos de aquel script, son
# de la imagen: se revisan al pasar a otra versión de AAPP.
#
# Validación: cada archivo declara en su primera línea dónde va
# ("## LOC = data/calibration/coef/amsua/amsua_clparams.dat"). Si lo bajado no
# la trae —una página de error, un HTML con código 200—, no se toca nada.
# Si cambia, la versión anterior queda al lado con la fecha: <archivo>.<AAAAMMDD>.

URL_CAL="https://nwp-saf.eumetsat.int/downloads/aapp_data_files/atovs_cal_files"
CALIB="$ANC_DIR/calibration"
COEF_ACTUALIZADOS=()

if [ ! -d "$CALIB/coef" ]; then
    echo "  · $CALIB todavía no existe (run_metop_l1.sh la siembra en la primera pasada); se omiten los coeficientes" | tee -a "$LOG_FILE"
else
    echo "=== COEFICIENTES DE CALIBRACIÓN (NWP SAF) ===" | tee -a "$LOG_FILE"
    for rel in coef/amsua/amsua_clparams.dat coef/mhs/mhs_clparams.dat \
               coef/hirs/h_calcoef_algoV4.dat coef/avhcl/avhcal.txt; do
        nombre=$(basename "$rel")
        tmp="$WORK_DIR/$nombre"
        if ! curl -sf --max-time 60 -o "$tmp" "$URL_CAL/$nombre"; then
            echo "  ⚠ $nombre: no se pudo bajar" | tee -a "$LOG_FILE"
            ERRORES+=("$nombre no se bajó")
            continue
        fi
        if [ "$(head -1 "$tmp" | tr -d '\r')" != "## LOC = data/calibration/$rel" ]; then
            echo "  ⚠ $nombre: lo bajado no es el archivo (primera línea: $(head -c 60 "$tmp" | tr -d '\r\n'))" | tee -a "$LOG_FILE"
            ERRORES+=("$nombre no válido")
            continue
        fi
        if cmp -s "$tmp" "$CALIB/$rel"; then
            echo "  = $nombre" | tee -a "$LOG_FILE"
            continue
        fi
        version_vieja=$(grep -m1 'version number' "$CALIB/$rel" 2>/dev/null | awk '{print $1}')
        version_nueva=$(grep -m1 'version number' "$tmp" | awk '{print $1}')
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  [dry-run] $nombre cambiaría (versión ${version_vieja:-?} → ${version_nueva:-?})" | tee -a "$LOG_FILE"
            continue
        fi
        [ ! -f "$CALIB/$rel" ] || cp -p "$CALIB/$rel" "$CALIB/$rel.$(date +%Y%m%d)"
        cp "$tmp" "$CALIB/$rel"
        chmod g+rw "$CALIB/$rel" 2>/dev/null || true
        echo "  ↑ $nombre actualizado (versión ${version_vieja:-?} → ${version_nueva:-?})" | tee -a "$LOG_FILE"
        COEF_ACTUALIZADOS+=("$nombre")
    done
fi

DURACION=$(( $(date '+%s') - START_EPOCH ))

if [ ${#ERRORES[@]} -gt 0 ]; then
    echo "❌ con problemas: ${ERRORES[*]} ($DURACION s). Ver $LOG_FILE" | tee -a "$LOG_FILE" >&2
    exit 1
fi
echo "✅ auxiliares de IASI: ${#NUEVOS[@]} nuevos · coeficientes actualizados: ${#COEF_ACTUALIZADOS[@]}${COEF_ACTUALIZADOS:+ (${COEF_ACTUALIZADOS[*]})} · $DURACION s" | tee -a "$LOG_FILE"

# Los logs de esta tarea son pequeños pero se acumulan
find "$LOG_DIR" -name "aapp_ancillary_*.log" -mtime +60 -delete
