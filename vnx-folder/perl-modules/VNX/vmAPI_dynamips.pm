# vmAPI_dynamips.pm
#
# This file is a module part of VNX package.
#
# Authors: Jorge Somavilla, Jorge Rodriguez, Miguel Ferrer, Francisco José Martín, David Fernández
# Coordinated by: David Fernández (david@dit.upm.es)
#
# Copyright (C) 2010, 	DIT-UPM
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
#@ISA    = qw(Exporter);
@EXPORT = qw(defineVM
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
  executeCMD);

package vmAPI_dynamips;

@ISA    = qw(Exporter);
#@EXPORT = qw(defineVM);
  
use strict;
use XML::LibXML;
use XML::DOM;
use XML::DOM::ValParser;

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
use Net::IP;
use Net::Telnet::Cisco;
use File::Basename;

#my $execution;    # the VNX::Execution object
#my $dh;           # the VNX::DataHandler object
#my $bd;           # the VNX::BinariesData object

my $conf_file="";
my $dynamipsHost="localhost";
my $dynamipsPort=get_dynamips_port_conf();


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
	my $vmName = shift;
	my $type   = shift;
	my $doc    = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
	my $sock    = shift;
	my $counter = shift;
	my $doc2       = $dh->get_doc;
	my @vm_ordered = $dh->get_vm_ordered;


# Comentado por DFC (31/12/2010) Sirve para algo?
=BEGIN
	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {

		my $vm = $vm_ordered[$i];

		# We get name attribute
		my $name = $vm->getAttribute("name");

		unless ( $name eq $vmName ) {
			next;
		}
	}
