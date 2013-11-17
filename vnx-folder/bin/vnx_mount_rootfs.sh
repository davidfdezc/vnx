#!/bin/bash

#
# Name: vnx_mount_rootfs
#
# Description: mount raw and qcow2 root filesystems 
#
# This file is a part of VNX package (http://vnx.dit.upm.es).
#
# Authors: David Fernández (david@dit.upm.es)
# Copyright (C) 2013,   DIT-UPM
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

#
# Constant and variables
#
USAGE="
Usage: 
  - Mount disk image:
          vnx_mount_rootfs [-t <type>] -r <rootfsname> <mnt_dir>

  - Unmount disk image:
          vnx_mount_rootfs -u <mnt_dir>

Options:  -t <type>       -> type of image: raw or qcow2
      -r <rootfsname> -> rootfs file
          -p <partnumber> -> number of partition to mount (defaults to 1)
      <mnt_dir>       -> mount directory
      -u              -> unmount rootfs
"

HEADER1="
----------------------------------------------------------------------------------
Virtual Networks over LinuX (VNX) -- http://www.dit.upm.es/vnx - vnx@dit.upm.es
vnx_mount_rootfs: (um)mount raw and qcow2 root filesystems
----------------------------------------------------------------------------------"

umount="no"  # indicates wheter "-u" umount switch is selected
type=""      # type of vm image (raw or qcow2)
partnum="1"  # number of partition to mount
i=1          # counter of args processed

# 
# Command line option processing
#
if [ $# -eq 0 ]
then
  echo "$HEADER1"
  echo "$USAGE"
  exit 1
fi

while getopts "ut:r:" opt; do
    case $opt in

    u)
        #echo "-u was triggered" >&2
        umount="yes"
    i=$[i+1]
        ;;
    t)
        #echo "-t was triggered, Parameter: $OPTARG" >&2
    type=$OPTARG
    if [ $type != raw || $type != qcow2 ] ; then        
            echo "ERROR. Invalid type in -t option: $type" >&2
            echo "$USAGE"
            exit 1
    fi
    i=$[i+2]
        ;;
    r)
        #echo "-r was triggered, Parameter: $OPTARG" >&2
    rootfs=$OPTARG
    if [[ $rootfs == "" ]] ; then        
            echo "ERROR. Invalid rootfs in -r option: $rootfs" >&2
            echo "$USAGE"
            exit 1
    fi
    i=$[i+2]
        ;;
    p)
        #echo "-p was triggered, Parameter: $OPTARG" >&2
    partnum=$OPTARG
    if [ "$partnum" -le "0" || "$partnum" -gt "10" ] ; then        
            echo "ERROR. Invalid partition number: $partnum" >&2
            echo "$USAGE"
            exit 1
    fi
    i=$[i+2]
        ;;

    esac
done

# mount dir is the last argument
eval mountdir=\$$i
if [ ! -d "$mountdir" ]; then
    echo "ERROR. Mount directory does not exist." >&2
    echo "$USAGE"
    exit 1
fi
# Convert mountdir to absolute path
mountdir=$( readlink -f $mountdir )

#
# Check rootfs argument
#
if [[ "$umount" == "no" ]]; then 
    if [[ "$rootfs" == "" ]] ; then
        echo "ERROR. No rootfs specified. Use -r option to specify it" >&2
        echo "$USAGE"
        exit 1
    elif [[ ! -f "$rootfs" || ! -r "$rootfs" ]]; then
       echo "ERROR. File $rootfs does not exist or it is not readable." >&2
       echo "$USAGE"
       exit 1
   fi
fi

if [[ "$umount" == "no" && $type == "" ]] ; then
    if [ $( echo $rootfs | egrep '\.img$' ) ]; then
        type="raw"
    elif [ $( echo $rootfs | egrep '\.qcow2$' ) ]; then
        type="qcow2"
    else
        echo "ERROR. Unknown rootfs type. use -t option to specify the type" >&2
        echo "$USAGE"
        exit 1
    fi
fi

#
# If qcow2 used:
#  - check that qemu-nbd command is installed
#  - load nbd module if not loaded
#
if [[ $type == "qcow2" ]]; then
    if ! hash qemu-nbd &> /dev/null ; then 
        echo "ERROR. qcow2 image format used but 'qemu-nbd' command not installed."
        exit 1
    fi

    if ! modinfo nbd &> /dev/null ; then 
        echo "Module nbd not loaded. Loading it..."
        if ! modprobe nbd; then 
            echo "ERROR. Can not load 'nbd' module needed by 'qemu-nbd' command."
            exit 1
        fi
    fi

fi

echo "$HEADER1"

if [[ $umount == "no" ]]; then
    echo "mounting $rootfs of type $type in $mountdir..."
else
    echo "unmounting $mountdir..."
fi

if [[ $umount == "no" ]]; then

    #   
    # Mount virtual machine disk image
    #
    if [[ $type == "raw" ]]; then
        # Mount raw disk
        if ! mount -o loop $rootfs $mountdir; then 
            echo "ERROR. Can not mount $rootfs in $mountdir."
            exit 1
    fi
    else
        # Mount qcow2 disk
        #echo "Mount qcow2 disk"
    # Look for a free nbd device
    for dev in /dev/nbd{?,??}; do 
            devname=$( basename $dev )
            if lsblk | grep $devname &> /dev/null ; then 
                echo "$dev in use"
            else
        break                
            fi
    done
        echo "Using $dev" 
    echo "qemu-nbd -n -c $dev $rootfs"
        if ! qemu-nbd -n -c $dev $rootfs; then 
            echo "ERROR. Can not connect $dev device to rootfs $rootfs."
        qemu-nbd -d $dev
            exit 1
    fi
        #read -p "Press any key..."
    sleep 1
    # Mount rootfs
        if ! mount ${dev}p${partnum} $mountdir; then 
            echo "ERROR. Can not mount $dev on $mountdir."
        qemu-nbd -d $dev
            exit 1
    fi
    fi    
else 
    #   
    # Unmount virtual machine disk image
    #
    # Guess partition type (raw or qcow2)
    if mount | grep "$mountdir " | grep "/dev/nbd"; then
        # Unmount qcow2 disk
    # Get block device
    partition=$( mount | grep "$mountdir " | awk '{print $1}' )
    echo "partition=$partition"
    dev=$( echo "$partition" | sed -e 's/p[0-9][0-9]\?$//' )
    echo "dev=$dev"
        # Unmount qcow2 disk
        if ! umount $mountdir; then 
            echo "ERROR. Can not unmount $mountdir."
            exit 1
    fi
    # Free ndb block device
        if ! qemu-nbd -d $dev; then 
            echo "ERROR. Can free nbd block device $dev."
            exit 1
    fi
    sleep 1
    # kill the qemu-nbd process: it seems it does not die
        # and remains running eating cpu...
    pid=$( ps uax | grep "qemu-nbd" | grep "$dev" | awk '{print $2}' )
        if [[ "$pid" != "" ]]; then 
        kill -9 $pid
        fi
    else 
        # Unmount raw disk
        # Mount raw disk
        if ! umount $mountdir; then 
            echo "ERROR. Can not unmount $mountdir."
            exit 1
    fi
    fi
fi