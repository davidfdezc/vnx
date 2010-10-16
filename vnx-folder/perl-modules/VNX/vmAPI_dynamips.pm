# vmAPI_libvirt.pm
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
  createVM
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
  

use VNX::Execution;
use VNX::BinariesData;
use VNX::Arguments;
use VNX::CheckSemantics;
use VNX::TextManipulation;
use VNX::NetChecks;
use VNX::FileChecks;
use VNX::DocumentChecks;
use VNX::IPChecks;
use Net::Telnet;
use Net::IP;
use Net::Telnet::Cisco;
use File::Basename;

my $execution;    # the VNX::Execution object
my $dh;           # the VNX::DataHandler object
my $bd;           # the VNX::BinariesData object


# Name of UML whose boot process has started but not reached the init program
# (for emergency cleanup).  If the mconsole socket has successfully been initialized
# on the UML then '#' is appended.
my $curr_uml;
my $F_flag;       # passed from createVM to halt
my $M_flag;       # passed from createVM to halt
#


my $HHOST="localhost";
my $HPORT="7300";
my $HIDLEPC="0x604f8104";
my $conf_file;

#
#
#
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
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	my $sock    = shift;
	my $counter = shift;
	$curr_uml = $vmName;
	
	my $doc2       = $dh->get_doc;
	my @vm_ordered = $dh->get_vm_ordered;

	my $path;
	my $filesystem;
	
	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {

		my $vm = $vm_ordered[$i];

		# We get name attribute
		my $name = $vm->getAttribute("name");

		unless ( $name eq $vmName ) {
			next;
		}
	}
	# Configuramos el fichero de configuracion especial
	&set_config_file($dh->get_default_dynamips());
		
	my $filenameconf;
	my $ifTagList;
	
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parse($doc);
	my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
	my $virtualm     = $virtualmList->item($0);
	
	my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
	my $filesystemTag     = $filesystemTagList->item($0);
	my $filesystem_type   = $filesystemTag->getAttribute("type");
	my $filesystem        = $filesystemTag->getFirstChild->getData;
	
	# Definicion del fichero host
	my $conf_dynamips = get_conf_file($vmName);
	
