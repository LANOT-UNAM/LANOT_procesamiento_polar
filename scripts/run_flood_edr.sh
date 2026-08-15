#!/bin/bash
#SBATCH --job-name=cspp_flood
#SBATCH --output=logs/flood_%j.out
#SBATCH --error=logs/flood_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --partition=normal
# ==============================================================================
# LANOT - UNAM | CSPP VIIRS Flood Detection v2.0
# ==============================================================================
#
# Level 1 (SDR de banda I) → detección de inundaciones a 375 m
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR y,
# si ya fue procesada, avisa y no hace nada. Una pasada se identifica por
# satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
#
# Entradas: GITCO* y SVI01-05* de la pasada. No usa ancillary dinámico: todo lo
# estático (DEM, máscaras de agua, climatologías, árboles de decisión) viene
# dentro del contenedor, así que no depende de la red.
#
# OJO CON LAS PASADAS NOCTURNAS: el algoritmo solo procesa gránulos diurnos
# (N_Day_Night_Flag "Day" o "Both"), así que una pasada de noche termina bien y
# sin productos. Por eso, a diferencia de los demás eslabones, aquí "cero
# productos" NO se trata como error: se marca la pasada como atendida para que
# no se reintente en cada corrida, y se avisa en el resumen.
#
# Uso:
#   ./run_flood_edr.sh            # la pasada más reciente pendiente
#   ./run_flood_edr.sh --force    # reprocesa aunque ya tenga marcador
#
# Variables de entorno (para pruebas o rutas alternas):
#   FLOOD_SDR_IN     Entrada Level 1  (def. /data/output/jpss/level1/viirs)
#   FLOOD_OUT        Salida           (def. /data/output/jpss/level2/flood)
#   FLOOD_GEOTIFF    GeoTIFF de vista (def. /data/output/jpss/geotiff/flood)
#   FLOOD_STATE_DIR  Marcadores .done (def. /data/output/jpss/state/cspp-flood)
#   FLOOD_CONTAINER  Imagen .sif      (def. /opt/containers/cspp_flood_v2.0.sif)
#   FLOOD_WORK_BASE  Raíz de staging  (def. /data/tmp)
#   FLOOD_LOG_BASE   Raíz de logs     (def. /var/log/lanot/polares)
#   FLOOD_AOI        Archivo de área de interés, opcional (ver manual §3.3)
#
# ==============================================================================

set -euo pipefail

SIF_IMAGE="${FLOOD_CONTAINER:-/opt/containers/cspp_flood_v2.0.sif}"

INPUT_SDR_DIR="${FLOOD_SDR_IN:-/data/output/jpss/level1/viirs}"
OUTPUT_DIR="${FLOOD_OUT:-/data/output/jpss/level2/flood}"
# El .tif no lo hace Polar2Grid sino el propio CSPP, con el convertidor que trae
# el bundle. Es formato de salida del producto, como el .nc, así que se genera
# aquí; lo que NO se hace aquí es la vista — de eso sigue encargándose
# run_polar2grid_edr.sh, que es el renderizador único de Level 2.
GEOTIFF_DIR="${FLOOD_GEOTIFF:-/data/output/jpss/geotiff/flood}"
STATE_DIR="${FLOOD_STATE_DIR:-/data/output/jpss/state/cspp-flood}"

WORK_BASE="${FLOOD_WORK_BASE:-/data/tmp}"
LOG_DIR="${FLOOD_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

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
  -f, --force          Ignora el marcador de procesado
  -k, --keep-staging   Conserva el directorio de enlaces, para diagnosticar
  -h, --help           Muestra esta ayuda
EOF
}

# GMTCO_j01_d20260811_t1947330_e1948557_b45236_c2026...h5 -> j01_d20260811_b45236
clave_de_pasada() {
    local nombre sat fecha orbita
    nombre=$(basename "$1")
    IFS='_' read -r _ sat fecha _ _ orbita _ <<< "$nombre"
    if [[ "$fecha" != d* ]] || [[ "$orbita" != b* ]]; then
        return 1
    fi
    echo "${sat}_${fecha}_${orbita}"
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

# Se prefiere el enlace duro: algunas herramientas recorren la entrada con
# "find -type f", que no encuentra enlaces simbólicos.
enlazar() {
    ln -f "$1" "$2" 2>/dev/null || ln -sf "$1" "$2"
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================

FORCE=0
KEEP=0

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)        FORCE=1 ;;
        -k|--keep-staging) KEEP=1 ;;
        -h|--help)         uso; exit 0 ;;
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
STAGING_DIR="${WORK_BASE}/flood_staging_${JOB_ID}"
WORK_DIR="${WORK_BASE}/flood_work_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$INPUT_SDR_DIR" ]; then
    echo "ERROR: Directorio de SDR no encontrado: $INPUT_SDR_DIR" >&2
    exit 1
