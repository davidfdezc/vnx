#!/bin/bash
#
# Name: vnx_convert_lxc_config
#
# Description: converts the LXC config file format from old and new formats 
#              (only the main variables used in VNX images are changed) 
#
# This file is part of VNX package.
#
# Authors: David Fernández (david@dit.upm.es)
#          Raul Alvarez (raul.alvarez@centeropenmiddleware.com)
# Copyright (C) 2018 DIT-UPM
#           Departamento de Ingeniería de Sistemas Telemáticos
#           Universidad Politécnica de Madrid
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
    vnx_convert_lxc_config [-q] -[n|o] <config file>
          -n -> converts to new config format (lxc version 2.1 or newer)    
          -o -> converts to old config format (lxc version 2.0 or older)    
		  -q -> silent operation
"		

[ "$#" -lt 1 ] && [ "$#" -gt 3 ] && msg "ERROR: illegal number of arguments$USAGE" && exit 1 

function msg {
  [ "$SILENT" != 'yes' ] && echo "$1"
}

# Parse arguments
while getopts ":hqn:o:" opt; do
  case $opt in
    q) 
      SILENT='yes'
      ;;
    n)
      msg "Converting to NEW format" >&2
      CONFIGFILE=$OPTARG 
      if [ ! -f $OPTARG ]; then
          msg "ERROR: $OPTARG config file not found!"
          exit 1
      fi
      sed -i -e 's/lxc.rootfs\s*=/lxc.rootfs.path =/g' -e 's/lxc.utsname\s*=/lxc.uts.name =/g' \
             -e 's/lxc.mount\s*=/lxc.mount.fstab =/g' -e 's/lxc.tty\s*=/lxc.tty.max =/g' \
             -e 's/lxc.network.type\s*=/lxc.net.0.type =/g' -e 's/lxc.network.link\s*=/lxc.net.0.link =/g' \
             -e 's/lxc.network.flags\s*=/lxc.net.0.flags =/g' -e 's/lxc.network.hwaddr\s*=/lxc.net.0.hwaddr =/g' \
             -e '/lxc.rootfs.backend\s*=.*/d' \
             $OPTARG
      ;;
    o)
      msg "Converting to OLD format" >&2
      if [ ! -f $OPTARG ]; then
          msg "ERROR: $OPTARG config file not found!"
          exit 1
      fi
      sed -i -e 's/lxc.rootfs.path\s*=\s*dir:/lxc.rootfs =/g' \
      		 -e 's/lxc.rootfs.path\s*=/lxc.rootfs =/g' -e 's/lxc.uts.name\s*=/lxc.utsname =/g' \
             -e 's/lxc.mount\s*=/lxc.mount.fstab =/g ' -e 's/lxc.tty.max\s*=/lxc.tty =/g' \
             -e 's/lxc.net.0.type\s*=/lxc.network.type =/g' -e 's/lxc.net.0.link\s*=/lxc.network.link =/g' \
             -e 's/lxc.net.0.flags\s*=/lxc.network.flags =/g' -e 's/lxc.net.0.hwaddr\s*=/lxc.network.hwaddr =/g' \
             $OPTARG
      ;;
    h)
      msg "$USAGE"
      ;;
    \?)
      msg "Invalid option: -$OPTARG" >&2
      msg "$USAGE"
      ;;
  esac
done