#!/bin/bash
################################################################################
# Script: run_metop_l1.sh
# Propósito: METOP-B/C del crudo de antena a Level 1 (metopizer + AAPP + OPS-LRS)
# Autor: LANOT - UNAM
#
# Descripción:
#   Es el RT-STPS + SDR de la rama METOP, en un solo eslabón, con aapp_v8.15.sif:
#
#     cadu_to_ccsds   crudo (CADU) → paquetes CCSDS por instrumento (isps.*)
#     ccsds_to_l0     CCSDS → EPS Level 0 (AMSA, MHSx, HIRS, AVHR, IASI, HKTM)
#     get_tle         TLE de EUMETSAT para M01 y M03 (no fatal: ver abajo)
#     AAPP_RUN_METOP  Level 0 → Level 1 (IASI con OPS-LRS)
#     convert_to_hdf5 binarios de AAPP → HDF5, como hace stratus
#
#   Sustituye a referencia/metop/metop2.sh. De ahí se conservan los argumentos de
#   cada programa, para que la salida se pueda comparar byte a byte con la de
#   stratus, y se corrige lo que no se debe copiar:
#     - el marcador de una sola línea por satélite (lastch5), que pierde una
#       pasada si llegan dos antes de que corra, y que se escribe ANTES de
#       procesar: aquí, marcador por crudo y solo si salió todo;
#     - el satélite sacado de un 'grep METOP-*' con cut por columnas: aquí, del
#       SCID con más paquetes en el reporte de cadu_to_ccsds, y cotejado con el
#       nombre de los Level 0 (_M01_/_M03_);
#     - las cinco llamadas a AAPP_RUN_METOP. No son redundantes aunque lo
#       parezcan: AAPP_RUN_METOP aborta en cuanto falla UN instrumento, y el
#       HIRS de METOP-B no calibra ("No enough calib cycles found", tahan,
#       2026-11-18), así que la llamada completa revienta y lo que se publica
#       sale de las sueltas. Aquí van dos: una con lo que se exige (con OPS-LRS
#       una sola vez) y otra, opcional, con HIRS, cuyo fallo se avisa y no
#       tumba la pasada. Lo que se pierde es el hirsl1d en la rejilla de HIRS.
#
#   Sin argumentos toma el crudo de METOP más reciente del buzón de antena
#   (config/cadenas.tsv), ignorando los que aún se están escribiendo.
#
# Uso:
#   ./run_metop_l1.sh                  # el crudo de METOP más reciente pendiente
#   ./run_metop_l1.sh <crudo>          # un crudo específico
#   ./run_metop_l1.sh --force [crudo]  # reprocesa aunque ya tenga marcador
#
# Códigos de salida: 0 hecho (o ya estaba, o nada pendiente), 1 fallo, 75 el
# candado de AAPP siguió tomado METOP_ESPERA_MIN minutos (no es fallo: el
# barrido no lo cuenta como intento).
#
# Éxito = AAPP_RUN_METOP en 0 Y los Level 1 de TODOS los instrumentos esperados
# para ese satélite. AAPP_RUN_METOP sale en 2 cuando falla OPS-LRS y aun así
# entrega lo demás: eso es un fallo (sin IASI no hay sondeos), pero lo que salió
# se entrega igual, sin marcador, para que el crudo se reintente.
#
# Instrumentos por satélite (como metop2.sh). Los exigidos deciden el éxito;
# los opcionales van en su propia llamada y solo se avisa si fallan:
#   M01 (METOP-B)  exigidos AMSU-A MHS IASI AVHRR, opcional HIRS
#   M03 (METOP-C)  exigidos AMSU-A MHS IASI AVHRR (sin HIRS: stratus no lo procesa)
#
# CONTRATO CON EL HOST. Todo lo que AAPP escribe vive en METOP_ANC_DIR, que se
# monta en /anc (ver el %help de contenedores/aapp_v8.15.def):
#   mmam/      MMAM y TLE que ccsds_to_l0 saca de cada pasada. Tiene que
#              PERSISTIR: con el caché vacío el HKTM sale distinto.
#   orbelems/  DIR_NAVIGATION: tle_db/ (get_tle) y satpos/ (AAPP_RUN_METOP).
#   calibration/  DIR_CALIBRATION: coeficientes de ATOVS y AVHRR. AAPP escribe
#              en coef/avhcl (avh_get_vis_coefs, en cada pasada) y HIRS guarda
#              ahí su historia; get_atovs_cal_files.sh los actualiza. Se siembra
#              la primera vez con la copia que trae la imagen.
#   opsaux/    DIR_IASICONFIG: BRD/GRD de IASI para OPS-LRS. Lo baja
#              get_aux_files.sh de NWP SAF; sin él no sale IASI.
# Los tres primeros se crean solos; opsaux/ se exige poblado.
#
# Variables de entorno (para pruebas o rutas alternas):
#   METOP_INPUT_DIR    Buzón de crudos     (def. /datawork/input/polar/raw)
#   METOP_OUTPUT_DIR   Salida Level 1      (def. /data/output/metop/level1)
#   METOP_STATE_DIR    Marcadores .done    (def. /data/output/metop/state/aapp)
#   METOP_ANC_DIR      Caché de AAPP       (def. /data/ancillary/aapp)
#   METOP_MPR_DIR      mpr-config-M0x      (def. <scripts>/../config)
#   METOP_CONTAINER    Imagen .sif         (def. /opt/containers/aapp_v8.15.sif)
#   METOP_MIN_AGE_MIN  Edad mínima (min)   (def. 1)
#   METOP_LOG_BASE     Raíz de logs        (def. /var/log/lanot/polares)
#   METOP_WORK_BASE    Raíz de trabajo     (def. /data/tmp)
#   METOP_TLE          1 = get_tle en cada pasada, 0 = no (def. 1)
#   METOP_HDF5         1 = convert_to_hdf5, 0 = no (def. 1)
#   METOP_INSTR_M01    Exigidos de M01     (def. "AMSU-A MHS IASI AVHRR")
#   METOP_INSTR_M03    Exigidos de M03     (def. "AMSU-A MHS IASI AVHRR")
#   METOP_OPC_M01      Opcionales de M01   (def. "HIRS")
#   METOP_OPC_M03      Opcionales de M03   (def. "")
#   METOP_ESPERA_MIN   Espera máxima por el candado de OPS-LRS (def. 60)
#   CADENAS_TSV        Cadena → satélite   (def. <scripts>/../config/cadenas.tsv)
#
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

