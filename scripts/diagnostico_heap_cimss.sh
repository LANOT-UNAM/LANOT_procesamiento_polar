#!/bin/bash
# ==============================================================================
# LANOT - UNAM | Diagnóstico de CSPP HEAP v3.0 para CIMSS
# ==============================================================================
#
# PUNTUAL, NO ES PARTE DE LA CADENA. Existe para responder a lo que pidió Kathy
# Strabala el 2026-08-25 en el foro de SSEC, en el hilo de que HEAP v3.0 no
# produce sondeos: <https://forums.ssec.wisc.edu/viewtopic.php?t=60121>
#
#   1. Correr FUERA del contenedor, para descartarlo como causa.
#   2. Repetir el caso de prueba con --noclean y subir el directorio de trabajo
#      a ftp://ftp.ssec.wisc.edu/pub/incoming
#
# Cuando el hilo se cierre, este script se borra.
#
# Hace las dos corridas —host y contenedor— con el MISMO comando de §3.3 del
# manual, cada una en su directorio, y compara las familias que salen. Dos
# corridas y no una porque "falla fuera del contenedor" solo significa algo si
# se sabe qué hace dentro con esa misma entrada y ese mismo día.
#
# ATENCIÓN A LA ASIMETRÍA, y hay que decírsela a CIMSS si el resultado no es
# limpio: el .sif de HEAP parte de Rocky 8 A PROPÓSITO, porque §1.3 declara
# Rocky 8.10 como sistema destino. Salvo que el host resulte ser también Rocky 8
# —lo dice la primera sección de la salida, no lo des por sabido—, la corrida
# del host no es "lo mismo sin contenedor": es sin contenedor Y en otro sistema
# operativo. Los dos desenlaces no pesan igual —
#
#   · falla también fuera  → concluyente, el contenedor queda descartado
#   · funciona fuera       → NO se puede atribuir al contenedor sin separar
#                            antes la variable del sistema operativo
#
# NO SUBE NADA. Deja el .tar.gz preparado e imprime el comando de subida, que
# lo ejecuta una persona: mandar archivos a un FTP público es irreversible.
#
# Uso:
#   ./diagnostico_heap_cimss.sh --verificar   # solo audita el ambiente
#   ./diagnostico_heap_cimss.sh               # las dos corridas y el paquete
#   ./diagnostico_heap_cimss.sh --host        # solo fuera del contenedor
#   ./diagnostico_heap_cimss.sh --contenedor  # solo dentro
#
# Variables de entorno:
#   HEAP_TARBALL    Bundle de HEAP    (def. /opt/contenedores/CSPP_HEAP_V3.0.tar.gz)
#   HEAP_TESTDATA   Datos de prueba   (def. /opt/contenedores/nucaps_test_data)
#   HEAP_HOST_HOME  Bundle en el host (def. /data/tmp/heap_host/CSPP_HEAP_3_0)
#   HEAP_SIF        Imagen            (def. /opt/containers/cspp_heap_v3.0.sif)
#   HEAP_DIAG_BASE  Raíz de trabajo   (def. /data/tmp/heap_diag_<fecha>)
#   HEAP_ANC_SEMILLA  Caché GFS ya poblado que se copia al anc de cada corrida,
#                     para no volver a bajar lo mismo dos veces (def. vacío)
#
# ==============================================================================

set -euo pipefail

TARBALL="${HEAP_TARBALL:-/opt/contenedores/CSPP_HEAP_V3.0.tar.gz}"
TESTDATA="${HEAP_TESTDATA:-/opt/contenedores/nucaps_test_data}"
HOST_HOME="${HEAP_HOST_HOME:-/data/tmp/heap_host/CSPP_HEAP_3_0}"
SIF="${HEAP_SIF:-/opt/containers/cspp_heap_v3.0.sif}"
BASE="${HEAP_DIAG_BASE:-/data/tmp/heap_diag_$(date +%Y%m%d_%H%M%S)}"
SEMILLA="${HEAP_ANC_SEMILLA:-}"

MODO="ambos"
case "${1:-}" in
    --verificar)  MODO="verificar" ;;
    --host)       MODO="host" ;;
    --contenedor) MODO="contenedor" ;;
    -h|--help)    sed -n '2,52p' "${BASH_SOURCE[0]}"; exit 0 ;;
    "")           ;;
    *)            echo "Opción no reconocida: $1 (--help)" >&2; exit 1 ;;
esac

# --- Ambiente -----------------------------------------------------------------

echo "=============================================================================="
echo "  Diagnóstico CSPP HEAP v3.0 para CIMSS | $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================================================="

FALTA=0
aviso() { echo "  ⚠ $*"; }
falla() { echo "  ✗ $*"; FALTA=1; }
bien()  { echo "  ✓ $*"; }

