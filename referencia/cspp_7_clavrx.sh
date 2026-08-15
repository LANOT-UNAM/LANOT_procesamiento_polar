#!/bin/bash

INPUT_TMP=/data/proc/input/npp/viirs
INPUT_TMP1=/data/proc/input/n20/viirs
WORK_VIIRS=/data/proc/clavrx/clavrx_test/work/npp
WORK_VIIRS1=/data/proc/clavrx/clavrx_test/work/n20
OUTPUT_LOCAL=/data/output2/npp_jpss/viirs/level2/clavrx
OUTPUT_PETA=/data2/output/npp_jpss/viirs/level2/clavrx
OUTPUT_SERVICE=/dataservice/npp-jpss1/viirs/level2/clavrx
OUTPUT_VISTA_LOCAL=/data/output2/npp_jpss/viirs/vistas/clavrx
OUTPUT_VISTA_DATASERVICE=/dataservice/npp-jpss1/viirs/vistas/clavrx
log=/home/lanotadm/log2

##Procesa NPP VIIRS to Level2 CLAVRX

export CSPP_CLAVRX_HOME=/data/opt2/CLAVRX/CLAVRx_3_0
source $CSPP_CLAVRX_HOME/env/set_clavrx_env.sh

export POLAR2GRID_HOME=/data/opt2/POLAR2GRID/polar2grid_v_3_0
export PATH=$PATH:$POLAR2GRID_HOME/bin

lastnppclavrx=$(ls -t $INPUT_TMP/*.h5|head -1|cut -d '_' -f 3,4|cut -c 1-15)
if [[ ! $lastnppclavrx == `cat $log/lastnppclavrx` ]]
then
    echo $lastnppclavrx > $log/lastnppclavrx
    cd $WORK_VIIRS
    echo -e "\nInicia proceso L1 a L2 CLAVRX NPP VIIRS\n"
    date
    run_clavrx.sh 3 $INPUT_TMP tmp ${PWD}
    $CSPP_CLAVRX_HOME/quicklooks/ql_clavrx.sh clavrx*.hdf
    date
    polar2grid.sh -r clavrx -w geotiff --num-workers 30 --dtype float32 --no-enhance --method nearest --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_750m -f clavrx_*.hdf
    date
    cp -uv *.hdf $OUTPUT_LOCAL
    cp -uv *.tif $OUTPUT_LOCAL
    echo -e "\nDatos L2 CLAVRX enviados Local\n"
    cp -uv *.hdf $OUTPUT_SERVICE
    cp -uv *.tif $OUTPUT_SERVICE
    echo -e "\nDatos L2 CLAVRX enviados Dataservice\n"
    cp -uv *.hdf $OUTPUT_PETA
    cp -uv *.tif $OUTPUT_PETA
    echo -e "\nDatos L2 CLAVRX enviados Peta\n"
    cp -uv *.png $OUTPUT_VISTA_LOCAL
    cp -uv *.png $OUTPUT_VISTA_DATASERVICE
    echo -e "\nDatos L2 CLAVRX enviados Local y Dataservice\n"
    echo -e "\nFin proceso L1 a L2 CLAVRX NPP VIIRS\n"
    date
    rm -rf *
    rm -f $INPUT_TMP/*.h5
else
    echo -e "\nYa fue procesado el ultimo CLAVRX NPP VIIRS $lastnppclavrx\n"
fi

##Procesa N20 VIIRS to Level2 CLAVRX

lastn20clavrx=$(ls -t $INPUT_TMP1/*.h5|head -1|cut -d '_' -f 3,4|cut -c 1-15)
if [[ ! $lastn20clavrx == `cat $log/lastn20clavrx` ]]
then
    echo $lastn20clavrx > $log/lastn20clavrx
    cd $WORK_VIIRS1
    echo -e "\nInicia proceso L1 a L2 CLAVRX N20 VIIRS\n"
    date
    run_clavrx.sh 3 $INPUT_TMP1 tmp ${PWD}
    $CSPP_CLAVRX_HOME/quicklooks/ql_clavrx.sh clavrx*.hdf
    date
    polar2grid.sh -r clavrx -w geotiff --num-workers 60 --dtype float32 --no-enhance --method nearest --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_750m -f clavrx_*.hdf
    date
    cp -uv *.hdf $OUTPUT_LOCAL
    cp -uv *.tif $OUTPUT_LOCAL
    echo -e "\nDatos L2 CLAVRX enviados Local\n"
    cp -uv *.hdf $OUTPUT_SERVICE
    cp -uv *.tif $OUTPUT_SERVICE
    echo -e "\nDatos L2 CLAVRX enviados Dataservice\n"
    cp -uv *.hdf $OUTPUT_PETA
    cp -uv *.tif $OUTPUT_PETA
    echo -e "\nDatos L2 CLAVRX enviados Peta\n"
    cp -uv *.png $OUTPUT_VISTA_LOCAL
    cp -uv *.png $OUTPUT_VISTA_DATASERVICE
    echo -e "\nDatos L2 CLAVRX enviados Local y Dataservice\n"
    echo -e "\nFin proceso L1 a L2 CLAVRX N20 VIIRS\n"
    date
    rm -rf *
    rm -f $INPUT_TMP1/*.h5
else
    echo -e "\nYa fue procesado el ultimo CLAVRX JPSS VIIRS $lastn20clavrx\n"
fi
