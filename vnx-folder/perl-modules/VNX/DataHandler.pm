# DataHandler.pm
#
# This file is a module part of VNUML package.
#
# Author: Fermin Galan Marquez (galan@dit.upm.es)
# Copyright (C) 2005, 	DIT-UPM
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

package DataHandler;

use strict;
use VNX::TextManipulation;
use VNX::DocumentChecks;
use VNX::FileChecks;

###########################################################################
# CLASS CONSTRUCTOR
#
# Arguments (apart from the firts one, the class itseft)
#
# - The Execution object reference
# - the XML DOM object reference
# - mode (t|x|d|P)
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
   $self->{'cmd_seq'} = shift;
   $self->{'xml_dir'} = shift;
   $self->{'input_file'} = shift;
   
   # Build static data array
   my %global_data;
   
   # 1. Fields that lives under <vm_defaults>
   my $vm_defaults_list = $self->{'doc'}->getElementsByTagName("vm_defaults");
   my $no_filesystem = 1;
   my $no_mem = 1;
   my $no_kernel = 1;
   my $no_shell = 1;
   my $no_basedir = 1;
   my $no_mgn_if = 1;
   my $no_xterm = 1;
   my $no_forwarding = 1;
   if ($vm_defaults_list->getLength == 1) {
   
      my $filesystem_list = $vm_defaults_list->item(0)->getElementsByTagName("filesystem");
      if ($filesystem_list->getLength == 1) {
         $global_data{'default_filesystem'} = &do_path_expansion(&text_tag($filesystem_list->item(0)));;
         $global_data{'default_filesystem_type'} = $filesystem_list->item(0)->getAttribute("type");
         $no_filesystem = 0;
      }
      
      my $default_mem_list = $vm_defaults_list->item(0)->getElementsByTagName("mem");
      if ($default_mem_list->getLength == 1) {
         $global_data{'default_mem'} = &text_tag($default_mem_list->item(0));;
         $no_mem = 0;
      }
      
      my $kernel_list = $vm_defaults_list->item(0)->getElementsByTagName("kernel");
      if ($kernel_list->getLength == 1) {
         $global_data{'default_kernel'} = &do_path_expansion(&text_tag($kernel_list->item(0)));
         $global_data{'default_initrd'} = &do_path_expansion($kernel_list->item(0)->getAttribute("initrd"));
         $global_data{'default_devfs'} = $kernel_list->item(0)->getAttribute("devfs");
         $global_data{'default_root'} = &do_path_expansion($kernel_list->item(0)->getAttribute("root"));
         $global_data{'default_modules'} = &do_path_expansion($kernel_list->item(0)->getAttribute("modules"));
         $global_data{'default_trace'} = $kernel_list->item(0)->getAttribute("trace");
         $no_kernel = 0;
      }
      
      my $shell_list = $vm_defaults_list->item(0)->getElementsByTagName("shell");
      if ($shell_list->getLength == 1) {
         $global_data{'default_shell'} = &do_path_expansion(&text_tag($shell_list->item(0)));
         $no_shell = 0;
      }

      my $basedir_list = $vm_defaults_list->item(0)->getElementsByTagName("basedir");
      if ($basedir_list->getLength == 1) {
         $global_data{'default_basedir'} = &do_path_expansion(&text_tag($basedir_list->item(0)));
         $no_basedir = 0;
      }
      
      my $mng_if_list = $vm_defaults_list->item(0)->getElementsByTagName("mng_if");
      if ($mng_if_list->getLength == 1) {
         $global_data{'default_mng_if'} = &text_tag($mng_if_list->item(0));
         $no_mgn_if = 0;
      }
      
      my $xterm_list = $vm_defaults_list->item(0)->getElementsByTagName("xterm");
      if ($xterm_list->getLength == 1) {
         $global_data{'default_xterm'} = &text_tag($xterm_list->item(0));
         $no_xterm = 0;
      }
            
      my $forwarding_list = $vm_defaults_list->item(0)->getElementsByTagName("forwarding");
      if ($forwarding_list->getLength == 1) {
         $global_data{'default_forwarding_type'} = $forwarding_list->item(0)->getAttribute("type");
         $no_forwarding = 0;
      }
      
      if ($vm_defaults_list->item(0)->getAttribute("exec_mode") ne "") {
         $global_data{'default_exec_mode'} = $vm_defaults_list->item(0)->getAttribute("exec_mode");
      }
      else {
         $global_data{'default_exec_mode'} = "net";
      }
      
   }
   
   if ($no_filesystem) {
   	  $global_data{'default_filesystem'} = &do_path_expansion("/usr/share/vnx/filesystems/root_fs_tutorial");
      $global_data{'default_filesystem_type'} = "cow";
   }
   if ($no_mem) {
      $global_data{'default_mem'} = "32M";
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
   if ($no_forwarding) {
      $global_data{'default_forwarding_type'} = "";
   }
   
   # 2. Fields taken from the scenario  

   # scenario's name
   my $scename_list = $self->{'doc'}->getElementsByTagName("scenario_name");
   if ($scename_list->getLength == 1) {
      $global_data{'scename'} = &text_tag($scename_list->item(0));
   }
   else {
      $self->{'execution'}->smartdie ("scenario name is missing\n");
   }
  
   # Host mapping
   my $hostmapping_list = $self->{'doc'}->getElementsByTagName("host_mapping");
   if ($hostmapping_list->getLength == 1) {
      $global_data{'host_mapping'} = 1;
   }
   else {
 	  $global_data{'host_mapping'} = 0;             # by default, management addresses are not mapped in /etc/hosts
   }
   # Dynamips mapping
   my $dynamipsmapping_list = $self->{'doc'}->getElementsByTagName("dynamips_ext");
   if ($dynamipsmapping_list->getLength == 1) {
      $global_data{'dynamips_ext'} =  &text_tag($dynamipsmapping_list->item(0));
   }
   else {
 	  $global_data{'dynamips_ext'} = 0;             
   }

   # Network configuration options, if <netconfig> is present
   my $netconfig_list = $self->{'doc'}->getElementsByTagName("netconfig");
   if ($netconfig_list->getLength == 1) {
      ($global_data{'stp'},$global_data{'promisc'}) = &netconfig($self, $netconfig_list->item(0));
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
   my $vmmgmt_list = $self->{'doc'}->getElementsByTagName("vm_mgmt");
   if ($vmmgmt_list->getLength == 1) {
	  my ($type,$net,$mask,$offset,$hostip,$autoconfigure) = &vmmgmt($self, $vmmgmt_list->item(0));
	  if ($type ne '') {
		  $global_data{'vmmgmt_type'} = $type;
	  }
	  if ($net ne '') {
		  $global_data{'vmmgmt_net'} = $net;
	  }
	  if ($mask ne '') {
		  $global_data{'vmmgmt_mask'} = $mask;
	  }
	  if ($offset ne '') {
		  $global_data{'vmmgmt_offset'} = $offset;
	  }
	  if ($hostip ne '') {
		  $global_data{'vmmgmt_hostip'} = $hostip;
	  }
	  if ($autoconfigure ne '') {
		  $global_data{'vmmgmt_autoconfigure'} = $autoconfigure;
	  }
   }

   # AutoMAC offset
   $global_data{'automac_offset'} = 0;
   my $automac_list = $self->{'doc'}->getElementsByTagName("automac");
   if ($automac_list->getLength == 1) {
      my $att = $automac_list->item(0)->getAttribute("offset");
      if ($att =~ /^$/) {
         $global_data{'automac_offset'} = 0;
      }
      else {
         $global_data{'automac_offset'} = $att;
      }
   }

   # SSH version, if present
   $global_data{'ssh_version'} = "1";	        # default SSH protocol version is 1}
   my $ssh_version_list = $self->{'doc'}->getElementsByTagName("ssh_version");
   if ($ssh_version_list->getLength == 1) {
      $global_data{'ssh_version'} = &text_tag($ssh_version_list->item(0));
   }

   # Tun device, if <tun_device> is present
   my $tun_device_list = $self->{'doc'}->getElementsByTagName("tun_device");
   if ($tun_device_list->getLength == 1) {
      $global_data{'tun_device'} = &do_path_expansion(&text_tag($tun_device_list->item(0)));
   }
   else {
      $global_data{'tun_device'} = &do_path_expansion("/dev/net/tun");   # default tun device
   }
   
   # 3. Other fields (constants):
   #$global_data{'max_name_length'} = 7;          # max length for names in <vm> and <net>
   $global_data{'delay'} = 5;		         # reference delay used by vnumlparser (mounting operations and blocks)   

   # 4. Assignement, by reference
   $self->{'global_data'} = \%global_data;  

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


# get_default_forwarding_type
#
# Returns the default forwarding type
#
sub get_default_forwarding_type {
   my $self = shift;
   return $self->{'global_data'}->{'default_forwarding_type'};
}

# get_default_exec_mode
#
# Returns the default exec mode
#
sub get_default_exec_mode {
   my $self = shift;
   return $self->{'global_data'}->{'default_exec_mode'};
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

   my $vm_list = $self->{'doc'}->getElementsByTagName("vm");
   my %vm_index;

   # Build a index hash
   for (my $i = 0; $i < $vm_list->getLength; $i++) {
      my $order = $vm_list->item($i)->getAttribute("order");
      if ($order =~ /^$/) {
        # Empty string
        # Do nothing
      }
      elsif ($order =~ /^\d+$/) {
         # A value
         $vm_index{$order} = $i;
      }
      else {
         my $name = $vm_list->item($i)->getAttribute("name");
         $self->{'execution'}->smartdie("vm $name has invalid order string: $order");
      }
  }
  
  # The first machines in the are the ones with "order" attribute
  foreach (sort numerically keys %vm_index) {
     @vm_ordered = (@vm_ordered, $vm_list->item($vm_index{$_}));
  }
   
  # Finally, add machines without order, in the same order they appear in the VNUML file
  for (my $i = 0; $i < $vm_list->getLength; $i++) {
     my $order = $vm_list->item($i)->getAttribute("order");
     if ($order =~ /^$/) {
        # Empty string
        @vm_ordered = (@vm_ordered, $vm_list->item($i));	
     }
  }

  return @vm_ordered;

}

# get_vm_to_use
#
# Returns a hash with the vm names of the scenario to use with -x mode. By
# defualt are UMLs defined in the VNUML source file are include, execpt when the -M switch. 
# is in use.
#
# Arguments:
#
# - plugins array (in order to invoke the execVmsToUse method that provide the vms for which the
#   plugin has to execute actions)
#
sub get_vm_to_use {
   my $self = shift;
   my @plugins = @_;
   
   # The hash to be returned at the end
   my %vm_hash;
   
   # Build a hash with the vms that the plugins need
   my %plugins_vms;
   foreach my $plugin (@plugins) {
      my @vms = $plugin->execVmsToUse($self->{'cmd_seq'});
      foreach (@vms) {
         $plugins_vms{$_} = 1;
      }
   }

   my @vms = $self->get_vm_ordered;
   for ( my $i = 0; $i < @vms; $i++) {
      my $vm = $vms[$i];

      # To get name attribute
      my $name = $vm->getAttribute("name");

      # Include only if have commands to execute or filetree to install (in -x modes); other modes (-t and -d) always
      if (
          ($self->{'mode'} eq "t") ||
	      ($self->{'mode'} eq "d") ||
	      ($self->{'mode'} eq "P") ||
	      ($self->{'mode'} eq "define") ||
	      ($self->{'mode'} eq "start") ||
	      ($self->{'mode'} eq "reset") ||
	      ($self->{'mode'} eq "reboot") ||
	      ($self->{'mode'} eq "save") ||
	      ($self->{'mode'} eq "restore") ||
	      ($self->{'mode'} eq "suspend") ||
	      ($self->{'mode'} eq "resume") ||
	      ($self->{'mode'} eq "undefine") ||
          (((&vm_has_tag($vm,"exec",$self->{'cmd_seq'})) || (&vm_has_tag($vm,"filetree",$self->{'cmd_seq'})) || (exists $plugins_vms{$name} && $plugins_vms{$name} eq "1") ) && ($self->{'mode'} eq "x") || (exists $plugins_vms{$name} && $plugins_vms{$name} eq "1")  && ($self->{'mode'} eq "execute") )  
	  ) {
	  	# En proceso de construccion, hay que quitar los plugins en caso de que %plugins_vms no tenga nada.
#	     if (
#          ($self->{'mode'} eq "t") ||
#	      ($self->{'mode'} eq "d") ||
#	      ($self->{'mode'} eq "P") ||
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
#          			((scalar(%plugins_vms) ge 0) && (($plugins_vms{$name} eq "1") && ($self->{'mode'} eq "x") || ($plugins_vms{$name} eq "1")  && ($self->{'mode'} eq "execute") ))  
#	  ) {

         # Only if list is not empty
         if ($self->{'vm_to_use'}) {
            my $vm_list = $self->{'vm_to_use'};
	        if ($vm_list =~ /^$name,|,$name,|,$name$|^$name$/) {
	           $vm_hash{$name} = 1;
	        }
	     }
	     else {
	        $vm_hash{$name} = "1";
         }
      }
   }
   return %vm_hash;

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

# get_fs_dir
#
# Arguments:
#
# - the name of the vm
#
# Returns the directory containing the filesystems for a particular vm
#
sub get_fs_dir {
   my $self = shift;
   my $name = shift;
   return $self->get_vm_dir($name) . "/fs";
}

# get_hostfs_dir
#
# Arguments:
#
# - the name of the vm
#
# Returns the hostfs mounting point (in the host) for a particular vm
#
sub get_hostfs_dir {
   my $self = shift;
   my $name = shift;
   return $self->get_vm_dir($name) . "/hostfs";
}

# get_run_dir
#
# Arguments:
#
# - the name of the vm
#
# Returns the directory containing the pid and mconsole socket for a particular vm
#
sub get_run_dir {
   my $self = shift;
   my $name = shift;
   return $self->get_vm_dir($name) . "/run";
}

# get_mnt_dir
#
# Arguments:
#
# - the name of the vm
#
# Returns the directory used to mount shared disks for a particular vm
#
sub get_mnt_dir {
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
# Returns the temporary directory a particular vm
#
sub get_vm_tmp_dir {
   my $self = shift;
   my $name = shift;
   return $self->get_vm_dir($name) . "/tmp";
}

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
   my $tag_list = $doc->getElementsByTagName($tag);

   # To process list
   for ( my $i = 0; $i < $tag_list->getLength; $i++ ) {
      my $tag = $tag_list->item($i);

      # To try getting attribute
      my $attribute_value = $tag->getAttribute($attribute);

      unless ($attribute_value =~ /^$/) {
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
   my $vm_defaults_list = $self->{'doc'}->getElementsByTagName("vm_defaults");
   if ($vm_defaults_list->getLength == 1) {
      my $console_list = $vm_defaults_list->item(0)->getElementsByTagName("console");
      for (my $i = 0; $i < $console_list->getLength; $i++) {
         my $console = $console_list->item($i);
         my $id = $console->getAttribute("id");
         unless (&console_in_vm($self,$vm,$id)) {
            push (@list, $console);
         }
      }
   }
   
   # Second, add from the vm
   my $console_list = $vm->getElementsByTagName("console");
   for (my $i = 0; $i < $console_list->getLength; $i++) {
      push (@list, $console_list->item($i));
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
   my $vm_defaults_list = $self->{'doc'}->getElementsByTagName("vm_defaults");
   if ($vm_defaults_list->getLength == 1) {
      my $route_list = $vm_defaults_list->item(0)->getElementsByTagName("route");
      for (my $i = 0; $i < $route_list->getLength; $i++) {
         my $route = $route_list->item($i);
         my $route_type = $route->getAttribute("type");
         my $route_dest = &text_tag($route);
         unless (&route_in_vm($self,$vm,$route_type,$route_dest)) {
            push (@list, $route);
         }
      }
   }
   
   # Second, add from the vm
   my $route_list = $vm->getElementsByTagName("route");
   for (my $i = 0; $i < $route_list->getLength; $i++) {
      push (@list, $route_list->item($i));
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
   my $vm_defaults_list = $self->{'doc'}->getElementsByTagName("vm_defaults");
   if ($vm_defaults_list->getLength == 1) {
      my $user_list = $vm_defaults_list->item(0)->getElementsByTagName("user");
      for (my $i = 0; $i < $user_list->getLength; $i++) {
         my $user = $user_list->item($i);
         my $username = $user->getAttribute("username");
         unless (&user_in_vm($self,$vm,$username)) {
            push (@list, $user);
         }
      }
   }
   
   # Second, add from the vm
   my $user_list = $vm->getElementsByTagName("user");
   for (my $i = 0; $i < $user_list->getLength; $i++) {
      push (@list, $user_list->item($i));
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
   my $vm_defaults_list = $self->{'doc'}->getElementsByTagName("vm_defaults");
   if ($vm_defaults_list->getLength == 1) {
      my $filetree_list = $vm_defaults_list->item(0)->getElementsByTagName("filetree");
      for (my $i = 0; $i < $filetree_list->getLength; $i++) {
         my $filetree = $filetree_list->item($i);
         my $when = $filetree->getAttribute("seq");
         my $root = $filetree->getAttribute("root");
         my $target = &text_tag($filetree);
         unless (&filetree_in_vm($self,$vm,$when,$root,$target)) {
            push (@list, $filetree);
         }
      }
   }
   
   # Second, add from the vm
   my $filetree_list = $vm->getElementsByTagName("filetree");
   for (my $i = 0; $i < $filetree_list->getLength; $i++) {
      push (@list, $filetree_list->item($i));
   }
   
   return @list;
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
   my $stp;
   my $promisc;

   my $stp_att = $net_cfg->getAttribute("stp");
   $stp = 1 if ( $stp_att =~ /^on$/ );
   $stp = 0 if ( $stp_att =~ /^off$/ );

   my $promisc_att = $net_cfg->getAttribute("promisc");
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

   my $vmmgmt_net_list = $vmmgmt->getElementsByTagName("mgmt_net");
   if ($vmmgmt_net_list->getLength > 0) {
		$hostip = $vmmgmt_net_list->item(0)->getAttribute("hostip");
		$autoconfigure = $vmmgmt_net_list->item(0)->getAttribute("autoconfigure");
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
   
   my $console_list = $vm->getElementsByTagName("console");
   for (my $i=0; $i < $console_list->getLength; $i++) {
      if ($console_list->item($i)->getAttribute("id") eq $id) {
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
   
   my $route_list = $vm->getElementsByTagName("route");
   for (my $i=0; $i < $route_list->getLength; $i++) {
      if (($route_list->item($i)->getAttribute("type") eq $type) &&
          (&text_tag($route_list->item($i)) eq $dest)) {
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
   
   my $user_list = $vm->getElementsByTagName("user");
   for (my $i=0; $i < $user_list->getLength; $i++) {
      if ($user_list->item($i)->getAttribute("username") eq $username) {
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
   
   my $filetree_list = $vm->getElementsByTagName("filetree");
   for (my $i=0; $i < $filetree_list->getLength; $i++) {
      if (($filetree_list->item($i)->getAttribute("seq") eq $when) &&
          ($filetree_list->item($i)->getAttribute("root") eq $root) &&
          (&chompslash(&text_tag($filetree_list->item($i))) eq &chompslash($target))) {
         return 1;
      }
   }
   
   return 0;

}

sub numerically { $a <=> $b; }     # Helper for sorting

1;
