#!/bin/bash
#SBATCH --job-name=heap_edr
#SBATCH --cpus-per-task=4
#SBATCH --output=/var/log/lanot/polares/cspp-edr/slurm_heap_%j.log
# ==============================================================================
# LANOT - UNAM | CSPP HEAP v3.0 (Level 1 → Level 2, sondeos NUCAPS)
# ==============================================================================
#
# SDR de CrIS y ATMS → perfiles atmosféricos de temperatura, humedad, ozono y
# gases traza en 100 niveles de presión, más parámetros de estabilidad (CAPE,
# CIN, índice de levantamiento), radiancias limpiadas de nube (CCR) y radiación
# de onda larga saliente (OLR).
#
# Salen DOS archivos por gránulo, no los tres que sugiere §1.7 del manual:
#
#   NUCAPS-ALL-HR_v3r2_*.nc   un archivo INTERMEDIO, que consumen otros módulos
#                             de NUCAPS. No es ninguno de los tres productos
#   NUCAPS-OLR_v3r2_*.nc      la radiación de onda larga saliente
#
# O sea que de los TRES productos finales (§1.7: NUCAPS-EDR, NUCAPS-CCR-AR y
# NUCAPS-OLR) solo sale uno. `NUCAPS-ALL-HR` no aparece en el manual porque no
# es un producto: lo confirmó CIMSS en el foro de SSEC el 2026-08-25
# (viewtopic.php?t=60121), y de paso corrigió lo que aquí se dio por hecho hasta
# entonces — las radiancias limpiadas de nube van en `NUCAPS-CCR-AR`, no en
# `ALL-HR`, así que el CCR **tampoco se produce** y su ausencia es síntoma del
# mismo fallo que la del EDR. Por eso el conteo
# de familias sale de los archivos y no de una lista fija: si una versión futura
# vuelve a separarlos, el marcador lo refleja sin tocar el script. El contenido
# está descrito en el NUCAPS External Users Manual, que §1.7 enlaza.
#
# Sin argumentos toma la PASADA más reciente que haya en el directorio de SDR de
# CrIS y, si ya fue procesada con éxito, avisa y no hace nada. Una pasada se
# identifica por satélite, fecha y órbita (p. ej. j01_d20260811_b45236).
#
# Las cuatro entradas van al MISMO directorio (manual §1.6, Tabla 1):
#   CrIS  SCRIF*.h5 + GCRSO*.h5
#   ATMS  TATMS*.h5 + GATMO*.h5
# Los dos instrumentos son obligatorios: el modo HR_IRMW combina infrarrojo y
# microondas, y sin ATMS no hay recuperación que hacer.
#
# DOS TRAMPAS que esta versión trae y conviene no redescubrir:
#
#   1. La 3.0 RETIRÓ el soporte a S-NPP (§1.2): solo n21, j01, m03 y m01. Una
#      pasada de NPP sale con un aviso y código 0 —no es un fallo, es que no hay
#      trabajo posible—, para que procesar_pasada.sh no la cuente como error.
#
#   2. El nombre del satélite NO es el de los SDR: HEAP pide 'n21' donde CSPP
#      SDR escribe 'j02'. NOAA-20 sí coincide en los dos lados.
#
# La órbita NO se cruza entre instrumentos: el mismo sobrevuelo lleva un b#####
# distinto según el sensor (verificado con VIIRS ÷ OMPS el 2026-08-13, y con
# CrIS ÷ VIIRS el 2026-08-15: b45265 contra b45264). Por eso la pasada la fija
# CrIS y los SDR de ATMS se emparejan por TIEMPO, enlazando los que se traslapan
# con la ventana de la pasada MÁS UN MARGEN — sin ese margen se pierde el primer
# gránulo de cada pasada. Ver enlazar_atms().
#
# El ancillary dinámico (GFS 0.5° en GRIB2) lo baja el propio driver a
# /data/ancillary/heap, que se monta en /anc. Ese caché NO se purga solo
# (§1.6.3): de eso se encarga update_heap_ancillary.sh, en cron.
#
# Uso:
#   ./run_heap_edr.sh                     # la pasada más reciente pendiente
#   ./run_heap_edr.sh --force             # reprocesa aunque ya tenga marcador
#   ./run_heap_edr.sh -p j01_d20260811    # una pasada concreta
#
# Variables de entorno (para pruebas o rutas alternas):
#   HEAP_CRIS_IN     Entrada CrIS     (def. /data/output/jpss/level1/cris)
#   HEAP_ATMS_IN     Entrada ATMS     (def. /data/output/jpss/level1/atms)
#   HEAP_OUT         Salida .nc       (def. /data/output/jpss/level2/sounder)
#   HEAP_STATE_DIR   Marcadores .done (def. /data/output/jpss/state/cspp-heap)
#   HEAP_CONTAINER   Imagen .sif      (def. /opt/containers/cspp_heap_v3.0.sif)
#   HEAP_HOME_HOST   Bundle en el host(def. /data/opt/CSPP_HEAP_3_0)
#   HEAP_CACHE       Caché dinámico   (def. /data/ancillary/heap)
#   HEAP_WORK_BASE   Raíz de trabajo  (def. /data/tmp)
#   HEAP_LOG_BASE    Raíz de logs     (def. /var/log/lanot/polares)
#   HEAP_MARGEN_ATMS Margen al enlazar ATMS (def. 90 s). Con 0 se pierde el
#                    primer gránulo de cada pasada: ver enlazar_atms().
#   HEAP_SALIDA      Cadena de -o (def. RO: OLR + recuperación). Letra por letra.
#   HEAP_OPTS        Banderas extra para run_heap.bash
#
# ==============================================================================