echo "Sistema del host:"
if [ -r /etc/os-release ]; then
    . /etc/os-release
    echo "  $PRETTY_NAME"
    case "$VERSION_ID" in
        8*) bien "coincide con el sistema destino del manual (§1.3, Rocky 8.10)" ;;
        *)  aviso "el manual (§1.3) declara Rocky 8.10; la corrida del host lleva"
            aviso "  además esa diferencia encima. Ver la nota de la cabecera." ;;
    esac
fi

echo "Requisitos de §1.3 en el host:"
for p in perl lftp; do
    if command -v "$p" > /dev/null; then bien "$p — $(command -v "$p")"
    else falla "$p NO está en el host; el manual lo exige (dnf install $p)"; fi
done

echo "Insumos:"
[ -d "$TESTDATA/input" ] && bien "datos de prueba: $TESTDATA/input" \
                         || falla "no están los datos de prueba: $TESTDATA/input"
[ -f "$SIF" ] && bien "imagen: $SIF" || falla "no está la imagen: $SIF"

if [ -d "$HOST_HOME" ]; then
    bien "bundle en el host: $HOST_HOME"
elif [ -f "$TARBALL" ]; then
    aviso "el bundle no está extraído en el host; se extraerá de $TARBALL"
else
    falla "ni $HOST_HOME ni $TARBALL: no hay cómo correr fuera del contenedor"
fi

if [ -n "$SEMILLA" ]; then
    [ -d "$SEMILLA" ] && bien "semilla de ancillary: $SEMILLA" \
                      || falla "no existe HEAP_ANC_SEMILLA: $SEMILLA"
fi

if [ "$FALTA" -ne 0 ]; then
    echo
    echo "Falta algo de lo de arriba. No se corre nada."
    exit 1
fi
if [ "$MODO" = "verificar" ]; then
    echo
    echo "Ambiente completo."
    exit 0
fi

# --- Preparación --------------------------------------------------------------

mkdir -p "$BASE"

if [ ! -d "$HOST_HOME" ]; then
    echo
    echo ">>> Extrayendo el bundle en el host..."
    mkdir -p "$(dirname "$HOST_HOME")"
    tar -xzf "$TARBALL" -C "$(dirname "$HOST_HOME")"
    [ -d "$HOST_HOME" ] || { echo "ERROR: la extracción no dejó $HOST_HOME" >&2; exit 1; }
fi

