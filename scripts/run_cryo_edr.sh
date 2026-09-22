#!/bin/bash
#SBATCH --job-name=cspp_cryo_edr
#SBATCH --output=/var/log/lanot/polares/cspp-edr/slurm_cryo_%j.out
#SBATCH --error=/var/log/lanot/polares/cspp-edr/slurm_cryo_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --partition=normal
# ==============================================================================
# LANOT - UNAM | CSPP VIIRS Cryosphere EDR v1.0
# ==============================================================================
#
# Level 1 (SDR de VIIRS) + Level 2 atmosphere → productos de criósfera
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue procesada con éxito, avisa y no hace nada. Una pasada se identifica
# por satélite, fecha y hora de inicio (p. ej. j01_d20260811_t194733;
# ver pasadas.sh).
#
# Requiere de ATMOS los productos Cloud Mask y Cloud Height de la misma pasada
# (manual §2: "CSPP CRYO also requires two VIIRS Atmosphere EDR products").
# No usa ancillary dinámico.
#
# Uso:
#   ./run_cryo_edr.sh            # la pasada más reciente pendiente
#   ./run_cryo_edr.sh --force    # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   CRYO_SDR_IN     Entrada Level 1   (def. /data/output/jpss/level1/viirs)
#   CRYO_ATMOS_IN   Entrada atmosphere(def. /data/output/jpss/level2/atmosphere)
#   CRYO_OUT        Salida            (def. /data/output/jpss/level2/cryosphere)
#   CRYO_STATE_DIR  Marcadores .done  (def. /data/output/jpss/state/cspp-cryo)
#   CRYO_CONTAINER  Imagen .sif       (def. /opt/containers/cspp_cryo_edr_v1.0.sif)
#   CRYO_WORK_BASE  Raíz de staging   (def. /data/tmp)
#   CRYO_LOG_BASE   Raíz de logs      (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_IMAGE="${CRYO_CONTAINER:-/opt/containers/cspp_cryo_edr_v1.0.sif}"

INPUT_SDR_DIR="${CRYO_SDR_IN:-/data/output/jpss/level1/viirs}"
INPUT_ATMOS_DIR="${CRYO_ATMOS_IN:-/data/output/jpss/level2/atmosphere}"
OUTPUT_CRYO_DIR="${CRYO_OUT:-/data/output/jpss/level2/cryosphere}"
STATE_DIR="${CRYO_STATE_DIR:-/data/output/jpss/state/cspp-cryo}"

WORK_BASE="${CRYO_WORK_BASE:-/data/tmp}"
LOG_DIR="${CRYO_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

CORES="${SLURM_CPUS_PER_TASK:-8}"
JOB_ID="${SLURM_JOB_ID:-$$}"

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0             Procesa la pasada más reciente de $INPUT_SDR_DIR
  $0 --force     Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force   Ignora el marcador de procesado
  -p, --pasada  Pasada concreta en vez de la más reciente: la clave completa
                (j01_d20260813_t191402) o cualquier trozo que la identifique
  -h, --help    Muestra esta ayuda

Pasadas disponibles en $INPUT_SDR_DIR:
$(listar_pasadas "$INPUT_SDR_DIR" GMTCO 2>/dev/null | cut -d' ' -f1 | sed 's/^/  /' || true)
EOF
}

# Qué es una pasada y cómo se elige: por tiempo, no por órbita (ver pasadas.sh).
# Fija CLAVE, SAT, FECHA y la ventana VENTANA_INI – VENTANA_FIN.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/pasadas.sh"

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

