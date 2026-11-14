#!/bin/bash
# ==============================================================================
# preparar_servidor.sh — deja un servidor listo para correr la cadena polar.
#
# Sustituye a setup_ambiente_rt_stps.sh y deploy_static_data_sdr.sh, que estaban
# divididos por la costura equivocada: se separaban por software (RT-STPS ÷ SDR)
# cuando los dos creaban árboles, extraían cosas y homologaban permisos, y se
# pisaban (el primero hacía chown -R sobre /data/opt, que es justo el árbol que
# llenaba el segundo, así que el resultado dependía del orden).
#
# Se corre UNA VEZ por servidor, con sudo, y desde el clon del repositorio: la
# fase de estáticos necesita contenedores/tarballs.tsv, que no se instala.
# El código de operación se instala aparte, con scripts/instalar.sh.
#
# Es idempotente: cada fase comprueba antes de actuar, así que volver a correrlo
# no rompe nada y sirve para completar un servidor a medio preparar.
#
# Fases:
#   1  Directorios, dueño y permisos
#   2  Estático de CSPP SDR    → /data/opt/SDR_4_1
#   3  Estático de CSPP ATMOS  → /data/opt/CSPP_ATMOS_1_0/anc/static
#   4  XML de RT-STPS, extraídos del .sif
#   5  leapsec.dat, extraído del .sif
#   6  Primer llenado de los cachés de ancillary dinámico
#
# Uso:
#   sudo ./scripts/preparar_servidor.sh              todas las fases
#   sudo ./scripts/preparar_servidor.sh --solo 4     solo esa
#        ./scripts/preparar_servidor.sh --verificar  audita sin tocar nada
#        ./scripts/preparar_servidor.sh --dry-run    dice qué haría
#
# Variables de entorno:
#   RAIZ        Prefijo de TODAS las rutas del host. Con RAIZ=/tmp/prueba el
#               script se puede ejercitar en una máquina sin /data.
#   DUENO       Dueño de los árboles de datos    (def. lanotadm:lanotadm)
#   TARBALLS    Bundles                          (def. /opt/contenedores)
#   TARFILES    Estáticos                        (def. $TARBALLS/tarfiles)
#   RTSTPS_SIF  Imagen de RT-STPS                (def. /opt/containers/rt_stps_7.0.sif)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFIESTO="${MANIFIESTO:-$SCRIPT_DIR/../contenedores/tarballs.tsv}"
INVENTARIO="${INVENTARIO:-$SCRIPT_DIR/../contenedores/obtener_tarballs.sh}"

RAIZ="${RAIZ:-}"
DUENO="${DUENO:-lanotadm:lanotadm}"
TARBALLS="${TARBALLS:-/opt/contenedores}"
TARFILES="${TARFILES:-$TARBALLS/tarfiles}"
RTSTPS_SIF="${RTSTPS_SIF:-/opt/containers/rt_stps_7.0.sif}"

# Rutas dentro del contenedor de RT-STPS
RTSTPS_XML_INTERNO="/opt/rt-stps/config"
RTSTPS_LEAPSEC_INTERNO="/opt/rt-stps/leapsec.dat"

XMLS=(npp.xml jpss1.xml jpss2.xml)

# ==============================================================================
# EL ÁRBOL
#
# Derivado de los valores por omisión que declaran los once run_*.sh, no de lo
# que decía el script viejo: aquel creaba /data/output/{level0,level1,...}, que
# es el árbol de la primera fase de la migración, y de state/ solo rt-stps.
# ==============================================================================

