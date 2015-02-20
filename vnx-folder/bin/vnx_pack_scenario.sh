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




if [ $VER ]; then
    TGZNAME=${SCENARIO}-v${VER}
else
    TGZNAME=${SCENARIO}
fi

echo "-- Packaging scenario $SCENARIO"

CONTENT="$SCENARIO/*.xml $SCENARIO/*.cvnx $SCENARIO/conf $SCENARIO/filesystems/create* $SCENARIO/filesystems/rootfs*"

if [ $INCROOTFS ]; then
  ROOTFS=$(readlink $SCENARIO/filesystems/rootfs*) 
  echo "--   Including rootfs: $ROOTFS"
  CONTENT="$CONTENT $SCENARIO/filesystems/$ROOTFS"
else
  echo "--   rootfs not packaged (use option -r if you want to include it)."
fi

echo "-- Creating ${TGZNAME}.tgz file..."
#tar cfzp --checkpoint --checkpoint-action="echo=." ${TGZNAME}.tgz $CONTENT
tar -czp --totals --checkpoint=.100 -f ${TGZNAME}.tgz $CONTENT
echo "-- ...done"