#	my $conf_dynamipsTagList = $virtualm->getElementsByTagName("dynamips");
#	if ( $conf_dynamipsTagList->getLength gt 0){
#		my $conf_dynamipsTag     = $conf_dynamipsTagList->item($0);
#		my $conf_dynamips        = $conf_dynamipsTag->getFirstChild->getData;
	
	if (!($conf_dynamips eq 0))
	{
	 	if (-e $conf_dynamips)
		{ 
			$execution->execute("cp " . $conf_dynamips . " " . $dh->get_vm_dir($vmName));
	   	 	$filenameconf  = $dh->get_vm_dir($vmName) . "/" . basename($conf_dynamips) ;
		}else{
			$execution->smartdie("Can not open " . $conf_dynamips );
		}
	}
	else{
		$filenameconf = $dh->get_vm_dir($vmName) . "/" . $vmName . ".conf";
		open (CONF_CISCO, ">$filenameconf") || die "ERROR: No puedo abrir el fichero $filenameconf";;
		print CONF_CISCO "hostname " . $vmName ."\n";
 		$ifTagList = $virtualm->getElementsByTagName("if");
 		my $numif = $ifTagList->getLength;
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
			
			my $ipv4_list = $ifTag->getElementsByTagName("ipv4");
			if ( $ipv4_list->getLength != 0 ) {
				my $ipv4_Tag = $ipv4_list->item(0);
				my $ipv4 =  $ipv4_Tag->getFirstChild->getData;
				my $subnetv4 = $ipv4_Tag->getAttribute("mask");
				print CONF_CISCO " ip address " . $ipv4 . " ". $subnetv4 . "\n";	
			}
			my $ipv6_list = $ifTag->getElementsByTagName("ipv6");
			if ( $ipv6_list->getLength != 0 ) {
				print CONF_CISCO " ipv6 enable\n";	
				my $ipv6_Tag = $ipv6_list->item(0);
				my $ipv6 =  $ipv6_Tag->getFirstChild->getData;
				print CONF_CISCO " ipv6 address " . $ipv6 . " ". $subnetv6 . "\n";	
			}
			print CONF_CISCO " no shutdown\n";		
 		}
 		
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
 				my $ip = new Net::IP ($destination) or die (Net::IP::Error());
 				$maskdestination = $ip->mask();
 				$destination = $ip->ip();
 			}
 			print CONF_CISCO "ip route ". $destination . " " . $maskdestination . " " . $gw . "\n";	
 			
 		}
 		close(CONF_CISCO);	
	}
    
    # Preparar las variables
    my $memTagList = $virtualm->getElementsByTagName("mem");
    my $mem = "96";

	if ( $memTagList->getLength != 0 ) {
		my $memTag     = $memTagList->item($0);
		$mem   = ($memTag->getFirstChild->getData)/1024;
	} 
   my $doc = $dh->get_doc;
   my $dynamips_ext_list = $doc->getElementsByTagName("dynamips_ext");

    
    # Definicion del router


    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    # Si es la primera vez que se ejecuta el escenario, se borra todo el hypervisor
    # Precacion, tambien se borra otros escenarios que este corriendo paralelamente
    if ($counter == 0)
    {
    	print "-----------------------------\n";
    	print "Reset hypervisor:\n";
    	$t->print("hypervisor reset");
   		$line = $t->getline; print $line;
    	$t->close;
    	print "-----------------------------\n";
    }
    
	
	
	#my $consoleportbase = "900";
	#my $consoleport = $consoleportbase + $counter;

    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    print("hypervisor version\n");
    $t->print("hypervisor version");
    $line = $t->getline; print $line;
    print("hypervisor working_dir \"". $dh->get_fs_dir($vmName)."\" \n");
    $t->print("hypervisor working_dir \"". $dh->get_fs_dir($vmName). "\" ");
    $line = $t->getline; print $line;
	
	
	# Set type
	my($trash,$model)=split(/-/,$type,2);
#    print("vm create $vmName 0 c3600\n");
#	$t->print("vm create $vmName 0 c3600");
#	$line = $t->getline; print $line;
    print("vm create $vmName 0 c$model\n");
	$t->print("vm create $vmName 0 c$model");
	$line = $t->getline; print $line;
	
	# Configuring telnet port

	my $consoleport = &get_port_conf($vmName,$counter);
	my $portfile = $dh->get_vm_dir($vmName) . "/port.txt";
	open (PORT_CISCO, ">$portfile") || die "ERROR: No puedo abrir el fichero $portfile";;
	print PORT_CISCO $consoleport ;	
	close (PORT_CISCO);
	print("vm set_con_tcp_port $vmName $consoleport\n");
	$t->print("vm set_con_tcp_port $vmName $consoleport");
    $line = $t->getline; print $line;
    
    # Set Chassis
    my $chassis = &get_chassis($vmName);
    $chassis =~ s/c//;
