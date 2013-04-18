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

package VNX::vmAPI_libvirt;

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
use VNX::Arguments;
use VNX::CheckSemantics;
use VNX::TextManipulation;
use VNX::NetChecks;
use VNX::FileChecks;
use VNX::DocumentChecks;
use VNX::IPChecks;
use VNX::vmAPICommon;
#needed for UML_bootfile
use File::Basename;
#use XML::DOM;
use XML::LibXML;
#use XML::DOM::ValParser;
use IO::Socket::UNIX qw( SOCK_STREAM );


use constant USE_UNIX_SOCKETS => 0;  # Use unix sockets (1) or TCP (0) to communicate with virtual machine 


#
# Module vmAPI_libvirt initialization code
#
sub init {

    my $logp = "libvirt-init> ";

	# get hypervisor from config file
	$hypervisor = &get_conf_value ($vnxConfigFile, 'libvirt', 'hypervisor');
	if (!defined $hypervisor) { $hypervisor = $LIBVIRT_DEFAULT_HYPERVISOR };
	#print "*** hypervisor = $hypervisor \n";
	
	# load kvm modules
	# TODO: it should be done only if
	#   - not previously load
	#   - the scenario contains KVM virtual machine
	#
    if ( $dh->any_kvm_vm eq 'true' ) {

        system("kvm-ok");
        if ( $? == -1 ) {
        	$execution->smartdie ("The scenario contains KVM virtual machines, but the system does not have virtualization support.")
        } else {
        	# Check if KVM module is loaded and load it if needed
        	my $res = `cat /proc/modules | grep 'kvm '`;
        	if (!$res) {
                wlog (V, "kvm module not loaded; loading it...", $logp);
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"modprobe"} . " kvm");
            }
			# Check CPU type (Intel or AMD)
			$res = `cat /proc/cpuinfo | egrep 'vmx|svm'`;
			if ($res =~ m/vmx/ ) {
			    wlog (VVV, "Intel CPU", $logp);
			    my $res = `cat /proc/modules | grep 'kvm_intel'`;
			    if (!$res) {
	                wlog (V, "kvm_intel module not loaded; loading it...", $logp);
	                $execution->execute( $logp, $bd->get_binaries_path_ref->{"modprobe"} . " kvm_intel");
			    }			
                $res = `cat /sys/module/kvm_intel/parameters/nested`; chomp ($res);
                if ($res eq 'Y') {
                    wlog (V, "Nested virtualization supported", $logp);                                    	
                } else {
                    wlog (V, "Nested virtualization not enabled.", $logp);
                    wlog (V, "If supported, add 'options kvm_intel nested=1' to file /etc/modprobe.d/kvm_intel.conf", $logp);                                                    	
                }
			} elsif ($res =~ m/svm/ ) {
                wlog (VVV, "AMD CPU", $logp);
                my $res = `cat /proc/modules | grep 'kvm_amd'`;
                if (!$res) {
                    wlog (V, "kvm_amd module not loaded; loading it...", $logp);
                    $execution->execute( $logp, $bd->get_binaries_path_ref->{"modprobe"} . " kvm_amd");
                }           
                $res = `cat /sys/module/kvm_amd/parameters/nested`; chomp ($res);
                if ($res eq 'Y') {
                    wlog (V, "Nested virtualization supported", $logp);                                     
                } else {
                    wlog (V, "Nested virtualization not enabled.", $logp);
                    wlog (V, "If supported, add 'options kvm_amd nested=1' to file /etc/modprobe.d/kvm_amd.conf", $logp);                                                       
                }
			}
			
        }
    } else {
    	wlog (VVV, "No KVM virtual machines. Skipping load of KVM kernel modules", "host> ");
    }       

}



###################################################################
#                                                                 #
#   defineVM                                                      #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################

sub defineVM {

	my $self    = shift;
	my $vm_name = shift;
	my $type    = shift;
	my $vm_doc  = shift;

    my $logp = "libvirt-defineVM-$vm_name> ";
	my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);
	
	my $error = 0;
	my $extConfFile;
	

	my $global_doc = $dh->get_doc;
	my @vm_ordered = $dh->get_vm_ordered;

	my $sdisk_content;
	my $sdisk_fname;  # For olive only
	my $filesystem;
	my $con;

=BEGIN
	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {

		my $vm = $vm_ordered[$i];

		# We get name attribute
		my $name = $vm->getAttribute("name");

		unless ( $name eq $vm_name ) {
			next;
		}
=END
=cut

    my $vm = $dh->get_vm_byname ($vm_name);
    wlog (VVV, "---- " . $vm->getAttribute("name"), $logp);
    wlog (VVV, "---- " . $vm->getAttribute("exec_mode"), $logp);

    my $exec_mode   = $dh->get_vm_exec_mode($vm);
    wlog (VVV, "---- vm_exec_mode = $exec_mode", $logp);

    if ( ($exec_mode ne "cdrom") && ($exec_mode ne "sdisk") ) {
        $execution->smartdie( "execution mode $exec_mode not supported for VM of type $type" );
    }       

    if ($exec_mode eq "cdrom") {
    #if ($type ne "libvirt-kvm-olive") {
        # Create a temporary directory to store vnxboot file and filetree files
        if ( $execution->get_exe_mode() ne $EXE_DEBUG ) {
            my $command =
                $bd->get_binaries_path_ref->{"mktemp"}
                . " -d -p "
                . $dh->get_vm_tmp_dir($vm_name)
                . " vnx_opt_fs.XXXXXX";
            chomp( $sdisk_content = `$command` );
            $execution->execute( $logp, "mkdir " . $sdisk_content . "/filetree");
        }
        else {
            $sdisk_content = $dh->get_tmp_dir . "/vnx_opt_fs.XXXXXX";
        }
        $sdisk_content .= "/";

    } elsif ($exec_mode eq "sdisk") {
        # Create the shared filesystem 
        $sdisk_fname = $dh->get_vm_fs_dir($vm_name) . "/sdisk.img";
        # qemu-img create jconfig.img 12M
        # TODO: change the fixed 50M to something configurable
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"qemu-img"} . " create $sdisk_fname 50M" );
        # mkfs.msdos jconfig.img
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"mkfs.msdos"} . " $sdisk_fname" ); 
        # Mount the shared disk to copy filetree files
        $sdisk_content = $dh->get_vm_hostfs_dir($vm_name) . "/";
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $sdisk_content );
        # Create filetree and config dirs in the shared disk
        $execution->execute( $logp, "mkdir -p $sdisk_content/filetree");
        $execution->execute( $logp, "mkdir -p $sdisk_content/config");        	
    }		

#		$filesystem = $dh->get_vm_fs_dir($name) . "/opt_fs";




=BEGIN Esto hay que adaptarlo para copiar las claves ssh con libvirt
		# Install global public ssh keys in the UML
		my $global_list = $global_doc->getElementsByTagName("global");
		my $key_list = $global_list->item(0)->getElementsByTagName("ssh_key");

		# If tag present, add the key
		for ( my $j = 0 ; $j < $key_list->getLength ; $j++ ) {
			my $keyfile =
			  &do_path_expansion( &text_tag( $key_list->item($j) ) );
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"cat"}
				  . " $keyfile >> $sdisk_content"
				  . "keyring_root" );
		}

		# Next install vm-specific keys and add users and groups
		my @user_list = $dh->merge_user($vm);
		foreach my $user (@user_list) {
			my $username      = $user->getAttribute("username");
			my $initial_group = $user->getAttribute("group");
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"touch"} 
				  . " $sdisk_content"
				  . "group_$username" );
			my $group_list = $user->getElementsByTagName("group");
			for ( my $k = 0 ; $k < $group_list->getLength ; $k++ ) {
				my $group = &text_tag( $group_list->item($k) );
				if ( $group eq $initial_group ) {
					$group = "*$group";
				}
				$execution->execute( $logp, $bd->get_binaries_path_ref->{"echo"}
					  . " $group >> $sdisk_content"
					  . "group_$username" );
			}
			my $key_list = $user->getElementsByTagName("ssh_key");
			for ( my $k = 0 ; $k < $key_list->getLength ; $k++ ) {
				my $keyfile =
				  &do_path_expansion( &text_tag( $key_list->item($k) ) );
				$execution->execute( $logp, $bd->get_binaries_path_ref->{"cat"}
					  . " $keyfile >> $sdisk_content"
					  . "keyring_$username" );
			}
		}
=END
=cut

