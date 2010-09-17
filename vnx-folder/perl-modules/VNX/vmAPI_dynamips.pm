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
  

##use strict;
#
#use Sys::Virt;
#use Sys::Virt::Domain;
#
##de vnumlparser
#use VNX::DataHandler;
#
#use VNX::Execution;
#use VNX::BinariesData;
#use VNX::Arguments;
#use VNX::CheckSemantics;
#use VNX::TextManipulation;
#use VNX::NetChecks;
#use VNX::FileChecks;
#use VNX::DocumentChecks;
#use VNX::IPChecks;

use Net::Telnet;

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
##needed for UML_bootfile
#use File::Basename;
#
#use XML::DOM;
#
##use XML::LibXML;
##use XML::DOM::ValParser;
#
#
#use IO::Socket::UNIX qw( SOCK_STREAM );
#
## Global objects
#
#my $execution;    # the VNX::Execution object
#my $dh;           # the VNX::DataHandler object
#my $bd;           # the VNX::BinariesData object
#
#
## Name of UML whose boot process has started but not reached the init program
## (for emergency cleanup).  If the mconsole socket has successfully been initialized
## on the UML then '#' is appended.
#my $curr_uml;
#my $F_flag;       # passed from createVM to halt
#my $M_flag;       # passed from createVM to halt
#
#
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
	#		$filesystem_small = $dh->get_fs_dir($vmName) . "/opt_fs.iso";
	#	open CONFILE, ">$path" . "vnxboot"
	#	  or $execution->smartdie("can not open ${path}vnxboot: $!")
	#	  unless ( $execution->get_exe_mode() == EXE_DEBUG );

		#$execution->execute($doc ,*CONFILE);
	#	print CONFILE "$doc\n";

