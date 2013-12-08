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

package static;

###########################################################
# Modules import
##########################################################

use strict;
use XML::DOM;
use Math::Round;

###########################################################
# Global variables 
###########################################################

my $restriction_dom_tree;
my %static_assignment;
my @vms_to_split;

###########################################################
# Subroutines
###########################################################
	
#
# Constructor
#
sub new {
	my ( $class, $restriction_file, $dom_tree, @cluster_info ) = @_;
	
	my $cluster_size = @cluster_info;
	
	my $self = {
		'restriction_file' => $restriction_file,		# Dom tree containing scenario specification
		'dom_tree' => $dom_tree,						# Scenario splitting algorithm
		'cluster_size' => $cluster_size,				# Number of physical cluster host
		'cluster_info' => [@cluster_info],				# Array of cluster host objects								
	};
	bless( $self, $class );
	return $self;
}

#
# Subroutine to check basic rules
#
sub initial_check {
	
	my $errorCode = 0;
	my $self = shift;
		# Check if restriction file exists
	my $restriction_file = $self->{restriction_file};
	open(FILEHANDLE, $restriction_file) or {
		print ("ERROR: cannot open restriction file... Aborting\n"),
		$errorCode = 1,
		return $errorCode,
	};
	
	my $parser = new XML::DOM::Parser;
	$restriction_dom_tree = $parser->parsefile($restriction_file);
	close (FILEHANDLE);
		# Get VM names from scenario file
	my $dom_tree = $self->{dom_tree};
	my $globalNode = $dom_tree->getElementsByTagName("vnx")->item(0);
	my $virtualmList=$globalNode->getElementsByTagName("vm");
	my @scenarioVmList;
	for (my $i=0; $i<$virtualmList->getLength; $i++) {
			my $vmName = $virtualmList->item($i)->getAttribute("name");
			@scenarioVmList = (@scenarioVmList, $vmName);
	}
		# Get VM names from restriction file
	my $restrictionNode = $restriction_dom_tree->getElementsByTagName("deployment_restrictions")->item(0);
	my @restrictionVmList;
	my $vm_deploy_at = $restrictionNode->getElementsByTagName("vm_deploy_at");
	if (!($vm_deploy_at eq undef)){
		for (my $i=0; $i<$vm_deploy_at->getLength; $i++) {
			my $vmName = $vm_deploy_at->item($i)->getAttribute("vm");
			@restrictionVmList = (@restrictionVmList, $vmName);
		}
	}
	
	my $affinityList = $restrictionNode->getElementsByTagName("affinity");
	for (my $j=0; $j<$affinityList->getLength; $j++ ){
		my $affinity = $affinityList->item($j);
		if (!($affinity eq undef)){
			my $vmAffinityList = $affinity->getElementsByTagName("vm");
			for (my $i=0; $i<$vmAffinityList->getLength; $i++) {
				my $vmName = $vmAffinityList->item($i)->getFirstChild->getData;
				@restrictionVmList = (@restrictionVmList, $vmName);
			}
		}
	}
	
	my $antiAffinityList = $restrictionNode->getElementsByTagName("antiaffinity");
	for (my $j=0; $j<$antiAffinityList->getLength; $j++ ){
	
		my $antiaffinity = $antiAffinityList->item($j);
		if (!($antiaffinity eq undef)){
			my $vmAntiAffinityList = $antiaffinity->getElementsByTagName("vm");
			for (my $i=0; $i<$vmAntiAffinityList->getLength; $i++) {
				my $vmName = $vmAntiAffinityList->item($i)->getFirstChild->getData;
				@restrictionVmList = (@restrictionVmList, $vmName);
			}
		}
	}
	
		# Check if restriction file vm names are in scenario file
	my $restrictionVmListSize = @restrictionVmList;
	my $scenarioVmListSize = @scenarioVmList;
	for (my $i=0; $i<$restrictionVmListSize; $i++) {
		my $match = 0;
		my $vmRestrictionName = @restrictionVmList[$i];
		for (my $j=0; $j<$scenarioVmListSize; $j++) {
			my $vmScenarioName = @scenarioVmList[$j];
			if($vmRestrictionName eq $vmScenarioName) {
				$match = 1;
				last;			
			}
		}
		if ($match == 0){
			print ("ERROR: The vm $vmRestrictionName from restriction file doesn't exist in this scenario... Aborting\n");
			$errorCode = 1;
			return $errorCode;
		}
	}
		# Get net names from scenario file
	my $netNameList=$globalNode->getElementsByTagName("net");
	my @scenarioNetList;
	for (my $i=0; $i<$netNameList->getLength; $i++) {
			my $netName = $netNameList->item($i)->getAttribute("name");
			@scenarioNetList = (@scenarioNetList, $netName);
	}
		# Get net names from restriction file
	my @restrictionNetList;
	my $net_deploy_together= $restrictionNode->getElementsByTagName("net_deploy_together");
	if (!($net_deploy_together eq undef)){
		for (my $i=0; $i<$net_deploy_together->getLength; $i++) {
			my $netName = $net_deploy_together->item($i)->getAttribute("net");
			@restrictionNetList = (@restrictionNetList, $netName);
		}
	}
	
	my $net_deploy_at= $restrictionNode->getElementsByTagName("net_deploy_at");
	if (!($net_deploy_at eq undef)){
		for (my $i=0; $i<$net_deploy_at->getLength; $i++) {
			my $netName = $net_deploy_at->item($i)->getAttribute("net");
			@restrictionNetList = (@restrictionNetList, $netName);
		}
	}
		# Check if restriction file net names are in scenario file
	my $restrictionNetListSize = @restrictionNetList;
	my $scenarioNetListSize = @scenarioNetList;
	for (my $i=0; $i<$restrictionNetListSize; $i++) {
		my $match = 0;
		my $netRestrictionName = @restrictionNetList[$i];
		for (my $j=0; $j<$scenarioNetListSize; $j++) {
			my $netScenarioName = @scenarioNetList[$j];
			if($netRestrictionName eq $netScenarioName) {
				$match = 1;
				last;			
			}
		}
		if ($match == 0){
			print ("ERROR: The net $netRestrictionName from restriction file doesn't exist in this scenario... Aborting\n");
			$errorCode = 1;
			return $errorCode;
		}
	}
		# Get host names from cluster
	my @cluster_info = $self->{cluster_info};
	my $cluster_size = $self->{cluster_size};
	my @clusterHostList;
	for (my $i=0; $i<$cluster_size; $i++) {
        #my $hostname = $self->{cluster_info}[$i]->{_hostname};
        my $hostname = $self->{cluster_info}[$i];
		@clusterHostList = (@clusterHostList, $hostname);
	}
		# Get host names from restriction file
	my @restrictionHostList;
	if (!($vm_deploy_at eq undef)){
		for (my $i=0; $i<$vm_deploy_at->getLength; $i++) {
			my $hostName = $vm_deploy_at->item($i)->getAttribute("host");
			@restrictionHostList = (@restrictionHostList, $hostName);
		}
	}
	
	if (!($net_deploy_at eq undef)){
		for (my $i=0; $i<$net_deploy_at->getLength; $i++) {
			my $hostName = $net_deploy_at->item($i)->getAttribute("host");
			@restrictionHostList = (@restrictionHostList, $hostName);
		}
	}
		# Check if restriction file host names are in cluster
	my $restrictionHostListSize = @restrictionHostList;
	my $clusterHostListSize = @clusterHostList;
	for (my $i=0; $i<$restrictionHostListSize; $i++) {
		my $match = 0;
		my $hostRestrictionName = @restrictionHostList[$i];
		for (my $j=0; $j<$clusterHostListSize; $j++) {
			my $hostClusterName = @clusterHostList[$j];
			if($hostRestrictionName eq $hostClusterName) {
				$match = 1;
				last;			
			}
		}
		if ($match == 0){
			print ("ERROR: The host $hostRestrictionName from restriction file doesn't exist in this scenario... Aborting\n");
			$errorCode = 1;
			return $errorCode;
		}
	}
		
	for (my $j=0; $j<$antiAffinityList->getLength; $j++ ){
	
		my $antiaffinity = $antiAffinityList->item($j);
		if (!($antiaffinity eq undef)){
			my $vmAntiAffinityList = $antiaffinity->getElementsByTagName("vm");
			my $antiAffinityVmNumber = $vmAntiAffinityList->getLength;
			if ($antiAffinityVmNumber > $cluster_size) {
				print ("ERROR: Antiaffinity vm size is bigger than cluster host size... Aborting\n");
				$errorCode = 1;
				return $errorCode;
			}
		}
	}
	return $errorCode;
}


