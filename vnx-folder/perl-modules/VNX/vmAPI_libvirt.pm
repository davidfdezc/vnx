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

package vmAPI_libvirt;

@ISA    = qw(Exporter);
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

use strict;
use warnings;

use Sys::Virt;
use Sys::Virt::Domain;

use VNX::Globals;
use VNX::DataHandler;
use VNX::Execution;
use VNX::BinariesData;
use VNX::Arguments;
use VNX::CheckSemantics;
use VNX::TextManipulation;
use VNX::NetChecks;
use VNX::FileChecks;
use VNX::DocumentChecks;
use VNX::IPChecks;

#needed for UML_bootfile
use File::Basename;

use XML::DOM;

#use XML::LibXML;
#use XML::DOM::ValParser;


use IO::Socket::UNIX qw( SOCK_STREAM );

# Global objects

#my $execution;    # the VNX::Execution object
#my $dh;           # the VNX::DataHandler object
#my $bd;           # the VNX::BinariesData object



###################################################################
#                                                                 #
#   defineVM                                                      #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

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
	
	my $error = 0;

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

		# To get filesystem and type
		my $filesystem_type;
		my $filesystem_list = $vm->getElementsByTagName("filesystem");
		if ( $filesystem_list->getLength == 1 ) {
			$filesystem =
			  &do_path_expansion(
				&text_tag( $vm->getElementsByTagName("filesystem")->item(0) ) );
			$filesystem_type =
			  $vm->getElementsByTagName("filesystem")->item(0)
			  ->getAttribute("type");
		}
		else {
			$filesystem      = $dh->get_default_filesystem;
			$filesystem_type = $dh->get_default_filesystem_type;
		}

		if ( $execution->get_exe_mode() ne $EXE_DEBUG ) {
			my $command =
			    $bd->get_binaries_path_ref->{"mktemp"}
			  . " -d -p "
			  . $dh->get_tmp_dir
			  . " vnx_opt_fs.XXXXXX";
			chomp( $path = `$command` );
		}
		else {
			$path = $dh->get_tmp_dir . "/vnx_opt_fs.XXXXXX";
		}
		$path .= "/";

		$filesystem = $dh->get_fs_dir($name) . "/opt_fs";

		# Install global public ssh keys in the UML
		my $global_list = $doc2->getElementsByTagName("global");
		my $key_list = $global_list->item(0)->getElementsByTagName("ssh_key");

		# If tag present, add the key
		for ( my $j = 0 ; $j < $key_list->getLength ; $j++ ) {
			my $keyfile =
			  &do_path_expansion( &text_tag( $key_list->item($j) ) );
			$execution->execute( $bd->get_binaries_path_ref->{"cat"}
				  . " $keyfile >> $path"
				  . "keyring_root" );
		}

		# Next install vm-specific keys and add users and groups
		my @user_list = $dh->merge_user($vm);
		foreach my $user (@user_list) {
			my $username      = $user->getAttribute("username");
			my $initial_group = $user->getAttribute("group");
			$execution->execute( $bd->get_binaries_path_ref->{"touch"} 
				  . " $path"
				  . "group_$username" );
			my $group_list = $user->getElementsByTagName("group");
			for ( my $k = 0 ; $k < $group_list->getLength ; $k++ ) {
				my $group = &text_tag( $group_list->item($k) );
				if ( $group eq $initial_group ) {
					$group = "*$group";
				}
				$execution->execute( $bd->get_binaries_path_ref->{"echo"}
					  . " $group >> $path"
					  . "group_$username" );
			}
			my $key_list = $user->getElementsByTagName("ssh_key");
			for ( my $k = 0 ; $k < $key_list->getLength ; $k++ ) {
				my $keyfile =
				  &do_path_expansion( &text_tag( $key_list->item($k) ) );
				$execution->execute( $bd->get_binaries_path_ref->{"cat"}
					  . " $keyfile >> $path"
					  . "keyring_$username" );
			}
		}
	}


	###################################################################
	#                  defineVM for libvirt-kvm-windows               #
	###################################################################
	if ( $type eq "libvirt-kvm-windows" ) {

		#Save xml received in vnxboot, for the autoconfiguration
		my $filesystem_small = $dh->get_fs_dir($vmName) . "/opt_fs.iso";
		open CONFILE, ">$path" . "vnxboot"
		  or $execution->smartdie("can not open ${path}vnxboot: $!")
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

		#$execution->execute($doc ,*CONFILE);
		print CONFILE "$doc\n";

		close CONFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		$execution->execute( $bd->get_binaries_path_ref->{"mkisofs"} . " -l -R -quiet -o $filesystem_small $path" );
		$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -rf $path" );

		my $parser       = new XML::DOM::Parser;
		my $dom          = $parser->parse($doc);
		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
		my $virtualmList = $globalNode->getElementsByTagName("vm");
		my $virtualm     = $virtualmList->item(0);

		my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
		my $filesystemTag     = $filesystemTagList->item(0);
		my $filesystem_type   = $filesystemTag->getAttribute("type");
		my $filesystem        = $filesystemTag->getFirstChild->getData;

		if ( $filesystem_type eq "cow" ) {

			# If cow file does not exist, we create it
			if ( !-f $dh->get_fs_dir($vmName) . "/root_cow_fs" ) {
				$execution->execute( "qemu-img"
					  . " create -b $filesystem -f qcow2 "
					  . $dh->get_fs_dir($vmName)
					  . "/root_cow_fs" );
			}
			$filesystem = $dh->get_fs_dir($vmName) . "/root_cow_fs";
		}

		# memory
		my $memTagList = $virtualm->getElementsByTagName("mem");
		my $memTag     = $memTagList->item(0);
		my $mem        = $memTag->getFirstChild->getData;

		# create XML for libvirt
		my $init_xml;
		$init_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
		my $domain_tag = $init_xml->createElement('domain');
		$init_xml->addChild($domain_tag);
		$domain_tag->addChild( $init_xml->createAttribute( type => "kvm" ) );

		# <name> tag
		my $name_tag = $init_xml->createElement('name');
		$domain_tag->addChild($name_tag);
		$name_tag->addChild( $init_xml->createTextNode($vmName) );

		# <memory> tag
		my $memory_tag = $init_xml->createElement('memory');
		$domain_tag->addChild($memory_tag);
		$memory_tag->addChild( $init_xml->createTextNode($mem) );

		# <vcpu> tag
		my $vcpu_tag = $init_xml->createElement('vcpu');
		$domain_tag->addChild($vcpu_tag);
		$vcpu_tag->addChild( $init_xml->createTextNode("1") );

        # <os> tag
		my $os_tag = $init_xml->createElement('os');
		$domain_tag->addChild($os_tag);
		my $type_tag = $init_xml->createElement('type');
		$os_tag->addChild($type_tag);
		$type_tag->addChild( $init_xml->createAttribute( arch => "i686" ) );
		$type_tag->addChild( $init_xml->createTextNode("hvm") );
		my $boot1_tag = $init_xml->createElement('boot');
		$os_tag->addChild($boot1_tag);
		$boot1_tag->addChild( $init_xml->createAttribute( dev => 'hd' ) );
		my $boot2_tag = $init_xml->createElement('boot');
		$os_tag->addChild($boot2_tag);
		$boot2_tag->addChild( $init_xml->createAttribute( dev => 'cdrom' ) );

        # <features> tag
		my $features_tag = $init_xml->createElement('features');
		$domain_tag->addChild($features_tag);
		my $pae_tag = $init_xml->createElement('pae');
		$features_tag->addChild($pae_tag);
		my $acpi_tag = $init_xml->createElement('acpi');
		$features_tag->addChild($acpi_tag);
		my $apic_tag = $init_xml->createElement('apic');
		$features_tag->addChild($apic_tag);

        # <clock> tag
		my $clock_tag = $init_xml->createElement('clock');
		$domain_tag->addChild($clock_tag);
		$clock_tag->addChild(
		$init_xml->createAttribute( sync => "localtime" ) );

        # <devices> tag
		my $devices_tag = $init_xml->createElement('devices');
		$domain_tag->addChild($devices_tag);

        # <emulator> tag
		my $emulator_tag = $init_xml->createElement('emulator');
		$devices_tag->addChild($emulator_tag);
		$emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/kvm") );

        # main <disk> tag --> main root filesystem
		my $disk1_tag = $init_xml->createElement('disk');
		$devices_tag->addChild($disk1_tag);
		$disk1_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
		$disk1_tag->addChild( $init_xml->createAttribute( device => 'disk' ) );
		my $source1_tag = $init_xml->createElement('source');
		$disk1_tag->addChild($source1_tag);
		$source1_tag->addChild(
			$init_xml->createAttribute( file => $filesystem ) );
		my $target1_tag = $init_xml->createElement('target');
		$disk1_tag->addChild($target1_tag);
		$target1_tag->addChild( $init_xml->createAttribute( dev => 'hda' ) );
		
		# DFC: Added '<driver name='qemu' type='qcow2'/>' to work with libvirt 0.8.x 
        my $driver1_tag = $init_xml->createElement('driver');
        $disk1_tag->addChild($driver1_tag);
        $driver1_tag->addChild( $init_xml->createAttribute( name => 'qemu' ) );
        $driver1_tag->addChild( $init_xml->createAttribute( type => 'qcow2' ) );
        # End of DFC

        # secondary <disk> tag --> cdrom for autoconfiguration or command execution
		my $disk2_tag = $init_xml->createElement('disk');
		$devices_tag->addChild($disk2_tag);
		$disk2_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
		$disk2_tag->addChild( $init_xml->createAttribute( device => 'cdrom' ) );
		my $source2_tag = $init_xml->createElement('source');
		$disk2_tag->addChild($source2_tag);
		$source2_tag->addChild(
			$init_xml->createAttribute( file => $filesystem_small ) );
		my $target2_tag = $init_xml->createElement('target');
		$disk2_tag->addChild($target2_tag);
		$target2_tag->addChild( $init_xml->createAttribute( dev => 'hdb' ) );

        # network <interface> tags
		my $ifTagList = $virtualm->getElementsByTagName("if");
		my $numif     = $ifTagList->getLength;

		for ( my $j = 0 ; $j < $numif ; $j++ ) {
			my $ifTag = $ifTagList->item($j);
			my $id    = $ifTag->getAttribute("id");
			my $net   = $ifTag->getAttribute("net");
			my $mac   = $ifTag->getAttribute("mac");

			my $interface_tag = $init_xml->createElement('interface');
			$devices_tag->addChild($interface_tag);
			$interface_tag->addChild(
				$init_xml->createAttribute( type => 'bridge' ) );
			$interface_tag->addChild(
				$init_xml->createAttribute( name => "eth" . $id ) );
			$interface_tag->addChild(
				$init_xml->createAttribute( onboot => "yes" ) );
			my $source_tag = $init_xml->createElement('source');
			$interface_tag->addChild($source_tag);
			$source_tag->addChild(
				$init_xml->createAttribute( bridge => $net ) );
			my $mac_tag = $init_xml->createElement('mac');
			$interface_tag->addChild($mac_tag);
			$mac =~ s/,//;
			$mac_tag->addChild( $init_xml->createAttribute( address => $mac ) );

		}

    	#
		# VM CONSOLES
		# 
		# Two different consoles are configured in VNX:
		#   <console id="0"> which is the graphical console accessed using VNC protocol and virt-viewer app
		#                    It cannot be used in Olive routers (they only have serial line consoles)
		#                    Attributes: display="yes|no" (optional) -> controls whether the console is showed when the 
        #		                                                        machine is started  
		#   <console id="1"> which is the text console accessed through:
		#                      - pts -> <console id="1">pts</console> 
		#                      - telnet -> <console id="1" port="2000">telnet</console>
		#                    By default, pts is used if not explicitily specified. 
		#                    Attributes: display="yes|no" (optional) -> controls whether the console is showed when the 
        #		                                                        machine is started  
		#                                port="port_num" (optional)  -> defines the host port where the console can
		#                                                               be accessed. If not specified, VNX chooses a free port.
        # For windows vm's only the graphical console is defined (id=0). Other consoles defined with ids different from 0 are ignored 
		my $consFile = $dh->get_vm_dir($vmName) . "/run/console";
		open (CONS_FILE, ">> $consFile") || $execution->smartdie ("ERROR: Cannot open file $consFile");

		# Go through <consoles> tag list to get attributes (display, port) and value  
		my $consTagList = $virtualm->getElementsByTagName("console");
		my $numcons     = $consTagList->getLength;
        my $cons0Display = $VNX::Globals::CONS_DISPLAY_DEFAULT;
		for ( my $j = 0 ; $j < $numcons ; $j++ ) {
			my $consTag = $consTagList->item($j);
       		my $value   = &text_tag($consTag);
			my $id      = $consTag->getAttribute("id");
			my $display = $consTag->getAttribute("display");
       		#print "** console: id=$id, value=$value\n" if ($exemode == $EXE_VERBOSE);
			if ( $id eq "0" ) {
				print "WARNING (vm=$vmName): value $value ignored for <console id='0'> tag (only 'vnc' allowed).\n" 
				   if ( ($value ne "") && ($value ne "vnc") ); 
				if ($display ne '') { $cons0Display = $display }
			}
			if ( $id > 0 ) {
				print "WARNING (vm=$vmName): only consoles with id='0' allowed for Windows libvirt virtual machines. Tag ignored.\n"
			} 
		}

        # Graphical console: <console id="0"> 
		#   Always created for all vms but Olive routers
		#   We just add a <graphics type="vnc"> tag
		my $graphics_tag = $init_xml->createElement('graphics');
		$devices_tag->addChild($graphics_tag);
		$graphics_tag->addChild( $init_xml->createAttribute( type => 'vnc' ) );
		#falta ip host
		my $ip_host = "";
		$graphics_tag->addChild(
			$init_xml->createAttribute( listen => $ip_host ) );
		# Write the vnc console entry in "./vnx/.../vms/$vmName/run/console" file
		# We do not know yet the vnc display (known when the machine is started in startVM)
		# By now, we just write 'UNK_VNC_DISPLAY'
		print CONS_FILE "con0=$cons0Display,vnc_display,UNK_VNC_DISPLAY\n";
		#print "$consFile: con0=$cons0Display,vnc_display,UNK_VNC_DISPLAY\n" if ($exemode == $EXE_VERBOSE);
		close (CONS_FILE); 

        # <serial> tag --> autoconfiguration control socket       
		my $serial_tag = $init_xml->createElement('serial');
		$serial_tag->addChild( $init_xml->createAttribute( type => 'unix' ) );
		$devices_tag->addChild($serial_tag);

		my $source3_tag = $init_xml->createElement('source');
		$serial_tag->addChild($source3_tag);
		$source3_tag->addChild( $init_xml->createAttribute( mode => 'bind' ) );
		$source3_tag->addChild(	$init_xml->createAttribute( path => $dh->get_vm_dir($vmName) . '/' . $vmName . '_socket' ) );
		my $target_tag = $init_xml->createElement('target');
		$serial_tag->addChild($target_tag);
		$target_tag->addChild( $init_xml->createAttribute( port => '1' ) );

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my $format    = 1;
		my $xmlstring = $init_xml->toString($format);

		open XML_FILE, ">" . $dh->get_vm_dir($vmName) . '/' . $vmName . '_libvirt.xml'
		  or $execution->smartdie(
			"can not open " . $dh->get_vm_dir . '/' . $vmName . '_libvirt.xml')
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		print XML_FILE "$xmlstring\n";
		close XML_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

		# check that the domain is not already defined or started
        my @doms = $con->list_defined_domains();
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$error = "Domain $vmName already defined\n";
				return $error;
			}
		}
		@doms = $con->list_domains();
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$error = "Domain $vmName already defined and started\n";
				return $error;
			}
		}
		
		my $domain = $con->define_domain($xmlstring);

		return $error;

	}
	
	###################################################################
	# defineVM for libvirt-kvm-linux/freebsd/olive                    #
	###################################################################
	elsif ( ($type eq "libvirt-kvm-linux")||($type eq "libvirt-kvm-freebsd")||
	        ($type eq "libvirt-kvm-olive") ) {

		print "*** $path\n" if ($exemode == $EXE_VERBOSE); 
		open CONFILE, ">$path" . "vnxboot"
		  or $execution->smartdie("can not open ${path}vnxboot: $!")
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		#$execution->execute($doc ,*CONFILE);
		print CONFILE "$doc\n";
		close CONFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

		# We create the XML libvirt file with virtual machine definition
		my $parser       = new XML::DOM::Parser;
		my $dom          = $parser->parse($doc);
		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
		my $virtualmList = $globalNode->getElementsByTagName("vm");
		my $virtualm     = $virtualmList->item(0);

		my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
		my $filesystemTag     = $filesystemTagList->item(0);
		my $filesystem_type   = $filesystemTag->getAttribute("type");
		my $filesystem        = $filesystemTag->getFirstChild->getData;

		if ( $filesystem_type eq "cow" ) {

     		# Create the COW filesystem if it does not exist
			if ( !-f $dh->get_fs_dir($vmName) . "/root_cow_fs" ) {

				$execution->execute( "qemu-img"
					  . " create -b $filesystem -f qcow2 "
					  . $dh->get_fs_dir($vmName)
					  . "/root_cow_fs" );
			}
			$filesystem = $dh->get_fs_dir($vmName) . "/root_cow_fs";
		}

		# memory
		my $memTagList = $virtualm->getElementsByTagName("mem");
		my $memTag     = $memTagList->item(0);
		my $mem        = $memTag->getFirstChild->getData;

		# create XML for libvirt
		my $init_xml;
		$init_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
		my $domain_tag = $init_xml->createElement('domain');
		$init_xml->addChild($domain_tag);
		# $domain_tag->addChild( $init_xml->createAttribute( type => "kvm" ) );
		# DFC: changed the first line to 
		# <domain type='qemu' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
		# to allow the use of <qemu:commandline> tag to especify the bios in Olive routers
		$domain_tag->addChild( $init_xml->createAttribute( type => "kvm" ) );
		$domain_tag->addChild( $init_xml->createAttribute( 'xmlns:qemu' => "http://libvirt.org/schemas/domain/qemu/1.0" ) );
 
		# <name> tag
		my $name_tag = $init_xml->createElement('name');
		$domain_tag->addChild($name_tag);
		$name_tag->addChild( $init_xml->createTextNode($vmName) );

		# <memory> tag
		my $memory_tag = $init_xml->createElement('memory');
		$domain_tag->addChild($memory_tag);
		$memory_tag->addChild( $init_xml->createTextNode($mem) );

		# <vcpu> tag
		my $vcpu_tag = $init_xml->createElement('vcpu');
		$domain_tag->addChild($vcpu_tag);
		$vcpu_tag->addChild( $init_xml->createTextNode("1") );

# 		 Not used anymore. Obsoleted by the use of <qemu:commandline> tag to define
#		 commandline arguments for kvm (-bios bios-0.10.6)
#        # DFC: Add <biosfile> tag for Olive routers 
#        if ($type eq "libvirt-kvm-olive") {
#			my $biosfile_tag = $init_xml->createElement('biosfile');
#			$domain_tag->addChild($biosfile_tag);
#			#biosfile
#			$biosfile_tag->addChild( $init_xml->createTextNode("bios-0.10.6.bin") );
#        }
        
        # <os> tag
		my $os_tag = $init_xml->createElement('os');
		$domain_tag->addChild($os_tag);
		my $type_tag = $init_xml->createElement('type');
		$os_tag->addChild($type_tag);
		$type_tag->addChild( $init_xml->createAttribute( arch => "i686" ) );
		$type_tag->addChild( $init_xml->createTextNode("hvm") );
		my $boot1_tag = $init_xml->createElement('boot');
		$os_tag->addChild($boot1_tag);
		$boot1_tag->addChild( $init_xml->createAttribute( dev => 'hd' ) );
		my $boot2_tag = $init_xml->createElement('boot');
		$os_tag->addChild($boot2_tag);
		$boot2_tag->addChild( $init_xml->createAttribute( dev => 'cdrom' ) );

        # <features> tag
        my $features_tag = $init_xml->createElement('features');
		$domain_tag->addChild($features_tag);
		my $pae_tag = $init_xml->createElement('pae');
		$features_tag->addChild($pae_tag);
		my $acpi_tag = $init_xml->createElement('acpi');
		$features_tag->addChild($acpi_tag);
		my $apic_tag = $init_xml->createElement('apic');
		$features_tag->addChild($apic_tag);

        # <clock> tag
		my $clock_tag = $init_xml->createElement('clock');
		$domain_tag->addChild($clock_tag);
		$clock_tag->addChild(
		$init_xml->createAttribute( sync => "localtime" ) );

        # <devices> tag
		my $devices_tag = $init_xml->createElement('devices');
		$domain_tag->addChild($devices_tag);

        # <emulator> tag
		my $emulator_tag = $init_xml->createElement('emulator');
		$devices_tag->addChild($emulator_tag);
		$emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/kvm") );

        # main <disk> tag --> main root filesystem
		my $disk1_tag = $init_xml->createElement('disk');
		$devices_tag->addChild($disk1_tag);
		$disk1_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
		$disk1_tag->addChild( $init_xml->createAttribute( device => 'disk' ) );
		my $source1_tag = $init_xml->createElement('source');
		$disk1_tag->addChild($source1_tag);
		$source1_tag->addChild(
			$init_xml->createAttribute( file => $filesystem ) );
		my $target1_tag = $init_xml->createElement('target');
		$disk1_tag->addChild($target1_tag);
		$target1_tag->addChild( $init_xml->createAttribute( dev => 'hda' ) );

		# DFC: Added '<driver name='qemu' type='qcow2'/>' to work with libvirt 0.8.x 
        my $driver1_tag = $init_xml->createElement('driver');
        $disk1_tag->addChild($driver1_tag);
        $driver1_tag->addChild( $init_xml->createAttribute( name => 'qemu' ) );
        $driver1_tag->addChild( $init_xml->createAttribute( type => 'qcow2' ) );
        # End of DFC

        # secondary <disk> tag --> cdrom or disk for autoconfiguration or command execution
        if ($type ne "libvirt-kvm-olive") {

			# Create the iso filesystem for the cdrom
			my $filesystem_small = $dh->get_fs_dir($vmName) . "/opt_fs.iso";
			$execution->execute( $bd->get_binaries_path_ref->{"mkisofs"}
				  . " -l -R -quiet -o $filesystem_small $path" );
			$execution->execute(
				$bd->get_binaries_path_ref->{"rm"} . " -rf $path" );

			# Create the cdrom definition
       		my $disk2_tag = $init_xml->createElement('disk');
			$devices_tag->addChild($disk2_tag);
			$disk2_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
			$disk2_tag->addChild( $init_xml->createAttribute( device => 'cdrom' ) );
			my $source2_tag = $init_xml->createElement('source');
			$disk2_tag->addChild($source2_tag);
			$source2_tag->addChild(
				$init_xml->createAttribute( file => $filesystem_small ) );
			my $target2_tag = $init_xml->createElement('target');
			$disk2_tag->addChild($target2_tag);
			$target2_tag->addChild( $init_xml->createAttribute( dev => 'hdb' ) );
        
        } else {   # For olive VMs we use a shared disk 

			# Create the shared filesystem 
			my $sdisk_fname = $dh->get_fs_dir($vmName) . "/sdisk.img";
			# qemu-img create jconfig.img 12M
			# TODO: change the fixed 50M to something configurable
			$execution->execute( $bd->get_binaries_path_ref->{"qemu-img"} . " create $sdisk_fname 50M" );
			# mkfs.msdos jconfig.img
			$execution->execute( $bd->get_binaries_path_ref->{"mkfs.msdos"} . " $sdisk_fname" ); 
			# Mount the shared disk to copy filetree files
			my $vmmnt_dir = $dh->get_mnt_dir($vmName);
			$execution->execute( $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $vmmnt_dir );
			# Copy autoconfiguration (vnxboot.xml) file to shared disk
			$execution->execute( $bd->get_binaries_path_ref->{"cp"} . " $path/vnxboot $vmmnt_dir/vnxboot.xml" );
			$execution->execute(
				$bd->get_binaries_path_ref->{"rm"} . " -rf $path" );
			# Dismount shared disk
			$execution->execute( $bd->get_binaries_path_ref->{"umount"} . " " . $vmmnt_dir );

			# Create the shared <disk> definition
       		my $disk2_tag = $init_xml->createElement('disk');
			$devices_tag->addChild($disk2_tag);
			$disk2_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
			$disk2_tag->addChild( $init_xml->createAttribute( device => 'disk' ) );
			my $source2_tag = $init_xml->createElement('source');
			$disk2_tag->addChild($source2_tag);
			$source2_tag->addChild(
				$init_xml->createAttribute( file => $sdisk_fname ) );
			my $target2_tag = $init_xml->createElement('target');
			$disk2_tag->addChild($target2_tag);
			$target2_tag->addChild( $init_xml->createAttribute( dev => 'hdb' ) );
        	
        }
        
        # network <interface> tags
		my $ifTagList = $virtualm->getElementsByTagName("if");
		my $numif     = $ifTagList->getLength;

		for ( my $j = 0 ; $j < $numif ; $j++ ) {
			my $ifTag = $ifTagList->item($j);
			my $id    = $ifTag->getAttribute("id");
			my $net   = $ifTag->getAttribute("net");
			my $mac   = $ifTag->getAttribute("mac");

			my $interface_tag = $init_xml->createElement('interface');
			$devices_tag->addChild($interface_tag);
			$interface_tag->addChild(
				$init_xml->createAttribute( type => 'bridge' ) );
			$interface_tag->addChild(
				$init_xml->createAttribute( name => "eth" . $id ) );
			$interface_tag->addChild(
				$init_xml->createAttribute( onboot => "yes" ) );
			my $source_tag = $init_xml->createElement('source');
			$interface_tag->addChild($source_tag);
			$source_tag->addChild(
				$init_xml->createAttribute( bridge => $net ) );
			my $mac_tag = $init_xml->createElement('mac');
			$interface_tag->addChild($mac_tag);
			$mac =~ s/,//;
			$mac_tag->addChild( $init_xml->createAttribute( address => $mac ) );

			# DFC: set interface model to 'i82559er' in olive router interfaces.
			#      Using e1000 the interfaces are not created correctly (to further investigate) 
			if ($type eq "libvirt-kvm-olive") {
				# <model type='i82559er'/>
				my $model_tag = $init_xml->createElement('model');
				$interface_tag->addChild($model_tag);
				$model_tag->addChild( $init_xml->createAttribute( type => 'i82559er') );
			}
			
		}

    	#
		# VM CONSOLES
		# 
		# Two different consoles are configured in VNX:
		#   <console id="0"> which is the graphical console accessed using VNC protocol and virt-viewer app
		#                    It cannot be used in Olive routers (they only have serial line consoles)
		#                    Attributes: display="yes|no" (optional) -> controls whether the console is showed when the 
        #		                                                        machine is started  
		#   <console id="1"> which is the text console accessed through:
		#                      - pts -> <console id="1">pts</console> 
		#                      - telnet -> <console id="1" port="2000">telnet</console>
		#                    By default, pts is used if not explicitily specified. 
		#                    Attributes: display="yes|no" (optional) -> controls whether the console is showed when the 
        #		                                                        machine is started  
		#                                port="port_num" (optional)  -> defines the host port where the console can
		#                                                               be accessed. If not specified, VNX chooses a free port.
        # By now ther consoles defined with ids different from 0-1 are ignored 
		my $consFile = $dh->get_vm_dir($vmName) . "/run/console";
		open (CONS_FILE, ">> $consFile") || $execution->smartdie ("ERROR: Cannot open file $consFile");

		# Go through <consoles> tag list to get attributes (display, port) and value  
		my $consTagList = $virtualm->getElementsByTagName("console");
		my $numcons     = $consTagList->getLength;
        my $consType = $VNX::Globals::CONS1_DEFAULT_TYPE;
        my $cons0Display = $VNX::Globals::CONS_DISPLAY_DEFAULT;
        my $cons1Display = $VNX::Globals::CONS_DISPLAY_DEFAULT;
        my $cons1Port = '';
		for ( my $j = 0 ; $j < $numcons ; $j++ ) {
			my $consTag = $consTagList->item($j);
       		my $value   = &text_tag($consTag);
			my $id      = $consTag->getAttribute("id");
			my $display = $consTag->getAttribute("display");
       		#print "** console: id=$id, value=$value\n" if ($exemode == $EXE_VERBOSE);
			if (  $id eq "0" ) {
				if ($display ne '') { $cons0Display = $display }
			}
			if ( $id eq "1" ) {
				if ( $value eq "pts" || $value eq "telnet" ) { $consType = $value; }
				$cons1Port = $consTag->getAttribute("port");
				if ($display ne '') { $cons1Display = $display }
			}
			if ( $id > 1 ) {
				print "WARNING (vm=$vmName): only consoles with id='0' or id='1' allowed for libvirt virtual machines. Tag ignored.\n"
			} 
		}

        # Graphical console: <console id="0"> 
		#   Always created for all vms but Olive routers
		#   We just add a <graphics type="vnc"> tag
		if ($type ne "libvirt-kvm-olive") { 
			my $graphics_tag = $init_xml->createElement('graphics');
			$devices_tag->addChild($graphics_tag);
			$graphics_tag->addChild( $init_xml->createAttribute( type => 'vnc' ) );
			#falta ip host
			my $ip_host = "";
			$graphics_tag->addChild(
				$init_xml->createAttribute( listen => $ip_host ) );
			# Write the vnc console entry in "./vnx/.../vms/$vmName/console" file
			# We do not know yet the vnc display (known when the machine is started in startVM)
			# By now, we just write 'UNK_VNC_DISPLAY'
			print CONS_FILE "con0=$cons0Display,vnc_display,UNK_VNC_DISPLAY\n";
			#print "$consFile: con0=$cons0Display,vnc_display,UNK_VNC_DISPLAY\n" if ($exemode == $EXE_VERBOSE);
		}
				     
        # Text console: <console id="1"> 
		#print "** console #1 type: $consType (port=$cons1Port)\n";

		if ($consType eq "pts") {
        
	        # <serial> and <console> tags -> libvirt console
			# <serial type='pty'>
	        #   <target port='0'/>
	        # </serial>
	        # <console type='pty'>
	        #   <target port='0'/>
	        # </console>
			my $serial2_tag = $init_xml->createElement('serial');
			$serial2_tag->addChild( $init_xml->createAttribute( type => 'pty' ) );
			$devices_tag->addChild($serial2_tag);
			my $target2_tag = $init_xml->createElement('target');
			$serial2_tag->addChild($target2_tag);
			$target2_tag->addChild( $init_xml->createAttribute( port => '1' ) );
			my $console_tag = $init_xml->createElement('console');
			$console_tag->addChild( $init_xml->createAttribute( type => 'pty' ) );
			$devices_tag->addChild($console_tag);
			my $target3_tag = $init_xml->createElement('target');
			$console_tag->addChild($target3_tag);
			$target3_tag->addChild( $init_xml->createAttribute( port => '1' ) );

			# We write the pts console entry in "./vnx/.../vms/$vmName/console" file
			# We do not know yet the pts device assigned (known when the machine is started in startVM)
			# By now, we just write 'UNK_PTS_DEV'
			print CONS_FILE "con1=$cons1Display,libvirt_pts,UNK_PTS_DEV\n";
			#print "$consFile: con1=$cons1Display,libvirt_pts,UNK_PTS_DEV\n" if ($exemode == $EXE_VERBOSE);
			
		} elsif ($consType eq "telnet") {

			# <serial type="tcp">
			my $serial2_tag = $init_xml->createElement('serial');
			$devices_tag->addChild($serial2_tag);
			$serial2_tag->addChild( $init_xml->createAttribute( type => 'tcp' ) );
      		#	<source mode="bind" host="0.0.0.0" service="2001"/>
			my $source4_tag = $init_xml->createElement('source');
			$serial2_tag->addChild($source4_tag);
			$source4_tag->addChild( $init_xml->createAttribute( mode => 'bind' ) );
			$source4_tag->addChild(	$init_xml->createAttribute( host => '0.0.0.0' ) );

			my $consolePort;
			# DFC: Look for a free port starting from $cons1Port
			if ($cons1Port eq "") { # telnet port not defined we choose a free one starting from $CONS_PORT
				$consolePort = $VNX::Globals::CONS_PORT;
				while ( !system("fuser -s -v -n tcp $consolePort") ) {
	 				$consolePort++;
				}
				$$VNX::Globals::CONS_PORT = $consolePort + 1;
			} else { # telnet port was defined in <console> tag
				$consolePort = $cons1Port;
				while ( !system("fuser -s -v -n tcp $consolePort") ) {
	 				$consolePort++;
				}
			}
 			print "WARNING (vm=$vmName): cannot use port $cons1Port for $vmName console #1; using $consolePort instead\n"
		    		if ( ($cons1Port ne "") && ($consolePort ne $cons1Port) );
			$source4_tag->addChild(	$init_xml->createAttribute( service => "$consolePort" ) );
      		#	<protocol type="telnet"/>
			my $protocol_tag = $init_xml->createElement('protocol');
			$serial2_tag->addChild($protocol_tag);
			$protocol_tag->addChild( $init_xml->createAttribute( type => 'telnet' ) );
	      	#	<target port="1"/>
			my $target2_tag = $init_xml->createElement('target');
			$serial2_tag->addChild($target2_tag);
			$target2_tag->addChild( $init_xml->createAttribute( port => '1' ) );

			# Write the console entry in "./vnx/.../vms/$vmName/console" file
			print CONS_FILE "con1=$cons1Display,telnet,$consolePort\n";	
			print "** $consFile: con1=$cons1Display,telnet,$consolePort\n" if ($exemode == $EXE_VERBOSE);	
        }
		close (CONS_FILE); 

=BEGIN
        # Console definition for Olive routers 
		# <serial type="tcp">
      	#	<source mode="bind" host="0.0.0.0" service="2001"/>
      	#	<protocol type="telnet"/>
      	#	<target port="1"/>
    	# </serial>
        if ($type eq "libvirt-kvm-olive") {
			# <serial type="tcp">
			my $serial2_tag = $init_xml->createElement('serial');
			$devices_tag->addChild($serial2_tag);
			$serial2_tag->addChild( $init_xml->createAttribute( type => 'tcp' ) );
      		#	<source mode="bind" host="0.0.0.0" service="2001"/>
			my $source4_tag = $init_xml->createElement('source');
			$serial2_tag->addChild($source4_tag);
			$source4_tag->addChild( $init_xml->createAttribute( mode => 'bind' ) );
			$source4_tag->addChild(	$init_xml->createAttribute( host => '0.0.0.0' ) );
			# DFC: Look for a free port starting from $CON_PORT
			while ( !system("fuser -s -v -n tcp $CON_PORT") ) {
 				$CON_PORT++;
			}
			$source4_tag->addChild(	$init_xml->createAttribute( service => "$CON_PORT" ) );
			print "console file = $portfile; CON_PORT = $CON_PORT\n";
			my $portfile = $dh->get_vm_dir($vmName) . "/console";
			print "console file = $portfile; CON_PORT = $CON_PORT\n";
			open (CONPORT, ">$portfile") || die "ERROR: Cannot open file $portfile";;
			print CONPORT $CON_PORT;	
			close (CONPORT); 
			$CON_PORT++;
      		#	<protocol type="telnet"/>
			my $protocol_tag = $init_xml->createElement('protocol');
			$serial2_tag->addChild($protocol_tag);
			$protocol_tag->addChild( $init_xml->createAttribute( type => 'telnet' ) );
	      	#	<target port="1"/>
			my $target2_tag = $init_xml->createElement('target');
			$serial2_tag->addChild($target2_tag);
			$target2_tag->addChild( $init_xml->createAttribute( port => '1' ) );
        } else {
        
	        # <serial> and <console> tags -> libvirt console
			# <serial type='pty'>
	        #   <target port='0'/>
	        # </serial>
	        # <console type='pty'>
	        #   <target port='0'/>
	        # </console>
			my $serial2_tag = $init_xml->createElement('serial');
			$serial2_tag->addChild( $init_xml->createAttribute( type => 'pty' ) );
			$devices_tag->addChild($serial2_tag);
			my $target2_tag = $init_xml->createElement('target');
			$serial2_tag->addChild($target2_tag);
	           if ($type eq "libvirt-kvm-olive") {
				$target2_tag->addChild( $init_xml->createAttribute( port => '3' ) );
	           } else {
				$target2_tag->addChild( $init_xml->createAttribute( port => '1' ) );
			}
			my $console_tag = $init_xml->createElement('console');
			$console_tag->addChild( $init_xml->createAttribute( type => 'pty' ) );
			$devices_tag->addChild($console_tag);
			my $target3_tag = $init_xml->createElement('target');
			$console_tag->addChild($target3_tag);
	           if ($type eq "libvirt-kvm-olive") {
				$target3_tag->addChild( $init_xml->createAttribute( port => '3' ) );
	           } else {
				$target3_tag->addChild( $init_xml->createAttribute( port => '1' ) );
			}
        
        }
      
=END
=cut  

        # <serial> tag --> autoconfiguration control socket       
		my $serial_tag = $init_xml->createElement('serial');
		$serial_tag->addChild( $init_xml->createAttribute( type => 'unix' ) );
		$devices_tag->addChild($serial_tag);

		# $devices_tag->addChild($disk2_tag);
		my $source3_tag = $init_xml->createElement('source');
		$serial_tag->addChild($source3_tag);
		$source3_tag->addChild( $init_xml->createAttribute( mode => 'bind' ) );
		$source3_tag->addChild(	$init_xml->createAttribute( path => $dh->get_vm_dir($vmName) . '/' . $vmName . '_socket' ) );
		my $target_tag = $init_xml->createElement('target');
		$serial_tag->addChild($target_tag);
           if ($type eq "libvirt-kvm-olive") {
			$target_tag->addChild( $init_xml->createAttribute( port => '2' ) );
           } else {
			$target_tag->addChild( $init_xml->createAttribute( port => '1' ) );
		}

        if ($type eq "libvirt-kvm-olive") {
	        # <qemu:commandline> tag
	        # Olive routers have to use an old bios version from qemu 0.10.6 version
	        # with newer versions they fail booting with error:
	        # "Fatal trap 30: reserved (unknown) fault while in kernel mode"
			my $qemucmdline_tag = $init_xml->createElement('qemu:commandline');
			$domain_tag->addChild($qemucmdline_tag);
			my $qemuarg_tag = $init_xml->createElement('qemu:arg');
			$qemucmdline_tag->addChild($qemuarg_tag);
			$qemuarg_tag->addChild( $init_xml->createAttribute( value => "-bios" ) );
			my $qemuarg2_tag = $init_xml->createElement('qemu:arg');
			$qemucmdline_tag->addChild($qemuarg2_tag);
			$qemuarg2_tag->addChild( $init_xml->createAttribute( value => "bios-0.10.6.bin" ) );
        }
		     
#   ############<graphics type='sdl' display=':0.0'/>
#      my $graphics_tag2 = $init_xml->createElement('graphics');
#      $devices_tag->addChild($graphics_tag2);
#      $graphics_tag2->addChild( $init_xml->createAttribute( type => 'sdl'));
#      # DFC  $graphics_tag2->addChild( $init_xml->createAttribute( display =>':0.0'));
#      $disp = $ENV{'DISPLAY'};
#      $graphics_tag2->addChild( $init_xml->createAttribute( display =>$disp));
#   ############

		# We connect with libvirt to define the virtual machine
		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my $format    = 1;
		my $xmlstring = $init_xml->toString($format);
		
		# Save the XML libvirt file to .vnx/scenarios/<vscenario_name>/vms/$vmName
		open XML_FILE, ">" . $dh->get_vm_dir($vmName) . '/' . $vmName . '_libvirt.xml'
		  or $execution->smartdie(
			"can not open " . $dh->get_vm_dir . '/' . $vmName . '_libvirt.xml' )
		    unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		print XML_FILE "$xmlstring\n";
		close XML_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

        # check that the domain is not already defined or started
        my @doms = $con->list_defined_domains();
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$error = "Domain $vmName already defined\n";
				return $error;
			}
		}
		@doms = $con->list_domains();
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$error = "Domain $vmName already defined and started\n";
				return $error;
			}
		}
		
		my $domain = $con->define_domain($xmlstring);

		return $error;

	}

	else {
		$error = "Define for type $type not implemented yet.\n";
		return $error;
	}
}




