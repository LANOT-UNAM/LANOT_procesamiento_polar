#!/bin/bash
# ==============================================================================
# instalar.sh — copia el código de operación a su ruta de sistema.
#
# Hasta ahora la cadena se ejecutaba desde el clon de git, y eso mezcla el árbol
# de trabajo con el de producción: un `git pull` a media pasada cambia el script
# que se está ejecutando, y cualquier edición exploratoria en el servidor queda
# en la ruta que usa cron. Con esto, desplegar es un acto explícito.
#
# El destino sigue el namespace que ya existe en el host: /var/log/lanot/polares
# para los logs, /usr/local/share/lanot para las paletas, /opt/lanot-tools para
# LANOT_tools. Deja sitio para /opt/lanot/goes y /opt/lanot/metop.
#
#   /opt/lanot/polares/scripts/   los run_*.sh, procesar_pasada.sh, recibe.sh
#   /opt/lanot/polares/config/    grid.yaml y los XML de RT-STPS
#   /opt/lanot/polares/VERSION    de qué commit salió esto
#
# La estructura {scripts,config} no es decorativa: run_polar2grid_l1.sh y
# run_polar2grid_edr.sh resuelven la rejilla como $SCRIPT_DIR/../config/grid.yaml
# y abortan si no está. Al final se comprueba que esa ruta resuelva.
#
# Uso:
#   sudo ./scripts/instalar.sh
#        ./scripts/instalar.sh --dry-run
#        PREFIX=/tmp/prueba ./scripts/instalar.sh
#
# Variables de entorno:
#   PREFIX           Dónde instalar   (def. /opt/lanot/polares)
#   DUENO            Dueño            (def. lanotadm:lanotadm)
#   LOCK_FILE        Candado de procesar_pasada.sh (def. /data/tmp/lanot_polares.lock)
#   INSTALAR_ESPERA  Segundos que se espera a la pasada en curso (def. 2700)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PREFIX="${PREFIX:-/opt/lanot/polares}"
DUENO="${DUENO:-lanotadm:lanotadm}"
LOCK_FILE="${LOCK_FILE:-/data/tmp/lanot_polares.lock}"
INSTALAR_ESPERA="${INSTALAR_ESPERA:-2700}"

# Lo que NO se instala, y por qué. Es lista de exclusión y no de inclusión para
# que un run_*.sh nuevo entre solo, sin tener que acordarse de este archivo.
#
#   instalar.sh           es esto mismo: herramienta de despliegue, vive en el clon.
#   preparar_servidor.sh  bootstrap; necesita contenedores/tarballs.tsv, que no se
#                         instala, y se corre una vez antes que nada.
#   generar_xml.py        herramienta de desarrollo; hay que correrla desde la raíz
#                         del repositorio porque escribe rutas relativas.
EXCLUIDOS=(
    instalar.sh
    preparar_servidor.sh
    generar_xml.py
)

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  sudo $0              Instala en $PREFIX
       $0 --dry-run    Dice qué instalaría

Opciones:
  -n, --dry-run
  -h, --help

Destino: $PREFIX
Dueño:   $DUENO
EOF
}

correr() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  [dry-run] $*"
        return 0
    fi
    "$@"
}

excluido() {
    local f
    for f in "${EXCLUIDOS[@]}"; do
        [ "$1" != "$f" ] || return 0
    done
    return 1
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================

DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)    uso; exit 0 ;;
        *)
            echo "ERROR: Argumento no reconocido: $1" >&2
            uso >&2
            exit 1
            ;;
    esac
    shift
done

