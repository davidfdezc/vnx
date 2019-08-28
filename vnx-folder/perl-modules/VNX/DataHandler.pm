# DataHandler.pm
#
# This file is a module part of VNX package.
#
# Author: Fermin Galan Marquez (galan@dit.upm.es), David Fernández (david@dit.upm.es)
# Copyright (C) 2011,2016 	DIT-UPM
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

# DataHandler class implementation. The instance of DataHandler encapsulates 
# the XML DOM and other static data, providing a interface for date access to the 
# main program.

package VNX::DataHandler;

use strict;
use warnings;

use VNX::TextManipulation;
use VNX::DocumentChecks;
use VNX::FileChecks;
use VNX::Execution;
use VNX::Globals;

###########################################################################
# CLASS CONSTRUCTOR
#
# Arguments (apart from the firts one, the class itseft)
#
# - The Execution object reference
# - the XML DOM object reference
# - mode (create|x|d|P)
# - list of comma separated machine targets of the actions (usually, the opt_M in the main 
#   program). It may be an empty string (when no opt_M is used), meaning all the machines
# - command secuence used in mode -x. Other modes, it does not used (empty string)
# - the name of the input file
# 
sub new {
   my $class = shift;
   my $self = {};
   bless $self;
   
   $self->{'execution'} = shift;
   $self->{'doc'} = shift;
   $self->{'mode'} = shift;
   $self->{'vm_to_use'} = shift;
   $self->{'host_to_use'} = shift;
   $self->{'cmd_seq'} = shift;
   $self->{'xml_dir'} = shift;
   $self->{'input_file'} = shift;
   $self->{'cfg_file'} = shift;
   
   # Build static data array
   my %global_data;
   
   # 1. Fields that live under <vm_defaults>
   my @vm_defaults_list = $self->{'doc'}->getElementsByTagName("vm_defaults");
   my $no_filesystem = 1;
   my $no_mem = 1;
   my $no_kernel = 1;
   my $no_shell = 1;
   my $no_basedir = 1;
   my $no_mgn_if = 1;
   my $no_xterm = 1;
   #my $no_forwarding = 1;
   if (@vm_defaults_list == 1) {
   
#      my @filesystem_list = $vm_defaults_list[0]->getElementsByTagName("filesystem");
#      if (@filesystem_list == 1) {
#         $global_data{'default_filesystem'} = &do_path_expansion(&text_tag($filesystem_list[0]));;
#         $global_data{'default_filesystem_type'} = $filesystem_list[0]->getAttribute("type");
#         $no_filesystem = 0;
#      }

    my $countcommand = 0;
    foreach my $command ($vm_defaults_list[0]->getElementsByTagName("filesystem")) {       
          my $merged_type = $self->get_vm_merged_type($command);
          my $filesystem_value = &text_tag($command);
          $global_data{"default_filesystem-$merged_type"} =$filesystem_value;
          wlog (VVV, "default exec_mode for vm type $merged_type set to $filesystem_value");
    } 
      
    my @default_mem_list = $vm_defaults_list[0]->getElementsByTagName("mem");
    if (@default_mem_list == 1) {
         $global_data{'default_mem'} = &text_tag($default_mem_list[0]);;
         $no_mem = 0;
    }
      
    my @kernel_list = $vm_defaults_list[0]->getElementsByTagName("kernel");
    if (@kernel_list == 1) {
         $global_data{'default_kernel'} = &do_path_expansion(&text_tag($kernel_list[0]));
         $global_data{'default_initrd'} = &do_path_expansion($kernel_list[0]->getAttribute("initrd"));
         $global_data{'default_devfs'} = $kernel_list[0]->getAttribute("devfs");
         $global_data{'default_root'} = &do_path_expansion($kernel_list[0]->getAttribute("root"));
         $global_data{'default_modules'} = &do_path_expansion($kernel_list[0]->getAttribute("modules"));
         $global_data{'default_trace'} = $kernel_list[0]->getAttribute("trace");
         $no_kernel = 0;
    }
      
    my @shell_list = $vm_defaults_list[0]->getElementsByTagName("shell");
    if (@shell_list == 1) {
         $global_data{'default_shell'} = &do_path_expansion(&text_tag($shell_list[0]));
         $no_shell = 0;
    }

    my @basedir_list = $vm_defaults_list[0]->getElementsByTagName("basedir");
    if (@basedir_list == 1) {
         $global_data{'default_basedir'} = &do_path_expansion(&text_tag($basedir_list[0]));
         $no_basedir = 0;
    }
      
    my @mng_if_list = $vm_defaults_list[0]->getElementsByTagName("mng_if");
    if (@mng_if_list == 1) {
         $global_data{'default_mng_if'} = &text_tag($mng_if_list[0]);
         $no_mgn_if = 0;
    }
      
    my @xterm_list = $vm_defaults_list[0]->getElementsByTagName("xterm");
    if (@xterm_list == 1) {
         $global_data{'default_xterm'} = &text_tag($xterm_list[0]);
         $no_xterm = 0;
    }

    $global_data{'default_forwarding_ipv4'} = 'no';            
    $global_data{'default_forwarding_ipv6'} = 'no';            
    foreach my $forwarding ($vm_defaults_list[0]->getElementsByTagName("forwarding")) {       
        if ( $forwarding->getAttribute("type") eq 'ip' or $forwarding->getAttribute("type") eq 'ipv4' ) {
            $global_data{'default_forwarding_ipv4'} = 'yes'; 
        }       
        if ( $forwarding->getAttribute("type") eq 'ipv6' ) {
            $global_data{'default_forwarding_ipv6'} = 'yes';                     
        }            
    }
#      my @forwarding_list = $vm_defaults_list[0]->getElementsByTagName("forwarding");
#      if (@forwarding_list == 1) {
#         $global_data{'default_forwarding_type'} = $forwarding_list[0]->getAttribute("type");
#         $no_forwarding = 0;
#      }
      

#      if ($vm_defaults_list->item(0)->getAttribute("exec_mode") ne "") {
#         $global_data{'default_exec_mode'} = $vm_defaults_list->item(0)->getAttribute("exec_mode");
#      }
#      else {
#          #$global_data{'default_exec_mode'} = "net";
#         $global_data{'default_exec_mode'} = "cdrom";
#      }

      $countcommand = 0;
      foreach my $command ($vm_defaults_list[0]->getElementsByTagName("exec_mode")) {      	
          my $merged_type = $self->get_vm_merged_type($command);
          my $execmode_value = &text_tag($command);
          $global_data{"default_exec_mode-$merged_type"} =$execmode_value;
          wlog (VVV, "default exec_mode for vm type $merged_type set to $execmode_value");
      } 
            
   }
   
   if ($no_filesystem) {
   	  $global_data{'default_filesystem'} = &do_path_expansion("/usr/share/vnx/filesystems/root_fs_tutorial");
      $global_data{'default_filesystem_type'} = "cow";
   }
   if ($no_mem) {
      $global_data{'default_mem'} = "256M";
   }
   if ($no_kernel) {
      $global_data{'default_kernel'} = &do_path_expansion("/usr/share/vnx/kernels/linux");
      $global_data{'default_initrd'} = '';
      $global_data{'default_devfs'} = '';
      $global_data{'default_root'} = '';
      $global_data{'default_modules'} = '';
      $global_data{'default_trace'} = '';
   }
   if ($no_shell) {
      $global_data{'default_shell'} = &do_path_expansion("/bin/bash");      # shell used by the script that vnx generates      
   }  
   if ($no_basedir) {
  	  $global_data{'default_basedir'} = '';
   }
   if ($no_mgn_if) {
      $global_data{'default_mng_if'} = '';
   }
   if ($no_xterm) {
      $global_data{'default_xterm'} = '';
   }
   #if ($no_forwarding) {
   #   $global_data{'default_forwarding_type'} = "";
   #}
   
   # 2. Fields taken from the scenario  

   # scenario's name
   my @scename_list = $self->{'doc'}->getElementsByTagName("scenario_name");
   if (@scename_list == 1) {
      $global_data{'scename'} = &text_tag($scename_list[0]);
   }
   else {
      $self->{'execution'}->smartdie ("<scenario_name> tag is missing or duplicated\n");
   }
  
   # Host mapping
   my @hostmapping_list = $self->{'doc'}->getElementsByTagName("host_mapping");
   if (@hostmapping_list == 1) {
      $global_data{'host_mapping'} = 1;
   }
   else {
 	  $global_data{'host_mapping'} = 0;             # by default, management addresses are not mapped in /etc/hosts
   }

   # Dynamips mapping
   my @dynamipsmapping_list = $self->{'doc'}->getElementsByTagName("dynamips_ext");
   if (@dynamipsmapping_list == 1) {
      $global_data{'dynamips_ext'} =  &text_tag($dynamipsmapping_list[0]);
   }
   else {
 	  $global_data{'dynamips_ext'} = 0;             
   }
   
   # Olive mapping
   my @olivemapping_list = $self->{'doc'}->getElementsByTagName("olive_ext");
   if (@olivemapping_list == 1) {
      $global_data{'olive_ext'} =  &text_tag($olivemapping_list[0]);
   }
   else {
 	  $global_data{'olive_ext'} = 0;             
   }

   # Network configuration options, if <netconfig> is present
   my @netconfig_list = $self->{'doc'}->getElementsByTagName("netconfig");
   if (@netconfig_list == 1) {
      ($global_data{'stp'},$global_data{'promisc'}) = &netconfig($self, $netconfig_list[0]);
   }
   else {
   	  $global_data{'promisc'} = "promisc";          # by default, interfaces are set up in promiscous mode
      $global_data{'stp'} = 0;		                # STP configuration in the bridges. By default is not set   
   }

   # VM management configuration options, if <vm_mgmt> is present
   $global_data{'vmmgmt_type'} = 'private';
   $global_data{'vmmgmt_net'} = '192.168.0.0';
   $global_data{'vmmgmt_mask'} = '24';
   $global_data{'vmmgmt_offset'} = '0';
   $global_data{'vmmgmt_netname'} = $global_data{'scename'} . "_Mgmt";
   $global_data{'vmmgmt_hostip'} = '192.168.0.1';
   $global_data{'vmmgmt_autoconfigure'} = '';
   my @vmmgmt_list = $self->{'doc'}->getElementsByTagName("vm_mgmt");
   if (@vmmgmt_list == 1) {
	  my ($type,$net,$mask,$offset,$hostip,$autoconfigure) = &vmmgmt($self, $vmmgmt_list[0]);
	  if (!empty($type)) {
		  $global_data{'vmmgmt_type'} = $type;
	  }
	  if (!empty($net)) {
		  $global_data{'vmmgmt_net'} = $net;
	  }
	  if (!empty($mask)) {
		  $global_data{'vmmgmt_mask'} = $mask;
	  }
	  if (!empty($offset)) {
		  $global_data{'vmmgmt_offset'} = $offset;
	  }
	  if (!empty($hostip)) {
		  $global_data{'vmmgmt_hostip'} = $hostip;
	  }
	  if (!empty($autoconfigure)) {
		  $global_data{'vmmgmt_autoconfigure'} = $autoconfigure;
	  }
   }

   # AutoMAC offset
   $global_data{'automac_offset'} = 0;
   my @automac_list = $self->{'doc'}->getElementsByTagName("automac");
   if (@automac_list == 1) {
      my $att = $automac_list[0]->getAttribute("offset");
      #if ($att =~ /^$/) {
      if (empty($att)) {
         $global_data{'automac_offset'} = 0;
      }
      else {
         $global_data{'automac_offset'} = $att;
      }
   }

   # SSH version, if present
   $global_data{'ssh_version'} = "2";	        # default SSH protocol version is 1}
   my @ssh_version_list = $self->{'doc'}->getElementsByTagName("ssh_version");
   if (@ssh_version_list == 1) {
      $global_data{'ssh_version'} = &text_tag($ssh_version_list[0]);
   }

   # Tun device, if <tun_device> is present
   my @tun_device_list = $self->{'doc'}->getElementsByTagName("tun_device");
   if (@tun_device_list == 1) {
      $global_data{'tun_device'} = &do_path_expansion(&text_tag($tun_device_list[0]));
   }
   else {
      $global_data{'tun_device'} = &do_path_expansion("/dev/net/tun");   # default tun device
   }
   
   # 3. Other fields (constants):
   #$global_data{'max_name_length'} = 7;          # max length for names in <vm> and <net>
   $global_data{'delay'} = 5;		         # reference delay used by vnumlparser (mounting operations and blocks)   

   # 4. Assignement, by reference
   $self->{'global_data'} = \%global_data;  
 
   	# DEBUG: print global_data hash  
   	wlog (VVV, "-- Content of dh->{'global_data'} -----------------------------------------------", "");
	while ( my ($k,$v) = each %global_data ) {
    	wlog (VVV, "$k => $v", "");
	}
   	wlog (VVV, "-- End of content of dh->{'global_data'} ----------------------------------------", "");

   return $self;
}

