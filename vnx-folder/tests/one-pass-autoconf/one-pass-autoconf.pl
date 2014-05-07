#!/usr/bin/perl

use strict;
use warnings;

use Term::ReadKey;
use VNX::Globals;
use VNX::FileChecks;
use XML::LibXML;


#my $rootfs='/usr/share/vnx/filesystems/vnx_rootfs_kvm_ubuntu-14.04-v025-mod.qcow2';
#my $rootfs='/usr/share/vnx/filesystems/vnx_rootfs_kvm_freebsd-9.1-v025-mod.qcow2';
my $rootfs='/usr/share/vnx/filesystems/vnx_rootfs_kvm_fedora-18-v025-mod.qcow2';

my $rootfs_mount_dir='/mnt';
my $vnxboot_file='/root/vnx/workspace/vnx/vnx-folder/tests/one-pass-autoconf/r1_cconf.xml';

my $get_os_distro_code = get_code_of_get_os_distro();

# Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
# host files will be modified instead of rootfs image ones
unless ( defined($rootfs_mount_dir) && $rootfs_mount_dir ne '' && $rootfs_mount_dir ne '/' ) {
	die;
}

#print $get_os_distro_code; exit;

#
# Mount the root filesystem
# We loop mounting all image partitions till we find a /etc directory
# 
my $mounted;

for ( my $i = 1; $i < 5; $i++) {

    wlog (VVV,  "Trying: vnx_mount_rootfs -p $i -r $rootfs $rootfs_mount_dir");

    system "vnx_mount_rootfs -b -p $i -r $rootfs $rootfs_mount_dir";
    if ( $? != 0 ) {
        wlog (VVV,  "Cannot mount partition $i of '$rootfs'");
    	next
    } else {
        system "ls $rootfs_mount_dir/etc  > /dev/null 2>&1";
        unless ($?) {
            $mounted='true';
            last	
        } else {
            wlog (VVV,  "/etc not found in partition $i of '$rootfs'");
        }
    }
    system "vnx_mount_rootfs -b -u $rootfs_mount_dir";
}

unless ($mounted) {
    wlog (VVV,  "ERROR: cannot mount '$rootfs'. One-pass-autoconfiguration not possible");
	exit (1);
}

#
# Guess image OS distro
#
# First, copy "get_os_distro" script to /tmp on image
my $get_os_distro_file = "$rootfs_mount_dir/tmp/get_os_distro"; 
open (GETOSDISTROFILE, "> $get_os_distro_file"); # or vnx_die ("cannot open file $get_os_distro_file");
print GETOSDISTROFILE "$get_os_distro_code";
close (GETOSDISTROFILE); 
system "chmod +x $rootfs_mount_dir/tmp/get_os_distro";
#pak();

# Second, execute the script chrooted to the image
my $os_distro = `LANG=C chroot $rootfs_mount_dir /tmp/get_os_distro`;
my @platform = split(/,/, $os_distro);
    
wlog (VVV, "$platform[0],$platform[1],$platform[2],$platform[3],$platform[4],$platform[5]");

# Third, delete the script
system "rm $rootfs_mount_dir/tmp/get_os_distro";
#pak("get_os_distro deleted");


# Parse VM config file
my $parser = XML::LibXML->new;
my $dom    = $parser->parse_file($vnxboot_file);

# Call autoconfiguration
if ($platform[0] eq 'Linux'){
    
    if ($platform[1] eq 'Ubuntu')    {
        wlog (VVV,  "Ubuntu");
        autoconfigure_ubuntu ($dom, $rootfs_mount_dir)
    }           
    elsif ($platform[1] eq 'Fedora') { 
        wlog (VVV,  "Fedora");
        autoconfigure_redhat ($dom, $rootfs_mount_dir, 'fedora')
    }
    elsif ($platform[1] eq 'CentOS') { 
        wlog (VVV,  "CentOS");
        autoconfigure_redhat ($dom, $rootfs_mount_dir, 'centos')
    }
    
} elsif ($platform[0] eq 'FreeBSD'){
        wlog (VVV,  "FreeBSD");
        autoconfigure_freebsd ($dom, $rootfs_mount_dir)
        
} else {
    wlog (VVV, "ERROR: unknown platform ($platform[0]). Only Linux and FreeBSD supported.");
    exit (1);
}