# Devuelve el sello temporal de un producto como AAAAMMDDHHMMSS, o código 1 si
# no lo reconoce. En Level 2 conviven dos convenciones:
#   JRR-CloudMask_v3r2_j01_s202608111947330_e...    -> fecha + hora + décimas
#   NOAA20_VIIRS_750M_2026223_1947_33_NWP_GFS-INTP  -> año + día juliano + HHMM_SS
sello_de_archivo() {
    local nombre="$1" s anio doy fecha

    # El campo de creación (_c<sello>) se quita ANTES de buscar nada, porque no
    # es tiempo de observación y compite con el que sí lo es.
    #
    # Esto costó una pasada entera el 2026-08-29. Un AFIMG se llama
    # AFIMG_npp_d20260829_t1852513_..._c20260829192258365504_cspp_dev.nc: la
    # fecha aparece DOS veces, y la regla de "fecha + 7 dígitos" no casa en el
    # campo de observación —entre la fecha y la hora va "_t", no un dígito— pero
    # sí en el de creación. Los ocho gránulos de esa pasada salieron con el
    # mismo sello, el de cuando se escribió el archivo, siete minutos fuera de
    # la ventana: 'FIRE: 0 productos en la ventana', etapa en ok, cero
    # incendios publicados y marcador escrito.
    #
    # Y no se había visto antes por pura casualidad de calendario: hasta ese día
    # solo se habían procesado crudos de fechas anteriores, donde la fecha de
    # creación NO coincide con FECHA_NUM y la regla no casaba. En operación real
    # —la antena entrega y se procesa enseguida— las dos fechas son la misma
    # SIEMPRE, así que esto habría fallado en cada pasada.
    nombre=$(echo "$nombre" | sed -E 's/_c[0-9]{6,}//')

    # Convención con fecha calendario
    s=$(echo "$nombre" | grep -oE "(${FECHA_NUM}|${FECHA_SIG})[0-9]{7}" | head -1 || true)
    if [ -n "$s" ]; then
        echo "${s:0:14}"   # se descartan las décimas de segundo
        return 0
    fi

    # Convención con día juliano
    s=$(echo "$nombre" | grep -oE "_[0-9]{7}_[0-9]{4}_[0-9]{2}_" | head -1 || true)
    if [ -n "$s" ]; then
        s="${s#_}"; s="${s%_}"
        anio="${s:0:4}"; doy="${s:4:3}"
        fecha=$(date -u -d "${anio}-01-01 +$((10#$doy - 1)) days" +%Y%m%d)
        echo "${fecha}${s:8:4}${s:13:2}"
        return 0
    fi

    return 1
}

# Rechaza un archivo si nombra explícitamente a OTRO satélite. Si no reconoce
# ninguno, no estorba: la ventana temporal ya filtra.
de_otro_satelite() {
    case "$SAT" in
        j01) echo "$1" | grep -qiE "j02|noaa21|npp" ;;
        j02) echo "$1" | grep -qiE "j01|noaa20|npp" ;;
        npp) echo "$1" | grep -qiE "j01|noaa20|j02|noaa21" ;;
        *)   return 1 ;;
    esac
}

# Enlaza los productos $3 cuyo sello temporal cae dentro de la ventana de la
# pasada. No se puede emparejar gránulo por gránulo: los SDR llegan agregados
# (un archivo por banda para toda la pasada, con un solo GMTCO), mientras que
# los productos de Level 2 son por gránulo.
enlazar() {
    ln -f "$1" "$2" 2>/dev/null || ln -sf "$1" "$2"
}

enlazar_en_ventana() {
    local destino="$1" origen="$2" patron="$3" enlazados=0 f nombre sello clave
    local -A elegido=()

    shopt -s nullglob
    for f in "$origen"/${patron}*.nc; do
        nombre=$(basename "$f")
        de_otro_satelite "$nombre" && continue
        sello=$(sello_de_archivo "$nombre") || continue
        [ "$sello" -ge "$VENTANA_INI" ] && [ "$sello" -le "$VENTANA_FIN" ] || continue

        # Deduplicación: los JRR-* llevan campo de creación (_c<sello>), así que
        # reprocesar una pasada deja DOS archivos del mismo producto y gránulo.
        # Hay que quedarse con el más reciente, porque LSR deduce cuántos
        # gránulos hay contando los JRR-AOD (cspp_viirs_surface_reflectance.py:313)
        # y luego exige esa misma cantidad de los demás productos. Los duplicados
        # inflan la cuenta y hacen fallar la corrida con un mensaje que culpa a
        # los NWP_GFS-INTP, que no se duplican porque su nombre no lleva _c.
        clave=$(echo "$nombre" | sed -E 's/_c[0-9]+\./_c./')
        if [ -z "${elegido[$clave]:-}" ] || [ "$f" -nt "${elegido[$clave]}" ]; then
            elegido[$clave]="$f"
        fi
    done
    shopt -u nullglob

    for f in "${elegido[@]}"; do
        enlazar "$f" "$destino"/
        enlazados=$((enlazados + 1))
    done

    echo "$enlazados"
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================

FORCE=0
PASADA=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        -h|--help)  uso; exit 0 ;;
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
STAGING_DIR="${WORK_BASE}/cryo_staging_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$INPUT_SDR_DIR" ]; then
    echo "ERROR: Directorio de SDR no encontrado: $INPUT_SDR_DIR" >&2
    exit 1
