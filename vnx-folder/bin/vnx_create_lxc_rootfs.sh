#!/bin/bash

#
# Name: create-rootfs
#
# Description: creates a customized LXC VNX rootfs starting from a basic VNX LXC rootfs
#
# This file is part of VNX package.
#
# Authors: David Fernández (david@dit.upm.es)
#          Raúl Álvarez (raul.alvarez.pinilla@alumnos.upm.es)
# Copyright (C) 2019 DIT-UPM
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
BASEROOTFSNAME=vnx_rootfs_lxc_ubuntu64-18.04-v025
ROOTFSNAME=vnx_rootfs_lxc_ubuntu64-18.04-v025-modified
ROOTFSLINKNAME="rootfs_lxc_ubuntu64-modified"

# Packages to be installed
PACKAGES="aptsh wget iperf traceroute telnet xterm curl ethtool chrony man bash_completion"

#
# Customization script
#

CUSTOMIZATIONSCRIPT=$(cat <<EOF

# Remove startup scripts
#systemctl disable apache2.service
#update-rc.d -f quagga disable

# Modify failsafe script to avoid delays on startup
#sed -i -e 's/.*sleep [\d]*.*/\tsleep 1/' /etc/init/failsafe.conf

# Add ~/bin to root PATH
sed -i -e '\$aPATH=\$PATH:~/bin' /root/.bashrc

# Allow root login by ssh
sed -i -e '/PermitRootLogin/d' /etc/ssh/sshd_config
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

# Add quagga pager env variable if needed
#sed -i -e '\$aexport VTYSH_PAGER=more' /etc/profile

# Delete the "mesg n" command in root's .profile to avoid the nasty message
# "mesg: ttyname failed: No such device" when executing commands with lxc-attach
sed -i '/^mesg n/d' /root/.profile

export DEBIAN_FRONTEND=noninteractive

# Additional commands here...





# Disable auto-upgrades if enabled
sed -i -e 's/"1"/"0"/g' /etc/apt/apt.conf.d/20auto-upgrades

EOF
)

function customize_config {

  # Modifications to config and other files in the directory where the rootfs is located
  # config file is located here: ${ROOTFSNAME}/config

cat << EOF >> ${ROOTFSNAME}/config

# Create /dev/net/tun
lxc.cgroup.devices.allow = c 10:200 rwm
lxc.hook.autodev = sh -c "modprobe tun; cd \${LXC_ROOTFS_MOUNT}/dev; mkdir net; mknod net/tun c 10 200; chmod 0666 net/tun"

# Create /dev/kvm
lxc.cgroup.devices.allow = c 10:232 rwm
lxc.hook.autodev = sh -c "cd \${LXC_ROOTFS_MOUNT}/dev; mknod -m 660 kvm c 10 232; chown root:\$(grep kvm \${LXC_ROOTFS_MOUNT}/etc/group | awk -F ':' '{print \$3}') kvm"
EOF
 

}


#
# Do not modify under this line (or do it with care...)
#

function customize_rootfs {

  echo "-----------------------------------------------------------------------"
  echo "Customizing rootfs..."
  echo "--"
  #echo "$CUSTOMIZATIONSCRIPT"
  #echo "lxc-attach -n $ROOTFSNAME -P $CDIR -- bash -c \"$CUSTOMIZATIONSCRIPT\" -P $CDIR"
  lxc-attach -n $ROOTFSNAME -P $CDIR -- bash -c "$CUSTOMIZATIONSCRIPT" -P $CDIR

}