###################################################################
#                                                                 #
#   undefineVM                                                    #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub undefineVM {

	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;

	my $error;


	###################################################################
	# undefineVM for libvirt-kvm-windows/linux/freebsd/olive          #
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_defined_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$listDom->undefine();
				print "Domain undefined.\n" if ($exemode == $EXE_VERBOSE);
				$error = 0;
				return $error;
			}
		}
		$error = "Domain $vmName does not exist.\n";
		return $error;

	}

	else {
		$error = "undefineVM for type $type not implemented yet.\n";
		return $error;
	}
}



###################################################################
#                                                                 #
#   destroyVM                                                     #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub destroyVM {

	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;

	my $error = 0;
	
	###################################################################
	#                  destroyVM for libvirt-kvm-windows/linux/freebsd#
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		$error = "Domain does not exist\n";
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$listDom->destroy();
				print "Domain destroyed\n" if ($exemode == $EXE_VERBOSE);

				# Delete vm directory (DFC 21/01/2010)
				$error = 0;
				last;

			}
		}

		# Remove vm fs directory (cow and iso filesystems)
		$execution->execute( "rm " . $dh->get_fs_dir($vmName) . "/*" );
		return $error;

	}
	else {
		$error = "Tipo aun no soportado...\n";
		return $error;
	}
}