#	}
	
	#
	# Read extended configuration files
	#
	if ( $type eq "libvirt-kvm-olive" ) {
		# Get the extended configuration file if it exists
		$extConfFile = $dh->get_default_olive();
		#print "*** oliveconf=$extConfFile\n";
		if ($extConfFile ne "0"){
			$extConfFile = &get_abs_path ($extConfFile);
		}
	}


	###################################################################
	#                  defineVM for libvirt-kvm-windows               #
	###################################################################
	if ( $type eq "libvirt-kvm-windows" ) {

		#Save xml received in vnxboot, for the autoconfiguration
		my $filesystem_small = $dh->get_vm_fs_dir($vm_name) . "/opt_fs.iso";
		open CONFILE, ">$sdisk_content" . "vnxboot"
		  or $execution->smartdie("can not open ${sdisk_content}vnxboot: $!")
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

		#$execution->execute( $logp, $vm_doc ,*CONFILE);
		print CONFILE "$vm_doc\n";

		close CONFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		$execution->execute( $logp, $bd->get_binaries_path_ref->{"mkisofs"} . " -l -R -quiet -o $filesystem_small $sdisk_content" );
		$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $sdisk_content" );

	    my $parser       = XML::LibXML->new();
	    my $dom          = $parser->parse_string($vm_doc);
		#my $parser       = new XML::DOM::Parser;
		#my $dom          = $parser->parse($vm_doc);
		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
		my $virtualmList = $globalNode->getElementsByTagName("vm");
		my $virtualm     = $virtualmList->item(0);

		my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
		my $filesystemTag     = $filesystemTagList->item(0);
		my $filesystem_type   = $filesystemTag->getAttribute("type");
		my $filesystem        = $filesystemTag->getFirstChild->getData;

		if ( $filesystem_type eq "cow" ) {

			# If cow file does not exist, we create it
			if ( !-f $dh->get_vm_fs_dir($vm_name) . "/root_cow_fs" ) {
				$execution->execute( $logp, "qemu-img"
					  . " create -b $filesystem -f qcow2 "
					  . $dh->get_vm_fs_dir($vm_name)
					  . "/root_cow_fs" );
			}
			$filesystem = $dh->get_vm_fs_dir($vm_name) . "/root_cow_fs";
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
		$name_tag->addChild( $init_xml->createTextNode($vm_name) );

        # <cpu> tag
        # Needed to activate nested virtualization if supported
        # <cpu match='minimum'>
        #   <model>pentiumpro</model>
        #   <feature policy='optional' name='vmx'/>
        #   <feature policy='optional' name='svm'/>
        # </cpu>
        my $cpu_tag = $init_xml->createElement('cpu');
        $domain_tag->addChild($cpu_tag);
        $cpu_tag->addChild( $init_xml->createAttribute( match => "minimum" ) );
        my $model_tag = $init_xml->createElement('model');
        $cpu_tag->addChild($model_tag);
        $model_tag->addChild( $init_xml->createTextNode("pentiumpro") );
        my $feature1_tag = $init_xml->createElement('feature');
        $cpu_tag->addChild($feature1_tag);
        $feature1_tag->addChild( $init_xml->createAttribute( policy => "optional" ) );
        $feature1_tag->addChild( $init_xml->createAttribute( name => "vmx" ) );
        my $feature2_tag = $init_xml->createElement('feature');
        $cpu_tag->addChild($feature2_tag);
        $feature2_tag->addChild( $init_xml->createAttribute( policy => "optional" ) );
        $feature2_tag->addChild( $init_xml->createAttribute( name => "svm" ) );

		# <memory> tag
		my $memory_tag = $init_xml->createElement('memory');
		$domain_tag->addChild($memory_tag);
		$memory_tag->addChild( $init_xml->createTextNode($mem) );

		# <vcpu> tag
		my $vcpu_tag = $init_xml->createElement('vcpu');
		$domain_tag->addChild($vcpu_tag);
		$vcpu_tag->addChild( $init_xml->createTextNode( $vm->getAttribute("vcpu") ) );

        # <os> tag
		my $os_tag = $init_xml->createElement('os');
		$domain_tag->addChild($os_tag);
		my $type_tag = $init_xml->createElement('type');
		$os_tag->addChild($type_tag);
		
        my $vm_arch = $vm->getAttribute("arch");
		unless (empty($vm_arch)) {
		  $type_tag->addChild( $init_xml->createAttribute( arch => "$vm_arch" ) );	
		}

        # DFC 23/6/2011: Added machine attribute to avoid a problem in CentOS hosts
		$type_tag->addChild( $init_xml->createAttribute( machine => "pc" ) );
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
		#my $ifTagList = $virtualm->getElementsByTagName("if");
		#my $numif     = $ifTagList->getLength;
		my $mng_if_exists = 0;
		my $mng_if_mac;

		#for ( my $j = 0 ; $j < $numif ; $j++ ) {
		foreach my $if ($virtualm->getElementsByTagName("if")) {
			#my $ifTag = $ifTagList->item($j);
			my $id  = $if->getAttribute("id");
			my $net = $if->getAttribute("net");
			my $mac = $if->getAttribute("mac");

			my $interface_tag = $init_xml->createElement('interface');
			$devices_tag->addChild($interface_tag);
			if ($id eq 0){
				$mng_if_exists = 1;
				$mac =~ s/,//;
				$mng_if_mac = $mac;		
				$interface_tag->addChild(
				$init_xml->createAttribute( type => 'network' ) );
				$interface_tag->addChild(
				$init_xml->createAttribute( name => "eth" . $id ) );
				$interface_tag->addChild(
				$init_xml->createAttribute( onboot => "yes" ) );
			    my $source_tag = $init_xml->createElement('source');
			    $interface_tag->addChild($source_tag);
			    $source_tag->addChild(
				$init_xml->createAttribute( network => 'default') );
				my $mac_tag = $init_xml->createElement('mac');
			    $interface_tag->addChild($mac_tag);
			    $mac =~ s/,//;
			    $mac_tag->addChild( $init_xml->createAttribute( address => $mac ) );
			}else{
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
		my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
		open (CONS_FILE, "> $consFile") || $execution->smartdie ("ERROR: Cannot open file $consFile");

		# Go through <consoles> tag list to get attributes (display, port) and value  
		#my $consTagList = $virtualm->getElementsByTagName("console");
		#my $numcons     = $consTagList->getLength;
        my $cons0Display = $VNX::Globals::CONS_DISPLAY_DEFAULT;
		#for ( my $j = 0 ; $j < $numcons ; $j++ ) {
		foreach my $cons ($virtualm->getElementsByTagName("console")) {
			#my $consTag = $consTagList->item($j);
       		my $value   = &text_tag($cons);
			my $id      = $cons->getAttribute("id");
			my $display = $cons->getAttribute("display");
       		#print "** console: id=$id, value=$value\n" if ($exemode == $EXE_VERBOSE);
			if ( $id eq "0" ) {
				print "WARNING (vm=$vm_name): value $value ignored for <console id='0'> tag (only 'vnc' allowed).\n" 
				   if ( ($value ne "") && ($value ne "vnc") ); 
                #if ($display ne '') { $cons0Display = $display }
                unless (empty($display)) { $cons0Display = $display }
			}
			if ( $id > 0 ) {
				print "WARNING (vm=$vm_name): only consoles with id='0' allowed for Windows libvirt virtual machines. Tag ignored.\n"
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
		# Write the vnc console entry in "./vnx/.../vms/$vm_name/run/console" file
		# We do not know yet the vnc display (known when the machine is started in startVM)
		# By now, we just write 'UNK_VNC_DISPLAY'
		print CONS_FILE "con0=$cons0Display,vnc_display,UNK_VNC_DISPLAY\n";
		#print "$consFile: con0=$cons0Display,vnc_display,UNK_VNC_DISPLAY\n" if ($exemode == $EXE_VERBOSE);
		close (CONS_FILE); 

        # <serial> tag --> host to VM (H2VM) communications channel       
		my $serial_tag = $init_xml->createElement('serial');
        if (USE_UNIX_SOCKETS == 1) { # Use a UNIX socket
		    $serial_tag->addChild( $init_xml->createAttribute( type => 'unix' ) );
        } else { # Use TCP
            $serial_tag->addChild( $init_xml->createAttribute( type => 'tcp' ) );
        }		    
		$devices_tag->addChild($serial_tag);

		my $source3_tag = $init_xml->createElement('source');
		$serial_tag->addChild($source3_tag);
		$source3_tag->addChild( $init_xml->createAttribute( mode => 'bind' ) );
        
        if (USE_UNIX_SOCKETS == 1) { # Use a UNIX socket

	        #my $sock_dir = "/var/run/libvirt/vnx/" . $dh->get_scename . "/";
	        #my $sock_dir = $dh->get_tmp_dir . "/.vnx/" . $dh->get_scename . "/";
	        #system "mkdir -p $sock_dir";
	        #$source3_tag->addChild( $init_xml->createAttribute( path => $sock_dir . $vm_name . '_socket' ) );
	        $source3_tag->addChild( $init_xml->createAttribute( path => $dh->get_vm_dir($vm_name) . '/run/' . $vm_name . '_socket' ) );

        } else {  # Use TCP
        	
            $source3_tag->addChild( $init_xml->createAttribute( host => "$VNX::Globals::H2VM_BIND_ADDR" ) );
            my $h2vm_port = get_next_free_port (\$VNX::Globals::H2VM_PORT);
            $source3_tag->addChild( $init_xml->createAttribute( service => $h2vm_port ) );
            # Add it to h2vm_port file
            my $h2vm_fname = $dh->get_vm_dir . "/$vm_name/run/h2vm_port";
            open H2VMFILE, "> $h2vm_fname"
                or $execution->smartdie("can not open $h2vm_fname\n")
                unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
            print H2VMFILE "$h2vm_port";
            close H2VMFILE;
            wlog (VV, "port $h2vm_port used for $vm_name H2VM channel", $logp);
        }
        my $target_tag = $init_xml->createElement('target');
        $serial_tag->addChild($target_tag);
        $target_tag->addChild( $init_xml->createAttribute( port => '1' ) );         


		if ($mng_if_exists){		
		
				my $qemucommandline_tag = $init_xml->createElement('qemu:commandline');
				$domain_tag->addChild($qemucommandline_tag);
				
				my $qemuarg_tag = $init_xml->createElement('qemu:arg');
				$qemucommandline_tag->addChild($qemuarg_tag);
				$qemuarg_tag->addChild( $init_xml->createAttribute( value => "-device" ) );
				
				$mng_if_mac =~ s/,//;
				my $qemuarg_tag2 = $init_xml->createElement('qemu:arg');
				$qemucommandline_tag->addChild($qemuarg_tag2);
				$qemuarg_tag2->addChild( $init_xml->createAttribute( value => "rtl8139,vlan=0,mac=$mng_if_mac" ) );
				
				my $qemuarg_tag3 = $init_xml->createElement('qemu:arg');
				$qemucommandline_tag->addChild($qemuarg_tag3);
				$qemuarg_tag3->addChild( $init_xml->createAttribute( value => "-net" ) );
				
				my $qemuarg_tag4 = $init_xml->createElement('qemu:arg');
				$qemucommandline_tag->addChild($qemuarg_tag4);
				$qemuarg_tag4->addChild( $init_xml->createAttribute( value => "tap,vlan=0,ifname=$vm_name-e0,script=no" ) );
				
		}



		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my $format    = 1;
		my $xmlstring = $init_xml->toString($format);

		open XML_FILE, ">" . $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_libvirt.xml'
		  or $execution->smartdie(
			"can not open " . $dh->get_vm_dir . '/' . $vm_name . '_libvirt.xml')
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		print XML_FILE "$xmlstring\n";
		close XML_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

		# check that the domain is not already defined or started
        my @doms = $con->list_defined_domains();
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
				$error = "Domain $vm_name already defined\n";
				return $error;
			}
		}
		@doms = $con->list_domains();
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
				$error = "Domain $vm_name already defined and started\n";
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

		#print "*** $sdisk_content\n" if ($exemode == $EXE_VERBOSE); 
		open CONFILE, "> $sdisk_content" . "vnxboot.xml"
		  or $execution->smartdie("can not open ${sdisk_content}vnxboot: $!")
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		#$execution->execute( $logp, $vm_doc ,*CONFILE);
		print CONFILE "$vm_doc\n";
		close CONFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

		# We create the XML libvirt file with virtual machine definition
        my $parser       = XML::LibXML->new();
        my $dom          = $parser->parse_string($vm_doc);
		#my $parser       = new XML::DOM::Parser;
		#my $dom          = $parser->parse($vm_doc);
		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
		my $virtualmList = $globalNode->getElementsByTagName("vm");
		my $virtualm     = $virtualmList->item(0);

		my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
		my $filesystemTag     = $filesystemTagList->item(0);
		my $filesystem_type   = $filesystemTag->getAttribute("type");
		my $filesystem        = $filesystemTag->getFirstChild->getData;

		if ( $filesystem_type eq "cow" ) {

     		# Create the COW filesystem if it does not exist
			if ( !-f $dh->get_vm_fs_dir($vm_name) . "/root_cow_fs" ) {

				$execution->execute( $logp, "qemu-img"
					  . " create -b $filesystem -f qcow2 "
					  . $dh->get_vm_fs_dir($vm_name)
					  . "/root_cow_fs" );
			}
			$filesystem = $dh->get_vm_fs_dir($vm_name) . "/root_cow_fs";
		}

		# memory
		my $memTagList = $virtualm->getElementsByTagName("mem");
		my $memTag     = $memTagList->item(0);
		my $mem        = $memTag->getFirstChild->getData;

		# conf tag
		my $confFile = '';
		my @confTagList = $virtualm->getElementsByTagName("conf");
        if (@confTagList == 1) {
			$confFile = $confTagList[0]->getFirstChild->getData;
			wlog (VVV, "vm_name configuration file: $confFile", $logp);
        }

		# create the vm description in XML for libvirt
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
		$name_tag->addChild( $init_xml->createTextNode($vm_name) );

        # <cpu> tag
        # Needed to activate nested virtualization if supported
		# <cpu match='minimum'>
		#   <model>pentiumpro</model>
        #   <feature policy='optional' name='vmx'/>
        #   <feature policy='optional' name='svm'/>
		# </cpu>
        my $cpu_tag = $init_xml->createElement('cpu');
        $domain_tag->addChild($cpu_tag);
        $cpu_tag->addChild( $init_xml->createAttribute( match => "minimum" ) );
        my $model_tag = $init_xml->createElement('model');
        $cpu_tag->addChild($model_tag);
        $model_tag->addChild( $init_xml->createTextNode("pentiumpro") );
        my $feature1_tag = $init_xml->createElement('feature');
        $cpu_tag->addChild($feature1_tag);
        $feature1_tag->addChild( $init_xml->createAttribute( policy => "optional" ) );
        $feature1_tag->addChild( $init_xml->createAttribute( name => "vmx" ) );
        my $feature2_tag = $init_xml->createElement('feature');
        $cpu_tag->addChild($feature2_tag);
        $feature2_tag->addChild( $init_xml->createAttribute( policy => "optional" ) );
        $feature2_tag->addChild( $init_xml->createAttribute( name => "svm" ) );

		# <memory> tag
		my $memory_tag = $init_xml->createElement('memory');
		$domain_tag->addChild($memory_tag);
		$memory_tag->addChild( $init_xml->createTextNode($mem) );

		# <vcpu> tag
		my $vcpu_tag = $init_xml->createElement('vcpu');
		$domain_tag->addChild($vcpu_tag);
		$vcpu_tag->addChild( $init_xml->createTextNode( $vm->getAttribute("vcpu") ) );

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
        my $vm_arch = $vm->getAttribute("arch");
		unless (empty($vm_arch)) {
		  $type_tag->addChild( $init_xml->createAttribute( arch => "$vm_arch" ) );	
		}
		# DFC 23/6/2011: Added machine attribute to avoid a problem in CentOS hosts
		$type_tag->addChild( $init_xml->createAttribute( machine => "pc" ) );
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

        # secondary <disk> tag --> cdrom or disk for autoconfiguration or command execution

        # Filetree files:
        #   Each file created when calling plugin->getBootFiles or specified in <filetrees> 
        #   with seq='on_boot' has been copied to $dh->get_vm_tmp_dir($vm_name) . "/on_boot" 
        #   directory, organized in filetree/$num subdirectories, being $num the order of filetrees. 
        #   We move all the files to the shared disk
        
        # Check if there is any filetree in $vm_doc
        my @filetree_tag_list = $dom->getElementsByTagName("filetree");
        if (@filetree_tag_list > 0) { # At least one filetree defined
            # Copy the files to the shared disk        
	        my $onboot_files_dir = $dh->get_vm_tmp_dir($vm_name) . "/on_boot";
	        $execution->execute( $logp, $bd->get_binaries_path_ref->{"mv"} . " -v $onboot_files_dir/filetree/* $sdisk_content/filetree/" );
	        $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $onboot_files_dir" );
	        my $res=`tree $sdisk_content`; wlog (VVV, "vm $vm_name 'on_boot' shared disk content:\n $res", $logp);
        }
    
        if ($exec_mode eq "cdrom") {
        #if ($type ne "libvirt-kvm-olive") {

			# Create the iso filesystem for the cdrom
			my $filesystem_small = $dh->get_vm_fs_dir($vm_name) . "/opt_fs.iso";
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"mkisofs"}
				  . " -l -R -quiet -o $filesystem_small $sdisk_content" );
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $sdisk_content" );

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
        
        } elsif ($exec_mode eq "sdisk") {

			# Copy autoconfiguration (vnxboot.xml) file to shared disk
			#$execution->execute( $logp, $bd->get_binaries_path_ref->{"cp"} . " $sdisk_content/vnxboot $sdisk_content/vnxboot.xml" );
			# Copy initial router configuration if defined 
			#print "****    confFile = $confFile\n";
			if ($confFile ne '') {
                #$execution->execute( $logp, "mkdir $sdisk_content/config" );
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"cp"} . " $confFile $sdisk_content/config" );
			}

			#$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $sdisk_content" );
			# Dismount shared disk
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content );

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
			# Testing Fedora 17 problem with shared disk...
			#$target2_tag->addChild( $init_xml->createAttribute( cache => 'none' ) );
			
        	
        }
        
        # network <interface> tags linux
		#my $ifTagList = $virtualm->getElementsByTagName("if");
		#my $numif     = $ifTagList->getLength;
		my $mng_if_exists = 0;
		my $mng_if_mac;

		#for ( my $j = 0 ; $j < $numif ; $j++ ) {
		foreach my $if ($virtualm->getElementsByTagName("if")) {
			#my $ifTag = $ifTagList->item($j);
			my $id    = $if->getAttribute("id");
			my $net   = $if->getAttribute("net");
            my $mac   = $if->getAttribute("mac");

			# Ignore loopback interfaces (they are configured by the ACED daemon, but
			# should not be treated by libvirt)
			if (defined($net) && $net eq "lo") { next}
			 
			my $interface_tag;
			if ($id eq 0){
				# Commented on 3/5/2012. Now mgmt interfaces are defined in <qemu:commandline> section
				$mng_if_exists = 1;
				$mac =~ s/,//;
				$mng_if_mac = $mac;		
				#$interface_tag->addChild(
				#$init_xml->createAttribute( type => 'network' ) );
				#$interface_tag->addChild(
				#$init_xml->createAttribute( name => "eth" . $id ) );
				#$interface_tag->addChild(
				#$init_xml->createAttribute( onboot => "yes" ) );
			    #my $source_tag = $init_xml->createElement('source');
			    #$interface_tag->addChild($source_tag);
			    #$source_tag->addChild(
				#$init_xml->createAttribute( network => 'default') );
				#my $mac_tag = $init_xml->createElement('mac');
			    #$interface_tag->addChild($mac_tag);
			    #$mac =~ s/,//;
			    #$mac_tag->addChild( $init_xml->createAttribute( address => $mac ) );
			}else{
				
				$interface_tag = $init_xml->createElement('interface');
                $devices_tag->addChild($interface_tag);
				
                # <interface type='bridge' name='eth1' onboot='yes'>
				$interface_tag->addChild( $init_xml->createAttribute( type => 'bridge' ) );
				$interface_tag->addChild( $init_xml->createAttribute( name => "eth" . $id ) );
				$interface_tag->addChild( $init_xml->createAttribute( onboot => "yes" ) );

			 	# <source bridge="Net0"/>
			    my $source_tag = $init_xml->createElement('source');
			    $interface_tag->addChild($source_tag);
			    $source_tag->addChild( $init_xml->createAttribute( bridge => $net ) );

                # <target dev="vm1-e1"/>
                my $target_tag = $init_xml->createElement('target');
                $interface_tag->addChild($target_tag);
                $target_tag->addChild( $init_xml->createAttribute( dev => "$vm_name-e$id" ) );

				# <mac address="02:fd:00:04:01:00"/>
				my $mac_tag = $init_xml->createElement('mac');
			    $interface_tag->addChild($mac_tag);
			    $mac =~ s/,//;
			    $mac_tag->addChild( $init_xml->createAttribute( address => $mac ) );

                # <model type='e1000'/>
                my $model_tag = $init_xml->createElement('model');
                $interface_tag->addChild($model_tag);
                $model_tag->addChild( $init_xml->createAttribute( type => 'e1000' ) );
			    
			}			

			# DFC: set interface model to 'i82559er' in olive router interfaces.
			#      Using e1000 the interfaces are not created correctly (to further investigate) 
			if ($type eq "libvirt-kvm-olive") {
                # TODO: check that all olive interfaces have a correct name attribute
                my $if_name = $if->getAttribute("name");
				my $model_tag = $init_xml->createElement('model');
				$interface_tag->addChild($model_tag);
				wlog (VVV, "olive: adding interface $if_name", $logp);
				if ($if_name =~ /^fxp/ ) {
                    # <model type='i82559er'/>
			        $model_tag->addChild( $init_xml->createAttribute( type => 'i82559er') );
				} elsif ($if_name =~ /^em/ ) {
                    # <model type='e1000'/>
				    $model_tag->addChild( $init_xml->createAttribute( type => 'e1000') );
				}
			}
			
		}
		
