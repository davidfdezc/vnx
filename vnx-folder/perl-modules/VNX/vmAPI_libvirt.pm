# vmAPI_libvirt.pm
#
# This file is a module part of VNX package.
#
# Authors: Jorge Somavilla, Jorge Rodriguez, Miguel Ferrer, Francisco José Martín, David Fernández
# Coordinated by: David Fernández (david@dit.upm.es)
#
# Copyright (C) 2016 	DIT-UPM
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
use v5.10;

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
my $one_pass_autoconf;
my $host_passthrough;
my $virtio;
my $disk_a;
my $disk_b;
my $disk_c;

# ---------------------------------------------------------------------------------------
#
# Module vmAPI_libvirt initialization code 
#
# ---------------------------------------------------------------------------------------
sub init {

    my $logp = "libvirt-init> ";
    my $error;
    
    return unless ( $dh->any_vmtouse_of_type('libvirt','kvm') );

	# get hypervisor from config file
	$hypervisor = get_conf_value ($vnxConfigFile, 'libvirt', 'hypervisor', 'root');
	if (!defined $hypervisor) { $hypervisor = $LIBVIRT_DEFAULT_HYPERVISOR };
    wlog (VVV, "[libvirt] conf: hypervisor=$hypervisor");

    # get one_pass_autoconf parameter from config file
    $one_pass_autoconf = get_conf_value ($vnxConfigFile, 'libvirt', 'one_pass_autoconf', 'root');
    if (!defined $one_pass_autoconf) { $one_pass_autoconf = $DEFAULT_ONE_PASS_AUTOCONF };
    wlog (VVV, "[libvirt] conf: one_pass_autoconf=$one_pass_autoconf");

    # get host-passthrough parameter from config file
    $host_passthrough = get_conf_value ($vnxConfigFile, 'libvirt', 'host_passthrough', 'root');
    if (!defined $host_passthrough) { $host_passthrough = $DEFAULT_HOST_PASSTHROUGH };
    wlog (VVV, "[libvirt] conf: host_passthrough=$host_passthrough");

    # get virtio parameter from config file
    $virtio = get_conf_value ($vnxConfigFile, 'libvirt', 'virtio', 'root');
    if (!defined $virtio) { $virtio = $DEFAULT_VIRTIO };
    wlog (VVV, "[libvirt] conf: virtio=$virtio");
    if ($virtio eq 'yes') {
        $disk_a = 'vda';
        $disk_b = 'vdb';
        $disk_c = 'vdc';
    } else {
        $disk_a = 'hda';
        $disk_b = 'hdb';        
        $disk_c = 'hdc';        
    }
	
root();

	# load kvm modules
    #system "kvm-ok > /dev/null"; // kvm-ok not supported in Fedora
    system( "egrep '^flags.*(vmx|svm)' /proc/cpuinfo > /dev/null " );
    if ( $? != 0 ) {
        #system("kvm-ok"); # To show command output on screen
        $error = "The scenario contains KVM virtual machines, but the host does not show hardware virtualization support for KVM.";
    } else {
        wlog (N, "  KVM acceleration supported", "") unless ($opts{b});
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
                wlog (N, "  KVM nested virtualization supported", "") unless ($opts{b});                                    	
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
                wlog (N, "  KVM nested virtualization supported", "") unless ($opts{b});                                     
            } else {
                wlog (V, "Nested virtualization not enabled.", $logp);
                wlog (V, "If supported, add 'options kvm_amd nested=1' to file /etc/modprobe.d/kvm_amd.conf", $logp);                                                       
            }
        }
    }
user();

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

	my $self    = shift;
	my $vm_name = shift;
	my $type    = shift;
	my $vm_doc  = shift;

    my $logp = "libvirt-define_vm-$vm_name> ";
	my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);
	
	my $error;
	my $extConfFile;
	
    my $doc = $dh->get_doc;                                # scenario global doc
    my $vm = $vm_doc->findnodes("/create_conf/vm")->[0];   # VM node in $vm_doc
    my @vm_ordered = $dh->get_vm_ordered;                  # ordered list of VMs in scenario 

	my $sdisk_content;
	my $sdisk_fname;  # For olive only
	my $filesystem;
	my $con;

    my $exec_mode   = $dh->get_vm_exec_mode($vm);
    my $vm_arch = $vm->getAttribute("arch");
    if (empty($vm_arch)) { $vm_arch = 'i686' }  # default value

    if ( ($exec_mode ne "cdrom") && ($exec_mode ne "sdisk") && ($exec_mode ne "none") && 
         !($exec_mode eq "adb" &&  $type eq "libvirt-kvm-android") ) {
        $execution->smartdie( "execution mode $exec_mode not supported for VM of type $type" );
    }       

    if ($exec_mode eq "cdrom") {
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
        wlog (VVV, "vmfs_on_tmp=$vmfs_on_tmp", $logp);
        if ($vmfs_on_tmp eq 'yes') {
            $sdisk_fname = $dh->get_vm_fs_dir_ontmp($vm_name) . "/sdisk.img";
        } else {
            $sdisk_fname = $dh->get_vm_fs_dir($vm_name) . "/sdisk.img";
        }                
        
        # qemu-img create jconfig.img 12M
        # TODO: change the fixed 50M to something configurable
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"qemu-img"} . " create $sdisk_fname 50M" );

        if ( $type eq "libvirt-kvm-linux" ) {
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"mkfs.ext3"} . " -Fq $sdisk_fname" ); 
        } else {
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"mkfs.msdos"} . " $sdisk_fname" ); 
        }        	
        
        # Mount the shared disk to copy filetree files
        $sdisk_content = $dh->get_vm_hostfs_dir($vm_name) . "/";
        #$execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop,uid=$uid " . $sdisk_fname . " " . $sdisk_content );
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $sdisk_content );
        # Create filetree and config dirs in the shared disk
        $execution->execute( $logp, "mkdir -p $sdisk_content/filetree");
        $execution->execute( $logp, "mkdir -p $sdisk_content/config");        	
    }		

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

	#
	# define_vm for libvirt-kvm-windows
	#
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