###########################################################################
# PUBLIC METHODS

######### GET METHODS #########

# get_global_data_ref
#
# Returns the global_data hash reference
#
sub get_global_data_ref {
   my $self = shift;
   return $self->{'global_data'};
} 

# get_doc
#
# Returns the doc object reference
#
sub get_doc {
   my $self = shift;
   return $self->{'doc'};
}

# get_scename
#
# Returns the scename
#
sub get_scename {
   my $self = shift;
   return $self->{'global_data'}->{'scename'};
} 

# get_vnx_dir
#
# Returns the vnx_dir
#
sub get_vnx_dir {
   my $self = shift;
   return $self->{'global_data'}->{'vnx_dir'};
} 

# get_tmp_dir
#
# Returns the tmp_dir
#
sub get_tmp_dir {
   my $self = shift;
   return $self->{'global_data'}->{'tmp_dir'};
} 

# get_tun_device
#
# Returns the tun_device
#
sub get_tun_device {
   my $self = shift;
   return $self->{'global_data'}->{'tun_device'};
}

# get_xml_dir
#
# Returns the directory where the XML of the specification lives
#
sub get_xml_dir {
   my $self = shift;
   return $self->{'xml_dir'};
} 

# get_input_file
#
# Returns the input file name
#
sub get_input_file {
   my $self = shift;
   return $self->{'input_file'};
} 

# get_cfg_file
#
# Returns the input file name
#
sub get_cfg_file {
   my $self = shift;
   return $self->{'cfg_file'};
} 

# get_ssh_version
#
# Returns the ssh_version
#
sub get_ssh_version {
   my $self = shift;
   return $self->{'global_data'}->{'ssh_version'};
} 

# get_delay
#
# Returns the delay
#
sub get_delay {
   my $self = shift;
   return $self->{'global_data'}->{'delay'};
} 

# get_host_mapping
#
# Returns the host_mapping
#
sub get_host_mapping {
   my $self = shift;
   return $self->{'global_data'}->{'host_mapping'};
} 

# get_promisc
#
# Returns the promisc
#
sub get_promisc {
   my $self = shift;
   return $self->{'global_data'}->{'promisc'};
} 

# get_stp
#
# Returns the stp
#
sub get_stp {
   my $self = shift;
   return $self->{'global_data'}->{'stp'};
} 

# get_vmmgmt_type
#
# Returns the vmmgmt_type
#
sub get_vmmgmt_type {
   my $self = shift;
   return $self->{'global_data'}->{'vmmgmt_type'};
} 

# get_vmmgmt_net
#
# Returns the vmmgmt_net
#
sub get_vmmgmt_net {
   my $self = shift;
   return $self->{'global_data'}->{'vmmgmt_net'};
} 

# get_vmmgmt_mask
#
# Returns the vmmgmt_mask
#
sub get_vmmgmt_mask {
   my $self = shift;
   return $self->{'global_data'}->{'vmmgmt_mask'};
} 

