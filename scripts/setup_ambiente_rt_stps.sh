#!/bin/bash
################################################################################
# Script: setup_ambiente_rt_stps.sh
# Propósito: Inicializar estructura de directorios y archivos para RT-STPS
# Autor: LANOT - UNAM
#
# Descripción:
#   Prepara el ambiente necesario para ejecutar RT-STPS:
#   - Crea directorios de trabajo
#   - Extrae archivos XML de configuración del contenedor
#   - Descarga archivo leapsec.dat actualizado
#
# Uso:
#   sudo ./setup_ambiente_rt_stps.sh
#
################################################################################

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================================================="
echo "  Setup Ambiente RT-STPS - LANOT"
echo "=============================================================================="
echo ""

# Verificar que se ejecuta como root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: Este script debe ejecutarse como root (usa sudo)${NC}" >&2
    exit 1
fi

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

CONTAINER_RT_STPS="/opt/containers/rt_stps_7.0.sif"
BASE_DATA="/data"

# Directorios a crear
DIRS=(
    "/data/opt/RT-STPS/rt-stps/config"
    "/data/ancillary/common"
    "/data/output/level0"
    "/data/output/level1"
    "/data/output/level2"
    "/data/output/geotiff"
    "/datawork/input/polar/raw"
    "/var/log/lanot/polares/rt-stps"
    "/var/log/lanot/polares/cspp-sdr"
    "/var/log/lanot/polares/polar2grid"
    "/opt/containers"
)

# ============================================================================
# PASO 1: Crear estructura de directorios
# ============================================================================

echo -e "${YELLOW}[1/4] Creando estructura de directorios...${NC}"
for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chown lanotadm:lanotadm "$dir"
        echo "  ✓ Creado: $dir"
    else
        echo "  ○ Ya existe: $dir"
    fi
done
echo ""

# ============================================================================
# PASO 2: Extraer archivos XML de configuración
# ============================================================================

echo -e "${YELLOW}[2/4] Extrayendo archivos XML de configuración...${NC}"

if [ ! -f "$CONTAINER_RT_STPS" ]; then
    echo -e "${RED}  ✗ ERROR: Contenedor no encontrado: $CONTAINER_RT_STPS${NC}"
    echo "  Debes compilar el contenedor primero con:"
    echo "    cd contenedores/"
    echo "    sudo apptainer build rt_stps_7.0.sif rt_stps_7.0.def"
    echo ""
    echo "  Continuando con el resto de la configuración..."
    echo ""
else
    # Extraer XMLs del contenedor
    CONFIG_DIR="/data/opt/RT-STPS/rt-stps/config"
    
    echo "  Extrayendo archivos de configuración del contenedor..."
    
    # Copiar XMLs desde el contenedor
    for xml_file in npp.xml jpss1.xml jpss2.xml; do
        if [ ! -f "$CONFIG_DIR/$xml_file" ]; then
            apptainer exec "$CONTAINER_RT_STPS" \
                cat "/opt/rt-stps/config/$xml_file" > "$CONFIG_DIR/$xml_file" 2>/dev/null || {
                echo -e "${YELLOW}  ⚠ No se pudo extraer $xml_file (puede que no exista en el contenedor)${NC}"
            }
            
            if [ -f "$CONFIG_DIR/$xml_file" ]; then
                echo "  ✓ Extraído: $xml_file"
            fi
        else
            echo "  ○ Ya existe: $xml_file"
        fi
    done
    echo ""
fi

# ============================================================================
# PASO 3: Descargar archivo leapsec.dat
# ============================================================================

echo -e "${YELLOW}[3/4] Descargando archivo de segundos intercalares (leapsec.dat)...${NC}"

LEAPSEC_FILE="/data/ancillary/common/leapsec.dat"

if [ -f "$LEAPSEC_FILE" ]; then
    echo "  ○ Archivo ya existe: $LEAPSEC_FILE"
    echo "    Fecha de modificación: $(stat -c %y "$LEAPSEC_FILE" | cut -d' ' -f1)"
    read -p "  ¿Descargar versión actualizada? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "  → Conservando archivo existente"
        echo ""
    else
        rm -f "$LEAPSEC_FILE"
    fi
fi

if [ ! -f "$LEAPSEC_FILE" ]; then
    echo "  Intentando descargar desde IERS..."
    
    # Intentar varias fuentes
    SOURCES=(
        "https://hpiers.obspm.fr/iers/bul/bulc/Leap_Second.dat"
        "https://www.ietf.org/timezones/data/leap-seconds.list"
        "https://raw.githubusercontent.com/eggert/tz/main/leap-seconds.list"
    )
    
    DOWNLOADED=false
    for url in "${SOURCES[@]}"; do
        echo "    Probando: $url"
        if wget -q -O "$LEAPSEC_FILE" "$url" 2>/dev/null; then
            echo "  ✓ Descargado exitosamente desde: $url"
            DOWNLOADED=true
            break
        fi
    done
    
    if [ "$DOWNLOADED" = false ]; then
        echo -e "${YELLOW}  ⚠ No se pudo descargar automáticamente${NC}"
        echo "  Creando archivo placeholder (debes actualizarlo manualmente)"
        
        # Crear archivo básico con datos hasta 2024
        cat > "$LEAPSEC_FILE" << 'EOF'