=END
=cut	
	
	
	# Configuramos el fichero de configuracion especial
	my $dynamipsconf = $dh->get_default_dynamips();
	if (!($dynamipsconf eq "0")){
		my $result = &set_config_file($dh->get_default_dynamips());	
	}

		
	my $filenameconf;
	my $ifTagList;
	
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parse($doc);
	my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
	my $virtualm     = $virtualmList->item(0);
	
	my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
	my $filesystemTag     = $filesystemTagList->item(0);
	my $filesystem_type   = $filesystemTag->getAttribute("type");
	my $filesystem        = $filesystemTag->getFirstChild->getData;
	
	# Definicion del fichero de configuracion extendida host
	my $conf_dynamips = get_conf_file($vmName);
	
	# Miro si hay definido en el XML un fichero de configuracion extendida
	if (!($conf_dynamips eq 0))
	{
		# Compruebo que se puede abrir.
	 	if (-e $conf_dynamips)
		{
			# Si existe, me voy al final del fichero y quito el end, ya que vamos a continuar
			# desde el final.  
	   	 	$filenameconf  = $dh->get_vm_dir($vmName) . "/" . $vmName . ".conf";
	   	 	$execution->execute("sed '/end/d' " . $conf_dynamips . ">" . $filenameconf);
	   	 	open (CONF_CISCO, ">>$filenameconf") || $execution->smartdie("ERROR: No puedo abrir el fichero $filenameconf");
	   	 	
	   	 	# Por defecto, los valores puestos en el XML del vnx ,
	   	 	# prevalecen sobre los puestos en cualquier fichero de configuracion.
	   	 	
			print CONF_CISCO "hostname " . $vmName ."\n";
	 		$ifTagList = $virtualm->getElementsByTagName("if");
	 		my $numif = $ifTagList->getLength;
	 		# Configuramos las interfaces.
	 		# P.ej:
	 		# 	interface e0/0
			# 	 mac-address fefd.0003.0101
			# 	 ip address 10.1.1.4 255.255.255.0
			# 	 ipv6 enable
			# 	 ipv6 address 2001:db8::1/64
			# 	 no shutdown
	 		
	 		for ( my $j = 0 ; $j < $numif ; $j++ ) {
	 			my $ifTag = $ifTagList->item($j);
				my $id    = $ifTag->getAttribute("id");
				my $net   = $ifTag->getAttribute("net");
				my $mac   = $ifTag->getAttribute("mac");
				$mac =~ s/,//;
				my @maclist = split(/:/,$mac);
				$mac = $maclist[0] . $maclist[1] . "." . $maclist[2] . $maclist[3] . "." . $maclist[4] . $maclist[5];
				my $nameif   = $ifTag->getAttribute("name");
				print CONF_CISCO "interface " . $nameif . "\n";	
				print CONF_CISCO " mac-address " . $mac . "\n";
				# Damos direccion IPv4	
				my $ipv4_list = $ifTag->getElementsByTagName("ipv4");
				if ( $ipv4_list->getLength != 0 ) {
					my $ipv4_Tag = $ipv4_list->item(0);
					my $ipv4 =  $ipv4_Tag->getFirstChild->getData;
					my $subnetv4 = $ipv4_Tag->getAttribute("mask");
					print CONF_CISCO " ip address " . $ipv4 . " ". $subnetv4 . "\n";	
				}
				# Damos direccion IPv6
				my $ipv6_list = $ifTag->getElementsByTagName("ipv6");
				if ( $ipv6_list->getLength != 0 ) {
					print CONF_CISCO " ipv6 enable\n";	
					my $ipv6_Tag = $ipv6_list->item(0);
					my $ipv6 =  $ipv6_Tag->getFirstChild->getData;
					print CONF_CISCO " ipv6 address " . $ipv6 . "\n";	
					}
				# Levantamos la interfaz
				print CONF_CISCO " no shutdown\n";	
	 		}
	 		# Configura las rutas	
			my $routeTagList = $virtualm->getElementsByTagName("route");
 			my $numroute = $routeTagList->getLength;
 			for ( my $j = 0 ; $j < $numroute ; $j++ ) {
 				my $routeTag = 	$routeTagList->item($j);
 				my $gw = $routeTag->getAttribute("gw");
 				my $destination = $routeTag->getFirstChild->getData;
 				my $maskdestination = "";
 				if ($destination eq "default"){
 					$destination = "0.0.0.0";
 					$maskdestination = "0.0.0.0";
 				}else {
 					my $ip = new Net::IP ($destination) or $execution->smartdie (Net::IP::Error());
 					$maskdestination = $ip->mask();
 					$destination = $ip->ip();
 				}
 				print CONF_CISCO "ip route ". $destination . " " . $maskdestination . " " . $gw . "\n";	
 			}
 			# Si en el fichero de configuracion extendida se define un usuario y password.
			my @login_users = &get_login_user($vmName);
 			my $login_user;
 			my $check_login_user = 0;
 			foreach $login_user(@login_users){
 				my $user=$login_user->[0];
 				my $pass=$login_user->[1];
 				if (($user eq "")&&(!($pass eq ""))){
 					print CONF_CISCO " line con 0 \n";
 					print CONF_CISCO " password $pass\n";
 					print CONF_CISCO " login\n";
 				}elsif((!($user eq ""))&&(!($pass eq ""))){
					print CONF_CISCO " username $user password 0 $pass\n";
					$check_login_user= 1;
 				}
    		}
    		if ($check_login_user eq 1){
    			print CONF_CISCO " line con 0 \n";
 				print CONF_CISCO " login local\n";
    		}
 			# Si el fichero de configuacion extendida se define una password de enable, se pone.
 			my $enablepass = &get_enable_pass($vmName);
 			if (!($enablepass eq "")){
				print CONF_CISCO " enable password " . $enablepass . "\n";
    		}
 			print CONF_CISCO " end\n";
 			close(CONF_CISCO);		 	
		}else{
			$execution->smartdie("Can not open " . $conf_dynamips );
		}
	}
	# Si no se ha definido ninguno, me defino el fichero de configuracion a pasar al cisco.
	else{
		$filenameconf = $dh->get_vm_dir($vmName) . "/" . $vmName . ".conf";
		open (CONF_CISCO, ">$filenameconf") || $execution->smartdie("ERROR: No puedo abrir el fichero $filenameconf");
		print CONF_CISCO "hostname " . $vmName ."\n";
 		$ifTagList = $virtualm->getElementsByTagName("if");
 		my $numif = $ifTagList->getLength;
 			# Configuramos las interfaces.
	 		# P.ej:
	 		# 	interface e0/0
			# 	 mac-address fefd.0003.0101
			# 	 ip address 10.1.1.4 255.255.255.0
			# 	 ipv6 enable
			# 	 ipv6 address 2001:db8::1/64
			# 	 no shutdown
 		for ( my $j = 0 ; $j < $numif ; $j++ ) {
 			my $ifTag = $ifTagList->item($j);
			my $id    = $ifTag->getAttribute("id");
			my $net   = $ifTag->getAttribute("net");
			my $mac   = $ifTag->getAttribute("mac");
			$mac =~ s/,//;
			my @maclist = split(/:/,$mac);
			$mac = $maclist[0] . $maclist[1] . "." . $maclist[2] . $maclist[3] . "." . $maclist[4] . $maclist[5];
			my $nameif   = $ifTag->getAttribute("name");
			print CONF_CISCO "interface " . $nameif . "\n";	
			print CONF_CISCO " mac-address " . $mac . "\n";
			# Damos direccion IPv4		
			my $ipv4_list = $ifTag->getElementsByTagName("ipv4");
			if ( $ipv4_list->getLength != 0 ) {
				my $ipv4_Tag = $ipv4_list->item(0);
				my $ipv4 =  $ipv4_Tag->getFirstChild->getData;
				my $subnetv4 = $ipv4_Tag->getAttribute("mask");
				print CONF_CISCO " ip address " . $ipv4 . " ". $subnetv4 . "\n";	
			}
			# Damos direccion IPv6
			my $ipv6_list = $ifTag->getElementsByTagName("ipv6");
			if ( $ipv6_list->getLength != 0 ) {
				print CONF_CISCO " ipv6 enable\n";	
				my $ipv6_Tag = $ipv6_list->item(0);
				my $ipv6 =  $ipv6_Tag->getFirstChild->getData;
				print CONF_CISCO " ipv6 address " . $ipv6 . "\n";	
				}
			# Levantamos la interfaz
			print CONF_CISCO " no shutdown\n";		
 		}
 		# Configura las rutas
 		my $routeTagList = $virtualm->getElementsByTagName("route");
 		my $numroute = $routeTagList->getLength;
 		for ( my $j = 0 ; $j < $numroute ; $j++ ) {
 			my $routeTag = 	$routeTagList->item($j);
 			my $gw = $routeTag->getAttribute("gw");
 			my $destination = $routeTag->getFirstChild->getData;
 			my $maskdestination = "";
 			if ($destination eq "default"){
 				$destination = "0.0.0.0";
 				$maskdestination = "0.0.0.0";
 			}else {
 				my $ip = new Net::IP ($destination) or $execution->smartdie (Net::IP::Error());
 				$maskdestination = $ip->mask();
 				$destination = $ip->ip();
 			}
 			print CONF_CISCO "ip route ". $destination . " " . $maskdestination . " " . $gw . "\n";	
 			
 		}
 		# Si en el fichero de configuracion extendida se define un usuario y password.
 			my @login_users = &get_login_user($vmName);
 			my $login_user;
 			my $check_login_user = 0;
 			foreach $login_user(@login_users){
 				my $user=$login_user->[0];
 				my $pass=$login_user->[1];
 				if (($user eq "")&&(!($pass eq ""))){
 					print CONF_CISCO " line con 0 \n";
 					print CONF_CISCO " password $pass\n";
 					print CONF_CISCO " login\n";
 				}elsif((!($user eq ""))&&(!($pass eq ""))){
					print CONF_CISCO " username $user password 0 $pass\n";
					$check_login_user= 1;
 				}
    		}
    		if ($check_login_user eq 1){
    			print CONF_CISCO " line con 0 \n";
 				print CONF_CISCO " login local\n";
    		}
    		
 		# Si el fichero de configuacion extendida se define una password de enable, se pone.
 		my $enablepass = get_enable_pass($vmName);
 		if (!($enablepass eq "")){
			print CONF_CISCO " enable password " . $enablepass . "\n";
    	}
    	# Se habilita el ip http server ya que si no se hace, el acceso por telnet se bloquea.
 		print CONF_CISCO "ip http server\n";
 		print CONF_CISCO " end\n";
 		close(CONF_CISCO);	
	}
    # Preparar las variables
    my $memTagList = $virtualm->getElementsByTagName("mem");
    my $mem = "96";

	if ( $memTagList->getLength != 0 ) {
		my $memTag     = $memTagList->item(0);
		$mem   = ($memTag->getFirstChild->getData)/1024;
	} 
	
   # my $dynamips_ext_list = $doc2->getElementsByTagName("dynamips_ext");

    
    # Definicion del router

	my $line;
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    # Si es la primera vez que se ejecuta el escenario, se borra todo el hypervisor
    # Precacion, tambien se borra otros escenarios que este corriendo paralelamente
    if ($counter == 0)
    {
    	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    	print "Reset hypervisor:\n" if ($exemode == $EXE_VERBOSE);;
    	$t->print("hypervisor reset");
   		$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    	$t->close;
    	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    }
    
	
	
	#my $consoleportbase = "900";
	#my $consoleport = $consoleportbase + $counter;

    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    print("hypervisor version\n") if ($exemode == $EXE_VERBOSE);
    $t->print("hypervisor version");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    print("hypervisor working_dir \"". $dh->get_fs_dir($vmName)."\" \n") if ($exemode == $EXE_VERBOSE);
    $t->print("hypervisor working_dir \"". $dh->get_fs_dir($vmName). "\" ");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
	
	
	# Set type
	my($trash,$model)=split(/-/,$type,2);
    print("vm create $vmName 0 c$model\n");
	$t->print("vm create $vmName 0 c$model");
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
#    my %consDisplayDefInXML = (1,$VNX::Globals::CONS_DISPLAY_DEFAULT,2,$VNX::Globals::CONS_DISPLAY_DEFAULT); 
    my %consDisplayDefInXML = (1,$CONS_DISPLAY_DEFAULT,2,$CONS_DISPLAY_DEFAULT); 
    print "** $vmName: console ports, con1='$consPortDefInXML{1}', con2='$consPortDefInXML{2}'\n" if ($exemode == $EXE_VERBOSE);
	for ( my $j = 0 ; $j < $numcons ; $j++ ) {
		my $consTag = $consTagList->item($j);
   		my $value = &text_tag($consTag);
		my $id    = $consTag->getAttribute("id");        # mandatory
		my $display = $consTag->getAttribute("display"); # optional
		my $port = $consTag->getAttribute("port");       # optional
   		print "** console: id=$id, display=$display port=$port value=$value\n" if ($exemode == $EXE_VERBOSE);
		if ( ($id eq "1") || ($id eq "2") ) {
			if ( $value ne "" && $value ne "telnet" ) { 
				print "WARNING (vm=$vmName): only 'telnet' value is allowed for Dynamips consoles. Value ignored.\n"
			}
			$consPortDefInXML{$id} = $port;
			if ($display ne '') { $consDisplayDefInXML{$id} = $display }
		}
		if ( ( $id eq "0" ) || ($id > 1) ) {
			print "WARNING (vm=$vmName): only consoles with id='1' or '2' allowed for Dynamips virtual machines. Tag with id=$id ignored.\n"
		} 
	}
	print "** $vmName: console ports, con1='$consPortDefInXML{1}', con2='$consPortDefInXML{2}'\n" if ($exemode == $EXE_VERBOSE);

    # Define ports for main console and aux console (only used for 7200)
	my @consolePort = qw();
    foreach my $j (1, 2) {
		if ($consPortDefInXML{$j} eq "") { # telnet port not defined we choose a free one starting from $CONS_PORT
			$consolePort[$j] = $VNX::Globals::CONS_PORT;
			while ( !system("fuser -s -v -n tcp $consolePort[$j]") ) {
				$consolePort[$j]++;
			}
			$VNX::Globals::CONS_PORT = $consolePort[$j] + 1;
		} else { # telnet port was defined in <console> tag
			$consolePort[$j] = $consPortDefInXML{$j};
			while ( !system("fuser -s -v -n tcp $consolePort[$j]") ) {
				$consolePort[$j]++;
			}
		}
		print "WARNING (vm=$vmName): cannot use port $consPortDefInXML{1} for console #1; using $consolePort[$j] instead\n"
	   		if ( ($consPortDefInXML{$j} ne "") && ($consolePort[$j] ne $consPortDefInXML{$j}) );
    }
	
	#my $consoleport = &get_port_conf($vmName,$counter);
	my $consFile = $dh->get_vm_dir($vmName) . "/console";
	
	open (PORT_CISCO, ">$consFile") || $execution->smartdie("ERROR (vm=$vmName): cannot open $consFile");
	print PORT_CISCO "con1=$consDisplayDefInXML{1},telnet,$consolePort[1]\n";
	print("vm set_con_tcp_port $vmName $consolePort[1]\n");
	$t->print("vm set_con_tcp_port $vmName $consolePort[1]");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    if ($type eq 'dynamips-7200') {
    	# Configure aux port
		print PORT_CISCO "con2=$consDisplayDefInXML{2},telnet,$consolePort[2]\n";
		print("vm set_con_tcp_port $vmName $consolePort[2]\n");
		$t->print("vm set_con_tcp_port $vmName $consolePort[2]");
	    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    }
	close (PORT_CISCO);
    
    # Set Chassis
    my $chassis = &get_chassis($vmName);
    $chassis =~ s/c//;
    print("c$model set_chassis $vmName $chassis\n");
    $t->print("c$model set_chassis $vmName $chassis");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    
	# Set Filesystem
    print("vm set_ios $vmName $filesystem\n");
    $t->print("vm set_ios $vmName $filesystem");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    
    # Set Mem
    print("vm set_ram $vmName $mem\n");
    $t->print("vm set_ram $vmName $mem");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    if (&get_sparsemem($vmName) eq "true"){
		print("vm set_sparse_mem $vmName 1\n");
		$t->print("vm set_sparse_mem $vmName 1");
   		$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    }
    
    # Set IDLEPC
    my $idlepc = get_idle_pc_conf($vmName);
	print("vm set_idle_pc $vmName $idlepc\n");
	$t->print("vm set_idle_pc $vmName $idlepc");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    
    #Set ios ghost
    if (&get_ghost_ios($vmName) eq "true"){
    	print("vm set_ghost_status $vmName 2\n");
		$t->print("vm set_ghost_status $vmName 2");
    	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    	my $temp = basename($filesystem);
    	print("vm set_ghost_file $vmName \"$temp.image-localhost.ghost\" \n");
		$t->print("vm set_ghost_file $vmName \"$temp.image-localhost.ghost\" ");
    	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    }
    
    #Set Blk_direct_jump
	print("vm set_blk_direct_jump $vmName 0\n");
	$t->print("vm set_blk_direct_jump $vmName 0");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    
    # Add slot cards
    my @cards=&get_cards_conf($vmName);
    my $index = 0;
    foreach my $slot (@cards){
    	print("vm slot_add_binding $vmName $index 0 $slot \n");
		$t->print("vm slot_add_binding $vmName $index 0 $slot");
    	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    	$index++;
    }
    
    # Connect virtual networks to host interfaces
    $ifTagList = $virtualm->getElementsByTagName("if");
	my $numif     = $ifTagList->getLength;

	for ( my $j = 0 ; $j < $numif ; $j++ ) {
		my $ifTag = $ifTagList->item($j);
		my $name   = $ifTag->getAttribute("name");
		my ($firstpart, $secondpart)= split("/",$name,2);
		my $firstnumber = substr $firstpart,-1,1;
		my $temp = $j + 1;
		print("nio create_tap nio_tap$counter$secondpart $vmName-e$temp\n");
		$t->print("nio create_tap nio_tap$counter$secondpart $vmName-e$temp");
   		$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
   		print("vm slot_add_nio_binding $vmName $firstnumber $secondpart nio_tap$counter$secondpart\n");
   		$t->print("vm slot_add_nio_binding $vmName $firstnumber $secondpart nio_tap$counter$secondpart");
   		$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
   		$execution->execute("ifconfig $vmName-e$temp 0.0.0.0");
	}
	
	# Set config file to router
	print("vm set_config $vmName \"$filenameconf\" \n");
   	$t->print("vm set_config $vmName \"$filenameconf\" ");
   	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
   	$t->close;

    print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    
    
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
	my $vmName = shift;
	my $type   = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vmName\n" if ($exemode == $EXE_VERBOSE);
    
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm destroy $vmName");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->print("hypervisor reset");
   	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
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
	my $vmName = shift;
	my $type   = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Destroying: $vmName\n" if ($exemode == $EXE_VERBOSE);
	
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm stop $vmName");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->print("vm delete $vmName");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->print("hypervisor reset");
   	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
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
	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;
	my $doc    = shift;