CONTAINER="${METOP_CONTAINER:-/opt/containers/aapp_v8.15.sif}"
INPUT_DIR="${METOP_INPUT_DIR:-/datawork/input/polar/raw}"
DIR_L1="${METOP_OUTPUT_DIR:-/data/output/metop/level1}"
STATE_DIR="${METOP_STATE_DIR:-/data/output/metop/state/aapp}"
ANC_DIR="${METOP_ANC_DIR:-/data/ancillary/aapp}"
MPR_DIR="${METOP_MPR_DIR:-$SCRIPT_DIR/../config}"
MIN_AGE_MIN="${METOP_MIN_AGE_MIN:-1}"
CON_TLE="${METOP_TLE:-1}"
CON_HDF5="${METOP_HDF5:-1}"
INSTR_M01="${METOP_INSTR_M01:-AMSU-A MHS IASI AVHRR}"
INSTR_M03="${METOP_INSTR_M03:-AMSU-A MHS IASI AVHRR}"
OPC_M01="${METOP_OPC_M01-HIRS}"
OPC_M03="${METOP_OPC_M03-}"
ESPERA_MIN="${METOP_ESPERA_MIN:-60}"

WORK_BASE="${METOP_WORK_BASE:-/data/tmp}"
JOB_ID="${SLURM_JOB_ID:-$$}"

LOG_BASE="${METOP_LOG_BASE:-/var/log/lanot/polares}"
LOG_DIR="${LOG_BASE}/aapp"

# OPS-LRS levanta servidores propios (MSGS__Serveur y compañía) y los baja con
# 'ops_process --stop' al terminar. No está comprobado que dos a la vez no se
# estorben, y una pasada tarda minutos, así que se serializa: METOP-B y METOP-C
# pasan con unos 50 min de diferencia y no hay nada que ganar corriendo juntos.
CANDADO="${WORK_BASE}/lanot_aapp.lock"