# get_vmmgmt_offset
#
# Returns the vmmgmt_offset
#
sub get_vmmgmt_offset {
   my $self = shift;
   return $self->{'global_data'}->{'vmmgmt_offset'};
} 

# get_vmmgmt_netname
#
# Returns the vmmgmt_netname
#
sub get_vmmgmt_netname {
   my $self = shift;
   return $self->{'global_data'}->{'vmmgmt_netname'};
}

# get_vmmgmt_hostip
#
# Returns the vmmgmt_hostip
#
sub get_vmmgmt_hostip {
   my $self = shift;
   return $self->{'global_data'}->{'vmmgmt_hostip'};
}

# get_vmmgmt_autoconfigure
#
# Returns the vmmgmt_autoconfigure
#
sub get_vmmgmt_autoconfigure {
   my $self = shift;
   return $self->{'global_data'}->{'vmmgmt_autoconfigure'};
}

# get_default_filesystem
#
# Returns the default filesystem
#
sub get_default_filesystem {
   my $self = shift;
   return $self->{'global_data'}->{'default_filesystem'};
}

#
# Returns the default filesystem type
#
sub get_default_filesystem_type {
   my $self = shift;
   return $self->{'global_data'}->{'default_filesystem_type'};
} 

# get_default_mem
#
# Returns the default mem
#
sub get_default_mem {
   my $self = shift;
   return $self->{'global_data'}->{'default_mem'};
} 

# get_default_kernel
#
# Returns the default kernel
#
sub get_default_kernel {
   my $self = shift;
   return $self->{'global_data'}->{'default_kernel'};
} 

# get_default_initrd
#
# Returns the default_initrd
#
sub get_default_initrd {
   my $self = shift;
   return $self->{'global_data'}->{'default_initrd'};
} 

# get_default_devfs
#
# Returns the default_devfs
#
sub get_default_devfs {
   my $self = shift;
   return $self->{'global_data'}->{'default_devfs'};
} 

# get_default_root
#
# Returns the default_root
#
sub get_default_root {
   my $self = shift;
   return $self->{'global_data'}->{'default_root'};
} 

# get_default_modules
#
# Returns the default_modules
#
sub get_default_modules {
   my $self = shift;
   return $self->{'global_data'}->{'default_modules'};
} 

# get_default_basedir
#
# Returns the default basedir
#
sub get_default_basedir {
   my $self = shift;
   return $self->{'global_data'}->{'default_basedir'};
}

# get_default_shell
#
# Returns the default shell
#
sub get_default_shell {
   my $self = shift;
   return $self->{'global_data'}->{'default_shell'};
}

# get_default_mng_if
#
# Returns the default mng_if
#
sub get_default_mng_if {
   my $self = shift;
   return $self->{'global_data'}->{'default_mng_if'};
}

# get_default_xterm
#
# Return the default xterm
#
sub get_default_xterm {
   my $self = shift;
   return $self->{'global_data'}->{'default_xterm'};
}

# get_default_dynamips
#
# Return the default dynamips
#
sub get_default_dynamips {
   my $self = shift;
   return $self->{'global_data'}->{'dynamips_ext'};
}

# get_default_olive
#
# Return the default olive
#
sub get_default_olive {
   my $self = shift;
   return $self->{'global_data'}->{'olive_ext'};
}

# get_default_forwarding_ipv4
#
# Returns the default forwarding type
#
sub get_default_forwarding_ipv4 {
   my $self = shift;
   return $self->{'global_data'}->{'default_forwarding_ipv4'};
}

# get_default_forwarding_ipv6
#
# Returns the default forwarding type
#
sub get_default_forwarding_ipv6 {
   my $self = shift;
   return $self->{'global_data'}->{'default_forwarding_ipv6'};
}

####################

###################################################################
# get_vm_filesystem
#
# Arguments:
# - a virtual machine node
#
# Returns the filesystem to be used for a VM. Returns:
# - the value of <filesystem> tag if present on <vm> definition, or 
# - the default value for VMs of that type defined in the <vm_defaults> tag, or
# - the default value for VMs of that type defined in Globals.pm 
#
sub get_vm_filesystem {

    my $self = shift;
    my $vm   = shift;

    my $logp = "get_vm_filesystem> ";

    my $type      = $vm->getAttribute('type');
    my $subtype   = $vm->getAttribute('subtype');   $subtype='' if (!defined($subtype)); 
    my $os        = $vm->getAttribute('os');        $os='' if (!defined($os));
    my $exec_mode = $vm->getAttribute("exec_mode"); $exec_mode='' if (!defined($exec_mode));
    
    wlog (VV, "type=$type, subtype=$subtype, os=$os, exec_mode=$exec_mode", $logp);

    # filesystem tag in dom tree        
    my @filesystem_list = $vm->getElementsByTagName("filesystem");
    my $filesystem;
    my $filesystem_type;
    
    if (@filesystem_list == 1) {
        $filesystem = get_abs_path(text_tag($vm->getElementsByTagName("filesystem")->item(0)));
        $filesystem =~ s/\R//g;  # Just in case it has a break line at the end
        $filesystem_type = $vm->getElementsByTagName("filesystem")->item(0)->getAttribute("type");
    } else {
        ($filesystem, $filesystem_type) = $dh->get_vm_default_filesystem ($type, $subtype, $os);
    }
    return ($filesystem, $filesystem_type);

}

# get_vm_default_filesystem
#
# Returns the default filesystem for a vm of type/subtype/os
# type parameter is mandatory; subtype and os parameters could be empty.
# If subtype is empty, os must also be empty
#
# Examples:
#     $dh->get_default_vm_filesystem ($type)
#     $dh->get_default_vm_filesystem ($type, $subtype)
#     $dh->get_default_vm_filesystem ($type, $subtype, $os)
#
sub get_vm_default_filesystem {

    my $self    = shift;    
    my $type    = shift;
    my $subtype = str(shift);
    my $os      = str(shift);
   
    my $merged_type;
    my $def_execmode;
   
    my $logp = "get_vm_default_filesystem> ";
    wlog (VV, "type=$type, subtype=$subtype, os=$os", $logp);
    
    if (!$type) { return "ERROR\n"; }
    if ( ($os) && (!$subtype) ) { return "ERROR\n"; }

    if ( (!$os) && (!$subtype) ) { # subtype and os empty
        $merged_type = "$type";        
        $def_execmode = $self->{'global_data'}->{"default_filesystem-$type"};
        
    } elsif ( (!$os) && ($subtype) ) { # os empty
        $merged_type = "$type-$subtype";
        $def_execmode = $self->{'global_data'}->{"default_filesystem-$type-$subtype"};
        if (!$def_execmode) { # Look for a default mode for the whole type
            $def_execmode = $self->{'global_data'}->{"default_filesystem-$type"};
        }
    } else { # none empty
        $merged_type = "$type-$subtype-$os";
        $def_execmode = $self->{'global_data'}->{"default_filesystem-$type-$subtype-$os"};
        if (!$def_execmode) { # Look for a default mode for the whole subtype
            $def_execmode = $self->{'global_data'}->{"default_filesystem-$type-$subtype"};
            if (!$def_execmode) { # Look for a default mode for the whole subtype
                $def_execmode = $self->{'global_data'}->{"default_filesystem-$type"};
            }
        } 
    }
    #wlog (VV, "type=$type, def_execmode=$def_execmode", $logp)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   ;

    # If no default found in <filesystem> tags under <vm_defaults>...   
    if (!$def_execmode) {  # ...set the defaults defined in Globals.pm
        wlog (VV, "merged-type=$merged_type", $logp);
        if ($merged_type eq 'uml') {
            $def_execmode = $DEFAUL_FILESYSTEM_UML[0];
            wlog (VV, "type=$type, def_execmode=$def_execmode", $logp);
        } elsif ($merged_type eq 'libvirt-kvm-linux') {
            $def_execmode = $DEFAUL_FILESYSTEM_LIBVIRT_KVM_LINUX[0];
        } elsif ($merged_type eq 'libvirt-kvm-freebsd') {
            $def_execmode = $DEFAUL_FILESYSTEM_LIBVIRT_KVM_FREEBSD[0];
        } elsif ($merged_type eq 'libvirt-kvm-netbsd') {
            $def_execmode = $DEFAUL_FILESYSTEM_LIBVIRT_KVM_NETBSD[0];
        } elsif ($merged_type eq 'libvirt-kvm-openbsd') {
            $def_execmode = $DEFAUL_FILESYSTEM_LIBVIRT_KVM_OPENBSD[0];
        } elsif ($merged_type eq 'libvirt-kvm-windows') {
            $def_execmode = $DEFAUL_FILESYSTEM_LIBVIRT_KVM_WINDOWS[0];
        } elsif ($merged_type eq 'libvirt-kvm-olive') {
            $def_execmode = $DEFAUL_FILESYSTEM_LIBVIRT_KVM_OLIVE[0];
        } elsif ($merged_type eq 'libvirt-kvm-android') {
            $def_execmode = $DEFAUL_FILESYSTEM_LIBVIRT_KVM_ANDROID[0];
        } elsif ($merged_type eq 'libvirt-kvm-wanos') {
            $def_execmode = $DEFAUL_FILESYSTEM_LIBVIRT_KVM_WANOS[0];
        } elsif ( ($merged_type eq 'dynamips-3600') or ($merged_type eq 'dynamips-7200') )  {
            $def_execmode = $DEFAUL_FILESYSTEM_DYNAMIPS[0];
        } elsif ($merged_type eq 'lxc')  {
            $def_execmode = $DEFAUL_FILESYSTEM_LXC[0];
        } else {
            $def_execmode = "ERROR";
        }
    }
    return ($def_execmode, 'cow');
}

