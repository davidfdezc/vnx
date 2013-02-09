# vmAPI_uml.pm
#
# This file is a module part of VNX package.
#
# Authors: Fermin Galán, Jorge Somavilla, Jorge Rodriguez, David Fernández
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

# Some words about UML boot process!
#
# The following is a comment to the -t mode.
#
# An auxiliary filesystem is used to configure the uml virtual machine during
# its boot process.  The auxiliary  filesytem is of type iso9660 and is mounted
# on /mnt/vnuml.  The root filesystem's /etc/fstab should contain an entry for this
# auxiliary filesystem:
# /dev/ubdb /mnt/vnuml iso9660 defaults 0 0
#
# In addition, the master filesystem should have a SXXumlboot symlink that
# points to /mnt/vnuml/umlboot, the actual boot script, built by the parser in
# certain cases.
#
# There are three boot modes, depending of the <filesystem> type option.
#
# a) type="direct"
#    The filesystem in the <filesystem> tag is used as the root filesystem.
#
# b) type "cow"
#    A copy-on-write (COW) file based on the filesystem in the <filesystem> tag
#    is created, and this COW is used as the root filesystem.  The base filesystem
#    from the <filesystem> tag is not modified, but its presence is necessary due
#    to the nature of COW mode.
#
# c) type "hostfs"
#    The filesystem is actually a host directory, which content is used as 
#    root filesystem for the virtual machine.
#
# Execpt in the case of "cow" no more than one virtual machine must use the same
# filesystem (otherwise, filesytem corruption would happen).
#
# To summarize, the master filesystem must meet the following requirements for vnuml:
#
# - /mnt/vnuml directory (empty)
# - symlink at rc point (/etc/rc.d/rc3.d/S11umlboot is suggested) pointing to
#   /mnt/vnuml/umlboot
# - /etc/fstab with the following last line:
#   /dev/ubdb /mnt/vnuml iso9660 defaults 0 0
#
# (In fact, /mnt/vnuml can be changed for other empty mount point: it is transparent
# from the point of view of the parser operation)

package VNX::vmAPI_uml;

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

#needed for create_vm_bootfile
use File::Basename;
use File::Path;

#use XML::DOM;

use XML::LibXML;
#use XML::DOM::ValParser;


use IO::Socket;
use Data::Dumper;
use IO::Socket::UNIX qw( SOCK_STREAM );

use constant USE_UNIX_SOCKETS => 0;  # Use unix sockets (1) or TCP (0) to communicate with virtual machine 


# Name of UML whose boot process has started but not reached the init program
# (for emergency cleanup).  If the mconsole socket has successfully been initialized
# on the UML then '#' is appended.
my $curr_uml;
my $F_flag;       # passed from createVM to halt
my $M_flag;       # passed from createVM to halt




#
# Module vmAPI_uml initialization code
#
sub init {
	my $logp = "uml-init> ";	
}


###################################################################
#                                                                 #
#   defineVM                                                      #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################
sub defineVM {

	my $self   = shift;
	my $vm_name = shift;
	my $type   = shift;
	my $vm_doc    = shift;
	
    my $logp = "uml-defineVM-$vm_name> ";
	my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);
	
	$curr_uml = $vm_name;

	my $error = 0;

	if ( $type ne "uml" ) {
		$error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}

=BEGIN
	my $doc2       = $dh->get_doc;
	my @vm_ordered = $dh->get_vm_ordered;

	my $path;
	my $filesystem;

	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {

		my $vm = $vm_ordered[$i];

		# We get name attribute
		my $name = $vm->getAttribute("name");

		unless ( $name eq $vm_name ) {
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

		$filesystem = $dh->get_vm_fs_dir($name) . "/opt_fs";

		# Install global public ssh keys in the UML
		my $global_list = $doc2->getElementsByTagName("global");
		my $key_list = $global_list->item(0)->getElementsByTagName("ssh_key");

		# If tag present, add the key
		for ( my $j = 0 ; $j < $key_list->getLength ; $j++ ) {
			my $keyfile =
			  &do_path_expansion( &text_tag( $key_list->item($j) ) );
			$execution->execute($logp,  $bd->get_binaries_path_ref->{"cat"}
				  . " $keyfile >> $path"
				  . "keyring_root" );
		}

		# Next install vm-specific keys and add users and groups
		my @user_list = $dh->merge_user($vm);
		foreach my $user (@user_list) {
			my $username      = $user->getAttribute("username");
			my $initial_group = $user->getAttribute("group");
			$execution->execute($logp,  $bd->get_binaries_path_ref->{"touch"} 
				  . " $path"
				  . "group_$username" );
			my $group_list = $user->getElementsByTagName("group");
			for ( my $k = 0 ; $k < $group_list->getLength ; $k++ ) {
				my $group = &text_tag( $group_list->item($k) );
				if ( $group eq $initial_group ) {
					$group = "*$group";
				}
				$execution->execute($logp,  $bd->get_binaries_path_ref->{"echo"}
					  . " $group >> $path"
					  . "group_$username" );
			}
			my $key_list = $user->getElementsByTagName("ssh_key");
			for ( my $k = 0 ; $k < $key_list->getLength ; $k++ ) {
				my $keyfile =
				  &do_path_expansion( &text_tag( $key_list->item($k) ) );
				$execution->execute($logp,  $bd->get_binaries_path_ref->{"cat"}
					  . " $keyfile >> $path"
					  . "keyring_$username" );
			}
		}
	}
=END
=cut

	return $error;
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

    my $logp = "uml-undefineVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;

	if ( $type ne "uml" ) {
        $error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}

	return $error;
}