# Dónde busca AAPP su calibración dentro de la imagen ($SOFT/data/calibration).
# Sobre ella se monta $ANC_DIR/calibration (ver en_aapp).
CALIBRACION_IMAGEN=/opt/aapp/install/AAPP_8.15/AAPP/data/calibration

# ============================================================================
# FUNCIONES
# ============================================================================

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

uso() {
    cat <<EOF
Uso:
  $0                  Procesa el crudo de METOP más reciente de $INPUT_DIR
  $0 <crudo>          Procesa un crudo específico
  $0 --force [crudo]  Reprocesa aunque ya exista el marcador

Opciones:
  -f, --force   Ignora el marcador de procesado
  -h, --help    Muestra esta ayuda
EOF
}

source "$SCRIPT_DIR/cadenas.sh"

# ¿Es de la rama METOP este crudo, según cadenas.tsv? consultar_cadena devuelve
# 4. Los chain6 de antes del 2026-11-19 dan 1 (los procesa la cadena vieja) y la
# autoselección no los toma; a mano, sí (ver SELECCIÓN DEL CRUDO).
es_de_metop() {
    local codigo=0
    consultar_cadena "$1" > /dev/null 2>&1 || codigo=$?
    [ "$codigo" -eq 4 ]
}

seleccionar_crudo_mas_reciente() {
    local candidato

    while IFS= read -r candidato; do
        if es_de_metop "$candidato"; then
            echo "$candidato"
            return 0
        fi
    done < <(find "$INPUT_DIR" -maxdepth 1 -type f -mmin "+${MIN_AGE_MIN}" \
                  -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)

    return 1
}

# Una orden dentro del contenedor, con el ambiente de AAPP cargado. Devuelve el
# código de la orden: una llamada por paso, para no perder el de ninguno.
#
# Las variables del contrato con el host van ANTES de cargar ATOVS_ENV8, que
# las toma con ${VAR:=…}. Y nada de tocar el PATH antes: ATOVS_ENV8 lo
# reemplaza entero si no ve en él sus rutas (lo arregla el .def, pero solo
# para las del metopizer y /opt/aapp/bin).
#
# La calibración NO se puede redirigir con variables: ATOVS_ENV8 fija
# DIR_CALIBRATION y PAR_CALIBRATION_COEF sin ${VAR:=…}, y cada script de AAPP
# lo vuelve a cargar (vía ATOVS_CONF), así que un export nuestro dura hasta el
# primer programa. Se monta encima de la ruta interna, como el estático de SDR.
#
# HOME apunta al trabajo porque ATOVS_CONF carga $HOME/ATOVS_ENV8 si existe, y
# apptainer monta el home real: en stratus, lanotadm tiene uno, y cualquier
# copia así cambiaría la configuración sin que nada lo diga.
en_aapp() {
    local etiqueta="$1"; shift
    local codigo=0

    echo "--- $etiqueta --- $(date '+%H:%M:%S')" >> "$LOG_FILE"
    apptainer exec \
        --bind "$INPUT_DIR_REAL":/input:ro \
        --bind "$WORK_DIR":/work \
        --bind "$ANC_DIR":/anc \
        --bind "$MPR_DIR_REAL":/mpr:ro \
        --bind "$ANC_DIR/calibration":"$CALIBRACION_IMAGEN" \
        --pwd /work \
        "$CONTAINER" \
        /bin/bash -c "export LC_ALL=C HOME=/work/aapp WRK=/work/aapp DIR_NAVIGATION=/anc/orbelems DIR_IASICONFIG=/anc/opsaux; . /opt/aapp/ATOVS_ENV8; $*" \
        >> "$LOG_FILE" 2>&1 || codigo=$?
    echo "--- $etiqueta: código $codigo --- $(date '+%H:%M:%S')" >> "$LOG_FILE"

    return $codigo
}

# Sale con error conservando el directorio de trabajo para depurar.
fallar() {
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] ERROR: $*" >&2
    echo "[$TIMESTAMP] Ver log: $LOG_FILE" >&2
    echo "[$TIMESTAMP] No se escribió el marcador: el crudo se reintentará." >&2
    echo "[$TIMESTAMP] Se conserva el directorio de trabajo: $WORK_DIR" >&2
    trap - EXIT
    exit 1
}

# ============================================================================
# ARGUMENTOS
# ============================================================================

