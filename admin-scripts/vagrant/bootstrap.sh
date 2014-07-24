#!/usr/bin/env bash

#
# VNX installation script for Vagrant VMs
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


HOSTNAME=vnx

echo "-- Installing VNX:"

echo ""
echo "---- Changing hostname:"
echo ""

echo $HOSTNAME > /etc/hostname
hostname $HOSTNAME
sed -i -e "s/127.0.1.1.*/127.0.1.1   $HOSTNAME/" /etc/hosts

echo ""
echo "---- Installing required packages:"
echo ""

apt-get update
apt-get -y install qemu-kvm libvirt-bin vlan xterm bridge-utils screen virt-manager \
  virt-viewer libxml-checker-perl libxml-parser-perl libnetaddr-ip-perl libnet-pcap-perl \
  libnet-ipv6addr-perl liberror-perl libexception-class-perl \
  uml-utilities libxml-libxml-perl libterm-readline-perl-perl libnet-telnet-perl \
  libnet-ip-perl libreadonly-perl libmath-round-perl libappconfig-perl \
  libdbi-perl graphviz genisoimage gnome-terminal tree libio-pty-perl libsys-virt-perl \
  libfile-homedir-perl curl w3m picocom expect lxc aptsh libxml-tidy-perl inkscape \
  linux-image-extra-virtual wmctrl wireshark x11-apps

  # Add sentences to /etc/profile to set DISPLAY variable to host ip address
  # (needed for windows machines)
  cat >> /etc/profile <<EOF
if [ -z \$DISPLAY ]; then
 export DISPLAY="\$(ip route show default | head -1 | awk '{print \$3}'):0"
 #echo "Setting DISPLAY to \$DISPLAY"
fi
EOF

echo ""
echo "---- Installing VNX application:"
echo ""

mkdir /tmp/vnx-update
cd /tmp/vnx-update
rm -rf /tmp/vnx-update/vnx-*
wget http://vnx.dit.upm.es/vnx/vnx-latest.tgz
tar xfvz vnx-latest.tgz
cd vnx-*
sudo ./install_vnx

sudo mv /usr/share/vnx/etc/vnx.conf.sample /etc/vnx.conf
# Set svg viewer to inkview
sed -i -e '/\[general\]/{:a;n;/^$/!ba;i\svg_viewer=inkview' -e '}' /etc/vnx.conf
# Set console to xterm
sed -i -e '/console_term/d' /etc/vnx.conf
sed -i -e '/\[general\]/{:a;n;/^$/!ba;i\console_term=xterm' -e '}' /etc/vnx.conf

echo ""
echo "---- Installing VNX LXC rootfs:"
echo ""

cd /usr/share/vnx/filesystems/
/usr/bin/vnx_download_rootfs -l -r vnx_rootfs_lxc_ubuntu-14.04-v025 -y
ln -s rootfs_lxc_ubuntu rootfs_lxc

echo "-- Rebooting to finish installation..."
reboot

echo "----"