#	$execution = shift;
#	$bd        = shift;
#	my $dh           = shift;
	my $sock         = shift;
	my $counter = shift;

    print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Starting router: $vmName\n" if ($exemode == $EXE_VERBOSE);
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm start $vmName");
    my $line = $t->getline; 
    print $line if ($exemode == $EXE_VERBOSE);

    # Display consoles 
	#VNX::vmAPICommon->start_consoles_from_console_file ($vmName, $dh->get_vm_dir($vmName) . "/console", $execution);
	VNX::vmAPICommon->start_consoles_from_console_file ($vmName, $dh->get_vm_dir($vmName) . "/console");

    # display console if required
#	my $parser       = new XML::DOM::Parser;
#	my $dom          = $parser->parse($doc);
#	my $display_console   = $dom->getElementsByTagName("display_console")->item(0)->getFirstChild->getData;
#	unless ($display_console eq "no") {
#		my $consoleport=&get_port_conf($vmName,$counter);
#    	$execution->execute("xterm -title Dynamips_$vmName -e 'telnet $dynamipsHost $consoleport' >/dev/null 2>&1 &");
#	}    

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
	my $vmName = shift;
	my $type   = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
	my $F_flag    = shift;
		
	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vmName\n" if ($exemode == $EXE_VERBOSE);
	    
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm stop $vmName");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->close;
	sleep(2);	
	
	#&change_vm_status( $dh, $vmName, "REMOVE" );
	&change_vm_status( $vmName, "REMOVE" );
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
	my $vmName   = shift;
	my $type     = shift;
	my $filename = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
		
	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vmName\n" if ($exemode == $EXE_VERBOSE);
    
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm extract_config $vmName");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    $t->close;
	
}
#
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
	my $vmName   = shift;
	my $type     = shift;
	my $filename = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Rebooting router: $vmName\n" if ($exemode == $EXE_VERBOSE);

    sleep(2);
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm stop $vmName");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    sleep(2);
    $t->print("vm start $vmName");
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
	my $vmName = shift;
	my $type   = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vmName\n" if ($exemode == $EXE_VERBOSE);
	
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm suspend $vmName");
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
	my $vmName = shift;
	my $type   = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vmName\n" if ($exemode == $EXE_VERBOSE);
    
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm resume $vmName");
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
	my $vmName = shift;
	my $type   = shift;

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vmName\n" if ($exemode == $EXE_VERBOSE);
	
    sleep(2);
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm stop $vmName");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    sleep(2);
    $t->print("vm start $vmName");
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
	my $vmName = shift;
	my $type   = shift;

	print "-----------------------------\n" if ($exemode == $EXE_VERBOSE);
    print "Shutdowning router: $vmName\n" if ($exemode == $EXE_VERBOSE);
	
    sleep(2);
    my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    $t->print("vm stop $vmName");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    sleep(2);
    $t->print("vm start $vmName");
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
	my $self = shift;
	my $merged_type = shift;
	my $seq  = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
	my $vm    = shift;
	my $vmName = shift;
	my @output = "Nothing to show";
	my $temp;
	my $port;
	# Recupero el puerto telnet de acceso al router
	my $consFile = $dh->get_vm_dir($vmName) . "/console";
	# Configuro el fichero de configuracion extendida
	my $dynamipsconf = $dh->get_default_dynamips();
	if (!($dynamipsconf eq "0")){
		&set_config_file($dh->get_default_dynamips());
	}
	# Get the console port from vm's console file
	open (PORT_CISCO, "< $consFile") || $execution->smartdie ("ERROR: cannot open $vmName console file ($consFile)");
	my $conData;
	if ($merged_type eq 'dynamips-7200') { # we use con2 (aux port)
		#$conData = &get_conf_value ($consFile, 'con2', $execution);
		$conData = &get_conf_value ($consFile, 'con2');
	} else { # we use con1 (console port)
		#$conData = &get_conf_value ($consFile, 'con1', $execution);			
		$conData = &get_conf_value ($consFile, 'con1');			
	}
	$conData =~ s/con.=//;  		# eliminate the "conX=" part of the line
	my @consField = split(/,/, $conData);
	$port=$consField[2];
	close (PORT_CISCO);	
	#print "** $vmName: console port = $port\n";