set -euo pipefail

SIF_HEAP="${HEAP_CONTAINER:-/opt/containers/cspp_heap_v3.0.sif}"

# El bundle de HEAP vive en el HOST, no en la imagen, y esto no es una manía de
# despliegue: su árbol de instalación tiene que ser ESCRIBIBLE. airsb103.exe —el
# Fortran de la recuperación— abre una unidad sin nombre dentro de él, y con el
# bundle en el .sif muere con "Cannot open file 'fort.40': Read-only file
# system". Eso tumba HEAP_Retrieval.pl y con él los conversores a NetCDF: no
# salen NUCAPS-EDR ni NUCAPS-CCR-AR, solo el OLR, y el wrapper devuelve 0 sin
# una queja. Costó dos semanas y un reporte equivocado a CIMSS (2026-08-29).
# Se despliega con preparar_servidor.sh --solo 7.
HOST_HEAP_HOME="${HEAP_HOME_HOST:-/data/opt/CSPP_HEAP_3_0}"

HOST_CRIS_IN="${HEAP_CRIS_IN:-/data/output/jpss/level1/cris}"
HOST_ATMS_IN="${HEAP_ATMS_IN:-/data/output/jpss/level1/atms}"
HOST_EDR_OUT="${HEAP_OUT:-/data/output/jpss/level2/sounder}"
STATE_DIR="${HEAP_STATE_DIR:-/data/output/jpss/state/cspp-heap}"
HOST_CACHE="${HEAP_CACHE:-/data/ancillary/heap}"

WORK_BASE="${HEAP_WORK_BASE:-/data/tmp}"
LOG_DIR="${HEAP_LOG_BASE:-/var/log/lanot/polares}/cspp-edr"

CORES="${SLURM_CPUS_PER_TASK:-4}"
JOB_ID="${SLURM_JOB_ID:-$$}"

# Segundos que se ensancha, a cada lado, la ventana con la que se enlazan los
# SDR de ATMS. Ver enlazar_atms(). 0 = traslape estricto.
MARGEN_ATMS="${HEAP_MARGEN_ATMS:-90}"

# Qué familias pide el driver: O = OLR, R = recuperación, S = subsetter. La ayuda
# del binario la documenta como "cadena de la forma ORS" con [choices: O, R, S] —
# el PDF de diciembre dice OSR y describe R distinto, manda el binario. Se parsea
# letra por letra: verificado en tahan el 2026-08-17, con -o R desaparece el OLR.
# Variable y no literal porque es lo primero que se mueve al diagnosticar por qué
# no salieron perfiles.
SALIDA_HEAP="${HEAP_SALIDA:-RO}"

# ==============================================================================
# FUNCIONES
# ==============================================================================

uso() {
    cat <<EOF
Uso:
  $0             Procesa la pasada más reciente de $HOST_CRIS_IN
  $0 --force     Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force   Ignora el marcador de procesado
  -p, --pasada  Pasada concreta en vez de la más reciente: la clave completa
                (j01_d20260813_b45265) o cualquier trozo que la identifique.
                Ojo: la órbita es la de CrIS, que NO es la de VIIRS — el mismo
                sobrevuelo es b45264 en VIIRS y b45265 aquí.
  -h, --help    Muestra esta ayuda

Requiere que run_sdr.sh haya corrido para los DOS sensores:
  scripts/run_sdr.sh --sensor cris
  scripts/run_sdr.sh --sensor atms

HEAP 3.0 no procesa S-NPP (manual §1.2): solo NOAA-20 y NOAA-21.

Pasadas disponibles en $HOST_CRIS_IN:
$(claves_disponibles 2>/dev/null | sed 's/^/  /' || true)
EOF
}

# GCRSO_j01_d20260811_t1947330_e2003097_b45236_c2026...h5 -> j01_d20260811_b45236
clave_de_pasada() {
    local nombre sat fecha orbita
    nombre=$(basename "$1")
    IFS='_' read -r _ sat fecha _ _ orbita _ <<< "$nombre"
    if [[ "$fecha" != d* ]] || [[ "$orbita" != b* ]]; then
        return 1
    fi
    echo "${sat}_${fecha}_${orbita}"
}

# Las pasadas que hay en el directorio de entrada, una por línea y sin repetir.
claves_disponibles() {
    find "$HOST_CRIS_IN" -maxdepth 1 -name 'GCRSO*.h5' -printf '%f\n' 2>/dev/null |
        while IFS= read -r nombre; do
            clave_de_pasada "$nombre" || true
        done | sort -u
}