# Get the id from the VM config file 
my $cid   = $dom->getElementsByTagName("id")->[0]->getFirstChild->getData;
chomp($cid);

# And save it to the VNACED_STATUS file
my $vnxaced_status_file = $rootfs_mount_dir . $VNXACED_STATUS;
#pak("before set_conf_value");
print "before:\n" . `cat $vnxaced_status_file`;
system "sed -i -e '/cmd_id/d' $vnxaced_status_file";
system "echo \"cmd_id=$cid\" >> $vnxaced_status_file";
print "after:\n" . `cat $vnxaced_status_file`;

pak("before calling umount");

system "vnx_mount_rootfs -b -u $rootfs_mount_dir";




sub get_code_of_get_os_distro {
    
return <<'EOF';
#!/usr/bin/perl

use strict;
use warnings;

my @os_distro = get_os_distro();

print join(", ", @os_distro);

#my @platform = split(/,/, $os_distro);
#print "$platform[0],$platform[1],$platform[2],$platform[3],$platform[4],$platform[5]\n";

sub get_os_distro {

    my $OS=`uname -s`; chomp ($OS);
    my $REV=`uname -r`; chomp ($REV);
    my $MACH=`uname -m`; chomp ($MACH);
    my $ARCH;
    my $OSSTR;
    my $DIST;
    my $KERNEL;
    my $PSEUDONAME;
        
    if ( $OS eq 'SunOS' ) {
            $OS='Solaris';
            $ARCH=`uname -p`;
            $OSSTR= "$OS,$REV,$ARCH," . `uname -v`;
    } elsif ( $OS eq "AIX" ) {
            $OSSTR= "$OS," . `oslevel` . "," . `oslevel -r`;
    } elsif ( $OS eq "Linux" ) {
            $KERNEL=`uname -r`;
            if ( -e '/etc/redhat-release' ) {
            my $relfile = `cat /etc/redhat-release`;
            my @fields  = split(/ /, $relfile);
                    $DIST = $fields[0];
                    $REV = $fields[2];
                    $PSEUDONAME = $fields[3];
                    $PSEUDONAME =~ s/\(//; $PSEUDONAME =~ s/\)//;
        } elsif ( -e '/etc/SuSE-release' ) {
                    $DIST=`cat /etc/SuSE-release | tr "\n" ' '| sed s/VERSION.*//`;
                    $REV=`cat /etc/SuSE-release | tr "\n" ' ' | sed s/.*=\ //`;
            } elsif ( -e '/etc/mandrake-release' ) {
                    $DIST='Mandrake';
                    $PSEUDONAME=`cat /etc/mandrake-release | sed s/.*\(// | sed s/\)//`;
                    $REV=`cat /etc/mandrake-release | sed s/.*release\ // | sed s/\ .*//`;
            } elsif ( -e '/etc/lsb-release' ) {
                    $DIST= `cat /etc/lsb-release | grep DISTRIB_ID | sed 's/DISTRIB_ID=//'`; 
                    $REV = `cat /etc/lsb-release | grep DISTRIB_RELEASE | sed 's/DISTRIB_RELEASE=//'`;
                    $PSEUDONAME = `cat /etc/lsb-release | grep DISTRIB_CODENAME | sed 's/DISTRIB_CODENAME=//'`;
            } elsif ( -e '/etc/debian_version' ) {
                    $DIST= "Debian"; 
                    $REV=`cat /etc/debian_version`;
        }
            if ( -e '/etc/UnitedLinux-release' ) {
                    $DIST=$DIST . " [" . `cat /etc/UnitedLinux-release | tr "\n" ' ' | sed s/VERSION.*//` . "]";
            }
        chomp ($KERNEL); chomp ($DIST); chomp ($PSEUDONAME); chomp ($REV);
            $OSSTR="$OS,$DIST,$REV,$PSEUDONAME,$KERNEL,$MACH";
    } elsif ( $OS eq "FreeBSD" ) {
            $DIST= "FreeBSD";
        $REV =~ s/-RELEASE//;
            $OSSTR="$OS,$DIST,$REV,$PSEUDONAME,$KERNEL,$MACH";
    }
return $OSSTR;
}
EOF
}

#
# autoconfigure for Ubuntu             
#
sub autoconfigure_ubuntu {
    
    my $dom = shift;
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $error;
    
    my $logp = "autoconfigure_ubuntu> ";

    wlog (VVV, "rootfs_mdir=$rootfs_mdir", $logp);
    
	# Big danger if rootfs mount directory ($rootfs_mdir) is empty: 
	# host files will be modified instead of rootfs image ones
	unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' && $rootfs_mdir ne '/' ) {
	    die;
	}    

    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # Files modified
    my $interfaces_file = "$rootfs_mdir" . "/etc/network/interfaces";
    my $sysctl_file     = "$rootfs_mdir" . "/etc/sysctl.conf";
    my $hosts_file      = "$rootfs_mdir" . "/etc/hosts";
    my $hostname_file   = "$rootfs_mdir" . "/etc/hostname";
    my $resolv_file     = "$rootfs_mdir" . "/etc/resolv.conf";
    my $rules_file      = "$rootfs_mdir" . "/etc/udev/rules.d/70-persistent-net.rules";
    
    # Backup and delete /etc/resolv.conf file
    if (-f $resolv_file ) {
	    system "cp $resolv_file ${resolv_file}.bak";
	    system "rm -f $resolv_file";
    }
        
    # before the loop, backup /etc/udev/...70
    # and /etc/network/interfaces
    # and erase their contents
    wlog (VVV, "   configuring $rules_file and $interfaces_file...");
    if (-f $rules_file) {
        system "cp $rules_file $rules_file.backup";
    }
    system "echo \"\" > $rules_file";
    open RULES, ">" . $rules_file or return "error opening $rules_file";
    system "cp $interfaces_file $interfaces_file.backup";
    system "echo \"\" > $interfaces_file";
    open INTERFACES, ">" . $interfaces_file or return "error opening $interfaces_file";

    print INTERFACES "\n";
    print INTERFACES "auto lo\n";
    print INTERFACES "iface lo inet loopback\n";

    # Network routes configuration: <route> tags
    my @ip_routes;   # Stores the route configuration lines
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ($route_type eq 'ipv4') {
            if ($route eq 'default') {
                push (@ip_routes, "   up route add -net default gw " . $route_gw . "\n");
            } else {
                push (@ip_routes, "   up route add -net $route gw " . $route_gw . "\n");
            }
        } elsif ($route_type eq 'ipv6') {
            if ($route eq 'default') {
                push (@ip_routes, "   up route -A inet6 add default gw " . $route_gw . "\n");
            } else {
                push (@ip_routes, "   up route -A inet6 add $route gw " . $route_gw . "\n");
            }
        }
    }   

    # Network interfaces configuration: <if> tags
    my @if_list = $vm->getElementsByTagName("if");
    for (my $j = 0 ; $j < @if_list; $j++){
        my $if  = $if_list[$j];
        my $id  = $if->getAttribute("id");
        my $net = $if->getAttribute("net");
        my $mac = $if->getAttribute("mac");
        $mac =~ s/,//g;

        my @if_name;
        # Special case: loopback interface
        if ( $net eq "lo" ) {
            @if_name = "lo:" . $id;
        } else {
            @if_name = "eth" . $id;
        }

        print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac .  "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . @if_name . "\"\n\n";
        #print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";
        print INTERFACES "auto " . @if_name . "\n";

        my @ipv4_list = $if->getElementsByTagName("ipv4");
        my @ipv6_list = $if->getElementsByTagName("ipv6");

        if ( (@ipv4_list == 0 ) && ( @ipv6_list == 0 ) ) {
            # No addresses configured for the interface. We include the following commands to 
            # have the interface active on start
            print INTERFACES "iface " . @if_name . " inet manual\n";
            print INTERFACES "  up ifconfig " . @if_name . " 0.0.0.0 up\n";
        } else {
            # Config IPv4 addresses
            for ( my $j = 0 ; $j < @ipv4_list ; $j++ ) {

                my $ipv4 = $ipv4_list[$j];
                my $mask = $ipv4->getAttribute("mask");
                my $ip   = $ipv4->getFirstChild->getData;

                if ($j == 0) {
                    print INTERFACES "iface " . @if_name . " inet static\n";
                    print INTERFACES "   address " . $ip . "\n";
                    print INTERFACES "   netmask " . $mask . "\n";
                } else {
                    print INTERFACES "   up /sbin/ifconfig " . @if_name . " inet add " . $ip . " netmask " . $mask . "\n";
                }
            }
            # Config IPv6 addresses
            for ( my $j = 0 ; $j < @ipv6_list ; $j++ ) {

                my $ipv6 = $ipv6_list[$j];
                my $ip   = $ipv6->getFirstChild->getData;
                my $mask = $ip;
                $mask =~ s/.*\///;
                $ip =~ s/\/.*//;

                if ($j == 0) {
                    print INTERFACES "iface " . @if_name . " inet6 static\n";
                    print INTERFACES "   address " . $ip . "\n";
                    print INTERFACES "   netmask " . $mask . "\n\n";
                } else {
                    print INTERFACES "   up /sbin/ifconfig " . @if_name . " inet6 add " . $ip . "/" . $mask . "\n";
                }
            }
            # TODO: To simplify and avoid the problems related with some routes not being installed 
            # due to the interfaces start order, we add all routes to all interfaces. This should be 
            # refined to add only the routes going to each interface
            print INTERFACES @ip_routes;

        }
    }
        
    close RULES;
    close INTERFACES;
        
    # Packet forwarding: <forwarding> tag
    my $ipv4_forwarding = 0;
    my $ipv6_forwarding = 0;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    for (my $j = 0 ; $j < @forwarding_list ; $j++){
        my $forwarding = $forwarding_list[$j];
        my $forwarding_type = $forwarding->getAttribute("type");
        if ($forwarding_type eq "ip"){
            $ipv4_forwarding = 1;
            $ipv6_forwarding = 1;
        } elsif ($forwarding_type eq "ipv4"){
            $ipv4_forwarding = 1;
        } elsif ($forwarding_type eq "ipv6"){
            $ipv6_forwarding = 1;
        }
    }
    wlog (VVV, "   configuring ipv4 ($ipv4_forwarding) and ipv6 ($ipv6_forwarding) forwarding in $sysctl_file...");
    system "echo >> $sysctl_file ";
    system "echo '# Configured by VNX' >> $sysctl_file ";
    system "echo 'net.ipv4.ip_forward=$ipv4_forwarding' >> $sysctl_file ";
    system "echo 'net.ipv6.conf.all.forwarding=$ipv6_forwarding' >> $sysctl_file ";

    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file");
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '1i127.0.0.1  localhost.localdomain   localhost' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change /etc/hostname
    system "echo $vm_name > $hostname_file";

    return $error;
    
}


