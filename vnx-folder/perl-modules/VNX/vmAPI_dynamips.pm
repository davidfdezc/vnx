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

  
#use feature qw(switch);
use XML::LibXML;
use XML::DOM;
#use XML::DOM::ValParser;
use VNX::Globals;
use VNX::Execution;
use VNX::BinariesData;
use VNX::Arguments;
use VNX::CheckSemantics;
use VNX::TextManipulation;
use VNX::NetChecks;
use VNX::FileChecks;
use VNX::DocumentChecks;
use VNX::IPChecks;
use VNX::CiscoExeCmd;
use VNX::vmAPICommon;
use Net::Telnet;
use NetAddr::IP;
#use Net::IP;
use File::Basename;
use File::Spec;


my $dynamipsHost;
my $dynamipsPort;


#
# Module vmAPI_uml initialization code
#
sub init {      
	$dynamipsHost = "localhost";
	#my $dynamipsPort=get_dynamips_port_conf();
	$dynamipsPort = &get_conf_value ($vnxConfigFile, 'dynamips', 'port');
	if (!defined $dynamipsPort) { $dynamipsPort = $DYNAMIPS_DEFAULT_PORT };
	#print "*** dynamipsPort = $dynamipsPort \n";
}    



####################################################################
##                                                                 #
##   defineVM                                                      #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub defineVM {
	
	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;
	my $vm_doc    = shift;

    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");
	
    my $extConfFile;
	my $newRouterConfFile;
	my $ifTagList;

	# Get the extended configuration file if it exists
	$extConfFile = $dh->get_default_dynamips();
	#print "*** dynamipsconf=$extConfFile\n";
	if ($extConfFile ne "0"){
		$extConfFile = &get_abs_path ($extConfFile);
		#$extConfFile = &validate_xml ($extConfFile); # Moved to vnx.pl	
	}
	
	my @vm_ordered = $dh->get_vm_ordered;

	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parse($vm_doc);
	my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
	my $virtualm     = $virtualmList->item(0);
	
	my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
	my $filesystemTag     = $filesystemTagList->item(0);
	my $filesystem_type   = $filesystemTag->getAttribute("type");
	my $filesystem        = $filesystemTag->getFirstChild->getData;
	
	# Get the configuration file name of the router (if defined) 
	# form the extended config file
	my $routerConfFile = get_router_conf_file($extConfFile, $vm_name);
	#print "**** conf_dynamips=$routerConfFile\n";

	# $newRouterConfFile is the file where we will store the configuration of the new router	
	$newRouterConfFile = $dh->get_vm_dir($vm_name) . "/" . $vm_name . ".conf";
	
	if ($routerConfFile ne 0) {
		# A router config file has been defined, we check if exists 
	 	if (-e $routerConfFile)	{
			# Router config file exists: we copy the content of the conf file 
			# provided to the new file, but deleting the "end" command 
			# (if exists) to allow adding new configuration commands at the end
	   	 	$execution->execute("sed '/^end/d' " . $routerConfFile . ">" . $newRouterConfFile);
		}else{
			# ERROR: The router config file has been defined, but it does not exists 
			$execution->smartdie("ERROR: cannot open " . $routerConfFile );
		}
	} else {
		# No configuration file defined for the router 
	}
	
	my @routerConf = &create_router_conf ($vm_name, $extConfFile);
	open (CONF, ">> $newRouterConfFile") or $execution->smartdie("ERROR: Cannot open $newRouterConfFile");
	print CONF @routerConf;
	close (CONF);
 	
    # Preparar las variables
    my $memTagList = $virtualm->getElementsByTagName("mem");
    my $mem = "96";

	if ( $memTagList->getLength != 0 ) {
		my $memTag     = $memTagList->item(0);
		$mem   = ($memTag->getFirstChild->getData)/1024;
	} 
	
    # Definicion del router
	my $line;
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    # Si es la primera vez que se ejecuta el escenario, se borra todo el hypervisor
    # Precacion, tambien se borra otros escenarios que este corriendo paralelamente
    # DFC Comentado 30/3/2011. Con los cambios en los interfaces de gestion ahora $counter llega
    # siempre a 0 y se resetea dynamips cada vez que se crea un router 
    #if ($counter == 0)
    #{
    #	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    #	print "Reset hypervisor:\n" if ($exemode == $EXE_VERBOSE);;
    #	$t->print("hypervisor reset");
   	#	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    #	$t->close;
    #	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    #}
    
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    print("hypervisor version\n") if ($exemode == $EXE_VERBOSE);
    $t->print("hypervisor version");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    print("hypervisor working_dir \"". $dh->get_vm_fs_dir($vm_name)."\" \n") if ($exemode == $EXE_VERBOSE);
    $t->print("hypervisor working_dir \"". $dh->get_vm_fs_dir($vm_name). "\" ");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
	
	
	# Set type
	my($trash,$model)=split(/-/,$type,2);
    print("vm create $vm_name 0 c$model\n");
	$t->print("vm create $vm_name 0 c$model");
	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
	
  	#
	# VM CONSOLES
	# 
	# Go through <consoles> tag list to see if specific ports have been
	# defined for the consoles and the value of display attribute if specified
	# In Dynamips, only con1 (console port, for all routers) and 
	# con2 (aux port, only for c7200) are allowed
	# 
	my $consTagList = $virtualm->getElementsByTagName("console");
	my $numcons     = $consTagList->getLength;
    my $consType;
    my %consPortDefInXML = (1,'',2,'');     # % means that consPortDefInXML is a perl associative array 
    my %consDisplayDefInXML = (1,$CONS_DISPLAY_DEFAULT,2,$CONS_DISPLAY_DEFAULT); 
    #print "** $vm_name: console ports, con1='$consPortDefInXML{1}', con2='$consPortDefInXML{2}'\n" if ($exemode == $EXE_VERBOSE);
	for ( my $j = 0 ; $j < $numcons ; $j++ ) {
		my $consTag = $consTagList->item($j);
   		my $value = &text_tag($consTag);
		my $id    = $consTag->getAttribute("id");        # mandatory
		my $display = $consTag->getAttribute("display"); # optional
		my $port = $consTag->getAttribute("port");       # optional
   		#print "** console: id=$id, display=$display port=$port value=$value\n" if ($exemode == $EXE_VERBOSE);
		if ( ($id eq "1") || ($id eq "2") ) {
			if ( $value ne "" && $value ne "telnet" ) { 
				print "WARNING (vm=$vm_name): only 'telnet' value is allowed for Dynamips consoles. Value ignored.\n"
			}
			$consPortDefInXML{$id} = $port;
			if ($display ne '') { $consDisplayDefInXML{$id} = $display }
		}
		if ( ( $id eq "0" ) || ($id > 1) ) {
			print "WARNING (vm=$vm_name): only consoles with id='1' or '2' allowed for Dynamips virtual machines. Tag with id=$id ignored.\n"
		} 
	}
	#print "** $vm_name: console ports, con1='$consPortDefInXML{1}', con2='$consPortDefInXML{2}'\n" if ($exemode == $EXE_VERBOSE);

    # Define ports for main console (all) and aux console (only for 7200)
	my @consolePort = qw();
    foreach my $j (1, 2) {
		if ($consPortDefInXML{$j} eq "") { # telnet port not defined we choose a free one starting from $CONS_PORT
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
		print "WARNING (vm=$vm_name): cannot use port $consPortDefInXML{1} for console #1; using $consolePort[$j] instead\n"
	   		if ( ($consPortDefInXML{$j} ne "") && ($consolePort[$j] ne $consPortDefInXML{$j}) );
    }
	
	#my $consoleport = &get_port_conf($vm_name,$counter);
	my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
	
	open (PORT_CISCO, ">$consFile") || $execution->smartdie("ERROR (vm=$vm_name): cannot open $consFile");
	print PORT_CISCO "con1=$consDisplayDefInXML{1},telnet,$consolePort[1]\n";
	print("vm set_con_tcp_port $vm_name $consolePort[1]\n");
	$t->print("vm set_con_tcp_port $vm_name $consolePort[1]");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    if ($type eq 'dynamips-7200') {
    	# Configure aux port
		print PORT_CISCO "con2=$consDisplayDefInXML{2},telnet,$consolePort[2]\n";
		print("vm set_con_tcp_port $vm_name $consolePort[2]\n");
		$t->print("vm set_con_tcp_port $vm_name $consolePort[2]");
	    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    }
	close (PORT_CISCO);
    
    # Set Chassis
    my $chassis = &get_simple_conf($extConfFile, $vm_name, 'chassis');
    $chassis =~ s/c//;
    print("c$model set_chassis $vm_name $chassis\n");
    $t->print("c$model set_chassis $vm_name $chassis");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);

    # Set NPE if 7200
    if ($model eq '7200') {
	    my $npe = &get_simple_conf($extConfFile, $vm_name, 'npe');
	    print("c$model set_npe $vm_name npe-$npe\n");
	    $t->print("c$model set_npe $vm_name npe-$npe");
	    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);   	
    } 
    
	# Set Filesystem
    print("vm set_ios $vm_name $filesystem\n");
    $t->print("vm set_ios $vm_name $filesystem");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    
    # Set Mem
    print("vm set_ram $vm_name $mem\n");
    $t->print("vm set_ram $vm_name $mem");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    if (&get_simple_conf($extConfFile, $vm_name, 'sparsemem') eq "true"){
		print("vm set_sparse_mem $vm_name 1\n");
		$t->print("vm set_sparse_mem $vm_name 1");
   		$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    }
    
    # Set IDLEPC
    #my $idlepc = get_idle_pc_conf($vm_name);
    my $imgName = basename ($filesystem);
    # Look for a specific idle_pc value for this image
    my $idlepc = &get_conf_value ($vnxConfigFile, 'dynamips', "idle_pc-$imgName");
    if (!defined $idlepc) { 
    	# Look for a generic idle_pc value 
    	$idlepc = &get_conf_value ($vnxConfigFile, 'dynamips', 'idle_pc');   
	    if (!defined $idlepc) { 
    		# Use default value in VNX::Globals
    		$idlepc = $DYNAMIPS_DEFAULT_IDLE_PC;
	    } 
    }
    #print "*** idlepc = $idlepc \n";
    
	print("vm set_idle_pc $vm_name $idlepc\n");
	$t->print("vm set_idle_pc $vm_name $idlepc");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    
    #Set ios ghost
    if (&get_simple_conf($extConfFile, $vm_name, 'ghostios') eq "true"){
    	print("vm set_ghost_status $vm_name 2\n");
		$t->print("vm set_ghost_status $vm_name 2");
    	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    	my $temp = basename($filesystem);
    	print("vm set_ghost_file $vm_name \"$temp.image-localhost.ghost\" \n");
		$t->print("vm set_ghost_file $vm_name \"$temp.image-localhost.ghost\" ");
    	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    }
    
    #Set Blk_direct_jump
	print("vm set_blk_direct_jump $vm_name 0\n");
	$t->print("vm set_blk_direct_jump $vm_name 0");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    
    # Add slot cards
    my @cards=&get_cards_conf($extConfFile, $vm_name);
    my $index = 0;
    foreach my $slot (@cards){
    	print("vm slot_add_binding $vm_name $index 0 $slot \n");
		$t->print("vm slot_add_binding $vm_name $index 0 $slot");
    	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    	$index++;
    }
    
    # Connect virtual networks to host interfaces
    $ifTagList = $virtualm->getElementsByTagName("if");
	for ( my $j = 0 ; $j < $ifTagList->getLength; $j++ ) {
		my $ifTag = $ifTagList->item($j);
		my $name  = $ifTag->getAttribute("name");
		my $id    = $ifTag->getAttribute("id");
		my $net   = $ifTag->getAttribute("net");
		my ($slot, $dev)= split("/",$name,2);
		$slot = substr $slot,-1,1;
		if ( $name =~ /^[gfeGFE]/ ) {
			#print "**** Ethernet interface: $name, slot=$slot, dev=$dev\n";
			print("nio create_tap nio_tap_$vm_name$slot$dev $vm_name-e$id\n");
			$t->print("nio create_tap nio_tap_$vm_name$slot$dev $vm_name-e$id");
	   		$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
	   		print("vm slot_add_nio_binding $vm_name $slot $dev nio_tap_$vm_name$slot$dev\n");
	   		$t->print("vm slot_add_nio_binding $vm_name $slot $dev nio_tap_$vm_name$slot$dev");
	   		$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
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
				if (scalar @$vmsInNet != 2) { $execution->smartdie ("ERROR: point-to-point network $net has " . scalar @vms . " virtual machines connected (must be 2)"); }
				#@vms = @$vmsInNet;
				$vms[0] = @$vmsInNet[0]->getAttribute ("name");
				$vms[1] = @$vmsInNet[1]->getAttribute ("name");
				# and we write it to the file
				open (PORTS_FILE, "> $portsFile") || $execution->smartdie ("ERROR: Cannot open file $portsFile for writting $net serial line ports");
				for ( my $i = 0 ; $i <= 1 ; $i++ ) {
					#print "**** $vms[$i]=$ports[$i]\n";
					print PORTS_FILE "$vms[$i]=$ports[$i]\n";
				}
				close (PORTS_FILE); 				
			} else {
				#print "*** $portsFile already exists, reading it...\n";
				# The file already exists; we read it and load the values
				open (PORTS_FILE, "< $portsFile") || $execution->smartdie("Could not open $portsFile file.");
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
				print("nio create_udp nio_udp_$vm_name$slot$dev $ports[0] 127.0.0.1 $ports[1]\n");
				$t->print("nio create_udp nio_udp_$vm_name$slot$dev $ports[0] 127.0.0.1 $ports[1]");
			} else {
				print("nio create_udp nio_udp_$vm_name$slot$dev $ports[1] 127.0.0.1 $ports[0]\n");
				$t->print("nio create_udp nio_udp_$vm_name$slot$dev $ports[1] 127.0.0.1 $ports[0]");
			}
	   		$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
	   		print("vm slot_add_nio_binding $vm_name $slot $dev nio_udp_$vm_name$slot$dev\n");
	   		$t->print("vm slot_add_nio_binding $vm_name $slot $dev nio_udp_$vm_name$slot$dev");
	   		$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
		}
   		$execution->execute("ifconfig $vm_name-e$id 0.0.0.0");
	}
	
	# Set config file to router
	print("vm set_config $vm_name \"$newRouterConfFile\" \n");
   	$t->print("vm set_config $vm_name \"$newRouterConfFile\" ");
   	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
   	$t->close;

    print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    
    
}