# Deja en ULTIMO_GCRSO un archivo representativo de la pasada: el más reciente
# si no se pidió ninguna, o el primer gránulo de la que se pida con --pasada. De
# ahí salen la clave y la ventana temporal con la que se emparejan los SDR de
# ATMS, que llevan otra órbita.
resolver_pasada() {
    local coinciden sat fecha orbita

    if [ -z "$PASADA" ]; then
        ULTIMO_GCRSO=$(find "$HOST_CRIS_IN" -maxdepth 1 -name 'GCRSO*.h5' \
                            -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        return 0
    fi

    # --pasada acepta la clave completa o cualquier trozo que la identifique:
    # "j01_d20260813_b45264", "d20260813" o hasta "45264". Se resuelve contra las
    # pasadas que de verdad estén en el directorio, así que un valor ambiguo o
    # inexistente se caza aquí y no a media corrida.
    mapfile -t coinciden < <(claves_disponibles | grep -F -- "$PASADA" || true)

    if [ "${#coinciden[@]}" -eq 0 ]; then
        echo "ERROR: Ninguna pasada de $HOST_CRIS_IN coincide con '$PASADA'" >&2
        echo "       Disponibles:" >&2
        claves_disponibles | sed 's/^/         /' >&2
        return 1
    fi

    if [ "${#coinciden[@]}" -gt 1 ]; then
        echo "ERROR: '$PASADA' coincide con más de una pasada; hay que ser más específico:" >&2
        printf '         %s\n' "${coinciden[@]}" >&2
        return 1
    fi

    IFS='_' read -r sat fecha orbita <<< "${coinciden[0]}"
    ULTIMO_GCRSO=$(find "$HOST_CRIS_IN" -maxdepth 1 -name "GCRSO_${sat}_${fecha}_*_${orbita}_*.h5" \
                        | sort | head -1)
}

# Del nombre de un SDR saca su intervalo como "AAAAMMDDHHMMSS AAAAMMDDHHMMSS".
# Código 1 si el nombre no tiene la forma esperada.
#   GCRSO_j01_d20260811_t1947330_e2003097_b45236_... -> 20260811194733 20260812200309
#
# Los campos t/e traen décimas de segundo (7 dígitos), que se descartan. Si la
# hora final es menor que la inicial, el archivo cruzó la medianoche.
#
# Las comparaciones numéricas van con [ ] y no con [[ ]] a propósito: los sellos
# de antes de las 10:00 UTC empiezan con cero (t0947330) y [[ ]] los interpreta
# como octal, con lo que aborta con "value too great for base". [ ] los lee en
# base 10 siempre.
intervalo_de() {
    local nombre fecha tini tfin fecha_fin
    nombre=$(basename "$1")
    IFS='_' read -r _ _ fecha tini tfin _ <<< "$nombre"

    if [[ "$fecha" != d* ]] || [[ "$tini" != t* ]] || [[ "$tfin" != e* ]]; then
        return 1
    fi

    fecha="${fecha#d}"; tini="${tini#t}"; tfin="${tfin#e}"

    if [ "$tfin" -lt "$tini" ]; then
        fecha_fin=$(date -u -d "${fecha} +1 day" +%Y%m%d)
    else
        fecha_fin="$fecha"
    fi

    echo "${fecha}${tini:0:6} ${fecha_fin}${tfin:0:6}"
}

# Suma (o resta) segundos a un sello de 14 dígitos, respetando el cambio de día.
#   desplazar_sello 20260813191402 -90  ->  20260813191232
#
# Vía época y no con "... -90 seconds" en la cadena de fecha: ahí GNU date lee
# el -90 como HUSO HORARIO y falla con "invalid date". El síntoma es traicionero
# porque la función devuelve cadena vacía en vez de abortar, y aguas abajo la
# comparación numérica no casa nada: en la prueba local el enlazado de ATMS caía
# a 0 archivos.
desplazar_sello() {
    local s="$1" base
    base=$(date -u -d "${s:0:4}-${s:4:2}-${s:6:2} ${s:8:2}:${s:10:2}:${s:12:2} UTC" +%s) || return 1
    date -u -d "@$(( base + ($2) ))" +%Y%m%d%H%M%S
}

# La ventana de la pasada, en VENTANA_INI y VENTANA_FIN: el inicio más temprano
# y el fin más tardío de TODOS los GCRSO de la órbita.
#
# No se puede sacar de un archivo representativo, que es como estaba y costó la
# primera corrida en tahan (2026-08-15). El motivo es que en level1/cris
# conviven las dos convenciones, según cómo haya salido cada corrida de
# run_sdr.sh:
#
#   d20260811  GCRSO t1951389_e1954487   un solo archivo de 3 min   (agregado)
#   d20260813  GCRSO t1914029_e1914327   15 archivos de 30 s        (por gránulo)
#
# Con la pasada por gránulos, la ventana de uno solo salía de 30 segundos y el
# traslape enganchaba 4 archivos de ATMS en vez de la pasada entera: HEAP recibía
# 15 gránulos de CrIS y microondas para medio minuto, y terminaba en 0 sin un
# solo producto. Recorriendo todos, la ventana es correcta en los dos casos.
ventana_de_pasada() {
    local f ini fin
    VENTANA_INI=""
    VENTANA_FIN=""

    shopt -s nullglob
    for f in "$HOST_CRIS_IN"/GCRSO_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5; do
        ini=""; fin=""
        read -r ini fin < <(intervalo_de "$f") || true
        [ -n "$ini" ] && [ -n "$fin" ] || continue

        if [ -z "$VENTANA_INI" ] || [ "$ini" -lt "$VENTANA_INI" ]; then
            VENTANA_INI="$ini"
        fi
        if [ -z "$VENTANA_FIN" ] || [ "$fin" -gt "$VENTANA_FIN" ]; then
            VENTANA_FIN="$fin"
        fi
    done
    shopt -u nullglob

    [ -n "$VENTANA_FIN" ]
}

# Enlaza un archivo en el staging. Se prefiere el enlace DURO: algunas
# herramientas recorren la entrada con "find -type f", que no encuentra enlaces
# simbólicos (son -type l), y entonces reportan que no hay archivos aunque estén
# a la vista. El enlace duro es indistinguible de un archivo normal y no cuesta
# espacio. Si origen y destino están en sistemas de archivos distintos, no se
# puede, y se recurre al simbólico.
enlazar() {
    ln -f "$1" "$2" 2>/dev/null || ln -sf "$1" "$2"
}

# Enlaza en el staging los SDR de ATMS que se TRASLAPAN con la ventana de la
# pasada de CrIS. No sirve emparejar por órbita —el b##### cambia de un
# instrumento a otro— ni exigir que el sello caiga dentro de la ventana, como
# hacen run_lsr_edr.sh y run_cryo_edr.sh: allá la entrada son gránulos sueltos,
# un punto en el tiempo, mientras que aquí cada SDR cubre un intervalo cuyos
# bordes no tienen por qué coincidir con los de CrIS. En la pasada del
# 2026-08-11, por ejemplo, el GCRSO agregado cubre 3 min y el GATMO 11: con el
# criterio de pertenencia no se habría enlazado ninguno.
#
# Al traslape se le suma un MARGEN a cada lado, y NO es opcional: HEAP necesita
# microondas que ENVUELVAN al gránulo, no solo que lo toquen.
#
# Medido en tahan el 2026-08-15 sobre j01_d20260813_b45265, misma pasada y solo
# cambiando HEAP_MARGEN_ATMS:
#
#      0 s → 32 archivos de ATMS → 14 gránulos de 15   (falta el PRIMERO)
#     90 s → 42 archivos de ATMS → 15 de 15
#
# El traslape estricto es inclusivo en los extremos —un gránulo que comparta un
# segundo entra— pero al primer gránulo de CrIS solo le daba un ATMS que empieza
# ya dentro de él, y con eso la recuperación no sale. No es que el gránulo
# viniera truncado: los 15 SCRIF pesan lo mismo (~28.97 MB).
#
# 90 s son unos tres gránulos de ATMS, holgura de sobra. Enlazar de más no
# cuesta nada, porque HEAP toma lo que le sirve y son un par de enlaces.
#
# Se buscan tres fechas —la anterior, la de la pasada y la siguiente— porque un
# archivo de ATMS puede empezar del otro lado de la medianoche.
#
# Deduplicación por el campo de creación (_c<sello>): reprocesar en Level 1 deja
# dos archivos del mismo gránulo y hay que quedarse con el más nuevo.
enlazar_atms() {
    local destino="$1" enlazados=0 f nombre ini fin clave d
    local -A elegido=()
    local fechas="$FECHA_PREV $FECHA_NUM $FECHA_SIG"
    local vistas=""
    local desde hasta

    desde=$(desplazar_sello "$VENTANA_INI" "-$MARGEN_ATMS")
    hasta=$(desplazar_sello "$VENTANA_FIN" "$MARGEN_ATMS")

    # Sin esto, un fallo de desplazar_sello dejaría los límites vacíos y el
    # traslape no casaría con nada: 0 archivos de ATMS y un diagnóstico que
    # apunta al lugar equivocado.
    if [ -z "$desde" ] || [ -z "$hasta" ]; then
        echo "ERROR: No se pudo aplicar el margen de ${MARGEN_ATMS}s a la ventana" >&2
        return 1
    fi

    shopt -s nullglob
    for d in $fechas; do
        case " $vistas " in *" $d "*) continue ;; esac
        vistas="$vistas $d"

        for f in "$HOST_ATMS_IN"/TATMS_"${SAT}"_d"${d}"_*.h5 \
                 "$HOST_ATMS_IN"/GATMO_"${SAT}"_d"${d}"_*.h5; do
            nombre=$(basename "$f")
            read -r ini fin < <(intervalo_de "$nombre") || continue
            [ -n "$ini" ] || continue

            # Traslape de intervalos con la ventana ensanchada, no pertenencia
            # de un punto
            [ "$ini" -le "$hasta" ] && [ "$fin" -ge "$desde" ] || continue

            clave=$(echo "$nombre" | sed -E 's/_c[0-9]+_/_c_/')
            if [ -z "${elegido[$clave]:-}" ] || [ "$f" -nt "${elegido[$clave]}" ]; then
                elegido[$clave]="$f"
            fi
        done
    done
    shopt -u nullglob

    for f in "${elegido[@]}"; do
        enlazar "$f" "$destino"/
        enlazados=$((enlazados + 1))
    done

    echo "$enlazados"
}

