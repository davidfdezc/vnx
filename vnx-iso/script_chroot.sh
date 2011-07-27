#!/bin/bash

function install_basic {

# Installs basic VNX requirements, VNX, and two filesystems

	# Package Installation
	# Enable universe and multiverse
	cp /etc/apt/sources.list /etc/apt/sources.list.backup
	sed -i -e "s/# deb/deb/g" /etc/apt/sources.list

	# Update and install
	apt-get update
	apt-get install -y build-essential qemu-kvm libvirt-bin vlan xterm bridge-utils  screen virt-manager virt-viewer libxml-checker-perl libxml-parser-perl libnetaddr-ip-perl libnet-pcap-perl libnet-ipv6addr-perl liberror-perl libexception-class-perl uml-utilities libxml-libxml-perl libxml2-dev libgnutls-dev libdevmapper-dev libterm-readline-perl-perl libnet-telnet-perl libnet-ip-perl libreadonly-perl libmath-round-perl libappconfig-perl libdbi-perl graphviz libnl-dev genisoimage gnome-terminal libfile-homedir-perl

	# If you use 64 bits version of Ubuntu, install 32 bits compatibility libraries:
	# apt-get install ia32-libs

	#Install libvirt 0.8.5:
	/etc/init.d/libvirt-bin stop
	wget http://libvirt.org/sources/libvirt-0.8.5.tar.gz
	tar xfvz libvirt-0.8.5.tar.gz
	cd libvirt-0.8.5
	./configure --without-xen --prefix=/usr && make && make install
	start libvirt-bin

	# For Ubuntu 10.04, just install the libsys-virt-perl package
	apt-get install libsys-virt-perl

	# Install VNX:
	mkdir /tmp/vnx-update
	cd /tmp/vnx-update
	wget -N http://idefix.dit.upm.es/download/vnx/vnx-latest.tgz
	tar xfvz vnx-latest.tgz
	cd vnx-*
	./install_vnx

	# Create the VNX config file (/etc/vnx.conf). You just can move the sample config file:
	mv /etc/vnx.conf.sample /etc/vnx.conf

	# root file systems
	# ubuntu server
	wget -N http://idefix.dit.upm.es/download/vnx/filesystems/root_fs_ubuntu-10.10-v02.qcow2.bz2
	bunzip2 root_fs_ubuntu-10.10-v02.qcow2.bz2
	ln -s root_fs_ubuntu-10.10-v02.qcow2 root_fs_ubuntu

	# VNUML root_fs_tutorial and kernel
	cd /usr/share/vnx/filesystems
	wget -N http://idefix.dit.upm.es/download/vnx/filesystems/root_fs_tutorial-0.6.0.bz2
	bunzip2 root_fs_tutorial-0.6.0.bz2
	ln -s root_fs_tutorial-0.6.0 root_fs_tutorial
	cd /usr/share/vnx/kernels
	wget -N http://jungla.dit.upm.es/~vnx/download/kernels/linux-2.6.18.1-bb2-xt-4m
	chmod +x linux-2.6.18.1-bb2-xt-4m
	ln -s linux-2.6.18.1-bb2-xt-4m linux
}


