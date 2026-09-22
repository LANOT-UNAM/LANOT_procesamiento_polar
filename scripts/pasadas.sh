#!/bin/bash
# ==============================================================================
# pasadas.sh — qué es una pasada, en términos de tiempo.
#
# No se ejecuta: se carga con `source` desde los run_*.sh de pasada y desde
# procesar_pasada.sh, para que todos agrupen y seleccionen igual.
#
# Una pasada es un grupo de archivos de geolocalización (GMTCO, GITCO, GOTCO,
# GCRSO…) del mismo satélite cuyos intervalos se suceden sin un hueco mayor que
# PASADA_HUECO_S. Su clave es satélite, fecha y hora de inicio del grupo:
#
#   j02_d20260922_t204743
#
# Hasta el 2026-09-22 la clave llevaba la órbita del nombre (j02_d20260922_b20040)
# y los archivos se elegían con un glob sobre ella. Ese día CSPP le puso a los
# SDR de VIIRS de dos sobrevuelos de NOAA-21 separados por una órbita —19:06 y
# 20:47— el mismo b20040 (ATMS y OMPS sí numeraron b20041 el segundo, con el
# mismo TLE). La segunda pasada heredó los marcadores de la primera, salió "ya
# estaba" en todo Level 2 y su staging habría mezclado las dos. La órbita queda
# en los nombres, pero ya no decide nada: dos sobrevuelos del mismo satélite
# están separados por ~100 min, y eso sí no lo puede equivocar nadie.
#
# Funciones:
#   intervalo_de <archivo>                     "INI FIN" (AAAAMMDDHHMMSS)
#   listar_pasadas <dir> <geo>                 una línea "CLAVE INI FIN" por pasada
#   resolver_pasada <dir> <geo> [<pedido>]     fija CLAVE, SAT, FECHA, VENTANA_INI,
#                                              VENTANA_FIN, FECHA_NUM, FECHA_SIG
#   archivos_de_pasada <dir> <patrón>          los archivos de la pasada resuelta
#   pasada_que_traslapa <dir> <geo> <sat> <ini> <fin>
#                                              la clave de otro instrumento
#
# Variables de entorno:
#   PASADA_HUECO_S   Hueco que separa dos pasadas, en segundos (def. 1200).
#                    Un corte de recepción dentro de la pasada dura minutos (3
#                    el 2026-09-22); dos pasadas del mismo satélite, ~100.
# ==============================================================================

PASADA_HUECO_S="${PASADA_HUECO_S:-1200}"

# Lee nombres de SDR por la entrada estándar y escribe, por cada uno que tenga la
# forma PREFIJO_sat_dAAAAMMDD_tHHMMSSs_eHHMMSSs_…:
#   sat ini_epoch fin_epoch INI FIN nombre
# Si el fin es menor que el inicio, el archivo cruzó la medianoche. gawk (mktime
# y strftime con UTC): es el awk de tahan (Rocky) y de bucefalo.
_intervalos() {
    awk -F_ '
        NF >= 6 && $3 ~ /^d[0-9]{8}$/ && $4 ~ /^t[0-9]{6}/ && $5 ~ /^e[0-9]{6}/ {
            f  = substr($3, 2)
            ti = substr($4, 2, 6)
            te = substr($5, 2, 6)
            ini = mktime(substr(f,1,4) " " substr(f,5,2) " " substr(f,7,2) " " \
                         substr(ti,1,2) " " substr(ti,3,2) " " substr(ti,5,2), 1)
            fin = mktime(substr(f,1,4) " " substr(f,5,2) " " substr(f,7,2) " " \
                         substr(te,1,2) " " substr(te,3,2) " " substr(te,5,2), 1)
            if (fin < ini) fin += 86400
            print $2, ini, fin, f ti, strftime("%Y%m%d%H%M%S", fin, 1), $0
        }'
}

intervalo_de() {
    local r
    r="$(basename "$1" | _intervalos)"
    [ -n "$r" ] || return 1
    echo "$r" | awk '{ print $4, $5 }'
}