#
# Subroutine to assign virtual machines
#
sub assign {
	my $self = shift;
		
	my $errorCode = &initial_check($self);
	if ($errorCode){
		$static_assignment{"error"} = "error";
		return %static_assignment;
	}
	
		# FIRST RULE: net_deploy_at
	my @restrictionNetList;
	my $restrictionNode = $restriction_dom_tree->getElementsByTagName("deployment_restrictions")->item(0);
	my $net_deploy_at= $restrictionNode->getElementsByTagName("net_deploy_at");
	if (!($net_deploy_at eq undef)){
		for (my $i=0; $i<$net_deploy_at->getLength; $i++) {
			my $netName = $net_deploy_at->item($i)->getAttribute("net");
			@restrictionNetList = (@restrictionNetList, $netName);
		}
	}
	my $dom_tree = $self->{dom_tree};
	my $globalNode = $dom_tree->getElementsByTagName("vnx")->item(0);
	my $virtualmList=$globalNode->getElementsByTagName("vm");
	
	my %netVms;
	my $restrictionNetListSize = @restrictionNetList;
		# Fill %netVms with name of net and the vms that belong to that net
	for (my $i=0; $i<$restrictionNetListSize; $i++) {
		
		my $netRestrictionName = @restrictionNetList[$i];
		my $index = 0;
		my $currentNetVms;
		for (my $n=0; $n<$virtualmList->getLength; $n++) {
			my $currentVM=$virtualmList->item($n);
			my $nameOfVM=$currentVM->getAttribute("name");
			my $interfaces=$currentVM->getElementsByTagName("if");

			for (my $k=0; $k<$interfaces->getLength; $k++) {
				my $netName = $interfaces->item($k)->getAttribute("net");
				if ($netRestrictionName eq $netName) {
					$currentNetVms->[$index] = $nameOfVM;
					$index++;
				}
			$netVms{$netRestrictionName} = $currentNetVms;
			}
		}
	}
	for (my $i=0; $i<$net_deploy_at->getLength; $i++) {
		my $netName = $net_deploy_at->item($i)->getAttribute("net");
		my $hostName = $net_deploy_at->item($i)->getAttribute("host");
		my $vmsToAppend = $netVms{$netName};
		
		my $j = 0;
		while (defined(my $vmToAppend = $vmsToAppend->[$j])) {
			if (!($static_assignment{$vmToAppend} eq $hostName) && !($static_assignment{$vmToAppend} eq undef)){
				print ("ERROR net_deploy_at: Trying to assing vm $vmToAppend to host $hostName but was previously assigned to host $static_assignment{$vmToAppend} ... Aborting\n");
				$static_assignment{"error"} = "error";
				return %static_assignment;
			}
			$static_assignment{$vmToAppend} = $hostName;
			$j++;
		}
	}
		
		# SECOND RULE: vm_deploy_at
	my $vm_deploy_at = $restrictionNode->getElementsByTagName("vm_deploy_at");
	if (!($vm_deploy_at eq undef)){
		for (my $i=0; $i<$vm_deploy_at->getLength; $i++) {
			my $vmName = $vm_deploy_at->item($i)->getAttribute("vm");
			my $hostName = $vm_deploy_at->item($i)->getAttribute("host");
			if (!($static_assignment{$vmName} eq $hostName) && !($static_assignment{$vmName} eq undef)){
				print ("ERROR vm_deploy_at: Trying to assing vm $vmName to host $hostName but was previously assigned to host $static_assignment{$vmName} ... Aborting\n");
				$static_assignment{"error"} = "error";
				return %static_assignment;
			}
			$static_assignment{$vmName} = $hostName;		
		}
	}
	
		# THIRD RULE: affinity
	my $affinityList = $restrictionNode->getElementsByTagName("affinity");

	for (my $j=0; $j<$affinityList->getLength; $j++ ){
		my $affinity = $affinityList->item($j);
		if (!($affinity eq undef)){
			my $vmAffinityList = $affinity->getElementsByTagName("vm");
			my $hostName;
			for (my $i=0; $i<$vmAffinityList->getLength; $i++) {
				my $vmName = $vmAffinityList->item($i)->getFirstChild->getData;
				if (!($static_assignment{$vmName} eq undef)) {
					if (!($static_assignment{$vmName} eq $hostName) && !($hostName eq undef) ) {
						print("ERROR affinity: Trying to assing vm $vmName to host $hostName but was previously assigned to host $static_assignment{$vmName} ... Aborting\n");
						$static_assignment{"error"} = "error";
						return %static_assignment;
					}
					$hostName = $static_assignment{$vmName};
				}				
			}
			for (my $i=0; $i<$vmAffinityList->getLength; $i++) {
				my $vmName = $vmAffinityList->item($i)->getFirstChild->getData;
				if ($hostName eq undef){
					my $cluster_size = $self->{cluster_size};
					my $index = $j % $cluster_size;
                    #$hostName = $self->{cluster_info}[$index]->{_hostname};
                    $hostName = $self->{cluster_info}[$index];
				}
				my $vmName = $vmAffinityList->item($i)->getFirstChild->getData;
				$static_assignment{$vmName} = $hostName;
			}
		}
	}

		# FOURTH RULE: net_deploy_together
	my @restrictionNetList;
	my $net_deploy_together = $restrictionNode->getElementsByTagName("net_deploy_together");
	if (!($net_deploy_together eq undef)){
		for (my $i=0; $i<$net_deploy_together->getLength; $i++) {
			my $netName = $net_deploy_together->item($i)->getAttribute("net");
			@restrictionNetList = (@restrictionNetList, $netName);
		}
	}

	my %netVms;
	$restrictionNetListSize = @restrictionNetList;
		# Fill %netVms with name of net and the vms that belong to that net
	for (my $i=0; $i<$restrictionNetListSize; $i++) {
		
		my $netRestrictionName = @restrictionNetList[$i];
		my $index = 0;
		my $currentNetVms;
		for (my $n=0; $n<$virtualmList->getLength; $n++) {
			my $currentVM=$virtualmList->item($n);
			my $nameOfVM=$currentVM->getAttribute("name");
			my $interfaces=$currentVM->getElementsByTagName("if");

			for (my $k=0; $k<$interfaces->getLength; $k++) {
				my $netName = $interfaces->item($k)->getAttribute("net");
				if ($netRestrictionName eq $netName) {
					$currentNetVms->[$index] = $nameOfVM;
					$index++;
				}
			$netVms{$netRestrictionName} = $currentNetVms;
			}
		}
	}
	
	for (my $i=0; $i<$net_deploy_together->getLength; $i++) {
		
		my $netRestrictionName = @restrictionNetList[$i];
		#my $netName = $net_deploy_together->item($i)->getAttribute("net");
		my $netVmList = $netVms{$netRestrictionName};
		my $hostName;
		
		my $j = 0;
		while (defined(my $vmName = $netVmList->[$j])) {
			if (!($static_assignment{$vmName} eq undef)) {
				if (!($static_assignment{$vmName} eq $hostName) && !($hostName eq undef) ) {
					print("ERROR net_deploy_together: Trying to assing vm $vmName to host $hostName but was previously assigned to host $static_assignment{$vmName} ... Aborting\n");
					$static_assignment{"error"} = "error";
					return %static_assignment;
				}
				$hostName = $static_assignment{$vmName};
			}else {
                #$hostName = $self->{cluster_info}[$0]->{_hostname};
                $hostName = $self->{cluster_info}[$0];
			}
			$j++;
		}
		
		my $k = 0;
		while (defined(my $vmName = $netVmList->[$k])) {
			$static_assignment{$vmName} = $hostName;
			$k++;
		}
	}
	
		# FIFTH RULE: antiaffinity
		# First, check what vms are already assigned
	my $antiAffinityList = $restrictionNode->getElementsByTagName("antiaffinity");
	for (my $j=0; $j<$antiAffinityList->getLength; $j++ ){
	
		my $antiaffinity = $antiAffinityList->item($j);
		if (!($antiaffinity eq undef)){
			my $vmAntiAffinityList = $antiaffinity->getElementsByTagName("vm");
			my %antiaffinityHash;
			for (my $i=0; $i<$vmAntiAffinityList->getLength; $i++) {
				my $vmName = $vmAntiAffinityList->item($i)->getFirstChild->getData;
				if (!($static_assignment{$vmName} eq undef)) {
					$antiaffinityHash{$vmName} = $static_assignment{$vmName};
				}
			}
		
			my @keys = keys (%antiaffinityHash);
			my $j = 0;
			while (defined(my $key = $keys[$j])) {
				my $hostName = $antiaffinityHash{$key};
				my $k = 0;
				while (defined(my $keyToCompare = $keys[$k])) {
					if (!($j == $k)) {
						my $hostNameToCompare = $antiaffinityHash{$keyToCompare};
						if ($hostName eq $hostNameToCompare) {
							print ("ERROR antiaffinity: the vm $key and the vm $keyToCompare are assigned to the same host... Aborting\n");
							$static_assignment{"error"} = "error";
							return %static_assignment;
						}
					}
					$k++;
				}
				$j++;
			}
		
			# Second, assign remaining vms to different hosts
			my $vmAntiAffinityList = $antiaffinity->getElementsByTagName("vm");
			my %antiaffinityHash;
			my @restrictionVmList;
			for (my $i=0; $i<$vmAntiAffinityList->getLength; $i++) {
				my $vmName = $vmAntiAffinityList->item($i)->getFirstChild->getData;
				@restrictionVmList = (@restrictionVmList, $vmName);
			}
		
			my @unavailableHostList;
			for (my $i=0; $i<$vmAntiAffinityList->getLength; $i++) {
				my $vmName = $vmAntiAffinityList->item($i)->getFirstChild->getData;
			
				if (!($static_assignment{$vmName} eq undef)) {
					@unavailableHostList = (@unavailableHostList, $static_assignment{$vmName});
				} 				
			}
				# Get available host names from cluster
			my @cluster_info = $self->{cluster_info};
			my $cluster_size = $self->{cluster_size};
			my @availableHostList;
			for (my $i=0; $i<$cluster_size; $i++) {
                #my $hostname = $self->{cluster_info}[$i]->{_hostname};
                my $hostname = $self->{cluster_info}[$i];
				my $j = 0;
				my $available = 1;
				while (defined(my $unavailableHost = $unavailableHostList[$j])) {
					if ($unavailableHost eq $hostname) { 
						$available = 0; 
					}
					$j++;
				}
				if ($available) {
					@availableHostList = (@availableHostList, $hostname);
				}
			}
			for (my $i=0; $i<$vmAntiAffinityList->getLength; $i++) {
				my $vmName = $vmAntiAffinityList->item($i)->getFirstChild->getData;
				if ($static_assignment{$vmName} eq undef) {
					my $hostName = pop (@availableHostList);
					if ($hostName eq undef) {
						print ("ERROR antiaffinity: there aren't available host to assign to vm $vmName... Aborting\n");
						$static_assignment{"error"} = "error";
						return %static_assignment;
					}
					$static_assignment{$vmName} = $hostName;			
				}
			}
		}
	}
	
	my @keys = keys (%static_assignment);
	my $j = 0;
	while (defined(my $key = $keys[$j])) {
		my $hostName = $static_assignment{$key};
		print("Static assignment: Virtual machine $key to physical host $hostName\n");
		$j++;
	}
	return %static_assignment;
}


	###########################################################
	# Subroutine to obtain vms to split
	###########################################################
sub remaining {
	my $self = shift;
	
	my $dom_tree = $self->{dom_tree};
	my $globalNode = $dom_tree->getElementsByTagName("vnx")->item(0);
	my $virtualmList=$globalNode->getElementsByTagName("vm");
	my @scenarioVmList;
	for (my $i=0; $i<$virtualmList->getLength; $i++) {
			my $vmName = $virtualmList->item($i)->getAttribute("name");
			if ($static_assignment{$vmName} eq undef){
				@vms_to_split = (@vms_to_split, $vmName);
			}
	}
	
	return @vms_to_split;	
}
1
# Subroutines end
###########################################################