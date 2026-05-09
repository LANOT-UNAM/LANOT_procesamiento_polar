#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Visualización de Productos Nivel 2 (Enterprise) con Polar2Grid
# ==============================================================================

# Si tienes polar2grid en contenedor, ajusta esta ruta. Si es nativo, déjalo vacío y ajusta el comando.
SIF_P2G="/opt/containers/polar2grid_v3.0.sif"

HOST_EDR_IN="/data/output/jpss/level2/atmosphere"
HOST_IMG_OUT="/data/output/jpss/images/level2_edr"

mkdir -p "$HOST_IMG_OUT"

echo "=== INICIANDO RENDERIZADO CON POLAR2GRID ==="

apptainer exec \
    --bind "$HOST_EDR_IN:/input_edr" \
    --bind "$HOST_IMG_OUT:/output_img" \
    "$SIF_P2G" /bin/bash -c "
        
        # Nos movemos a la carpeta de salida para que las imágenes caigan ahí
        cd /output_img
        
        echo '--- Generando GeoTIFFs de Productos Atmosféricos ---'
        
        # Lector: viirs_l2
        # Productos (-p): cloud_mask, cloud_top_height, cloud_top_phase, aod_550
        # Formato (-w): geotiff (o png)
        
        polar2grid.sh -r viirs_l2 \
            -w geotiff \
            -p cloud_mask cloud_top_height cloud_top_phase aod_550 \
            -f /input_edr/*.nc
            
        # Opcional: Agregar contornos de costas (si tienes shapefiles configurados en P2G)
        # add_coastlines.sh --add-borders --add-coastlines *.tif
    "

if [ $? -eq 0 ]; then
    echo "✅ ÉXITO: Mapas generados en $HOST_IMG_OUT"
else
    echo "❌ ERROR: Falló la generación de imágenes."
fi