# Root solo si de verdad se va a escribir en una ruta del sistema. Lo que se
# comprueba es el ancestro que ya exista: con PREFIX=/tmp/algo/nuevo/polares no
# existe ni el padre, y lo que decide es si se puede crear la cadena entera.
ancestro_existente() {
    local d="$1"
    while [ ! -d "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
        d="$(dirname "$d")"
    done
    echo "$d"
}

if [ "$DRY_RUN" -eq 0 ] && [ "$EUID" -ne 0 ]; then
    base="$(ancestro_existente "$PREFIX")"
    if [ ! -w "$base" ]; then
        echo "ERROR: no se puede escribir en $base. Usa sudo, o PREFIX." >&2
        exit 1
    fi
fi

# ==============================================================================
# ESPERAR A LA PASADA EN CURSO
# ==============================================================================
# procesar_pasada.sh invoca cada run_*.sh de nuevo en cada etapa, así que
# instalar a media pasada no corrompe el script que se está ejecutando —install
# escribe un archivo nuevo, y el que corre conserva el suyo— pero sí deja una
# pasada hecha la mitad con una versión y la mitad con otra. Se toma el mismo
# candado que ella y se retiene hasta el final: mientras se copia, tampoco
# arranca ninguna. Una pasada tarda ~30 min; el plazo por omisión, 45.
#
# Sin el directorio del candado (una máquina de desarrollo, un PREFIX de
# prueba) no hay pasada que esperar.

if [ "$DRY_RUN" -eq 0 ] && [ -d "$(dirname "$LOCK_FILE")" ]; then
    exec 9>>"$LOCK_FILE"
    if ! flock -n 9; then
        echo "Hay una pasada en curso (candado: $LOCK_FILE)."
        echo "Se espera a que termine, hasta $((INSTALAR_ESPERA / 60)) min..."
        if ! flock -w "$INSTALAR_ESPERA" 9; then
            echo "ERROR: la pasada no terminó en $((INSTALAR_ESPERA / 60)) min; no se instaló nada." >&2
            echo "       Reintenta más tarde, o sube INSTALAR_ESPERA." >&2
            exit 1
        fi
        echo "La pasada terminó; se instala."
        echo ""
    fi
fi

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

echo "=============================================================="
echo "  Instalando la cadena polar en $PREFIX"
echo "=============================================================="
echo ""

correr install -d -m 755 "$PREFIX"
correr install -d -m 755 "$PREFIX/scripts"
correr install -d -m 755 "$PREFIX/config"

echo "Scripts:"
n_sh=0
# También los .py, y no solo los .sh: publicar_vistas.sh monta su directorio
# dentro del contenedor esperando encontrar ahí a publicar_vistas.py, así que si
# el compañero no se instala, la herramienta no funciona en producción. Antes el
# glob dejaba fuera a generar_xml.py por accidente; ahora hay que excluirlo a
# propósito, que es lo que dice la lista de arriba.
for f in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/*.py; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    if excluido "$base"; then
        echo "  ○ $base — no se instala (vive en el clon)"
        continue
    fi
    correr install -m 755 "$f" "$PREFIX/scripts/$base"
    echo "  ✓ $base"
    n_sh=$((n_sh + 1))
done

echo ""
echo "Configuración:"
n_cfg=0
for f in "$REPO_DIR"/config/*; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    correr install -m 644 "$f" "$PREFIX/config/$base"
    echo "  ✓ $base"
    n_cfg=$((n_cfg + 1))
done

# ------------------------------------------------------------------- VERSION
echo ""
echo "VERSION:"
commit="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo desconocido)"
rama="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo desconocida)"
sucio="$(git -C "$REPO_DIR" status --porcelain 2>/dev/null || true)"

version_txt="$(
    echo "commit:    $commit"
    echo "rama:      $rama"
    echo "instalado: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo "desde:     $REPO_DIR"
    echo "por:       ${SUDO_USER:-$(id -un)}"
    if [ -n "$sucio" ]; then
        echo ""
        echo "ATENCIÓN: el árbol de trabajo tenía cambios sin commitear."
        echo "Esto NO corresponde exactamente al commit de arriba:"
        printf '%s\n' "$sucio" | sed 's/^/  /'
    fi
)"

if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s\n' "$version_txt" | sed 's/^/  [dry-run] /'
else
    printf '%s\n' "$version_txt" > "$PREFIX/VERSION"
    chmod 644 "$PREFIX/VERSION"
    printf '%s\n' "$version_txt" | sed 's/^/  /'
fi

if [ -n "$sucio" ]; then
    echo ""
    echo "  ⚠ Se instaló un árbol con cambios sin commitear. Queda anotado en VERSION."
fi

# Dueño al final, cuando ya está todo.
correr chown -R "$DUENO" "$PREFIX" 2>/dev/null || true

# ------------------------------------------------------------ comprobaciones
echo ""
echo "Comprobaciones:"

fallos=0

# La que de verdad importa: los dos renderizadores abren la rejilla por ruta
# relativa a su propia ubicación, así que el layout {scripts,config} tiene que
# resolver desde el destino, no solo desde el clon.
grid_desde_scripts="$PREFIX/scripts/../config/grid.yaml"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] se comprobaría $grid_desde_scripts"
elif [ -f "$grid_desde_scripts" ]; then
    echo "  ✓ la rejilla resuelve desde scripts/: config/grid.yaml"
else
    echo "  ✗ no resuelve $grid_desde_scripts"
    echo "    run_polar2grid_l1.sh y run_polar2grid_edr.sh abortarían."
    fallos=$((fallos + 1))
fi

# Igual de indispensable: sin la tabla de cadenas, recibe.sh, run_rt_stps.sh y
# el barrido no reconocen ningún crudo (scripts/cadenas.sh la busca ahí).
cadenas_desde_scripts="$PREFIX/scripts/../config/cadenas.tsv"
if [ "$DRY_RUN" -eq 1 ]; then
    echo "  [dry-run] se comprobaría $cadenas_desde_scripts"
elif [ -f "$cadenas_desde_scripts" ]; then
    echo "  ✓ la tabla de cadenas resuelve desde scripts/: config/cadenas.tsv"
else
    echo "  ✗ no resuelve $cadenas_desde_scripts"
    echo "    recibe.sh, run_rt_stps.sh y barrer_pendientes.sh no reconocerían ningún crudo."
    fallos=$((fallos + 1))
fi

echo ""
echo "=============================================================="
if [ "$fallos" -eq 0 ]; then
    echo "  Listo: $n_sh scripts y $n_cfg archivos de configuración."
    echo ""
    echo "  En operación la cadena se invoca desde $PREFIX/scripts/, como lanotadm:"
    echo "    recepción:  ssh lanotadm@<servidor> $PREFIX/scripts/recibe.sh <crudo>"
    echo "    cron:       $PREFIX/scripts/update_sdr_daily.sh, update_atmos_ancillary.sh…"
    echo "  Sin enlace en ~lanotadm/bin: ahí vive el recibe.sh de la cadena vieja."
    exit 0
fi
echo "  Instalación incompleta: $fallos comprobación(es) fallaron."
exit 1
