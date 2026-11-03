#!/bin/bash
#SBATCH --job-name=cspp_flood
#SBATCH --output=/var/log/lanot/polares/cspp-edr/slurm_flood_%j.out
#SBATCH --error=/var/log/lanot/polares/cspp-edr/slurm_flood_%j.err
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
# satélite, fecha y hora de inicio (p. ej. j01_d20260811_t194733;
# ver pasadas.sh).
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
#   ./run_flood_edr.sh                      # la pasada más reciente pendiente
#   ./run_flood_edr.sh --force              # reprocesa aunque ya tenga marcador
#   ./run_flood_edr.sh --pasada d20260813   # una pasada concreta, no la más reciente
#
# --pasada existe sobre todo para las pruebas: la pasada más reciente puede ser
# nocturna, y de noche este eslabón no produce nada (ver abajo), así que no sirve
# para verificar la conversión a GeoTIFF. Se le da la clave completa o cualquier
# trozo que la identifique; si coincide con varias, las lista y no hace nada.
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
  $0                          Procesa la pasada más reciente de $INPUT_SDR_DIR
  $0 --force                  Reprocesa aunque ya exista el marcador
  $0 --pasada d20260813       Procesa una pasada concreta, no la más reciente

Opciones:
  -f, --force          Ignora el marcador de procesado
  -p, --pasada         Pasada concreta en vez de la más reciente: la clave completa
                       (j01_d20260813_t191402) o cualquier trozo que la identifique
  -k, --keep-staging   Conserva los directorios de enlaces y de trabajo, para diagnosticar
  -h, --help           Muestra esta ayuda

Pasadas disponibles en $INPUT_SDR_DIR:
$(listar_pasadas "$INPUT_SDR_DIR" GITCO 2>/dev/null | cut -d' ' -f1 | sed 's/^/  /' || true)
EOF
}

# Qué es una pasada y cómo se elige: por tiempo, no por órbita (ver pasadas.sh).
# Fija CLAVE, SAT, FECHA y la ventana VENTANA_INI – VENTANA_FIN.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/pasadas.sh"

# El código de satélite de los SDR (j01) no es el que usa Polar2Grid en los
# nombres de sus salidas (noaa20). El .tif de flood cae en el mismo árbol que
# esas salidas y lo filtra el mismo renderizador, así que se nombra como ellas;
# si no, en vistas/ queda ordenado aparte de todo lo demás de su propia pasada.
# El código de los SDR se sigue usando para leer los nombres de ENTRADA.
sat_polar2grid() {
    case "$1" in
        npp) echo npp    ;;
        j01) echo noaa20 ;;
        j02) echo noaa21 ;;
        *)   echo "$1"   ;;
    esac
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
PASADA=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force)        FORCE=1 ;;
        -k|--keep-staging) KEEP=1 ;;
        -h|--help)         uso; exit 0 ;;
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
STAGING_DIR="${WORK_BASE}/flood_staging_${JOB_ID}"
WORK_DIR="${WORK_BASE}/flood_work_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$INPUT_SDR_DIR" ]; then
    echo "ERROR: Directorio de SDR no encontrado: $INPUT_SDR_DIR" >&2
    exit 1
fi

resolver_pasada "$INPUT_SDR_DIR" GITCO "$PASADA" || exit 1

if [ -z "$CLAVE" ]; then
    echo "No hay SDR de banda I que procesar en $INPUT_SDR_DIR (no se ven archivos GITCO*)."
    exit 0
fi

SAT_VISTA=$(sat_polar2grid "$SAT")

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

# Con -k se conserva también el directorio de trabajo: ahí quedan los logs por
# gránulo (NOAA_VIIRS_Flood_*_run_0_*.log), que son lo único que dice qué vio el
# binario. Sin ellos, una pasada sin productos no se puede distinguir de una rota.
limpiar() {
    if [ "$KEEP" -eq 1 ]; then
        echo "--keep-staging: se conservan $STAGING_DIR y $WORK_DIR"
        rm -f "${REF_FILE:-}"
    else
        rm -rf "$STAGING_DIR" "$WORK_DIR" "${REF_FILE:-}"
    fi
}
trap limpiar EXIT

# Flood solo necesita la banda I y su geolocalización
while IFS= read -r f; do
    enlazar "$f" "$STAGING_DIR"/
done < <(archivos_de_pasada "$INPUT_SDR_DIR" GITCO; archivos_de_pasada "$INPUT_SDR_DIR" 'SVI0[1-5]')

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