###################################################################
#                                                                 #
#   startVM                                                       #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub startVM {

	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;
	my $doc    = shift;
#	$execution = shift;
#	$bd        = shift;
#	my $dh     = shift;
	my $sock   = shift;
	my $counter = shift;

	my $error;
	
	#print "**********  STARTVM *****************\n";
	
=BEGIN	
	###################################################################
	#                  startVM for libvirt-kvm-windows                #
	###################################################################
	if ( $type eq "libvirt-kvm-windows" ) {

		my $addr = "qemu:///system";

		print "Connecting to $addr...";
		my $con = Sys::Virt->new( address => $addr, readonly => 0 );
		print "OK\n";

		my @doms = $con->list_defined_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$listDom->create();
				print "Domain started\n";

				# save pid in run dir
				my $uuid = $listDom->get_uuid_string();
				$execution->execute( "ps aux | grep kvm | grep " 
					  . $uuid
					  . " | grep -v grep | awk '{print \$2}' > "
					  . $dh->get_run_dir($vmName)
					  . "/pid" );
				
				# display console if required
				my $parser       = new XML::DOM::Parser;
				my $dom          = $parser->parse($doc);
				my $display_console   = $dom->getElementsByTagName("display_console")->item(0)->getFirstChild->getData;
				unless ($display_console eq "no") {
					$execution->execute("virt-viewer $vmName &");
				}

				my $net = &get_admin_address( $counter, $dh->get_vmmgmt_type,$dh->get_vmmgmt_net,$dh->get_vmmgmt_mask,$dh->get_vmmgmt_offset,$dh->get_vmmgmt_hostip, 2 );

				# If host_mapping is in use, append trailer to /etc/hosts config file

				if ( $dh->get_host_mapping ) {

					#@host_lines = ( @host_lines, $net->addr() . " $vm_name" );
					#$execution->execute( $net->addr() . " $vm_name\n", *HOSTLINES );
					open HOSTLINES, ">>" . $dh->get_sim_dir . "/hostlines"
						or $execution->smartdie("can not open $dh->get_sim_dir/hostlines\n")
						unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
					print HOSTLINES $net->addr() . " $vmName\n";
					close HOSTLINES;
				}

				$error = 0;
				return $error;
			}
		}
		$error = "Domain does not exist\n";
		return $error;

	}
	
