#!/bin/bash
# ==============================================================================
# Script: almacena_polar.sh (Versión 3.4 - Tars que solo crecen y días cerrados)
# ==============================================================================
#
# 3.4 (2026-10-12):
#  - tar rf en vez de tar cf. Con cf, si los archivos de una fecha se repartían
#    entre dos corridas, la segunda reescribía el tar y se perdía lo que había
#    guardado la primera, cuyos originales ya estaban borrados del NFS.
#  - Solo se archivan días UTC cerrados: lo de hoy se queda para la corrida
#    siguiente, y lo que llegue tarde de un día ya archivado se anexa a su tar.
#  - Antes de borrar un original se comprueba que esté en el tar; los errores
#    de tar ya no se tiran a /dev/null.
#  - Los miembros se guardan con ruta relativa a / (tar -C /), igual que como
#    quedaban antes al quitarles tar la '/' inicial, para que los anexados
#    tengan la misma forma que los que ya están en los tars.

export TZ=UTC

DRY_RUN=false
LIMIT=0
sat=""
source /home/lanotadm/.bash_aliases

while getopts "s:l:d" opt; do
  case $opt in
    s) sat="$OPTARG" ;;
    l) LIMIT="$OPTARG" ;;
    d) DRY_RUN=true ;;
    *) echo "Uso: $0 -s <satelite> [-l limite] [-d]"; exit 1 ;;
  esac
done

if [ -z "$sat" ]; then echo "Error: Falta satélite -s"; exit 1; fi
if ! mountpoint -q "$DEPOT"; then echo "Error: $DEPOT no montado"; exit 1; fi

start_time=$(date +%s)
hoy=$(date +%Y%j)
inputdir="$OUTPUT_DIR/$sat"
depotdir="$DEPOT/polar"
MANIFEST_FILE=$(mktemp /tmp/manifest_XXXXXX.txt)
trap 'rm -f "$MANIFEST_FILE" /tmp/tar_list_$$_* ' EXIT

files_success=0
files_failed=0
files_today=0
tars_written=0

echo "----------------------------------------------------------------"
echo "INICIO DE RESPALDO: $(date)"
echo "----------------------------------------------------------------"

