#
# vmAPI_dynamips.pm
#
# This file is a module part of VNX package.
#
# Authors: Jorge Rodriguez, David Fernández, Jorge Somavilla
# Coordinated by: David Fernández (david@dit.upm.es)
#
# Copyright (C) 2011, 	DIT-UPM
# 			Departamento de Ingenieria de Sistemas Telematicos
#			Universidad Politecnica de Madrid
#			SPAIN
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

#

package VNX::vmAPI_dynamips;

use strict;
use warnings;
use Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
  init
  define_vm
  undefine_vm
  start_vm
  shutdown_vm
  suspend_vm
  resume_vm
  save_vm
  restore_vm
  get_state_vm
  execute_cmd
  );

  
use XML::LibXML;
use VNX::Globals;
use VNX::Execution;
use VNX::BinariesData;
use VNX::CheckSemantics;
use VNX::TextManipulation;
use VNX::NetChecks;
use VNX::FileChecks;
use VNX::DocumentChecks;
use VNX::IPChecks;
use VNX::CiscoConsMgmt;
use VNX::vmAPICommon;
use Net::Telnet;
use NetAddr::IP;
use File::Basename;
use File::Spec;


my $dynamips_host;
my $dynamips_port;
my $dynamips_ver_num;
my $dynamips_ver_string;

# ---------------------------------------------------------------------------------------
#
# Module vmAPI_dynamips initialization code 
#
# ---------------------------------------------------------------------------------------
sub init {
	
	my $logp = "dynamips-init> ";
	my $error;
    my @lines;
    my $ret_code;
    my $ret_str;
    
    return unless ( $dh->any_vmtouse_of_type('dynamips') );

	$dynamips_host = "localhost";
	$dynamips_port = get_conf_value ($vnxConfigFile, 'dynamips', 'port', 'root');
	if (!defined $dynamips_port) { $dynamips_port = $DYNAMIPS_DEFAULT_PORT };
	
	# Get dynamips version
	my $t;
	my $t_error = t_connect(\$t);
	unless ($t_error) {
    
        my $res = dyn_cmd($t, "hypervisor version", \@lines, \$ret_code, \$ret_str );
        return $res if ($res);
        $dynamips_ver_string = $ret_str;
        $dynamips_ver_num = $dynamips_ver_string;
        $dynamips_ver_string =~ s/100-//;
        $dynamips_ver_num =~ s/-.*//;
	    wlog (N, "  Dynamips ver=$dynamips_ver_string") unless ($opts{b});

    } else {
        $error = "Dynamips telnet object returns '" . $t_error . "'";
    }
    
    $t->close;
    return $error;
}    

# ---------------------------------------------------------------------------------------
#
# define_vm
#
# Defined a virtual machine 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
#   - $vm_doc: XML document describing the virtual machine in DOM tree format
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub define_vm {
	
	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;
	my $vm_doc    = shift;
	
	my $logp = "dynamips-define_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", "$logp");
	
	my $error;
    my $ret_code;
    my $ret_str;
    my $res;
    my @lines;
    	
    my $extConfFile;
	my $newRouterConfFile;
	my $ifTagList;

	# Get the extended configuration file if it exists
	$extConfFile = $dh->get_default_dynamips();
	if ($extConfFile ne "0"){
		$extConfFile = get_abs_path ($extConfFile);
	}
	
    my $doc = $dh->get_doc;                                # scenario global doc
    my $vm = $vm_doc->findnodes("/create_conf/vm")->[0];   # VM node in $vm_doc
    my @vm_ordered = $dh->get_vm_ordered;                  # ordered list of VMs in scenario 