=END
=cut

	
	###################################################################
	# startVM for libvirt-kvm-windows/linux/freebsd/olive             #
	###################################################################
	if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
	        ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_defined_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$listDom->create();
				print "Domain started\n" if ($exemode == $EXE_VERBOSE);

				# save pid in run dir
				my $uuid = $listDom->get_uuid_string();
				$execution->execute( "ps aux | grep kvm | grep " 
					  . $uuid
					  . " | grep -v grep | awk '{print \$2}' > "
					  . $dh->get_run_dir($vmName)
					  . "/pid" );
				
				#		
			    # Console management
			    # 
    			
   				# First, we have to change the 'UNK_VNC_DISPLAY' and 'UNK_PTS_DEV' tags 
				# we temporarely wrote to console files (./vnx/.../vms/$vmName/console) 
				# by the correct values assigned by libvirt to the virtual machine
				my $consFile = $dh->get_vm_dir($vmName) . "/run/console";
  	
				# Graphical console (id=0)
				if ($type ne "libvirt-kvm-olive" ) { # Olive routers do not have graphical consoles
					# TODO: use $execution->execute
					my $cmd=$bd->get_binaries_path_ref->{"virsh"} . " -c qemu:///system vncdisplay $vmName";
			       	my $vncDisplay=`$cmd`;
			       	$vncDisplay =~ s/\s+$//;    # Delete linefeed at the end		
					$execution->execute ($bd->get_binaries_path_ref->{"sed"}." -i -e 's/UNK_VNC_DISPLAY/$vncDisplay/' $consFile");
					#print "****** sed -i -e 's/UNK_VNC_DISPLAY/$vncDisplay/' $consFile\n";
				}
			
				# Text console (id=1)
			    if ($type ne "libvirt-kvm-windows")  { # Windows does not have text console
			    	# Check if con1 is of type "libvirt_pts"
			    	#my $conData= &get_conf_value ($consFile, "con1", $execution);
			    	my $conData= &get_conf_value ($consFile, "con1");
					if ( $conData ne '') {
					    my @consField = split(/,/, $conData);
					    if ($consField[1] eq 'libvirt_pts') {
			        		my $cmd=$bd->get_binaries_path_ref->{"virsh"} . " -c qemu:///system ttyconsole $vmName";
			           		my $ptsDev=`$cmd`;
			           		$ptsDev =~ s/\s+$//;    # Delete linefeed at the end		
							$execution->execute ($bd->get_binaries_path_ref->{"sed"}." -i -e 's#UNK_PTS_DEV#$ptsDev#' $consFile");
					    }
					} else {
						print "WARNING (vm=$vmName): no data for console #1 found in $consFile"
					}
				}
			   
				# Then, we just read the console file and start the active consoles
				VNX::vmAPICommon->start_consoles_from_console_file ($vmName);
						    
					    
=BEGIN                        
        		if ($type eq "libvirt-kvm-olive") {
        			my $consport;
					my $portfile = $dh->get_vm_dir($vmName) . "/console";
					if (-e $portfile ){
						open (CONPORT, "<$portfile") || die "ERROR: No puedo abrir el fichero $portfile";
						$consport= <CONPORT>;
						close (CONPORT);
					} else {
						printf "ERROR: file $portfile does not exist\n";
					}
					
					
					# display console if required
					my $parser       = new XML::DOM::Parser;
					my $dom          = $parser->parse($doc);
					my $display_console   = $dom->getElementsByTagName("display_console")->item(0)->getFirstChild->getData;
					unless ($display_console eq "no") {
		    			$execution->execute("xterm -title '$vmName (Olive)' -e 'telnet localhost $consport' >/dev/null 2>&1 &");
					}
        		}
        		else {
        			# display console if required
					my $parser       = new XML::DOM::Parser;
					my $dom          = $parser->parse($doc);
					my $display_console   = $dom->getElementsByTagName("display_console")->item(0)->getFirstChild->getData;
					unless ($display_console eq "no") {
						$execution->execute("virt-viewer $vmName &");
					}
				}
=END
=cut				
				
				my $net = &get_admin_address( $counter, $dh->get_vmmgmt_type,$dh->get_vmmgmt_net,$dh->get_vmmgmt_mask,$dh->get_vmmgmt_offset,$dh->get_vmmgmt_hostip, 2 );

				# If host_mapping is in use, append trailer to /etc/hosts config file

				if ( $dh->get_host_mapping ) {

					#@host_lines = ( @host_lines, $net->addr() . " $vm_name" );
					#$execution->execute( $net->addr() . " $vm_name\n", *HOSTLINES );
					open HOSTLINES, ">>" . $dh->get_sim_dir . "/hostlines"
						or $execution->smartdie("can not open $dh->get_sim_dir/hostlines\n")
						unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
					print HOSTLINES $net->addr() . " $vmName\n";
					close HOSTLINES;
				}

				$error = 0;
				return $error;
			}
		}
		$error = "Domain does not exist\n";
		return $error;

	}
	else {
		$error = "Type is not yet supported\n";
		return $error;
	}
}



###################################################################
#                                                                 #
#   shutdownVM                                                    #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub shutdownVM {

	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
	my $F_flag = shift; # Not used here, only in vmAPI_uml

	my $error = 0;

	# Sample code
	print "Shutting down vm $vmName of type $type\n" if ($exemode == $EXE_VERBOSE);

   	###################################################################
	#                 shutdownVM for libvirt-kvm-windows/linux/freebsd#
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {

				$listDom->shutdown();
				#&change_vm_status( $dh, $vmName, "REMOVE" );
				&change_vm_status( $vmName, "REMOVE" );

				# remove run directory (de momento no se puede porque necesitamos saber a que pid esperar)
				# lo habilito para la demo
				$execution->execute( "rm -rf " . $dh->get_run_dir($vmName) );

				print "Domain shut down\n" if ($exemode == $EXE_VERBOSE);
				return $error;
			}
		}
		$error = "Domain does not exist..\n";
		return $error;

	}
	else {
		$error = "Type is not yet supported\n";
		return $error;
	}
}



###################################################################
#                                                                 #
#   saveVM                                                        #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub saveVM {

	my $self     = shift;
	my $vmName   = shift;
	my $type     = shift;
	my $filename = shift;
