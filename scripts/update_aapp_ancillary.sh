#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Auxiliares de IASI para OPS-LRS (rama METOP)
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
# Lo que NO hace, a propósito: correr get_atovs_cal_files.sh (coeficientes de
# AMSU, MHS, HIRS y AVHRR). Escribe además en data/preproc y data/navigation,
# que en esta cadena son de la imagen y de solo lectura, y sustituye el archivo
# local por lo que baje en cuanto difiera, sin mirar qué es. Esos coeficientes
# cambian cuando se lanza o recalibra un satélite: se actualizan al pasar a otra
# versión de AAPP, recompilando la imagen y volviendo a sembrar
# /data/ancillary/aapp/calibration (borrarla y dejar que run_metop_l1.sh la
# siembre).
#
# Cron sugerido (crontab de lanotadm), semanal y lejos de las pasadas de METOP
# (03–04 y 15–17 UTC). Domingo 12:15 CST = 18:15 UTC:
#
#   15 12 * * 0 /opt/lanot/polares/scripts/update_aapp_ancillary.sh >> /var/log/lanot/polares/cadena/cron.log 2>&1
#
# Uso:
#   ./update_aapp_ancillary.sh              # descarga lo que falte
#   ./update_aapp_ancillary.sh --dry-run    # lista lo que bajaría, sin bajar
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

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Bajaría (vacío = nada nuevo):" | tee -a "$LOG_FILE"
    grep -v -E '^\s*$|^---|^===' "$LOG_FILE" | grep -E '^IASI_' | sed 's/^/  /' || echo "  (nada)"
    exit "$CODIGO"
fi

# get_aux_files.sh sale en 0 aunque no haya podido leer el índice (no hay
# 'else' para un index.html vacío), así que el código no basta.
if [ "$CODIGO" -ne 0 ]; then
    echo "ERROR: get_aux_files.sh terminó con código $CODIGO. Ver $LOG_FILE" >&2
    exit 1
fi

# --- Lo nuevo: ¿es de verdad un auxiliar de IASI? -----------------------------
# Lo que se sabe malo se aparta a cuarentena/ en vez de borrarse: sirve para
# ver qué contestó el servidor. Los .TMP que hayan quedado de una descarga
# cortada se borran (get_aux_files.sh los rehace).
find "$OPSAUX" -maxdepth 1 -type f -name '*.TMP' -delete

find "$OPSAUX" -maxdepth 1 -type f -printf '%f\n' | sort > "$WORK_DIR/.despues"
mapfile -t NUEVOS < <(comm -13 "$WORK_DIR/.antes" "$WORK_DIR/.despues")
MALOS=0
for f in "${NUEVOS[@]}"; do
    inicio=$(head -c 64 "$OPSAUX/$f" | tr -d '\0' | tr '[:upper:]' '[:lower:]')
    if [ ! -s "$OPSAUX/$f" ] || [[ "$inicio" == *"<!doctype"* ]] || [[ "$inicio" == *"<html"* ]]; then
        mkdir -p "$OPSAUX/cuarentena"
        mv "$OPSAUX/$f" "$OPSAUX/cuarentena/"
        echo "  ⚠ $f no es un auxiliar (vacío o HTML): a cuarentena/" | tee -a "$LOG_FILE"
        MALOS=$((MALOS + 1))
    else
        echo "  + $f" | tee -a "$LOG_FILE"
    fi
done

# Lo que sí tiene que haber al final, por satélite: un BRD y un GRD vigentes.
FALTAN=()
for sat in M01 M03; do
    for tipo in BRD GRD; do
        if [ -z "$(find "$OPSAUX" -maxdepth 1 -type f -name "IASI_${tipo}_xx_${sat}_*" -size +0 -print -quit)" ]; then
            FALTAN+=("${tipo}_${sat}")
        fi
    done
done

# Que lanotadm pueda escribir aunque esto lo corra otra persona (o root, desde
# preparar_servidor.sh).
chmod -R g+rwX "$OPSAUX" 2>/dev/null || true

DESPUES=$(find "$OPSAUX" -maxdepth 1 -type f | wc -l)
DURACION=$(( $(date '+%s') - START_EPOCH ))

if [ ${#FALTAN[@]} -gt 0 ] || [ "$MALOS" -gt 0 ]; then
    echo "❌ ${#NUEVOS[@]} archivos nuevos, $MALOS apartados; faltan: ${FALTAN[*]:-nada} ($DURACION s)" | tee -a "$LOG_FILE" >&2
    exit 1
fi
echo "✅ ${#NUEVOS[@]} archivos nuevos ($ANTES → $DESPUES) en $DURACION s" | tee -a "$LOG_FILE"

# Los logs de esta tarea son pequeños pero se acumulan
find "$LOG_DIR" -name "aapp_ancillary_*.log" -mtime +60 -delete