#
# autoconfigure for Redhat (Fedora and CentOS)             
#
sub autoconfigure_redhat {

    my $dom = shift;
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $os_type = shift; # fedora or centos
    my $error;

    my $logp = "autoconfigure_redhat ($os_type)> ";

    # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
    # host files will be modified instead of rootfs image ones
    unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' && $rootfs_mdir ne '/' ) {
        die;
    }    
        
    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # Files modified
    my $interfaces_file = "$rootfs_mdir" . "/etc/network/interfaces";
    my $sysctl_file     = "$rootfs_mdir" . "/etc/sysctl.conf";
    my $hosts_file      = "$rootfs_mdir" . "/etc/hosts";
    my $hostname_file   = "$rootfs_mdir" . "/etc/hostname";
    my $resolv_file     = "$rootfs_mdir" . "/etc/resolv.conf";
    my $rules_file      = "$rootfs_mdir" . "/etc/udev/rules.d/70-persistent-net.rules";
    my $sysconfnet_file = "$rootfs_mdir" . "/etc/sysconfig/network";
    my $sysconfnet_dir  = "$rootfs_mdir" . "/etc/sysconfig/network-scripts";

    # Delete /etc/resolv.conf file
    if (-f $resolv_file ) {
        system "cp $resolv_file ${resolv_file}.bak";
        system "rm -f $resolv_file";
    }

    system "mv $sysconfnet_file ${sysconfnet_file}.bak";
    system "cat ${sysconfnet_file}.bak | grep -v 'NETWORKING=' | grep -v 'NETWORKING_IPv6=' > $sysconfnet_file";
    system "echo NETWORKING=yes >> $sysconfnet_file";
    system "echo NETWORKING_IPV6=yes >> $sysconfnet_file";

    if (-f $rules_file) {
        system "cp $rules_file $rules_file.backup";
    }
    system "echo \"\" > $rules_file";

    wlog (VVV, "   configuring $rules_file...");
    open RULES, ">" . $rules_file or return "error opening $rules_file";

    # Delete ifcfg and route files
    system "rm -f $sysconfnet_dir/ifcfg-Auto_eth*"; 
    system "rm -f $sysconfnet_dir/ifcfg-eth*"; 
    system "rm -f $sysconfnet_dir/route-Auto*"; 
    system "rm -f $sysconfnet_dir/route6-Auto*"; 
        
    # Network interfaces configuration: <if> tags
    my @if_list = $vm->getElementsByTagName("if");
    my $first_ipv4_if;
    my $first_ipv6_if;
        
    for (my $i = 0 ; $i < @if_list ; $i++){
        my $if  = $if_list[$i];
        my $id  = $if->getAttribute("id");
        my $net = $if->getAttribute("net");
        my $mac = $if->getAttribute("mac");
        $mac =~ s/,//g;
            
        wlog (VVV, "processing if $id, net=$net, mac=$mac");            
        my @if_name;
        # Special case: loopback interface
        if ( $net eq "lo" ) {
            @if_name = "lo:" . $id;
        } else {
            @if_name = "eth" . $id;
        }
            
        if ($platform[1] eq 'Fedora') { 
            print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac .  "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . @if_name . "\"\n\n";
            #print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";

        } elsif ($platform[1] eq 'CentOS') { 
#           print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"" . @if_name . "\"\n\n";
        }

        my $if_file;
        if ($platform[1] eq 'Fedora') { 
           $if_file = "$sysconfnet_dir/ifcfg-Auto_@if_name";
        } elsif ($platform[1] eq 'CentOS') { 
            $if_file = "$sysconfnet_dir/ifcfg-@if_name";
        }
        system "echo \"\" > $if_file";
        open IF_FILE, ">" . $if_file or return "error opening $if_file";
    
        if ($platform[1] eq 'CentOS') { 
            print IF_FILE "DEVICE=@if_name\n";
        }
        print IF_FILE "HWADDR=$mac\n";
        print IF_FILE "TYPE=Ethernet\n";
        #print IF_FILE "BOOTPROTO=none\n";
        print IF_FILE "ONBOOT=yes\n";
        if ($platform[1] eq 'Fedora') { 
            print IF_FILE "NAME=\"Auto @if_name\"\n";
        } elsif ($platform[1] eq 'CentOS') { 
            print IF_FILE "NAME=\"@if_name\"\n";
        }

        print IF_FILE "IPV6INIT=yes\n";
            
        my @ipv4_list = $if->getElementsByTagName("ipv4");
        my @ipv6_list = $if->getElementsByTagName("ipv6");

        # Config IPv4 addresses
        for ( my $j = 0 ; $j < @ipv4_list ; $j++ ) {

            my $ipv4 = $ipv4_list[$j];
            my $mask = $ipv4->getAttribute("mask");
            my $ip   = $ipv4->getFirstChild->getData;

            $first_ipv4_if = "@if_name" unless defined($first_ipv4_if); 

            if ($j == 0) {
                print IF_FILE "IPADDR=$ip\n";
                print IF_FILE "NETMASK=$mask\n";
            } else {
                my $num = $j+1;
                print IF_FILE "IPADDR$num=$ip\n";
                print IF_FILE "NETMASK$num=$mask\n";
            }
        }
        # Config IPv6 addresses
        my $ipv6secs;
        for ( my $j = 0 ; $j < @ipv6_list ; $j++ ) {

            my $ipv6 = $ipv6_list[$j];
            my $ip   = $ipv6->getFirstChild->getData;

            $first_ipv6_if = "@if_name" unless defined($first_ipv6_if); 

            if ($j == 0) {
                print IF_FILE "IPV6_AUTOCONF=no\n";
                print IF_FILE "IPV6ADDR=$ip\n";
            } else {
                $ipv6secs .= " $ip" if $ipv6secs ne '';
                $ipv6secs .= "$ip" if $ipv6secs eq '';
            }
        }
        if (defined($ipv6secs)) {
            print IF_FILE "IPV6ADDR_SECONDARIES=\"$ipv6secs\"\n";
        }
        close IF_FILE;
    }
    close RULES;

    # Network routes configuration: <route> tags
    if (defined($first_ipv4_if)) {
	    my $route4_file = "$sysconfnet_dir/route-Auto_$first_ipv4_if";
	    system "echo \"\" > $route4_file";
	    open ROUTE_FILE, ">" . $route4_file or return "error opening $route4_file";
    }
    if (defined($first_ipv6_if)) {
	    my $route6_file = "$sysconfnet_dir/route6-Auto_$first_ipv6_if";
	    system "echo \"\" > $route6_file";
	    open ROUTE6_FILE, ">" . $route6_file or return "error opening $route6_file";
    }
            
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list ; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ( $route_type eq 'ipv4' && defined($first_ipv4_if) ) {
            if ($route eq 'default') {
                #print ROUTE_FILE "ADDRESS$j=0.0.0.0\n";
                #print ROUTE_FILE "NETMASK$j=0\n";
                #print ROUTE_FILE "GATEWAY$j=$route_gw\n";
                # Define the default route in $sysconfnet_file
                system "echo GATEWAY=$route_gw >> $sysconfnet_file"; 
            } else {
                my $mask = $route;
                $mask =~ s/.*\///;
                $mask = cidr_to_mask ($mask);
                $route =~ s/\/.*//;
                print ROUTE_FILE "ADDRESS$j=$route\n";
                print ROUTE_FILE "NETMASK$j=$mask\n";
                print ROUTE_FILE "GATEWAY$j=$route_gw\n";
            }
        } elsif ($route_type eq 'ipv6' && defined($first_ipv6_if) ) {
            if ($route eq 'default') {
                print ROUTE6_FILE "2000::/3 via $route_gw metric 0\n";
            } else {
                print ROUTE6_FILE "$route via $route_gw metric 0\n";
            }
        }
    }
    close ROUTE_FILE  if defined($first_ipv4_if);
    close ROUTE6_FILE if defined($first_ipv6_if);
        
    # Packet forwarding: <forwarding> tag
    my $ipv4_forwarding = 0;
    my $ipv6_forwarding = 0;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    for (my $j = 0 ; $j < @forwarding_list ; $j++){
        my $forwarding = $forwarding_list[$j];
        my $forwarding_type = $forwarding->getAttribute("type");
        if ($forwarding_type eq "ip"){
            $ipv4_forwarding = 1;
            $ipv6_forwarding = 1;
        } elsif ($forwarding_type eq "ipv4"){
            $ipv4_forwarding = 1;
        } elsif ($forwarding_type eq "ipv6"){
            $ipv6_forwarding = 1;
        }
    }
    wlog (VVV, "   configuring ipv4 ($ipv4_forwarding) and ipv6 ($ipv6_forwarding) forwarding in $sysctl_file...");
    system "echo >> $sysctl_file ";
    system "echo '# Configured by VNX' >> $sysctl_file ";
    system "echo 'net.ipv4.ip_forward=$ipv4_forwarding' >> $sysctl_file ";
    system "echo 'net.ipv6.conf.all.forwarding=$ipv6_forwarding' >> $sysctl_file ";

    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file");
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '1i127.0.0.1  localhost.localdomain   localhost' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change /etc/hostname
    system "echo $vm_name > $hostname_file";

    #system "hostname $vm_name";
    system "mv $sysconfnet_file ${sysconfnet_file}.bak";
    system "cat ${sysconfnet_file}.bak | grep -v HOSTNAME > $sysconfnet_file";
    system "echo HOSTNAME=$vm_name >> $sysconfnet_file";

    return $error;    
}

