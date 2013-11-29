# vmAPI_lxc.pm
#
# This file is a module part of VNX package.
#
# Authors: David Fernández
# Coordinated by: David Fernández (david@dit.upm.es)
#
# Copyright (C) 2013   DIT-UPM
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
#

package VNX::vmAPI_lxc;

use strict;
use warnings;
use Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
  init
  defineVM
  undefineVM
  destroyVM
  startVM
  shutdownVM
  saveVM
  restoreVM
  suspendVM
  resumeVM
  rebootVM
  resetVM
  executeCMD
  );


use Sys::Virt;
use Sys::Virt::Domain;
use VNX::Globals;
use VNX::DataHandler;
use VNX::Execution;
use VNX::BinariesData;
use VNX::CheckSemantics;
use VNX::TextManipulation;
use VNX::NetChecks;
use VNX::FileChecks;
use VNX::DocumentChecks;
use VNX::IPChecks;
use VNX::vmAPICommon;
use File::Basename;
use XML::LibXML;
use IO::Socket::UNIX qw( SOCK_STREAM );


use constant USE_UNIX_SOCKETS => 0;  # Use unix sockets (1) or TCP (0) to communicate with virtual machine 


# ---------------------------------------------------------------------------------------
#
# Module vmAPI_lxc initialization code 
#
# ---------------------------------------------------------------------------------------
sub init {

    my $logp = "lxc-init> ";

}