###################################################################
#                                                                 #
#   startVM                                                       #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################
sub startVM {

	my $self    = shift;
	my $vm_name  = shift;
	my $type    = shift;
	my $no_consoles = shift;
	
	my $logp = "uml-startVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);
	
	$curr_uml = $vm_name;

	my $error = 0;

	if ( $type ne "uml" ) {
        $error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}

	my $vm_doctxt = $dh->get_vm_doctxt($vm_name);  # Content of ${vm_name}_cconf.xml file
	                                               # created by make_vmAPI_doc
    my $parser = new XML::DOM::Parser;
    my $vm_doc = $parser->parse($vm_doctxt);

	my $global_doc = $dh->get_doc;
	my @vm_ordered = $dh->get_vm_ordered;



	my $path;       # Pathname to the temporal directory where the files included in the 
	                # opt_fs will be copied 
	my $filesystem; # Pathname of the opt_fs filesystem included as "ubdb=$filesystem" when
	                # the UML vm is started
	my $exec_mode;

	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {

		my $vm = $vm_ordered[$i];

		# We get name attribute
		my $name = $vm->getAttribute("name");

		unless ( $name eq $vm_name ) {
			next;
		}

=BEGIN Parece que sobra...
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
=END
=cut

    	$exec_mode = $dh->get_vm_exec_mode($vm);

        # Create the temporary directory to store opt_fs files
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

		$filesystem = $dh->get_vm_fs_dir($name) . "/opt_fs";

		# Install global public ssh keys in the UML
		#my $global_list = $global_doc->getElementsByTagName("global");
		#my $key_list = $global_list->item(0)->getElementsByTagName("ssh_key");

		# If tag present, add the key
		#for ( my $j = 0 ; $j < $key_list->getLength ; $j++ ) {
		foreach my $key ($global_doc->getElementsByTagName("global")->item(0)->getElementsByTagName("ssh_key")) {
			my $keyfile =
			  &do_path_expansion( &text_tag( $key ) );
			$execution->execute($logp,  $bd->get_binaries_path_ref->{"cat"}
				  . " $keyfile >> $path"
				  . "keyring_root" );
		}

		# Next install vm-specific keys and add users and groups
		my @user_list = $dh->merge_user($vm);
		foreach my $user (@user_list) {
			my $username      = $user->getAttribute("username");
			my $initial_group = $user->getAttribute("group");
			$execution->execute($logp,  $bd->get_binaries_path_ref->{"touch"} 
				  . " $path"
				  . "group_$username" );
			#my $group_list = $user->getElementsByTagName("group");
			#for ( my $k = 0 ; $k < $group_list->getLength ; $k++ ) {
			foreach my $group ($user->getElementsByTagName("group")) {	
				my $group_name = &text_tag( $group );
				if ( $group_name eq $initial_group ) {
					$group_name = "*$group";
				}
				$execution->execute($logp,  $bd->get_binaries_path_ref->{"echo"}
					  . " $group_name >> $path"
					  . "group_$username" );
			}
			#my $key_list = $user->getElementsByTagName("ssh_key");
			#for ( my $k = 0 ; $k < $key_list->getLength ; $k++ ) {
			foreach my $key ($user->getElementsByTagName("ssh_key")) {
				my $keyfile =
				  &do_path_expansion( &text_tag( $key ) );
				$execution->execute($logp,  $bd->get_binaries_path_ref->{"cat"}
					  . " $keyfile >> $path"
					  . "keyring_$username" );
			}
		}
		
		# To make configuration file
        &create_vm_bootfile( $path, $vm );

        # To make plugins configuration
        &create_vm_onboot_commands_file( $path, $vm, $vm_doc );
		
	}

	# Create the opt_fs iso filesystem
	$execution->execute($logp,  $bd->get_binaries_path_ref->{"mkisofs"}
		  . " -R -quiet -o $filesystem $path" );
	$execution->execute($logp, 
		$bd->get_binaries_path_ref->{"rm"} . " -rf $path" );




    my @params;
    my @build_params;

	my $globalNode = $vm_doc->getElementsByTagName("create_conf")->item(0);

	my $virtualmList  = $globalNode->getElementsByTagName("vm");
	my $virtualm      = $virtualmList->item(0);
	my $virtualm_name = $virtualm->getAttribute("name");

	my $kernelTagList = $virtualm->getElementsByTagName("kernel");
    my $kernel_item   = $kernelTagList->item(0);
    my $kernelTag     = $kernel_item->getFirstChild->getData;
	my $kernel;
    my $kernel_traces = "off";

	if ( $kernelTag ne 'default' ) {
		$kernel = $kernelTag;
        wlog (VVV, "kernel tag=" . $kernel_item->toString, $logp);
        #if ( $kernel_item->getAttribute("initrd") !~ /^$/ ) {
        unless ( empty($kernel_item->getAttribute("initrd")) ) {
			push( @params,
				"initrd=" . $kernel_item->getAttribute("initrd") );
			push( @build_params,
				"initrd=" . $kernel_item->getAttribute("initrd") );
		}
        #if ( $kernel_item->getAttribute("devfs") !~ /^$/ ) {
        unless ( empty($kernel_item->getAttribute("devfs")) ) {
			push( @params, "devfs=" . $kernel_item->getAttribute("devfs") );
			push( @build_params,
				"devfs=" . $kernel_item->getAttribute("devfs") );
		}
        #if ( $kernel_item->getAttribute("root") !~ /^$/ ) {
        unless ( empty($kernel_item->getAttribute("root")) ) {
			push( @params, "root=" . $kernel_item->getAttribute("root") );
			push( @build_params,
				"root=" . $kernel_item->getAttribute("root") );
		}
        #if ( $kernel_item->getAttribute("modules") !~ /^$/ ) {
        unless ( empty($kernel_item->getAttribute("modules")) ) {
			push( @build_params,
				"modules=" . $kernel_item->getAttribute("modules") );
		}
		if ( $kernel_item->getAttribute("trace") eq "on" ) {
			wlog (VVV, "UML kernel traces active for VM $virtualm_name", $logp);
			$kernel_traces = "on";
			push( @params,       "stderr=1" );
			push( @build_params, "stderr=1" );
		}
	}
	else {
		$kernel = $dh->get_default_kernel;
		if ( $dh->get_default_initrd !~ /^$/ ) {
			push( @params,       "initrd=" . $dh->get_default_initrd );
			push( @build_params, "initrd=" . $dh->get_default_initrd );
		}
		if ( $dh->get_default_devfs !~ /^$/ ) {
			push( @params,       "devfs=" . $dh->get_default_devfs );
			push( @build_params, "devfs=" . $dh->get_default_devfs );
		}
		if ( $dh->get_default_root !~ /^$/ ) {
			push( @params,       "root=" . $dh->get_default_root );
			push( @build_params, "root=" . $dh->get_default_root );
		}
		if ( $dh->get_default_modules !~ /^$/ ) {
			push( @build_params, "modules=" . $dh->get_default_modules );
		}
		if ( $dh->get_default_trace eq "on" ) {
            wlog (V, "UML kernel traces active for VM $virtualm_name", $logp);
            $kernel_traces = "on";
			push( @params,       "stderr=1" );
			push( @build_params, "stderr=1" );
		}
	}


	my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
	my $filesystemTag     = $filesystemTagList->item(0);
	my $filesystem_type   = $filesystemTag->getAttribute("type");
	$filesystem           = $filesystemTag->getFirstChild->getData;

	# If cow type, we have to check whether particular filesystem exists
	# to set the right boot filesystem.
	if ( $filesystem_type eq "cow" ) {
		if ( -f $dh->get_vm_fs_dir($vm_name) . "/root_cow_fs" ) {
			$filesystem = $dh->get_vm_fs_dir($vm_name) . "/root_cow_fs";
		}
		else {
			$filesystem =
			  $dh->get_vm_fs_dir($vm_name) . "/root_cow_fs,$filesystem";
		}
	}

	# set ubdb
	push( @params, "ubdb=" . $dh->get_vm_fs_dir($vm_name) . "/opt_fs" );

	# Boot command line
	if ( $filesystem_type ne "hostfs" ) {
		push( @params, "ubda=$filesystem" );
	}
	else {

	 # See http://user-mode-linux.sourceforge.net/UserModeLinux-HOWTO-9.html
		push( @params, "root=/dev/root" );
		push( @params, "rootflags=$filesystem" );
		push( @params, "rootfstype=hostfs" );
	}

	# hostfs configuration
	push( @params, "hostfs=" . $dh->get_vm_hostfs_dir($vm_name) );

	# VNUML-ize filesystem
	my $Z_flagTagList = $virtualm->getElementsByTagName("Z_flag");
	my $Z_flagTag     = $Z_flagTagList->item(0);
	my $Z_flag        = $Z_flagTag->getFirstChild->getData;

	if ( ( !-f $dh->get_vm_fs_dir($vm_name) . "/build-stamp" ) && ( !$Z_flag ) )
	{

        print "*** You should not see this message as VNUML-ize process has been eliminated\n"; 
		push( @build_params, "root=/dev/root" );
		push( @build_params, "rootflags=/" );
		push( @build_params, "rootfstype=hostfs" );
		push( @build_params, "ubdb=$filesystem" );

		#%%# push(@build_params, "init=@prefix@/@libdir@/vnumlize.sh");

        push( @build_params, "con=null" );

		$execution->execute($logp, "$kernel @build_params");
		$execution->execute($logp,  $bd->get_binaries_path_ref->{"touch"} . " "
			  . $dh->get_vm_fs_dir($vm_name)
			  . "/build-stamp" );
		if ( $> == 0 ) {
			$execution->execute($logp,  $bd->get_binaries_path_ref->{"chown"} . " "
				  . $execution->get_uid . " "
				  . $dh->get_vm_fs_dir($vm_name)
				  . "/root_cow_fs" );
			$execution->execute($logp,  $bd->get_binaries_path_ref->{"chown"} . " "
				  . $execution->get_uid . " "
				  . $dh->get_vm_fs_dir($vm_name)
				  . "/build-stamp" );
		}
	}

	# Memory assignment
	my $memTagList = $virtualm->getElementsByTagName("mem");
	my $memTag     = $memTagList->item(0);
	my $mem        = $memTag->getFirstChild->getData;
	# DFC: memory comes in Kbytes; convert it to Mbytes and add and "M"
	$mem = $mem / 1024;
	$mem = $mem . "M"; 
	push( @params, "mem=" . $mem );

	# Go through each interface
	#my $ifTagList = $virtualm->getElementsByTagName("if");
	#my $numif     = $ifTagList->getLength;

	#for ( my $j = 0 ; $j < $numif ; $j++ ) {
	foreach my $if ($virtualm->getElementsByTagName("if")) {

		#my $ifTag = $ifTagList->item($j);

		my $id  = $if->getAttribute("id");
		my $net = $if->getAttribute("net");
		my $mac = $if->getAttribute("mac");

		if ( &get_net_by_mode( $net, "uml_switch" ) != 0 ) {
			my $uml_switch_sock = $dh->get_networks_dir . "/$net.ctl";
			push( @params, "eth$id=daemon$mac,unix,$uml_switch_sock" );
		}
		else {
			push( @params, "eth$id=tuntap,$vm_name-e$id$mac" );
		}
	}

	# Background UML execution without consoles by default
	if ( $kernel_traces eq "on" ) {
        push( @params, "uml_dir=" . $dh->get_vm_dir($vm_name) . "/ umid=run con=null con0=xterm" );
	} else {
        push( @params, "uml_dir=" . $dh->get_vm_dir($vm_name) . "/ umid=run con=null" );

		# Process <console> tags
		my @console_list = $dh->merge_console($virtualm);
	
		my $xterm_used = 0;
		if (scalar(@console_list) == 0) {
			# No consoles defined; use default configuration 
	        push( @params, "con0=pts" );
	#        push( @params, "con0=xterm" );
		} else{
			foreach my $console (@console_list) {
				my $console_id    = $console->getAttribute("id");
				my $console_value = &text_tag($console);
				if ($console_value eq '') { $console_value = 'xterm' } # Default value
				if ( $console_value eq "xterm" ) {
		
	# xterms are treated like pts, to avoid unstabilities
	# (see https://lists.dit.upm.es/pipermail/vnuml-users/2007-July/000651.html for details)
	               $console_value = "pts";
	#                $console_value = "xterm";
				}
				if ( $console_value ne "" ) {
					push( @params, "con$console_id=$console_value" );
				}
			}
		}

    }

	my $notify_ctl = $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_socket';

	# Add mconsole option to command line
	push( @params, "mconsole=notify:$notify_ctl" );
	# my @group = getgrnam("[arroba]TUN_GROUP[arroba]");
	my @group = getgrnam("uml-net");

	# Boot command execution

	#get tag o_flag (el output)
	my @o_flagTagList = $virtualm->getElementsByTagName("o_flag");
	my $num           = @o_flagTagList;
	my $o_flagTag     = $o_flagTagList[0];
	my $o_flag        = "";
	eval { $o_flag = $o_flagTag->getFirstChild->getData; };

	#get tag e_flag
	my @e_flagTagList = $virtualm->getElementsByTagName("e_flag");
	my $e_flagTag     = $e_flagTagList[0];
	my $e_flag        = "";
	eval { $e_flag = $e_flagTag->getFirstChild->getData; };

	#get tag group2_flag (output)
	my @group2TagList = $virtualm->getElementsByTagName("group2");
	my $group2Tag     = $group2TagList[0];
	my $group2        = "";
	eval { $group2 = $group2Tag->getFirstChild->getData; };

	#get tag F_flag
	my @F_flagTagList = $virtualm->getElementsByTagName("F_flag");
	my $F_flagTag     = $F_flagTagList[0];
	my $F_flag        = "";
	eval { $F_flag = $F_flagTag->getFirstChild->getData; };

	# Where to output?
	my $output;

	#if ($args->get('o'))

	if ($o_flag) {

		# Deal with all special cases

		# Two special cases: /dev/null and /dev/stdout (we could also
		# generalice, but it is too DANGEROUS -for instance, if the
		# user tries '-o /dev/hda')
		if ( $o_flag eq '/dev/null' ) {
			$output = '/dev/null';
		}
		elsif ( $o_flag eq '/dev/stdout' ) {
			$output = '/dev/stdout';
		}
		elsif ( $o_flag =~ /^\/dev/ ) {
			wlog (V, 
"VNX warning: for safety /dev files (except /dev/null and /dev/stdout) are forbidden in -o. Using default (standard output)", $logp);
			$output = '/dev/stdout';
		}
		elsif ( $o_flag eq "-" ) {

			# Alias for standar output
			$output = '/dev/stdout';
		}
		else {

			# Check if the files is a writable regular file
			if ( ( -f $o_flag ) && ( -w $o_flag ) ) {
				$output = $o_flag;
			}
			else {

				# Otherwise, the value is treated as an prefix
				$output = $o_flag . ".$vm_name";
			}
		}
	}
	else {

		# Default value when -o is not being used
		if ($execution->get_exe_mode() eq $EXE_VERBOSE) {
            $output = '/dev/stdout';
		} else {
            $output = '/dev/null';
		}
	}
		
	# Create an initialize the socket to receive feedback from the VM
    my $sock = &UML_notify_init ($notify_ctl) if ($execution->get_exe_mode() ne $EXE_DEBUG);

=BEGIN
	# If using 'sdisk' mode to execute commands, create the serial line used by VNXACED daemon
    if ( $exec_mode eq 'sdisk' ) {
		# Get a free TCP port on the host
        my $h2vm_port = get_next_free_port (\$VNX::Globals::H2VM_PORT);
		push( @params, "con1=port:$h2vm_port" );
    }
=END
=cut    

	# Launch the UML virtual machine
	$execution->execute_bg( "$kernel @params",
		$output, &vm_tun_access($virtualm) ? $group2 : '' );

	if ( $execution->get_exe_mode() ne $EXE_DEBUG ) {

		my $boot_status = &UML_init_wait( $vm_name, $sock, $dh->get_boot_timeout);

		if ( !$boot_status ) {

			&UML_notify_cleanup( $sock, $notify_ctl );

			halt_uml( $vm_name, $F_flag );
			$execution->smartdie("Boot timeout exceeded for vm $vm_name!");
		}
		elsif ( $boot_status < 0 && !&UML_init_wait( $vm_name, $sock, 1, 1 ) ) {
			&kill_curr_uml;
		}
	}

	# Console pts and xterm processing
	if ( $execution->get_exe_mode() ne $EXE_DEBUG ) {
		
		# Go through <consoles> tag list to get default value for display attribute  
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
       		wlog (VVV, "console: id=$id, display=$display, value=$value", $logp);
			if ($display ne '') {
				if (  $id eq "0" ) {
					$cons0Display = $display 
				} elsif ( $id eq "1" ) {
					$cons1Display = $display
				} 
			}
		}

						
		my $consFile = $dh->get_vm_run_dir($vm_name) . "/console";
		my @console_list = $dh->merge_console($virtualm);
	
		if (scalar(@console_list) == 0) { 
			# Nothing defined for the consoles. 
			# Default configuration: con0=no,uml_pts,/dev/pts/9 
			my $pts = "";
			while ( $pts =~ /^$/ )
			{ # I'm sure that this loop could be smarter, but it works :)
				wlog (V, "Trying to get console 0 pts...\n", $logp)
				  if ( $execution->get_exe_mode() eq $EXE_VERBOSE );
				sleep 1;    # Needed to avoid  syncronization problems
				# Execute uml_mconsole using "system"" to capture output
				my $command = $bd->get_binaries_path_ref->{"uml_mconsole"} . " " 
				           . $dh->get_vm_run_dir($vm_name) . "/mconsole config con0 2> /dev/null";
				my $mconsole_output = `$command`;
				wlog (V, "mconsole config con0 returns $mconsole_output", $logp);
                wlog (VVV, "UML kernel traces=$kernel_traces (1)", $logp);
				if ( $mconsole_output =~ /^OK pts:(.*)$/ ) {
					$pts = $1;
					wlog (V, "...pts is $pts\n", $logp)
					  if ( $execution->get_exe_mode() eq $EXE_VERBOSE );
					$execution->execute($logp,  $bd->get_binaries_path_ref->{"echo"}
						  .	 " $pts > " . $dh->get_vm_run_dir($vm_name)	. "/pts" );
					$execution->execute($logp,  $bd->get_binaries_path_ref->{"echo"}
						  	. " con0=no,uml_pts,$pts >> " . $consFile );
				} elsif ( $kernel_traces eq "on" ) {
                    wlog (VVV, "UML kernel traces active for VM $virtualm_name (1)", $logp);
					$pts = "xterm (kernel_traces=on)";
				}
			}
			
		} else {
		
			my $get_screen_pts;
			foreach my $console (@console_list) {
				my $console_id    = $console->getAttribute("id");
				my $console_value = &text_tag($console);
				if ($console_value eq '') { $console_value = 'xterm' } # Default value
				my $display = $console->getAttribute("display");
				#wlog (VVV, "**** console: id=$console_id, display=$display, value=$console_value");
				if ( $display eq '' ) { # set default value
					if ( $console_id eq "0" )    { $display = $cons0Display } 
					elsif ( $console_id eq "1" ) { $display = $cons1Display } 					
				}
				if ( $console_value eq "pts" ) {
					my $pts = "";
					while ( $pts =~ /^$/ )
					{ # I'm sure that this loop could be smarter, but it works :)
                        wlog (V, "Trying to get console 0 pts...\n", $logp)
						  if ( $execution->get_exe_mode() eq $EXE_VERBOSE );
						sleep 1;    # Needed to avoid  syncronization problems
						my $command =
						    $bd->get_binaries_path_ref->{"uml_mconsole"} . " "
						  . $dh->get_vm_run_dir($vm_name)
						  . "/mconsole config con$console_id 2> /dev/null";
						my $mconsole_output = `$command`;
                        wlog (V, "mconsole config con0 returns $mconsole_output", $logp);
                        wlog (VVV, "UML kernel traces=$kernel_traces (2)", $logp);
						if ( $mconsole_output =~ /^OK pts:(.*)$/ ) {
							$pts = $1;
							wlog (V, "...pts is $pts", $logp)
							  if ( $execution->get_exe_mode() eq $EXE_VERBOSE );
							$execution->execute($logp, 
								    $bd->get_binaries_path_ref->{"echo"}
								  . " $pts > "
								  . $dh->get_vm_run_dir($vm_name)
								  . "/pts" );
							$execution->execute($logp, 
								    $bd->get_binaries_path_ref->{"echo"}
								  . " con$console_id=$display,uml_pts,$pts >> "
								  . $consFile );
		                } elsif ( $kernel_traces eq "on" ) {
                            wlog (VVV, "UML kernel traces active for VM $virtualm_name (2)", $logp);
		                    $pts = "xterm (kernel_traces=on)";
		                }
					}
					if ($e_flag) {

						# Optionally (if -e is being used) put the value in a
						# screen.conf file
						# FIXME: this would be obsolete in the future with the
						# 'vn console' tool
						print SCREEN_CONF "screen -t $vm_name $pts\n";
					}
				}

				# xterm processing is quite similar to pts since 1.8.3, but
				# the difference is that the descriptor will be internally
				# used by VNUML itself, instead of recording to a file
				elsif ( $console_value eq "xterm" ) {
					my $xterm_pts = "";
					while ( $xterm_pts =~ /^$/ )
					{ # I'm sure that this loop could be smarter, but it works :)
                        wlog (V, "Trying to get console $console_id pts...\n", $logp)
						  if ( $execution->get_exe_mode() eq $EXE_VERBOSE );
						sleep 1;    # Needed to avoid  syncronization problems
						my $command =
						    $bd->get_binaries_path_ref->{"uml_mconsole"} . " "
						  . $dh->get_vm_run_dir($vm_name)
						  . "/mconsole config con$console_id 2> /dev/null";
						my $mconsole_output = `$command`;
                        wlog (V, "mconsole config con0 returns $mconsole_output", $logp);
                        wlog (VVV, "UML kernel traces=$kernel_traces (3)", $logp);
						if ( $mconsole_output =~ /^OK pts:(.*)$/ ) {
							$xterm_pts = $1;
							wlog (V, "...xterm pts is $xterm_pts", $logp)
							  if ( $execution->get_exe_mode() eq $EXE_VERBOSE );
							$execution->execute($logp, 
								    $bd->get_binaries_path_ref->{"echo"}
								  . " $xterm_pts > "
								  . $dh->get_vm_run_dir($vm_name)
								  . "/pts" );
							# Write console spec to vms/$name/run/console file
							$execution->execute($logp, 
								    $bd->get_binaries_path_ref->{"echo"}
								  . " con$console_id=$display,uml_pts,$xterm_pts >> "
								  . $consFile );
	
                        } elsif ( $kernel_traces eq "on" ) {
                            wlog (VVV, "UML kernel traces active for VM $virtualm_name (3)", $logp);
                            $xterm_pts = "xterm (kernel_traces=on)";
                        }
					}
				}
			}
			
		}
		# Then, we just read the console file and start the active consoles,
		# unless options -n|--no_console were specified by the user
		unless ($no_consoles eq 1){
		   VNX::vmAPICommon->start_consoles_from_console_file ($vm_name);
		}			
	}

	# done in vnx core
	# &change_vm_status( $dh, $vm_name, "running" );

	# Close screen configuration file
	if ( ($e_flag) && ( $execution->get_exe_mode() ne $EXE_DEBUG ) ) {
		close SCREEN_CONF;
	}

    return 0;
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

    my $logp = "uml-destroyVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;
	
	if ( $type ne "uml" ) {
        $error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}

    &halt_uml( $vm_name, 1 );