function create_new_rootfs {

  #clear

  echo "-----------------------------------------------------------------------"
  echo "Deleting new rootfs directory if already exists..."
  rm -rf ${ROOTFSNAME}
  if [ -L ${ROOTFSLINKNAME} ]; then
    rm ${ROOTFSLINKNAME}
  fi
  # Create a tmp dir
  TMPDIR=$( mktemp --tmpdir=. -td tmp-rootfs.XXXXXX )
  echo "TMPDIR=$TMPDIR"
  cd $TMPDIR

  # Download base rootfs
  echo "-----------------------------------------------------------------------"
  echo "Downloading base rootfs..."
  vnx_download_rootfs -r ${BASEROOTFSNAME}.tgz

  mv ${BASEROOTFSNAME} ../${ROOTFSNAME}
  rm -f ${BASEROOTFSNAME}.tgz
  cd .. 
  rmdir $TMPDIR

  echo "--"
  echo "Changing rootfs config file..."
  # Change rootfs config to adapt it to the directory where is has been downloaded
  # Get LXC version on this system
  LXCVERS=$( lxc-start --version )
  [[ "$LXCVERS" =~ ^(2\.1|3\.) ]] && LXCVERS=new || LXCVERS=old
  # Get format version of image config file
  grep -q 'lxc.rootfs.path' ${ROOTFSNAME}/config && CONFIGVERS=new || CONFIGVERS=old
  echo "LXCVERS=$LXCVERS; CONFIGVERS=$CONFIGVERS"
  echo "Config file: ${ROOTFSNAME}/config"

  if [ $LXCVERS == 'new' ]; then
    if [ $CONFIGVERS == 'old' ]; then
        echo "Converting config file to new format..."
        cp ${ROOTFSNAME}/config ${ROOTFSNAME}/config.bak
        sed -i -e 's/lxc.rootfs\s*=/lxc.rootfs.path =/g' -e 's/lxc.utsname\s*=/lxc.uts.name =/g' \
               -e 's/lxc.mount\s*=/lxc.mount.fstab =/g' -e 's/lxc.tty\s*=/lxc.tty.max =/g' \
               -e 's/lxc.network.type\s*=/lxc.net.0.type =/g' -e 's/lxc.network.link\s*=/lxc.net.0.link =/g' \
               -e 's/lxc.network.flags\s*=/lxc.net.0.flags =/g' -e 's/lxc.network.hwaddr\s*=/lxc.net.0.hwaddr =/g' \
               -e '/lxc.rootfs.backend\s*=.*/d' \               
               ${ROOTFSNAME}/config
    fi
    [ ! -f ${ROOTFSNAME}/fstab ] && touch ${ROOTFSNAME}/fstab
    sed -i -e '/lxc\.rootfs\.path/d' -e '/lxc\.mount\.fstab/d' ${ROOTFSNAME}/config
    echo "
lxc.rootfs.path = $CDIR/${ROOTFSNAME}/rootfs
lxc.mount.fstab = $CDIR/${ROOTFSNAME}/fstab
" >> ${ROOTFSNAME}/config
  else 
    # LXC old version
    if [ $CONFIGVERS == 'new' ]; then
        echo "Converting config file to old format..."
        cp ${ROOTFSNAME}/config ${ROOTFSNAME}/config.bak
        sed -i -e 's/lxc.rootfs.path\s*=\s*dir:/lxc.rootfs =/g' \
      		   -e 's/lxc.rootfs.path\s*=/lxc.rootfs =/g' -e 's/lxc.uts.name\s*=/lxc.utsname =/g' \
               -e 's/lxc.mount\s*=/lxc.mount.fstab =/g ' -e 's/lxc.tty.max\s*=/lxc.tty =/g' \
               -e 's/lxc.net.0.type\s*=/lxc.network.type =/g' -e 's/lxc.net.0.link\s*=/lxc.network.link =/g' \
               -e 's/lxc.net.0.flags\s*=/lxc.network.flags =/g' -e 's/lxc.net.0.hwaddr\s*=/lxc.network.hwaddr =/g' \
               ${ROOTFSNAME}/config
    fi
    [ ! -f ${ROOTFSNAME}/fstab ] && touch ${ROOTFSNAME}/fstab
    sed -i -e '/lxc.rootfs/d' -e '/lxc.mount/d' ${ROOTFSNAME}/config
    echo "
lxc.rootfs = $CDIR/${ROOTFSNAME}/rootfs
lxc.mount = $CDIR/${ROOTFSNAME}/fstab
" >> ${ROOTFSNAME}/config

  fi

}

