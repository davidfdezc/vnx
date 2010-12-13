#/bin/bash

XMLFILE=$1
echo $XMLFILE
# Find tag in the xml, convert tabs to spaces, remove leading spaces, remove the tag.
VMNAME=$( grep "<name>" $XMLFILE | \
        tr '\011' '\040' | \
        sed -e 's/^[ ]*//' \
            -e 's/^<.*>\([^<].*\)<.*>$/\1/' )
echo Starting $VMNAME virtual machine
virsh create $XMLFILE && virt-viewer $VMNAME &
