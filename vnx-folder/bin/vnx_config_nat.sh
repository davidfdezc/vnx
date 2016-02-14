#!/bin/bash

#
# Name: vnx_config_nat
#
# Description: setup or release rules to configure a NAT between two interfaces
#
# This file is a part of VNX package (http://vnx.dit.upm.es).
#
# Authors: David Fernández (david@dit.upm.es)
# Copyright (C) 2015,   DIT-UPM
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

USAGE="
Usage:
    
vnx_config_nat [-d] <internal_if> <external_if> 

    being:
        <internal_if>: the name of the internal interface. 
        <external_if>: the name of the public interface. 
        [-d]:          use this option to delete the NAT rules
"

while getopts ":d" opt; do
    case $opt in

    d)
        delete="yes"
        shift
        ;;
    *)
        echo ""       
        echo "ERROR: Invalid option -$OPTARG" >&2
        echo "$USAGE"
        exit 1
        ;;
      
    esac
done
  
if [[ $# -ne 2 ]]; then
        echo ""       
    echo "ERROR: incorrect number of parameters"
    echo "$USAGE"
    exit 1
fi

# Check if internal interface exists
ifconfig -a | grep "^$1" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    if [[ "$delete" == "yes" ]]; then 
        echo ""
        echo "WARNING: internal interface $1 does not exist"
        echo ""
    else
        echo ""
        echo "ERROR: internal interface $1 does not exist"
        echo ""
        exit 1
    fi
fi
INTERNALIF=$1

# Check if internal interface exists
ifconfig -a | grep "^$2" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    if [[ "$delete" == "yes" ]]; then 
        echo ""
        echo "WARNING: external interface $2 does not exist"
        echo ""
    else
        echo ""
        echo "ERROR: external interface $2 does not exist"
        echo ""
        exit 1
    fi
fi
EXTERNALIF=$2

if [[ "$delete" != "yes" ]]; then 

    echo "Adding NAT rules (int_if=$INTERNALIF, ext_if=$EXTERNALIF)"
    #
    # iptables to configure (taken from http://www.revsys.com/writings/quicktips/nat.html)
    #
    # /sbin/iptables -v -t nat -A POSTROUTING -o $EXTERNALIF -j MASQUERADE
    # /sbin/iptables -v -A FORWARD -i $EXTERNALIF -o $INTERNALIF -m state --state RELATED,ESTABLISHED -j ACCEPT
    # /sbin/iptables -v -A FORWARD -i $INTERNALIF -o $EXTERNALIF -j ACCEPT
    #

    echo 1 > /proc/sys/net/ipv4/ip_forward

    # Check if rule #1 exists
    iptables-save | grep "POSTROUTING -o $EXTERNALIF -j MASQUERADE" > /dev/null
    if [ $? -ne 0 ]; then
        echo "  Adding rule #1..."
        /sbin/iptables -v -t nat -A POSTROUTING -o $EXTERNALIF -j MASQUERADE
    else
        echo "  Rule #1 already configured"
    fi  

    # Check if rule #2 exists
    iptables-save | grep "FORWARD -i $EXTERNALIF -o $INTERNALIF -m state --state RELATED,ESTABLISHED -j ACCEPT" > /dev/null
    if [ $? -ne 0 ]; then
        echo "  Adding rule #2..."
        /sbin/iptables -v -A FORWARD -i $EXTERNALIF -o $INTERNALIF -m state --state RELATED,ESTABLISHED -j ACCEPT
    else
        echo "  Rule #2 already configured"
    fi  

    # Check if rule #3 exists
    iptables-save | grep "FORWARD -i $INTERNALIF -o $EXTERNALIF -j ACCEPT" > /dev/null
    if [ $? -ne 0 ]; then
        echo "  Adding rule #3..."
        /sbin/iptables -v -A FORWARD -i $INTERNALIF -o $EXTERNALIF -j ACCEPT
    else
        echo "  Rule #3 already configured"
    fi  

else

    echo "Deleting NAT rules (int_if=$INTERNALIF, ext_if=$EXTERNALIF)"

    # Check if rule #1 exists
    iptables-save | grep "POSTROUTING -o $EXTERNALIF -j MASQUERADE" > /dev/null
    if [ $? -ne 0 ]; then
        echo "  Rule #1 not configured"
    else
        echo "  Deleting rule #1..."
        /sbin/iptables -v -t nat -D POSTROUTING -o $EXTERNALIF -j MASQUERADE
    fi  

    # Check if rule #2 exists
    iptables-save | grep "FORWARD -i $EXTERNALIF -o $INTERNALIF -m state --state RELATED,ESTABLISHED -j ACCEPT" > /dev/null
    if [ $? -ne 0 ]; then
        echo "  Rule #2 not configured"
    else
        echo "  Deleting rule #1..."
        /sbin/iptables -v -D FORWARD -i $EXTERNALIF -o $INTERNALIF -m state --state RELATED,ESTABLISHED -j ACCEPT
    fi  

    # Check if rule #3 exists
    iptables-save | grep "FORWARD -i $INTERNALIF -o $EXTERNALIF -j ACCEPT" > /dev/null
    if [ $? -ne 0 ]; then
        echo "  Rule #3 not configured"
    else
        echo "  Deleting rule #3..."
        /sbin/iptables -v -D FORWARD -i $INTERNALIF -o $EXTERNALIF -j ACCEPT
    fi  

fi
