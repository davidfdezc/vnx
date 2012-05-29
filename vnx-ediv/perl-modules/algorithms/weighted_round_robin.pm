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

package weighted_round_robin;

###########################################################
# Modules import
###########################################################

use strict;
use warnings;
use XML::DOM;
use Math::Round;
use VNX::Globals;
use VNX::Execution;
use VNX::ClusterMgmt;
use Data::Dumper;


my $seg_mod_name = "WeightedRoundRobin";

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

    my %host_cpu_index;
    my %host_cpu_dynamic;
    my %host_vm_percentage;
    my %allocation;
    my $total_cpu;
    my $total_cpu_index;

    my $vm_list = $scenario->getElementsByTagName("vm");     # Scenario VMs node list
    my $vm_number = $vm_list->getLength;                     # Number of VMs in scenario

	wlog (VV, "Segmentator $seg_mod_name: $cluster_size active hosts; $vm_number virtual machines", "");

    # Get host cpu index
    foreach my $host_id (@cluster_hosts) {
        my $cpu_index = get_host_cpu($host_id);
        wlog (VV, "Segmentator: CPU load of $host_id is $cpu_index", "");
        $host_cpu_index{$host_id} = $cpu_index;
        $total_cpu_index += $cpu_index;
    }

    # "Percentages" assignation
    my $fake_percentage = 0;

    foreach my $host_id (@cluster_hosts) {
    }

    # Adjusting to real percentages
    # VMs assignation
    my %assigned_vm_number;
    my $already_assigned_vm_number;
    my $last_host_id;        
    foreach my $host_id (@cluster_hosts) {
        $host_vm_percentage{$host_id} = $host_cpu_index{$host_id} / $total_cpu_index *100.00;
        $assigned_vm_number{$host_id} = round ($host_vm_percentage{$host_id} * $vm_number / 100);
        $already_assigned_vm_number += $assigned_vm_number{$host_id};
        wlog (VV, sprintf ("Segmentator: $assigned_vm_number{$host_id} VMs assigned to $host_id (%3.1f%s)", $host_vm_percentage{$host_id}, "%"), "");
        $last_host_id = $host_id;
    }

    if ($vm_number - $already_assigned_vm_number != 0) {
        $assigned_vm_number{$last_host_id} = $assigned_vm_number{$last_host_id} + $vm_number - $already_assigned_vm_number;
        wlog (VV, "Segmentator: round adjustement", "");
        wlog (VV, "Segmentator: $assigned_vm_number{$last_host_id} VMs assigned to $last_host_id", "");
    }
	

	my $static_assignment_undef = 1;
	my @keys = keys (%static_assignment);
	my $j = 0;
	while (defined(my $key = $keys[$j])) {
		 $static_assignment_undef = 0;
		$j++;
	}
		
	if ($static_assignment_undef){ 
		
		# No static assignements
		my $i = 0;  # VM index
		my $offset = 0;
        foreach my $host_id (@cluster_hosts) {
            my $limit = $offset + $assigned_vm_number{$host_id};
            for (; $i<$limit; $i++) {
                my $vm_name = $vm_list->item($i)->getAttribute("name");
                $allocation{$vm_name} = $host_id;
                wlog (VV, "Segmentator: vm $vm_name goes to host $host_id", "");     
                $offset++;
            }
        }
		
    } else {  
    	
    	# Some vms are statically assigned
        
        # Get the number of VMs explicitily assigned to each host and rest it 
        # from the total number assigned to that host
        my %offset;
        my @keys = keys (%static_assignment);
        my $j = 0;
        while (defined(my $key = $keys[$j])) {
            my $hostName = $static_assignment{$key};
            $offset{$hostName}++;
            $allocation{$key} = $hostName;
            $j++;
        }

        # Check if the virtual assigned number is lower than WRR assignment
        @keys = keys (%offset);
        $j = 0;
        while (defined(my $key = $keys[$j])) {
            if ($offset{$key}>$assigned_vm_number{$key}){
                wlog (VV, "  **** WARNING: Too many vms statically assigned to host $key ****");
                $assigned_vm_number{$key} = 0;
            } else {
                $assigned_vm_number{$key} = $assigned_vm_number{$key} - $offset{$key};
            }
                    
            $j++;
        }
    	
        # Assign all virtual machines
        my $vms_to_split_size = @vms_to_split;
        $j = 0;
        my $offset = 0;
        foreach my $host_id (@cluster_hosts) {
            my $limit = $offset + $assigned_vm_number{$host_id};
            for (; $j<$limit; $j++) {
                if ($vms_to_split_size > 0){
                    my $vm = $vms_to_split[$j];
                    $allocation{$vm} = $host_id;
                    wlog (VV, "Segmentator: Virtual machine $vm goes to physical host $host_id");  
                    $offset++;
                    $vms_to_split_size--;
                }
            }
        }
		
	}

    #foreach my $vm (keys(%allocation)) {
    #    wlog (V, "---- $vm --> $allocation{$vm}")
    #}
	
	return %allocation;

}
1