formato_duracion() {
    local s="$1"
    if [ "$s" -ge 3600 ]; then
        printf '%dh %dm %ds' $((s / 3600)) $(((s % 3600) / 60)) $((s % 60))
    elif [ "$s" -ge 60 ]; then
        printf '%dm %ds' $((s / 60)) $((s % 60))
    else
        printf '%ds' "$s"
    fi
}

# ==============================================================================
# ARGUMENTOS
# ==============================================================================

FORCE=0
PASADA=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        -h|--help)  uso; exit 0 ;;
        -p|--pasada)
            if [ $# -lt 2 ]; then
                echo "ERROR: --pasada necesita un valor" >&2
                exit 1
            fi
            PASADA="$2"
            shift
            ;;
        *)
            echo "ERROR: Argumento no reconocido: $1" >&2
            uso >&2
            exit 1
            ;;
    esac
    shift
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
START_EPOCH=$(date '+%s')

# Staging y directorio de trabajo son HERMANOS, no anidados: el driver borra lo
# que encuentra bajo -w al terminar, así que un staging dentro se lo llevaría por
# delante junto con sus temporales.
HOST_WORK="${WORK_BASE}/heap_work_${JOB_ID}"
STAGING_DIR="${WORK_BASE}/heap_staging_${JOB_ID}"

