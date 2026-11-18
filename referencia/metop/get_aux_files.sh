#!/bin/ksh
#
# A script to download OPS-LRS auxiliary files from the NWPSAF web site.
#
# COPYRIGHT
#    This software was developed within the context of the EUMETSAT Satellite
#    Application Facility on Numerical Weather Prediction (NWP SAF), under the
#    Cooperation Agreement dated 29 June 2011, between EUMETSAT and the
#    Met Office, UK, by one or more partners within the NWP SAF. The partners
#    in the NWP SAF are the Met Office, ECMWF, KNMI and MeteoFrance.
#
#    Copyright 2016, EUMETSAT, All Rights Reserved.
#
# 06/04/2016 Nigel Atkinson
# 27/09/2018 Update the url to EUMETSAT ftp site and substitute %5F with _
# 02/09/2020 Update the url to nwp-saf.eumetsat.int
# 01/02/2023 Add --no-check-certificate
###################################################################################


usage(){
  echo 'usage : get_aux_files.sh [options] directory'
  echo '         -d date  : Required date YYYYMMDD - defaults to today'
  echo '         -s sat   : Satellite (M01, M02, M03) - defaults to all'
  echo '         -l       : List required files not already in local directory but do not download'
}

required_date=$(date +%Y%m%d)  #default

while getopts d:s:l c
do
  case $c in
    d) required_date="$OPTARG";;
    s) satellite="$OPTARG";;
    l) list=1;;
    *) usage
       exit 1;;
  esac
done
shift `expr $OPTIND - 1`

[ $# = 0 ] && { usage; exit 0; }

directory=$1
[ -d $directory ] || { echo "Directory $directory does not exist"; exit 1; }

url=https://nwp-saf.eumetsat.int/downloads/aapp_data_files/OPS-LRS/aux_data/
#url=ftp://ftp.eumetsat.int/pub/NWPSAF/aapp_data_files/OPS-LRS/aux_data/
rm -f index.html files.txt

wget --no-check-certificate $url 2>/dev/null

prevtype=zz

if [ -s index.html ]; then
  while read a; do
    b=${a#*href}           #look for lines containing href
    if [ "$b" != "$a" ]; then
      file=${b:2}
      file=${file%%\"*}    #go up to the next " charcter
      file=$(echo $file | sed -e 's:\%5F:_:g')    #replace %5F with _
      [[ $file = *IASI* ]] && echo $(basename $file) >>files.txt
    fi
  done < index.html

#Re-order the file list with most recent first

  sort -r files.txt >files1.txt
  mv files1.txt files.txt

#Loop over files, identifying the ones that are needed

  while read file; do
    set $(IFS=_; echo $file)
    sat=$4
    type=$2

    required=N
    if [ "$satellite" = "" ] || [ "$satellite" = "$sat" ]; then
      if [ $type = xxx ] || [ $type = VER ] || [ $type = CTX ] || [ $type = ENG ]; then
        required=Y
      else

#Check the start date and if it is the first one to be earlier than the requested date then we need it

        yyyymmdd=${5:0:8}
        if [ "$type$sat" != "$prevtype" ] && [ "$yyyymmdd" -le "$required_date" ]; then
          required=Y
          prevtype=$type$sat
        else
          required=N
        fi
      fi
    fi

#Download or list the required files that are not already in the output directory

    if [ "$required" = Y ] && [ ! -s $directory/$file ]; then
      if [ "$list" = 1 ]; then
        echo $file
      else
        rm -f $directory/${file}.TMP
        wget --no-check-certificate --output-document=$directory/${file}.TMP $url/$file \
          && mv $directory/${file}.TMP $directory/$file
      fi
    fi
  done < files.txt
fi
rm -f index.html files.txt
