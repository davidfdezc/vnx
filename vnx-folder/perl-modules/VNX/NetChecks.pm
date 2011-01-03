# NetChecks.pm
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

# NetChecks implementes several functions related with network checks

package VNX::NetChecks;
require(Exporter);

@ISA = qw(Exporter);
@EXPORT = qw( tundevice_needed check_net_host_conn );

use strict;
use VNX::Globals;
use VNX::DocumentChecks;

# tundevice_needed
#
# Check if the tundevice will be needed in order to run the scenario.
#
# Arguments:
#
# - The DataHandler object describin the VNUML XML specification
# - the vmmgmt_type
# - a list with the machine nodes
#
# Return 1 in the case the tun device is needed
#
sub tundevice_needed {

#   my $dh = shift;
   my $vmmgmt_type = shift;
   my @machines = @_;

   my $net_list = $dh->get_doc->getElementsByTagName("net");
   for (my $i = 0; $i < $net_list->getLength; $i++ ) {
   	  # Get attributes
   	  my $name = $net_list->item($i)->getAttribute("name");
   	  my $mode = $net_list->item($i)->getAttribute("mode");
   	  
   	  if ($mode ne "uml_switch") {
         # 1. <net mode="virtual_bridge">
         return 1;
   	  }
   	  else {
         # 2. <net mode="uml_switch"> with connection to the host (-tap is used)
         return 1 if (&check_net_host_conn($name,$dh->get_doc));
   	  }
   }
   
   # 2. Management interfaces
   #return 1 if ($vmmgmt_type eq 'private' && &at_least_one_vm_with_mng_if($dh,@machines) ne "");
   return 1 if ($vmmgmt_type eq 'private' && &at_least_one_vm_with_mng_if(@machines) ne "");
   
   return 0;
	
}

# check_net_host_conn
#
# Check if there is at least one connection on the host (one of the <hostif>) to
# the network passed as first argument
#
# The XML DOM reference is the second argument. 
#
sub check_net_host_conn {

   my $net = shift;
   my $doc = shift;

   my $hostif_list = $doc->getElementsByTagName("hostif");
   for ( my $i = 0 ; $i < $hostif_list->getLength ; $i++ ) {
   	  my $net_name = $hostif_list->item($i)->getAttribute("net");
      return 1 if ($net eq $net_name);
   }
   return 0;
}

1;