=BEGIN
	my @pids;


	# 1. Kill all Linux processes, gracefully
	@pids = &get_kernel_pids($vm_name);
	wlog (VVV, "pids=" . Dumper(@pids));
	if ( @pids != 0 ) {
		my $pids_string = join( " ", @pids );
		$execution->execute($logp,  $bd->get_binaries_path_ref->{"kill"}
			  . " -SIGTERM $pids_string" );
		print "Waiting UMLs to term gracefully...\n"
		  unless ( $execution->get_exe_mode() eq $EXE_NORMAL );
		sleep( $dh->get_delay )
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
	}

    # 2. Kill all remaining Linux processes, by brute force
    @pids = &get_kernel_pids($vm_name);
    wlog (VVV, "pids=" . Dumper(@pids));
    if ( @pids != 0 ) {
        my $pids_string = join( " ", @pids );
        $execution->execute($logp,  $bd->get_binaries_path_ref->{"kill"}
              . " -SIGKILL $pids_string" );
        print "Waiting remaining UMLs to term forcely...\n"
          unless ( $execution->get_exe_mode() eq $EXE_NORMAL );
        #sleep( $dh->get_delay )
        #  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
    }
=END
=cut

    my $pid;
    my $pids;
    
    # Kill all Linux processes, by brute force (why being polite if you can be rude? :-)
    # Get pid of VM parent process (seems that /pid file only stores the pid
    # of the parent process, we have to call 'ps --ppid ...' to get the 
    # whole list of processes associated to a VM)
    my $pid_file = $dh->get_vm_run_dir($vm_name) . "/pid";
    wlog (VVV, "pid_file=$pid_file", $logp);
    unless ( !-f $pid_file ) {
    	print "*******\n";
    	my $command = $bd->get_binaries_path_ref->{"cat"} . " $pid_file";
        chomp( $pid = `$command` );
        wlog (N, "main process pid=$pid", $logp);
        # Get pids of child processes
        $command = $bd->get_binaries_path_ref->{"ps"} . " --ppid $pid | grep -v PID | awk '{ print \$1 }'"; 
        chomp( $pids = `$command` );
        $pids=~s/\n/ /g;
        wlog (N, "child processes pids=$pids", $logp);
        $execution->execute($logp,  $bd->get_binaries_path_ref->{"kill"}
              . " -SIGKILL $pid $pids" );
        wlog (N, "UML processes killed...\n", $logp)
          unless ( $execution->get_exe_mode() eq $EXE_NORMAL );
    }

	# Remove vm fs directory (cow and iso filesystems)
    sleep( 1 );
	$execution->execute($logp,  "rm " . $dh->get_vm_fs_dir($vm_name) . "/*" );
	return $error;

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
	$F_flag    = shift;

    my $logp = "uml-shutdownVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;

	if ( $type ne "uml" ) {
        $error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}
#pak();
	&halt_uml( $vm_name, $F_flag );

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
	
	my $logp = "uml-saveVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;

	if ( $type ne "uml" ) {
        $error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}

	$error = "saveVM not supported for UML virtual machines\n";
	return $error;

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

    my $logp = "uml-restoreVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;

	if ( $type ne "uml" ) {
        $error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}

	$error = "restoreVM not supported for UML virtual machines\n";
	return $error;

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

    my $logp = "uml-suspendVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;

	if ( $type ne "uml" ) {
        $error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}

	$error = "suspendVM not supported for UML virtual machines\n";
	return $error;

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

    my $logp = "uml-resumeVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;

	if ( $type ne "uml" ) {
        $error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}

	$error = "resumeVM not supported for UML virtual machines\n";
	return $error;

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

    my $logp = "uml-rebootVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error = 0;

	if ( $type ne "uml" ) {
        $error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}

	$error = "rebootVM not supported for UML virtual machines\n";
	return $error;

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

    my $logp = "uml-resetVM-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

	my $error;

	if ( $type ne "uml" ) {
        $error = "$sub_name called with type $type (should be uml)\n";
		return $error;
	}

	$error = "resetVM not supported for UML virtual machines\n";
	return $error;

}



##sub executeCMD {
#
#	my $self = shift;
#	my $seq  = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
#	%vm_ips    = shift;
#
#	#Commands sequence (start, stop or whatever).
#
#	# Previous checkings and warnings
#	my @vm_ordered = $dh->get_vm_ordered;
#	my %vm_hash    = $dh->get_vm_to_use(@plugins);
#
#	# First loop: look for uml_mconsole exec capabilities if needed. This
#	# loop can cause exit, if capabilities are not accomplished
#	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
#		my $vm = $vm_ordered[$i];
#
#		# We get name attribute
#		my $name = $vm->getAttribute("name");
#
#		# We have to process it?
#		unless ( $vm_hash{$name} ) {
#			next;
#		}
#		my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
#		if ( $merged_type eq "uml" ) {
#			if ( &get_vm_exec_mode($vm) eq "mconsole" ) {
#				unless ( &check_mconsole_exec_capabilities($vm) ) {
#					$execution->smartdie(
#"vm $name uses mconsole to exec and it is not a uml_mconsole exec capable virtual machine"
#					);
#				}
#			}
#		}
#		elsif ( $merged_type eq "libvirt-kvm-windows" ) {
#
#			#Nothing to do.
#		}
#	}
#
#	# Second loop: warning
#	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
#		my $vm = $vm_ordered[$i];
#
#		# We get name attribute
#		my $name = $vm->getAttribute("name");
#
#		# We have to process it?
#		unless ( $vm_hash{$name} ) {
#			next;
#		}
#		my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
#		if ( $merged_type eq "uml" ) {
#
#		   # Check if the virtual machine execute commans using "net" mode. This
#		   # involves additional checkings
#			if ( &get_vm_exec_mode($vm) eq "net" ) {
#
#				my $mng_if = &mng_if_value( $dh, $vm );
#				if ( $dh->get_vmmgmt_type eq 'none' ) {
#					print
#"VNX warning: vm $name uses network to exec and vm management is not enabled (via <vm_mgmt> element)\n";
#					print
#"VNX warning: connectivity is needed to vm $name throught the virtual networks\n";
#				}
#				elsif ( $mng_if eq "no" ) {
#
#	# Network management is being used, but the virtual machine is configured to
#	# not use management interface
#					print
#"VNX warning: vm $name uses network to exec but is not using management interface (<mng_if>no</mng_if>)\n";
#					print
#"VNX warning: connectivity is needed to vm $name throught the virtual networks\n";
#				}
#			}
#		}
#		elsif ( $merged_type eq "libvirt-kvm-windows" ) {
#
#			#Nothing to do.
#		}
#
#	}
#
#
#	# Each -x invocation uses an "unique" random generated identifier, that
#	# would avoid collision problems among several users
#	my $random_id = &generate_random_string(6);
#
#	# 1. To install configuration files subtree
#	&conf_files( $seq, %vm_ips );
#
#	# 2. To build commands files
#	&command_files( $random_id, $seq );
#
#	# 3. To load commands file in each UML
#	&install_command_files( $random_id, $seq, %vm_ips );
#
#	# 4. To execute commands file in each UML
#	&exec_command_files( $random_id, $seq, %vm_ips );
#
#	# 5. To execute commands file in host
#	&exec_command_host($seq);

#}



