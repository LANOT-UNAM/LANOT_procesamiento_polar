#!/bin/bash

INPUT_DIR=/data/input/polar/raw
PROC_DIR=/data/proc/aapp/work
MMAM=/data/proc/aapp/work/MMAM
METOP=/home/lanotadm/METOPIZER/metopizer-3.51.1
OUTPUTAMSU=/data3/output2/noaa_metop/amsua/level1
OUTPUTMHS=/data3/output2/noaa_metop/mhs/level1
OUTPUTHIRS=/data3/output2/noaa_metop/hirs/level1
OUTPUTAVHRR=/data3/output2/noaa_metop/avhrr/level1
OUTPUTIASI=/data3/output2/noaa_metop/iasi/level1
VISTAAVHRR=/data3/output2/noaa_metop/avhrr/vistas
NUCAPS=/data3/proc/nucaps/CSPP_HEAP_TESTDATA_2_0/input/metop1
NUCAPS2=/data3/proc/nucaps/CSPP_HEAP_TESTDATA_2_0/input/metop3
log=/home/lanotadm/log

. $HOME/ATOVS_ENV8
. $AAPP_PREFIX/ATOVS_CONF

export PATH_OPS=/data/opt/AAPP/install/opslrs/OPS-LRS-run/OPS/perl
export DIR_IASICONFIG=/data/opt/AAPP/OPSAUX
export PATH=$PATH:$DIR_IASICONFIG

export POLAR2GRID_HOME=/data/opt/POLAR2GRID/polar2grid_v_3_0/
export PATH=$PATH:$POLAR2GRID_HOME/bin

if [ -z "$1" ]
then
    echo "Usanza:  $0 <archivo raw>"
    exit -1
else
    rawfile=$1
fi

lastch5=$INPUT_DIR/$rawfile

