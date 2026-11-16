#!/bin/bash
#SBATCH --job-name=omps_tos_edr
#SBATCH --cpus-per-task=1
#SBATCH --output=/var/log/lanot/polares/cspp-edr/slurm_omps_tos_%j.log
# ==============================================================================
# LANOT - UNAM | CSPP OMPS V8TOS EDR v1.0 (Level 2 → Level 2, SO2)
# ==============================================================================
#
# V8TOZ (ozono total de CSPP OMPS EDR) → V8TOS: columna de SO2 en cuatro
# supuestos de altura —PBL, TRL 0–5 km, TRM 5–10 km, STL 15–19 km— y el ozono
# total corregido por SO2. Un V8TOS por cada V8TOZ.
#
# NO lee SDR, sino los V8TOZ que deja run_omps_edr.sh, así que corre después de
# él: es a OMPS lo que LSR es a ATMOS. Tampoco tiene ancillary dinámico.
#
# La pasada se resuelve igual que en run_omps_edr.sh —sobre los GOTCO de
# level1/omps, con la misma clave— y de level2/omps se enlazan los V8TOZ cuyo
# sello cae en su ventana.
#
# Los huecos de recepción los resuelve el driver: parte la entrada en tramos
# continuos ("contiguous runsets") y promedia la corrección dentro de cada uno
# (manual §2.2). Una pasada de NOAA-20 sin hueco aparente salió en dos tramos el
# 2026-11-14 porque dos gránulos se traslapaban 2.5 s, y los 19 salieron igual.
#
# Uso:
#   ./run_omps_tos_edr.sh            # la pasada más reciente pendiente
#   ./run_omps_tos_edr.sh --force    # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   OMPS_SDR_IN       Level 1 de OMPS, para resolver la pasada
#                     (def. /data/output/jpss/level1/omps)
#   OMPS_OUT          Entrada V8TOZ y salida V8TOS (def. /data/output/jpss/level2/omps)
#   OMPS_TOS_STATE_DIR Marcadores .done (def. /data/output/jpss/state/cspp-omps-tos)
#   OMPS_TOS_CONTAINER Imagen .sif     (def. /opt/containers/cspp_omps_tos_v1.0.sif)
#   OMPS_TOS_WORK_BASE Raíz de trabajo (def. /data/tmp)
#   OMPS_TOS_LOG_BASE  Raíz de logs    (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_TOS="${OMPS_TOS_CONTAINER:-/opt/containers/cspp_omps_tos_v1.0.sif}"

# OMPS_SDR_IN y OMPS_OUT son las de run_omps_edr.sh a propósito: la entrada de
# este eslabón es la salida de aquél, y procesar_pasada.sh las comparte.
HOST_SDR_IN="${OMPS_SDR_IN:-/data/output/jpss/level1/omps}"
HOST_L2="${OMPS_OUT:-/data/output/jpss/level2/omps}"
STATE_DIR="${OMPS_TOS_STATE_DIR:-/data/output/jpss/state/cspp-omps-tos}"

WORK_BASE="${OMPS_TOS_WORK_BASE:-/data/tmp}"
LOG_DIR="${OMPS_TOS_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

JOB_ID="${SLURM_JOB_ID:-$$}"

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0             Procesa la pasada más reciente de $HOST_SDR_IN
  $0 --force     Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force   Ignora el marcador de procesado
  -p, --pasada  Pasada concreta en vez de la más reciente: la clave completa
                (j01_d20261114_t201010) o cualquier trozo que la identifique
  -h, --help    Muestra esta ayuda

Requiere los V8TOZ de la pasada en $HOST_L2:
  scripts/run_omps_edr.sh -p <pasada>

Pasadas disponibles en $HOST_SDR_IN:
$(listar_pasadas "$HOST_SDR_IN" GOTCO 2>/dev/null | cut -d' ' -f1 | sed 's/^/  /' || true)
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

# Sello de observación de un V8TOZ (AAAAMMDDHHMMSS), sin el campo de creación,
# que lleva también la fecha y compite con el bueno (ver run_lsr_edr.sh).
#   V8TOZ-EDR_v4r5_n21_s202611141913246_e202611141914024_c202611141949520.nc
sello_de_archivo() {
    local s
    s=$(echo "$1" | sed -E 's/_c[0-9]{6,}//' | grep -oE "_s(${FECHA_NUM}|${FECHA_SIG})[0-9]{6}" | head -1 || true)
    [ -n "$s" ] || return 1
    echo "${s:2:14}"
}

