# BinariesData.pm
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

# BinariesData class implementation. Contain the data related with the binary commands
# needed by the VNUML parser.

package BinariesData;

use strict;
use VNX::TextManipulation;

# TODO: constant should be included in a .pm that would be loaded from each module
# that needs them
use constant EXE_DEBUG => 0;	#	- does not execute, only shows
use constant EXE_VERBOSE => 1;	#	- executes and shows
use constant EXE_NORMAL => 2;	#	- executes

###########################################################################
# CLASS CONSTRUCTOR
#
# Arguments:
#
# - the execution mode
#
sub new {
   my $class = shift;
   my $self = {};
   bless $self;

   $self->{'exe_mode'} = shift;
   
   # List of mandatory binaries
   my @binaries_mandatory = ("touch", "rm",  "mv", "echo", "modprobe", "tunctl", 
   "ifconfig", "cp", "cat", "lsof", "chown",
   "hostname", "route", "scp", "chmod", "ssh", "uml_mconsole",                                                                             
   "date", "ps", "grep", "kill", "ln", "mkisofs", "mktemp", "su", "find",
   "qemu-img", "mkfs.msdos", "mount", "umount");
   
   # List of optional binaries for xterm, vlan, screen and
   # uml_switch (defaults are empty: the add_additional_*_binaries 
   # methods add required binaries, based on the VNUML specification
   my @binaries_xterm = ();
   my @binaries_vlan = ();
   my @binaries_screen = ();
   my @binaries_switch = ();
   my @binaries_bridge = ();

   # Hash to store paths of binaries (empty util check_binaries method is called)
   my %bp;
  
   # Assignements by reference
   $self->{'binaries_mandatory'} = \@binaries_mandatory;
   $self->{'binaries_screen'} = \@binaries_screen;
   $self->{'binaries_vlan'} = \@binaries_vlan;
   $self->{'binaries_switch'} = \@binaries_switch;
   $self->{'binaries_bridge'} = \@binaries_bridge;
   $self->{'binaries_xterm'} = \@binaries_xterm;
   $self->{'binaries_path'} = \%bp;

   return $self;  
}

###########################################################################
# PUBLIC METHODS

# add_additional_xterm_binaries
#
# Arguments:
#	- The DataHandler object describin the VNUML XML specification
#
sub add_additional_xterm_binaries {
	my $self = shift;
	my $dh = shift;

    # Check <vm_defaults>, in order to detect consoles with xterm
    my %xterm_console_default;
	my $vm_defaults_list = $dh->get_doc->getElementsByTagName("vm_defaults");
    if ($vm_defaults_list->getLength == 1) {
       my $console_list = $vm_defaults_list->item(0)->getElementsByTagName("console");
       for (my $i = 0; $i < $console_list->getLength; $i++) {
          if (&text_tag($console_list->item($i)) eq "xterm") {
             my $console_id = $console_list->item($i)->getAttribute("id");
             $xterm_console_default{$console_id} = 1;
          }
       }
    }

	my %xterm_binaries;
	my $vm_list = $dh->get_doc->getElementsByTagName("vm");
	for ( my $i = 0 ; $i < $vm_list->getLength; $i++ ) {
		# Is using the virtual machine a xterm? Check the efective
		# consoles list
						
		my $xterm_is_used = 0;
		my @console_list = $dh->merge_console($vm_list->item($i));
		foreach my $console (@console_list) {
	       if (&text_tag($console) eq 'xterm') {
		      $xterm_is_used = 1;
		      last;
		   }
		}
		
		if ($xterm_is_used) {
		   my $xterm;
		   my $xterm_list = $vm_list->item($i)->getElementsByTagName("xterm");
		   if ($xterm_list->getLength > 0) {
	          $xterm = &text_tag($xterm_list->item(0));
           }
		   else {
		      # If <xterm> has been specified in <vm_defaults> use that value
			  if (($vm_defaults_list->getLength == 1) && ($vm_defaults_list->item(0)->getElementsByTagName("xterm")->getLength == 1)) {
			     $xterm = &text_tag($vm_defaults_list->item(0)->getElementsByTagName("xterm")->item(0));
			  }
			  else {			
			     # Get the default xterm for the kernel
			     my $kernel = $dh->get_default_kernel;
		  	     my $kernel_list = $vm_list->item($i)->getElementsByTagName("kernel");
			     if ($kernel_list->getLength > 0) {
				    $kernel = &text_tag($kernel_list->item(0));
			     }
			     my $cmd = "$kernel --help | grep \"default values are 'xterm=\"";
			     chomp(my $line = `$cmd`);
			     if ($line =~ /'xterm=([^\']+)/) {
			        $xterm = $1;
			     }
			     else {
			        $xterm = "xterm,-T,-e";
			     }
		      }
		   }
	       # Asumming the xterm string will be something as the
	       # following pattern: gnome-terminal,-t,-x (this is the 
	       # format for the xterm= UML switch)
	       $xterm =~ s/^(.+),.+,.+$/\1/;
	       $xterm_binaries{$1} = 1;		
	    }
	}
	
	my @list = keys %xterm_binaries;
	if ($#list >= 0) {
		push(@list,'xauth');
	}
	$self->{'binaries_xterm'} = \@list;
}