if [[ ! $lastch5 == `cat $log/lastch5` ]]
then
    echo "\n Procesando $rawfile \n"
    echo $lastch5 > $log/lastch5
    cp -uv $lastch5 $PROC_DIR/level0
    cd $PROC_DIR/level0
    # El crudo que se acaba de copiar, no "el chain5 más reciente": desde el
    # 2026-09-21 METOP llega por chain6 y chain5 es Aqua. Así no depende del
    # número de cadena.
    chain5=$PROC_DIR/level0/$rawfile
    echo -e "\n Inicia proceso CADU to CCSDS\n"
    date
    $METOP/bin/cadu_to_ccsds --in $chain5 --out isps > proc_cadu_to_ccsds
    cat proc_cadu_to_ccsds
    ls -lt
    echo -e "\n Fin proceso CADU to CCSDS \n"
    date
    whichmetop=$(grep METOP-* proc_cadu_to_ccsds|cut -d ' ' -f 11,12|cut -c 2-8)
    echo -e "\n $whichmetop \n"
    if [ $whichmetop == "METOP-1" ]
    then
	echo -e "\n Inicia proceso CCSDS to Level0 \n"
	date
	$METOP/bin/ccsds_to_l0 --config-apid $METOP/config/ccsds.config --config-mphr $METOP/config/mpr-config-M01 -d $PROC_DIR/level0 -g $MMAM -u $MMAM -t tle -i isps.hktm.ccsds isps.amsua.ccsds isps.mhs.ccsds isps.avhrr.ccsds isps.hirs.ccsds isps.iasi.ccsds isps.a-dcs.ccsds
	ls -lt
	echo -e "\n Fin proceso CCSDS to Level0 \n"
	date
	get_tle
	echo -e "\n Telemetria actualizada\n"
	echo -e "\n Inicia proceso Level0 to Level1\n"
	date
	AAPP_RUN_METOP -i "AMSU-A" -o $PROC_DIR/level1
	AAPP_RUN_METOP -i "MHS" -o $PROC_DIR/level1
	AAPP_RUN_METOP -i "HIRS" -o $PROC_DIR/level1
	AAPP_RUN_METOP -i "IASI AVHRR" -g IASI -o $PROC_DIR/level1
	AAPP_RUN_METOP -i "AMSU-A MHS HIRS IASI AVHRR" -g IASI -o $PROC_DIR/level1
	ls -lt $PROC_DIR/level1
	echo -e "\n Fin proceso Level0 to Level1\n"
	date
	echo -e "\n Inicio conversion of AAPP binary formats to HDF5\n"
	cd $PROC_DIR/level1
	convert_to_hdf5 amsual1c*.l1c
	convert_to_hdf5 mhsl1c*.l1c
	convert_to_hdf5 hirsl1*
	convert_to_hdf5 hrpt*.l1b
	convert_to_hdf5 iasil1*
	cp -uv amsual1* $OUTPUTAMSU
	cp -uv mhsl1* $OUTPUTMHS
	cp -uv hirsl1* $OUTPUTHIRS
	cp -uv hrpt* $OUTPUTAVHRR
	cp -uv iasil1* $OUTPUTIASI
	cp -uv IASI_*_1C_M01_* $OUTPUTIASI
	cp -uv amsual1b* $NUCAPS
	cp -uv mhsl1b* $NUCAPS
	cp -uv IASI_*_1C_M01_* $NUCAPS
	echo -e "\n Fin conversion of AAPP binary formats to HDF5 \n"
	date
	lastmetop1=$(ls -t $PROC_DIR/amsual1b*.l1b|head -1|cut -d '_' -f 4,5|cut -c 1-15)
	polar2grid.sh -r avhrr_l1b_aapp -w geotiff --num-workers 40 --dtype float32 --no-enhance --method nearest --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_1000m -f hrpt_*.l1b
	cp -uv *.tif $OUTPUTAVHRR
	cp -uv *.tif $VISTAAVHRR
	rm -rf *
	ssh tsom03 nohup /home/lanotadm/bin/cspp_nucaps_metop.sh < /dev/null >& ~/log2/metop1_$lastmetop1.log &
    else
	echo -e "\n Inicia proceso CCSDS to Level0 \n"
	date
	$METOP/bin/ccsds_to_l0 --config-apid $METOP/config/ccsds.config --config-mphr $METOP/config/mpr-config-M03 -d $PROC_DIR/level0 -g $MMAM -u $MMAM -t tle -i isps.hktm.ccsds isps.amsua.ccsds isps.mhs.ccsds isps.avhrr.ccsds isps.hirs.ccsds isps.iasi.ccsds isps.a-dcs.ccsds
	ls -lt
	echo -e "\n Fin proceso CCSDS to Level0 \n"
	date
	get_tle
	echo -e "\n Telemetria actualizada\n"
	echo -e "\n Inicia proceso Level0 to Level1\n"
	date
	AAPP_RUN_METOP -i "AMSU-A" -o $PROC_DIR/level1
	AAPP_RUN_METOP -i "MHS" -o $PROC_DIR/level1
	AAPP_RUN_METOP -i "HIRS" -o $PROC_DIR/level1
	AAPP_RUN_METOP -i "IASI AVHRR" -g IASI -o $PROC_DIR/level1
	AAPP_RUN_METOP -i "AMSU-A MHS IASI AVHRR" -g IASI -o $PROC_DIR/level1
	ls -lt $PROC_DIR/level1
	echo -e "\n Fin proceso Level0 to Level1\n"
	date
	echo -e "\n Inicio conversion of AAPP binary formats to HDF5\n"
	cd $PROC_DIR/level1
	convert_to_hdf5 amsual1c*.l1c
	convert_to_hdf5 mhsl1c*.l1c
	convert_to_hdf5 hirsl1*
	convert_to_hdf5 hrpt*.l1b
	convert_to_hdf5 iasil1*
	cp -uv amsual1* $OUTPUTAMSU
	cp -uv mhsl1* $OUTPUTMHS
	cp -uv hrpt* $OUTPUTAVHRR
	cp -uv iasil1* $OUTPUTIASI
	cp -uv IASI_*_1C_M03_* $OUTPUTIASI
	cp -uv amsual1b* $NUCAPS2
	cp -uv mhsl1b* $NUCAPS2
	cp -uv IASI_*_1C_M03_* $NUCAPS2
	echo -e "\n Fin conversion of AAPP binary formats to HDF5 \n"
	date
	lastmetop3=$(ls -t $PROC_DIR/amsual1b*.l1b|head -1|cut -d '_' -f 4,5|cut -c 1-15)
	polar2grid.sh -r avhrr_l1b_aapp -w geotiff --num-workers 40 --dtype float32 --no-enhance --method nearest --grid-configs ${POLAR2GRID_HOME}/grid_configs/grid.yaml -g wgs84_geo_1000m -f hrpt_*.l1b
	cp -uv *.tif $OUTPUTAVHRR
	cp -uv *.tif $VISTAAVHRR
	rm -rf *
	ssh tsom03 nohup /home/lanotadm/bin/cspp_nucaps_metop.sh < /dev/null >& ~/log2/metop3_$lastmetop3.log &
    fi
else
    echo -e "\n Ya fue procesado $lastch5\n"
fi

cd $PROC_DIR/level0/

rm -rf *
