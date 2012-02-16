#!/bin/bash

if [ $# -ne 1 ]
then
  echo "Script to update VNX on another host"
  echo ""
  echo "Usage: `basename $0` <host name or ip address>"
  exit 1
fi


HOST=$1
VNXTARFILE=/usr/share/vnx/src/vnx-latest.tgz
REMOTETMPDIR=vnx-update

#ssh $1 "cd /tmp; mkdir -p $REMOTETMPDIR && rm -rf $REMOTETMPDIR/\*"
# Create tmpdir and delete content if already created
ssh $1 "mkdir -vp /tmp/$REMOTETMPDIR; rm -vrf /tmp/$REMOTETMPDIR/*"
# Copy tar file
scp $VNXTARFILE $1:/tmp/$REMOTETMPDIR
# Uncompress vnx and install
ssh $1 "cd /tmp/$REMOTETMPDIR; tar xfvz vnx-latest.tgz; cd vnx-*; ./install_vnx"
