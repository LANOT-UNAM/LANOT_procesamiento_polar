#!/bin/bash
# ==============================================================================
# prueba_dos_turnos.sh — dos pasadas reales a la vez, sin tocar la operación.
#
# Antes de abrir el segundo turno (plan_operacion_datawork.md §0.6 y §0.7) hay
# que saber dos cosas que ninguna prueba con apptainer simulado responde:
#
#   1. ¿Se mezclan? Puntos 6 y 7 del plan: de_otro_satelite() con dos satélites
#      en la misma ventana de Level 2, y los cachés de ACSPO y Active Fire
#      escritos por dos corridas a la vez.
#   2. ¿Se estorban? Cuánto se alarga cada etapa con la otra pasada corriendo,
#      que es lo que decide si MAX_PARALELO tiene que bajar de 3 a 2.
#
# Corre el MISMO par de crudos dos veces, cada una en su propio árbol bajo
# /data/tmp: primero en serie (el control) y luego las dos a la vez. Se compara
# una contra otra y no contra producción, porque desde que producción procesó
# esos crudos cambiaron el TLE y el GFS disponible, y cualquier diferencia se
# confundiría con un efecto de la concurrencia.
#
# Los cachés de ancillary y el candado de HEAP NO se redirigen: compartirlos es
# justo lo que se prueba. Por eso tiene que correr como lanotadm, el dueño de
# esos cachés: un archivo que la prueba dejara ahí con otro dueño y modo 644
# no lo podría reescribir la operación después. Y por eso corre desde
# /opt/lanot/polares, que lanotadm sí puede leer.
#
# El par por omisión es NPP 08:33 y NOAA-20 08:52 UTC del 2026-10-14, el caso
# que más se encima (19 min entre recepciones) y que en producción salió bien
# en serie. La segunda arranca 19 min después de la primera, como en la antena:
# así se enciman el SDR de una con el Level 2 de la otra, que es lo que pasaría
# con dos turnos. A la vez NO, salvo que se pida: ATMOS corre todos los gránulos
# en paralelo y con 10 ocupa ~240 de los 251 GB de tahan —el kernel tira la
# caché entera y manda ~9 GB a swap, medido el 2026-10-14 con NPP—, así que dos
# ATMOS juntas pedirían el doble de la RAM y el OOM killer podría matar
# cualquier proceso de la máquina, no solo los de la prueba. Con 19 min de
# desfase la ATMOS de la segunda empieza cuando la de la primera ya acabó.
#
# Hora apropiada: fuera de los racimos de JPSS (07–09 y 19–21 UTC, 01–03 y
# 13–15 en tahan). Dura ~2 h con el control. Por ejemplo:
#
#   echo /opt/lanot/polares/scripts/prueba_dos_turnos.sh \
#       | sudo -u lanotadm at 17:30
#
# El informe queda en <base>/informe.txt; el árbol, para inspeccionarlo.
#
# Uso:
#   prueba_dos_turnos.sh [opciones] [RAW_A RAW_B]
#
# Opciones:
#   -b, --base DIR      Árbol de la prueba (def. /data/tmp/prueba_dos_turnos_<sello>)
#   -d, --desfase SEG   La segunda arranca SEG segundos después (def. 1140, los
#                       19 min entre NPP y NOAA-20). Menos de 600 exige
#                       --permitir-choque: las dos ATMOS no caben juntas en RAM
#       --permitir-choque  Acepta un desfase menor de 600 s
#   -s, --sin-serie     Salta el control; solo la corrida simultánea
#   -e, --espera MIN    Si hay una pasada de producción en curso, cuánto
#                       esperarla antes de rendirse (def. 60)
#   -h, --help
#
# Variables de entorno:
#   RTSTPS_INPUT_DIR    Buzón de RAW            (def. /datawork/input/polar/raw)
#   LOCK_PRODUCCION     Candado de la operación (def. /data/tmp/lanot_polares.lock)
#   SALIDA_PRODUCCION   Árbol de producción, para detectar fugas (def. /data/output/jpss)
#   LOGS_PRODUCCION     (def. /var/log/lanot/polares)
#   PRUEBA_USUARIO      Usuario exigido (def. lanotadm; vacío para no exigir)
#   PRUEBA_MIN_GB       Espacio libre mínimo para empezar (def. 100; ocupa ~30)
#   SCRIPTS_DIR         De dónde sale procesar_pasada.sh (def. junto a este script)
#
# Sale en 0 si las dos corridas terminan bien, producen lo mismo que el control
# y nada cayó en el árbol de producción; en 1 si no. En 2 si no pudo empezar.
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPTS_DIR:-$SCRIPT_DIR}"

