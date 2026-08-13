
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

if [[ $rawfile =~ ^chain[26]-* ]]; then
    nohup /home/lanotadm/bin/cspp.sh $rawfile < /dev/null >& ~/log2/$rawfile.log &
elif [[ $rawfile =~ ^chain4-* ]]; then
    ssh tsom03 nohup /home/lanotadm/bin/noaa2 $rawfile < /dev/null >& ~/log/$rawfile.log &
elif [[ $rawfile =~ ^chain5-* ]]; then
    nohup /home/lanotadm/bin/metop2.sh $rawfile < /dev/null >& ~/log/$rawfile.log &
fi
