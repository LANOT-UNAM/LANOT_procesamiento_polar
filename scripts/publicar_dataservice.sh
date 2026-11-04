#!/bin/bash
# ==============================================================================
# publicar_dataservice.sh — copia Level 1 a /dataservice/jpss para los FTP.
#
# Para cron de lanotadm, cada 5 minutos (el candado lo toma el propio script):
#   */5 * * * * /opt/lanot/polares/scripts/publicar_dataservice.sh
#
# Qué se publica. En /dataservice cada GeoTIFF va JUNTO al dato del que sale,
# aunque en /data/output/jpss vivan en árboles separados (decidido el
# 2026-10-23, para que quien baje una carpeta del FTP tenga los dos):
#
#   /dataservice/jpss/        ←  /data/output/jpss/
#   level1/viirs              ←  level1/viirs (SDR .h5)
#                                + geotiff/{m_bands,i_bands,dnb,rgb}
#   level1/{atms,cris,omps}   ←  lo mismo (SDR .h5)
#   level2/<familia>          ←  level2/<familia> (.nc) + geotiff/<la suya>
#   vistas/…                  ←  vistas/… (JPG y los SVG de Skew-T), igual
#
# El reparto está en DESTINOS. Level 2 y vistas desde el 2026-10-23; level0
# no. Las carpetas van con nombre y nunca "todo /data/output/jpss", para que
# nada se publique por accidente. No choca con lo que publica la cadena vieja,
# que escribe en /dataservice/npp-jpss1.
#
# Hasta el 2026-10-23 los GeoTIFF se publicaban en geotiff/… también en
# /dataservice. Esas carpetas están en RETIRADAS: ya no reciben nada y solo se
# podan, así que en PUB_DS_DIAS días quedan vacías y se pueden borrar a mano.
#
# /dataservice es NFS (172.16.1.100:/data, soft). Medido el 2026-10-14: escribe
# a 1 GB/s, lo que da 10 GbE, y sin un timeout ni una retransmisión. Lo caro
# son los metadatos: un READDIR cuesta ~5 ms, así que recorrer árboles grandes
# del lado remoto es lento. De ahí tres decisiones:
#
#   - Se lista cada carpeta de destino UNA vez, y se compara contra el listado
#     local por nombre, tamaño y mtime. Nada de un stat remoto por archivo.
#   - Se copia con cp a un temporal oculto y luego mv, no con rsync: el mismo
#     resultado —ningún consumidor ve un archivo a medias, porque el rename es
#     atómico— en 1.7 s por GB y medio en vez de 3.9 (rsync copia en un solo
#     flujo con búferes chicos).
#   - Antes de empezar, un stat del destino con timeout. Si el NFS no responde,
#     se sale en vez de esperar archivo por archivo; el siguiente tic reintenta.
#
# Nunca va dentro de procesar_pasada.sh: un NFS lento frenaría la pasada con el
# candado tomado, y detrás se quedaría la siguiente.
#
# Cuándo un archivo está listo para salir:
#
#   - Lo que no es GeoTIFF (SDR, .nc de Level 2, vistas): cuando lleva QUIETO
#     PUB_DS_QUIETO_MIN minutos. Los SDR llegan ya terminados, pero varios
#     drivers de CSPP escriben sus .nc directo en level2/, y una vista se escribe
#     en su lugar: sin esto, un tic podía copiar un archivo a medias (se
#     corregiría en el siguiente, pero alguien pudo bajarlo entre tanto).
#   - GeoTIFF: solo si su pasada tiene marcador del renderizador más nuevo que
#     el archivo —polar2grid_l1 para los de Level 1, polar2grid para los de
#     Level 2—. Polar2Grid escribe directo en geotiff/, así que un .tif puede
#     estar a medias; el marcador se escribe solo cuando la etapa terminó bien.
#     La clave sale del nombre: noaa20_viirs_…_20261014_083828_… es
#     j01_d20261014_t083828.
#
# Retención: PUB_DS_DIAS días, contados por mtime, que se conserva al copiar.
# Se publica lo que tenga menos de eso y se borra del destino lo que tenga más,
# con el mismo corte en minutos: si no coincidieran, se publicaría y borraría
# el mismo archivo en cada tic.
#
# Variables de entorno:
#   PUB_DS_ORIGEN     Árbol de productos   (def. /data/output/jpss)
#   PUB_DS_DEST       Destino              (def. /dataservice/jpss)
#   PUB_DS_DIAS       Retención en días    (def. 5)
#   PUB_DS_QUIETO_MIN Minutos sin cambios para publicar lo que no es GeoTIFF (def. 2)
#   PUB_DS_LOCK       Candado propio       (def. /data/tmp/publicar_dataservice.lock)
#   PUB_DS_LOG        Log                  (def. /var/log/lanot/polares/cadena/publicar_dataservice.log)
#   ESTADO_BASE       Marcadores           (def. /data/output/jpss/state)
#   L1G_STATE_DIR     Marcadores de P2G L1 (def. $ESTADO_BASE/polar2grid_l1)
#   P2G_STATE_DIR     Marcadores de P2G L2 (def. $ESTADO_BASE/polar2grid)
#
# Uso:
#   publicar_dataservice.sh            publica y poda
#   publicar_dataservice.sh -n         dice qué haría, sin copiar ni borrar
# ==============================================================================