# add_additional_vlan_binaries
#
# Arguments:
#	- The DataHandler object describing the VNUML XML specification
#
sub add_additional_vlan_binaries {
   my $self = shift;
   my $dh = shift;
   
   # Check that there are at least one <net> tag using vlan attribute   
   my @list = ();
   if ($dh->check_tag_attribute("net","vlan") != 0) {   
      push (@list,"vconfig");
   }
   $self->{'binaries_vlan'} = \@list;
}

# add_additional_screen_binaries
#
# Arguments:
#	- The DataHandler object describing the VNUML XML specification
#
sub add_additional_screen_binaries {
   my $self = shift;
   my $dh = shift;
   
   my @list = ();
   
   my $vm_list = $dh->get_doc->getElementsByTagName("vm");
   for (my $i = 0; $i < $vm_list->getLength; $i++) {
      my @console_list = $dh->merge_console($vm_list->item($i));
	  foreach my $console (@console_list) {
         if (&text_tag($console) eq 'pts') {
		    push (@list,"screen");
		    last;
		 }
	  }
   }
      
   $self->{'binaries_screen'} = \@list;
}

# add_additional_uml_switch_binaries
#
# Arguments:
#	- The DataHandler object describing the VNUML XML specification
#
sub add_additional_uml_switch_binaries {
   my $self = shift;
   my $dh = shift;
   
   my @list = ();
   
   # Additional case: when using <mgmt_net autoconfigure="on"> uml_switch
   # must be added.
   if ($dh->get_vmmgmt_autoconfigure ne "") {
      @list = ("uml_switch");
   }   
   
   my $net_list = $dh->get_doc->getElementsByTagName("net");
   for (my $i = 0; $i < $net_list->getLength; $i++) {
      if ($net_list->item($i)->getAttribute("mode") eq "uml_switch") {
         @list  = ("uml_switch");
         last;
      }
   }   
   $self->{'binaries_switch'} = \@list;
}

# add_additional_bridge_binaries
#
# Arguments:
#	- The DataHandler object describing the VNUML XML specification
#
sub add_additional_bridge_binaries {
   my $self = shift;
   my $dh = shift;
   
   my @list = ();
   my $net_list = $dh->get_doc->getElementsByTagName("net");
   for (my $i = 0; $i < $net_list->getLength; $i++) {
      if ($net_list->item($i)->getAttribute("mode") eq "virtual_bridge") {
         push (@list, "brctl");
         last;
      }
   }   
   $self->{'binaries_bridge'} = \@list;
}

# check_binaries_mandatory
sub check_binaries_mandatory {
   my $self = shift; 
   my $ref = $self->{'binaries_mandatory'};
   my @list = @$ref;
   return &check_binaries($self, @list); 
}

# check_binaries_screen
sub check_binaries_screen {
   my $self = shift;   
   my $ref = $self->{'binaries_screen'};
   my @list = @$ref;
   return &check_binaries($self, @list); 
}

# check_binaries_vlan
sub check_binaries_vlan {
   my $self = shift;
   my $ref = $self->{'binaries_vlan'};
   my @list = @$ref;
   return &check_binaries($self, @list); 
}

# check_binaries_switch
sub check_binaries_switch {
   my $self = shift;   
   my $ref = $self->{'binaries_switch'};
   my @list = @$ref;
   return &check_binaries($self, @list); 
}

# check_binaries_bridge
sub check_binaries_bridge {
   my $self = shift;   
   my $ref = $self->{'binaries_bridge'};
   my @list = @$ref;
   return &check_binaries($self, @list); 
}

# check_binaries_xterm
sub check_binaries_xterm {
   my $self = shift;   
   my $ref = $self->{'binaries_xterm'};
   my @list = @$ref;
   return &check_binaries($self, @list); 
}

# get_binaries_path_ref
#
# Returns the binaries path associative array reference

sub get_binaries_path_ref {
   my $self = shift;
   
   return $self->{'binaries_path'};
   
}

###########################################################################
# PRIVATE METHODS (it only must be used from this class itsefl)

# check_binaries
#
# Check if the binaries needed for VNUML operation are available.
# First argument is the list of binaries to check. Return the
# number of unchecked binaries (0 if all the binaries were found).
#
# Path of checked binaries are stored in the binary_path hast hable in the
# BinariesData object.
#
sub check_binaries {
   my $self = shift;
   
   my $exe_mode = $self->{'exe_mode'};
   
   my $unchecked = 0;
   foreach (@_) {
      #print "Checking $_... " if (($exe_mode == EXE_VERBOSE) || ($exe_mode == EXE_DEBUG));
      my $fail = system("which $_ > /dev/null");
      if ($fail) {
         print "$_ not found\n" if (($exe_mode == EXE_VERBOSE) || ($exe_mode == EXE_DEBUG));;
	     $unchecked++;
      }
      else {
         my $where = `which $_`;
         chomp($where);
         #print "$where\n" if (($exe_mode == EXE_VERBOSE) || ($exe_mode == EXE_DEBUG));;
         # Add to the binary_path hash array
         $self->{'binaries_path'}->{$_} = $where;
      }
   }
   
   return $unchecked; 

}

1;