#    print("c3600 set_chassis $vmName $chassis\n");
#    $t->print("c3600 set_chassis $vmName $chassis");
#    $line = $t->getline; print $line;
    print("c$model set_chassis $vmName $chassis\n");
    $t->print("c$model set_chassis $vmName $chassis");
    $line = $t->getline; print $line;
    
	# Set Filesystem
    print("vm set_ios $vmName $filesystem\n");
    $t->print("vm set_ios $vmName $filesystem");
    $line = $t->getline; print $line;
    
    # Set Mem
    print("vm set_ram $vmName $mem\n");
    $t->print("vm set_ram $vmName $mem");
    $line = $t->getline; print $line;
    if (&get_sparsemem($vmName) eq "true"){
		print("vm set_sparse_mem $vmName 1\n");
		$t->print("vm set_sparse_mem $vmName 1");
   		$line = $t->getline; print $line;
    }
    
    # Set IDLEPC
    my $idlepc = get_idle_pc_conf($vmName);
	print("vm set_idle_pc $vmName $idlepc\n");
	$t->print("vm set_idle_pc $vmName $idlepc");
    $line = $t->getline; print $line;
    
    #Set ios ghost
    if (&get_ghost_ios($vmName) eq "true"){
    	print("vm set_ghost_status $vmName 2\n");
		$t->print("vm set_ghost_status $vmName 2");
    	$line = $t->getline; print $line;
    	my $temp = basename($filesystem);
    	print("vm set_ghost_file $vmName \"$temp.image-localhost.ghost\" \n");
		$t->print("vm set_ghost_file $vmName \"$temp.image-localhost.ghost\" ");
    	$line = $t->getline; print $line;
    }
    
    #Set Blk_direct_jump
	print("vm set_blk_direct_jump $vmName 0\n");
	$t->print("vm set_blk_direct_jump $vmName 0");
    $line = $t->getline; print $line;
    
    # Add slot cards
    my @cards=&get_cards_conf($vmName);
    my $index = 0;
    foreach $slot (@cards){
    	print("vm slot_add_binding $vmName $index 0 $slot \n");
		$t->print("vm slot_add_binding $vmName $index 0 $slot");
    	$line = $t->getline; print $line;
    	$index++;
    }
    
    # Connect virtual networks to host interfaces
    $ifTagList = $virtualm->getElementsByTagName("if");
	my $numif     = $ifTagList->getLength;

	for ( my $j = 0 ; $j < $numif ; $j++ ) {
		my $temp = $j + 1;
		print("nio create_tap nio_tap$counter$j $vmName-e$temp\n");
		$t->print("nio create_tap nio_tap$counter$j $vmName-e$temp");
   		$line = $t->getline; print $line;
   		print("vm slot_add_nio_binding $vmName 0 $j nio_tap$counter$j\n");
   		$t->print("vm slot_add_nio_binding $vmName 0 $j nio_tap$counter$j");
   		$line = $t->getline; print $line;
   		$execution->execute("ifconfig $vmName-e$temp 0.0.0.0");
	}
	
	# Set config file to router
	print("vm set_config $vmName \"$filenameconf\" \n");
   	$t->print("vm set_config $vmName \"$filenameconf\" ");
   	$line = $t->getline; print $line;
   	$t->close;

    print "-----------------------------\n";
    
  
    
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
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	$F_flag    = shift;
		print "-----------------------------\n";
    print "Shutdowning router: $vmName\n";
	

	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm destroy $vmName");
    $line = $t->getline; print $line;
    $t->close;
}