function install_rest {

# Installs all the other filesystems

	# ubuntu with gui
	wget -N http://idefix.dit.upm.es/download/vnx/filesystems/root_fs_ubuntu-10.10-gui-v01.qcow2.bz2
	bunzip2 root_fs_ubuntu-10.10-gui-v01.qcow2.bz2
	ln -s root_fs_ubuntu-10.10-gui-v01.qcow2 root_fs_ubuntu-gui

	# freebsd server
	wget -N http://idefix.dit.upm.es/download/vnx/filesystems/root_fs_freebsd-8.1-v01.qcow2.bz2
	bunzip2 root_fs_freebsd-8.1-v01.qcow2.bz2
	ln -s root_fs_freebsd-8.1-v01.qcow2 root_fs_freebsd

	# freebsd gui
	wget -N http://idefix.dit.upm.es/download/vnx/filesystems/root_fs_freebsd-8.1-gui-v01.qcow2.bz2
	bunzip2 root_fs_freebsd-8.1-gui-v01.qcow2.bz2
	ln -s root_fs_freebsd-8.1-gui-v01.qcow2 root_fs_freebsd-gui

	# Dynamips support
	apt-get install dynamips dynagen


	# Create file /etc/init.d/dynamips
	echo '#!/bin/sh
# Start/stop the dynamips program as a daemon.
#
### BEGIN INIT INFO
# Provides:          dynamips
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Cisco hardware emulator daemon
### END INIT INFO

DAEMON=/usr/bin/dynamips
NAME=dynamips
PORT=7200
PIDFILE=/var/run/$NAME.pid 
LOGFILE=/var/log/$NAME.log
DESC="Cisco Emulator"
SCRIPTNAME=/etc/init.d/$NAME

test -f $DAEMON || exit 0

. /lib/lsb/init-functions


case "$1" in
start)  log_daemon_msg "Starting $DESC " "$NAME"
        start-stop-daemon --start --chdir /tmp --background --make-pidfile --pidfile $PIDFILE --name $NAME --startas $DAEMON -- -H $PORT -l $LOGFILE
        log_end_msg $?
        ;;
stop)   log_daemon_msg "Stopping $DESC " "$NAME"
        start-stop-daemon --stop --quiet --pidfile $PIDFILE --name $NAME
        log_end_msg $?
        ;;
restart) log_daemon_msg "Restarting $DESC " "$NAME"
        start-stop-daemon --stop --retry 5 --quiet --pidfile $PIDFILE --name $NAME
        start-stop-daemon --start --chdir /tmp --background --make-pidfile --pidfile $PIDFILE --name $NAME --startas $DAEMON -- -H $PORT -l $LOGFILE
        log_end_msg $?
        ;;
status)
        status_of_proc -p $PIDFILE $DAEMON $NAME && exit 0 || exit $? 
        #status $NAME
        #RETVAL=$?
        ;; 
*)      log_action_msg "Usage: $SCRIPTNAME {start|stop|restart|status}"
        exit 2
        ;;
esac
exit 0' > /etc/init.d/dynamips

	# Set execution permissions for the script and add it to system start-up
	chmod +x /etc/init.d/dynamips
	update-rc.d dynamips defaults
	/etc/init.d/dynamips start

	# Download and install cisco IOS image: ARREGLAR LINK!!!
	cd /usr/share/vnx/filesystems
	wget ... c3640-js-mz.124-19.image
	ln -s c3640-js-mz.124-19.image c3640

	# Calculate the idle-pc value for your computer following the procedure in http://dynagen.org/tutorial.htm: 
	dynagen /usr/share/vnx/examples/R.net
	console R     # type 'no' to exit the config wizard and wait 
	              # for the router to completely start 
	idle-pc get R

	# Olive: Download old qemu bios from 0.10.6 version and copy it to /usr/share/qemu directory:
	wget http://downloads.sourceforge.net/project/kvm/qemu-kvm/0.10.6/qemu-kvm-0.10.6.tar.gz
	tar xfvz qemu-kvm-0.10.6.tar.gz
	cp qemu-kvm-0.10.6/pc-bios/bios.bin /usr/share/qemu-kvm/bios-0.10.6.bin
	rm qemu-kvm-0.10.6.tar.gz
}



INSTALL_TYPE=""

cdir=$( dirname $0 )
cd $cdir

# To avoid locale issues and in order to import GPG keys
export HOME=/root
export LC_ALL=C


install_basic
#echo "instalo basic ($INSTALL_TYPE)"
#sleep 10
if [[ $INSTALL_TYPE = "full" ]]; then
	install_rest
fi

	# sustituir 2.6.15-26-k7 por la versión del kernel que salga en /lib/modules
	# hacer ls de /lib/modules, guardarlo en variable, y hacer mk... $variable
	#mkinitramfs -o /initrd.gz 2.6.32-28-generic
#	kvers=$(ls /lib/modules)
#        mkinitramfs -o /initrd.lz $kvers



cd $cdir
rm -rf script_chroot
exit 0