# --- [1/3] Clasificación ---
total_found=0
while read -r filepath; do
    [ ! -f "$filepath" ] && continue

    IFS='/' read -ra array <<< "$filepath"
    sensor="${array[4]}"
    level="${array[5]}"
    destfile_base="$sat.$sensor"

    if [ "$level" = "level2" ]; then
        filename=$(basename "$filepath")
        product=$(echo "$filename" | cut -d'_' -f1 | sed 's/VIIRS-//' | tr '[:upper:]' '[:lower:]')
        [ -z "${product}" ] && product="all"
        destfile_base="$destfile_base.$product"
    fi

    # Lógica de fechas (Se mantiene la prioridad para evitar error 2020/2025)
    if [[ "$filepath" =~ _d([0-9]{8}) ]]; then
        yymmdd="${BASH_REMATCH[1]}"; year="${yymmdd:0:4}"; jday=$(date -d "$yymmdd" +%j)
    elif [[ "$filepath" =~ ([0-9]{4})([0-9]{2})([0-9]{2})[0-9]{6} ]]; then
        year="${BASH_REMATCH[1]}"; yymmdd="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"; jday=$(date -d "$yymmdd" +%j)
    elif [[ "$filepath" =~ ([0-9]{2})([0-9]{3})[0-9]{6} ]]; then
        year="20${BASH_REMATCH[1]}"; jday="${BASH_REMATCH[2]}"
    else
        continue
    fi
    [ -z "$jday" ] && continue

    # El día en curso todavía puede recibir archivos: se archiva mañana
    if [ "$year$jday" -ge "$hoy" ]; then
        files_today=$((files_today + 1))
        continue
    fi

    week=$(( (10#$jday / 7) + 1 )); week=$(printf "%02d" "$week")
    destdir="$depotdir/$sat/$sensor/$level/$year/$week"
    full_tar_path="$destdir/$destfile_base-$year$jday.tar"

    echo "$full_tar_path|$filepath" >> "$MANIFEST_FILE"
    total_found=$((total_found + 1))
    [[ "$LIMIT" -gt 0 && "$total_found" -ge "$LIMIT" ]] && break
done < <(find "$inputdir" -type f \( -name "*.h5" -o -name "*.hdf" -o -name "*.PDS" -o -name "*.nc" -o -name "*.tif" \) | sort -r)

echo "Archivos detectados para procesar: $total_found"
echo "Archivos del día en curso, para la próxima corrida: $files_today"

# --- [2/3] Empaquetado ---
if [ "$total_found" -gt 0 ]; then
    echo "--- [2/3] Iniciando empaquetado hacia Lustre ---"

    # IMPORTANTE: Usamos < <(...) para evitar el subshell de la tubería |
    while read -r target_tar; do
        [ -z "$target_tar" ] && continue

        # Rutas sin la '/' inicial: así las escribe tar con -C /
        list_file=$(mktemp /tmp/tar_list_$$_XXXXXX)
        awk -F'|' -v t="$target_tar" '$1 == t { sub(/^\/+/, "", $2); print $2 }' "$MANIFEST_FILE" > "$list_file"
        batch_count=$(wc -l < "$list_file")

        if [ "$DRY_RUN" = true ]; then
            accion="nuevo"; [ -f "$target_tar" ] && accion="se anexa"
            echo "[DRY-RUN] $target_tar ($batch_count archivos, $accion)"
            files_success=$((files_success + batch_count))
        else
            echo -n "[$(date +'%T')] $target_tar ($batch_count)... "
            mkdir -p "$(dirname "$target_tar")"

            # rf crea el tar si no existe y, si existe, anexa: nunca reescribe
            if tar rf "$target_tar" -C / --no-recursion --ignore-failed-read -T "$list_file"; then
                # Solo se borra lo que de verdad quedó dentro del tar
                members=$(mktemp /tmp/tar_list_$$_XXXXXX)
                tar tf "$target_tar" | sort -u > "$members"
                ok=0; faltan=0
                while read -r f_rel; do
                    if grep -qxF -- "$f_rel" "$members"; then
                        rm -f "/$f_rel"; ok=$((ok + 1))
                    else
                        faltan=$((faltan + 1))
                    fi
                done < "$list_file"
                rm -f "$members"
                files_success=$((files_success + ok))
                files_failed=$((files_failed + faltan))
                tars_written=$((tars_written + 1))
                if [ "$faltan" -eq 0 ]; then
                    echo "OK."
                else
                    echo "INCOMPLETO: $faltan no quedaron en el tar y no se borran."
                fi
            else
                # Puede haber anexado una parte; los originales se conservan y
                # la próxima corrida los vuelve a anexar (al extraer gana el último)
                files_failed=$((files_failed + batch_count))
                echo "FALLÓ."
            fi
        fi
        rm -f "$list_file"
    # El 'sort -u' aquí garantiza que procesamos cada .tar una sola vez
    done < <(cut -d'|' -f1 "$MANIFEST_FILE" | sort -u)
fi

# --- [3/3] Resumen ---
duration=$(( $(date +%s) - start_time ))
echo "----------------------------------------------------------------"
echo "RESUMEN DE OPERACIÓN:"
echo "Estado: FINALIZADO"
echo "Tiempo: $((duration / 60))m $((duration % 60))s"
echo "Archivos respaldados y borrados de NFS: $files_success"
echo "Archivos fallidos (permanecen en NFS): $files_failed"
echo "Archivos del día en curso (próxima corrida): $files_today"
echo "Paquetes .tar escritos en Lustre: $tars_written"
echo "----------------------------------------------------------------"