#
####################################################################
##                                                                 #
##   createVM                                                      #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub createVM{
	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;
	my $doc    = shift;
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	my $sock    = shift;
	my $counter = shift;
	$curr_uml = $vmName;
	
	my $doc2       = $dh->get_doc;
	my @vm_ordered = $dh->get_vm_ordered;

	my $path;
	my $filesystem;
	
	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {

		my $vm = $vm_ordered[$i];

		# We get name attribute
		my $name = $vm->getAttribute("name");

		unless ( $name eq $vmName ) {
			next;
		}
	}

	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parse($doc);
	my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
	my $virtualm     = $virtualmList->item($0);
	
	my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
	my $filesystemTag     = $filesystemTagList->item($0);
	my $filesystem_type   = $filesystemTag->getAttribute("type");
	my $filesystem        = $filesystemTag->getFirstChild->getData;
	
	
	my $conf_dynamipsTagList = $virtualm->getElementsByTagName("conf_dynamips");
	my $conf_dynamipsTag     = $conf_dynamipsTagList->item($0);
	my $conf_dynamips        = $conf_dynamipsTag->getFirstChild->getData;
		
		
	$HIDLEPC="0x604f8104";
	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    print "-----------------------------\n";
    print "Reset hypervisor:\n";
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    if ($counter == 0)
    {
    	$t->print("hypervisor reset");
   		$line = $t->getline; print $line;
    	$t->close;
    	print "-----------------------------\n";
    }
    

	my $consoleportbase = "900";
	my $consoleport = $consoleportbase + $counter;
	$ram = "96";

    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    print("hypervisor version\n");
    $t->print("hypervisor version");
    $line = $t->getline; print $line;
    print("hypervisor working_dir \"". $dh->get_fs_dir($vmName)."\" \n");
    $t->print("hypervisor working_dir \"". $dh->get_fs_dir($vmName). "\" ");
    $line = $t->getline; print $line;
    print("vm create $vmName 0 c3600\n");
    $t->print("vm create $vmName 0 c3600");
    $line = $t->getline; print $line;
    print("vm set_con_tcp_port $vmName $consoleport\n");
    $t->print("vm set_con_tcp_port $vmName $consoleport");
    $line = $t->getline; print $line;
    print("c3600 set_chassis $vmName 3640\n");
    $t->print("c3600 set_chassis $vmName 3640");
    $line = $t->getline; print $line;
    #$t->print("vm set_ios $rname $RIOSFILE");
    print("vm set_ios $vmName $filesystem\n");
    $t->print("vm set_ios $vmName $filesystem");
    $line = $t->getline; print $line;
    print("vm set_ram $vmName $ram\n");
    $t->print("vm set_ram $vmName $ram");
    $line = $t->getline; print $line;
	print("vm set_sparse_mem $vmName 1\n");
	$t->print("vm set_sparse_mem $vmName 1");
    $line = $t->getline; print $line;
	print("vm set_idle_pc $vmName $HIDLEPC\n");
	$t->print("vm set_idle_pc $vmName $HIDLEPC");
    $line = $t->getline; print $line;
	print("vm set_blk_direct_jump $vmName 0\n");
	$t->print("vm set_blk_direct_jump $vmName 0");
    $line = $t->getline; print $line;
	print("vm slot_add_binding $vmName 0 0 NM-4E\n");
	$t->print("vm slot_add_binding $vmName 0 0 NM-4E");
    $line = $t->getline; print $line;
	#print("vm slot_add_binding $vmName 1 0 NM-4T");
	#$t->print("vm slot_add_binding $vmName 1 0 NM-4T");
    #$line = $t->getline; print $line;
    my $ifTagList = $virtualm->getElementsByTagName("if");
	my $numif     = $ifTagList->getLength;

	for ( my $j = 0 ; $j < $numif ; $j++ ) {
		my $temp = $j + 1;
		print("nio create_tap nio_tap$counter$j $vmName-e$temp\n");
		$t->print("nio create_tap nio_tap$counter$j $vmName-e$temp");
   		$line = $t->getline; print $line;
   		print("vm slot_add_nio_binding $vmName 0 $j nio_tap$counter$j\n");
   		$t->print("vm slot_add_nio_binding $vmName 0 $j nio_tap$counter$j");
   		$line = $t->getline; print $line;
   		$execution->execute("ifconfig $vmName-e$temp 0.0.0.0");
	}
	print("vm set_config $vmName \"$conf_dynamips\" \n");
    $t->print("vm set_config $vmName \"$conf_dynamips\" ");
    $line = $t->getline; print $line;


    print "-----------------------------\n";
    print "-----------------------------\n";
    print "Starting router: $vmName\n";
    $t->print("vm start $vmName");
    $line = $t->getline; print $line;
	
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
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	$F_flag    = shift;
	    print "-----------------------------\n";
    print "Destroying: $vmName\n";
	
	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm stop $vmName");
    $line = $t->getline; print $line;
    $t->print("vm delete $vmName");
    $line = $t->getline; print $line;
    #$t->print("hypervisor reset");
    #$line = $t->getline; print $line;
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
	#$rname = "r11";
	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;
	my $doc    = shift;
	$execution = shift;
	$bd        = shift;
	my $dh           = shift;
	my $sock         = shift;
	my $counter = shift;
	
    print "-----------------------------\n";
    print "Starting router: $vmName\n";
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm start $vmName");
    $line = $t->getline; print $line;
    