# ¿Puede siquiera arrancar el binario en este host? HEAP se distribuye SOLO
# como binarios, enlazados contra el HDF5 de Rocky 8 (libhdf5.so.103,
# libhdf5_hl.so.100). En un host más nuevo el soname no existe y no es que el
# software falle: es que no carga. Comprobarlo ANTES de correr evita presentar
# a CIMSS un fallo de sistema como si fuera un resultado sobre los sondeos.
# Medido en tahan el 2026-08-29, Rocky Linux 10.2.
HOST_CONCLUYENTE=1
echo
echo ">>> Comprobando que los binarios carguen en este host..."
FALTANTES=$(ldd "$HOST_HOME"/bin/* 2>/dev/null | grep -i "not found" | sort -u || true)
if [ -n "$FALTANTES" ]; then
    HOST_CONCLUYENTE=0
    echo "  ✗ faltan librerías en el host:"
    echo "$FALTANTES" | sed 's/^/    /'
    echo
    echo "  La corrida del host NO va a ser concluyente: el binario no carga, así que"
    echo "  lo que salga de ella no dice nada sobre por qué faltan los sondeos. Se"
    echo "  ejecuta igual para dejar constancia del intento, y el paquete lo advierte."
    {
        echo "La corrida 'host' de este paquete NO es concluyente."
        echo
        echo "Host: $( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-desconocido}" )"
        echo "El manual de CSPP HEAP v3.0 (§1.3) declara Rocky 8.10 como sistema destino."
        echo "Los binarios del bundle no cargan en este host; faltan:"
        echo "$FALTANTES"
        echo
        echo "Por eso corremos HEAP en un contenedor Apptainer basado en Rocky 8: no es"
        echo "una capa añadida sobre el sistema soportado, es la forma de tenerlo."
    } > "$BASE/host_NO_CONCLUYENTE.txt"
else
    bien "los binarios cargan; la corrida del host será comparable"
fi

# --noclean es lo que pide CIMSS: sin esa bandera el directorio se poda al
# terminar y el envío no sirve de nada. Si el driver no la reconoce, hay que
# saberlo ANTES de correr media hora.
echo
echo ">>> Comprobando que el driver acepte --noclean..."
AYUDA=$(cd "$HOST_HOME" && . ./scripts/cspp_heap_env.sh > /dev/null 2>&1;
        "$HOST_HOME/scripts/run_heap.bash" --help 2>&1 || true)
if echo "$AYUDA" | grep -q -- '--noclean'; then
    bien "--noclean está en el --help"
    NOCLEAN="--noclean"
else
    aviso "el --help no menciona --noclean; se pasa igual, porque es lo que pidió"
    aviso "  CIMSS, pero revisa que el directorio de trabajo sobreviva."
    NOCLEAN="--noclean"
fi

# --- Las corridas -------------------------------------------------------------

# El comando de §3.3, palabra por palabra salvo la ruta de entrada (absoluta,
# para no escribir dentro de $TESTDATA) y el --noclean que pidió CIMSS.
correr() {
    local etiqueta="$1" work="$BASE/$etiqueta" registro
    registro="$BASE/${etiqueta}.log"

    mkdir -p "$work/anc"
    if [ -n "$SEMILLA" ]; then
        cp -a "$SEMILLA"/. "$work/anc/" 2>/dev/null || true
    fi

    echo
    echo ">>> Corrida '$etiqueta' → $work"
    local inicio fin
    inicio=$(date +%s)

    if [ "$etiqueta" = "host" ]; then
        ( cd "$work" \
          && export CSPP_HEAP_HOME="$HOST_HOME" \
          && . "$HOST_HOME/scripts/cspp_heap_env.sh" \
          && "$HOST_HOME/scripts/run_heap.bash" \
                -s n21 -i "$TESTDATA/input" -o RO -p 4 -d "$work/anc" $NOCLEAN \
        ) > "$registro" 2>&1 || echo "  (terminó con código $?)"
    else
        apptainer exec \
            --bind "$TESTDATA:$TESTDATA" \
            --bind "$work:$work" \
            --pwd "$work" \
            "$SIF" \
            /bin/bash -c ". \$CSPP_HEAP_HOME/scripts/cspp_heap_env.sh && \
                run_heap.bash -s n21 -i \"$TESTDATA/input\" -o RO -p 4 \
                              -d \"$work/anc\" $NOCLEAN" \
            > "$registro" 2>&1 || echo "  (terminó con código $?)"
    fi

    fin=$(date +%s)
    echo "  duración: $(( fin - inicio ))s · registro: $registro"
    if [ "$etiqueta" = "host" ] && [ "$HOST_CONCLUYENTE" -eq 0 ]; then
        echo "  ⚠ NO CONCLUYENTE: los binarios no cargan en este host (ver"
        echo "    $BASE/host_NO_CONCLUYENTE.txt). No compares este conteo con el otro."

    fi

    # El conteo por familia es el veredicto: §3.3 espera 48 archivos, 16 de
    # cada una de NUCAPS-EDR, NUCAPS-CCR-AR y NUCAPS-OLR.
    echo "  NetCDF por familia:"
    if compgen -G "$work/*.nc" > /dev/null; then
        find "$work" -maxdepth 1 -name '*.nc' -printf '%f\n' \
            | sed 's/_v3r.*//' | sort | uniq -c | sed 's/^/    /'
        echo "    total: $(find "$work" -maxdepth 1 -name '*.nc' | wc -l)"
    else
        echo "    ninguno en la raíz del directorio de trabajo"
    fi
    # 'retriev' es la palabra que el log NO menciona cuando la recuperación se
    # salta; es el indicio que se dejó pasar en agosto.
    echo "  menciones de 'retriev' en el log: $(grep -ic retriev "$registro" || true)"
}

case "$MODO" in
    host)       correr host ;;
    contenedor) correr contenedor ;;
    ambos)      correr host; correr contenedor ;;
esac

# --- El paquete para el FTP ---------------------------------------------------

PAQUETE="$BASE/lanot_heap_v3.0_$(date +%Y%m%d).tar.gz"
echo
echo ">>> Empaquetando para CIMSS..."
tar -czf "$PAQUETE" -C "$(dirname "$BASE")" "$(basename "$BASE")" \
    --exclude='*.tar.gz' --exclude='anc'
echo "  $PAQUETE  ($(du -h "$PAQUETE" | cut -f1))"
echo
echo "  El caché de ancillary queda FUERA del paquete a propósito: son GRIB2 que"
echo "  CIMSS ya tiene y que solo abultan. Si los piden, se manda aparte."
echo
echo "=============================================================================="
echo "  Para subirlo —hazlo tú, esto no manda nada solo—:"
echo
echo "    lftp -e 'cd incoming; put $PAQUETE; bye' -u anonymous, ftp.ssec.wisc.edu"
echo
echo "  Y avisar en el hilo t=60121 con el nombre del archivo, porque el"
echo "  directorio es anónimo y no se puede listar."
echo "=============================================================================="
