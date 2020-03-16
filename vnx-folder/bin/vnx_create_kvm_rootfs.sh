#!/bin/bash

#
# Name: create_rootfs
#
# Description: creates a VNX rootfs starting from an Ubuntu cloud image
#
# This file is a module part of VNX package.
#
# Author: David Fernández (david@dit.upm.es)
# Copyright (C) 2019 DIT-UPM
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

# Input data:

# Image to download
IMGSRVURL=https://cloud-images.ubuntu.com/xenial/current/
IMG=xenial-server-cloudimg-amd64-disk1.img # Ubuntu 16.04 64 bits

# Name of image to create
IMG2=vnx_rootfs_kvm_ubuntu64-16.04-v025-modified
IMG2LINK=rootfs_kvm_ubuntu64-modified

# Size of image created
IMG2SIZE=40G

# Packages to install in new rootfs
PACKAGES="aptsh traceroute ntp curl man "

# Commands to execute after package installation (one per line)
COMMANDS=$(cat <<EOF

# Create a file and wait till it is ready
touch /root/.create-rootfs
while [ ! -e /root/.create-rootfs ]; do sleep 3; done

# Installation commands go here. Included are the example commands for an openstack compute node

# Modify failsafe script to avoid delays on startup
sed -i -e 's/.*sleep [\d]*.*/\tsleep 1/' /etc/init/failsafe.conf

# Add ~/bin to root PATH
sed -i -e '\$aPATH=\$PATH:~/bin' /root/.bashrc

# Allow ssh root login
sed -i -e 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config


echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu" "trusty-updates/kilo main" > /etc/apt/sources.list.d/cloudarchive-kilo.list
apt-get update 
apt-get -y dist-upgrade

# STEP 6
apt-get -y -o Dpkg::Options::="--force-confold" install nova-compute sysfsutils

# STEP 8
apt-get -y -o Dpkg::Options::="--force-confold" install neutron-plugin-ml2 neutron-plugin-openvswitch-agent

#apt-get -y -o Dpkg::Options::="--force-confold" install software-properties-common

# Allow ssh root login
sed -i -e 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

EOF
)

#
# Do not modify under this line (or do it with care...)
#

TMPDIR=$( mktemp -d -t 'vnx-XXXXX' )
START_TIME=$SECONDS

#
# Create config file
#
function create-cloud-config-file {

cat > $TMPDIR/vnx-customize-data <<EOF
#cloud-config
manage_etc_hosts: True
hostname: vnx
password: xxxx
chpasswd: { expire: False }

groups:
  - vnx

users:
  - default
  - name: vnx
    gecos: VNX
    primary-group: vnx
    groups: sudo

chpasswd:
  list: |
    vnx:xxxx
    root:xxxx
  expire: False
ssh_pwauth: True

# Update system and install VNXACE dependencies
apt_update: true
apt_upgrade: true
packages:
 - libxml-libxml-perl
 - libnetaddr-ip-perl 
 - acpid
 - mpack
EOF

# Add aditional packages
for p in $PACKAGES; do
  echo " - $p" >> $TMPDIR/vnx-customize-data 
done

# Add additional commands
if [ "$COMMANDS" ]; then
  echo "cc_ready_cmd:" >> $TMPDIR/vnx-customize-data
  echo "$COMMANDS" | while read c; do 
    if [ "$c" ]; then    
      echo " - $c" >> $TMPDIR/vnx-customize-data
    fi
  done
fi

}


