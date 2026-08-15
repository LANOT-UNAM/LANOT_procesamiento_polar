#!/bin/bash
# ==============================================================================
# obtener_tarballs.sh — inventario de los tarballs de CSPP, RT-STPS y Polar2Grid
#
# Trabaja sobre contenedores/tarballs.tsv, que es la única lista completa de qué
# archivos necesita un servidor de la cadena. Cuatro modos:
#
#   --verificar   (por omisión, sin red) Qué falta, qué sobra y qué no cuadra.
#   --descargar   Imprime qué bajar y de dónde. NO baja: el sitio de CSPP pide
#                 registro, así que no hay URL directa que automatizar y se
#                 decidió no guardar credenciales ni cookies.
#   --novedades   Compara contra la portada pública de CSPP y avisa de versiones
#                 nuevas. Es el único aviso que existe: el sitio no tiene lista
#                 de correo ni RSS, solo un foro.
#   --registrar   Llena los sha1 del manifiesto a partir de los tarballs que ya
#                 están en el host. Correrlo ANTES de borrar nada.
#
# Los dos roles del manifiesto se verifican distinto, y esa es la idea central:
#   bundle    se conserva, porque alimenta `apptainer build` → se verifica el
#             .tar.gz y su sha1.
#   estatico  se borra tras extraerlo → se verifica el DESTINO, que es el estado
#             del que de verdad dependen los run_*.sh (run_atmos_edr.sh aborta si
#             falta .../anc/static/Config).
#
# Variables de entorno:
#   TARBALLS    Dónde viven los bundles      (def. /opt/contenedores)
#   TARFILES    Dónde viven los estáticos    (def. $TARBALLS/tarfiles)
#   MANIFIESTO  Otro manifiesto              (def. junto a este script)
#   CSPP_PORTADA  Otra portada               (def. https://cimss.ssec.wisc.edu/cspp/)
#   RAIZ        Prefijo para 'destino' y 'comprobacion', que en el manifiesto son
#               absolutos (/data/opt/...). Con RAIZ=/tmp/prueba todo el inventario
#               se puede ejercitar en una máquina que no tenga /data.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFIESTO="${MANIFIESTO:-$SCRIPT_DIR/tarballs.tsv}"
TARBALLS="${TARBALLS:-/opt/contenedores}"
TARFILES="${TARFILES:-$TARBALLS/tarfiles}"
CSPP_PORTADA="${CSPP_PORTADA:-https://cimss.ssec.wisc.edu/cspp/}"
RAIZ="${RAIZ:-}"

URL_CIMSS="https://cimss.ssec.wisc.edu/cspp/download/"
URL_DRL="https://directreadout.sci.gsfc.nasa.gov/"

TEMPORALES="$(mktemp -d)"
trap 'rm -rf "$TEMPORALES"' EXIT

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0                Verifica el inventario (sin red)
  $0 --descargar    Qué falta y de dónde bajarlo
  $0 --novedades    Compara versiones contra la portada de CSPP
  $0 --registrar    Llena los sha1 del manifiesto desde los tarballs presentes

Opciones:
  -v, --verificar   Modo por omisión
  -d, --descargar
  -n, --novedades
  -r, --registrar
  -h, --help

Manifiesto: $MANIFIESTO
Bundles:    $TARBALLS
Estáticos:  $TARFILES
EOF
}

# Las filas de datos del manifiesto, sin comentarios ni líneas vacías.
filas() {
    grep -v '^[[:space:]]*#' "$MANIFIESTO" | grep -v '^[[:space:]]*$'
}

# Dónde debe estar el tarball de una fila, según su rol.
ruta_de() {
    case "$1" in
        bundle)   echo "$TARBALLS/$2" ;;
        estatico) echo "$TARFILES/$2" ;;
        *)        echo "" ;;
    esac
}

# ¿El destino de un estático está poblado? Vacío o inexistente cuentan como no.
desplegado() {
    local comprobacion="$1"
    [ "$comprobacion" != "-" ] || return 1
    comprobacion="$RAIZ$comprobacion"
    [ -e "$comprobacion" ] || return 1
    if [ -d "$comprobacion" ]; then
        [ -n "$(ls -A "$comprobacion" 2>/dev/null)" ] || return 1
    else
        [ -s "$comprobacion" ] || return 1
    fi
    return 0
}