###################################################################
#
sub executeCMD {

	my $self = shift;
	my $merged_type = shift;
	my $seq  = shift;
	my $vm    = shift;
	my $vm_name = shift;
    my $plugin_ftree_list_ref = shift;
    my $plugin_exec_list_ref  = shift;
    my $ftree_list_ref        = shift;
    my $exec_list_ref         = shift;	

    my $logp = "uml-executeCMD-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$merged_type, seq=$seq ...)", $logp);

    my $error;

    if ( $merged_type ne "uml" ) {
        $error = "$sub_name called with type $merged_type (should be uml)\n";
        return $error;
    }

    my $uml_log_file = '/var/log/vnxaced.log';

    # Calculate the efective basedir
    my $basedir = $dh->get_default_basedir;
    my @basedir_list = $vm->getElementsByTagName("basedir");
    if (@basedir_list == 1) {
		$basedir = &text_tag($basedir_list[0]);
	}
	my $basename = basename $0;

    # Get the exec_mode for this vm
    my $mode = $dh->get_vm_exec_mode($vm);
    wlog (VV, "Using exec_mode=$mode", $logp);

    if ( ( $mode eq "mconsole" ) || ( $mode eq "net" ) ) {

	    #
	    # mconsole and net (SSH) command execution modes inherited from VNUML
	    #
	
	    #
	    # Process <filetree> tags
	    #
		my $random_id  = &generate_random_string(6);
		
		# For debuging purposes, we save a copy of the <filetree> and <exec> to ${vm_name}_command.xml file 
	    # First, we delete the previous content of the file
	    $execution->execute($logp,  "rm -f " . $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml" );
	
	    # Get the management ip address (for mode=net only)	
	    my %mngt_addr = &get_admin_address( 'file', $vm_name );
		
		my $dst_num = 1;
		
		# Process all the filetrees generated by plugins and with sequence $seq
		# prepared by vnx.pl before calling executeCMD
	    foreach my $filetree (@{$plugin_ftree_list_ref},@{$ftree_list_ref}) {
	
	        # Save a copy of the <filetree> to command.xml file 
	        $execution->execute($logp,  "echo \"" . $filetree->toString(1) . "\" >> " . $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml" );
			
=BEGIN
		            # To get host directory (subtree) to install in the UML
		            my $src;
		            my $filetree_value = &text_tag($filetree);
		            if ( $filetree_value =~ /^\// ) {
		                # Absolute pathname
		                $src = &do_path_expansion($filetree_value);
		            }
		            else {
		                # Relative pahtname
		                if ( $basedir eq "" ) {
		                    # Relative to xml_dir
		                    $src = &do_path_expansion(&chompslash( $dh->get_xml_dir ) . "/$filetree_value" );
		                }
		                else {
		                    # Relative to basedir
		                    $src = &do_path_expansion(&chompslash($basedir) . "/$filetree_value" );
		                }
		            }
		            $src = &chompslash($src);
=END
=cut
	
	        my $src =$dh->get_vm_tmp_dir($vm_name) . "/$seq/filetree/$dst_num";
		        
	        # To get installation point at the UML
	        my $root = $filetree->getAttribute("root");
	        my $user         = $filetree->getAttribute("user");
	        my $group        = $filetree->getAttribute("group");
	        my $perms        = $filetree->getAttribute("perms");
	
	        # To get executing user and execution mode
	        #my $user   = &get_user_in_seq( $vm, $seq );
	       
	        if ( $mode eq "net" ) {
	                	
	            # Copy (scp) the files to the vm
	            $execution->execute($logp,  $bd->get_binaries_path_ref->{"scp"} . " -q -r -oProtocol=" . $dh->get_ssh_version . 
	                " -o 'StrictHostKeyChecking no'" . " $src/* $user\@" . $mngt_addr{'vm'}->addr() . ":$root" );
	            # Delete the files in the host after copying
	            $execution->execute($logp,  $bd->get_binaries_path_ref->{"rm"} . " -rf $seq/filetree/$dst_num" );
	        }
	        elsif ( $mode eq "mconsole" ) {
	            # Copy to the hostfs mount point and issue a mv command in the virtual machine to the right place.
	            #
	            # It seems that permissions in host context are not the same that permissions in vm context
	            # (for example, the root in vm can not go into directories owned by root in host with 700 permissions)
	            # This cause some problems, because of some files of the tree could be lost during mv command.
	            # The workaorund consists in:
	            #
	            # 1. In host: save directory permissions (the three octal digit triplet) in a hash
	            # 2. In host: 777-ize all files
	            # 3. In vm: perform the cp operation (scripted)
	            # 4. In vm: restore permissions (using the hash in step 1)
			
	            my $mconsole = $dh->get_vm_run_dir($vm_name) . "/mconsole";
	            if ( -S $mconsole ) {
	
	                # Copy the files to a temporary directory under vm hostfs directory
	                #my $command =  $bd->get_binaries_path_ref->{"mktemp"} . " -d -p " . $dh->get_vm_hostfs_dir($vm_name) . " filetree.XXXXXX";
	                #chomp( my $filetree_host = `$command` );
	                #$filetree_host =~ /filetree\.(\w+)$/;
	                
	                
	                #$execution->execute($logp, $bd->get_binaries_path_ref->{"cp"} . " -r $src/* $filetree_host" );
	                #my $random_id   = $1;
	                #my $filetree_vm = "/mnt/hostfs/filetree.$random_id";
	
	                #my $filetree_host = $dh->get_vm_hostfs_dir($vm_name) . "/$seq/filetree/$dst_num";
	                my $filetree_host = $dh->get_vm_hostfs_dir($vm_name) . "/filetree/$dst_num";
	                $execution->execute($logp, "mkdir -p $filetree_host" );
	                $execution->execute($logp, $bd->get_binaries_path_ref->{"mv"} . " $src/* $filetree_host" );
	                my $filetree_vm = "/mnt/hostfs/filetree/$dst_num";
	                my $ftree_id   = "$seq.$dst_num";
			
	                # 1. Save directory permissions
	                my %file_perms = &save_dir_permissions($filetree_host);
			
	                # 2. 777-ize all
	                $execution->execute($logp, $bd->get_binaries_path_ref->{"chmod"} . " -R 777 $filetree_host" );
			
	                # 3a. Prepare the copying script. Note that cp can not be executed directly, because
	                # wee need to "mark" the end of copy and actively monitoring it before continue. Otherwise
	                # race condictions may occur. See https://lists.dit.upm.es/pipermail/vnuml-devel/2007-January/000459.html
	                # for some detail
	                # FIXME: the procedure is quite similar to the one in commands_file function. Maybe
	                # it could be generalized in a external function, to avoid duplication
	                open COMMAND_FILE,">" . $dh->get_vm_hostfs_dir($vm_name) . "/filetree_cp.$ftree_id" 
	                    or $execution->smartdie( "can not open " . $dh->get_vm_hostfs_dir($vm_name) . "/filetree_cp.$ftree_id: $!" )
	                    unless ($execution->get_exe_mode() eq $EXE_DEBUG );
	                
	                #$execution->set_verb_prompt("$vm_name> ");
			
	                my $shell      = $dh->get_default_shell;
	                my @shell_list = $vm->getElementsByTagName("shell");
	                if ( @shell_list == 1 ) {
	                    $shell = &text_tag( $shell_list[0] );
	                }
	                my $date_command = $bd->get_binaries_path_ref->{"date"} . " +%s";
	                chomp( my $now = `$date_command` );
	                $execution->execute($logp, "#!" . $shell, *COMMAND_FILE );
	                $execution->execute($logp, "# filetree.$ftree_id copying script",*COMMAND_FILE );
	                $execution->execute($logp, "# generated by $basename $version$branch at $now",*COMMAND_FILE);
	                $execution->execute($logp, "# <filetree> tag: seq=$seq,root=$root,user=$user,group=$group,perms=$perms", *COMMAND_FILE );
			        if ( $root =~ /\/$/ ) {
			            $execution->execute($logp,  "# Create the directory if it does not exist", *COMMAND_FILE );
			            $execution->execute($logp,  "if [ -d $root ]; then", *COMMAND_FILE );
	                    #$execution->execute($logp,  "    mkdir -vp $root >> $uml_log_file", *COMMAND_FILE );
	                    $execution->execute($logp,  "    mkdir -p $root >> $uml_log_file", *COMMAND_FILE );
			            $execution->execute($logp,  "fi", *COMMAND_FILE );
	                    #$execution->execute($logp,  "cp -Rv $filetree_vm/* $root >> $uml_log_file", *COMMAND_FILE );
	                    #if ( $user ne ''  ) { $execution->execute($logp,  "chown -vR $user $root/*  >> $uml_log_file",  *COMMAND_FILE ); }
	                    #if ( $group ne '' ) { $execution->execute($logp,  "chown -vR .$group $root/* >> $uml_log_file", *COMMAND_FILE ); }
	                    #if ( $perms ne '' ) { $execution->execute($logp,  "chmod -vR $perms $root/*  >> $uml_log_file", *COMMAND_FILE ); }
	                    $execution->execute($logp,  "cp -R $filetree_vm/* $root >> $uml_log_file", *COMMAND_FILE );
	                    if ( $user ne ''  ) { $execution->execute($logp,  "chown -R $user $root/*  >> $uml_log_file",  *COMMAND_FILE ); }
	                    if ( $group ne '' ) { $execution->execute($logp,  "chown -R .$group $root/* >> $uml_log_file", *COMMAND_FILE ); }
	                    if ( $perms ne '' ) { $execution->execute($logp,  "chmod -R $perms $root/*  >> $uml_log_file", *COMMAND_FILE ); }
			        } else {
			            my $root_dir = dirname($root);
			            $execution->execute($logp,  "# Create the directory if it does not exist", *COMMAND_FILE );
			            $execution->execute($logp,  "if [ -d $root_dir ]; then", *COMMAND_FILE );
	                    #$execution->execute($logp,  "    mkdir -vp $root_dir >> $uml_log_file", *COMMAND_FILE );
	                    $execution->execute($logp,  "    mkdir -p $root_dir >> $uml_log_file", *COMMAND_FILE );
			            $execution->execute($logp,  "fi", *COMMAND_FILE );
	                    #$execution->execute($logp,  "cp -Rv $filetree_vm/* $root", *COMMAND_FILE );
	                    #if ( $user ne ''  ) { $execution->execute($logp,  "chown -vR $user $root >> $uml_log_file", *COMMAND_FILE );   }
	                    #if ( $group ne '' ) { $execution->execute($logp,  "chown -vR .$group $root >> $uml_log_file", *COMMAND_FILE ); }
	                    #if ( $perms ne '' ) { $execution->execute($logp,  "chmod -vR $perms $root >> $uml_log_file", *COMMAND_FILE );  }
	                    $execution->execute($logp,  "cp -R $filetree_vm/* $root", *COMMAND_FILE );
	                    if ( $user ne ''  ) { $execution->execute($logp,  "chown -R $user $root >> $uml_log_file", *COMMAND_FILE );   }
	                    if ( $group ne '' ) { $execution->execute($logp,  "chown -R .$group $root >> $uml_log_file", *COMMAND_FILE ); }
	                    if ( $perms ne '' ) { $execution->execute($logp,  "chmod -R $perms $root >> $uml_log_file", *COMMAND_FILE );  }
			        }
	                
	                $execution->execute($logp, "echo 1 > /mnt/hostfs/filetree_cp.$ftree_id.end",*COMMAND_FILE);
			
	                close COMMAND_FILE
	                    unless ($execution->get_exe_mode() eq $EXE_DEBUG );
	                #$execution->pop_verb_prompt();
	                $execution->execute($logp, $bd->get_binaries_path_ref->{"chmod"} . " a+x " . $dh->get_vm_hostfs_dir($vm_name) . "/filetree_cp.$ftree_id" );
	
	#pak "Antes llamada mconsole: $mconsole/mnt/hostfs/filetree_cp.$ftree_id ";		
	                # 3b. Script execution
	                $execution->execute_mconsole( $logp,  $mconsole,"/mnt/hostfs/filetree_cp.$ftree_id" );
	#pak "Despues llamada mconsole";       
			
	                # 3c. Actively wait for the copying end
	                chomp( my $init = `$date_command` );
	                wlog (V, "Waiting filetree $src->$root filetree copy... ", $logp);
	                &filetree_wait( $dh->get_vm_hostfs_dir($vm_name) . "/filetree_cp.$ftree_id.end" );
	                chomp( my $end = `$date_command` );
	                my $time = $end - $init;
	                wlog (V, "(" . $time . "s)", $logp);
	#pak;
	                # 3d. Cleaning
	                $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_vm_hostfs_dir($vm_name) . "/filetree" );
	                $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_vm_hostfs_dir($vm_name) . "/filetree_cp.$ftree_id" );
	                $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -f "  . $dh->get_vm_hostfs_dir($vm_name) . "/filetree_cp.$ftree_id.end" );
			
	                # 4. Restore directory permissions; we need to perform some transformation
	                # in the keys (finelame) host-relative -> vm-relative
	                my %file_vm_perms;
	                foreach ( keys %file_perms ) {
	                    $_ =~ /^$filetree_host\/(.*)$/;
	                    my $new_key = "$root/$1";
	                    $file_vm_perms{$new_key} = $file_perms{$_};
	                }
	                &set_file_permissions( $mconsole,$dh->get_vm_hostfs_dir($vm_name),%file_vm_perms );
			
	                # Setting proper user
	                &set_file_user($mconsole, $dh->get_vm_hostfs_dir($vm_name),$user,keys %file_vm_perms	);
	            }
	            else {
	                wlog (V, "VNX warning: $mconsole socket does not exist. Copy of $src files can not be performed", $logp);
	            }
			}
	        $dst_num++;
		
		}
	   	
	   	
	    #
	    # Process <exec> tags
	    #
	    
		# We open file in host to create the script with the <exec>'s commands
		my $cmd_file_bname = "exec.$seq.$random_id";
		my $cmd_file = $dh->get_vm_hostfs_dir($vm_name) . "/$cmd_file_bname";
		
		wlog(VVV, "cmd_file=$cmd_file", $logp);
	    open COMMAND_FILE,"> $cmd_file"
				  or $execution->smartdie("cannot open $cmd_file: $!" )
				  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
	
		#$execution->set_verb_prompt("$vm_name> ");
	
	    # We create the script
		my $shell      = $dh->get_default_shell;
		my @shell_list = $vm->getElementsByTagName("shell");
		if ( @shell_list == 1 ) {
			$shell = &text_tag( $shell_list[0] );
		}
		my $command = $bd->get_binaries_path_ref->{"date"};
		chomp( my $now = `$command` );
		$execution->execute($logp, "#!" . $shell,              *COMMAND_FILE );
		$execution->execute($logp, "# commands sequence: $seq", *COMMAND_FILE );
		$execution->execute($logp, "# file generated by $basename $version$branch at $now",*COMMAND_FILE );
	
	    my $num_exec=1;
	    foreach my $command (@{$plugin_exec_list_ref},@{$exec_list_ref}) {
	
	        # Save a copy of the <exec> to command.xml file 
	        $execution->execute($logp, "echo \"" . $command->toString(1) . "\" >> " . $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml" );
	
	        my $type    = $command->getAttribute("type");
	        # Case 1. Verbatim type
	        if ( $type eq "verbatim" ) {
	            # Including command "as is"
	            $execution->execute($logp,  &text_tag_multiline($command) . "  # <exec> #$num_exec",*COMMAND_FILE );
	        }
	        # Case 2. File type
	        elsif ( $type eq "file" ) {
		
	            # We open the file and write commands line by line
	                my $include_file = &do_path_expansion( &text_tag($command) );
	                open INCLUDE_FILE, "$include_file"
	                    or $execution->smartdie("cannot open $include_file: $!");
	                while (<INCLUDE_FILE>) {
	                    chomp;
	                    $execution->execute($logp,  $_ . "  # <exec> #$num_exec", *COMMAND_FILE );
	                }
	                close INCLUDE_FILE;
	        }
				 	# Other case. Don't do anything (it would be and error in the XML!)
	        $num_exec++;
		}
		# Commands to add traces to $uml_log_file
	    $execution->execute($logp,  "CMDS=`cat /mnt/hostfs/$cmd_file_bname | grep '# <exec> #' | grep -v CMDS`", *COMMAND_FILE );
	    $execution->execute($logp,  "DATE=`date`", *COMMAND_FILE );
	    $execution->execute($logp,  "echo 'Commands executed on \$DATE:' >> $uml_log_file",*COMMAND_FILE );
	    $execution->execute($logp,  "echo \"\$CMDS\" >> $uml_log_file",*COMMAND_FILE );
	    $execution->execute($logp,  "touch /mnt/hostfs/$cmd_file_bname.done",*COMMAND_FILE );
	
=BEGIN Moved to vnx
		# Plugin operation
		# $execution->execute($logp, "# commands generated by plugins",*COMMAND_FILE);
		foreach my $plugin (@plugins) {
	
			# contemplar que ahora la string seq puede contener
			# varios seq separados por espacios
			my @commands = $plugin->execCommands( $vm_name, $seq );
	
			my $error = shift(@commands);
			if ( $error ne "" ) {
				$execution->smartdie("plugin $plugin execCommands($vm_name,$seq) error: $error");
			}
			foreach my $cmd (@commands) {
				$execution->execute($logp,  $cmd, *COMMAND_FILE );
			}
	
		}
=END
=cut	
	
		# We close file and mark it executable
		close COMMAND_FILE
		  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
	    my $res=`cat $cmd_file`;
	    wlog(VVV, "cmd_file:\n$res\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~", $logp);
		  
		#$execution->pop_verb_prompt();
		$execution->execute($logp,  $bd->get_binaries_path_ref->{"chmod"} . " a+x $cmd_file" );
	
	
	
		#
		# Copy the commands file script to virtual machine
		#
		my $user = &get_user_in_seq( $vm, $seq );
		#my $mode = &get_vm_exec_mode($vm);
		# my $type = $vm->getAttribute("type");
	
		if ( $mode eq "net" ) {
			# We install the file in /tmp of the virtual machine, using ssh
			$execution->execute($logp,  $bd->get_binaries_path_ref->{"ssh"} . " -x -" . $dh->get_ssh_version . 
			       " -o 'StrictHostKeyChecking no'" . " -l $user " . $mngt_addr{'vm'}->addr() . 
			       " rm -f /tmp/$cmd_file_bname &> /dev/null"	);
	
			$execution->execute($logp,  $bd->get_binaries_path_ref->{"scp"} . " -q -oProtocol=" . $dh->get_ssh_version  . 
			       " -o 'StrictHostKeyChecking no' $cmd_file" . 
			       " $user\@" . $mngt_addr{'vm'}->addr() . ":/tmp" );
	
		} elsif ( $mode eq "mconsole" ) {
	
	  		# We install the file in /mnt/hostfs of the virtual machine, using a simple cp
	  		# No needed; the file was directly created in the vm hostfs directory
			# $execution->execute($logp,  $bd->get_binaries_path_ref->{"cp"} . " $cmd_file " . $dh->get_vm_hostfs_dir($vm_name) );
	
	    }
	
		
		#
		# Execute the commands file script on the virtual machine
		#
		if ( $mode eq "net" ) {
			# Executing through SSH
			$execution->execute($logp, 
				    $bd->get_binaries_path_ref->{"ssh"} . " -x -"
					. $dh->get_ssh_version
					. " -o 'StrictHostKeyChecking no'"
					. " -l $user " . $mngt_addr{'vm'}->addr() . " /mnt/hostfs/$cmd_file_bname"
					);
		} elsif ( $mode eq "mconsole" ) {
	
			# Executing through mconsole
			my $mconsole = $dh->get_vm_run_dir($vm_name) . "/mconsole";
			if ( -S $mconsole ) {
	
			# Note the explicit declaration of standard input, ouput and error descriptors. It has been noticed
			# (http://www.mail-archive.com/user-mode-linux-user@lists.sourceforge.net/msg05369.html)
			# that not doing so can cause problems in some situations (i.e., executin /etc/init.d/apache2)
				$execution->execute_mconsole( $logp,  $mconsole,
					"su $user /mnt/hostfs/$cmd_file_bname </dev/null >/dev/null 2>/dev/null"
						);
			}
			else {
				wlog (V, "VNX warning: $mconsole socket does not exist. Commands in vnx.$vm_name.$seq.$random_id has not been executed", $logp);
			}
	
		}
	
		# We delete the file in the host after installation (this line could be
		# commented out in order to hold the scripts in the hosts for debugging
		# purposes)
	#pak;	
	    $execution->execute($logp,  $bd->get_binaries_path_ref->{"rm"} . " -f $cmd_file*");
    
    
	} elsif ( $mode eq "sdisk" ) {

	    #
    	# Shared disk command execution mode
    	# Note: code copied from vmAPI_libvirt->executeCMD
	    #
		wlog (V, "execution mode: $mode", $logp);
	
        my $sdisk_content;
        my $sdisk_fname;
        
        my $user   = &get_user_in_seq( $vm, $seq );

	    # Mount the shared disk to copy command.xml and filetree files
	    #$sdisk_fname  = $dh->get_vm_fs_dir($vm_name) . "/sdisk.img";
	    $sdisk_content = $dh->get_vm_hostfs_dir($vm_name);
        #$execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content );
        #$execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $sdisk_content );
	    # Delete the previous content of the shared disk (although it is done at 
	    # the end of this sub, we do it again here just in case...) 
	    $execution->execute( $logp, "rm -rf $sdisk_content/filetree/*");
		$execution->execute( $logp, "rm -rf $sdisk_content/*.xml");
        $execution->execute( $logp, "rm -rf $sdisk_content/config/*");
        # Create filetree and config dirs in  the shared disk
        $execution->execute( $logp, "mkdir -p $sdisk_content/filetree");
        $execution->execute( $logp, "mkdir -p $sdisk_content/config");
        
        # We create the command.xml file to be passed to the vm
        wlog (VVV, "opening file $sdisk_content/command.xml...", $logp);
		open COMMAND_FILE, "> $sdisk_content/command.xml"
			or $execution->smartdie( "can not open $sdisk_content/command.xml" )
	                    unless ($execution->get_exe_mode() eq $EXE_DEBUG );
=BEGIN
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
=END
=cut
		   
		#$execution->set_verb_prompt("$vm_name> ");
		
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


        #$execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content );
	        
		# Send the exeCommand order to the virtual machine through the shared file
		
		my $cmd;
		my $msg_file      = $dh->get_vm_hostfs_dir($vm_name) . '/cmd/command.msg';
		my $msg_file_lock = $dh->get_vm_hostfs_dir($vm_name) . '/cmd/command.lock';
		my $msg_file_res  = $dh->get_vm_hostfs_dir($vm_name) . '/cmd/command.res';
		system ("mkdir -p " . $dh->get_vm_hostfs_dir($vm_name) . '/cmd' );

		$| = 1;

        # Create lock file
        $cmd = "touch $msg_file_lock"; system ($cmd);
        # Save command to msf file
        $cmd = "echo 'exeCommand sdisk' > $msg_file"; system ($cmd);
        # Delete lock file
        $cmd = "rm -f $msg_file_lock"; system ($cmd);
        sleep 1;

        # Wait for command response
        my $tout = 10;
        while ( ! (-e $msg_file_res && ! -e $msg_file_lock )  && ($tout > 0) ) {
            sleep 1; $tout--; print ".";
        }
        if ( $tout == 0 ) {
            wlog (N, "\nERROR: tiemeout waiting for command response", $logp);
        } else {
            my $res = `cat $msg_file_res`;
            wlog (N, "\nResult: $res", $logp);
            system("rm -f $msg_file_res");
        }


=BEGIN
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

=END
=cut

        # Cleaning
        #$execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $sdisk_content );
        $execution->execute( $logp, "rm -rf $sdisk_content/filetree/*");
        $execution->execute( $logp, "rm -rf $sdisk_content/*.xml");
        $execution->execute( $logp, "rm -rf $sdisk_content/config/*");
        #$execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content );

	
	} else {        	
			wlog (V, "VNX warning: unknown execution mode ($mode)", $logp);
    }
    			
}



