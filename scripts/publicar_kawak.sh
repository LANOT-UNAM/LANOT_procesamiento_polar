#!/bin/bash
# ==============================================================================
# publicar_kawak.sh — copia a kawak las vistas de la cadena nueva.
#
# Para cron, cada 15 minutos:
#   12-59/15 * * * * flock -n /data/tmp/publicar_kawak.lock /opt/lanot/polares/scripts/publicar_kawak.sh
#
# Publica TODO lo de JPSS, de todos los satélites, y las vistas de AVHRR de
# METOP (desde el 2026-11-20, abajo). Hasta el 2026-11-04 fue
# provisional y solo copiaba lo que la cadena vieja no producía —VIIRS y sondeos
# de NOAA-21, ozono, MiRS y Skew-T—, porque las dos nombraban igual sus vistas
# de NPP y NOAA-20 y una copia habría pisado las de la otra. Con la rama JPSS de
# la cadena vieja apagada, polar/jpss en kawak es solo nuestro.
#
# METOP va a su propio árbol, polar/metop, al lado de polar/noaa-metop, que es
# el de la cadena vieja (crea_vistas_metop.sh, en kawak, sobre los GeoTIFF de
# stratus): lo mismo que polar/jpss junto a polar/npp-jpss1. Así las dos cadenas
# publican a la vez sin pisarse y se pueden comparar pasada por pasada, aunque
# los nombres de archivo sean idénticos. Decidido el 2026-11-20; ese mismo día y
# por unas horas publicó en noaa-metop/avhrr/vistas (una sola vista).
#
# --mkpath porque polar/metop no existía: rsync crea la carpeta final pero no
# las intermedias.
#
# La correspondencia de carpetas es la de la página, no la de vistas/:
#
#   vistas/dnb, rgb, flood   → viirs/dnb, rgb, flood
#   vistas/acspo             → viirs/sst
#   vistas/fire              → viirs/fires
#   vistas/atmos (AOD550)    → viirs/aerosols
#   vistas/atmos (lo demás)  → viirs/clouds
#   vistas/lsr               → viirs/vegindex
#   vistas/sounder           → sounder         (al lado de viirs/: no es VIIRS)
#   vistas/sounder/skewt     → sounder/skewt
#   vistas/omps              → omps            (al lado de viirs/: es OMPS)
#   vistas/mirs              → atms            (al lado de viirs/: es ATMS)
#
#   metop/vistas/avhrr       → metop/avhrr        (otra raíz: PUB_KAWAK_METOP_*)
#   metop/vistas/mirs        → metop/amsu-mhs     (como mirs → atms en JPSS)
#   metop/vistas/sounder     → metop/sounder      (y skewt/, como en JPSS)
#
# Solo mira lo de los últimos PUB_KAWAK_DIAS días, y copia con --update: un
# archivo que ya está en kawak se reemplaza solo si el de aquí es más nuevo (un
# Skew-T regenerado), nunca al revés.
#
# Variables de entorno:
#   PUB_KAWAK_VISTAS  Raíz de vistas     (def. /data/output/jpss/vistas)
#   PUB_KAWAK_DEST    Destino rsync      (def. kawak:/var/www/html/polar/jpss)
#   PUB_KAWAK_METOP_VISTAS  Raíz de vistas de METOP (def. /data/output/metop/vistas)
#   PUB_KAWAK_METOP_DEST    Destino de METOP  (def. kawak:/var/www/html/polar/metop)
#   PUB_KAWAK_DIAS    Antigüedad máxima  (def. 2)
#   PUB_KAWAK_LOG     Log                (def. /var/log/lanot/polares/cadena/publicar_kawak.log)
# ==============================================================================

set -uo pipefail

VISTAS="${PUB_KAWAK_VISTAS:-/data/output/jpss/vistas}"
DEST="${PUB_KAWAK_DEST:-kawak:/var/www/html/polar/jpss}"
VISTAS_METOP="${PUB_KAWAK_METOP_VISTAS:-/data/output/metop/vistas}"
DEST_METOP="${PUB_KAWAK_METOP_DEST:-kawak:/var/www/html/polar/metop}"
DIAS="${PUB_KAWAK_DIAS:-2}"
LOG="${PUB_KAWAK_LOG:-/var/log/lanot/polares/cadena/publicar_kawak.log}"

DRY_RUN=()
case "${1:-}" in
    -n|--dry-run) DRY_RUN=(--dry-run) ;;
    -h|--help)    sed -n '3,/^# ===/{/^# ===/!p}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "")           ;;
    *)            echo "ERROR: Argumento no reconocido: $1" >&2; exit 1 ;;
esac

# Sin terminal (cron), todo al log; con terminal, a los dos.
if [ -t 1 ]; then
    exec > >(tee -a "$LOG") 2>&1
else
    exec >> "$LOG" 2>&1
fi

copiados=0
fallos=0

# copia <subdir de vistas> <subdir en kawak> <patrón de find> [<patrón a excluir>]
copia() {
    local origen="$VISTAS/$1" destino="$DEST/$2" patron="$3" excluir="${4:-}"
    local -a filtro=(-name "$patron")
    [ -z "$excluir" ] || filtro+=(! -name "$excluir")
    [ -d "$origen" ] || return 0

    local lista n salida codigo=0
    lista=$(cd "$origen" && find . -maxdepth 1 -type f "${filtro[@]}" -mtime "-$DIAS" -printf '%f\n')
    [ -n "$lista" ] || return 0

    salida=$(printf '%s\n' "$lista" |
             rsync -t --update --mkpath "${DRY_RUN[@]}" --files-from=- --out-format='%n' \
                   "$origen/" "$destino/" 2>&1) || codigo=$?
    if [ "$codigo" -ne 0 ]; then
        fallos=$((fallos + 1))
        echo "  ✗ $1 → $2 (rsync, código $codigo): $(echo "$salida" | tail -1)"
        return 0
    fi
    n=$(printf '%s' "$salida" | grep -c . || true)
    if [ "$n" -gt 0 ]; then
        copiados=$((copiados + n))
        printf '%s\n' "$salida" | sed "s|^|  $2/|"
    fi
}

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Publicación en $DEST y $DEST_METOP${DRY_RUN:+ (dry-run)}"

copia dnb           viirs/dnb       '*.jpg'
copia rgb           viirs/rgb       '*.jpg'
copia flood         viirs/flood     '*.jpg'
copia acspo         viirs/sst       '*.jpg'
copia fire          viirs/fires     '*.jpg'
copia atmos         viirs/aerosols  '*AOD550*.jpg'
copia atmos         viirs/clouds    '*.jpg' '*AOD550*'
copia lsr           viirs/vegindex  '*.jpg'
copia sounder       sounder         '*.jpg'
copia sounder/skewt sounder/skewt   '*.svg'
copia omps          omps            '*.jpg'
copia mirs          atms            '*.jpg'

# METOP: otra raíz de origen y otro árbol en kawak; copia() las toma de ahí.
VISTAS="$VISTAS_METOP" DEST="$DEST_METOP" copia avhrr  avhrr     '*.jpg'
VISTAS="$VISTAS_METOP" DEST="$DEST_METOP" copia mirs   amsu-mhs  '*.jpg'
VISTAS="$VISTAS_METOP" DEST="$DEST_METOP" copia sounder       sounder        '*.jpg'
VISTAS="$VISTAS_METOP" DEST="$DEST_METOP" copia sounder/skewt sounder/skewt  '*.svg'

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copiados: $copiados · fallos: $fallos"
[ "$fallos" -eq 0 ]