# ==============================================================================
# SELECCIÓN DE LA PASADA
# ==============================================================================

if [ ! -d "$HOST_CRIS_IN" ]; then
    echo "ERROR: Directorio de SDR de CrIS no encontrado: $HOST_CRIS_IN" >&2
    echo "       Corre antes: run_sdr.sh --sensor cris" >&2
    exit 1
fi

resolver_pasada || exit 1

if [ -z "$ULTIMO_GCRSO" ]; then
    echo "No hay SDR de CrIS que procesar en $HOST_CRIS_IN (no se ven archivos GCRSO*)."
    exit 0
fi

if ! CLAVE=$(clave_de_pasada "$ULTIMO_GCRSO"); then
    echo "ERROR: No se pudo derivar la pasada del nombre: $(basename "$ULTIMO_GCRSO")" >&2
    exit 1
fi

IFS='_' read -r SAT FECHA ORBITA <<< "$CLAVE"

echo "=============================================================================="
echo "CSPP HEAP v3.0 (NUCAPS) | pasada $CLAVE"
echo "=============================================================================="

# ==============================================================================
# ¿ESTE SATÉLITE ESTÁ SOPORTADO?
# ==============================================================================
# Va antes que el marcador: si la respuesta es que no, no hay nada que consultar.
# HEAP pide su propio nombre de misión, que no es el de los SDR (§1.2).

case "$SAT" in
    j01) MISION=j01 ;;
    j02) MISION=n21 ;;
    npp)
        echo ""
        echo "ℹ  HEAP 3.0 retiró el soporte a S-NPP (manual §1.2): solo procesa"
        echo "   n21, j01, m03 y m01. La pasada $CLAVE no se puede sondear con"
        echo "   esta versión; la única vía sería conservar un HEAP 2.x aparte."
        echo ""
        echo "   No hay nada que hacer."
        exit 0
        ;;
    *)
        echo "ERROR: Satélite no reconocido en la clave $CLAVE: '$SAT'" >&2
        echo "       Se esperaba j01 (NOAA-20), j02 (NOAA-21) o npp." >&2
        exit 1
        ;;
esac

echo "  Misión HEAP: $MISION  (los SDR la nombran $SAT)"

# ==============================================================================
# ¿YA FUE PROCESADA?
# ==============================================================================

MARKER="${STATE_DIR}/${CLAVE}.done"

if [ -f "$MARKER" ] && [ "$FORCE" -eq 0 ]; then
    echo ""
    echo "ℹ  La pasada $CLAVE ya fue procesada:"
    while IFS= read -r linea; do
        echo "   $linea"
    done < "$MARKER"
    echo ""
    echo "   No hay nada que hacer. Usa --force para reprocesarla."
    exit 0
fi

if [ -f "$MARKER" ]; then
    echo "--force: se reprocesa a pesar del marcador existente"
fi

# ==============================================================================
# VALIDACIÓN DEL AMBIENTE
# ==============================================================================

if [ ! -x "$HOST_HEAP_HOME/scripts/run_heap.bash" ]; then
    echo "ERROR: No está el bundle de HEAP en el host: $HOST_HEAP_HOME" >&2
    echo "       Va montado, no dentro del .sif (ver la nota de arriba)." >&2
    echo "       Despliégalo con: sudo ./scripts/preparar_servidor.sh --solo 7" >&2
    exit 1
fi

if [ ! -f "$SIF_HEAP" ]; then
    echo "ERROR: Contenedor no encontrado: $SIF_HEAP" >&2
    exit 1
fi

if [ ! -d "$HOST_ATMS_IN" ]; then
    echo "ERROR: Directorio de SDR de ATMS no encontrado: $HOST_ATMS_IN" >&2
    echo "       HR_IRMW combina infrarrojo y microondas: sin ATMS no hay sondeo." >&2
    echo "       Corre antes: run_sdr.sh --sensor atms" >&2
    exit 1
fi

# ==============================================================================
# STAGING DE LA PASADA
# ==============================================================================
# El driver recibe un directorio y procesa todo lo que encuentre, así que se
# enlaza únicamente lo de esta pasada. Los enlaces pueden acabar siendo
# simbólicos si origen y destino están en sistemas de archivos distintos, y por
# eso más abajo se montan además los dos directorios de origen sobre sí mismos:
# sin ese bind el contenedor ve los nombres pero no los archivos, y el driver
# los da por procesados sin abrir ninguno (verificado en tahan el 2026-08-13 con
# OMPS: 39 gránulos "listos" en el mismo segundo y "0 products of 20").

