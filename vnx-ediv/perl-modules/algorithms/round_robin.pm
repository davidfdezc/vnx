# This file is part of EDIV package
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation
# Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# Copyright: (C) 2008 Telefonica Investigacion y Desarrollo, S.A.U.
# Authors: Fco. Jose Martin,
#          Miguel Ferrer
#          Departamento de Ingenieria de Sistemas Telematicos, Universidad Politécnica de Madrid
#

package round_robin;

#
# Modules import
#

use strict;
use warnings;
use XML::DOM;
use Math::Round;
use VNX::Globals;
use VNX::Execution;


my $seg_mod_name = "RoundRobin";

#
# Subroutine to obtain segmentation name
#
sub name {

    return $seg_mod_name;

}


#
# Subroutine to obtain segmentation mode
#
# 
# Arguments:
# - ref_dom_tree
# - ref_cluster_hosts
# - ref_cluster
# - ref_vms_to_split, a reference to an array with the names of the vms to distribute
# - ref_static_assignment, reference to a hash with the vms assigned statically
#
# Returns:
# - %allocation, a hash that associates vm names to host_id's (the keys are vm names)
# 
sub split {

	my ( $class, $ref_dom_tree, $ref_cluster_hosts, $ref_cluster, $ref_vms_to_split, $ref_static_assignment ) = @_;
	
	my $scenario = $$ref_dom_tree;
	my @cluster_hosts = @$ref_cluster_hosts;
	my $cluster_size = @cluster_hosts;
	my $cluster = $$ref_cluster;
	my @vms_to_split = @$ref_vms_to_split;
	my %static_assignment = %$ref_static_assignment;   

	wlog (VV, "Segmentator: Cluster physical machines -> $cluster_size\n");

	my %allocation;
	
	# Check if there is any static assignement 
	my $static_assignment_undef = 1;
	my @keys = keys (%static_assignment);
	my $j = 0;
	while (defined(my $key = $keys[$j])) {
		 $static_assignment_undef = 0;
		$j++;
	}
	
	wlog (VV, "Segmentator: static_assignment_undef=$static_assignment_undef");
		
	if ($static_assignment_undef){ # No static assignements
		my $VMList = $scenario->getElementsByTagName("vm");		# Scenario virtual machines node list
		my $vm_number = $VMList->getLength;						# Number of virtual machines of scenario
		
		for (my $i=0; $i<$vm_number; $i++) {
			my $virtualm = $VMList->item($i);
			my $virtualm_name = $virtualm->getAttribute("name");
			my $assigned_host_index = $i % $cluster_size;
            #my $assigned_host = $cluster_hosts[$assigned_host_index]->{_hostname};
            my $assigned_host = $cluster->{hosts}{$cluster_hosts[$assigned_host_index]}->host_id;
			$allocation{$virtualm_name} = $assigned_host;
			wlog (VV, "Segmentator: Virtual machine $virtualm_name to physical host $assigned_host"); 	
		}
	} else { # Some vms are statically assigned

		my %offset;  # Hash to store the number of machines statically assigned to each host
		
		my @keys = keys (%static_assignment);
		my $j = 0;
		while (defined(my $key = $keys[$j])) {
			my $host_id = $static_assignment{$key};
			$offset{$host_id}++;           # Increase number of vm allocated to that host
			$allocation{$key} = $host_id;  # Store allocation of the vm 
			$j++;
		}
		
		my $vms_to_split_size = @vms_to_split;
		for (my $i=0; $i<$vms_to_split_size; $i++){ # For each vm to allocate...
			my $vm = $vms_to_split[$i];
			my $selected_host = $cluster_hosts[0];
            #my $selected_hostname = $cluster_info[$0]->{_hostname};
			
			
#			for (my $j=1; $j<$cluster_size; $j++) {
            foreach my $host_id (@cluster_hosts) {
                #my $hostName = $cluster_hosts[$j]->{_hostname};
                #my $host_name = $cluster->{hosts}{$host_id}->host_name;
				if ($offset{$host_id} < $offset{$selected_host}){
					$selected_host = $host_id;
				}

			}
			$allocation{$vm} = $selected_host;
			wlog (VV, "Segmentator: Virtual machine $vm to physical host $selected_host");
			$offset{$selected_host}++;
		}
		
	}
	
	return %allocation;

}
1