#		# configuracion de la interfaz de gestion
#		my $mngifTagList = $virtualm->getElementsByTagName("mng_if");
#		my $mngifTag     = $mngifTagList->item(0);
#		my $mngid    = $mngifTag->getAttribute("id");
#		my $mngnet   = $mngifTag->getAttribute("net");
#		my $mngmac   = $mngifTag->getAttribute("mac");
		#
		

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
		my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
		open (CONS_FILE, "> $consFile") || $execution->smartdie ("ERROR: Cannot open file $consFile");

		# Go through <consoles> tag list to get attributes (display, port) and value  
		#my $consTagList = $virtualm->getElementsByTagName("console");
		#my $numcons     = $consTagList->getLength;
        my $consType = $VNX::Globals::CONS1_DEFAULT_TYPE;
        my $cons0Display = $VNX::Globals::CONS_DISPLAY_DEFAULT;
        my $cons1Display = $VNX::Globals::CONS_DISPLAY_DEFAULT;
        my $cons1Port = '';
		#for ( my $j = 0 ; $j < $numcons ; $j++ ) {
		foreach my $cons ($virtualm->getElementsByTagName("console")) {
			#my $consTag = $consTagList->item($j);
       		my $value   = &text_tag($cons);
			my $id      = $cons->getAttribute("id");
			my $display = $cons->getAttribute("display");
       		#print "** console: id=$id, value=$value\n" if ($exemode == $EXE_VERBOSE);
			if (  $id eq "0" ) {
                #if ($display ne '') { $cons0Display = $display }
				unless (empty($display)) { $cons0Display = $display }
			}
			if ( $id eq "1" ) {
				if ( $value eq "pts" || $value eq "telnet" ) { $consType = $value; }
				$cons1Port = $cons->getAttribute("port");
				#if ($display ne '') { $cons1Display = $display }
                unless (empty($display)) { $cons1Display = $display }
			}
			if ( $id > 1 ) {
				print "WARNING (vm=$vm_name): only consoles with id='0' or id='1' allowed for libvirt virtual machines. Tag ignored.\n"
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
			# Write the vnc console entry in "./vnx/.../vms/$vm_name/console" file
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
	        #
			my $serial2_tag = $init_xml->createElement('serial');
			$serial2_tag->addChild( $init_xml->createAttribute( type => 'pty' ) );
			$devices_tag->addChild($serial2_tag);
			my $target2_tag = $init_xml->createElement('target');
			$serial2_tag->addChild($target2_tag);
			$target2_tag->addChild( $init_xml->createAttribute( port => '0' ) );
			my $console_tag = $init_xml->createElement('console');
			$console_tag->addChild( $init_xml->createAttribute( type => 'pty' ) );
			$devices_tag->addChild($console_tag);
			my $target3_tag = $init_xml->createElement('target');
			$console_tag->addChild($target3_tag);
			$target3_tag->addChild( $init_xml->createAttribute( port => '0' ) );

			# We write the pts console entry in "./vnx/.../vms/$vm_name/console" file
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
 			print "WARNING (vm=$vm_name): cannot use port $cons1Port for $vm_name console #1; using $consolePort instead\n"
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

			# Write the console entry to "./vnx/.../vms/$vm_name/console" file
			print CONS_FILE "con1=$cons1Display,telnet,$consolePort\n";	
			#wlog (VVV, "** $consFile: con1=$cons1Display,telnet,$consolePort");	
        }
		close (CONS_FILE); 

        # <serial> tag --> host to VM (H2VM) communications channel       
        my $serial_tag = $init_xml->createElement('serial');
        if (USE_UNIX_SOCKETS == 1) { # Use a UNIX socket
            $serial_tag->addChild( $init_xml->createAttribute( type => 'unix' ) );
        } else { # Use TCP
            $serial_tag->addChild( $init_xml->createAttribute( type => 'tcp' ) );
        }           
        $devices_tag->addChild($serial_tag);

		my $source3_tag = $init_xml->createElement('source');
		$serial_tag->addChild($source3_tag);
		$source3_tag->addChild( $init_xml->createAttribute( mode => 'bind' ) );
		
        if (USE_UNIX_SOCKETS == 1) { # Use a UNIX socket

            #my $sock_dir = "/var/run/libvirt/vnx/" . $dh->get_scename . "/";
            #my $sock_dir = $dh->get_tmp_dir . "/.vnx/" . $dh->get_scename . "/";
            #system "mkdir -p $sock_dir";
            #$source3_tag->addChild( $init_xml->createAttribute( path => $sock_dir . $vm_name . '_socket' ) );
            $source3_tag->addChild(    $init_xml->createAttribute( path => $dh->get_vm_dir($vm_name) . '/run/' . $vm_name . '_socket' ) );

        } else {  # Use TCP
            
            $source3_tag->addChild( $init_xml->createAttribute( host => "$VNX::Globals::H2VM_BIND_ADDR" ) );
            my $h2vm_port = get_next_free_port (\$VNX::Globals::H2VM_PORT);
            $source3_tag->addChild( $init_xml->createAttribute( service => $h2vm_port ) );
            # Add it to h2vm_port file
            my $h2vm_fname = $dh->get_vm_dir . "/$vm_name/run/h2vm_port";
            open H2VMFILE, "> $h2vm_fname"
                or $execution->smartdie("can not open $h2vm_fname\n")
                unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
            print H2VMFILE "$h2vm_port";
            close H2VMFILE;
            wlog (VV, "port $h2vm_port used for $vm_name H2VM channel", $logp);

            # <protocol type="raw"/>
            my $protocol_tag = $init_xml->createElement('protocol');
            $serial_tag->addChild($protocol_tag);
            #$protocol_tag->addChild( $init_xml->createAttribute( type => 'raw' ) );
            $protocol_tag->addChild( $init_xml->createAttribute( type => 'telnet' ) );
        }

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
			$qemuarg2_tag->addChild( $init_xml->createAttribute( value => "bios-olive.bin" ) );
            # Prueba para solucionar los problemas con los interfaces emX...no va :-(
            #my $qemuarg3_tag = $init_xml->createElement('qemu:arg');
            #$qemucmdline_tag->addChild($qemuarg3_tag);
            #$qemuarg3_tag->addChild( $init_xml->createAttribute( value => "-no-acpi" ) );
        }
		
		
		if ($mng_if_exists){		
		
            # -device rtl8139,netdev=lan1 -netdev tap,id=lan1,ifname=ubuntu-e0,script=no,downscript=no
		
            my $qemucommandline_tag = $init_xml->createElement('qemu:commandline');
            $domain_tag->addChild($qemucommandline_tag);
				
            my $qemuarg_tag = $init_xml->createElement('qemu:arg');
            $qemucommandline_tag->addChild($qemuarg_tag);
            $qemuarg_tag->addChild( $init_xml->createAttribute( value => "-device" ) );
				
            $mng_if_mac =~ s/,//;
            my $qemuarg_tag2 = $init_xml->createElement('qemu:arg');
            $qemucommandline_tag->addChild($qemuarg_tag2);
            $qemuarg_tag2->addChild( $init_xml->createAttribute( value => "rtl8139,netdev=mgmtif0,mac=$mng_if_mac" ) );
				
            my $qemuarg_tag3 = $init_xml->createElement('qemu:arg');
            $qemucommandline_tag->addChild($qemuarg_tag3);
            $qemuarg_tag3->addChild( $init_xml->createAttribute( value => "-netdev" ) );
				
            my $qemuarg_tag4 = $init_xml->createElement('qemu:arg');
            $qemucommandline_tag->addChild($qemuarg_tag4);
            $qemuarg_tag4->addChild( $init_xml->createAttribute( value => "tap,id=mgmtif0,ifname=$vm_name-e0,script=no" ) );
				
		}
		