mkdir -p "$STAGING_DIR" "$HOST_WORK" "$HOST_EDR_OUT" "$HOST_CACHE" "$LOG_DIR" "$STATE_DIR"
trap 'rm -rf "$HOST_WORK" "$STAGING_DIR"' EXIT

CRIS_COUNT=0

shopt -s nullglob
for prefijo in SCRIF GCRSO; do
    for f in "$HOST_CRIS_IN"/${prefijo}_"${SAT}"_"${FECHA}"_*_"${ORBITA}"_*.h5; do
        enlazar "$f" "$STAGING_DIR"/
        CRIS_COUNT=$((CRIS_COUNT + 1))
    done
done
shopt -u nullglob

if [ "$CRIS_COUNT" -eq 0 ]; then
    echo "ERROR: No se enlazó ningún SDR de CrIS de la pasada $CLAVE" >&2
    echo "       Se esperaban SCRIF*/GCRSO* en $HOST_CRIS_IN" >&2
    exit 1
fi

# La ventana abarca todos los GCRSO de la órbita; las tres fechas acotan la
# búsqueda de los SDR de ATMS, que pueden caer del otro lado de la medianoche.
if ! ventana_de_pasada; then
    echo "ERROR: No se pudo derivar la ventana temporal de la pasada $CLAVE" >&2
    echo "       Ningún GCRSO de $HOST_CRIS_IN tiene la forma esperada" >&2
    echo "       (GCRSO_<sat>_d<fecha>_t<inicio>_e<fin>_b<órbita>_...)." >&2
    exit 1
fi

FECHA_NUM="${FECHA#d}"
FECHA_PREV=$(date -u -d "${FECHA_NUM} -1 day" +%Y%m%d)
FECHA_SIG=$(date -u -d "${FECHA_NUM} +1 day" +%Y%m%d)

ATMS_COUNT=$(enlazar_atms "$STAGING_DIR")

LOG_FILE="$LOG_DIR/heap_${TIMESTAMP}_${CLAVE}.log"

echo "  Ventana:  $VENTANA_INI – $VENTANA_FIN" | tee -a "$LOG_FILE"
echo "  CrIS:     $CRIS_COUNT archivos"        | tee -a "$LOG_FILE"
echo "  ATMS:     $ATMS_COUNT archivos (margen ${MARGEN_ATMS}s)" | tee -a "$LOG_FILE"
echo "  Caché:    $HOST_CACHE"                 | tee -a "$LOG_FILE"
echo "  Salida:   $HOST_EDR_OUT"               | tee -a "$LOG_FILE"
echo "  Hilos:    $CORES"                      | tee -a "$LOG_FILE"

if [ "$ATMS_COUNT" -eq 0 ]; then
    echo "❌ ERROR: No hay SDR de ATMS que se traslapen con la pasada $CLAVE" | tee -a "$LOG_FILE"
    echo "   El modo HR_IRMW combina infrarrojo y microondas: sin ATMS no hay" | tee -a "$LOG_FILE"
    echo "   sondeo. Corre: run_sdr.sh --sensor atms"                          | tee -a "$LOG_FILE"
    echo "   Ojo: la órbita de ATMS NO es la de CrIS, el emparejamiento es por" | tee -a "$LOG_FILE"
    echo "   tiempo. Busca en $HOST_ATMS_IN algo de esa ventana."               | tee -a "$LOG_FILE"
    exit 1
fi

# ==============================================================================
# PROCESAMIENTO
# ==============================================================================
# El manual pide directorio de trabajo limpio en cada ejecución: HOST_WORK nace
# vacío y se descarta al final, así que eso se cumple solo. Los productos se
# piden en /work con --dest y de ahí se mueven a la salida DESPUÉS de contarlos:
# no se publica lo que no se ha verificado.
#
# Ojo con las comillas: el guion viaja como UNA sola cadena entrecomillada, así
# que toda comilla doble interior tiene que ir escapada. Una sin escapar parte el
# guion y bash recibe argumentos de más.

echo "" | tee -a "$LOG_FILE"
echo ">>> Ejecutando run_heap.bash (misión $MISION, modo HR_IRMW)..." | tee -a "$LOG_FILE"

EXIT_CODE=0
apptainer exec \
    --bind "$HOST_HEAP_HOME:/opt/cspp_heap" \
    --bind "$STAGING_DIR:/input" \
    --bind "$HOST_CRIS_IN:$HOST_CRIS_IN" \
    --bind "$HOST_ATMS_IN:$HOST_ATMS_IN" \
    --bind "$HOST_WORK:/work" \
    --bind "$HOST_CACHE:/anc" \
    --pwd /work \
    "$SIF_HEAP" /bin/bash -c "
        export HDF5_USE_FILE_LOCKING=FALSE
        export LC_ALL=C
        source \$CSPP_HEAP_HOME/scripts/cspp_heap_env.sh
        run_heap.bash -s $MISION -i /input -m HR_IRMW -o $SALIDA_HEAP \
                      -p $CORES -w /work -d /anc ${HEAP_OPTS:-}
    " >> "$LOG_FILE" 2>&1 || EXIT_CODE=$?

DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