#######################


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

    my $self = shift;
    my $vm   = shift;

    my $logp = "get_vm_exec_mode> ";

    my $type      = $vm->getAttribute('type');
    my $subtype   = $vm->getAttribute('subtype');   $subtype='' if (!defined($subtype)); 
    my $os        = $vm->getAttribute('os');        $os='' if (!defined($os));
    my $exec_mode = $vm->getAttribute("exec_mode"); $exec_mode='' if (!defined($exec_mode));
    
    wlog (VV, "type=$type, subtype=$subtype, os=$os, exec_mode=$exec_mode", $logp);
    if ( !empty($vm->getAttribute("exec_mode")) ) {
        return $vm->getAttribute("exec_mode");
    }
    else {
        return $dh->get_default_exec_mode ($type, $vm->getAttribute('subtype'), $vm->getAttribute('os'));
    }

}

# get_default_exec_mode
#
# Returns the default exec mode for a vm of type/subtype/os
# type parameter is mandatory; subtype and os parameters could be empty.
# If subtype is empty, os must also be empty
#
# Examples:
#     $dh->get_default_exec_mode ($type)
#     $dh->get_default_exec_mode ($type, $subtype)
#     $dh->get_default_exec_mode ($type, $subtype, $os)
#
sub get_default_exec_mode {

    my $self    = shift;    
    my $type    = shift;
    my $subtype = str(shift);
    my $os      = str(shift);
   
    my $merged_type;
    my $def_execmode;
   
    my $logp = "get_default_exec_mode> ";
    wlog (VV, "type=$type, subtype=$subtype, os=$os", $logp);
    
    if (!$type) { return "ERROR\n"; }
    if ( ($os) && (!$subtype) ) { return "ERROR\n"; }


    if ( (!$os) && (!$subtype) ) { # subtype and os empty
        $merged_type = "$type";        
        $def_execmode = $self->{'global_data'}->{"default_exec_mode-$type"};
        
    } elsif ( (!$os) && ($subtype) ) { # os empty
        $merged_type = "$type-$subtype";
        $def_execmode = $self->{'global_data'}->{"default_exec_mode-$type-$subtype"};
        if (!$def_execmode) { # Look for a default mode for the whole type
            $def_execmode = $self->{'global_data'}->{"default_exec_mode-$type"};
        }
    } else { # none empty
        $merged_type = "$type-$subtype-$os";
        $def_execmode = $self->{'global_data'}->{"default_exec_mode-$type-$subtype-$os"};
        if (!$def_execmode) { # Look for a default mode for the whole subtype
            $def_execmode = $self->{'global_data'}->{"default_exec_mode-$type-$subtype"};
            if (!$def_execmode) { # Look for a default mode for the whole subtype
                $def_execmode = $self->{'global_data'}->{"default_exec_mode-$type"};
            }
        } 
    }
    #wlog (VV, "type=$type, def_execmode=$def_execmode", $logp)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   ;

    # If no default found in <exec_mode> tags under <vm_defaults>...   
    if (!$def_execmode) {  # ...set the defaults defined in Globals.pm
        wlog (VV, "merged-type=$merged_type", $logp);
        if ($merged_type eq 'uml') {
            $def_execmode = $EXEC_MODES_UML[0];
    		wlog (VV, "type=$type, def_execmode=$def_execmode", $logp);
        } elsif ($merged_type eq 'libvirt-kvm-linux') {
            $def_execmode = $EXEC_MODES_LIBVIRT_KVM_LINUX[0];
        } elsif ($merged_type eq 'libvirt-kvm-freebsd') {
            $def_execmode = $EXEC_MODES_LIBVIRT_KVM_FREEBSD[0];
        } elsif ($merged_type eq 'libvirt-kvm-netbsd') {
            $def_execmode = $EXEC_MODES_LIBVIRT_KVM_NETBSD[0];
        } elsif ($merged_type eq 'libvirt-kvm-openbsd') {
            $def_execmode = $EXEC_MODES_LIBVIRT_KVM_OPENBSD[0];
        } elsif ($merged_type eq 'libvirt-kvm-windows') {
            $def_execmode = $EXEC_MODES_LIBVIRT_KVM_WINDOWS[0];
        } elsif ($merged_type eq 'libvirt-kvm-olive') {
            $def_execmode = $EXEC_MODES_LIBVIRT_KVM_OLIVE[0];
        } elsif ($merged_type eq 'libvirt-kvm-android') {
            $def_execmode = $EXEC_MODES_LIBVIRT_KVM_ANDROID[0];
        } elsif ($merged_type eq 'libvirt-kvm-wanos') {
            $def_execmode = $EXEC_MODES_LIBVIRT_KVM_WANOS[0];
        } elsif ( ($merged_type eq 'dynamips-3600') or ($merged_type eq 'dynamips-7200') )  {
            $def_execmode = $EXEC_MODES_DYNAMIPS[0];
        } elsif ($merged_type eq 'lxc')  {
            $def_execmode = $EXEC_MODES_LXC[0];
        } else {
        	$def_execmode = "ERROR";
        }
    }
    return $def_execmode;
}

# get_default_ostype
#
# Returns the default ostype for a given VM merged type
#
sub get_default_ostype {

    my $self    = shift;    
    my $merged_type = shift;

    my $ostype;

    if ($merged_type eq 'uml') {
        $ostype = $EXEC_OSTYPE_UML[0];
    } elsif ($merged_type eq 'libvirt-kvm-linux') {
        $ostype = $EXEC_OSTYPE_LIBVIRT_KVM_LINUX[0];
    } elsif ($merged_type eq 'libvirt-kvm-freebsd') {
        $ostype = $EXEC_OSTYPE_LIBVIRT_KVM_FREEBSD[0];
    } elsif ($merged_type eq 'libvirt-kvm-netbsd') {
        $ostype = $EXEC_OSTYPE_LIBVIRT_KVM_NETBSD[0];
    } elsif ($merged_type eq 'libvirt-kvm-openbsd') {
        $ostype = $EXEC_OSTYPE_LIBVIRT_KVM_OPENBSD[0];
    } elsif ($merged_type eq 'libvirt-kvm-windows') {
        $ostype = $EXEC_OSTYPE_LIBVIRT_KVM_WINDOWS[0];
    } elsif ($merged_type eq 'libvirt-kvm-olive') {
        $ostype = $EXEC_OSTYPE_LIBVIRT_KVM_OLIVE[0];
    } elsif ( ($merged_type eq 'dynamips-3600') or ($merged_type eq 'dynamips-7200') )  {
        $ostype = $EXEC_OSTYPE_DYNAMIPS[0];
    }
}