# Rechaza un archivo si nombra explícitamente a OTRO satélite. CSPP OMPS llama
# n21 a NOAA-21 en sus EDR, y no j02 como en los SDR.
de_otro_satelite() {
    case "$SAT" in
        j01) echo "$1" | grep -qiE "j02|noaa21|n21|npp" ;;
        j02) echo "$1" | grep -qiE "j01|noaa20|n20|npp" ;;
        npp) echo "$1" | grep -qiE "j01|noaa20|n20|j02|noaa21|n21" ;;
        *)   return 1 ;;
    esac
}

# Enlace duro si se puede (mismo sistema de archivos), simbólico si no.
enlazar() {
    ln -f "$1" "$2" 2>/dev/null || ln -sf "$1" "$2"
}

# Enlaza en $1 los V8TOZ de $2 de la ventana de la pasada, uno por gránulo: si
# OMPS se reprocesó, quedan dos del mismo gránulo con distinto campo de
# creación, y se toma el más reciente.
enlazar_v8toz() {
    local destino="$1" origen="$2" enlazados=0 f nombre sello clave
    local -A elegido=()

    preparar_filtro_fechas
    shopt -s nullglob
    for f in "$origen"/V8TOZ-EDR_*.nc; do
        nombre="${f##*/}"
        en_fechas_de_ventana "$nombre" || continue
        de_otro_satelite "$nombre" && continue
        sello=$(sello_de_archivo "$nombre") || continue
        [ "$sello" -ge "$VENTANA_INI" ] && [ "$sello" -le "$VENTANA_FIN" ] || continue
        clave=$(echo "$nombre" | sed -E 's/_c[0-9]{6,}/_c/')
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

# Staging y trabajo, hermanos y no anidados, como en los demás EDR.
HOST_WORK="${WORK_BASE}/omps_tos_work_${JOB_ID}"
STAGING_DIR="${WORK_BASE}/omps_tos_staging_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$HOST_SDR_IN" ]; then
    echo "ERROR: Directorio de SDR de OMPS no encontrado: $HOST_SDR_IN" >&2
    exit 1
fi

resolver_pasada "$HOST_SDR_IN" GOTCO "$PASADA" || exit 1

if [ -z "$CLAVE" ]; then
    echo "No hay pasadas de OMPS en $HOST_SDR_IN (no se ven archivos GOTCO*)."
    exit 0
fi

echo "=============================================================================="
echo "CSPP OMPS V8TOS EDR v1.0 | pasada $CLAVE"
echo "=============================================================================="

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
# STAGING DE LA PASADA
# ==============================================================================
# Antes de validar el ambiente: sin V8TOZ no hay nada que hacer, y eso pasa en
# cada pasada nocturna (OMPS mide luz solar) y cuando OMPS falló.

mkdir -p "$STAGING_DIR" "$HOST_WORK"
trap 'rm -rf "$HOST_WORK" "$STAGING_DIR"' EXIT

TOZ_COUNT=0
[ -d "$HOST_L2" ] && TOZ_COUNT=$(enlazar_v8toz "$STAGING_DIR" "$HOST_L2")

if [ "$TOZ_COUNT" -eq 0 ]; then
    echo "ℹ  Sin V8TOZ de la pasada $CLAVE en $HOST_L2 ($VENTANA_INI–$VENTANA_FIN)."
    echo "   Nada que hacer: o es de noche, o falta correr run_omps_edr.sh -p $CLAVE"
    exit 0
fi

# ==============================================================================
# VALIDACIÓN DEL AMBIENTE
# ==============================================================================