#	    my $parser       = XML::LibXML->new();
#	    my $dom          = $parser->parse_string($vm_doc);
#		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
#		my $virtualmList = $globalNode->getElementsByTagName("vm");
#		my $virtualm     = $virtualmList->item(0);

		my $filesystemTagList = $vm->getElementsByTagName("filesystem");
		my $filesystemTag     = $filesystemTagList->item(0);
		my $filesystem_type   = $filesystemTag->getAttribute("type");
		$filesystem           = $filesystemTag->getFirstChild->getData;

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
		my $memTagList = $vm->getElementsByTagName("mem");
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
=BEGIN  # Eliminated. Substituted by host-passthough
        
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
=END
=cut
		# Check host_passthrough option and add <cpu mode="host-passthrough"/> tag 
		# in case it is enabled
		if ($host_passthrough eq 'yes') {
	        my $cpu_tag = $init_xml->createElement('cpu');
	        $domain_tag->addChild($cpu_tag);
			$cpu_tag->setAttribute( mode => "host-passthrough");
		}

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
        $type_tag->addChild( $init_xml->createAttribute( arch => "$vm_arch" ) );	

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

        if ($vm_arch eq "x86_64" ) {
            #$emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/kvm") );
            $emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/qemu-system-x86_64") );
        } else {
            $emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/qemu-system-i386") );
        } 

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
        $target1_tag->addChild( $init_xml->createAttribute( dev => $disk_a ) );
		
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
		$target2_tag->addChild( $init_xml->createAttribute( dev => $disk_b ) );

        # network <interface> tags
		my $mng_if_exists = 0;
		my $mng_if_mac;

		foreach my $if ($vm->getElementsByTagName("if")) {
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
        my $cons0Display = $VNX::Globals::CONS_DISPLAY_DEFAULT;
		foreach my $cons ($vm->getElementsByTagName("console")) {
       		my $value   = &text_tag($cons);
			my $id      = $cons->getAttribute("id");
			my $display = $cons->getAttribute("display");
       		#print "** console: id=$id, value=$value\n" if ($exemode == $EXE_VERBOSE);
			if ( $id eq "0" ) {
				wlog (N, "$hline\nWARNING (vm=$vm_name): value $value ignored for <console id='0'> tag (only 'vnc' allowed).\n$hline", $logp) 
				   if ( ($value ne "") && ($value ne "vnc") ); 
                #if ($display ne '') { $cons0Display = $display }
                unless (empty($display)) { $cons0Display = $display }
			}
			if ( $id > 0 ) {
				wlog (N, "$hline\nWARNING (vm=$vm_name): only consoles with id='0' allowed for Windows libvirt virtual machines. Tag ignored.\n$hline", $logp);
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
		# We do not know yet the vnc display (known when the machine is started in start_vm)
		# By now, we just write 'UNK_VNC_DISPLAY'
		print CONS_FILE "con0=$cons0Display,vnc_display,UNK_VNC_DISPLAY\n";
		#print "$consFile: con0=$cons0Display,vnc_display,UNK_VNC_DISPLAY\n" if ($exemode == $EXE_VERBOSE);
		close (CONS_FILE); 

        # <video> tag
        if ( $vm->exists("./video") ) {
            my $video_type = $vm->findnodes('./video')->[0]->to_literal();
            wlog (VVV,"video type set to $video_type", $logp);
            my $video_tag = $init_xml->createElement('video');
            my $model_tag = $init_xml->createElement('model');
            $video_tag->addChild($model_tag);
            my @allowed_video_types = qw/vga cirrus vmvga xen vbox qxl/;
            if ( grep( /^${video_type}$/, @allowed_video_types ) ) {
                $model_tag->setAttribute( type => $video_type); 
                #$video_tag->setAttribute( vram => "9216");
                #$video_tag->setAttribute( heads => "1");
                $devices_tag->addChild($video_tag);
            } else {
                wlog (N, "$hline\nWARNING: unknown video card type: $video_type.\n$hline", $logp)            	
            }
#            given ($video_type) {
#                when (@allowed_video_types) 
#                        { $model_tag->setAttribute( type => $video_type); 
#                          $devices_tag->addChild($video_tag);                                            }
#                default { wlog (N, "WARNING: unknown video card type: $video_type", $logp)} 
#            }
        }

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

        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

		my $format    = 1;
		my $xmlstring = $init_xml->toString($format);

		open XML_FILE, ">" . $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_libvirt.xml'
		  or $execution->smartdie(
			"can not open " . $dh->get_vm_dir . '/' . $vm_name . '_libvirt.xml')
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
		print XML_FILE "$xmlstring\n";
		close XML_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

        eval {
			# check that the domain is not already defined or started
root();
	        my @doms = $con->list_defined_domains();
			foreach my $listDom (@doms) {
				my $dom_name = $listDom->get_name();
				if ( $dom_name eq $vm_name ) {
					$error = "VM $vm_name already defined";
user();
					return $error;
				}
			}
			@doms = $con->list_domains();
			foreach my $listDom (@doms) {
				my $dom_name = $listDom->get_name();
				if ( $dom_name eq $vm_name ) {
					$error = "VM $vm_name already defined and started";
user();
					return $error;
				}
			}
			my $domain = $con->define_domain($xmlstring);
user();
        };
        if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }

	}
	
	#
	# define_vm for libvirt-kvm-linux/freebsd/openbsd/olive
	#
	elsif ( ($type eq "libvirt-kvm-linux")   || ($type eq "libvirt-kvm-freebsd") ||
	        ($type eq "libvirt-kvm-olive")   || ($type eq "libvirt-vbox")        || 
	        ($type eq "libvirt-kvm-android") || ($type eq "libvirt-kvm-wanos")   ||
	        ($type eq "libvirt-kvm-netbsd")  || ($type eq "libvirt-kvm-openbsd") ) {

        # Create vnxboot.xml file under $sdisk_content directory
        unless ( $execution->get_exe_mode() eq $EXE_DEBUG || $type eq "libvirt-kvm-android" || $type eq "libvirt-kvm-wanos" ) {
            open CONFILE, ">$sdisk_content" . "vnxboot.xml"
                or $execution->smartdie("can not open ${sdisk_content}vnxboot: $!");
            print CONFILE "$vm_doc\n";
            close CONFILE;
        }

        #        
		# We create the XML libvirt virtual machine specification file starting from the VNX XML 
		# virtual machine definition received in $vm_doc
		# 
#        my $parser       = XML::LibXML->new();
#        my $dom          = $parser->parse_string($vm_doc);
#		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
#		my $virtualmList = $globalNode->getElementsByTagName("vm");
#		my $virtualm     = $virtualmList->item(0);

		my $filesystemTagList = $vm->getElementsByTagName("filesystem");
		my $filesystemTag     = $filesystemTagList->item(0);
		my $filesystem_type   = $filesystemTag->getAttribute("type");
		$filesystem           = $filesystemTag->getFirstChild->getData;
        if ( $filesystem_type eq "cow" ) {
			
			my $cow_fs;
            if ($vmfs_on_tmp eq 'yes') {
                $cow_fs = $dh->get_vm_fs_dir_ontmp($vm_name) . "/root_cow_fs";
            } else {
                $cow_fs = $dh->get_vm_fs_dir($vm_name) . "/root_cow_fs";
            }
            wlog (V, "cow_fs=$cow_fs", $logp);
     		# Create the COW filesystem if it does not exist
			if ( !-f $cow_fs ) {
				$execution->execute( $logp, "qemu-img create -b $filesystem -f qcow2 $cow_fs");
			}
			$filesystem = $cow_fs;

		}

		# memory
		my $memTagList = $vm->getElementsByTagName("mem");
		my $memTag     = $memTagList->item(0);
		my $mem        = $memTag->getFirstChild->getData;

		# conf tag
		my $confFile = '';
		my @confTagList = $vm->getElementsByTagName("conf");
        if (@confTagList == 1) {
			$confFile = $confTagList[0]->getFirstChild->getData;
			wlog (VVV, "vm_name configuration file: $confFile", $logp);
        }

		# create the XML VM specification document for libvirt
		my $init_xml;
		$init_xml = XML::LibXML->createDocument( "1.0", "UTF-8" );
		my $domain_tag = $init_xml->createElement('domain');
		$init_xml->addChild($domain_tag);

        if ( ($type eq "libvirt-kvm-linux") || ($type eq "libvirt-kvm-freebsd") ||
             ($type eq "libvirt-kvm-olive") || ($type eq "libvirt-kvm-android") || 
             ($type eq "libvirt-kvm-wanos") || ($type eq "libvirt-kvm-netbsd")  ||
             ($type eq "libvirt-kvm-openbsd") ) {
    		# Note: changed the first line to 
    		# <domain type='qemu' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
    		# to allow the use of <qemu:commandline> tag to especify the bios in Olive routers
    		$domain_tag->addChild( $init_xml->createAttribute( type => "kvm" ) );
    		if ($type ne "libvirt-kvm-android" ) {
                $domain_tag->addChild( $init_xml->createAttribute( 'xmlns:qemu' => "http://libvirt.org/schemas/domain/qemu/1.0" ) );
    		}
        } elsif ( ( $type eq "libvirt-vbox") ) {
    		$domain_tag->addChild( $init_xml->createAttribute( type => "vbox" ) );
	    }
	            
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
		# Note 21/5/20013: this block prevents freebsd 64 bits to start. 
		#                  We eliminate it in that case. 
=BEGIN  # Eliminated. Substituted by host-passthough
		unless ( ($type eq "libvirt-kvm-freebsd") & ($vm->getAttribute("arch") eq "x86_64" ) || 
		         ($type eq "libvirt-kvm-android") ) {
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
		}
=END
=cut		
		# Check host_passthrough option and add <cpu mode="host-passthrough"/> tag 
		# in case it is enabled
        if ($host_passthrough eq 'yes') {
            my $cpu_tag = $init_xml->createElement('cpu');
            $domain_tag->addChild($cpu_tag);
            $cpu_tag->setAttribute( mode => "host-passthrough");
        }

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
        $type_tag->addChild( $init_xml->createAttribute( arch => "$vm_arch" ) );	

		# DFC 23/6/2011: Added machine attribute to avoid a problem in CentOS hosts
		my $machine;
		if ($type eq 'libvirt-kvm-android') {
			$machine = 'pc-i440fx-1.5';
		} else {
            $machine = 'pc';
		}
		$type_tag->addChild( $init_xml->createAttribute( machine => "$machine" ) );
		$type_tag->addChild( $init_xml->createTextNode("hvm") );

        # boot tag
        print $vm->toString() . "\n";
        if( $vm->exists("./boot") ){
            my $boot = $vm->findnodes('./boot')->[0]->to_literal();
            if ($boot eq 'network') {
                my $boot0_tag = $init_xml->createElement('boot');
                $os_tag->addChild($boot0_tag);
                $boot0_tag->addChild( $init_xml->createAttribute( dev => 'network' ) );                
            } elsif ($boot eq 'cdrom') {
                my $boot0_tag = $init_xml->createElement('boot');
                $os_tag->addChild($boot0_tag);
                $boot0_tag->addChild( $init_xml->createAttribute( dev => 'cdrom' ) );                
            }
            wlog (VVV,"boot tag set to $boot", $logp);
        }
		my $boot1_tag = $init_xml->createElement('boot');
		$os_tag->addChild($boot1_tag);
		$boot1_tag->addChild( $init_xml->createAttribute( dev => 'hd' ) );
		#my $boot2_tag = $init_xml->createElement('boot');
		#$os_tag->addChild($boot2_tag);
		#$boot2_tag->addChild( $init_xml->createAttribute( dev => 'cdrom' ) );

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

        if ($vm_arch eq "x86_64" ) {
            #$emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/kvm") );
            $emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/qemu-system-x86_64") );
        } else {
            $emulator_tag->addChild( $init_xml->createTextNode("/usr/bin/qemu-system-i386") );
        } 

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
        $target1_tag->addChild( $init_xml->createAttribute( dev => $disk_a ) );

		# DFC: Added '<driver name='qemu' type='qcow2'/>' to work with libvirt 0.8.x 
        my $driver1_tag = $init_xml->createElement('driver');
        $disk1_tag->addChild($driver1_tag);
        $driver1_tag->addChild( $init_xml->createAttribute( name => 'qemu' ) );
        $driver1_tag->addChild( $init_xml->createAttribute( type => 'qcow2' ) );

        # secondary <disk> tag --> cdrom or disk for autoconfiguration or command execution

        # Processing <filetree> tags:
        #
        # Files:
        #   Each file created when calling plugin->getBootFiles or specified in <filetree>'s 
        #   with seq='on_boot' has been copied to $dh->get_vm_tmp_dir($vm_name) . "/on_boot" 
        #   directory, organized in filetree/$num subdirectories, being $num the order of filetrees. 
        #   We move all the files to the shared disk
        
        # Check if there is any <filetree> tag in $vm_doc
        my @filetree_tag_list = $vm_doc->getElementsByTagName("filetree");
        if (@filetree_tag_list > 0) { # At least one filetree defined
            # Copy the files to the shared disk        
	        my $onboot_files_dir = $dh->get_vm_tmp_dir($vm_name) . "/on_boot";
	        $execution->execute( $logp, $bd->get_binaries_path_ref->{"mv"} . " -v $onboot_files_dir/filetree/* $sdisk_content/filetree/" );
	        $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $onboot_files_dir" );
	        my $res=`tree $sdisk_content`; wlog (VVV, "vm $vm_name 'on_boot' shared disk content:\n $res", $logp);
        }
    
        if ($exec_mode eq "cdrom") {

			# Create the iso filesystem for the cdrom
			my $filesystem_small;
            if ($vmfs_on_tmp eq 'yes') {
                $filesystem_small = $dh->get_vm_fs_dir_ontmp($vm_name) . "/opt_fs.iso";
            } else {
                $filesystem_small = $dh->get_vm_fs_dir($vm_name) . "/opt_fs.iso";
            }                
                			
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"mkisofs"}
				  . " -l -R -quiet -o $filesystem_small $sdisk_content" );
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $sdisk_content" );

			# Create the cdrom definition in libvirt XML doc
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
			$target2_tag->addChild( $init_xml->createAttribute( dev => $disk_b ) );
        
        } elsif ($exec_mode eq "sdisk") {

			# Copy autoconfiguration (vnxboot.xml) file to shared disk
			#$execution->execute( $logp, $bd->get_binaries_path_ref->{"cp"} . " $sdisk_content/vnxboot $sdisk_content/vnxboot.xml" );

			# If defined in a <config> tag, copy the configuration file specified to shared disk 
			if ($confFile ne '') {
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"cp"} . " $confFile $sdisk_content/config" );
			}

			# Dismount shared disk
			# Note: under some systems this umount fails. We sleep for a while and, in case it fails, we wait and retry 3 times...
            Time::HiRes::sleep(0.2);
            my $retry=3;
			while ( $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content ) ) {
                $retry--; last if $retry == 0;  
                wlog (N, "umount $sdisk_content failed. Retrying...", "");			
                Time::HiRes::sleep(0.2);
			}

			# Create the shared <disk> definition in libvirt XML document
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
			$target2_tag->addChild( $init_xml->createAttribute( dev => $disk_b ) );
			# Testing Fedora 17 problem with shared disk...
			#$target2_tag->addChild( $init_xml->createAttribute( cache => 'none' ) );
			
        }
        
        #<disk type='file' device='cdrom'>
        #    <source file='$cdrom_fname'/>
        #    <target dev='$disk_b'/>
        #</disk>
        if ( $vm->exists("./cdrom") ) {
            my $cdrom = $vm->findnodes('./cdrom')->[0]->to_literal();

            # Create the cdrom definition in libvirt XML doc
            my $disk2_tag = $init_xml->createElement('disk');
            $devices_tag->addChild($disk2_tag);
            $disk2_tag->addChild( $init_xml->createAttribute( type   => 'file' ) );
            $disk2_tag->addChild( $init_xml->createAttribute( device => 'cdrom' ) );
            my $source2_tag = $init_xml->createElement('source');
            $disk2_tag->addChild($source2_tag);
            $source2_tag->addChild(
                $init_xml->createAttribute( file => $cdrom ) );
            my $target2_tag = $init_xml->createElement('target');
            $disk2_tag->addChild($target2_tag);
            $target2_tag->addChild( $init_xml->createAttribute( dev => $disk_c ) );

        }
        
        
        # network <interface> tags linux
		my $mng_if_exists = 0;
		my $mng_if_mac;

		foreach my $if ($vm->getElementsByTagName("if")) {
			my $id    = $if->getAttribute("id");
			my $net   = $if->getAttribute("net");
            my $mac   = $if->getAttribute("mac");
            my $net_mode = $dh->get_net_mode($net) unless ($id == 0);

			# Ignore loopback interfaces (they are configured by the ACED daemon and
			# should not be processed by libvirt)
			if (defined($net) && $net eq "lo") { next}
			 
			my $interface_tag;
			if ($id eq 0){
				$mng_if_exists = 1;
				$mac =~ s/,//;
				$mng_if_mac = $mac;	
                # Now mgmt interfaces are defined in <qemu:commandline> section
                # but for android VMs (they hang when using the present libvirt 
                # mgmt definition)
			 	unless ($type eq 'libvirt-kvm-android' ) { next }
			}
			$interface_tag = $init_xml->createElement('interface');
            $devices_tag->addChild($interface_tag);
				
            # Ex: <interface type='bridge' name='eth1' onboot='yes'>
			$interface_tag->addChild( $init_xml->createAttribute( type => 'bridge' ) );
			$interface_tag->addChild( $init_xml->createAttribute( name => "eth" . $id ) );
			$interface_tag->addChild( $init_xml->createAttribute( onboot => "yes" ) );

			# Ex: <source bridge="Net0"/>
			my $source_tag = $init_xml->createElement('source');
			$interface_tag->addChild($source_tag);
            if ($id eq 0 && empty($net) && $type eq 'libvirt-kvm-android' ) {
                $source_tag->addChild( $init_xml->createAttribute( bridge => "${vm_name}-mgmt" ) );
            } else {
#print "net=$net\n"; pak();            	
                $source_tag->addChild( $init_xml->createAttribute( bridge => $net ) );
            }

            # Ex: <virtualport type="openvswitch"/>
            if (str($net_mode) eq "openvswitch"){
                my $virtualswitch_tag = $init_xml->createElement('virtualport');
                $interface_tag->addChild($virtualswitch_tag);
                $virtualswitch_tag->addChild($init_xml->createAttribute( type => 'openvswitch' ) );
            }

            # Ex: <target dev="vm1-e1"/>
            my $target_tag = $init_xml->createElement('target');
            $interface_tag->addChild($target_tag);
            $target_tag->addChild( $init_xml->createAttribute( dev => "$vm_name-e$id" ) );

			# Ex: <mac address="02:fd:00:04:01:00"/>
			my $mac_tag = $init_xml->createElement('mac');
			$interface_tag->addChild($mac_tag);
			$mac =~ s/,//;
			$mac_tag->addChild( $init_xml->createAttribute( address => $mac ) );

            # <model type='e1000'/>
            my $model_tag = $init_xml->createElement('model');
            $interface_tag->addChild($model_tag);
            $model_tag->addChild( $init_xml->createAttribute( type => 'e1000' ) );
			    
						

			# DFC: set interface model to 'i82559er' in olive router interfaces.
			#      If using e1000 instead, the interfaces are not created correctly (to further investigate) 
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
        my $consType = $VNX::Globals::CONS1_DEFAULT_TYPE;
        my $cons0Display = $VNX::Globals::CONS_DISPLAY_DEFAULT;
        my $cons1Display = $VNX::Globals::CONS_DISPLAY_DEFAULT;
        my $cons1Port = '';
		foreach my $cons ($vm->getElementsByTagName("console")) {
       		my $value   = &text_tag($cons);
			my $id      = $cons->getAttribute("id");
			my $display = $cons->getAttribute("display");
       		wlog (VVV, "console: id=$id, value=$value", $logp);
			if (  $id eq "0" ) {
                #if ($display ne '') { $cons0Display = $display }
				unless (empty($display)) { $cons0Display = $display }
                else                     { $cons0Display = '' }
			}
			if ( $id eq "1" ) {
				if ( $value eq "pts" || $value eq "telnet" ) { $consType = $value; }
				$cons1Port = $cons->getAttribute("port");
				#if ($display ne '') { $cons1Display = $display }
                unless (empty($display)) { $cons1Display = $display }
                else                     { $cons1Display = '' }
			}
			if ( $id > 1 ) {
				wlog (N, "$hline\nWARNING (vm=$vm_name): only consoles with id='0' or id='1' allowed for libvirt virtual machines. Tag ignored.\n$hline", $logp);
			} 
		}

        # Graphical console: <console id="0"> 
		#   Always created for all vms but Olive routers
		#   We just add a <graphics type="vnc"> tag
		if ($type ne "libvirt-kvm-olive") { 
			my $graphics_tag = $init_xml->createElement('graphics');
			$devices_tag->addChild($graphics_tag);
			$graphics_tag->addChild( $init_xml->createAttribute( type => 'vnc' ) );
			my $ip_host = "";
			$graphics_tag->addChild(
				$init_xml->createAttribute( listen => $ip_host ) );
			# Write the vnc console entry in "./vnx/.../vms/$vm_name/console" file
			# We do not know yet the vnc display (known when the machine is started in start_vm)
			# By now, we just write 'UNK_VNC_DISPLAY'
			print CONS_FILE "con0=$cons0Display,vnc_display,UNK_VNC_DISPLAY\n";
			wlog (VVV, "$consFile: con0=$cons0Display,vnc_display,UNK_VNC_DISPLAY", $logp);
		}
				     
        # Text console: <console id="1"> 
		wlog (VVV, "console #1 type: $consType (port=" . str2($cons1Port) . ")", $logp);

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
			# We do not know yet the pts device assigned (known when the machine is started in start_vm)
			# By now, we just write 'UNK_PTS_DEV'
			print CONS_FILE "con1=$cons1Display,libvirt_pts,UNK_PTS_DEV\n";
			wlog (VVV, "$consFile: con1=$cons1Display,libvirt_pts,UNK_PTS_DEV", $logp);
			
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
 			wlog (N, "$hline\nWARNING (vm=$vm_name): cannot use port $cons1Port for $vm_name console #1; using $consolePort instead.\n$hline", $logp)
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

        # <video> tag
        if ( $vm->exists("./video") ) {
            my $video_type = $vm->findnodes('./video')->[0]->to_literal();
            wlog (VVV,"video type set to $video_type", $logp);
            my $video_tag = $init_xml->createElement('video');
            my $model_tag = $init_xml->createElement('model');
            $video_tag->addChild($model_tag);
            my @allowed_video_types = qw/vga cirrus vmvga xen vbox qxl/;
            if ( grep( /^${video_type}$/, @allowed_video_types ) ) {
                $model_tag->setAttribute( type => $video_type); 
                #$video_tag->setAttribute( vram => "9216");
                #$video_tag->setAttribute( heads => "1");
                $devices_tag->addChild($video_tag);
            } else {
                wlog (N, "$hline\nWARNING: unknown video card type: $video_type.\n$hline", $logp)                
            }
        }

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
		
		
        if ($mng_if_exists && $type ne 'libvirt-kvm-android'){      
		
            # -device rtl8139,netdev=lan1 -netdev tap,id=lan1,ifname=ubuntu-e0,script=no,downscript=no
            my $mgmt_eth_type = 'rtl8139';
		
            my $qemucommandline_tag = $init_xml->createElement('qemu:commandline');
            $domain_tag->addChild($qemucommandline_tag);
				
            my $qemuarg_tag = $init_xml->createElement('qemu:arg');
            $qemucommandline_tag->addChild($qemuarg_tag);
            $qemuarg_tag->addChild( $init_xml->createAttribute( value => "-device" ) );
				
            $mng_if_mac =~ s/,//;
            my $qemuarg_tag2 = $init_xml->createElement('qemu:arg');
            $qemucommandline_tag->addChild($qemuarg_tag2);
            $qemuarg_tag2->addChild( $init_xml->createAttribute( value => "$mgmt_eth_type,netdev=mgmtif0,mac=$mng_if_mac" ) );
				
            my $qemuarg_tag3 = $init_xml->createElement('qemu:arg');
            $qemucommandline_tag->addChild($qemuarg_tag3);
            $qemuarg_tag3->addChild( $init_xml->createAttribute( value => "-netdev" ) );
				
            my $qemuarg_tag4 = $init_xml->createElement('qemu:arg');
            $qemucommandline_tag->addChild($qemuarg_tag4);
            $qemuarg_tag4->addChild( $init_xml->createAttribute( value => "tap,id=mgmtif0,ifname=$vm_name-e0,script=no" ) );
				
		}

        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

        my $format    = 1;
        my $xmlstring = $init_xml->toString($format);

        # Save the XML libvirt file to .vnx/scenarios/<vscenario_name>/vms/$vm_name
        unless ( $execution->get_exe_mode() eq $EXE_DEBUG ) {
	        open XML_FILE, ">" . $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_libvirt.xml'
	          or $execution->smartdie("can not open " . $dh->get_vm_dir . '/' . $vm_name . '_libvirt.xml' );
	        print XML_FILE "$xmlstring\n";
	        close XML_FILE;
        }

        eval {
root();
	        # check that the domain is not already defined or started
	        my @doms = $con->list_defined_domains();
			foreach my $listDom (@doms) {
				my $dom_name = $listDom->get_name();
				if ( $dom_name eq $vm_name ) {
					$error = "VM $vm_name already defined";
user();
					return $error;
				}
			}
			@doms = $con->list_domains();
			foreach my $listDom (@doms) {
				my $dom_name = $listDom->get_name();
				if ( $dom_name eq $vm_name ) {
					$error = "VM $vm_name already defined and started";
user();
					return $error;
				}
			}
	        
	        # Define the new virtual machine
	        unless ( $execution->get_exe_mode() eq $EXE_DEBUG ) {
			  my $domain = $con->define_domain($xmlstring);
	        }
user();
        };
        if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }

	} else {
		$error = "define_vm for type $type not implemented yet";
		return $error;
	}
	
	
    # Do one-pass autoconfiguration if configured in vnx.conf and if it is possible 
    # depending on image type (by now only for Linux systems)
    if ( ($one_pass_autoconf eq 'yes') && ($type eq "libvirt-kvm-linux") ) {

        wlog (V, "One-pass autoconfiguration", $logp);

        my $rootfs_mount_dir = $dh->get_vm_dir($vm_name) . '/mnt';

        my $get_os_distro_code = get_code_of_get_os_distro();

        # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
        # host files will be modified instead of rootfs image ones
        unless ( defined($rootfs_mount_dir) && $rootfs_mount_dir ne '' && $rootfs_mount_dir ne '/' ) {
            die;
        }

        #
        # Mount the root filesystem
        # We loop mounting all image partitions till we find a /etc directory
        # 
        my $mounted;
        for ( my $i = 1; $i < 5; $i++) {

            wlog (VVV,  "Trying: vnx_mount_rootfs -p $i -r $filesystem $rootfs_mount_dir", $logp);
            $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -p $i -r $filesystem $rootfs_mount_dir");
            #system "vnx_mount_rootfs -b -p $i -r $filesystem $rootfs_mount_dir";
            if ( $? != 0 ) {
                wlog (VVV,  "Cannot mount partition $i of '$filesystem'", $logp);
                next
            } else {
                system "ls $rootfs_mount_dir/etc  > /dev/null 2>&1";
                unless ($?) {
                    $mounted='true';
                    last    
                } else {
                    wlog (VVV,  "/etc not found in partition $i of '$filesystem'", $logp);
                }
            }
            $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -u $rootfs_mount_dir");
            #system "vnx_mount_rootfs -b -u $rootfs_mount_dir";
        }

        unless ($mounted) {
            wlog (VVV,  "cannot mount '$filesystem'. One-pass-autoconfiguration not possible", $logp);
            return $error
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
		my $os_distro = `LANG=C chroot $rootfs_mount_dir /tmp/get_os_distro 2> /dev/null`;
		my @platform = split(/,/, $os_distro);
        
        # Check consistency of VM definition and hardware platform 
        # We cannot use the information returned by get_os_distro ($platform[5]) because as it is executed 
        # using chroot and returns the host info, not the rootfs image. We use the command file instead
        my $rootfs_arch;
        if    ( `file $rootfs_mount_dir/bin/bash | grep 32-bit` ) { $rootfs_arch = 'i686' }
        elsif ( `file $rootfs_mount_dir/bin/bash | grep 64-bit` ) { $rootfs_arch = 'x86_64' }

        wlog (V, "Image OS detected: $platform[0],$platform[1],$platform[2],$platform[3]," . str($rootfs_arch), $logp);

        if ( defined($rootfs_arch) && $vm_arch ne $rootfs_arch ) {
            # Delete script, dismount the rootfs image and return error        
            system "rm $rootfs_mount_dir/tmp/get_os_distro";
            $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -u $rootfs_mount_dir");
            #system "vnx_mount_rootfs -b -u $rootfs_mount_dir";
            return "Inconsistency detected between VM $vm_name architecture defined in XML ($vm_arch) and rootfs architecture ($platform[5])";
        } 

		# Third, delete the script
		system "rm $rootfs_mount_dir/tmp/get_os_distro";
		#pak("get_os_distro deleted");        

		# Parse VM config file
		#my $parser = XML::LibXML->new;
		#my $dom    = $parser->parse_file( $dh->get_vm_dir($vm_name) . "/${vm_name}_conf.xml" );
		
		# Call autoconfiguration
		if ($platform[0] eq 'Linux'){
		    
            if    ($platform[1] eq 'Ubuntu') 
                { autoconfigure_debian_ubuntu ($vm_doc, $rootfs_mount_dir, 'ubuntu') }           
            elsif ($platform[1] eq 'Debian' || $platform[1] eq 'Kali') 
                { autoconfigure_debian_ubuntu ($vm_doc, $rootfs_mount_dir, 'debian') }           
		    elsif ($platform[1] eq 'Fedora') 
                { autoconfigure_redhat ($vm_doc, $rootfs_mount_dir, 'fedora') }
		    elsif ($platform[1] eq 'CentOS') 
		        { autoconfigure_redhat ($vm_doc, $rootfs_mount_dir, 'centos') }
		    
		#} elsif ($platform[0] eq 'FreeBSD'){
		#        wlog (VVV,  "FreeBSD");
		#        autoconfigure_freebsd ($dom, $rootfs_mount_dir)
		        
		} else {
		    wlog (VVV, "One-pass-autoconfiguration not possible for this platform ($platform[0]). Only available for Linux.");
            return $error;
		}
		
		# Get the id from the VM config file 
		my $cid   = $vm_doc->getElementsByTagName("id")->[0]->getFirstChild->getData;
		chomp($cid);
		
		# And save it to the VNACED_STATUS file
        system "mkdir -p ${rootfs_mount_dir}/${VNXACED_STATUS_DIR}" unless (-d $rootfs_mount_dir . $VNXACED_STATUS);
		my $vnxaced_status_file = $rootfs_mount_dir . $VNXACED_STATUS;
		system "sed -i -e '/cmd_id/d' $vnxaced_status_file" if (-f $vnxaced_status_file);
		system "echo \"cmd_id=$cid\" >> $vnxaced_status_file";

        # Set the VNACED_STATUS variable 'on_boot_cmds_pending' to yes 
        system "sed -i -e '/on_boot_cmds_pending/d' $vnxaced_status_file" if (-f $vnxaced_status_file);
        system "echo \"on_boot_cmds_pending=yes\" >> $vnxaced_status_file";

        # Set the VNACED_STATUS variable 'exec_mode' 
        system "sed -i -e '/exec_mode/d' $vnxaced_status_file" if (-f $vnxaced_status_file);
        system "echo \"exec_mode=$exec_mode\" >> $vnxaced_status_file";

        # Dismount the rootfs image        
        $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -u $rootfs_mount_dir");
        
    } elsif ( $type eq "libvirt-kvm-android") {
        # Always configure android in this way (no vnxaced available for Android yet)    

        wlog (V, "Android one-pass autoconfiguration", $logp);

        my $rootfs_mount_dir = $dh->get_vm_dir($vm_name) . '/mnt';

        # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
        # host files will be modified instead of rootfs image ones
        unless ( defined($rootfs_mount_dir) && $rootfs_mount_dir ne '' && $rootfs_mount_dir ne '/' ) {
            die;
        }

        #
        # Mount the root filesystem
        # We loop mounting all image partitions till we find a /android*/system/etc directory
        # 
        my $mounted;
        my $android_root;
        for ( my $i = 1; $i < 5; $i++) {

            wlog (VVV,  "Trying: vnx_mount_rootfs -p $i -r $filesystem $rootfs_mount_dir", $logp);
            $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -p $i -r $filesystem $rootfs_mount_dir");
            if ( $? != 0 ) {
                wlog (VVV,  "Cannot mount partition $i of '$filesystem'", $logp);
                next
            } else {
                system "ls $rootfs_mount_dir/android*/system/etc  > /dev/null 2>&1";
                unless ($?) {
                    $mounted='true';
                    $android_root = $rootfs_mount_dir . "/" . `basename $rootfs_mount_dir/android*`;
                    chomp($android_root);
                    print $android_root . "\n";
                    last    
                } else {
                    wlog (VVV,  "/etc not found in partition $i of '$filesystem'", $logp);
                }
            }
            $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -u $rootfs_mount_dir");
        }

        unless ($mounted) {
            wlog (VVV,  "cannot mount '$filesystem'. Android one-pass-autoconfiguration not possible", $logp);
            return $error
            #exit (1);
        }
    
        autoconfigure_android ($vm_doc, $android_root, $dh->get_vmmgmt_type);
        # Dismount the rootfs image        
        $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -u $rootfs_mount_dir");
    
    } elsif ( $type eq "libvirt-kvm-wanos") {
        # Always configure wanos in this way (no vnxaced available for wanos)    

        wlog (V, "wanos one-pass autoconfiguration", $logp);

        my $rootfs_mount_dir = $dh->get_vm_dir($vm_name) . '/mnt';

        # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
        # host files will be modified instead of rootfs image ones
        unless ( defined($rootfs_mount_dir) && $rootfs_mount_dir ne '' && $rootfs_mount_dir ne '/' ) {
            die;
        }

        #
        # Mount the root filesystem
        # We loop mounting all image partitions till we find a /tce/etc/wanos/wanos.conf file
        # 
        my $mounted;
        for ( my $i = 1; $i < 5; $i++) {

            wlog (VVV,  "Trying: vnx_mount_rootfs -p $i -r $filesystem $rootfs_mount_dir", $logp);
            $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -p $i -r $filesystem $rootfs_mount_dir");
            #system "vnx_mount_rootfs -b -p $i -r $filesystem $rootfs_mount_dir";
            if ( $? != 0 ) {
                wlog (VVV,  "Cannot mount partition $i of '$filesystem'", $logp);
                next
            } else {
                system "ls $rootfs_mount_dir/tce/etc/wanos/wanos.conf  > /dev/null 2>&1";
                unless ($?) {
                    $mounted='true';
                    last    
                } else {
                    wlog (VVV,  "/tce/etc/wanos/wanos.conf not found in partition $i of '$filesystem'", $logp);
                }
            }
            $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -u $rootfs_mount_dir");
            #system "vnx_mount_rootfs -b -u $rootfs_mount_dir";
        }
        unless ($mounted) {
            wlog (VVV,  "cannot mount '$filesystem'. wanos one-pass-autoconfiguration not possible", $logp);
            return $error
            #exit (1);
        }

        # Parse VM config file
        #my $parser = XML::LibXML->new;
        #my $dom    = $parser->parse_file( $dh->get_vm_dir($vm_name) . "/${vm_name}_conf.xml" );
    
        autoconfigure_wanos ($vm_doc, $rootfs_mount_dir, $dh->get_vmmgmt_type);
        # Dismount the rootfs image        
        $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -u $rootfs_mount_dir");
    
    }
	
    return $error;
	
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
sub undefine_vm {

	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;

    my $logp = "libvirt-undefine_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error;
	my $con;

	#
	# undefine_vm for libvirt-kvm-windows/linux/freebsd/openbsd/olive
	#
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") || 
         ($type eq "libvirt-kvm-android") || ($type eq "libvirt-kvm-wanos") || 
         ($type eq "libvirt-kvm-netbsd")  || ($type eq "libvirt-kvm-openbsd") ) {

        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

        eval {
			my @doms = $con->list_defined_domains();
	
			foreach my $listDom (@doms) {
				my $dom_name = $listDom->get_name();
				if ( $dom_name eq $vm_name ) {
					unless ( $execution->get_exe_mode() eq $EXE_DEBUG ) {
					    $listDom->undefine();
					}
	                wlog (V, "VM succesfully undefined.", $logp);
		            # Remove vm directory content
                    $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_vm_dir($vm_name) . "/*.xml "
                                         . $dh->get_vm_dir($vm_name) . "/run/* " . $dh->get_vm_dir($vm_name) . "/fs/* "
                                         . $dh->get_vm_dir($vm_name) . "/tmp/* " );
user();
	                return $error;
				}
			}
            # Remove vm directory content
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_vm_dir($vm_name) . "/*.xml "
                                 . $dh->get_vm_dir($vm_name) . "/run/* " . $dh->get_vm_dir($vm_name) . "/fs/* "
                                 . $dh->get_vm_dir($vm_name) . "/tmp/* " );
			$error = "VM $vm_name does not exist";
user();
        };
        if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }
        
		return $error;
	}

	else {
		$error = "undefine_vm for type $type not implemented yet";
		return $error;
	}
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

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;
    my $no_consoles = shift;

    my $logp = "libvirt-start_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;
    my $con;
    
    #
    # start_vm for libvirt-kvm-windows/linux/freebsd/openbsd/olive
    #
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ||
         ($type eq "libvirt-kvm-android") || ($type eq "libvirt-kvm-wanos") ||
         ($type eq "libvirt-kvm-netbsd")  || ($type eq "libvirt-kvm-openbsd") ) {

        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

        my @doms;
        eval {
root();
          @doms = $con->list_defined_domains();
user();
        };
        if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }

        foreach my $listDom (@doms) {
            
            my $dom_name;
            eval {
root();             
                $dom_name = $listDom->get_name();
user();                
            };          
            if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }
            
            if ( $dom_name eq $vm_name ) {

                eval {
root();                 
                    $listDom->create();
user();
                };                  
                if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }

                wlog (V, "VM successfully started", $logp);
                
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
root();                 
                    my $cmd=$bd->get_binaries_path_ref->{"virsh"} . " -c qemu:///system vncdisplay $vm_name";
