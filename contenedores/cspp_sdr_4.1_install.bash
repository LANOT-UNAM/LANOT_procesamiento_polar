#!/bin/bash

# Installation script for the CSPP SDR Version 4.1 software.
# Users' should download the script, and execute it in the
# top level directory where they want the software to be installed.
# The software will reside in $PWD/CSPP/SDR_4_1 .
#
#   September 2024

# Set installation directory
INSTALL=$PWD

# Download and verify tarfiles
echo $'\n(Downloading tarfiles)\n'
mkdir tarfiles
cd tarfiles
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1.tar.gz
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_static_luts_npp.tar.gz
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_static_luts_j01.tar.gz
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_static_luts_j02.tar.gz
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_static_tiles.tar.gz
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_straylight_luts_npp.tar.gz
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_straylight_luts_j01.tar.gz
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_straylight_luts_j02.tar.gz
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_TEST_DATA.tar.gz
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1.tar.gz.sha1
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_static_luts_npp.tar.gz.sha1
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_static_luts_j01.tar.gz.sha1
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_static_luts_j02.tar.gz.sha1
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_static_tiles.tar.gz.sha1
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_straylight_luts_npp.tar.gz.sha1
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_straylight_luts_j01.tar.gz.sha1
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_straylight_luts_j02.tar.gz.sha1
wget http://bin.ssec.wisc.edu/pub/CSPP/hidden/SDR/v4.1/CSPP_SDR_V4.1_TEST_DATA.tar.gz.sha1
shasum -c *.sha1

# Install tarfiles
echo $'\n(Installing tarfiles)\n'
cd $INSTALL
# Make a CSPP top level installation directory
mkdir CSPP
cd CSPP
tar xf $INSTALL/tarfiles/CSPP_SDR_V4.1.tar.gz
tar xf $INSTALL/tarfiles/CSPP_SDR_V4.1_static_luts_npp.tar.gz
tar xf $INSTALL/tarfiles/CSPP_SDR_V4.1_static_luts_j01.tar.gz
tar xf $INSTALL/tarfiles/CSPP_SDR_V4.1_static_luts_j02.tar.gz
tar xf $INSTALL/tarfiles/CSPP_SDR_V4.1_static_tiles.tar.gz
tar xf $INSTALL/tarfiles/CSPP_SDR_V4.1_straylight_luts_npp.tar.gz
tar xf $INSTALL/tarfiles/CSPP_SDR_V4.1_straylight_luts_j01.tar.gz
tar xf $INSTALL/tarfiles/CSPP_SDR_V4.1_straylight_luts_j02.tar.gz

echo $'\n(CSPP SDR V4.1 Installation Completed)\n'
