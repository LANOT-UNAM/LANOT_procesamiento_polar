#!/bin/bash
# ==============================================================================
# publicar_kawak.sh — copia a kawak las vistas de la cadena nueva. PROVISIONAL.
#
# Para cron, cada 15 minutos:
#   12-59/15 * * * * flock -n /data/tmp/publicar_kawak.lock /opt/lanot/polares/scripts/publicar_kawak.sh
#
# Provisional porque la página de kawak se alimenta hoy de la cadena vieja, y las
# dos nombran igual sus vistas de NPP y NOAA-20 (convención de Polar2Grid): una
# copia de esos satélites PISARÍA las de la vieja. Así que mientras convivan:
#
#   - de las vistas de VIIRS, solo NOAA-21, que la cadena vieja no procesa;
#   - de los sondeos, solo NOAA-21 en los mapas (los de NOAA-20 salen como
#     j01_atms-cris_…, un nombre que falta corregir), y TODOS los Skew-T, que
#     la cadena vieja no produce;
#   - del ozono, TODOS los satélites: la cadena vieja tampoco lo produce, así
#     que no hay nombre con el cual chocar;
#   - de las microondas de ATMS (MiRS), TODOS, por lo mismo. Los quicklooks de
#     ATMS de la cadena vieja van a otro árbol (polar/npp-jpss1/atms) y se
#     llaman SATMS_*, así que tampoco chocan.
#
# Cuando la cadena vieja se apague (ver estado_y_pendientes.md, "Condiciones para
# jubilar la cadena vieja"), esto se sustituye por la publicación de todo.
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
# Solo mira lo de los últimos PUB_KAWAK_DIAS días, y copia con --update: un
# archivo que ya está en kawak se reemplaza solo si el de aquí es más nuevo (un
# Skew-T regenerado), nunca al revés.
#
# Variables de entorno:
#   PUB_KAWAK_VISTAS  Raíz de vistas     (def. /data/output/jpss/vistas)
#   PUB_KAWAK_DEST    Destino rsync      (def. kawak:/var/www/html/polar/jpss)
#   PUB_KAWAK_DIAS    Antigüedad máxima  (def. 2)
#   PUB_KAWAK_LOG     Log                (def. /var/log/lanot/polares/cadena/publicar_kawak.log)
# ==============================================================================

set -uo pipefail

VISTAS="${PUB_KAWAK_VISTAS:-/data/output/jpss/vistas}"
DEST="${PUB_KAWAK_DEST:-kawak:/var/www/html/polar/jpss}"
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
             rsync -t --update "${DRY_RUN[@]}" --files-from=- --out-format='%n' \
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

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Publicación en $DEST${DRY_RUN:+ (dry-run)}"

copia dnb           viirs/dnb       'noaa21_*'
copia rgb           viirs/rgb       'noaa21_*'
copia flood         viirs/flood     'noaa21_*'
copia acspo         viirs/sst       'noaa21_*'
copia fire          viirs/fires     'noaa21_*'
copia atmos         viirs/aerosols  'noaa21_*AOD550*'
copia atmos         viirs/clouds    'noaa21_*' '*AOD550*'
copia lsr           viirs/vegindex  'noaa21_*'
copia sounder       sounder         'noaa21_*'
copia sounder/skewt sounder/skewt   '*.svg'
copia omps          omps            '*.jpg'
copia mirs          atms            '*.jpg'

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Copiados: $copiados · fallos: $fallos"
[ "$fallos" -eq 0 ]
