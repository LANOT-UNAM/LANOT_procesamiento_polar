#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Generación Nivel 2 Atmosphere EDR v1.0
# ==============================================================================
#
# Level 1 (SDR de VIIRS) → Level 2 atmosférico (JRR-*.nc)
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue procesada con éxito, avisa y no hace nada. Una pasada se identifica
# por satélite, fecha y órbita (p. ej. j01_d20260811_b45236), datos que vienen
# en el nombre de los propios SDR.
#
# Requiere todas las bandas de la pasada (SVM*, SVI*, SVDNB, GDNBO, GITCO,
# GMTCO), tal como las deja run_sdr.sh. Se enlazan en un directorio de staging
# para procesar una pasada a la vez, aunque level1 tenga varias acumuladas.
#
# Ancillary dinámico: por omisión NO se descarga (bandera -l), porque en
# operación la descarga la hace update_atmos_ancillary.sh desde cron. Si el
# caché no tiene lo del día, la corrida falla; usa --download para bajarlo al
# vuelo. El caché es EXCLUSIVO de ATMOS: ~6 GB diarios sueltos en la raíz, sin
# subdirectorios, podados por delete_old_anc.sh. No compartirlo con el de CSPP
# SDR, que sí usa subdirectorios por día (2026_01_02_002/).
#
# Uso:
#   ./run_atmos_edr.sh                 # la pasada más reciente pendiente
#   ./run_atmos_edr.sh --download      # permite bajar ancillary al vuelo
#   ./run_atmos_edr.sh --force         # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   ATMOS_SDR_IN     Entrada Level 1  (def. /data/output/jpss/level1/viirs)
#   ATMOS_OUT        Salida Level 2   (def. /data/output/jpss/level2/atmosphere)
#   ATMOS_STATE_DIR  Marcadores .done (def. /data/output/jpss/state/cspp-atmos)
#   ATMOS_CACHE      Caché dinámico   (def. /data/ancillary/atmos)
#   ATMOS_STATIC     Ancillary fijo   (def. /data/opt/CSPP_ATMOS_1_0/anc/static)
#   ATMOS_CONTAINER  Imagen .sif      (def. /opt/containers/cspp_atmos_edr_v1.0.sif)
#   ATMOS_WORK_BASE  Raíz de trabajo  (def. /data/tmp)
#   ATMOS_LOG_BASE   Raíz de logs     (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_ATMOS="${ATMOS_CONTAINER:-/opt/containers/cspp_atmos_edr_v1.0.sif}"

HOST_STATIC="${ATMOS_STATIC:-/data/opt/CSPP_ATMOS_1_0/anc/static}"
HOST_CACHE="${ATMOS_CACHE:-/data/ancillary/atmos}"
HOST_SDR_IN="${ATMOS_SDR_IN:-/data/output/jpss/level1/viirs}"
HOST_EDR_OUT="${ATMOS_OUT:-/data/output/jpss/level2/atmosphere}"
STATE_DIR="${ATMOS_STATE_DIR:-/data/output/jpss/state/cspp-atmos}"

WORK_BASE="${ATMOS_WORK_BASE:-/data/tmp}"
LOG_DIR="${ATMOS_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

CORES="${SLURM_CPUS_PER_TASK:-20}"

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
                  (j01_d20260813_b45264) o cualquier trozo que la identifique
      --download  Quita '-l': CSPP baja el ancillary que falte (requiere red)
  -h, --help      Muestra esta ayuda

Pasadas disponibles en $HOST_SDR_IN:
$(claves_disponibles 2>/dev/null | sed 's/^/  /' || true)
EOF
}

# Deriva la clave de la pasada del nombre de un SDR:
#   GMTCO_j01_d20260811_t1947330_e1948557_b45236_c2026...h5 -> j01_d20260811_b45236
clave_de_pasada() {
    local nombre sat fecha orbita
    nombre=$(basename "$1")

    IFS='_' read -r _ sat fecha _ _ orbita _ <<< "$nombre"

    if [[ "$fecha" != d* ]] || [[ "$orbita" != b* ]]; then
        return 1
    fi

    echo "${sat}_${fecha}_${orbita}"
}

# Las pasadas que hay en el directorio de entrada, una por línea y sin repetir.
claves_disponibles() {
    find "$HOST_SDR_IN" -maxdepth 1 -name 'GMTCO*.h5' -printf '%f\n' 2>/dev/null |
        while IFS= read -r nombre; do
            clave_de_pasada "$nombre" || true
        done | sort -u
}