set -uo pipefail

ORIGEN="${PUB_DS_ORIGEN:-/data/output/jpss}"
DEST="${PUB_DS_DEST:-/dataservice/jpss}"
DIAS="${PUB_DS_DIAS:-5}"
LOCK="${PUB_DS_LOCK:-/data/tmp/publicar_dataservice.lock}"
LOG="${PUB_DS_LOG:-/var/log/lanot/polares/cadena/publicar_dataservice.log}"
ESTADO="${ESTADO_BASE:-/data/output/jpss/state}"
DIR_P2G_L1="${L1G_STATE_DIR:-$ESTADO/polar2grid_l1}"
DIR_P2G_L2="${P2G_STATE_DIR:-$ESTADO/polar2grid}"

# Una línea por carpeta de destino: el destino y, detrás, las carpetas de
# origen que se publican en él. Relativas a ORIGEN y DEST.
DESTINOS=(
    "level1/viirs  level1/viirs geotiff/m_bands geotiff/i_bands geotiff/dnb geotiff/rgb"
    "level1/atms   level1/atms"
    "level1/cris   level1/cris"
    "level1/omps   level1/omps"

    "level2/atmosphere  level2/atmosphere geotiff/atmos"
    "level2/lsr         level2/lsr        geotiff/lsr"
    "level2/acspo       level2/acspo      geotiff/acspo"
    "level2/fires       level2/fires      geotiff/fire"
    "level2/flood       level2/flood      geotiff/flood"
    "level2/cryosphere  level2/cryosphere"
    "level2/sounder     level2/sounder    geotiff/sounder"
    "level2/omps        level2/omps       geotiff/omps"
    "level2/mirs        level2/mirs       geotiff/mirs"

    "vistas/dnb            vistas/dnb"
    "vistas/rgb            vistas/rgb"
    "vistas/atmos          vistas/atmos"
    "vistas/lsr            vistas/lsr"
    "vistas/acspo          vistas/acspo"
    "vistas/fire           vistas/fire"
    "vistas/flood          vistas/flood"
    "vistas/sounder        vistas/sounder"
    "vistas/sounder/skewt  vistas/sounder/skewt"
    "vistas/omps           vistas/omps"
    "vistas/mirs           vistas/mirs"
)

# Carpetas de destino que ya no reciben nada: solo se podan.
RETIRADAS=(
    geotiff/m_bands geotiff/i_bands geotiff/dnb geotiff/rgb
)

# Los GeoTIFF de estas carpetas los hace run_polar2grid_l1.sh; los de las demás
# carpetas geotiff/, run_polar2grid_edr.sh. Decide qué marcador cuenta.
GEOTIFF_L1=" geotiff/m_bands geotiff/i_bands geotiff/dnb geotiff/rgb "

RETENCION_MIN=$((DIAS * 1440))
QUIETO_MIN="${PUB_DS_QUIETO_MIN:-2}"

DRY_RUN=0
case "${1:-}" in
    -n|--dry-run) DRY_RUN=1 ;;
    -h|--help)    sed -n '3,/^# ===/{/^# ===/!p}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "")           ;;
    *)            echo "ERROR: Argumento no reconocido: $1" >&2; exit 1 ;;
esac

# Un tic a la vez: si el anterior sigue copiando, este no hace nada.
mkdir -p "$(dirname "$LOCK")" 2>/dev/null || true
exec 9>"$LOCK"
flock -n 9 || exit 0

# Sin terminal (cron), al log; con terminal, a los dos. Cada 5 minutos, así que
# un tic sin nada que hacer no escribe: solo los que copian, borran o fallan.
SALIDA="$(mktemp -t publicar_dataservice_XXXXXX)"
trap 'rm -f "$SALIDA"' EXIT
exec 3>&1
exec > "$SALIDA" 2>&1