=BEGIN
	my @result;
	my $result;
	# Compruebo si alguna ventana con telnet a ese puerto se está ejecutando
	@result = `ps ax | grep telnet`;
	foreach $result (@result) {
		if ($result =~ m/telnet\s*localhost\s*$port/){
			# Si se esta ejecutando, es que el puerto está ocupado, por lo que se sale
			# y avisa al usuario de que cierre ese puerto.
			return "\n------\nERROR: cannot access $vmName console at port $port. Please, release the router console and try again.\n------\n";
		}
	}
=END
=cut

	# Recuperamos las sentencias de ejecucion
	my $command_list = $vm->getElementsByTagName("exec");
	my $countcommand = 0;
	for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
		# Por cada sentencia.
		my $command = $command_list->item($j);	
		# To get attributes
		my $cmd_seq_string = $command->getAttribute("seq");
		# JSF 02/12/10: we accept several commands in the same seq tag,
		# separated by spaces
		my @cmd_seqs = split(' ',$cmd_seq_string);
		foreach my $cmd_seq (@cmd_seqs) {
		
			# Se comprueba si la seq es la misma que la que te pasan a ejecutar
			if ( $cmd_seq eq $seq ) {
				my $type = $command->getAttribute("type");
				# Case 1. Verbatim type
				if ( $type eq "verbatim" ) {
					# Including command "as is"
					my $command_tag = &text_tag($command);
					# Si el primer elemento a ejecutar es un reload, no se ejecuta en el router
					# sino que:
					# 1º Se para el router
					# 2º Se introduce el nuevo fichero de configuracion (que estará como parametro de la funcion reload)
					# 3º Se vuelve a encender.
					if ($command_tag =~ m/^reload/){
						my @file_conf = split('reload ',$command_tag);
						&reload_conf ($vmName, $file_conf[1], $dynamipsHost, $dynamipsPort, $consFile);
=BEGIN						
						my $t = new Net::Telnet (Timeout => 10);
					    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
					    print("vm stop $vmName \n");
						$t->print("vm stop $vmName");
						sleep(2);
					    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
					   	print("vm set_config $vmName \"$filenameconf\" \n");
					   	$t->print("vm set_config $vmName \"$filenameconf\" ");
					   	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
					   	$t->print("vm start $vmName");
					    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
					    sleep (3);
   						#$execution->execute("xterm -title Dynamips_$vmName -e 'telnet $dynamipsHost $port' >/dev/null 2>&1 &");
   						#VNX::vmAPICommon->start_consoles_from_console_file ($vmName, $consFile, $execution);
   						VNX::vmAPICommon->start_consoles_from_console_file ($vmName, $consFile);
=END
=cut   									
					}else{
						# Command is not a 'reload', we execute it 

						# Get the user name and password. If several users are define, 
						# we just take the first one.
						my @login_users = &get_login_user($vmName);
		     			my $login_user = $login_users[0];
		 				my $user=$login_user->[0];
						my $pass=$login_user->[1];
						# Get enable password
 						my $enablepass = get_enable_pass($vmName);
						# create CiscoExeCmd object to connect to router console
						my $sess = new VNX::CiscoExeCmd ('localhost', $port, $user, $pass, $enablepass);
						# Connect to console
						my $res = $sess->open;
						if (!$res) { $execution->smartdie("ERROR: cannot connect to ${vmName}'s console at port $port.\n" .
							                              "       Please, release the router console and try again.\n"); }
						# Put router in priviledged mode
						$res = $sess->goToEnableMode;
						if ($res eq 'timeout') {
							$execution->smartdie("ERROR: timeout connecting to ${vmName}'s console at port $port.\n" .
							                     "       Please, release the router console and try again.\n"); 
						} elsif ($res eq 'invalidlogin') { 
							$execution->smartdie("ERROR: invalid login connecting to ${vmName}'s console at port $port\n") 
						}
						# execute the command
						my @output = $sess->exeCmd ($command_tag);
						print "-- cmd result: \n\n@output\n";
						$sess->exeCmd ("disable");
						$sess->exeCmd ("exit");
						$sess->close;
						
=BEGIN
						# Para que funcione correctamente se ha de hacer siempre primero esta secuencia
						# en telnet para dejarle preparado aunque esté en situacion desconocida.
						$telnet = new Net::Telnet (Timeout => 10);
   						$telnet->open(Host => '127.0.0.1', Port => $port);
    					$telnet->print("");
    					$telnet->print("");
    					$telnet->print("");
    					$telnet->print("exit");
    					$telnet->print("");
    					$telnet->print("");
    					$telnet->print("");
    					sleep(3);
    					$telnet->close;
    					# Hasta aqui es la secuencia.
    					# Se conecta a traves de un nuevo modulo perl al cisco a traves del puerto leido anterior mente
						my $session = Net::Telnet::Cisco->new(Host => $dynamipsHost, Port => $port);
						# Siempre se ejecuta este comando para que estemos en una situacion conocida.
						$session->cmd(' show version');
						# Se adquiere en pass de enable.
						# Si no tiene, esta funcion devolvera un "" que significa que no tiene pass
						# y que es admitida por el cisco si el enable no tienen password
						my $enablepass = get_enable_pass($vmName);
						if ($session->enable($enablepass)){
							# Se ejecuta el comando.
							@output = $session->cmd(" $command_tag");
							# Se sale del enable para seguridad de no poder ejecutar otro comando sin permiso
							$session->disable();
						}else {
							die ("Can't enable")
						}
						$session->close();
						# Saca por pantalla el resulŧado del comando anterior
						print "\nOutput of command \"$command_tag\" on $vmName\n";
						print "@output";
=END
=cut															
								
					}
				}
				# Case 2. File type
				# En caso de que sea un fichero, simplemente se lee el fichero
				# y se va ejecutando linea por linea.
				# En el caso de que se requiera un enable, este se tiene que poner en el fichero.
				elsif ( $type eq "file" ) {
					# We open the file and write commands line by line
					my $include_file =  &do_path_expansion( &text_tag($command) );
							
					# Get the user name and password. If several users are define, 
					# we just take the first one.
					my @login_users = &get_login_user($vmName);
	     			my $login_user = $login_users[0];
	 				my $user=$login_user->[0];
					my $pass=$login_user->[1];
					# Get enable password
					my $enablepass = get_enable_pass($vmName);
					# create CiscoExeCmd object to connect to router console
					my $sess = new VNX::CiscoExeCmd ('localhost', $port, $user, $pass, $enablepass);
					# Connect to console
					my $res = $sess->open;
					if (!$res) { $execution->smartdie("ERROR: cannot connect to ${vmName}'s console at port $port.\n" .
						                              "       Please, release the router console and try again.\n"); }
					# Put router in priviledged mode
					$res = $sess->goToEnableMode;
					if ($res eq 'timeout') {
						$execution->smartdie("ERROR: timeout connecting to ${vmName}'s console at port $port.\n" .
						                     "       Please, release the router console and try again.\n"); 
					} elsif ($res eq 'invalidlogin') { 
						$execution->smartdie("ERROR: invalid login connecting to ${vmName}'s console at port $port\n") 
					}
					# execute the file with commands 
					@output = $sess->exeCmdFile ("$include_file");
					print "-- cmd result: \n\n@output\n";
					$sess->exeCmd ("disable");
					$sess->exeCmd ("exit");
					$sess->close;
						
=BEGIN							
					open INCLUDE_FILE, "$include_file"
					  or $execution->smartdie("can not open $include_file: $!");
					  	# Secuencia para dejar el router en un estado conocido
					  	$telnet = new Net::Telnet (Timeout => 10);
   						$telnet->open(Host => '127.0.0.1', Port => $port);
    					$telnet->print("");
    					$telnet->print("");
    					$telnet->print("");
    					$telnet->print("exit");
    					$telnet->print("");
    					$telnet->print("");
    					$telnet->print("");
    					sleep(3);
    					$telnet->close;
    					# Fin de la secuencia
						my $session = Net::Telnet::Cisco->new(Host => $dynamipsHost, Port => $port);
						# Comando para dejartlo en estado conocido.
						$session->cmd(' show version');
						print "\nExecution: Command --> Output\n";
						while (<INCLUDE_FILE>) {
							# Se van ejecutando linea por linea
							chomp;
							$command_tag = $_;
							@output = $session->cmd(" $command_tag");
							print "$command_tag --> @output\n";
						}
    					$session->cmd(" end");
    					# Cuando se acaba, se hace un disable para mayor seguridad.
						$session->disable();
						$session->close();
						close INCLUDE_FILE;
=END
=cut

				}
	
			# Other case. Don't do anything (it would be and error in the XML!)
			}
		}
	}	
}