#    my $ifTagList = $virtualm->getElementsByTagName("if");
#	my $numif     = $ifTagList->getLength;
#
#	for ( my $j = 0 ; $j < $numif ; $j++ ) {
##			my $ifTag = $ifTagList->item($j);
##			my $id    = $ifTag->getAttribute("id");
#			my $net   = $ifTag->getAttribute("net");
##			my $mac   = $ifTag->getAttribute("mac");
##
##			my $interface_tag = $init_xml->createElement('interface');
##			$devices_tag->addChild($interface_tag);
##			$interface_tag->addChild(
##				$init_xml->createAttribute( type => 'bridge' ) );
##			$interface_tag->addChild(
##				$init_xml->createAttribute( name => "eth" . $id ) );
##			$interface_tag->addChild(
##				$init_xml->createAttribute( onboot => "yes" ) );
##			my $source_tag = $init_xml->createElement('source');
##			$interface_tag->addChild($source_tag);
##			$source_tag->addChild(
##				$init_xml->createAttribute( bridge => $net ) );
##			my $mac_tag = $init_xml->createElement('mac');
##			$interface_tag->addChild($mac_tag);
##			$mac =~ s/,//;
##			$mac_tag->addChild( $init_xml->createAttribute( address => $mac ) );
#			$execution->execute("ifconfig $vmName-$j up");
#			$execution->execute("brctl addif $net $vmName-$j");
#			#$t->print("nio create_tap nio_tap $j $vmName-$j");
#    		#$line = $t->getline; print $line;
#    		#$t->print("vm slot_add_nio_binding $vmName 0 $j nio_tap $j");
#    		#$line = $t->getline; print $line;
#	
#		}
#    
    
	my $consoleport=&get_port_conf($vmName,$counter);
    
    $execution->execute("gnome-terminal -t $vmName -e 'telnet $HHOST $consoleport' >/dev/null 2>&1 &");
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
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	$F_flag    = shift;
		print "-----------------------------\n";
    print "Shutdowning router: $vmName\n";
	

	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm stop $vmName");
    $line = $t->getline; print $line;
    $t->close;

	
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
		my $self   = shift;
	my $vmName = shift;
	my $type   = shift;
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	$F_flag    = shift;
		print "-----------------------------\n";
    print "Shutdowning router: $vmName\n";
	

	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm extract_config $vmName");
    $line = $t->getline; print $line;
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
	
	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	$F_flag    = shift;
		print "-----------------------------\n";
    print "Shutdowning router: $vmName\n";
	

	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm stop $vmName");
    $line = $t->getline; print $line;
    $t->print("vm start $vmName");
    $line = $t->getline; print $line;
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
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	$F_flag    = shift;
		print "-----------------------------\n";
    print "Shutdowning router: $vmName\n";
	

	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm suspend $vmName");
    $line = $t->getline; print $line;
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
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	$F_flag    = shift;
		print "-----------------------------\n";
    print "Shutdowning router: $vmName\n";
	

	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm resume $vmName");
    $line = $t->getline; print $line;
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
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	$F_flag    = shift;
		print "-----------------------------\n";
    print "Shutdowning router: $vmName\n";
	

	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm stop $vmName");
    $line = $t->getline; print $line;
    $t->print("vm start $vmName");
    $line = $t->getline; print $line;
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
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	$F_flag    = shift;
		print "-----------------------------\n";
    print "Shutdowning router: $vmName\n";
	

	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm stop $vmName");
    $line = $t->getline; print $line;
    $t->print("vm start $vmName");
    $line = $t->getline; print $line;
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
	$execution = shift;
	$bd        = shift;
	$dh        = shift;
	my $vm    = shift;
	my $name = shift;
	
	my $session = Net::Telnet::Cisco->new(Host => '127.0.0.1',
										  Port => '900');
	my @output = $session->cmd('show version');
	
	
}


## INTERNAL USE ##
sub set_config_file{
	my $tempconf = shift;
	if (-e $tempconf){
		$conf_file = $tempconf;
		return 0;	
	}else
	{
		return 1;
	}
}
sub get_sparsemem {
	my $vmName = shift;
	my $result = "false";
	
	unless(-e $conf_file){
		return $result;
	}
	
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
# 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vmName ) {
			last;
		}
 	}
	if($name eq $vmName){
		my $sparsemem_list = $virtualm->getElementsByTagName("sparsemem");
		if ($sparsemem_list->getLength gt 0){
			my $sparsemem = $sparsemem_list->item($0);
			$result = &text_tag($sparsemem);
 			$global_tag = 0;
		}
	}
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item($0);
			my $sparsemem_gl_list = $globaltag->getElementsByTagName("sparsemem");
			if ($sparsemem_gl_list->getLength gt 0){
				my $sparsemem_gl = $sparsemem_gl_list->item($0);
				$result = &text_tag($sparsemem_gl);
			}
		}	
	}