DIRS_775=(
    /data/output/jpss/level0
    /data/output/jpss/level1/viirs
    /data/output/jpss/level1/atms
    /data/output/jpss/level1/cris
    /data/output/jpss/level1/omps
    /data/output/jpss/level2/atmos
    /data/output/jpss/level2/lsr
    /data/output/jpss/level2/cryo
    /data/output/jpss/level2/acspo
    /data/output/jpss/level2/fires
    /data/output/jpss/level2/flood
    /data/output/jpss/level2/omps
    /data/output/jpss/level2/sounder
    /data/output/jpss/level2/mirs
    /data/output/jpss/geotiff/m_bands
    /data/output/jpss/geotiff/i_bands
    /data/output/jpss/geotiff/dnb
    /data/output/jpss/geotiff/rgb
    /data/output/jpss/geotiff/atmos
    /data/output/jpss/geotiff/lsr
    /data/output/jpss/geotiff/acspo
    /data/output/jpss/geotiff/fire
    /data/output/jpss/geotiff/flood
    /data/output/jpss/geotiff/mirs
    /data/output/jpss/vistas/dnb
    /data/output/jpss/vistas/rgb
    /data/output/jpss/vistas/atmos
    /data/output/jpss/vistas/lsr
    /data/output/jpss/vistas/acspo
    /data/output/jpss/vistas/fire
    /data/output/jpss/vistas/flood
    /data/output/jpss/vistas/mirs
    /data/output/jpss/state/rt-stps
    /data/output/jpss/state/cspp-sdr
    /data/output/jpss/state/cspp-atmos
    /data/output/jpss/state/cspp-lsr
    /data/output/jpss/state/cspp-cryo
    /data/output/jpss/state/cspp-acspo
    /data/output/jpss/state/cspp-active-fire
    /data/output/jpss/state/cspp-flood
    /data/output/jpss/state/cspp-omps
    /data/output/jpss/state/cspp-omps-tos
    /data/output/jpss/state/cspp-heap
    /data/output/jpss/state/cspp-mirs
    /data/output/jpss/state/polar2grid
    /data/output/jpss/state/polar2grid_l1
    /data/tmp
    /datawork/input/polar/raw
    /var/log/lanot/polares/rt-stps
    /var/log/lanot/polares/cspp-sdr
    /var/log/lanot/polares/cspp-edr
    /var/log/lanot/polares/polar2grid
    /var/log/lanot/polares/cadena
    # Un caché de ancillary POR SOFTWARE: delete_old_anc.sh de ATMOS borra todo
    # lo de más de 14 días del directorio que se le indique, así que apuntarlo al
    # caché de SDR se lo llevaría entero.
    /data/ancillary/common
    /data/ancillary/atmos
    /data/ancillary/acspo
    /data/ancillary/active_fire_cache
    /data/ancillary/heap
    # MiRS no descarga nada (--noSFR -l), pero su driver exige un caché escribible
    /data/ancillary/mirs
)

DIRS_755=(
    /data/opt
    /data/opt/RT-STPS/rt-stps/config
    /opt/containers
    /opt/contenedores
)

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  sudo $0                 Todas las fases
  sudo $0 --solo <n>      Solo la fase n
       $0 --verificar     Audita sin tocar nada
       $0 --dry-run       Dice qué haría

Fases:
  1  Directorios, dueño y permisos
  2  Estático de CSPP SDR
  3  Estático de CSPP ATMOS
  4  XML de RT-STPS (del .sif)
  5  leapsec.dat (del .sif)
  6  Primer llenado de los cachés de ancillary

Opciones:
  -s, --solo <n>           Una sola fase
  -v, --verificar          Solo auditar
  -n, --dry-run            No ejecutar, solo decir
      --conservar-tarballs No borrar los estáticos ya extraídos
  -h, --help

Raíz:      ${RAIZ:-(ninguna)}
Dueño:     $DUENO
Estáticos: $TARFILES
EOF
}

paso() { echo ""; echo "=============================================================="; echo "  $*"; echo "=============================================================="; }

# Ejecuta, o dice qué ejecutaría.
correr() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] $*"
        return 0
    fi
    "$@"
}

filas_estaticas() {
    grep -v '^[[:space:]]*#' "$MANIFIESTO" | grep -v '^[[:space:]]*$' | awk -F'\t' -v s="$1" '$1=="estatico" && $2==s'
}

# ¿Está poblado el destino de un estático? Misma regla que obtener_tarballs.sh.
desplegado() {
    local c="$1"
    [ "$c" != "-" ] || return 1
    c="$RAIZ$c"
    [ -e "$c" ] || return 1
    if [ -d "$c" ]; then
        [ -n "$(ls -A "$c" 2>/dev/null)" ] || return 1
    else
        [ -s "$c" ] || return 1
    fi
    return 0
}