fi

ULTIMO_GITCO=$(find "$INPUT_SDR_DIR" -maxdepth 1 -name 'GITCO*.h5' \
                    -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$ULTIMO_GITCO" ]; then
    echo "No hay SDR de banda I que procesar en $INPUT_SDR_DIR (no se ven archivos GITCO*)."
    exit 0
fi

if ! CLAVE=$(clave_de_pasada "$ULTIMO_GITCO"); then
    echo "ERROR: No se pudo derivar la pasada del nombre: $(basename "$ULTIMO_GITCO")" >&2
    exit 1
fi

IFS='_' read -r SAT FECHA ORBITA <<< "$CLAVE"

echo "=== CSPP VIIRS Flood v2.0 | pasada $CLAVE ==="

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
# VALIDACIÓN Y STAGING
# ==============================================================================

if [ ! -f "$SIF_IMAGE" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_IMAGE" >&2
    exit 1
fi

if [ -n "${FLOOD_AOI:-}" ] && [ ! -f "$FLOOD_AOI" ]; then
    echo "ERROR: Archivo de área de interés no encontrado: $FLOOD_AOI" >&2
    exit 1
fi

mkdir -p "$STAGING_DIR" "$WORK_DIR" "$OUTPUT_DIR" "$GEOTIFF_DIR" "$LOG_DIR" "$STATE_DIR"

limpiar() {
    if [ "$KEEP" -eq 1 ]; then
        echo "--keep-staging: se conserva $STAGING_DIR"
        rm -rf "$WORK_DIR"; rm -f "${REF_FILE:-}"
    else
        rm -rf "$STAGING_DIR" "$WORK_DIR" "${REF_FILE:-}"
    fi
}
trap limpiar EXIT

# Flood solo necesita la banda I y su geolocalización
shopt -s nullglob
for f in "$INPUT_SDR_DIR"/GITCO_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5 \
         "$INPUT_SDR_DIR"/SVI0[1-5]_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5; do
    enlazar "$f" "$STAGING_DIR"/
done
shopt -u nullglob

SDR_COUNT=$(find "$STAGING_DIR" -name '*.h5' | wc -l)

if [ "$SDR_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR de banda I de la pasada $CLAVE" >&2
    exit 1
fi

LOG_FILE="$LOG_DIR/flood_${TIMESTAMP}_${CLAVE}.log"

echo "  SDR:     $SDR_COUNT archivos (GITCO* + SVI0[1-5]*)" | tee -a "$LOG_FILE"
echo "  Salida:  $OUTPUT_DIR"                               | tee -a "$LOG_FILE"
echo "  Hilos:   $CORES"                                    | tee -a "$LOG_FILE"

# ==============================================================================
# EJECUCIÓN
# ==============================================================================
# El driver no tiene opción de directorio de salida (-o no existe en su línea de
# comandos) y deja los productos en el DIRECTORIO DE TRABAJO, no en el actual:
#   "Moving output files from /work/NOAA_VIIRS_Flood_..._run_0 to /work"
# Por eso hay que moverlos desde /work al destino antes de limpiar, igual que en
# run_atmos_edr.sh. Con --pwd /work, además, los intermedios que escriba en el
# directorio actual no ensucian la salida.

REF_FILE=$(mktemp -t flood_ref_XXXXXX)

OPCION_AOI=""
if [ -n "${FLOOD_AOI:-}" ]; then
    OPCION_AOI="-a /aoi/$(basename "$FLOOD_AOI")"
    echo "  AOI:     $FLOOD_AOI" | tee -a "$LOG_FILE"
fi

BIND_OPTS=(
    -B "${STAGING_DIR}":/input_data
    -B "${OUTPUT_DIR}":/output_data
    -B "${GEOTIFF_DIR}":/output_tif
    -B "${WORK_DIR}":/work
    -B "${INPUT_SDR_DIR}":"${INPUT_SDR_DIR}"
)
[ -n "${FLOOD_AOI:-}" ] && BIND_OPTS+=( -B "$(dirname "$FLOOD_AOI")":/aoi )

EXIT_CODE=0
apptainer exec \
    --env LC_ALL=C \
    "${BIND_OPTS[@]}" \
    --pwd /work \
    "${SIF_IMAGE}" \
    /bin/bash -c "
        . \$CSPP_VIIRS_FLOOD_HOME/cspp_viirs_flood_env.sh
        \$CSPP_VIIRS_FLOOD_HOME/bin/cspp_viirs_flood.sh -W /work -n $CORES -vv $OPCION_AOI /input_data
        RC=\$?

        if [ \$RC -ne 0 ]; then
            echo \"--- cspp_viirs_flood.sh terminó con código \$RC ---\"
            exit \$RC
        fi

        # GeoTIFF para la vista, con el convertidor del propio bundle: Polar2Grid
        # no puede con esto —su lector viirs_edr_flood es para el formato HDF de
        # la v1.x— y no hace falta. cspp_viirs_flood2tif.sh saca el dataset
        # WaterDetection a Byte con EPSG:4326, tomando las esquinas de los
        # atributos del NetCDF, y le pega la paleta flood.ct. O sea que el .tif
        # sale ya como IMAGEN con colormap embebido, no como dato: por eso lo
        # viste mapdrawer y no geotiff2view.
        #
        # Va antes del traslado porque el convertidor escribe junto a la entrada
        # (OUTPUT=\${INPUT/.nc/.tif}) y aquí /work sí es escribible. Los .tif por
        # gránulo se quedan en /work y se los lleva la limpieza; solo sobrevive
        # el fusionado.
        if ls /work/*.nc > /dev/null 2>&1; then
            echo '--- Convirtiendo a GeoTIFF ---'
            for f in /work/*.nc; do
                \$CSPP_VIIRS_FLOOD_HOME/bin/cspp_viirs_flood2tif.sh "\$f"
            done

            # Un .tif por gránulo no sirve de vista: la pasada son ~10. El sello
            # del primero da el nombre, en el formato que metadata.py de
            # LANOT_tools sabe leer (AAAAMMDD_HHMMSS).
            PRIMERO=\$(ls /work/*.nc | sort | head -1)
            SELLO=\$(basename "\$PRIMERO" | grep -oE '_s[0-9]{15}' | head -1)
            SELLO=\${SELLO#_s}
            SALIDA=/output_tif/${SAT}_viirs_flood_\${SELLO:0:8}_\${SELLO:8:6}.tif

            echo "--- Fusionando gránulos en \$SALIDA ---"
            \$CSPP_VIIRS_FLOOD_HOME/bin/cspp_viirs_tifmerge.sh -W /work -o "\$SALIDA" /work/*.tif
        fi

        echo '--- Trasladando resultados (NetCDF) a Lustre ---'
        find /work -maxdepth 1 -name '*.nc' -exec mv -t /output_data/ {} +
    " >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP Flood falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                   | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

NC_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 -name '*.nc' -newer "$REF_FILE" 2>/dev/null | wc -l)

# ==============================================================================
# VERIFICACIÓN
# ==============================================================================
# Cero productos puede significar dos cosas muy distintas, y confundirlas ya
# costó una corrida: el algoritmo solo trabaja de día, así que una pasada
# nocturna termina bien y sin salida; pero si procesó gránulos y aun así no hay
# archivos, algo se rompió. Se distingue con el propio reporte del driver, que
# lista los gránulos que salieron adelante:
#     successful_runs   []                 -> no procesó nada (de noche)
#     successful_runs   ['J01...', ...]    -> sí procesó
GRANULOS_OK=0
if grep -qE "successful_runs +\[.+\]" "$LOG_FILE"; then
    GRANULOS_OK=1
fi

if [ "$NC_COUNT" -eq 0 ] && [ "$GRANULOS_OK" -eq 1 ]; then
    echo "❌ ERROR: el driver procesó gránulos pero no quedó ningún producto." | tee -a "$LOG_FILE"
    echo "   Revisa dónde los dejó; deberían estar en $OUTPUT_DIR."           | tee -a "$LOG_FILE"
    echo "   grep 'output files' $LOG_FILE"                                    | tee -a "$LOG_FILE"
    echo "   No se escribió el marcador: la pasada se reintentará."            | tee -a "$LOG_FILE"
    exit 1
fi

# ==============================================================================
# MARCADOR
# ==============================================================================
# Si no procesó gránulos, se marca igual para no reintentar la pasada en cada
# corrida, pero el resumen lo dice con todas sus letras.

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "sdr:       $SDR_COUNT archivos de entrada"
    echo "productos: $NC_COUNT archivos .nc"
    echo "duracion:  $DURACION"
    echo "salida:    $OUTPUT_DIR"
    echo "log:       $LOG_FILE"
} > "$MARKER"

if [ "$NC_COUNT" -eq 0 ]; then
    echo "⚠  Sin productos para la pasada $CLAVE ($DURACION)"                    | tee -a "$LOG_FILE"
    echo "   Es lo esperado si la pasada es nocturna: el algoritmo solo procesa" | tee -a "$LOG_FILE"
    echo "   gránulos diurnos. Si sabes que era de día, revisa el log."          | tee -a "$LOG_FILE"
    echo "   Marcador: $MARKER"                                                  | tee -a "$LOG_FILE"
    exit 0
fi

echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE en $OUTPUT_DIR ($DURACION)" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"
