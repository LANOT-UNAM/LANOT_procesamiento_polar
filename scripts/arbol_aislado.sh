#!/bin/bash
# ==============================================================================
# arbol_aislado.sh — biblioteca: redirige toda la cadena a un árbol propio.
#
#   source arbol_aislado.sh
#   exportar_arbol /data/tmp/mi_prueba
#
# Exporta las rutas de salida, estado, trabajo y log de los run_*.sh y de
# procesar_pasada.sh, con las mismas variables que ellos leen, para correr una
# pasada sin tocar /data/output ni /var/log/lanot. Los cachés de ancillary NO se
# redirigen: cada prueba decide (prueba_dos_turnos.sh los comparte a propósito;
# prueba_restauracion.sh los aísla). Tampoco el candado ni TMPDIR.
#
# La sacó de prueba_dos_turnos.sh el 2026-11-21, para que la prueba de
# restauración use exactamente el mismo aislamiento. Al agregar una variable de
# salida a un run_*.sh, agregarla aquí: si se escapa, la red es la búsqueda de
# fugas de cada prueba. OMPS TOS (2026-11-14) se había escapado: lo agregó la
# misma revisión.
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

    export ATMOS_OUT="$O/level2/atmos"
    export ACSPO_OUT="$O/level2/acspo"
    export FIRE_OUT="$O/level2/fires"
    export FLOOD_OUT="$O/level2/flood"
    export OMPS_OUT="$O/level2/omps"
    export HEAP_OUT="$O/level2/sounder"
    export MIRS_OUT="$O/level2/mirs"
    export LSR_OUT="$O/level2/lsr"
    export CRYO_OUT="$O/level2/cryo"
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
    export OMPS_TOS_STATE_DIR="$S/cspp-omps-tos"
    export HEAP_STATE_DIR="$S/cspp-heap"
    export MIRS_STATE_DIR="$S/cspp-mirs"
    export LSR_STATE_DIR="$S/cspp-lsr"
    export CRYO_STATE_DIR="$S/cspp-cryo"
    export L1G_STATE_DIR="$S/polar2grid_l1"
    export P2G_STATE_DIR="$S/polar2grid"

    for v in RTSTPS SDR ATMOS ACSPO FIRE FLOOD OMPS OMPS_TOS HEAP MIRS LSR CRYO L1G P2G; do
        export "${v}_WORK_BASE=$T"
        export "${v}_LOG_BASE=$L"
    done

    mkdir -p "$O" "$S" "$T" "$L/cadena"
}