# ------------------------------------------------------------------- fase 1
fase_1_directorios() {
    paso "[1/7] Directorios, dueño y permisos"
    local d faltaban=0

    for d in "${DIRS_755[@]}" "${DIRS_775[@]}"; do
        if [ ! -d "$RAIZ$d" ]; then
            faltaban=$((faltaban + 1))
        fi
    done

    for d in "${DIRS_755[@]}"; do
        correr mkdir -p "$RAIZ$d"
        correr chmod 755 "$RAIZ$d"
    done
    for d in "${DIRS_775[@]}"; do
        correr mkdir -p "$RAIZ$d"
        correr chmod 775 "$RAIZ$d"
    done

    # El chown se acota a lo que este script crea. El script viejo hacía
    # chown -R sobre /data/opt entero, que puede tener software de otros.
    for d in "${DIRS_755[@]}" "${DIRS_775[@]}"; do
        correr chown "$DUENO" "$RAIZ$d"
    done

    echo "  ${#DIRS_755[@]} + ${#DIRS_775[@]} directorios; faltaban $faltaban"
}

# ---------------------------------------------------------------- fases 2 y 3
desplegar_estaticos() {
    local slug="$1" etiqueta="$2"
    local rol s version archivo origen receta destino comprobacion sha1
    local ruta hash desde n=0 ya=0 fallos=0

    paso "$etiqueta"

    if [ ! -f "$MANIFIESTO" ]; then
        echo "ERROR: no se encontró el manifiesto: $MANIFIESTO" >&2
        echo "Esta fase se corre desde el clon del repositorio." >&2
        return 1
    fi

    while IFS=$'\t' read -r rol s version archivo origen receta destino comprobacion sha1; do
        if desplegado "$comprobacion"; then
            echo "  ○ $archivo — ya desplegado"
            ya=$((ya + 1))
            # Si el tarball sobrevivió a una corrida anterior, este es el momento.
            if [ -f "$TARFILES/$archivo" ] && [ "$CONSERVAR" -eq 0 ]; then
                echo "    borrando el tarball redundante"
                correr rm -f "$TARFILES/$archivo"
            fi
            continue
        fi

        # Se busca en los dos sitios. TARFILES es donde viven los estáticos, pero
        # el bundle de HEAP llegó aquí desde el otro lado: era entrada de
        # 'apptainer build' y vivía en TARBALLS hasta que dejó de instalarse en
        # su imagen (2026-08-29). Obligar a moverlo a mano sería una trampa
        # silenciosa para quien despliegue un servidor nuevo.
        ruta="$TARFILES/$archivo"; desde="$TARFILES"
        if [ ! -f "$ruta" ] && [ -f "$TARBALLS/$archivo" ]; then
            ruta="$TARBALLS/$archivo"; desde="$TARBALLS"
        fi
        if [ ! -f "$ruta" ]; then
            echo "  ✗ $archivo — FALTA y su destino no está poblado"
            echo "    buscado en $TARFILES y en $TARBALLS"
            fallos=$((fallos + 1))
            continue
        fi

        echo "  → $archivo"

        # 1 de 3: el sha1, si está registrado.
        if [ "$sha1" != "-" ]; then
            hash="$(sha1sum "$ruta" | awk '{print $1}')"
            if [ "$hash" != "$sha1" ]; then
                echo "    ✗ SHA1 no cuadra; no se extrae"
                echo "      esperado: $sha1"
                echo "      obtenido: $hash"
                fallos=$((fallos + 1))
                continue
            fi
            echo "    ✓ sha1"
        else
            echo "    ? sin sha1 registrado (contenedores/obtener_tarballs.sh --registrar)"
        fi

        # 2 de 3: que tar termine bien.
        correr mkdir -p "$RAIZ$destino"
        if ! correr tar -zxf "$ruta" -C "$RAIZ$destino"; then
            echo "    ✗ falló la extracción"
            fallos=$((fallos + 1))
            continue
        fi
        echo "    ✓ extraído en $RAIZ$destino"

        # 3 de 3: que el destino haya quedado poblado. Solo entonces se borra el
        # tarball: es lo que hace seguro deshacerse de decenas de GB.
        if [ "$DRY_RUN" -eq 0 ] && ! desplegado "$comprobacion"; then
            echo "    ✗ el destino sigue sin poblarse: $RAIZ$comprobacion"
            echo "      se conserva el tarball"
            fallos=$((fallos + 1))
            continue
        fi
        echo "    ✓ destino poblado"

        if [ "$CONSERVAR" -eq 1 ]; then
            echo "    ○ se conserva el tarball (--conservar-tarballs)"
        elif [ "$desde" = "$TARBALLS" ]; then
            # Los estáticos se borran porque duplican lo que ya está en /data/opt
            # y se pueden volver a bajar. Este no: está en el directorio de los
            # bundles, viene de un sitio con registro y, desde que no entra en
            # ninguna imagen, es la ÚNICA copia del software.
            echo "    ○ se conserva: está en $TARBALLS, con los bundles"
        else
            correr rm -f "$ruta"
            echo "    ✓ tarball borrado"
        fi
        n=$((n + 1))
    done < <(filas_estaticas "$slug")

    correr chown -R "$DUENO" "$RAIZ/data/opt" 2>/dev/null || true

    echo ""
    echo "  Desplegados ahora: $n · ya estaban: $ya · con problemas: $fallos"
    [ "$fallos" -eq 0 ] || return 1
    return 0
}