sub create_router_conf {

	my $vm_name      = shift;
	my $extConfFile = shift;

	my @routerConf;

	# Load and parse libvirt XML definition of virtual machine
	my $vmXMLFile = $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_cconf.xml';
	open XMLFILE, "$vmXMLFile" or $execution->smartdie("can not open $vmXMLFile file");
	my $doc = do { local $/; <XMLFILE> };
	close XMLFILE;

	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parse($doc);
	my $vm = $dom->getElementsByTagName("vm")->item(0);

    	# Hostname
	push (@routerConf,  "hostname " . $vm_name ."\n");

	# Enable IPv4 and IPv6 routing
	push (@routerConf,  "ip routing\n");	
	push (@routerConf,  "ipv6 unicast-routing\n");	

	# Network interface configuration
	my $ifTagList = $vm->getElementsByTagName("if");
	# P.ej:
	# 	interface e0/0
	# 	 mac-address fefd.0003.0101
	# 	 ip address 10.1.1.4 255.255.255.0
	# 	 ip address 11.1.1.4 255.255.255.0 secondary
	# 	 ipv6 enable
	# 	 ipv6 address 2001:db8::1/64
	# 	 ipv6 address 2001:db9::1/64
	# 	 no shutdown
 	for ( my $j = 0 ; $j < $ifTagList->getLength ; $j++ ) {
 		my $ifTag = $ifTagList->item($j);
		my $id    = $ifTag->getAttribute("id");
		my $net   = $ifTag->getAttribute("net");
		my $mac   = $ifTag->getAttribute("mac");
		$mac =~ s/,//;
		my @maclist = split(/:/,$mac);
		$mac = $maclist[0] . $maclist[1] . "." . $maclist[2] . $maclist[3] . "." . $maclist[4] . $maclist[5];
		my $nameif   = $ifTag->getAttribute("name");
		push (@routerConf,  "interface " . $nameif . "\n");	
		push (@routerConf,  " mac-address " . $mac . "\n");
		# Configure IPv4 addresses		
		my $ipv4_list = $ifTag->getElementsByTagName("ipv4");
		if ($ipv4_list->getLength == 0) {
			push (@routerConf,  " no ip address\n");	
		} else {
	 		for ( my $i = 0 ; $i < $ipv4_list->getLength ; $i++ ) {
				my $ipv4_Tag = $ipv4_list->item($i);
				my $ipv4 =  $ipv4_Tag->getFirstChild->getData;
				my $subnetv4 = $ipv4_Tag->getAttribute("mask");
				if ($i == 0) {
					push (@routerConf,  " ip address " . $ipv4 . " ". $subnetv4 . "\n");	
				} else {
					push (@routerConf,  " ip address " . $ipv4 . " ". $subnetv4 . " secondary\n");					
				}
	 		}
 		}
		# Configure IPv6 addresses		
		my $ipv6_list = $ifTag->getElementsByTagName("ipv6");
		if ( $ipv6_list->getLength != 0 ) {
			push (@routerConf,  " ipv6 enable\n");	
	 		for ( my $i = 0 ; $i < $ipv6_list->getLength ; $i++ ) {
				my $ipv6_Tag = $ipv6_list->item($i);
				my $ipv6 =  $ipv6_Tag->getFirstChild->getData;
				push (@routerConf,  " ipv6 address " . $ipv6 . "\n");	
	 		}
 		}
		# Levantamos la interfaz
		push (@routerConf,  " no shutdown\n");		
 	}
 	# IP route configuration
 	my $routeTagList = $vm->getElementsByTagName("route");
 	for ( my $j = 0 ; $j < $routeTagList->getLength ; $j++ ) {
 		my $routeTag = 	$routeTagList->item($j);
 		my $gw = $routeTag->getAttribute("gw");
 		my $destination = $routeTag->getFirstChild->getData;
 		my $maskdestination = "";
 		if ($destination eq "default"){
 			$destination = "0.0.0.0";
 			$maskdestination = "0.0.0.0";
 		}else {
 			print "****** $destination\n";
 			my $ip = new NetAddr::IP ($destination) or $execution->smartdie (NetAddr::IP::Error());
 			$maskdestination = $ip->mask();
 			$destination = $ip->addr();
 		}
 		push (@routerConf,  "ip route ". $destination . " " . $maskdestination . " " . $gw . "\n");	
 		
 	}
 	# Si en el fichero de configuracion extendida se define un usuario y password.
 	my @login_users = &get_login_user($extConfFile, $vm_name);
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
 	my $enablepass = get_enable_pass($extConfFile, $vm_name);
 	if (!($enablepass eq "")){
		push (@routerConf,  " enable password " . $enablepass . "\n");
    }
    # Se habilita el ip http server ya que si no se hace, el acceso por telnet se bloquea.
 	# push (@routerConf,  "ip http server\n";
 	push (@routerConf,  " end\n");

	return @routerConf;
}