FORCE=0
INPUT_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        -h|--help)  uso; exit 0 ;;
        -*)
            echo "ERROR: Opción desconocida: $1" >&2
            uso >&2
            exit 1
            ;;
        *)
            if [ -n "$INPUT_FILE" ]; then
                echo "ERROR: Solo se admite un crudo por ejecución" >&2
                exit 1
            fi
            INPUT_FILE="$1"
            ;;
    esac
    shift
done

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP_FILE=$(date '+%Y%m%d_%H%M%S')
START_EPOCH=$(date '+%s')

# ============================================================================
# SELECCIÓN DEL CRUDO
# ============================================================================

if [ -n "$INPUT_FILE" ]; then
    if [ ! -f "$INPUT_FILE" ]; then
        echo "ERROR: Archivo no encontrado: $INPUT_FILE" >&2
        exit 1
    fi
    INPUT_FILE=$(realpath "$INPUT_FILE")

    # A mano se acepta también un METOP de antes del corte de la rama (código 1
    # con satélite METOP: los 268 chain6 de septiembre a noviembre), y uno que
    # no se llame chainN-… (pruebas), del que decide el SCID. Lo que la tabla
    # dice que es de otro satélite, no.
    CODIGO_CADENA=0
    SAT_INFO=$(consultar_cadena "$INPUT_FILE" 2>/dev/null) || CODIGO_CADENA=$?
    case "$CODIGO_CADENA" in
        4) ;;
        1)
            if [[ "$SAT_INFO" != METOP* ]]; then
                echo "ERROR: $(basename "$INPUT_FILE") es de ${SAT_INFO% *} según $CADENAS_TSV, no de METOP." >&2
                exit 1
            fi
            echo "[$TIMESTAMP] Aviso: crudo de METOP anterior a la rama METOP en $CADENAS_TSV; se procesa porque se pidió."
            ;;
        0)
            echo "ERROR: $(basename "$INPUT_FILE") es de ${SAT_INFO% *} según $CADENAS_TSV, no de METOP." >&2
            exit 1
            ;;
        2)  echo "[$TIMESTAMP] Aviso: $CADENAS_TSV no conoce este crudo; el satélite saldrá del SCID." ;;
        *)
            echo "ERROR: no se pudo consultar $CADENAS_TSV" >&2
            exit 1
            ;;
    esac
else
    if [ ! -d "$INPUT_DIR" ]; then
        echo "ERROR: Directorio de entrada no encontrado: $INPUT_DIR" >&2
        exit 1
    fi

    echo "[$TIMESTAMP] Buscando el crudo de METOP más reciente en: $INPUT_DIR"

    if ! INPUT_FILE=$(seleccionar_crudo_mas_reciente); then
        echo "[$TIMESTAMP] No hay crudos de METOP pendientes."
        echo "              (según $CADENAS_TSV; se ignoran los modificados"
        echo "               en los últimos ${MIN_AGE_MIN} min, que pueden estar incompletos)"
        exit 0
    fi
    INPUT_FILE=$(realpath "$INPUT_FILE")
fi

# A la raíz: apptainer no arranca si quien corre no puede entrar al directorio
# actual, y "sudo -u lanotadm" desde el clon hereda un home ajeno ("can't change
# directory to /home/…: permission denied", 2026-11-18). Lo mismo que hacen
# procesar_pasada.sh y recibe.sh; va después de resolver las rutas de los
# argumentos, que pueden ser relativas.
cd / || exit 1

FILENAME=$(basename "$INPUT_FILE")
INPUT_DIR_REAL=$(dirname "$INPUT_FILE")

echo "=============================================================================="
echo "[$TIMESTAMP] METOP → LEVEL 1: $FILENAME"
echo "=============================================================================="

# ============================================================================
# ¿YA FUE PROCESADO?
# ============================================================================
# Como en run_rt_stps.sh: el marcador tiene que ser más nuevo que el crudo,
# porque la antena recicla los nombres (los chainN-M_passNN sin sello de hora).

MARKER="${STATE_DIR}/${FILENAME}.done"
MANIFIESTO="${STATE_DIR}/${FILENAME}.l1"

