# vnx_autoconfigure.pl
#
# This file is a module part of VNX package.
#
# Author: David Fernández (david@dit.upm.es)
# Copyright (C) 2015,   DIT-UPM
#           Departamento de Ingenieria de Sistemas Telematicos
#           Universidad Politecnica de Madrid
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

# Autoconfigure contains the functions to configure network files used by vmAPI_* and vnxaced  


#
# autoconfigure for Ubuntu/Debian
#
sub autoconfigure_debian_ubuntu {
    
    my $dom         = shift; # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $os_type     = shift; # ubuntu or debian
    my $vnxaced     = shift; # defined if called from vnxaced code
    my $error;
    
    my $logp = "autoconfigure_debian_ubuntu> ";

    wlog (VVV, "rootfs_mdir=$rootfs_mdir", $logp);
    
    # Big danger if rootfs mount directory ($rootfs_mdir) is empty: 
    # host files will be modified instead of rootfs image ones
    #unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' && $rootfs_mdir ne '/' ) {
    #    die;
    #}    
    if ( !defined($rootfs_mdir) || $rootfs_mdir eq '' || (!defined($vnxaced) && $rootfs_mdir eq '/' ) ) {
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
    my $dhclient_file   = "$rootfs_mdir" . "/etc/dhcp/dhclient.conf";
    
    # Backup and delete /etc/resolv.conf file
    #if (-f $resolv_file ) {
    #    system "cp $resolv_file ${resolv_file}.bak";
    #    system "rm -f $resolv_file";
    #}
        
    # before the loop, backup /etc/udev/...70
    # and /etc/network/interfaces
    # and erase their contents
    wlog (VVV, "   configuring $rules_file and $interfaces_file...", $logp);
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

    # Network routes configuration: we read all <route> tags
    # and store the ip route configuration commands in @ip_routes
    my @ipv4_routes;       # Stores the IPv4 route configuration lines
    my @ipv4_routes_gws;   # Stores the IPv4 gateways of each route
    my @ipv6_routes;       # Stores the IPv6 route configuration lines
    my @ipv6_routes_gws;   # Stores the IPv6 gateways of each route
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ($route_type eq 'ipv4') {
            if ($route eq 'default') {
                #push (@ipv4_routes, "   up route add -net default gw " . $route_gw . "\n");
                push (@ipv4_routes, "   up ip -4 route add default via " . $route_gw . "\n");
            } else {
                #push (@ipv4_routes, "   up route add -net $route gw " . $route_gw . "\n");
                push (@ipv4_routes, "   up ip -4 route add $route via " . $route_gw . "\n");
            }
            push (@ipv4_routes_gws, $route_gw);
        } elsif ($route_type eq 'ipv6') {
            if ($route eq 'default') {
                #push (@ipv6_routes, "   up route -A inet6 add default gw " . $route_gw . "\n");
                push (@ipv6_routes, "   up ip -6 route add default via " . $route_gw . "\n");
            } else {
                #push (@ipv6_routes, "   up route -A inet6 add $route gw " . $route_gw . "\n");
                push (@ipv6_routes, "   up ip -6 route add $route via " . $route_gw . "\n");
            }
            push (@ipv6_routes_gws, $route_gw);
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

        my $if_name;
        # Special cases: loopback interface and management
        if ( !defined($net) && $id == 0 ) {
            $if_name = "eth" . $id;
        } elsif ( $net eq "lo" ) {
            $if_name = "lo:" . $id;
        } else {
            $if_name = "eth" . $id;
        }

        print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac .  "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $if_name . "\"\n\n";
        #print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";
        print INTERFACES "\nauto " . $if_name . "\n";

        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");
        my @ipv4_addr_list;
        my @ipv4_mask_list;
        my @ipv6_addr_list;
        my @ipv6_mask_list;

        if ( (@ipv4_tag_list == 0 ) && ( @ipv6_tag_list == 0 ) ) {
            # No addresses configured for the interface. We include the following commands to 
            # have the interface active on start
            if ( $net eq "lo" ) {
                print INTERFACES "iface " . $if_name . " inet static\n";
            } else {
                print INTERFACES "iface " . $if_name . " inet manual\n";
            }
            print INTERFACES "  up ifconfig " . $if_name . " 0.0.0.0 up\n";
        } else {
            # Config IPv4 addresses
            for ( my $j = 0 ; $j < @ipv4_tag_list ; $j++ ) {

                my $ipv4 = $ipv4_tag_list[$j];
                my $mask = $ipv4->getAttribute("mask");
                my $ip   = $ipv4->getFirstChild->getData;

                if ($ip =~ /^dhcp/) {
                    print INTERFACES "iface " . $if_name . " inet dhcp\n";
                    my @aux = split(',', $ip);
                    if ( defined ($aux[1]) ) {
                        system "echo 'interface \"$if_name\"' { >> $dhclient_file";
                        system "echo '  send dhcp-requested-address $aux[1];' >> $dhclient_file";
                        system "echo '}' >> $dhclient_file";     
                    }              
                } else {
                    if ($j == 0) {
                        print INTERFACES "iface " . $if_name . " inet static\n";
                        print INTERFACES "   address " . $ip . "\n";
                        print INTERFACES "   netmask " . $mask . "\n";
                    } else {
                        print INTERFACES "   up /sbin/ifconfig " . $if_name . " inet add " . $ip . " netmask " . $mask . "\n";
                    }
                    push (@ipv4_addr_list, $ip);
                    push (@ipv4_mask_list, $mask);
                }
            }
            # Config IPv6 addresses
            for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

                my $ipv6 = $ipv6_tag_list[$j];
                my $ip   = $ipv6->getFirstChild->getData;
                my $mask = $ip;
                $mask =~ s/.*\///;
                $ip =~ s/\/.*//;

                if ($ip eq 'dhcp') {
                        print INTERFACES "iface " . $if_name . " inet6 dhcp\n";                  
                } else {
                    if ($j == 0) {
                        print INTERFACES "iface " . $if_name . " inet6 static\n";
                        print INTERFACES "   address " . $ip . "\n";
                        print INTERFACES "   netmask " . $mask . "\n";
                    } else {
                        print INTERFACES "   up /sbin/ifconfig " . $if_name . " inet6 add " . $ip . "/" . $mask . "\n";
                    }
                    push (@ipv6_addr_list, $ip);
                    push (@ipv6_mask_list, $mask);
                }
            }

            #
            # Include in the interface configuration the routes that point to it
            #
            # IPv4 routes
            for (my $i = 0 ; $i < @ipv4_routes ; $i++){
                my $route = $ipv4_routes[$i];
                chomp($route); 
                for (my $j = 0 ; $j < @ipv4_addr_list ; $j++) {
                    my $ipv4_route_gw = new NetAddr::IP $ipv4_routes_gws[$i];
                    if ($ipv4_route_gw->within(new NetAddr::IP $ipv4_addr_list[$j], $ipv4_mask_list[$j])) {
                        print INTERFACES $route . "\n";
                    }
                }
            }           
            # IPv6 routes
            for (my $i = 0 ; $i < @ipv6_routes ; $i++){
                my $route = $ipv6_routes[$i];
                chomp($route); 
                for (my $j = 0 ; $j < @ipv6_addr_list ; $j++) {
                    my $ipv6_route_gw = new NetAddr::IP $ipv6_routes_gws[$i];
                    if ($ipv6_route_gw->within(new NetAddr::IP $ipv6_addr_list[$j], $ipv6_mask_list[$j])) {
                        print INTERFACES $route . "\n";
                    }
                }
            }           
        }
        
        # Process dns tags
        my $dns_addrs;
        foreach my $dns ($if->getElementsByTagName("dns")) {
            $dns_addrs .= ' ' . $dns->getFirstChild->getData;
        }      
        if (defined($dns_addrs)) {
            print INTERFACES "   dns-nameservers" . $dns_addrs . "\n";	
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
    wlog (VVV, "   configuring ipv4 ($ipv4_forwarding) and ipv6 ($ipv6_forwarding) forwarding in $sysctl_file...", $logp);
    system "echo >> $sysctl_file ";
    system "echo '# Configured by VNX' >> $sysctl_file ";
    system "echo 'net.ipv4.ip_forward=$ipv4_forwarding' >> $sysctl_file ";
    system "echo 'net.ipv6.conf.all.forwarding=$ipv6_forwarding' >> $sysctl_file ";

    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file", $logp);
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

    my $dom = shift;         # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $os_type = shift; # fedora or centos
    my $vnxaced     = shift; # defined if called from vnxaced code
    my $error;

    my $logp = "autoconfigure_redhat ($os_type)> ";

    # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
    # host files will be modified instead of rootfs image ones
    if ( !defined($rootfs_mdir) || $rootfs_mdir eq '' || (!defined($vnxaced) && $rootfs_mdir eq '/' ) ) {
        die;
    }    
        
    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # Files modified
    my $sysctl_file     = "$rootfs_mdir" . "/etc/sysctl.conf";
    my $hosts_file      = "$rootfs_mdir" . "/etc/hosts";
    my $hostname_file   = "$rootfs_mdir" . "/etc/hostname";
    my $resolv_file     = "$rootfs_mdir" . "/etc/resolv.conf";
    my $rules_file      = "$rootfs_mdir" . "/etc/udev/rules.d/70-persistent-net.rules";
    my $sysconfnet_file = "$rootfs_mdir" . "/etc/sysconfig/network";
    my $sysconfnet_dir  = "$rootfs_mdir" . "/etc/sysconfig/network-scripts";
    my $dhclient_file   = "$rootfs_mdir" . "/etc/dhcp/dhclient.conf";

    # Delete /etc/resolv.conf file
    #if (-f $resolv_file ) {
    #    system "cp $resolv_file ${resolv_file}.bak";
    #    system "rm -f $resolv_file";
    #}

    system "mv $sysconfnet_file ${sysconfnet_file}.bak";
    system "cat ${sysconfnet_file}.bak | grep -v 'NETWORKING=' | grep -v 'NETWORKING_IPv6=' > $sysconfnet_file";
    system "echo NETWORKING=yes >> $sysconfnet_file";
    system "echo NETWORKING_IPV6=yes >> $sysconfnet_file";

    if (-f $rules_file) {
        system "cp $rules_file $rules_file.backup";
    }
    system "echo \"\" > $rules_file";

    wlog (VVV, "   configuring $rules_file...", $logp);
    open RULES, ">" . $rules_file or return "error opening $rules_file";

    # Delete ifcfg and route files
    system "rm -f $sysconfnet_dir/ifcfg-Auto_eth*"; 
    system "rm -f $sysconfnet_dir/ifcfg-eth*"; 
    system "rm -f $sysconfnet_dir/route-*"; 
    system "rm -f $sysconfnet_dir/route6-*"; 

    # Network routes configuration: we read all <route> tags
    # and store the ip route configuration commands in @ip_routes
    my @ipv4_routes;       # Stores the IPv4 route configuration lines
    my @ipv4_routes_gws;   # Stores the IPv4 gateways of each route
    my @ipv6_routes;       # Stores the IPv6 route configuration lines
    my @ipv6_routes_gws;   # Stores the IPv6 gateways of each route
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ($route_type eq 'ipv4') {
            if ($route eq 'default') {
                push (@ipv4_routes, "default via " . $route_gw);
            } else {
                push (@ipv4_routes, "$route via " . $route_gw);
            }
            push (@ipv4_routes_gws, $route_gw);
        } elsif ($route_type eq 'ipv6') {
            if ($route eq 'default') {
                push (@ipv6_routes, "default via " . $route_gw);
            } else {
                push (@ipv6_routes, "$route via " . $route_gw);
            }
            push (@ipv6_routes_gws, $route_gw);
        }
    }   
        
    # Network interfaces configuration: <if> tags
    my @if_list = $vm->getElementsByTagName("if");
    my $first_ipv4_if;
    my $first_ipv6_if;
        
    for (my $i = 0 ; $i < @if_list ; $i++){
        my $if  = $if_list[$i];
        my $id  = $if->getAttribute("id");
        my $net = str($if->getAttribute("net"));
        my $mac = $if->getAttribute("mac");
        $mac =~ s/,//g;
            
        wlog (VVV, "Processing if $id, net=" . str($net) . ", mac=$mac", $logp);            

        my $if_name;
        # Special cases: loopback interface and management
        if ( !defined($net) && $id == 0 ) {
            $if_name = "eth" . $id;
        } elsif ( $net eq "lo" ) {
            $if_name = "lo:" . $id;
        } else {
            $if_name = "eth" . $id;
        }
            
        if ($os_type eq 'fedora') { 
            print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac .  "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $if_name . "\"\n\n";
            #print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";

        } elsif ($os_type eq 'centos') { 
#           print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"" . $if_name . "\"\n\n";
        }

        my $if_file;
        if ($os_type eq 'fedora') { 
            $if_file = "$sysconfnet_dir/ifcfg-Auto_$if_name";
        } elsif ($os_type eq 'centos') {  
            $if_file = "$sysconfnet_dir/ifcfg-$if_name";
        }
        system "echo \"\" > $if_file";
        open IF_FILE, ">" . $if_file or return "error opening $if_file";
    
        if ($os_type eq 'centos' || $net eq "lo") { 
            print IF_FILE "DEVICE=$if_name\n";
        }
        if ( $net ne "lo" ) {
            print IF_FILE "HWADDR=$mac\n";
        }
        print IF_FILE "TYPE=Ethernet\n";
        #print IF_FILE "BOOTPROTO=none\n";
        print IF_FILE "ONBOOT=yes\n";
        if ($os_type eq 'fedora') { 
            print IF_FILE "NAME=\"Auto $if_name\"\n";
        } elsif ($os_type eq 'centos') { 
            print IF_FILE "NAME=\"$if_name\"\n";
        }
        if ( $net eq "lo" ) {
            print IF_FILE "NM_CONTROLLED=no\n";
        }

        print IF_FILE "IPV6INIT=yes\n";
            
        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");
        my @ipv4_addr_list;
        my @ipv4_mask_list;
        my @ipv6_addr_list;
        my @ipv6_mask_list;

        my $dhcp;
        # Config IPv4 addresses
        for ( my $j = 0 ; $j < @ipv4_tag_list ; $j++ ) {
            my $ipv4 = $ipv4_tag_list[$j];
            my $mask = $ipv4->getAttribute("mask");
            my $ip   = $ipv4->getFirstChild->getData;

            $first_ipv4_if = "$if_name" unless defined($first_ipv4_if); 

            if ($ip =~ /^dhcp/) {
                $dhcp ='yes'; 
                my @aux = split(',', $ip);
                if ( defined ($aux[1]) ) {
                    system "echo 'interface \"$if_name\"' { >> $dhclient_file";
                    system "echo '  send dhcp-requested-address $aux[1];' >> $dhclient_file";
                    system "echo '}' >> $dhclient_file";     
                }              
            } else {               
                if ($j == 0) {
                    print IF_FILE "IPADDR=$ip\n";
                    print IF_FILE "NETMASK=$mask\n";
                } else {
                    my $num = $j+1;
                    print IF_FILE "IPADDR$num=$ip\n";
                    print IF_FILE "NETMASK$num=$mask\n";
                }
                push (@ipv4_addr_list, $ip);
                push (@ipv4_mask_list, $mask);
            }
        }
        # Config IPv6 addresses
        my $ipv6secs;
        for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {
            my $ipv6 = $ipv6_tag_list[$j];
            my $ip   = $ipv6->getFirstChild->getData;

            my $mask = $ip;
            $mask =~ s/.*\///;
            $ip =~ s/\/.*//;

            $first_ipv6_if = "$if_name" unless defined($first_ipv6_if); 

            if ($ip eq 'dhcp') {
                $dhcp ='yes';
            } else {
                if ($j == 0) {
                    print IF_FILE "IPV6_AUTOCONF=no\n";
                    print IF_FILE "IPV6ADDR=$ip/$mask\n";
                } else {
                    $ipv6secs .= " $ip/$mask" if $ipv6secs ne '';
                    $ipv6secs .= "$ip/$mask" if $ipv6secs eq '';
                }
                push (@ipv6_addr_list, $ip);
                push (@ipv6_mask_list, $mask);
            }
        }
        if (defined($dhcp)) {
            print IF_FILE "BOOTPROTO=dhcp\n";
        } else {
            print IF_FILE "BOOTPROTO=none\n";
        }
        if (defined($ipv6secs)) {
            print IF_FILE "IPV6ADDR_SECONDARIES=\"$ipv6secs\"\n";
        }
        close IF_FILE;
        
        #
        # Write routes associated to this interface to the /etc/sysconf/network-scripts/route-<ifname> file
        #
        my $route4_file;
        my $route6_file;
        if ($os_type eq 'fedora') { 
            $route4_file = "$sysconfnet_dir/route-Auto_$if_name";
            $route6_file = "$sysconfnet_dir/route6-Auto_$if_name";
        } elsif ($os_type eq 'centos') { 
            $route4_file = "$sysconfnet_dir/route-$if_name";
            $route6_file = "$sysconfnet_dir/route6-$if_name";
        }
        # IPv4 routes
        #system "echo \"\" > $route4_file";
        open ROUTE4_FILE, ">" . $route4_file or return "error opening $route4_file";
        wlog (VVV, "Creating $route4_file file", $logp);            
        
        for (my $i = 0 ; $i < @ipv4_routes ; $i++){
            my $route = $ipv4_routes[$i];
            chomp($route); 
            for (my $j = 0 ; $j < @ipv4_addr_list ; $j++) {
                my $ipv4_route_gw = new NetAddr::IP $ipv4_routes_gws[$i];
                if ($ipv4_route_gw->within(new NetAddr::IP $ipv4_addr_list[$j], $ipv4_mask_list[$j])) {

                    print ROUTE4_FILE "$route\n";
                    wlog (VVV, "  Writting route: $route", $logp);            
                    #if ($route =~ /default/) {
                    #if ($route eq 'default') {
                        #print ROUTE_FILE "ADDRESS$j=0.0.0.0\n";
                        #print ROUTE_FILE "NETMASK$j=0\n";
                        #print ROUTE_FILE "GATEWAY$j=$route_gw\n";
                        # Define the default route in $sysconfnet_file
                        #system "echo GATEWAY=$route_gw >> $sysconfnet_file";
                    #} else {
                        #my $mask = $route;
                        #$mask =~ s/.*\///;
                        #$mask = cidr_to_mask ($mask);
                        #$route =~ s/\/.*//;
                        #print ROUTE_FILE "ADDRESS$j=$route\n";
                        #print ROUTE_FILE "NETMASK$j=$mask\n";
                        #print ROUTE_FILE "GATEWAY$j=$route_gw\n";
                    #}
                }
            }
        }          
        close (ROUTE4_FILE);
         
        # IPv6 routes
        open ROUTE6_FILE, ">" . $route6_file or return "error opening $route6_file";
        wlog (VVV, "Creating $route6_file file", $logp);            
        for (my $i = 0 ; $i < @ipv6_routes ; $i++){
            my $route = $ipv6_routes[$i];
            chomp($route); 
            for (my $j = 0 ; $j < @ipv6_addr_list ; $j++) {
                my $ipv6_route_gw = new NetAddr::IP $ipv6_routes_gws[$i];
                if ($ipv6_route_gw->within(new NetAddr::IP $ipv6_addr_list[$j], $ipv6_mask_list[$j])) {
                    print ROUTE6_FILE "$route\n";
                    wlog (VVV, "  Writting route: $route", $logp);            
                }
            }
        }           
        close (ROUTE6_FILE);
        
        
    }
    close RULES;
        
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
    wlog (VVV, "   configuring ipv4 ($ipv4_forwarding) and ipv6 ($ipv6_forwarding) forwarding in $sysctl_file...", $logp);
    system "echo >> $sysctl_file ";
    system "echo '# Configured by VNX' >> $sysctl_file ";
    system "echo 'net.ipv4.ip_forward=$ipv4_forwarding' >> $sysctl_file ";
    system "echo 'net.ipv6.conf.all.forwarding=$ipv6_forwarding' >> $sysctl_file ";

    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file", $logp);
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

    my $dom = shift;         # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $vnxaced     = shift; # defined if called from vnxaced code
    my $error;

    my $logp = "autoconfigure_freebsd> ";

    # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
    # host files will be modified instead of rootfs image ones
    if ( !defined($rootfs_mdir) || $rootfs_mdir eq '' || (!defined($vnxaced) && $rootfs_mdir eq '/' ) ) {
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
    wlog (VVV, "   configuring /etc/rc.conf...", $logp);
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
        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        for ( my $j = 0 ; $j < @ipv4_tag_list ; $j++ ) {

            my $ipv4 = $ipv4_tag_list[$j];
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
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");
        for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

            my $ipv6 = $ipv6_tag_list[$j];
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
        wlog (VVV, "   configuring ipv4 forwarding...", $logp);
        print RC "gateway_enable=\"YES\"\n";
    }
    if ($ipv6_forwarding == 1) {
        wlog (VVV, "   configuring ipv6 forwarding...", $logp);
        print RC "ipv6_gateway_enable=\"YES\"\n";
    }

    close RC;
       
    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file", $logp);
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
# autoconfigure for Android
#
sub autoconfigure_android {
    
    my $dom         = shift; # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $vmmgmt_type = shift; # Management network type
    my $vnxaced     = shift; # defined if called from vnxaced code
    my $error;
    
    my $logp = "autoconfigure_android> ";

    wlog (VVV, "rootfs_mdir=$rootfs_mdir", $logp);
    
    # Big danger if rootfs mount directory ($rootfs_mdir) is empty: 
    # host files will be modified instead of rootfs image ones
    if ( !defined($rootfs_mdir) || $rootfs_mdir eq '' || (!defined($vnxaced) && $rootfs_mdir eq '/' ) ) {
        die;
    }    

    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # Files modified
    my $sysctl_file     = "$rootfs_mdir" . "/system/etc/sysctl.conf";
    my $build_prop_file = "$rootfs_mdir" . "/system/build.prop";
    my $init_sh         = "$rootfs_mdir" . "/system/etc/init.sh";
    my $hosts_file      = "$rootfs_mdir" . "/system/etc/hosts";
    
        
    # Network routes configuration: we read all <route> tags
    # and store the ip route configuration commands in @ip_routes
    my @ipv4_routes;       # Stores the IPv4 route configuration lines
    my @ipv4_routes_gws;   # Stores the IPv4 gateways of each route
    my @ipv6_routes;       # Stores the IPv6 route configuration lines
    my @ipv6_routes_gws;   # Stores the IPv6 gateways of each route
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ($route_type eq 'ipv4') {
            if ($route eq 'default') {
                push (@ipv4_routes, "ip route add default via " . $route_gw . "\n");
            } else {
                push (@ipv4_routes, "ip route add $route via " . $route_gw . "\n");
            }
            push (@ipv4_routes_gws, $route_gw);
        } elsif ($route_type eq 'ipv6') {
            if ($route eq 'default') {
                push (@ipv6_routes, "route -A inet6 add default gw " . $route_gw . "\n");
            } else {
                push (@ipv6_routes, "   up route -A inet6 add $route gw " . $route_gw . "\n");
            }
            push (@ipv6_routes_gws, $route_gw);
        }
    }   

    # Network interfaces configuration: <if> tags
    my @ipv4_ifs;       # Stores the IPv4 interfaces configuration lines
    my @ipv6_ifs;       # Stores the IPv6 interfaces configuration lines
    
    my @if_list = $vm->getElementsByTagName("if");
    for (my $j = 0 ; $j < @if_list; $j++){
        my $if  = $if_list[$j];
        my $id  = $if->getAttribute("id");
        my $net = $if->getAttribute("net");
        my $mac = $if->getAttribute("mac");
        $mac =~ s/,//g;

        if ($id gt 2) { next };

        my $if_name;
        # Special cases: loopback interface and management
#        if ( !defined($net) && $id == 0 ) {
#            $if_name = "eth" . $id;
#        } elsif ( $net eq "lo" ) {
#            $if_name = "lo:" . $id;
#        } else {
            #$if_name = "eth" . $id;
            
        if ($vmmgmt_type eq 'net') {
            if ($id=="0") {
                $if_name = "eth1";
            } elsif ($id=="1") {
                $if_name = "eth0";
            }
        } elsif ($vmmgmt_type eq 'private') {
            $if_name = "eth" . $id;
        } else {
            if ($id=="1") {
                $if_name = "eth1";
            } elsif ($id=="2") {
                $if_name = "eth0";
            }           
        }

        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");
        my @ipv4_addr_list;
        my @ipv4_mask_list;
        my @ipv6_addr_list;
        my @ipv6_mask_list;

        if ( (@ipv4_tag_list == 0 ) && ( @ipv6_tag_list == 0 ) ) {
            # No addresses configured for the interface. We include the following commands to 
            # have the interface active on start
            #if ( $net eq "lo" ) {
            #    push (@ipv4_ifs, "iface " . $if_name . " inet static\n");
            #} else {
            #    push (@ipv4_ifs, "iface " . $if_name . " inet manual\n");
            #}
        } else {
            # Config IPv4 addresses
            for ( my $k = 0 ; $k < @ipv4_tag_list ; $k++ ) {

                my $ipv4 = $ipv4_tag_list[$k];
                my $mask = $ipv4->getAttribute("mask");
                my $ip   = $ipv4->getFirstChild->getData;

                if ($ip eq 'dhcp') {
                    #push (@ipv4_ifs, "netcfg " . $if_name . " dhcp\n");         
                    #push (@ipv4_ifs, "start dhcpd_${if_name}:${if_name}\n"); 
                    #push (@ipv4_ifs, "dhcpcd -LK -d ${if_name}\n");       
                    #push (@ipv4_ifs, "setprop net.dns${j} \\\`getprop dhcp.eth${j}.dns1\\\`\n");
                    
                    push (@ipv4_ifs, "netcfg " . $if_name . " dhcp\n");
=BEGIN          
                    push (@ipv4_ifs, "sleep 5 \n" . 
                                     "echo \\\`getprop net.eth1.dns1\\\` > /data/local/tmp/dns \n" .
                                     "if [ \\\$DNS ]; then \n" .
                                     "    ndc resolver setifdns ${if_name} \\\$DNS 8.8.8.8 \n".
                                     "else \n" .
                                     "    ndc resolver setifdns ${if_name} 8.8.8.8 8.8.4.4 \n".
                                     "fi \n" .
                                     "ndc resolver setdefaultif ${if_name} \n");
=END
=cut                                     
                    push (@ipv4_ifs, "for i in \\\`seq 5 -1 0\\\`; do \n" .
                                     "    DNS=\\\$( getprop net.${if_name}.dns1 ) \n" .
                                     "    if [ \\\$DNS ]; then \n" .
                                     "        echo \\\$i DNS=\\\$DNS >> /data/local/tmp/init.log \n" .
                                     "        echo \\\$i ndc resolver setifdns ${if_name} \\\$DNS 8.8.8.8 >> /data/local/tmp/init.log \n" .
                                     "        echo \\\$i ndc resolver setdefaultif ${if_name} >> /data/local/tmp/init.log \n" .
                                     "        ndc resolver setifdns ${if_name} \\\$DNS 8.8.8.8 \n".
                                     "        ndc resolver setdefaultif ${if_name} \n" .                             
                                     "        break \n" .                             
                                     "    fi \n" .
                                     #"    echo \\\"\\\$i...sleeping\\\" >> /data/local/tmp/init.log \n" .
                                     "    sleep 1 \n" .
                                     "done \n");
                    #push (@ipv4_ifs, "ndc resolver setifdns ${if_name} \\\`getprop dhcp.eth${j}.dns1\\\` 8.8.8.8\n");
                    #push (@ipv4_ifs, "ndc resolver setdefaultif ${if_name}\n");                             
                } else {
                    
                    push (@ipv4_ifs, "ip link set " . $if_name . " up\n");
                    push (@ipv4_ifs, "ip addr add dev " . $if_name . " $ip/$mask\n");
                    push (@ipv4_addr_list, $ip);
                    push (@ipv4_mask_list, $mask);
                }                
                
            }
            # Config IPv6 addresses
            for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

                my $ipv6 = $ipv6_tag_list[$j];
                my $ip   = $ipv6->getFirstChild->getData;
                my $mask = $ip;
                $mask =~ s/.*\///;
                $ip =~ s/\/.*//;

                if ($ip eq 'dhcp') {
                    push (@ipv4_ifs, "netcfg " . $if_name . " dhcp\n"); # TODO: investigate command...                  
                } else {
                    push (@ipv6_ifs, "ifconfig " . $if_name . " $ip netmask $mask\n");
                    push (@ipv6_addr_list, $ip);
                    push (@ipv6_mask_list, $mask);
                }
            }

        }
    }
        
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
    wlog (VVV, "   configuring ipv4 ($ipv4_forwarding) and ipv6 ($ipv6_forwarding) forwarding in $sysctl_file...", $logp);
    system "echo >> $sysctl_file ";
    system "echo '# Configured by VNX' >> $sysctl_file ";
    system "echo 'net.ipv4.ip_forward=$ipv4_forwarding' >> $sysctl_file ";
    system "echo 'net.ipv6.conf.all.forwarding=$ipv6_forwarding' >> $sysctl_file ";
    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $build_prop_file", $logp);
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "echo \"127.0.0.1  localhost $vm_name\" >> $hosts_file";
    # Insert the new 127.0.0.1 line
    #system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change hostname in /system/build.prop
    system "echo \"net.hostname=$vm_name\" >> $build_prop_file";

    # Configuring init.sh
    foreach my $if (@ipv4_ifs) {
        print $if;
        system "echo \"$if\" >> $init_sh";
    }
    foreach my $if (@ipv6_ifs) {
        system "echo \"$if\" >> $init_sh";
    }
    foreach my $route (@ipv4_routes) {
        system "echo \"$route\" >> $init_sh";
    }
    foreach my $route (@ipv6_routes) {
        system "echo \"$route\" >> $init_sh";
    }
    system "sed -i -e 's/return 0//' $init_sh";
    system "echo \"return 0\" >> $init_sh";
    
    #my $mkshrc = "$rootfs_mdir" . "/system/etc/mkshrc";
    #print "mkshrc=$mkshrc";
    #system "sed -i -e '\$isleep 5' $mkshrc";
    #system "sed -i -e '\$iecho `getprop net.eth1.dns1` > /data/local/tmp/dns' $mkshrc";
    #system "sed -i -e '\$indc resolver setifdns eth1 8.8.8.8 8.8.4.4' $mkshrc";
    #system "sed -i -e '\$indc resolver setdefaultif eth1' $mkshrc";

    return $error;
    
}

#
# autoconfigure for Wanos
#
# Quick and dirty hack to autoconfigure wanos virtual machines
# 
#
sub autoconfigure_wanos {
    
    my $dom         = shift; # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $vmmgmt_type = shift; # Management network type
    my $vnxaced     = shift; # defined if called from vnxaced code
    my $error;
    
    my $logp = "autoconfigure_wanos> ";

    wlog (VVV, "rootfs_mdir=$rootfs_mdir", $logp);
    
    # Big danger if rootfs mount directory ($rootfs_mdir) is empty: 
    # host files will be modified instead of rootfs image ones
    if ( !defined($rootfs_mdir) || $rootfs_mdir eq '' || (!defined($vnxaced) && $rootfs_mdir eq '/' ) ) {
        die;
    }    

    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # Files modified
    my $wanos_cfg     = "$rootfs_mdir" . "/tce/etc/wanos/wanos.conf";    
    my $hosts_file    = "$rootfs_mdir" . "/tce/etc/hosts";
    my $hostname_file = "$rootfs_mdir" . "/tce/etc/hostname";
  
    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file", $logp);
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entry (127.0.0.1)
    system "sed -i -e '/127.0.0.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '1i127.0.0.1  localhost.localdomain   localhost' $hosts_file";
    # Change /etc/hostname
    system "echo $vm_name > $hostname_file";
    # Management IP address and mask is configured in interface with id=1
    my @ifs = $vm->findnodes("/create_conf/vm/if[\@id='1']");
    my @ipv4 = $ifs[0]->getElementsByTagName("ipv4");
    my $mask = $ipv4[0]->getAttribute("mask");
    my $ip   = $ipv4[0]->getFirstChild->getData;
    # Convert mask to masklen
    my $aux_ip = NetAddr::IP->new ($ip, $mask);
    $mask = $aux_ip->masklen();
    my $net = $aux_ip->network()->addr();
    
    # Gateway is configured in in a default route
    my @routes = $vm->getElementsByTagName("route");
    my $gw   = $routes[0]->getAttribute("gw");
    
    wlog (V, "wanos configuration: ip_addr=$ip/$mask, net=$net, gw=$gw", $logp);
    
    system "sed -i " . 
           "-e 's/^IP=.*/IP=$ip/' " .
           "-e 's/^MASK=.*/MASK=$mask/' " . 
           "-e 's/^NET=.*/NET=$net/' " . 
           "-e 's/^GW=.*/GW=$gw/' " . 
           "-e 's/^MODE=.*/MODE=Core/' " .
           $wanos_cfg;            
             
    return $error;
    
}

1;