#
#
####################################################################
##                                                                 #
##   undefineVM                                                    #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub undefineVM{

	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vm_name\n" if ($exemode == $EXE_VERBOSE);
    
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm destroy $vm_name");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    #$t->print("hypervisor reset");
   	#$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->close;
}

#
####################################################################
##                                                                 #
##   destroyVM                                                     #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub destroyVM{

	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");

	my $line;

    print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Destroying: $vm_name\n" if ($exemode == $EXE_VERBOSE);

    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);

   	$t->print("vm stop $vm_name");
   	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
   	$t->print("vm delete $vm_name");
   	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);

	# We have to destroy the tap or udp devices created for the router
	# using the "nio create_tap" or "nio create_udp" commands 

	# Load and parse libvirt XML definition of virtual machine
	my $vmXMLFile = $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_cconf.xml';
	if (-e $vmXMLFile) {
		open XMLFILE, "$vmXMLFile" or $execution->smartdie("can not open $vmXMLFile file");
		my $doc = do { local $/; <XMLFILE> };
		close XMLFILE;
		my $parser       = new XML::DOM::Parser;
		my $dom          = $parser->parse($doc);
		my $vm = $dom->getElementsByTagName("vm")->item(0);
	
		my $ifTagList = $vm->getElementsByTagName("if");
	 	for ( my $j = 0 ; $j < $ifTagList->getLength ; $j++ ) {
	 		my $ifTag  = $ifTagList->item($j);
			my $ifName = $ifTag->getAttribute("name");
			my ($slot, $dev)= split("/",$ifName,2);
			$slot = substr $slot,-1,1;
			print "**** Ethernet interface: $ifName, slot=$slot, dev=$dev\n";
			if ( $ifName =~ /^[gfeGFE]/ ) {
				print("nio delete nio_tap_$vm_name$slot$dev\n");
				$t->print("nio delete nio_tap_$vm_name$slot$dev");
		   		my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
			}
			elsif ( $ifName =~ /^[sS]/ ) {
				print("nio delete nio_udp_$vm_name$slot$dev\n");
				$t->print("nio delete nio_udp_$vm_name$slot$dev");
		   		$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
			}
		}
	}
    
   	#$t->print("hypervisor reset");
   	#$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
   	$t->close;

}

