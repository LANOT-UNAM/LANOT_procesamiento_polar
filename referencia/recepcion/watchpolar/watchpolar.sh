#!/bin/bash
#
# Detecta cuando una imagen raw terminó de ser descargada del satélite
# y la envía a procesamiento con software libre en el servidor
# stratus.
#
# Versión 001 Wed 03 Feb 2021 09:56:52 PM CST	First implementation 
# Version 002 Sat May 29 20:23:31 UTC 2021 	Added cron to keep it running
# Version 003 Thu Mar 13 05:10:36 AM UTC 2025  Separated monitor and copy
#
# Alejandro Aguilar Sierra, asierra@unam.mx, LANOT, UNAM

watchdir=/nexus/data1/passdisk
#  stratus debe tener la llave pública de polaracq y una IP en la red local de polares
logfile=/home/teradm/watchpolar/watchlog.txt

# Nota, nunca usar --outfile porque el while no funcionará
inotifywait -e create -e close_write --timefmt "%Y%m%d-%H:%M:%S" --format "%T %e %f" -m $watchdir|
    while read hora action file; do
	echo "$hora $action $file" >> $logfile
	if [[ "$action" == "CREATE" ]]; then
	    echo "Created $file at $hora" >> $logfile
	elif [[ "$action" == "CLOSE_WRITE,CLOSE" ]]; then
	    echo "Adquired $file at $hora" >> $logfile
	    /home/teradm/watchpolar/copypolar.sh $file & 
	fi	    
    done