## INTERNAL USE ##

sub reload_conf {
	my $vmName    = shift;
	my $confFile = shift;
	my $dynamipsHost = shift;
	my $dynamipsPort = shift;
	my $consFile = shift;
	
	unless (-e $confFile) {	$execution->smartdie ("router $vmName configuration file not found ($confFile)") } 
	my $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $dynamipsHost, Port => $dynamipsPort);
    print("vm stop $vmName \n");
	$t->print("vm stop $vmName");
    my $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
   	print("vm set_config $vmName \"$confFile\" \n");
   	$t->print("vm set_config $vmName \"$confFile\" ");
   	$line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
   	$t->print("vm start $vmName");
    $line = $t->getline; print $line if ($exemode == $EXE_VERBOSE);
    sleep (3);    
	VNX::vmAPICommon->start_consoles_from_console_file ($vmName, $consFile);
}



# Recibe un fichero o directorio y devuelve el path absoluto si es que no lo es en un principio
sub get_absolute_file{
	my $tempconf = shift;
	# Comprueba si es una variable global o no
	if (!($tempconf =~ m/^\/((\w|\.|-)+\/)*(\w|\.|-)+$/)){
		return( $dh->get_xml_dir() . $tempconf);
	}
	return $tempconf;
}

sub set_config_file{
	my $tempconf = shift;
	# Comprueba si es una variable global o no
	if (!($tempconf =~ m/^\/((\w|\.|-)+\/)*(\w|\.|-)+$/)){
		$tempconf = $dh->get_xml_dir() . $tempconf;
	}
	# Comprueba que exista el fichero
	if (-e $tempconf){
		$conf_file = $tempconf;;
		open CONF_EXT_FILE, "$conf_file";
   			my @conf_file_array = <CONF_EXT_FILE>;
   			my $conf_file_string = join("",@conf_file_array);
   		close CONF_EXT_FILE;
		my $schemalocation;

#jsf	if ($input_file_string =~ /="(.*).xsd"/) {
	    if ($conf_file_string =~ /="(\S*).xsd"/) {
        	$schemalocation = $1 .".xsd";
		}else{
			print "input_file_string = $conf_file_string, $schemalocation=schemalocation\n" if ($exemode == $EXE_VERBOSE);
			$execution->smartdie("XSD not found");
		}
		if (!(-e $schemalocation)){
			$execution->smartdie("$schemalocation not found");
		}
		# Valida el XML contra el Schema
        my $schema = XML::LibXML::Schema->new(location => $schemalocation);
		
		
		my $parser = XML::LibXML->new;
		#$doc    = $parser->parse_file($document);
		my $doc = $parser->parse_file($conf_file);
		
		eval { $schema->validate($doc) };
	
		if ($@) {
		  # Validation errors
		  $execution->smartdie("$conf_file is not a well-formed VNX file");
		}
		return 0;	
	}else
	{
		$execution->smartdie("$conf_file not found");
	}
}

