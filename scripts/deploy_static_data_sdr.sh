#!/bin/bash
# ==============================================================================
# SCRIPT: Despliegue de Datos Estáticos CSPP SDR v4.1 en Lustre
# ==============================================================================

TAR_DIR="/opt/contenedores/tarfiles"
TARGET_DIR="/data/opt"

# Lista exclusiva de los archivos estáticos (Omitimos el binario base y los test data)
FILES=(
    "CSPP_SDR_V4.1_static_luts_j01.tar.gz"
    "CSPP_SDR_V4.1_static_luts_j02.tar.gz"
    "CSPP_SDR_V4.1_static_luts_npp.tar.gz"
    "CSPP_SDR_V4.1_static_tiles.tar.gz"
    "CSPP_SDR_V4.1_straylight_luts_j01.tar.gz"
    "CSPP_SDR_V4.1_straylight_luts_j02.tar.gz"
    "CSPP_SDR_V4.1_straylight_luts_npp.tar.gz"
)

echo "=== INICIANDO DESPLIEGUE DE DATOS ESTÁTICOS ==="
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

for FILE in "${FILES[@]}"; do
    FILE_PATH="$TAR_DIR/$FILE"
    SHA1_PATH="$FILE_PATH.sha1"

    if [ -f "$FILE_PATH" ]; then
        echo "--------------------------------------------------"
        echo "Procesando: $FILE"
        
        # 1. Verificación del Checksum
        if [ -f "$SHA1_PATH" ]; then
            echo "[1/2] Verificando integridad (SHA1)..."
            # Extraemos el hash esperado del archivo .sha1
            EXPECTED_HASH=$(cat "$SHA1_PATH" | awk '{print $1}')
            CURRENT_HASH=$(sha1sum "$FILE_PATH" | awk '{print $1}')
            
            if [ "$EXPECTED_HASH" != "$CURRENT_HASH" ]; then
                echo "❌ ERROR: El checksum de $FILE no coincide."
                echo "Esperado: $EXPECTED_HASH"
                echo "Actual:   $CURRENT_HASH"
                echo "Saltando archivo..."
                continue
            fi
            echo "✅ Checksum correcto."
        else
            echo "⚠️ Advertencia: No se encontró el archivo .sha1 para $FILE"
        fi

        # 2. Descompresión
        echo "[2/2] Descomprimiendo en $TARGET_DIR/SDR_4_1/..."
        tar -zxf "$FILE_PATH"
        
        if [ $? -eq 0 ]; then
            echo "✅ Descompresión finalizada con éxito."
        else
            echo "❌ ERROR al descomprimir $FILE."
        fi
    else
        echo "❌ ERROR: No se encontró el archivo $FILE_PATH"
    fi
done

echo "--------------------------------------------------"
echo "=== DESPLIEGUE COMPLETADO ==="
echo "Puedes verificar el peso total de la carpeta con:"
echo "du -sh /data/opt/SDR_4_1"