# OJO CON LAS COMILLAS: el guion de adentro va como argumento de `bash -c` dentro
# de UNA cadena entrecomillada, así que toda comilla doble interior tiene que ir
# escapada (\"). Una sin escapar cierra la cadena del shell de afuera: lo que
# sigue queda sujeto a separación de palabras y el guion se parte en pedazos. El
# 2026-08-14 pasó exactamente eso con `echo "--- Fusionando..."`, y el síntoma no
# se parece a la causa —"Fusionando: -c: line 38: syntax error: unexpected end of
# file"—: `Fusionando` era el \$0 del bash de adentro. Peor: bash ejecuta lo que
# va leyendo, así que CSPP corrió completo y el guion murió después, al llegar al
# `if` sin `fi`, dejando sin ejecutar el traslado a la salida.
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
                \$CSPP_VIIRS_FLOOD_HOME/bin/cspp_viirs_flood2tif.sh \"\$f\"
            done

            # Un .tif por gránulo no sirve de vista: la pasada son ~10. El sello
            # del primero da el nombre, en el formato que metadata.py de
            # LANOT_tools sabe leer (AAAAMMDD_HHMMSS).
            PRIMERO=\$(ls /work/*.nc | sort | head -1)
            SELLO=\$(basename \"\$PRIMERO\" | grep -oE '_s[0-9]{15}' | head -1)
            SELLO=\${SELLO#_s}

            if [ -z \"\$SELLO\" ]; then
                echo \"AVISO: no se pudo derivar el sello temporal de \$PRIMERO\"
                echo \"       No se fusiona el GeoTIFF; los .nc sí se conservan.\"
            else
                echo '--- Fusionando gránulos ---'
                \$CSPP_VIIRS_FLOOD_HOME/bin/cspp_viirs_tifmerge.sh -W /work /work/*.tif
                RC_MERGE=\$?

                # tifmerge NO acepta destino: nombra él la salida —el sello de
                # inicio del primer gránulo, el de fin del último y su propia
                # marca de creación, con sufijo _merged— y la deja junto a la
                # entrada, en /work. Pasarle -o no da error y tampoco escribe
                # nada en la ruta pedida (verificado en tahan el 2026-08-14: la
                # fusión de los 10 gránulos apareció como
                # VIIRS-Flood_v2r0_n20_s…_e…_c…_merged.tif dentro de /work, y
                # geotiff/flood quedó vacío). Así que se busca y se renombra al
                # nombre que el renderizador filtra: SAT_viirs_flood_FECHA_HORA.
                FUSIONADO=\$(ls -t /work/*_merged.tif 2>/dev/null | head -1)

                if [ \$RC_MERGE -ne 0 ] || [ -z \"\$FUSIONADO\" ]; then
                    echo \"AVISO: la fusión no dejó ningún *_merged.tif (código \$RC_MERGE)\"
                    echo \"       Los .nc sí se conservan; la vista se queda sin GeoTIFF.\"
                else
                    SALIDA=/output_tif/${SAT_VISTA}_viirs_flood_\${SELLO:0:8}_\${SELLO:8:6}.tif
                    echo \"--- Fusionado \$(basename \"\$FUSIONADO\") -> \$SALIDA ---\"
                    mv \"\$FUSIONADO\" \"\$SALIDA\"
                fi
            fi
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
TIF_COUNT=$(find "$GEOTIFF_DIR" -maxdepth 1 -name '*.tif' -newer "$REF_FILE" 2>/dev/null | wc -l)

# ==============================================================================
# VERIFICACIÓN
# ==============================================================================
# Cero productos puede significar dos cosas muy distintas, y confundirlas ya
# costó una corrida: el algoritmo solo trabaja de día, así que una pasada
# nocturna termina bien y sin salida; pero si el binario sí generó archivos y aun
# así no hay ninguno en la salida, algo se rompió en el traslado.
#
# `successful_runs` NO sirve para distinguirlas, aunque lo parezca: CSPP lista
# ahí todo gránulo cuyo binario terminó en 0, produzca o no. En la pasada
# nocturna del 2026-08-14 los cinco gránulos aparecieron a la vez en
# `successful_runs` y en `failed_aoi_runs`, con rc_exe = 0 — y sin un solo
# producto. Lo que sí distingue los dos casos es el inventario que el propio
# driver imprime por gránulo después de mover su salida:
#     VIIRS Flood output files = []           -> no produjo nada (de noche)
#     VIIRS Flood output files = ['...']      -> produjo, y debe estar en la salida
PRODUJO=0
if grep -qE "VIIRS Flood output files = \[.+\]" "$LOG_FILE"; then
    PRODUJO=1
fi

if [ "$NC_COUNT" -eq 0 ] && [ "$PRODUJO" -eq 1 ]; then
    echo "❌ ERROR: el driver generó archivos pero no quedó ningún producto." | tee -a "$LOG_FILE"
    echo "   Revisa dónde los dejó; deberían estar en $OUTPUT_DIR."          | tee -a "$LOG_FILE"
    echo "   grep 'output files' $LOG_FILE"                                   | tee -a "$LOG_FILE"
    echo "   No se escribió el marcador: la pasada se reintentará."           | tee -a "$LOG_FILE"
    exit 1
fi

# Y si produjo, que esté todo: un .nc en la salida por cada gránulo cuyo
# inventario no salió vacío. Lo que llegó se queda (el barrido no retoma Flood),
# pero sin marcador. Un gránulo diurno que falle callado deja "[]" igual que uno
# nocturno, así que esto no lo atrapa: atrapa lo que se pierde en el traslado.
GRANULOS_CON_SALIDA=$(grep -acE "VIIRS Flood output files = \[.+\]" "$LOG_FILE" || true)
if [ "$NC_COUNT" -gt 0 ] && [ "$NC_COUNT" -lt "$GRANULOS_CON_SALIDA" ]; then
    echo "❌ ERROR: Flood salió a medias: $NC_COUNT productos de $GRANULOS_CON_SALIDA gránulos con salida." | tee -a "$LOG_FILE"
    echo "   Lo que llegó quedó en $OUTPUT_DIR, sin marcador."                  | tee -a "$LOG_FILE"
    echo "   grep 'output files' $LOG_FILE"                                     | tee -a "$LOG_FILE"
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
    echo "geotiff:   $TIF_COUNT fusionado en $GEOTIFF_DIR"
    echo "duracion:  $DURACION"
    echo "salida:    $OUTPUT_DIR"
    echo "log:       $LOG_FILE"
} > "$MARKER"

if [ "$NC_COUNT" -eq 0 ]; then
    echo "⚠  Sin productos para la pasada $CLAVE ($DURACION)"                    | tee -a "$LOG_FILE"
    echo "   Es lo esperado si la pasada es nocturna: el algoritmo solo procesa" | tee -a "$LOG_FILE"
    echo "   gránulos diurnos. La firma en el log es que VIIRS_Swath_Projection" | tee -a "$LOG_FILE"
    echo "   termina en 0 sin escribir ningún GITCO_Prj_SVI_*.h5, y entonces el" | tee -a "$LOG_FILE"
    echo "   'ls ... | xargs' de la detección corre sin argumento y contesta"    | tee -a "$LOG_FILE"
    echo "   'Parameter error!' una vez por gránulo."                            | tee -a "$LOG_FILE"
    echo "   Si sabes que era de día, revisa el log y vuelve a correr con -k"    | tee -a "$LOG_FILE"
    echo "   para conservar los logs por gránulo del directorio de trabajo."     | tee -a "$LOG_FILE"
    echo "   Marcador: $MARKER"                                                  | tee -a "$LOG_FILE"
    exit 0
fi

# El .nc es el producto y el .tif fusionado es lo que el renderizador viste. Que
# falte el segundo no invalida al primero, así que no se cae la etapa ni se borra
# el marcador — pero tiene que decirse: sin ese archivo, run_polar2grid_edr.sh
# genera cero vistas de inundaciones y no se queja, porque ahí flood es solo un
# filtro que no encuentra nada. Así se perdió la fusión del 2026-08-14, que sí se
# había hecho pero quedó en el directorio de trabajo.
if [ "$TIF_COUNT" -eq 0 ]; then
    echo "⚠  $NC_COUNT productos de la pasada $CLAVE en $OUTPUT_DIR ($DURACION)," | tee -a "$LOG_FILE"
    echo "   pero SIN el GeoTIFF fusionado en $GEOTIFF_DIR."                      | tee -a "$LOG_FILE"
    echo "   La vista de inundaciones no va a salir. Busca la fusión en el log:"  | tee -a "$LOG_FILE"
    echo "   grep -i 'fusion' $LOG_FILE"                                          | tee -a "$LOG_FILE"
    echo "   Marcador: $MARKER"                                                   | tee -a "$LOG_FILE"
    exit 0
fi

echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE en $OUTPUT_DIR ($DURACION)" | tee -a "$LOG_FILE"
echo "   GeoTIFF fusionado: $GEOTIFF_DIR ($TIF_COUNT)"                             | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER" | tee -a "$LOG_FILE"