#
# autoconfigure for FreeBSD             
#
sub autoconfigure_freebsd {

    my $dom = shift;
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $error;

    my $logp = "autoconfigure_freebsd> ";

    # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
    # host files will be modified instead of rootfs image ones
    unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' && $rootfs_mdir ne '/' ) {
        die;
    }    

    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # IF prefix names assigned to interfaces  
    my $IF_MGMT_PREFIX="re";    # type rtl8139 for management if    
    my $IF_PREFIX="em";         # type e1000 for the rest of ifs   
    
    # Files to modify
    my $hosts_file      = "$rootfs_mdir" . "/etc/hosts";
    my $hostname_file   = "$rootfs_mdir" . "/etc/hostname";
    my $rc_file         = "$rootfs_mdir" . "/etc/rc.conf";

    # before the loop, backup /etc/rc.conf
    wlog (VVV, "   configuring /etc/rc.conf...");
    system "cp $rc_file $rc_file.backup";

    open RC, ">>" . $rc_file or return "error opening $rc_file";

    chomp (my $now = `date`);

    print RC "\n";
    print RC "#\n";
    print RC "# VNX Autoconfiguration commands ($now)\n";
    print RC "#\n";
    print RC "\n";

    print RC "hostname=\"$vm_name\"\n";
    print RC "sendmail_enable=\"NONE\"\n"; #avoids some startup errors

    # Network interfaces configuration: <if> tags
    my @if_list = $vm->getElementsByTagName("if");
    my $k = 0; # Index to the next $IF_PREFIX interface to be used
    for (my $i = 0 ; $i < @if_list; $i++){
        my $if = $if_list[$i];
        my $id    = $if->getAttribute("id");
        my $net   = $if->getAttribute("net");
        my $mac   = $if->getAttribute("mac");
        $mac =~ s/,//g; 
        
        # IF names
        my $if_orig_name;
        my $if_new_name;
        if ($id eq 0) { # Management interface 
            $if_orig_name = $IF_MGMT_PREFIX . "0";    
            $if_new_name = "eth0";
        } else { 
            my $if_num = $k;
            $k++;
            $if_orig_name = $IF_PREFIX . $if_num;    
            $if_new_name = "eth" . $id;
        }

        print RC "ifconfig_" . $if_orig_name . "_name=\"" . $if_new_name . "\"\n";
    
        my $alias_num=-1;
                
        # IPv4 addresses
        my @ipv4_list = $if->getElementsByTagName("ipv4");
        for ( my $j = 0 ; $j < @ipv4_list ; $j++ ) {

            my $ipv4 = $ipv4_list[$j];
            my $mask = $ipv4->getAttribute("mask");
            my $ip   = $ipv4->getFirstChild->getData;

            if ($alias_num == -1) {
                print RC "ifconfig_" . $if_new_name . "=\"inet " . $ip . " netmask " . $mask . "\"\n";
            } else {
                print RC "ifconfig_" . $if_new_name . "_alias" . $alias_num . "=\"inet " . $ip . " netmask " . $mask . "\"\n";
            }
            $alias_num++;
        }

        # IPv6 addresses
        my @ipv6_list = $if->getElementsByTagName("ipv6");
        for ( my $j = 0 ; $j < @ipv6_list ; $j++ ) {

            my $ipv6 = $ipv6_list[$j];
            my $ip   = $ipv6->getFirstChild->getData;
            my $mask = $ip;
            $mask =~ s/.*\///;
            $ip =~ s/\/.*//;

            if ($alias_num == -1) {
                print RC "ifconfig_" . $if_new_name . "=\"inet6 " . $ip . " prefixlen " . $mask . "\"\n";
            } else {
                print RC "ifconfig_" . $if_new_name . "_alias" . $alias_num . "=\"inet6 " . $ip . " prefixlen " . $mask . "\"\n";
            }
            $alias_num++;
        }
    }
        
    # Network routes configuration: <route> tags
    # Example content:
    #     static_routes="r1 r2"
    #     ipv6_static_routes="r3 r4"
    #     default_router="10.0.1.2"
    #     route_r1="-net 10.1.1.0/24 10.0.0.3"
    #     route_r2="-net 10.1.2.0/24 10.0.0.3"
    #     ipv6_default_router="2001:db8:1::1"
    #     ipv6_route_r3="2001:db8:7::/3 2001:db8::2"
    #     ipv6_route_r4="2001:db8:8::/64 2001:db8::2"
    my @route_list = $vm->getElementsByTagName("route");
    my @routeCfg;           # Stores the route_* lines 
    my $static_routes;      # Stores the names of the ipv4 routes
    my $ipv6_static_routes; # Stores the names of the ipv6 routes
    my $i = 1;
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag = $route_list[$j];
        if (defined($route_tag)){
            my $route_type = $route_tag->getAttribute("type");
            my $route_gw   = $route_tag->getAttribute("gw");
            my $route      = $route_tag->getFirstChild->getData;

            if ($route_type eq 'ipv4') {
                if ($route eq 'default'){
                    push (@routeCfg, "default_router=\"$route_gw\"\n");
                } else {
                    push (@routeCfg, "route_r$i=\"-net $route $route_gw\"\n");
                    $static_routes = ($static_routes eq '') ? "r$i" : "$static_routes r$i";
                    $i++;
                }
            } elsif ($route_type eq 'ipv6') {
                if ($route eq 'default'){
                    push (@routeCfg, "ipv6_default_router=\"$route_gw\"\n");
                } else {
                    push (@routeCfg, "ipv6_route_r$i=\"$route $route_gw\"\n");
                    $ipv6_static_routes = ($ipv6_static_routes eq '') ? "r$i" : "$ipv6_static_routes r$i";
                    $i++;                   
                }
            }
        }
    }
    unshift (@routeCfg, "ipv6_static_routes=\"$ipv6_static_routes\"\n");
    unshift (@routeCfg, "static_routes=\"$static_routes\"\n");
    print RC @routeCfg;

    # Packet forwarding: <forwarding> tag
    my $ipv4_forwarding = 0;
    my $ipv6_forwarding = 0;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    for (my $j = 0 ; $j < @forwarding_list ; $j++){
        my $forwarding   = $forwarding_list[$j];
        my $forwarding_type = $forwarding->getAttribute("type");
        if ($forwarding_type eq "ip"){
            $ipv4_forwarding = 1;
            $ipv6_forwarding = 1;
        } elsif ($forwarding_type eq "ipv4"){
            $ipv4_forwarding = 1;
        } elsif ($forwarding_type eq "ipv6"){
            $ipv6_forwarding = 1;
        }
    }
    if ($ipv4_forwarding == 1) {
        wlog (VVV, "   configuring ipv4 forwarding...");
        print RC "gateway_enable=\"YES\"\n";
    }
    if ($ipv6_forwarding == 1) {
        wlog (VVV, "   configuring ipv6 forwarding...");
        print RC "ipv6_gateway_enable=\"YES\"\n";
    }

    close RC;
       
    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file");
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '1i127.0.0.1  localhost.localdomain   localhost' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change /etc/hostname
    system "echo $vm_name > $hostname_file";

    return $error;            
}

#
# Converts a CIDR prefix length to a dot notation mask
#
sub cidr_to_mask {

  my $len=shift;
  my $dec32=2 ** 32;
  # decimal equivalent
  my $dec=$dec32 - ( 2 ** (32-$len));
  # netmask in dotted decimal
  my $mask= join '.', unpack 'C4', pack 'N', $dec;
  return $mask;
}


sub press_any_key {
    
    my $msg = shift;
    
    my $hline = "----------------------------------------------------------------------------------";
    
    print "$hline\n";
    if ($msg) { print "Execution paused ($msg)\n" } 
    print "Press any key to continue...\n";
    
    # Copy-paste from http://perlmonks.thepen.com/33566.html
    # A simpler alternative to this code is <>, but that is ugly :)

    my $key;
    ReadMode 4; # Turn off controls keys
    while (not defined ($key = ReadKey(1))) {
        # No key yet
    }
    ReadMode 0; # Reset tty mode before exiting
    print "$hline\n";

}

sub pak { 
    my $msg = shift;
    press_any_key ($msg);
}

sub wlog {
	
	my $level = shift;
	my $msg = shift;
	my $logp = shift;
	
	print $msg . "\n";
	
}