ahora() { date '+%Y-%m-%d %H:%M:%S'; }

INICIO=$(date +%s)
QUIETO_HASTA=$((INICIO - QUIETO_MIN * 60))
copiados=0
bytes=0
borrados=0
fallos=0
esperando=0

terminar() {
    local codigo="$1"
    if [ "$copiados" -gt 0 ] || [ "$borrados" -gt 0 ] || [ "$fallos" -gt 0 ] || [ "$DRY_RUN" -eq 1 ]; then
        echo "[$(ahora)] Copiados: $copiados ($((bytes / 1048576)) MB en $(( $(date +%s) - INICIO )) s)" \
             "· borrados: $borrados · fallos: $fallos · GeoTIFF esperando su marcador: $esperando"
        if [ "$DRY_RUN" -eq 1 ]; then
            cat "$SALIDA" >&3
        elif [ -t 3 ]; then
            tee -a "$LOG" < "$SALIDA" >&3
        else
            cat "$SALIDA" >> "$LOG"
        fi
    elif [ -t 3 ]; then
        echo "[$(ahora)] Nada que publicar ni podar." >&3
    fi
    exit "$codigo"
}

# ¿Está listo un GeoTIFF? Su pasada tiene que tener el marcador del renderizador
# que lo hizo, y ese marcador ser más nuevo que el archivo (un re-renderizado con
# --force reescribe los .tif antes de reescribir el marcador).
#
# La clave de la pasada es la hora de inicio de su VIIRS, y la hora del nombre
# es la del primer gránulo del sensor: coinciden en VIIRS, pero no en sondeos
# (atms-cris), MiRS (atms) ni ozono (omps). Para esos, cuenta el marcador del
# mismo satélite que caiga a menos de PUB_DS_MARGEN_S de esa hora: dos pasadas
# del mismo satélite están a una órbita (~100 min) una de otra.
MARGEN_S="${PUB_DS_MARGEN_S:-1800}"
declare -A _MARCADORES_SAT=()   # "<dir> <sat>" → "época:ruta …", leído una vez por tic

geotiff_listo() {
    local ruta="$1" origen_rel="$2" nombre sat marcadores exacto t m e r
    nombre="$(basename "$ruta")"
    # La hora va seguida de "_" (los de Polar2Grid) o de ".tif" (el de flood).
    # Los sondeos de NOAA-20 salían como j01_atms-cris_…, no noaa20_, hasta que
    # run_polar2grid_edr.sh los renombró (2026-11-04). j01|j02 se pueden quitar
    # cuando el último j01_ haya salido de la ventana de PUB_DS_DIAS.
    [[ "$nombre" =~ ^(npp|noaa20|noaa21|j01|j02)_[a-z-]+_.*_([0-9]{8})_([0-9]{6})[_.] ]] || return 1
    case "${BASH_REMATCH[1]}" in
        noaa20|j01) sat=j01 ;;
        noaa21|j02) sat=j02 ;;
        npp)    sat=npp ;;
    esac
    if [[ "$GEOTIFF_L1" == *" $origen_rel "* ]]; then
        marcadores="$DIR_P2G_L1"
    else
        marcadores="$DIR_P2G_L2"
    fi
    exacto="$marcadores/${sat}_d${BASH_REMATCH[2]}_t${BASH_REMATCH[3]}.done"
    [ -e "$exacto" ] && { [ "$exacto" -nt "$ruta" ]; return; }

    # Sin marcador con la hora exacta: el de la pasada más cercana.
    t=$(date -u -d "${BASH_REMATCH[2]} ${BASH_REMATCH[3]:0:2}:${BASH_REMATCH[3]:2:2}:${BASH_REMATCH[3]:4:2}" +%s) || return 1
    if [ -z "${_MARCADORES_SAT["$marcadores $sat"]+x}" ]; then
        _MARCADORES_SAT["$marcadores $sat"]=""
        for m in "$marcadores/${sat}"_d*_t*.done; do
            [ -e "$m" ] || continue
            [[ "$(basename "$m")" =~ _d([0-9]{8})_t([0-9]{2})([0-9]{2})([0-9]{2})\.done$ ]] || continue
            e=$(date -u -d "${BASH_REMATCH[1]} ${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}" +%s) || continue
            _MARCADORES_SAT["$marcadores $sat"]+="$e:$m "
        done
    fi
    for r in ${_MARCADORES_SAT["$marcadores $sat"]}; do
        e="${r%%:*}"; m="${r#*:}"
        [ $(( t > e ? t - e : e - t )) -le "$MARGEN_S" ] || continue
        [ "$m" -nt "$ruta" ]
        return
    done
    return 1
}