=BEGIN		
		# TEST, TEST, TEST
		# Nested virtualization test (12/10/12)
		my $qemucommandline_tag = $init_xml->createElement('qemu:commandline');
        $domain_tag->addChild($qemucommandline_tag);
                
        my $qemuarg_tag = $init_xml->createElement('qemu:arg');
        $qemucommandline_tag->addChild($qemuarg_tag);
        $qemuarg_tag->addChild( $init_xml->createAttribute( value => "-cpu" ) );
                
        my $qemuarg_tag2 = $init_xml->createElement('qemu:arg');
        $qemucommandline_tag->addChild($qemuarg_tag2);
        $qemuarg_tag2->addChild( $init_xml->createAttribute( value => "qemu32,+vmx" ) );
=END
=cut		
		     
#   ############<graphics type='sdl' display=':0.0'/>
#      my $graphics_tag2 = $init_xml->createElement('graphics');
#      $devices_tag->addChild($graphics_tag2);
#      $graphics_tag2->addChild( $init_xml->createAttribute( type => 'sdl'));
#      # DFC  $graphics_tag2->addChild( $init_xml->createAttribute( display =>':0.0'));
#      $disp = $ENV{'DISPLAY'};
#      $graphics_tag2->addChild( $init_xml->createAttribute( display =>$disp));
#   ############

		# We connect with libvirt to define the virtual machine
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		#my $con;
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my $format    = 1;
		my $xmlstring = $init_xml->toString($format);
		
		# Save the XML libvirt file to .vnx/scenarios/<vscenario_name>/vms/$vm_name
		open XML_FILE, ">" . $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_libvirt.xml'
		  or $execution->smartdie(
			"can not open " . $dh->get_vm_dir . '/' . $vm_name . '_libvirt.xml' )
		    unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		print XML_FILE "$xmlstring\n";
		close XML_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

        # check that the domain is not already defined or started
        my @doms = $con->list_defined_domains();
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
				$error = "Domain $vm_name already defined\n";
				return $error;
			}
		}
		@doms = $con->list_domains();
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
				$error = "Domain $vm_name already defined and started\n";
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
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "libvirt-undefineVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error;
	my $con;


	###################################################################
	# undefineVM for libvirt-kvm-windows/linux/freebsd/olive          #
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		#my $hypervisor = "qemu:///system";
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		#my $con;
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_defined_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
				$listDom->undefine();
				print "Domain undefined.\n" if ($exemode == $EXE_VERBOSE);
				$error = 0;
				return $error;
			}
		}
		$error = "Domain $vm_name does not exist.\n";
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
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "libvirt-destroyVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;
	my $con;
	
	
	###################################################################
	#                  destroyVM for libvirt-kvm-windows/linux/freebsd#
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		#my $hypervisor = "qemu:///system";
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		#my $con;
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		$error = "Domain does not exist\n";
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
				$listDom->destroy();
				print "Domain destroyed\n" if ($exemode == $EXE_VERBOSE);

				# Delete vm directory (DFC 21/01/2010)
				$error = 0;
				last;
			}
		}

		# Remove vm fs directory (cow and iso filesystems)
		$execution->execute( $logp, "rm " . $dh->get_vm_fs_dir($vm_name) . "/*" );
		return $error;

	}
	else {
		$error = "destroyVM for type $type not implemented yet.\n";
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
	my $vm_name = shift;
	my $type   = shift;
	my $no_consoles = shift;

    my $logp = "libvirt-startVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error;
	my $con;
	
	###################################################################
	# startVM for libvirt-kvm-windows/linux/freebsd/olive             #
	###################################################################
	if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
	        ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		#my $con;
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_defined_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
				$listDom->create();
				print "Domain started\n" if ($exemode == $EXE_VERBOSE);

=BEGIN
                sleep (2);
		        # Send the exeCommand order to the virtual machine using the socket
                my $vm = $dh->get_vm_byname ($vm_name);
                my $exec_mode   = $dh->get_vm_exec_mode($vm);
                wlog (VVV, "---- vm_exec_mode = $exec_mode");
                
                my $vmsocket;
                if (USE_UNIX_SOCKETS == 1) { # Use a UNIX socket

	                #my $socket_fh = "/var/run/libvirt/vnx/" . $dh->get_scename . "/${vm_name}_socket";
	                #my $socket_fh = $dh->get_tmp_dir . "/.vnx/" . $dh->get_scename . "/${vm_name}_socket";
	                my $socket_fh = $dh->get_vm_dir($vm_name). '/run/' . $vm_name . '_socket';
	
	                $vmsocket = IO::Socket::UNIX->new(
	                   Type => SOCK_STREAM,
	                   Peer => $socket_fh,
	                ) or $execution->smartdie("Can't connect to server: $!\n");

                } else {  # Use TCP

		            # Add it to h2vm_port file
                    my $h2vm_fname = $dh->get_vm_dir . "/$vm_name/run/h2vm_port";
		            open H2VMFILE, "< $h2vm_fname"
		                or $execution->smartdie("can not open $h2vm_fname\n")
		                unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		            my $h2vm_port = <H2VMFILE>;

                    wlog (VV, "port $h2vm_port used for $vm_name H2VM channel");

                    $vmsocket = IO::Socket::INET->new(
                        Proto    => "tcp",
                        PeerAddr => "localhost",
                        PeerPort => "$h2vm_port",
                    ) or $execution->smartdie("Can't connect to $vm_name H2VM port: $!\n");

                }
                
                #sleep 30;
                # We send some nop (no operation) commands before sending the real command
                # This is to avoid the loose of the first characters sent through the serial line
                sleep (1);
                print $vmsocket "nop\n";     
                print $vmsocket "nop\n";     
                print $vmsocket "nop\n";     
                # Now we send the real command
                print $vmsocket "exeCommand $exec_mode\n";     

				# save pid in run dir
				my $uuid = $listDom->get_uuid_string();
				$execution->execute( $logp, "ps aux | grep kvm | grep " 
					  . $uuid
					  . " | grep -v grep | awk '{print \$2}' > "
					  . $dh->get_vm_run_dir($vm_name)
					  . "/pid" );
=END
=cut
				
				#		
			    # Console management
			    # 
    			
   				# First, we have to change the 'UNK_VNC_DISPLAY' and 'UNK_PTS_DEV' tags 
				# we temporarily wrote to console files (./vnx/.../vms/$vm_name/console) 
				# by the correct values assigned by libvirt to the virtual machine
				my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
  	
				# Graphical console (id=0)
				if ($type ne "libvirt-kvm-olive" ) { # Olive routers do not have graphical consoles
					# TODO: use $execution->execute
					my $cmd=$bd->get_binaries_path_ref->{"virsh"} . " -c qemu:///system vncdisplay $vm_name";
			       	my $vncDisplay=`$cmd`;
			       	if ($vncDisplay eq '') { # wait and repeat command again
			       		wlog (V, "Command $cmd failed. Retrying...", $logp);
			       		sleep 2;
			       		$vncDisplay=`$cmd`;
			       		if ($vncDisplay eq '') {execution->smartdie ("Cannot get display for $vm_name. Error executing command: $cmd")}
			       	}
			       	
			       	$vncDisplay =~ s/\s+$//;    # Delete linefeed at the end		
					$execution->execute( $logp, $bd->get_binaries_path_ref->{"sed"}." -i -e 's/UNK_VNC_DISPLAY/$vncDisplay/' $consFile");
					#print "****** sed -i -e 's/UNK_VNC_DISPLAY/$vncDisplay/' $consFile\n";
				}
			
				# Text console (id=1)
			    if ($type ne "libvirt-kvm-windows")  { # Windows does not have text console
			    	# Check if con1 is of type "libvirt_pts"
			    	my $conData= &get_conf_value ($consFile, '', 'con1');
					if ( defined $conData) {
					    my @consField = split(/,/, $conData);
					    if ($consField[1] eq 'libvirt_pts') {
			        		my $cmd=$bd->get_binaries_path_ref->{"virsh"} . " -c qemu:///system ttyconsole $vm_name";
			           		my $ptsDev=`$cmd`;
					       	if ($ptsDev eq '') { # wait and repeat command again
					       		wlog (V, "Command $cmd failed. Retrying...", $logp);
					       		sleep 2;
					       		$ptsDev=`$cmd`;
					       		if ($ptsDev eq '') {execution->smartdie ("Cannot get pts device for $vm_name. Error executing command: $cmd")}
					       	}
			           		$ptsDev =~ s/\s+$//;    # Delete linefeed at the end		
							$execution->execute( $logp, $bd->get_binaries_path_ref->{"sed"}." -i -e 's#UNK_PTS_DEV#$ptsDev#' $consFile");
					    }
					} else {
						print "WARNING (vm=$vm_name): no data for console #1 found in $consFile"
					}
				}
			   
				# Then, we just read the console file and start the active consoles,
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
	my $vm_name = shift;
	my $type   = shift;
	my $F_flag = shift; # Not used here, only in vmAPI_uml

    my $logp = "libvirt-shutdownVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;
	my $con;

	# Sample code
	print "Shutting down vm $vm_name of type $type\n" if ($exemode == $EXE_VERBOSE);

   	###################################################################
	#                 shutdownVM for libvirt-kvm-windows/linux/freebsd#
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		#my $hypervisor = "qemu:///system";
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		#my $con;
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();
		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			#print "**** dom_name=$dom_name\n";
			if ( $dom_name eq $vm_name ) {
				$listDom->shutdown();
				&change_vm_status( $vm_name, "REMOVE" );

				# remove run directory (de momento no se puede porque necesitamos saber a que pid esperar)
				# lo habilito para la demo
				$execution->execute( $logp, "rm -rf " . $dh->get_vm_run_dir($vm_name) . "/*" );

				print "Domain shutdown\n" if ($exemode == $EXE_VERBOSE);
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
	my $vm_name   = shift;
	my $type     = shift;
	my $filename = shift;

    my $logp = "libvirt-saveVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;
	my $con;

	# Sample code
	print "saveVM: saving vm $vm_name of type $type\n" if ($exemode == $EXE_VERBOSE);

	if ( $type eq "libvirt-kvm" ) {

		#my $hypervisor = "qemu:///system";
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		#my $con;
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
				$listDom->save($filename);
				print "Domain saved to file $filename\n" if ($exemode == $EXE_VERBOSE);
				&change_vm_status( $vm_name, "paused" );
				return $error;
			}
		}
		$error = "Domain does not exist..\n";
		#undef ($con); print "*******  undef(con)\n";
		return $error;

	}
	###################################################################
	#                  saveVM for libvirt-kvm-windows/linux/freebsd   #
	###################################################################
    elsif ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
             ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") )   {

		#my $hypervisor = "qemu:///system";
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
				$listDom->save($filename);
				print "Domain saved to file $filename\n" if ($exemode == $EXE_VERBOSE);
				&change_vm_status( $vm_name, "paused" );
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
	my $vm_name   = shift;
	my $type     = shift;
	my $filename = shift;

    my $logp = "libvirt-restoreVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;
	my $con;

	print
	  "restoreVM: restoring vm $vm_name of type $type from file $filename\n";

 	###################################################################
	#                  restoreVM for libvirt-kvm-windows/linux/freebsd#
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) 
    {
	    
		#my $hypervisor = "qemu:///system";
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my $dom = $con->restore_domain($filename);
		print("Domain restored from file $filename\n");
		&change_vm_status( $vm_name, "running" );
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
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "libvirt-suspendVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;
	my $con;

	###################################################################
	#                  suspendVM for libvirt-kvm-windows/linux/freebsd#
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		#my $hypervisor = "qemu:///system";
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
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
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "libvirt-resumeVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;
	my $con;

	# Sample code
	print "resumeVM: resuming vm $vm_name\n" if ($exemode == $EXE_VERBOSE);

	###################################################################
	#                  resumeVM for libvirt-kvm-windows/linux/freebsd #
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		#my $hypervisor = "qemu:///system";
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
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
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "libvirt-rebootVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;
	my $con;

	###################################################################
	#                  rebootVM for libvirt-kvm-windows/linux/freebsd #
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		#my $hypervisor = "qemu:///system";
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
				$listDom->reboot(&Sys::Virt::Domain::REBOOT_RESTART);
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
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "libvirt-resetVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error;
	my $con;

	# Sample code
	print "resetVM: reseting vm $vm_name\n" if ($exemode == $EXE_VERBOSE);

	###################################################################
	#                  resetVM for libvirt-kvm-windows/linux/freebsd  #
	###################################################################
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ) {

		#my $hypervisor = "qemu:///system";
		print "Connecting to $hypervisor hypervisor..." if ($exemode == $EXE_VERBOSE);
		eval { $con = Sys::Virt->new( address => $hypervisor, readonly => 0 ) };
		if ($@) { $execution->smartdie ("error connecting to $hypervisor hypervisor.\n" . $@->stringify() ); }
		else    {print "OK\n" if ($exemode == $EXE_VERBOSE); }

		my @doms = $con->list_domains();

		foreach my $listDom (@doms) {
			my $dom_name = $listDom->get_name();
			if ( $dom_name eq $vm_name ) {
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

	my $self    = shift;
	my $merged_type = shift;
	my $seq     = shift;
	my $vm      = shift;
	my $vm_name = shift;
	my $plugin_ftree_list_ref = shift;
	my $plugin_exec_list_ref  = shift;
    my $ftree_list_ref        = shift;
    my $exec_list_ref         = shift;

    my $error = 0;

    my $logp = "libvirt-executeCMD-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$merged_type, seq=$seq ...)", $logp);

#pak ("press any key to continue");

	# Previous checkings and warnings
#	my @vm_ordered = $dh->get_vm_ordered;
#	my %vm_hash    = $dh->get_vm_to_use(@plugins);

	my $random_id  = &generate_random_string(6);


	###########################################
	#   executeCMD for WINDOWS                #
	###########################################
	#### NEW VERSION same CD for filetree and exec
			
	if ( $merged_type eq "libvirt-kvm-windows" ) {
		############ WINDOWS ##############
		############ FILETREE ##############
		my @filetree_list = $dh->merge_filetree($vm);
		my $user   = &get_user_in_seq( $vm, $seq );
		my $exec_mode   = $dh->get_vm_exec_mode($vm);
		my $command =  $bd->get_binaries_path_ref->{"mktemp"} . " -d -p " . $dh->get_vm_hostfs_dir($vm_name)  . " filetree.XXXXXX";
# AHORA SE LLAMARA COMMAND.XML Y LO PONGO EN OTRO DIR
#		open COMMAND_FILE, ">" . $dh->get_vm_hostfs_dir($vm_name) . "/filetree.xml" or $execution->smartdie("can not open " . $dh->get_vm_hostfs_dir($vm_name) . "/filetree.xml $!" ) unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		open COMMAND_FILE, ">" . $dh->get_vm_tmp_dir($vm_name) . "/command.xml" or $execution->smartdie("can not open " . $dh->get_vm_hostfs_dir($vm_name) . "/command.xml $!" ) unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		
		$execution->set_verb_prompt("$vm_name> ");
		my $shell      = $dh->get_default_shell;
		my @shell_list = $vm->getElementsByTagName("shell");
		if ( @shell_list == 1 ) {
			$shell = &text_tag( $shell_list[0] );
		}
		my $date_command = $bd->get_binaries_path_ref->{"date"};
		chomp( my $now = `$date_command` );
		my $basename = basename $0;
# AHORA EL NODO PRINCIPAL SE LLAMARA COMMAND
#		$execution->execute( $logp, "<filetrees>", *COMMAND_FILE );
		$execution->execute( $logp, "<command>", *COMMAND_FILE );
		
		# Insert random id number for the command file
		my $fileid = $vm_name . "-" . &generate_random_string(6);
		$execution->execute( $logp, "<id>" . $fileid ."</id>", *COMMAND_FILE );
		my $dst_num = 0;
		chomp( my $filetree_host = `$command` );
		$filetree_host =~ /filetree\.(\w+)$/;
		$execution->execute( $logp, "mkdir " . $filetree_host ."/filetree");
		foreach my $filetree (@filetree_list) {
			# To get momment
			my $filetree_seq_string = $filetree->getAttribute("seq");
			# To install subtree (only in the right momment)
			# FIXME: think again the "always issue"; by the moment deactivated

			# JSF 01/12/10: we accept several commands in the same seq tag,
			# separated by commas
			my @filetree_seqs = split(',',$filetree_seq_string);
			foreach my $filetree_seq (@filetree_seqs) {
				
				# Remove leading or trailing spaces
                $filetree_seq =~ s/^\s+//;
                $filetree_seq =~ s/\s+$//;
				
				if ( $filetree_seq eq $seq ) {
					$dst_num++;
					my $src;
					my $filetree_value = &text_tag($filetree);

					$src = &get_abs_path ($filetree_value);
					$src = &chompslash($src);
					#my $filetree_vm = "/mnt/hostfs/filetree.$random_id";
					
					$execution->execute( $logp, "mkdir " . $filetree_host ."/filetree/".  $dst_num);
					$execution->execute( $logp, $bd->get_binaries_path_ref->{"cp"} . " -r $src/* $filetree_host" . "/filetree/" . $dst_num );
					my %file_perms = &save_dir_permissions($filetree_host);
					my $dest = $filetree->getAttribute("root");
					my $filetreetxt = $filetree->toString(1); 
					print "$filetreetxt" if ($exemode == $EXE_VERBOSE);
					$execution->execute( $logp, "$filetreetxt", *COMMAND_FILE );
				}
			}
		}
#		$execution->execute( $logp, "</filetrees>", *COMMAND_FILE );

# NO CERRAMOS COMMAND_FILE PORQUE VAMOS A SEGUIR ESCRIBIENDO LOS COMANDOS A CONTINUACION DE LOS FILETREES
#		close COMMAND_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );




=BEGIN		
		open( DU, "du -hs0c " . $dh->get_vm_hostfs_dir($vm_name) . " | awk '{ var = \$1; var2 = substr(var,0,length(var)); print var2} ' |") || die "Failed: $!\n";
		my $dimension = <DU>;
		$dimension = $dimension + 20;
		my $dimensiondisk = $dimension + 30;
		close DU unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		open( DU, "du -hs0c " . $dh->get_vm_hostfs_dir($vm_name) . " | awk '{ var = \$1; var3 = substr(var,length(var),length(var)+1); print var3} ' |") || die "Failed: $!\n";
		my $unit = <DU>;
		close DU unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
=END
=cut

# ESTO NO VEO QUE SE USE :-m
		# Calculate dimension and units of hostfs_dir
#		my $cmd = "du -hs0c " . $dh->get_vm_hostfs_dir($vm_name); 
#		my $dures = `$cmd`;
#		my @dures = split (/\t| /,$dures);
#		my $dimension=$dures[0];	$dimension=~ s/[B|K|M|G]//;
#		my $unit=$dures[0];		$unit=~ s/\d*//;
#		print "**** dimension=$dimension, unit=$unit\n" if ($exemode == $EXE_VERBOSE);
#		$dimension = $dimension + 20;
#		my $dimensiondisk = $dimension + 30;
#
#		if ($dst_num > 0){
#			if (   ( $unit eq "K\n" || $unit eq "B\n" )|| ( ( $unit eq "M\n" ) && ( $dimension <= 32 ) ) ){
#				$unit          = 'M';
#				$dimension     = 32;
#				$dimensiondisk = 50;
#			}
# Y ESTO AHORA NO HACE FALTA AQUI
#			$execution->execute( $logp, "mkdir /tmp/disk.$random_id");
#			$execution->execute( $logp, "mkdir  /tmp/disk.$random_id/filetree");
#			$execution->execute( $logp, "cp " . $dh->get_vm_hostfs_dir($vm_name) . "/filetree.xml" . " " . "$filetree_host" );
			#$execution->execute( $logp, "cp -rL " . $filetree_host . "/*" . " " . "/tmp/disk.$random_id/filetree" );

# TODAVIA NO HACEMOS EL ISO, PORQUE HABRA QUE METER LOS COMANDOS
#			$execution->execute( $logp, "mkisofs -R -nobak -follow-links -max-iso9660-filename -allow-leading-dots " . 
#			                    "-pad -quiet -allow-lowercase -allow-multidot -o /tmp/disk.$random_id.iso $filetree_host");


# TAMPOCO CREAMOS EL XML DEL DISPOSITIVO TODAVIA							
#			my $disk_filetree_windows_xml;
#			$disk_filetree_windows_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
#			
#			my $disk_filetree_windows_tag = $disk_filetree_windows_xml->createElement('disk');
#			$disk_filetree_windows_xml->addChild($disk_filetree_windows_tag);
#			$disk_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( type => "file" ) );
#			$disk_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( device => "cdrom" ) );
#			
#			my $driver_filetree_windows_tag =$disk_filetree_windows_xml->createElement('driver');
#			$disk_filetree_windows_tag->addChild($driver_filetree_windows_tag);
#			$driver_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( name => "qemu" ) );
#			$driver_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( cache => "default" ) );
#			
#			my $source_filetree_windows_tag =$disk_filetree_windows_xml->createElement('source');
#			$disk_filetree_windows_tag->addChild($source_filetree_windows_tag);
#			$source_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( file => "/tmp/disk.$random_id.iso" ) );
#			
#			my $target_filetree_windows_tag =$disk_filetree_windows_xml->createElement('target');
#			$disk_filetree_windows_tag->addChild($target_filetree_windows_tag);
#			$target_filetree_windows_tag->addChild( $disk_filetree_windows_xml->createAttribute( dev => "hdb" ) );
#			
#			my $readonly_filetree_windows_tag =$disk_filetree_windows_xml->createElement('readonly');
#			$disk_filetree_windows_tag->addChild($readonly_filetree_windows_tag);
#			my $format_filetree_windows   = 1;
#			my $xmlstring_filetree_windows = $disk_filetree_windows_xml->toString($format_filetree_windows );
#			
#			$execution->execute( $logp, "rm -f ". $dh->get_vm_hostfs_dir($vm_name) . "/filetree_libvirt.xml"); 
#			open XML_FILETREE_WINDOWS_FILE, ">" . $dh->get_vm_hostfs_dir($vm_name) . '/' . 'filetree_libvirt.xml'
#	 			or $execution->smartdie("can not open " . $dh->get_vm_hostfs_dir . '/' . 'filetree_libvirt.xml' )
#	  			unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
#			print XML_FILETREE_WINDOWS_FILE "$xmlstring_filetree_windows\n";
#			close XML_FILETREE_WINDOWS_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
#			
#			#$execution->execute( $logp, "virsh -c qemu:///system 'attach-disk \"$vm_name\" /tmp/disk.$random_id.iso hdb --mode readonly --driver file --type cdrom'");
#			$execution->execute( $logp, "virsh -c qemu:///system 'attach-device \"$vm_name\" ". $dh->get_vm_hostfs_dir($vm_name) . "/filetree_libvirt.xml'");
#			print "Copying file tree in client, through socket: \n" . $dh->get_vm_dir($vm_name). '/'.$vm_name.'_socket' if ($exemode == $EXE_VERBOSE);
#			waitfiletree($dh->get_vm_dir($vm_name) .'/'.$vm_name.'_socket');
#			sleep(4);
#			# 3d. Cleaning
#			$execution->execute( $logp, "rm /tmp/disk.$random_id.iso");
#			$execution->execute( $logp, "rm -r /tmp/disk.$random_id");
#			$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/vnx.$vm_name.$seq.$random_id" );
#			$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_vm_hostfs_dir($vm_name) . "/filetree.$random_id" );
#			$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $filetree_host" );
#			$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_vm_hostfs_dir($vm_name) . "/filetree_cp.$random_id" );
#			$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_vm_hostfs_dir($vm_name) . "/filetree.xml" );
#			$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_vm_hostfs_dir($vm_name) . "/filetree_cp.$random_id.end" );
#		}
		############ COMMAND_FILE ########################
		# We open file

# VAMOS A USAR EL COMMAND_FILE DEL FILETREE, YA ABIERTO, AL QUE AÑADIREMOS LOS COMANDOS
#		open COMMAND_FILE,">" . $dh->get_tmp_dir . "/vnx.$vm_name.$seq.$random_id" or $execution->smartdie("can not open " . $dh->get_tmp_dir . "/vnx.$vm_name.$seq: $!" )
#		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

		# FIXME: consider to use a different new VNX::Execution object to perform this
		# actions (avoiding this nasty verb_prompt backup)
#		$execution->set_verb_prompt("$vm_name> ");
#		$cmd = $bd->get_binaries_path_ref->{"date"};
#		chomp( $now = `$cmd` );

		# To process exec tags of matching commands sequence
		#my $command_list = $vm->getElementsByTagName("exec");

# EL COMMAND_FILE YA ESTA CREADO
		# To process list, dumping commands to file
#		$execution->execute( $logp, "<command>", *COMMAND_FILE );
		
		# Insert random id number for the command file
#		$fileid = $vm_name . "-" . &generate_random_string(6);
#		$execution->execute( $logp, "<id>" . $fileid ."</id>", *COMMAND_FILE );

		my $countcommand = 0;
		#for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
		foreach my $command ($vm->getElementsByTagName("exec")) {
			#my $command = $command_list->item($j);	
			# To get attributes
			my $cmd_seq_string = $command->getAttribute("seq");
			
			# JSF 01/12/10: we accept several commands in the same seq tag,
			# separated by commas
			my @cmd_seqs = split(',',$cmd_seq_string);
			foreach my $cmd_seq (@cmd_seqs) {
			
			    # Remove leading or trailing spaces
                $cmd_seq =~ s/^\s+//;
                $cmd_seq =~ s/\s+$//;
			
				if ( $cmd_seq eq $seq ) {
					my $type = $command->getAttribute("type");
					# Case 1. Verbatim type
					if ( $type eq "verbatim" ) {
						# Including command "as is"
						my $comando = $command->toString(1);
						$execution->execute( $logp, $comando, *COMMAND_FILE );
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
							$execution->execute( $logp, 
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
		$execution->execute( $logp, "</command>", *COMMAND_FILE );
		# We close file and mark it executable
		close COMMAND_FILE
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
        $execution->pop_verb_prompt();

# AHORA EL FICHERO ES COMMAND.XML
#		$execution->execute( $logp, $bd->get_binaries_path_ref->{"chmod"} . " a+x " . $dh->get_tmp_dir  . "/vnx.$vm_name.$seq.$random_id" );
		$execution->execute( $logp, $bd->get_binaries_path_ref->{"chmod"} . " a+x " . $dh->get_vm_tmp_dir($vm_name) . "/command.xml");
		############# INSTALL COMMAND FILES #############
		# Nothing to do in libvirt mode
		############# EXEC_COMMAND_FILE #################
				
		if ( $countcommand != 0 ) {

            # Save a copy of the last command.xml 
            $execution->execute( $logp, "cp " . $dh->get_vm_tmp_dir($vm_name) . "/command.xml " . $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml" );

			$execution->execute( $logp, "mkdir /tmp/diskc.$seq.$random_id");
# REESCRIBIMOS ESTAS LINEAS CON LAS NUEVAS COSAS QUE USAMOS
            $execution->execute( $logp, "cp " . $dh->get_vm_tmp_dir($vm_name) . "/command.xml" . " " . "$filetree_host" );
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"mkisofs"} . " -d -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/disk.$random_id.iso $filetree_host");
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
		#	$source_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( file => "/tmp/diskc.$seq.$random_id.iso" ) );
			$source_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( file => "/tmp/disk.$random_id.iso" ) );
			
			
			my $target_command_windows_tag =$disk_command_windows_xml->createElement('target');
			$disk_command_windows_tag->addChild($target_command_windows_tag);
			$target_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( dev => "hdb" ) );
			
			my $readonly_command_windows_tag =$disk_command_windows_xml->createElement('readonly');
			$disk_command_windows_tag->addChild($readonly_command_windows_tag);
			my $format_command_windows   = 1;
			my $xmlstring_command_windows = $disk_command_windows_xml->toString($format_command_windows );
			
			$execution->execute( $logp, "rm ". $dh->get_vm_hostfs_dir($vm_name) . "/command_libvirt.xml"); 
			
			open XML_COMMAND_WINDOWS_FILE, ">" . $dh->get_vm_hostfs_dir($vm_name) . '/' . 'command_libvirt.xml'
	 			 or $execution->smartdie("can not open " . $dh->get_vm_hostfs_dir . '/' . 'command_libvirt.xml' )
	  		unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
			print XML_COMMAND_WINDOWS_FILE "$xmlstring_command_windows\n";
			close XML_COMMAND_WINDOWS_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
			$execution->execute( $logp, "virsh -c qemu:///system 'attach-device \"$vm_name\" ". $dh->get_vm_hostfs_dir($vm_name) . "/command_libvirt.xml'");
			#$execution->execute( $logp, "virsh -c qemu:///system 'attach-disk \"$vm_name\" /tmp/diskc.$seq.$random_id.iso hdb --mode readonly --driver file --type cdrom'");
			print "Sending command to client... \n" if ($exemode == $EXE_VERBOSE);

            my $vmsocket;
            if (USE_UNIX_SOCKETS == 1) { # Use a UNIX socket

	            #my $socket_fh = "/var/run/libvirt/vnx/" . $dh->get_scename . "/${vm_name}_socket";
	            #my $socket_fh = $dh->get_tmp_dir . "/.vnx/" . $dh->get_scename . "/${vm_name}_socket";
	            my $socket_fh = $dh->get_vm_dir($vm_name).'/run/'.$vm_name.'_socket';
	            $vmsocket = IO::Socket::UNIX->new(
	                Type => SOCK_STREAM,
	                Peer => $socket_fh,
	                Timeout => 10
	            ) or $execution->smartdie("Can't connect to server: $!");

            } else {  # Use TCP

                # Add it to h2vm_port file
                my $h2vm_fname = $dh->get_vm_dir . "/$vm_name/run/h2vm_port";
                open H2VMFILE, "< $h2vm_fname"
                    or $execution->smartdie("can not open $h2vm_fname\n")
                    unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
                my $h2vm_port = <H2VMFILE>;

                wlog (VV, "port $h2vm_port used for $vm_name H2VM channel", $logp);

                $vmsocket = IO::Socket::INET->new(
                    Proto    => "tcp",
                    PeerAddr => "$VNX::Globals::H2VM_BIND_ADDR",
                    PeerPort => "$h2vm_port",
                ) or $execution->smartdie("Can't connect to $vm_name H2VM port: $!");

            }

            wait_sock_answer ($vmsocket);
            sleep(2);
            $vmsocket->close();         
			
			$execution->execute( $logp, "rm /tmp/diskc.$seq.$random_id.iso");
			$execution->execute( $logp, "rm -r /tmp/diskc.$seq.$random_id");
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/vnx.$vm_name.$seq.$random_id" );
		    sleep(2);
		}

		
	###########################################
	#   executeCMD for LINUX & FREEBSD        #
	###########################################

	} elsif ( ($merged_type eq "libvirt-kvm-linux")   || 
	          ($merged_type eq "libvirt-kvm-freebsd") || 
	          ($merged_type eq "libvirt-kvm-olive") )    {
		
		
		# Calculate the efective basedir
      	#my $basedir = $dh->get_default_basedir;
      	#my $basedir_list = $vm->getElementsByTagName("basedir");
      	#if ($basedir_list->getLength == 1) {
		#        $basedir = &text_tag($basedir_list->item(0));
		#}

        my $sdisk_content;
        my $sdisk_fname;
        
        my $user   = &get_user_in_seq( $vm, $seq );
        my $exec_mode   = $dh->get_vm_exec_mode($vm);
        wlog (VVV, "---- vm_exec_mode = $exec_mode", $logp);

        if ( ($exec_mode ne "cdrom") && ($exec_mode ne "sdisk") ) {
            return "execution mode $exec_mode not supported for VM of type $merged_type";
        }       

        #if ($merged_type ne "libvirt-kvm-olive") {
        if ($exec_mode eq "cdrom") {
            # Create a temporary directory to store command.xml file and filetree files
	        my $command =  $bd->get_binaries_path_ref->{"mktemp"} . " -d -p " . $dh->get_vm_tmp_dir($vm_name)  . " filetree.XXXXXX";
	        chomp( $sdisk_content = `$command` );
	        $sdisk_content =~ /filetree\.(\w+)$/;
	        # create filetree dir
	        $execution->execute( $logp, "mkdir " . $sdisk_content ."/filetree");

        } elsif ($exec_mode eq "sdisk") {
	        # Mount the shared disk to copy command.xml and filetree files
	        $sdisk_fname  = $dh->get_vm_fs_dir($vm_name) . "/sdisk.img";
	        $sdisk_content = $dh->get_vm_hostfs_dir($vm_name);
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content );
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $sdisk_content );
	        # Delete the previous content of the shared disk (although it is done at 
	        # the end of this sub, we do it again here just in case...) 
	        $execution->execute( $logp, "rm -rf $sdisk_content/filetree/*");
	        $execution->execute( $logp, "rm -rf $sdisk_content/*.xml");
            $execution->execute( $logp, "rm -rf $sdisk_content/config/*");
            # Create filetree and config dirs in  the shared disk
            $execution->execute( $logp, "mkdir -p $sdisk_content/filetree");
            $execution->execute( $logp, "mkdir -p $sdisk_content/config");
        }
        
        # We create the command.xml file to be passed to the vm
        wlog (VVV, "opening file $sdisk_content/command.xml...", $logp);
        my $retry = 3;
        while ( ! open COMMAND_FILE, "> $sdisk_content/command.xml" ) {
        	# Sometimes this open fails with a read-only filesystem error message (??)...
        	# ...retrying inmediately seems to solve the problem...
            $retry--; wlog (VVV, "open failed for file $sdisk_content/command.xml...retrying", $logp);
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content );
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $sdisk_content );
            if ( $retry ==  0 ) {
                $execution->smartdie("cannot open " . $dh->get_vm_tmp_dir($vm_name) . "/command.xml $!" ) 
                unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
            }
		} 
		   
		$execution->set_verb_prompt("$vm_name> ");
		
		#my $shell      = $dh->get_default_shell;
		#my $shell_list = $vm->getElementsByTagName("shell");
		#if ( $shell_list->getLength == 1 ) {
		#	$shell = &text_tag( $shell_list->item(0) );
		#}
		
		$execution->execute( $logp, "<command>", *COMMAND_FILE );
		# Insert random id number for the command file
		my $fileid = $vm_name . "-" . &generate_random_string(6);
		$execution->execute( $logp, "<id>" . $fileid ."</id>", *COMMAND_FILE );
		my $dst_num = 1;
		
#pak "pak1";
		
		#		
		# Process of <filetree> tags
		#
		
		# 1 - Plugins <filetree> tags
		wlog (VVV, "executeCMD: number of plugin ftrees " . scalar(@{$plugin_ftree_list_ref}), $logp);
		
		foreach my $filetree (@{$plugin_ftree_list_ref}) {
			# Add the <filetree> tag to the command.xml file
			my $filetree_txt = $filetree->toString(1);
			$execution->execute( $logp, "$filetree_txt", *COMMAND_FILE );
	        # Each file created when calling plugin->getExecFiles has been copied to
	        # $dh->get_vm_tmp_dir($vm_name) . "/$seq/filetree/$dst_num" directory. 
	        # We move those files to the shared disk
	        my $files_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq"; 
	        $execution->execute( $logp, $bd->get_binaries_path_ref->{"mv"} . " $files_dir/filetree/$dst_num $sdisk_content/filetree" );
	        $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $files_dir/filetree/$dst_num" );
			wlog (VVV, "executeCMD: adding plugin filetree \"$filetree_txt\" to command.xml", $logp);
			$dst_num++;			 
		}
		
		# 2 - User defined <filetree> tags
        wlog (VVV, "executeCMD: number of user defined ftrees " . scalar(@{$ftree_list_ref}), $logp);
        
        foreach my $filetree (@{$ftree_list_ref}) {
            # Add the <filetree> tag to the command.xml file
            my $filetree_txt = $filetree->toString(1);
            $execution->execute( $logp, "$filetree_txt", *COMMAND_FILE );
            # Each file created when calling plugin->getExecFiles has been copied to
            # $dh->get_vm_tmp_dir($vm_name) . "/$seq/filetree/$dst_num" directory. 
            # We move those files to the shared disk
            my $files_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq"; 
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"mv"} . " $files_dir/filetree/$dst_num $sdisk_content/filetree" );
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $files_dir/filetree/$dst_num" );
            wlog (VVV, "executeCMD: adding user defined filetree \"$filetree_txt\" to command.xml", $logp);
            $dst_num++;            
        }
        
        my $res=`tree $sdisk_content`; 
        wlog (VVV, "executeCMD: shared disk content:\n $res", $logp);

		$execution->set_verb_prompt("$vm_name> ");
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
		}

		# 2 - User defined <exec> tags
        wlog (VVV, "executeCMD: number of user-defined <exec> = " . scalar(@{$ftree_list_ref}), $logp);
        
        foreach my $cmd (@{$exec_list_ref}) {
            # Add the <exec> tag to the command.xml file
            my $cmd_txt = $cmd->toString(1);
            $execution->execute( $logp, "$cmd_txt", *COMMAND_FILE );
            wlog (VVV, "executeCMD: adding user defined exec \"$cmd_txt\" to command.xml", $logp);

            # Process particular cases
            # 1 - Olive load config command
            if ($merged_type eq "libvirt-kvm-olive")  {
                my $ostype = $cmd->getAttribute("ostype");
                if ( $ostype eq "load" ) {
                    # We have to copy the configuration file to the shared disk
                    my @aux = split(' ', &text_tag($cmd));
                    wlog (VVV, "config file = $aux[1]", $logp);
                    # TODO: relative pathname
                    my $src = &get_abs_path ($aux[1]);
                    $src = &chompslash($src);
                    $execution->execute( $logp, $bd->get_binaries_path_ref->{"cp"} . " $src $sdisk_content/config");                                                  
                 }              
            }
        }


		# We close file and mark it executable
        $execution->execute( $logp, "</command>", *COMMAND_FILE );
		close COMMAND_FILE
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		$execution->pop_verb_prompt();
		
