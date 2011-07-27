#!/usr/bin/perl

my $usage = <<EOF;
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Virtual Networks over LinuX (VNX) -- http://www.dit.upm.es/vnx - vnx@dit.upm.es          
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

vnx_set_def_rootfs:  Creates links for the default VNX root filesystem

Usage: vnx_set_def_rootfs <rootfs_name> <dist_version> <rootfs_version>

Examples: 
  'vnx_set_def_rootfs ubuntu 10.04 v021' command creates the following link:

        /usr/share/vnx/filesystems/rootfs_ubuntu -->
            /usr/share/vnx/filesystems/vnx_rootfs_ubuntu-10.04-v021.qcow2
       
  'vnx_set_def_rootfs fedora-gui 14 v021' command creates the following link:

        /usr/share/vnx/filesystems/vnx_rootfs_fedora-gui -->
            /usr/share/vnx/filesystems/vnx_rootfs_fedora-14-gui-v021.qcow2
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
EOF


# Command line arguments process 
if ($#ARGV != 2) {
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
my $rootfsType = $ARGV[0];
my $distVersion = $ARGV[1];
my $rootfsVersion = $ARGV[2];
my $guiDist;
my $rootfsFname;
my $linkName;

print "vnx_set_def_rootfs:   \n";
print "    rootfs type=$rootfsType\n    distribution version=$distVersion\n    rootfs version=$rootfsVersion\n";

if ($rootfsType =~ /.*-gui/) {
	$rootfsType =~ s/-gui//;
	#print "gui distrib\n";
	$guiDist = 'true';
}

if ($guiDist) {
	$rootfsFname = "$VNXFSDIR/vnx_rootfs_$rootfsType-$distVersion-gui-$rootfsVersion.qcow2";
	$linkName = "$VNXFSDIR/rootfs_$rootfsType-gui";
} else {
	$rootfsFname = "$VNXFSDIR/vnx_rootfs_$rootfsType-$distVersion-$rootfsVersion.qcow2";
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



  