user();                 
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
                    my $conData=get_conf_value ($consFile, '', 'con1');
                    if ( defined $conData) {
                        my @consField = split(/,/, $conData);
                        if ($consField[1] eq 'libvirt_pts') {
root();                         
                            my $cmd=$bd->get_binaries_path_ref->{"virsh"} . " -c qemu:///system ttyconsole $vm_name";
user();
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
                        wlog (V, "$hline\nWARNING (vm=$vm_name): no data for console #1 found in $consFile.\n$hline", $logp);
                    }
                }
               
                # Then, we just read the console file and start the active consoles,
                # unless options -n|--no_console were specified by the user
                unless ($no_consoles eq 1){
root();
                   VNX::vmAPICommon->start_consoles_from_console_file ($vm_name);
user();                
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
                            
root();
                            # Get the vm management ip address 
                            my %net = &get_admin_address( 'file', $vm_name );
                            # Add it to hostlines file
                            open HOSTLINES, ">>" . $dh->get_sim_dir . "/hostlines"
                                or $execution->smartdie("can not open $dh->get_sim_dir/hostlines\n")
                                unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
                            print HOSTLINES $net{'vm'}->addr() . " $vm_name\n";
                            close HOSTLINES;
user();                            
                        }               
                    }
                }
                return $error;
            }
        }
        $error = "VM $vm_name does not exist";
        return $error;

    }
    else {
        $error = "Type is not yet supported";
        return $error;
    }
}