fi

resolver_pasada "$INPUT_SDR_DIR" GMTCO "$PASADA" || exit 1

if [ -z "$CLAVE" ]; then
    echo "No hay SDR que procesar en $INPUT_SDR_DIR (no se ven archivos GMTCO*)."
    exit 0
fi

echo "=== CSPP VIIRS Cryosphere v1.0 | pasada $CLAVE ==="

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

if [ ! -f "$SIF_IMAGE" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_IMAGE" >&2
    exit 1
fi

if [ ! -d "$INPUT_ATMOS_DIR" ]; then
    echo "ERROR: Directorio de productos ATMOS no encontrado: $INPUT_ATMOS_DIR" >&2
    echo "       CRYO necesita Cloud Mask y Cloud Height: corre run_atmos_edr.sh antes." >&2
    exit 1
fi

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================

mkdir -p "$STAGING_DIR" "$OUTPUT_CRYO_DIR" "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$STAGING_DIR"' EXIT

# CRYO solo necesita las bandas M y su geolocalización
while IFS= read -r f; do
    ln -sf "$f" "$STAGING_DIR"/
done < <(archivos_de_pasada "$INPUT_SDR_DIR" 'SVM*'; archivos_de_pasada "$INPUT_SDR_DIR" GMTCO)

SDR_COUNT=$(find "$STAGING_DIR" -name '*.h5' | wc -l)

if [ "$SDR_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR de la pasada $CLAVE" >&2
    exit 1
fi

PRODUCTOS_ATMOS=$(( $(enlazar_en_ventana "$STAGING_DIR" "$INPUT_ATMOS_DIR" "JRR-CloudMask")
                  + $(enlazar_en_ventana "$STAGING_DIR" "$INPUT_ATMOS_DIR" "JRR-CloudHeight") ))

if [ "$PRODUCTOS_ATMOS" -eq 0 ]; then
    echo "ERROR: No hay Cloud Mask / Cloud Height para la pasada $CLAVE en $INPUT_ATMOS_DIR" >&2
    echo "       Corre run_atmos_edr.sh para esa pasada antes que CRYO." >&2
    exit 1
fi

LOG_FILE="$LOG_DIR/cryo_edr_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR:      $SDR_COUNT archivos (SVM* + GMTCO*)"        | tee -a "$LOG_FILE"
echo "  ATMOS:    $PRODUCTOS_ATMOS productos en $VENTANA_INI-$VENTANA_FIN"       | tee -a "$LOG_FILE"
echo "  Salida:   $OUTPUT_CRYO_DIR"                           | tee -a "$LOG_FILE"
echo "  Hilos:    $CORES"                                     | tee -a "$LOG_FILE"

# ==============================================================================
# EJECUCIÓN
# ==============================================================================
# viirs_cryo.sh escribe los resultados en el directorio actual, por eso el
# --pwd /output_data.

REF_FILE=$(mktemp -t cryo_edr_ref_XXXXXX)
trap 'rm -rf "$STAGING_DIR" "$REF_FILE"' EXIT

EXIT_CODE=0
apptainer exec \
    --env LC_ALL=C \
    --env CSPP_VIIRS_CRYO_HOME=/opt/cspp_cryo \
    -B "${STAGING_DIR}":/input_data \
    -B "${OUTPUT_CRYO_DIR}":/output_data \
    -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}" \
    -B "${INPUT_ATMOS_DIR}":"${INPUT_ATMOS_DIR}" \
    --pwd /output_data \
    "${SIF_IMAGE}" \
    /opt/cspp_cryo/bin/viirs_cryo.sh -p "${CORES}" /input_data \
    >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP CRYO falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                  | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN DE PRODUCTOS
# ==============================================================================

NC_COUNT=$(find "$OUTPUT_CRYO_DIR" -maxdepth 1 -name '*.nc' -newer "$REF_FILE" 2>/dev/null | wc -l)

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: CSPP CRYO terminó sin error pero no generó productos." | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                     | tee -a "$LOG_FILE"
    exit 1
fi

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "sdr:       $SDR_COUNT archivos de entrada"
    echo "productos: $NC_COUNT archivos .nc"
    echo "duracion:  $DURACION"
    echo "salida:    $OUTPUT_CRYO_DIR"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE en $OUTPUT_CRYO_DIR ($DURACION)" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"