# listar_pasadas <dir> <geo>
#
# Las pasadas que hay en <dir>, agrupando los archivos <geo>_*.h5. Una línea por
# pasada, "CLAVE INI FIN", ordenadas por satélite y hora. En level1 conviven
# archivos agregados (uno por pasada) y por gránulo (uno cada 30-85 s); con los
# dos sale la misma pasada.
listar_pasadas() {
    local dir="$1" geo="$2"
    find "$dir" -maxdepth 1 -name "${geo}_*.h5" -printf '%f\n' 2>/dev/null |
        _intervalos | sort -k1,1 -k2,2n |
        awk -v hueco="$PASADA_HUECO_S" '
            function emitir() {
                if (sat != "")
                    printf "%s_d%s_t%s %s %s\n", sat, substr(ini,1,8), substr(ini,9,6), ini, fin
            }
            $1 != sat || $2 > fin_ep + hueco {
                emitir(); sat = $1; ini = $4; fin = $5; fin_ep = $3; next
            }
            $3 > fin_ep { fin_ep = $3; fin = $5 }
            END { emitir() }'
}

# Fija las variables de la pasada a partir de su línea de listar_pasadas.
_fijar_pasada() {
    read -r CLAVE VENTANA_INI VENTANA_FIN <<< "$1"
    SAT="${CLAVE%%_*}"
    FECHA_NUM="${VENTANA_INI:0:8}"
    FECHA_SIG="${VENTANA_FIN:0:8}"
    FECHA="d${FECHA_NUM}"
}

# resolver_pasada <dir> <geo> [<pedido>]
#
# Sin pedido, la pasada del archivo <geo> modificado más recientemente. Con él,
# la única pasada cuya clave lo contenga: la completa (j02_d20260922_t204743) o
# cualquier trozo que la identifique ("t2047", "204743"). Si ninguna clave lo
# contiene, se busca en los NOMBRES de los archivos, y así siguen sirviendo las
# claves con órbita de antes (j01_d20260811_b45236) y trozos como "b45236": si
# esa órbita la llevan dos pasadas, es ambiguo y se dice. Un nombre de archivo
# completo (….h5) da la pasada que lo contiene.
#
# Deja CLAVE, SAT, FECHA (dAAAAMMDD), VENTANA_INI, VENTANA_FIN, FECHA_NUM y
# FECHA_SIG (fechas de inicio y fin de la ventana). Código 0 con CLAVE vacía si
# no hay ningún archivo; 1 si el pedido no identifica una sola pasada.
resolver_pasada() {
    local dir="$1" geo="$2" pedido="${3:-}"
    local reciente sat ini linea glob
    local -a pasadas=() coinciden=()

    CLAVE=""; SAT=""; FECHA=""; VENTANA_INI=""; VENTANA_FIN=""; FECHA_NUM=""; FECHA_SIG=""

    mapfile -t pasadas < <(listar_pasadas "$dir" "$geo")
    [ "${#pasadas[@]}" -gt 0 ] || [ -n "$pedido" ] || return 0

    if [ -z "$pedido" ]; then
        reciente=$(find "$dir" -maxdepth 1 -name "${geo}_*.h5" -printf '%T@ %f\n' 2>/dev/null |
                       sort -rn | head -1 | cut -d' ' -f2-)
        read -r sat ini < <(echo "$reciente" | _intervalos | awk '{ print $1, $4 }') || return 0
        mapfile -t coinciden < <(_pasadas_que_contienen "$sat" "$ini" "${pasadas[@]}")
        [ "${#coinciden[@]}" -eq 0 ] || _fijar_pasada "${coinciden[0]}"
        return 0
    fi

    for linea in "${pasadas[@]}"; do
        case "${linea%% *}" in *"$pedido"*) coinciden+=("$linea") ;; esac
    done

    # Ninguna clave lo contiene: se busca en los nombres de los archivos.
    if [ "${#coinciden[@]}" -eq 0 ]; then
        if [[ "$pedido" == *.h5 ]]; then
            glob="$(basename "$pedido")"
        elif [[ "$pedido" =~ ^([a-z0-9]+)_d([0-9]{8})_b([0-9]+)$ ]]; then
            glob="${geo}_${BASH_REMATCH[1]}_d${BASH_REMATCH[2]}_*_b${BASH_REMATCH[3]}_*.h5"
        else
            glob="${geo}_*${pedido}*.h5"
        fi
        mapfile -t coinciden < <(
            find "$dir" -maxdepth 1 -name "$glob" -printf '%f\n' 2>/dev/null |
                _intervalos | awk '{ print $1, $4 }' |
                while read -r sat ini; do
                    _pasadas_que_contienen "$sat" "$ini" "${pasadas[@]}"
                done | sort -u)
    fi

    if [ "${#coinciden[@]}" -eq 0 ]; then
        echo "ERROR: Ninguna pasada de $dir coincide con '$pedido'" >&2
        echo "       Disponibles:" >&2
        printf '         %s\n' "${pasadas[@]%% *}" >&2
        return 1
    fi
    if [ "${#coinciden[@]}" -gt 1 ]; then
        echo "ERROR: '$pedido' coincide con más de una pasada; hay que ser más específico:" >&2
        printf '         %s\n' "${coinciden[@]%% *}" >&2
        return 1
    fi

    _fijar_pasada "${coinciden[0]}"
}

