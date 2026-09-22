
#!/bin/bash
#

if [ -z "$1" ]
then
    echo "Usanza:  $0 <archivo raw>"
    exit -1
else
    rawfile=$1
fi

DATE_TIME=$(date -u '+%Y-%m-%d %H:%M:%S')
echo "Procesando $rawfile" 
echo "Fecha $DATE_TIME"
echo "Procesando $rawfile" >> /home/lanotadm/log/polar.log
echo "Fecha $DATE_TIME" >> /home/lanotadm/log/polar.log
#exit 0

# Reenvío a la cadena nueva en tahan. En segundo plano (trap '' HUP hace de
# nohup) para que la copia, hasta 2.4 GB, no retrase a la cadena vieja.
(
    trap '' HUP
    unico="${rawfile}_$(date -u +%Y%m%dT%H%M%S)"
    origen=/data/input/polar/raw/$rawfile
    buzon=/datawork/input/polar
    tam=$(stat -c %s "$origen")

    # Copiar a /datawork: a tmp/ y luego mv a raw/, para que tahan nunca vea un
    # crudo a medio copiar. Se compara el tamaño porque /datawork va montado soft.
    if cp "$origen" "$buzon/tmp/$unico" &&
       [ "$(stat -c %s "$buzon/tmp/$unico")" = "$tam" ] &&
       mv "$buzon/tmp/$unico" "$buzon/raw/$unico"; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S') copiado $rawfile -> $unico"
        # Avisar a tahan/recibe
        ssh -o BatchMode=yes -o ConnectTimeout=20 lanotadm@tahan \
            /opt/lanot/polares/scripts/recibe.sh "$unico"
        echo "$(date -u '+%Y-%m-%d %H:%M:%S') recibe.sh de tahan: código $?"
    else
        echo "$(date -u '+%Y-%m-%d %H:%M:%S') ERROR copiando $rawfile a $buzon"
        rm -f "$buzon/tmp/$unico"
    fi
) < /dev/null >> /home/lanotadm/log/reenvio_polar.log 2>&1 &

# Cadenas de TeraScan desde el 2026-09-21 (system.config de polaracq):
#   1 NOAA-21, 2 NOAA-20, 4 NPP, 5 Aqua, 6 METOP-B/C (AHRPT)
# NOAA-21 y Aqua no pasan por aquí: NOAA-21 solo lo procesa la cadena nueva
# (reenvío de arriba) y Aqua ya no se procesa en ningún sistema. NOAA-15/19 (noaa2 en
# tsom03) no llegan desde agosto de 2025.
if [[ $rawfile =~ ^chain[24]- ]]; then
    nohup /home/lanotadm/bin/cspp.sh $rawfile < /dev/null >& ~/log2/$rawfile.log &
elif [[ $rawfile =~ ^chain6- ]]; then
    nohup /home/lanotadm/bin/metop2.sh $rawfile < /dev/null >& ~/log/$rawfile.log &
fi
