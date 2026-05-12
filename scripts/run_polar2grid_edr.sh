#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Visualización de Productos Nivel 2 EDR y LSR con Polar2Grid v3.2
# ==============================================================================

SIF_P2G="/opt/containers/polar2grid_v3.2.sif"

# Rutas en Lustre (Entradas)
HOST_SDR_IN="/data/output/jpss/level1/viirs"
HOST_EDR_IN="/data/output/jpss/level2/atmosphere"
HOST_LSR_IN="/data/output/jpss/level2/lsr"           # NUEVO: Entrada LSR

# Rutas en Lustre (Salidas de Imágenes)
HOST_IMG_OUT="/data/output/jpss/vistas/atmos"
HOST_LSR_IMG_OUT="/data/output/jpss/vistas/lsr"      # NUEVO: Salida de vistas LSR
HOST_DNB_IMG_OUT="/data/output/jpss/vistas/dnb"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOST_WORK="/data/tmp/p2g_work_$TIMESTAMP"
LOG_DIR="/var/log/lanot/polares/polar2grid"

# Creamos todos los directorios necesarios
mkdir -p "$LOG_DIR" "$HOST_IMG_OUT" "$HOST_LSR_IMG_OUT" "$HOST_WORK"
LOG_FILE="$LOG_DIR/p2g_edr_lsr_$TIMESTAMP.log"

echo "=== INICIANDO RENDERIZADO CON POLAR2GRID v3.2 ===" | tee -a "$LOG_FILE"

apptainer exec \
    --bind "$HOST_SDR_IN:/input_sdr" \
    --bind "$HOST_EDR_IN:/input_edr" \
    --bind "$HOST_LSR_IN:/input_lsr" \
    --bind "$HOST_IMG_OUT:/output_img" \
    --bind "$HOST_LSR_IMG_OUT:/output_lsr_img" \
    --bind "$HOST_DNB_IMG_OUT:/output_dnb_img" \
    --bind "$HOST_WORK:/work" \
    "$SIF_P2G" /bin/bash -c "
        
        # 1. Normalizar nombres de los archivos GMTCO (Geolocalización)
        echo '--- Normalizando nombres de archivos SDR ---'
        mkdir -p /work/sdr_links
        for f in /input_sdr/GMTCO*.h5; do
            if [ -f \"\$f\" ]; then
                base=\$(basename \"\$f\" | sed 's/_cspp_dev//')
                ln -s \"\$f\" \"/work/sdr_links/\$base\"
            fi
        done
        
        # 2. Renderizado de Productos Atmosféricos (EDR)
        echo '--- Generando GeoTIFFs de Productos Atmosféricos ---'
        cd /output_img
        polar2grid.sh -v -r viirs_edr \
            -w geotiff \
            -f /input_edr/JRR-*.nc /work/sdr_links/GMTCO*.h5
            
        # 3. Renderizado de Productos de Superficie (LSR)
        echo '--- Generando GeoTIFFs de Productos LSR (NDVI, EVI, Reflectancia) ---'
        cd /output_lsr_img
        
        # Se omite el enlace a los GMTCO porque los archivos SurfRefl 
        # ya contienen su propia geolocalización (Lat/Lon internamente).
        polar2grid.sh -v -r viirs_edr \
            -w geotiff \
            -f /input_lsr/SurfRefl_*.nc
            
        # 4. Renderizado de DNB
        echo '--- Generando GeoTIFFs de DNB ---'
        cd /output_dnb_img
        
        # Se omite el enlace a los GMTCO porque los archivos SurfRefl 
        # ya contienen su propia geolocalización (Lat/Lon internamente).
        polar2grid.sh -v -r viirs_sdr \
            -w geotiff \
            -p dnb ncc \
            -f /input_sdr/SVDNB_*.h5 /input_sdr/GDNBO_*.h5
            
    " >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

# Validación contando los archivos resultantes en ambas carpetas
TIF_ATMOS_COUNT=$(ls -1 "$HOST_IMG_OUT"/*.tif 2>/dev/null | wc -l)
TIF_LSR_COUNT=$(ls -1 "$HOST_LSR_IMG_OUT"/*.tif 2>/dev/null | wc -l)

echo "=== PROCESO FINALIZADO ===" | tee -a "$LOG_FILE"
echo "Imágenes Atmosféricas generadas: $TIF_ATMOS_COUNT" | tee -a "$LOG_FILE"
echo "Imágenes de Superficie (LSR) generadas: $TIF_LSR_COUNT" | tee -a "$LOG_FILE"

# Limpieza del directorio de trabajo temporal
rm -rf "$HOST_WORK"

exit $EXIT_CODE
