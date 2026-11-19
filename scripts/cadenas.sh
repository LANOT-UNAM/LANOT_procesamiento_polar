#!/bin/bash
# ==============================================================================
# cadenas.sh — qué satélite es un crudo, según config/cadenas.tsv.
#
# No se ejecuta: se carga con `source` desde recibe.sh, run_rt_stps.sh,
# run_metop_l1.sh y barrer_pendientes.sh, para que decidan con la misma tabla.
#
#   consultar_cadena <ruta_del_crudo>
#
# Imprime "<satelite> <xml>" y devuelve:
#   0  rama JPSS: lo procesa RT-STPS con ese xml
#   4  rama METOP: lo procesa run_metop_l1.sh (xml es "-")
#   1  no lo procesa esta cadena (xml es "-")
#   2  la tabla no lo conoce: cadena sin fila, o nombre sin chainN
#   3  no se puede leer la tabla
#
# El 4 es un código aparte, y no un 0 con otra salida, a propósito: todo lo
# escrito antes de METOP lee "0 = a RT-STPS", y un crudo de METOP que llegara a
# RT-STPS saldría en 0 sin decodificar nada (ver run_rt_stps.sh).
#
# La fila se elige por la hora de modificación del crudo, así que hace falta la
# ruta y no solo el nombre (ver el encabezado de la tabla).
#
# Variables de entorno:
#   CADENAS_TSV   La tabla (def. <scripts>/../config/cadenas.tsv)
# ==============================================================================

CADENAS_TSV="${CADENAS_TSV:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/../config/cadenas.tsv}"

consultar_cadena() {
    local ruta="$1"
    local nombre cadena mtime
    local c desde sat tele xml rama t
    local mejor_t=-1 mejor_sat="" mejor_xml="" mejor_rama=""

    nombre="$(basename "$ruta")"

    # Nombres que no vienen de la antena (pruebas a mano): se reconoce el
    # satélite por su nombre, como antes de la tabla.
    if [[ ! "$nombre" =~ ^chain([0-9]+)- ]]; then
        if   [[ "$nombre" =~ j02 ]] || [[ "$nombre" =~ noaa21 ]]; then echo "NOAA-21 jpss2.xml"; return 0
        elif [[ "$nombre" =~ j01 ]] || [[ "$nombre" =~ noaa20 ]]; then echo "NOAA-20 jpss1.xml"; return 0
        elif [[ "$nombre" =~ npp ]];                               then echo "NPP npp.xml";       return 0
        fi
        return 2
    fi
    cadena="${BASH_REMATCH[1]}"

    if [ ! -r "$CADENAS_TSV" ]; then
        echo "ERROR: no se puede leer la tabla de cadenas: $CADENAS_TSV" >&2
        return 3
    fi

    mtime="$(stat -c %Y "$ruta" 2>/dev/null || date +%s)"

    while read -r c desde sat tele xml rama; do
        [ -n "$c" ] && [ "${c:0:1}" != "#" ] || continue
        [ "$c" = "$cadena" ] || continue
        if [ "$desde" = "-" ]; then
            t=0
        elif ! t="$(date -u -d "$desde" +%s 2>/dev/null)"; then
            echo "ERROR: fecha ilegible en $CADENAS_TSV: $desde" >&2
            return 3
        fi
        if [ "$t" -le "$mtime" ] && [ "$t" -gt "$mejor_t" ]; then
            mejor_t="$t"; mejor_sat="$sat"; mejor_xml="$xml"; mejor_rama="$rama"
        fi
    done < "$CADENAS_TSV"

    [ -n "$mejor_sat" ] || return 2

    echo "$mejor_sat $mejor_xml"
    case "$mejor_rama" in
        jpss)  [ "$mejor_xml" != "-" ] || { echo "ERROR: $CADENAS_TSV: rama jpss sin xml para chain$cadena" >&2; return 3; }
               return 0 ;;
        metop) return 4 ;;
        -)     return 1 ;;
        *)     echo "ERROR: $CADENAS_TSV: rama desconocida '$mejor_rama' para chain$cadena" >&2
               return 3 ;;
    esac
}