#	$dh        = shift;
#	$bd        = shift;
#	$execution = shift;
	

	my $error = 0;

	# Sample code
	print "dummy plugin: saving vm $vmName of type $type\n" if ($exemode == $EXE_VERBOSE);

	if ( $type eq "libvirt-kvm" ) {

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$listDom->save($filename);
				print "Domain saved to file $filename\n" if ($exemode == $EXE_VERBOSE);
				#&change_vm_status( $dh, $vmName, "paused" );
				&change_vm_status( $vmName, "paused" );
				return $error;
			}
		}
		$error = "Domain does not exist..\n";
		return $error;

	}
	###################################################################
	#                  saveVM for libvirt-kvm-windows/linux/freebsd   #
	###################################################################
    elsif ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
             ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") )   {

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$listDom->save($filename);
				print "Domain saved to file $filename\n" if ($exemode == $EXE_VERBOSE);
				#&change_vm_status( $dh, $vmName, "paused" );
				&change_vm_status( $vmName, "paused" );
				return $error;
			}
		}
		$error = "Domain does not exist...\n";
		return $error;

	}
	else {
		$error = "Type $type is not yet supported\n";
		return $error;
	}
}



###################################################################
#                                                                 #
#   restoreVM                                                     #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub restoreVM {

	my $self     = shift;
	my $vmName   = shift;
	my $type     = shift;
	my $filename = shift;

	my $error = 0;

	print
	  "dummy plugin: restoring vm $vmName of type $type from file $filename\n";

 	###################################################################
	#                  restoreVM for libvirt-kvm-windows/linux/freebsd#
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) 
    {
	    
		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my $dom = $con->restore_domain($filename);
		print("Domain restored from file $filename\n");
		#&change_vm_status( $dh, $vmName, "running" );
		&change_vm_status( $vmName, "running" );
		return $error;

	}
	else {
		$error = "Type is not yet supported\n";
		return $error;
	}
}



###################################################################
#                                                                 #
#   suspendVM                                                     #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub suspendVM {

	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;

	my $error = 0;

	###################################################################
	#                  suspendVM for libvirt-kvm-windows/linux/freebsd#
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$listDom->suspend();
				print "Domain suspended\n" if ($exemode == $EXE_VERBOSE);
				return $error;
			}
		}
		$error = "Domain does not exist.\n";
		return $error;

	}
	else {
		$error = "Type is not yet supported\n";
		return $error;
	}
}



###################################################################
#                                                                 #
#   resumeVM                                                      #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub resumeVM {

	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;

	my $error = 0;

	# Sample code
	print "dummy plugin: resuming vm $vmName\n" if ($exemode == $EXE_VERBOSE);

	###################################################################
	#                  resumeVM for libvirt-kvm-windows/linux/freebsd #
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$listDom->resume();
				print "Domain resumed\n" if ($exemode == $EXE_VERBOSE);
				return $error;
			}
		}
		$error = "Domain does not exist.\n";
		return $error;

	}
	else {
		$error = "Type is not yet supported\n";
		return $error;
	}
}



###################################################################
#                                                                 #
#   rebootVM                                                      #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub rebootVM {

	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;

	my $error = 0;

	###################################################################
	#                  rebootVM for libvirt-kvm-windows/linux/freebsd #
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$listDom->reboot($Sys::Virt::Domain::REBOOT_RESTART);
				print "Domain rebooting\n" if ($exemode == $EXE_VERBOSE);
				return $error;
			}
		}
		$error = "Domain does not exist\n";
		return $error;

	}
	else {
		$error = "Type is not yet supported\n";
		return $error;
	}

}



###################################################################
#                                                                 #
#   resetVM                                                       #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub resetVM {

	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;

	my $error;

	# Sample code
	print "dummy plugin: reseting vm $vmName\n" if ($exemode == $EXE_VERBOSE);

	###################################################################
	#                  resetVM for libvirt-kvm-windows/linux/freebsd  #
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		my $addr = "qemu:///system";
		print "Connecting to $addr hypervisor..." if ($exemode == $EXE_VERBOSE);
		my $con;
		eval { $con = Sys::Virt->new( address => $addr, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $addr hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vmName ) {
				$listDom->reboot(&Sys::Virt::Domain::REBOOT_DESTROY);
				print "Domain reset" if ($exemode == $EXE_VERBOSE);
				$error = 0;
				return $error;
			}
		}
		$error = "Domain does not exist\n";
		return $error;

	}else {
		$error = "Type is not yet supported\n";
		return $error;
	}
}



###################################################################
#                                                                 #
#   executeCMD                                                    #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub executeCMD {

	my $self = shift;
	my $merged_type = shift;
	my $seq  = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
	my $vm    = shift;
	my $name = shift;

	#Commands sequence (start, stop or whatever).

	# Previous checkings and warnings
