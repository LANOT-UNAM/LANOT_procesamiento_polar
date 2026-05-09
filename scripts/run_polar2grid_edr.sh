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
LOG_DIR="/var/log/lanot/polares/polar2grid"
mkdir -p "$LOG_DIR" "$HOST_IMG_OUT"
LOG_FILE="$LOG_DIR/p2g_edr_$TIMESTAMP.log"

echo "=== INICIANDO RENDERIZADO CON POLAR2GRID v3.2 ===" | tee -a "$LOG_FILE"

apptainer exec \
    --bind "$HOST_SDR_IN:/input_sdr" \
    --bind "$HOST_EDR_IN:/input_edr" \
    --bind "$HOST_IMG_OUT:/output_img" \
    "$SIF_P2G" /bin/bash -c "
        
        cd /output_img
        echo '--- Generando GeoTIFFs de Productos Atmosféricos ---'
        
        # ALIMENTACIÓN DOBLE:
        # Pasamos los productos JRR (Nivel 2) Y los GMTCO (Nivel 1 para geolocalización)
        polar2grid.sh -v -r viirs_edr \
            -w geotiff \
            -p cloud_mask cloud_top_height cloud_top_phase aod_550 \
            -f /input_edr/JRR-*.nc /input_sdr/GMTCO*.h5
            
    " >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

# Como P2G miente con el Exit Code 0 cuando falla internamente, 
# verificaremos si realmente se crearon los archivos .tif
TIF_COUNT=$(ls -1 "$HOST_IMG_OUT"/*.tif 2>/dev/null | wc -l)

if [ "$TIF_COUNT" -gt 0 ]; then
    echo "✅ ÉXITO: $TIF_COUNT mapas GeoTIFF generados en $HOST_IMG_OUT" | tee -a "$LOG_FILE"
else
    echo "❌ ERROR: No se generaron imágenes TIFF. Revisa el log en:" | tee -a "$LOG_FILE"
    echo "   $LOG_FILE" | tee -a "$LOG_FILE"
    exit 1
fi