#pak "pak2";

		# Print command.xml file content to log if VVV
		open FILE, "< $sdisk_content/command.xml";
		my $cmd_file = do { local $/; <FILE> };
		close FILE;
		wlog (VVV, "command.xml file passed to vm $vm_name: \n$cmd_file", $logp);
        # Save a copy of the last command.xml vm main dir 
        $execution->execute( $logp, "cp " . "$sdisk_content/command.xml " . $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml" );

#pak "pak3";

        if ($exec_mode eq "cdrom") {
        #if ($merged_type ne "libvirt-kvm-olive") {

	        # Create the shared cdrom and offer it to the VM 
	        my $iso_disk = $dh->get_vm_tmp_dir($vm_name) . "/disk.$random_id.iso";
	        my $empty_iso_disk = $dh->get_vm_tmp_dir($vm_name) . "/empty.iso";
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"mkisofs"} . " -d -nobak -follow-links -max-iso9660-filename -allow-leading-dots " . 
			                    "-pad -quiet -allow-lowercase -allow-multidot " . 
			                    "-o $iso_disk $sdisk_content");
			$execution->execute( $logp, "virsh -c qemu:///system 'attach-disk \"$vm_name\" $iso_disk hdb --mode readonly --type cdrom'");

            # Send the exeCommand order to the virtual machine using the socket

            my $vmsocket;
            if (USE_UNIX_SOCKETS == 1) { # Use a UNIX socket

                #my $socket_fh = "/var/run/libvirt/vnx/" . $dh->get_scename . "/${vm_name}_socket";
                #my $socket_fh = $dh->get_tmp_dir . "/.vnx/" . $dh->get_scename . "/${vm_name}_socket";
                my $socket_fh = $dh->get_vm_dir($vm_name).'/run/'.$vm_name.'_socket';
                $vmsocket = IO::Socket::UNIX->new(
                    Type => SOCK_STREAM,
                    Peer => $socket_fh,
                    Timeout => 10
                ) or $execution->smartdie("Can't connect to server: $!");

            } else {  # Use TCP

                # Add it to h2vm_port file
                my $h2vm_fname = $dh->get_vm_dir . "/$vm_name/run/h2vm_port";
                open H2VMFILE, "< $h2vm_fname"
                    or $execution->smartdie("can not open $h2vm_fname\n")
                    unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
                my $h2vm_port = <H2VMFILE>;

                wlog (VV, "port $h2vm_port used for $vm_name H2VM channel", $logp);

                $vmsocket = IO::Socket::INET->new(
                    Proto    => "tcp",
                    PeerAddr => "$VNX::Globals::H2VM_BIND_ADDR",
                    PeerPort => "$h2vm_port",
                ) or $execution->smartdie("Can't connect to $vm_name H2VM port: $!");

            }

            $vmsocket->flush; # delete socket buffers, just in case...  
            print $vmsocket "exeCommand cdrom\n";     
            wlog (N, "exeCommand sent to VM $vm_name", $logp);            
	        # Wait for confirmation from the VM		
            wait_sock_answer ($vmsocket);
            $vmsocket->close();
            
            #waitfiletree($dh->get_vm_dir($vm_name) .'/'.$vm_name.'_socket');
			# mount empty iso, while waiting for new command	
			$execution->execute( $logp, "touch $empty_iso_disk");
			$execution->execute( $logp, "virsh -c qemu:///system 'attach-disk \"$vm_name\" $empty_iso_disk hdb --mode readonly --type cdrom'");
			sleep 1;
