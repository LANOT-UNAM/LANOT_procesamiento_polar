#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Visualización de Productos Nivel 2 EDR con Polar2Grid v3.2
# ==============================================================================

SIF_P2G="/opt/containers/polar2grid_v3.2.sif"

# Rutas en Lustre
HOST_SDR_IN="/data/output/jpss/level1/viirs"
HOST_EDR_IN="/data/output/jpss/level2/atmosphere"
HOST_IMG_OUT="/data/output/jpss/vistas/atmosphere" 

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOST_WORK="/data/tmp/p2g_work_$TIMESTAMP"
LOG_DIR="/var/log/lanot/polares/polar2grid"

mkdir -p "$LOG_DIR" "$HOST_IMG_OUT" "$HOST_WORK"
LOG_FILE="$LOG_DIR/p2g_edr_$TIMESTAMP.log"

echo "=== INICIANDO RENDERIZADO CON POLAR2GRID v3.2 ===" | tee -a "$LOG_FILE"

apptainer exec \
    --bind "$HOST_SDR_IN:/input_sdr" \
    --bind "$HOST_EDR_IN:/input_edr" \
    --bind "$HOST_IMG_OUT:/output_img" \
    --bind "$HOST_WORK:/work" \
    "$SIF_P2G" /bin/bash -c "
        
        # 1. Normalizar nombres de los archivos GMTCO (Geolocalización)
        echo '--- Normalizando nombres de archivos SDR ---'
        mkdir -p /work/sdr_links
        for f in /input_sdr/GMTCO*.h5; do
            if [ -f \"\$f\" ]; then
                # Extraemos el nombre base y le podamos el sufijo de desarrollo
                base=\$(basename \"\$f\" | sed 's/_cspp_dev//')
                ln -s \"\$f\" \"/work/sdr_links/\$base\"
            fi
        done
        
        # Nos movemos a la salida definitiva
        cd /output_img
        echo '--- Generando GeoTIFFs de Productos Atmosféricos ---'
        
        # 2. ALIMENTACIÓN DOBLE CON ENLACES LIMPIOS:
        polar2grid.sh -v -r viirs_edr \
            -w geotiff \
            -p cloud_mask cloud_top_height cloud_top_phase aod_550 \
            -f /input_edr/JRR-*.nc /work/sdr_links/GMTCO*.h5
            
    " >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

# Validación estricta contando los archivos resultantes
TIF_COUNT=$(ls -1 "$HOST_IMG_OUT"/*.tif 2>/dev/null | wc -l)

if [ "$TIF_COUNT" -gt 0 ]; then
    echo "✅ ÉXITO: $TIF_COUNT mapas GeoTIFF generados en $HOST_IMG_OUT" | tee -a "$LOG_FILE"
    # Limpiamos el directorio temporal de enlaces
    rm -rf "$HOST_WORK"
else
    echo "❌ ERROR: No se generaron imágenes TIFF. Revisa el log en:" | tee -a "$LOG_FILE"
    echo "   $LOG_FILE" | tee -a "$LOG_FILE"
    exit 1
fi