#	my @vm_ordered = $dh->get_vm_ordered;
#	my %vm_hash    = $dh->get_vm_to_use(@plugins);

	# First loop: look for uml_mconsole exec capabilities if needed. This
	# loop can cause exit, if capabilities are not accomplished
	my $random_id  = &generate_random_string(6);

	###########################################
	#   executeCMD for WINDOWS                #
	###########################################

	if ( $merged_type eq "libvirt-kvm-windows" ) {
		############ WINDOWS ##############
		############ FILETREE ##############
		my @filetree_list = $dh->merge_filetree($vm);
		my $user   = &get_user_in_seq( $vm, $seq );
		my $mode   = &get_vm_exec_mode($vm);
		my $command =  $bd->get_binaries_path_ref->{"mktemp"} . " -d -p " . $dh->get_hostfs_dir($name)  . " filetree.XXXXXX";
		open COMMAND_FILE, ">" . $dh->get_hostfs_dir($name) . "/filetree.xml" or $execution->smartdie("can not open " . $dh->get_hostfs_dir($name) . "/filetree.xml $!" ) unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		my $verb_prompt_bk = $execution->get_verb_prompt();
		# FIXME: consider to use a different new VNX::Execution object to perform this
		# actions (avoiding this nasty verb_prompt backup)
		$execution->set_verb_prompt("$name> ");
		my $shell      = $dh->get_default_shell;
		my $shell_list = $vm->getElementsByTagName("shell");
		if ( $shell_list->getLength == 1 ) {
			$shell = &text_tag( $shell_list->item(0) );
		}
		my $date_command = $bd->get_binaries_path_ref->{"date"};
		chomp( my $now = `$date_command` );
		my $basename = basename $0;
		$execution->execute( "<filetrees>", *COMMAND_FILE );
		# Insert random id number for the command file
		my $fileid = $name . "-" . &generate_random_string(6);
		$execution->execute(  "<id>" . $fileid ."</id>", *COMMAND_FILE );
		my $countfiletree = 0;
		chomp( my $filetree_host = `$command` );
		$filetree_host =~ /filetree\.(\w+)$/;
		$execution->execute("mkdir " . $filetree_host ."/destination");
		foreach my $filetree (@filetree_list) {
			# To get momment
			my $filetree_seq_string = $filetree->getAttribute("seq");
			# To install subtree (only in the right momment)
			# FIXME: think again the "always issue"; by the moment deactivated

			# JSF 01/12/10: we accept several commands in the same seq tag,
			# separated by spaces
			my @filetree_seqs = split(' ',$filetree_seq_string);
			foreach my $filetree_seq (@filetree_seqs) {
				if ( $filetree_seq eq $seq ) {
					$countfiletree++;
					my $src;
					my $filetree_value = &text_tag($filetree);

					$src = &get_abs_path ($filetree_value);

=BEGIN
					if ( $filetree_value =~ /^\// ) {
						# Absolute pathname
						$src = &do_path_expansion($filetree_value);
					}
					else {
						
				      	# Calculate the efective basedir
      					my $basedir = $dh->get_default_basedir;
      					# Comentado por DFC: esta parte sobre, es el mismo código de get_default_basedir
      					#my $basedir_list = $vm->getElementsByTagName("basedir");
      					#if ($basedir_list->getLength == 1) {
					    #     $basedir = &text_tag($basedir_list->item(0));
				      	#}
						# Relative pathname
						if ( $basedir eq "" ) {
							# Relative to xml_dir
							$src = &do_path_expansion( &chompslash( $dh->get_xml_dir ) . "/$filetree_value" );
						}
						else {
							# Relative to basedir
							$src =  &do_path_expansion(	&chompslash($basedir) . "/$filetree_value" );
						}
					}
=END
=cut

					$src = &chompslash($src);
					my $filetree_vm = "/mnt/hostfs/filetree.$random_id";
					
					$execution->execute("mkdir " . $filetree_host ."/destination/".  $countfiletree);
					$execution->execute( $bd->get_binaries_path_ref->{"cp"} . " -r $src/* $filetree_host" . "/destination/" . $countfiletree );
					my %file_perms = &save_dir_permissions($filetree_host);
					my $dest = $filetree->getAttribute("root");
					my $filetreetxt = $filetree->toString(1); 
					print "$filetreetxt" if ($exemode == $EXE_VERBOSE);
					$execution->execute( "$filetreetxt", *COMMAND_FILE );
				}
			}
		}
		$execution->execute( "</filetrees>", *COMMAND_FILE );
		close COMMAND_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

=BEGIN		
		open( DU, "du -hs0c " . $dh->get_hostfs_dir($name) . " | awk '{ var = \$1; var2 = substr(var,0,length(var)); print var2} ' |") || die "Failed: $!\n";
		my $dimension = <DU>;
		$dimension = $dimension + 20;
		my $dimensiondisk = $dimension + 30;
		close DU unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		open( DU, "du -hs0c " . $dh->get_hostfs_dir($name) . " | awk '{ var = \$1; var3 = substr(var,length(var),length(var)+1); print var3} ' |") || die "Failed: $!\n";
		my $unit = <DU>;
		close DU unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
=END
=cut
		# Calculate dimension and units of hostfs_dir
		my $cmd = "du -hs0c " . $dh->get_hostfs_dir($name); 
		my $dures = `$cmd`;
		my @dures = split (/\t| /,$dures);
		my $dimension=$dures[0];	$dimension=~ s/[B|K|M|G]//;
		my $unit=$dures[0];		$unit=~ s/\d*//;
		print "**** dimension=$dimension, unit=$unit\n" if ($exemode == $EXE_VERBOSE);
		$dimension = $dimension + 20;
		my $dimensiondisk = $dimension + 30;

		if ($countfiletree > 0){
			if (   ( $unit eq "K\n" || $unit eq "B\n" )|| ( ( $unit eq "M\n" ) && ( $dimension <= 32 ) ) ){
				$unit          = 'M';
				$dimension     = 32;
				$dimensiondisk = 50;
			}
			$execution->execute("mkdir /tmp/disk.$random_id");
			$execution->execute("mkdir  /tmp/disk.$random_id/destination");
			$execution->execute( "cp " . $dh->get_hostfs_dir($name) . "/filetree.xml" . " " . "$filetree_host" );
			#$execution->execute( "cp -rL " . $filetree_host . "/*" . " " . "/tmp/disk.$random_id/destination" );
			$execution->execute("mkisofs -R -nobak -follow-links -max-iso9660-filename -allow-leading-dots " . 
			                    "-pad -quiet -allow-lowercase -allow-multidot -o /tmp/disk.$random_id.iso $filetree_host");
							
			my $disk_filetree_windows_xml;
			$disk_filetree_windows_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
			
			my $disk_filetree_windows_tag = $disk_filetree_windows_xml->createElement('disk');
			$disk_filetree_windows_xml->addChild($disk_filetree_windows_tag);
			$disk_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( type => "file" ) );
			$disk_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( device => "cdrom" ) );
			
			my $driver_filetree_windows_tag =$disk_filetree_windows_xml->createElement('driver');
			$disk_filetree_windows_tag->addChild($driver_filetree_windows_tag);
			$driver_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( name => "qemu" ) );
			$driver_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( cache => "default" ) );
			
			my $source_filetree_windows_tag =$disk_filetree_windows_xml->createElement('source');
			$disk_filetree_windows_tag->addChild($source_filetree_windows_tag);
			$source_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( file => "/tmp/disk.$random_id.iso" ) );
			
			my $target_filetree_windows_tag =$disk_filetree_windows_xml->createElement('target');
			$disk_filetree_windows_tag->addChild($target_filetree_windows_tag);
			$target_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( dev => "hdb" ) );
			
			my $readonly_filetree_windows_tag =$disk_filetree_windows_xml->createElement('readonly');
			$disk_filetree_windows_tag->addChild($readonly_filetree_windows_tag);
			my $format_filetree_windows   = 1;
			my $xmlstring_filetree_windows = $disk_filetree_windows_xml->toString($format_filetree_windows );
			
			$execution->execute("rm -f ". $dh->get_hostfs_dir($name) . "/filetree_libvirt.xml"); 
			open XML_FILETREE_WINDOWS_FILE, ">" . $dh->get_hostfs_dir($name) . '/' . 'filetree_libvirt.xml'
	 			or $execution->smartdie("can not open " . $dh->get_hostfs_dir . '/' . 'filetree_libvirt.xml' )
	  			unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
			print XML_FILETREE_WINDOWS_FILE "$xmlstring_filetree_windows\n";
			close XML_FILETREE_WINDOWS_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
			
			#$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/disk.$random_id.iso hdb --mode readonly --driver file --type cdrom'");
			$execution->execute("virsh -c qemu:///system 'attach-device \"$name\" ". $dh->get_hostfs_dir($name) . "/filetree_libvirt.xml'");
			print "Copying file tree in client, through socket: \n" . $dh->get_vm_dir($name). '/'.$name.'_socket' if ($exemode == $EXE_VERBOSE);
			waitfiletree($dh->get_vm_dir($name) .'/'.$name.'_socket');
			sleep(4);
			# 3d. Cleaning
			$execution->execute("rm /tmp/disk.$random_id.iso");
			$execution->execute("rm -r /tmp/disk.$random_id");
			$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" );
			$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_hostfs_dir($name) . "/filetree.$random_id" );
			$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -rf $filetree_host" );
			$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id" );
			$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree.xml" );
			$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id.end" );
		}
		############ COMMAND_FILE ########################
		# We open file
		open COMMAND_FILE,">" . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" or $execution->smartdie("can not open " . $dh->get_tmp_dir . "/vnx.$name.$seq: $!" )
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

		# FIXME: consider to use a different new VNX::Execution object to perform this
		# actions (avoiding this nasty verb_prompt backup)
		$execution->set_verb_prompt("$name> ");
		$cmd = $bd->get_binaries_path_ref->{"date"};
		chomp( $now = `$cmd` );

		# To process exec tags of matching commands sequence
		my $command_list = $vm->getElementsByTagName("exec");

		# To process list, dumping commands to file
		$execution->execute( "<command>", *COMMAND_FILE );
		
		# Insert random id number for the command file
		$fileid = $name . "-" . &generate_random_string(6);
		$execution->execute(  "<id>" . $fileid ."</id>", *COMMAND_FILE );
		my $countcommand = 0;
		for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
			my $command = $command_list->item($j);	
			# To get attributes
			my $cmd_seq_string = $command->getAttribute("seq");
			
			# JSF 01/12/10: we accept several commands in the same seq tag,
			# separated by spaces
			my @cmd_seqs = split(' ',$cmd_seq_string);
			foreach my $cmd_seq (@cmd_seqs) {
			
				if ( $cmd_seq eq $seq ) {
					my $type = $command->getAttribute("type");
					# Case 1. Verbatim type
					if ( $type eq "verbatim" ) {
						# Including command "as is"
						my $comando = $command->toString(1);
						$execution->execute( $comando, *COMMAND_FILE );
						$countcommand = $countcommand + 1;
					}

					# Case 2. File type
					elsif ( $type eq "file" ) {
						# We open the file and write commands line by line
						my $include_file =  &do_path_expansion( &text_tag($command) );
						open INCLUDE_FILE, "$include_file"
						  or $execution->smartdie("can not open $include_file: $!");
						while (<INCLUDE_FILE>) {
							chomp;
							$execution->execute(
								#"<exec seq=\"file\" type=\"file\">" 
								  #. $_
								  #. "</exec>",
								  $_,
								*COMMAND_FILE
							);
							$countcommand = $countcommand + 1;
						}
						close INCLUDE_FILE;
					}

			 # Other case. Don't do anything (it would be and error in the XML!)
				}
			}
		}
		$execution->execute( "</command>", *COMMAND_FILE );
		# We close file and mark it executable
		close COMMAND_FILE
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		$execution->set_verb_prompt($verb_prompt_bk);
		$execution->execute( $bd->get_binaries_path_ref->{"chmod"} . " a+x " . $dh->get_tmp_dir  . "/vnx.$name.$seq.$random_id" );
		############# INSTALL COMMAND FILES #############
		# Nothing to do in libvirt mode
		############# EXEC_COMMAND_FILE #################
		
		if ( $countcommand != 0 ) {
			$execution->execute("mkdir /tmp/diskc.$seq.$random_id");
			$execution->execute( "cp " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" . " " . "/tmp/diskc.$seq.$random_id/" . "command.xml" );
			$execution->execute("mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/diskc.$seq.$random_id.iso /tmp/diskc.$seq.$random_id/");
			
			my $disk_command_windows_xml;
			$disk_command_windows_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
			
			my $disk_command_windows_tag = $disk_command_windows_xml->createElement('disk');
			$disk_command_windows_xml->addChild($disk_command_windows_tag);
			$disk_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( type => "file" ) );
			$disk_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( device => "cdrom" ) );
			
			my $driver_command_windows_tag =$disk_command_windows_xml->createElement('driver');
			$disk_command_windows_tag->addChild($driver_command_windows_tag);
			$driver_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( name => "qemu" ) );
			$driver_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( cache => "default" ) );
			
			my $source_command_windows_tag =$disk_command_windows_xml->createElement('source');
			$disk_command_windows_tag->addChild($source_command_windows_tag);
			$source_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( file => "/tmp/diskc.$seq.$random_id.iso" ) );
			
			my $target_command_windows_tag =$disk_command_windows_xml->createElement('target');
			$disk_command_windows_tag->addChild($target_command_windows_tag);
			$target_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( dev => "hdb" ) );
			
			my $readonly_command_windows_tag =$disk_command_windows_xml->createElement('readonly');
			$disk_command_windows_tag->addChild($readonly_command_windows_tag);
			my $format_command_windows   = 1;
			my $xmlstring_command_windows = $disk_command_windows_xml->toString($format_command_windows );
			
			$execution->execute("rm ". $dh->get_hostfs_dir($name) . "/command_libvirt.xml"); 
			
			open XML_COMMAND_WINDOWS_FILE, ">" . $dh->get_hostfs_dir($name) . '/' . 'command_libvirt.xml'
	 			 or $execution->smartdie("can not open " . $dh->get_hostfs_dir . '/' . 'command_libvirt.xml' )
	  		unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
			print XML_COMMAND_WINDOWS_FILE "$xmlstring_command_windows\n";
			close XML_COMMAND_WINDOWS_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
			$execution->execute("virsh -c qemu:///system 'attach-device \"$name\" ". $dh->get_hostfs_dir($name) . "/command_libvirt.xml'");
			#$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/diskc.$seq.$random_id.iso hdb --mode readonly --driver file --type cdrom'");
			print "Sending command to client... \n" if ($exemode == $EXE_VERBOSE);
			waitexecute($dh->get_vm_dir($name).'/'.$name.'_socket');
			$execution->execute("rm /tmp/diskc.$seq.$random_id.iso");
			$execution->execute("rm -r /tmp/diskc.$seq.$random_id");
			$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" );
		    sleep(2);
		}

	###########################################
	#   executeCMD for LINUX & FREEBSD        #
	###########################################
			
	}elsif (($merged_type eq "libvirt-kvm-linux") || ($merged_type eq "libvirt-kvm-freebsd") ) {
		          	          	
		############### LINUX ####################
		############### FILETREE #################
		my @filetree_list = $dh->merge_filetree($vm);
		my $user   = &get_user_in_seq( $vm, $seq );
		my $mode   = &get_vm_exec_mode($vm);
		my $command =  $bd->get_binaries_path_ref->{"mktemp"} . " -d -p " . $dh->get_hostfs_dir($name)  . " filetree.XXXXXX";
		open COMMAND_FILE, ">" . $dh->get_hostfs_dir($name) . "/filetree.xml" or $execution->smartdie("can not open " . $dh->get_hostfs_dir($name) . "/filetree.xml $!" ) unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		my $verb_prompt_bk = $execution->get_verb_prompt();
		# FIXME: consider to use a different new VNX::Execution object to perform this
		# actions (avoiding this nasty verb_prompt backup)
		$execution->set_verb_prompt("$name> ");
		my $shell      = $dh->get_default_shell;
		my $shell_list = $vm->getElementsByTagName("shell");
		if ( $shell_list->getLength == 1 ) {
			$shell = &text_tag( $shell_list->item(0) );
		}
		my $date_command = $bd->get_binaries_path_ref->{"date"};
		chomp( my $now = `$date_command` );
		my $basename = basename $0;
		$execution->execute( "<filetrees>", *COMMAND_FILE );
		# Insert random id number for the command file
		my $fileid = $name . "-" . &generate_random_string(6);
		$execution->execute(  "<id>" . $fileid ."</id>", *COMMAND_FILE );
		my $countfiletree = 0;
		chomp( my $filetree_host = `$command` );
		$filetree_host =~ /filetree\.(\w+)$/;
		$execution->execute("mkdir " . $filetree_host ."/destination");
		foreach my $filetree (@filetree_list) {
			# To get momment
			my $filetree_seq_string = $filetree->getAttribute("seq");
			
			# JSF 01/12/10: we accept several commands in the same seq tag,
			# separated by spaces
			my @filetree_seqs = split(' ',$filetree_seq_string);
			foreach my $filetree_seq (@filetree_seqs) {
			
				# To install subtree (only in the right momment)
				# FIXME: think again the "always issue"; by the moment deactivated
				if ( $filetree_seq eq $seq ) {
					$countfiletree++;
					my $src;
					my $filetree_value = &text_tag($filetree);

					$src = &get_abs_path ($filetree_value);
=BEGIN
					if ( $filetree_value =~ /^\// ) {
					# Absolute pathname
					$src = &do_path_expansion($filetree_value);
					}
					else {
				      	# Calculate the efective basedir
      					my $basedir = $dh->get_default_basedir;
      					my $basedir_list = $vm->getElementsByTagName("basedir");
      					if ($basedir_list->getLength == 1) {
					         $basedir = &text_tag($basedir_list->item(0));
				      	}
						# Relative pahtname
						if ( $basedir eq "" ) {
						# Relative to xml_dir
							$src = &do_path_expansion( &chompslash( $dh->get_xml_dir ) . "/$filetree_value" );
						}
						else {
						# Relative to basedir
							$src =  &do_path_expansion(	&chompslash($basedir) . "/$filetree_value" );
						}
					}
=END
=cut

					$src = &chompslash($src);
					my $filetree_vm = "/mnt/hostfs/filetree.$random_id";
					
					$execution->execute("mkdir " . $filetree_host ."/destination/".  $countfiletree);
					$execution->execute( $bd->get_binaries_path_ref->{"cp"} . " -r $src/* $filetree_host" . "/destination/" . $countfiletree );
					my %file_perms = &save_dir_permissions($filetree_host);
					my $dest = $filetree->getAttribute("root");
					my $filetreetxt = $filetree->toString(1);
					$execution->execute( "$filetreetxt", *COMMAND_FILE );
				}
			}
		}
		$execution->execute( "</filetrees>", *COMMAND_FILE );
		close COMMAND_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

=BEGIN		
		open( DU, "du -hs0c " . $dh->get_hostfs_dir($name) . " | awk '{ var = \$1; var2 = substr(var,0,length(var)); print var2} ' |") || die "Failed: $!\n";
		my $dimension = <DU>;
		print "**** dimension = $dimension\n";
		print "**** host_fs_dir=" . $dh->get_hostfs_dir($name);
		$dimension = $dimension + 20;
		my $dimensiondisk = $dimension + 30;
		close DU unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		open( DU, "du -hs0c " . $dh->get_hostfs_dir($name) . " | awk '{ var = \$1; var3 = substr(var,length(var),length(var)+1); print var3} ' |") || die "Failed: $!\n";
		my $unit = <DU>;
		print "**** unit = $unit\n";
		close DU unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
=END
=cut
		# Calculate dimension and units of hostfs_dir
		my $cmd = "du -hs0c " . $dh->get_hostfs_dir($name); 
		my $dures = `$cmd`;
		my @dures = split (/\t| /,$dures);
		my $dimension=$dures[0];	$dimension=~ s/[B|K|M|G]//;
		my $unit=$dures[0];		$unit=~ s/\d*//;
		print "**** dimension=$dimension, unit=$unit\n" if ($exemode == $EXE_VERBOSE);
		$dimension = $dimension + 20;
		my $dimensiondisk = $dimension + 30;

		if ($countfiletree > 0){
			if (   ( $unit eq "K\n" || $unit eq "B\n" )|| ( ( $unit eq "M\n" ) && ( $dimension <= 32 ) ) ){
				$unit          = 'M';
				$dimension     = 32;
				$dimensiondisk = 50;
			}
			$execution->execute("mkdir /tmp/disk.$random_id");
			$execution->execute("mkdir  /tmp/disk.$random_id/destination");
			$execution->execute( "cp " . $dh->get_hostfs_dir($name) . "/filetree.xml" . " " . "$filetree_host" );
			#$execution->execute( "cp -rL " . $filetree_host . "/*" . " " . "/tmp/disk.$random_id/destination" );
			$execution->execute("mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/disk.$random_id.iso $filetree_host");
			$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/disk.$random_id.iso hdb --mode readonly --driver file --type cdrom'");
			print "Copying file tree in client, through socket: \n" . $dh->get_vm_dir($name). '/'.$name.'_socket' if ($exemode == $EXE_VERBOSE);
			waitfiletree($dh->get_vm_dir($name) .'/'.$name.'_socket');
			# mount empty iso, while waiting for new command	
			$execution->execute("touch /tmp/empty.iso");
			$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/empty.iso hdb --mode readonly --driver file --type cdrom'");
			sleep 1;
		   	# 3d. Cleaning
			$execution->execute("rm /tmp/empty.iso");
			$execution->execute("rm /tmp/disk.$random_id.iso");
			$execution->execute("rm -r /tmp/disk.$random_id");
			$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" );
			$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_hostfs_dir($name) . "/filetree.$random_id" );
			$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -rf $filetree_host" );
			$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id" );
			$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree.xml" );
			$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id.end" );
		}
		############ COMMAND_FILE ########################

		# We open file
		open COMMAND_FILE,">" . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" or $execution->smartdie("can not open " . $dh->get_tmp_dir . "/vnx.$name.$seq: $!" )
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		# FIXME: consider to use a different new VNX::Execution object to perform this
		# actions (avoiding this nasty verb_prompt backup)
		$execution->set_verb_prompt("$name> ");
		$cmd = $bd->get_binaries_path_ref->{"date"};
		chomp( $now = `$command` );

		# $execution->execute("#!" . $shell,*COMMAND_FILE);
		# $execution->execute("#commands sequence: $seq",*COMMAND_FILE);
		# $execution->execute("#file generated by $basename $version$branch at $now",*COMMAND_FILE);

		# To process exec tags of matching commands sequence
		my $command_list = $vm->getElementsByTagName("exec");

		# To process list, dumping commands to file
		$execution->execute( "<command>", *COMMAND_FILE );
		
		# Insert random id number for the command file
		$fileid = $name . "-" . &generate_random_string(6);
		$execution->execute(  "<id>" . $fileid ."</id>", *COMMAND_FILE );
		
		my $countcommand = 0;
		for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
			my $command = $command_list->item($j);

			# To get attributes
			my $cmd_seq_string = $command->getAttribute("seq");
			my $type    = $command->getAttribute("type");
            my $typeos = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));


			# JSF 01/12/10: we accept several commands in the same seq tag,
			# separated by spaces
