#!/bin/bash

# 
# Draft script to package VNX scenarios
#
# Author: David Fernández (david@dit.upm.es)
#
# This file is part of the Virtual Networks over LinuX (VNX) Project distribution. 
# (www: http://www.dit.upm.es/vnx - e-mail: vnx@dit.upm.es) 
# 
# Departamento de Ingenieria de Sistemas Telematicos (DIT)
# Universidad Politecnica de Madrid
# SPAIN
#

USAGE="vnx_pack_scenario: simple script to package VNX scenarios in a tgz file 

Usage:  vnx_pack_scenario -f <scenario_dir> [-v <version>] [-r]
              -f -> directory where the scenario is
              -v -> set version number in tgz name
              -r -> include root filesystem
"

#echo "num args=$#"
if [ "$#" -lt 2 ]; then
    echo -e "\nERROR: Invalid number of parameters" 
    echo -e "\n$USAGE\n"
    exit 1
fi

while getopts ":f:v:hr" opt; do
    case "$opt" in
        f)
            SCENARIO="$OPTARG" 
            if [ ! -d $SCENARIO ]; then 
                echo -e "\nERROR: scenario $SCENARIO does not exist\n"
                exit 1
            fi
            SCENABSNAME=$( readlink -m $SCENARIO )
            SCENDIRNAME=$( dirname $SCENABSNAME )
            SCENBASENAME=$( basename $SCENABSNAME )
            #echo SCENBASENAME=$SCENBASENAME
            ;;
        v)
            VER="$OPTARG" 
            ;;
        r)
            INCROOTFS="yes"           
            ;;
        h)
            echo -e "\n$USAGE\n"
            exit 0 
            ;;
        \?)
            echo "\nERROR: Invalid option '-$OPTARG'\n"
            exit 1
            ;;
    esac
done

# Change dir to scenario upper directory
cd $SCENDIRNAME
echo SCENABSNAME=$SCENABSNAME
echo SCENDIRNAME=$SCENDIRNAME
echo SCENBASENAME=$SCENBASENAME

pwd

if [ $VER ]; then
    TGZNAME=${SCENBASENAME}-v${VER}
else
    TGZNAME=${SCENBASENAME}
fi

echo "-- Packaging scenario $SCENBASENAME"

CONTENT="$SCENBASENAME/*.xml $SCENBASENAME/*.cvnx $SCENBASENAME/conf $SCENBASENAME/filesystems/create* $SCENBASENAME/filesystems/rootfs*"

if [ $INCROOTFS ]; then
  ROOTFS=$(readlink $SCENBASENAME/filesystems/rootfs*) 
  echo "--   Including rootfs: $ROOTFS"
  CONTENT="$CONTENT $SCENBASENAME/filesystems/$ROOTFS"

  # Exclude sockets to avoid errors when making tar file
  TMPFILE=$( mktemp )
  find $SCENBASENAME/filesystems/$ROOTFS -type s > $TMPFILE
  CONTENT="$CONTENT -X $TMPFILE"
else
  echo "--   rootfs not packaged (use option -r if you want to include it)."
fi

echo "-- Creating ${TGZNAME}.tgz file..."
#tar cfzp --checkpoint --checkpoint-action="echo=." ${TGZNAME}.tgz $CONTENT
#tar -czp --totals --checkpoint=.100 -f ${TGZNAME}.tgz $CONTENT

#echo "Executing du -sb --apparent-size $CONTENT | awk '{ total += $1; }; END { print total }'"
SIZE=$( du -sb --apparent-size $CONTENT | awk '{ total += $1 - 512; }; END { print total }' )
#echo "SIZE=$SIZE"
if [ $INCROOTFS ]; then
  SIZE=$(( $SIZE * 1033 / 1000))
else
  SIZE=$(( $SIZE * 101 / 100))
fi  
#echo "SIZE=$SIZE"

#echo "LANG=C tar -cf - $CONTENT | pv -p -s ${SIZE} -N  ${TGZNAME}.tgz | gzip > ${TGZNAME}.tgz"
LANG=C tar -cf - $CONTENT | pv -p -s ${SIZE} | gzip > ${TGZNAME}.tgz
echo "-- ...done"

if [ $TMPFILE ]; then
  rm $TMPFILE
fi