#
# Create install vnxaced script
#
function create-install-vnxaced-script {

cat > $TMPDIR/install-vnxaced <<EOF
#!/bin/bash

# Redirect script STDOUT and STDERR to console and log file 
# (commented cause it does not work...)
#LOG=/var/log/install-vnxaced.log
#CONSOLE=/dev/tty1
#exec >  >(tee $CONSOLE | tee -a $LOG)
#exec 2> >(tee $CONSOLE | tee -a $LOG >&2)

# Configure classic network interfaces naming
sed -i -e 's/\(GRUB_CMDLINE_LINUX=.*\)"/\1 net.ifnames=0 biosdevnames=0"/' /etc/default/grub
update-grub

USERDATAFILE=\$( find /var/lib/cloud -name user-data.txt )
echo \$USERDATAFILE

cd /tmp
munpack \$USERDATAFILE

tar xfvz vnx-aced-lf*.tgz
perl vnx-aced-lf-*/install_vnxaced

# Configure serial console on ttyS0
#cd /etc/init
#cp tty1.conf ttyS0.conf
#sed -i -e 's/tty1/ttyS0/' ttyS0.conf


# Eliminate cloud-init package
apt-get purge --auto-remove -y cloud-init cloud-guest-utils
apt-get purge --auto-remove -y open-vm-tools

# Disable cloud-init adding 'ds=nocloud' kernel parameter
#sed -i -e 's/\(GRUB_CMDLINE_LINUX_DEFAULT=.*\)"/\1 ds=nocloud ds=nocloud-net"/' /etc/default/grub
#sed -i -e 's/\(GRUB_CMDLINE_LINUX=.*\)"/\1 ds=nocloud ds=nocloud-net"/' /etc/default/grub
#update-grub

echo "VER=0.25" >> /etc/vnx_rootfs_version
DIST=\`lsb_release -i -s\` 
VER=\`lsb_release -r -s\` 
DESC=\`lsb_release -d -s\` 
DATE=\`date\` 
echo "OS=\$DIST \$VER" >> /etc/vnx_rootfs_version
echo "DESC=\$DESC" >> /etc/vnx_rootfs_version
echo "MODDATE=\$DATE" >> /etc/vnx_rootfs_version
echo "MODDESC=System created. Packages installed: \$PACKAGES" >> /etc/vnx_rootfs_version

# Execute additional commands
#$COMMANDS

vnx_halt -y
EOF

}

#
# Create inlcude file
#
#function create-include-file {
#
#cat > include-file <<EOF
#include
#file://usr/share/vnx/aced/vnx-aced-lf-2.0b.4058.tgz
#EOF
#
#}

#
# main
#

HLINE="----------------------------------------------------------------------------------"
echo ""
echo $HLINE
echo "Virtual Networks over LinuX (VNX) -- http://www.dit.upm.es/vnx - vnx@dit.upm.es"
echo $HLINE


# Create config files
create-cloud-config-file
create-install-vnxaced-script

# get a fresh copy of image
echo "--"
echo "-- Downloading image: ${IMGSRVURL}${IMG}"
echo "--"
rm -fv $IMG
wget ${IMGSRVURL}${IMG}

# Resize image 
echo "--"
echo "-- Resizing image ${IMG} to ${IMG2SIZE}..."
qemu-img resize ${IMG} ${IMG2SIZE}

# Convert img to qcow2 format and change name
echo "--"
echo "-- Converting image to qcow2 format..."
qemu-img convert -O qcow2 $IMG ${IMG%.*}.qcow2
mv ${IMG%.*}.qcow2 ${IMG2}.qcow2

# create multi-vnx-customize-data file mime multipart file including config files
# to copy to VM
#   include-file:text/x-include-url 
#   /usr/share/vnx/aced/vnx-aced-lf-2.0b.4058.tgz:application/octet-stream 
echo "--"
echo "-- Creating iso customization disk..."
write-mime-multipart  --output=$TMPDIR/multi-vnx-customize-data \
   $TMPDIR/vnx-customize-data:text/cloud-config  \
   /usr/share/vnx/aced/vnx-aced-lf-latest.tgz:application/octet-stream \
   $TMPDIR/install-vnxaced:text/x-shellscript

# Create iso disk with customization data
cloud-localds $TMPDIR/vnx-customize-data.img $TMPDIR/multi-vnx-customize-data
#cloud-localds vnx-customize-data.img vnx-customize-data

# Start virtual machine with the customization data disk
echo "--"
echo "-- Starting virtual machine to configure it..."
echo "--"
echo "kvm -net nic -net user -hda ${IMG2}.qcow2 -hdb vnx-customize-data.img -m 1024 -smp 2"
kvm -net nic -net user -hda ${IMG2}.qcow2 -hdb $TMPDIR/vnx-customize-data.img -m 1024 -smp 2

ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "--"
echo "-- rootfs creation finished ($ELAPSED_TIME secs.):"
ls -lh ${IMG2}.qcow2
if [ "$IMG2LINK" ]; then
  echo "--"
  echo "-- Creating symbolic link to new rootfs: $IMG2LINK"
  rm -f $IMG2LINK
  ln -sv ${IMG2}.qcow2 $IMG2LINK
  echo "--"
fi
echo $HLINE

# delete temp files
rm -f $TMPDIR/*vnx-customize-data $TMPDIR/install-vnxaced $TMPDIR/vnx-customize-data.img $IMG
rmdir $TMPDIR/
