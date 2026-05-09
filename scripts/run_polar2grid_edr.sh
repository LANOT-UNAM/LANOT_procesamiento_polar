#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Visualización de Productos Nivel 2 EDR con Polar2Grid v3.2
# ==============================================================================

# 1. CONFIGURACIÓN DE RUTAS EN EL HOST
# ------------------------------------------------------------------------------
SIF_P2G="/opt/containers/polar2grid_v3.2.sif"

# Rutas en Lustre
HOST_EDR_IN="/data/output/jpss/level2/atmosphere"
HOST_IMG_OUT="/data/output/jpss/images/level2_edr"

# Logs
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/var/log/lanot/polares/polar2grid"
mkdir -p "$LOG_DIR" "$HOST_IMG_OUT"
LOG_FILE="$LOG_DIR/p2g_edr_$TIMESTAMP.log"

echo "=== INICIANDO RENDERIZADO CON POLAR2GRID v3.2 ===" | tee -a "$LOG_FILE"

# 2. EJECUCIÓN DEL CONTENEDOR
# ------------------------------------------------------------------------------
apptainer exec \
    --bind "$HOST_EDR_IN:/input_edr" \
    --bind "$HOST_IMG_OUT:/output_img" \
    "$SIF_P2G" /bin/bash -c "
        
        # Nos movemos a la carpeta de salida montada
        cd /output_img
        
        echo '--- Generando GeoTIFFs de Productos Atmosféricos ---'
        
        # polar2grid.sh ya está en el PATH gracias al archivo .def
        # Lector: viirs_l2 (para NetCDF de Enterprise)
        # Productos: Máscara, Altura, Fase y Aerosoles (AOD)
        polar2grid.sh -r viirs_l2 \
            -w geotiff \
            -p cloud_mask cloud_top_height cloud_top_phase aod_550 \
            -f /input_edr/*.nc
            
        echo '--- Proceso de renderizado finalizado ---'
        
        # Descomenta la siguiente línea si deseas superponer contornos de costas y fronteras
        # add_coastlines.sh --add-borders --add-coastlines *.tif
    " >> "$LOG_FILE" 2>&1

EXIT_CODE=$?

# 3. FINALIZACIÓN
# ------------------------------------------------------------------------------
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ ÉXITO: Mapas GeoTIFF generados en $HOST_IMG_OUT" | tee -a "$LOG_FILE"
else
    echo "❌ ERROR: Falló la generación de imágenes. Revisa el log en:" | tee -a "$LOG_FILE"
    echo "   $LOG_FILE" | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi
