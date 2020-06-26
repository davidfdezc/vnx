#!/bin/bash

#
# Name: vnx_mount_rootfs
#
# Description: mount raw, qcow2, vmdk and vdi root filesystems 
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

#
# Constant and variables
#
VNXACED_VER='2.0b.4710'
VNXACED_BUILT='DD/MM/YYYY'

USAGE="
Usage: 
  - Mount disk image:
          vnx_mount_rootfs [-t <type>] [-p <partnumber>] -r <rootfsname> <mnt_dir>

  - Unmount disk image:
          vnx_mount_rootfs -u <mnt_dir>
          
Options:    -t <type>       -> type of image: raw, qcow2, vmdk, vdi
            -r <rootfsname> -> rootfs file
            -p <partnumber> -> number of partition to mount (defaults to 1)
            <mnt_dir>       -> mount directory
            -u              -> unmount rootfs
            -b              -> do not print headers (silent mode)
            -s              -> mount the image changing the owner of files to the 
                               original user that executed the script with sudo
"

HEADER1="
----------------------------------------------------------------------------------
Virtual Networks over LinuX (VNX) -- http://www.dit.upm.es/vnx - vnx@dit.upm.es
Version: $VNXACED_VER ($VNXACED_BUILT)

vnx_mount_rootfs: (um)mount raw, qcow2, vmdk and vdi root filesystems
----------------------------------------------------------------------------------"

umount="no"  # indicates whether "-u" umount switch is selected
type=""      # type of vm image (raw, qcow2, vmdk and vdi)
partnum="1"  # number of partition to mount
i=1          # counter of args processed

# Exit codes:
#   0  -> OK
#   1  -> Error in command line parameters 
#   2  -> Mount directory does not exist
#   3  -> No rootfs specified. Use -r option to specify it
#   4  -> Image file does not exist or it is not readable
#   5  -> Unknown rootfs type. use -t option to specify the type
#   6  -> qcow2 image format used but 'qemu-nbd' command not installed
#   7  -> Cannot load 'nbd' module needed by 'qemu-nbd' command
#   8  -> Cannot mount image in mountdir
#   9  -> Cannot connect $dev device to rootfs $rootfs
#   10 -> Cannot mount $dev on $mountdir
#   11 -> Cannot unmount $mountdir
#   12 -> Cannot free nbd block device
#   13 -> Error executing 'part -a $dev'


#
# Write message in standard output having into account 
# silent mode (-b) user selection
#
write_msg (){
    #echo "brief=$brief"
    if [[ ! $brief ]]; then
        echo "$1"
    fi
}

# 
# Command line option processing
#
if [ $# -eq 0 ]
then
    write_msg "$HEADER1"
    write_msg "$USAGE"
    exit 1
fi

while getopts ":ubst:r:p:" opt; do
    case $opt in

    u)
        umount="yes"
        i=$[i+1]
        ;;
    t)
        type=$OPTARG
        if [[ "$type" != 'raw' && "$type" != 'qcow2' && "$type" != 'vmdk' && "$type" != 'vdi' ]] ; then
            write_msg ""       
            write_msg "ERROR. Invalid type in -t option: $type" >&2
            write_msg "$USAGE"
            exit 1
        fi
        i=$[i+2]
        ;;
    r)
        rootfs=$OPTARG
        if [[ "$rootfs" == "" ]] ; then        
            write_msg ""       
            write_msg "ERROR. Invalid rootfs in -r option: $rootfs" >&2
            write_msg "$USAGE"
            exit 1
        fi
        i=$[i+2]
        ;;
    p)
        partnum=$OPTARG
        if [[ "$partnum" -le "0" || "$partnum" -gt "10" ]] ; then        
            write_msg ""       
            write_msg "ERROR. Invalid partition number: $partnum" >&2
            write_msg "$USAGE"
            exit 1
        fi
        i=$[i+2]
        ;;
    b)
        brief="yes"
        i=$[i+1]
        ;;
    s)
        sudoed_user="yes"
        i=$[i+1]
        ;;
    *)
        write_msg ""       
        write_msg "Invalid option: -$OPTARG" >&2
        write_msg "$USAGE"
        exit 1
        ;;
      
    esac
done

if [[ `id -u` != 0 ]]; then
    write_msg "ERROR: you need root permissions to execute vnx_mount_rootfs (use sudo to execute it)"
    exit 1
fi

if [[ $sudoed_user && ! $SUDO_USER ]]; then
    write_msg ""       
    write_msg "ERROR: -s option used but vnx_mount_rootfs not executed with sudo" >&2
    exit 1
fi

if [[ $sudoed_user ]]; then
    # Check bindfs is installed
    if [ ! $( which bindfs ) ]; then
        # Option A: exit with error
        echo ""
        echo "-----------------------------------------"
        echo "ERROR: command 'bindfs' not installed"
        echo "-----------------------------------------"
        exit 1;
        # Option B: install bindfs
        #echo "-------------------------------------------------------"
        #echo "WARNING: command 'bindfs' not installed. Installing..."
        #echo "-------------------------------------------------------"
        #apt-get update
        #apt-get -y install bindfs
    fi
fi

# mount dir is the last argument
eval mountdir=\$$i
if [[ ! -d "$mountdir" ]]; then
    write_msg ""       
    write_msg "ERROR. Mount directory ($mountdir) does not exist." >&2
    #write_msg "$USAGE"
    exit 2
fi
# Convert mountdir to absolute path
mountdir=$( readlink -f $mountdir )

# Calculate auxiliary mount directory name (used for -s option)
basemountdir=$(basename $mountdir)
dirmountdir=$(dirname $mountdir)
smountdir="$dirmountdir/.$basemountdir"

#
# Check rootfs argument
#
if [[ "$umount" == "no" ]]; then 
    if [[ "$rootfs" == "" ]] ; then
        write_msg ""       
        write_msg "ERROR. No rootfs specified. Use -r option to specify it" >&2
        write_msg "$USAGE"
        exit 3
    elif [[ ! -f "$rootfs" || ! -r "$rootfs" ]]; then
        write_msg ""       
        write_msg "ERROR. File $rootfs does not exist or it is not readable." >&2
        #write_msg "$USAGE"
        exit 4
   fi
fi

if [[ "$umount" == "no" && $type == "" ]] ; then
    if [[ $( echo $rootfs | egrep '\.img$' ) ]]; then
        type="raw"
    elif [[ $( echo $rootfs | egrep '\.qcow2$' ) ]]; then
        type="qcow2"
    elif [[ $( echo $rootfs | egrep '\.vmdk$' ) ]]; then
        type="vmdk"
    elif [[ $( echo $rootfs | egrep '\.vdi$' ) ]]; then
        type="vdi"
    else
        if [[ "$( file -b "$rootfs" | egrep 'QEMU QCOW Image|QEMU QCOW2 Image' )" ]]; then
            type="qcow2"
        elif [[ "$( file -b "$rootfs" | egrep 'VMware4 disk image' )" ]]; then
            type="vmdk"
        elif [[ "$( file -b "$rootfs" | egrep 'VirtualBox Disk Image' )" ]]; then
            type="vdi"
        else        
            write_msg ""       
            write_msg "ERROR. Unknown rootfs type. use -t option to specify the type" >&2
            write_msg "$USAGE"
            exit 5
        fi
    fi
fi

#
# If qcow2 used:
#  - check that qemu-nbd command is installed
#  - load nbd module if not loaded
#
if [[ $type == "qcow2" || $type == "vmdk" || $type == "vdi" ]]; then
    if ! hash qemu-nbd &> /dev/null ; then 
        write_msg ""
        write_msg "ERROR. $type image format used but 'qemu-nbd' command not installed."
        exit 6
    fi

    if ! lsmod | grep nbd &> /dev/null ; then 
        write_msg "Module nbd not loaded. Loading it..."
        if ! modprobe nbd max_part=16; then 
            write_msg ""
            write_msg "ERROR. Cannot load 'nbd' module needed by 'qemu-nbd' command."
            exit 7
        fi
    fi

fi

write_msg "$HEADER1"

if [[ $umount == "no" ]]; then
    write_msg "mounting $rootfs of type $type in $mountdir..."
else
    write_msg "unmounting $mountdir..."
fi