#    my $parser       = XML::LibXML->new();
#    my $dom          = $parser->parse_string($vm_doc);
#	my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
#	my $virtualmList = $globalNode->getElementsByTagName("vm");
#	my $virtualm     = $virtualmList->item(0);
	
	my $filesystemTagList = $vm->getElementsByTagName("filesystem");
	my $filesystemTag     = $filesystemTagList->item(0);
	my $filesystem_type   = $filesystemTag->getAttribute("type");
	my $filesystem        = $filesystemTag->getFirstChild->getData;
	
	# Get the configuration file name of the router (if defined) 
	# form the extended config file
	my $routerConfFile = get_router_conf_file($extConfFile, $vm_name);

	# $newRouterConfFile is the file where we will store the configuration of the new router	
	$newRouterConfFile = $dh->get_vm_dir($vm_name) . "/" . $vm_name . ".conf";
	
	if ($routerConfFile ne 0) {
		# A router config file has been defined, we check if exists 
	 	if (-e $routerConfFile)	{
			# Router config file exists: we copy the content of the conf file 
			# provided to the new file, but deleting the "end" command 
			# (if exists) to allow adding new configuration commands at the end
	   	 	$execution->execute( $logp, "sed '/^end/d' " . $routerConfFile . ">" . $newRouterConfFile);
		}else{
			# ERROR: The router config file has been defined, but it does not exists 
			return "ERROR: cannot open " . $routerConfFile;
		}
	} else {
		# No configuration file defined for the router 
	}
	
	my @routerConf = create_router_conf ($vm_name, $extConfFile);
	open (CONF, ">> $newRouterConfFile") or return "ERROR: Cannot open $newRouterConfFile";
	print CONF @routerConf;
	close (CONF);
 	
    # Memory
    my @memTagList = $vm->getElementsByTagName("mem");
    my $mem = "96";

	if ( @memTagList != 0 ) {
		$mem   = ($memTagList[0]->getFirstChild->getData)/1024;
	} 
	
    # Connect with dynamips hypervisor
	my $line;
    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    
    $res = dyn_cmd($t, "hypervisor working_dir \"". $dh->get_vm_fs_dir($vm_name). "\" ", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);

    #t_print ($t, "hypervisor working_dir \"". $dh->get_vm_fs_dir($vm_name). "\" ", $logp);
    #$line = t_getline ($t, $logp);
	
	# Set type
	my($trash,$model)=split(/-/,$type,2);

    $res = dyn_cmd($t, "vm create $vm_name 0 c$model", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
	#t_print ($t, "vm create $vm_name 0 c$model", $logp);
	#$line = t_getline ($t, $logp);
	
  	#
	# VM CONSOLES
	# 
	# Go through <consoles> tag list to see if specific ports have been
	# defined for the consoles and the value of display attribute if specified
	# In Dynamips, only con1 (console port, for all routers) and 
	# con2 (aux port, only for c7200) are allowed
	# 
    my $consType;
    my %consPortDefInXML = (1,'',2,'');     # % means that consPortDefInXML is a perl associative array 
    my %consDisplayDefInXML = (1,$CONS_DISPLAY_DEFAULT,2,$CONS_DISPLAY_DEFAULT); 
    #print "** $vm_name: console ports, con1='$consPortDefInXML{1}', con2='$consPortDefInXML{2}'\n" if ($exemode == $EXE_VERBOSE);
	foreach my $cons ($vm->getElementsByTagName("console")) {
   		my $value = text_tag($cons);
		my $id    = $cons->getAttribute("id");        # mandatory
		my $display = $cons->getAttribute("display"); # optional
		my $port = $cons->getAttribute("port");       # optional
   		#print "** console: id=$id, display=$display port=$port value=$value\n" if ($exemode == $EXE_VERBOSE);
		if ( ($id eq "1") || ($id eq "2") ) {
			if ( $value ne "" && $value ne "telnet" ) { 
				wlog (N, "WARNING (vm=$vm_name): only 'telnet' value is allowed for Dynamips consoles. Value ignored.", $logp);
			}
			$consPortDefInXML{$id} = $port;
			if ($display ne '') { $consDisplayDefInXML{$id} = $display }
		}
		if ( ( $id eq "0" ) || ($id > 1) ) {
			wlog (N, "WARNING (vm=$vm_name): only consoles with id='1' or '2' allowed for Dynamips virtual machines. Tag with id=$id ignored.", $logp)
		} 
	}
	#print "** $vm_name: console ports, con1='$consPortDefInXML{1}', con2='$consPortDefInXML{2}'\n" if ($exemode == $EXE_VERBOSE);

    # Define ports for main console (all) and aux console (only for 7200)
	my @consolePort = qw();
    foreach my $j (1, 2) {
		if (empty($consPortDefInXML{$j})) { # telnet port not defined we choose a free one starting from $CONS_PORT
			$consolePort[$j] = $VNX::Globals::CONS_PORT;
			while ( !system("fuser -n tcp $consolePort[$j]") ) {
				$consolePort[$j]++;
			}
			$VNX::Globals::CONS_PORT = $consolePort[$j] + 1;
		} else { # telnet port was defined in <console> tag
		    
			$consolePort[$j] = $consPortDefInXML{$j};
			while ( !system("fuser -n tcp $consolePort[$j]") ) {
				$consolePort[$j]++;
			}
		}
		wlog (V, "WARNING (vm=$vm_name): cannot use port $consPortDefInXML{1} for console #1; using $consolePort[$j] instead", $logp)
	   		if ( (!empty($consPortDefInXML{$j})) && ($consolePort[$j] ne $consPortDefInXML{$j}) );
    }
	
	#my $consoleport = get_port_conf($vm_name,$counter);
	my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
	
	open (PORT_CISCO, ">$consFile") || return "ERROR (vm=$vm_name): cannot open $consFile";
	print PORT_CISCO "con1=$consDisplayDefInXML{1},telnet,$consolePort[1]\n";

    $res = dyn_cmd($t, "vm set_con_tcp_port $vm_name $consolePort[1]", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
	#t_print ($t, "vm set_con_tcp_port $vm_name $consolePort[1]", $logp);
    #$line = t_getline ($t, $logp); 
    if ($type eq 'dynamips-7200') {
    	# Configure aux port
		print PORT_CISCO "con2=$consDisplayDefInXML{2},telnet,$consolePort[2]\n";
	    $res = dyn_cmd($t, "vm set_con_tcp_port $vm_name $consolePort[2]", \@lines, \$ret_code, \$ret_str );
	    return $res if ($res);
		#t_print ($t, "vm set_con_tcp_port $vm_name $consolePort[2]", $logp);
	    #$line = t_getline ($t, $logp);
    }
	close (PORT_CISCO);
    
    # Set Chassis
    my $chassis = merge_simpleconf($extConfFile, $vm_name, 'chassis');
    $chassis =~ s/c//;
    $res = dyn_cmd($t, "c$model set_chassis $vm_name $chassis", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
    #t_print ($t, "c$model set_chassis $vm_name $chassis", $logp);
    #$line = t_getline ($t, $logp);

    # Set NPE if 7200
    if ($model eq '7200') {
	    my $npe = merge_simpleconf($extConfFile, $vm_name, 'npe');
        $res = dyn_cmd($t, "c$model set_npe $vm_name npe-$npe", \@lines, \$ret_code, \$ret_str );
        return $res if ($res);
	    #t_print ($t, "c$model set_npe $vm_name npe-$npe", $logp);
	    #$line = t_getline ($t, $logp);
    } 
    
	# Set Filesystem
    $res = dyn_cmd($t, "vm set_ios $vm_name $filesystem", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
    #t_print ($t, "vm set_ios $vm_name $filesystem", $logp);
    #$line = t_getline ($t, $logp);
    
    # Set Mem
    $res = dyn_cmd($t, "vm set_ram $vm_name $mem", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
    #t_print ($t, "vm set_ram $vm_name $mem", $logp);
    #$line = t_getline ($t, $logp);
    if (merge_simpleconf($extConfFile, $vm_name, 'sparsemem') eq "true"){
	    $res = dyn_cmd($t, "vm set_sparse_mem $vm_name 1", \@lines, \$ret_code, \$ret_str );
	    return $res if ($res);
		#t_print ($t, "vm set_sparse_mem $vm_name 1", $logp);
   		#$line = t_getline ($t, $logp);
    }
    
    # Set IDLEPC
    my $imgName = basename ($filesystem);
    # Look for a specific idle_pc value for this image
    my $idlepc = get_conf_value ($vnxConfigFile, 'dynamips', "idle_pc-$imgName", 'root');
    if (!defined $idlepc) { 
    	# Look for a generic idle_pc value 
    	$idlepc = get_conf_value ($vnxConfigFile, 'dynamips', 'idle_pc', 'root');   
	    if (!defined $idlepc) { 
    		# Use default value in VNX::Globals
    		$idlepc = $DYNAMIPS_DEFAULT_IDLE_PC;
	    } 
    }

    #print "*** idlepc = $idlepc \n";
    $res = dyn_cmd($t, "vm set_idle_pc $vm_name $idlepc", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
	#t_print ($t, "vm set_idle_pc $vm_name $idlepc", $logp);
    #$line = t_getline ($t, $logp);
    
    #Set ios ghost
    if (merge_simpleconf($extConfFile, $vm_name, 'ghostios') eq "true"){
	    $res = dyn_cmd($t, "vm set_ghost_status $vm_name 2", \@lines, \$ret_code, \$ret_str );
	    return $res if ($res);
		#t_print ($t, "vm set_ghost_status $vm_name 2", $logp);
    	#$line = t_getline ($t, $logp);
    	my $temp = basename($filesystem);
        $res = dyn_cmd($t, "vm set_ghost_file $vm_name \"$temp.image-localhost.ghost\" ", \@lines, \$ret_code, \$ret_str );
        return $res if ($res);
		#t_print ($t, "vm set_ghost_file $vm_name \"$temp.image-localhost.ghost\" ", $logp);
    	#$line = t_getline ($t, $logp);
    }
    
    #Set Blk_direct_jump
    $res = dyn_cmd($t, "vm set_blk_direct_jump $vm_name 0", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
	#t_print ($t, "vm set_blk_direct_jump $vm_name 0", $logp);
    #$line = t_getline ($t, $logp);
    
    # Add slot cards
    my @cards=get_cards_conf($extConfFile, $vm_name);
    my $index = 0;
    foreach my $slot (@cards){
	    $res = dyn_cmd($t, "vm slot_add_binding $vm_name $index 0 $slot", \@lines, \$ret_code, \$ret_str );
	    return $res if ($res);
		#t_print ($t, "vm slot_add_binding $vm_name $index 0 $slot", $logp);
    	#$line = t_getline ($t, $logp);
    	$index++;
    }
    
    # Connect virtual networks to host interfaces
	foreach my $if ($vm->getElementsByTagName("if")) {
		my $name  = $if->getAttribute("name");
		my $id    = $if->getAttribute("id");
		my $net   = $if->getAttribute("net");
		my ($slot, $dev)= split("/",$name,2);
		$slot = substr $slot,-1,1;
		if ( $name =~ /^[gfeGFE]/ ) {
			#print "**** Ethernet interface: $name, slot=$slot, dev=$dev\n";
	        $res = dyn_cmd($t, "nio create_tap nio_tap_$vm_name$slot$dev $vm_name-e$id", \@lines, \$ret_code, \$ret_str );
	        return $res if ($res);
			#t_print ($t, "nio create_tap nio_tap_$vm_name$slot$dev $vm_name-e$id", $logp);
	   		#$line = t_getline ($t, $logp);
            $res = dyn_cmd($t, "vm slot_add_nio_binding $vm_name $slot $dev nio_tap_$vm_name$slot$dev", \@lines, \$ret_code, \$ret_str );
            return $res if ($res);
	   		#t_print ($t, "vm slot_add_nio_binding $vm_name $slot $dev nio_tap_$vm_name$slot$dev", $logp);
	   		#$line = t_getline ($t, $logp);
		}
		elsif ( $name =~ /^[sS]/ ) {
			#print "**** Serial interface: $name, slot=$slot, dev=$dev\n";			
			#print "**** Serial interface: VNX::Globals::SERLINE_PORT=$VNX::Globals::SERLINE_PORT\n";
			
			#
			# Ports used to create the virtual serial line for the pt2pt link are
			# stored in a file under $vnxDir/networks. For example, for a link that 
			# joins two routers, r1 and r2, using a net named Net1 the file is named:
			#
			#     $vnxDir/networks/Net1.ports
			#
			# and the content is:
			#
			#     r1=12002
			#     r2=12003
			#
			# First, we check if the file already exists
			my @vms;
			my @ports;
			my $portsFile = $dh->get_networks_dir . "/" . $net . ".ports";
			#print "**** portsFile=$portsFile\n"; 
			if (!-e $portsFile) {
				#print "*** $portsFile does not exist, creating it...\n";
				# We choose two free UDP ports
				for ( my $i = 0 ; $i <= 1 ; $i++ ) {
					$ports[$i] = $VNX::Globals::SERLINE_PORT;
					while ( !system("fuser -s -v -n tcp $ports[$i]") ) {
						$ports[$i]++;
					}
					$VNX::Globals::SERLINE_PORT = $ports[$i] + 1;
				}
				# Get virtual machines connected to the serial line
				my ($vmsInNet,$ifsInNet) = $dh->get_vms_in_a_net ($net);
				if (scalar @$vmsInNet != 2) { return "ERROR: point-to-point network $net has " . scalar @vms . " virtual machines connected (must be 2)"; }
				#@vms = @$vmsInNet;
				$vms[0] = @$vmsInNet[0]->getAttribute ("name");
				$vms[1] = @$vmsInNet[1]->getAttribute ("name");
				# and we write it to the file
				open (PORTS_FILE, "> $portsFile") || return "ERROR: Cannot open file $portsFile for writting $net serial line ports";
				for ( my $i = 0 ; $i <= 1 ; $i++ ) {
					#print "**** $vms[$i]=$ports[$i]\n";
					print PORTS_FILE "$vms[$i]=$ports[$i]\n";
				}
				close (PORTS_FILE); 				
			} else {
				#print "*** $portsFile already exists, reading it...\n";
				# The file already exists; we read it and load the values
				open (PORTS_FILE, "< $portsFile") || return "Could not open $portsFile file.";
				foreach my $line (<PORTS_FILE>) {
				    chomp($line);               # remove the newline from $line.
				    my $name = $line;				    
				    $name =~ s/=.*//;  	  
				    my $port = $line;
					$port =~ s/.*=//;  
					#print "**** vm=$name, port=$port\n";
				    push (@vms,$name);
				    push (@ports,$port);
				}	
				close (PORTS_FILE); 							
			}
			#print "**** Serial interface: ports[0]=$ports[0], ports[1]=$ports[1]\n";
			if ($vms[0] eq $vm_name) {
	            $res = dyn_cmd($t, "nio create_udp nio_udp_$vm_name$slot$dev $ports[0] 127.0.0.1 $ports[1]", \@lines, \$ret_code, \$ret_str );
	            return $res if ($res);
				#t_print ($t, "nio create_udp nio_udp_$vm_name$slot$dev $ports[0] 127.0.0.1 $ports[1]", $logp);
			} else {
                $res = dyn_cmd($t, "nio create_udp nio_udp_$vm_name$slot$dev $ports[1] 127.0.0.1 $ports[0]", \@lines, \$ret_code, \$ret_str );
                return $res if ($res);
				#t_print ($t, "nio create_udp nio_udp_$vm_name$slot$dev $ports[1] 127.0.0.1 $ports[0]", $logp);
			}
	   		#$line = t_getline ($t, $logp);
            $res = dyn_cmd($t, "vm slot_add_nio_binding $vm_name $slot $dev nio_udp_$vm_name$slot$dev", \@lines, \$ret_code, \$ret_str );
            return $res if ($res);
	   		#t_print ($t, "vm slot_add_nio_binding $vm_name $slot $dev nio_udp_$vm_name$slot$dev", $logp);
	   		#$line = t_getline ($t, $logp);
		}
   		$execution->execute( $logp, "ifconfig $vm_name-e$id 0.0.0.0");
	}
	
	# Set config file to router
    $res = dyn_cmd($t, "vm set_config $vm_name \"$newRouterConfFile\" ", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
   	#t_print ($t, "vm set_config $vm_name \"$newRouterConfFile\" ", $logp);
   	#$line = t_getline ($t, $logp);
   	$t->close;
    
    return $error;
    
}

sub create_router_conf {

	my $vm_name      = shift;
	my $extConfFile = shift;

	my @routerConf;

    my $logp = "dynamips-create_router_conf> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, extConfFile=$extConfFile ...)", "$logp");

	# Load and parse libvirt XML definition of virtual machine
	#my $vm_xml_file = $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_conf.xml';
	#open XMLFILE, "$vm_xml_file" or return "can not open $vm_xml_file file";
	#my $doc = do { local $/; <XMLFILE> };
	#close XMLFILE;

    #my $parser       = XML::LibXML->new();
    #my $dom          = $parser->parse_string($doc);
    
    my $doc =$dh->get_vm_doc($vm_name,'dom');
	my $vm = $doc->getElementsByTagName("vm")->item(0);

   	# Hostname
	push (@routerConf,  "hostname " . $vm_name ."\n");

	# Enable IPv4 and IPv6 routing
	push (@routerConf,  "ip routing\n");	
	push (@routerConf,  "ipv6 unicast-routing\n");	

	# Network interface configuration
	# P.ej:
	# 	interface e0/0
	# 	 mac-address fefd.0003.0101
	# 	 ip address 10.1.1.4 255.255.255.0
	# 	 ip address 11.1.1.4 255.255.255.0 secondary
	# 	 ipv6 enable
	# 	 ipv6 address 2001:db8::1/64
	# 	 ipv6 address 2001:db9::1/64
	# 	 no shutdown
 	foreach my $if ($vm->getElementsByTagName("if")) {
		my $id    = $if->getAttribute("id");
		my $net   = $if->getAttribute("net");
		my $mac   = $if->getAttribute("mac");
		$mac =~ s/,//;
		my @maclist = split(/:/,$mac);
		$mac = $maclist[0] . $maclist[1] . "." . $maclist[2] . $maclist[3] . "." . $maclist[4] . $maclist[5];
		my $nameif   = $if->getAttribute("name");
		push (@routerConf,  "interface " . $nameif . "\n");	
		push (@routerConf,  " mac-address " . $mac . "\n");
		# Configure IPv4 addresses		
		my @ipv4_list = $if->getElementsByTagName("ipv4");
		if (@ipv4_list == 0) {
			push (@routerConf,  " no ip address\n");	
		} else {
	 		for ( my $i = 0 ; $i < @ipv4_list; $i++ ) {
				my $ipv4_tag = $ipv4_list[$i];
				my $ipv4 =  $ipv4_tag->getFirstChild->getData;
				my $subnetv4 = $ipv4_tag->getAttribute("mask");
				if ($i == 0) {
					push (@routerConf,  " ip address " . $ipv4 . " ". $subnetv4 . "\n");	
				} else {
					push (@routerConf,  " ip address " . $ipv4 . " ". $subnetv4 . " secondary\n");					
				}
	 		}
 		}
		# Configure IPv6 addresses		
		my @ipv6_list = $if->getElementsByTagName("ipv6");
	    if ( @ipv6_list != 0 ) {
            push (@routerConf,  " ipv6 enable\n");  
	    }	    	
		foreach my $ipv6 (@ipv6_list) {
            #my $ipv6 =  $ipv6_Tag->getFirstChild->getData;
            push (@routerConf,  " ipv6 address " . $ipv6->getFirstChild->getData . "\n");	
 		}
		# Levantamos la interfaz
		push (@routerConf,  " no shutdown\n");		
 	}
 	# IP route configuration
 	foreach my $route ($vm->getElementsByTagName("route")) {
 		my $gw = $route->getAttribute("gw");
 		my $destination = $route->getFirstChild->getData;
 		my $maskdestination = "";
 		if ($destination eq "default"){
 			$destination = "0.0.0.0";
 			$maskdestination = "0.0.0.0";
 		}else {
 			#print "****** $destination\n";
 			my $ip = new NetAddr::IP ($destination) or return NetAddr::IP::Error();
 			$maskdestination = $ip->mask();
 			$destination = $ip->addr();
 		}
 		push (@routerConf,  "ip route ". $destination . " " . $maskdestination . " " . $gw . "\n");	
 		
 	}
 	# Si en el fichero de configuracion extendida se define un usuario y password.
 	my @login_users = merge_login($extConfFile, $vm_name);
 	my $login_user;
 	my $check_login_user = 0;
 	foreach $login_user(@login_users){
 		my $user=$login_user->[0];
 		my $pass=$login_user->[1];
 		if (($user eq "")&&(!($pass eq ""))){
 			push (@routerConf,  " line con 0 \n");
 			push (@routerConf,  " password $pass\n");
 			push (@routerConf,  " login\n");
 		}elsif((!($user eq ""))&&(!($pass eq ""))){
			push (@routerConf,  " username $user password 0 $pass\n");
			$check_login_user= 1;
 		}
    }
    if ($check_login_user eq 1){
    	push (@routerConf,  " line con 0 \n");
 		push (@routerConf,  " login local\n");
    }
    	
 	# Si el fichero de configuacion extendida se define una password de enable, se pone.
 	my $enablepass = merge_enablepass($extConfFile, $vm_name);
 	if (!($enablepass eq "")){
		push (@routerConf,  " enable password " . $enablepass . "\n");
    }
    # Se habilita el ip http server ya que si no se hace, el acceso por telnet se bloquea.
 	# push (@routerConf,  "ip http server\n";
 	push (@routerConf,  " end\n");

	return @routerConf;
}

# ---------------------------------------------------------------------------------------
#
# undefine_vm
#
# Undefines a virtual machine 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub undefine_vm{

	my $self    = shift;
	my $vm_name = shift;
	my $type    = shift;

    my $logp = "dynamips-undefine_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", "$logp");

	my $error;
    my $ret_code;
    my $ret_str;
    my $res;
    my @lines;
    	
    wlog (V, "Undefining router: $vm_name", $logp);
    
    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    $res = dyn_cmd($t, "vm delete $vm_name", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);

    # Remove vm directory content, all but VM XML specification file
    #$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_vm_dir($vm_name) . "/*" );
    $execution->execute( $logp, $bd->get_binaries_path_ref->{"find"} . " " . 
                                $dh->get_vm_dir($vm_name) . "/* " . "! -name '*.xml' -delete");

    #
    # Contact dynamips hypervisor and destroy the nio interfaces associated with the router
    #
    # Load and parse VM XML definition of virtual machine
    #my $vm_xml_file = $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_conf.xml';
    #if (-e $vm_xml_file) {
        #open XMLFILE, "$vm_xml_file" or return "can not open $vm_xml_file file";
        #my $doc = do { local $/; <XMLFILE> };
        #close XMLFILE;
        #my $parser = XML::LibXML->new();
        #my $dom    = $parser->parse_string($doc);
        
        my $doc = $dh->get_vm_doc($vm_name,'dom');
        my $vm  = $doc->getElementsByTagName("vm")->item(0);
    
        foreach my $if ($vm->getElementsByTagName("if")) {
            my $ifName = $if->getAttribute("name");
            my ($slot, $dev)= split("/",$ifName,2);
            $slot = substr $slot,-1,1;
            wlog (V, "Ethernet interface: $ifName, slot=$slot, dev=$dev", $logp);
            if ( $ifName =~ /^[gfeGFE]/ ) {
			    $res = dyn_cmd($t, "nio delete nio_tap_$vm_name$slot$dev", \@lines, \$ret_code, \$ret_str );
			    return $res if ($res);
            }
            elsif ( $ifName =~ /^[sS]/ ) {
                $res = dyn_cmd($t, "nio delete nio_udp_$vm_name$slot$dev", \@lines, \$ret_code, \$ret_str );
                return $res if ($res);
            }
        }
        # Remove VM XML specification file
        #$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -f $vm_xml_file" );
    #}
    $t->close;
    
    return $error;
}


# ---------------------------------------------------------------------------------------
#
# start_vm
#
# Starts a virtual machine already defined with define_vm
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
#   - $no_consoles: if true, virtual machine consoles are not opened
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub start_vm {

	my $self    = shift;
	my $vm_name  = shift;
	my $type    = shift;
	my $no_consoles = shift;
	
    my $logp = "dynamips-start_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", "$logp");

	my $error;
    my $ret_code;
    my $ret_str;
    my $res;
    my @lines;
	
    wlog (V, "Starting router: $vm_name", $logp);

    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    $res = dyn_cmd($t, "vm start $vm_name", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);

    # Read the console file and start the active consoles,
	# unless options -n|--no_console were specified by the user
	unless ($no_consoles eq 1){
	   VNX::vmAPICommon->start_consoles_from_console_file ($vm_name);
	}	
	
    # If host_mapping is in use and the vm has a management interface, 
    # then we have to add an entry for this vm in /etc/hosts
    if ( $dh->get_host_mapping ) {
        my @vm_ordered = $dh->get_vm_ordered;
        for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
            my $vm = $vm_ordered[$i];
            my $name = $vm->getAttribute("name");
            unless ( $name eq $vm_name ) { next; }
                                    
                # Check whether the vm has a management interface enabled
                my $mng_if_value = mng_if_value($vm);
                unless ( ($dh->get_vmmgmt_type eq 'none' ) || ($mng_if_value eq "no") ) {
                            
                # Get the vm management ip address 
                my %net = get_admin_address( 'file', $vm_name );
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

# ---------------------------------------------------------------------------------------
#
# shutdown_vm
#
# Shutdowns a virtual machine
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub shutdown_vm{
	my $self    = shift;
	my $vm_name = shift;
	my $type    = shift;
    my $kill    = shift;
	
	my $logp = "dynamips-shutdown_vm-$vm_name> ";
	my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", "$logp");
	
	my $error;
    my $line;
    my $ret_code;
    my $ret_str;
    my $res;
    my @lines;
	
	# This is an ordered shutdown. We first save the configuration:

	# To be implemented

    wlog (N, "Shutdowning router $vm_name", $logp);

    # Then we shutdown and destroy the virtual router:
    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    if ($kill) {
        $res = dyn_cmd($t, "vm stop $vm_name", \@lines, \$ret_code, \$ret_str );
        # Do not return any error...
    } else {
        $res = dyn_cmd($t, "vm stop $vm_name", \@lines, \$ret_code, \$ret_str );
        return $res if ($res);
    }

    #t_print ($t, "vm stop $vm_name", $logp);
    #$line = t_getline ($t, $logp);
    $t->close;
    		
	return $error;
}

# ---------------------------------------------------------------------------------------
#
# save_vm
#
# Stops a virtual machine and saves its status to disk
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
#   - $filename: the name of the file to save the VM state to
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub save_vm{
	
	my $self     = shift;
	my $vm_name   = shift;
	my $type     = shift;
	my $filename = shift;
	
	my $logp = "dynamips-save_vm-$vm_name> ";
	my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", "$logp");
	
	my $error;
	my $ret_code;
    my $ret_str;
    my $res;
    my @lines;
		
    wlog (V, "Saving router: $vm_name", $logp);
    
    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    $res = dyn_cmd($t, "vm extract_config $vm_name", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
    #t_print ($t, "vm extract_config $vm_name", $logp);
    #my $line = t_getline ($t, $logp);
    $t->close;

    return $error;	
}

# ---------------------------------------------------------------------------------------
#
# restore_vm
#
# Restores the status of a virtual machine from a file previously saved with save_vm
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
#   - $filename: the name of the file with the VM state
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub restore_vm{
	
	my $self     = shift;
	my $vm_name   = shift;
	my $type     = shift;
	my $filename = shift;
	
	my $logp = "dynamips-restore_vm-$vm_name> ";
	my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", "$logp");

    my $error;
    my $ret_code;
    my $ret_str;
    my $res;
    my @lines;
    
    wlog (V, "Restoring router: $vm_name", $logp);

    return "not implemented...";

    sleep(2);
    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    $res = dyn_cmd($t, "?? ", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
    #t_print ($t, "vm stop $vm_name", $logp);
    #my $line = t_getline ($t, $logp);
    sleep(2);
    $res = dyn_cmd($t, "?? ", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
    #t_print ($t, "vm start $vm_name", $logp);
    #$line = t_getline ($t, $logp);
    $t->close;

    return $error;
    	
}

# ---------------------------------------------------------------------------------------
#
# suspend_vm
#
# Stops a virtual machine and saves its status to memory
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub suspend_vm{

	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "dynamips-suspend_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", "$logp");

    my $error;
    my $ret_code;
    my $ret_str;
    my $res;
    my @lines;
    
    wlog (V, "Suspending router: $vm_name", $logp);
	
    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    $res = dyn_cmd($t, "vm suspend $vm_name", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
    #t_print ($t, "vm suspend $vm_name", $logp);
    #my $line = t_getline ($t, $logp);
    $t->close;

    return $error;	
}

# ---------------------------------------------------------------------------------------
#
# resume_vm
#
# Restores the status of a virtual machine from memory (previously saved with suspend_vm)
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub resume_vm{

	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "dynamips-resume_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", "$logp");

    my $error;
    my $ret_code;
    my $ret_str;
    my $res;
    my @lines;

    wlog (V, "Resuming router: $vm_name", $logp);
    
    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    $res = dyn_cmd($t, "vm resume $vm_name", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
    #t_print ($t, "vm resume $vm_name", $logp);
    #my $line = t_getline ($t, $logp);
    $t->close;

    return $error;	
}

=BEGIN
# ---------------------------------------------------------------------------------------
#
# reboot_vm
#
# Reboots a virtual machine
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub reboot_vm{
	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "dynamips-reboot_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", "$logp");

    my $error;
    my $ret_code;
    my $ret_str;
    
    wlog (V, "Rebooting router: $vm_name", $logp);
	
    sleep(2);
    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    t_print ($t, "vm stop $vm_name", $logp);
    my $line = t_getline ($t, $logp);
    sleep(2);
    t_print ($t, "vm start $vm_name", $logp);
    $line = t_getline ($t, $logp);
    $t->close;

    return $error;

}

# ---------------------------------------------------------------------------------------
#
# reset_vm
#
# Restores the status of a virtual machine form a file previously saved with save_vm
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub reset_vm{
	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "dynamips-reset_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", "$logp");

    my $error;
    my $ret_code;
    my $ret_str;
    
    wlog (V, "Reseting router: $vm_name", $logp);
	
    sleep(2);
    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    t_print ($t, "vm stop $vm_name", $logp);
    my $line = t_getline ($t, $logp);
    sleep(2);
    t_print ($t, "vm start $vm_name", $logp);
    $line = t_getline ($t, $logp);
    $t->close;

    return $error;
    	
}
=END
=cut

# ---------------------------------------------------------------------------------------
#
# get_state_vm
#
# Returns the status of a VM from the hypervisor point of view 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $ref_hstate: reference to a variable that will hold the state of VM as reported by the hipervisor 
#   - $ref_vstate: reference to a variable that will hold the equivalent VNX state (undefined, defined, 
#                  running, suspended, hibernated) to the state reported by the supervisor (a best effort
#                  mapping among both state spaces is done) 
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub get_state_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $ref_hstate = shift;
    my $ref_vstate = shift;

    my $logp = "lxc-get_status_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name ...)", $logp);

    my $error;
    my $ret_code;
    my $ret_str;
    my $res;
    my @lines;


    # Implementation notes:
    # - For the standard version of Dynamips (0.2.8), the only way to get info about the status of a 
    #   router is command "vm list" of the hypervisor, that lists the routers started, but does not
    #   give any additional info (e.g. if the router is suspended)
    # - For the new version 0.2.11 (https://github.com/GNS3/dynamips/blob/v0.2.11/README.hypervisor)
    #   there is a more detailed command vm get_status <instance_name>, that gives more info about 
    #   the status of a router:  Return values: 0=inactive, 1=shutting down, 2=running, 3=suspended. 

    # Implementation for 0.2.8
    my $t;
    if ( $error = t_connect(\$t) ) { return $error }
    $res = dyn_cmd($t, "vm list", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
    #t_print ($t, "vm list", $logp);
    #my @lines = t_getline ($t, $logp);
    #print "vm list returns: " . join(", ", @lines) . "\n";

    my $found; 
    foreach my $line (@lines) { 
        wlog (VVV, "line=$line", $logp);
        if ( $line =~ /^101 $vm_name / ) { $found = 'true' } 
    }
    if ($found) {
        $$ref_vstate = "running";
        $$ref_hstate = "running";
    } else {
        $$ref_vstate = "undefined";
        $$ref_hstate = "undefined";
    }
    
    wlog (VVV, "state=$$ref_vstate, hstate=$$ref_hstate, error=$error");
    return $error;
}

# ---------------------------------------------------------------------------------------
#
# execute_cmd
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
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------

sub execute_cmd{

	my $self        = shift;
    my $vm_name      = shift;
	my $merged_type = shift;
	my $seq         = shift;
	my $vm          = shift;

    my $logp = "dynamips-execute_cmd-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$merged_type ...)", "$logp");

	my @output = "Nothing to show";
	my $temp;
	my $port;
	my $extConfFile; 
	
	my $error;
    my $ret_code;
    my $ret_str;
	
	# Recupero el puerto telnet de acceso al router
	my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
	# Configuro el fichero de configuracion extendida
	$extConfFile = $dh->get_default_dynamips();
	if ($extConfFile ne "0"){
		$extConfFile = get_abs_path ($extConfFile);
		#$extConfFile = validate_xml ($extConfFile);	# Moved to vnx.pl
	}
	# Get the console port from vm's console file
	open (PORT_CISCO, "< $consFile") || return "ERROR: cannot open $vm_name console file ($consFile)";
	my $conData;
	if ($merged_type eq 'dynamips-7200') { # we use con2 (aux port)
		$conData = get_conf_value ($consFile, '', 'con2');
	} else { # we use con1 (console port)
		$conData = get_conf_value ($consFile, '', 'con1');			
	}
	$conData =~ s/con.=//;  		# eliminate the "conX=" part of the line
	my @consField = split(/,/, $conData);
	$port=$consField[2];
	close (PORT_CISCO);	
	#print "** $vm_name: console port = $port\n";

    # Exec tag examples:
    #   <exec seq="brief" type="verbatim" mode="telnet" ostype="show">show ip interface brief</exec>
    #   <exec seq="brief" type="verbatim" mode="telnet" ostype="set">hostname Router1</exec>
    #   <exec seq="brief" type="verbatim" mode="telnet" ostype="load">conf/r1.conf</exec>

	# Loop through all vm <exec> tags 
	my $countcommand = 0;
	foreach my $command ($vm->getElementsByTagName("exec")) {
		my $cmd_seq_string = $command->getAttribute("seq");

		# Split the different commands in the same seq (tag, separated by commas (csv format)
		my @cmd_seqs = split(',',$cmd_seq_string);
		foreach my $cmd_seq (@cmd_seqs) {
		
		    # Remove leading or trailing spaces
            $cmd_seq =~ s/^\s+//;
            $cmd_seq =~ s/\s+$//;
		
			# Check if the seq atribute value is the one we look ($seq)
			if ( $cmd_seq eq $seq ) {
				
				my $type = $command->getAttribute("type");
				my $ostype = $command->getAttribute("ostype");
				wlog (VVV, "-- ostype = $ostype", "$vm_name> ");

				# Case 1. Verbatim type
				if ( $type eq "verbatim" ) { # <exec> tag specifies a single command
				
					my $command_tag = text_tag($command);
					if ( ($ostype eq 'show') || ($ostype eq 'set') ) {

						# Get the user name and password. If several users are defined, 
						# we just take the first one.
						my @login_users = merge_login($extConfFile, $vm_name);
		     			my $login_user = $login_users[0];
		 				my $user=$login_user->[0];
						my $pass=$login_user->[1];
						# Get enable password
 						my $enablepass = merge_enablepass($extConfFile, $vm_name);
						# create CiscoConsMgmt object to connect to router console
						my $sess = new VNX::CiscoConsMgmt ($dh->get_tmp_dir, 'localhost', $port, $user, $pass, $enablepass);
						# Connect to console
						my $res = $sess->open;
						if (!$res) { return "ERROR: cannot connect to ${vm_name}'s console at port $port.\n" .
                                            "       Please, release the router console and try again.\n"; }
						# Put router in priviledged mode
						if ($exemode == $EXE_VERBOSE) {
                            $res = $sess->goto_state ('enable', 'debug') ;
						} else {
							$res = $sess->goto_state ('enable') ;
						}
						if ($res eq 'timeout') {
							return "ERROR: timeout connecting to ${vm_name}'s console at port $port.\n" .
							       "       Please, release the router console and try again.\n"; 
                        } elsif ($res eq 'user_login_needed') { 
                            return "ERROR: invalid login connecting to ${vm_name}'s console at port $port\n" 
                        } elsif ($res eq 'invalid_login') { 
                            return "ERROR: invalid login connecting to ${vm_name}'s console at port $port\n" 
                        } elsif ($res eq 'bad_enable_passwd') { 
                            return "ERROR: invalid enable password connecting to ${vm_name}'s console at port $port\n" 
                        }
					    if ($ostype eq 'set') {	my @output = $sess->exe_cmd ('configure terminal'); }
						# execute the command
						my @output = $sess->exe_cmd ($command_tag);
						wlog (N, "\ncmd '$command_tag' result: \n\n@output\n");
					    if ($ostype eq 'set') {	my @output = $sess->exe_cmd ('end'); }
						$sess->exe_cmd ("disable");
						$sess->exe_cmd ("exit");
						$sess->close;

					} if ($ostype eq 'load') {
						
						my $newRouterConfFile = $dh->get_vm_dir($vm_name) . "/" . $vm_name . ".conf";
						
						# Parse command
						if ( $command_tag =~ /merge / ) {
							# Merge mode: add configuration in VNX spec (hostname, ip addressses and routes)
							# to the configuration file provided
							#print "*** load merge\n";
							$command_tag =~ s/merge //;
							my $confFile = get_abs_path($command_tag);
							if (-e $confFile) {
								# Eliminate end command if it exists
	   	 						$execution->execute( $logp, "sed '/^end/d' " . $confFile . ">" . $newRouterConfFile);
								# Add configuration in VNX spec file to the router config file
								my @routerConf = create_router_conf ($vm_name, $extConfFile);
								open (CONF, ">> $newRouterConfFile") or return "ERROR: Cannot open $newRouterConfFile";
								print CONF @routerConf;
								close (CONF);
								$error = reload_conf ($vm_name, $newRouterConfFile, $dynamips_host, $dynamips_port, $consFile);
							} else {
								 return "ERROR: configuration file $confFile not found\n" 
							}
						} else {
							# Normal mode: just load the configuration file as it is
							my $confFile = get_abs_path($command_tag);
							if (-e $confFile) {
								$error = reload_conf ($vm_name, $confFile, $dynamips_host, $dynamips_port, $consFile);
	   	 						# Copy the file loaded config to vm directory
	   	 						$execution->execute( $logp, "cat " . $confFile . ">" . $newRouterConfFile);
							} else {
								return "ERROR: configuration file $confFile not found\n" 
							}
						}
					}
				} elsif ( $type eq "file" ) {
					
					# Case 2. File type
					# <exec> tag specifies a file containing a list of commands
					if ( ($ostype eq 'show') || ($ostype eq 'set') ) {

						# We open the file and read and execute commands line by line
						my $include_file =  do_path_expansion( text_tag($command) );
								
						# Get the user name and password. If several users are define, 
						# we just take the first one.
						my @login_users = merge_login($extConfFile, $vm_name);
		     			my $login_user = $login_users[0];
		 				my $user=$login_user->[0];
						my $pass=$login_user->[1];
						# Get enable password
						my $enablepass = merge_enablepass($extConfFile, $vm_name);
						# create CiscoConsMgmt object to connect to router console
						my $sess = new VNX::CiscoConsMgmt ($dh->get_tmp_dir, 'localhost', $port, $user, $pass, $enablepass);
						# Connect to console
						my $res = $sess->open;
						if (!$res) { return "ERROR: cannot connect to ${vm_name}'s console at port $port.\n" .
							                "       Please, release the router console and try again.\n"; }
						# Put router in priviledged mode
                        if ($exemode == $EXE_VERBOSE) {
                            $res = $sess->goto_state ('enable', 'debug') ;
                        } else {
                            $res = $sess->goto_state ('enable') ;
                        }
                        if ($res eq 'timeout') {
                            return "ERROR: timeout connecting to ${vm_name}'s console at port $port.\n" .
                                   "       Please, release the router console and try again.\n"; 
                        } elsif ($res eq 'user_login_needed') { 
                            return "ERROR: invalid login connecting to ${vm_name}'s console at port $port\n" 
                        } elsif ($res eq 'invalid_login') {
                            return "ERROR: invalid login connecting to ${vm_name}'s console at port $port\n" 
                        } elsif ($res eq 'bad_enable_passwd') {
                            return "ERROR: invalid enable password connecting to ${vm_name}'s console at port $port\n" 
                        }
						if ($ostype eq 'set') {	my @output = $sess->exe_cmd ('configure terminal'); }
						# execute the file with commands 
						@output = $sess->exe_cmd_file ("$include_file");
						wlog (N, "-- cmd result: \n\n@output");
						if ($ostype eq 'set') {	my @output = $sess->exe_cmd ('end'); }
						$sess->exe_cmd ("disable");
						$sess->exe_cmd ("exit");
						$sess->close;
					} elsif ($ostype eq 'load')  { # should never occur when checnked in CheckSemantics
							return "ERROR: ostype='load' not allowed with <exec> tags of mode='file'\n" 
					}
					
				}
				# Other cases impossible. Only 'verbatim' or 'file' allowed by vnx XSD definition

			}
		}
	}	

	return $error

}

#
# Internal subs
#
sub reload_conf {

	my $vm_name    = shift;
	my $confFile = shift;
	my $dynamips_host = shift;
	my $dynamips_port = shift;
	my $consFile = shift;

    my $t;
    my $error;
    my $ret_code;
    my $ret_str;
    my $res;
    my @lines;

    my $logp = "dynamips-reload_conf> ";
	
	$confFile = get_abs_path ($confFile);
	unless (-e $confFile) {	return "router $vm_name configuration file not found ($confFile)" } 
    if ( $error = t_connect(\$t) ) { return $error }
    $res = dyn_cmd($t, "vm stop $vm_name", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
	#t_print ($t, "vm stop $vm_name", $logp);
    #my $line = t_getline ($t, $logp);
    $res = dyn_cmd($t, "vm set_config $vm_name \"$confFile\" ", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
   	#t_print ($t, "vm set_config $vm_name \"$confFile\" ", $logp);
   	#$line = t_getline ($t, $logp);
    $res = dyn_cmd($t, "vm start $vm_name", \@lines, \$ret_code, \$ret_str );
    return $res if ($res);
   	#t_print ($t, "vm start $vm_name", $logp);
    #$line = t_getline ($t, $logp);
    sleep (3);    
	VNX::vmAPICommon->start_consoles_from_console_file ($vm_name);
	return $error;
}


#
# merge_login
#
# Returns login values defined in configuration file for a virtual machine
#
sub merge_login {

	my $extConfFile = shift;
	my $vm_name    = shift;

	my @users;
	
	# If the extended config file is not defined, return default value 
	if ($extConfFile eq '0'){
		push(@users,["",""]);
		return @users;

	} else {
		
		# Parse config file
	    my $parser       = XML::LibXML->new();
	    my $dom          = $parser->parse_file($extConfFile);
	    my $found;

		# Look for login tags in vm section of config file
		my @login_list = $dom->findnodes("/vnx_dynamips/vm[\@name='$vm_name']/login");
		if (@login_list){
		    foreach my $login (@login_list) {
		        my $user = $login->getAttribute("user");     if (!defined($user)) { $user = '' };
		        my $pass = $login->getAttribute("password"); if (!defined($pass)) { $pass = '' };
                push(@users,[$user,$pass]);
		        $found = 1;
		    }
		}
		
		# If no specific login values found for the vm, look for global login values 
		if (!$found) {
		    my @login_list = $dom->findnodes("/vnx_dynamips/global/login");
		    if (@login_list) {
		        foreach my $login (@login_list) {
		            my $user = $login->getAttribute("user");     if (!defined($user)) { $user = '' };
		            my $pass = $login->getAttribute("password"); if (!defined($pass)) { $pass = '' };
                    push(@users,[$user,$pass]);
		            $found = 1;
		        }
		    }
		}
	
	    # If neither specific nor global login values found, return empty strings
	    if (!$found) {
	        push(@users,["",""]);
	    }
	    return @users;
    }  	
}

#
# merge_enablepass
#
# returns router priviledged mode (enable) password defined in config file (or an empty string if not defined)
#
sub merge_enablepass {

	my $extConfFile = shift;
	my $vm_name = shift;

	my $result = "";

    if ($extConfFile ne '0'){

        # Parse extended config file
        my $parser       = XML::LibXML->new();
        my $dom          = $parser->parse_file($extConfFile);
        my $found;

        # Look for enable tags in vm section of config file
        my @enable_list = $dom->findnodes("/vnx_dynamips/vm[\@name='$vm_name']/enable");
        if (@enable_list){
            $result = $enable_list[0]->getAttribute("password");
            $found = 1;
        }
        
        # If no specific enable values found for the vm, look for values in global section 
        if (!$found) {
            my @enable_list = $dom->findnodes("/vnx_dynamips/global/enable");
            if (@enable_list) {
                    $result = $enable_list[0]->getAttribute("password");
                    $found = 1;
            }
        }

        return $result;
    } 

}

#
# Get the value of a simple tag in extended configuration file
# 
# Returns the value of the parameter or the default value if not found 
# 
sub merge_simpleconf {

	my $extConfFile = shift;
	my $vm_name      = shift;
	my $tagName     = shift;
	
	my $global_tag = 1;
	my $result;
	
	# Set default value
#  Changed to make the code compatible with perl 5.8. (given not supported) 
#	given ($tagName) {
#	    when ('sparsemem') { $result = 'true'; }
#	    when ('ghostios')  { $result = 'false'; }
#	    when ('npe')       { $result = '200'; }
#	    when ('chassis')   { $result = '3640'; }
#	}

	if     ($tagName eq 'sparsemem') { $result = 'true'; }
	elsif  ($tagName eq 'ghostios')  { $result = 'false'; }
	elsif  ($tagName eq 'npe')       { $result = '200'; }
	elsif  ($tagName eq 'chassis')   { $result = '3640'; }

    if ($extConfFile ne '0'){

        # Parse extended config file
        my $parser       = XML::LibXML->new();
        my $dom          = $parser->parse_file($extConfFile);
        my $found;

        # Look for tags in vm section of config file
        my @tag_list = $dom->findnodes("/vnx_dynamips/vm[\@name='$vm_name']/$tagName");
        if (@tag_list){
            $result = text_tag($tag_list[0]);
            $found = 1;
        }
        
        # If no specific enable values found for the vm, look for values in global section 
        if (!$found) {
            my @tag_list = $dom->findnodes("/vnx_dynamips/global/$tagName");
            if (@tag_list) {
                $result = text_tag($tag_list[0]);
                $found = 1;
            }
        }

        return $result;
    } 

}


#
# get_router_conf_file:
#																
#   Gets the router configuration file from the dynamips extended 
#   configuration file (if exists)
# 
# Arguments:						
# 	vmName: name of virtual router
# 
# Returns:									
# 	absolute path of the router config file or empty string if not defined
#
sub get_router_conf_file {

	my $extConfFile = shift;
	my $vm_name    = shift;

    my $logp = "dynamips-get_router_conf_file> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, extConfFile=$extConfFile ...)", "$logp");

	my $result = "0";
	
	if ($extConfFile ne '0'){
	    my $parser       = XML::LibXML->new();
	    my $dom          = $parser->parse_file($extConfFile);
	    my @conf = $dom->findnodes("/vnx_dynamips/vm[\@name='$vm_name']/conf");  
	    if(@conf == 1){
	        $result = get_abs_path ( text_tag($conf[0]) );
	    }
    }

    wlog (VVV, "returns $result\n", "get_router_conf_file");
 	return $result;
}


#################################################################
# get_card_conf													#
# 																#
# Saca del fichero de configuración extendida, las tarjetas que #
# se tienen que conectar al router								#
# Entrada:														#
# 	Nombre del router virtual									#
# Salida:														#
# 	Array de los nombres de las tarjetas que tienen que ser 	#
#	agregadas al router, en caso de que no haya o etiqueta o 	#
#	no exista el fichero, por defecto se inserta una placa		#
# 	NM-4E														# 
#################################################################

sub get_cards_conf {
	
	my $extConfFile = shift;
	my $vm_name      = shift;

	my @slotarray;
	
	# If the extended config file is not defined, return default value 
	if ($extConfFile eq '0'){
		push(@slotarray,"NM-4E");
		return @slotarray;
	}
	
	# Parseamos el fichero.
    my $parser       = XML::LibXML->new();
    my $dom          = $parser->parse_file($extConfFile);
 	my $default_tag = 1;
 	my $global_tag = 1;

    foreach my $slot ($dom->findnodes("/vnx_dynamips/vm[\@name='$vm_name']/hw/slot")) {
        push(@slotarray,text_tag($slot));
        $global_tag = 0;
    }

	# Si no hay tarjetas definidas en la seccion del router virtual.
	# se utilizan el que está definido en la parte global.
    if ($global_tag eq 1){
        foreach my $slot ($dom->findnodes("/vnx_dynamips/global/hw/slot")) {
            push(@slotarray,text_tag($slot));
            # Como ya tenemos tarjetas definidas, no utilizamos la configurada por defecto.
            $default_tag = 0;
        }
    }
	
	# Si no tenemos definidas ninguna tarjeta en la definicion del router virtual o el la seccion global
	# utilizamos el valor por defecto "NM-4E"
	
	# Diferente al ser un array y no poder asignarle un valor por defecto al principio
	if (($global_tag eq 1 )&&($default_tag eq 1)){
		push(@slotarray,"NM-4E");
	}
 	return @slotarray;
}

#
# Auxiliar functions to make the code related to telnet connection with dynamips hypervisor readable.
#

#
# t_connect
#
# Creates a new telnet object and connects to hypervisor. Returns error string
#  
sub t_connect {

    my $t_ref = shift;

    $$t_ref = new Net::Telnet (Timeout => 10, Errmode => 'return');
    $$t_ref->open(Host => $dynamips_host, Port => $dynamips_port);
    return $$t_ref->errmsg;
    
}

#
# dyn_cmd
#
sub dyn_cmd {

    my $t = shift;
    my $cmd = shift;
    my $ref_lines = shift;
    my $ref_ret_code = shift;
    my $ref_ret_str = shift;
    my $line;

    my $logp = "dyn_cmd> ";
    wlog (VVV, "Sending command '$cmd' to dynamips hypervisor", $logp);

    $t->print($cmd);
    
    $line = $t->getline;
    while ( $line !~ /^\d\d\d\-/ ) {
        chomp($line);
        wlog (VVV, $line, $logp);
        push (@{$ref_lines}, $line);
        $line = $t->getline;
    }
    chomp($line);
    $$ref_ret_code = $line; $$ref_ret_code =~ s/(\d\d\d).*/$1/;
    $$ref_ret_str = $line; $ref_ret_str =~ s/\d\d\d\-//;
   
    #if ( $line !~ /^100-/ ) {
    if ( $$ref_ret_code ne 100 ) {
        wlog (ERR, "Dynamips hypervisor returns '$line'");
        return $$ref_ret_str;    
    } else {
        wlog (VVV, "Dynamips hypervisor returns '$line'");    
        return;
    }
}

=BEGIN
#
# t_print
#
# Auxiliar function to make the code readable. Calls wlog to write log message and 
# $t->print to send the command through telnet to the router 
#
sub t_print {

 my $t = shift;
 my $cmd = shift;
 my $logp = shift;

 wlog (VVV, $cmd, $logp);
 $t->print($cmd); 
	
}

#
# t_getline
#
# Auxiliar function to make the code readable. Calls $t->getline to read the response 
# from telnet. It reads until a "XXX-string" message is received (e.g, '100-OK' or 
# '206-unable to create VM instance 'cisco''). Returns the lines read and prints an
# error message if the result code is not 100
#
sub t_getline {

    my $t = shift;
    my $logp = shift;

    my @lines;
    my $line = $t->getline;
    while ( $line !~ /^\d\d\d\-/ ) {
    	chomp ($line);
        wlog (VVV, $line, $logp);
        push (@lines, $line);
   	    $line = $t->getline;
    }
    push (@lines, $line);
    if ( $line !~ /^100-/ ) {
        wlog (ERR, "Dynamips hypervisor returns '$line'")    
    }
    
    return @lines;
}
=END
=cut

1;