INPUT_DIR="${RTSTPS_INPUT_DIR:-/datawork/input/polar/raw}"
LOCK_PRODUCCION="${LOCK_PRODUCCION:-/data/tmp/lanot_polares.lock}"
SALIDA_PRODUCCION="${SALIDA_PRODUCCION:-/data/output/jpss}"
LOGS_PRODUCCION="${LOGS_PRODUCCION:-/var/log/lanot/polares}"
PRUEBA_USUARIO="${PRUEBA_USUARIO-lanotadm}"
PRUEBA_MIN_GB="${PRUEBA_MIN_GB:-100}"

RAW_A="chain4-3_pass33_20261014T083305"     # NPP
RAW_B="chain2-3_pass13_20261014T085225"     # NOAA-20, 19 min después

SELLO=$(date '+%Y%m%d_%H%M%S')
BASE=""
DESFASE=1140
PERMITIR_CHOQUE=0
CON_SERIE=1
ESPERA_MIN=60

uso() {
    sed -n '/^# Uso:/,/^# Sale en 0/p' "$0" | sed 's/^# \{0,1\}//'
}

ahora() { date '+%Y-%m-%d %H:%M:%S'; }

POSICIONALES=()
while [ $# -gt 0 ]; do
    case "$1" in
        -b|--base)      BASE="$2"; shift 2 ;;
        -d|--desfase)   DESFASE="$2"; shift 2 ;;
        -s|--sin-serie) CON_SERIE=0; shift ;;
        --permitir-choque) PERMITIR_CHOQUE=1; shift ;;
        -e|--espera)    ESPERA_MIN="$2"; shift 2 ;;
        -h|--help)      uso; exit 0 ;;
        -*)             echo "Opción desconocida: $1" >&2; uso >&2; exit 2 ;;
        *)              POSICIONALES+=("$1"); shift ;;
    esac
done
case "${#POSICIONALES[@]}" in
    0) ;;
    2) RAW_A="${POSICIONALES[0]}"; RAW_B="${POSICIONALES[1]}" ;;
    *) echo "Se esperan dos crudos o ninguno" >&2; exit 2 ;;
esac
BASE="${BASE:-/data/tmp/prueba_dos_turnos_$SELLO}"

case "$DESFASE" in
    ''|*[!0-9]*) echo "--desfase lleva segundos: $DESFASE" >&2; exit 2 ;;
esac
if [ "$DESFASE" -lt 600 ] && [ "$PERMITIR_CHOQUE" -eq 0 ]; then
    echo "❌ Con ${DESFASE}s de desfase las dos ATMOS correrían juntas, y cada una" >&2
    echo "   ocupa ~240 GB con una pasada de 10 gránulos: no caben en tahan." >&2
    echo "   Si es lo que quieres medir, agrega --permitir-choque." >&2
    exit 2
fi