fase_2_sdr()   { desplegar_estaticos jpss_sdr    "[2/7] Estático de CSPP SDR"; }
fase_3_atmos() { desplegar_estaticos viirs_atmos "[3/7] Estático de CSPP ATMOS"; }

# HEAP no despliega un estático sino el software entero, y es deliberado: su
# árbol de instalación tiene que ser escribible, porque el Fortran de la
# recuperación abre 'fort.40' dentro de él. Con el bundle en el .sif la corrida
# termina en 0 sin escribir un solo sondeo. Ver contenedores/cspp_heap_v3.0.def.
fase_7_heap() {
    desplegar_estaticos heap "[7/7] Bundle de CSPP HEAP" || return 1

    # Los demás estáticos son DATOS: basta con poder leerlos. Este es SOFTWARE, y
    # el chown -R al dueño de /data/opt deja los ejecutables fuera del alcance de
    # quien corra la cadena si su usuario no es ese. El síntoma no dice
    # "permisos" en ningún sitio visible: el preprocesador muere con
    #     sh: .../Common_Bin/main_nucaps_preprocessor: Permission denied
    # en un log interno del gránulo, y el wrapper devuelve 0 igualmente. Visto
    # en tahan el 2026-08-29, la primera vez que se corrió con el bundle
    # desplegado en /data/opt en vez de extraído a mano.
    #
    # a+rX con equis MAYÚSCULA: lectura para todos, y ejecución solo en
    # directorios y en lo que ya fuera ejecutable para alguien. Con x minúscula
    # se volvería ejecutable cada tabla de coeficientes del paquete.
    if [ -d "$RAIZ/data/opt/CSPP_HEAP_3_0" ]; then
        echo "  → permisos: a+rX y g+w sobre el bundle"
        # a+rX: leer y ejecutar. Sin esto muere el preprocesador con
        #   sh: .../main_nucaps_preprocessor: Permission denied
        #
        # g+w: ESCRIBIR. Sin esto muere airsb103.exe un paso más allá con
        #   Fortran runtime error: Cannot open file 'fort.40': Permission denied
        # y, como siempre en este paquete, el wrapper devuelve 0 igualmente.
        # Los dos fallos se dieron seguidos el 2026-08-29 y son la misma
        # historia: este bundle no es un estático de solo lectura como los
        # demás, es software que escribe en su propio árbol.
        #
        # Se concede al GRUPO y no a todos: quien corra la cadena tiene que
        # pertenecer al grupo de $DUENO. Compruébalo con 'id' antes de dar por
        # buena esta fase; si tu usuario no está en él, o lo agregas
        # (usermod -aG) o corres la cadena como ese usuario.
        correr chmod -R a+rX "$RAIZ/data/opt/CSPP_HEAP_3_0"
        correr chmod -R g+w  "$RAIZ/data/opt/CSPP_HEAP_3_0"

        grupo="${DUENO#*:}"
        if [ "$DRY_RUN" -eq 0 ] && ! id -nG | tr ' ' '\n' | grep -qx "$grupo"; then
            echo "    ⚠ $(id -un) NO pertenece al grupo '$grupo'."
            echo "      HEAP fallará al escribir dentro de su árbol. Opciones:"
            echo "        sudo usermod -aG $grupo $(id -un)   (y volver a entrar)"
            echo "        o correr la cadena como ${DUENO%%:*}"
        fi
    fi
}

