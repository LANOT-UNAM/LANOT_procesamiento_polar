#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Compilación de contenedores
# ==============================================================================
#
# Las recetas parten de una imagen base común (lanot_base_rocky8.sif y
# lanot_base_rocky9.sif), así que hay un orden: primero la base de su serie,
# después el contenedor. Este script se encarga de eso.
#
# La compilación ocurre en el directorio donde están los tarballs, porque el
# %files de cada receta los referencia por nombre, relativos al directorio de
# trabajo.
#
# Uso:
#   ./construir.sh                      # lista lo que se puede compilar
#   ./construir.sh cspp_flood_v2.0      # compila esa receta (y su base si falta)
#   ./construir.sh --base 9             # solo la base de la serie 9
#   ./construir.sh --todos              # las dos bases y todas las recetas
#
# Variables de entorno:
#   TARBALLS  Directorio con los .tar.gz y donde quedan los .sif
#             (def. /opt/contenedores)
#   DESTINO   Dónde instalar el .sif ya compilado (def. no se instala)
#
# ==============================================================================

set -euo pipefail

RECETAS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARBALLS="${TARBALLS:-/opt/contenedores}"
DESTINO="${DESTINO:-}"

serie_de() {
    grep -q "lanot_base_rocky8" "$RECETAS_DIR/$1.def" && echo 8 || echo 9
}

compilar_base() {
    local serie="$1"
    local sif="$TARBALLS/lanot_base_rocky${serie}.sif"

    if [ -f "$sif" ]; then
        echo "  base rocky$serie: ya existe ($(du -h "$sif" | cut -f1))"
        return 0
    fi

    echo ">>> Compilando base rocky$serie..."
    ( cd "$TARBALLS" && sudo apptainer build "lanot_base_rocky${serie}.sif" \
                             "$RECETAS_DIR/lanot_base_rocky${serie}.def" )
}

compilar() {
    local receta="$1"
    local def="$RECETAS_DIR/$receta.def"

    if [ ! -f "$def" ]; then
        echo "ERROR: No existe la receta: $def" >&2
        exit 1
    fi

    compilar_base "$(serie_de "$receta")"

    echo ">>> Compilando $receta..."
    ( cd "$TARBALLS" && sudo apptainer build "$receta.sif" "$def" )

    echo ">>> Verificando..."
    apptainer test "$TARBALLS/$receta.sif"

    if [ -n "$DESTINO" ]; then
        echo ">>> Instalando en $DESTINO"
        sudo install -m 755 "$TARBALLS/$receta.sif" "$DESTINO/"
    fi

    echo "✅ $receta listo: $TARBALLS/$receta.sif ($(du -h "$TARBALLS/$receta.sif" | cut -f1))"
}

if [ ! -d "$TARBALLS" ]; then
    echo "ERROR: No existe el directorio de tarballs: $TARBALLS" >&2
    echo "       Indícalo con la variable TARBALLS." >&2
    exit 1
fi

case "${1:-}" in
    "")
        echo "Recetas disponibles en $RECETAS_DIR:"
        for d in "$RECETAS_DIR"/*.def; do
            n=$(basename "$d" .def)
            case "$n" in lanot_base_*) continue ;; esac
            printf "  %-32s base rocky%s\n" "$n" "$(serie_de "$n")"
        done
        echo
        echo "Tarballs y .sif en: $TARBALLS"
        echo "Uso: $0 <receta> | --base <8|9> | --todos"
        ;;
    --base)
        compilar_base "${2:?indica la serie: 8 o 9}"
        ;;
    --todos)
        compilar_base 8
        compilar_base 9
        for d in "$RECETAS_DIR"/*.def; do
            n=$(basename "$d" .def)
            case "$n" in lanot_base_*) continue ;; esac
            compilar "$n"
        done
        ;;
    -h|--help)
        sed -n '2,26p' "${BASH_SOURCE[0]}"
        ;;
    *)
        compilar "${1%.def}"
        ;;
esac