#
#
####################################################################
##                                                                 #
##   startVM                                                       #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub startVM {

	my $self    = shift;
	my $vm_name  = shift;
	my $type    = shift;
	my $no_consoles = shift;
	
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");

    print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Starting router: $vm_name\n" if ($exemode == $EXE_VERBOSE);
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm start $vm_name");
    my $line = $t->getline; 
    print $line if ($exemode == $EXE_VERBOSE);

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

}


#
#
####################################################################
##                                                                 #
##   shutdownVM                                                    #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub shutdownVM{
	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;
	my $F_flag    = shift;
	
	my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");
	
	# This is an ordered shutdown. We first save the configuration:

	# To be implemented

    # Then we shutdown and destroy the virtual router:
    &destroyVM ($self, $vm_name, $type);
    		
=BEGIN    		
	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vm_name\n" if ($exemode == $EXE_VERBOSE);
	    
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm stop $vm_name");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->close;
	sleep(2);	
=END
=cut
	
	#&change_vm_status( $dh, $vm_name, "REMOVE" );
	&change_vm_status( $vm_name, "REMOVE" );

}

#
#
####################################################################
##                                                                 #
##   saveVM                                                        #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub saveVM{
	
	my $self     = shift;
	my $vm_name   = shift;
	my $type     = shift;
	my $filename = shift;
	
	my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");
		
	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vm_name\n" if ($exemode == $EXE_VERBOSE);
    
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm extract_config $vm_name");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->close;
	
}

#
####################################################################
##                                                                 #
##   restoreVM                                                     #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub restoreVM{
	
	my $self     = shift;
	my $vm_name   = shift;
	my $type     = shift;
	my $filename = shift;
	
	my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Rebooting router: $vm_name\n" if ($exemode == $EXE_VERBOSE);

    sleep(2);
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm stop $vm_name");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    sleep(2);
    $t->print("vm start $vm_name");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->close;
	
}

#
#
####################################################################
##                                                                 #
##   suspendVM                                                     #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub suspendVM{

	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vm_name\n" if ($exemode == $EXE_VERBOSE);
	
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm suspend $vm_name");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->close;
	
}

#
####################################################################
##                                                                 #
##   resumeVM                                                      #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub resumeVM{

	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vm_name\n" if ($exemode == $EXE_VERBOSE);
    
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm resume $vm_name");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->close;
	
}

####################################################################
##                                                                 #
##   rebootVM                                                      #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub rebootVM{
	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vm_name\n" if ($exemode == $EXE_VERBOSE);
	
    sleep(2);
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm stop $vm_name");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    sleep(2);
    $t->print("vm start $vm_name");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->close;
}

####################################################################
##                                                                 #
##   resetVM                                                       #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub resetVM{
	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)");

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vm_name\n" if ($exemode == $EXE_VERBOSE);
	
    sleep(2);
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm stop $vm_name");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    sleep(2);
    $t->print("vm start $vm_name");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->close;
	
}