if [[ $umount == "no" ]]; then

    #   
    # Mount virtual machine disk image
    #
    if [[ $type == "raw" ]]; then

        if [[ $sudoed_user ]]; then
            # Create auxiliar mount dir
            mkdir -p $smountdir
            # Mount rootfs
            if ! mount -o loop "$rootfs" "$smountdir"; then
                write_msg "" 
                write_msg "ERROR. Cannot mount $rootfs in $mountdir."
                exit 8
            fi
            # Use bindfs to bind the auxiliar to mount  directory 
            # changing owner to $SUDO_USER
            write_msg "bindfs -o user=$SUDO_USER $smountdir $mountdir "
            bindfs -u $SUDO_USER $smountdir $mountdir 
        else
            # Mount raw disk
            if ! mount -o loop "$rootfs" "$mountdir"; then
                write_msg "" 
                write_msg "ERROR. Cannot mount $rootfs in $mountdir."
                exit 8
            fi
        fi
    else
        # Mount qcow2/vmdk/vdi disk
        # Look for a free nbd device
        for dev in /dev/nbd{?,??}; do 
            devname=$( basename $dev )
            if lsblk | grep $devname &> /dev/null ; then 
                write_msg "$dev in use"
            else
                break                
            fi
        done
        write_msg "Using $dev" 
        #write_msg "qemu-nbd -n -c $dev $rootfs"
        write_msg "qemu-nbd -c $dev $rootfs"
        #if ! qemu-nbd -n -c $dev "$rootfs"; then 
        if ! qemu-nbd -c $dev "$rootfs"; then 
            write_msg ""
            write_msg "ERROR. Cannot connect $dev device to rootfs $rootfs."
            qemu-nbd -d $dev
            exit 9
        fi
        # some time partition devices are not created, we use partx for that
        #if ! partx -a $dev; then 
        #    write_msg ""
        #    write_msg "ERROR executing 'part -a $dev'"
        #    qemu-nbd -d $dev
        #    exit 13
		#fi

        #read -p "Press any key..."
        sleep 1

        if [[ $sudoed_user ]]; then
            # Create auxiliar mount dir
            mkdir -p $smountdir
            # Mount rootfs
            if ! mount -v ${dev}p${partnum} $smountdir; then 
                write_msg ""
                write_msg "ERROR. Cannot mount $dev on $smountdir."
                qemu-nbd -d $dev
                exit 10
            fi
            # Use bindfs to bind the auxiliar to mount  directory 
            # changing owner to $SUDO_USER
            write_msg "bindfs -o user=$SUDO_USER $smountdir $mountdir "
            bindfs -u $SUDO_USER $smountdir $mountdir 
        else
            # Mount rootfs
            if ! mount ${dev}p${partnum} $mountdir; then 
                write_msg ""
                write_msg "ERROR. Cannot mount $dev on $mountdir."
                qemu-nbd -d $dev
                exit 10
            fi
        fi
    fi    

else 

    #   
    # Unmount virtual machine disk image
    #
    if mount | grep "$smountdir "; then
        sudoed_user="yes"
    fi

    # Guess partition type (raw, qcow2/vmdk/vdi)
    if mount | grep -e "$mountdir " -e "$smountdir " | grep "/dev/nbd"; then

        # Unmount qcow2/vmdk/vdi disk

        if [[ $sudoed_user ]]; then
            write_msg "umount $mountdir"
            if ! umount $mountdir; then 
                write_msg ""
                write_msg "ERROR. Cannot unmount $mountdir."
                #exit 11
            fi
        mountdir=$smountdir
        fi
        # Get block device
        partitions=$( mount | grep " $mountdir " | awk '{print $1}' )
        
        #write_msg "partitions=$partitions"
        while read -r partition; do
            write_msg "partition=$partition"
            dev=$( echo "$partition" | sed -e 's/p[0-9][0-9]\?$//' )
            write_msg "dev=$dev"
            # Unmount qcow2/vmdk/vdi disk
            if ! umount $mountdir; then 
                write_msg ""
                write_msg "ERROR. Cannot unmount $mountdir."
                exit 11
            fi
            # Free ndb block device
            echo "qemu-nbd -d $dev"
            if ! qemu-nbd -d $dev; then 
                write_msg ""
                write_msg "ERROR. Cannot free nbd block device $dev."
                exit 12
            fi
            sleep 1
            # kill the qemu-nbd process: it seems it does not die
            # and remains running eating cpu...
            pid=$( ps uax | grep "qemu-nbd" | grep "$dev" | awk '{print $2}' )
            if [[ "$pid" != "" ]]; then 
                kill -9 $pid
            fi
        done <<< "$partitions"
        if [[ $sudoed_user ]]; then
            rmdir $mountdir
        fi

    else 

        write_msg "Unmount raw disk"
        #write_msg "mountdir=$mountdir,smountdir=$smountdir"
        # Unmount raw disk
        if [[ $sudoed_user ]]; then
            if ! umount $mountdir; then 
                write_msg ""
                write_msg "ERROR. Cannot unmount $mountdir."
                #exit 11
            fi
            mountdir=$smountdir
        fi
        if ! umount $mountdir; then 
            write_msg ""
            write_msg "ERROR. Cannot unmount $mountdir."
            exit 11
        fi
        if [[ $sudoed_user ]]; then
            rmdir $mountdir
        fi
    fi
fi
