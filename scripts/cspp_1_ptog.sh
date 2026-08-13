#!/bin/bash

INPUT_TMP=/data/proc/input/npp/viirs
INPUT_TMP1=/data/proc/input/n20/viirs
WORK_VIIRS=/data2/proc/cspp/cspp_sdr_data/viirs/work
WORK_VIIRS2=/data2/proc/cspp/cspp_sdr_data/viirs/work2
OUTPUT_L1_VIIRS_LOCAL=/data/output2/npp_jpss/viirs/level1
OUTPUT_L1_VIIRS_PETA=/data2/output/npp_jpss/viirs/level1
OUTPUT_L1_VIIRS_SERVICE=/dataservice/npp-jpss1/viirs/level1
OUTPUT_RGB_VIIRS_SERVICE=/dataservice/npp-jpss1/viirs/vistas/rgb
OUTPUT_DNB_VIIRS_SERVICE=/dataservice/npp-jpss1/viirs/vistas/dnb
log=/home/lanotadm/log2

export POLAR2GRID_HOME=/data/opt2/POLAR2GRID/polar2grid_v_3_0
export PATH=$PATH:$POLAR2GRID_HOME/bin

### Genera GEOTIFF NPP VIIRS L1 ###

lastnppp2g=$(ls -t $INPUT_TMP/*.h5|head -1|cut -d '_' -f 3,4|cut -c 1-15)

if [[ ! $lastnppp2g == `cat $log/lastnppp2g` ]]
then
    echo $lastnppp2g > $log/lastnppp2g
    cd $WORK_VIIRS
    echo -e "\nInicia proceso P2G NPP VIIRS\n"
    date
    polar2grid.sh -r viirs_sdr -w geotiff --m-bands --m-angle-products --m-rad-products --num-workers 40 --dtype float32 --no-enhance --method nearest --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_750m -f *.h5
    polar2grid.sh -r viirs_sdr -w geotiff --i-bands --i-angle-products --i-rad-products --num-workers 40 --dtype float32 --no-enhance --method nearest --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_375m -f *.h5
    polar2grid.sh -r viirs_sdr -w geotiff -p adaptive_dnb dynamic_dnb hncc_dnb --dnb-angle-products --num-workers 40 --dtype float32 --method nearest --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_750m -f *.h5
    date
    cp -uv *.tif $OUTPUT_L1_VIIRS_SERVICE
    echo -e "\nDatos L1 VIIRS GEOTIFF enviados Dataservice\n"
    cp -uv *.h5 $OUTPUT_L1_VIIRS_SERVICE
    echo -e "\nDatos L1 VIIRS H5 enviados Dataservice\n"
    cp -uv *.tif $OUTPUT_L1_VIIRS_LOCAL
    echo -e "\nDatos L1 VIIRS GEOTIFF enviados Local\n"
    cp -uv *.h5 $OUTPUT_L1_VIIRS_LOCAL
    echo -e "\nDatos L1 VIIRS H5 enviados Local\n"
    rm -f *.log
    rm -f *.tif

    polar2grid.sh -r viirs_sdr -w geotiff -p adaptive_dnb dynamic_dnb dynamic_dnb_saturation histogram_dnb hncc_dnb --num-workers 40 --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_750m -f *.h5
    cp -uv *.tif $OUTPUT_DNB_VIIRS_SERVICE
     echo -e "\nDatos L1 VIIRS VISTAS DNB enviados SERVICE\n"

    polar2grid.sh -r viirs_sdr -w geotiff -p false_color true_color --num-workers 40 --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_750m -f *.h5
    cp -uv *.tif $OUTPUT_RGB_VIIRS_SERVICE  
#    cp -uv *.tif $OUTPUT_L1_VIIRS_PETA
#    echo -e "\nDatos L1 VIIRS GEOTIFF enviados Peta\n"
#    cp -uv *.h5 $OUTPUT_L1_VIIRS_PETA
#    echo -e "\nDatos L1 VIIRS H5 enviados Peta\n"
    rm -f *.log
    rm -f *.tif
    rm -f *.h5
    rm -rf *
    echo -e "\nArchivos L1b VIIRS to GEOTIFF procesados\n"
    date
else
    echo -e "\nYa fue procesado el ultimo NPP VIIRS $lastnppp2g\n"
fi

### Genera GEOTIFF N20 VIIRS L1 ###

lastn20p2g=$(ls -t $INPUT_TMP1/*.h5|head -1|cut -d '_' -f 3,4|cut -c 1-15)

if [[ ! $lastn20p2g == `cat $log/lastn20p2g` ]]
then
    echo $lastn20p2g > $log/lastn20p2g
    cd $WORK_VIIRS2
    echo -e "\nInicia proceso P2G NPP VIIRS\n"
    date
    polar2grid.sh -r viirs_sdr -w geotiff --m-bands --m-angle-products --m-rad-products --num-workers 40 --dtype float32 --no-enhance --method nearest --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_750m -f *.h5
    polar2grid.sh -r viirs_sdr -w geotiff --i-bands --i-angle-products --i-rad-products --num-workers 40 --dtype float32 --no-enhance --method nearest --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_375m -f *.h5
    polar2grid.sh -r viirs_sdr -w geotiff -p adaptive_dnb dynamic_dnb hncc_dnb --dnb-angle-products --num-workers 40 --dtype float32 --method nearest --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_750m -f *.h5
    date
    cp -uv *.tif $OUTPUT_L1_VIIRS_SERVICE
    echo -e "\nDatos L1 VIIRS GEOTIFF enviados Dataservice\n"
    cp -uv *.h5 $OUTPUT_L1_VIIRS_SERVICE
    echo -e "\nDatos L1 VIIRS H5 enviados Dataservice\n"
    cp -uv *.tif $OUTPUT_L1_VIIRS_LOCAL
    echo -e "\nDatos L1 VIIRS GEOTIFF enviados Local\n"
    cp -uv *.h5 $OUTPUT_L1_VIIRS_LOCAL
    echo -e "\nDatos L1 VIIRS H5 enviados Local\n"
#    cp -uv *.tif $OUTPUT_L1_VIIRS_PETA
#    echo -e "\nDatos L1 VIIRS GEOTIFF enviados Peta\n"
#    cp -uv *.h5 $OUTPUT_L1_VIIRS_PETA
#    echo -e "\nDatos L1 VIIRS H5 enviados Peta\n"
    rm -f *.log
    rm -f *.tif
    
    polar2grid.sh -r viirs_sdr -w geotiff -p adaptive_dnb dynamic_dnb dynamic_dnb_saturation histogram_dnb hncc_dnb --num-workers 40 --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_750m -f *.h5
    cp -uv *.tif $OUTPUT_DNB_VIIRS_SERVICE
    echo -e "\nDatos L1 VIIRS VISTAS DNB enviados SERVICE\n"
    rm -f *.log
    rm -f *.tif

    polar2grid.sh -r viirs_sdr -w geotiff -p false_color true_color --num-workers 40 --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_750m -f *.h5
    cp -uv *.tif $OUTPUT_RGB_VIIRS_SERVICE

    rm -f *.log
    rm -f *.tif
    rm -f *.h5
    rm -rf *
    echo -e "\nArchivos L1b VIIRS to GEOTIFF procesados\n"
    date
else
    echo -e "\nYa fue procesado el ultimo NPP VIIRS $lastn20p2g\n"
fi