####################################################################
##                                                                 #
##   executeCMD                                                    #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub executeCMD{

	my $self        = shift;
	my $merged_type = shift;
	my $seq         = shift;
	my $vm          = shift;
	my $vm_name      = shift;

    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$merged_type ...)");

	my @output = "Nothing to show";
	my $temp;
	my $port;
	my $extConfFile; 
	
	# Recupero el puerto telnet de acceso al router
	my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
	# Configuro el fichero de configuracion extendida
	$extConfFile = $dh->get_default_dynamips();
	if ($extConfFile ne "0"){
		$extConfFile = &get_abs_path ($extConfFile);
		#$extConfFile = &validate_xml ($extConfFile);	# Moved to vnx.pl
	}
	# Get the console port from vm's console file
	open (PORT_CISCO, "< $consFile") || $execution->smartdie ("ERROR: cannot open $vm_name console file ($consFile)");
	my $conData;
	if ($merged_type eq 'dynamips-7200') { # we use con2 (aux port)
		$conData = &get_conf_value ($consFile, '', 'con2');
	} else { # we use con1 (console port)
		$conData = &get_conf_value ($consFile, '', 'con1');			
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
	my $command_list = $vm->getElementsByTagName("exec");
	my $countcommand = 0;
	for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
		my $command = $command_list->item($j);	
		my $cmd_seq_string = $command->getAttribute("seq");
		# JSF 02/12/10: we accept several commands in the same seq tag,
		# separated by commas
		my @cmd_seqs = split(',',$cmd_seq_string);
		foreach my $cmd_seq (@cmd_seqs) {
		
		    # Remove leading or trailing spaces
            $cmd_seq =~ s/^\s+//;
            $cmd_seq =~ s/\s+$//;
		
			# Check if the seq atribute value is the one we look ($seq)
			if ( $cmd_seq eq $seq ) {
				my $type = $command->getAttribute("type");
				my $ostype = $command->getAttribute("ostype");
				# Case 1. Verbatim type
				if ( $type eq "verbatim" ) { # <exec> tag specifies a single command
				
					my $command_tag = &text_tag($command);
					
					if ( ($ostype eq 'show') || ($ostype eq 'set') ) {

						# Get the user name and password. If several users are defined, 
						# we just take the first one.
						my @login_users = &get_login_user($extConfFile, $vm_name);
		     			my $login_user = $login_users[0];
		 				my $user=$login_user->[0];
						my $pass=$login_user->[1];
						# Get enable password
 						my $enablepass = get_enable_pass($extConfFile, $vm_name);
						# create CiscoExeCmd object to connect to router console
						my $sess = new VNX::CiscoExeCmd ('localhost', $port, $user, $pass, $enablepass);
						# Connect to console
						my $res = $sess->open;
						if (!$res) { $execution->smartdie("ERROR: cannot connect to ${vm_name}'s console at port $port.\n" .
							                              "       Please, release the router console and try again.\n"); }
						# Put router in priviledged mode
						$res = $sess->goToEnableMode;
						if ($res eq 'timeout') {
							$execution->smartdie("ERROR: timeout connecting to ${vm_name}'s console at port $port.\n" .
							                     "       Please, release the router console and try again.\n"); 
                        } elsif ($res eq 'invalid_login') { 
                            $execution->smartdie("ERROR: invalid login connecting to ${vm_name}'s console at port $port\n") 
                        } elsif ($res eq 'bad_enable_passwd') { 
                            $execution->smartdie("ERROR: invalid enable password connecting to ${vm_name}'s console at port $port\n") 
                        }
					    if ($ostype eq 'set') {	my @output = $sess->exeCmd ('configure terminal'); }
						# execute the command
						my @output = $sess->exeCmd ($command_tag);
						print "\ncmd '$command_tag' result: \n\n@output\n";
					    if ($ostype eq 'set') {	my @output = $sess->exeCmd ('end'); }
						$sess->exeCmd ("disable");
						$sess->exeCmd ("exit");
						$sess->close;

					} if ($ostype eq 'load') {
						
						my $newRouterConfFile = $dh->get_vm_dir($vm_name) . "/" . $vm_name . ".conf";
						
						# Parse command
						if ( $command_tag =~ /merge / ) {
							# Merge mode: add configuration in VNX spec (hostname, ip addressses and routes)
							# to the configuration file provided
							print "*** load merge\n";
							$command_tag =~ s/merge //;
							my $confFile = &get_abs_path($command_tag);
							if (-e $confFile) {
								# Eliminate end command if it exists
	   	 						$execution->execute("sed '/^end/d' " . $confFile . ">" . $newRouterConfFile);
								# Add configuration in VNX spec file to the router config file
								my @routerConf = &create_router_conf ($vm_name, $extConfFile);
								open (CONF, ">> $newRouterConfFile") or $execution->smartdie("ERROR: Cannot open $newRouterConfFile");
								print CONF @routerConf;
								close (CONF);
								&reload_conf ($vm_name, $newRouterConfFile, $dynamipsHost, $dynamipsPort, $consFile);
							} else {
								$execution->smartdie("ERROR: configuration file $confFile not found\n") 
							}
						} else {
							# Normal mode: just load the configuration file as it is
							my $confFile = &get_abs_path($command_tag);
							if (-e $confFile) {
								&reload_conf ($vm_name, $confFile, $dynamipsHost, $dynamipsPort, $consFile);
	   	 						# Copy the file loaded config to vm directory
	   	 						$execution->execute("cat " . $confFile . ">" . $newRouterConfFile);
							} else {
								$execution->smartdie("ERROR: configuration file $confFile not found\n") 
							}
						}
					}
					
					

# DFC 5/5/2011: command reload deprecated. ostype='load' command type defined to load configurations					
#					if ($command_tag =~ m/^reload/){
#						my @file_conf = split('reload ',$command_tag);
#						&reload_conf ($vm_name, $file_conf[1], $dynamipsHost, $dynamipsPort, $consFile);
#						print "WARNING: reload command deprecated; use ostype='load' instead\n"
#					}else{
#					}
				}

				elsif ( $type eq "file" ) { # <exec> tag specifies a file containing a list of commands

					if ( ($ostype eq 'show') || ($ostype eq 'set') ) {

						# We open the file and read and execute commands line by line
						my $include_file =  &do_path_expansion( &text_tag($command) );
								
						# Get the user name and password. If several users are define, 
						# we just take the first one.
						my @login_users = &get_login_user($extConfFile, $vm_name);
		     			my $login_user = $login_users[0];
		 				my $user=$login_user->[0];
						my $pass=$login_user->[1];
						# Get enable password
						my $enablepass = get_enable_pass($extConfFile, $vm_name);
						# create CiscoExeCmd object to connect to router console
						my $sess = new VNX::CiscoExeCmd ('localhost', $port, $user, $pass, $enablepass);
						# Connect to console
						my $res = $sess->open;
						if (!$res) { $execution->smartdie("ERROR: cannot connect to ${vm_name}'s console at port $port.\n" .
							                              "       Please, release the router console and try again.\n"); }
						# Put router in priviledged mode
						$res = $sess->goToEnableMode;
						if ($res eq 'timeout') {
							$execution->smartdie("ERROR: timeout connecting to ${vm_name}'s console at port $port.\n" .
							                     "       Please, release the router console and try again.\n"); 
						} elsif ($res eq 'invalidlogin') { 
							$execution->smartdie("ERROR: invalid login connecting to ${vm_name}'s console at port $port\n") 
						}
						if ($ostype eq 'set') {	my @output = $sess->exeCmd ('configure terminal'); }
						# execute the file with commands 
						@output = $sess->exeCmdFile ("$include_file");
						print "-- cmd result: \n\n@output\n";
						if ($ostype eq 'set') {	my @output = $sess->exeCmd ('end'); }
						$sess->exeCmd ("disable");
						$sess->exeCmd ("exit");
						$sess->close;
					} elsif ($ostype eq 'load')  { # should never occur when checnked in CheckSemantics
							$execution->smartdie("ERROR: ostype='load' not allowed with <exec> tags of mode='file'\n") 
					}
					
				}
				# Other cases impossible. Only 'verbatim' or 'file' allowed by vnx XSD definition
			}
		}
	}	
}