function start_and_install_packages {

  echo "-----------------------------------------------------------------------"
  echo "Installing packages in rootfs..."

  # Install packages in rootfs
  echo "lxc-start --daemon -n $ROOTFSNAME -f ${ROOTFSNAME}/config -P $CDIR"
  lxc-start --daemon -n $ROOTFSNAME -f ${ROOTFSNAME}/config -P $CDIR
  echo lxc-wait -n $ROOTFSNAME -s RUNNING -P $CDIR
  lxc-wait -n $ROOTFSNAME -s RUNNING -P $CDIR
  sleep 3
  echo lxc-attach -n $ROOTFSNAME -P $CDIR -- dhclient eth0
  lxc-attach -n $ROOTFSNAME -P $CDIR -- dhclient eth0
  echo lxc-attach -n $ROOTFSNAME -P $CDIR -- ifconfig eth0
  lxc-attach -n $ROOTFSNAME -P $CDIR -- ifconfig eth0
  echo lxc-attach -n $ROOTFSNAME -P $CDIR -- ping -c 3 www.dit.upm.es
  lxc-attach -n $ROOTFSNAME -P $CDIR -- ping -c 3 www.dit.upm.es
  lxc-attach -n $ROOTFSNAME -P $CDIR -- apt-get update
  echo lxc-attach -n $ROOTFSNAME -P $CDIR -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install $PACKAGES"
  lxc-attach -n $ROOTFSNAME -P $CDIR -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y install $PACKAGES"

  # Create /dev/net/tun device
  lxc-attach -n $ROOTFSNAME -P $CDIR -- mkdir /dev/net 
  lxc-attach -n $ROOTFSNAME -P $CDIR -- mknod /dev/net/tun c 10 200 
  lxc-attach -n $ROOTFSNAME -P $CDIR -- chmod 666 /dev/net/tun 

}

function create_rootfs_tgz {
  echo "-----------------------------------------------------------------------"
  echo "Creating rootfs tgz file..."
  rm -f $BASEROOTFSNAME.tgz
  tmpfile=$(mktemp)
  find ${ROOTFSNAME} -type s > $tmpfile
  #cat $tmpfile
  size=$(du -sb --apparent-size ${ROOTFSNAME} | awk '{ total += $1 - 512; }; END { print total }')
  size=$(( $size * 1020 / 1000 ))
  LANG=C tar --numeric-owner -cpf - ${ROOTFSNAME} -X $tmpfile | pv -p -s $size | gzip > ${ROOTFSNAME}.tgz
  for LINK in $ROOTFSLINKNAME; do
    rm -f $LINK
    ln -s ${ROOTFSNAME} $LINK
  done
}


#
# Main
#

# move to the directory where the script is located
cd `dirname $0`
CDIR=$(pwd)

SCRIPTNAME=$( basename $0 )
LOGFILE=${CDIR}/${SCRIPTNAME}.log

# Trick to log script output to $LOGFILE using script command 
# https://stackoverflow.com/questions/5985060/bash-script-using-script-command-from-a-bash-script-for-logging-a-session
[ -z "$TYPESCRIPT" ] && TYPESCRIPT=1 exec /usr/bin/script ${LOGFILE} -c "TYPESCRIPT=1  ${CDIR}/$SCRIPTNAME $*"

echo "-----------------------------------------------------------------------"
echo "Creating VNX LXC rootfs:"
echo "  Base rootfs:  $BASEROOTFSNAME"
echo "  New rootfs:   $ROOTFSNAME"
echo "  Rootfs link:  $ROOTFSLINKNAME"
echo "  Packages to install: $PACKAGES"
echo "  Logfile:      ${SCRIPTNAME}.log"
echo "-----------------------------------------------------------------------"

create_new_rootfs
start_and_install_packages
customize_rootfs
lxc-stop -n $ROOTFSNAME -P $CDIR # Stop the VM
customize_config
rm -f lxc-monitord.log # Delete log of the VM
create_rootfs_tgz

echo "...done"
echo "-----------------------------------------------------------------------"
