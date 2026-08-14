#!/bin/bash

INPUT_TMP=/data/proc/input/npp/viirs
INPUT_TMP1=/data/proc/input/n20/viirs
WORK_VIIRS=/data/proc/flood/cspp_flood_v1_1_test/work/npp
WORK_VIIRS1=/data/proc/flood/cspp_flood_v1_1_test/work/n20
OUTPUT_LOCAL=/data/output2/npp_jpss/viirs/level2/flood
OUTPUT_PETA=/data2/output/npp_jpss/viirs/level2/flood
OUTPUT_SERVICE=/dataservice/npp-jpss1/viirs/level2/flood
OUTPUT_VISTA_LOCAL=/dataservice/npp-jpss1/viirs/vistas/flood
log=/home/lanotadm/log2

##Procesa NPP VIIRS to Level2 FLOOD

export CSPP_FLOOD_HOME=/data/opt2/FLOOD/CSPP_FLOOD_1_1

export POLAR2GRID_HOME=/data/opt2/POLAR2GRID/polar2grid_v_3_0
export PATH=$PATH:$POLAR2GRID_HOME/bin

lastnppflood=$(ls -t $INPUT_TMP/*.h5|head -1|cut -d '_' -f 3,4|cut -c 1-15)
if [[ ! $lastnppflood == `cat $log/lastnppflood` ]]
then
    echo $lastnppflood > $log/lastnppflood
    cd $WORK_VIIRS
    echo -e "\nInicia proceso L1 a L2 FLOOD NPP VIIRS\n"
    date
    $CSPP_FLOOD_HOME/scripts/cspp_flood.sh $INPUT_TMP
    date
    $CSPP_FLOOD_HOME/scripts/flood2tif.sh *.hdf
    date
    cp -uv *_log.txt $log
    cp -uv *.hdf $OUTPUT_LOCAL
    echo -e "\nDatos L2 FLOOD enviados Local\n"
    cp -uv *.hdf $OUTPUT_SERVICE
    echo -e "\nDatos L2 FLOOD enviados Dataservice\n"
    cp -uv *.hdf $OUTPUT_PETA
    echo -e "\nDatos L2 FLOOD enviados Peta\n"
    cp -uv *.tif $OUTPUT_VISTA_LOCAL
    echo -e "\nFin proceso L1 a L2 FLOOD NPP VIIRS\n"
    date
    rm -rf *
#    rm -f $INPUT_TMP/*
else
    echo -e "\nYa fue procesado el ultimo FLOOD NPP VIIRS $lastnppflood\n"
fi

##Procesa N20 VIIRS to Level2 FLOOD

lastn20flood=$(ls -t $INPUT_TMP1/*.h5|head -1|cut -d '_' -f 3,4|cut -c 1-15)
if [[ ! $lastn20flood == `cat $log/lastn20flood` ]]
then
    echo $lastn20flood > $log/lastn20flood
    cd $WORK_VIIRS1
    echo -e "\nInicia proceso L1 a L2 FLOOD N20 VIIRS\n"
    date
    $CSPP_FLOOD_HOME/scripts/cspp_flood.sh $INPUT_TMP1
    date
    $CSPP_FLOOD_HOME/scripts/flood2tif.sh *.hdf
    date
    cp -uv *.hdf $OUTPUT_LOCAL
    echo -e "\nDatos L2 FLOOD enviados Local\n"
    cp -uv *.hdf $OUTPUT_SERVICE
    echo -e "\nDatos L2 FLOOD enviados Dataservice\n"
    cp -uv *.hdf $OUTPUT_PETA
    echo -e "\nDatos L2 FLOOD enviados Peta\n"
    cp -uv *.tif $OUTPUT_VISTA_LOCAL
    echo -e "\nFin proceso L1 a L2 FLOOD N20 VIIRS\n"
    date
    rm -rf *
#    rm -f $INPUT_TMP1/*
else
    echo -e "\nYa fue procesado el ultimo FLOOD N20 VIIRS $lastn20flood\n"
fi
