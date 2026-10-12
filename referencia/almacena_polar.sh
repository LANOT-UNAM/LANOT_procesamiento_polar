#!/bin/bash
# ==============================================================================
# Script: almacena_polar.sh (Versión 3.3 - Corrección de Estadísticas y Scope)
# ==============================================================================

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
inputdir="$OUTPUT_DIR/$sat"
depotdir="$DEPOT/polar"
MANIFEST_FILE=$(mktemp /tmp/manifest_XXXXXX.txt)

files_success=0
files_failed=0
tars_created=0

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

    week=$(( (10#$jday / 7) + 1 )); week=$(printf "%02d" "$week")
    destdir="$depotdir/$sat/$sensor/$level/$year/$week"
    full_tar_path="$destdir/$destfile_base-$year$jday.tar"

    echo "$full_tar_path|$filepath" >> "$MANIFEST_FILE"
    total_found=$((total_found + 1))
    [[ "$LIMIT" -gt 0 && "$total_found" -ge "$LIMIT" ]] && break
done < <(find "$inputdir" -type f \( -name "*.h5" -o -name "*.hdf" -o -name "*.PDS" -o -name "*.nc" -o -name "*.tif" \) | sort -r)

echo "Archivos detectados para procesar: $total_found"

# --- [2/3] Empaquetado (Corregido para preservar variables) ---
if [ "$total_found" -gt 0 ]; then
    echo "--- [2/3] Iniciando empaquetado hacia Lustre ---"
    
    # IMPORTANTE: Usamos < <(...) para evitar el subshell de la tubería |
    while read -r target_tar; do
        [ -z "$target_tar" ] && continue
        
        list_file=$(mktemp /tmp/tar_list_XXXXXX.txt)
        grep "^$target_tar|" "$MANIFEST_FILE" | cut -d'|' -f2 > "$list_file"
        batch_count=$(wc -l < "$list_file")
        
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY-RUN] $target_tar ($batch_count archivos)"
            files_success=$((files_success + batch_count))
        else
            echo -n "[$(date +'%T')] $target_tar ($batch_count)... "
            mkdir -p "$(dirname "$target_tar")"
            
            if tar cf "$target_tar" --no-recursion --ignore-failed-read -T "$list_file" 2>/dev/null; then
                # Borramos los archivos de la lista
                while read -r f_to_del; do rm -f "$f_to_del"; done < "$list_file"
                files_success=$((files_success + batch_count))
                tars_created=$((tars_created + 1))
                echo "OK."
            else
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
echo "Paquetes .tar generados en Lustre: $tars_created"
echo "----------------------------------------------------------------"

rm -f "$MANIFEST_FILE"
