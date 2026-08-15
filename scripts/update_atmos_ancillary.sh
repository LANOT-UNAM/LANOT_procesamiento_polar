#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Precarga del ancillary dinámico de CSPP VIIRS ATMOS
# ==============================================================================
#
# Descarga al caché local los datos auxiliares que ATMOS necesita (CMCSST, GFS,
# mapa de nieve, AMSR2) y poda los que ya pasaron de 14 días.
#
# Separa la descarga del procesamiento: así run_atmos_edr.sh puede correr con
# '-l' (sin red) y una pasada nunca se queda esperando a que responda el
# servidor de SSEC.
#
# Cron sugerido (crontab de lanotadm). Cuatro veces al día porque el GFS tiene
# cuatro corridas diarias (00z, 06z, 12z, 18z) y el manual (§2.4) pide juntar
# las cuatro:
#
#   17 2,8,14,20 * * * /opt/lanot/polares/scripts/update_atmos_ancillary.sh
#
# El podado va incluido en cada corrida: delete_old_anc.sh solo borra lo que
# pasa de 14 días, así que es idempotente y no hace falta un cron aparte.
#
# Variables de entorno (para pruebas o rutas alternas):
#   ATMOS_CACHE      Caché dinámico (def. /data/ancillary/atmos)
#   ATMOS_CONTAINER  Imagen .sif    (def. /opt/containers/cspp_atmos_edr_v1.0.sif)
#   ATMOS_LOG_BASE   Raíz de logs   (def. /var/log/lanot/polares)
#
# ==============================================================================

set -euo pipefail

SIF_ATMOS="${ATMOS_CONTAINER:-/opt/containers/cspp_atmos_edr_v1.0.sif}"
HOST_CACHE="${ATMOS_CACHE:-/data/ancillary/atmos}"
LOG_DIR="${ATMOS_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')

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

if [ ! -f "$SIF_ATMOS" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_ATMOS" >&2
    exit 1
fi

mkdir -p "$HOST_CACHE" "$LOG_DIR"
LOG_FILE="$LOG_DIR/atmos_ancillary_${TIMESTAMP}.log"

echo "=== ACTUALIZANDO ANCILLARY DINÁMICO DE ATMOS: $(date) ===" | tee -a "$LOG_FILE"
echo "  Caché: $HOST_CACHE" | tee -a "$LOG_FILE"

ANTES=$(find "$HOST_CACHE" -maxdepth 1 -type f 2>/dev/null | wc -l)

# Se monta ÚNICAMENTE el caché de ATMOS: delete_old_anc.sh borra por antigüedad
# dentro de CSPP_DYNAMIC_ANCIL_DIR, así que acotar los binds limita el daño
# posible si alguna vez se le pasara un directorio equivocado.
EXIT_CODE=0
apptainer exec \
    --bind "$HOST_CACHE:/opt/CSPP_ATMOS_1_0/anc/cache" \
    "$SIF_ATMOS" /bin/bash -c "
        export CSPP_VIIRS_ATMOS_HOME=/opt/CSPP_ATMOS_1_0
        export CSPP_DYNAMIC_ANCIL_DIR=\$CSPP_VIIRS_ATMOS_HOME/anc/cache
        export PATH=\$CSPP_VIIRS_ATMOS_HOME/bin:\$PATH
        export HDF5_USE_FILE_LOCKING=FALSE

        echo '--- [1/2] Descargando ancillary más reciente (atmos_ancillary.sh) ---'
        atmos_ancillary.sh
        RC=\$?

        if [ \$RC -ne 0 ]; then
            echo \"--- atmos_ancillary.sh terminó con código \$RC ---\"
            exit \$RC
        fi

        echo '--- [2/2] Podando archivos de más de 14 días (delete_old_anc.sh) ---'
        delete_old_anc.sh
    " >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DESPUES=$(find "$HOST_CACHE" -maxdepth 1 -type f 2>/dev/null | wc -l)
DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: La actualización falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE" | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

echo "✅ ÉXITO: caché con $DESPUES archivos (antes $ANTES) en $DURACION" | tee -a "$LOG_FILE"
echo "   Espacio usado: $(du -sh "$HOST_CACHE" | cut -f1)" | tee -a "$LOG_FILE"

# Los logs de esta tarea se acumulan rápido: se corren 4 veces al día
find "$LOG_DIR" -name "atmos_ancillary_*.log" -mtime +30 -delete
