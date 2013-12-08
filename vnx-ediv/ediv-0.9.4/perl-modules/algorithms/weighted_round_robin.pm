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
##########################################################

use strict;
use XML::DOM;
use Math::Round;

###########################################################
# Global variables 
###########################################################

my $scenario;
my @cluster_info;
my $cluster_size;
my @vms_to_split;
my %static_assignment;

###########################################################
# Subroutines
###########################################################
	###########################################################
	# Subroutine to obtain segmentation name
	###########################################################
sub name {

	my $name = "WeightedRoundRobin";

}

	###########################################################
	# Subroutine to obtain segmentation mode
	###########################################################
sub split {
	
	my ( $class, $rdom_tree, $rcluster_hosts, $rvms_to_split, $rstatic_assignment ) = @_;
	
	$scenario = $$rdom_tree;
	@cluster_info = @$rcluster_hosts;
	$cluster_size = @cluster_info;
	@vms_to_split = @$rvms_to_split;
	%static_assignment = %$rstatic_assignment;
	
	my %host_cpu_dynamic;
	my %host_vm_percentage;
	my %allocation;
	my $total_cpu;
	my $default_percentage = 100 / $cluster_size;
	my $max_percentage = $default_percentage * 1.5;
	my $min_percentage = $default_percentage * 0.5; 
	
		#Check if cluster size is bigger than 1
	if ($cluster_size < 2){
		print ("Segmentator: To use weighted round robin algorithm, cluster must be bigger than one host...Aborting\n");
		$allocation{"error"} = "error";
		return %allocation;
	}
		# Obtain cpudynamic dates 
	for (my $i=0; $i<$cluster_size; $i++) {
		my $cpu_dynamic = $cluster_info[$i]->{_cpudynamic};
		my $hostname = $cluster_info[$i]->{_hostname};
		print ("Segmentator: Dynamic CPU load of $hostname is $cpu_dynamic\n");
		$host_cpu_dynamic{$hostname} = $cpu_dynamic;
		$total_cpu += $cpu_dynamic;
	}
		
		# Check if some host has low cpu usage
	my @cluster_machines = keys(%host_cpu_dynamic);
	my $low_cpu_usage = 1;
	my $host_cpu;
	my $cluster_machines = @cluster_machines;
	for (my $j=0; $j<$cluster_machines; $j++) {
		$host_cpu = $host_cpu_dynamic{$cluster_machines[$j]};
		if ($host_cpu >= 0.2) {
			$low_cpu_usage = 0;
		} 
	}
	
	if ($low_cpu_usage) {
		print("Segmentator: cluster CPU load is low. Reverting to standard round robin mode\n");
		%allocation = round_robin->split($rdom_tree, $rcluster_hosts, $rvms_to_split, $rstatic_assignment);
		#%allocation = &round_robin($rdom_tree, $rcluster_hosts, $rvms_to_split, $rstatic_assignment);
		return %allocation;
	}
	
		# "Percentages" assignation
	my $fake_percentage = 0;
	for (my $i=0; $i<$cluster_size; $i++) {
		my $hostname = $cluster_info[$i]->{_hostname};
		$host_vm_percentage{$hostname} = (100.00-($host_cpu_dynamic{$hostname} / $total_cpu *100.00)) / ($cluster_size - 1);
		if ($host_vm_percentage{$hostname} < $min_percentage) {
			$host_vm_percentage{$hostname} = $min_percentage;
		}
		if ($host_vm_percentage{$hostname} > $max_percentage) {
			$host_vm_percentage{$hostname} = $max_percentage;
		}
		$fake_percentage += $host_vm_percentage{$hostname};
	}
		# Adjusting to real percentages
	for (my $i=0; $i<$cluster_size; $i++) {
		my $hostname = $cluster_info[$i]->{_hostname};
		$host_vm_percentage{$hostname} = 100 * $host_vm_percentage{$hostname} / $fake_percentage;
		print ("Segmentator: Assigned $host_vm_percentage{$hostname}% to $hostname\n");
	}
	
		# VMs assignation
	my $VMList = $scenario->getElementsByTagName("vm");		# Scenario virtual machines node list
	my $vm_number = $VMList->getLength;						# Number of virtual machines of scenario
	my %assigned_vm_number;
	my $already_assigned_vm_number;
		
	for (my $i=0; $i<$cluster_size-1; $i++) {
		my $hostname = $cluster_info[$i]->{_hostname};
		$assigned_vm_number{$hostname} = round ($host_vm_percentage{$hostname} * $vm_number / 100);
		$already_assigned_vm_number += $assigned_vm_number{$hostname};
		print("Segmentator: $assigned_vm_number{$hostname} VMs assigned to $hostname\n");
	}
		
	my $last_hostname = $cluster_info[$cluster_size-1]->{_hostname};
	$assigned_vm_number{$last_hostname} = $vm_number - $already_assigned_vm_number;
	print("Segmentator: $assigned_vm_number{$last_hostname} VMs assigned to $last_hostname\n");
	
	my $static_assignment_undef = 1;
	my @keys = keys (%static_assignment);
	my $j = 0;
	while (defined(my $key = $keys[$j])) {
		 $static_assignment_undef = 0;
		$j++;
	}
		
	if ($static_assignment_undef){
		my $j = 0;
		my $offset = 0;
		for (my $i=0; $i<$cluster_size; $i++) {
			my $hostname = $cluster_info[$i]->{_hostname};
			my $limit = $offset + $assigned_vm_number{$hostname};
			for ($j; $j<$limit; $j++) {
				my $virtualm = $VMList->item($j);
				my $virtualm_name = $virtualm->getAttribute("name");
				$allocation{$virtualm_name} = $hostname;
				print("Segmentator: Virtual machine $virtualm_name goes to physical host $hostname\n"); 	
				$offset++;
			}
		}
	} else {
			#  Obtain the number of virtual machines that have been assigned by explicit method
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
		my @keys = keys (%offset);
		my $j = 0;
		while (defined(my $key = $keys[$j])) {
			if ($offset{$key}>$assigned_vm_number{$key}){
				print ("  **** WARNING: Too many vms statically assigned to host $key ****\n");
				$assigned_vm_number{$key} = 0;
			} else {
				$assigned_vm_number{$key} = $assigned_vm_number{$key} - $offset{$key};
			}
					
			$j++;
		}
		
			# Assign all virtual machines
		my $vms_to_split_size = @vms_to_split;
		my $j = 0;
		my $offset = 0;
		for (my $i=0; $i<$cluster_size; $i++) {
			my $hostname = $cluster_info[$i]->{_hostname};
			my $limit = $offset + $assigned_vm_number{$hostname};
			for ($j; $j<$limit; $j++) {
				if ($vms_to_split_size > 0){
					my $virtualm = $vms_to_split[$j];
					$allocation{$virtualm} = $hostname;
					print("Segmentator: Virtual machine $virtualm goes to physical host $hostname\n"); 	
					$offset++;
					$vms_to_split_size--;
				}
			}
		}
	}

	#print("Segmentator: Done. Press RETURN key to continue or CONTROL-C to abort\n");
	#my $input = <STDIN>;

	return %allocation;

}
1
# Subroutines end
###########################################################