#pak "pak4";

		   	# Cleaning
	        $execution->execute( $logp, "rm $iso_disk $empty_iso_disk");
	        $execution->execute( $logp, "rm -rf $sdisk_content");
	        $execution->execute( $logp, "rm -rf " . $dh->get_vm_tmp_dir($vm_name) . "/$seq");

        } elsif ($exec_mode eq "sdisk") {

            $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content );
	        
	        # Send the exeCommand order to the virtual machine using the socket
            my $vmsocket;
            if (USE_UNIX_SOCKETS == 1) { # Use a UNIX socket

                #my $socket_fh = "/var/run/libvirt/vnx/" . $dh->get_scename . "/${vm_name}_socket";
                #my $socket_fh = $dh->get_tmp_dir . "/.vnx/" . $dh->get_scename . "/${vm_name}_socket";
                my $socket_fh = $dh->get_vm_dir($vm_name).'/run/'.$vm_name.'_socket';
                $vmsocket = IO::Socket::UNIX->new(
                    Type => SOCK_STREAM,
                    Peer => $socket_fh,
                    Timeout => 10
                ) or $execution->smartdie("Can't connect to server: $!");

            } else {  # Use TCP

                # Add it to h2vm_port file
                my $h2vm_fname = $dh->get_vm_dir . "/$vm_name/run/h2vm_port";
                open H2VMFILE, "< $h2vm_fname"
                    or $execution->smartdie("can not open $h2vm_fname\n")
                    unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
                my $h2vm_port = <H2VMFILE>;

                wlog (VV, "port $h2vm_port used for $vm_name H2VM channel", $logp);

                $vmsocket = IO::Socket::INET->new(
                    Proto    => "tcp",
                    PeerAddr => "127.0.0.1",
                    PeerPort => "$h2vm_port",
                ) or $execution->smartdie("Can't connect to $vm_name H2VM port: $!");

            }
	        
	        $vmsocket->flush; # delete socket buffers, just in case...  
            if ( $merged_type eq "libvirt-kvm-olive" ) {
                print $vmsocket "exeCommand\n";
            } else {
                print $vmsocket "exeCommand sdisk\n";  
            }  

            wlog (N, "exeCommand sent to VM $vm_name", $logp);            
            
            # Wait for confirmation from the VM     
            wait_sock_answer ($vmsocket);
            $vmsocket->close();	        
	        #readSocketResponse ($vmsocket);