if [ $EXIT_CODE -ne 0 ]; then
    echo "❌ ERROR: CSPP HEAP falló (código $EXIT_CODE) tras $DURACION" | tee -a "$LOG_FILE"
    echo "   Revisa el log: $LOG_FILE"                                  | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR"                    | tee -a "$LOG_FILE"
    trap - EXIT
    exit $EXIT_CODE
fi

# ==============================================================================
# VERIFICACIÓN Y ENTREGA
# ==============================================================================
# El código de salida no basta: estos drivers pueden terminar en 0 sin producir
# nada. Con --maxdepth 1 se cuenta solo lo entregado en /work y no lo que pueda
# quedar dentro del temporal que el propio driver crea y poda.

mapfile -t PRODUCTOS < <(find "$HOST_WORK" -maxdepth 1 -type f -name 'NUCAPS-*.nc' | sort)
NC_COUNT=${#PRODUCTOS[@]}

if [ "$NC_COUNT" -eq 0 ]; then
    echo "❌ ERROR: HEAP terminó sin error pero no generó productos."          | tee -a "$LOG_FILE"
    echo "   Sospecha número uno, el ancillary: §1.6.3 dice que si no hay dos" | tee -a "$LOG_FILE"
    echo "   pronósticos GFS que acoten la ventana, se emite un aviso y los"   | tee -a "$LOG_FILE"
    echo "   gránulos afectados NO se procesan. Empieza por:"                  | tee -a "$LOG_FILE"
    echo "   grep -iE 'gfs|warning|ancillary' $LOG_FILE"                       | tee -a "$LOG_FILE"
    echo "   y revisa que $HOST_CACHE tenga un directorio yyyy_mm_dd_jdy"      | tee -a "$LOG_FILE"
    echo "   de la fecha de la pasada."                                        | tee -a "$LOG_FILE"
    echo "   Si los gránulos salen todos con la misma marca de tiempo, no"     | tee -a "$LOG_FILE"
    echo "   llegó a abrirlos: revisa que $HOST_CRIS_IN y $HOST_ATMS_IN se"    | tee -a "$LOG_FILE"
    echo "   vean dentro del contenedor."                                      | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR"                           | tee -a "$LOG_FILE"
    trap - EXIT
    exit 1
fi

# Las familias se cuentan por lo que DE VERDAD haya, no contra una lista fija de
# patrones: el manual (§1.7) documenta NUCAPS-EDR, NUCAPS-CCR-AR y NUCAPS-OLR, y
# en modo HR_IRMW los nombres reales no son esos.
#
# CORREGIDO el 2026-08-17, y conviene leer por qué antes de volver a tocarlo.
# Hasta hoy este bloque daba por hecho que NUCAPS-ALL-HR era "EDR y CCR juntos"
# y contaba como recuperación todo lo que no fuera OLR. Es falso: un ncdump de
# ese archivo en tahan muestra CrIS_Radiances, ATMS_Brightness_Temps,
# Cloud_Fraction, Cloud_Height y Land_Fraction, y NO tiene Pressure, Temperature,
# H2O_MR ni Stability. El "ALL" es por todos los FOV, no por "todo junto". Con
# aquel criterio la etapa firmó marcadores de éxito durante dos días sin haber
# producido un solo sondeo, que es justo lo que el eslabón existe para producir.
#
# AFINADO el 2026-08-29 con la respuesta de CIMSS (foro de SSEC, t=60121): aquel
# 17 se concluyó que ALL-HR "era el CCR". La mitad estaba bien —es un archivo
# intermedio, entrada de otros módulos de NUCAPS— pero la etiqueta no: las
# radiancias limpiadas de nube van en `NUCAPS-CCR-AR`, que **tampoco sale**. No
# falta uno de los tres productos finales, faltan DOS, y eso mueve el fallo más
# atrás de lo que se pensaba: tampoco el cloud-clearing entrega su producto.
#
# El otro indicio que se dejó pasar fue la duración: 15 gránulos en 22 s. Una
# recuperación NUCAPS es físico-iterativa con transferencia radiativa y no corre
# a esa velocidad; ese número no era un logro, era la señal de que el paso caro
# nunca se ejecutó.
#
# Por eso el criterio ya no infiere: exige NUCAPS-EDR por nombre. Es la única
# familia cuya ausencia significa, sin ambigüedad, que no hubo recuperación.

declare -A FAMILIAS=()
for f in "${PRODUCTOS[@]}"; do
    fam=$(basename "$f")
    fam="${fam%%_v*}"
    FAMILIAS[$fam]=$(( ${FAMILIAS[$fam]:-0} + 1 ))
done

RECUPERACION=${FAMILIAS[NUCAPS-EDR]:-0}

# Radiancias y OLR sin un solo perfil no es una corrida buena, por muchos
# archivos que haya. El criterio de los otros EDR —¿produjo algo?— se queda
# corto aquí, porque HEAP entrega varias cosas y solo una es el producto.
if [ "$RECUPERACION" -eq 0 ]; then
    echo "❌ ERROR: $NC_COUNT archivos, pero ningún NUCAPS-EDR."                | tee -a "$LOG_FILE"
    echo "   Los perfiles son el producto; lo demás es entrada y subproducto."  | tee -a "$LOG_FILE"
    echo "   Familias encontradas:"                                            | tee -a "$LOG_FILE"
    for fam in $(printf '%s\n' "${!FAMILIAS[@]}" | sort); do
        echo "     $fam: ${FAMILIAS[$fam]}"                                    | tee -a "$LOG_FILE"
    done
    echo ""                                                                    | tee -a "$LOG_FILE"
    echo "   Si salieron ALL-HR (intermedio) pero ni EDR ni CCR-AR, ni la"      | tee -a "$LOG_FILE"
    echo "   recuperación ni el cloud-clearing llegaron a correr."               | tee -a "$LOG_FILE"
    echo "   llegó a correr. Lo verificado el 2026-08-17, para no repetirlo:"   | tee -a "$LOG_FILE"
    echo "     · NO es la bandera -o: vale '${SALIDA_HEAP}' y se parsea letra"  | tee -a "$LOG_FILE"
    echo "       por letra (con -o R desaparece el OLR, como debe)."            | tee -a "$LOG_FILE"
    echo "     · NO es el ancillary: el caché tenía su directorio del día."     | tee -a "$LOG_FILE"
    echo "     · NO son gránulos rechazados: el log no menciona 'retriev' ni"   | tee -a "$LOG_FILE"
    echo "       una sola vez, así que el paso caro nunca se intentó."          | tee -a "$LOG_FILE"
    echo "   Desconfía de la duración: 15 gránulos en ~25 s no es una"          | tee -a "$LOG_FILE"
    echo "   recuperación físico-iterativa, es el preprocesador solo."          | tee -a "$LOG_FILE"
    echo "   Siguiente paso, conservar el temporal del driver y mirar qué hizo" | tee -a "$LOG_FILE"
    echo "   el wrapper de perl, que hoy es una caja negra en el log:"          | tee -a "$LOG_FILE"
    echo "     HEAP_OPTS='--noclean -v' $0 -p $CLAVE --force"                   | tee -a "$LOG_FILE"
    echo ""                                                                    | tee -a "$LOG_FILE"
    echo "   Si en cambio hay EDR pero de menos, ahí sí revisa rechazados y"    | tee -a "$LOG_FILE"
    echo "   ancillary: grep -iE 'reject|quality|gfs' $LOG_FILE"                | tee -a "$LOG_FILE"
    echo "   (Si se pidió HEAP_SALIDA=O a propósito, esto es lo esperado.)"     | tee -a "$LOG_FILE"
    echo "   Se conservan $HOST_WORK y $STAGING_DIR"                            | tee -a "$LOG_FILE"
    trap - EXIT
    exit 1
fi

# ------------------------------------------------------------------------------
# Rescate de los logs propios de HEAP, ANTES de borrar el directorio de trabajo.
#
# El manual (§3.3) avisa que además de los NetCDF quedan ahí "other log and text
# files". La convención de la cadena es conservar el directorio de trabajo solo
# cuando la etapa falla, y para los demás eslabones está bien. HEAP tiene un caso
# que ellos no: puede terminar **bien y parcial** —28 productos donde caben 30—
# y entonces el diagnóstico hace falta justo cuando el criterio dice "éxito,
# borra todo". Sin esto, una corrida así no se puede investigar después y
# repetirla no contesta qué pasó en aquella.
#
# Pasó el 2026-08-15: la primera corrida buena dejó 14 de 15 gránulos y en el
# log nuestro —37 líneas— no había una sola mención a gránulos rechazados.

RESCATE="$LOG_DIR/heap_${TIMESTAMP}_${CLAVE}_cspp"
mapfile -t LOGS_CSPP < <(find "$HOST_WORK" -type f ! -name '*.nc' 2>/dev/null | sort)

if [ "${#LOGS_CSPP[@]}" -gt 0 ]; then
    mkdir -p "$RESCATE"
    cp -p "${LOGS_CSPP[@]}" "$RESCATE"/ 2>/dev/null || true
    echo "  Logs de HEAP: ${#LOGS_CSPP[@]} archivos en $RESCATE" | tee -a "$LOG_FILE"
fi

mv "${PRODUCTOS[@]}" "$HOST_EDR_OUT/"

{
    echo "procesado: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "pasada:    $CLAVE"
    echo "satelite:  $SAT (misión HEAP $MISION)"
    echo "cris:      $CRIS_COUNT archivos"
    echo "atms:      $ATMS_COUNT archivos"
    for fam in $(printf '%s\n' "${!FAMILIAS[@]}" | sort); do
        printf '%-10s %s archivos\n' "$(echo "$fam" | tr 'A-Z' 'a-z'):" "${FAMILIAS[$fam]}"
    done
    echo "duracion:  $DURACION"
    echo "salida:    $HOST_EDR_OUT"
    echo "log:       $LOG_FILE"
} > "$MARKER"

echo "" | tee -a "$LOG_FILE"
DESGLOSE=$(for fam in $(printf '%s\n' "${!FAMILIAS[@]}" | sort); do
               printf '%s %s, ' "${FAMILIAS[$fam]}" "$fam"
           done)
echo "✅ ÉXITO: $NC_COUNT productos de la pasada $CLAVE (${DESGLOSE%, }) en $DURACION" | tee -a "$LOG_FILE"
echo "   Salida:   $HOST_EDR_OUT" | tee -a "$LOG_FILE"
echo "   Marcador: $MARKER"       | tee -a "$LOG_FILE"