# ------------------------------------------------------------------- fase 4
fase_4_xml() {
    paso "[4/7] XML de RT-STPS"
    local destino="$RAIZ/data/opt/RT-STPS/rt-stps/config"
    local xml n=0

    if [ ! -f "$RTSTPS_SIF" ]; then
        echo "ERROR: no está la imagen de RT-STPS: $RTSTPS_SIF" >&2
        echo "Compílala antes: ./contenedores/construir.sh rt_stps_7.0" >&2
        return 1
    fi

    correr mkdir -p "$destino"
    for xml in "${XMLS[@]}"; do
        if [ -f "$destino/$xml" ]; then
            echo "  ○ $xml — ya está"
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "    [dry-run] extraer $xml del contenedor"
            continue
        fi
        if apptainer exec "$RTSTPS_SIF" cat "$RTSTPS_XML_INTERNO/$xml" > "$destino/$xml" 2>/dev/null \
           && [ -s "$destino/$xml" ]; then
            echo "  ✓ $xml"
            n=$((n + 1))
        else
            rm -f "$destino/$xml"
            echo "  ✗ $xml — no se pudo extraer del contenedor" >&2
            return 1
        fi
    done
    correr chown -R "$DUENO" "$destino"
    echo "  Extraídos: $n"
}

# ------------------------------------------------------------------- fase 5
#
# El script viejo intentaba tres URL y, si todas fallaban, escribía un
# PLACEHOLDER con datos hasta 2016 y seguía como si nada. Peor: al no quedar
# vacío, dejaba inalcanzable la extracción del contenedor, que era la única
# fuente con el formato que RT-STPS espera. Aquí hay una sola fuente y, si no
# está, la fase falla.
fase_5_leapsec() {
    paso "[5/7] leapsec.dat"
    local destino="$RAIZ/data/ancillary/common/leapsec.dat"
    local tmp

    if [ -s "$destino" ]; then
        echo "  ○ ya está ($(date -r "$destino" +%F 2>/dev/null || echo "fecha desconocida"))"
        echo "    Se refresca con update_sdr_daily.sh, no aquí."
        return 0
    fi

    if [ ! -f "$RTSTPS_SIF" ]; then
        echo "ERROR: no está la imagen de RT-STPS: $RTSTPS_SIF" >&2
        return 1
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "    [dry-run] extraer $RTSTPS_LEAPSEC_INTERNO del contenedor"
        return 0
    fi

    correr mkdir -p "$(dirname "$destino")"
    tmp="$(mktemp)"
    if apptainer exec "$RTSTPS_SIF" cat "$RTSTPS_LEAPSEC_INTERNO" > "$tmp" 2>/dev/null \
       && [ -s "$tmp" ]; then
        mv "$tmp" "$destino"
        chown "$DUENO" "$destino"
        echo "  ✓ extraído del contenedor ($(wc -l < "$destino") líneas)"
    else
        rm -f "$tmp"
        echo "ERROR: no se pudo extraer $RTSTPS_LEAPSEC_INTERNO de $RTSTPS_SIF" >&2
        echo "Sin leapsec.dat, RT-STPS fecha mal los datos. No se inventa uno." >&2
        return 1
    fi
}

# ------------------------------------------------------------------- fase 6
fase_6_cache() {
    paso "[6/7] Primer llenado de los cachés de ancillary"
    local s fallos=0

    for s in update_sdr_daily.sh update_atmos_ancillary.sh; do
        if [ ! -x "$SCRIPT_DIR/$s" ]; then
            echo "  ✗ no está o no es ejecutable: $SCRIPT_DIR/$s"
            fallos=$((fallos + 1))
            continue
        fi
        echo "  → $s (puede tardar: ATMOS baja ~6 GB)"
        if ! correr "$SCRIPT_DIR/$s"; then
            echo "  ✗ $s terminó con error"
            fallos=$((fallos + 1))
        fi
    done

    echo ""
    echo "  Estos dos van además en cron; ver docs/estado_y_pendientes.md."
    [ "$fallos" -eq 0 ] || return 1
}