if [ -f "$MARKER" ] && [ "$MARKER" -nt "$INPUT_FILE" ] && [ "$FORCE" -eq 0 ]; then
    echo ""
    echo "ℹ  $FILENAME ya fue procesado:"
    while IFS= read -r linea; do
        echo "   $linea"
    done < "$MARKER"
    echo ""
    echo "   No hay nada que hacer. Usa --force para reprocesarlo."
    exit 0
fi

if [ -f "$MARKER" ]; then
    echo "[$TIMESTAMP] --force: se reprocesa a pesar del marcador existente"
fi

# ============================================================================
# VALIDACIÓN DEL AMBIENTE
# ============================================================================

if [ ! -f "$CONTAINER" ]; then
    echo "ERROR: Contenedor no encontrado: $CONTAINER" >&2
    exit 1
fi

for sat in M01 M03; do
    if [ ! -s "$MPR_DIR/mpr-config-$sat" ]; then
        echo "ERROR: No se encontró $MPR_DIR/mpr-config-$sat" >&2
        exit 1
    fi
done
MPR_DIR_REAL=$(realpath "$MPR_DIR")

# Sin las BRD/GRD de IASI, OPS-LRS falla y la pasada nunca saldría completa:
# mejor decirlo aquí que después de diez minutos de AAPP.
if [ -z "$(find "$ANC_DIR/opsaux" -maxdepth 1 -type f -name 'IASI_*' -print -quit 2>/dev/null)" ]; then
    echo "ERROR: $ANC_DIR/opsaux no tiene los auxiliares de IASI (IASI_BRD_*, IASI_GRD_*…)." >&2
    echo "       Se bajan de NWP SAF con get_aux_files.sh, que viaja en la imagen:" >&2
    echo "         mkdir -p $ANC_DIR/opsaux" >&2
    echo "         apptainer exec -B $ANC_DIR/opsaux:/opsaux --pwd /tmp $CONTAINER get_aux_files.sh /opsaux" >&2
    exit 1
fi

# satpos/ y la historia de HIRS por satélite: AAPP escribe ahí sin crearlos.
mkdir -p "$ANC_DIR"/{mmam,orbelems/tle_db,orbelems/satpos} "$LOG_DIR" "$STATE_DIR"

WORK_DIR="${WORK_BASE}/aapp_${TIMESTAMP_FILE}_${JOB_ID}"
mkdir -p "$WORK_DIR"/{isps,l0,aapp,l1}
trap 'rm -rf "$WORK_DIR"' EXIT

LOG_FILE="${LOG_DIR}/${TIMESTAMP_FILE}_${FILENAME}.log"

# ============================================================================
# CANDADO (ver CANDADO arriba)
# ============================================================================

exec 9> "$CANDADO"
# Lo comparten lanotadm (operación) y quien pruebe a mano desde el clon: si lo
# crea una persona con su umask, lanotadm ya no puede abrirlo y la siguiente
# pasada muere aquí (pasó con las pruebas del 2026-11-18: quedó de
# aguilars:aguilars, así que ni g+w alcanzaba). Es un archivo vacío: escribible
# para todos no expone nada.
chmod a+rw "$CANDADO" 2>/dev/null || true
if ! flock -n 9; then
    echo "[$TIMESTAMP] Otra corrida de AAPP en curso; se espera hasta ${ESPERA_MIN} min..."
    if ! flock -w $((ESPERA_MIN * 60)) 9; then
        # 75, como procesar_pasada.sh: el barrido no lo cuenta como intento.
        echo "ERROR: el candado $CANDADO no se liberó en ${ESPERA_MIN} min." >&2
        exit 75
    fi
fi

# La calibración, la primera vez: la copia que trae la imagen. Después ya no
# se toca desde aquí; la mantienen AAPP y get_atovs_cal_files.sh.
if [ ! -d "$ANC_DIR/calibration/coef" ]; then
    echo "[$TIMESTAMP] Sembrando $ANC_DIR/calibration desde la imagen (primera vez)"
    rm -rf "$ANC_DIR/calibration.tmp"   # de una siembra interrumpida: cp -r anidaría
    apptainer exec --bind "$ANC_DIR":/anc --pwd /anc "$CONTAINER" \
        /bin/bash -c "cp -r $CALIBRACION_IMAGEN /anc/calibration.tmp" \
        || { echo "ERROR: no se pudo copiar la calibración de la imagen" >&2; rm -rf "$ANC_DIR/calibration.tmp"; exit 1; }
    # cp copia el modo de la imagen (644): sin esto, si la siembra la hace una
    # persona en pruebas, lanotadm no puede actualizar los coeficientes después.
    chmod -R g+rwX "$ANC_DIR/calibration.tmp"
    mv "$ANC_DIR/calibration.tmp" "$ANC_DIR/calibration"