#pak "pak4";
            # Cleaning
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $sdisk_content );
            $execution->execute( $logp, "rm -rf $sdisk_content/filetree/*");
            $execution->execute( $logp, "rm -rf $sdisk_content/*.xml");
            $execution->execute( $logp, "rm -rf $sdisk_content/config/*");
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content );
	    }

#pak "pak5";
	} 

    ################## EXEC_COMMAND_HOST ########################3

    my $doc = $dh->get_doc;
    
    # If host <host> is not present, there is nothing to do
    return if ( $doc->getElementsByTagName("host") eq 0 );
    
    # To get <host> tag
    my $host = $doc->getElementsByTagName("host")->item(0);
    
    # To process exec tags of matching commands sequence
    #my $command_list_host = $host->getElementsByTagName("exec");
    
    # To process list, dumping commands to file
    #for ( my $j = 0 ; $j < $command_list_host->getLength ; $j++ ) {
    foreach my $command ($host->getElementsByTagName("exec")) {
        #my $command = $command_list_host->item($j);
    
        # To get attributes
        my $cmd_seq = $command->getAttribute("seq");
        my $type    = $command->getAttribute("type");
    
        if ( $cmd_seq eq $seq ) {
    
            # Case 1. Verbatim type
            if ( $type eq "verbatim" ) {
    
                # To include the command "as is"
                $execution->execute( $logp, &text_tag_multiline($command) );
            }
    
            # Case 2. File type
            elsif ( $type eq "file" ) {
    
                # We open file and write commands line by line
                my $include_file = &do_path_expansion( &text_tag($command) );
                open INCLUDE_FILE, "$include_file"
                    or $execution->smartdie("can not open $include_file: $!");
                while (<INCLUDE_FILE>) {
                    chomp;
                    $execution->execute( $logp, $_);
                }
                close INCLUDE_FILE;
            }
    
            # Other case. Don't do anything (it would be an error in the XML!)
        }
    }
    return $error;
}