###################################################################
#
sub UML_init_wait {

    my $vm_name   = shift;
    my $sock      = shift;
	my $timeout   = shift;
	my $no_prompt = shift;
	my $data;

	my $MCONSOLE_SOCKET      = 0;
	my $MCONSOLE_PANIC       = 1;
	my $MCONSOLE_HANG        = 2;
	my $MCONSOLE_USER_NOTIFY = 3;

    my $logp = "uml_init_wait-$vm_name> ";

	#print "***** UML_init_wait: sock=$sock, timeout=$timeout, no_prompt=$no_prompt\n";
	while (1) {
		eval {
			# We program an alarm delivered to this process after $timeout seconds
			# See http://perldoc.perl.org/functions/alarm.html for details 
			local $SIG{ALRM} = sub { die "timeout"; };
			alarm $timeout;

			while (1) {

			# block on recv--alarm will signal timeout if no message is received
				if ( defined( recv( $sock, $data, 4096, 0 ) ) ) {
					my ( $magic, $version, $type, $len, $message ) =
					  unpack( "LiiiA*", $data );
					if ( $type == $MCONSOLE_SOCKET ) {
						$curr_uml =~ s/#*$/#/;
					}
					elsif ($type == $MCONSOLE_USER_NOTIFY
						&& $message =~ /init_start/ )
					{
						my ($uml) = $curr_uml =~ /(.+)#/;
						#wlog (N, "Virtual machine $uml sucessfully booted.\n")
						#   if ( $execution->get_exe_mode() eq $EXE_VERBOSE );
						alarm 0;
						return 0;
					}
				}
			}
		};
		if ($@) {
			wlog (N, "UML_init_wait error: $@");
			if ( defined($no_prompt) ) {
				return 0;
			}
			else {
				#print "**** curr_uml=$curr_uml\n" if ($exemode == $EXE_VERBOSE);
				my ($uml) = $curr_uml =~ /(.+)#/;
				#print "**** uml=$uml\n" if ($exemode == $EXE_VERBOSE);
				while (1) {
					wlog (N, "Boot timeout for virtual machine $uml reached.  Abort, Retry, or Continue? [A/r/c]: ");
					my $response = <STDIN>;
					return 0 if ( $response =~ /^$/ || $response =~ /^a/i );
					last if ( $response =~ /^r/i );
					return -1 if ( $response =~ /^c/i );
				}
			}
		}
		else {
			return 1;
		}
	}
}



###################################################################
#
sub get_net_by_mode {

	my $name_target = shift;
	my $mode_target = shift;

	my $doc = $dh->get_doc;

	# To get list of defined <net>
	#my $net_list = $doc->getElementsByTagName("net");

	# To process list
	#for ( my $i = 0 ; $i < $net_list->getLength ; $i++ ) {
	foreach my $net ($doc->getElementsByTagName("net")) {
		#my $net  = $net_list->item($i);
		my $name = $net->getAttribute("name");
		my $mode = $net->getAttribute("mode");

		if (   ( $name_target eq $name )
			&& ( ( $mode_target eq "*" ) || ( $mode_target eq $mode ) ) )
		{
			return $net;
		}

		# Special case (implicit virtual_bridge)
		if (   ( $name_target eq $name )
			&& ( $mode_target eq "virtual_bridge" )
			&& ( $mode eq "" ) )
		{
			return $net;
		}
	}

	return 0;
}