#print "cmd_seq_string=$cmd_seq_string\n";		
			my @cmd_seqs = split(' ',$cmd_seq_string);
			foreach my $cmd_seq (@cmd_seqs) {
#print "cmd_seq=$cmd_seq\n";
				if ( $cmd_seq eq $seq ) {

					# Case 1. Verbatim type
					if ( $type eq "verbatim" ) {

						# Including command "as is"

						#$execution->execute("<comando>",*COMMAND_FILE);
						my $comando = $command->toString(1);
						$execution->execute( $comando, *COMMAND_FILE );

						#$execution->execute("</comando>",*COMMAND_FILE);
						$countcommand = $countcommand + 1;

					}

					# Case 2. File type
					elsif ( $type eq "file" ) {

						# We open the file and write commands line by line
						my $include_file = &do_path_expansion( &text_tag($command) );
						open INCLUDE_FILE, "$include_file" or $execution->smartdie("can not open $include_file: $!");
						while (<INCLUDE_FILE>) {
							chomp;
							$execution->execute(
								#"<exec seq=\"file\" type=\"file\">" 
								  #. $_
								  #. "</exec>",
								  $_,
								*COMMAND_FILE
							);
							$countcommand = $countcommand + 1;
						}
						close INCLUDE_FILE;
					}

			 # Other case. Don't do anything (it would be and error in the XML!)
				}
			}
		}
		$execution->execute( "</command>", *COMMAND_FILE );
		# We close file and mark it executable
		close COMMAND_FILE
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		$execution->set_verb_prompt($verb_prompt_bk);
		$execution->execute( $bd->get_binaries_path_ref->{"chmod"} . " a+x " . $dh->get_tmp_dir  . "/vnx.$name.$seq.$random_id" );
		############# INSTALL COMMAND FILES #############
		# Nothing to do in ibvirt mode
		############# EXEC_COMMAND_FILE #################
		if ( $countcommand != 0 ) {
			$execution->execute("mkdir /tmp/diskc.$seq.$random_id");
			$execution->execute( "cp " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id" . " " . "/tmp/diskc.$seq.$random_id/" . "command.xml" );
			$execution->execute("mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/diskc.$seq.$random_id.iso /tmp/diskc.$seq.$random_id/");
			$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/diskc.$seq.$random_id.iso hdb --mode readonly --driver file --type cdrom'");
			print "Sending command to client... \n" if ($exemode == $EXE_VERBOSE);			
			waitexecute($dh->get_vm_dir($name).'/'.$name.'_socket');
			# mount empty iso, while waiting for new command	
			$execution->execute("touch /tmp/empty.iso");
			$execution->execute("virsh -c qemu:///system 'attach-disk \"$name\" /tmp/empty.iso hdb --mode readonly --driver file --type cdrom'"	);
			sleep 1;
			$execution->execute("rm /tmp/empty.iso");		
			$execution->execute("rm /tmp/diskc.$seq.$random_id.iso");
			$execution->execute("rm -r /tmp/diskc.$seq.$random_id");
			$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir  . "/vnx.$name.$seq.$random_id" );
			sleep(2);
		}
				
		################## EXEC_COMMAND_HOST ########################3

		my $doc = $dh->get_doc;
	
		# If host <host> is not present, there is nothing to do
		return if ( $doc->getElementsByTagName("host")->getLength eq 0 );
	
		# To get <host> tag
		my $host = $doc->getElementsByTagName("host")->item(0);
	
		# To process exec tags of matching commands sequence
		my $command_list_host = $host->getElementsByTagName("exec");
	
		# To process list, dumping commands to file
		for ( my $j = 0 ; $j < $command_list_host->getLength ; $j++ ) {
			my $command = $command_list_host->item($j);
	
			# To get attributes
			my $cmd_seq = $command->getAttribute("seq");
			my $type    = $command->getAttribute("type");
	
			if ( $cmd_seq eq $seq ) {
	
				# Case 1. Verbatim type
				if ( $type eq "verbatim" ) {
	
					# To include the command "as is"
					$execution->execute( &text_tag_multiline($command) );
				}
	
				# Case 2. File type
				elsif ( $type eq "file" ) {
	
					# We open file and write commands line by line
					my $include_file = &do_path_expansion( &text_tag($command) );
					open INCLUDE_FILE, "$include_file"
					  or $execution->smartdie("can not open $include_file: $!");
					while (<INCLUDE_FILE>) {
						chomp;
						$execution->execute($_);
					}
					close INCLUDE_FILE;
				}
	
				# Other case. Don't do anything (it would be an error in the XML!)
			}
		}
		
	###########################################
	#   executeCMD for OLIVE                  #
	###########################################

	} elsif ( ($merged_type eq "libvirt-kvm-olive") ) {
		          	          	
      	# Calculate the efective basedir
      	my $basedir = $dh->get_default_basedir;
      	my $basedir_list = $vm->getElementsByTagName("basedir");
      	if ($basedir_list->getLength == 1) {
		        $basedir = &text_tag($basedir_list->item(0));
		}

		# We create the command.xml file to be passed to the vm		
		my @filetree_list = $dh->merge_filetree($vm);
		my $user   = &get_user_in_seq( $vm, $seq );
		my $mode   = &get_vm_exec_mode($vm);
		open COMMAND_FILE, ">" . $dh->get_vm_tmp_dir($name) . "/command.xml" 
		   or $execution->smartdie("can not open " . $dh->get_vm_tmp_dir($name) . "/command.xml $!" ) 
		   unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		my $verb_prompt_bk = $execution->get_verb_prompt();
		# FIXME: consider to use a different new VNX::Execution object to perform this
		# actions (avoiding this nasty verb_prompt backup)
		$execution->set_verb_prompt("$name> ");
		my $shell      = $dh->get_default_shell;
		my $shell_list = $vm->getElementsByTagName("shell");
		if ( $shell_list->getLength == 1 ) {
			$shell = &text_tag( $shell_list->item(0) );
		}
		$execution->execute( "<command>", *COMMAND_FILE );
		# Insert random id number for the command file
		my $fileid = $name . "-" . &generate_random_string(6);
		$execution->execute(  "<id>" . $fileid ."</id>", *COMMAND_FILE );
		my $countfiletree = 0;

		# Mount the shared disk to copy filetree files
		my $sdisk_fname = $dh->get_fs_dir($name) . "/sdisk.img";
		my $vmmnt_dir = $dh->get_mnt_dir($name);
		$execution->execute( $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $vmmnt_dir );
		# Delete the previous content of the shared disk
		$execution->execute( "rm -rf $vmmnt_dir/destination/*");
		$execution->execute( "rm -rf $vmmnt_dir/command.xml");
		$execution->execute( "rm -rf $vmmnt_dir/vnxboot.xml");

		$execution->execute("mkdir -p $vmmnt_dir/destination");
		foreach my $filetree (@filetree_list) {
			# To get momment
			my $filetree_seq_string = $filetree->getAttribute("seq");
	
			# JSF 01/12/10: we accept several commands in the same seq tag,
			# separated by spaces
			my @filetree_seqs = split(' ',$filetree_seq_string);
			foreach my $filetree_seq (@filetree_seqs) {
			
				# To install subtree (only in the right momment)
				# FIXME: think again the "always issue"; by the moment deactivated
				if ( $filetree_seq eq $seq ) {
					$countfiletree++;
					my $src;
					my $filetree_value = &text_tag($filetree);

					$src = &get_abs_path ($filetree_value);

=BEGIN
					if ( $filetree_value =~ /^\// ) {
						# Absolute pathname
						$src = &do_path_expansion($filetree_value);
					}
					else { # Relative pahtname
						if ( $basedir eq "" ) {
						# Relative to xml_dir
							$src = &do_path_expansion( &chompslash( $dh->get_xml_dir ) . "/$filetree_value" );
						}
						else {
						# Relative to basedir
							$src =  &do_path_expansion(	&chompslash($basedir) . "/$filetree_value" );
						}
					}
=END
=cut

					$src = &chompslash($src);
					$execution->execute("mkdir $vmmnt_dir/destination/".  $countfiletree);
					$execution->execute( $bd->get_binaries_path_ref->{"cp"} . " -r $src/* $vmmnt_dir/destination/" . $countfiletree );
					my %file_perms = &save_dir_permissions($vmmnt_dir);
					my $dest = $filetree->getAttribute("root");
					my $filetreetxt = $filetree->toString(1);
					$execution->execute( "$filetreetxt", *COMMAND_FILE );
				}
			}
		}
		$execution->set_verb_prompt("$name> ");
		my $command = $bd->get_binaries_path_ref->{"date"};
		chomp( my $now = `$command` );

		# We process exec tags matching the commands sequence string ($sec)
		my $command_list = $vm->getElementsByTagName("exec");
		my $countcommand = 0;
		for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
			my $command = $command_list->item($j);

			# To get attributes
			my $cmd_seq_string = $command->getAttribute("seq");
			my $type    = $command->getAttribute("type");
            my $typeos = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));

			# JSF 01/12/10: we accept several commands in the same seq tag,
			# separated by spaces
			#print "cmd_seq_string=$cmd_seq_string\n";		
			my @cmd_seqs = split(' ',$cmd_seq_string);
			foreach my $cmd_seq (@cmd_seqs) {
			#print "cmd_seq=$cmd_seq\n";
				if ( $cmd_seq eq $seq ) {

					# Case 1. Verbatim type
					if ( $type eq "verbatim" ) {
						# Including command "as is"
						my $comando = $command->toString(1);
						$execution->execute( $comando, *COMMAND_FILE );
						$countcommand = $countcommand + 1;
						my $ostype = $command->getAttribute("ostype");
						if ( $ostype eq "load" ) {
							# We have to copy the configuration file to the shared disk
							my @aux = split(' ', &text_tag($command));
							print "*** config file = $aux[1]\n" if ($exemode == $EXE_VERBOSE);
							# TODO: relative pathname
							my $src = &get_abs_path ($aux[1]);
=BEGIN							
							if ( $aux[1] =~ /^\// ) {
								# Absolute pathname
								$src = &do_path_expansion($aux[1]);
							}
							else { # Relative pahtname
								if ( $basedir eq "" ) {
								# Relative to xml_dir
									$src = &do_path_expansion( &chompslash( $dh->get_xml_dir ) . "/$aux[1]" );
								}
								else {
								# Relative to basedir
									$src =  &do_path_expansion(	&chompslash($basedir) . "/$aux[1]" );
								}
							}
=END
=cut							
							
							
							$src = &chompslash($src);
							$execution->execute( $bd->get_binaries_path_ref->{"cp"} . " $src $vmmnt_dir");													
						}			
						
					}

					# Case 2. File type
					elsif ( $type eq "file" ) {
						# We open the file and write commands line by line
						my $include_file = &do_path_expansion( &text_tag($command) );
						open INCLUDE_FILE, "$include_file" or $execution->smartdie("can not open $include_file: $!");
						while (<INCLUDE_FILE>) {
							chomp;
							$execution->execute(
								#"<exec seq=\"file\" type=\"file\">" 
								  #. $_
								  #. "</exec>",
								  $_,
								*COMMAND_FILE
							);
							$countcommand = $countcommand + 1;
						}
						close INCLUDE_FILE;
					}
			 # Other case. Don't do anything (it would be and error in the XML!)
				}
			}
		}
		$execution->execute( "</command>", *COMMAND_FILE );
		# We close file and mark it executable
		close COMMAND_FILE
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		$execution->set_verb_prompt($verb_prompt_bk);
        #$execution->execute( "cat " . $dh->get_vm_tmp_dir($name) . "/command.xml" ); 

		# Copy command.xml file to shared disk
		$execution->execute( "cp " . $dh->get_vm_tmp_dir($name) . "/command.xml $vmmnt_dir" );
		# Dismount shared disk
		$execution->execute( $bd->get_binaries_path_ref->{"umount"} . " " . $dh->get_mnt_dir($name) );

 		# Send the exeCommand order to the virtual machine using the socket
		my $socket_fh = $dh->get_vm_dir($name). '/' . $name . '_socket';
		my $vmsocket = IO::Socket::UNIX->new(
		   Type => SOCK_STREAM,
		   Peer => $socket_fh,
		) or die("Can't connect to server: $!\n");
		print $vmsocket "exeCommand\n";		
		readSocketResponse ($vmsocket);

		################## EXEC_COMMAND_HOST ########################3

		my $doc = $dh->get_doc;
	
		# If host <host> is not present, there is nothing to do
		return if ( $doc->getElementsByTagName("host")->getLength eq 0 );
	
		# To get <host> tag
		my $host = $doc->getElementsByTagName("host")->item(0);
	
		# To process exec tags of matching commands sequence
		my $command_list_host = $host->getElementsByTagName("exec");
	
		# To process list, dumping commands to file
		for ( my $j = 0 ; $j < $command_list_host->getLength ; $j++ ) {
			my $command = $command_list_host->item($j);
	
			# To get attributes
			my $cmd_seq = $command->getAttribute("seq");
			my $type    = $command->getAttribute("type");
	
			if ( $cmd_seq eq $seq ) {
	
				# Case 1. Verbatim type
				if ( $type eq "verbatim" ) {
	
					# To include the command "as is"
					$execution->execute( &text_tag_multiline($command) );
				}
	
				# Case 2. File type
				elsif ( $type eq "file" ) {
	
					# We open file and write commands line by line
					my $include_file = &do_path_expansion( &text_tag($command) );
					open INCLUDE_FILE, "$include_file"
					  or $execution->smartdie("can not open $include_file: $!");
					while (<INCLUDE_FILE>) {
						chomp;
						$execution->execute($_);
					}
					close INCLUDE_FILE;
				}
	
				# Other case. Don't do anything (it would be an error in the XML!)
			}
		}
	}
		
		
}

