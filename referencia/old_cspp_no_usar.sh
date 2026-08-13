# NOTA: Este archivo solo es una referencia al proceso anterior. NO USAR

#!/bin/bash

INPUT_DIR=/data/input/polar/raw
INPUT_VIIRS=/data3/output2/npp_jpss/viirs/level0
INPUT_ATMS=/data3/output2/npp_jpss/atms/level0
INPUT_CRIS=/data3/output2/npp_jpss/cris/level0
INPUT_OMPS=/data3/output2/npp_jpss/omps/level0
WORK_VIIRS=/data/proc/cspp/cspp_sdr_data/viirs/work
WORK_ATMS=/data/proc/cspp/cspp_sdr_data/atms/work
WORK_CRIS=/data/proc/cspp/cspp_sdr_data/cris/work
WORK_OMPS=/data/proc/cspp/cspp_sdr_data/omps/work
WORK_VIIRS2=/data/proc/cspp/cspp_sdr_data/viirs/work2
WORK_ATMS2=/data/proc/cspp/cspp_sdr_data/atms/work2
WORK_CRIS2=/data/proc/cspp/cspp_sdr_data/cris/work2
WORK_OMPS2=/data/proc/cspp/cspp_sdr_data/omps/work2
OUTPUT_L0_VIIRS_PETA=/data/output/npp_jpss/viirs/level0
OUTPUT_L0_VIIRS_SERVICE=/dataservice/npp-jpss1/viirs/level0
OUTPUT_L1_VIIRS_TSOM3=/data3/output2/npp_jpss/viirs/level1
OUTPUT_L1_VIIRS_PETA=/data/output/npp_jpss/viirs/level1
OUTPUT_L1_VIIRS_SERVICE=/dataservice/npp-jpss1/viirs/level1
TMP_L1_NPP_VIIRS=/data3/proc/input/npp/viirs
TMP_L1_N20_VIIRS=/data3/proc/input/n20/viirs
OUTPUT_ATMS_L0_PETA=/data/output/npp_jpss/atms/level0
OUTPUT_ATMS_L0_SERVICE=/dataservice/npp-jpss1/atms/level0
OUTPUT_ATMS_L1_TSOM3=/data3/output2/npp_jpss/atms/level1
OUTPUT_ATMS_L1_PETA=/data/output/npp_jpss/atms/level1
OUTPUT_ATMS_L1_SERVICE=/dataservice/npp-jpss1/atms/level1
TMP_L1_NPP_ATMS=/data3/proc/nucaps/CSPP_HEAP_TESTDATA_2_0/input/npp
TMP_L1_N20_ATMS=/data3/proc/nucaps/CSPP_HEAP_TESTDATA_2_0/input/n20
VISTA_ATMS_L1_TSOM3=/data3/output2/npp_jpss/atms/vistas
VISTA_ATMS_L1_PETA=/data/output/npp_jpss/atms/vistas
VISTA_ATMS_L1_SERVICE=/dataservice/npp-jpss1/atms/vistas
OUTPUT_CRIS_L0_PETA=/data/output/npp_jpss/cris/level0
OUTPUT_CRIS_L0_SERVICE=/dataservice/npp-jpss1/cris/level0
OUTPUT_CRIS_L1_TSOM3=/data3/output2/npp_jpss/cris/level1
OUTPUT_CRIS_L1_PETA=/data/output/npp_jpss/cris/level1
OUTPUT_CRIS_L1_SERVICE=/dataservice/npp-jpss1/cris/level1
TMP_L1_NPP_CRIS=/data3/proc/nucaps/CSPP_HEAP_TESTDATA_2_0/input/npp
TMP_L1_N20_CRIS=/data3/proc/nucaps/CSPP_HEAP_TESTDATA_2_0/input/n20
VISTA_CRIS_L1_TSOM3=/data3/output2/npp_jpss/cris/vistas
VISTA_CRIS_L1_PETA=/data/output/npp_jpss/cris/vistas
VISTA_CRIS_L1_SERVICE=/dataservice/npp-jpss1/cris/vistas
OUTPUT_OMPS_L0_PETA=/data/output/npp_jpss/omps/level0
OUTPUT_OMPS_L0_SERVICE=/dataservice/npp-jpss1/omps/level0
OUTPUT_OMPS_L1_TSOM3=/data3/output2/npp_jpss/omps/level1
OUTPUT_OMPS_L1_PETA=/data/output/npp_jpss/omps/level1
OUTPUT_OMPS_L1_SERVICE=/dataservice/npp-jpss1/omps/level1
TMP_L1_NPP_OMPS=/data3/proc/input/npp/omps
TMP_L1_N20_OMPS=/data3/proc/input/n20/omps
VISTA_OMPS_L1_TSOM3=/data3/output2/npp_jpss/omps/vistas
VISTA_OMPS_L1_PETA=/data/output/npp_jpss/omps/vistas
VISTA_OMPS_L1_SERVICE=/dataservice/npp-jpss1/omps/vistas
log=/home/lanotadm/log2