######################################################
# 3. To stop UML (politely)
sub halt_uml {

	my $vm_name     = shift;
	my $F_flag     = shift;                 # DFC

    my $logp = "halt_uml-$vm_name> ";
    wlog (VVV, "halt_uml called (F_flag=$F_flag)", $logp);	
	my @vm_ordered = $dh->get_vm_ordered;
	my %vm_hash    = $dh->get_vm_to_use;

	&kill_curr_uml;

	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {

		my $vm = $vm_ordered[$i];
		my $name = $vm->getAttribute("name");
		unless ( ( $vm_name eq "" ) or ( $name eq $vm_name ) ) {
			next;
		}

		&change_vm_status( $name, "REMOVE" );

		# Currently booting uml has already been killed
		if ( defined($curr_uml) && $name eq $curr_uml ) {
			next;
		}

        # Depending of how parser has been called (-F switch), the stop process is
        # more or less "aggressive" (and quick)
        # uml_mconsole is very verbose: redirect its error output to null device
		my $mconsole = $dh->get_vm_run_dir($name) . "/mconsole";
		if ( -S $mconsole ) {

			#  if ($args->get('F'))
			if ($F_flag) {

				# Halt trought mconsole socket,
				$execution->execute($logp, 
					$bd->get_binaries_path_ref->{"uml_mconsole"}
					  . " $mconsole halt 2>/dev/null" );

			}
			else {
				$execution->execute($logp, 
					$bd->get_binaries_path_ref->{"uml_mconsole"}
					  . " $mconsole cad 2>/dev/null" );

			}
		}
		else {
			wlog (V, "VNX warning: $mconsole socket does not exist", $logp);
		}
	}

}



####################################################################
## Remove the effective user xauth privileges on the current display
#sub xauth_remove {
#	if ( $> == 0 && $execution->get_uid != 0 && &xauth_needed ) {
#		$execution->execute($logp,  "su -s /bin/sh -c '"
#			  . $bd->get_binaries_path_ref->{"xauth"}
#			  . " remove $ENV{DISPLAY}' "
#			  . getpwuid( $execution->get_uid ) );
#	}
#}



###################################################################
#
sub kill_curr_uml {
	
    wlog (VVV, "kill_curr_uml called"); 
	# Force kill the currently booting uml process, if there is one
	if ( defined($curr_uml) ) {
		my $mconsole_init = $curr_uml =~ s/#$//;

		# Halt through mconsole socket,
		my $mconsole = $dh->get_vm_run_dir($curr_uml) . "/mconsole";
		if ( -S $mconsole && $mconsole_init ) {
			$execution->execute("kill_curr_uml> ", $bd->get_binaries_path_ref->{"uml_mconsole"}
				  . " $mconsole halt 2>/dev/null" );
		}
		elsif ( -f $dh->get_vm_run_dir($curr_uml) . "/pid" ) {
			
			my $cmd = $bd->get_binaries_path_ref->{"cat"} . " " . $dh->get_vm_run_dir($curr_uml) . "/pid";
			my $pid = `cmd`;
			wlog (VVV, "kill_curr_uml: pid=$pid");
			$execution->execute("kill_curr_uml> ", $bd->get_binaries_path_ref->{"kill"}
				  . " -SIGTERM `"
				  . $bd->get_binaries_path_ref->{"cat"} . " "
				  . $dh->get_vm_run_dir($curr_uml)
				  . "/pid`" );
		}
	}
}



#######################################################
## Check to see if any of the UMLs use xterm in console tags
#sub xauth_needed {
#
#	my $vm_list = $dh->get_doc->getElementsByTagName("vm");
#	for ( my $i = 0 ; $i < $vm_list->getLength ; $i++ ) {
#		my @console_list = $dh->merge_console( $vm_list->item($i) );
#		foreach my $console (@console_list) {
#			if ( &text_tag($console) eq 'xterm' ) {
#				return 1;
#			}
#		}
#	}
#
#	return 0;
#}

###################################################################
#
sub change_vm_status {

#	my $dh     = shift;
	my $vm     = shift;
	my $status = shift;

	my $status_file = $dh->get_vm_dir($vm) . "/status";

	if ( $status eq "REMOVE" ) {
		$execution->execute( "change_vm_status> ", 
			$bd->get_binaries_path_ref->{"rm"} . " -f $status_file" );
	}
	else {
		$execution->execute( "change_vm_status> ", 
			$bd->get_binaries_path_ref->{"echo"} . " $status > $status_file" );
	}
}



###################################################################
# vm_tun_access
#
# Returns 1 if a vm accesses the host via a tun device and 0 otherwise
#
sub vm_tun_access {
	my $vm = shift;

	# We get name attribute
	my $name = $vm->getAttribute("name");

	# To throw away and remove management device (id 0), if neeed
	#my $mng_if_value = &mng_if_value( $dh, $vm );
	my $mng_if_value = &mng_if_value( $vm );

	if ( $dh->get_vmmgmt_type eq 'private' && $mng_if_value ne "no" ) {
		return 1;
	}

	# To get UML's interfaces list
	#my $if_list = $vm->getElementsByTagName("if");

	# To process list
	#for ( my $j = 0 ; $j < $if_list->getLength ; $j++ ) {
	foreach my $if ($vm->getElementsByTagName("if")) {
		#my $if = $if_list->item($j);

		# We get attribute
		my $net = $if->getAttribute("net");

		if ( &get_net_by_mode( $net, "virtual_bridge" ) != 0 ) {
			return 1;
		}
	}
	return 0;
}



####################################################################
## UML_alive
##
## Returns 1 if there is a running UML in the process space
## of the operating system, 0 in the other case.
## Is based in a greped ps (doing the same with a pidof is not
## possible since version 1.2.0)
##
## This functions is similar to UMLs_ready function
#sub UML_alive {
#
#	my @pids = &get_kernel_pids;
#	if ( $#pids < 0 ) {
#		return 0;
#	}
#	my $pids_string = join( " ", @pids );
#	my $pipe = $bd->get_binaries_path_ref->{"ps"}
#	  . " --no-headers -p $pids_string 2> /dev/null|"
#	  ;    ## Avoiding strange warnings in the ps list
#	open my $ps_list, "$pipe";
#	if (<$ps_list>) {
#		close $ps_list;
#		return $pids_string;
#	}
#	close $ps_list;
#	return 0;
#}



###################################################################
# get_kernel_pids;
#
# Return a list with the list of PID of UML kernel processes
#
sub get_kernel_pids {
	my $vm_name = shift;
	my @pid_list;

    my $logp = "get_kernel_pids-$vm_name> ";
	foreach my $vm ( $dh->get_vm_ordered ) {

		# Get name attribute
		my $name = $vm->getAttribute("name");
#		print "*$name* vs *$vm_name*\n";
		unless ( ( $vm_name eq 0 ) || ( $name eq $vm_name ) ) {
			next;
		}
		my $pid_file = $dh->get_vm_run_dir($name) . "/pid";
		wlog (VVV, "vm $vm_name pid_file=$pid_file", $logp);
		next if ( !-f $pid_file );
		my $command = $bd->get_binaries_path_ref->{"cat"} . " $pid_file";
		chomp( my $pid = `$command` );
		wlog (VVV, "vm $vm_name pid$pid", $logp);
		push( @pid_list, $pid );
	}
	return @pid_list;

}