# ---------------------------------------------------------------------------------------
#
# defineVM
#
# Defined a virtual machine 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. lxc)
#   - $vm_doc: XML document describing the virtual machines
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub defineVM {

    my $self    = shift;
    my $vm_name = shift;
    my $type    = shift;
    my $vm_doc  = shift;

    my $logp = "lxc-defineVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);
#pak ("lxc-define...");   
    my $error = 0;
    my $extConfFile;
    

    my $global_doc = $dh->get_doc;
    my @vm_ordered = $dh->get_vm_ordered;

    my $filesystem;

    my $vm = $dh->get_vm_byname ($vm_name);
    wlog (VVV, "---- " . $vm->getAttribute("name"), $logp);
    wlog (VVV, "---- " . $vm->getAttribute("exec_mode"), $logp);

    my $exec_mode   = $dh->get_vm_exec_mode($vm);
    wlog (VVV, "---- vm_exec_mode = $exec_mode", $logp);

    #
    # defineVM for lxc
    #
    if  ($type eq "lxc") {
    	    	
        #
        # Read VM XML specification file
        # 
        my $parser       = XML::LibXML->new();
        my $dom          = $parser->parse_string($vm_doc);
        my $global_node   = $dom->getElementsByTagName("create_conf")->item(0);
        my $vm     = $global_node->getElementsByTagName("vm")->item(0);

        my $filesystem_type   = $vm->getElementsByTagName("filesystem")->item(0)->getAttribute("type");
        my $filesystem        = $vm->getElementsByTagName("filesystem")->item(0)->getFirstChild->getData;

        # Directory where vm files are going to be mounted
        my $vm_lxc_dir;

        if ( $filesystem_type eq "cow" ) {

            # Directory where COW files are going to be stored (upper dir in terms of overlayfs) 
            my $vm_cow_dir = $dh->get_vm_fs_dir($vm_name);

            $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";

            # Create the overlay filesystem
            # umount first, just in case it is mounted...
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $vm_lxc_dir );
            # Ex: mount -t overlayfs -o upperdir=/tmp/lxc1,lowerdir=/var/lib/lxc/vnx_rootfs_lxc_ubuntu-13.04-v025/ none /var/lib/lxc/lxc1
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -t overlayfs -o upperdir=" . $vm_cow_dir . 
                                 ",lowerdir=" . $filesystem . " none " . $vm_lxc_dir );
        } else {
        	
            #$vm_lxc_dir = $filesystem;
            $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
            $execution->execute( $logp, "rmdir $vm_lxc_dir" );
            $execution->execute( $logp, "ln -s $filesystem $vm_lxc_dir" );
            
        }
        
        die "ERROR: variable vm_lxc_dir is empty" unless ($vm_lxc_dir ne '');
        my $vm_lxc_rootfs="${vm_lxc_dir}/rootfs";
        my $vm_lxc_config="${vm_lxc_dir}/config";
        my $vm_lxc_fstab="${vm_lxc_dir}/fstab";


        # Configure /etc/hostname and /etc/hosts files in VM
        # echo lxc1 > /var/lib/lxc/lxc1/rootfs/etc/hostname
        $execution->execute( $logp, "echo $vm_name > ${vm_lxc_rootfs}/etc/hostname" ); 
        # Ex: sed -i -e "s/127.0.1.1.*/127.0.1.1   lxc1/" /var/lib/lxc/lxc1/rootfs/etc/host
        $execution->execute( $logp, "sed -i -e 's/127.0.1.1.*/127.0.1.1   $vm_name/' ${vm_lxc_rootfs}/etc/hosts" ); 

        # Modify LXC VM config file
        # Backup config file just in case...
        $execution->execute( $logp, "cp $vm_lxc_config $vm_lxc_config" . ".bak" ); 

        # vm name
        # Set lxc.utsname = $vm_name
        # Delete lines with "lxc.utsname" 
        $execution->execute( $logp, "sed -i -e '/lxc.utsname/d' $vm_lxc_config" ); 
        # Add new line: lxc.utsname = $vm_name
        $execution->execute( $logp, "echo '' >> $vm_lxc_config" );
        $execution->execute( $logp, "echo 'lxc.utsname = $vm_name' >> $vm_lxc_config" );
        
        # Set lxc.rootfs
        # Delete lines with "lxc.rootfs" 
        $execution->execute( $logp, "sed -i -e '/lxc.rootfs/d' $vm_lxc_config" ); 
        # Add new line: lxc.rootfs = $vm_lxc_dir/rootfs
        $execution->execute( $logp, "echo 'lxc.rootfs = $vm_lxc_dir/rootfs' >> $vm_lxc_config" );
        
        # Set lxc.mount  = /var/lib/lxc/lxc1/fstab
        # Delete lines with "lxc.fstab" 
        $execution->execute( $logp, "sed -i -e '/lxc.mount/d' $vm_lxc_config" ); 
        # Add new line: lxc.mount = $vm_lxc_dir/fstab
        $execution->execute( $logp, "echo 'lxc.mount = $vm_lxc_dir/fstab' >> $vm_lxc_config" );
        
        #
        # Configure network interfaces
        #   
        # Example:
		#    # interface eth0
		#    lxc.network.type=veth
		#    # ifname inside VM
		#    lxc.network.name = eth0
		#    # ifname on the host
		#    lxc.network.veth.pair = lxc1e0
		#    lxc.network.hwaddr = 02:fd:00:04:01:00
		#    # bridge if connects to
		#    lxc.network.link=lxcbr0
		#    lxc.network.flags=up        

        # Delete lines with "lxc.network" 
        $execution->execute( $logp, "sed -i -e '/lxc.network/d' $vm_lxc_config" ); 
        
        my $mng_if_exists = 0;
        my $mng_if_mac;

        # Create vm /etc/network/interfaces file
        #my $vm_etc_net_ifs = $vm_lxc_rootfs . "/etc/network/interfaces";
        # Backup file, just in case.... 
        #$execution->execute( $logp, "cp $vm_etc_net_ifs ${vm_etc_net_ifs}.bak" );
        # Add loopback interface        
        #$execution->execute( $logp, "echo 'auto lo' > $vm_etc_net_ifs" );
        #$execution->execute( $logp, "echo 'iface lo inet loopback' >> $vm_etc_net_ifs" );

        foreach my $if ($vm->getElementsByTagName("if")) {
            my $id    = $if->getAttribute("id");
            my $net   = $if->getAttribute("net");
            my $mac   = $if->getAttribute("mac");
            $mac =~ s/,//; # TODO: why is there a comma before mac addresses?

            $execution->execute( $logp, "echo '' >> $vm_lxc_config" );
            $execution->execute( $logp, "echo '# interface eth$id' >> $vm_lxc_config" );
            $execution->execute( $logp, "echo 'lxc.network.type=veth' >> $vm_lxc_config" );
            $execution->execute( $logp, "echo '# ifname inside VM' >> $vm_lxc_config" );
            $execution->execute( $logp, "echo 'lxc.network.name=eth$id' >> $vm_lxc_config" );
            $execution->execute( $logp, "echo '# ifname on the host' >> $vm_lxc_config" );
            $execution->execute( $logp, "echo 'lxc.network.veth.pair=$vm_name-e$id' >> $vm_lxc_config" );
            $execution->execute( $logp, "echo 'lxc.network.hwaddr=$mac' >> $vm_lxc_config" );
            if ($id != 0) {
	            $execution->execute( $logp, "echo '# bridge if connects to' >> $vm_lxc_config" );
	            $execution->execute( $logp, "echo 'lxc.network.link=$net' >> $vm_lxc_config" );
            }
            $execution->execute( $logp, "echo 'lxc.network.flags=up' >> $vm_lxc_config" );

            #
            # Add interface to /etc/network/interfaces
            #
            #$execution->execute( $logp, "echo 'iface lo inet loopback' >> $vm_etc_net_ifs" );
              

        }                       

        #
        # VM autoconfiguration 
        #
        # Adapted from 'autoconfigure_ubuntu' fuction in vnxaced.pl             
        #
    	# TODO: generalize to other Linux distributions
    	
	    # Files modified
	    my $interfaces_file = ${vm_lxc_rootfs} . "/etc/network/interfaces";
	    my $sysctl_file     = ${vm_lxc_rootfs} . "/etc/sysctl.conf";
	    my $hosts_file      = ${vm_lxc_rootfs} . "/etc/hosts";
	    my $hostname_file   = ${vm_lxc_rootfs} . "/etc/hostname";
	    my $resolv_file     = ${vm_lxc_rootfs} . "/etc/resolv.conf";
	    my $rules_file      = ${vm_lxc_rootfs} . "/etc/udev/rules.d/70-persistent-net.rules";
	    
	    # Backup and delete /etc/resolv.conf file
	    system "cp $resolv_file ${resolv_file}.bak";
	    system "rm -f $resolv_file";
	        
	    # before the loop, backup /etc/udev/...70 and /etc/network/interfaces
	    # and erase their contents
	    wlog (VVV, "configuring $rules_file and $interfaces_file...", $logp);
	    #system "cp $rules_file $rules_file.backup";
	    system "echo \"\" > $rules_file";
	    open RULES, ">" . $rules_file or print "error opening $rules_file";
	    system "cp $interfaces_file $interfaces_file.backup";
	    system "echo \"\" > $interfaces_file";
	    open INTERFACES, ">" . $interfaces_file or print "error opening $interfaces_file";
	
	    print INTERFACES "\n";
	    print INTERFACES "auto lo\n";
	    print INTERFACES "iface lo inet loopback\n";
	
	    # Network routes configuration: <route> tags
	    my @ip_routes;   # Stores the route configuration lines
        foreach my $route ($vm->getElementsByTagName("route")) {
	    	
	        my $route_type = $route->getAttribute("type");
	        my $route_gw   = $route->getAttribute("gw");
	        my $route_data = $route->getFirstChild->getData;
	        if ($route_type eq 'ipv4') {
	            if ($route_data eq 'default') {
	                push (@ip_routes, "   up route add -net default gw " . $route_gw . "\n");
	            } else {
	                push (@ip_routes, "   up route add -net $route_data gw " . $route_gw . "\n");
	            }
	        } elsif ($route_type eq 'ipv6') {
	            if ($route_data eq 'default') {
	                push (@ip_routes, "   up route -A inet6 add default gw " . $route_gw . "\n");
	            } else {
	                push (@ip_routes, "   up route -A inet6 add $route_data gw " . $route_gw . "\n");
	            }
	        }
	    }   
	
	    # Network interfaces configuration: <if> tags
        foreach my $if ($vm->getElementsByTagName("if")) {
	        my $id    = $if->getAttribute("id");
	        my $net   = $if->getAttribute("net");
	        my $mac   = $if->getAttribute("mac");
	        $mac =~ s/,//g;
	
	        my $ifName;
	        # Special case: loopback interface
	        if ( $net eq "lo" ) {
	            $ifName = "lo:" . $id;
	        } else {
	            $ifName = "eth" . $id;
	        }
	
	        print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac .  "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $ifName . "\"\n\n";
	        print INTERFACES "auto " . $ifName . "\n";
	
	        my $ipv4_tag_list = $if->getElementsByTagName("ipv4");
	        my $ipv6_tag_list = $if->getElementsByTagName("ipv6");
	
	        if ( ($ipv4_tag_list->size == 0 ) && ( $ipv6_tag_list->size == 0 ) ) {
	            # No addresses configured for the interface. We include the following commands to 
	            # have the interface active on start
	            print INTERFACES "iface " . $ifName . " inet manual\n";
	            print INTERFACES "  up ifconfig " . $ifName . " 0.0.0.0 up\n";
	        } else {
	            # Config IPv4 addresses
	            for ( my $j = 0 ; $j < $ipv4_tag_list->size ; $j++ ) {
	
	                my $ipv4_tag = $ipv4_tag_list->item($j);
	                my $mask    = $ipv4_tag->getAttribute("mask");
	                my $ip      = $ipv4_tag->getFirstChild->getData;
	
	                if ($j == 0) {
	                    print INTERFACES "iface " . $ifName . " inet static\n";
	                    print INTERFACES "   address " . $ip . "\n";
	                    print INTERFACES "   netmask " . $mask . "\n";
	                } else {
	                    print INTERFACES "   up /sbin/ifconfig " . $ifName . " inet add " . $ip . " netmask " . $mask . "\n";
	                }
	            }
	            # Config IPv6 addresses
	            for ( my $j = 0 ; $j < $ipv6_tag_list->size ; $j++ ) {
	
	                my $ipv6_tag = $ipv6_tag_list->item($j);
	                my $ip    = $ipv6_tag->getFirstChild->getData;
	                my $mask = $ip;
	                $mask =~ s/.*\///;
	                $ip =~ s/\/.*//;
	
	                if ($j == 0) {
	                    print INTERFACES "iface " . $ifName . " inet6 static\n";
	                    print INTERFACES "   address " . $ip . "\n";
	                    print INTERFACES "   netmask " . $mask . "\n\n";
	                } else {
	                    print INTERFACES "   up /sbin/ifconfig " . $ifName . " inet6 add " . $ip . "/" . $mask . "\n";
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
	    my $ipv4Forwarding = 0;
	    my $ipv6Forwarding = 0;
	    my $forwardingTaglist = $vm->getElementsByTagName("forwarding");
	    my $numforwarding = $forwardingTaglist->size;
	    for (my $j = 0 ; $j < $numforwarding ; $j++){
	        my $forwardingTag   = $forwardingTaglist->item($j);
	        my $forwarding_type = $forwardingTag->getAttribute("type");
	        if ($forwarding_type eq "ip"){
	            $ipv4Forwarding = 1;
	            $ipv6Forwarding = 1;
	        } elsif ($forwarding_type eq "ipv4"){
	            $ipv4Forwarding = 1;
	        } elsif ($forwarding_type eq "ipv6"){
	            $ipv6Forwarding = 1;
	        }
	    }
	    wlog (VVV, "configuring ipv4 ($ipv4Forwarding) and ipv6 ($ipv6Forwarding) forwarding in $sysctl_file...", $logp);
	    system "echo >> $sysctl_file ";
	    system "echo '# Configured by VNXACED' >> $sysctl_file ";
	    system "echo 'net.ipv4.ip_forward=$ipv4Forwarding' >> $sysctl_file ";
	    system "echo 'net.ipv6.conf.all.forwarding=$ipv6Forwarding' >> $sysctl_file ";
	
	    # Configuring /etc/hosts and /etc/hostname
	    #write_log ("   configuring $hosts_file and /etc/hostname...");
	    #system "cp $hosts_file $hosts_file.backup";
	
	    #/etc/hosts: insert the new first line
	    #system "sed '1i\ 127.0.0.1  $vm_name    localhost.localdomain   localhost' $hosts_file > /tmp/hosts.tmp";
	    #system "mv /tmp/hosts.tmp $hosts_file";
	
	    #/etc/hosts: and delete the second line (former first line)
	    #system "sed '2 d' $hosts_file > /tmp/hosts.tmp";
	    #system "mv /tmp/hosts.tmp $hosts_file";
	
	    #/etc/hosts: insert the new second line
	    #system "sed '2i\ 127.0.1.1  $vm_name' $hosts_file > /tmp/hosts.tmp";
	    #system "mv /tmp/hosts.tmp $hosts_file";
	
	    #/etc/hosts: and delete the third line (former second line)
	    #system "sed '3 d' $hosts_file > /tmp/hosts.tmp";
	    #system "mv /tmp/hosts.tmp $hosts_file";
	
	    #/etc/hostname: insert the new first line
	    #system "sed '1i\ $vm_name' $hostname_file > /tmp/hostname.tpm";
	    #system "mv /tmp/hostname.tpm $hostname_file";
	
	    #/etc/hostname: and delete the second line (former first line)
	    #system "sed '2 d' $hostname_file > /tmp/hostname.tpm";
	    #system "mv /tmp/hostname.tpm $hostname_file";
	
	    #system "hostname $vm_name";
	    
	    # end of vm autoconfiguration

        #
        # VM CONSOLES
        # 
        my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
        open (CONS_FILE, "> $consFile") || $execution->smartdie ("ERROR: Cannot open file $consFile");

        my @cons_list = $dh->merge_console($vm);
    
        if (scalar(@cons_list) == 0) {
            # No consoles defined; use default configuration 
            print CONS_FILE "con1=yes,lxc,$vm_name\n";
            wlog (VVV, "con1=yes,lxc,$vm_name", $logp);

        } else{
            foreach my $cons (@cons_list) {
                my $cons_id      = $cons->getAttribute("id");
                my $cons_display = $cons->getAttribute("display");
                if (empty($cons_display)) { $cons_display = 'yes'};
                my $cons_value = &text_tag($cons);

                print CONS_FILE "con${cons_id}=$cons_display,lxc,$vm_name\n";
                wlog (VVV, "con${cons_id}=$cons_display,lxc,$vm_name", $logp);

            }
        }
        close (CONS_FILE); 

        return $error;

    } else {
        $error = "defineVM for type $type not implemented yet.\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# undefineVM
#
# Undefines a virtual machine 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. lxc)
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub undefineVM {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "lxc-undefineVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error = 0;
    my $con;

    #
    # undefineVM for lxc
    #
    if ($type eq "lxc") {

        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";

        # Umount the overlay filesystem
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $vm_lxc_dir );
        
        return $error;
    }

    else {
        $error = "undefineVM for type $type not implemented yet.\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# destroyVM
#
# Destroys a virtual machine 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine 
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub destroyVM {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "lxc-destroyVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error = 0;
    my $con;
    
    
    #
    # destroyVM for lxc
    #
    if ($type eq "lxc") {

        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
        $execution->execute( $logp, "lxc-kill -n $vm_name");

        # Umount the overlay filesystem
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $vm_lxc_dir );

        # Delete COW files directory
        my $vm_cow_dir = $dh->get_vm_dir($vm_name);
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $vm_cow_dir . "/fs/*" );

        return $error;

    }
    else {
        $error = "destroyVM for type $type not implemented yet.\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# startVM
#
# Starts a virtual machine already defined with defineVM
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
#   - $no_consoles: if true, virtual machine consoles are not opened
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub startVM {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;
    my $no_consoles = shift;

    my $logp = "lxc-startVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error = 0;
    my $con;
    
    #
    # startVM for lxc
    #
    if ($type eq "lxc") {

        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
#pak ("before: lxc-start -n $vm_name -f $vm_lxc_dir/config");        
        $execution->execute( $logp, "lxc-start -d -n $vm_name -f $vm_lxc_dir/config");

        # Start the active consoles, unless options -n|--no_console were specified by the user
        unless ($no_consoles eq 1){
            Time::HiRes::sleep(0.5);
            VNX::vmAPICommon->start_consoles_from_console_file ($vm_name);
        }

		# 
        # Check if there is any <filetree> tag with seq='on_boot' in $vm_doc
        # and execute the command if they exists
        #
        
		# Get VM XML definition from .vnx/scenarios/<scenario_name>/vms/$vm_name_cconf.xml file
		my $parser = XML::LibXML->new();
    	my $doc = $parser->parse_file($dh->get_vm_dir($vm_name) . '/' . $vm_name . '_cconf.xml');

        my @filetree_tag_list = $doc->getElementsByTagName("filetree");
        my @exec_tag_list = $doc->getElementsByTagName("fexec");
        if ( (@filetree_tag_list > 0) || (@exec_tag_list > 0) )  { 
        	
        	# At least one on_boot filetree or exec defined
			#
			# Wait for VM to start
			#
			my $tout = 10;
			while ( system("lxc-info -s -n $vm_name | grep RUNNING > /dev/null") ) {
			    wlog (VVV, "waiting for VM $vm_name to start....", $logp);
			    sleep 1;
			    if ( !$tout-- ) {
			    	wlog (N, "time out waiting for VM $vm_name to start...on_boot commands not executed", $logp);
			        return 1;
			    }
			}
			
			my $dst_num = 1;
			foreach my $filetree ($doc->getElementsByTagName("filetree")) {
				
				my $seq    = $filetree->getAttribute("seq");
				wlog (VVV, "$seq filetree: " . $filetree->toString(1), $logp );

   				my $files_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq/filetree/$dst_num/"; 
				execute_filetree ($vm_name, $filetree, "$files_dir");
            	$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $files_dir" );
            	$dst_num++;            
			}

			foreach my $exec ($doc->getElementsByTagName("exec")) {
				
				my $seq    = $exec->getAttribute("seq");
				wlog (VVV, "$seq exec: " . $exec->toString(1), $logp );

            	my $command = $exec->getFirstChild->getData;
        		my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
            	wlog (V, "executing '$seq' user defined exec command '$command'", $logp);
        		$execution->execute( $logp, "lxc-attach -n $vm_name -- $command");
			}

        }
		
        # If host_mapping is in use and the vm has a management interface, 
        # then we have to add an entry for this vm in $dh->get_sim_dir/hostlines file
        if ( $dh->get_host_mapping ) {
        	my @vm_ordered = $dh->get_vm_ordered;
	        for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
	        	my $vm = $vm_ordered[$i];
	            my $name = $vm->getAttribute("name");
	            unless ( $name eq $vm_name ) { next; }
						    		
				# Check whether the vm has a management interface enabled
				my $mng_if_value = &mng_if_value($vm);
				unless ( ($dh->get_vmmgmt_type eq 'none' ) || ($mng_if_value eq "no") ) {
                            
                 	# Get the vm management ip address 
                    my %net = &get_admin_address( 'file', $vm_name );
                    # Add it to hostlines file
                    open HOSTLINES, ">>" . $dh->get_sim_dir . "/hostlines"
                        or $execution->smartdie("can not open $dh->get_sim_dir/hostlines\n")
                        unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
                    print HOSTLINES $net{'vm'}->addr() . " $vm_name\n";
                    close HOSTLINES;
                }	    		
            }
        }
        
        return $error;

    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}



# ---------------------------------------------------------------------------------------
#
# shutdownVM
#
# Shutdowns a virtual machine
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub shutdownVM {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "lxc-shutdownVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error = 0;

    # Sample code
    print "Shutting down vm $vm_name of type $type\n" if ($exemode == $EXE_VERBOSE);

    #
    # shutdownVM for lxc
    #
    if ($type eq "lxc") {
    	
        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
        $execution->execute( $logp, "lxc-shutdown -n $vm_name");
    	
        return $error;
    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}


# ---------------------------------------------------------------------------------------
#
# saveVM
#
# Stops a virtual machine and saves its status to disk
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
#   - $filename: the name of the file to save the VM state to
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub saveVM {

    my $self     = shift;
    my $vm_name  = shift;
    my $type     = shift;
    my $filename = shift;

    my $logp = "lxc-saveVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error = 0;

    # Sample code
    print "saveVM: saving vm $vm_name of type $type\n" if ($exemode == $EXE_VERBOSE);

    if ( $type eq "lxc" ) {
        return $error;

    }
}

# ---------------------------------------------------------------------------------------
#
# restoreVM
#
# Restores the status of a virtual machine from a file previously saved with saveVM
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
#   - $filename: the name of the file with the VM state
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub restoreVM {

    my $self     = shift;
    my $vm_name   = shift;
    my $type     = shift;
    my $filename = shift;

    my $logp = "lxc-restoreVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error = 0;

    print
      "restoreVM: restoring vm $vm_name of type $type from file $filename\n";

    #
    # restoreVM for lxc
    #
    if ($type eq "lxc") {

        return $error;

    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# suspendVM
#
# Stops a virtual machine and saves its status to memory
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub suspendVM {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "lxc-suspendVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error = 0;

    #
    # suspendVM for lxc
    #
    if ($type eq "lxc") {

        return $error;

    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# resumeVM
#
# Restores the status of a virtual machine from memory (previously saved with suspendVM)
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub resumeVM {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "lxc-resumeVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error = 0;

    # Sample code
    print "resumeVM: resuming vm $vm_name\n" if ($exemode == $EXE_VERBOSE);

    #
    # resumeVM for lxc
    #
    if ($type eq "lxc") {

        return $error;

    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# rebootVM
#
# Reboots a virtual machine
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub rebootVM {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "lxc-rebootVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error = 0;

    #
    # rebootVM for lxc
    #
    if ($type eq "lxc") {

        return $error;

    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }

}

# ---------------------------------------------------------------------------------------
#
# resetVM
#
# Restores the status of a virtual machine form a file previously saved with saveVM
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub resetVM {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "lxc-resetVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    # Sample code
    print "resetVM: reseting vm $vm_name\n" if ($exemode == $EXE_VERBOSE);

    #
    # resetVM for lxc
    #
    if ($type eq "lxc") {

        return $error;

    }else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# executeCMD
#
# Executes a set of <filetree> and <exec> commands in a virtual mchine
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
#   - $seq: the sequence tag of commands to execute
#   - $vm: the virtual machine XML definition node
#   - $seq: the sequence tag of commands to execute
#   - $plugin_ftree_list_ref: a reference to an array with the plugin <filetree> commands
#   - $plugin_exec_list_ref: a reference to an array with the plugin <exec> commands
#   - $ftree_list_ref: a reference to an array with the user-defined <filetree> commands
#   - $exec_list_ref: a reference to an array with the user-defined <exec> commands
# 
# Returns:
#   - 0 if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub executeCMD {

    my $self    = shift;
    my $vm_name = shift;
    my $merged_type = shift;
    my $seq     = shift;
    my $vm      = shift;
    my $plugin_ftree_list_ref = shift;
    my $plugin_exec_list_ref  = shift;
    my $ftree_list_ref        = shift;
    my $exec_list_ref         = shift;

    my $error = 0;

    my $logp = "lxc-executeCMD-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$merged_type, seq=$seq ...)", $logp);


    my $random_id  = &generate_random_string(6);


    if ($merged_type eq "lxc")    {
        
        my $user   = get_user_in_seq( $vm, $seq );
        # exec_mode should always be 'lxc-attach' ...TODO: check on CheckSemantics
        my $exec_mode   = $dh->get_vm_exec_mode($vm);
        wlog (VVV, "---- vm_exec_mode = $exec_mode", $logp);

        if ($exec_mode ne "lxc-attach") {
            return "execution mode $exec_mode not supported for VM of type $merged_type";
        }       
       
        # We create the command.xml file. It is not needed for LXC, as the commands are 
        # directly executed o the VM using lxc-attach. But we create it anyway for 
        # compatibility with other virtualization modules
		my $command_file = $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml";
        wlog (VVV, "opening file $command_file...", $logp);
        my $retry = 3;
        open COMMAND_FILE, "> $command_file" 
            or  $execution->smartdie("cannot open /command_file $!" ) 
            unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
                          
        $execution->execute( $logp, "<command>", *COMMAND_FILE );
        # Insert random id number for the command file
        my $fileid = $vm_name . "-" . &generate_random_string(6);
        $execution->execute( $logp, "<id>" . $fileid ."</id>", *COMMAND_FILE );
        my $dst_num = 1;
            
        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
        my $vm_lxc_rootfs="${vm_lxc_dir}/rootfs";
        
        #       
        # Process of <filetree> tags
        #

        # 1 - Plugins <filetree> tags
        wlog (VVV, "executeCMD: number of plugin ftrees " . scalar(@{$plugin_ftree_list_ref}), $logp);
        
        foreach my $filetree (@{$plugin_ftree_list_ref}) {
            # Add the <filetree> tag to the command.xml file
            my $filetree_txt = $filetree->toString(1);
            $execution->execute( $logp, "$filetree_txt", *COMMAND_FILE );
            wlog (VVV, "executeCMD: adding plugin filetree \"$filetree_txt\" to command.xml", $logp);

   			my $files_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq"; 
			execute_filetree ($vm_name, $filetree, "$files_dir/filetree/$dst_num/");
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $files_dir/filetree/$dst_num" );
			
            $dst_num++;          
        }
        
        # 2 - User defined <filetree> tags
        wlog (VVV, "executeCMD: number of user defined ftrees " . scalar(@{$ftree_list_ref}), $logp);
        
        foreach my $filetree (@{$ftree_list_ref}) {
            # Add the <filetree> tag to the command.xml file
            my $filetree_txt = $filetree->toString(1);
            $execution->execute( $logp, "$filetree_txt", *COMMAND_FILE );
            wlog (VVV, "executeCMD: adding user defined filetree \"$filetree_txt\" to command.xml", $logp);
   
   			my $files_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq"; 
			execute_filetree ($vm_name, $filetree, "$files_dir/filetree/$dst_num/");
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $files_dir/filetree/$dst_num" );
			
            $dst_num++;            
        }
        
        my $res=`tree $vm_lxc_rootfs/tmp`; 
        wlog (VVV, "executeCMD: shared disk content:\n $res", $logp);

        my $command = $bd->get_binaries_path_ref->{"date"};
        chomp( my $now = `$command` );

        #       
        # Process of <exec> tags
        #
        
        # 1 - Plugins <exec> tags
        wlog (VVV, "executeCMD: number of plugin <exec> = " . scalar(@{$plugin_ftree_list_ref}), $logp);
        
        foreach my $cmd (@{$plugin_exec_list_ref}) {
            # Add the <exec> tag to the command.xml file
            my $cmd_txt = $cmd->toString(1);
            $execution->execute( $logp, "$cmd_txt", *COMMAND_FILE );
            wlog (VVV, "executeCMD: adding plugin exec \"$cmd_txt\" to command.xml", $logp);

            my $command = $cmd->getFirstChild->getData;
        	my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
            wlog (V, "executeCMD: executing user defined exec command '$command'", $logp);
        	$execution->execute( $logp, "lxc-attach -n $vm_name -- $command");
        }

        # 2 - User defined <exec> tags
        wlog (VVV, "executeCMD: number of user-defined <exec> = " . scalar(@{$ftree_list_ref}), $logp);
        
        foreach my $cmd (@{$exec_list_ref}) {
            # Add the <exec> tag to the command.xml file
            my $cmd_txt = $cmd->toString(1);
            $execution->execute( $logp, "$cmd_txt", *COMMAND_FILE );
            wlog (VVV, "executeCMD: adding user defined exec \"$cmd_txt\" to command.xml", $logp);
            
            my $command = $cmd->getFirstChild->getData;
        	my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
            wlog (V, "executeCMD: executing user defined exec command '$command'", $logp);
        	$execution->execute( $logp, "lxc-attach -n $vm_name -- $command");
        }

        # We close file and mark it executable
        $execution->execute( $logp, "</command>", *COMMAND_FILE );
        close COMMAND_FILE
          unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

        # Print command.xml file content to log if VVV
        open FILE, "< " . $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml";
        my $cmd_file = do { local $/; <FILE> };
        close FILE;
        wlog (VVV, "command.xml file passed to vm $vm_name: \n$cmd_file", $logp);


    } 

    return $error;
}

#
# execute_filetree: adapted from the same function in vnxaced.pl
#
# Copies the files specified in a filetree tag to the virtual machine rootfs
# 
sub execute_filetree {

    my $vm_name = shift;
    my $filetree_tag = shift;
    my $source_path = shift;

    my $logp = "lxc-execute_filetree-$vm_name> ";

    my $seq          = str($filetree_tag->getAttribute("seq"));
    my $root         = str($filetree_tag->getAttribute("root"));
    my $user         = str($filetree_tag->getAttribute("user"));
    my $group        = str($filetree_tag->getAttribute("group"));
    my $perms        = str($filetree_tag->getAttribute("perms"));
    my $source       = str($filetree_tag->getFirstChild->getData);
    
    # Store directory where the vm rootfs is mounted
    my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
    my $vm_lxc_rootfs="${vm_lxc_dir}/rootfs/";
    
    # Add vm rootfs location to filtree files destination ($root) 
    $root = $vm_lxc_rootfs . $root;
    
    #my $folder = $j + 1;
    #$j++;
    #my $source_path = $cmd_path . "/filetree/" . $folder . "/";
    wlog (VVV, "   processing " . $filetree_tag->toString(1), $logp ) ;
    wlog (VVV, "      seq=$seq, root=$root, user=$user, group=$group, perms=$perms, source_path=$source_path", $logp);

    my $res=`ls -R $source_path`; wlog (VVV, "filetree source files: $res", $logp);
    # Get the number of files in source dir
    my $num_files=`ls -a1 $source_path | wc -l`;
    if ($num_files < 3) { # count "." and ".."
        wlog (VVV, "   ERROR in filetree: no files to copy in $source_path (seq=$seq)\n", $logp);
        return;
    }
    # Check if files destination (root attribute) is a directory or a file
    my $cmd;
    if ( $root =~ /\/$/ ) {
        # Destination is a directory
        wlog (VVV, "   Destination is a directory", $logp);
        unless (-d $root){
            wlog (VVV, "   creating unexisting dir '$root'...", $logp);
            system "mkdir -p $root";
        }

        $cmd="cp -vR ${source_path}* $root";
        wlog (VVV, "   Executing '$cmd' ...", $logp);
        $res=`$cmd`;
        wlog (VVV, "Copying filetree files ($root):", $logp);
        wlog (VVV, "$res", $logp);

        # Change owner and permissions if specified in <filetree>
        my @files= <${source_path}*>;
        foreach my $file (@files) {
            my $fname = basename ($file);
            wlog (VVV, $file . "," . $fname, $logp);
            if ( $user ne ''  ) {
                $res=`chown -R $user $root/$fname`; wlog(VVV, $res, $logp); }
            if ( $group ne '' ) {
                $res=`chown -R .$group $root/$fname`; wlog(VVV, $res, $logp); }
            if ( $perms ne '' ) {
                $res=`chmod -R $perms $root/$fname`; wlog(VVV, $res, $logp); }
        }
            
    } else {
        # Destination is a file
        # Check that $source_path contains only one file
        wlog (VVV, "   Destination is a file", $logp);
        wlog (VVV, "       source_path=${source_path}", $logp);
        wlog (VVV, "       root=${root}", $logp);
        if ($num_files > 3) { # count "." and ".."
            wlog ("   ERROR in filetree: destination ($root) is a file and there is more than one file in $source_path (seq=$seq)\n", $logp);
            next;
        }
        my $file_dir = dirname($root);
        unless (-d $file_dir){
            wlog ("   creating unexisting dir '$file_dir'...", $logp);
            system "mkdir -p $file_dir";
        }
        $cmd="cp -v ${source_path}* $root";
        wlog (VVV, "   Executing '$cmd' ...", $logp);
        $res=`$cmd`;
        wlog (VVV, "Copying filetree file ($root):", $logp);
        wlog (VVV, "$res", $logp);
        # Change owner and permissions of file $root if specified in <filetree>
        if ( $user ne ''  ) {
            $cmd="chown -R $user $root";
            $res=`$cmd`; wlog(VVV, $cmd . "/n" . $res, $logp); }
        if ( $group ne '' ) {
            $cmd="chown -R .$group $root";
            $res=`$cmd`; wlog(VVV, $cmd . "/n" . $res, $logp); }
        if ( $perms ne '' ) {
            $cmd="chmod -R $perms $root";
            $res=`$cmd`; wlog(VVV, $cmd . "/n" . $res, $logp); }
    }
}


###################################################################
#                                                                 
sub change_vm_status {

    my $vm     = shift;
    my $status = shift;

    my $status_file = $dh->get_vm_dir($vm) . "/status";
    my $logp = "change_vm_status> ";

    if ( $status eq "REMOVE" ) {
        $execution->execute( $logp, 
            $bd->get_binaries_path_ref->{"rm"} . " -f $status_file" );
    }
    else {
        $execution->execute( $logp, 
            $bd->get_binaries_path_ref->{"echo"} . " $status > $status_file" );
    }
}


###################################################################
# get_net_by_type
#
# Returns a network whose name is the first argument and whose type is second
# argument (may be "*" if the type doesn't matter). If there is no net with
# the given constrictions, 0 value is returned
#
# Note the default type is "lan"
#
sub get_net_by_type {

    my $name_target = shift;
    my $type_target = shift;

    my $doc = $dh->get_doc;

    # To get list of defined <net>
    #my $net_list = $doc->getElementsByTagName("net");

    # To process list
    #for ( my $i = 0 ; $i < $net_list->getLength ; $i++ ) {
    foreach my $net ($doc->getElementsByTagName("net")) {
        #my $net  = $net_list->item($i);
        my $name = $net->getAttribute("name");
        my $type = $net->getAttribute("type");

        if (   ( $name_target eq $name )
            && ( ( $type_target eq "*" ) || ( $type_target eq $type ) ) )
        {
            return $net;
        }

        # Special case (implicit lan)
        if (   ( $name_target eq $name )
            && ( $type_target eq "lan" )
            && ( $type eq "" ) )
        {
            return $net;
        }
    }

    return 0;
}



###################################################################
# get_ip_hostname
#
# Return a suitable IP address to being added to the /etc/hosts file of the
# virtual machine passed as first argument (as node)
#
# In the current implementation, the first IP address for no management if is used.
# Only works for IPv4 addresses
#
# If no valid IP address if found or IPv4 has been disabled (with -6), returns 0.
#
sub get_ip_hostname {

    return 0 unless ( $dh->is_ipv4_enabled );

    my $vm = shift;

    # To check <mng_if>
    #my $mng_if_value = &mng_if_value( $dh, $vm );
    my $mng_if_value = &mng_if_value( $vm );

    #my $if_list = $vm->getElementsByTagName("if");
    #for ( my $i = 0 ; $i < $if_list->getLength ; $i++ ) {
    foreach my $if ($vm->getElementsByTagName("if")) {
        my $id = $if->getAttribute("id");
        if (   ( $id == 0 )
            && $dh->get_vmmgmt_type ne 'none'
            && ( $mng_if_value ne "no" ) )
        {

            # Skip the management interface
            # Actually is a redundant checking, because check_semantics doesn't
            # allow a id=0 <if> if managemente interface hasn't been disabled
            next;
        }
        my @ipv4_list = $if->getElementsByTagName("ipv4");
        if ( @ipv4_list != 0 ) {
            my $ip = &text_tag( $ipv4_list[0] );
            if ( &valid_ipv4_with_mask($ip) ) {
                $ip =~ /^(\d+).(\d+).(\d+).(\d+).*$/;
                $ip = "$1.$2.$3.$4";
            }
            return $ip;
        }
    }

    # No valid IPv4 found
    return 0;
}


###################################################################
#
sub get_user_in_seq {

    my $vm  = shift;
    my $seq = shift;

    my $username = "";

    # Looking for in <exec>
    #my $exec_list = $vm->getElementsByTagName("exec");
    #for ( my $i = 0 ; $i < $exec_list->getLength ; $i++ ) {
    foreach my $exec ($vm->getElementsByTagName("exec")) {
        if ( $exec->getAttribute("seq") eq $seq ) {
            #if ( $exec->getAttribute("user") ne "" ) {
            unless ( empty($exec->getAttribute("user")) ) {
                $username = $exec->getAttribute("user");
                last;
            }
        }
    }

    # If not found in <exec>, try with <filetree>
    if ( $username eq "" ) {
        #my $filetree_list = $vm->getElementsByTagName("filetree");
        #for ( my $i = 0 ; $i < $filetree_list->getLength ; $i++ ) {
        foreach my $filetree ($vm->getElementsByTagName("filetree")) {
            if ( $filetree->getAttribute("seq") eq $seq ) {
                #if ( $filetree->getAttribute("user") ne "" ) {
                unless ( empty($filetree->getAttribute("user")) ) {
                    $username = $filetree->getAttribute("user");
                    last;
                }
            }
        }
    }

    # If no mode was found in <exec> or <filetree>, use default
    if ( $username eq "" ) {
        $username = "root";
    }

    return $username;

}



###################################################################
# save_dir_permissions
#
# Argument:
# - a directory in the host enviroment in which the permissions
#   of the files will be saved
#
# Returns:
# - a hash with the permissions (a 3-character string with an octal
#   representation). The key of the hash is the file name
#
sub save_dir_permissions {

    my $dir = shift;

    my @files = &get_directory_files($dir);
    my %file_perms;

    foreach (@files) {

        # The directory itself is ignored
        unless ( $_ eq $dir ) {

# Tip from: http://open.itworld.com/5040/nls_unix_fileattributes_060309/page_1.html
            my $mode = ( stat($_) )[2];
            $file_perms{$_} = sprintf( "%04o", $mode & 07777 );

            #print "DEBUG: save_dir_permissions $_: " . $file_perms{$_} . "\n";
        }
    }

    return %file_perms;
}



###################################################################
# get_directory_files
#
# Argument:
# - a directory in the host enviroment
#
# Returns:
# - a list with all files in the given directory
#
sub get_directory_files {

    my $dir = shift;

    # FIXME: the current implementation is based on invoking find shell
    # command. Maybe there are smarter ways of doing the same
    # just with Perl commands. This would remove the need of "find"
    # in @binaries_mandatory in BinariesData.pm

    my $command = $bd->get_binaries_path_ref->{"find"} . " $dir";
    my $out     = `$command`;
    my @files   = split( /\n/, $out );

    return @files;
}



###################################################################
# Wait for a filetree end file (see conf_files function)
sub filetree_wait {
    my $file = shift;

    do {
        if ( -f $file ) {
            return 1;
        }
        sleep 1;
    } while (1);
    return 0;
}

=BEGIN

#
# Get the value of a simple tag in extended configuration file
# 
# Returns the value of the parameter or the default value if not found 
# 
sub get_simple_conf {

    my $extConfFile = shift;
    my $vm_name      = shift;
    my $tagName     = shift;
    
    my $global_tag = 1;
    my $result;
    
    #if     ($tagName eq 'sparsemem') { $result = 'true'; }
    #elsif  ($tagName eq 'ghostios')  { $result = 'false'; }
    #elsif  ($tagName eq 'npe')       { $result = '200'; }
    #elsif  ($tagName eq 'chassis')   { $result = '3640'; }
        
    # If the extended config file is not defined, return default value 
    if ($extConfFile eq '0'){
        return "$result\n";
    }
    
    # Parse the extended config file
    my $parser       = XML::LibXML->new();
    my $dom          = $parser->parse_string($extConfFile);
    #my $parser       = new XML::DOM::Parser;
    #my $dom          = $parser->parsefile($extConfFile);
    my $global_node   = $dom->getElementsByTagName("vnx_olive")->item(0);
    #my $virtualmList = $global_node->getElementsByTagName("vm");
            
    # First, we look for a definition in the $vm_name <vm> section 
    #for ( my $j = 0 ; $j < $virtualmList->getLength ; $j++ ) {
    foreach my $vm ($global_node->getElementsByTagName("vm")) {
        # We get name attribute
        #my $vm = $virtualmList->item($j);
        my $name = $vm->getAttribute("name");
        if ( $name eq $vm_name ) {
            my $tag_list = $vm->getElementsByTagName("$tagName");
            if ($tag_list->getLength gt 0){
                my $tag = $tag_list->item(0);
                $result = &text_tag($tag);
                $global_tag = 0;
                            print "*** vmName = $name, specific entry found ($result)\n";
            }
            last;
        }
    }
    # Then, if a virtual machine specific definition was not found, 
    # have a look in the <global> section
    if ($global_tag eq 1){
        my @globalList = $global_node->getElementsByTagName("global");
        if (@globalList gt 0){
            my $globaltag = $globalList[0];
            my @tag_gl_list = $globaltag->getElementsByTagName("$tagName");
            if (@tag_gl_list gt 0){
                my $tag_gl = $tag_gl_list[0];
                $result = &text_tag($tag_gl);
                print "*** vmName = $vm_name, global entry found ($result)\n";
            }
        }   
    }
    return $result;
}
=END
=cut

1;