fi

# ============================================================================
# 1. CADU → CCSDS
# ============================================================================

echo "[$(date '+%H:%M:%S')] cadu_to_ccsds..."
en_aapp cadu_to_ccsds \
    "cd /work/isps && cadu_to_ccsds --in /input/$FILENAME --out isps" \
    || fallar "cadu_to_ccsds falló"

# El satélite sale del reporte: "276542 data packets had SCID of 13 (METOP-3)".
# Puede haber más de una línea si se colaron CADU ruidosos: gana la que tenga
# más paquetes. METOP-1 = M01 = METOP-B; METOP-3 = M03 = METOP-C. El -a es
# indispensable: la barra de progreso de cadu_to_ccsds deja bytes que no son
# texto, y sin él grep contesta "binary file matches" en vez de las líneas.
SCID_SAT=$(grep -aoE '[0-9]+ data packets had SCID of [0-9]+ \(METOP-[0-9]\)' "$LOG_FILE" \
           | sort -rn | head -1 | grep -oE 'METOP-[0-9]' || true)
case "$SCID_SAT" in
    METOP-1) SAT=M01; SATELLITE=METOP-B; INSTRUMENTOS="$INSTR_M01"; OPCIONALES="$OPC_M01" ;;
    METOP-3) SAT=M03; SATELLITE=METOP-C; INSTRUMENTOS="$INSTR_M03"; OPCIONALES="$OPC_M03" ;;
    *)       fallar "no se pudo identificar el satélite en el reporte de cadu_to_ccsds (SCID: '${SCID_SAT:-ninguno}')" ;;
esac
echo "[$(date '+%H:%M:%S')] Satélite: $SATELLITE ($SAT, $SCID_SAT)"

# ============================================================================
# 2. CCSDS → LEVEL 0
# ============================================================================
# Los mismos argumentos que metop2.sh. -g/-u leen y actualizan el caché de
# MMAM, que persiste en el host. Los isps.* que no van a Level 0 (GOME, ASCAT,
# GRAS, SEM) se quedan en el directorio de trabajo y se borran con él.

echo "[$(date '+%H:%M:%S')] ccsds_to_l0..."
en_aapp ccsds_to_l0 \
    "cd /work/isps && ccsds_to_l0 --config-apid \$METOPIZER_HOME/config/ccsds.config --config-mphr /mpr/mpr-config-$SAT -d /work/l0 -g /anc/mmam -u /anc/mmam -t tle -i isps.hktm.ccsds isps.amsua.ccsds isps.mhs.ccsds isps.avhrr.ccsds isps.hirs.ccsds isps.iasi.ccsds isps.a-dcs.ccsds" \
    || fallar "ccsds_to_l0 falló"