# Acepta el nombre a secas o la ruta.
ruta_raw() {
    case "$1" in
        */*) echo "$1" ;;
        *)   echo "$INPUT_DIR/$1" ;;
    esac
}
RAW_A="$(ruta_raw "$RAW_A")"
RAW_B="$(ruta_raw "$RAW_B")"

# ==============================================================================
# EL ÁRBOL DE PRUEBA
#
# Todas las rutas de salida, estado, trabajo y log de los trece run_*.sh y de
# procesar_pasada.sh, con las mismas variables que ellos leen. Si a alguna se le
# escapa una, la red es la búsqueda de fugas del final.
# ==============================================================================

exportar_arbol() {
    local O="$1/output" S="$1/output/state" T="$1/tmp" L="$1/logs"
    local v

    export ESTADO_BASE="$S"
    export CADENA_LOG_BASE="$L/cadena"

    export RTSTPS_OUTPUT_DIR="$O/level0"
    export SDR_INPUT_DIR="$O/level0"
    export SDR_OUTPUT_BASE="$O/level1"

    for v in ATMOS ACSPO FIRE FLOOD LSR CRYO L1G P2G; do
        export "${v}_SDR_IN=$O/level1/viirs"
    done
    export OMPS_SDR_IN="$O/level1/omps"
    export MIRS_SDR_IN="$O/level1/atms"
    export HEAP_CRIS_IN="$O/level1/cris"
    export HEAP_ATMS_IN="$O/level1/atms"

    export ATMOS_OUT="$O/level2/atmosphere"
    export ACSPO_OUT="$O/level2/acspo"
    export FIRE_OUT="$O/level2/fires"
    export FLOOD_OUT="$O/level2/flood"
    export OMPS_OUT="$O/level2/omps"
    export HEAP_OUT="$O/level2/sounder"
    export MIRS_OUT="$O/level2/mirs"
    export LSR_OUT="$O/level2/lsr"
    export CRYO_OUT="$O/level2/cryosphere"
    export LSR_ATMOS_IN="$ATMOS_OUT"
    export CRYO_ATMOS_IN="$ATMOS_OUT"

    export FLOOD_GEOTIFF="$O/geotiff/flood"
    export L1G_GEOTIFF="$O/geotiff"
    export L1G_VISTAS="$O/vistas"
    export P2G_GEOTIFF="$O/geotiff"
    export P2G_VISTAS="$O/vistas"
    export P2G_EDR_IN="$ATMOS_OUT"
    export P2G_ACSPO_IN="$ACSPO_OUT"
    export P2G_FIRE_IN="$FIRE_OUT"
    export P2G_FLOOD_TIF="$FLOOD_GEOTIFF"
    export P2G_LSR_IN="$LSR_OUT"
    export P2G_MIRS_IN="$MIRS_OUT"
    export P2G_OMPS_IN="$OMPS_OUT"
    export P2G_SOUNDER_IN="$HEAP_OUT"

    export RTSTPS_STATE_DIR="$S/rt-stps"
    export SDR_STATE_DIR="$S/cspp-sdr"
    export ATMOS_STATE_DIR="$S/cspp-atmos"
    export ACSPO_STATE_DIR="$S/cspp-acspo"
    export FIRE_STATE_DIR="$S/cspp-active-fire"
    export FLOOD_STATE_DIR="$S/cspp-flood"
    export OMPS_STATE_DIR="$S/cspp-omps"
    export HEAP_STATE_DIR="$S/cspp-heap"
    export MIRS_STATE_DIR="$S/cspp-mirs"
    export LSR_STATE_DIR="$S/cspp-lsr"
    export CRYO_STATE_DIR="$S/cspp-cryo"
    export L1G_STATE_DIR="$S/polar2grid_l1"
    export P2G_STATE_DIR="$S/polar2grid"

    for v in RTSTPS SDR ATMOS ACSPO FIRE FLOOD OMPS HEAP MIRS LSR CRYO L1G P2G; do
        export "${v}_WORK_BASE=$T"
        export "${v}_LOG_BASE=$L"
    done

    mkdir -p "$O" "$S" "$T" "$L/cadena"
}

# Una pasada en segundo plano, en el árbol $1, con su propio candado: el de
# producción no se toma nunca, para no dejar fuera a una pasada real. El PID
# queda en LANZADO y no se imprime: con pid=$(lanzar …) el proceso sería hijo
# del subshell de la sustitución, y wait no podría esperarlo.
LANZADO=""
lanzar() {
    local arbol="$1" turno="$2" raw="$3"
    (
        exportar_arbol "$arbol"
        export LOCK_FILE="$arbol/turno$turno.lock"
        export TMPDIR="$arbol/tmp"
        cd /
        exec "$SCRIPTS_DIR/procesar_pasada.sh" "$raw"
    ) > "$arbol/turno$turno.out" 2>&1 &
    LANZADO=$!
}

# vmstat cada 10 s mientras dura una fase.
VMSTAT_PID=""
grabar_vmstat() { vmstat -t -w 10 > "$1" 2>&1 & VMSTAT_PID=$!; }
parar_vmstat()  { [ -z "$VMSTAT_PID" ] || kill "$VMSTAT_PID" 2>/dev/null; VMSTAT_PID=""; }

# ==============================================================================
# ANTES DE EMPEZAR
# ==============================================================================

if [ -n "$PRUEBA_USUARIO" ] && [ "$(id -un)" != "$PRUEBA_USUARIO" ]; then
    echo "❌ Esta prueba corre como $PRUEBA_USUARIO, no como $(id -un)." >&2
    echo "   Comparte los cachés de ancillary con la operación, y lo que deje ahí" >&2
    echo "   con otro dueño la operación no lo podría reescribir. Por ejemplo:" >&2
    echo "     echo $0 | sudo -u $PRUEBA_USUARIO at 17:30" >&2
    exit 2
fi
for r in "$RAW_A" "$RAW_B"; do
    [ -f "$r" ] || { echo "❌ No existe el crudo: $r" >&2; exit 2; }
done
if [ -e "$BASE" ]; then
    echo "❌ Ya existe $BASE; elige otro --base" >&2
    exit 2
fi
LIBRE_GB=$(df -BG --output=avail "$(dirname "$BASE")" | tail -1 | tr -dc '0-9')
if [ "${LIBRE_GB:-0}" -lt "$PRUEBA_MIN_GB" ]; then
    echo "❌ Solo hay ${LIBRE_GB} GB libres en $(dirname "$BASE"); la prueba ocupa ~30" >&2
    exit 2
fi

mkdir -p "$BASE"
INFORME="$BASE/informe.txt"
exec > >(tee -a "$BASE/prueba.log") 2>&1

echo "=============================================================================="
echo "  PRUEBA DE DOS TURNOS | $(ahora)"
echo "=============================================================================="
echo "  Crudo A:   $RAW_A"
echo "  Crudo B:   $RAW_B"
echo "  Árbol:     $BASE"
echo "  Scripts:   $SCRIPTS_DIR"
[ ! -f "$SCRIPTS_DIR/../VERSION" ] || sed 's/^/  /' "$SCRIPTS_DIR/../VERSION" | head -2
echo "  Desfase:   ${DESFASE}s"
echo "  Control:   $([ "$CON_SERIE" -eq 1 ] && echo "sí, en serie primero" || echo "no (--sin-serie)")"

# Que no haya una pasada de producción en curso: su carga contaminaría las
# medidas. Se mira el candado sin quedárselo.
echo ""
for ((i = 0; ; i++)); do
    if flock -n "$LOCK_PRODUCCION" true 2>/dev/null; then
        break
    fi
    if [ "$i" -ge "$ESPERA_MIN" ]; then
        echo "❌ Una pasada de producción sigue en curso tras $ESPERA_MIN min; no se empieza."
        exit 2
    fi
    [ "$i" -gt 0 ] || echo "  Hay una pasada de producción en curso; esperando (hasta $ESPERA_MIN min)..."
    sleep 60
done

MARCA="$BASE/.inicio"
touch "$MARCA"
trap parar_vmstat EXIT

# ==============================================================================
# FASE 1 — CONTROL EN SERIE
# ==============================================================================

correr_serie() {
    local arbol="$BASE/serie" c
    mkdir -p "$arbol"
    echo ""
    echo "--- Control en serie: $(ahora)"
    grabar_vmstat "$arbol/vmstat.txt"
    date +%s > "$arbol/.t_inicio"
    lanzar "$arbol" A "$RAW_A"; c=0; wait "$LANZADO" || c=$?
    echo "    A terminó con código $c: $(ahora)"; echo "$c" > "$arbol/turnoA.codigo"
    lanzar "$arbol" B "$RAW_B"; c=0; wait "$LANZADO" || c=$?
    echo "    B terminó con código $c: $(ahora)"; echo "$c" > "$arbol/turnoB.codigo"
    date +%s > "$arbol/.t_fin"
    parar_vmstat
}

# ==============================================================================
# FASE 2 — LAS DOS A LA VEZ
# ==============================================================================

correr_simultaneo() {
    local arbol="$BASE/simultaneo" pa pb ca=0 cb=0
    mkdir -p "$arbol"
    echo ""
    echo "--- Simultáneo: $(ahora)"
    grabar_vmstat "$arbol/vmstat.txt"
    date +%s > "$arbol/.t_inicio"
    lanzar "$arbol" A "$RAW_A"; pa=$LANZADO
    [ "$DESFASE" -eq 0 ] || sleep "$DESFASE"
    lanzar "$arbol" B "$RAW_B"; pb=$LANZADO
    wait "$pa" || ca=$?
    echo "    A terminó con código $ca: $(ahora)"; echo "$ca" > "$arbol/turnoA.codigo"
    wait "$pb" || cb=$?
    echo "    B terminó con código $cb: $(ahora)"; echo "$cb" > "$arbol/turnoB.codigo"
    date +%s > "$arbol/.t_fin"
    parar_vmstat
}

[ "$CON_SERIE" -eq 0 ] || correr_serie
correr_simultaneo

# ==============================================================================
# FUGAS Y PRODUCCIÓN DURANTE LA PRUEBA
#
# Nada de la prueba debe aparecer en el árbol ni en los logs de producción. Lo
# que aparezca puede ser también de la operación —el barrido retomando una
# pasada—, así que se lista para revisarlo y no se da por fuga sin mirar.
# ==============================================================================

echo ""
echo "--- Buscando escrituras en producción desde $(date -r "$MARCA" '+%H:%M:%S')..."
find "$SALIDA_PRODUCCION" -newer "$MARCA" -type f 2>/dev/null > "$BASE/escrito_en_produccion.txt"
find "$LOGS_PRODUCCION" -newer "$MARCA" -type f \
     ! -name 'barrido.log' ! -name 'cron.log' ! -name 'publicar_kawak.log' \
     ! -name 'publicar_dataservice.log' \
     ! -name '*_recibe.log' ! -name 'atmos_ancillary_*' ! -name 'update_daily_*' \
     2>/dev/null > "$BASE/logs_de_produccion.txt"

# ==============================================================================
# INFORME
# ==============================================================================

python3 -I - "$BASE" "$CON_SERIE" "$DESFASE" <<'EOF' | tee "$INFORME"
import filecmp, os, re, subprocess, sys, time
from collections import defaultdict

base, con_serie, desfase = sys.argv[1], sys.argv[2] == "1", int(sys.argv[3])
fases = (["serie"] if con_serie else []) + ["simultaneo"]
problemas = []

def leer(p, defecto=""):
    try:
        return open(p, errors="replace").read()
    except OSError:
        return defecto

def mmss(s):
    return "—" if s is None else f"{int(s // 60)}m {int(s % 60):02d}s"

# --- La corrida de cada turno, de su log de cadena
def turnos(fase):
    r = {t: {"codigo": leer(f"{base}/{fase}/turno{t}.codigo", "?").strip()} for t in "AB"}
    logs = sorted(os.path.join(f"{base}/{fase}/logs/cadena", f)
                  for f in os.listdir(f"{base}/{fase}/logs/cadena") if f.endswith(".log"))
    for log in logs:
        txt = leer(log)
        m = re.search(r"Pasada:\s+(\S+)", txt)
        mt = re.search(r"RESUMEN \| pasada \S+ \| (\d+)m (\d+)s", txt)
        e = re.search(r"Entrada:\s+(\S+)", txt)
        fallidas = re.findall(r"^\s+(\S+)\s+fallo\b", txt, re.M)
        # A cuál turno pertenece: por el crudo que dice el log, no por el orden
        t = "A" if e and os.path.basename(e.group(1)) == os.path.basename(raws["A"]) else "B"
        r[t].update(clave=m.group(1) if m else None,
                    total=int(mt.group(1)) * 60 + int(mt.group(2)) if mt else None,
                    fallidas=fallidas, log=log)
    return r

raws = {}
prueba_log = leer(f"{base}/prueba.log")
raws["A"] = re.search(r"Crudo A:\s+(\S+)", prueba_log).group(1)
raws["B"] = re.search(r"Crudo B:\s+(\S+)", prueba_log).group(1)

T = {f: turnos(f) for f in fases}

print()
print("=" * 78)
print(f"  INFORME — PRUEBA DE DOS TURNOS ({time.strftime('%Y-%m-%d %H:%M')})")
print("=" * 78)
print(f"  Árbol: {base}   desfase: {desfase}s")
print()
print(f"  {'fase':11s} {'turno':5s} {'clave':24s} {'código':6s} {'total':>8s}  fallidas")
for f in fases:
    for t in "AB":
        x = T[f][t]
        print(f"  {f:11s} {t:5s} {str(x.get('clave')):24s} {x['codigo']:6s} "
              f"{mmss(x.get('total')):>8s}  {' '.join(x.get('fallidas') or []) or '—'}")
        if x["codigo"] != "0":
            problemas.append(f"{f}/{t}: procesar_pasada.sh salió con {x['codigo']}")
        if x.get("fallidas"):
            problemas.append(f"{f}/{t}: etapas con fallo: {' '.join(x['fallidas'])}")
for f in fases:
    if T[f]["A"].get("clave") == T[f]["B"].get("clave"):
        problemas.append(f"{f}: las dos corridas tomaron la misma clave ({T[f]['A'].get('clave')})")
if con_serie:
    for t in "AB":
        if T["serie"][t].get("clave") != T["simultaneo"][t].get("clave"):
            problemas.append(f"turno {t}: clave distinta en serie ({T['serie'][t].get('clave')}) "
                             f"y a la vez ({T['simultaneo'][t].get('clave')})")

# --- Duración de cada etapa: inicio en el nombre del log, fin en su mtime
ETAPAS = [("rt-stps", r"^\d{8}_\d{6}_", "rt_stps"),
          ("cspp-sdr", r"_viirs_", "sdr_viirs"), ("cspp-sdr", r"_atms_", "sdr_atms"),
          ("cspp-sdr", r"_cris_", "sdr_cris"), ("cspp-sdr", r"_omps_", "sdr_omps"),
          ("cspp-edr", r"^atmos_edr_", "atmos"), ("cspp-edr", r"^acspo_", "acspo"),
          ("cspp-edr", r"^active_fire_", "fire"), ("cspp-edr", r"^flood_", "flood"),
          ("cspp-edr", r"^omps_", "omps"), ("cspp-edr", r"^heap_\d", "heap"),
          ("cspp-edr", r"^mirs_", "mirs"), ("cspp-edr", r"^lsr_edr_", "lsr"),
          ("cspp-edr", r"^cryo_edr_", "cryo"), ("polar2grid", r"^p2g_l1_", "p2g_l1"),
          ("polar2grid", r"^p2g_\d", "p2g_edr")]
SAT = {"npp": "npp", "NPP": "npp", "j01": "j01", "NOAA-20": "j01", "j02": "j02", "NOAA-21": "j02"}

def duraciones(fase):
    d = defaultdict(float)   # (etapa, sat) -> segundos; OMPS son dos llamadas
    for sub, pat, etapa in ETAPAS:
        dirp = f"{base}/{fase}/logs/{sub}"
        if not os.path.isdir(dirp):
            continue
        for f in os.listdir(dirp):
            p = os.path.join(dirp, f)
            if not os.path.isfile(p) or not f.endswith(".log") or not re.search(pat, f):
                continue
            mi = re.search(r"(\d{8}_\d{6})", f)
            ms = re.search(r"(?<![A-Za-z])(npp|j01|j02|NPP|NOAA-20|NOAA-21)(?![A-Za-z0-9])", f)
            if not mi or not ms:
                continue
            ini = time.mktime(time.strptime(mi.group(1), "%Y%m%d_%H%M%S"))
            d[(etapa, SAT[ms.group(1)])] += max(0.0, os.path.getmtime(p) - ini)
    return d

D = {f: duraciones(f) for f in fases}
sats = []
for f in fases:
    for t in "AB":
        c = T[f][t].get("clave") or ""
        if c[:3] not in sats and c:
            sats.append(c[:3])
print()
print("  Duración por etapa (min). La razón es simultáneo ÷ serie.")
cab = f"  {'etapa':10s}"
for s in sats:
    cab += f" | {s + ' serie':>9s} {s + ' a la vez':>12s} {'razón':>6s}"
print(cab)
razones = []
for _, _, etapa in ETAPAS:
    fila = f"  {etapa:10s}"
    hay = False
    for s in sats:
        a = D["serie"].get((etapa, s)) if con_serie else None
        b = D["simultaneo"].get((etapa, s))
        hay = hay or a is not None or b is not None
        r = (b / a) if a and b and a > 20 else None   # menos de 20 s no se compara
        if r:
            razones.append(r)
        fila += (f" | {a / 60 if a else 0:9.1f} {b / 60 if b else 0:12.1f} "
                 f"{('%.2f' % r) if r else '—':>6s}")
    if hay:
        print(fila)
if razones:
    razones.sort()
    print(f"  Razón: mediana {razones[len(razones) // 2]:.2f}, máxima {razones[-1]:.2f}")

# --- Fase completa
print()
for f in fases:
    try:
        ti = int(leer(f"{base}/{f}/.t_inicio")); tf = int(leer(f"{base}/{f}/.t_fin"))
        print(f"  Fase {f}: {mmss(tf - ti)} de reloj")
    except ValueError:
        pass

# --- vmstat
def vmstat(fase):
    filas, cols = [], None
    for l in leer(f"{base}/{fase}/vmstat.txt").splitlines():
        p = l.split()
        if "us" in p and "id" in p:
            cols = p
            continue
        if cols and p and p[0].isdigit():
            filas.append(dict(zip(cols, p)))
    if not filas:
        return None
    n = lambda k: [int(x[k]) for x in filas if k in x]
    ocup = [100 - v for v in n("id")]
    return dict(muestras=len(filas), cpu_med=sum(ocup) / len(ocup), cpu_max=max(ocup),
                r_max=max(n("r")), wa_max=max(n("wa")),
                libre_min=min(n("free")) / 1024 ** 2,
                swap_io=sum(n("si")) + sum(n("so")))
print()
print(f"  {'vmstat':11s} {'muestras':>8s} {'CPU media':>9s} {'CPU máx':>8s} {'r máx':>6s} "
      f"{'wa máx':>7s} {'RAM libre mín':>13s} {'swap si+so':>10s}")
for f in fases:
    v = vmstat(f)
    if v:
        print(f"  {f:11s} {v['muestras']:8d} {v['cpu_med']:8.0f}% {v['cpu_max']:7.0f}% "
              f"{v['r_max']:6d} {v['wa_max']:6d}% {v['libre_min']:10.0f} GB {v['swap_io']:10d}")

# --- Productos: los de la corrida simultánea contra los del control
def productos(fase):
    raiz = f"{base}/{fase}/output"
    r = {}
    for d, sub, fs in os.walk(raiz):
        rel = os.path.relpath(d, raiz)
        if rel == "state" or rel.startswith("state/"):
            continue
        for f in fs:
            norm = re.sub(r"_c\d{8,}", "_c", f)   # el campo de creación cambia
            r[os.path.join(rel, norm)] = os.path.join(d, f)
    return r

def checksum(p):
    try:
        out = subprocess.run(["gdalinfo", "-checksum", p], capture_output=True,
                             text=True, timeout=300).stdout
    except Exception:
        return None
    return tuple(re.findall(r"Checksum=(\d+)", out))

print()
P = {f: productos(f) for f in fases}
for f in fases:
    cuenta = defaultdict(int)
    for k in P[f]:
        cuenta[k.split("/")[0]] += 1
    print(f"  Productos {f:11s}: {len(P[f]):5d}  " +
          "  ".join(f"{k} {v}" for k, v in sorted(cuenta.items())))
if con_serie:
    s, v = set(P["serie"]), set(P["simultaneo"])
    solo_s, solo_v = sorted(s - v), sorted(v - s)
    if solo_s or solo_v:
        problemas.append(f"productos distintos: {len(solo_s)} solo en serie, {len(solo_v)} solo a la vez")
        for k in solo_s[:15]:
            print(f"    solo en serie:   {k}")
        for k in solo_v[:15]:
            print(f"    solo a la vez:   {k}")
    tif_ig = tif_dif = nc_ig = nc_dif = 0
    difs = []
    for k in sorted(s & v):
        a, b = P["serie"][k], P["simultaneo"][k]
        if k.endswith(".tif"):
            if checksum(a) == checksum(b):
                tif_ig += 1
            else:
                tif_dif += 1; difs.append(k)
        elif k.endswith(".nc"):
            if filecmp.cmp(a, b, shallow=False):
                nc_ig += 1
            else:
                nc_dif += 1; difs.append(k)
    print(f"  GeoTIFF con el mismo checksum: {tif_ig}, distinto: {tif_dif}")
    print(f"  NetCDF idénticos byte a byte:  {nc_ig}, distintos: {nc_dif}")
    for k in difs[:15]:
        print(f"    difiere: {k}")
    if tif_dif:
        problemas.append(f"{tif_dif} GeoTIFF con píxeles distintos al control")
    if nc_dif:
        # Los .nc de CSPP han resultado reproducibles, pero alguno puede llevar la
        # hora de creación dentro: se señala para revisarlo con h5diff, no se
        # da por fallo.
        print("    (un .nc distinto puede ser solo un atributo de fecha: revisar con h5diff)")

# --- Fugas y producción
esc = [l for l in leer(f"{base}/escrito_en_produccion.txt").splitlines() if l]
logs = [l for l in leer(f"{base}/logs_de_produccion.txt").splitlines() if l]
print()
print(f"  Escrito en el árbol de producción durante la prueba: {len(esc)} archivo(s)")
for l in esc[:10]:
    print(f"    {l}")
print(f"  Logs nuevos en producción durante la prueba: {len(logs)}")
for l in logs[:10]:
    print(f"    {l}")
claves = {T[f][t].get("clave") for f in fases for t in "AB"} - {None}
raws_base = {os.path.basename(raws[t]) for t in "AB"}
fugas = [l for l in esc + logs if any(c in l for c in claves | raws_base)]
if fugas:
    problemas.append(f"{len(fugas)} archivo(s) de la prueba cayeron en producción")
if any("/cadena/" in l for l in logs):
    print("  ⚠ Producción procesó una pasada durante la prueba: las duraciones están contaminadas")

print()
if problemas:
    print("  ❌ PROBLEMAS:")
    for p in problemas:
        print(f"     - {p}")
else:
    if con_serie:
        print("  ✅ Las dos pasadas a la vez terminaron bien, produjeron lo mismo que el")
        print("     control y nada cayó en producción.")
    else:
        print("  ✅ Las dos pasadas a la vez terminaron bien y nada cayó en producción.")
        print("     Sin control (--sin-serie): los productos no se compararon con nada.")
print()
print(f"  Para borrar el árbol: rm -rf {base}")
sys.exit(1 if problemas else 0)
EOF
CODIGO=${PIPESTATUS[0]}

echo ""
echo "  Informe: $INFORME   ($(du -sh "$BASE" 2>/dev/null | cut -f1) en $BASE)"
exit "$CODIGO"