#		close CONFILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
#		$execution->execute( $bd->get_binaries_path_ref->{"mkisofs"} . " -l -R -quiet -o $filesystem_small $path" );
#		$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -rf $path" );

		my $parser       = new XML::DOM::Parser;
		my $dom          = $parser->parse($doc);
		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
		my $virtualmList = $globalNode->getElementsByTagName("vm");
		my $virtualm     = $virtualmList->item($0);

		my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
		my $filesystemTag     = $filesystemTagList->item($0);
		my $filesystem_type   = $filesystemTag->getAttribute("type");
		my $filesystem        = $filesystemTag->getFirstChild->getData;
		
		my $dynamips_portList = $virtualm->getElementsByTagName("dynamips_port");
		my $dynamips_portTag = $dynamips_portList->item($0);
		my $dynamips_port = $dynamips_portTag->getFirstChild->getData;
		
	$HHOST="localhost";
	$HPORT="7300";
	$HIDLEPC="0x604f8104";
	$RIOSFILE="/usr/share/vnx/filesystems/c3640";
    print "-----------------------------\n";
    print "Reset hypervisor:\n";
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("hypervisor reset");
    $line = $t->getline; print $line;
    $t->close;
    print "-----------------------------\n";
    
    #$rname = $_[0];
	#$rconsoleport = $_[1];	
	#$ram = $_[2];
	
	$rname = "r11";
	$rconsoleport = "901";	
	$ram = "96";

    print "-----------------------------\n";
    print "Creating router: $rname\n";
    print "  console: $rconsoleport\n";
    print "  ram: $ram\n";

    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("hypervisor version");
    $line = $t->getline; print $line;
    $t->print("vm create $rname 0 c3600");
    $line = $t->getline; print $line;
    $t->print("vm set_con_tcp_port $rname $rconsoleport");
    $line = $t->getline; print $line;
    $t->print("c3600 set_chassis $rname 3640");
    $line = $t->getline; print $line;
    #$t->print("vm set_ios $rname $RIOSFILE");
    $t->print("vm set_ios $rname $filesystem");
    $line = $t->getline; print $line;
    $t->print("vm set_ram $rname $ram");
    $line = $t->getline; print $line;
	$t->print("vm set_sparse_mem $rname 1");
    $line = $t->getline; print $line;
	$t->print("vm set_idle_pc $rname $HIDLEPC");
    $line = $t->getline; print $line;
	$t->print("vm set_blk_direct_jump $rname 0");
    $line = $t->getline; print $line;
	$t->print("vm slot_add_binding $rname 0 0 NM-4E");
    $line = $t->getline; print $line;
	$t->print("vm slot_add_binding $rname 1 0 NM-4T");
    $line = $t->getline; print $line;
    $t->close;

    print "-----------------------------\n";
}
#sub defineVM {
#
##	my $self   = shift;
##	my $vmName = shift;
##	my $type   = shift;
##	my $doc    = shift;
##	$execution = shift;
##	$bd        = shift;
##	$dh        = shift;
##	my $sock    = shift;
##	my $counter = shift;
##	$curr_uml = $vmName;
##
##	my $error = 0;
##
##	my $doc2       = $dh->get_doc;
##	my @vm_ordered = $dh->get_vm_ordered;
##
##	my $path;
##	my $filesystem;
##
##	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
##
##		my $vm = $vm_ordered[$i];
##
##		# We get name attribute
##		my $name = $vm->getAttribute("name");
##
##		unless ( $name eq $vmName ) {
##			next;
##		}
##
##		# To get filesystem and type
##		my $filesystem_type;
##		my $filesystem_list = $vm->getElementsByTagName("filesystem");
##		if ( $filesystem_list->getLength == 1 ) {
##			$filesystem =
##			  &do_path_expansion(
##				&text_tag( $vm->getElementsByTagName("filesystem")->item(0) ) );
##			$filesystem_type =
##			  $vm->getElementsByTagName("filesystem")->item(0)
##			  ->getAttribute("type");
##		}
##		else {
##			$filesystem      = $dh->get_default_filesystem;
##			$filesystem_type = $dh->get_default_filesystem_type;
##		}
##
##
##		if ( $execution->get_exe_mode() != EXE_DEBUG ) {
##			my $command =
##			    $bd->get_binaries_path_ref->{"mktemp"}
##			  . " -d -p "
##			  . $dh->get_tmp_dir
##			  . " vnx_opt_fs.XXXXXX";
##			chomp( $path = `$command` );
##		}
##		else {
##			$path = $dh->get_tmp_dir . "/vnx_opt_fs.XXXXXX";
##		}
##		$path .= "/";
##
##		$filesystem = $dh->get_fs_dir($name) . "/opt_fs";
##
##		# Install global public ssh keys in the UML
##		my $global_list = $doc2->getElementsByTagName("global");
##		my $key_list = $global_list->item(0)->getElementsByTagName("ssh_key");
##
##		# If tag present, add the key
##		for ( my $j = 0 ; $j < $key_list->getLength ; $j++ ) {
##			my $keyfile =
##			  &do_path_expansion( &text_tag( $key_list->item($j) ) );
##			$execution->execute( $bd->get_binaries_path_ref->{"cat"}
##				  . " $keyfile >> $path"
##				  . "keyring_root" );
##		}
##
##		# Next install vm-specific keys and add users and groups
##		my @user_list = $dh->merge_user($vm);
##		foreach my $user (@user_list) {
##			my $username      = $user->getAttribute("username");
##			my $initial_group = $user->getAttribute("group");
##			$execution->execute( $bd->get_binaries_path_ref->{"touch"} 
##				  . " $path"
##				  . "group_$username" );
##			my $group_list = $user->getElementsByTagName("group");
##			for ( my $k = 0 ; $k < $group_list->getLength ; $k++ ) {
##				my $group = &text_tag( $group_list->item($k) );
##				if ( $group eq $initial_group ) {
##					$group = "*$group";
##				}
##				$execution->execute( $bd->get_binaries_path_ref->{"echo"}
##					  . " $group >> $path"
##					  . "group_$username" );
##			}
##			my $key_list = $user->getElementsByTagName("ssh_key");
##			for ( my $k = 0 ; $k < $key_list->getLength ; $k++ ) {
##				my $keyfile =
##				  &do_path_expansion( &text_tag( $key_list->item($k) ) );
##				$execution->execute( $bd->get_binaries_path_ref->{"cat"}
##					  . " $keyfile >> $path"
##					  . "keyring_$username" );
##			}
##		}
##	}
##
##
##	###################################################################
##	#                  defineVM for libvirt-kvm-windows               #
##	###################################################################
##	if ( $type eq "libvirt-kvm-windows" ) {
##
##		$filesystem_small = $dh->get_fs_dir($vmName) . "/opt_fs.iso";
##		open CONFILE, ">$path" . "vnxboot"
##		  or $execution->smartdie("can not open ${path}vnxboot: $!")
##		  unless ( $execution->get_exe_mode() == EXE_DEBUG );
##
##		#$execution->execute($doc ,*CONFILE);
##		print CONFILE "$doc\n";
##
##		close CONFILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
##		$execution->execute( $bd->get_binaries_path_ref->{"mkisofs"} . " -l -R -quiet -o $filesystem_small $path" );
##		$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -rf $path" );
##
##		my $parser       = new XML::DOM::Parser;
##		my $dom          = $parser->parse($doc);
##		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
##		my $virtualmList = $globalNode->getElementsByTagName("vm");
##		my $virtualm     = $virtualmList->item($0);
##
##		my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
##		my $filesystemTag     = $filesystemTagList->item($0);
##		my $filesystem_type   = $filesystemTag->getAttribute("type");
##		my $filesystem        = $filesystemTag->getFirstChild->getData;
##
##		if ( $filesystem_type eq "cow" ) {
##
##			# DFC If cow file does not exist, we create it
##			if ( !-f $dh->get_fs_dir($vmName) . "/root_cow_fs" ) {
##				$execution->execute( "qemu-img"
##					  . " create -b $filesystem -f qcow2 "
##					  . $dh->get_fs_dir($vmName)
##					  . "/root_cow_fs" );
##			}
##			$filesystem = $dh->get_fs_dir($vmName) . "/root_cow_fs";
##		}
##
##		# memory
##		my $memTagList = $virtualm->getElementsByTagName("mem");
##		my $memTag     = $memTagList->item($0);
##		my $mem        = $memTag->getFirstChild->getData;
##
##		# create XML for libvirt
##		my $init_xml;
##		$init_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
##		my $domain_tag = $init_xml->createElement('domain');
##		$init_xml->addChild($domain_tag);
##		$domain_tag->addChild( $init_xml->createAttribute( type => "kvm" ) );
##
##		my $name_tag = $init_xml->createElement('name');
##		$domain_tag->addChild($name_tag);
##
##		#name
##		$name_tag->addChild( $init_xml->createTextNode($vmName) );
##
##		my $memory_tag = $init_xml->createElement('memory');
##		$domain_tag->addChild($memory_tag);
##
##		#memory
##		$memory_tag->addChild( $init_xml->createTextNode($mem) );
##
##		my $vcpu_tag = $init_xml->createElement('vcpu');
##		$domain_tag->addChild($vcpu_tag);
##
##		#vcpu
##		$vcpu_tag->addChild( $init_xml->createTextNode("1") );
##
##		my $os_tag = $init_xml->createElement('os');
##		$domain_tag->addChild($os_tag);
##		my $type_tag = $init_xml->createElement('type');
##		$os_tag->addChild($type_tag);
##		$type_tag->addChild( $init_xml->createAttribute( arch => "i686" ) );
##		$type_tag->addChild( $init_xml->createTextNode("hvm") );
##		my $boot1_tag = $init_xml->createElement('boot');
##		$os_tag->addChild($boot1_tag);
##		$boot1_tag->addChild( $init_xml->createAttribute( dev => 'hd' ) );
##		my $boot2_tag = $init_xml->createElement('boot');
##		$os_tag->addChild($boot2_tag);
##		$boot2_tag->addChild( $init_xml->createAttribute( dev => 'cdrom' ) );
##
##		my $features_tag = $init_xml->createElement('features');
##		$domain_tag->addChild($features_tag);
##		my $pae_tag = $init_xml->createElement('pae');
##		$features_tag->addChild($pae_tag);
##		my $acpi_tag = $init_xml->createElement('acpi');
##		$features_tag->addChild($acpi_tag);
##		my $apic_tag = $init_xml->createElement('apic');
##		$features_tag->addChild($apic_tag);
##
##		my $clock_tag = $init_xml->createElement('clock');
##		$domain_tag->addChild($clock_tag);
##		$clock_tag->addChild(
##			$init_xml->createAttribute( sync => "localtime" ) );
##
##		my $devices_tag = $init_xml->createElement('devices');
##		$domain_tag->addChild($devices_tag);
##
##		my $emulator_tag = $init_xml->createElement('emulator');
##		$devices_tag->addChild($emulator_tag);
##		$emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/kvm") );
##
##		my $disk1_tag = $init_xml->createElement('disk');
##		$devices_tag->addChild($disk1_tag);
##		$disk1_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
##		$disk1_tag->addChild( $init_xml->createAttribute( device => 'disk' ) );
##		my $source1_tag = $init_xml->createElement('source');
##		$disk1_tag->addChild($source1_tag);
##		$source1_tag->addChild(
##			$init_xml->createAttribute( file => $filesystem ) );
##		my $target1_tag = $init_xml->createElement('target');
##		$disk1_tag->addChild($target1_tag);
##		$target1_tag->addChild( $init_xml->createAttribute( dev => 'hda' ) );
##
##		my $disk2_tag = $init_xml->createElement('disk');
##		$devices_tag->addChild($disk2_tag);
##		$disk2_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
##		$disk2_tag->addChild( $init_xml->createAttribute( device => 'cdrom' ) );
##		my $source2_tag = $init_xml->createElement('source');
##		$disk2_tag->addChild($source2_tag);
##		$source2_tag->addChild(
##			$init_xml->createAttribute( file => $filesystem_small ) );
##		my $target2_tag = $init_xml->createElement('target');
##		$disk2_tag->addChild($target2_tag);
##		$target2_tag->addChild( $init_xml->createAttribute( dev => 'hdb' ) );
##
##		my $ifTagList = $virtualm->getElementsByTagName("if");
##		my $numif     = $ifTagList->getLength;
##
##		for ( my $j = 0 ; $j < $numif ; $j++ ) {
##			my $ifTag = $ifTagList->item($j);
##			my $id    = $ifTag->getAttribute("id");
##			my $net   = $ifTag->getAttribute("net");
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
##
##		}
##
##		my $graphics_tag = $init_xml->createElement('graphics');
##		$devices_tag->addChild($graphics_tag);
##		$graphics_tag->addChild( $init_xml->createAttribute( type => 'vnc' ) );
### DFC		my $vnc_port;
###		for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
###			my $vm = $vm_ordered[$i];
###
###			# To get name attribute
###			my $name = $vm->getAttribute("name");
###			if ( $vmName eq $name ) {
###				$vnc_port = $vm_vnc_port{$name} = 6900 + $i;
###			}
###		}
###		$graphics_tag->addChild(
###			$init_xml->createAttribute( port => $vnc_port ) );
##
##		#[JSF] host ip left
##		$graphics_tag->addChild(
##			$init_xml->createAttribute( listen => $ip_host ) );
##
##		my $serial_tag = $init_xml->createElement('serial');
##		$serial_tag->addChild( $init_xml->createAttribute( type => 'unix' ) );
##		$devices_tag->addChild($serial_tag);
##
##		# $devices_tag->addChild($disk2_tag);
##		my $source3_tag = $init_xml->createElement('source');
##		$serial_tag->addChild($source3_tag);
##		$source3_tag->addChild( $init_xml->createAttribute( mode => 'bind' ) );
##		$source3_tag->addChild(	$init_xml->createAttribute( path => $dh->get_vm_dir($vmName). '/' . $vmName . '_socket' ) );
##		my $target_tag = $init_xml->createElement('target');
##		$serial_tag->addChild($target_tag);
##		$target_tag->addChild( $init_xml->createAttribute( port => '1' ) );
##
###   ############<graphics type='sdl' display=':0.0'/>
###      my $graphics_tag2 = $init_xml->createElement('graphics');
###      $devices_tag->addChild($graphics_tag2);
###      $graphics_tag2->addChild( $init_xml->createAttribute( type => 'sdl'));
###      # DFC  $graphics_tag2->addChild( $init_xml->createAttribute( display =>':0.0'));
###      $disp = $ENV{'DISPLAY'};
###      $graphics_tag2->addChild( $init_xml->createAttribute( display =>$disp));
###
###
###   ############
##
##		my $addr = "qemu:///system";
##		print "Connecting to $addr...";
##		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
##		print "OK\n";
##		my $format    = 1;
##		my $xmlstring = $init_xml->toString($format);
##
##		open XML_FILE, ">" . $dh->get_vm_dir($vmName) . '/' . $vmName . '_libvirt.xml'
##		  or $execution->smartdie(
##			"can not open " . $dh->get_vm_dir . '/' . $vmName . '_libvirt.xml' )
##		  unless ( $execution->get_exe_mode() == EXE_DEBUG );
##		print XML_FILE "$xmlstring\n";
##		close XML_FILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
##
##		# check that the domain is not already defined or started
##        my @doms = $con->list_defined_domains();
##		foreach my $listDom (@doms) {
##			my $dom_name = $listDom->get_name();
##			if ( $dom_name eq $vmName ) {
##				$error = "Domain $vmName already defined\n";
##				return $error;
##			}
##		}
##		@doms = $con->list_domains();
##		foreach my $listDom (@doms) {
##			my $dom_name = $listDom->get_name();
##			if ( $dom_name eq $vmName ) {
##				$error = "Domain $vmName already defined and started\n";
##				return $error;
##			}
##		}
##		
##		my $domain = $con->define_domain($xmlstring);
##
##		return $error;
##
##	}
##	
##	###################################################################
##	#                  defineVM for libvirt-kvm-linux/freebsd         #
##	###################################################################
##	elsif ( ($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd") ) {
##
##		$filesystem_small = $dh->get_fs_dir($vmName) . "/opt_fs.iso";
##		open CONFILE, ">$path" . "vnxboot"
##		  or $execution->smartdie("can not open ${path}vnxboot: $!")
##		  unless ( $execution->get_exe_mode() == EXE_DEBUG );
##
##		#$execution->execute($doc ,*CONFILE);
##		print CONFILE "$doc\n";
##
##		close CONFILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
##		$execution->execute( $bd->get_binaries_path_ref->{"mkisofs"}
##			  . " -l -R -quiet -o $filesystem_small $path" );
##		$execution->execute(
##			$bd->get_binaries_path_ref->{"rm"} . " -rf $path" );
##
##		my $parser       = new XML::DOM::Parser;
##		my $dom          = $parser->parse($doc);
##		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
##		my $virtualmList = $globalNode->getElementsByTagName("vm");
##		my $virtualm     = $virtualmList->item($0);
##
##		my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
##		my $filesystemTag     = $filesystemTagList->item($0);
##		my $filesystem_type   = $filesystemTag->getAttribute("type");
##		my $filesystem        = $filesystemTag->getFirstChild->getData;
##
##		if ( $filesystem_type eq "cow" ) {
##
##			# DFC If cow file does not exist, we create it
##			if ( !-f $dh->get_fs_dir($vmName) . "/root_cow_fs" ) {
##
##				$execution->execute( "qemu-img"
##					  . " create -b $filesystem -f qcow2 "
##					  . $dh->get_fs_dir($vmName)
##					  . "/root_cow_fs" );
##			}
##			$filesystem = $dh->get_fs_dir($vmName) . "/root_cow_fs";
##		}
##
##		# memory
##		my $memTagList = $virtualm->getElementsByTagName("mem");
##		my $memTag     = $memTagList->item($0);
##		my $mem        = $memTag->getFirstChild->getData;
##
##		# create XML for libvirt
##		my $init_xml;
##		$init_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
##		my $domain_tag = $init_xml->createElement('domain');
##		$init_xml->addChild($domain_tag);
##		$domain_tag->addChild( $init_xml->createAttribute( type => "kvm" ) );
##
##		my $name_tag = $init_xml->createElement('name');
##		$domain_tag->addChild($name_tag);
##
##		#name
##		$name_tag->addChild( $init_xml->createTextNode($vmName) );
##
##		my $memory_tag = $init_xml->createElement('memory');
##		$domain_tag->addChild($memory_tag);
##
##		#memory
##		$memory_tag->addChild( $init_xml->createTextNode($mem) );
##
##		my $vcpu_tag = $init_xml->createElement('vcpu');
##		$domain_tag->addChild($vcpu_tag);
##
##		#vcpu
##		$vcpu_tag->addChild( $init_xml->createTextNode("1") );
##
##		my $os_tag = $init_xml->createElement('os');
##		$domain_tag->addChild($os_tag);
##		my $type_tag = $init_xml->createElement('type');
##		$os_tag->addChild($type_tag);
##		$type_tag->addChild( $init_xml->createAttribute( arch => "i686" ) );
##		$type_tag->addChild( $init_xml->createTextNode("hvm") );
##		my $boot1_tag = $init_xml->createElement('boot');
##		$os_tag->addChild($boot1_tag);
##		$boot1_tag->addChild( $init_xml->createAttribute( dev => 'hd' ) );
##		my $boot2_tag = $init_xml->createElement('boot');
##		$os_tag->addChild($boot2_tag);
##		$boot2_tag->addChild( $init_xml->createAttribute( dev => 'cdrom' ) );
##
##		my $features_tag = $init_xml->createElement('features');
##		$domain_tag->addChild($features_tag);
##		my $pae_tag = $init_xml->createElement('pae');
##		$features_tag->addChild($pae_tag);
##		my $acpi_tag = $init_xml->createElement('acpi');
##		$features_tag->addChild($acpi_tag);
##		my $apic_tag = $init_xml->createElement('apic');
##		$features_tag->addChild($apic_tag);
##
##		my $clock_tag = $init_xml->createElement('clock');
##		$domain_tag->addChild($clock_tag);
##		$clock_tag->addChild(
##			$init_xml->createAttribute( sync => "localtime" ) );
##
##		my $devices_tag = $init_xml->createElement('devices');
##		$domain_tag->addChild($devices_tag);
##
##		my $emulator_tag = $init_xml->createElement('emulator');
##		$devices_tag->addChild($emulator_tag);
##		$emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/kvm") );
##
##		my $disk1_tag = $init_xml->createElement('disk');
##		$devices_tag->addChild($disk1_tag);
##		$disk1_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
##		$disk1_tag->addChild( $init_xml->createAttribute( device => 'disk' ) );
##		my $source1_tag = $init_xml->createElement('source');
##		$disk1_tag->addChild($source1_tag);
##		$source1_tag->addChild(
##			$init_xml->createAttribute( file => $filesystem ) );
##		my $target1_tag = $init_xml->createElement('target');
##		$disk1_tag->addChild($target1_tag);
##		$target1_tag->addChild( $init_xml->createAttribute( dev => 'hda' ) );
##
##		my $disk2_tag = $init_xml->createElement('disk');
##		$devices_tag->addChild($disk2_tag);
##		$disk2_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
##		$disk2_tag->addChild( $init_xml->createAttribute( device => 'cdrom' ) );
##		my $source2_tag = $init_xml->createElement('source');
##		$disk2_tag->addChild($source2_tag);
##		$source2_tag->addChild(
##			$init_xml->createAttribute( file => $filesystem_small ) );
##		my $target2_tag = $init_xml->createElement('target');
##		$disk2_tag->addChild($target2_tag);
##		$target2_tag->addChild( $init_xml->createAttribute( dev => 'hdb' ) );
##
##		my $ifTagList = $virtualm->getElementsByTagName("if");
##		my $numif     = $ifTagList->getLength;
##
##		for ( my $j = 0 ; $j < $numif ; $j++ ) {
##			my $ifTag = $ifTagList->item($j);
##			my $id    = $ifTag->getAttribute("id");
##			my $net   = $ifTag->getAttribute("net");
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
##
##		}
##
##		my $graphics_tag = $init_xml->createElement('graphics');
##		$devices_tag->addChild($graphics_tag);
##		$graphics_tag->addChild( $init_xml->createAttribute( type => 'vnc' ) );
### DFC		my $vnc_port;
###		for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
###			my $vm = $vm_ordered[$i];
###
###			# To get name attribute
###			my $name = $vm->getAttribute("name");
###			if ( $vmName eq $name ) {
###				$vnc_port = $vm_vnc_port{$name} = 6900 + $i;
###			}
###		}
###		$graphics_tag->addChild(
###			$init_xml->createAttribute( port => $vnc_port ) );
##
##		#[JSF] host ip left
##		$graphics_tag->addChild(
##			$init_xml->createAttribute( listen => $ip_host ) );
##
##		my $serial_tag = $init_xml->createElement('serial');
##		$serial_tag->addChild( $init_xml->createAttribute( type => 'unix' ) );
##		$devices_tag->addChild($serial_tag);
##
##		# $devices_tag->addChild($disk2_tag);
##		my $source3_tag = $init_xml->createElement('source');
##		$serial_tag->addChild($source3_tag);
##		$source3_tag->addChild( $init_xml->createAttribute( mode => 'bind' ) );
##		$source3_tag->addChild(	$init_xml->createAttribute( path => $dh->get_vm_dir($vmName). '/' . $vmName . '_socket' ) );
##		my $target_tag = $init_xml->createElement('target');
##		$serial_tag->addChild($target_tag);
##		$target_tag->addChild( $init_xml->createAttribute( port => '1' ) );
##
###   ############<graphics type='sdl' display=':0.0'/>
###      my $graphics_tag2 = $init_xml->createElement('graphics');
###      $devices_tag->addChild($graphics_tag2);
###      $graphics_tag2->addChild( $init_xml->createAttribute( type => 'sdl'));
###      # DFC  $graphics_tag2->addChild( $init_xml->createAttribute( display =>':0.0'));
###      $disp = $ENV{'DISPLAY'};
###      $graphics_tag2->addChild( $init_xml->createAttribute( display =>$disp));
###
###
###   ############
##
##		my $addr = "qemu:///system";
##		print "Connecting to $addr...";
##		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
##		print "OK\n";
##		my $format    = 1;
##		my $xmlstring = $init_xml->toString($format);
##
##		open XML_FILE, ">" . $dh->get_vm_dir($vmName) . '/' . $vmName . '_libvirt.xml'
##		  or $execution->smartdie(
##			"can not open " . $dh->get_vm_dir . '/' . $vmName . '_libvirt.xml' )
##		  unless ( $execution->get_exe_mode() == EXE_DEBUG );
##		print XML_FILE "$xmlstring\n";
##		close XML_FILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
##
##        # check that the domain is not already defined or started
##        my @doms = $con->list_defined_domains();
##		foreach my $listDom (@doms) {
##			my $dom_name = $listDom->get_name();
##			if ( $dom_name eq $vmName ) {
##				$error = "Domain $vmName already defined\n";
##				return $error;
##			}
##		}
##		@doms = $con->list_domains();
##		foreach my $listDom (@doms) {
##			my $dom_name = $listDom->get_name();
##			if ( $dom_name eq $vmName ) {
##				$error = "Domain $vmName already defined and started\n";
##				return $error;
##			}
##		}
##		
##		my $domain = $con->define_domain($xmlstring);
##
##		return $error;
##
##	}
##
##	else {
##		$error = "Define for type $type not implemented yet.\n";
##		return $error;
##	}
#}
#
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
	
}
#sub undefineVM {
#
#	my $self   = shift;
#	my $vmName = shift;
#	my $type   = shift;
#
#	my $error;
#
#
#	###################################################################
#	#                  defineVM for libvirt-kvm-windows/linux/freebsd #
#	###################################################################
#	if ( ($type eq "libvirt-kvm-windows")||($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd") ) {
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_defined_domains();
#
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$listDom->undefine();
#				print "Domain undefined.\n";
#				$error = 0;
#				return $error;
#			}
#		}
#		$error = "Domain $vmName does not exist.\n";
#		return $error;
#
#	}
#
#	else {
#		$error = "undefineVM for type $type not implemented yet.\n";
#		return $error;
#	}
#}
#
#
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
	
}
#sub createVM {
#
#	my $self   = shift;
#	my $vmName = shift;
#	my $type   = shift;
#	my $doc    = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
#	my $sock    = shift;
#	my $counter = shift;
#	$curr_uml = $vmName;
#
#	my $error = 0;
#
#	my $doc2       = $dh->get_doc;
#	my @vm_ordered = $dh->get_vm_ordered;
#
#	#my $vm;
#	my $path;
#	my $filesystem;
#
#	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
#
#		my $vm = $vm_ordered[$i];
#
#		# We get name attribute
#		my $name = $vm->getAttribute("name");
#
#		unless ( $name eq $vmName ) {
#			next;
#		}
#
#		# To get filesystem and type
#		my $filesystem_type;
#		my $filesystem_list = $vm->getElementsByTagName("filesystem");
#		if ( $filesystem_list->getLength == 1 ) {
#			$filesystem =
#			  &do_path_expansion(
#				&text_tag( $vm->getElementsByTagName("filesystem")->item(0) ) );
#			$filesystem_type =
#			  $vm->getElementsByTagName("filesystem")->item(0)
#			  ->getAttribute("type");
#		}
#		else {
#			$filesystem      = $dh->get_default_filesystem;
#			$filesystem_type = $dh->get_default_filesystem_type;
#		}
#
#		if ( $execution->get_exe_mode() != EXE_DEBUG ) {
#			my $command =
#			    $bd->get_binaries_path_ref->{"mktemp"}
#			  . " -d -p "
#			  . $dh->get_tmp_dir
#			  . " vnx_opt_fs.XXXXXX";
#			chomp( $path = `$command` );
#		}
#		else {
#			$path = $dh->get_tmp_dir . "/vnx_opt_fs.XXXXXX";
#		}
#		$path .= "/";
#
#		$filesystem = $dh->get_fs_dir($name) . "/opt_fs";
#
#		# Install global public ssh keys in the UML
#		my $global_list = $doc2->getElementsByTagName("global");
#		my $key_list = $global_list->item(0)->getElementsByTagName("ssh_key");
#
#		# If tag present, add the key
#		for ( my $j = 0 ; $j < $key_list->getLength ; $j++ ) {
#			my $keyfile =
#			  &do_path_expansion( &text_tag( $key_list->item($j) ) );
#			$execution->execute( $bd->get_binaries_path_ref->{"cat"}
#				  . " $keyfile >> $path"
#				  . "keyring_root" );
#		}
#
#		# Next install vm-specific keys and add users and groups
#		my @user_list = $dh->merge_user($vm);
#		foreach my $user (@user_list) {
#			my $username      = $user->getAttribute("username");
#			my $initial_group = $user->getAttribute("group");
#			$execution->execute( $bd->get_binaries_path_ref->{"touch"} 
#				  . " $path"
#				  . "group_$username" );
#			my $group_list = $user->getElementsByTagName("group");
#			for ( my $k = 0 ; $k < $group_list->getLength ; $k++ ) {
#				my $group = &text_tag( $group_list->item($k) );
#				if ( $group eq $initial_group ) {
#					$group = "*$group";
#				}
#				$execution->execute( $bd->get_binaries_path_ref->{"echo"}
#					  . " $group >> $path"
#					  . "group_$username" );
#			}
#			my $key_list = $user->getElementsByTagName("ssh_key");
#			for ( my $k = 0 ; $k < $key_list->getLength ; $k++ ) {
#				my $keyfile =
#				  &do_path_expansion( &text_tag( $key_list->item($k) ) );
#				$execution->execute( $bd->get_binaries_path_ref->{"cat"}
#					  . " $keyfile >> $path"
#					  . "keyring_$username" );
#			}
#		}
#	}
#
#	###################################################################
#	#                  createVM for libvirt-kvm-windows               #
#	###################################################################
#	if ( $type eq "libvirt-kvm-windows" ) {
#
#		#Save xml received in vnxboot, for the autoconfiguration
#		$filesystem_small = $dh->get_fs_dir($vmName) . "/opt_fs.iso";
#		open CONFILE, ">$path" . "vnxboot"
#		  or $execution->smartdie("can not open ${path}vnxboot: $!")
#		  unless ( $execution->get_exe_mode() == EXE_DEBUG );
#
#		#$execution->execute($doc ,*CONFILE);
#		print CONFILE "$doc\n";
#
#		close CONFILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
#		$execution->execute( $bd->get_binaries_path_ref->{"mkisofs"}
#			  . " -l -R -quiet -o $filesystem_small $path" );
#		$execution->execute(
#			$bd->get_binaries_path_ref->{"rm"} . " -rf $path" );
#
#		my $parser       = new XML::DOM::Parser;
#		my $dom          = $parser->parse($doc);
#		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
#		my $virtualmList = $globalNode->getElementsByTagName("vm");
#		my $virtualm     = $virtualmList->item($0);
#
#		my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
#		my $filesystemTag     = $filesystemTagList->item($0);
#		my $filesystem_type   = $filesystemTag->getAttribute("type");
#		my $filesystem        = $filesystemTag->getFirstChild->getData;
#
#		if ( $filesystem_type eq "cow" ) {
#
#			# If cow file does not exist, we create it
#			if ( !-f $dh->get_fs_dir($vmName) . "/root_cow_fs" ) {
#
#				$execution->execute( "qemu-img"
#					  . " create -b $filesystem -f qcow2 "
#					  . $dh->get_fs_dir($vmName)
#					  . "/root_cow_fs" );
#			}
#			$filesystem = $dh->get_fs_dir($vmName) . "/root_cow_fs";
#		}
#
#		# memory
#		my $memTagList = $virtualm->getElementsByTagName("mem");
#		my $memTag     = $memTagList->item($0);
#		my $mem        = $memTag->getFirstChild->getData;
#
#		# create XML for libvirt
#		my $init_xml;
#		$init_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
#		my $domain_tag = $init_xml->createElement('domain');
#		$init_xml->addChild($domain_tag);
#		$domain_tag->addChild( $init_xml->createAttribute( type => "kvm" ) );
#
#		my $name_tag = $init_xml->createElement('name');
#		$domain_tag->addChild($name_tag);
#
#		#name
#		$name_tag->addChild( $init_xml->createTextNode($vmName) );
#
#		my $memory_tag = $init_xml->createElement('memory');
#		$domain_tag->addChild($memory_tag);
#
#		#memory
#		$memory_tag->addChild( $init_xml->createTextNode($mem) );
#
#		my $vcpu_tag = $init_xml->createElement('vcpu');
#		$domain_tag->addChild($vcpu_tag);
#
#		#vcpu
#		$vcpu_tag->addChild( $init_xml->createTextNode("1") );
#
#		my $os_tag = $init_xml->createElement('os');
#		$domain_tag->addChild($os_tag);
#		my $type_tag = $init_xml->createElement('type');
#		$os_tag->addChild($type_tag);
#		$type_tag->addChild( $init_xml->createAttribute( arch => "i686" ) );
#		$type_tag->addChild( $init_xml->createTextNode("hvm") );
#		my $boot1_tag = $init_xml->createElement('boot');
#		$os_tag->addChild($boot1_tag);
#		$boot1_tag->addChild( $init_xml->createAttribute( dev => 'hd' ) );
#		my $boot2_tag = $init_xml->createElement('boot');
#		$os_tag->addChild($boot2_tag);
#		$boot2_tag->addChild( $init_xml->createAttribute( dev => 'cdrom' ) );
#
#		my $features_tag = $init_xml->createElement('features');
#		$domain_tag->addChild($features_tag);
#		my $pae_tag = $init_xml->createElement('pae');
#		$features_tag->addChild($pae_tag);
#		my $acpi_tag = $init_xml->createElement('acpi');
#		$features_tag->addChild($acpi_tag);
#		my $apic_tag = $init_xml->createElement('apic');
#		$features_tag->addChild($apic_tag);
#
#		my $clock_tag = $init_xml->createElement('clock');
#		$domain_tag->addChild($clock_tag);
#		$clock_tag->addChild(
#			$init_xml->createAttribute( sync => "localtime" ) );
#
#		my $devices_tag = $init_xml->createElement('devices');
#		$domain_tag->addChild($devices_tag);
#
#		my $emulator_tag = $init_xml->createElement('emulator');
#		$devices_tag->addChild($emulator_tag);
#		$emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/kvm") );
#
#		my $disk1_tag = $init_xml->createElement('disk');
#		$devices_tag->addChild($disk1_tag);
#		$disk1_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
#		$disk1_tag->addChild( $init_xml->createAttribute( device => 'disk' ) );
#		my $source1_tag = $init_xml->createElement('source');
#		$disk1_tag->addChild($source1_tag);
#		$source1_tag->addChild(
#			$init_xml->createAttribute( file => $filesystem ) );
#		my $target1_tag = $init_xml->createElement('target');
#		$disk1_tag->addChild($target1_tag);
#		$target1_tag->addChild( $init_xml->createAttribute( dev => 'hda' ) );
#
#		my $disk2_tag = $init_xml->createElement('disk');
#		$devices_tag->addChild($disk2_tag);
#		$disk2_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
#		$disk2_tag->addChild( $init_xml->createAttribute( device => 'cdrom' ) );
#		my $source2_tag = $init_xml->createElement('source');
#		$disk2_tag->addChild($source2_tag);
#		$source2_tag->addChild(
#			$init_xml->createAttribute( file => $filesystem_small ) );
#		my $target2_tag = $init_xml->createElement('target');
#		$disk2_tag->addChild($target2_tag);
#		$target2_tag->addChild( $init_xml->createAttribute( dev => 'hdb' ) );
#
#		my $ifTagList = $virtualm->getElementsByTagName("if");
#		my $numif     = $ifTagList->getLength;
#
#		for ( my $j = 0 ; $j < $numif ; $j++ ) {
#			my $ifTag = $ifTagList->item($j);
#			my $id    = $ifTag->getAttribute("id");
#			my $net   = $ifTag->getAttribute("net");
#			my $mac   = $ifTag->getAttribute("mac");
#
#			my $interface_tag = $init_xml->createElement('interface');
#			$devices_tag->addChild($interface_tag);
#			$interface_tag->addChild(
#				$init_xml->createAttribute( type => 'bridge' ) );
#			$interface_tag->addChild(
#				$init_xml->createAttribute( name => "eth" . $id ) );
#			$interface_tag->addChild(
#				$init_xml->createAttribute( onboot => "yes" ) );
#			my $source_tag = $init_xml->createElement('source');
#			$interface_tag->addChild($source_tag);
#			$source_tag->addChild(
#				$init_xml->createAttribute( bridge => $net ) );
#			my $mac_tag = $init_xml->createElement('mac');
#			$interface_tag->addChild($mac_tag);
#			$mac =~ s/,//;
#			$mac_tag->addChild( $init_xml->createAttribute( address => $mac ) );
#
#		}
#
#		my $graphics_tag = $init_xml->createElement('graphics');
#		$devices_tag->addChild($graphics_tag);
#		$graphics_tag->addChild( $init_xml->createAttribute( type => 'vnc' ) );
## DFC		my $vnc_port;
##		for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
##			my $vm = $vm_ordered[$i];
##
##			# To get name attribute
##			my $name = $vm->getAttribute("name");
##			if ( $vmName eq $name ) {
##				$vnc_port = $vm_vnc_port{$name} = 6900 + $i;
##			}
##		}
##		$graphics_tag->addChild(
##			$init_xml->createAttribute( port => $vnc_port ) );
#
#		#[JSF] host ip left
#		$graphics_tag->addChild(
#			$init_xml->createAttribute( listen => $ip_host ) );
#
#		my $serial_tag = $init_xml->createElement('serial');
#		$serial_tag->addChild( $init_xml->createAttribute( type => 'unix' ) );
#		$devices_tag->addChild($serial_tag);
#
#		my $source3_tag = $init_xml->createElement('source');
#		$serial_tag->addChild($source3_tag);
#		$source3_tag->addChild( $init_xml->createAttribute( mode => 'bind' ) );
#		$source3_tag->addChild(	$init_xml->createAttribute( path => $dh->get_vm_dir($vmName) . '/' . $vmName . '_socket' ) );
#		my $target_tag = $init_xml->createElement('target');
#		$serial_tag->addChild($target_tag);
#		$target_tag->addChild( $init_xml->createAttribute( port => '1' ) );
#
##   ############<graphics type='sdl' display=':0.0'/>
##      my $graphics_tag2 = $init_xml->createElement('graphics');
##      $devices_tag->addChild($graphics_tag2);
##      $graphics_tag2->addChild( $init_xml->createAttribute( type => 'sdl'));
##      # DFC  $graphics_tag2->addChild( $init_xml->createAttribute( display =>':0.0'));
##      $disp = $ENV{'DISPLAY'};
##      $graphics_tag2->addChild( $init_xml->createAttribute( display =>$disp));
##
##
##   ############
#
#		my $addr = "qemu:///system";
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#		my $format    = 1;
#		my $xmlstring = $init_xml->toString($format);
#
#		open XML_FILE, ">" . $dh->get_vm_dir($vmName) . '/' . $vmName . '_libvirt.xml'
#		  or $execution->smartdie(
#			"can not open " . $dh->get_vm_dir . '/' . $vmName . '_libvirt.xml')
#		  unless ( $execution->get_exe_mode() == EXE_DEBUG );
#		print XML_FILE "$xmlstring\n";
#		close XML_FILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
#
#
#        # check that the domain is not already defined or started
#        my @doms = $con->list_defined_domains();
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$error = "Domain $vmName already defined\n";
#				return $error;
#			}
#		}
#		@doms = $con->list_domains();
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$error = "Domain $vmName already defined and started\n";
#				return $error;
#			}
#		}
#
#		my $domain = $con->create_domain($xmlstring);
#
#		# save pid in run dir
#		my $uuid = $domain->get_uuid_string();
#		$execution->execute( "ps aux | grep kvm | grep " 
#			  . $uuid
#			  . " | grep -v grep | awk '{print \$2}' > "
#			  . $dh->get_run_dir($vmName)
#			  . "/pid" );
#
#		$execution->execute("virt-viewer $vmName &");
#		
#        return $error;
#	}
#	
#	###################################################################
#	#                  createVM for libvirt-kvm-linux/freebsd         #
#	###################################################################
#	elsif ( ($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd") ) {
#
#		#Save xml received in vnxboot, for the autoconfiguration
#		$filesystem_small = $dh->get_fs_dir($vmName) . "/opt_fs.iso";
#		open CONFILE, ">$path" . "vnxboot"
#		  or $execution->smartdie("can not open ${path}vnxboot: $!")
#		  unless ( $execution->get_exe_mode() == EXE_DEBUG );
#
#		#$execution->execute($doc ,*CONFILE);
#		print CONFILE "$doc\n";
#
#		close CONFILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
#		$execution->execute( $bd->get_binaries_path_ref->{"mkisofs"}
#			  . " -l -R -quiet -o $filesystem_small $path" );
#		$execution->execute(
#			$bd->get_binaries_path_ref->{"rm"} . " -rf $path" );
#
#		my $parser       = new XML::DOM::Parser;
#		my $dom          = $parser->parse($doc);
#		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
#		my $virtualmList = $globalNode->getElementsByTagName("vm");
#		my $virtualm     = $virtualmList->item($0);
#
#		my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
#		my $filesystemTag     = $filesystemTagList->item($0);
#		my $filesystem_type   = $filesystemTag->getAttribute("type");
#		my $filesystem        = $filesystemTag->getFirstChild->getData;
#
#		if ( $filesystem_type eq "cow" ) {
#
#			# If cow file does not exist, we create it
#			if ( !-f $dh->get_fs_dir($vmName) . "/root_cow_fs" ) {
#
#				$execution->execute( "qemu-img"
#					  . " create -b $filesystem -f qcow2 "
#					  . $dh->get_fs_dir($vmName)
#					  . "/root_cow_fs" );
#
#			}
#			$filesystem = $dh->get_fs_dir($vmName) . "/root_cow_fs";
#		}
#
#		# memory
#		my $memTagList = $virtualm->getElementsByTagName("mem");
#		my $memTag     = $memTagList->item($0);
#		my $mem        = $memTag->getFirstChild->getData;
#
#		# create XML for libvirt
#		my $init_xml;
#		$init_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
#		my $domain_tag = $init_xml->createElement('domain');
#		$init_xml->addChild($domain_tag);
#		$domain_tag->addChild( $init_xml->createAttribute( type => "kvm" ) );
#
#		my $name_tag = $init_xml->createElement('name');
#		$domain_tag->addChild($name_tag);
#
#		#name
#		$name_tag->addChild( $init_xml->createTextNode($vmName) );
#
#		my $memory_tag = $init_xml->createElement('memory');
#		$domain_tag->addChild($memory_tag);
#
#		#memory
#		$memory_tag->addChild( $init_xml->createTextNode($mem) );
#
#		my $vcpu_tag = $init_xml->createElement('vcpu');
#		$domain_tag->addChild($vcpu_tag);
#
#		#vcpu
#		$vcpu_tag->addChild( $init_xml->createTextNode("1") );
#
#		my $os_tag = $init_xml->createElement('os');
#		$domain_tag->addChild($os_tag);
#		my $type_tag = $init_xml->createElement('type');
#		$os_tag->addChild($type_tag);
#		$type_tag->addChild( $init_xml->createAttribute( arch => "i686" ) );
#		$type_tag->addChild( $init_xml->createTextNode("hvm") );
#		my $boot1_tag = $init_xml->createElement('boot');
#		$os_tag->addChild($boot1_tag);
#		$boot1_tag->addChild( $init_xml->createAttribute( dev => 'hd' ) );
#		my $boot2_tag = $init_xml->createElement('boot');
#		$os_tag->addChild($boot2_tag);
#		$boot2_tag->addChild( $init_xml->createAttribute( dev => 'cdrom' ) );
#
#		my $features_tag = $init_xml->createElement('features');
#		$domain_tag->addChild($features_tag);
#		my $pae_tag = $init_xml->createElement('pae');
#		$features_tag->addChild($pae_tag);
#		my $acpi_tag = $init_xml->createElement('acpi');
#		$features_tag->addChild($acpi_tag);
#		my $apic_tag = $init_xml->createElement('apic');
#		$features_tag->addChild($apic_tag);
#
#		my $clock_tag = $init_xml->createElement('clock');
#		$domain_tag->addChild($clock_tag);
#		$clock_tag->addChild(
#			$init_xml->createAttribute( sync => "localtime" ) );
#
#		my $devices_tag = $init_xml->createElement('devices');
#		$domain_tag->addChild($devices_tag);
#
#		my $emulator_tag = $init_xml->createElement('emulator');
#		$devices_tag->addChild($emulator_tag);
#		$emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/kvm") );
#
#		my $disk1_tag = $init_xml->createElement('disk');
#		$devices_tag->addChild($disk1_tag);
#		$disk1_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
#		$disk1_tag->addChild( $init_xml->createAttribute( device => 'disk' ) );
#		my $source1_tag = $init_xml->createElement('source');
#		$disk1_tag->addChild($source1_tag);
#		$source1_tag->addChild(
#			$init_xml->createAttribute( file => $filesystem ) );
#		my $target1_tag = $init_xml->createElement('target');
#		$disk1_tag->addChild($target1_tag);
#		$target1_tag->addChild( $init_xml->createAttribute( dev => 'hda' ) );
#
#		my $disk2_tag = $init_xml->createElement('disk');
#		$devices_tag->addChild($disk2_tag);
#		$disk2_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
#		$disk2_tag->addChild( $init_xml->createAttribute( device => 'cdrom' ) );
#		my $source2_tag = $init_xml->createElement('source');
#		$disk2_tag->addChild($source2_tag);
#		$source2_tag->addChild(
#			$init_xml->createAttribute( file => $filesystem_small ) );
#		my $target2_tag = $init_xml->createElement('target');
#		$disk2_tag->addChild($target2_tag);
#		$target2_tag->addChild( $init_xml->createAttribute( dev => 'hdb' ) );
#
#		my $ifTagList = $virtualm->getElementsByTagName("if");
#		my $numif     = $ifTagList->getLength;
#
#		for ( my $j = 0 ; $j < $numif ; $j++ ) {
#			my $ifTag = $ifTagList->item($j);
#			my $id    = $ifTag->getAttribute("id");
#			my $net   = $ifTag->getAttribute("net");
#			my $mac   = $ifTag->getAttribute("mac");
#
#			my $interface_tag = $init_xml->createElement('interface');
#			$devices_tag->addChild($interface_tag);
#			$interface_tag->addChild(
#				$init_xml->createAttribute( type => 'bridge' ) );
#			$interface_tag->addChild(
#				$init_xml->createAttribute( name => "eth" . $id ) );
#			$interface_tag->addChild(
#				$init_xml->createAttribute( onboot => "yes" ) );
#			my $source_tag = $init_xml->createElement('source');
#			$interface_tag->addChild($source_tag);
#			$source_tag->addChild(
#				$init_xml->createAttribute( bridge => $net ) );
#			my $mac_tag = $init_xml->createElement('mac');
#			$interface_tag->addChild($mac_tag);
#			$mac =~ s/,//;
#			$mac_tag->addChild( $init_xml->createAttribute( address => $mac ) );
#
#		}
#
#		my $graphics_tag = $init_xml->createElement('graphics');
#		$devices_tag->addChild($graphics_tag);
#		$graphics_tag->addChild( $init_xml->createAttribute( type => 'vnc' ) );
## DFC		my $vnc_port;
##		for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
##			my $vm = $vm_ordered[$i];
##
##			# To get name attribute
##			my $name = $vm->getAttribute("name");
##			if ( $vmName eq $name ) {
##				$vnc_port = $vm_vnc_port{$name} = 6900 + $i;
##			}
##		}
##		$graphics_tag->addChild(
##			$init_xml->createAttribute( port => $vnc_port ) );
#
#		#[JSF] falta sacar la ip host
#		$graphics_tag->addChild(
#			$init_xml->createAttribute( listen => $ip_host ) );
#
#		my $serial_tag = $init_xml->createElement('serial');
#		$serial_tag->addChild( $init_xml->createAttribute( type => 'unix' ) );
#		$devices_tag->addChild($serial_tag);
#
#		# $devices_tag->addChild($disk2_tag);
#		my $source3_tag = $init_xml->createElement('source');
#		$serial_tag->addChild($source3_tag);
#		$source3_tag->addChild( $init_xml->createAttribute( mode => 'bind' ) );
#		$source3_tag->addChild(	$init_xml->createAttribute( path => $dh->get_vm_dir($vmName) . '/' . $vmName . '_socket' ) );
#		my $target_tag = $init_xml->createElement('target');
#		$serial_tag->addChild($target_tag);
#		$target_tag->addChild( $init_xml->createAttribute( port => '1' ) );
#
##   ############<graphics type='sdl' display=':0.0'/>
##      my $graphics_tag2 = $init_xml->createElement('graphics');
##      $devices_tag->addChild($graphics_tag2);
##      $graphics_tag2->addChild( $init_xml->createAttribute( type => 'sdl'));
##      # DFC  $graphics_tag2->addChild( $init_xml->createAttribute( display =>':0.0'));
##      $disp = $ENV{'DISPLAY'};
##      $graphics_tag2->addChild( $init_xml->createAttribute( display =>$disp));
##
##
##   ############
#
#		my $addr = "qemu:///system";
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#		my $format    = 1;
#		my $xmlstring = $init_xml->toString($format);
#
#		open XML_FILE, ">" . $dh->get_vm_dir($vmName) . '/' . $vmName . '_libvirt.xml'
#		  or $execution->smartdie(
#			"can not open " . $dh->get_vm_dir . '/' . $vmName . '_libvirt.xml')
#		  unless ( $execution->get_exe_mode() == EXE_DEBUG );
#		print XML_FILE "$xmlstring\n";
#		close XML_FILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
#
#
#        # check that the domain is not already defined or started
#        my @doms = $con->list_defined_domains();
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$error = "Domain $vmName already defined\n";
#				return $error;
#			}
#		}
#		@doms = $con->list_domains();
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$error = "Domain $vmName already defined and started\n";
#				return $error;
#			}
#		}
#
#		my $domain = $con->create_domain($xmlstring);
#
#		# save pid in run dir
#		my $uuid = $domain->get_uuid_string();
#		$execution->execute( "ps aux | grep kvm | grep " 
#			  . $uuid
#			  . " | grep -v grep | awk '{print \$2}' > "
#			  . $dh->get_run_dir($vmName)
#			  . "/pid" );
#
#		$execution->execute("virt-viewer $vmName &");
#		
#        return $error;
#        
#	}
#	else {
#		$error = "createVM for type $type not implemented yet.\n";
#		return $error;
#	}
#}
#
#
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
	$rname = "r11";
	$rconsoleport = "901";	
	$ram = "96";

    print "-----------------------------\n";
    print "Creating router: $rname\n";
    print "  console: $rconsoleport\n";
    print "  ram: $ram\n";

    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm stop ".$rname);
    $line = $t->getline; print $line;
}
#sub destroyVM {
#
#	my $self   = shift;
#	my $vmName = shift;
#	my $type   = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
#
#	my $error = 0;
#	
#	###################################################################
#	#                  destroyVM for libvirt-kvm-windows/linux/freebsd#
#	###################################################################
#	if ( ( $type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd") ) {
#
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_domains();
#
#		$error = "Domain does not exist\n";
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$listDom->destroy();
#				print "Domain destroyed\n";
#
#				# Delete vm directory (DFC 21/01/2010)
#				$error = 0;
#				last;
#
#			}
#		}
#
#		# Remove vm fs directory (cow and iso filesystems)
#		$execution->execute( "rm " . $dh->get_fs_dir($vmName) . "/*" );
#		return $error;
#
#	}
#	else {
#		$error = "Tipo aun no soportado...\n";
#		return $error;
#	}
#}
#
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
	$rname = "r11";
    print "-----------------------------\n";
    print "Starting router: $rname\n";
    $t = new Net::Telnet (Timeout => 10);
    $t->open(Host => $HHOST, Port => $HPORT);
    $t->print("vm start $rname");
    $line = $t->getline; print $line;
}