# Deja en ULTIMO_GMTCO un archivo representativo de la pasada: el más reciente si
# no se pidió ninguna, o el primer gránulo de la que se pida con --pasada. De ahí
# salen la clave y, donde aplica, la ventana temporal con la que se emparejan los
# productos que no llevan órbita en el nombre.
resolver_pasada() {
    local coinciden sat fecha orbita

    if [ -z "$PASADA" ]; then
        ULTIMO_GMTCO=$(find "$HOST_SDR_IN" -maxdepth 1 -name 'GMTCO*.h5' \
                            -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        return 0
    fi

    # --pasada acepta la clave completa o cualquier trozo que la identifique:
    # "j01_d20260813_b45264", "d20260813" o hasta "45264". Se resuelve contra las
    # pasadas que de verdad estén en el directorio, así que un valor ambiguo o
    # inexistente se caza aquí y no a media corrida.
    mapfile -t coinciden < <(claves_disponibles | grep -F -- "$PASADA" || true)

    if [ "${#coinciden[@]}" -eq 0 ]; then
        echo "ERROR: Ninguna pasada de $HOST_SDR_IN coincide con '$PASADA'" >&2
        echo "       Disponibles:" >&2
        claves_disponibles | sed 's/^/         /' >&2
        return 1
    fi

    if [ "${#coinciden[@]}" -gt 1 ]; then
        echo "ERROR: '$PASADA' coincide con más de una pasada; hay que ser más específico:" >&2
        printf '         %s\n' "${coinciden[@]}" >&2
        return 1
    fi

    IFS='_' read -r sat fecha orbita <<< "${coinciden[0]}"
    ULTIMO_GMTCO=$(find "$HOST_SDR_IN" -maxdepth 1 -name "GMTCO_${sat}_${fecha}_*_${orbita}_*.h5" \
                        | sort | head -1)
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
resolver_pasada || exit 1

if [ -z "$ULTIMO_GMTCO" ]; then
    echo "No hay SDR que procesar en $HOST_SDR_IN (no se ven archivos GMTCO*)."
    exit 0
fi

if ! CLAVE=$(clave_de_pasada "$ULTIMO_GMTCO"); then
    echo "ERROR: No se pudo derivar la pasada del nombre: $(basename "$ULTIMO_GMTCO")" >&2
    echo "       Se esperaba algo como GMTCO_j01_d20260811_t1947330_e1948557_b45236_c...h5" >&2
    exit 1
fi

IFS='_' read -r SAT FECHA ORBITA <<< "$CLAVE"

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
# STAGING DE LA PASADA
# ==============================================================================
# viirs_atmos.sh procesa TODOS los SDR del directorio que se le pase, así que se
# enlaza solo la pasada elegida. Los enlaces apuntan a rutas del host, por eso
# más abajo se monta HOST_SDR_IN en su propia ruta además del staging.

STAGING_DIR="${HOST_WORK}/input_pasada"
mkdir -p "$STAGING_DIR" "$HOST_CACHE" "$HOST_EDR_OUT" "$LOG_DIR" "$STATE_DIR"

ln -sf "$HOST_SDR_IN"/*_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5 "$STAGING_DIR"/ 2>/dev/null || true

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

if [ "$DOWNLOAD" -eq 1 ]; then
    FLAG_LOCAL=""
    echo "  Ancillary: se descargará lo que falte (--download)" | tee -a "$LOG_FILE"
else
    FLAG_LOCAL="-l"
    echo "  Ancillary: solo caché local (precargado por cron)"  | tee -a "$LOG_FILE"
fi

# Referencia para contar solo lo generado en esta corrida. No sirve el mtime del
# log (se escribe durante toda la ejecución, así que queda más nuevo que los
# productos) ni el del directorio de salida.
REF_FILE=$(mktemp -t atmos_edr_ref_XXXXXX)
trap "rm -f $REF_FILE" EXIT

EXIT_CODE=0
apptainer exec \
    --bind "$STAGING_DIR:/input_sdr" \
    --bind "$HOST_SDR_IN:$HOST_SDR_IN" \
    --bind "$HOST_EDR_OUT:/output_edr" \
    --bind "$HOST_STATIC:/opt/CSPP_ATMOS_1_0/anc/static" \
    --bind "$HOST_CACHE:/opt/CSPP_ATMOS_1_0/anc/cache" \
    --bind "$HOST_WORK:/work" \
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
        viirs_atmos.sh -v $FLAG_LOCAL -W /work -p $CORES /input_sdr
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
    " >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP ATMOS falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                   | tee -a "$LOG_FILE"
    echo "   El directorio de trabajo se conserva: $HOST_WORK"           | tee -a "$LOG_FILE"
    exit $EXIT_CODE
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
