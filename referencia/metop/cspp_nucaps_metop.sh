#!/bin/bash

INPUT_AMSUA=/data/output2/noaa_metop/amsua/level1
INPUT_MHS=/data/output2/noaa_metop/mhs/level1
INPUT_HIRS=/data/output2/noaa_metop/hirs/level1
INPUT_AVHRR=/data/output2/noaa_metop/avhrr/level1
INPUT_IASI=/data/output2/noaa_metop/iasi/level1
INPUT_AVHRR_VISTA=/data/output2/noaa_metop/avhrr/vistas
INPUT_TMP=/data/proc/nucaps/CSPP_HEAP_TESTDATA_2_0/input/metop1
INPUT_TMP2=/data/proc/nucaps/CSPP_HEAP_TESTDATA_2_0/input/metop3
ANCILLARY=/data/proc/nucaps/CSPP_HEAP_TESTDATA_2_0/dynanc
WORK_METOP=/data/proc/nucaps/CSPP_HEAP_TESTDATA_2_0/work/metop
OUTPUT_AMSUA_SERV=/dataservice/noaa-metop/amsua/level1
OUTPUT_MHS_SERV=/dataservice/noaa-metop/mhs/level1
OUTPUT_HIRS_SERV=/dataservice/noaa-metop/hirs/level1
OUTPUT_AVHRR_SERV=/dataservice/noaa-metop/avhrr/level1
OUTPUT_IASI_SERV=/dataservice/noaa-metop/iasi/level1
VISTA_AVHRR_SERV=/dataservice/noaa-metop/avhrr/vistas
OUTPUT_LOCAL=/data/output2/noaa_metop/nucaps/level2
OUTPUT_PETA=/data2/output2/noaa_metop/nucaps/level2
OUTPUT_SERVICE=/dataservice/noaa-metop/nucaps/level2
OUTPUT_VISTA_LOCAL=/data/output2/noaa_metop/nucaps/vistas
OUTPUT_VISTA_SERVICE=/dataservice/noaa-metop/nucaps/vistas
log=/home/lanotadm/log2

##Procesa METOP 1 to Level2 NUCAPS

export CSPP_HEAP_HOME=/data/opt2/NUCAPS/CSPP_HEAP_2_0
source $CSPP_HEAP_HOME/scripts/cspp_heap_env.sh

export POLAR2GRID_HOME=/data/opt2/POLAR2GRID/polar2grid_v_3_0
export PATH=$PATH:$POLAR2GRID_HOME/bin

export CSPP_SOUNDER_QL_HOME=/data/opt2/SQL/cspp-sounder-ql-1.3
source $CSPP_SOUNDER_QL_HOME/cspp_sounder_ql_env.sh

