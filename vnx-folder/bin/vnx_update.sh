#!/bin/bash

# Script to update the VNX version from idefix.dit.upm.es 

REMOTETMPDIR=vnx-update
VNXLATESTURL='http://idefix.dit.upm.es/download/vnx/vnx-latest.tgz'

# Create tmpdir and delete content if already created
mkdir -vp /tmp/$REMOTETMPDIR
rm -vrf /tmp/$REMOTETMPDIR/*
cd /tmp/$REMOTETMPDIR/

# Download latest version from idefix.dit.upm.es
wget $VNXLATESTURL

# Uncompress vnx and install
tar xfvz vnx-latest.tgz 
cd vnx-*
./install_vnx

vnx --version