# ---------------------------------------------------------------------------------------
#
# shutdown_vm
#
# Shutdowns a virtual machine, The VM should be in 'running' state. If $kill is not defined,
# an ordered shutdown request is sent to VM; if $kill is defined, a power-off is issued.
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
sub shutdown_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;
    my $kill    = shift;

    my $logp = "libvirt-shutdown_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;
    my $con;

    wlog (V, "Shutting down vm $vm_name of type $type", $logp);

    #
    # shutdown_vm for libvirt-kvm-windows/linux/freebsd/openbsd#
    #
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ||
         ($type eq "libvirt-kvm-android") || ($type eq "libvirt-kvm-wanos") ||
         ($type eq "libvirt-kvm-netbsd")  || ($type eq "libvirt-kvm-openbsd") ) {

        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

        eval {
root();
            my @doms = $con->list_domains();
            foreach my $listDom (@doms) {
                my $dom_name = $listDom->get_name();
                if ( $dom_name eq $vm_name ) {

			        if (defined($kill)) {
			            # Kill the VM
                        $listDom->destroy();
			        } else {
			            # Shutdown the VM
                        $listDom->shutdown();
			        }

                    # remove run directory content
                    #$execution->execute( $logp, "rm -rf " . $dh->get_vm_run_dir($vm_name) . "/*" );

	                # Change back the console file to use 'UNK_VNC_DISPLAY' and 'UNK_PTS_DEV' tags 
	                my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
                    $execution->execute( $logp, $bd->get_binaries_path_ref->{"sed"} . " -i " .
                                          "-e 's/^\\(con0=.*,\\).*/\\1UNK_VNC_DISPLAY/g' " .
                                          "-e 's/^\\(con1=.*,\\).*/\\1UNK_PTS_DEV/g'" . " $consFile");
    
                    wlog (V, "VM succesfully shutted down", $logp);
user();
                    return $error;
                }
            }
            $error = "VM $vm_name does not exist";
user();
        };
        if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }
        
        return $error;

    }
    else {
        $error = "Type is not yet supported";
        return $error;
    }
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
sub suspend_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "libvirt-suspend_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;
    my $con;

    #
    # suspend_vm for libvirt-kvm-windows/linux/freebsd/openbsd
    #
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ||
         ($type eq "libvirt-kvm-android") || ($type eq "libvirt-kvm-wanos") ||
         ($type eq "libvirt-kvm-netbsd")  || ($type eq "libvirt-kvm-openbsd") ) {

        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

        eval {
root();
            my @doms = $con->list_domains();
            foreach my $listDom (@doms) {
                my $dom_name = $listDom->get_name();
                if ( $dom_name eq $vm_name ) {
                    $listDom->suspend();
                    wlog (V, "VM successfully suspended (error=$error)", $logp);
                    return $error;
                }
            }
            $error = "VM $vm_name does not exist";
user();     
        };
        if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }
        
        return $error;

    }
    else {
        $error = "Type is not yet supported";
        return $error;
    }
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
sub resume_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "libvirt-resume_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;
    my $con;

    wlog (V, "resuming VM $vm_name", $logp);

    #
    # resume_vm for libvirt-kvm-windows/linux/freebsd/openbsd
    #
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ||
         ($type eq "libvirt-kvm-android") || ($type eq "libvirt-kvm-wanos") ||
         ($type eq "libvirt-kvm-netbsd")  || ($type eq "libvirt-kvm-openbsd") ) {

        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

        eval {
root();
            my @doms = $con->list_domains();
            foreach my $listDom (@doms) {
                my $dom_name = $listDom->get_name();
                if ( $dom_name eq $vm_name ) {
                    $listDom->resume();
                    wlog (V, "VM successfully resumed", $logp);
                    return $error;
                }
            }
            $error = "VM $vm_name does not exist";
user();         
        };
        if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }
        
        return $error;

    }
    else {
        $error = "Type is not yet supported";
        return $error;
    }
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
sub save_vm {

	my $self     = shift;
	my $vm_name  = shift;
	my $type     = shift;
	my $filename = shift;

    my $logp = "libvirt-save_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error;
	my $con;

	wlog (V, "saving vm $vm_name of type $type", $logp);

	if ( $type eq "libvirt-kvm" ) {

        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

        eval {
root();
			my @doms = $con->list_domains();
			foreach my $listDom (@doms) {
				my $dom_name = $listDom->get_name();
				if ( $dom_name eq $vm_name ) {
					$listDom->save($filename);
					wlog (V, "VM saved to file $filename", $logp);
					return $error;
				}
			}
			$error = "VM $vm_name does not exist";
user();
        };
        if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }
        			
		return $error;

	}
	#
	# save_vm for libvirt-kvm-windows/linux/freebsd/openbsd
	#
    elsif (  ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
             ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ||
             ($type eq "libvirt-kvm-netbsd")  || ($type eq "libvirt-kvm-openbsd") ) {

        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

        eval {
root();
			my @doms = $con->list_domains();
			foreach my $listDom (@doms) {
				my $dom_name = $listDom->get_name();
				if ( $dom_name eq $vm_name ) {
					$listDom->save($filename);
					wlog (V, "VM successfully saved to file $filename", $logp);
					#&change_vm_status( $vm_name, "paused" );
					return $error;
				}
			}
            $error = "VM $vm_name does not exist";
user();
        };
        if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }
        
		return $error;

	}
	else {
		$error = "Type $type is not yet supported";
		return $error;
	}
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
sub restore_vm {

	my $self     = shift;
	my $vm_name   = shift;
	my $type     = shift;
	my $filename = shift;

    my $logp = "libvirt-restore_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error;
	my $con;

	wlog (V, "restoring vm $vm_name of type $type from file $filename", $logp);

 	#
	# restore_vm for libvirt-kvm-windows/linux/freebsd/openbsd#
	#
    if ( ($type eq "libvirt-kvm-windows") || ($type eq "libvirt-kvm-linux") ||
         ($type eq "libvirt-kvm-freebsd") || ($type eq "libvirt-kvm-olive") ||
         ($type eq "libvirt-kvm-android") || ($type eq "libvirt-kvm-wanos") ||
         ($type eq "libvirt-kvm-netbsd")  || ($type eq "libvirt-kvm-openbsd") ) {
	    
        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

        eval {
root();
			my $dom = $con->restore_domain($filename);
user();
        };
        if ($@) { return "Error calling $hypervisor hypervisor " . $@->stringify(); }

		wlog (V, "VM restored from file $filename", $logp);
		return $error;

	}
	else {
		$error = "Type is not yet supported";
		return $error;
	}
}



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

    my $logp = "libvirt-get_status_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name ...)", $logp);

    my $error;
    my $con;

        wlog (V, "Connecting to $hypervisor hypervisor...", $logp);
        eval { 
root();
            $con = Sys::Virt->new( address => $hypervisor, readonly => 0 );
user();
        };
        if ($@) { return "Error connecting to $hypervisor hypervisor " . $@->stringify(); }

    my $dom;