# Cotejo: los Level 0 tienen que ser del satélite que dijo el SCID.
mapfile -t L0S < <(find "$WORK_DIR/l0" -maxdepth 1 -type f -name '????_???_00_M0?_*Z' -printf '%f\n' | sort)
if [ ${#L0S[@]} -eq 0 ]; then
    fallar "ccsds_to_l0 terminó sin error pero no generó ningún Level 0"
fi
for f in "${L0S[@]}"; do
    if [ "${f:12:3}" != "$SAT" ]; then
        fallar "el Level 0 $f no es de $SAT, que es lo que dijo el SCID"
    fi
done
echo "[$(date '+%H:%M:%S')] Level 0: ${#L0S[@]} archivos (${L0S[*]%%_*})"

# ============================================================================
# 3. TLE
# ============================================================================
# get_tle baja los TLE de EUMETSAT a orbelems/tle_db. Si no hay red, AAPP usa
# los más recientes que ya estén ahí, así que no es fatal; pero la navegación
# se degrada con los días, y por eso se avisa en el resumen.

TLE_ESTADO="no se pidió"
if [ "$CON_TLE" = "1" ]; then
    echo "[$(date '+%H:%M:%S')] get_tle..."
    if en_aapp get_tle "cd /work/aapp && get_tle"; then
        TLE_ESTADO="actualizados"
    else
        TLE_ESTADO="FALLÓ la descarga (se usan los de tle_db)"
        echo "  ⚠ get_tle falló: se sigue con los TLE que haya en $ANC_DIR/orbelems/tle_db"
    fi
fi

# ============================================================================
# 4. LEVEL 0 → LEVEL 1
# ============================================================================

echo "[$(date '+%H:%M:%S')] AAPP_RUN_METOP -i \"$INSTRUMENTOS\" -g IASI..."
CODIGO_AAPP=0
en_aapp AAPP_RUN_METOP \
    "AAPP_RUN_METOP -i \"$INSTRUMENTOS\" -g IASI -d /work/l0 -o /work/l1" \
    || CODIGO_AAPP=$?

# Los opcionales, uno por llamada y DESPUÉS: AAPP_RUN_METOP borra al empezar
# los 1b de $WRK, pero los de la llamada principal ya se movieron a /work/l1.
# Cada uno lleva su rejilla por omisión (HIRS → atovpp en la de HIRS).
OPC_FALLIDOS=()
for instr in $OPCIONALES; do
    echo "[$(date '+%H:%M:%S')] AAPP_RUN_METOP -i \"$instr\" (opcional)..."
    if ! en_aapp "AAPP_RUN_METOP $instr" \
            "AAPP_RUN_METOP -i \"$instr\" -d /work/l0 -o /work/l1"; then
        OPC_FALLIDOS+=("$instr")
        echo "  ⚠ $instr falló; no cuenta para el marcador (ver log)"
    fi
done

# ============================================================================
# 5. HDF5
# ============================================================================
# Lo que convierte metop2.sh. Un fallo aquí no tumba la pasada: no se sabe
# todavía quién consume los HDF5 (plan_metop.md, "Productos y usuarios").

HDF5_FALLIDOS=0
if [ "$CON_HDF5" = "1" ]; then
    mapfile -t PARA_HDF5 < <(cd "$WORK_DIR/l1" && ls amsual1c_*.l1c mhsl1c_*.l1c hirsl1* hrpt_*.l1b iasil1* 2>/dev/null || true)
    if [ ${#PARA_HDF5[@]} -gt 0 ]; then
        echo "[$(date '+%H:%M:%S')] convert_to_hdf5 (${#PARA_HDF5[@]} archivos)..."
    fi
    for f in "${PARA_HDF5[@]}"; do
        en_aapp "convert_to_hdf5 $f" "cd /work/l1 && convert_to_hdf5 $f" \
            || HDF5_FALLIDOS=$((HDF5_FALLIDOS + 1))
    done
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DURACION=$(formato_duracion $(( $(date '+%s') - START_EPOCH )))

# ============================================================================
# ENTREGA
# ============================================================================
# Por instrumento, como stratus: level1/{amsua,mhs,hirs,avhrr,iasi}. Se entrega
# también lo parcial: un AVHRR bueno sirve aunque OPS-LRS haya fallado.

declare -A DESTINO=(
    [amsu]=amsua [mhsl]=mhs [hirs]=hirs [hrpt]=avhrr [iasi]=iasi [IASI]=iasi
)
mapfile -t L1S < <(find "$WORK_DIR/l1" -maxdepth 1 -type f -printf '%f\n' | sort)
ENTREGADOS=()
SIN_DESTINO=()
for f in "${L1S[@]}"; do
    destino="${DESTINO[${f:0:4}]:-}"
    if [ -z "$destino" ]; then
        SIN_DESTINO+=("$f")
        continue
    fi
    mkdir -p "$DIR_L1/$destino"
    mv -f "$WORK_DIR/l1/$f" "$DIR_L1/$destino/"
    ENTREGADOS+=("$destino/$f")
done

# ============================================================================
# ¿SALIÓ TODO?
# ============================================================================
# Se mira lo ENTREGADO, no el directorio de trabajo: la primera prueba contó
# el AMSU-A en el trabajo, la clasificación no lo reconoció, y el marcador
# quedó escrito con el AMSU-A borrado junto con el trabajo.

declare -A PATRON=(
    [AMSU-A]="amsua/amsual1b_${SAT}_*.l1b"
    [MHS]="mhs/mhsl1b_${SAT}_*.l1b"
    [HIRS]="hirs/hirsl1b_${SAT}_*.l1b"
    [AVHRR]="avhrr/hrpt_${SAT}_*.l1b"
    [IASI]="iasi/IASI_xxx_1C_${SAT}_*"
)
FALTANTES=()
for instr in $INSTRUMENTOS; do
    encontrado=0
    for e in "${ENTREGADOS[@]}"; do
        # shellcheck disable=SC2053  # el patrón es glob a propósito
        if [[ "$e" == ${PATRON[$instr]} ]] && [ -s "$DIR_L1/$e" ]; then
            encontrado=1
            break
        fi
    done
    [ "$encontrado" -eq 1 ] || FALTANTES+=("$instr")
done

# Un archivo sin destino es un producto que AAPP empezó a dar y esta tabla no
# conoce: no se tira. Se queda en el trabajo, que se conserva, y no hay marcador.
if [ ${#SIN_DESTINO[@]} -gt 0 ]; then
    echo "  ⚠ Sin destino en level1 (se quedan en $WORK_DIR/l1): ${SIN_DESTINO[*]}" | tee -a "$LOG_FILE"
fi

if [ "$CODIGO_AAPP" -ne 0 ] || [ ${#FALTANTES[@]} -gt 0 ] || [ ${#SIN_DESTINO[@]} -gt 0 ]; then
    [ ${#ENTREGADOS[@]} -gt 0 ] && echo "[$TIMESTAMP] Se entregaron ${#ENTREGADOS[@]} archivos parciales a $DIR_L1"
    if [ "$CODIGO_AAPP" -eq 2 ]; then
        fallar "AAPP_RUN_METOP salió en 2: falló OPS-LRS (IASI). Faltan: ${FALTANTES[*]:-ninguno}"
    elif [ "$CODIGO_AAPP" -ne 0 ]; then
        fallar "AAPP_RUN_METOP falló (código $CODIGO_AAPP). Faltan: ${FALTANTES[*]:-ninguno}"
    elif [ ${#FALTANTES[@]} -gt 0 ]; then
        fallar "AAPP_RUN_METOP terminó en 0 pero faltan: ${FALTANTES[*]}"
    else
        fallar "hay Level 1 que no se sabe a qué instrumento van: ${SIN_DESTINO[*]}"
    fi
fi

# ============================================================================
# MARCADOR
# ============================================================================

{
    echo "procesado:    $(date '+%Y-%m-%d %H:%M:%S')"
    echo "satelite:     $SATELLITE ($SAT)"
    echo "instrumentos: $INSTRUMENTOS"
    echo "opcionales:   ${OPCIONALES:-ninguno}${OPC_FALLIDOS:+ (fallaron: ${OPC_FALLIDOS[*]})}"
    echo "level0:       ${#L0S[@]} archivos"
    echo "level1:       ${#ENTREGADOS[@]} archivos"
    echo "tle:          $TLE_ESTADO"
    echo "log:          $LOG_FILE"
} > "$MARKER"

# Qué Level 1 son de este crudo, para el orquestador de la rama (pieza 3).
printf '%s\n' "${ENTREGADOS[@]}" > "$MANIFIESTO"

echo ""
echo "=============================================================================="
echo "[$TIMESTAMP] PROCESAMIENTO COMPLETADO"
echo "=============================================================================="
echo "  Satélite:      $SATELLITE ($SAT)"
echo "  Instrumentos:  $INSTRUMENTOS"
if [ -n "$OPCIONALES" ]; then
echo "  Opcionales:    $OPCIONALES${OPC_FALLIDOS:+  ⚠ fallaron: ${OPC_FALLIDOS[*]}}"
fi
echo "  Level 0:       ${#L0S[@]} archivos"
echo "  Level 1:       ${#ENTREGADOS[@]} archivos en $DIR_L1"
echo "  TLE:           $TLE_ESTADO"
if [ "$HDF5_FALLIDOS" -gt 0 ]; then
echo "  HDF5:          ⚠ $HDF5_FALLIDOS conversiones fallaron (ver log)"
fi
echo "  Duración:      $DURACION"
echo "  Log:           $LOG_FILE"
echo "  Marcador:      $MARKER"
echo "=============================================================================="

exit 0
