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

package vmAPI_uml;

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

#use strict;

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


# Name of UML whose boot process has started but not reached the init program
# (for emergency cleanup).  If the mconsole socket has successfully been initialized
# on the UML then '#' is appended.
my $curr_uml;
my $F_flag;       # passed from createVM to halt
my $M_flag;       # passed from createVM to halt



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
	$curr_uml = $vmName;

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


		if ( $execution->get_exe_mode() ne EXE_DEBUG ) {
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
	#                  defineVM for uml                               #
	###################################################################
	if ( $type eq "uml" ) {
		#$error = "Can't define vm of type uml.\n";
		$error = 0;
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
	#                  undefineVM for uml                             #
	###################################################################
	if ( $type eq "uml" ) {
		#$error = "Can't undefine vm of type uml.\n";
		$error = 0;
		return $error;
	}
	else {
		$error = "undefineVM for type $type not implemented yet.\n";
		return $error;
	}
}


# Currently used by vnx
###################################################################
#                                                                 #
#   createVM                                                      #
#                                                                 #
#                                                                 #
#                                                                 #
###################################################################
sub createVM {

	my $self   = shift;
	my $vmName = shift;
	my $type   = shift;
	my $doc    = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
	my $sock    = shift;
	my $counter = shift;
	$curr_uml = $vmName;

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

		# my $path;lo defino fuera del for para que esté disponible
		if ( $execution->get_exe_mode() ne EXE_DEBUG ) {
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
	#                  createVM for uml                               #
	###################################################################
	if ( $type eq "uml" ) {

		my @params;
		my @build_params;

		for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {

			#my $vm = $vm_ordered[$i];
			$vm = $vm_ordered[$i];

			# We get name attribute
			my $name = $vm->getAttribute("name");

			unless ( $name eq $vmName ) {
				next;
			}

			# To make configuration file
			&UML_bootfile( $path, $vm, $counter );

			# To make plugins configuration
			&UML_plugins_conf( $path, $vm );
		}

		# Create the iso filesystem

		$execution->execute( $bd->get_binaries_path_ref->{"mkisofs"}
			  . " -R -quiet -o $filesystem $path" );
		$execution->execute(
			$bd->get_binaries_path_ref->{"rm"} . " -rf $path" );

		my $parser = new XML::DOM::Parser;
		my $dom    = $parser->parse($doc);

		my $globalNode = $dom->getElementsByTagName("create_conf")->item(0);

		my $virtualmList  = $globalNode->getElementsByTagName("vm");
		my $virtualm      = $virtualmList->item(0);
		my $virtualm_name = $virtualm->getAttribute("name");

		my $kernelTagList = $virtualm->getElementsByTagName("kernel");
#		my $kernelTag     = $kernelTagList->item(0);
#		my $kernel_item   = $kernelTag->getFirstChild->getData;
        my $kernel_item   = $kernelTagList->item(0);
        my $kernelTag     = $kernel_item->getFirstChild->getData;
		my $kernel;

		if ( $kernelTag ne 'default' ) {
			$kernel = $kernelTag;
			if ( $kernel_item->getAttribute("initrd") !~ /^$/ ) {
				push( @params,
					"initrd=" . $kernel_item->getAttribute("initrd") );
				push( @build_params,
					"initrd=" . $kernel_item->getAttribute("initrd") );
			}
			if ( $kernel_item->getAttribute("devfs") !~ /^$/ ) {
				push( @params, "devfs=" . $kernel_item->getAttribute("devfs") );
				push( @build_params,
					"devfs=" . $kernel_item->getAttribute("devfs") );
			}
			if ( $kernel_item->getAttribute("root") !~ /^$/ ) {
				push( @params, "root=" . $kernel_item->getAttribute("root") );
				push( @build_params,
					"root=" . $kernel_item->getAttribute("root") );
			}
			if ( $kernel_item->getAttribute("modules") !~ /^$/ ) {
				push( @build_params,
					"modules=" . $kernel_item->getAttribute("modules") );
			}
			if ( $kernel_item->getAttribute("trace") eq "on" ) {
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
				push( @params,       "stderr=1" );
				push( @build_params, "stderr=1" );
			}
		}


		my $filesystemTagList = $virtualm->getElementsByTagName("filesystem");
		my $filesystemTag     = $filesystemTagList->item(0);
		my $filesystem_type   = $filesystemTag->getAttribute("type");
		my $filesystem        = $filesystemTag->getFirstChild->getData;

		# If cow type, we have to check whether particular filesystem exists
		# to set the right boot filesystem.
		if ( $filesystem_type eq "cow" ) {
			if ( -f $dh->get_fs_dir($vmName) . "/root_cow_fs" ) {
				$filesystem = $dh->get_fs_dir($vmName) . "/root_cow_fs";
			}
			else {
				$filesystem =
				  $dh->get_fs_dir($vmName) . "/root_cow_fs,$filesystem";
			}
		}

		# set ubdb
		push( @params, "ubdb=" . $dh->get_fs_dir($vmName) . "/opt_fs" );

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
		push( @params, "hostfs=" . $dh->get_hostfs_dir($vmName) );

		# VNUML-ize filesystem
		my $Z_flagTagList = $virtualm->getElementsByTagName("Z_flag");
		my $Z_flagTag     = $Z_flagTagList->item(0);
		my $Z_flag        = $Z_flagTag->getFirstChild->getData;

		if ( ( !-f $dh->get_fs_dir($vmName) . "/build-stamp" ) && ( !$Z_flag ) )
		{

			push( @build_params, "root=/dev/root" );
			push( @build_params, "rootflags=/" );
			push( @build_params, "rootfstype=hostfs" );
			push( @build_params, "ubdb=$filesystem" );

			#%%# push(@build_params, "init=@prefix@/@libdir@/vnumlize.sh");

			push( @build_params, "con=null" );

			$execution->execute("$kernel @build_params");
			$execution->execute( $bd->get_binaries_path_ref->{"touch"} . " "
				  . $dh->get_fs_dir($vmName)
				  . "/build-stamp" );
			if ( $> == 0 ) {
				$execution->execute( $bd->get_binaries_path_ref->{"chown"} . " "
					  . $execution->get_uid . " "
					  . $dh->get_fs_dir($vmName)
					  . "/root_cow_fs" );
				$execution->execute( $bd->get_binaries_path_ref->{"chown"} . " "
					  . $execution->get_uid . " "
					  . $dh->get_fs_dir($vmName)
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
		my $ifTagList = $virtualm->getElementsByTagName("if");
		my $numif     = $ifTagList->getLength;

		for ( my $j = 0 ; $j < $numif ; $j++ ) {

			my $ifTag = $ifTagList->item($j);

			my $id  = $ifTag->getAttribute("id");
			my $net = $ifTag->getAttribute("net");
			my $mac = $ifTag->getAttribute("mac");

			if ( &get_net_by_mode( $net, "uml_switch" ) != 0 ) {
				my $uml_switch_sock = $dh->get_networks_dir . "/$net.ctl";
				push( @params, "eth$id=daemon$mac,unix,$uml_switch_sock" );
			}
			else {
				push( @params, "eth$id=tuntap,$vmName-e$id$mac" );
			}
		}

		# Management interface

		my $mng_ifTagList = $virtualm->getElementsByTagName("mng_if");
		my $mng_ifTag     = $mng_ifTagList->item(0);
		my $mng_if_value  = $mng_ifTag->getAttribute("value");
		my $mac           = $mng_ifTag->getAttribute("mac");

		unless ( $mng_if_value eq "no" || $dh->get_vmmgmt_type eq 'none' ) {
			if ( $dh->get_vmmgmt_type eq 'private' ) {
				push( @params, "eth0=tuntap,$virtualm_name-e0$mac" );
			}
			else {

				# use the switch daemon
				my $uml_switch_sock = $dh->get_networks_dir . "/"
				  . $dh->get_vmmgmt_netname . ".ctl";
				push( @params, "eth0=daemon$mac,unix,$uml_switch_sock" );
			}
		}

		# Background UML execution without consoles by default
		push( @params,
			"uml_dir=" . $dh->get_vm_dir($vmName) . "/ umid=run con=null" );

		# Process <console> tags
		my @console_list = $dh->merge_console($virtualm);

		my $xterm_used = 0;
		foreach my $console (@console_list) {
			my $console_id    = $console->getAttribute("id");
			my $console_value = &text_tag($console);
			if ( $console_value eq "xterm" ) {

# xterms are treated like pts, to avoid unstabilities
# (see https://lists.dit.upm.es/pipermail/vnuml-users/2007-July/000651.html for details)
				$console_value = "pts";
			}
			push( @params, "con$console_id=$console_value" );
		}

		#get tag notify_ctl
		my $notify_ctlTagList = $virtualm->getElementsByTagName("notify_ctl");
		my $notify_ctlTag     = $notify_ctlTagList->item(0);
		my $notify_ctl        = $notify_ctlTag->getFirstChild->getData;

		# Add mconsole option to command line
		push( @params, "mconsole=notify:$notify_ctl" );

		# my @group = getgrnam("[arroba]TUN_GROUP[arroba]");
		my @group = getgrnam("uml-net");

		# Boot command execution

		#get tag o_flag (el output)
		my $o_flagTagList = $virtualm->getElementsByTagName("o_flag");
		my $num           = $o_flagTagList->getLength;
		my $o_flagTag     = $o_flagTagList->item(0);
		my $o_flag        = "";
		eval { $o_flag = $o_flagTag->getFirstChild->getData; };

		#get tag e_flag
		my $e_flagTagList = $virtualm->getElementsByTagName("e_flag");
		my $e_flagTag     = $e_flagTagList->item(0);
		my $e_flag        = "";
		eval { $e_flag = $e_flagTag->getFirstChild->getData; };

		#get tag group2_flag (output)
		my $group2TagList = $virtualm->getElementsByTagName("group2");
		my $group2Tag     = $group2TagList->item(0);
		my $group2        = "";
		eval { $group2 = $group2Tag->getFirstChild->getData; };

		#get tag F_flag
		my $F_flagTagList = $virtualm->getElementsByTagName("F_flag");
		my $F_flagTag     = $F_flagTagList->item(0);
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
				print
"VNX warning: for safety /dev files (except /dev/null and /dev/stdout) are forbidden in -o. Using default (standard output)\n";
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
					$output = $o_flag . ".$vmName";
				}
			}
		}
		else {

			# Default value when -o is not being used
			$output = '/dev/stdout';
		}

		$execution->execute_bg( "$kernel @params",
			$output, &vm_tun_access($virtualm) ? $group2 : '' );

		if ( $execution->get_exe_mode() ne EXE_DEBUG ) {

			my $boot_status = &UML_init_wait( $sock, $dh->get_boot_timeout );

			if ( !$boot_status ) {

				&UML_notify_cleanup( $sock, $notify_ctl );

				halt_uml( $vmName, $F_flag );
				$execution->smartdie("Boot timeout exceeded for vm $vmName!");
			}
			elsif ( $boot_status < 0 && !&UML_init_wait( $sock, 1, 1 ) ) {
				&kill_curr_uml;
			}
		}

		# Console pts and xterm processing
		#if ( $execution->get_exe_mode() != EXE_DEBUG ) { JSF 16/11: error "EXE_DEBUG no numerico"
		if ( $execution->get_exe_mode() ne EXE_DEBUG ) {
			my @console_list = $dh->merge_console($virtualm);
			my $get_screen_pts;
			foreach my $console (@console_list) {
				my $console_id    = $console->getAttribute("id");
				my $console_value = &text_tag($console);
				if ( $console_value eq "pts" ) {
					my $pts = "";
					while ( $pts =~ /^$/ )
					{ # I'm sure that this loop could be smarter, but it works :)
						print "Trying to get console $console_id pts...\n"
						  #if ( $execution->get_exe_mode() == EXE_VERBOSE );
						  if ( $execution->get_exe_mode() eq EXE_VERBOSE );
						sleep 1;    # Needed to avoid  syncronization problems
						my $command =
						    $bd->get_binaries_path_ref->{"uml_mconsole"} . " "
						  . $dh->get_run_dir($vmName)
						  . "/mconsole config con$console_id 2> /dev/null";
						my $mconsole_output = `$command`;
						if ( $mconsole_output =~ /^OK pts:(.*)$/ ) {
							$pts = $1;
							print "...pts is $pts\n"
							  #if ( $execution->get_exe_mode() == EXE_VERBOSE );
							  if ( $execution->get_exe_mode() eq EXE_VERBOSE );
							$execution->execute(
								    $bd->get_binaries_path_ref->{"echo"}
								  . " $pts > "
								  . $dh->get_run_dir($vmName)
								  . "/pts" );
						}
					}
					if ($e_flag) {

						# Optionally (if -e is being used) put the value in a
						# screen.conf file
						# FIXME: this would be obsolete in the future with the
						# 'vn console' tool
						print SCREEN_CONF "screen -t $vmName $pts\n";
					}
				}

				# xterm processing is quite similar to pts since 1.8.3, but
				# the difference is that the descriptor will be internally
				# used by VNUML itself, instead of recording to a file
				elsif ( $console_value eq "xterm" ) {
					my $xterm_pts = "";
					while ( $xterm_pts =~ /^$/ )
					{ # I'm sure that this loop could be smarter, but it works :)
						print "Trying to get console $console_id pts...\n"
						  # if ( $execution->get_exe_mode() == EXE_VERBOSE ); #JSF 16/11:error "EXE_VERBOSE no numerico"
						  if ( $execution->get_exe_mode() eq EXE_VERBOSE );
						sleep 1;    # Needed to avoid  syncronization problems
						my $command =
						    $bd->get_binaries_path_ref->{"uml_mconsole"} . " "
						  . $dh->get_run_dir($vmName)
						  . "/mconsole config con$console_id 2> /dev/null";
						my $mconsole_output = `$command`;
						if ( $mconsole_output =~ /^OK pts:(.*)$/ ) {
							$xterm_pts = $1;
							print "...xterm pts is $xterm_pts\n"
							  #if ( $execution->get_exe_mode() == EXE_VERBOSE ); JSF 16/11: error "EXE_VERBOSE" no numerico
							  if ( $execution->get_exe_mode() eq EXE_VERBOSE );
							$execution->execute(
								    $bd->get_binaries_path_ref->{"echo"}
								  . " $xterm_pts > "
								  . $dh->get_run_dir($vmName)
								  . "/pts" );

			  # Get the xterm binary to use and parse it (it is supossed to be a
			  # comma separated string with three fields)
							my $xterm = $dh->get_default_xterm;
							my $xterm_list =
							  $virtualm->getElementsByTagName("xterm");
							if ( $xterm_list->getLength == 1 ) {
								$xterm = &text_tag( $xterm_list->item(0) );
							}

			# Decode a <xterm> string (first argument) like "xterm,-T title,-e"
			# or "gnome-terminal,-t title,-x". The former is assumed as default.
							my $xterm_cmd =
"xterm -T $vmName -e screen -t $vmName $xterm_pts";
							$xterm =~ /^(.+),(.+),(.+)$/;
							if ( ( $1 ne "" ) && ( $2 ne "" ) && ( $3 ne "" ) )
							{
								my $s1 = $1;
								my $s2 = $2;
								my $s3 = $3;

					   # If the second attribute is empty, we add the vm name as
					   # title
								if ( $s2 =~ /\W+\w+\W+/ ) {
									$xterm_cmd =
"$s1 $s2 $s3 screen -t $vmName $xterm_pts";
								}
								else {
									$xterm_cmd =
"$s1 $s2 $vmName $s3 screen -t $vmName $xterm_pts";
								}
							}
							
							# display console if required
							my $display_console   = $dom->getElementsByTagName("display_console")->item(0)->getFirstChild->getData;
							unless ($display_console eq "no") {
								$execution->execute_bg( "$xterm_cmd", "/dev/null",
								"" );
							}
						}
					}
				}
			}
		}

		# done in vnx core
		# &change_vm_status( $dh, $vmName, "running" );

		# Close screen configuration file
		if ( ($e_flag) && ( $execution->get_exe_mode() ne EXE_DEBUG ) ) {
			close SCREEN_CONF;
		}

	}
	else {
		$error = "createVM for type $type not implemented yet.\n";
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
	#                  destroyVM for uml                              #
	###################################################################
	if ( $type eq "uml" ) {

		my @pids;

		# DFC
		&halt_uml( $vmName, 1 );

		# 1. Kill all Linux processes, gracefully
		@pids = &get_kernel_pids($vmName);
		if ( @pids != 0 ) {

			my $pids_string = join( " ", @pids );
			$execution->execute( $bd->get_binaries_path_ref->{"kill"}
				  . " -SIGTERM $pids_string" );
			print "Waiting UMLs to term gracefully...\n"
			  #unless ( $execution->get_exe_mode() == EXE_NORMAL );
			  unless ( $execution->get_exe_mode() eq EXE_NORMAL );
			sleep( $dh->get_delay )
			  #unless ( $execution->get_exe_mode() == EXE_DEBUG );
			  unless ( $execution->get_exe_mode() eq EXE_DEBUG );
		}

		# 2. Kill all remaining Linux processes, by brute force
		@pids = &get_kernel_pids($vmName);
		if ( @pids != 0 ) {
			my $pids_string = join( " ", @pids );
			$execution->execute( $bd->get_binaries_path_ref->{"kill"}
				  . " -SIGKILL $pids_string" );
			print "Waiting remaining UMLs to term forcely...\n"
			  #unless ( $execution->get_exe_mode() == EXE_NORMAL );
			  unless ( $execution->get_exe_mode() eq EXE_NORMAL );
			sleep( $dh->get_delay )
			  #unless ( $execution->get_exe_mode() == EXE_DEBUG );
			  unless ( $execution->get_exe_mode() eq EXE_DEBUG );
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
#	my $dh           = shift;
	my $sock         = shift;
	my $manipcounter = shift;

	my $error;

	###################################################################
	#                  startVM for uml                                #
	###################################################################
	if ( $type eq "uml" ) {

		$error = &createVM(
			$self, $vmName, $type, $doc, $execution,
			$bd,   $dh,     $sock, $manipcounter
		);
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
	$F_flag    = shift;

	my $error = 0;

	###################################################################
	#                  shutdownVM for uml                             #
	###################################################################	
	if ( $type eq "uml" ) {
		&halt_uml( $vmName, $F_flag );
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

	###################################################################
	#                  saveVM for uml                                 #
	###################################################################
	if ( $type eq "uml" ) {
		$error = "Type uml is not yet supported\n";
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

	###################################################################
	#                  restoreVM for uml                              #
	###################################################################
	if ( $type eq "uml" ) {
		$error = "Type uml is not yet supported\n";
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
	#                  suspendVM for uml                              #
	###################################################################
	if ( $type eq "uml" ) {
		$error = "Type uml is not yet supported\n";
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

	###################################################################
	#                  resumeVM for uml                               #
	###################################################################
	if ( $type eq "uml" ) {
		$error = "Type uml is not yet supported\n";
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
	#                  rebootVM for uml                               #
	###################################################################
	if ( $type eq "uml" ) {
		$error = "Type uml is not yet supported\n";
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

	###################################################################
	#                  resetVM for uml                                #
	###################################################################
	if ( $type eq "uml" ) {
		$error = "Type uml is not yet supported\n";
		return $error;
	}
	else {
		$error = "Type is not yet supported\n";
		return $error;
	}
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
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
	$vm    = shift;
	my $name = shift;

	#Commands sequence (start, stop or whatever).

	# Previous checkings and warnings
#	my @vm_ordered = $dh->get_vm_ordered;
#	my %vm_hash    = $dh->get_vm_to_use(@plugins);
my $random_id  = &generate_random_string(6);
			my @filetree_list = $dh->merge_filetree($vm);
			foreach my $filetree (@filetree_list) {
			
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
	
				# To get installation point at the UML
				my $dest = $filetree->getAttribute("root");
	
				# To get momment
				# JSF 02/12/10: we accept several commands in the same seq tag,
				# separated by spaces
				#my $filetree_seq = $filetree->getAttribute("seq");
				my $filetree_seq_string = $filetree->getAttribute("seq");
				my @filetree_seqs = split(' ',$filetree_seq_string);
				foreach my $filetree_seq (@filetree_seqs) {

					# To install subtree (only in the right momment)
					# FIXME: think again the "always issue"; by the moment deactivated
					if ( $filetree_seq eq $seq ) {
				
						# To get executing user and execution mode
						my $user   = &get_user_in_seq( $vm, $seq );
						my $mode   = &get_vm_exec_mode($vm);
		               # my $typeos = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
		
						if ( $mode eq "net" ) {
							$execution->execute( $bd->get_binaries_path_ref->{"scp"} . " -q -r -oProtocol=" . $dh->get_ssh_version . " -o 'StrictHostKeyChecking no'" . " $src/* $user\@$vm_ips{$name}:$dest" );
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
		
							my $mconsole = $dh->get_run_dir($name) . "/mconsole";
							if ( -S $mconsole ) {
								my $command =  $bd->get_binaries_path_ref->{"mktemp"} . " -d -p " . $dh->get_hostfs_dir($name) . " filetree.XXXXXX";
								chomp( my $filetree_host = `$command` );
								$filetree_host =~ /filetree\.(\w+)$/;
								my $random_id   = $1;
								my $filetree_vm = "/mnt/hostfs/filetree.$random_id";
		
								$execution->execute($bd->get_binaries_path_ref->{"cp"} . " -r $src/* $filetree_host" );
		
								# 1. Save directory permissions
								my %file_perms = &save_dir_permissions($filetree_host);
		
								# 2. 777-ize all
								$execution->execute($bd->get_binaries_path_ref->{"chmod"} . " -R 777 $filetree_host" );
		
								# 3a. Prepare the copying script. Note that cp can not be executed directly, because
								# wee need to "mark" the end of copy and actively monitoring it before continue. Otherwise
								# race condictions may occur. See https://lists.dit.upm.es/pipermail/vnuml-devel/2007-January/000459.html
								# for some detail
								# FIXME: the procedure is quite similar to the one in commands_file function. Maybe
								# it could be generalized in a external function, to avoid duplication
								open COMMAND_FILE,">" . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id" or $execution->smartdie( "can not open " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id: $!" )
								 #unless ($execution->get_exe_mode() == EXE_DEBUG );
								 unless ($execution->get_exe_mode() eq EXE_DEBUG );
								my $verb_prompt_bk = $execution->get_verb_prompt();
		
								# FIXME: consider to use a different new VNX::Execution object to perform this
								# actions (avoiding this nasty verb_prompt backup)
								$execution->set_verb_prompt("$name> ");
		
								my $shell      = $dh->get_default_shell;
								my $shell_list = $vm->getElementsByTagName("shell");
								if ( $shell_list->getLength == 1 ) {
									$shell = &text_tag( $shell_list->item(0) );
								}
								my $date_command =
								  $bd->get_binaries_path_ref->{"date"};
								chomp( my $now = `$date_command` );
								my $basename = basename $0;
								$execution->execute( "#!" . $shell, *COMMAND_FILE );
								$execution->execute("#filetree.$random_id copying script",*COMMAND_FILE );
								$execution->execute("#generated by $basename $version$branch at $now",*COMMAND_FILE);
								$execution->execute( "cp -r $filetree_vm/* $dest",*COMMAND_FILE );
								$execution->execute("echo 1 > /mnt/hostfs/filetree_cp.$random_id.end",*COMMAND_FILE);
		
								close COMMAND_FILE
								  #unless ($execution->get_exe_mode() == EXE_DEBUG );
								  unless ($execution->get_exe_mode() eq EXE_DEBUG );
								$execution->set_verb_prompt($verb_prompt_bk);
								$execution->execute($bd->get_binaries_path_ref->{"chmod"} . " a+x " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id" );
		
								# 3b. Script execution
								$execution->execute_mconsole( $mconsole,"/mnt/hostfs/filetree_cp.$random_id" );
		
								# 3c. Actively wait for the copying end
								chomp( my $init = `$date_command` );
								print  "Waiting filetree $src->$dest filetree copy... "
								  #if ( $execution->get_exe_mode() == EXE_VERBOSE );
								  if ( $execution->get_exe_mode() eq EXE_VERBOSE );
								&filetree_wait( $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id.end" );
								chomp( my $end = `$date_command` );
								my $time = $init - $end;
								print "(" . $time . "s)\n"
								  #if ( $execution->get_exe_mode() == EXE_VERBOSE );
								  if ( $execution->get_exe_mode() eq EXE_VERBOSE );
		
								# 3d. Cleaning
								$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -rf $filetree_host" );
								$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id" );
								$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f "  . $dh->get_hostfs_dir($name) . "/filetree_cp.$random_id.end" );
		
								  # 4. Restore directory permissions; we need to perform some transformation
								  # in the keys (finelame) host-relative -> vm-relative
								my %file_vm_perms;
								foreach ( keys %file_perms ) {
									$_ =~ /^$filetree_host\/(.*)$/;
									my $new_key = "$dest/$1";
									$file_vm_perms{$new_key} = $file_perms{$_};
								}
								&set_file_permissions( $mconsole,$dh->get_hostfs_dir($name),%file_vm_perms );
		
								# Setting proper user
								&set_file_user($mconsole, $dh->get_hostfs_dir($name),$user,     keys %file_vm_perms
								);
							}
							else {
								print "VNX warning: $mconsole socket does not exist. Copy of $src files can not be performed\n";
							}
						}
	
							}
					}
				}
   			 ###################### COMMAND_FILES ##########################
   			 
			# We open file
			open COMMAND_FILE,
			  ">" . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id"
			  or $execution->smartdie(
				"can not open " . $dh->get_tmp_dir . "/vnx.$name.$seq: $!" )
			  #unless ( $execution->get_exe_mode() == EXE_DEBUG );
			  unless ( $execution->get_exe_mode() eq EXE_DEBUG );

			my $verb_prompt_bk = $execution->get_verb_prompt();

# FIXME: consider to use a different new VNX::Execution object to perform this
# actions (avoiding this nasty verb_prompt backup)
			$execution->set_verb_prompt("$name> ");

			my $shell      = $dh->get_default_shell;
			my $shell_list = $vm->getElementsByTagName("shell");
			if ( $shell_list->getLength == 1 ) {
				$shell = &text_tag( $shell_list->item(0) );
			}
			my $command = $bd->get_binaries_path_ref->{"date"};
			chomp( my $now = `$command` );
			$execution->execute( "#!" . $shell,              *COMMAND_FILE );
			$execution->execute( "#commands sequence: $seq", *COMMAND_FILE );
			$execution->execute("#file generated by $basename $version$branch at $now",*COMMAND_FILE );

			# To process exec tags of matching commands sequence
			my $command_list = $vm->getElementsByTagName("exec");

			# To process list, dumping commands to file
			for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
				my $command = $command_list->item($j);

				# To get attributes
				#my $cmd_seq = $command->getAttribute("seq");
				# JSF 01/12/10: we accept several commands in the same seq tag,
				# separated by spaces				
				my $cmd_seq_string = $command->getAttribute("seq");
				my @cmd_seqs = split(' ',$cmd_seq_string);
				my $type    = $command->getAttribute("type");
				foreach my $cmd_seq (@cmd_seqs) {

					if ( $cmd_seq eq $seq ) {
	
						# Case 1. Verbatim type
						if ( $type eq "verbatim" ) {
	
							# Including command "as is"
							$execution->execute( &text_tag_multiline($command),
								*COMMAND_FILE );
						}
	
						# Case 2. File type
						elsif ( $type eq "file" ) {
	
							# We open the file and write commands line by line
							my $include_file =
							  &do_path_expansion( &text_tag($command) );
							open INCLUDE_FILE, "$include_file"
							  or $execution->smartdie(
								"can not open $include_file: $!");
							while (<INCLUDE_FILE>) {
								chomp;
								$execution->execute( $_, *COMMAND_FILE );
							}
							close INCLUDE_FILE;
						}
	
				 # Other case. Don't do anything (it would be and error in the XML!)
					}
				}
			}

		 # Plugin operation
		 # $execution->execute("# commands generated by plugins",*COMMAND_FILE);
			foreach my $plugin (@plugins) {

				# contemplar que ahora la string seq puede contener
				# varios seq separados por espacios
				my @commands = $plugin->execCommands( $name, $seq );

				my $error = shift(@commands);
				if ( $error ne "" ) {
					$execution->smartdie(
						"plugin $plugin execCommands($name,$seq) error: $error"
					);
				}

				foreach my $cmd (@commands) {
					$execution->execute( $cmd, *COMMAND_FILE );
				}

			}

			# We close file and mark it executable
			close COMMAND_FILE
			  #unless ( $execution->get_exe_mode() == EXE_DEBUG );
			  unless ( $execution->get_exe_mode() eq EXE_DEBUG );
			$execution->set_verb_prompt($verb_prompt_bk);
			$execution->execute( $bd->get_binaries_path_ref->{"chmod"} . " a+x "
				  . $dh->get_tmp_dir
				  . "/vnx.$name.$seq.$random_id" );
		################################## INSTALL_COMMAND_FILES ###########################################
		my $user = &get_user_in_seq( $vm, $seq );
		my $mode = &get_vm_exec_mode($vm);

		# my $type = $vm->getAttribute("type");

		if ( $mode eq "net" ) {

			# We install the file in /tmp of the virtual machine, using ssh
			$execution->execute( $bd->get_binaries_path_ref->{"ssh"} . " -x -" . $dh->get_ssh_version . " -o 'StrictHostKeyChecking no'" . " -l $user $vm_ips{$name} rm -f /tmp/vnx.$name.$seq.$random_id &> /dev/null"	);
			$execution->execute( $bd->get_binaries_path_ref->{"scp"} . " -q -oProtocol=" . $dh->get_ssh_version  . " -o 'StrictHostKeyChecking no' " . $dh->get_tmp_dir . "/vnx.$name.$seq.$random_id $user\@$vm_ips{$name}:/tmp" );
		}
		elsif ( $mode eq "mconsole" ) {

  # We install the file in /mnt/hostfs of the virtual machine, using a simple cp
			$execution->execute( $bd->get_binaries_path_ref->{"cp"}
				  . " /tmp/vnx.$name.$seq.$random_id "
				  . $dh->get_hostfs_dir($name) );
		}
		elsif ( $mode eq "pts" ) {

			# TODO (Casey's works)
		}
		################################## EXEC_COMMAND_FILES ########################################
		

			# We execute the file. Several possibilities, depending on the mode
			if ( $mode eq "net" ) {

				# Executing through SSH
				$execution->execute(
					    $bd->get_binaries_path_ref->{"ssh"} . " -x -"
					  . $dh->get_ssh_version
					  . " -o 'StrictHostKeyChecking no'"
					  . " -l $user $vm_ips{$name} /tmp/vnx.$name.$seq.$random_id"
				);
			}
			elsif ( $mode eq "mconsole" ) {

				# Executing through mconsole
				my $mconsole = $dh->get_run_dir($name) . "/mconsole";
				if ( -S $mconsole ) {

# Note the explicit declaration of standard input, ouput and error descriptors. It has been noticed
# (http://www.mail-archive.com/user-mode-linux-user@lists.sourceforge.net/msg05369.html)
# that not doing so can cause problems in some situations (i.e., executin /etc/init.d/apache2)
					$execution->execute_mconsole( $mconsole,
"su $user /mnt/hostfs/vnx.$name.$seq.$random_id </dev/null >/dev/null 2>/dev/null"
					);
				}
				else {
					print
"VNX warning: $mconsole socket does not exist. Commands in vnx.$name.$seq.$random_id has not been executed\n";
				}
			}
			elsif ( $mode eq "pts" ) {

				# TODO (Casey's works)
			}

		 # We delete the file in the host after installation (this line could be
		 # commented out in order to hold the scripts in the hosts for debugging
		 # purposes)
			$execution->execute( $bd->get_binaries_path_ref->{"rm"} . " -f "
				  . $dh->get_tmp_dir
				  . "/vnx.$name.$seq.$random_id" );
			
			
}



###################################################################
#
sub UML_init_wait {
	my $sock      = shift;
	my $timeout   = shift;
	my $no_prompt = shift;
	my $data;


	my $MCONSOLE_SOCKET      = 0;
	my $MCONSOLE_PANIC       = 1;
	my $MCONSOLE_HANG        = 2;
	my $MCONSOLE_USER_NOTIFY = 3;

	while (1) {
		eval {
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
						print "Virtual machine $uml sucessfully booted.\n"
						  #if ( $execution->get_exe_mode() == EXE_VERBOSE ); JSF: error "EXE_VERBOSE no numerico" 
						   if ( $execution->get_exe_mode() eq EXE_VERBOSE );
						alarm 0;
						return;
					}
				}
			}
		};
		if ($@) {
			if ( defined($no_prompt) ) {
				return 0;
			}
			else {

				my ($uml) = $curr_uml =~ /(.+)#/;
				while (1) {
					print
"Boot timeout for virtual machine $uml reached.  Abort, Retry, or Continue? [A/r/c]: ";
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
	my $net_list = $doc->getElementsByTagName("net");

	# To process list
	for ( my $i = 0 ; $i < $net_list->getLength ; $i++ ) {
		my $net  = $net_list->item($i);
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

	my $vmName     = shift;
	my $F_flag     = shift;                 # DFC
	my @vm_ordered = $dh->get_vm_ordered;
	my %vm_hash    = $dh->get_vm_to_use;
	&kill_curr_uml;

	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
		my $vm = $vm_ordered[$i];

		# To get name attribute
		my $name = $vm->getAttribute("name");

		unless ( ( $vmName eq "" ) or ( $name eq $vmName ) ) {
			next;
		}

		#&change_vm_status( $dh, $name, "REMOVE" );
		&change_vm_status( $name, "REMOVE" );

		# Currently booting uml has already been killed
		if ( defined($curr_uml) && $name eq $curr_uml ) {
			next;
		}

	  # Depending of how parser has been called (-F switch), the stop process is
	  # more or less "aggressive" (and quick)
	  # uml_mconsole is very verbose: redirect its error output to null device
		my $mconsole = $dh->get_run_dir($name) . "/mconsole";
		if ( -S $mconsole ) {

			#  if ($args->get('F'))
			if ($F_flag) {

				# Halt trought mconsole socket,
				$execution->execute(
					$bd->get_binaries_path_ref->{"uml_mconsole"}
					  . " $mconsole halt 2>/dev/null" );

			}
			else {
				$execution->execute(
					$bd->get_binaries_path_ref->{"uml_mconsole"}
					  . " $mconsole cad 2>/dev/null" );

			}
		}
		else {
			print "VNX warning: $mconsole socket does not exist\n";
		}
	}

}



####################################################################
## Remove the effective user xauth privileges on the current display
#sub xauth_remove {
#	if ( $> == 0 && $execution->get_uid != 0 && &xauth_needed ) {
#		$execution->execute( "su -s /bin/sh -c '"
#			  . $bd->get_binaries_path_ref->{"xauth"}
#			  . " remove $ENV{DISPLAY}' "
#			  . getpwuid( $execution->get_uid ) );
#	}
#}



###################################################################
#
sub kill_curr_uml {

	# Force kill the currently booting uml process, if there is one
	if ( defined($curr_uml) ) {
		my $mconsole_init = $curr_uml =~ s/#$//;

		# Halt through mconsole socket,
		my $mconsole = $dh->get_run_dir($curr_uml) . "/mconsole";
		if ( -S $mconsole && $mconsole_init ) {
			$execution->execute( $bd->get_binaries_path_ref->{"uml_mconsole"}
				  . " $mconsole halt 2>/dev/null" );
		}
		elsif ( -f $dh->get_run_dir($curr_uml) . "/pid" ) {
			$execution->execute( $bd->get_binaries_path_ref->{"kill"}
				  . " -SIGTERM `"
				  . $bd->get_binaries_path_ref->{"cat"} . " "
				  . $dh->get_run_dir($curr_uml)
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



#######################################################
## To remove TUN/TAPs devices
#sub tun_destroy_switched {
#
#	my $doc = $dh->get_doc;
#
#	# Remove the symbolic link to the management switch socket
#	if ( $dh->get_vmmgmt_type eq 'net' ) {
#		my $socket_file =
#		  $dh->get_networks_dir . "/" . $dh->get_vmmgmt_netname . ".ctl";
#		$execution->execute(
#			$bd->get_binaries_path_ref->{"rm"} . " -f $socket_file" );
#	}
#
#	my $net_list = $doc->getElementsByTagName("net");
#
#	for ( my $i = 0 ; $i < $net_list->getLength ; $i++ ) {
#
#		# We get attributes
#		my $name = $net_list->item($i)->getAttribute("name");
#		my $mode = $net_list->item($i)->getAttribute("mode");
#		my $sock = $net_list->item($i)->getAttribute("sock");
#		my $vlan = $net_list->item($i)->getAttribute("vlan");
#		my $cmd;
#
#		# This function only processes uml_switch networks
#		if ( $mode eq "uml_switch" ) {
#
#			# Decrease the use counter
#			&dec_cter("$name.ctl");
#
#   # Destroy the uml_switch only when no other concurrent scenario is using it
#			if ( &get_cter("$name.ctl") == 0 ) {
#				my $socket_file = $dh->get_networks_dir() . "/$name.ctl";
#
#				# Casey (rev 1.90) proposed to use -f instead of -S, however
#				# I've performed some test and it fails... let's use -S?
#				#if ($sock eq '' && -f $socket_file) {
#				if ( $sock eq '' && -S $socket_file ) {
#					$cmd =
#					    $bd->get_binaries_path_ref->{"kill"} . " `"
#					  . $bd->get_binaries_path_ref->{"lsof"}
#					  . " -t $socket_file`";
#					$execution->execute($cmd);
#					sleep 1;
#				}
#				$execution->execute(
#					$bd->get_binaries_path_ref->{"rm"} . " -f $socket_file" );
#			}
#
#			# To check if VLAN is being used
#			#my $tun_vlan_if = $tun_if . ".$vlan" unless ($vlan =~ /^$/);
#
#			# To decrease use counter
#			#&dec_cter($tun_vlan_if);
#			#}
#		}
#	}
#}



#######################################################
## To remove TUN/TAPs devices
#sub tun_destroy {
#
#	my @vm_ordered = $dh->get_vm_ordered;
#
#	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
#		my $vm = $vm_ordered[$i];
#
#		# To get name attribute
#		my $name = $vm->getAttribute("name");
#
#		# To throw away and remove management device (id 0), if neeed
#		my $mng_if_value = &mng_if_value( $dh, $vm );
#
#		if ( $dh->get_vmmgmt_type eq 'private' && $mng_if_value ne "no" ) {
#			my $tun_if = $name . "-e0";
#			$execution->execute(
#				$bd->get_binaries_path_ref->{"ifconfig"} . " $tun_if down" );
#			$execution->execute( $bd->get_binaries_path_ref->{"tunctl"}
#				  . " -d $tun_if -f "
#				  . $dh->get_tun_device );
#		}
#
#		# To get UML's interfaces list
#		my $if_list = $vm->getElementsByTagName("if");
#
#		# To process list
#		for ( my $j = 0 ; $j < $if_list->getLength ; $j++ ) {
#			my $if = $if_list->item($j);
#
#			# To get attributes
#			my $id  = $if->getAttribute("id");
#			my $net = $if->getAttribute("net");
#
#			# Only exists TUN/TAP in a bridged network
#			#if (&check_net_br($net)) {
#			if ( &get_net_by_mode( $net, "virtual_bridge" ) != 0 ) {
#
#				# To build TUN device name
#				my $tun_if = $name . "-e" . $id;
#
#				# To throw away TUN device
#				$execution->execute( $bd->get_binaries_path_ref->{"ifconfig"}
#					  . " $tun_if down" );
#
#				# To remove TUN device
#				$execution->execute( $bd->get_binaries_path_ref->{"tunctl"}
#					  . " -d $tun_if -f "
#					  . $dh->get_tun_device );
#			}
#
#		}
#
#	}
#
#}



#######################################################
## To restore host configuration
#sub host_unconfig {
#
#	my $doc = $dh->get_doc;
#
#	# If host <host> is not present, there is nothing to unconfigure
#	return if ( $doc->getElementsByTagName("host")->getLength eq 0 );
#
#	# To get <host> tag
#	my $host = $doc->getElementsByTagName("host")->item(0);
#
#	# To get host routes list
#	my $route_list = $host->getElementsByTagName("route");
#	for ( my $i = 0 ; $i < $route_list->getLength ; $i++ ) {
#		my $route_dest = &text_tag( $route_list->item($i) );
#		my $route_gw   = $route_list->item($i)->getAttribute("gw");
#		my $route_type = $route_list->item($i)->getAttribute("type");
#
#		# Routes for IPv4
#		if ( $route_type eq "ipv4" ) {
#			if ( $dh->is_ipv4_enabled ) {
#				if ( $route_dest eq "default" ) {
#					$execution->execute( $bd->get_binaries_path_ref->{"route"}
#						  . " -A inet del $route_dest gw $route_gw" );
#				}
#				elsif ( $route_dest =~ /\/32$/ ) {
#
## Special case: X.X.X.X/32 destinations are not actually nets, but host. The syntax of
## route command changes a bit in this case
#					$execution->execute( $bd->get_binaries_path_ref->{"route"}
#						  . " -A inet del -host $route_dest gw $route_gw" );
#				}
#				else {
#					$execution->execute( $bd->get_binaries_path_ref->{"route"}
#						  . " -A inet del -net $route_dest gw $route_gw" );
#				}
#
##$execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet del $route_dest gw $route_gw");
#			}
#		}
#
#		# Routes for IPv6
#		else {
#			if ( $dh->is_ipv6_enabled ) {
#				if ( $route_dest eq "default" ) {
#					$execution->execute( $bd->get_binaries_path_ref->{"route"}
#						  . " -A inet6 del 2000::/3 gw $route_gw" );
#				}
#				else {
#					$execution->execute( $bd->get_binaries_path_ref->{"route"}
#						  . " -A inet6 del $route_dest gw $route_gw" );
#				}
#			}
#		}
#	}
#
#	# To get host interfaces list
#	my $if_list = $host->getElementsByTagName("hostif");
#
#	# To process list
#	for ( my $i = 0 ; $i < $if_list->getLength ; $i++ ) {
#		my $if = $if_list->item($i);
#
#		# To get name attribute
#		my $net = $if->getAttribute("net");
#
#		# Destroy the tun device
#		$execution->execute(
#			$bd->get_binaries_path_ref->{"ifconfig"} . " $net down" );
#		$execution->execute( $bd->get_binaries_path_ref->{"tunctl"}
#			  . " -d $net -f "
#			  . $dh->get_tun_device );
#	}
#}



#######################################################
## To remove external interfaces
#sub external_if_remove {
#
#	my $doc = $dh->get_doc;
#
#	# To get list of defined <net>
#	my $net_list = $doc->getElementsByTagName("net");
#
#	# To process list, decreasing use counter of external interfaces
#	for ( my $i = 0 ; $i < $net_list->getLength ; $i++ ) {
#		my $net = $net_list->item($i);
#
#		# To get name attribute
#		my $name = $net->getAttribute("name");
#
#		# We check if there is an associated external interface
#		my $external_if = $net->getAttribute("external");
#		next if ( $external_if =~ /^$/ );
#
#		# To check if VLAN is being used
#		my $vlan = $net->getAttribute("vlan");
#		$external_if .= ".$vlan" unless ( $vlan =~ /^$/ );
#
#		# To decrease use counter
#		&dec_cter($external_if);
#
#		# To clean up not in use physical interfaces
#		if ( &get_cter($external_if) == 0 ) {
#			$execution->execute( $bd->get_binaries_path_ref->{"ifconfig"}
#				  . " $name 0.0.0.0 "
#				  . $dh->get_promisc
#				  . " up" );
#			$execution->execute( $bd->get_binaries_path_ref->{"brctl"}
#				  . " delif $name $external_if" );
#			unless ( $vlan =~ /^$/ ) {
#				$execution->execute( $bd->get_binaries_path_ref->{"vconfig"}
#					  . " rem $external_if" );
#			}
#			else {
#
#		# Note that now the interface has no IP address nor mask assigned, it is
#		# unconfigured! Tag <physicalif> is checked to try restore the interface
#		# configuration (if it exists)
#				&physicalif_config($external_if);
#			}
#		}
#	}
#}



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



#######################################################
## To remove bridges
#sub bridges_destroy {
#
#	my $doc = $dh->get_doc;
#
#	# To get list of defined <net>
#	my $net_list = $doc->getElementsByTagName("net");
#
#	# To process list, decreasing use counter of external interfaces
#	for ( my $i = 0 ; $i < $net_list->getLength ; $i++ ) {
#
#		# To get attributes
#		my $name = $net_list->item($i)->getAttribute("name");
#		my $mode = $net_list->item($i)->getAttribute("mode");
#
#		# This function only processes uml_switch networks
#		if ( $mode ne "uml_switch" ) {
#
## Set bridge down and remove it only in the case there isn't any associated interface
#			if ( &vnet_ifs($name) == 0 ) {
#				$execution->execute(
#					$bd->get_binaries_path_ref->{"ifconfig"} . " $name down" );
#				$execution->execute(
#					$bd->get_binaries_path_ref->{"brctl"} . " delbr $name" );
#			}
#		}
#	}
#}



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
	my $if_list = $vm->getElementsByTagName("if");

	# To process list
	for ( my $j = 0 ; $j < $if_list->getLength ; $j++ ) {
		my $if = $if_list->item($j);

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
   my $hostnum = shift;
   my $ip;

   my $net = NetAddr::IP->new($dh->get_vmmgmt_net."/".$dh->get_vmmgmt_mask);
   if ($vmmgmt_type eq 'private') {
	   # check to make sure that the address space won't wrap
	   if ($dh->get_vmmgmt_offset + ($seed << 2) > (1 << (32 - $dh->get_vmmgmt_mask)) - 3) {
		   $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
	   }

	   # create a private subnet from the seed
	   $net += $dh->get_vmmgmt_offset + ($seed << 2);
	   $ip = NetAddr::IP->new($net->addr()."/30") + $hostnum;
   } else {
	   # vmmgmt type is 'net'

	   # don't assign the hostip
	   my $hostip = NetAddr::IP->new($dh->get_vmmgmt_hostip."/".$dh->get_vmmgmt_mask);
	   if ($hostip > $net + $dh->get_vmmgmt_offset &&
		   $hostip <= $net + $dh->get_vmmgmt_offset + $seed + 1) {
		   $seed++;
	   }

	   # check to make sure that the address space won't wrap
	   if ($dh->get_vmmgmt_offset + $seed > (1 << (32 - $dh->get_vmmgmt_mask)) - 3) {
		   $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
	   }

	   # return an address in the vmmgmt subnet
	   $ip = $net + $dh->get_vmmgmt_offset + $seed + 1;
   }
   return $ip;
}



###################################################################
# get_kernel_pids;
#
# Return a list with the list of PID of UML kernel processes
#
sub get_kernel_pids {
	my $vmName = shift;
	my @pid_list;

	foreach my $vm ( $dh->get_vm_ordered ) {

		# Get name attribute
		my $name = $vm->getAttribute("name");
#		print "*$name* vs *$vmName*\n";
		unless ( ( $vmName eq 0 ) || ( $name eq $vmName ) ) {
			next;
		}
		my $pid_file = $dh->get_run_dir($name) . "/pid";
		next if ( !-f $pid_file );
		my $command = $bd->get_binaries_path_ref->{"cat"} . " $pid_file";
		chomp( my $pid = `$command` );
		push( @pid_list, $pid );
	}
	return @pid_list;

}



###################################################################
#
sub UML_bootfile {

	my $path   = shift;
	my $vm     = shift;
	my $number = shift;

	my $basename = basename $0;

	my $vm_name = $vm->getAttribute("name");

	# We open boot file, taking S$boot_prio and $runlevel
	open CONFILE, ">$path" . "umlboot"
	  or $execution->smartdie("can not open ${path}umlboot: $!")
	  #unless ( $execution->get_exe_mode() == EXE_DEBUG );
	  unless ( $execution->get_exe_mode() eq EXE_DEBUG );
	my $verb_prompt_bk = $execution->get_verb_prompt();

# FIXME: consider to use a different new VNX::Execution object to perform this
# actions (avoiding this nasty verb_prompt backup)
	$execution->set_verb_prompt("$vm_name> ");

	# We begin boot script
	my $shell      = $dh->get_default_shell;
	my $shell_list = $vm->getElementsByTagName("shell");
	if ( $shell_list->getLength == 1 ) {
		$shell = &text_tag( $shell_list->item(0) );
	}
	my $command = $bd->get_binaries_path_ref->{"date"};
	chomp( my $now = `$command` );
	$execution->execute( "#!" . $shell, *CONFILE );
	$execution->execute( "# UML boot file generated by $basename at $now",
		*CONFILE );
	$execution->execute( "UTILDIR=/mnt/vnx", *CONFILE );

	# 1. To set hostname
	$execution->execute( "hostname $vm_name", *CONFILE );

	# Configure management interface internal side, if neeed
	#my $mng_if_value = &mng_if_value( $dh, $vm );
	my $mng_if_value = &mng_if_value( $vm );
	unless ( $mng_if_value eq "no" || $dh->get_vmmgmt_type eq 'none' ) {
		my $net = &get_admin_address( $number, $dh->get_vmmgmt_type, 2 );

		$execution->execute(
			"ifconfig eth0 "
			  . $net->addr()
			  . " netmask "
			  . $net->mask() . " up",
			*CONFILE
		);

		# If host_mapping is in use, append trailer to /etc/hosts config file
		if ( $dh->get_host_mapping ) {
			#@host_lines = ( @host_lines, $net->addr() . " $vm_name" );
			#$execution->execute( $net->addr() . " $vm_name\n", *HOSTLINES );
			open HOSTLINES, ">>" . $dh->get_sim_dir . "/hostlines"
				or $execution->smartdie("can not open $dh->get_sim_dir/hostlines\n")
				unless ( $execution->get_exe_mode() eq EXE_DEBUG );
			print HOSTLINES $net->addr() . " $vm_name\n";
			close HOSTLINES;
		}
	}

	# 3. Interface configuration

	# To get UML's interfaces list

	my $if_list =
	  $vm->getElementsByTagName("if");    ### usar en su lugar el xml recibido

	# To process list
	for ( my $i = 0 ; $i < $if_list->getLength ; $i++ ) {
		my $if = $if_list->item($i);

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
				$execution->execute( "ifconfig $if_name 0.0.0.0 pointopoint up",
					*CONFILE );
				$execution->execute(
"tc qdisc replace dev $if_name root tbf rate $bw latency 50ms burst $burst",
					*CONFILE
				);
			}
			else {

				# To set up interface (without address, at the begining)
				$execution->execute(
					"ifconfig $if_name 0.0.0.0 " . $dh->get_promisc . " up",
					*CONFILE );
			}
		}

# 4a. To process interface IPv4 addresses
# The first address have to be assigned without "add" to avoid creating subinterfaces
		if ( $dh->is_ipv4_enabled ) {
			my $ipv4_list = $if->getElementsByTagName("ipv4");
			my $command   = "";
			for ( my $j = 0 ; $j < $ipv4_list->getLength ; $j++ ) {
				my $ip = &text_tag( $ipv4_list->item($j) );
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
					  $ipv4_list->item($j)->getAttribute("mask");
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

				$execution->execute(
"ifconfig $if_name $command $ip netmask $ipv4_effective_mask",
					*CONFILE
				);
				if ( $command =~ /^$/ ) {
					$command = "add";
				}
			}
		}

		# 4b. To process interface IPv6 addresses
		if ( $dh->is_ipv6_enabled ) {
			my $ipv6_list = $if->getElementsByTagName("ipv6");
			for ( my $j = 0 ; $j < $ipv6_list->getLength ; $j++ ) {
				my $ip = &text_tag( $ipv6_list->item($j) );
				if ( &valid_ipv6_with_mask($ip) ) {

					# Implicit slashed mask in the address
					$execution->execute( "ifconfig $if_name add $ip",
						*CONFILE );
				}
				else {

					# Check the value of the mask attribute
					my $ipv6_effective_mask = "/64";    # Default mask value
					my $ipv6_mask_attr =
					  $ipv6_list->item($j)->getAttribute("mask");
					if ( $ipv6_mask_attr ne "" ) {

					   # Note that, in the case of IPv6, mask are always slashed
						$ipv6_effective_mask = $ipv6_mask_attr;
					}
					$execution->execute(
						"ifconfig $if_name add $ip$ipv6_effective_mask",
						*CONFILE );
				}
			}
		}

		#}
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
					$execution->execute(
						"route -A inet add default gw $route_gw", *CONFILE );
				}
				elsif ( $route_dest =~ /\/32$/ ) {

# Special case: X.X.X.X/32 destinations are not actually nets, but host. The syntax of
# route command changes a bit in this case
					$execution->execute(
						"route -A inet add -host $route_dest  gw $route_gw",
						*CONFILE );
				}
				else {
					$execution->execute(
						"route -A inet add -net $route_dest gw $route_gw",
						*CONFILE );
				}

	#$execution->execute("route -A inet add $route_dest gw $route_gw",*CONFILE);
			}
		}

		# Routes for IPv6
		else {
			if ( $dh->is_ipv6_enabled ) {
				if ( $route_dest eq "default" ) {
					$execution->execute(
						"route -A inet6 add 2000::/3 gw $route_gw", *CONFILE );
				}
				else {
					$execution->execute(
						"route -A inet6 add $route_dest gw $route_gw",
						*CONFILE );
				}
			}
		}
	}

	# 6. Forwarding configuration
	my $f_type          = $dh->get_default_forwarding_type;
	my $forwarding_list = $vm->getElementsByTagName("forwarding");
	if ( $forwarding_list->getLength == 1 ) {
		$f_type = $forwarding_list->item(0)->getAttribute("type");
		$f_type = "ip" if ( $f_type =~ /^$/ );
	}
	if ( $dh->is_ipv4_enabled ) {
		$execution->execute( "echo 1 > /proc/sys/net/ipv4/ip_forward",
			*CONFILE )
		  if ( $f_type eq "ip" or $f_type eq "ipv4" );
	}
	if ( $dh->is_ipv6_enabled ) {
		$execution->execute( "echo 1 > /proc/sys/net/ipv6/conf/all/forwarding",
			*CONFILE )
		  if ( $f_type eq "ip" or $f_type eq "ipv6" );
	}

	# 7. Hostname configuration in /etc/hosts
	my $ip_hostname = &get_ip_hostname($vm);
	if ($ip_hostname) {
		$execution->execute( "HOSTNAME=\$(hostname)", *CONFILE );
		$execution->execute( "grep \$HOSTNAME /etc/hosts > /dev/null 2>&1",
			*CONFILE );
		$execution->execute( "if [ \$? == 1 ]",       *CONFILE );
		$execution->execute( "then",                  *CONFILE );
		$execution->execute( "   echo >> /etc/hosts", *CONFILE );
		$execution->execute( "   echo \\# Hostname configuration >> /etc/hosts",
			*CONFILE );
		$execution->execute(
			"   echo \"$ip_hostname \$HOSTNAME\" >> /etc/hosts", *CONFILE );
		$execution->execute( "fi", *CONFILE );
	}

	# 8. modify inittab to halt when ctrl-alt-del is pressed
	# This task is now performed by the vnumlize.sh script

	# 9. mount host filesystem in /mnt/hostfs.
	# From: http://user-mode-linux.sourceforge.net/hostfs.html
	# FIXME: this could be also moved to vnumlize.sh, solving the problem
	# of how to get $hostfs_dir in that script
	my $hostfs_dir = $dh->get_hostfs_dir($vm_name);
	$execution->execute( "mount none /mnt/hostfs -t hostfs -o $hostfs_dir",
		*CONFILE );
	$execution->execute( "if [ \$? != 0 ]",                     *CONFILE );
	$execution->execute( "then",                                *CONFILE );
	$execution->execute( "   mount none /mnt/hostfs -t hostfs", *CONFILE );
	$execution->execute( "fi",                                  *CONFILE );

	# 10. To call the plugin configuration script
	$execution->execute( "\$UTILDIR/plugins_conf.sh", *CONFILE );

	# 11. send message to /proc/mconsole to notify host that init has started
	$execution->execute( "echo init_start > /proc/mconsole", *CONFILE );

	# 12. create groups, users, and install appropriate public keys
	$execution->execute( "function add_groups() {", *CONFILE );
	$execution->execute( "   while read group; do", *CONFILE );
	$execution->execute(
		"      if ! grep \"^\$group:\" /etc/group > /dev/null 2>&1; then",
		*CONFILE );
	$execution->execute( "         groupadd \$group",           *CONFILE );
	$execution->execute( "      fi",                            *CONFILE );
	$execution->execute( "   done<\$groups_file",               *CONFILE );
	$execution->execute( "}",                                   *CONFILE );
	$execution->execute( "function add_keys() {",               *CONFILE );
	$execution->execute( "   eval homedir=~\$1",                *CONFILE );
	$execution->execute( "   if ! [ -d \$homedir/.ssh ]; then", *CONFILE );
	$execution->execute( "      su -pc \"mkdir -p \$homedir/.ssh\" \$1",
		*CONFILE );
	$execution->execute( "      chmod 700 \$homedir/.ssh", *CONFILE );
	$execution->execute( "   fi",                          *CONFILE );
	$execution->execute( "   if ! [ -f \$homedir/.ssh/authorized_keys ]; then",
		*CONFILE );
	$execution->execute(
		"      su -pc \"touch \$homedir/.ssh/authorized_keys\" \$1", *CONFILE );
	$execution->execute( "   fi",                 *CONFILE );
	$execution->execute( "   while read key; do", *CONFILE );
	$execution->execute(
"      if ! grep \"\$key\" \$homedir/.ssh/authorized_keys > /dev/null 2>&1; then",
		*CONFILE
	);
	$execution->execute(
		"         echo \$key >> \$homedir/.ssh/authorized_keys", *CONFILE );
	$execution->execute( "      fi",       *CONFILE );
	$execution->execute( "   done<\$file", *CONFILE );
	$execution->execute( "}",              *CONFILE );
	$execution->execute( "for file in `ls \$UTILDIR/group_* 2> /dev/null`; do",
		*CONFILE );
	$execution->execute( "   options=",                         *CONFILE );
	$execution->execute( "   myuser=\${file#\$UTILDIR/group_}", *CONFILE );
	$execution->execute(
		"   if [ \"\$myuser\" == \"root\" ]; then continue; fi", *CONFILE );
	$execution->execute( "   groups_file = `sed \"s/^\\*//\" \$file` ",
		*CONFILE );
	$execution->execute( "   add_groups", *CONFILE );
	$execution->execute( "   if effective_group=`grep \"^\\*\" \$file`; then",
		*CONFILE );
	$execution->execute(
		"      options=\"\$options -g \${effective_group#\\*}\"", *CONFILE );
	$execution->execute( "   fi", *CONFILE );
	$execution->execute(
		"   other_groups=`sed '/^*/d;H;\$!d;g;y/\\n/,/' \$file`", *CONFILE );
	$execution->execute(
		"   if grep \"^\$myuser:\" /etc/passwd > /dev/null 2>&1; then",
		*CONFILE );
	$execution->execute(
"      other_groups=\"-G `su -pc groups \$myuser | sed 's/[[:space:]]\\+/,/g'`\$other_groups\"",
		*CONFILE
	);
	$execution->execute(
		"      usermod \$options \$initial_groups\$other_groups \$myuser",
		*CONFILE );
	$execution->execute( "   else", *CONFILE );
	$execution->execute(
"      if [ \"\$other_groups\" != \"\" ]; then other_groups=\"-G \${other_groups#,}\"; fi",
		*CONFILE
	);
	$execution->execute( "      useradd -m \$options \$other_groups \$myuser",
		*CONFILE );
	$execution->execute( "   fi", *CONFILE );
	$execution->execute( "done",  *CONFILE );
	$execution->execute(
		"for file in `ls \$UTILDIR/keyring_* 2> /dev/null`; do", *CONFILE );
	$execution->execute( "   add_keys \${file#\$UTILDIR/keyring_} < \$file",
		*CONFILE );
	$execution->execute( "done", *CONFILE );

	# Close file and restore prompting method
	$execution->set_verb_prompt($verb_prompt_bk);
	close CONFILE unless ( $execution->get_exe_mode() eq EXE_DEBUG );

	# To configure management device (id 0), if needed
	if ( $dh->get_vmmgmt_type eq 'private' && $mng_if_value ne "no" ) {
		my $net = &get_admin_address( $number, $dh->get_vmmgmt_type, 1 );
		$execution->execute( $bd->get_binaries_path_ref->{"ifconfig"}
			  . " $vm_name-e0 "
			  . $net->addr()
			  . " netmask "
			  . $net->mask()
			  . " up" );
	}

	# Boot file will be executable
	$execution->execute(
		$bd->get_binaries_path_ref->{"chmod"} . " a+x $path" . "umlboot" );

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
	  unless ( $execution->get_exe_mode() eq EXE_DEBUG );
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
	close CONFILE unless ( $execution->get_exe_mode() eq EXE_DEBUG );

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
sub exec_command_host {

	my $self = shift;
	my $seq  = shift;
#	$execution = shift;
#	$bd        = shift;
#	$dh        = shift;
	

	my $doc = $dh->get_doc;

	# If host <host> is not present, there is nothing to do
	return if ( $doc->getElementsByTagName("host")->getLength eq 0 );

	# To get <host> tag
	my $host = $doc->getElementsByTagName("host")->item(0);

	# To process exec tags of matching commands sequence
	my $command_list = $host->getElementsByTagName("exec");

	# To process list, dumping commands to file
	for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
		my $command = $command_list->item($j);

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
#
sub check_mconsole_exec_capabilities {
	my $vm = shift;

	my $name = $vm->getAttribute("name");

	# Checking the kernel
	my $kernel_check = 0;
	my $kernel       = $dh->get_default_kernel;
	my $kernel_list  = $vm->getElementsByTagName("kernel");
	if ( $kernel_list->getLength > 0 ) {
		$kernel = &text_tag( $kernel_list->item(0) );

	}

	my $grep   = $bd->get_binaries_path_ref->{"grep"};
	my $result = `$kernel --showconfig | $grep MCONSOLE_EXEC`;

	if ( $result =~ /^CONFIG_MCONSOLE_EXEC=y$/ ) {
		$kernel_check = 1;

	}
	$kernel_check = 1;

	# Checking the uml_mconsole command
	my $mconsole_check = 0;
	my $mconsole       = $dh->get_run_dir($name) . "/mconsole";

	if ( -S $mconsole ) {

		my $grep         = $bd->get_binaries_path_ref->{"grep"};
		my $uml_mconsole = $bd->get_binaries_path_ref->{"uml_mconsole"};
		my $result = `$uml_mconsole $mconsole help 2> /dev/null | $grep exec`;
		if ( $result ne "" ) {

			$mconsole_check = 1;
		}
	}
	else {
		print "VNX warning: $mconsole socket does not exist\n";

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
	$execution->execute(
		$bd->get_binaries_path_ref->{"chmod"} . " 777 $cmd_file_host" );
	$execution->execute_mconsole( $mconsole, "$cmd_file_vm" );

	# Clean up
	$execution->execute(
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
	$execution->execute(
		$bd->get_binaries_path_ref->{"chmod"} . " 777 $cmd_file_host" );
	$execution->execute_mconsole( $mconsole, "$cmd_file_vm" );

	# Clean up
	$execution->execute(
		$bd->get_binaries_path_ref->{"rm"} . " -f $cmd_file_host" );

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



###################################################################
# Clean up listen socket
sub UML_notify_cleanup {
	my $sock = shift;
	my $notify_ctl = shift;

	close($sock);
	unlink $notify_ctl;
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