root();
    eval { $dom = $con->get_domain_by_name($vm_name) };
user();

    if ($dom) {
	    $$ref_hstate = $dom->get_info->{'state'};
	        
	    if    ($$ref_hstate eq Sys::Virt::Domain::STATE_NOSTATE)  { $$ref_hstate='STATE_NOSTATE'; $$ref_vstate='error' }
	    elsif ($$ref_hstate eq Sys::Virt::Domain::STATE_RUNNING)  { $$ref_hstate='STATE_RUNNING'; $$ref_vstate='running' }
	    elsif ($$ref_hstate eq Sys::Virt::Domain::STATE_BLOCKED)  { $$ref_hstate='STATE_BLOCKED'; $$ref_vstate='error' }
	    elsif ($$ref_hstate eq Sys::Virt::Domain::STATE_PAUSED)   { $$ref_hstate='STATE_PAUSED';  $$ref_vstate='paused' }
	    elsif ($$ref_hstate eq Sys::Virt::Domain::STATE_SHUTDOWN) { $$ref_hstate='STATE_SHUTDOWN';$$ref_vstate='error' }
	    elsif ($$ref_hstate eq Sys::Virt::Domain::STATE_SHUTOFF)  { $$ref_hstate='STATE_SHUTOFF'; $$ref_vstate='defined' }
	    elsif ($$ref_hstate eq Sys::Virt::Domain::STATE_CRASHED)  { $$ref_hstate='STATE_CRASHED'; $$ref_vstate='error' }
    } else {
    	# Domain not found
        $$ref_hstate='STATE_NOTFOUND';
        $$ref_vstate='undefined';
    }
    
    wlog (VVV, "state=$$ref_vstate, hstate=$$ref_hstate, error=" . str($error));
    return $error;