#
# Internal subs
#
sub reload_conf {

	my $vm_name    = shift;
	my $confFile = shift;
	my $dynamipsHost = shift;
	my $dynamipsPort = shift;
	my $consFile = shift;
	
	$confFile = &get_abs_path ($confFile);
	unless (-e $confFile) {	$execution->smartdie ("router $vm_name configuration file not found ($confFile)") } 
	my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    print("vm stop $vm_name \n");
	$t->print("vm stop $vm_name");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
   	print("vm set_config $vm_name \"$confFile\" \n");
   	$t->print("vm set_config $vm_name \"$confFile\" ");
   	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
   	$t->print("vm start $vm_name");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    sleep (3);    
	VNX::vmAPICommon->start_consoles_from_console_file ($vm_name);
}



# Devuelve en un array de dos columnas, los valores dados en la etiqueta login del XML
# Por defecto (si no existe) no devuelve usuarios.
sub get_login_user {

	my $extConfFile = shift;
	my $vm_name    = shift;

	my @users;
	
	# If the extended config file is not defined, return default value 
	if ($extConfFile eq '0'){
		push(@users,["",""]);
		return @users;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($extConfFile);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	# Buscamos la seccion de la maquina virtual
	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
# 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vm_name ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vm_name){
		my $login_user_list = $virtualm->getElementsByTagName("login");
		if ((my $length_user = $login_user_list->getLength) gt 0){
			for ( my $j = 0 ; $j < $length_user ; $j++ ) {
				my $login_user = $login_user_list->item($j);
				my $user = $login_user->getAttribute("user");
				my $pass = $login_user->getAttribute("password");
				push(@users,[$user,$pass]);
	 			$global_tag = 0;
			}
		}
	}
	# Si en anteriores comprobaciones no existe, se pasa a la global
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item(0);
			my $login_user_gl_list = $globaltag->getElementsByTagName("login");
			if ((my $length_user = $login_user_gl_list->getLength) gt 0){
				for ( my $j = 0 ; $j < $length_user ; $j++ ) {
					my $login_user_gl = $login_user_gl_list->item($j);
					my $user_gl = $login_user_gl->getAttribute("user");
					my $pass_gl = $login_user_gl->getAttribute("password");
					push(@users,[$user_gl,$pass_gl]);
		 			$global_tag = 0;
				}
			}
		}	
	}
	# Devuelve el valor por defecto
	if (($global_tag eq 1 )&&($default_tag eq 1)){
		push(@users,["",""]);
	}
 	return @users;
}

#
# get_enable_pass: returns router priviledged mode (enable) password 
#                  or an empty string if not defined
sub get_enable_pass {

	my $extConfFile = shift;
	my $vm_name = shift;

	my $result = "";

	# If the extended config file is not defined, return default value 
	if ($extConfFile eq '0'){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($extConfFile);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	# Buscamos la seccion de la maquina virtual
	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vm_name ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vm_name){
		my $enable_pass_list = $virtualm->getElementsByTagName("enable");
		if ($enable_pass_list->getLength gt 0){
			my $enable_pass = $enable_pass_list->item(0);
			$result = $enable_pass->getAttribute("password");
 			$global_tag = 0;
		}
	}
	# Si en anteriores comprobaciones no existe, se pasa a la global
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item(0);
			my $enable_pass_gl_list = $globaltag->getElementsByTagName("enable");
			if ($enable_pass_gl_list->getLength gt 0){
				my $enable_pass_gl = $enable_pass_gl_list->item(0);
				$result = $enable_pass_gl->getAttribute("password");
			}
		}	
	}
 	return $result;
}

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
	
	# Set default value