# Devuelve en un array de dos columnas, los valores dados en la etiqueta login del XML
# Por defecto (si no existe) no devuelve usuarios.
sub get_login_user {
	my $vmName = shift;
	my @users;
	
	# Si no hay fichero, se pone el valor por defecto de ""
	unless(-e $conf_file){
		push(@users,["",""]);
		return @users;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
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

		if ( $name eq $vmName ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vmName){
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

	my $vmName = shift;
	my $result = "";

	unless(-e $conf_file){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
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

		if ( $name eq $vmName ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vmName){
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

# Devuelve el valor de la etiqueta sparsemem
# Si no se define, devuelve un valor true.
sub get_sparsemem {
	my $vmName = shift;
	my $result = "true";
	
	unless(-e $conf_file){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
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

		if ( $name eq $vmName ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vmName){
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
	my $vmName = shift;
	my $result = "false";
	
	unless(-e $conf_file){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
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

		if ( $name eq $vmName ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vmName){
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
	my $vmName = shift;
	# Valor por defecto en caso de no encontrarse definicion en el fichero de configuarcion
	# extendida
	my $result = "c3640";
	
	unless(-e $conf_file){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
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

		if ( $name eq $vmName ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vmName){
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

#################################################################
# get_conf_file													#
# 																#
# Saca del fichero de configuración extendida, el fichero		#
# 
# Entrada:														#
# 	Nombre del router virtual									#
# Salida:														#
# 	Nombre del chasis a utilizar, si no está definido se utiliza#
#   el de por defecto, que es "c3640"							# 
#################################################################
sub get_conf_file {
	my $vmName = shift;
	my $result = "0";
	
	unless(-e $conf_file){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
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

		if ( $name eq $vmName ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vmName){
		my $conf_list = $virtualm->getElementsByTagName("conf");
		if ($conf_list->getLength gt 0){
			my $conftag = $conf_list->item(0);
			$result = &text_tag($conftag);
			$global_tag = 0;
		}
	}
 	return $result;
}


# Returns dynamips port from /etc/vnx.conf file
# If not defined, 7200 is used by default
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

# Devuelve el valor de la etiqueta idle_pc
# Si no se define, devuelve un valor 0x604f8104.
sub get_idle_pc_conf {
	my $vmName = shift;
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


sub get_port_conf {
	my $vmName = shift;
	my $counter = shift;
	my $result =  900 + $counter;
	
	unless(-e $conf_file){
		return $result;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
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

		if ( $name eq $vmName ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vmName){
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
	my $vmName = shift;
	my @slotarray;
	
	# Si no hay fichero, se pone el valor por defecto de "NM-4E"
	unless(-e $conf_file){
		push(@slotarray,"NM-4E");
		return @slotarray;
	}
	# Parseamos el fichero.
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
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

		if ( $name eq $vmName ) {
			last;
		}
 	}
 	# Comprobamos que la maquina es la correcta
	if($name eq $vmName){
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



1;