# _pasadas_que_contienen <sat> <instante> <línea>…: las líneas de listar_pasadas
# del satélite cuya ventana contiene el instante.
_pasadas_que_contienen() {
    local sat="$1" t="$2" linea c_ini c_fin; shift 2
    for linea in "$@"; do
        read -r _ c_ini c_fin <<< "$linea"
        if [ "${linea%%_*}" = "$sat" ] && [ "$t" -ge "$c_ini" ] && [ "$t" -le "$c_fin" ]; then
            echo "$linea"
        fi
    done
}

# archivos_de_pasada <dir> <patrón>
#
# Las rutas de los archivos <patrón>_<SAT>_d…h5 de <dir> cuyo intervalo se
# traslapa con la ventana de la pasada resuelta. <patrón> es un comodín de find:
# 'GMTCO', 'SVM*', 'SVI0[1-5]' o '*' para todas las bandas. Los de la pasada
# empiezan dentro de la ventana, así que basta mirar las fechas de su inicio y
# de su fin.
archivos_de_pasada() {
    local dir="$1" patron="$2" d
    local -a fechas=("$FECHA_NUM")
    [ "$FECHA_SIG" = "$FECHA_NUM" ] || fechas+=("$FECHA_SIG")
    for d in "${fechas[@]}"; do
        find "$dir" -maxdepth 1 -name "${patron}_${SAT}_d${d}_*.h5" -printf '%f\n' 2>/dev/null
    done | _intervalos |
        awk -v ini="$VENTANA_INI" -v fin="$VENTANA_FIN" -v dir="$dir" \
            '$4 <= fin && $5 >= ini { print dir "/" $6 }' | sort
}

# pasada_que_traslapa <dir> <geo> <sat> <ini> <fin>
#
# La clave de la pasada de otro instrumento (<geo>: GOTCO de OMPS, GCRSO de CrIS)
# que se traslapa con la ventana dada. La órbita tampoco es común entre
# instrumentos —el mismo sobrevuelo es b45236 en VIIRS y b45237 en OMPS—, así que
# esto siempre fue por tiempo. Si se traslapan dos, gana la de más traslape y se
# avisa en stderr. Código 1 si ninguna: el instrumento no dejó datos.
pasada_que_traslapa() {
    local dir="$1" geo="$2" sat="$3" v_ini="$4" v_fin="$5" r
    r="$(listar_pasadas "$dir" "$geo" |
        awk -v sat="$sat" -v ini="$v_ini" -v fin="$v_fin" '
            function ep(s) {
                return mktime(substr(s,1,4) " " substr(s,5,2) " " substr(s,7,2) " " \
                              substr(s,9,2) " " substr(s,11,2) " " substr(s,13,2), 1)
            }
            index($1, sat "_") == 1 && $2 <= fin && $3 >= ini {
                a = ($2 > ini) ? $2 : ini; b = ($3 < fin) ? $3 : fin
                t = ep(b) - ep(a); n++
                todas = todas " " $1
                if (mejor == "" || t > max) { mejor = $1; max = t }
            }
            END {
                if (n > 1) printf "  ⚠ se traslapan %d pasadas (%s); se toma %s\n", n, substr(todas, 2), mejor > "/dev/stderr"
                if (mejor != "") print mejor
            }')"
    [ -n "$r" ] || return 1
    echo "$r"
}
