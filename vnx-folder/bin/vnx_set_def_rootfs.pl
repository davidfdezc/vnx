#!/usr/bin/perl

use strict;

my $usage = <<EOF;
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Virtual Networks over LinuX (VNX) -- http://www.dit.upm.es/vnx - vnx\@dit.upm.es          
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

vnx_set_def_rootfs:  Creates links for the default VNX root filesystem

Usage: vnx_set_def_rootfs <virtplatform> <rootfs_name> <dist_version> <rootfs_version>

Examples: 
  'vnx_set_def_rootfs kvm ubuntu 10.04 v021' command creates the following link:

        /usr/share/vnx/filesystems/rootfs_ubuntu -->
            /usr/share/vnx/filesystems/vnx_rootfs_kvm_ubuntu-10.04-v021.qcow2
       
  'vnx_set_def_rootfs kvm fedora-gui 14 v021' command creates the following link:

        /usr/share/vnx/filesystems/vnx_rootfs_fedora-gui -->
            /usr/share/vnx/filesystems/vnx_rootfs_kvm_fedora-14-gui-v021.qcow2
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
EOF


# Command line arguments process 
if ($#ARGV != 3) {
	print "$usage";
    exit (1);
}

for (my $i=0; $i <= $#ARGV; $i++) {
        if ( ($ARGV[$i] eq "-h") or ($ARGV[$i] eq "--help") ) {
                print "$usage\n";
                exit (1);
        }
}

my $VNXFSDIR = "/usr/share/vnx/filesystems";
my $virtPlatform = $ARGV[0];
my $rootfsType = $ARGV[1];
my $distVersion = $ARGV[2];
my $rootfsVersion = $ARGV[3];
my $guiDist;
my $rootfsFname;
my $linkName;

print "vnx_set_def_rootfs:   \n";
print "    virt platform=$virtPlatform\n    rootfs type=$rootfsType\n    distribution version=$distVersion\n    rootfs version=$rootfsVersion\n";

if ($rootfsType =~ /.*-gui/) {
	$rootfsType =~ s/-gui//;
	#print "gui distrib\n";
	$guiDist = 'true';
}

if ($guiDist) {
	$rootfsFname = "$VNXFSDIR/vnx_rootfs_${virtPlatform}_${rootfsType}-${distVersion}-gui-${rootfsVersion}.qcow2";
	$linkName = "$VNXFSDIR/rootfs_$rootfsType-gui";
} else {
	$rootfsFname = "$VNXFSDIR/vnx_rootfs_${virtPlatform}_${rootfsType}-${distVersion}-${rootfsVersion}.qcow2";
	$linkName = "$VNXFSDIR/rootfs_$rootfsType";
}

#print "$rootfsFname\n";
#print "$linkName\n";

if (-f $rootfsFname) {
	print "\nCreating link:\n$linkName -->\n        $rootfsFname\n";
	my $res=`rm -vf $linkName`; #print $res;
	$res=`ln -vs $rootfsFname $linkName`; #print $res;
} else {
	print "ERROR: $rootfsFname does not exist\n"
}



  