# DFC: Changed to make the code compatible with perl 5.8. 
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


		
	# If the extended config file is not defined, return default value 
	if ($extConfFile eq '0'){
		return "$result\n";
	}
	
	# Parse the extended config file
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($extConfFile);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
			
	# First, we look for a definition in the $vm_name <vm> section 
	for ( my $j = 0 ; $j < $virtualmList->getLength ; $j++ ) {
	 	# We get name attribute
	 	my $virtualm = $virtualmList->item($j);
		my $name = $virtualm->getAttribute("name");
		if ( $name eq $vm_name ) {
			my $tag_list = $virtualm->getElementsByTagName("$tagName");
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
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item(0);
			my $tag_gl_list = $globaltag->getElementsByTagName("$tagName");
			if ($tag_gl_list->getLength gt 0){
				my $tag_gl = $tag_gl_list->item(0);
				$result = &text_tag($tag_gl);
                print "*** vmName = $vm_name, global entry found ($result)\n";
			}
		}	
	}
	return $result;
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

	my $result = "0";
	
	# If the extended config file is not defined, return default value 
	if ($extConfFile eq '0'){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($extConfFile);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	# Buscamos la seccion de la maquina virtual
 	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vm_name ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vm_name){
		my $conf_list = $virtualm->getElementsByTagName("conf");
		if ($conf_list->getLength gt 0){
			my $conftag = $conf_list->item(0);
			$result = &text_tag($conftag);
			$global_tag = 0;
			$result = &get_abs_path ($result);
		}
	}
	print "**** get_router_conf_file: $result\n";
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
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($extConfFile);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	# Buscamos la seccion de la maquina virtual
 	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vm_name ) {
			my $hw_list = $virtualm->getElementsByTagName("hw");
			if ($hw_list->getLength gt 0){
				my $hw = $hw_list->item(0);
				my $slot_list = $hw->getElementsByTagName("slot");
		 		my $numslot = $slot_list->getLength;
		 		# Añadimos las tarjetas que haya en el fichero.
		 		for ( my $j = 0 ; $j < $numslot ; $j++ ) {
		 			my $slotTag = $slot_list->item($j);
					my $slot = &text_tag($slotTag);
					push(@slotarray,$slot);
					# Como ya tenemos tarjetas no vemos las globales.
					$global_tag = 0;
		 		}
			}
			last;
		}
 	}
	# Si no hay tarjetas definidas en la seccion del router virtual.
	# se utilizan el que está definido en la parte global.
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item(0);
			my $hw_gl_list = $globaltag->getElementsByTagName("hw");
			if ($hw_gl_list->getLength gt 0){
				my $hw_gl = $hw_gl_list->item(0);
				my $slot_gl_list = $hw_gl->getElementsByTagName("slot");
	 			my $numslotgl = $slot_gl_list->getLength;
	 			for ( my $j = 0 ; $j < $numslotgl ; $j++ ) {
	 				my $slotTaggl = $slot_gl_list->item($j);
					my $slot_gl = &text_tag($slotTaggl);
					push(@slotarray,$slot_gl);
					# Como ya tenemos tarjetas definidas, no utilizamos la configurada por defecto.
					$default_tag = 0;
	 			}
			}
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

###################################################################
#                                                                 
sub change_vm_status {

#	my $dh     = shift;
	my $vm     = shift;
	my $status = shift;

	my $status_file = $dh->get_vm_dir($vm) . "/status";

	if ( $status eq "REMOVE" ) {
		$execution->execute(
			$bd->get_binaries_path_ref->{"rm"} . " -f $status_file" );
	}
	else {
		$execution->execute(
			$bd->get_binaries_path_ref->{"echo"} . " $status > $status_file" );
	}
}

=BEGIN
#
# get_dynamips_port_conf
#
#   Returns dynamips daemon port from /etc/vnx.conf file
#   If not defined, returns default value ($VNX::Globals::DYNAMIPS_DEFAULT_PORT)
#
sub get_dynamips_port_conf {

	my $result = $VNX::Globals::DYNAMIPS_DEFAULT_PORT;
	
	unless(-e $VNX::Globals::MAIN_CONF_FILE){
		return $result;
	}
	open FILE, "<$VNX::Globals::MAIN_CONF_FILE" or $execution->smartdie("$VNX::Globals::MAIN_CONF_FILE not found");
	my @lines = <FILE>;
	foreach my $line (@lines){
	    if (($line =~ /port/) && !($line =~ /^#/)){ 
			my @config1 = split(/=/, $line);
			my @config2 = split(/#/,$config1[1]);
			$result = $config2[0];
			chop $result;
			$result =~ s/\s+//g;
	    }
	}
 	return $result;
}

#
# get_dynamips_port_conf
#
#   Returns idle-pc value from /etc/vnx.conf file
#   If not defined, returns 0x604f8104
#
sub get_idle_pc_conf {
	my $vm_name = shift;
	my $result = "0x604f8104";
	
	unless(-e $VNX::Globals::MAIN_CONF_FILE){
		return $result;
	}
	open FILE, "<$VNX::Globals::MAIN_CONF_FILE" or $execution->smartdie("$VNX::Globals::MAIN_CONF_FILE not found");
	my @lines = <FILE>;
	foreach my $line (@lines){
	    if (($line =~ /idle_pc/) && !($line =~ /^#/)){ 
			my @config1 = split(/=/, $line);
			my @config2 = split(/#/,$config1[1]);
			$result = $config2[0];
			chop $result;
			$result =~ s/\s+//g;
	    }
	}
 	return $result;
}
=END
=cut

=BEGIN
# 
# get_port_conf
#
#
#
sub get_port_conf {

	my $extConfFile = shift;
	my $vm_name    = shift;
	my $counter   = shift;

	my $result =  900 + $counter;
	
	unless(-e $extConfFile){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($extConfFile);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");

 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	# Buscamos la seccion de la maquina virtual
 	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vm_name ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vm_name){
		my $hw_list = $virtualm->getElementsByTagName("hw");
		if ($hw_list->getLength gt 0){
			my $hw = $hw_list->item(0);
			my $console_list = $hw->getElementsByTagName("console");
	 		if($console_list->getLength gt 0){
	 			my $consoleTag = $console_list->item(0);
	 			$result = $consoleTag->getAttribute("port");
	 			$global_tag = 0;
	 		}
		}
	}
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item(0);
			my $hw_gl_list = $globaltag->getElementsByTagName("hw");
			if ($hw_gl_list->getLength gt 0){
				my $hw_gl = $hw_gl_list->item(0);
				my $console_gl_list = $hw_gl->getElementsByTagName("console_base");
	 			if($console_gl_list->getLength gt 0){
	 				my $console_gl_Tag = $console_gl_list->item(0);
	 				my $base = $console_gl_Tag->getAttribute("port");
	 				$result = $base + $counter;
	 			}
			}
		}	
	}
#	if (($default_tag eq 1)&&($global_tag eq 1)){
#		$result = 900 + $counter; 
#	}
 	return $result;
}
=END
=cut


=BEGIN
# Devuelve el valor de la etiqueta sparsemem
# Si no se define, devuelve un valor true.
sub get_sparsemem {

	my $extConfFile = shift;
	my $vm_name    = shift;

	my $result = "true";
	
	# If the extended config file is not defined, return default value 
	if ($extConfFile eq '0'){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($extConfFile);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	# Buscamos la seccion de la maquina virtual
	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vm_name ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vm_name){
		my $sparsemem_list = $virtualm->getElementsByTagName("sparsemem");
		if ($sparsemem_list->getLength gt 0){
			my $sparsemem = $sparsemem_list->item(0);
			$result = &text_tag($sparsemem);
 			$global_tag = 0;
		}
	}
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item(0);
			my $sparsemem_gl_list = $globaltag->getElementsByTagName("sparsemem");
			if ($sparsemem_gl_list->getLength gt 0){
				my $sparsemem_gl = $sparsemem_gl_list->item(0);
				$result = &text_tag($sparsemem_gl);
			}
		}	
	}
 	return $result;
}

