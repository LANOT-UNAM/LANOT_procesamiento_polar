#!/bin/ksh
#
# A script to download ATOVS (AMSU-A, MHS, HIRS) calibration files from the NWPSAF ftp site.
#
# Downloads each file then checks whether there are differences compared with
# the current file. If so, the current file is replaced. If not, the downloaded file
# is deleted.
#
# Note that the files are quite small, so this approach is OK. For larger files, a more
# sophisticated system would be needed (e.g. check the dates).
#
# COPYRIGHT
#    This software was developed within the context of the EUMETSAT Satellite
#    Application Facility on Numerical Weather Prediction (NWP SAF), under the
#    Cooperation Agreement dated 29 June 2011, between EUMETSAT and the
#    Met Office, UK, by one or more partners within the NWP SAF. The partners
#    in the NWP SAF are the Met Office, ECMWF, KNMI and MeteoFrance.
#
#    Copyright 2018, EUMETSAT, All Rights Reserved.
#
# 05/08/2018 Nigel Atkinson
# 15/11/2018 Add avhcal.txt
# 19/06/2019 Update url
# 02/09/2020 Move to nwp-saf.eumetsat.int
# 01/02/2023 Add --no-check-certificate
###################################################################################

usage(){
  echo 'usage : get_atovs_cal_files.sh [AAPP_PREFIX]'
}

[ "$1" ] && AAPP_PREFIX=$1
[ $AAPP_PREFIX ] || { usage; exit 1; }
[ -d $AAPP_PREFIX ] || { echo "$AAPP_PREFIX is not a directory"; exit 1; }

#url=ftp://ftp.eumetsat.int/pub/NWPSAF/aapp_data_files/atovs_cal_files
url=https://nwp-saf.eumetsat.int/downloads/aapp_data_files/atovs_cal_files

coefdir=$AAPP_PREFIX/AAPP/data
files="amsua_clparams.dat mhs_clparams.dat h_calcoef_algoV4.dat avhcal.txt fdf.dat satid.txt"
dirs="calibration/coef/amsua calibration/coef/mhs calibration/coef/hirs calibration/coef/avhcl preproc navigation"
set $dirs

for file in $files; do
  cd $coefdir/$1
  echo "Checking $PWD"
  rm -f ${file}.1
  wget --no-check-certificate -T 30 $url/$file || { echo "Cannot download $file"; exit 1; }

  if [ -s ${file}.1 ]; then 
    if [ "$(diff ${file}.1 ${file})" ]; then
      mv ${file}.1 ${file}
      echo "Updated ${file}"
      echo
    else
      rm -f ${file}.1
      echo "No change to ${file}"
      echo
    fi
  else
    echo "Created ${file}"
    echo
  fi
  shift
done