lastm1amsua=$(ls -t $INPUT_AMSUA/*_M01_*.l1b |head -1|cut -d '_' -f 4,5|cut -c 1-15)
lastm1mhs=$(ls -t $INPUT_MHS/*_M01_*.l1b |head -1|cut -d '_' -f 4,5|cut -c 1-15)
lastm1hirs=$(ls -t $INPUT_HIRS/*_M01_*.l1b |head -1|cut -d '_' -f 4,5|cut -c 1-15)
lastm1avhrr=$(ls -t $INPUT_AVHRR/*_M01_*.l1b |head -1|cut -d '_' -f 4,5|cut -c 1-15)
lastm1iasi=$(ls -t $INPUT_IASI/*_M01_*.l1c |head -1|cut -d '_' -f 4,5|cut -c 1-15)
lastm1iasi2=$(ls -t $INPUT_IASI/IASI*_M01_* |head -1|cut -d '_' -f 6,7|cut -c 1-15)
lastm1avhrrvis=$(ls -t $INPUT_AVHRR_VISTA/*_avhrr_*.tif |head -1|cut -d '_' -f 6,7|cut -c 1-13)

if [[ ! $lastm1amsua == `cat $log/lastm1amsua` ]]
then
    echo $lastm1amsua > $log/lastm1amsua
    date
    cp -uv $INPUT_AMSUA/*$lastm1amsua* $OUTPUT_AMSUA_SERV
    cp -uv $INPUT_MHS/*$lastm1mhs* $OUTPUT_MHS_SERV
    cp -uv $INPUT_HIRS/*$lastm1hirs* $OUTPUT_HIRS_SERV
    cp -uv $INPUT_AVHRR/*$lastm1avhrr* $OUTPUT_AVHRR_SERV
    cp -uv $INPUT_IASI/*$lastm1iasi* $OUTPUT_IASI_SERV
    cp -uv $INPUT_IASI/*$lastm1iasi2* $OUTPUT_IASI_SERV
    cp -uv $INPUT_AVHRR_VISTA/*$lastm1avhrrvis* $VISTA_AVHRR_SERV
    cd $WORK_METOP
    echo -e "\nInicia proceso NUCAPS METOP1 \n"
    date
    run_heap.bash -s m01 -i $INPUT_TMP -w $WORK_METOP -d $ANCILLARY -p 10 -c
    date
#    polar2grid.sh -r nucaps -w geotiff --num-workers 60 --dtype float32 --method nearest -f NUCAPS-EDR_v3r0*.nc
    cp -uv *.nc $OUTPUT_LOCAL
    cp -uv *.txt $OUTPUT_LOCAL
    echo -e "\nDatos NUCAPS enviados Local\n"
    cp -uv *.nc $OUTPUT_SERVICE
    cp -uv *.txt $OUTPUT_SERVICE
    echo -e "\nDatos NUCAPS enviados Dataservice\n"
    cp -uv *.nc $OUTPUT_PETA
    cp -uv *.txt $OUTPUT_PETA
    echo -e "\nDatos NUCAPS enviados Peta\n"
    date
    rm -rf *
    echo -e "\nFin proceso NUCAPS NPP\n"
else
    echo -e "\nYa fue procesado el ultimo NUCAPS METOP1 $lastm1amsua\n"
fi

rm -f $INPUT_TMP/*

##Procesa METOP 3 to Level2 NUCAPS

lastm3amsua=$(ls -t $INPUT_AMSUA/*_M03_*.l1b |head -1|cut -d '_' -f 4,5|cut -c 1-15)
lastm3mhs=$(ls -t $INPUT_MHS/*_M03_*.l1b |head -1|cut -d '_' -f 4,5|cut -c 1-15)
lastm3avhrr=$(ls -t $INPUT_AVHRR/*_M03_*.l1b |head -1|cut -d '_' -f 4,5|cut -c 1-15)
lastm3iasi=$(ls -t $INPUT_IASI/*_M03_*.l1c |head -1|cut -d '_' -f 4,5|cut -c 1-15)
lastm3iasi2=$(ls -t $INPUT_IASI/IASI*_M03_* |head -1|cut -d '_' -f 6,7|cut -c 1-15)
lastm3avhrrvis=$(ls -t $INPUT_AVHRR_VISTA/*_avhrr_*.tif |head -1|cut -d '_' -f 6,7|cut -c 1-13)

if [[ ! $lastm3amsua == `cat $log/lastm3amsua` ]]
then
    echo $lastm3amsua > $log/lastm3amsua
    date
    cp -uv $INPUT_AMSUA/*$lastm3amsua* $OUTPUT_AMSUA_SERV
    cp -uv $INPUT_MHS/*$lastm3mhs* $OUTPUT_MHS_SERV
    cp -uv $INPUT_AVHRR/*$lastm3avhrr* $OUTPUT_AVHRR_SERV
    cp -uv $INPUT_IASI/*$lastm3iasi* $OUTPUT_IASI_SERV
    cp -uv $INPUT_IASI/*$lastm3iasi2* $OUTPUT_IASI_SERV
    cp -uv $INPUT_AVHRR_VISTA/*$lastm3avhrrvis* $VISTA_AVHRR_SERV
    cd $WORK_METOP
    echo -e "\nInicia proceso NUCAPS METOP3 \n"
    date
    run_heap.bash -s m03 -i $INPUT_TMP2 -w $WORK_METOP -d $ANCILLARY -p 10 -c
    date
#    polar2grid.sh -r nucaps -w geotiff --num-workers 60 --dtype float32 --method nearest -f NUCAPS-EDR_v3r0*.nc
    cp -uv *.nc $OUTPUT_LOCAL
    cp -uv *.txt $OUTPUT_LOCAL
    echo -e "\nDatos NUCAPS enviados Local\n"
    cp -uv *.nc $OUTPUT_SERVICE
    cp -uv *.txt $OUTPUT_SERVICE
    echo -e "\nDatos NUCAPS enviados Dataservice\n"
    cp -uv *.nc $OUTPUT_PETA
    cp -uv *.txt $OUTPUT_PETA
    echo -e "\nDatos NUCAPS enviados Peta\n"
    date
    rm -rf *
    echo -e "\nFin proceso NUCAPS METOP3\n"
else
    echo -e "\nYa fue procesado el ultimo METOP3 $lastm3amsua\n"
fi

rm -f $INPUT_TMP2/*