# get_default_trace
#
# Returns the default trace
#
sub get_default_trace {
   my $self = shift;
   return $self->{'global_data'}->{'default_trace'};
}

# get_boot_timeout
#
# Returns the boot_timeout
#
sub get_boot_timeout {
   my $self = shift;
   return $self->{'global_data'}->{'boot_timeout'};
} 

# get_automac_offset
#
# Returns the automac_offset
#
sub get_automac_offset {
   my $self = shift;
   return $self->{'global_data'}->{'automac_offset'};
} 

# get_vm_byname
#
# Returns a VM knowing its name 
#
sub get_vm_byname {
    my $self = shift;
    my $vm_name = shift;

    #wlog (VVV, "---- looking for " . $vm_name);

    my $global_doc = $dh->get_doc;
    my @vm_ordered = $dh->get_vm_ordered;
	
    for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
        my $vm = $vm_ordered[$i];
        # We get name attribute
        my $name = $vm->getAttribute("name");
        #wlog (VVV, "----" . $name);
        unless ( $name eq $vm_name ) {
            next;
        }
        #wlog (VVV, "return $name");
        return $vm;
    }
    return "";
}

# get_vm_name
#
# Returns a VM knowing its name 
#
sub get_vm_name {
    my $self = shift;
    my $vm = shift;

    return $vm->getAttribute("name");
}

# get_vm_order
#
# Returns the order of a vm in the scenario
#
# Used mainly by automac fumction to associate always the same 
# mac address to every vm
#
sub get_vm_order {
    my $self = shift;
    my $vm_name = shift;

    my @vm_ordered = $dh->get_vm_ordered;
    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];

		if ( $vm->getAttribute("name") eq $vm_name ) {
			return $i;			
		}
    }
	$self->{'execution'}->smartdie("ERROR in get_vm_ordered, vm $vm_name not found in vm list")   
}

# get_vm_ordered
#
# Returns a list of vm nodes, ordered based on "order" number
#
# TODO check there isn't duplicated order numbers
#
sub get_vm_ordered {
    my $self = shift;

	# The array to be returned at the end
	my @vm_ordered;

	my @vm_list = $self->{'doc'}->getElementsByTagName("vm");
	my %vm_index;

	# Build a index hash
	for (my $i = 0; $i < @vm_list; $i++) {
	 
		my $order = $vm_list[$i]->getAttribute("order");
		
		if (!defined($order)) { 
		#if ($order =~ /^$/) {
			# Empty string
			# Do nothing
		}
		elsif ($order =~ /^\d+$/) {
			# A value
			$vm_index{$order} = $i;
		}
		else {
			my $name = $vm_list[$i]->getAttribute("name");
            $self->{'execution'}->smartdie("vm $name has invalid order string: $order");
      }
  }
  
  # The first machines in the list are the ones with "order" attribute
  foreach (sort numerically keys %vm_index) {
     @vm_ordered = (@vm_ordered, $vm_list[$vm_index{$_}]);
  }
   
  # Finally, add machines without order, in the same order they appear in the VNX file
  for (my $i = 0; $i < @vm_list; $i++) {
     my $order = $vm_list[$i]->getAttribute("order");
     if (!defined($order)) { 
     #if ($order =~ /^$/) {
        # Empty string
        @vm_ordered = (@vm_ordered, $vm_list[$i]);	
     }
  }

  return @vm_ordered;

}

#
# get_vm_to_use_ordered
#
# Returns a hash with the vm names of the scenario to be used for each mode having 
# into account -M option (does not take into account -H option of EDIV) 
#
# Arguments:
#
# - plugins array (in order to invoke the execVmsToUse method that provide the vms for which the
#   plugin has to execute actions)
#
# Returns:
# - @vms_ordered
#
sub get_vm_to_use_ordered {
    
    my $self = shift;
    #my @plugins = @_;
   
    # The array to be returned at the end
    my @vms_ordered;
    
    my @vms = $self->get_vm_ordered;
    for ( my $i = 0; $i < @vms; $i++) {
        my $name = $vms[$i]->getAttribute("name");

        if ($self->{'vm_to_use'}) { # VNX has been invoked with option -M
                                    # Only select the vm if its name is on 
                                    # the comma separated list after "-M" 
            my $vm_list = $self->{'vm_to_use'};
            if ($vm_list =~ /^$name,|,$name,|,$name$|^$name$/) {
                push (@vms_ordered, $vms[$i]);
            }
        } else { # No -M option, always select the vm
            push (@vms_ordered, $vms[$i]);
        }
    }
    return @vms_ordered;
}

#
# host_in_M_option 
#
# Returns 'true':
# - if the -M option is selected and the 'host' is included in the list
# - if the -M option is not selected
# Returns undefined otherwise 
#
sub host_in_M_option {
       
    my $self = shift;
       
    if ($self->{'vm_to_use'}) {  # VNX has been invoked with option -M
        if ($self->{'vm_to_use'} =~ /^host,|,host,|,host$|^host$/) {
            return 'true'
        } else {
            return
        }
    } else {
        return 'true'    
    }
}