export CSPP_SDR_HOME=/data/opt/CSPP/SDR_4_0
source $CSPP_SDR_HOME/cspp_sdr_env.sh

if [ -z "$1" ]
then
    echo "Usanza:  $0 <archivo raw>"
    exit -1
else
    rawfile=$1
fi


cd /data/opt/RT-STPS/rt-stps

lastpathfile=$INPUT_DIR/$rawfile

echo -e "\nInicia Proceso RAW to L0\n"

## Genera RDR NPP y JPSS1

if [[ $rawfile =~ ^chain2-* ]]; then
    if [[ ! $lastpathfile == `cat $log/lastch2` ]]
    then
        echo "Procesando $rawfile"
        echo $lastpathfile > $log/lastch2
	date
        ./bin/batch.sh config/npp.xml $lastpathfile
	date

	##Procesa RDR VIIRS to Level1 NPP

	lastrdrviirs=$(ls -t $INPUT_VIIRS/RNSCA-RVIRS_npp_*.h5|head -1|cut -d '_' -f 4,5|cut -c 1-15)
	echo $lastrdrviirs > $log/lastrdrviirs
	cp -uv $INPUT_VIIRS/*$lastrdrviirs* $OUTPUT_L0_VIIRS_PETA
#	cp -uv $INPUT_VIIRS/*$lastrdrviirs* $OUTPUT_L0_VIIRS_SERVICE
	cd $WORK_VIIRS
      	echo -e "\nInicia proceso L0 a L1 CSPP VIIRS\n"
	date
	viirs_sdr.sh -p 20 -a -g -m $INPUT_VIIRS/*$lastrdrviirs*
	date
	cp -uv *.h5 $TMP_L1_NPP_VIIRS
	echo -e "\nDatos L1 NPP VIIRS enviados TMP\n"
#	cp -uv *.h5 $OUTPUT_L1_VIIRS_TSOM3
#	echo -e "\nDatos L1 VIIRS enviados TSOM3\n"
	cp -uv *.h5 $OUTPUT_L1_VIIRS_SERVICE
	echo -e "\nDatos L1 VIIRS enviados Dataservice\n"
	cp -uv *.h5 /data3/proc/sr/cspp_lsr_test_data/input/npp
	echo -e "\nDatos L1 VIIRS enviados para SR\n"
	cp -uv *.h5 $OUTPUT_L1_VIIRS_PETA
	echo -e "\nDatos L1 VIIRS enviados Peta\n"
	echo -e "\nFin proceso L0 a L1 NPP VIIRS\n"
	date
	ssh tsom03 nohup /home/lanotadm/bin/cspp_1_ptog.sh < /dev/null >& ~/log2/ptog_$lastrdrviirs.log &
	ssh tsom03 nohup /home/lanotadm/bin/cspp_2_fire.sh < /dev/null >& ~/log2/fire_$lastrdrviirs.log &
	ssh tsom03 nohup /home/lanotadm/bin/cspp_3_asci.sh < /dev/null >& ~/log2/asci_$lastrdrviirs.log &

	##Procesa RDR ATMS to Level1 NPP

	lastrdratms=$(ls -t $INPUT_ATMS/RATMS-RNSCA_npp_*.h5|head -1|cut -d '_' -f 4,5|cut -c 1-15)
	echo $lastrdratms > $log/lastrdratms
	cp -uv $INPUT_ATMS/*$lastrdratms* $OUTPUT_ATMS_L0_PETA
	cp -uv $INPUT_ATMS/*$lastrdratms* $OUTPUT_ATMS_L0_SERVICE
	cd $WORK_ATMS
	echo -e "\nInicia proceso L0 a L1 CSPP ATMS\n"
	date
	atms_sdr.sh -p 20 -a -m $INPUT_ATMS/*$lastrdratms*
	rm -f *.log
	ql_sdr.sh .
	date
	cp -uv *.h5 $TMP_L1_NPP_ATMS
	echo -e "\nDatos L1 NPP ATMS enviados TMP\n"
	cp -uv *.h5 $OUTPUT_ATMS_L1_TSOM3
	echo -e "\nDatos L1 ATMS enviados TSOM3\n"
	cp -uv *.h5 $OUTPUT_ATMS_L1_PETA
	echo -e "\nDatos L1 ATMS enviados Peta\n"
	cp -uv *.h5 $OUTPUT_ATMS_L1_SERVICE
	echo -e "\nDatos L1 ATMS enviados Dataservice\n"
	cp -uv *.png $VISTA_ATMS_L1_TSOM3
	cp -uv *.png $VISTA_ATMS_L1_PETA
	cp -uv *.png $VISTA_ATMS_L1_SERVICE
	echo -e "\nVistas L1 ATMS enviados Local Peta Dataservice\n"
	rm -rf *
	echo -e "\nTermina proceso L0 a L1 CSPP ATMS\n"
	date

	##Procesa RDR CRIS to Level1 NPP

	lastrdrcris=$(ls -t $INPUT_CRIS/RCRIS-RNSCA_npp_*.h5|head -1|cut -d '_' -f 4,5|cut -c 1-15)
	echo $lastrdrcris > $log/lastrdrcris
	cp -uv $INPUT_CRIS/*$lastrdrcris* $OUTPUT_CRIS_L0_PETA
#	cp -uv $INPUT_CRIS/*$lastrdrcris* $OUTPUT_CRIS_L0_SERVICE
	cd $WORK_CRIS
	echo -e "\nInicia proceso L0 a L1 CSPP CRIS\n"
	date
	cris_sdr.sh -p 20 -a $INPUT_CRIS/*$lastrdrcris*
	rm -f *.log
	ql_sdr.sh --plot scatter .
	date
	cp -uv *.h5 $TMP_L1_NPP_CRIS
	echo -e "\nDatos L1 CRIS NPP enviados TMP\n"
	cp -uv *.h5 $OUTPUT_CRIS_L1_TSOM3
	echo -e "\nDatos L1 CRIS enviados TSOM3\n"
	cp -uv *.h5 $OUTPUT_CRIS_L1_PETA
	echo -e "\nDatos L1 CRIS enviados Peta\n"
	cp -uv *.h5 $OUTPUT_CRIS_L1_SERVICE
	echo -e "\nDatos L1 CRIS enviados Dataservice\n"
	cp -uv *.png $VISTA_CRIS_L1_TSOM3
	cp -uv *.png $VISTA_CRIS_L1_PETA
	cp -uv *.png $VISTA_CRIS_L1_SERVICE
	echo -e "\nVistas L1 CRIS enviados Local Peta Dataservice\n"
	rm -rf *
	echo -e "\nTermina proceso L0 a L1 CSPP CRIS\n"
	date

	ssh tsom03 nohup /home/lanotadm/bin/cspp_nucaps.sh < /dev/null >& ~/log2/nucaps_$lastrdratms.log &

	##Procesa RDR OMPS to Level1 NPP

	lastrdromps=$(ls -t $INPUT_OMPS/RNSCA-ROTCS_npp_*.h5|head -1|cut -d '_' -f 4,5|cut -c 1-15)
	lastrdromps1=$(ls -t $INPUT_OMPS/RNSCA-RONPS_npp_*.h5|head -1|cut -d '_' -f 4,5|cut -c 1-15)
	echo $lastrdromps > $log/lastrdromps
	cp -uv $INPUT_OMPS/RNSCA-*$lastrdromps* $OUTPUT_OMPS_L0_PETA
	cp -uv $INPUT_OMPS/RNSCA-*$lastrdromps1* $OUTPUT_OMPS_L0_PETA
	cp -uv $INPUT_OMPS/RNSCA-*$lastrdromps* $OUTPUT_OMPS_L0_SERVICE
	cp -uv $INPUT_OMPS/RNSCA-*$lastrdromps1* $OUTPUT_OMPS_L0_SERVICE
	cd $WORK_OMPS
	echo -e "\nInicia proceso L0 a L1 CSPP OMPS\n"
	date
	omps_sdr.sh -p 20 -a -m $INPUT_OMPS/RNSCA-ROTCS_*$lastrdromps*
	omps_sdr.sh -p 20 -a -m $INPUT_OMPS/RNSCA-RONPS_*$lastrdromps1*
	rm -f *.log
	ql_sdr.sh .
	date
	cp -uv *.h5 $TMP_L1_NPP_OMPS
	echo -e "\nDatos L1 OMPS NPP enviados TMP\n"
#	cp -uv *.h5 $OUTPUT_OMPS_L1_TSOM3
#	echo -e "\nDatos L1 OMPS enviados TSOM3\n"
	cp -uv *.h5 $OUTPUT_OMPS_L1_PETA
	echo -e "\nDatos L1 OMPS enviados Peta\n"
	cp -uv *.h5 $OUTPUT_OMPS_L1_SERVICE
	echo -e "\nDatos L1 OMPS enviados Dataservice\n"
	cp -uv *.png $VISTA_OMPS_L1_TSOM3
	cp -uv *.png $VISTA_OMPS_L1_PETA
	cp -uv *.png $VISTA_OMPS_L1_SERVICE
	rm -rf *
	echo -e "\nTermina proceso L0 a L1 CSPP OMPS\n"
	date
	ssh tsom03 nohup /home/lanotadm/bin/cspp_5_acspo.sh < /dev/null >& ~/log2/acspo_$lastrdrviirs.log &
	ssh tsom03 nohup /home/lanotadm/bin/cspp_6_flood.sh < /dev/null >& ~/log2/flood_$lastrdrviirs.log &
	ssh tsom03 nohup /home/lanotadm/bin/cspp_7_clavrx.sh < /dev/null >& ~/log2/clavrx_$lastrdrviirs.log &
    else
        echo -e "\nYa fue procesado $rawfile\n"
    fi
elif [[ $rawfile =~ ^chain6-* ]]; then
    if [[ ! $lastpathfile == `cat $log/lastch6` ]]
    then
        echo "Procesando $rawfile"
        echo $lastpathfile > $log/lastch6
	date
        ./bin/batch.sh config/jpss1.xml $lastpathfile
	date
	##Procesa RDR VIIRS to Level1 N20

	lastrdrviirs=$(ls -t $INPUT_VIIRS/RNSCA-RVIRS_j01_*.h5|head -1|cut -d '_' -f 4,5|cut -c 1-15)
        echo $lastrdrviirs > $log/lastrdrviirs
        cp -uv $INPUT_VIIRS/*$lastrdrviirs* $OUTPUT_L0_VIIRS_PETA
        cp -uv $INPUT_VIIRS/*$lastrdrviirs* $OUTPUT_L0_VIIRS_SERVICE
        cd $WORK_VIIRS2
        echo -e "\nInicia proceso L0 a L1 CSPP VIIRS\n"
        date
        viirs_sdr.sh -p 20 -a -g -m $INPUT_VIIRS/*$lastrdrviirs*
	date
	cp -uv *.h5 $TMP_L1_N20_VIIRS
	echo -e "\nDatos L1 N20 VIIRS enviados TMP\n"
#        cp -uv *.h5 $OUTPUT_L1_VIIRS_TSOM3
#        echo -e "\nDatos L1 VIIRS enviados TSOM3\n"
        cp -uv *.h5 $OUTPUT_L1_VIIRS_SERVICE
        echo -e "\nDatos L1 VIIRS enviados Dataservice\n"
	cp -uv *.h5 /data3/proc/sr/cspp_lsr_test_data/input/n20
	echo -e "\nDatos L1 VIIRS enviados para SR\n"
        cp -uv *.h5 $OUTPUT_L1_VIIRS_PETA
        echo -e "\nDatos L1 VIIRS enviados Peta\n"
        echo -e "\nFin proceso L0 a L1 CSPP VIIRS\n"
	date
	ssh tsom03 nohup /home/lanotadm/bin/cspp_1_ptog.sh < /dev/null >& ~/log2/ptog_$lastrdrviirs.log &
	ssh tsom03 nohup /home/lanotadm/bin/cspp_2_fire.sh < /dev/null >& ~/log2/fire_$lastrdrviirs.log &
        ssh tsom03 nohup /home/lanotadm/bin/cspp_3_asci.sh < /dev/null >& ~/log2/asci_$lastrdrviirs.log &
        ##Procesa RDR ATMS to Level1 N20

        lastrdratms=$(ls -t $INPUT_ATMS/RATMS-RNSCA_j01_*.h5|head -1|cut -d '_' -f 4,5|cut -c 1-15)
        echo $lastrdratms > $log/lastrdratms
        cp -uv $INPUT_ATMS/*$lastrdratms* $OUTPUT_ATMS_L0_PETA
        cp -uv $INPUT_ATMS/*$lastrdratms* $OUTPUT_ATMS_L0_SERVICE
        cd $WORK_ATMS2
        echo -e "\nInicia proceso L0 a L1 CSPP ATMS\n"
	date
        atms_sdr.sh -p 20 -a -m $INPUT_ATMS/*$lastrdratms*
	rm -f *.log
	ql_sdr.sh .
	date
	cp -uv *.h5 $TMP_L1_N20_ATMS
	echo -e "\nDatos L1 N20 ATMS enviados TMP\n"
        cp -uv *.h5 $OUTPUT_ATMS_L1_TSOM3
        echo -e "\nDatos L1 ATMS enviados TSOM3\n"
        cp -uv *.h5 $OUTPUT_ATMS_L1_PETA
        echo -e "\nDatos L1 ATMS enviados Peta\n"
        cp -uv *.h5 $OUTPUT_ATMS_L1_SERVICE
        echo -e "\nDatos L1 ATMS enviados Dataservice\n"
        cp -uv *.png $VISTA_ATMS_L1_TSOM3
        cp -uv *.png $VISTA_ATMS_L1_PETA
        cp -uv *.png $VISTA_ATMS_L1_SERVICE
        echo -e "\nVistas L1 ATMS enviados Local Peta Dataservice\n"
        rm -rf *
        echo -e "\nTermina proceso L0 a L1 CSPP ATMS\n"
        date

	##Procesa RDR CRIS to Level1 N20

        lastrdrcris=$(ls -t $INPUT_CRIS/RCRIS-RNSCA_j01_*.h5|head -1|cut -d '_' -f 4,5|cut -c 1-15)
        echo $lastrdrcris > $log/lastrdrcris
        cp -uv $INPUT_CRIS/*$lastrdrcris* $OUTPUT_CRIS_L0_PETA
        cp -uv $INPUT_CRIS/*$lastrdrcris* $OUTPUT_CRIS_L0_SERVICE
        cd $WORK_CRIS2
        echo -e "\nInicia proceso L0 a L1 CSPP CRIS\n"
	date
        cris_sdr.sh -p 20 -a $INPUT_CRIS/*$lastrdrcris*
	rm -f *.log
	ql_sdr.sh --plot scatter .
	date
        cp -uv *.h5 $TMP_L1_N20_CRIS
	echo -e "\nDatos L1 CRIS N20 enviados TMP\n"
        cp -uv *.h5 $OUTPUT_CRIS_L1_TSOM3
        echo -e "\nDatos L1 CRIS enviados TSOM3\n"
        cp -uv *.h5 $OUTPUT_CRIS_L1_PETA
        echo -e "\nDatos L1 CRIS enviados Peta\n"
        cp -uv *.h5 $OUTPUT_CRIS_L1_SERVICE
        echo -e "\nDatos L1 CRIS enviados Dataservice\n"
        cp -uv *.png $VISTA_CRIS_L1_TSOM3
        cp -uv *.png $VISTA_CRIS_L1_PETA
        cp -uv *.png $VISTA_CRIS_L1_SERVICE
        echo -e "\nVistas L1 CRIS enviados Local Peta Dataservice\n"
        rm -rf *
        echo -e "\nTermina proceso L0 a L1 CSPP CRIS\n"
	date

	ssh tsom03 nohup /home/lanotadm/bin/cspp_nucaps.sh < /dev/null >& ~/log2/nucaps_$lastrdratms.log &

	##Procesa RDR OMPS to Level1 N20

        lastrdromps=$(ls -t $INPUT_OMPS/RNSCA-ROTCS_j01_*.h5|head -1|cut -d '_' -f 4,5|cut -c 1-15)
	lastrdromps1=$(ls -t $INPUT_OMPS/RNSCA-RONPS_j01_*.h5|head -1|cut -d '_' -f 4,5|cut -c 1-15)
        echo $lastrdromps > $log/lastrdromps
	cp -uv $INPUT_OMPS/RNSCA-*$lastrdromps* $OUTPUT_OMPS_L0_PETA
        cp -uv $INPUT_OMPS/RNSCA-*$lastrdromps1* $OUTPUT_OMPS_L0_PETA
        cp -uv $INPUT_OMPS/RNSCA-*$lastrdromps* $OUTPUT_OMPS_L0_SERVICE
        cp -uv $INPUT_OMPS/RNSCA-*$lastrdromps1* $OUTPUT_OMPS_L0_SERVICE
        cd $WORK_OMPS2
        echo -e "\nInicia proceso L0 a L1 CSPP OMPS\n"
	date
        omps_sdr.sh -p 20 -a -m $INPUT_OMPS/RNSCA-ROTCS_*$lastrdromps*
        omps_sdr.sh -p 20 -a -m $INPUT_OMPS/RNSCA-RONPS_*$lastrdromps1*
	rm -f *.log
	ql_sdr.sh .
	date
	cp -uv *.h5 $TMP_L1_N20_OMPS
	echo -e "\nDatos L1 OMPS NPP enviados TMP\n"
#        cp -uv *.h5 $OUTPUT_OMPS_L1_TSOM3
#        echo -e "\nDatos L1 OMPS enviados TSOM3\n"
        cp -uv *.h5 $OUTPUT_OMPS_L1_PETA
        echo -e "\nDatos L1 OMPS enviados Peta\n"
        cp -uv *.h5 $OUTPUT_OMPS_L1_SERVICE
        echo -e "\nDatos L1 OMPS enviados Dataservice\n"
        cp -uv *.png $VISTA_OMPS_L1_TSOM3
        cp -uv *.png $VISTA_OMPS_L1_PETA
        cp -uv *.png $VISTA_OMPS_L1_SERVICE
        rm -rf *
        echo -e "\nTermina proceso L0 a L1 CSPP OMPS\n"
        date
	ssh tsom03 nohup /home/lanotadm/bin/cspp_5_acspo.sh < /dev/null >& ~/log2/acspo_$lastrdrviirs.log &
	ssh tsom03 nohup /home/lanotadm/bin/cspp_6_flood.sh < /dev/null >& ~/log2/flood_$lastrdrviirs.log &
	ssh tsom03 nohup /home/lanotadm/bin/cspp_7_clavrx.sh < /dev/null >& ~/log2/clavrx_$lastrdrviirs.log &
    else
        echo -e "\nYa fue procesado $rawfile\n"
    fi
fi