#sub startVM {
#
#	my $self   = shift;
#	my $vmName = shift;
#	my $type   = shift;
#	my $doc    = shift;
#	$execution = shift;
#	$bd        = shift;
#	my $dh           = shift;
#	my $sock         = shift;
#	my $manipcounter = shift;
#
#	my $error;
#
#	###################################################################
#	#                  startVM for libvirt-kvm-windows                #
#	###################################################################
#	if ( $type eq "libvirt-kvm-windows" ) {
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_defined_domains();
#
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$listDom->create();
#				print "Domain started\n";
#
#				# save pid in run dir
#				my $uuid = $listDom->get_uuid_string();
#				$execution->execute( "ps aux | grep kvm | grep " 
#					  . $uuid
#					  . " | grep -v grep | awk '{print \$2}' > "
#					  . $dh->get_run_dir($vmName)
#					  . "/pid" );
#
#				$execution->execute("virt-viewer $vmName &");
#
#		my $net = &get_admin_address( $counter, $dh->get_vmmgmt_type,$dh->get_vmmgmt_net,$dh->get_vmmgmt_mask,$dh->get_vmmgmt_offset,$dh->get_vmmgmt_hostip, 2 );
#
#		# If host_mapping is in use, append trailer to /etc/hosts config file
#
#		if ( $dh->get_host_mapping ) {
#
#			#@host_lines = ( @host_lines, $net->addr() . " $vm_name" );
#			#$execution->execute( $net->addr() . " $vm_name\n", *HOSTLINES );
#			open HOSTLINES, ">>" . $dh->get_sim_dir . "/hostlines"
#				or $execution->smartdie("can not open $dh->get_sim_dir/hostlines\n")
#				unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			print HOSTLINES $net->addr() . " $vmName\n";
#			close HOSTLINES;
#		}
#
#				$error = 0;
#				return $error;
#			}
#		}
#		$error = "Domain does not exist\n";
#		return $error;
#
#	}
#	###################################################################
#	#                  startVM for libvirt-kvm-linux/freebsd          #
#	###################################################################
#	elsif ( ($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd") ) {
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_defined_domains();
#
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$listDom->create();
#				print "Domain started\n";
#
#				# save pid in run dir
#				my $uuid = $listDom->get_uuid_string();
#				$execution->execute( "ps aux | grep kvm | grep " 
#					  . $uuid
#					  . " | grep -v grep | awk '{print \$2}' > "
#					  . $dh->get_run_dir($vmName)
#					  . "/pid" );
#
#				$execution->execute("virt-viewer $vmName &");
#
#
#		my $net = &get_admin_address( $counter, $dh->get_vmmgmt_type,$dh->get_vmmgmt_net,$dh->get_vmmgmt_mask,$dh->get_vmmgmt_offset,$dh->get_vmmgmt_hostip, 2 );
#
#		# If host_mapping is in use, append trailer to /etc/hosts config file
#
#		if ( $dh->get_host_mapping ) {
#
#			#@host_lines = ( @host_lines, $net->addr() . " $vm_name" );
#			#$execution->execute( $net->addr() . " $vm_name\n", *HOSTLINES );
#			open HOSTLINES, ">>" . $dh->get_sim_dir . "/hostlines"
#				or $execution->smartdie("can not open $dh->get_sim_dir/hostlines\n")
#				unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			print HOSTLINES $net->addr() . " $vmName\n";
#			close HOSTLINES;
#		}
#
#				$error = 0;
#				return $error;
#			}
#		}
#		$error = "Domain does not exist\n";
#		return $error;
#
#	}
#	else {
#		$error = "Type is not yet supported\n";
#		return $error;
#	}
#}
#
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
	
}
#sub shutdownVM {
#
#	my $self   = shift;
#	my $vmName = shift;
#	my $type   = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
#	$F_flag    = shift;
#
#	my $error = 0;
#
#	# Sample code
#	print "Shutting down vm $vmName of type $type\n";
#
#   	###################################################################
#	#                 shutdownVM for libvirt-kvm-windows/linux/freebsd#
#	###################################################################
#	if ( ($type eq "libvirt-kvm-windows")||($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd") ) {
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_domains();
#
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#
#				$listDom->shutdown();
#				&change_vm_status( $dh, $vmName, "REMOVE" );
#
#				# remove run directory (de momento no se puede porque necesitamos saber a que pid esperar)
##				$execution->execute( "rm -rf " . $dh->get_run_dir($vmName) );
#
#				print "Domain shut down\n";
#				return $error;
#			}
#		}
#		$error = "Domain does not exist..\n";
#		return $error;
#
#	}
#	else {
#		$error = "Type is not yet supported\n";
#		return $error;
#	}
#}
#
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
	
}
#sub saveVM {
#
#	my $self     = shift;
#	my $vmName   = shift;
#	my $type     = shift;
#	my $filename = shift;
#	$dh        = shift;
#	$bd        = shift;
#	$execution = shift;
#	
#
#	my $error = 0;
#
#	# Sample code
#	print "dummy plugin: saving vm $vmName of type $type\n";
#
#	if ( $type eq "libvirt-kvm" ) {
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_domains();
#
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$listDom->save($filename);
#				print "Domain saved to file $filename\n";
#				&change_vm_status( $dh, $vmName, "paused" );
#				return $error;
#			}
#		}
#		$error = "Domain does not exist..\n";
#		return $error;
#
#	}
#	###################################################################
#	#                  saveVM for libvirt-kvm-windows/linux/freebsd   #
#	###################################################################
#	elsif ( ($type eq "libvirt-kvm-windows")||($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd")) {
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_domains();
#
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$listDom->save($filename);
#				print "Domain saved to file $filename\n";
#				&change_vm_status( $dh, $vmName, "paused" );
#				return $error;
#			}
#		}
#		$error = "Domain does not exist...\n";
#		return $error;
#
#	}
#	else {
#		$error = "Type $type is not yet supported\n";
#		return $error;
#	}
#}
#
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
	
}
#sub restoreVM {
#
#	my $self     = shift;
#	my $vmName   = shift;
#	my $type     = shift;
#	my $filename = shift;
#
#	my $error = 0;
#
#	print
#	  "dummy plugin: restoring vm $vmName of type $type from file $filename\n";
#
# 	###################################################################
#	#                  restoreVM for libvirt-kvm-windows/linux/freebsd#
#	###################################################################
#	if ( ($type eq "libvirt-kvm-windows")||($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd")) {
#		my $addr = "qemu:///system";
#		print "Connecting to $addr...\n";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my $dom = $con->restore_domain($filename);
#		print("Domain restored from file $filename\n");
#		&change_vm_status( $dh, $vmName, "running" );
#		return $error;
#
#	}
#	else {
#		$error = "Type is not yet supported\n";
#		return $error;
#	}
#}
#
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
	
}
#sub suspendVM {
#
#	my $self   = shift;
#	my $vmName = shift;
#	my $type   = shift;
#
#	my $error = 0;
#
#	###################################################################
#	#                  suspendVM for libvirt-kvm-windows/linux/freebsd#
#	###################################################################
#    if (($type eq "libvirt-kvm-windows")||($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd")) {
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_domains();
#
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$listDom->suspend();
#				print "Domain suspended\n";
#				return $error;
#			}
#		}
#		$error = "Domain does not exist.\n";
#		return $error;
#
#	}
#	else {
#		$error = "Type is not yet supported\n";
#		return $error;
#	}
#}
#
#
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
	
}
#sub resumeVM {
#
#	my $self   = shift;
#	my $vmName = shift;
#	my $type   = shift;
#
#	my $error = 0;
#
#	# Sample code
#	print "dummy plugin: resuming vm $vmName\n";
#
#	###################################################################
#	#                  resumeVM for libvirt-kvm-windows/linux/freebsd #
#	###################################################################
#	if (($type eq "libvirt-kvm-windows")||($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd")) {
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_domains();
#
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$listDom->resume();
#				print "Domain resumed\n";
#				return $error;
#			}
#		}
#		$error = "Domain does not exist.\n";
#		return $error;
#
#	}
#	else {
#		$error = "Type is not yet supported\n";
#		return $error;
#	}
#}
#
#
#
####################################################################
##                                                                 #
##   rebootVM                                                      #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub rebootVM{
	
}
#sub rebootVM {
#
#	my $self   = shift;
#	my $vmName = shift;
#	my $type   = shift;
#
#	my $error = 0;
#
#	###################################################################
#	#                  rebootVM for libvirt-kvm-windows/linux/freebsd #
#	###################################################################
#	if (($type eq "libvirt-kvm-windows")||($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd")) {
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_domains();
#
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$listDom->reboot($Sys::Virt::Domain::REBOOT_RESTART);
#				print "Domain rebooting\n";
#				return $error;
#			}
#		}
#		$error = "Domain does not exist\n";
#		return $error;
#
#	}
#	else {
#		$error = "Type is not yet supported\n";
#		return $error;
#	}
#
#}
#
#
#
####################################################################
##                                                                 #
##   resetVM                                                       #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub resetVM{
	
}
#sub resetVM {
#
#	my $self   = shift;
#	my $vmName = shift;
#	my $type   = shift;
#
#	my $error;
#
#	# Sample code
#	print "dummy plugin: reseting vm $vmName\n";
#
#	###################################################################
#	#                  resetVM for libvirt-kvm-windows/linux/freebsd  #
#	###################################################################
#	if (($type eq "libvirt-kvm-windows")||($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd")) {
#		my $addr = "qemu:///system";
#
#		print "Connecting to $addr...";
#		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
#		print "OK\n";
#
#		my @doms = $con->list_domains();
#
#		foreach my $listDom (@doms) {
#			my $dom_name = $listDom->get_name();
#			if ( $dom_name eq $vmName ) {
#				$listDom->reboot(&Sys::Virt::Domain::REBOOT_DESTROY);
#				print "Domain reset";
#				$error = 0;
#				return $error;
#			}
#		}
#		$error = "Domain does not exist\n";
#		return $error;
#
#	}else {
#		$error = "Type is not yet supported\n";
#		return $error;
#	}
#}
#
#
#
####################################################################
##                                                                 #
##   executeCMD                                                    #
##                                                                 #
##                                                                 #
##                                                                 #
####################################################################
#
sub executeCMD{
	
}
#sub executeCMD {
#
#	my $self = shift;
#	my $merged_type = shift;
#	my $seq  = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
#	my $vm    = shift;
#	my $name = shift;
#
#	#Commands sequence (start, stop or whatever).
#
#	# Previous checkings and warnings
##	my @vm_ordered = $dh->get_vm_ordered;
##	my %vm_hash    = $dh->get_vm_to_use(@plugins);
#
#	# First loop: look for uml_mconsole exec capabilities if needed. This
#	# loop can cause exit, if capabilities are not accomplished
#my $random_id  = &generate_random_string(6);
#
#		if ( $merged_type eq "libvirt-kvm-windows" ) {
#			############ WINDOWS ##############
#			############ FILETREE ##############
#			my @filetree_list = $dh->merge_filetree($vm);
#			my $user   = &get_user_in_seq( $vm, $seq );
#			my $mode   = &get_vm_exec_mode($vm);
#			my $command =  $bd->get_binaries_path_ref->{"mktemp"} . " -d -p " . $dh->get_hostfs_dir($name)  . " filetree.XXXXXX";
#			open COMMAND_FILE, ">" . $dh->get_hostfs_dir($name) . "/filetree.xml" or $execution->smartdie("can not open " . $dh->get_hostfs_dir($name) . "/filetree.xml $!" ) unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			my $verb_prompt_bk = $execution->get_verb_prompt();
#			# FIXME: consider to use a different new VNX::Execution object to perform this
#			# actions (avoiding this nasty verb_prompt backup)
#			$execution->set_verb_prompt("$name> ");
#			my $shell      = $dh->get_default_shell;
#			my $shell_list = $vm->getElementsByTagName("shell");
#			if ( $shell_list->getLength == 1 ) {
#				$shell = &text_tag( $shell_list->item(0) );
#			}
#			my $date_command = $bd->get_binaries_path_ref->{"date"};
#			chomp( my $now = `$date_command` );
#			my $basename = basename $0;
#			$execution->execute( "<filetrees>", *COMMAND_FILE );
#			# Insert random id number for the command file
#			my $fileid = $name . "-" . &generate_random_string(6);
#			$execution->execute(  "<id>" . $fileid ."</id>", *COMMAND_FILE );
#			my $countfiletree = 0;
#			chomp( my $filetree_host = `$command` );
#			$filetree_host =~ /filetree\.(\w+)$/;
#			$execution->execute("mkdir " . $filetree_host ."/destination");
#			foreach my $filetree (@filetree_list) {
#				# To get momment
#				my $filetree_seq = $filetree->getAttribute("seq");
#				# To install subtree (only in the right momment)
#				# FIXME: think again the "always issue"; by the moment deactivated
#				if ( $filetree_seq eq $seq ) {
#					$countfiletree++;
#					my $src;
#					my $filetree_value = &text_tag($filetree);
#					if ( $filetree_value =~ /^\// ) {
#					# Absolute pathname
#					$src = &do_path_expansion($filetree_value);
#					}
#					else {
#						# Relative pahtname
#						if ( $basedir eq "" ) {
#						# Relative to xml_dir
#							$src = &do_path_expansion( &chompslash( $dh->get_xml_dir ) . "/$filetree_value" );
#						}
#						else {
#						# Relative to basedir
#							$src =  &do_path_expansion(	&chompslash($basedir) . "/$filetree_value" );
#						}
#					}
#					$src = &chompslash($src);
#					my $filetree_vm = "/mnt/hostfs/filetree.$random_id";
#					
#					$execution->execute("mkdir " . $filetree_host ."/destination/".  $countfiletree);
#					$execution->execute( $bd->get_binaries_path_ref->{"cp"} . " -r $src/* $filetree_host" . "/destination/" . $countfiletree );
#					my %file_perms = &save_dir_permissions($filetree_host);
#					my $dest = $filetree->getAttribute("root");
#					my $filetreetxt = $filetree->toString(1);
#					$execution->execute( "$filetreetxt", *COMMAND_FILE );
#				}
#			}
#			$execution->execute( "</filetrees>", *COMMAND_FILE );
#			close COMMAND_FILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			
#			open( DU, "du -hs0c " . $dh->get_hostfs_dir($name) . " | awk '{ var = \$1; var2 = substr(var,0,length(var)); print var2} ' |") || die "Failed: $!\n";
#			my $dimension = <DU>;
#			$dimension = $dimension + 20;
#			my $dimensiondisk = $dimension + 30;
#			close DU unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			open( DU, "du -hs0c " . $dh->get_hostfs_dir($name) . " | awk '{ var = \$1; var3 = substr(var,length(var),length(var)+1); print var3} ' |") || die "Failed: $!\n";
#			my $unit = <DU>;
#			close DU unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			if ($countfiletree > 0){
#				if (   ( $unit eq "K\n" || $unit eq "B\n" )|| ( ( $unit eq "M\n" ) && ( $dimension <= 32 ) ) ){
#					$unit          = 'M';
#					$dimension     = 32;
#					$dimensiondisk = 50;
#				}
#				$execution->execute("mkdir /tmp/disk.$random_id");
#				$execution->execute("mkdir  /tmp/disk.$random_id/destination");
#				$execution->execute( "cp " . $dh->get_hostfs_dir($name) . "/filetree.xml" . " " . "$filetree_host" );
#				#$execution->execute( "cp -rL " . $filetree_host . "/*" . " " . "/tmp/disk.$random_id/destination" );
#				$execution->execute("mkisofs -R -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/disk.$random_id.iso $filetree_host");
#				
#								
#				my $disk_filetree_windows_xml;
#				$disk_filetree_windows_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
#				
#				my $disk_filetree_windows_tag = $disk_filetree_windows_xml->createElement('disk');
#				$disk_filetree_windows_xml->addChild($disk_filetree_windows_tag);
#				$disk_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( type => "file" ) );
#				$disk_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( device => "cdrom" ) );
#				
#				my $driver_filetree_windows_tag =$disk_filetree_windows_xml->createElement('driver');
#				$disk_filetree_windows_tag->addChild($driver_filetree_windows_tag);
#				$driver_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( name => "qemu" ) );
#				$driver_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( cache => "default" ) );
#				
#				my $source_filetree_windows_tag =$disk_filetree_windows_xml->createElement('source');
#				$disk_filetree_windows_tag->addChild($source_filetree_windows_tag);
#				$source_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( file => "/tmp/disk.$random_id.iso" ) );
#				
#				my $target_filetree_windows_tag =$disk_filetree_windows_xml->createElement('target');
#				$disk_filetree_windows_tag->addChild($target_filetree_windows_tag);
#				$target_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( dev => "hdb" ) );
#				
#				my $readonly_filetree_windows_tag =$disk_filetree_windows_xml->createElement('readonly');
#				$disk_filetree_windows_tag->addChild($readonly_filetree_windows_tag);
#				my $format_filetree_windows   = 1;
#				my $xmlstring_filetree_windows = $disk_filetree_windows_xml->toString($format_filetree_windows );
#				
#				$execution->execute("rm ". $dh->get_hostfs_dir($name) . "/filetree_libvirt.xml"); 
#				open XML_FILETREE_WINDOWS_FILE, ">" . $dh->get_hostfs_dir($name) . '/' . 'filetree_libvirt.xml'
#		 			 or $execution->smartdie("can not open " . $dh->get_hostfs_dir . '/' . 'filetree_libvirt.xml' )
#		  		unless ( $execution->get_exe_mode() == EXE_DEBUG );
#				print XML_FILETREE_WINDOWS_FILE "$xmlstring_filetree_windows\n";
#				close XML_FILETREE_WINDOWS_FILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
#				
#				
#				
#				#$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/disk.$random_id.iso hdb --mode readonly --driver file --type cdrom'");
#				$execution->execute("virsh -c qemu:///system 'attach-device \"$name\" ". $dh->get_hostfs_dir($name) . "/filetree_libvirt.xml'");
#				print "Copying file tree in client, through socket: \n" . $dh->get_vm_dir($name). '/'.$name.'_socket';
#				waitfiletree($dh->get_vm_dir($name) .'/'.$name.'_socket');
#				sleep(4);
#				# 3d. Cleaning
#				$execution->execute("rm /tmp/disk.$random_id.iso");
#				$execution->execute("rm -r /tmp/disk.$random_id");
#				$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" );
#				$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -r " . $dh->get_hostfs_dir($name) . "/filetree.$random_id" );
#				$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -rf $filetree_host" );
#				$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id" );
#				$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree.xml" );
#				$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id.end" );
#			}
#			############ COMMAND_FILE ########################
#			# We open file
#			open COMMAND_FILE,">" . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" or $execution->smartdie("can not open " . $dh->get_tmp_dir . "/vnx.$name.$seq: $!" )
#			  unless ( $execution->get_exe_mode() == EXE_DEBUG );
#
#			# FIXME: consider to use a different new VNX::Execution object to perform this
#			# actions (avoiding this nasty verb_prompt backup)
#			$execution->set_verb_prompt("$name> ");
#			my $command = $bd->get_binaries_path_ref->{"date"};
#			chomp( my $now = `$command` );
#
#			# To process exec tags of matching commands sequence
#			my $command_list = $vm->getElementsByTagName("exec");
#
#			# To process list, dumping commands to file
#			$execution->execute( "<command>", *COMMAND_FILE );
#			
#			# Insert random id number for the command file
#			my $fileid = $name . "-" . &generate_random_string(6);
#			$execution->execute(  "<id>" . $fileid ."</id>", *COMMAND_FILE );
#			my $countcommand = 0;
#			for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
#				my $command = $command_list->item($j);	
#				# To get attributes
#				my $cmd_seq = $command->getAttribute("seq");
#				if ( $cmd_seq eq $seq ) {
#					my $type = $command->getAttribute("type");
#					# Case 1. Verbatim type
#					if ( $type eq "verbatim" ) {
#						# Including command "as is"
#						my $comando = $command->toString(1);
#						$execution->execute( $comando, *COMMAND_FILE );
#						$countcommand = $countcommand + 1;
#					}
#
#					# Case 2. File type
#					elsif ( $type eq "file" ) {
#						# We open the file and write commands line by line
#						my $include_file =  &do_path_expansion( &text_tag($command) );
#						open INCLUDE_FILE, "$include_file"
#						  or $execution->smartdie("can not open $include_file: $!");
#						while (<INCLUDE_FILE>) {
#							chomp;
#							$execution->execute(
#								#"<exec seq=\"file\" type=\"file\">" 
#								  #. $_
#								  #. "</exec>",
#								  $_,
#								*COMMAND_FILE
#							);
#							$countcommand = $countcommand + 1;
#						}
#						close INCLUDE_FILE;
#					}
#
#			 # Other case. Don't do anything (it would be and error in the XML!)
#				}
#			}
#			$execution->execute( "</command>", *COMMAND_FILE );
#			# We close file and mark it executable
#			close COMMAND_FILE
#			  unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			$execution->set_verb_prompt($verb_prompt_bk);
#			$execution->execute( $bd->get_binaries_path_ref->{"chmod"} . " a+x " . $dh->get_tmp_dir  . "/vnx.$name.$seq.$random_id" );
#			############# INSTALL COMMAND FILES #############
#			# Nothing to do in ibvirt mode
#			############# EXEC_COMMAND_FILE #################
#			
#			if ( $countcommand != 0 ) {
#				$execution->execute("mkdir /tmp/diskc.$seq.$random_id");
#				$execution->execute( "cp " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" . " " . "/tmp/diskc.$seq.$random_id/" . "command.xml" );
#				$execution->execute("mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/diskc.$seq.$random_id.iso /tmp/diskc.$seq.$random_id/");
#				
#				my $disk_command_windows_xml;
#				$disk_command_windows_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
#				
#				my $disk_command_windows_tag = $disk_command_windows_xml->createElement('disk');
#				$disk_command_windows_xml->addChild($disk_command_windows_tag);
#				$disk_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( type => "file" ) );
#				$disk_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( device => "cdrom" ) );
#				
#				my $driver_command_windows_tag =$disk_command_windows_xml->createElement('driver');
#				$disk_command_windows_tag->addChild($driver_command_windows_tag);
#				$driver_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( name => "qemu" ) );
#				$driver_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( cache => "default" ) );
#				
#				my $source_command_windows_tag =$disk_command_windows_xml->createElement('source');
#				$disk_command_windows_tag->addChild($source_command_windows_tag);
#				$source_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( file => "/tmp/diskc.$seq.$random_id.iso" ) );
#				
#				my $target_command_windows_tag =$disk_command_windows_xml->createElement('target');
#				$disk_command_windows_tag->addChild($target_command_windows_tag);
#				$target_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( dev => "hdb" ) );
#				
#				my $readonly_command_windows_tag =$disk_command_windows_xml->createElement('readonly');
#				$disk_command_windows_tag->addChild($readonly_command_windows_tag);
#				my $format_command_windows   = 1;
#				my $xmlstring_command_windows = $disk_command_windows_xml->toString($format_command_windows );
#				
#				$execution->execute("rm ". $dh->get_hostfs_dir($name) . "/command_libvirt.xml"); 
#				
#				open XML_COMMAND_WINDOWS_FILE, ">" . $dh->get_hostfs_dir($name) . '/' . 'command_libvirt.xml'
#		 			 or $execution->smartdie("can not open " . $dh->get_hostfs_dir . '/' . 'command_libvirt.xml' )
#		  		unless ( $execution->get_exe_mode() == EXE_DEBUG );
#				print XML_COMMAND_WINDOWS_FILE "$xmlstring_command_windows\n";
#				close XML_COMMAND_WINDOWS_FILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
#				$execution->execute("virsh -c qemu:///system 'attach-device \"$name\" ". $dh->get_hostfs_dir($name) . "/command_libvirt.xml'");
#				#$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/diskc.$seq.$random_id.iso hdb --mode readonly --driver file --type cdrom'");
#				print "Sending command to client... \n";
#				waitexecute($dh->get_vm_dir($name).'/'.$name.'_socket');
#				$execution->execute("rm /tmp/diskc.$seq.$random_id.iso");
#				$execution->execute("rm -r /tmp/diskc.$seq.$random_id");
#				$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" );
#			    sleep(2);
#			}
#			
#
#		}elsif (($merged_type eq "libvirt-kvm-linux")||($merged_type eq "libvirt-kvm-freebsd")){
#			############### LINUX ####################
#			############### FILETREE #################
#			my @filetree_list = $dh->merge_filetree($vm);
#			my $user   = &get_user_in_seq( $vm, $seq );
#			my $mode   = &get_vm_exec_mode($vm);
#			my $command =  $bd->get_binaries_path_ref->{"mktemp"} . " -d -p " . $dh->get_hostfs_dir($name)  . " filetree.XXXXXX";
#			open COMMAND_FILE, ">" . $dh->get_hostfs_dir($name) . "/filetree.xml" or $execution->smartdie("can not open " . $dh->get_hostfs_dir($name) . "/filetree.xml $!" ) unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			my $verb_prompt_bk = $execution->get_verb_prompt();
#			# FIXME: consider to use a different new VNX::Execution object to perform this
#			# actions (avoiding this nasty verb_prompt backup)
#			$execution->set_verb_prompt("$name> ");
#			my $shell      = $dh->get_default_shell;
#			my $shell_list = $vm->getElementsByTagName("shell");
#			if ( $shell_list->getLength == 1 ) {
#				$shell = &text_tag( $shell_list->item(0) );
#			}
#			my $date_command = $bd->get_binaries_path_ref->{"date"};
#			chomp( my $now = `$date_command` );
#			my $basename = basename $0;
#			$execution->execute( "<filetrees>", *COMMAND_FILE );
#			# Insert random id number for the command file
#			my $fileid = $name . "-" . &generate_random_string(6);
#			$execution->execute(  "<id>" . $fileid ."</id>", *COMMAND_FILE );
#			my $countfiletree = 0;
#			chomp( my $filetree_host = `$command` );
#			$filetree_host =~ /filetree\.(\w+)$/;
#			$execution->execute("mkdir " . $filetree_host ."/destination");
#			foreach my $filetree (@filetree_list) {
#				# To get momment
#				my $filetree_seq = $filetree->getAttribute("seq");
#				# To install subtree (only in the right momment)
#				# FIXME: think again the "always issue"; by the moment deactivated
#				if ( $filetree_seq eq $seq ) {
#					$countfiletree++;
#					my $src;
#					my $filetree_value = &text_tag($filetree);
#					if ( $filetree_value =~ /^\// ) {
#					# Absolute pathname
#					$src = &do_path_expansion($filetree_value);
#					}
#					else {
#						# Relative pahtname
#						if ( $basedir eq "" ) {
#						# Relative to xml_dir
#							$src = &do_path_expansion( &chompslash( $dh->get_xml_dir ) . "/$filetree_value" );
#						}
#						else {
#						# Relative to basedir
#							$src =  &do_path_expansion(	&chompslash($basedir) . "/$filetree_value" );
#						}
#					}
#					$src = &chompslash($src);
#					my $filetree_vm = "/mnt/hostfs/filetree.$random_id";
#					
#					$execution->execute("mkdir " . $filetree_host ."/destination/".  $countfiletree);
#					$execution->execute( $bd->get_binaries_path_ref->{"cp"} . " -r $src/* $filetree_host" . "/destination/" . $countfiletree );
#					my %file_perms = &save_dir_permissions($filetree_host);
#					my $dest = $filetree->getAttribute("root");
#					my $filetreetxt = $filetree->toString(1);
#					$execution->execute( "$filetreetxt", *COMMAND_FILE );
#				}
#			}
#			$execution->execute( "</filetrees>", *COMMAND_FILE );
#			close COMMAND_FILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			
#			open( DU, "du -hs0c " . $dh->get_hostfs_dir($name) . " | awk '{ var = \$1; var2 = substr(var,0,length(var)); print var2} ' |") || die "Failed: $!\n";
#			my $dimension = <DU>;
#			$dimension = $dimension + 20;
#			my $dimensiondisk = $dimension + 30;
#			close DU unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			open( DU, "du -hs0c " . $dh->get_hostfs_dir($name) . " | awk '{ var = \$1; var3 = substr(var,length(var),length(var)+1); print var3} ' |") || die "Failed: $!\n";
#			my $unit = <DU>;
#			close DU unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			if ($countfiletree > 0){
#				if (   ( $unit eq "K\n" || $unit eq "B\n" )|| ( ( $unit eq "M\n" ) && ( $dimension <= 32 ) ) ){
#					$unit          = 'M';
#					$dimension     = 32;
#					$dimensiondisk = 50;
#				}
#				$execution->execute("mkdir /tmp/disk.$random_id");
#				$execution->execute("mkdir  /tmp/disk.$random_id/destination");
#				$execution->execute( "cp " . $dh->get_hostfs_dir($name) . "/filetree.xml" . " " . "$filetree_host" );
#				#$execution->execute( "cp -rL " . $filetree_host . "/*" . " " . "/tmp/disk.$random_id/destination" );
#				$execution->execute("mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/disk.$random_id.iso $filetree_host");
#				$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/disk.$random_id.iso hdb --mode readonly --driver file --type cdrom'");
#				print "Copying file tree in client, through socket: \n" . $dh->get_vm_dir($name). '/'.$name.'_socket';
#				waitfiletree($dh->get_vm_dir($name) .'/'.$name.'_socket');
#				# mount empty iso, while waiting for new command	
#				$execution->execute("touch /tmp/empty.iso");
#				$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/empty.iso hdb --mode readonly --driver file --type cdrom'");
#				sleep 1;
#			   	# 3d. Cleaning
#				$execution->execute("rm /tmp/empty.iso");
#				$execution->execute("rm /tmp/disk.$random_id.iso");
#				$execution->execute("rm -r /tmp/disk.$random_id");
#				$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" );
#				$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -r " . $dh->get_hostfs_dir($name) . "/filetree.$random_id" );
#				$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -rf $filetree_host" );
#				$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id" );
#				$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree.xml" );
#				$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id.end" );
#			}
#			############ COMMAND_FILE ########################
#
#			# We open file
#			open COMMAND_FILE,">" . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" or $execution->smartdie("can not open " . $dh->get_tmp_dir . "/vnx.$name.$seq: $!" )
#			  unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			# FIXME: consider to use a different new VNX::Execution object to perform this
#			# actions (avoiding this nasty verb_prompt backup)
#			$execution->set_verb_prompt("$name> ");
#			my $command = $bd->get_binaries_path_ref->{"date"};
#			chomp( my $now = `$command` );
#
#			# $execution->execute("#!" . $shell,*COMMAND_FILE);
#			# $execution->execute("#commands sequence: $seq",*COMMAND_FILE);
#			# $execution->execute("#file generated by $basename $version$branch at $now",*COMMAND_FILE);
#
#			# To process exec tags of matching commands sequence
#			my $command_list = $vm->getElementsByTagName("exec");
#
#			# To process list, dumping commands to file
#			$execution->execute( "<command>", *COMMAND_FILE );
#			
#			# Insert random id number for the command file
#			$fileid = $name . "-" . &generate_random_string(6);
#			$execution->execute(  "<id>" . $fileid ."</id>", *COMMAND_FILE );
#			
#			my $countcommand = 0;
#			for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
#				my $command = $command_list->item($j);
#
#				# To get attributes
#				my $cmd_seq = $command->getAttribute("seq");
#				my $type    = $command->getAttribute("type");
#                my $typeos = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
#
#				if ( $cmd_seq eq $seq ) {
#
#					# Case 1. Verbatim type
#					if ( $type eq "verbatim" ) {
#
#						# Including command "as is"
#
#						#$execution->execute("<comando>",*COMMAND_FILE);
#						my $comando = $command->toString(1);
#						$execution->execute( $comando, *COMMAND_FILE );
#
#						#$execution->execute("</comando>",*COMMAND_FILE);
#						$countcommand = $countcommand + 1;
#
#					}
#
#					# Case 2. File type
#					elsif ( $type eq "file" ) {
#
#						# We open the file and write commands line by line
#						my $include_file = &do_path_expansion( &text_tag($command) );
#						open INCLUDE_FILE, "$include_file" or $execution->smartdie("can not open $include_file: $!");
#						while (<INCLUDE_FILE>) {
#							chomp;
#							$execution->execute(
#								#"<exec seq=\"file\" type=\"file\">" 
#								  #. $_
#								  #. "</exec>",
#								  $_,
#								*COMMAND_FILE
#							);
#							$countcommand = $countcommand + 1;
#						}
#						close INCLUDE_FILE;
#					}
#
#			 # Other case. Don't do anything (it would be and error in the XML!)
#				}
#			}
#			$execution->execute( "</command>", *COMMAND_FILE );
#			# We close file and mark it executable
#			close COMMAND_FILE
#			  unless ( $execution->get_exe_mode() == EXE_DEBUG );
#			$execution->set_verb_prompt($verb_prompt_bk);
#			$execution->execute( $bd->get_binaries_path_ref->{"chmod"} . " a+x " . $dh->get_tmp_dir  . "/vnx.$name.$seq.$random_id" );
#			############# INSTALL COMMAND FILES #############
#			# Nothing to do in ibvirt mode
#			############# EXEC_COMMAND_FILE #################
#			if ( $countcommand != 0 ) {
#				$execution->execute("mkdir /tmp/diskc.$seq.$random_id");
#				$execution->execute( "cp " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" . " " . "/tmp/diskc.$seq.$random_id/" . "command.xml" );
#				$execution->execute("mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/diskc.$seq.$random_id.iso /tmp/diskc.$seq.$random_id/");
#				$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/diskc.$seq.$random_id.iso hdb --mode readonly --driver file --type cdrom'");
#				print "Sending command to client... \n";			
#				waitexecute($dh->get_vm_dir($name).'/'.$name.'_socket');
#				# mount empty iso, while waiting for new command	
#				$execution->execute("touch /tmp/empty.iso");
#				$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/empty.iso hdb --mode readonly --driver file --type cdrom'"	);
#				sleep 1;
#				$execution->execute("rm /tmp/empty.iso");		
#				$execution->execute("rm /tmp/diskc.$seq.$random_id.iso");
#				$execution->execute("rm -r /tmp/diskc.$seq.$random_id");
#				$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir  . "/vnx.$name.$seq.$random_id" );
#				sleep(2);
#			}
#				
#				################## EXEC_COMMAND_HOST ########################3
#
#				my $doc = $dh->get_doc;
#			
#				# If host <host> is not present, there is nothing to do
#				return if ( $doc->getElementsByTagName("host")->getLength eq 0 );
#			
#				# To get <host> tag
#				my $host = $doc->getElementsByTagName("host")->item(0);
#			
#				# To process exec tags of matching commands sequence
#				my $command_list_host = $host->getElementsByTagName("exec");
#			
#				# To process list, dumping commands to file
#				for ( my $j = 0 ; $j < $command_list_host->getLength ; $j++ ) {
#					my $command = $command_list_host->item($j);
#			
#					# To get attributes
#					my $cmd_seq = $command->getAttribute("seq");
#					my $type    = $command->getAttribute("type");
#			
#					if ( $cmd_seq eq $seq ) {
#			
#						# Case 1. Verbatim type
#						if ( $type eq "verbatim" ) {
#			
#							# To include the command "as is"
#							$execution->execute( &text_tag_multiline($command) );
#						}
#			
#						# Case 2. File type
#						elsif ( $type eq "file" ) {
#			
#							# We open file and write commands line by line
#							my $include_file = &do_path_expansion( &text_tag($command) );
#							open INCLUDE_FILE, "$include_file"
#							  or $execution->smartdie("can not open $include_file: $!");
#							while (<INCLUDE_FILE>) {
#								chomp;
#								$execution->execute($_);
#							}
#							close INCLUDE_FILE;
#						}
#			
#						# Other case. Don't do anything (it would be an error in the XML!)
#					}
#				}
#		}
#}
#
#
#
####################################################################
##                                                                 
#sub change_vm_status {
#
#	my $dh     = shift;
#	my $vm     = shift;
#	my $status = shift;
#
#	my $status_file = $dh->get_vm_dir($vm) . "/status";
#
#	if ( $status eq "REMOVE" ) {
#		$execution->execute(
#			$bd->get_binaries_path_ref->{"rm"} . " -f $status_file" );
#	}
#	else {
#		$execution->execute(
#			$bd->get_binaries_path_ref->{"echo"} . " $status > $status_file" );
#	}
#}
#
#
#
#
####################################################################
## get_admin_address
##
## Returns a four elements list:
##
## - network address
## - network mask
## - IPv4 address of one peer
## - IPv4 address of the other peer
##
## This functions takes a single argument, an integer which acts as counter
## for UML'. It uses NetAddr::IP objects to calculate addresses for TWO hosts,
## whose addresses and mask returns.
##
## Private addresses of 192.168. prefix are used. For now, this is
## hardcoded in this function. It could, and should, i think, become
## part of the VNUML dtd.
##
## In VIRTUAL SWITCH MODE (net_sw) this function ...
## which returns UML ip undefined. Or, if one needs UML ip, function 
## takes two arguments: $vm object and interface id. Interface id zero 
## is reserved for management interface, and is default is none is supplied
#sub get_admin_address {
#
#   my $seed = shift;
#   my $vmmgmt_type = shift;
#   my $vmmgmt_net = shift;
#   my $vmmgmt_mask = shift;
#   my $vmmgmt_offset = shift;
#   my $vmmgmt_hostip = shift;
#   my $hostnum = shift;
#   my $ip;
#
#   my $net = NetAddr::IP->new($vmmgmt_net."/".$vmmgmt_mask);
#   if ($vmmgmt_type eq 'private') {
#	   # check to make sure that the address space won't wrap
#	   if ($vmmgmt_offset + ($seed << 2) > (1 << (32 - $vmmgmt_mask)) - 3) {
#		   $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
#	   }
#
#	   # create a private subnet from the seed
#	   $net += $vmmgmt_offset + ($seed << 2);
#	   $ip = NetAddr::IP->new($net->addr()."/30") + $hostnum;
#   } else {
#	   # vmmgmt type is 'net'
#
#	   # don't assign the hostip
#	   my $hostip = NetAddr::IP->new($vmmgmt_hostip."/".$vmmgmt_mask);
#	   if ($hostip > $net + $vmmgmt_offset &&
#		   $hostip <= $net + $vmmgmt_offset + $seed + 1) {
#		   $seed++;
#	   }
#
#	   # check to make sure that the address space won't wrap
#	   if ($vmmgmt_offset + $seed > (1 << (32 - $vmmgmt_mask)) - 3) {
#		   $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
#	   }
#
#	   # return an address in the vmmgmt subnet
#	   $ip = $net + $vmmgmt_offset + $seed + 1;
#   }
#   return $ip;
#}
#
#
#
#
####################################################################
##
#sub UML_plugins_conf {
#
#	my $path   = shift;
#	my $vm     = shift;
#	my $number = shift;
#
#	my $basename = basename $0;
#
#	my $name = $vm->getAttribute("name");
#
#	open CONFILE, ">$path" . "plugins_conf.sh"
#	  or $execution->smartdie("can not open ${path}plugins_conf.sh: $!")
#	  unless ( $execution->get_exe_mode() == EXE_DEBUG );
#	my $verb_prompt_bk = $execution->get_verb_prompt();
#
## FIXME: consider to use a different new VNX::Execution object to perform this
## actions (avoiding this nasty verb_prompt backup)
#	$execution->set_verb_prompt("$name> ");
#
#	# We begin plugin configuration script
#	my $shell      = $dh->get_default_shell;
#	my $shell_list = $vm->getElementsByTagName("shell");
#	if ( $shell_list->getLength == 1 ) {
#		$shell = &text_tag( $shell_list->item(0) );
#	}
#	my $command = $bd->get_binaries_path_ref->{"date"};
#	chomp( my $now = `$command` );
#	$execution->execute( "#!" . $shell, *CONFILE );
#	$execution->execute(
#		"# plugin configuration script generated by $basename at $now",
#		*CONFILE );
#	$execution->execute( "UTILDIR=/mnt/vnx", *CONFILE );
#
#	my $at_least_one_file = "0";
#	foreach my $plugin (@plugins) {
#		my %files = $plugin->bootingCreateFiles($name);
#
#		if ( defined( $files{"ERROR"} ) && $files{"ERROR"} ne "" ) {
#			$execution->smartdie(
#				"plugin $plugin bootingCreateFiles($name) error: "
#				  . $files{"ERROR"} );
#		}
#
#		foreach my $key ( keys %files ) {
#
#			# Create the directory to hold de file (idempotent operation)
#			my $dir = dirname($key);
#			mkpath( "$path/plugins_root/$dir", { verbose => 0 } );
#			$execution->set_verb_prompt($verb_prompt_bk);
#			$execution->execute( $bd->get_binaries_path_ref->{"cp"}
#				  . " $files{$key} $path/plugins_root/$key" );
#			$execution->set_verb_prompt("$name(plugins)> ");
#
#			# Remove the file in the host (this is part of the plugin API)
#			$execution->execute(
#				$bd->get_binaries_path_ref->{"rm"} . " $files{$key}" );
#
#			$at_least_one_file = 1;
#
#		}
#
#		my @commands = $plugin->bootingCommands($name);
#
#		my $error = shift(@commands);
#		if ( $error ne "" ) {
#			$execution->smartdie(
#				"plugin $plugin bootingCommands($name) error: $error");
#		}
#
#		foreach my $cmd (@commands) {
#			$execution->execute( $cmd, *CONFILE );
#		}
#	}
#
#	if ($at_least_one_file) {
#
#		# The last commands in plugins_conf.sh is to push plugin_root/ to vm /
#		$execution->execute(
#			"# Generated by $basename to push files generated by plugins",
#			*CONFILE );
#		$execution->execute( "cp -r \$UTILDIR/plugins_root/* /", *CONFILE );
#	}
#
#	# Close file and restore prompting method
#	$execution->set_verb_prompt($verb_prompt_bk);
#	close CONFILE unless ( $execution->get_exe_mode() == EXE_DEBUG );
#
#	# Configuration file must be executable
#	$execution->execute( $bd->get_binaries_path_ref->{"chmod"}
#		  . " a+x $path"
#		  . "plugins_conf.sh" );
#
#}
#
#
#
####################################################################
## get_net_by_type
##
## Returns a network whose name is the first argument and whose type is second
## argument (may be "*" if the type doesn't matter). If there is no net with
## the given constrictions, 0 value is returned
##
## Note the default type is "lan"
##
#sub get_net_by_type {
#
#	my $name_target = shift;
#	my $type_target = shift;
#
#	my $doc = $dh->get_doc;
#
#	# To get list of defined <net>
#	my $net_list = $doc->getElementsByTagName("net");
#
#	# To process list
#	for ( my $i = 0 ; $i < $net_list->getLength ; $i++ ) {
#		my $net  = $net_list->item($i);
#		my $name = $net->getAttribute("name");
#		my $type = $net->getAttribute("type");
#
#		if (   ( $name_target eq $name )
#			&& ( ( $type_target eq "*" ) || ( $type_target eq $type ) ) )
#		{
#			return $net;
#		}
#
#		# Special case (implicit lan)
#		if (   ( $name_target eq $name )
#			&& ( $type_target eq "lan" )
#			&& ( $type eq "" ) )
#		{
#			return $net;
#		}
#	}
#
#	return 0;
#}
#
#
#
####################################################################
## get_ip_hostname
##
## Return a suitable IP address to being added to the /etc/hosts file of the
## virtual machine passed as first argument (as node)
##
## In the current implementation, the first IP address for no management if is used.
## Only works for IPv4 addresses
##
## If no valid IP address if found or IPv4 has been disabled (with -6), returns 0.
##
#sub get_ip_hostname {
#
#	return 0 unless ( $dh->is_ipv4_enabled );
#
#	my $vm = shift;
#
#	# To check <mng_if>
#	my $mng_if_value = &mng_if_value( $dh, $vm );
#
#	my $if_list = $vm->getElementsByTagName("if");
#	for ( my $i = 0 ; $i < $if_list->getLength ; $i++ ) {
#		my $id = $if_list->item($i)->getAttribute("id");
#		if (   ( $id == 0 )
#			&& $dh->get_vmmgmt_type ne 'none'
#			&& ( $mng_if_value ne "no" ) )
#		{
#
#			# Skip the management interface
#			# Actually is a redundant checking, because check_semantics doesn't
#			# allow a id=0 <if> if managemente interface hasn't been disabled
#			next;
#		}
#		my $ipv4_list = $if_list->item($i)->getElementsByTagName("ipv4");
#		if ( $ipv4_list->getLength != 0 ) {
#			my $ip = &text_tag( $ipv4_list->item(0) );
#			if ( &valid_ipv4_with_mask($ip) ) {
#				$ip =~ /^(\d+).(\d+).(\d+).(\d+).*$/;
#				$ip = "$1.$2.$3.$4";
#			}
#			return $ip;
#		}
#	}
#
#	# No valid IPv4 found
#	return 0;
#}
#
#
#
####################################################################
##
#sub waitfiletree {
#
#	my $socket_path = shift;
#	
#	my $socket = IO::Socket::UNIX->new(
#	   Type => SOCK_STREAM,
#	   Peer => $socket_path,
#	)
#	   or die("Can't connect to server: $!\n");
#	
#	chomp( my $line = <$socket> );
#	print qq{Done. \n};
#	sleep(2);
#	$socket->close();
#
#}
#
#
#
####################################################################
##
#sub waitexecute {
#
#	my $socket_path = shift;
#	my $numprocess = shift;
#	my $i;
#	my $socket = IO::Socket::UNIX->new(
#		   Type => SOCK_STREAM,
#		   Peer => $socket_path,
#			)
#   			or die("Can't connect to server: $!\n");
#	chomp( my $line = <$socket> );
#	print qq{Done. \n};
#	sleep(2);
#	$socket->close();
#
#}
#
#
#
####################################################################
##
#sub get_user_in_seq {
#
#	my $vm  = shift;
#	my $seq = shift;
#
#	my $username = "";
#
#	# Looking for in <exec>
#	my $exec_list = $vm->getElementsByTagName("exec");
#	for ( my $i = 0 ; $i < $exec_list->getLength ; $i++ ) {
#		if ( $exec_list->item($i)->getAttribute("seq") eq $seq ) {
#			if ( $exec_list->item($i)->getAttribute("user") ne "" ) {
#				$username = $exec_list->item($i)->getAttribute("user");
#				last;
#			}
#		}
#	}
#
#	# If not found in <exec>, try with <filetree>
#	if ( $username eq "" ) {
#		my $filetree_list = $vm->getElementsByTagName("filetree");
#		for ( my $i = 0 ; $i < $filetree_list->getLength ; $i++ ) {
#			if ( $filetree_list->item($i)->getAttribute("seq") eq $seq ) {
#				if ( $filetree_list->item($i)->getAttribute("user") ne "" ) {
#					$username = $filetree_list->item($i)->getAttribute("user");
#					last;
#				}
#			}
#		}
#	}
#
#	# If no mode was found in <exec> or <filetree>, use default
#	if ( $username eq "" ) {
#		$username = "root";
#	}
#
#	return $username;
#
#}
#
#
#
####################################################################
## get_vm_exec_mode
##
## Arguments:
## - a virtual machine node
##
## Returns the corresponding mode for the command executions in the virtual
## machine issued as argument. If no exec_mode is found (note that exec_mode attribute in
## <vm> is optional), the default is retrieved from the DataHandler object
##
#sub get_vm_exec_mode {
#
#	my $vm = shift;
#
#	if ( $vm->getAttribute("mode") ne "" ) {
#		return $vm->getAttribute("mode");
#	}
#	else {
#		return $dh->get_default_exec_mode;
#	}
#
#}
#
#
#
#
####################################################################
## save_dir_permissions
##
## Argument:
## - a directory in the host enviroment in which the permissions
##   of the files will be saved
##
## Returns:
## - a hash with the permissions (a 3-character string with an octal
##   representation). The key of the hash is the file name
##
#sub save_dir_permissions {
#
#	my $dir = shift;
#
#	my @files = &get_directory_files($dir);
#	my %file_perms;
#
#	foreach (@files) {
#
#		# The directory itself is ignored
#		unless ( $_ eq $dir ) {
#
## Tip from: http://open.itworld.com/5040/nls_unix_fileattributes_060309/page_1.html
#			my $mode = ( stat($_) )[2];
#			$file_perms{$_} = sprintf( "%04o", $mode & 07777 );
#
#			#print "DEBUG: save_dir_permissions $_: " . $file_perms{$_} . "\n";
#		}
#	}
#
#	return %file_perms;
#}
#
#
#
####################################################################
## get_directory_files
##
## Argument:
## - a directory in the host enviroment
##
## Returns:
## - a list with all files in the given directory
##
#sub get_directory_files {
#
#	my $dir = shift;
#
#	# FIXME: the current implementation is based on invoking find shell
#	# command. Maybe there are smarter ways of doing the same
#	# just with Perl commands. This would remove the need of "find"
#	# in @binaries_mandatory in BinariesData.pm
#
#	my $command = $bd->get_binaries_path_ref->{"find"} . " $dir";
#	my $out     = `$command`;
#	my @files   = split( /\n/, $out );
#
#	return @files;
#}
#
#
#
####################################################################
## Wait for a filetree end file (see conf_files function)
#sub filetree_wait {
#	my $file = shift;
#
#	do {
#		if ( -f $file ) {
#			return 1;
#		}
#		sleep 1;
#	} while (1);
#	return 0;
#}
#
#
#
####################################################################
##
#sub merge_vm_type {
#	my $type = shift;
#	my $subtype = shift;
#	my $os = shift;
#	my $merged_type = $type;
#	
#	if (!($subtype eq "")){
#		$merged_type = $merged_type . "-" . $subtype;
#		if (!($os eq "")){
#			$merged_type = $merged_type . "-" . $os;
#		}
#	}
#	return $merged_type;
#	
#}
#
#
#
#
#1;

1;