# --------------------------------------------------------------- verificación
verificar() {
    local d faltan=0 xml n_xml=0

    paso "Auditoría (no se toca nada)"
    [ -z "$RAIZ" ] || echo "Raíz: $RAIZ"

    echo "Directorios:"
    for d in "${DIRS_755[@]}" "${DIRS_775[@]}"; do
        if [ ! -d "$RAIZ$d" ]; then
            echo "  ✗ falta $d"
            faltan=$((faltan + 1))
        fi
    done
    [ "$faltan" -ne 0 ] || echo "  ✓ los $(( ${#DIRS_755[@]} + ${#DIRS_775[@]} )) están"

    echo ""
    echo "Estáticos:"
    if [ -x "$INVENTARIO" ]; then
        RAIZ="$RAIZ" TARBALLS="$TARBALLS" TARFILES="$TARFILES" \
            "$INVENTARIO" --verificar | sed -n '/estatico\|static\|STATIC/p;$p' || true
        echo "  (detalle completo: $INVENTARIO --verificar)"
    else
        echo "  ? no está $INVENTARIO; ¿se está corriendo fuera del clon?"
    fi

    echo ""
    echo "XML de RT-STPS:"
    for xml in "${XMLS[@]}"; do
        if [ -s "$RAIZ/data/opt/RT-STPS/rt-stps/config/$xml" ]; then
            n_xml=$((n_xml + 1))
        else
            echo "  ✗ falta $xml"
            faltan=$((faltan + 1))
        fi
    done
    [ "$n_xml" -ne "${#XMLS[@]}" ] || echo "  ✓ los ${#XMLS[@]} están"

    echo ""
    echo "leapsec.dat:"
    if [ -s "$RAIZ/data/ancillary/common/leapsec.dat" ]; then
        echo "  ✓ presente"
    else
        echo "  ✗ falta o está vacío"
        faltan=$((faltan + 1))
    fi

    echo ""
    echo "Cachés de ancillary:"
    # El de HEAP no lo llena la fase 6 ni ningún cron: lo puebla el propio
    # driver la primera vez que corre una pasada, así que vacío es lo normal
    # hasta entonces.
    for d in /data/ancillary /data/ancillary/atmos /data/ancillary/heap; do
        if [ -d "$RAIZ$d" ] && [ -n "$(ls -A "$RAIZ$d" 2>/dev/null)" ]; then
            echo "  ✓ $d con contenido"
        else
            echo "  ~ $d vacío (fase 6, o el cron todavía no ha corrido)"
        fi
    done

    echo ""
    if [ "$faltan" -eq 0 ]; then
        echo "El servidor está preparado."
        return 0
    fi
    echo "Faltan $faltan cosas. Corre: sudo $0"
    return 1
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================

DRY_RUN=0
CONSERVAR=0
SOLO=""
MODO="preparar"

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run)          DRY_RUN=1 ;;
        -v|--verificar)        MODO="verificar" ;;
        --conservar-tarballs)  CONSERVAR=1 ;;
        -s|--solo)
            if [ $# -lt 2 ]; then
                echo "ERROR: --solo necesita un número de fase" >&2
                exit 1
            fi
            SOLO="$2"
            shift
            ;;
        -h|--help) uso; exit 0 ;;
        *)
            echo "ERROR: Argumento no reconocido: $1" >&2
            uso >&2
            exit 1
            ;;
    esac
    shift
done

if [ "$MODO" = "verificar" ]; then
    verificar
    exit $?
fi

# La guarda de root va aquí y no antes: --verificar, --dry-run y --help no
# necesitan permisos, y son justo lo que se corre para mirar sin arreglar.
if [ "$DRY_RUN" -eq 0 ] && [ "$EUID" -ne 0 ] && [ -z "$RAIZ" ]; then
    echo "ERROR: hay que correrlo como root (sudo), o con RAIZ apuntando a un" >&2
    echo "       directorio de prueba." >&2
    exit 1
fi

FASES=(fase_1_directorios fase_2_sdr fase_3_atmos fase_4_xml fase_5_leapsec fase_6_cache fase_7_heap)

if [ -n "$SOLO" ]; then
    case "$SOLO" in
        [1-7]) ;;
        *) echo "ERROR: --solo acepta 1..7, no '$SOLO'" >&2; exit 1 ;;
    esac
    "${FASES[$((SOLO - 1))]}"
    exit $?
fi

FALLOS=0
for f in "${FASES[@]}"; do
    "$f" || { echo "  ⚠ la fase $f falló; se sigue con las demás" >&2; FALLOS=$((FALLOS + 1)); }
done

paso "Resumen"
if [ "$FALLOS" -eq 0 ]; then
    echo "  Las siete fases terminaron bien."
    echo ""
    echo "  Siguiente paso: instalar el código de operación."
    echo "    sudo ./scripts/instalar.sh"
    exit 0
fi
echo "  Fases con problemas: $FALLOS"
echo "  Revisa arriba y repite con --solo <n>."
exit 1