# NOTE: Other way of getting the status is using virsh:
# root();
#    my $virsh_vm_state = `LANG=C virsh list --all | grep " $vm_name " | awk '{print \$3\$4}'`;
#user();
#    if    ($virsh_vm_state eq 'running')  { $$ref_state = 'running' }
#    elsif ($virsh_vm_state eq 'shut off') { $$ref_state = 'defined' }
#    elsif ($virsh_vm_state eq 'paused')   { $$ref_state = 'suspended' }
#    ...     

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
sub execute_cmd {

	my $self    = shift;
    my $vm_name = shift;
	my $merged_type = shift;
	my $seq     = shift;
	my $vm      = shift;
	my $plugin_ftree_list_ref = shift;
	my $plugin_exec_list_ref  = shift;
    my $ftree_list_ref        = shift;
    my $exec_list_ref         = shift;

    my $error;

    my $logp = "libvirt-execute_cmd-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$merged_type, seq=$seq ...)", $logp);

	my $random_id  = &generate_random_string(6);


	###########################################
	#   execute_cmd for WINDOWS                #
	###########################################
			
	if ( $merged_type eq "libvirt-kvm-windows" ) {


		my @filetree_list = $dh->merge_filetree($vm);
		my $user   = &get_user_in_seq( $vm, $seq );
		my $exec_mode   = $dh->get_vm_exec_mode($vm);
		my $command =  $bd->get_binaries_path_ref->{"mktemp"} . " -d -p " . $dh->get_vm_hostfs_dir($vm_name)  . " filetree.XXXXXX";
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
					wlog (V, "$filetreetxt", $logp);
					$execution->execute( $logp, "$filetreetxt", *COMMAND_FILE );
				}
			}
		}


		my $countcommand = 0;
		foreach my $command ($vm->getElementsByTagName("exec")) {
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

		$execution->execute( $logp, $bd->get_binaries_path_ref->{"chmod"} . " a+x " . $dh->get_vm_tmp_dir($vm_name) . "/command.xml");
				
		if ( $countcommand != 0 ) {

            # Save a copy of the last command.xml 
            $execution->execute( $logp, "cp " . $dh->get_vm_tmp_dir($vm_name) . "/command.xml " . $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml" );

			$execution->execute( $logp, "mkdir /tmp/diskc.$seq.$random_id");
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
			$target_command_windows_tag->addChild( $disk_command_windows_xml->createAttribute( dev => $disk_b ) );
			
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
			wlog (V, "Sending command to client... ", $logp);

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

		
	#
	# execute_cmd for LINUX & FREEBSD & OpenBSD
	#
	} elsif ( ($merged_type eq "libvirt-kvm-linux") || ($merged_type eq "libvirt-kvm-freebsd") || 
	          ($merged_type eq "libvirt-kvm-olive") || ($merged_type eq "libvirt-kvm-netbsd")  || 
              ($merged_type eq "libvirt-kvm-openbsd") ) {
		
        my $sdisk_content;
        my $sdisk_fname;
        
        my $user   = get_user_in_seq( $vm, $seq );
        my $exec_mode   = $dh->get_vm_exec_mode($vm);
        wlog (VVV, "---- vm_exec_mode = $exec_mode", $logp);

        if ( ($exec_mode ne "cdrom") && ($exec_mode ne "sdisk") ) {
            return "execution mode $exec_mode not supported for VM of type $merged_type";
        }       

        if ($exec_mode eq "cdrom") {
            # Create a temporary directory to store command.xml file and filetree files
	        my $command =  $bd->get_binaries_path_ref->{"mktemp"} . " -d -p " . $dh->get_vm_tmp_dir($vm_name)  . " filetree.XXXXXX";
	        chomp( $sdisk_content = `$command` );
	        $sdisk_content =~ /filetree\.(\w+)$/;
	        # create filetree dir
	        $execution->execute( $logp, "mkdir " . $sdisk_content ."/filetree");

        } elsif ($exec_mode eq "sdisk") {
	        # Mount the shared disk to copy command.xml and filetree files
            if ($vmfs_on_tmp eq 'yes') {
                $sdisk_fname = $dh->get_vm_fs_dir_ontmp($vm_name) . "/sdisk.img";
            } else {
                $sdisk_fname = $dh->get_vm_fs_dir($vm_name) . "/sdisk.img";
            }                
	        $sdisk_content = $dh->get_vm_hostfs_dir($vm_name);
	        # Umount first (just in case it was mounted by error)
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content );
            #$execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop,uid=$uid " . $sdisk_fname . " " . $sdisk_content );
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $sdisk_content );
	        # Delete the previous content of the shared disk (although it is done at 
	        # the end of this sub, we do it again here just in case...) 
	        $execution->execute( $logp, "rm -rf $sdisk_content/filetree/*");
            $execution->execute( $logp, "rm -rf $sdisk_content/*.xml");
            #$execution->execute( $logp, "find $sdisk_content/ -type f -not -name 'vnxboot.xml' | xargs rm "); # Do not delete vnxboot.xml file
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
            #$execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop,uid=$uid " . $sdisk_fname . " " . $sdisk_content );
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
			
		#		
		# Process of <filetree> tags
		#
		
		# 1 - Plugins <filetree> tags
		wlog (VVV, "execute_cmd: number of plugin ftrees " . scalar(@{$plugin_ftree_list_ref}), $logp);
		
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
			wlog (VVV, "execute_cmd: adding plugin filetree \"$filetree_txt\" to command.xml", $logp);
			$dst_num++;			 
		}
		
		# 2 - User defined <filetree> tags
        wlog (VVV, "execute_cmd: number of user defined ftrees " . scalar(@{$ftree_list_ref}), $logp);
        
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
            wlog (VVV, "execute_cmd: adding user defined filetree \"$filetree_txt\" to command.xml", $logp);
            $dst_num++;            
        }
        
        my $res=`tree $sdisk_content`; 
        wlog (VVV, "execute_cmd: shared disk content:\n $res", $logp);

		$execution->set_verb_prompt("$vm_name> ");
		my $command = $bd->get_binaries_path_ref->{"date"};
		chomp( my $now = `$command` );

		#		
		# Process of <exec> tags
		#
		
		# 1 - Plugins <exec> tags
		wlog (VVV, "execute_cmd: number of plugin <exec> = " . scalar(@{$plugin_ftree_list_ref}), $logp);
		
		foreach my $cmd (@{$plugin_exec_list_ref}) {
			# Add the <exec> tag to the command.xml file
			my $cmd_txt = $cmd->toString(1);
			$execution->execute( $logp, "$cmd_txt", *COMMAND_FILE );
			wlog (VVV, "execute_cmd: adding plugin exec \"$cmd_txt\" to command.xml", $logp);
		}

		# 2 - User defined <exec> tags
        wlog (VVV, "execute_cmd: number of user-defined <exec> = " . scalar(@{$ftree_list_ref}), $logp);
        
        foreach my $cmd (@{$exec_list_ref}) {
            # Add the <exec> tag to the command.xml file
            my $cmd_txt = $cmd->toString(1);
            $execution->execute( $logp, "$cmd_txt", *COMMAND_FILE );
            wlog (VVV, "execute_cmd: adding user defined exec \"$cmd_txt\" to command.xml", $logp);

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
		
		# Print command.xml file content to log if VVV
		open FILE, "< $sdisk_content/command.xml";
		my $cmd_file = do { local $/; <FILE> };
		close FILE;
		wlog (VVV, "command.xml file passed to vm $vm_name: \n$cmd_file", $logp);
        # Save a copy of the last command.xml vm main dir 
        $execution->execute( $logp, "cp " . "$sdisk_content/command.xml " . $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml" );

        if ($exec_mode eq "cdrom") {

	        # Create the shared cdrom and offer it to the VM 
	        my $iso_disk = $dh->get_vm_tmp_dir($vm_name) . "/disk.$random_id.iso";
	        my $empty_iso_disk = $dh->get_vm_tmp_dir($vm_name) . "/empty.iso";
			$execution->execute( $logp, $bd->get_binaries_path_ref->{"mkisofs"} . " -d -nobak -follow-links -max-iso9660-filename -allow-leading-dots " . 
			                    "-pad -quiet -allow-lowercase -allow-multidot " . 
			                    "-o $iso_disk $sdisk_content");
			$execution->execute( $logp, "virsh -c qemu:///system 'attach-disk \"$vm_name\" $iso_disk $disk_b --mode readonly --type cdrom'");

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
			$execution->execute( $logp, "virsh -c qemu:///system 'attach-disk \"$vm_name\" $empty_iso_disk $disk_b --mode readonly --type cdrom'");
			sleep 1;

		   	# Cleaning
	        $execution->execute( $logp, "rm $iso_disk $empty_iso_disk");
	        $execution->execute( $logp, "rm -rf $sdisk_content");
	        $execution->execute( $logp, "rm -rf " . $dh->get_vm_tmp_dir($vm_name) . "/$seq");

        } elsif ($exec_mode eq "sdisk") {
            # Dismount shared disk
            # Note: under some systems this umount fails. We sleep for a while and, in case it fails, we wait and retry 3 times...
            Time::HiRes::sleep(0.2);
            my $retry=3;
            while ( $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content ) ) {
                $retry--; last if $retry == 0;  
                wlog (N, "umount $sdisk_content failed. Retrying...", "");          
                Time::HiRes::sleep(0.2);
            }
	        
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
            	
            	#print $vmsocket "hello\n";
            	#wait_sock_answer ($vmsocket);
            	
                print $vmsocket "exeCommand sdisk\n";  
            }  

            wlog (N, "exeCommand sent to VM $vm_name", $logp);            
            
            # Wait for confirmation from the VM     
            wait_sock_answer ($vmsocket);
            $vmsocket->close();	        
	        #readSocketResponse ($vmsocket);
            # Cleaning
            #$execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop,uid=$uid " . $sdisk_fname . " " . $sdisk_content );
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $sdisk_content );
            $execution->execute( $logp, "rm -rf $sdisk_content/filetree/*");
            $execution->execute( $logp, "rm -rf $sdisk_content/*.xml");
            $execution->execute( $logp, "rm -rf $sdisk_content/config/*");
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content );
	    }

	} elsif ( ($merged_type eq "libvirt-kvm-android") || ($merged_type eq "libvirt-kvm-wanos")) {
		$error = "Command execution not supported for libvirt-kvm-android VMs"
	}
	

    return $error;
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


1;