sha1_de() {
    sha1sum "$1" | awk '{print $1}'
}

# ------------------------------------------------------------------ verificar
verificar() {
    local ok=0 faltan=0 malos=0 pendientes=0 sin_sha1=0 redundantes=0
    local rol slug version archivo origen receta destino comprobacion sha1
    local ruta hash

    echo "=== Inventario de tarballs ==="
    echo "Manifiesto: $MANIFIESTO"
    echo ""

    while IFS=$'\t' read -r rol slug version archivo origen receta destino comprobacion sha1; do
        ruta="$(ruta_de "$rol" "$archivo")"

        if [ "$rol" = "estatico" ] && desplegado "$comprobacion"; then
            # El caso normal una vez preparado el servidor: el contenido está en
            # su sitio y el tarball ya no hace falta.
            if [ -f "$ruta" ]; then
                echo "  ~ $archivo — desplegado; el tarball es redundante y se puede borrar"
                redundantes=$((redundantes + 1))
            else
                echo "  ✓ $archivo — desplegado en $RAIZ$comprobacion"
            fi
            ok=$((ok + 1))
            continue
        fi

        if [ ! -f "$ruta" ]; then
            if [ "$rol" = "estatico" ]; then
                echo "  ✗ $archivo — FALTA, y su destino no está poblado"
            else
                echo "  ✗ $archivo — FALTA (receta $receta)"
            fi
            faltan=$((faltan + 1))
            continue
        fi

        if [ "$sha1" = "-" ]; then
            echo "  ? $archivo — presente, sin sha1 registrado (usa --registrar)"
            sin_sha1=$((sin_sha1 + 1))
        else
            hash="$(sha1_de "$ruta")"
            if [ "$hash" != "$sha1" ]; then
                echo "  ✗ $archivo — SHA1 NO CUADRA"
                echo "      esperado: $sha1"
                echo "      obtenido: $hash"
                malos=$((malos + 1))
                continue
            fi
        fi

        if [ "$rol" = "estatico" ]; then
            echo "  → $archivo — presente, pendiente de extraer en $RAIZ$destino"
            pendientes=$((pendientes + 1))
        else
            echo "  ✓ $archivo"
            ok=$((ok + 1))
        fi
    done < <(filas)

    # Tarballs que están en el host pero no en el manifiesto. Casi siempre son
    # versiones retiradas, que sí se pueden borrar porque su imagen ya no se
    # compila; por eso se listan aparte y no como error.
    local sobrantes=0 f base
    if [ -d "$TARBALLS" ]; then
        for f in "$TARBALLS"/*.tar.gz; do
            [ -e "$f" ] || continue
            base="$(basename "$f")"
            if ! filas | cut -f4 | grep -qxF "$base"; then
                if [ "$sobrantes" -eq 0 ]; then
                    echo ""
                    echo "No están en el manifiesto (¿versión retirada? se pueden borrar):"
                fi
                echo "  · $base ($(du -h "$f" | cut -f1))"
                sobrantes=$((sobrantes + 1))
            fi
        done
    fi

    # Dos estáticos con la misma comprobación no se pueden distinguir: extraído
    # uno, el otro se daría por desplegado sin estarlo. Pasa si --registrar cayó
    # en un archivo que ambos tarballs comparten. Se avisa en vez de callarlo.
    local ambiguas
    ambiguas="$(filas | awk -F'\t' '$1=="estatico" && $8!="-" {print $8}' | sort | uniq -d)"
    if [ -n "$ambiguas" ]; then
        echo ""
        echo "AVISO: comprobaciones repetidas; esas filas no se distinguen entre sí:"
        printf '%s\n' "$ambiguas" | while IFS= read -r c; do echo "  · $c"; done
        echo "  Corrígelas a mano en el manifiesto, con un archivo propio de cada tarball."
    fi

    echo ""
    echo "=== Resumen ==="
    echo "  En orden:              $ok"
    [ "$pendientes"  -eq 0 ] || echo "  Pendientes de extraer: $pendientes"
    [ "$redundantes" -eq 0 ] || echo "  Tarballs redundantes:  $redundantes"
    [ "$sin_sha1"    -eq 0 ] || echo "  Sin sha1 registrado:   $sin_sha1"
    [ "$sobrantes"   -eq 0 ] || echo "  Fuera del manifiesto:  $sobrantes"
    [ "$faltan"      -eq 0 ] || echo "  FALTAN:                $faltan"
    [ "$malos"       -eq 0 ] || echo "  SHA1 INCORRECTO:       $malos"

    if [ "$faltan" -gt 0 ] || [ "$malos" -gt 0 ]; then
        echo ""
        echo "Hay archivos faltantes o corruptos. '$0 --descargar' dice cuáles."
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------ descargar
descargar() {
    local rol slug version archivo origen receta destino comprobacion sha1
    local ruta n=0

    echo "=== Qué falta ==="
    echo ""
    echo "La descarga NO se automatiza: los dos sitios piden registro y no hay"
    echo "URL directa. Baja estos archivos desde el navegador y déjalos donde"
    echo "dice cada uno; después, '$0 --verificar' confirma que llegaron bien."
    echo ""

    while IFS=$'\t' read -r rol slug version archivo origen receta destino comprobacion sha1; do
        ruta="$(ruta_de "$rol" "$archivo")"
        # Un estático ya desplegado no hace falta bajarlo aunque su tarball no esté:
        # justamente se borra tras extraerlo.
        if [ "$rol" = "estatico" ] && desplegado "$comprobacion"; then
            continue
        fi
        [ ! -f "$ruta" ] || continue

        n=$((n + 1))
        echo "  $archivo"
        case "$origen" in
            cimss) echo "      de:    $URL_CIMSS" ;;
            drl)   echo "      de:    $URL_DRL" ;;
            *)     echo "      de:    (origen '$origen' no reconocido)" ;;
        esac
        echo "      a:     $(dirname "$ruta")/"
        [ "$sha1" = "-" ] || echo "      sha1:  $sha1"
        echo ""
    done < <(filas)

    if [ "$n" -eq 0 ]; then
        echo "  (nada: el inventario está completo)"
        return 0
    fi
    echo "Total: $n archivo(s)."
    return 0
}

# ------------------------------------------------------------------ novedades
novedades() {
    local html slugs_upstream rol slug version archivo origen receta destino comprobacion sha1
    local arriba nuevas=0 vistos=""

    echo "=== Versiones contra la portada de CSPP ==="
    echo "Portada: $CSPP_PORTADA"
    echo ""

    html="$TEMPORALES/portada.html"
    slugs_upstream="$TEMPORALES/slugs.tsv"

    if ! curl -sSL --max-time 60 -o "$html" "$CSPP_PORTADA"; then
        echo "ERROR: no se pudo descargar la portada." >&2
        return 1
    fi

    # Cada paquete se enlaza como <slug>_v<version>.shtml, así que la versión
    # viene en la URL. Es más estable que el texto descriptivo del enlace.
    grep -o 'href="[a-z0-9_]*_v[0-9][^"]*\.shtml"' "$html" \
        | sed -e 's/^href="//' -e 's/\.shtml"$//' \
        | sed -e 's/_v\([0-9]\)/\t\1/' \
        > "$slugs_upstream" || true

    if [ ! -s "$slugs_upstream" ]; then
        echo "ERROR: no se reconoció ningún paquete en la portada." >&2
        echo "La estructura del sitio cambió; hay que revisar este script." >&2
        return 1
    fi

    while IFS=$'\t' read -r rol slug version archivo origen receta destino comprobacion sha1; do
        # Un paquete puede tener varias filas (bundle + parche + estáticos);
        # basta con mirarlo una vez.
        case " $vistos " in *" $slug "*) continue ;; esac
        vistos="$vistos $slug"

        # La portada lista versiones viejas junto a la nueva (jpss_sdr aparece
        # como 4.1 y 4.1.1), así que gana la mayor.
        arriba="$(awk -F'\t' -v s="$slug" '$1==s {print $2}' "$slugs_upstream" | sort -V | tail -1)"

        if [ -z "$arriba" ]; then
            printf '  ? %-14s tenemos %-10s (no aparece en la portada)\n' "$slug" "$version"
            continue
        fi
        if [ "$arriba" = "$version" ]; then
            printf '  ✓ %-14s %s\n' "$slug" "$version"
        else
            printf '  ★ %-14s tenemos %-10s arriba hay %s\n' "$slug" "$version" "$arriba"
            nuevas=$((nuevas + 1))
        fi
    done < <(filas)

    echo ""
    if [ "$nuevas" -eq 0 ]; then
        echo "Todo al día."
    else
        echo "$nuevas paquete(s) con versión distinta arriba."
        echo "Actualizar implica: bajar el tarball nuevo, subir la versión en el"
        echo "manifiesto y en el .def de su receta, y recompilar la imagen."
    fi
    return 0
}

# ------------------------------------------------------------------ registrar
registrar() {
    local rol slug version archivo origen receta destino comprobacion sha1
    local ruta nuevo primero n=0 sin=0

    nuevo="$TEMPORALES/tarballs.tsv"

    echo "=== Registrando sha1 y comprobaciones ==="
    echo ""

    while IFS= read -r linea; do
        case "$linea" in
            '#'*|'') printf '%s\n' "$linea" >> "$nuevo"; continue ;;
        esac

        IFS=$'\t' read -r rol slug version archivo origen receta destino comprobacion sha1 <<< "$linea"
        ruta="$(ruta_de "$rol" "$archivo")"

        if [ -f "$ruta" ]; then
            sha1="$(sha1_de "$ruta")"
            # Para los estáticos se guarda un ARCHIVO de dentro del tarball, no su
            # directorio raíz: los siete estáticos de SDR se extraen todos sobre
            # SDR_4_1/, así que una comprobación por directorio daría por
            # desplegados los siete en cuanto se extrajera uno. Se deduce mientras
            # el tarball todavía está, que es la única oportunidad.
            if [ "$rol" = "estatico" ] && [ "$comprobacion" = "-" ] && [ "$destino" != "-" ]; then
                primero="$(tar tzf "$ruta" 2>/dev/null | grep -v '/$' | head -1 || true)"
                [ -z "$primero" ] || comprobacion="$destino/$primero"
            fi
            echo "  ✓ $archivo"
            echo "      sha1: $sha1"
            [ "$comprobacion" = "-" ] || echo "      destino: $comprobacion"
            n=$((n + 1))
        else
            echo "  · $archivo — no está; se deja como estaba"
            sin=$((sin + 1))
        fi

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$rol" "$slug" "$version" "$archivo" "$origen" \
            "$receta" "$destino" "$comprobacion" "$sha1" >> "$nuevo"
    done < "$MANIFIESTO"

    cp "$nuevo" "$MANIFIESTO"

    echo ""
    echo "Registrados: $n"
    [ "$sin" -eq 0 ] || echo "Sin registrar (ausentes): $sin"
    echo ""
    echo "Revisa el diff y commitéalo: el manifiesto es lo único que se versiona."
    return 0
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================

MODO="verificar"

while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verificar) MODO="verificar" ;;
        -d|--descargar) MODO="descargar" ;;
        -n|--novedades) MODO="novedades" ;;
        -r|--registrar) MODO="registrar" ;;
        -h|--help)      uso; exit 0 ;;
        *)
            echo "ERROR: Argumento no reconocido: $1" >&2
            uso >&2
            exit 1
            ;;
    esac
    shift
done

if [ ! -f "$MANIFIESTO" ]; then
    echo "ERROR: No se encontró el manifiesto: $MANIFIESTO" >&2
    exit 1
fi

case "$MODO" in
    verificar) verificar ;;
    descargar) descargar ;;
    novedades) novedades ;;
    registrar) registrar ;;
esac