if [ ! -f "$SIF_TOS" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_TOS" >&2
    exit 1
fi

mkdir -p "$LOG_DIR" "$STATE_DIR"
LOG_FILE="$LOG_DIR/omps_tos_${TIMESTAMP}_${CLAVE}.log"

echo "  V8TOZ:  $TOZ_COUNT gránulos" | tee -a "$LOG_FILE"
echo "  Salida: $HOST_L2"            | tee -a "$LOG_FILE"

# ==============================================================================
# PROCESAMIENTO
# ==============================================================================
# -W /work: ahí escribe los V8TOS y su log. --pwd /work, porque todo apptainer
# exec necesita un pwd escribible y el de procesar_pasada.sh es /. El staging
# lleva enlaces duros o simbólicos a $HOST_L2, que por eso se monta sobre sí
# mismo. El driver colorea su log con códigos ANSI aunque no escriba a una
# terminal, y no respeta NO_COLOR: se le quitan con sed. Con pipefail, el código
# que queda es el de apptainer, no el de sed.

echo "" | tee -a "$LOG_FILE"
echo ">>> Ejecutando cspp-omps-tos.sh..." | tee -a "$LOG_FILE"

EXIT_CODE=0
apptainer exec \
    --bind "$STAGING_DIR:/input" \
    --bind "$HOST_L2:$HOST_L2" \
    --bind "$HOST_WORK:/work" \
    --pwd /work \
    "$SIF_TOS" /bin/bash -c "
        export HDF5_USE_FILE_LOCKING=FALSE
        export LC_ALL=C
        source \$CSPP_OMPS_V8TOS_HOME/cspp-omps-tos_env.sh
        cspp-omps-tos.sh -v -W /work /input
    " 2>&1 | sed -u 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE" || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP OMPS V8TOS falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                      | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR"                        | tee -a "$LOG_FILE"
    trap - EXIT
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN Y ENTREGA
# ==============================================================================
# Un V8TOS por cada V8TOZ (manual §2.4), así que la cuenta es directa. El
# driver, además, remata cada tramo con
#   Runset k => NOAA20: <ini> -> <fin>, exit:0, inputs/outputs=(7/7)
# y se exige que todos digan exit:0: un tramo puede caer sin que caiga el resto.

#
# Salvo los gránulos que el driver descarta por estar de noche (SZA > 90):
# los anuncia con un WARN cada uno y no les saca V8TOS. OMPS sí deja V8TOZ de
# alguna pasada de madrugada —j01_d20261115_t084200, los 16 descartados—, así
# que el "sin datos" de procesar_pasada.sh, que mira si hay SDR, no alcanza.
# Esos se descuentan de lo esperado; si son todos, la etapa termina bien, con
# v8tos=0 y la línea "noche" en el marcador para que el resumen diga por qué.

mapfile -t PRODUCTOS < <(find "$HOST_WORK" -maxdepth 1 -type f -name 'V8TOS-EDR*.nc' | sort)
NC_COUNT=${#PRODUCTOS[@]}
NOCHE=$(grep -ac 'excluded for SZA>90' "$LOG_FILE" || true)
ESPERADOS=$(( TOZ_COUNT - NOCHE ))

if [ "$NC_COUNT" -eq 0 ] && [ "$ESPERADOS" -le 0 ]; then
    {
        echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "pasada:    $CLAVE"
        echo "v8toz:     $TOZ_COUNT archivos"
        echo "v8tos:     0 archivos"
        echo "noche:     $NOCHE (SZA>90)"
        echo "duracion:  $DURACION"
        echo "salida:    $HOST_L2"
        echo "log:       $LOG_FILE"
    } > "$MARKER"
    echo "ℹ  Los $TOZ_COUNT V8TOZ de la pasada $CLAVE son de noche (SZA>90): no hay V8TOS que hacer." | tee -a "$LOG_FILE"
    echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"
    exit 0
fi

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: V8TOS terminó sin error pero no generó productos." | tee -a "$LOG_FILE"
    echo "   grep -n 'Runset' $LOG_FILE"                              | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR"                  | tee -a "$LOG_FILE"
    trap - EXIT
    exit 1
fi

TRAMOS=$(grep -acE 'Runset [0-9]+ =>' "$LOG_FILE" || true)
TRAMOS_MAL=$(grep -aE 'Runset [0-9]+ =>' "$LOG_FILE" | grep -vc 'exit:0,' || true)

mv "${PRODUCTOS[@]}" "$HOST_L2/"

# Con menos V8TOS que V8TOZ, lo que salió se entrega igual —el barrido no
# retoma OMPS, así que borrarlo sería perderlo—, pero sin marcador, para que el
# resumen lo cuente.
if [ "$NC_COUNT" -lt "$ESPERADOS" ] || [ "$TRAMOS_MAL" -gt 0 ]; then
    echo "❌ ERROR: V8TOS salió a medias: $NC_COUNT de $ESPERADOS ($NOCHE de noche), $TRAMOS_MAL de $TRAMOS tramo(s) con error." | tee -a "$LOG_FILE"
    echo "   Lo que salió quedó en $HOST_L2, sin marcador." | tee -a "$LOG_FILE"
    echo "   grep -n 'Runset' $LOG_FILE"                     | tee -a "$LOG_FILE"
    exit 1
fi

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "v8toz:     $TOZ_COUNT archivos"
    echo "v8tos:     $NC_COUNT archivos"
    echo "tramos:    $TRAMOS"
    [ "$NOCHE" -eq 0 ] || echo "noche:     $NOCHE (SZA>90)"
    echo "duracion:  $DURACION"
    echo "salida:    $HOST_L2"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "" | tee -a "$LOG_FILE"
echo "✅ ÉXITO: $NC_COUNT V8TOS de la pasada $CLAVE ($TRAMOS tramo(s)) en $DURACION" | tee -a "$LOG_FILE"
echo "   Salida:   $HOST_L2" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER"  | tee -a "$LOG_FILE"