# get_vm_to_use
#
# Returns a hash with the vm names of the scenario to be used for each mode. 
# For all modes except "execution", it returns all the vms defined in the VNX 
# source file, except when the -M switch is in use.
#
#  my @vm_ordered = $dh->get_vm_ordered;
#  my %vm_hash = $dh->get_vm_to_use;
#  for ( my $i = 0; $i < @vm_ordered; $i++) {
#      my $vm = $vm_ordered[$i];
#      my $vm_name = $vm->getAttribute("name");
#      unless ($vm_hash{$vm_name}){
#         next;       
#      }
#      ...
#  }
# Arguments:
#
# - plugins array (in order to invoke the execVmsToUse method that provide the vms for which the
#   plugin has to execute actions)
#
sub get_vm_to_use {
    
    my $self = shift;
    #my @plugins = @_;
   
    # The hash to be returned at the end
    my %vm_hash;

#    # Build a hash with the vms that the plugins need
#    my %plugins_vms;
#    foreach my $plugin (@plugins) {
#        my @vms = $plugin->execVmsToUse($self->{'cmd_seq'});
#        foreach (@vms) {
#            $plugins_vms{$_} = 1;
#        }
#    }

    my @vms = $self->get_vm_ordered;
    for ( my $i = 0; $i < @vms; $i++) {
        my $vm = $vms[$i];

        # To get name attribute
        my $name = $vm->getAttribute("name");

=BEGIN
        # Include only if have commands to execute or filetree to install (in -x modes); other modes (-t and -d) always
        if ( ($self->{'mode'} eq "create") ||
	         ($self->{'mode'} eq "shutdown") ||
	         ($self->{'mode'} eq "destroy") ||
	         ($self->{'mode'} eq "define") ||
	         ($self->{'mode'} eq "start") ||
	         ($self->{'mode'} eq "reset") ||
	         ($self->{'mode'} eq "reboot") ||
	         ($self->{'mode'} eq "save") ||
	         ($self->{'mode'} eq "restore") ||
	         ($self->{'mode'} eq "suspend") ||
	         ($self->{'mode'} eq "resume") ||
	         ($self->{'mode'} eq "undefine") ||
	         ($self->{'mode'} eq "console") ||
	         ($self->{'mode'} eq "console-info") ||
             (((&vm_has_tag($vm,"exec",$self->{'cmd_seq'})) || 
             (&vm_has_tag($vm,"filetree",$self->{'cmd_seq'})) || 
             (exists $plugins_vms{$name} && $plugins_vms{$name} eq "1") ) && ($self->{'mode'} eq "execute") || 
             (exists $plugins_vms{$name} && $plugins_vms{$name} eq "1")  && ($self->{'mode'} eq "execute") )  
	  ) {
=END
=cut
         if ($self->{'vm_to_use'}) { # VNX has been invoked with option -M
                                     # Only select the vm if its name is on 
                                     # the comma separated list after "-M" 
            my $vm_list = $self->{'vm_to_use'};
            if ($vm_list =~ /^$name,|,$name,|,$name$|^$name$/) {
               $vm_hash{$name} = 1;
            }
         } else { # No -M option, always select the vm
            $vm_hash{$name} = "1";
         }
      }
#   }
   return %vm_hash;


# En proceso de construccion, hay que quitar los plugins en caso de que %plugins_vms no tenga nada.
#	     if (
#          ($self->{'mode'} eq "create") ||
#	      ($self->{'mode'} eq "shutdown") ||
#	      ($self->{'mode'} eq "destroy") ||
#	      ($self->{'mode'} eq "define") ||
#	      ($self->{'mode'} eq "start") ||
#	      ($self->{'mode'} eq "reset") ||
#	      ($self->{'mode'} eq "reboot") ||
#	      ($self->{'mode'} eq "save") ||
#	      ($self->{'mode'} eq "restore") ||
#	      ($self->{'mode'} eq "suspend") ||
#	      ($self->{'mode'} eq "resume") ||
#	      ($self->{'mode'} eq "undefine") ||
#          (((&vm_has_tag($vm,"exec",$self->{'cmd_seq'})) || (&vm_has_tag($vm,"filetree",$self->{'cmd_seq'})) || 
#          			((scalar(%plugins_vms) ge 0) && (($plugins_vms{$name} eq "1") && ($self->{'mode'} eq "execute") || ($plugins_vms{$name} eq "1")  && ($self->{'mode'} eq "execute") ))  
#	  ) {

}

######### SET METHODS #########

# set_boot_timeout
#
# Set the boot_timeout
#
sub set_boot_timeout {
   my $self = shift;
   my $boot_timeout = shift;
   $self->{'global_data'}->{'boot_timeout'} = $boot_timeout;
} 

# set_vnuml_dir
#
# Set the vnuml_dir
#
sub set_vnx_dir {
   my $self = shift;
   my $vnx_dir = shift;
   $self->{'global_data'}->{'vnx_dir'} = $vnx_dir;
} 

# set_tmp_dir
#
# Set the tmp_dir
#
sub set_tmp_dir {
   my $self = shift;
   my $tmp_dir = shift;
   $self->{'global_data'}->{'tmp_dir'} = $tmp_dir;
} 

######### OTHER METHODS #########   

# get_sim_dir
#
# Returns the scenario directory
#
sub get_sim_dir {
   my $self = shift;
   return $self->get_vnx_dir . "/scenarios/" . $self->get_scename;
}

# get_sim_tmp_dir
#
# Returns the scenario directory
#
sub get_sim_tmp_dir {
   my $self = shift;
   return $self->get_vnx_dir . "/scenarios/" . $self->get_scename . "/tmp";
}

# get_global_run_dir
#
# Returns the directory containing the run time files for a scenario
#
sub get_global_run_dir {
   my $self = shift;
   return $self->get_sim_dir . "/run";
}

# get_networks_dir
#
# Returns the networks directory
#
sub get_networks_dir {
   my $self = shift;
   return $self->get_vnx_dir . "/networks";
}

# get_vm_dir
#
# Returns the directory containing vm-specific runtime files
#
sub get_vm_dir {
   my $self = shift;
   my $name = shift;
   if (defined($name)) {
	   return $self->get_sim_dir . "/vms/$name";
   } else {
	   return $self->get_sim_dir . "/vms";
   }
}

# get_vm_fs_dir
#
# Arguments:
#
# - the name of the vm
#
# Returns the directory containing the filesystems for a particular vm
#
sub get_vm_fs_dir {
   my $self = shift;
   my $name = shift;
   return $self->get_vm_dir($name) . "/fs";
}

# get_vm_fs_dir_ontmp
#
# Arguments:
#
# - the name of the vm
#
# Returns the directory containing the filesystems for a particular vm when using --vmfs-tmp option
#
sub get_vm_fs_dir_ontmp {
   my $self = shift;
   my $name = shift;
   return $self->get_tmp_dir() . "/.vnx/" . $self->get_scename . "/vms/" . $name . "/fs";
}

# get_vm_hostfs_dir
#
# Arguments:
#
# - the name of the vm
#
# Returns the hostfs mounting point (in the host) for a particular vm
#
sub get_vm_hostfs_dir {
   my $self = shift;
   my $name = shift;
   return $self->get_vm_dir($name) . "/hostfs";
}

# get_vm_run_dir
#
# Arguments:
#
# - the name of the vm
#
# Returns the directory containing the pid and mconsole socket for a particular vm
#
sub get_vm_run_dir {
   my $self = shift;
   my $name = shift;
   return $self->get_vm_dir($name) . "/run";
}

# get_vm_mnt_dir
#
# Arguments:
#
# - the name of the vm
#
# Returns the directory used to mount shared disks for a particular vm
#
sub get_vm_mnt_dir {
   my $self = shift;
   my $name = shift;
   return $self->get_vm_dir($name) . "/mnt";
}

# get_vm_tmp_dir
#
# Arguments:
#
# - the name of the vm
#
# Returns the temporary directory of a particular vm
#
sub get_vm_tmp_dir {
   my $self = shift;
   my $name = shift;
   return $self->get_vm_dir($name) . "/tmp";
}


# get_vm_doc
#
# Arguments:
#
# - the name of the vm
# - the format: dom or txt 
#
# Returns the content of the XML file with the <create_conf> tag created by make_vm_API_doc for a particular vm
# in DOM tree or XML textual format 
#
sub get_vm_doc {

    my $self  = shift;
    my $name  = shift;
    my $format = shift;
    my $vm_doc;
    
    my $file = $self->get_vm_dir($name) . "/${name}_conf.xml";

    if ($format eq 'txt') {
	    open FILE, "< $file";
	    $vm_doc = do { local $/; <FILE> };
	    close FILE;
    } else {
        $vm_doc = XML::LibXML->new()->parse_file($file);
    }
    return $vm_doc;
}

# get_vm_doctxt
#
# Arguments:
#
# - the name of the vm
#
# Returns the content of the XML file with the <create_conf> tag created by make_vm_API_doc for a particular vm
# in XML textual format
#
#sub get_vm_doctxt {
#   	my $self = shift;
#   	my $name = shift;
#   	my $file = $self->get_vm_dir($name) . "/${name}_conf.xml";
#   	#print "*** file=$file\n";
#   	open FILE, "< $file";
#	my $vm_doc = do { local $/; <FILE> };
#	close FILE;
#	return $vm_doc;
#}


###########################################################################
# OTHERS

# enable_ipv6
#
sub enable_ipv6 {
   my $self = shift;
   $self->{'ipv6_enabled'} = shift;
}

# enable_ipv4
#
sub enable_ipv4 {
   my $self = shift;
   $self->{'ipv4_enabled'} = shift;
}

# is_ipv6_enabled
#
sub is_ipv6_enabled {
   my $self = shift;
   return $self->{'ipv6_enabled'};
}

# is_ipv4_enabled
#
sub is_ipv4_enabled {
   my $self = shift;
   return $self->{'ipv4_enabled'};
}

# check_tag_attribute
#
# Return the number of occurrences of the attribute in the second argument
# in the tag of the first argument. Note that 0 is returned if no match
# is found
#
sub check_tag_attribute {

	my $self = shift;
	my $tag = shift;
	my $attribute = shift;
	my $matches = 0;

	my $doc = $self->{'doc'};

   	# To get list of defined tags
	foreach my $tag ($doc->getElementsByTagName($tag)) {

      # To try getting attribute
		my $attribute_value = $tag->getAttribute($attribute);

        unless (empty($attribute_value)) {
			$matches++;
		}

	}

	return $matches;

}

# merge_console
#
# Returns a list of <console> nodes, merging the ones of the virtual
# machine passed as argument and the ones (if any) in <vm_defaults>.
#
# Overriding criterium: equal id attribute.
#
sub merge_console {

    my $self = shift;
	my $vm = shift;
	my @list = ();
   
	# First, add from vm_defaults
	my @vm_defaults_list = $self->{'doc'}->getElementsByTagName("vm_defaults");
	if (@vm_defaults_list == 1) {
      	foreach my $console ($vm_defaults_list[0]->getElementsByTagName("console")) {
			my $id = $console->getAttribute("id");
			unless (&console_in_vm($self,$vm,$id)) {
				push (@list, $console);
			}
		}
	}
   
	# Second, add from the vm
    foreach my $console ($vm->getElementsByTagName("console")) {		
		push (@list, $console);
	}
   
	return @list;
}

# merge_route
#
# Returns a list of <route> nodes, merging the ones of the virtual
# machine passed as argument and the ones (if any) in <vm_defaults>.
#
# Overriding criterium: equal type attribute and and tag value
#
sub merge_route {

    my $self = shift;
    my $vm = shift;
    my @list = ();
   
    # First, add from vm_defaults
    my @vm_defaults_list = $self->{'doc'}->getElementsByTagName("vm_defaults");
    if (@vm_defaults_list == 1) {
        my $route_list = $vm_defaults_list[0]->getElementsByTagName("route");
        foreach my $route ( $vm_defaults_list[0]->getElementsByTagName("route") ) {
            my $route_type = $route->getAttribute("type");
            my $route_dest = &text_tag($route);
            unless (&route_in_vm($self,$vm,$route_type,$route_dest)) {
                push (@list, $route);
            }
        }
    }
   
    # Second, add from the vm
    foreach my $route ( $vm->getElementsByTagName("route") ) {	    	
        push (@list, $route);
    }
   
    return @list;
}

# merge_user
#
# Returns a list of <user> nodes, merging the ones of the virtual
# machine passed as argument and the ones (if any) in <vm_defaults>.
#
# Overriding criterium: equal username attribute
#
sub merge_user {

    my $self = shift;
    my $vm = shift;
    my @list = ();
   
    # First, add from vm_defaults
    my @vm_defaults_list = $self->{'doc'}->getElementsByTagName("vm_defaults");
    if (@vm_defaults_list == 1) {
        foreach my $user ($vm_defaults_list[0]->getElementsByTagName("user")) { 
            my $username = $user->getAttribute("username");
            unless (&user_in_vm($self,$vm,$username)) {
                push (@list, $user);
            }
        }
    }
   
    # Second, add from the vm
    foreach my $user ($vm->getElementsByTagName("user")) { 
        push (@list, $user);
    }
   
    return @list;
}

# merge_filetree
#
# Returns a list of <filetree> nodes, merging the ones of the virtual
# machine passed as argument and the ones (if any) in <vm_defaults>.
#
# Overriding criterium: equal root and when attributes and tag value
# (after chompslash)
#
sub merge_filetree {

    my $self = shift;
    my $vm = shift;
    my @list = ();
   
    # First, add from vm_defaults
    my @vm_defaults_list = $self->{'doc'}->getElementsByTagName("vm_defaults");
    if (@vm_defaults_list == 1) {
        my $filetree_list = $vm_defaults_list[0]->getElementsByTagName("filetree");
        foreach my $filetree ($vm_defaults_list[0]->getElementsByTagName("filetree")) { 
            my $when = $filetree->getAttribute("seq");
            my $root = $filetree->getAttribute("root");
            my $target = &text_tag($filetree);
            unless (&filetree_in_vm($self,$vm,$when,$root,$target)) {
                push (@list, $filetree);
            }
        }
    }
   
    # Second, add from the vm
    foreach my $filetree ($vm->getElementsByTagName("filetree")) {
        push (@list, $filetree);
    }
   
    return @list;
}

sub merge_shell {
	
    my $self = shift;
    my $vm = shift;

	my $shell      = $dh->get_default_shell;
	my @shell_list = $vm->getElementsByTagName("shell");
	if ( @shell_list == 1 ) {
		$shell = &text_tag( $shell_list[0] );
	}
	return $shell;	
}



###########################################################################
# PRIVATE METHODS (it only must be used from this class itsefl)

# netconfig
#
# This functions uses has argument <netconfig> tag, where
# resides configuration to apply.
#
# Returns a 2 elements list with the stp and promisc values
#
sub netconfig {
   my $self = shift;

   my $net_cfg = shift;
   my $stp = 0;
   my $promisc = "";

   my $stp_att = str($net_cfg->getAttribute("stp"));
   $stp = 1 if ( $stp_att =~ /^on$/ );
   $stp = 0 if ( $stp_att =~ /^off$/ );

   my $promisc_att = str($net_cfg->getAttribute("promisc"));
   $promisc = "promisc" if ( $promisc =~ /^on$/ );
   $promisc = "" if ( $promisc =~ /^off$/ );

   return ($stp, $promisc)

}

# vmmgmt
#
# This function receives the <vm_mgmt> tag as an argument.
#
# Returns a 5-element array with values for vmmgmt_type,
# vmmgmt_network, vmmgmt_mask, vmmgmt_offset, vmmgmt_hostip and
# vmmgmt_autoconfigure
#
sub vmmgmt {
    
    my $self = shift;

    my $vmmgmt = shift;
    my $hostip = '';
    my $autoconfigure = '';

    my @vmmgmt_net_list = $vmmgmt->getElementsByTagName("mgmt_net");
    if (@vmmgmt_net_list > 0) {
        #$hostip = $vmmgmt_net_list[0]->getAttribute("hostip");
        if ( defined($vmmgmt->getAttribute('network')) && defined($vmmgmt->getAttribute('mask'))) {
	        $hostip = NetAddr::IP->new(str($vmmgmt->getAttribute('network'))."/".str($vmmgmt->getAttribute('mask')))  + 1;
	        $hostip = $hostip->addr();
        } else {
            $hostip = '';
        }
        $autoconfigure = $vmmgmt_net_list[0]->getAttribute("autoconfigure");
    }

    return ($vmmgmt->getAttribute('type'),
        $vmmgmt->getAttribute('network'),
        $vmmgmt->getAttribute('mask'),
        $vmmgmt->getAttribute('offset'),
        $hostip,
        $autoconfigure);
}

# console_in_vm
#
# Return true if the <console> (identified by id) is in the <vm>
#
# - vm node
# - id attribute in <console>
#
sub console_in_vm {

    my $self = shift;
    my $vm = shift;
    my $id = shift;
   
    foreach my $console ($vm->getElementsByTagName("console")) {
        if ($console->getAttribute("id") eq $id) {
            return 1;
        }
    }
   
    return 0;
}

# route_in_vm
#
# Return true if the <route> (identified by type and dest) is in the <vm>
#
# - vm node
# - type attribute in <route>
# - destination (value of tag <route>)
#
sub route_in_vm {

    my $self = shift;
    my $vm = shift;
    my $type = shift;
    my $dest = shift;
   
    foreach my $route ($vm->getElementsByTagName("route")) {
        if (($route->getAttribute("type") eq $type) && (&text_tag($route) eq $dest)) {
            return 1;
        }
    }
   
    return 0;

}

# user_in_vm
#
# Return true if the <user> (identified by username) is in the <vm>
#
# - vm node
# - username attribute in <user>
#
sub user_in_vm {

    my $self = shift;
    my $vm = shift;
    my $username = shift;
   
   	foreach my $user ($vm->getElementsByTagName("user")) {
        if ($user->getAttribute("username") eq $username) {
            return 1;
        }
    }
   
    return 0;

}

# filetree_in_vm
#
# Return true if the <filetree> (identified by when, root and target) is in the <vm>
#
# - vm node
# - when attribute in <filetree>
# - root attribute in <filetree>
# - target (<filetree> tag value)
#
sub filetree_in_vm {
    
    my $self = shift;
    my $vm = shift;
    my $when = shift;
    my $root = shift;
    my $target = shift;
   
    foreach my $filetree ($vm->getElementsByTagName("filetree")) {
        if (($filetree->getAttribute("seq") eq $when) &&
            ($filetree->getAttribute("root") eq $root) &&
            (&chompslash(&text_tag($filetree)) eq &chompslash($target))) {
                return 1;
        }
    }
   
    return 0;

}

sub numerically { $a <=> $b; }     # Helper for sorting

#
# get_net_byname
#
# Returns a net knowing its name 
#
sub get_net_byname {

    my $self = shift;
    my $net_name = shift;

    #wlog (VVV, "---- looking for " . $vm_name);

    my $global_doc = $dh->get_doc;

    foreach my $net ($global_doc->getElementsByTagName("net")) {
		if ($net->getAttribute("name") eq $net_name) {
			return $net
		};
    }
    return "";
}

#
# get_net_type: returns the type of a <net> ('' if not found).
#
sub get_net_type {

   	my $self = shift;
	my $netName = shift;
	
	foreach my $net ($self->{'doc'}->getElementsByTagName("net")) {
	    my $name = $net->getAttribute ("name");
        if ($name eq $netName) {
	    	return $net->getAttribute ("type");
        }
	}
	return ''
}

#
# get_net_mode: returns the mode of a <net> ('' if not found).
#
sub get_net_mode {

    my $self = shift;
    my $netName = shift;
    
    foreach my $net ($self->{'doc'}->getElementsByTagName("net")) {
        my $name = $net->getAttribute ("name");
        if ($name eq $netName) {
            return $net->getAttribute ("mode");
        }
    }
    return ''
}

#
# get_net_extif: returns the external attribute of a <net> ('' if not found).
#
sub get_net_extif {

    my $self = shift;
    my $netName = shift;
    
    foreach my $net ($self->{'doc'}->getElementsByTagName("net")) {
        my $name = $net->getAttribute ("name");
        if ($name eq $netName) {
            return $net->getAttribute ("external");
        }
    }
    return ''
}

#
# get_net_vlan: returns the vlan attribute of a <net> ('' if not found).
#
sub get_net_vlan {

    my $self = shift;
    my $netName = shift;
    
    foreach my $net ($self->{'doc'}->getElementsByTagName("net")) {
        my $name = $net->getAttribute ("name");
        if ($name eq $netName) {
            return $net->getAttribute ("vlan");
        }
    }
    return ''
}

# get_net_by_mode
#
# Returns a network whose name is the first argument and whose mode is second
# argument (may be "*" if the type doesn't matter). If there is no net with
# the given constrictions, 0 value is returned
#
# Note the default mode is "virtual_bridge"
#
sub get_net_by_mode {
   
    my $self = shift;
    my $name_target = shift;
    my $mode_target = shift;
   
    my $logp = "get_net_by_mode";
    wlog (VVV, "name=$name_target, mode=$mode_target", $logp);
    my $doc = $dh->get_doc;
   
    # To get list of defined <net>
   	foreach my $net ($doc->getElementsByTagName("net")) {
        my $name = $net->getAttribute("name");
        my $mode = $net->getAttribute("mode");

        if (($name_target eq $name) && (($mode_target eq "*") || ($mode_target eq $mode))) {
            return $net;
        }
        # Special case (implicit virtual_bridge)
        if (($name_target eq $name) && ($mode_target eq "virtual_bridge") && ($mode eq "")) {
            return $net;
        }
    }
   
    return 0;	
}

#
# get_vms_in_a_net: returns references to two arrays with the virtual machines and the 
#                   interfaces connected to a <net>
#
# Example usage:
#
#   my ($vms,$ifs) = $dh->get_vms_in_a_net ($net);
#   for (my $i = 0; $i < scalar @$vms; $i++) {
#	  print "vm name=" . @$vms[$i]->getAttribute ("name");
#	  print "if name=" . @$ifs[$i]->getAttribute ("name");	
#   }
#
sub get_vms_in_a_net {

   	my $self = shift;
	my $netName = shift;
	my @vms;
	my @ifs;
	
	foreach my $vm ($self->{'doc'}->getElementsByTagName("vm")) {
        my $found;
	    my $name = $vm->getAttribute ("name");
		# Network interfaces loop
        foreach my $if ($vm->getElementsByTagName ("if")) {
            my $id = $if->getAttribute ("id");
            my $net = $if->getAttribute ("net");
            if ($net eq $netName) {
                #print "  vm found: $name \n";
                push (@vms, $vm);
                push (@ifs, $if);
            }
        }
	}
	return (\@vms, \@ifs)
}

#
# get_vm_merged_type
#
#
sub get_vm_merged_type {

   	my $self = shift;
	my $vm = shift;

    my $type;
    if ($vm->nodeName() eq 'vm') {
        $type = $vm->getAttribute("type");
    } elsif ($vm->nodeName() eq 'filesystem') {
        $type = $vm->getAttribute("vm_type");
    }
	my $subtype = $vm->getAttribute("subtype");
	my $os = $vm->getAttribute("os");
	
	my $merged_type = $type;
	
    #if (!($subtype eq "")){
    if (!empty($subtype)){
		$merged_type = $merged_type . "-" . $subtype;
        #if (!($os eq "")){
        if (!empty($os)){
			$merged_type = $merged_type . "-" . $os;
		}
	}
	return $merged_type;
}

#
# get_vm_type
#
#
sub get_vm_type {

    my $self = shift;
    my $vm = shift;

    my @type;

    $type[0] = $vm->getAttribute("type");
    $type[1] = str($vm->getAttribute("subtype"));
    $type[2] = str($vm->getAttribute("os"));
    
    return @type;
}

#
# get_seqs
#
# Returns an array with all the sequences defined for the node passed in $vm
#  - If $vm is a virtual machine, returns the sequences for that vm
#  - If $vm is not defined, the global node (dh->$doc) is used, and returns all 
#    the sequences for the complete scenario 
#
sub get_seqs {

    my $self = shift;
    my $vm = shift;
    my %vm_seqs;

    unless (defined($vm)) {
    	$vm = $self->{'doc'}
    }
    foreach my $filetree ($vm->getElementsByTagName("filetree")) {

        my @seqs = split /,/, $filetree->getAttribute('seq'); 
        foreach my $seq (@seqs) {
            $vm_seqs{$seq} = 'yes';
        }
    }
    foreach my $exec ($vm->getElementsByTagName("exec")) {
        my @seqs = split /,/, $exec->getAttribute('seq'); 
        foreach my $seq (@seqs) {
            $vm_seqs{$seq} = 'yes';
        }
    }

    return %vm_seqs;
}

#
# get_seq_desc
#
# Returns the text value of an <seq_help> tag with sequence = $seq
# or none if not found 
#
sub get_seq_desc {
       
    my $self = shift;
    my $seq = shift;

    my $doc = $self->{'doc'};
    foreach my $exechelp ($doc->getElementsByTagName("seq_help")) {         
        if ($exechelp->getAttribute('seq') eq $seq) {
            return text_tag($exechelp);         
        } 
    }
}



#
# any_vmtouse_of_type
#
# Checks if there is any VM of type $type in the list of virtual virtual 
# machines to use ($dh->get_vm_to_use_ordered)
#
sub any_vmtouse_of_type {

    my $self = shift;
    my $type = shift;
    my $subtype = shift;
    my $os = shift;

    my $logp="any_vmtouse_of_type> ";
    wlog (VVV, "Looking for VM of type type=$type, subtype=" . str($subtype) . ", os=" . str($os), $logp);

    my $compare_subtype=defined($subtype);
    my $compare_os=defined($os);
    my $found;

    my $global_doc = $dh->get_doc;
    my @vm_ordered = $dh->get_vm_to_use_ordered;

    foreach my $vm (@vm_ordered) {    

        if ( ($vm->getAttribute("type")    eq $type    ) &&
             ( !$compare_subtype || $vm->getAttribute("subtype") eq $subtype ) &&
             ( !$compare_os      || $vm->getAttribute("os")      eq $os      ) ) {
            wlog (VVV, "VM of type $type-" . str($subtype) . "-" . str($os) . " found", $logp);
            return 'true'     	
        }
    }
    wlog (VVV, "No VM of type $type-" . str($subtype) . "-" . str($os) . " found", $logp);
    return $found;
}


1;
