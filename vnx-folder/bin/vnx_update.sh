#!/bin/bash

#
# Name: vnx_update
#
# Description: simple script to update the VNX version from VNX repository on http://idefix.dit.upm.es/vnx 
#
# This file is a part of VNX package (http://vnx.dit.upm.es).
#
# Authors: David Fernández (david@dit.upm.es)
# Copyright (C) 2014,   DIT-UPM
#           Departamento de Ingenieria de Sistemas Telematicos
#           Universidad Politecnica de Madrid
#           SPAIN
#           
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# An online copy of the licence can be found at http://www.gnu.org/copyleft/gpl.html
#

REMOTETMPDIR=vnx-update
VNXREPOURL=http://vnx.dit.upm.es/vnx/src
VNXLATEST=vnx-latest.tgz

USAGE="
Usage: 
  vnx_update -l 
  vnx_update [-v <version>] 
  vnx_update -h

Options:    -l              -> get a list of VNX versions available
            -v <version>    -> version to install

Example:
  vnx_update -v 2.0b.4199
"

VNXFNAME=${VNXLATEST}

while getopts "hlv:" opt; do

    case $opt in

    h)
        echo "$USAGE"
        exit 0
        ;;
    v)
        VNXFNAME=vnx-${OPTARG}-\*.tgz
        VERS=${OPTARG}
        ;;
    l)
        SHOWVERS="true"
        ;;
    ?)
        exit 1
        ;;
      
    esac
done

shift $(($OPTIND -1))

if [ $1 ]; then 
    echo "ERROR: parameter $1 invalid"
    echo "$USAGE"
    exit 1
fi

#echo "VNXFNAME=$VNXFNAME"

if [ $SHOWVERS ]; then
 
    echo ""
    echo "VNX versions available: "
    echo "----------------------- "
    wget -q -O - $VNXREPOURL | egrep -o "\"vnx-.*-.*.tgz\"" | sed  -e 's/"vnx-\(.*\)-[0-9]*.tgz"/\1/'
    echo "----------------------- "

else
    # Create tmpdir and delete content if already created
    mkdir -vp /tmp/$REMOTETMPDIR
    rm -rf /tmp/$REMOTETMPDIR/*
    cd /tmp/$REMOTETMPDIR/

    # Download latest version from idefix.dit.upm.es
    echo "wget -r -l1 -np -nd \"$VNXREPOURL\" -A \"$VNXFNAME\""
    wget -q -r -l1 -np -nd "$VNXREPOURL" -A "$VNXFNAME"

    echo "ls $VNXFNAME"
    FULLVNXFNAME=$(ls -1 | grep "$VERS")
    echo "$FULLVNXFNAME"

    if [ ! $FULLVNXFNAME ]; then
        echo "Version $VNXFNAME not found on VNX repository"
        exit 1
    fi

    # Uncompress vnx and install
    tar xfz $FULLVNXFNAME
    cd vnx-*
    ./install_vnx

    #vnx --version
fi