# Leap Second Data
# Este es un archivo PLACEHOLDER
# Descarga la versión actualizada desde:
# https://hpiers.obspm.fr/iers/bul/bulc/Leap_Second.dat
#
# O desde el contenedor RT-STPS si ya tienes una versión:
# apptainer exec /opt/containers/rt_stps_7.0.sif cat /opt/rt-stps/leapsec.dat

1972-06-30 23:59:60
1972-12-31 23:59:60
1973-12-31 23:59:60
1974-12-31 23:59:60
1975-12-31 23:59:60
1976-12-31 23:59:60
1977-12-31 23:59:60
1978-12-31 23:59:60
1979-12-31 23:59:60
1981-06-30 23:59:60
1982-06-30 23:59:60
1983-06-30 23:59:60
1985-06-30 23:59:60
1987-12-31 23:59:60
1989-12-31 23:59:60
1990-12-31 23:59:60
1992-06-30 23:59:60
1993-06-30 23:59:60
1994-06-30 23:59:60
1995-12-31 23:59:60
1997-06-30 23:59:60
1998-12-31 23:59:60
2005-12-31 23:59:60
2008-12-31 23:59:60
2012-06-30 23:59:60
2015-06-30 23:59:60
2016-12-31 23:59:60
EOF
        echo -e "${YELLOW}  ⚠ Creado archivo placeholder${NC}"
        echo -e "${YELLOW}  ⚠ ACCIÓN REQUERIDA: Actualiza manualmente $LEAPSEC_FILE${NC}"
    fi
fi
echo ""

# Intentar extraer del contenedor si existe
if [ -f "$CONTAINER_RT_STPS" ] && [ ! -s "$LEAPSEC_FILE" ]; then
    echo "  Intentando extraer leapsec.dat del contenedor..."
    apptainer exec "$CONTAINER_RT_STPS" \
        cat "/opt/rt-stps/leapsec.dat" > "$LEAPSEC_FILE" 2>/dev/null && {
        echo "  ✓ Extraído desde el contenedor"
    } || {
        echo "  ⚠ No se pudo extraer del contenedor"
    }
    echo ""
fi

# ============================================================================
# PASO 4: Configurar permisos
# ============================================================================

echo -e "${YELLOW}[4/4] Configurando permisos...${NC}"

# Asegurar que los directorios son accesibles
chmod -R 755 /data/opt/RT-STPS 2>/dev/null || true
chmod -R 755 /data/ancillary 2>/dev/null || true
chmod -R 775 /data/output 2>/dev/null || true
chmod -R 775 /datawork/input 2>/dev/null || true
chmod -R 775 /var/log/lanot 2>/dev/null || true
chown -R lanotadm:lanotadm /data/opt
chown -R lanotadm:lanotadm /data/ancillary
chown -R lanotadm:lanotadm /data/output
chown -R lanotadm:lanotadm /datawork/input
chown -R lanotadm:lanotadm /var/log/lanot     
echo "  ✓ Permisos configurados"
echo ""

# ============================================================================
# RESUMEN
# ============================================================================

echo "=============================================================================="
echo -e "${GREEN}  Setup completado${NC}"
echo "=============================================================================="
echo ""
echo "Estructura creada:"
echo "  • Configuración:  /data/opt/RT-STPS/rt-stps/config/"
echo "  • Ancillary:      /data/ancillary/common/"
echo "  • Productos:      /data/products/{level0,level1,level2,geotiff}/"
echo "  • Logs:           /var/log/lanot/polares/"
echo "  • Contenedores:   /opt/containers/"
echo ""
echo "Archivos de configuración:"

# Verificar XMLs
for xml in npp.xml jpss1.xml jpss2.xml; do
    if [ -f "/data/opt/RT-STPS/rt-stps/config/$xml" ]; then
        echo -e "  ${GREEN}✓${NC} $xml"
    else
        echo -e "  ${RED}✗${NC} $xml ${YELLOW}(faltante - debes agregarlo manualmente)${NC}"
    fi
done

# Verificar leapsec.dat
if [ -f "$LEAPSEC_FILE" ] && [ -s "$LEAPSEC_FILE" ]; then
    echo -e "  ${GREEN}✓${NC} leapsec.dat"
else
    echo -e "  ${RED}✗${NC} leapsec.dat ${YELLOW}(faltante o vacío)${NC}"
fi

echo ""
echo "Próximos pasos:"
echo "  1. Si falta el contenedor, compílalo:"
echo "     cd contenedores/ && sudo apptainer build rt_stps_7.0.sif rt_stps_7.0.def"
echo ""
echo "  2. Si faltan archivos XML, extráelos del tar.gz de RT-STPS o cópialos desde"
echo "     una instalación existente a: /data/opt/RT-STPS/rt-stps/config/"
echo ""
echo "  3. Verifica que leapsec.dat esté actualizado (último segundo intercalar: 2016)"
echo ""
echo "  4. Prueba el procesamiento:"
echo "     ./scripts/procesar_rt_stps_solo.sh /datawork/input/polar/raw/tu_archivo.raw"
echo ""
echo "=============================================================================="

exit 0