#	if (($default_tag eq 1)&&($global_tag eq 1)){
#		$result = 900 + $counter; 
#	}
 	return $result;
}

sub get_ghost_ios {
	my $vmName = shift;
	my $result = "false";
	
	unless(-e $conf_file){
		return $result;
	}
	
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
# 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vmName ) {
			last;
		}
 	}
	if($name eq $vmName){
		my $ghostios_list = $virtualm->getElementsByTagName("ghostios");
		if ($ghostios_list->getLength gt 0){
			my $ghostios = $ghostios_list->item($0);
			$result = &text_tag($ghostios);
 			$global_tag = 0;
		}
	}
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item($0);
			my $ghostios_gl_list = $globaltag->getElementsByTagName("ghostios");
			if ($ghostios_gl_list->getLength gt 0){
				my $ghostios_gl = $ghostios_gl_list->item($0);
				$result = &text_tag($ghostios_gl);
			}
		}	
	}
#	if (($default_tag eq 1)&&($global_tag eq 1)){
#		$result = 900 + $counter; 
#	}
 	return $result;
}

sub get_chassis {
	my $vmName = shift;
	my $result = "c3640";
	
	unless(-e $conf_file){
		return $result;
	}
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vmName ) {
			last;
		}
 	}
	if($name eq $vmName){
		my $hw_list = $virtualm->getElementsByTagName("hw");
		if ($hw_list->getLength gt 0){
			my $hw = $hw_list->item($0);
			my $chassis_list = $hw->getElementsByTagName("chassis");
	 		if($chassis_list->getLength gt 0){
	 			my $chassisTag = $chassis_list->item($0);
	 			$result = &text_tag($chassisTag);
	 			$global_tag = 0;
	 		}
		}
	}
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item($0);
			my $hw_gl_list = $globaltag->getElementsByTagName("hw");
			if ($hw_gl_list->getLength gt 0){
				my $hw_gl = $hw_gl_list->item($0);
				my $chassis_gl_list = $hw_gl->getElementsByTagName("chassis");
	 			if($chassis_gl_list->getLength gt 0){
	 				my $chassisTag = $chassis_gl_list->item($0);
	 				$result = &text_tag($chassisTag);
	 			}
			}
		}	
	}
 	return $result;
}

sub get_conf_file {
	my $vmName = shift;
	my $result = "0";
	
	unless(-e $conf_file){
		return $result;
	}
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vmName ) {
			last;
		}
 	}
	if($name eq $vmName){
		my $conf_list = $virtualm->getElementsByTagName("conf");
		if ($conf_list->getLength gt 0){
			my $conftag = $conf_list->item($0);
			$result = &text_tag($conftag);
			$global_tag = 0;
		}
	}
	#if (($default_tag eq 1)&&($global_tag eq 1)){
	#	$result = "0x604f8104";
	#}
 	return $result;
}
sub get_idle_pc_conf {
	my $vmName = shift;
	my $result = "0x604f8104";
	
	unless(-e $conf_file){
		return $result;
	}
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vmName ) {
			last;
		}
 	}
	if($name eq $vmName){
		my $hw_list = $virtualm->getElementsByTagName("hw");
		if ($hw_list->getLength gt 0){
			my $hw = $hw_list->item($0);
			my $idle_pc_list = $hw->getElementsByTagName("idle_pc");
	 		if($idle_pc_list->getLength gt 0){
	 			my $idle_pcTag = $idle_pc_list->item($0);
	 			$result = $idle_pcTag->getAttribute("value");
	 			$global_tag = 0;
	 		}
		}
	}
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item($0);
			my $hw_gl_list = $globaltag->getElementsByTagName("hw");
			if ($hw_gl_list->getLength gt 0){
				my $hw_gl = $hw_gl_list->item($0);
				my $idle_pc_gl_list = $hw_gl->getElementsByTagName("idle_pc");
	 			if($idle_pc_gl_list->getLength gt 0){
	 				$result = $idle_pc_gl_Tag->getAttribute("value");
	 			}
			}
		}	
	}
	#if (($default_tag eq 1)&&($global_tag eq 1)){
	#	$result = "0x604f8104";
	#}
 	return $result;
}