# Devuelve el valor de la etiqueta ghost_ios
# Si no se define, devuelve un valor false.
sub get_ghost_ios {
	
	my $extConfFile = shift;
	my $vm_name    = shift;

	my $result = "false";
	
	# If the extended config file is not defined, return default value 
	if ($extConfFile eq '0'){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($extConfFile);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	# Buscamos la seccion de la maquina virtual
	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vm_name ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vm_name){
		my $ghostios_list = $virtualm->getElementsByTagName("ghostios");
		if ($ghostios_list->getLength gt 0){
			my $ghostios = $ghostios_list->item(0);
			$result = &text_tag($ghostios);
 			$global_tag = 0;
		}
	}
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item(0);
			my $ghostios_gl_list = $globaltag->getElementsByTagName("ghostios");
			if ($ghostios_gl_list->getLength gt 0){
				my $ghostios_gl = $ghostios_gl_list->item(0);
				$result = &text_tag($ghostios_gl);
			}
		}	
	}
 	return $result;
}


#################################################################
# get_chassis 													#
# 																#
# Saca del fichero de configuración extendida, el chassis 		#
# que este definido												#
# Entrada:														#
# 	Nombre del router virtual									#
# Salida:														#
# 	Nombre del chasis a utilizar, si no está definido se utiliza#
#   el de por defecto, que es "c3640"							# 
#################################################################
sub get_chassis {

	my $extConfFile = shift;
	my $vm_name    = shift;

	# Default chasis if not defined in extended config file
	my $result = "c3640";
	
	# If the extended config file is not defined, return default value 
	if ($extConfFile eq '0'){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($extConfFile);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	# Buscamos la seccion de la maquina virtual
 	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vm_name ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vm_name){
		my $hw_list = $virtualm->getElementsByTagName("hw");
		if ($hw_list->getLength gt 0){
			my $hw = $hw_list->item(0);
			my $chassis_list = $hw->getElementsByTagName("chassis");
	 		if($chassis_list->getLength gt 0){
	 			my $chassisTag = $chassis_list->item(0);
	 			$result = &text_tag($chassisTag);
	 			$global_tag = 0;
	 		}
		}
	}
	# Si no hay tarjetas definidas en la seccion del router virtual.
	# se utilizan el que está definido en la parte global.
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item(0);
			my $hw_gl_list = $globaltag->getElementsByTagName("hw");
			if ($hw_gl_list->getLength gt 0){
				my $hw_gl = $hw_gl_list->item(0);
				my $chassis_gl_list = $hw_gl->getElementsByTagName("chassis");
	 			if($chassis_gl_list->getLength gt 0){
	 				my $chassisTag = $chassis_gl_list->item(0);
	 				$result = &text_tag($chassisTag);
	 			}
			}
		}	
	}
	# Si no hay chassis definido en la seccion del router virtual.
	# se utiliza el de por defecto "c3640".
 	return $result;
}

=END
=cut

=BEGIN Moved to VNX
# 
# validateExtXMLFiles
# 
#   Checks the existence of the extended configuration file and validates it.
#   Returns the full pathname of the file.
#
# Arguments:
#   extConfFile: the extended configuration filename provided in the XML
#
# Returns
#   full path name of file
#
sub validateExtXMLFiles{
	
	my $self = shift;
	my $tempconf = shift;
	#print "*** vmAPI_dynamips: validateExtXMLFiles tempconf=$tempconf\n";

	$tempconf = &get_abs_path ($tempconf);
	
	# Comprueba que exista el fichero
	if (-e $tempconf){
		#$extConfFile = $tempconf;
		open CONF_EXT_FILE, "$tempconf";
   			my @conf_file_array = <CONF_EXT_FILE>;
   			my $extConfFile_string = join("",@conf_file_array);
   		close CONF_EXT_FILE;
		my $schemalocation;

#jsf	if ($input_file_string =~ /="(.*).xsd"/) {
	    if ($extConfFile_string =~ /="(\S*).xsd"/) {
        	$schemalocation = $1 .".xsd";
		}else{
			print "input_file_string = $extConfFile_string, $schemalocation=schemalocation\n" if ($exemode == $EXE_VERBOSE);
			$execution->smartdie("XSD not found");
		}
		if (!(-e $schemalocation)){
			$execution->smartdie("$schemalocation not found");
		}
		# Valida el XML contra el Schema
        my $schema = XML::LibXML::Schema->new(location => $schemalocation);
		
		
		my $parser = XML::LibXML->new;
		#$doc    = $parser->parse_file($document);
		my $doc = $parser->parse_file($tempconf);
		
		eval { $schema->validate($doc) };
	
		if ($@) {
		  # Validation errors
		  $execution->smartdie("$tempconf is not a well-formed Dynamips extended configuration file");
		}
    	#print "*** validateExtXMLFiles: tempconf=$tempconf\n";
		return $tempconf;	
	}else
	{
		$execution->smartdie("$tempconf not found");
	}
}
=END
=cut

1;
