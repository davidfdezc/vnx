#!/bin/bash

#
# Name: create-rootfs
#
# Description: creates a customized LXC VNX rootfs starting from a basic VNX LXC rootfs
#
# This file is part of VNX package.
#
# Authors: David Fernández (david@dit.upm.es)
#          Raul Alvarez (raul.alvarez@centeropenmiddleware.com)
# Copyright (C) 2015 DIT-UPM
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

# 
# Configuration
#


BASEROOTFSNAME=vnx_rootfs_lxc_ubuntu64-14.04-v025
ROOTFSNAME=vnx_rootfs_lxc_ubuntu64-14.04-v025-openstack-network
ROOTFSLINKNAME="rootfs_lxc_ubuntu64-ostack-network"
# General tools
PACKAGES="wget iperf unzip telnet xterm curl ethtool ntp man software-properties-common"
# Openstack packages
PACKAGES+=" ubuntu-cloud-keyring" 

CUSTOMIZESCRIPT=$(cat <<EOF

# Remove startup scripts
# update-rc.d -f apache2 remove
# echo manual | sudo tee /etc/init/isc-dhcp-server.override

# Modify failsafe script to avoid delays on startup
sed -i -e 's/.*sleep [\d]*.*/\tsleep 1/' /etc/init/failsafe.conf

# Add ~/bin to root PATH
sed -i -e '$aPATH=$PATH:~/bin' /root/.bashrc

# Allow root login by ssh
sed -i -e 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# STEP 1
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu" "trusty-updates/kilo main" > /etc/apt/sources.list.d/cloudarchive-kilo.list
apt-get update
apt-get -y dist-upgrade

# STEP 8
sed -i -e '/net\.ipv4\.ip_forward/d' /etc/sysctl.conf
sed -i -e '/net\.ipv4\.conf\.all\.rp_filter/d' /etc/sysctl.conf
sed -i -e '/net\.ipv4\.conf\.default\.rp_filter/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.conf
echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.conf
apt-get -y -o Dpkg::Options::="--force-confold" install neutron-plugin-ml2 neutron-plugin-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent
service openvswitch-switch restart
ovs-vsctl add-br br-ex

EOF
)

function customize_rootfs {

  lxc-attach -n MV -- bash -c "$CUSTOMIZESCRIPT"

}

#
# Do not modify under this line (or do it with care...)
#

function create_new_rootfs {

  # move to the directory where the script is located
  CDIR=`dirname $0`
  cd $CDIR
  CDIR=$(pwd)

  #clear

  echo "-----------------------------------------------------------------------"
  echo "Deleting base and new rootfs directories..."
  rm -rf ${BASEROOTFSNAME}
  rm -rf ${ROOTFSNAME}
  rm -f ${BASEROOTFSNAME}.tgz

  # Download base rootfs
  echo "-----------------------------------------------------------------------"
  echo "Downloading base rootfs..."
  vnx_download_rootfs -r ${BASEROOTFSNAME}.tgz

  mv ${BASEROOTFSNAME} ${ROOTFSNAME}
  echo "--"
  echo "Changing rootfs config file..."
  # Change rootfs config to adapt it to the directory wher is has been downloaded
  sed -i -e '/lxc.rootfs/d' -e '/lxc.mount/d' ${ROOTFSNAME}/config
  echo "
lxc.rootfs = $CDIR/${ROOTFSNAME}/rootfs
lxc.mount = $CDIR/${ROOTFSNAME}/fstab
" >> ${ROOTFSNAME}/config

}

function start_and_install_packages {

  echo "-----------------------------------------------------------------------"
  echo "Installing packages in rootfs..."

  # Install packages in rootfs
  lxc-start --daemon -n MV -f ${ROOTFSNAME}/config
  lxc-wait -n MV -s RUNNING
  sleep 3
  lxc-attach -n MV -- dhclient eth0
  lxc-attach -n MV -- ifconfig eth0
  lxc-attach -n MV -- ping -c 3 www.dit.upm.es
  lxc-attach -n MV -- apt-get update
  lxc-attach -n MV -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install $PACKAGES"

  # Create /dev/net/tun device
  lxc-attach -n MV -- mkdir /dev/net 
  lxc-attach -n MV -- mknod /dev/net/tun c 10 200 
  lxc-attach -n MV -- chmod 666 /dev/net/tun 

}

function create_rootfs_tgz {
  echo "-----------------------------------------------------------------------"
  echo "Creating rootfs tgz file..."
  rm $BASEROOTFSNAME.tgz
  tmpfile=$(mktemp)
  find ${ROOTFSNAME} -type s > $tmpfile 
  #cat $tmpfile
  size=$(du -sb --apparent-size ${ROOTFSNAME} | awk '{ total += $1 - 512; }; END { print total }')
  size=$(( $size * 1020 / 1000 ))
  LANG=C tar -cpf - ${ROOTFSNAME} -X $tmpfile | pv -p -s $size | gzip > ${ROOTFSNAME}.tgz
  for LINK in $ROOTFSLINKNAME; do
    rm -f $LINK
    ln -s ${ROOTFSNAME} $LINK
  done
}


#
# Main
#
echo "-----------------------------------------------------------------------"
echo "Creating VNX LXC rootfs:"
echo "  Base rootfs:  $BASEROOTFSNAME"
echo "  New rootfs:   $ROOTFSNAME"
echo "  Rootfs link:  $ROOTFSLINKNAME"
echo "  Packages to install: $PACKAGES"
echo "-----------------------------------------------------------------------"

create_new_rootfs
start_and_install_packages 
customize_rootfs
lxc-stop -n MV  # Stop the VM
create_rootfs_tgz

echo "...done"
echo "-----------------------------------------------------------------------"
