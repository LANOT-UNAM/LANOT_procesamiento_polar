#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Generación Nivel 2 Atmosphere EDR v1.0
# ==============================================================================
#
# Level 1 (SDR de VIIRS) → Level 2 atmosférico (JRR-*.nc)
#
# Requiere TODAS las bandas de la pasada en el mismo directorio (SVM*, SVI*,
# SVDNB, GDNBO, GITCO, GMTCO), tal como las deja run_sdr.sh.
#
# Ancillary dinámico: CSPP descarga lo que falte (CMCSST, GFS, mapa de nieve)
# al caché indicado por CSPP_DYNAMIC_ANCIL_DIR. Ese caché es EXCLUSIVO de
# ATMOS: guarda ~6 GB por día en la raíz, sin subdirectorios diarios, y se poda
# con delete_old_anc.sh. No debe compartirse con el caché de CSPP SDR, que sí
# usa subdirectorios por día (2026_01_02_002/...).
#
# Variables de entorno (para pruebas o rutas alternas):
#   ATMOS_SDR_IN     Entrada Level 1  (def. /data/output/jpss/level1/viirs)
#   ATMOS_OUT        Salida Level 2   (def. /data/output/jpss/level2/atmosphere)
#   ATMOS_CACHE      Caché dinámico   (def. /data/ancillary/atmos)
#   ATMOS_STATIC     Ancillary fijo   (def. /data/opt/CSPP_ATMOS_1_0/anc/static)
#   ATMOS_CONTAINER  Imagen .sif      (def. /opt/containers/cspp_atmos_edr_v1.0.sif)
#   ATMOS_WORK_BASE  Raíz de trabajo  (def. /data/tmp)
#   ATMOS_LOG_BASE   Raíz de logs     (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_ATMOS="${ATMOS_CONTAINER:-/opt/containers/cspp_atmos_edr_v1.0.sif}"

# Rutas en Lustre
HOST_STATIC="${ATMOS_STATIC:-/data/opt/CSPP_ATMOS_1_0/anc/static}"
HOST_CACHE="${ATMOS_CACHE:-/data/ancillary/atmos}"
HOST_SDR_IN="${ATMOS_SDR_IN:-/data/output/jpss/level1/viirs}"
HOST_EDR_OUT="${ATMOS_OUT:-/data/output/jpss/level2/atmosphere}"

WORK_BASE="${ATMOS_WORK_BASE:-/data/tmp}"
LOG_DIR="${ATMOS_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

# Hilos de procesamiento (respeta la asignación de Slurm si la hay)
CORES="${SLURM_CPUS_PER_TASK:-20}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')
HOST_WORK="${WORK_BASE}/atmos_work_${TIMESTAMP}"

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

if [ ! -d "$HOST_SDR_IN" ]; then
    echo "ERROR: Directorio de SDR no encontrado: $HOST_SDR_IN" >&2
    exit 1
fi

if ! compgen -G "$HOST_SDR_IN/GMTCO*.h5" > /dev/null; then
    echo "ERROR: No hay SDR que procesar en $HOST_SDR_IN (no se ven archivos GMTCO*)" >&2
    exit 1
fi

# El caché es propio de ATMOS y lo llena CSPP en la primera corrida
mkdir -p "$HOST_CACHE" "$HOST_WORK" "$HOST_EDR_OUT" "$LOG_DIR"

LOG_FILE="$LOG_DIR/atmos_edr_$TIMESTAMP.log"

echo "=== INICIANDO PROCESAMIENTO ATMOSPHERE EDR v1.0 ===" | tee -a "$LOG_FILE"
echo "  Entrada: $HOST_SDR_IN"          | tee -a "$LOG_FILE"
echo "  Salida:  $HOST_EDR_OUT"         | tee -a "$LOG_FILE"
echo "  Caché:   $HOST_CACHE"           | tee -a "$LOG_FILE"
echo "  Hilos:   $CORES"                | tee -a "$LOG_FILE"

# ==============================================================================
# EJECUCIÓN
# ==============================================================================
# Sin '-l': esa bandera desactiva la descarga del ancillary remoto y, con el
# caché vacío, CMCSST_DAILY aborta y la corrida entrega 0 productos.
# Cuando exista update_atmos_ancillary.sh en cron, se puede volver a poner.

# Referencia para contar solo lo generado en esta corrida. No sirve el mtime del
# log (se escribe durante toda la ejecución, así que queda más nuevo que los
# productos) ni el del directorio de salida.
REF_FILE=$(mktemp -t atmos_edr_ref_XXXXXX)
trap "rm -f $REF_FILE" EXIT

EXIT_CODE=0
apptainer exec \
    --bind "$HOST_SDR_IN:/input_sdr" \
    --bind "$HOST_EDR_OUT:/output_edr" \
    --bind "$HOST_STATIC:/opt/CSPP_ATMOS_1_0/anc/static" \
    --bind "$HOST_CACHE:/opt/CSPP_ATMOS_1_0/anc/cache" \
    --bind "$HOST_WORK:/work" \
    "$SIF_ATMOS" /bin/bash -c "
        export CSPP_VIIRS_ATMOS_HOME=/opt/CSPP_ATMOS_1_0
        export CSPP_DYNAMIC_ANCIL_DIR=\$CSPP_VIIRS_ATMOS_HOME/anc/cache
        export PATH=\$CSPP_VIIRS_ATMOS_HOME/bin:\$PATH
        export HDF5_USE_FILE_LOCKING=FALSE

        # Verificación del montaje de Config
        if [ ! -d \"/opt/CSPP_ATMOS_1_0/anc/static/Config\" ]; then
            echo 'FATAL: El contenedor no ve la carpeta Config.'
            exit 1
        fi

        echo '--- Ejecutando algoritmos Enterprise ---'
        viirs_atmos.sh -v -W /work -p $CORES /input_sdr
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

DURACION=$(( $(date '+%s') - START_EPOCH ))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP ATMOS falló (código $EXIT_CODE) tras ${DURACION}s" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                     | tee -a "$LOG_FILE"
    echo "   El directorio de trabajo se conserva: $HOST_WORK"             | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN DE PRODUCTOS
# ==============================================================================
# CSPP puede terminar con código 0 sin generar nada: si falta ancillary
# dinámico, cada gránulo aborta y el log remata con "0 products of N".

NC_COUNT=$(find "$HOST_EDR_OUT" -maxdepth 1 -name '*.nc' -newer "$REF_FILE" 2>/dev/null | wc -l)

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: CSPP ATMOS terminó sin error pero no generó productos."  | tee -a "$LOG_FILE"
    echo "   Busca en el log la línea 'products of' y los FATAL asociados:"  | tee -a "$LOG_FILE"
    echo "   grep -E 'products of|FATAL|ERROR \\(USR' $LOG_FILE"             | tee -a "$LOG_FILE"
    echo "   Causa típica: falta ancillary dinámico (CMCSST, GFS) en $HOST_CACHE" | tee -a "$LOG_FILE"
    echo "   El directorio de trabajo se conserva: $HOST_WORK"               | tee -a "$LOG_FILE"
    exit 1
fi

echo "✅ ÉXITO: $NC_COUNT productos generados en $HOST_EDR_OUT (${DURACION}s)" | tee -a "$LOG_FILE"

# Limpieza segura del temporal, solo cuando hubo productos
rm -rf "$HOST_WORK"