###################################################################
#
sub create_vm_bootfile {

	my $path   = shift;
	my $vm     = shift;

	my $basename = basename $0;

	my $vm_name = $vm->getAttribute("name");
    my $logp = "create_vm_bootfile-$vm_name> ";
    wlog (VVV, "vmAPI_uml->create_vm_bootfile called", $logp);

	# We open boot file, taking S$boot_prio and $runlevel
	open CONFILE, ">$path" . "umlboot"
	  or $execution->smartdie("can not open ${path}umlboot: $!")
	  #unless ( $execution->get_exe_mode() == $EXE_DEBUG );
	  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
	
	#$execution->set_verb_prompt("$vm_name> ");

	# We begin boot script
	my $shell      = $dh->get_default_shell;
	my @shell_list = $vm->getElementsByTagName("shell");
	if ( @shell_list == 1 ) {
		$shell = &text_tag( $shell_list[0] );
	}
	my $command = $bd->get_binaries_path_ref->{"date"};
	chomp( my $now = `$command` );
	$execution->execute($logp,  "#!" . $shell, *CONFILE );
	$execution->execute($logp,  "# UML boot file generated by $basename at $now",
		*CONFILE );
	$execution->execute($logp,  "UTILDIR=/mnt/vnuml", *CONFILE );

	# 1. To set hostname
	$execution->execute($logp,  "hostname $vm_name", *CONFILE );

	# Configure management interface internal side, if neeed
	my $mng_if_value = &mng_if_value( $vm );

	unless ( $mng_if_value eq "no" || $dh->get_vmmgmt_type eq 'none' ) {
		my %net = &get_admin_address( 'file', $vm_name );

		$execution->execute($logp, 
			"ifconfig eth0 "
			  . $net{'vm'}->addr()
			  . " netmask "
			  . $net{'vm'}->mask() . " up",
			*CONFILE
		);

		# If host_mapping is in use, append trailer to /etc/hosts config file
		if ( $dh->get_host_mapping ) {
			#@host_lines = ( @host_lines, $net->addr() . " $vm_name" );
			#$execution->execute($logp,  $net->addr() . " $vm_name\n", *HOSTLINES );
			open HOSTLINES, ">>" . $dh->get_sim_dir . "/hostlines"
				or $execution->smartdie("can not open $dh->get_sim_dir/hostlines\n")
				unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
			print HOSTLINES $net{'vm'}->addr() . " $vm_name\n";
			close HOSTLINES;
		}
	}

	# 3. Interface configuration

	# To get UML's interfaces list

	#my $if_list =
	#  $vm->getElementsByTagName("if");    ### usar en su lugar el xml recibido

	# To process list
	#for ( my $i = 0 ; $i < $if_list->getLength ; $i++ ) {
	foreach my $if ($vm->getElementsByTagName("if")) {
		#my $if = $if_list->item($i);

		# We get id and name attributes
		my $id       = $if->getAttribute("id");
		my $net_name = $if->getAttribute("net");

		my $if_name;

		# Special case: loopback interface
		if ( $net_name eq "lo" ) {
			$if_name = "lo:" . $id;
		}
		else {

			$if_name = "eth" . $id;

			# To found wether the interface is connected to a PPP link
			if ( ( my $net = &get_net_by_type( $net_name, "ppp" ) ) != 0 ) {

				# Get the bandwidth
				my $bw = &text_tag( $net->getElementsByTagName("bw")->item(0) );
				my $burst = ( $bw - ( $bw % 5 ) ) / 5;

				# VERY VERY weird, but I don't know a better way to calcule an
				# entire division in Perl! Please help me! :)
				$burst = 1000 if ( $burst < 1000 );

				# Thanks to Sergio Fernandez Munoz for the tc "magic words" :)
				$execution->execute($logp,  "ifconfig $if_name 0.0.0.0 pointopoint up",
					*CONFILE );
				$execution->execute($logp, 
"tc qdisc replace dev $if_name root tbf rate $bw latency 50ms burst $burst",
					*CONFILE
				);
			}
			else {

				# To set up interface (without address, at the begining)
				$execution->execute($logp, 
					"ifconfig $if_name 0.0.0.0 " . $dh->get_promisc . " up",
					*CONFILE );
			}
		}

# 4a. To process interface IPv4 addresses
# The first address have to be assigned without "add" to avoid creating subinterfaces
		if ( $dh->is_ipv4_enabled ) {
			#my $ipv4_list = $if->getElementsByTagName("ipv4");
			my $command   = "";
			#for ( my $j = 0 ; $j < $ipv4_list->getLength ; $j++ ) {
			foreach my $ipv4 ($if->getElementsByTagName("ipv4")) {
				my $ip = &text_tag( $ipv4 );
				my $ipv4_effective_mask = "255.255.255.0";  # Default mask value
				if ( &valid_ipv4_with_mask($ip) ) {

					# Implicit slashed mask in the address
					$ip =~ /.(\d+)$/;
					$ipv4_effective_mask = &slashed_to_dotted_mask($1);

					# The IP need to be chomped of the mask suffix
					$ip =~ /^(\d+).(\d+).(\d+).(\d+).*$/;
					$ip = "$1.$2.$3.$4";
				}
				else {

					# Check the value of the mask attribute
					my $ipv4_mask_attr =
					  $ipv4->getAttribute("mask");
					if ( $ipv4_mask_attr ne "" ) {

						# Slashed or dotted?
						if ( &valid_dotted_mask($ipv4_mask_attr) ) {
							$ipv4_effective_mask = $ipv4_mask_attr;
						}
						else {
							$ipv4_mask_attr =~ /.(\d+)$/;
							$ipv4_effective_mask = &slashed_to_dotted_mask($1);
						}
					}
				}

				$execution->execute($logp, "ifconfig $if_name $command $ip netmask $ipv4_effective_mask",*CONFILE);
				if ( $command =~ /^$/ ) {
					$command = "add";
				}
			}
		}

		# 4b. To process interface IPv6 addresses
		if ( $dh->is_ipv6_enabled ) {
			#my $ipv6_list = $if->getElementsByTagName("ipv6");
			#for ( my $j = 0 ; $j < $ipv6_list->getLength ; $j++ ) {
			foreach my $ipv6 ($if->getElementsByTagName("ipv6")) {
				my $ip = &text_tag( $ipv6 );
				if ( &valid_ipv6_with_mask($ip) ) {

					# Implicit slashed mask in the address
					$execution->execute($logp,  "ifconfig $if_name add $ip",
						*CONFILE );
				}
				else {

					# Check the value of the mask attribute
					my $ipv6_effective_mask = "/64";    # Default mask value
					my $ipv6_mask_attr =
					  $ipv6->getAttribute("mask");
					if ( $ipv6_mask_attr ne "" ) {

					   # Note that, in the case of IPv6, mask are always slashed
						$ipv6_effective_mask = $ipv6_mask_attr;
					}
					$execution->execute($logp, 
						"ifconfig $if_name add $ip$ipv6_effective_mask",
						*CONFILE );
				}
			}
		}

		#
	}

	# 5a. Route configuration
	my @route_list = $dh->merge_route($vm); ### usar en su lugar el xml recibido
	foreach my $route (@route_list) {
		my $route_dest = &text_tag($route);
		my $route_gw   = $route->getAttribute("gw");
		my $route_type = $route->getAttribute("type");

		# Routes for IPv4
		if ( $route_type eq "ipv4" ) {
			if ( $dh->is_ipv4_enabled ) {
				if ( $route_dest eq "default" ) {
					$execution->execute($logp, 
						"route -A inet add default gw $route_gw", *CONFILE );
				}
				elsif ( $route_dest =~ /\/32$/ ) {

# Special case: X.X.X.X/32 destinations are not actually nets, but host. The syntax of
# route command changes a bit in this case
					$execution->execute($logp, 
						"route -A inet add -host $route_dest  gw $route_gw",
						*CONFILE );
				}
				else {
					$execution->execute($logp, 
						"route -A inet add -net $route_dest gw $route_gw",
						*CONFILE );
				}

	#$execution->execute($logp, "route -A inet add $route_dest gw $route_gw",*CONFILE);
			}
		}

		# Routes for IPv6
		else {
			if ( $dh->is_ipv6_enabled ) {
				if ( $route_dest eq "default" ) {
					$execution->execute($logp, 
						"route -A inet6 add 2000::/3 gw $route_gw", *CONFILE );
				}
				else {
					$execution->execute($logp, 
						"route -A inet6 add $route_dest gw $route_gw",
						*CONFILE );
				}
			}
		}
	}

	# 6. Forwarding configuration
	my $f_type          = $dh->get_default_forwarding_type;
	my @forwarding_list = $vm->getElementsByTagName("forwarding");
	if ( @forwarding_list == 1 ) {
		$f_type = $forwarding_list[0]->getAttribute("type");
        #$f_type = "ip" if ( $f_type =~ /^$/ );
        $f_type = "ip" if (empty($f_type));
	}
	if ( $dh->is_ipv4_enabled ) {
		$execution->execute($logp,  "echo 1 > /proc/sys/net/ipv4/ip_forward",
			*CONFILE )
		  if ( $f_type eq "ip" or $f_type eq "ipv4" );
	}
	if ( $dh->is_ipv6_enabled ) {
		$execution->execute($logp,  "echo 1 > /proc/sys/net/ipv6/conf/all/forwarding",
			*CONFILE )
		  if ( $f_type eq "ip" or $f_type eq "ipv6" );
	}

	# 7. Hostname configuration in /etc/hosts
	my $ip_hostname = &get_ip_hostname($vm);
	if ($ip_hostname) {
		$execution->execute($logp,  "HOSTNAME=\$(hostname)", *CONFILE );
		$execution->execute($logp,  "grep \$HOSTNAME /etc/hosts > /dev/null 2>&1",
			*CONFILE );
		$execution->execute($logp,  "if [ \$? == 1 ]",       *CONFILE );
		$execution->execute($logp,  "then",                  *CONFILE );
		$execution->execute($logp,  "   echo >> /etc/hosts", *CONFILE );
		$execution->execute($logp,  "   echo \\# Hostname configuration >> /etc/hosts",
			*CONFILE );
		$execution->execute($logp, 
			"   echo \"$ip_hostname \$HOSTNAME\" >> /etc/hosts", *CONFILE );
		$execution->execute($logp,  "fi", *CONFILE );
	}

	# 8. modify inittab to halt when ctrl-alt-del is pressed
	# This task is now performed by the vnumlize.sh script

	# 9. mount host filesystem in /mnt/hostfs.
	# From: http://user-mode-linux.sourceforge.net/hostfs.html
	# FIXME: this could be also moved to vnumlize.sh, solving the problem
	# of how to get $hostfs_dir in that script
	my $hostfs_dir = $dh->get_vm_hostfs_dir($vm_name);
	$execution->execute($logp,  "mount none /mnt/hostfs -t hostfs -o $hostfs_dir",
		*CONFILE );
	$execution->execute($logp,  "if [ \$? != 0 ]",                     *CONFILE );
	$execution->execute($logp,  "then",                                *CONFILE );
	$execution->execute($logp,  "   mount none /mnt/hostfs -t hostfs", *CONFILE );
	$execution->execute($logp,  "fi",                                  *CONFILE );

	# 10. To call the plugin configuration script
	$execution->execute($logp,  "\$UTILDIR/onboot_commands.sh", *CONFILE );

	# 11. send message to /proc/mconsole to notify host that init has started
	$execution->execute($logp,  "echo init_start > /proc/mconsole", *CONFILE );

	# 12. create groups, users, and install appropriate public keys
	$execution->execute($logp,  "function add_groups() {", *CONFILE );
	$execution->execute($logp,  "   while read group; do", *CONFILE );
	$execution->execute($logp, 
		"      if ! grep \"^\$group:\" /etc/group > /dev/null 2>&1; then",
		*CONFILE );
	$execution->execute($logp,  "         groupadd \$group",           *CONFILE );
	$execution->execute($logp,  "      fi",                            *CONFILE );
	$execution->execute($logp,  "   done<\$groups_file",               *CONFILE );
	$execution->execute($logp,  "}",                                   *CONFILE );
	$execution->execute($logp,  "function add_keys() {",               *CONFILE );
	$execution->execute($logp,  "   eval homedir=~\$1",                *CONFILE );
	$execution->execute($logp,  "   if ! [ -d \$homedir/.ssh ]; then", *CONFILE );
	$execution->execute($logp,  "      su -pc \"mkdir -p \$homedir/.ssh\" \$1",
		*CONFILE );
	$execution->execute($logp,  "      chmod 700 \$homedir/.ssh", *CONFILE );
	$execution->execute($logp,  "   fi",                          *CONFILE );
	$execution->execute($logp,  "   if ! [ -f \$homedir/.ssh/authorized_keys ]; then",
		*CONFILE );
	$execution->execute($logp, 
		"      su -pc \"touch \$homedir/.ssh/authorized_keys\" \$1", *CONFILE );
	$execution->execute($logp,  "   fi",                 *CONFILE );
	$execution->execute($logp,  "   while read key; do", *CONFILE );
	$execution->execute($logp, 
"      if ! grep \"\$key\" \$homedir/.ssh/authorized_keys > /dev/null 2>&1; then",
		*CONFILE
	);
	$execution->execute($logp, 
		"         echo \$key >> \$homedir/.ssh/authorized_keys", *CONFILE );
	$execution->execute($logp,  "      fi",       *CONFILE );
	$execution->execute($logp,  "   done<\$file", *CONFILE );
	$execution->execute($logp,  "}",              *CONFILE );
	$execution->execute($logp,  "for file in `ls \$UTILDIR/group_* 2> /dev/null`; do",
		*CONFILE );
	$execution->execute($logp,  "   options=",                         *CONFILE );
	$execution->execute($logp,  "   myuser=\${file#\$UTILDIR/group_}", *CONFILE );
	$execution->execute($logp, 
		"   if [ \"\$myuser\" == \"root\" ]; then continue; fi", *CONFILE );
	$execution->execute($logp,  "   groups_file = `sed \"s/^\\*//\" \$file` ",
		*CONFILE );
	$execution->execute($logp,  "   add_groups", *CONFILE );
	$execution->execute($logp,  "   if effective_group=`grep \"^\\*\" \$file`; then",
		*CONFILE );
	$execution->execute($logp, 
		"      options=\"\$options -g \${effective_group#\\*}\"", *CONFILE );
	$execution->execute($logp,  "   fi", *CONFILE );
	$execution->execute($logp, 
		"   other_groups=`sed '/^*/d;H;\$!d;g;y/\\n/,/' \$file`", *CONFILE );
	$execution->execute($logp, 
		"   if grep \"^\$myuser:\" /etc/passwd > /dev/null 2>&1; then",
		*CONFILE );
	$execution->execute($logp, 
"      other_groups=\"-G `su -pc groups \$myuser | sed 's/[[:space:]]\\+/,/g'`\$other_groups\"",
		*CONFILE
	);
	$execution->execute($logp, 
		"      usermod \$options \$initial_groups\$other_groups \$myuser",
		*CONFILE );
	$execution->execute($logp,  "   else", *CONFILE );
	$execution->execute($logp, 
"      if [ \"\$other_groups\" != \"\" ]; then other_groups=\"-G \${other_groups#,}\"; fi",
		*CONFILE
	);
	$execution->execute($logp,  "      useradd -m \$options \$other_groups \$myuser",
		*CONFILE );
	$execution->execute($logp,  "   fi", *CONFILE );
	$execution->execute($logp,  "done",  *CONFILE );
	$execution->execute($logp, 
		"for file in `ls \$UTILDIR/keyring_* 2> /dev/null`; do", *CONFILE );
	$execution->execute($logp,  "   add_keys \${file#\$UTILDIR/keyring_} < \$file",
		*CONFILE );
	$execution->execute($logp,  "done", *CONFILE );

	# Close file and restore prompt
	#$execution->pop_verb_prompt();
	close CONFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

	# Boot file will be executable
	$execution->execute($logp, 
		$bd->get_binaries_path_ref->{"chmod"} . " a+x $path" . "umlboot" );

}