sub get_port_conf {
	my $vmName = shift;
	my $counter = shift;
	my $result =  900 + $counter;
	
	unless(-e $conf_file){
		return $result;
	}
	
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vmName ) {
			last;
		}
 	}
	if($name eq $vmName){
		my $hw_list = $virtualm->getElementsByTagName("hw");
		if ($hw_list->getLength gt 0){
			my $hw = $hw_list->item($0);
			my $console_list = $hw->getElementsByTagName("console");
	 		if($console_list->getLength gt 0){
	 			my $consoleTag = $console_list->item($0);
	 			$result = $consoleTag->getAttribute("port");
	 			$global_tag = 0;
	 		}
		}
	}
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item($0);
			my $hw_gl_list = $globaltag->getElementsByTagName("hw");
			if ($hw_gl_list->getLength gt 0){
				my $hw_gl = $hw_gl_list->item($0);
				my $console_gl_list = $hw_gl->getElementsByTagName("console_base");
	 			if($console_gl_list->getLength gt 0){
	 				my $console_gl_Tag = $console_gl_list->item($0);
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

sub get_cards_conf {
	my $vmName = shift;
	my @slotarray;
	
	unless(-e $conf_file){
		push(@slotarray,"NM-4E");
		return @slotarray;
	}
	
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($conf_file);
	my $globalNode   = $dom->getElementsByTagName("vnx_dynamips")->item(0);
	my $virtualmList = $globalNode->getElementsByTagName("vm");
		
 	my $numsvm = $virtualmList->getLength;
 	my $name;
 	my $virtualm;
 	my $default_tag = 1;
 	my $global_tag = 1;
 	for ( my $j = 0 ; $j < $numsvm ; $j++ ) {
 		# We get name attribute
 		$virtualm = $virtualmList->item($j);
		$name = $virtualm->getAttribute("name");

		if ( $name eq $vmName ) {
			last;
		}
 	}
	if($name eq $vmName){
		my $hw_list = $virtualm->getElementsByTagName("hw");
		if ($hw_list->getLength gt 0){
			my $hw = $hw_list->item($0);
			my $slot_list = $hw->getElementsByTagName("slot");
	 		my $numslot = $slot_list->getLength;
	 		for ( my $j = 0 ; $j < $numslot ; $j++ ) {
	 			my $slotTag = $slot_list->item($j);
				my $slot = &text_tag($slotTag);
				push(@slotarray,$slot);
				$global_tag = 0;
	 		}
		}
	}
	
	if ($global_tag eq 1){
		my $globalList = $globalNode->getElementsByTagName("global");
		if ($globalList->getLength gt 0){
			my $globaltag = $globalList->item($0);
			my $hw_gl_list = $globaltag->getElementsByTagName("hw");
			if ($hw_gl_list->getLength gt 0){
				my $hw_gl = $hw_gl_list->item($0);
				my $slot_gl_list = $hw_gl->getElementsByTagName("slot");
	 			my $numslotgl = $slot_gl_list->getLength;
	 			for ( my $j = 0 ; $j < $numslotgl ; $j++ ) {
	 				my $slotTaggl = $slot_gl_list->item($j);
					my $slot_gl = &text_tag($slotTaggl);
					push(@slotarray,$slot_gl);
					$default_tag = 0;
	 			}
			}
		}	
	}
	# Diferente al ser un array y no poder asignarle un valor por defecto al principio
	if (($global_tag eq 1 )&&($default_tag eq 1)){
		push(@slotarray,"NM-4E");
	}
 	return @slotarray;
}

1;