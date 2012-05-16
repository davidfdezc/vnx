#/bin/bash


function createXML {

XMLFILE=$1
ROOTFS=$2
ROOTFSNAME=$3

cat << EOF > $XMLFILE
<domain type='kvm'>
  <name>$ROOTFSNAME</name>
  <memory>524288</memory>
  <vcpu>1</vcpu>
  <os>
	<type arch="i686">hvm</type>
	<boot dev='hd'/>
	<boot dev='cdrom'/>
  </os>
  <features>
	 <pae/>
	 <acpi/>
	 <apic/>
  </features>
  <clock sync="localtime"/>
  <devices>
	<emulator>/usr/bin/kvm</emulator>
	<disk type='file' device='disk'>
	  <source file='$ROOTFS'/>
	  <target dev='hda'/>
	  <driver name="qemu" type="qcow2"/>
	</disk>
	<disk type='file' device='cdrom'>
	  <!--source file='/almacen/iso/ubuntu-10.04.1-server-i386.iso'/-->
	  <target dev='hdb'/>
	</disk>
	<interface type='network'>
	  <source network='default'/>
	</interface>
	<graphics type='vnc'/>
    <serial type="pty">
      <target port="0"/>
     </serial>
     <console type="pty">
      <target port="0"/>
     </console>
     <serial type="unix">
      <source mode="bind" path="/tmp/${ROOTFSNAME}_socket"/>
      <target port="1"/>
     </serial>
	
  </devices>
</domain>
EOF
}

if [ $# -ne 1 ]
then
  echo "Usage: `basename $0` <rootfs_to_modify>"
  exit 1
fi


# cmd parameters
ROOTFS=$(readlink -f $1)
ROOTFSNAME=$( basename $ROOTFS )

XMLFILE="/tmp/vnx_modify_rootfs/$ROOTFSNAME.$$.xml"

mkdir -p /tmp/vnx_modify_rootfs/

echo "--"
echo "-- Creating libvirt XML file $XMLFILE..."
createXML $XMLFILE $ROOTFS $ROOTFSNAME
echo "-- Starting $ROOTFSNAME virtual machine..."
virsh create $XMLFILE && virt-viewer $ROOTFSNAME &