###################################################################
#
sub create_vm_onboot_commands_file {

	my $path   = shift;
    my $vm     = shift;
    my $vm_doc = shift;   

	my $basename = basename $0;
	
	my $uml_log_file = '/var/log/vnxaced.log';

	my $vm_name = $vm->getAttribute("name");
	my $logp = "create_vm_onboot_commands_file-$vm_name> ";

	open CONFILE, ">$path" . "onboot_commands.sh"
	  or $execution->smartdie("can not open ${path}onboot_commands.sh: $!")
	  unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
	
	#$execution->set_verb_prompt("$vm_name> ");

	# We begin plugin configuration script
	my $shell      = $dh->get_default_shell;
	my @shell_list = $vm->getElementsByTagName("shell");
	if ( @shell_list == 1 ) {
		$shell = &text_tag( $shell_list[0] );
	}
	my $command = $bd->get_binaries_path_ref->{"date"};
	chomp( my $now = `$command` );
	$execution->execute($logp,  "#!" . $shell, *CONFILE );
	$execution->execute($logp, 
		"# plugin configuration script generated by $basename at $now",
		*CONFILE );
	$execution->execute($logp,  "UTILDIR=/mnt/vnuml", *CONFILE );
	
	
	# Add the filetree and exec commands found in vm_doc
	# <filetree> tags
	my $ftree_num = 1;
	#my $filetree_taglist = $vm_doc->getElementsByTagName("filetree");
	#for (my $j = 0 ; $j < $filetree_taglist->getLength ; $j++){
	foreach my $filetree ($vm_doc->getElementsByTagName("filetree")) {
        #my $filetree_tag = $filetree_taglist->item($j);
        my $seq          = $filetree->getAttribute("seq");
        my $root         = $filetree->getAttribute("root");
        my $user         = $filetree->getAttribute("user");
        my $group        = $filetree->getAttribute("group");
        my $perms        = $filetree->getAttribute("perms");
	    my $filetree_vm = "/mnt/hostfs/filetree/$ftree_num";
	    
	    # Copy the files
        my $src =$dh->get_vm_tmp_dir($vm_name) . "/$seq/filetree/$ftree_num";
        my $filetree_host = $dh->get_vm_hostfs_dir($vm_name) . "/filetree/$ftree_num";
        $execution->execute($logp, "mkdir -p $filetree_host" );
        $execution->execute($logp, $bd->get_binaries_path_ref->{"mv"} . " $src/* $filetree_host" );
        
	    # Create the commands in the script
        $execution->execute($logp,  "# <filetree> tag: seq=$seq,root=$root,user=$user,group=$group,perms=$perms", *CONFILE );
        $execution->execute($logp,  "ls -R /mnt/hostfs >> $uml_log_file", *CONFILE );

        if ( $root =~ /\/$/ ) {
	        $execution->execute($logp,  "# Create the directory if it does not exist", *CONFILE );
	        $execution->execute($logp,  "if [ -d $root ]; then", *CONFILE );
	        $execution->execute($logp,  "    mkdir -vp $root >> $uml_log_file", *CONFILE );
	        $execution->execute($logp,  "fi", *CONFILE );
            #$execution->execute($logp,  "cp -Rv $filetree_vm/* $root >> $uml_log_file", *CONFILE );
            #if ( $user ne ''  ) { $execution->execute($logp,  "chown -vR $user $root/*  >> $uml_log_file",  *CONFILE ); }
            #if ( $group ne '' ) { $execution->execute($logp,  "chown -vR .$group $root/* >> $uml_log_file", *CONFILE ); }
            #if ( $perms ne '' ) { $execution->execute($logp,  "chmod -vR $perms $root/*  >> $uml_log_file", *CONFILE ); }
            $execution->execute($logp,  "cp -R $filetree_vm/* $root >> $uml_log_file", *CONFILE );
            if ( $user ne ''  ) { $execution->execute($logp,  "chown -R $user $root/*  >> $uml_log_file",  *CONFILE ); }
            if ( $group ne '' ) { $execution->execute($logp,  "chown -R .$group $root/* >> $uml_log_file", *CONFILE ); }
            if ( $perms ne '' ) { $execution->execute($logp,  "chmod -R $perms $root/*  >> $uml_log_file", *CONFILE ); }
        } else {
            my $root_dir = dirname($root);
            $execution->execute($logp,  "# Create the directory if it does not exist", *CONFILE );
            $execution->execute($logp,  "if [ -d $root_dir ]; then", *CONFILE );
            #$execution->execute($logp,  "    mkdir -vp $root_dir >> $uml_log_file", *CONFILE );
            $execution->execute($logp,  "    mkdir -p $root_dir >> $uml_log_file", *CONFILE );
            $execution->execute($logp,  "fi", *CONFILE );
            #$execution->execute($logp,  "cp -Rv $filetree_vm/* $root", *CONFILE );
            #if ( $user ne ''  ) { $execution->execute($logp,  "chown -vR $user $root >> $uml_log_file", *CONFILE );   }
            #if ( $group ne '' ) { $execution->execute($logp,  "chown -vR .$group $root >> $uml_log_file", *CONFILE ); }
            #if ( $perms ne '' ) { $execution->execute($logp,  "chmod -vR $perms $root >> $uml_log_file", *CONFILE );  }
            $execution->execute($logp,  "cp -R $filetree_vm/* $root", *CONFILE );
            if ( $user ne ''  ) { $execution->execute($logp,  "chown -R $user $root >> $uml_log_file", *CONFILE );   }
            if ( $group ne '' ) { $execution->execute($logp,  "chown -R .$group $root >> $uml_log_file", *CONFILE ); }
            if ( $perms ne '' ) { $execution->execute($logp,  "chmod -R $perms $root >> $uml_log_file", *CONFILE );  }
        }
        
        $ftree_num++;
	}
	$execution->execute($logp, "echo 1 > $path" . "onboot_commands.end",*CONFILE);
	
    # <exec> tags
    #my $execTagList = $vm_doc->getElementsByTagName("exec");
    #for (my $j = 0 ; $j < $execTagList->getLength; $j++){
    foreach my $exec ($vm_doc->getElementsByTagName("exec")) {
        #my $execTag = $execTagList->item($j);
        my $seq     = $exec->getAttribute("seq");
        my $type    = $exec->getAttribute("type");
        my $ostype  = $exec->getAttribute("ostype");
        my $command = $exec->getFirstChild->getData;
        $execution->execute($logp,  "# <exec> tag: seq=$seq,type=$type,ostype=$ostype", *CONFILE );
        $execution->execute($logp,  "$command", *CONFILE );

    }
	
=BEGIN
	my $at_least_one_file = "0";
	foreach my $plugin (@plugins) {
		my %files = $plugin->getBootFiles($vm_name);

		if ( defined( $files{"ERROR"} ) && $files{"ERROR"} ne "" ) {
			$execution->smartdie(
				"plugin $plugin getBootFiles($vm_name) error: "
				  . $files{"ERROR"} );
		}

		foreach my $key ( keys %files ) {

			# Create the directory to hold de file (idempotent operation)
			my $dir = dirname($key);
			mkpath( "$path/plugins_root/$dir", { verbose => 0 } );
			$execution->set_verb_prompt($verb_prompt_bk);
			$execution->execute($logp,  $bd->get_binaries_path_ref->{"cp"}
				  . " $files{$key} $path/plugins_root/$key" );
			$execution->set_verb_prompt("$vm_name(plugins)> ");

			# Remove the file in the host (this is part of the plugin API)
			$execution->execute($logp, 
				$bd->get_binaries_path_ref->{"rm"} . " $files{$key}" );

			$at_least_one_file = 1;

		}

		my @commands = $plugin->getBootCommands($vm_name);

		my $error = shift(@commands);
		if ( $error ne "" ) {
			$execution->smartdie(
				"plugin $plugin getBootCommands($vm_name) error: $error");
		}

		foreach my $cmd (@commands) {
			$execution->execute($logp,  $cmd, *CONFILE );
		}
	}

	if ($at_least_one_file) {

		# The last commands in onboot_commands.sh is to push plugin_root/ to vm /
		$execution->execute($logp, 
			"# Generated by $basename to push files generated by plugins",
			*CONFILE );
		$execution->execute($logp,  "cp -r \$UTILDIR/plugins_root/* /", *CONFILE );
	}
=END
=cut	

	# Close file and restore prompting method
    #$execution->pop_verb_prompt();
	close CONFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

	# Configuration file must be executable
	$execution->execute($logp, $bd->get_binaries_path_ref->{"chmod"}
		  . " a+x $path"
		  . "onboot_commands.sh" );

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
	#my $exec_list = $vm->getElementsByTagName("exec");
	#for ( my $i = 0 ; $i < $exec_list->getLength ; $i++ ) {
	foreach my $exec ($vm->getElementsByTagName("exec")) {
		if ( $exec->getAttribute("seq") eq $seq ) {
			if ( $exec->getAttribute("user") ne "" ) {
				$username = $exec->getAttribute("user");
				last;
			}
		}
	}

=BEGIN modified to only apply to exec. each filetree can have its own user
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
=END
=cut

	# If no mode was found in <exec> or <filetree>, use default
	if ( $username eq "" ) {
		$username = "root";
	}

	return $username;

}



###################################################################
#
sub check_mconsole_exec_capabilities {
	my $vm = shift;

	my $name = $vm->getAttribute("name");

	# Checking the kernel
	my $kernel_check = 0;
	my $kernel       = $dh->get_default_kernel;
	my @kernel_list  = $vm->getElementsByTagName("kernel");
	if ( @kernel_list > 0 ) {
		$kernel = &text_tag( $kernel_list[0] );

	}

	my $grep   = $bd->get_binaries_path_ref->{"grep"};
	my $result = `$kernel --showconfig | $grep MCONSOLE_EXEC`;

	if ( $result =~ /^CONFIG_MCONSOLE_EXEC=y$/ ) {
		$kernel_check = 1;

	}
	$kernel_check = 1;

	# Checking the uml_mconsole command
	my $mconsole_check = 0;
	my $mconsole       = $dh->get_vm_run_dir($name) . "/mconsole";

	if ( -S $mconsole ) {

		my $grep         = $bd->get_binaries_path_ref->{"grep"};
		my $uml_mconsole = $bd->get_binaries_path_ref->{"uml_mconsole"};
		my $result = `$uml_mconsole $mconsole help 2> /dev/null | $grep exec`;
		if ( $result ne "" ) {

			$mconsole_check = 1;
		}
	}
	else {
		wlog (V, "VNX warning: $mconsole socket does not exist", "check_mconsole_exec_capabilities> ");

	}

	return ( $kernel_check && $mconsole_check );
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



######################################################
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
# set_file_permissions
#
# Set file permissions in the virtual machine, using mconsole
#
# Arguments:
# - the mconsole socket
# - the hostfs directory (in hostfs enviroment)
# - a hash of permissions. The key of the hash is the file name
#
sub set_file_permissions {

	my $mconsole  = shift;
	my $hostfs    = shift;
	my %file_hash = @_;

    my $logp = "set_file_permissions> ";

	# We produce a file in hostfs to speed up execution (executing command
	# by command is slow)
	my $command =
	    $bd->get_binaries_path_ref->{"mktemp"} . " -p " 
	  . $hostfs
	  . " set_file_permissions.XXXXXX";
	chomp( my $cmd_file_host = `$command` );
	$cmd_file_host =~ /(set_file_permissions\.\w+)$/;
	my $cmd_file_vm = "/mnt/hostfs/$1";

	open FILE, ">$cmd_file_host";
	foreach ( keys %file_hash ) {

		#print "DEBUG: set_file_permissions: $_: " .  $file_hash{$_} ."\n";
		my $perm = $file_hash{$_};
		print FILE "chmod $perm $_\n";
	}
	close FILE;
	$execution->execute( "set_file_permissions> ", 
		$bd->get_binaries_path_ref->{"chmod"} . " 777 $cmd_file_host" );
	$execution->execute_mconsole( $logp,  $mconsole, "$cmd_file_vm" );

	# Clean up
	$execution->execute( "set_file_permissions> ", 
		$bd->get_binaries_path_ref->{"rm"} . " -f $cmd_file_host" );

}



###################################################################
# set_file_user
#
# Set user ownership of files in virtual machine, using mconsole
#
# Arguments:
# - the mconsole socket
# - the hostfs directory (in host enviroment)
# - the user to set
# - a list of files
#
sub set_file_user {

	my $mconsole = shift;
	my $hostfs   = shift;
	my $user     = shift;
	my @files    = @_;

    my $logp = "set_file_permissions> ";

	# We produce a file in hostfs to speed up execution (executing command
	# by command is slow)
	my $command =
	    $bd->get_binaries_path_ref->{"mktemp"} . " -p " 
	  . $hostfs
	  . " set_file_user.XXXXXX";
	chomp( my $cmd_file_host = `$command` );
	$cmd_file_host =~ /(set_file_user\.\w+)$/;
	my $cmd_file_vm = "/mnt/hostfs/$1";

	open FILE, ">$cmd_file_host";
	foreach (@files) {

		#print "DEBUG set_file_user: $_: "\n";
		print FILE "chown $user $_\n";
	}
	close FILE;
	$execution->execute( "set_file_user> ", 
		$bd->get_binaries_path_ref->{"chmod"} . " 777 $cmd_file_host" );
	$execution->execute_mconsole( $logp,  $mconsole, "$cmd_file_vm" );

	# Clean up
	$execution->execute( "set_file_user> ", 
		$bd->get_binaries_path_ref->{"rm"} . " -f $cmd_file_host" );

}


######################################################
# Initialize socket for listening
sub UML_notify_init {

	my $notify_ctl = shift;
	my $sock;
	my $flags;

#	my $command = $bd->get_binaries_path_ref->{"mktemp"} . " -p " . $dh->get_tmp_dir . " vnx_notify.ctl.XXXXXX";
#	chomp($notify_ctl = `$command`);

	# create socket
	!defined(socket($sock, AF_UNIX, SOCK_DGRAM, 0)) and 
		$execution->smartdie("socket() failed : $!");


	# bind socket to file
	unlink($notify_ctl);
	!defined(bind($sock, sockaddr_un($notify_ctl))) and 
		$execution->smartdie("binding '$notify_ctl' failed : $!");
	
	# give the socket ownership of the effective uid, if the current user is root
	if ($> == 0) {
		$execution->execute("UML_notify_init", $bd->get_binaries_path_ref->{"chown"} . " " . $execution->get_uid . " " . $notify_ctl);
	}

#	return ($sock, $notify_ctl);
	return $sock;
}


###################################################################
# Clean up listen socket
sub UML_notify_cleanup {
	my $sock = shift;
	my $notify_ctl = shift;

	close($sock);
	unlink $notify_ctl;
}

#sub para {
#	my $mensaje = shift;
#	my $var = shift;
#	print "************* $mensaje *************\n";
#	if (defined $var){
#	   print $var . "\n";	
#	}
#	print "*********************************\n";
#	<STDIN>;
#}

1;