sub readSocketResponse 
{
	my $socket = shift;
        #print "readResponse\n";
	while (1) {
		my $line = <$socket>;
		#chomp ($line);		
		print "** $line" if ($exemode == $EXE_VERBOSE);
		last if ( ( $line =~ /^OK/) || ( $line =~ /^NOTOK/) );
	}

	print "----------------------------\n" if ($exemode == $EXE_VERBOSE);

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




###################################################################
# get_admin_address
#
# Returns a four elements list:
#
# - network address
# - network mask
# - IPv4 address of one peer
# - IPv4 address of the other peer
#
# This functions takes a single argument, an integer which acts as counter
# for UML'. It uses NetAddr::IP objects to calculate addresses for TWO hosts,
# whose addresses and mask returns.
#
# Private addresses of 192.168. prefix are used. For now, this is
# hardcoded in this function. It could, and should, i think, become
# part of the VNUML dtd.
#
# In VIRTUAL SWITCH MODE (net_sw) this function ...
# which returns UML ip undefined. Or, if one needs UML ip, function 
# takes two arguments: $vm object and interface id. Interface id zero 
# is reserved for management interface, and is default is none is supplied
sub get_admin_address {

   my $seed = shift;
   my $vmmgmt_type = shift;
   my $vmmgmt_net = shift;
   my $vmmgmt_mask = shift;
   my $vmmgmt_offset = shift;
   my $vmmgmt_hostip = shift;
   my $hostnum = shift;
   my $ip;

   my $net = NetAddr::IP->new($vmmgmt_net."/".$vmmgmt_mask);
   if ($vmmgmt_type eq 'private') {
	   # check to make sure that the address space won't wrap
	   if ($vmmgmt_offset + ($seed << 2) > (1 << (32 - $vmmgmt_mask)) - 3) {
		   $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
	   }

	   # create a private subnet from the seed
	   $net += $vmmgmt_offset + ($seed << 2);
	   $ip = NetAddr::IP->new($net->addr()."/30") + $hostnum;
   } else {
	   # vmmgmt type is 'net'

	   # don't assign the hostip
	   my $hostip = NetAddr::IP->new($vmmgmt_hostip."/".$vmmgmt_mask);
	   if ($hostip > $net + $vmmgmt_offset &&
		   $hostip <= $net + $vmmgmt_offset + $seed + 1) {
		   $seed++;
	   }

	   # check to make sure that the address space won't wrap
	   if ($vmmgmt_offset + $seed > (1 << (32 - $vmmgmt_mask)) - 3) {
		   $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
	   }

	   # return an address in the vmmgmt subnet
	   $ip = $net + $vmmgmt_offset + $seed + 1;
   }
   return $ip;
}




###################################################################
#
sub UML_plugins_conf {

	my $path   = shift;
	my $vm     = shift;
	my $number = shift;

	my $basename = basename $0;

	my $name = $vm->getAttribute("name");

	open CONFILE, ">$path" . "plugins_conf.sh"
	  or $execution->smartdie("can not open ${path}plugins_conf.sh: $!")
	  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
	my $verb_prompt_bk = $execution->get_verb_prompt();

# FIXME: consider to use a different new VNX::Execution object to perform this
# actions (avoiding this nasty verb_prompt backup)
	$execution->set_verb_prompt("$name> ");

	# We begin plugin configuration script
	my $shell      = $dh->get_default_shell;
	my $shell_list = $vm->getElementsByTagName("shell");
	if ( $shell_list->getLength == 1 ) {
		$shell = &text_tag( $shell_list->item(0) );
	}
	my $command = $bd->get_binaries_path_ref->{"date"};
	chomp( my $now = `$command` );
	$execution->execute( "#!" . $shell, *CONFILE );
	$execution->execute(
		"# plugin configuration script generated by $basename at $now",
		*CONFILE );
	$execution->execute( "UTILDIR=/mnt/vnx", *CONFILE );

	my $at_least_one_file = "0";
	foreach my $plugin (@plugins) {
		my %files = $plugin->bootingCreateFiles($name);

		if ( defined( $files{"ERROR"} ) && $files{"ERROR"} ne "" ) {
			$execution->smartdie(
				"plugin $plugin bootingCreateFiles($name) error: "
				  . $files{"ERROR"} );
		}

		foreach my $key ( keys %files ) {

			# Create the directory to hold de file (idempotent operation)
			my $dir = dirname($key);
			mkpath( "$path/plugins_root/$dir", { verbose => 0 } );
			$execution->set_verb_prompt($verb_prompt_bk);
			$execution->execute( $bd->get_binaries_path_ref->{"cp"}
				  . " $files{$key} $path/plugins_root/$key" );
			$execution->set_verb_prompt("$name(plugins)> ");

			# Remove the file in the host (this is part of the plugin API)
			$execution->execute(
				$bd->get_binaries_path_ref->{"rm"} . " $files{$key}" );

			$at_least_one_file = 1;

		}

		my @commands = $plugin->bootingCommands($name);

		my $error = shift(@commands);
		if ( $error ne "" ) {
			$execution->smartdie(
				"plugin $plugin bootingCommands($name) error: $error");
		}

		foreach my $cmd (@commands) {
			$execution->execute( $cmd, *CONFILE );
		}
	}

	if ($at_least_one_file) {

		# The last commands in plugins_conf.sh is to push plugin_root/ to vm /
		$execution->execute(
			"# Generated by $basename to push files generated by plugins",
			*CONFILE );
		$execution->execute( "cp -r \$UTILDIR/plugins_root/* /", *CONFILE );
	}

	# Close file and restore prompting method
	$execution->set_verb_prompt($verb_prompt_bk);
	close CONFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

	# Configuration file must be executable
	$execution->execute( $bd->get_binaries_path_ref->{"chmod"}
		  . " a+x $path"
		  . "plugins_conf.sh" );

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
	my $net_list = $doc->getElementsByTagName("net");

	# To process list
	for ( my $i = 0 ; $i < $net_list->getLength ; $i++ ) {
		my $net  = $net_list->item($i);
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

	my $if_list = $vm->getElementsByTagName("if");
	for ( my $i = 0 ; $i < $if_list->getLength ; $i++ ) {
		my $id = $if_list->item($i)->getAttribute("id");
		if (   ( $id == 0 )
			&& $dh->get_vmmgmt_type ne 'none'
			&& ( $mng_if_value ne "no" ) )
		{

			# Skip the management interface
			# Actually is a redundant checking, because check_semantics doesn't
			# allow a id=0 <if> if managemente interface hasn't been disabled
			next;
		}
		my $ipv4_list = $if_list->item($i)->getElementsByTagName("ipv4");
		if ( $ipv4_list->getLength != 0 ) {
			my $ip = &text_tag( $ipv4_list->item(0) );
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
sub waitfiletree {

	my $socket_path = shift;
	
	my $socket = IO::Socket::UNIX->new(
	   Type => SOCK_STREAM,
	   Peer => $socket_path,
	)
	   or die("Can't connect to server: $!\n");
	
	chomp( my $line = <$socket> );
	print qq{Done. \n};
	sleep(2);
	$socket->close();

}



###################################################################
#
sub waitexecute {

	my $socket_path = shift;
	my $numprocess = shift;
	my $i;
	my $socket = IO::Socket::UNIX->new(
		   Type => SOCK_STREAM,
		   Peer => $socket_path,
			)
   			or die("Can't connect to server: $!\n");
	chomp( my $line = <$socket> );
	print qq{Done. \n};
	sleep(2);
	$socket->close();

}



###################################################################
#
sub get_user_in_seq {

	my $vm  = shift;
	my $seq = shift;

	my $username = "";

	# Looking for in <exec>
	my $exec_list = $vm->getElementsByTagName("exec");
	for ( my $i = 0 ; $i < $exec_list->getLength ; $i++ ) {
		if ( $exec_list->item($i)->getAttribute("seq") eq $seq ) {
			if ( $exec_list->item($i)->getAttribute("user") ne "" ) {
				$username = $exec_list->item($i)->getAttribute("user");
				last;
			}
		}
	}

	# If not found in <exec>, try with <filetree>
	if ( $username eq "" ) {
		my $filetree_list = $vm->getElementsByTagName("filetree");
		for ( my $i = 0 ; $i < $filetree_list->getLength ; $i++ ) {
			if ( $filetree_list->item($i)->getAttribute("seq") eq $seq ) {
				if ( $filetree_list->item($i)->getAttribute("user") ne "" ) {
					$username = $filetree_list->item($i)->getAttribute("user");
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
# get_vm_exec_mode
#
# Arguments:
# - a virtual machine node
#
# Returns the corresponding mode for the command executions in the virtual
# machine issued as argument. If no exec_mode is found (note that exec_mode attribute in
# <vm> is optional), the default is retrieved from the DataHandler object
#
sub get_vm_exec_mode {

	my $vm = shift;

	if ( $vm->getAttribute("mode") ne "" ) {
		return $vm->getAttribute("mode");
	}
	else {
		return $dh->get_default_exec_mode;
	}

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



###################################################################
#
sub merge_vm_type {
	my $type = shift;
	my $subtype = shift;
	my $os = shift;
	my $merged_type = $type;
	
	if (!($subtype eq "")){
		$merged_type = $merged_type . "-" . $subtype;
		if (!($os eq "")){
			$merged_type = $merged_type . "-" . $os;
		}
	}
	return $merged_type;
	
}

sub para {
	my $mensaje = shift;
	my $var = shift;
	print "************* $mensaje *************\n";
	if (defined $var){
	   print $var . "\n";	
	}
	print "*********************************\n";
	<STDIN>;
}


1;

