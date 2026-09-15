#!/bin/bash
#
# make sure a process is always running.
#
# Alejandro Aguilar Sierra, asierra@unam.mx, LANOT, UNAM

process=watchpolar.sh
makerun="/home/teradm/watchpolar/watchpolar.sh"

if ps ax | grep -v grep | grep $process > /dev/null
then
    exit
else
    $makerun &
fi

exit