=BEGIN
sub readSocketResponse 
{
	my $socket = shift;
        #print "readResponse\n";
	while (1) {
		my $line = <$socket>;
		#chomp ($line);		
		print "** $line"; # if ($exemode == $EXE_VERBOSE);
		last if ( ( $line =~ /^OK/) || ( $line =~ /^NOTOK/) );
	}

	print "----------------------------\n" if ($exemode == $EXE_VERBOSE);

}
=END
=cut

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

=BEGIN
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
	$execution->execute( $logp, "#!" . $shell, *CONFILE );
	$execution->execute( $logp, 
		"# plugin configuration script generated by $basename at $now",
		*CONFILE );
	$execution->execute( $logp, "UTILDIR=/mnt/vnx", *CONFILE );

	my $at_least_one_file = "0";
	foreach my $plugin (@plugins) {
		my %files = $plugin->getBootFiles($name);

		if ( defined( $files{"ERROR"} ) && $files{"ERROR"} ne "" ) {
			$execution->smartdie(
				"plugin $plugin getBootFiles($name) error: "
				  . $files{"ERROR"} );
		}

		foreach my $key ( keys %files ) {

			# Create the directory to hold de file (idempotent operation)
			my $dir = dirname($key);
			mkpath( "$path/plugins_root/$dir", { verbose => 0 } );
			$execution->set_verb_prompt($verb_prompt_bk);
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"cp"}
				  . " $files{$key} $path/plugins_root/$key" );
			$execution->set_verb_prompt("$name(plugins)> ");

			# Remove the file in the host (this is part of the plugin API)
			$execution->execute( $logp, 
				$bd->get_binaries_path_ref->{"rm"} . " $files{$key}" );

			$at_least_one_file = 1;

		}

		my @commands = $plugin->getBootCommands($name);

		my $error = shift(@commands);
		if ( $error ne "" ) {
			$execution->smartdie(
				"plugin $plugin getBootCommands($name) error: $error");
		}

		foreach my $cmd (@commands) {
			$execution->execute( $logp, $cmd, *CONFILE );
		}
	}

	if ($at_least_one_file) {

		# The last commands in plugins_conf.sh is to push plugin_root/ to vm /
		$execution->execute( $logp, 
			"# Generated by $basename to push files generated by plugins",
			*CONFILE );
		$execution->execute( $logp, "cp -r \$UTILDIR/plugins_root/* /", *CONFILE );
	}

	# Close file and restore prompting method
	$execution->set_verb_prompt($verb_prompt_bk);
	close CONFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

	# Configuration file must be executable
	$execution->execute( $logp, $bd->get_binaries_path_ref->{"chmod"}
		  . " a+x $path"
		  . "plugins_conf.sh" );

}
=END
=cut


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
	my $globalNode   = $dom->getElementsByTagName("vnx_olive")->item(0);
	#my $virtualmList = $globalNode->getElementsByTagName("vm");
			
	# First, we look for a definition in the $vm_name <vm> section 
	#for ( my $j = 0 ; $j < $virtualmList->getLength ; $j++ ) {
	foreach my $virtualm ($globalNode->getElementsByTagName("vm")) {
	 	# We get name attribute
	 	#my $virtualm = $virtualmList->item($j);
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
		my @globalList = $globalNode->getElementsByTagName("global");
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