# Poda: lo que pasó de la retención, y temporales huérfanos de un tic que murió
# a media copia.
podar() {
    local rel="$1" destino="$DEST/$1" nombre
    [ -d "$destino" ] || return 0
    while IFS= read -r nombre; do
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  [dry-run] borraría $rel/$nombre"
            borrados=$((borrados + 1))
        elif rm -f "$destino/$nombre"; then
            borrados=$((borrados + 1))
        else
            fallos=$((fallos + 1))
        fi
    done < <(find "$destino" -maxdepth 1 -type f \
                  \( \( ! -name '.*' -mmin "+$RETENCION_MIN" \) -o \( -name '.*.tmp.*' -mmin +60 \) \) \
                  -printf '%f\n' 2>/dev/null)
}

# publicar_destino <destino> <origen>...
publicar_destino() {
    local rel="$1"; shift
    local destino="$DEST/$rel" o nombre tam mtime dir ruta origen_rel tmp
    local -a origenes=()
    local -A remoto=()

    for o in "$@"; do
        [ -d "$ORIGEN/$o" ] && origenes+=("$ORIGEN/$o")
    done
    [ "${#origenes[@]}" -gt 0 ] || return 0

    if [ "$DRY_RUN" -eq 0 ] && ! mkdir -p "$destino" 2>/dev/null; then
        echo "  ✗ $rel: no se pudo crear $destino"
        fallos=$((fallos + 1))
        return 0
    fi

    # El destino, de una sola lectura aunque lleguen varios orígenes. Los
    # temporales (.*) no cuentan.
    while IFS=$'\t' read -r nombre tam mtime; do
        remoto["$nombre"]="$tam $mtime"
    done < <(find "$destino" -maxdepth 1 -type f ! -name '.*' -printf '%f\t%s\t%Ts\n' 2>/dev/null)

    # Lo local dentro de la retención, de todos los orígenes y del más viejo al
    # más nuevo: si un tic se interrumpe, lo pendiente es lo más reciente y no
    # huecos en medio.
    while IFS=$'\t' read -r mtime tam nombre dir; do
        [ "${remoto[$nombre]:-}" != "$tam $mtime" ] || continue
        ruta="$dir/$nombre"
        origen_rel="${dir#"$ORIGEN"/}"
        if [ "${origen_rel%%/*}" = geotiff ]; then
            if ! geotiff_listo "$ruta" "$origen_rel"; then
                esperando=$((esperando + 1))
                continue
            fi
        elif [ "$mtime" -gt "$QUIETO_HASTA" ]; then
            continue     # se está escribiendo: al siguiente tic
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  [dry-run] copiaría $origen_rel/$nombre → $rel/"
            copiados=$((copiados + 1)); bytes=$((bytes + tam))
            continue
        fi
        tmp="$destino/.$nombre.tmp.$$"
        if cp --preserve=timestamps "$ruta" "$tmp" 2>/dev/null && mv -f "$tmp" "$destino/$nombre"; then
            copiados=$((copiados + 1)); bytes=$((bytes + tam))
        else
            rm -f "$tmp" 2>/dev/null
            echo "  ✗ $rel/$nombre: falló la copia"
            fallos=$((fallos + 1))
        fi
    # Nunca logs ni los .aux.xml que deja gdalinfo -stats: en level2/fires hay
    # miles de logs de CSPP Active Fire de antes del 2026-10-23.
    done < <(find "${origenes[@]}" -maxdepth 1 -type f -mmin "-$RETENCION_MIN" \
                  ! -name '*.log' ! -name '*.aux.xml' \
                  -printf '%Ts\t%s\t%f\t%h\n' | sort -n)

    podar "$rel"
}

# El NFS, antes de tocar nada. Con montaje soft una operación puede tardar
# minutos en devolver error; mejor saberlo aquí una vez que en cada archivo.
if ! timeout 30 stat -f "$DEST" > /dev/null 2>&1; then
    echo "[$(ahora)] ✗ $DEST no responde (NFS); se reintenta en el siguiente tic"
    fallos=$((fallos + 1))
    terminar 1
fi

for linea in "${DESTINOS[@]}"; do
    read -r -a campos <<< "$linea"
    publicar_destino "${campos[@]}"
done

for c in "${RETIRADAS[@]}"; do
    podar "$c"
done

[ "$fallos" -eq 0 ] && terminar 0 || terminar 1
