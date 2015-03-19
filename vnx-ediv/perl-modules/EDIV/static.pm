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
#                2011-2015 Dpto. Ingenieria de Sistemas Telematicos - UPM (VNX version)
# Authors: Fco. Jose Martin,
#          Miguel Ferrer
#          David Fernández
#          Departamento de Ingenieria de Sistemas Telematicos, Universidad Politécnica de Madrid
#

package static;

###########################################################
# Modules import
##########################################################

use strict;
use warnings;
use XML::LibXML;
use Math::Round;
use VNX::ClusterMgmt;
use VNX::DataHandler;
use VNX::Globals;
use VNX::Execution;


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
	
    my $restriction_file = $self->{restriction_file};

	# Check if restriction file exists
	unless (-r $restriction_file) {
        print "ERROR: cannot open restriction file... Aborting\n";
        return 1,
    }
	#open(FILEHANDLE, $restriction_file) or {
	#	print "ERROR: cannot open restriction file... Aborting\n",
	#	$errorCode = 1,
	#	return $errorCode,
	#};
	
	#my $parser = new XML::DOM::Parser;
	#$restriction_dom_tree = $parser->parsefile($restriction_file);
	my $parser = XML::LibXML->new();
    $restriction_dom_tree = $parser->parse_file($restriction_file);
	#close (FILEHANDLE);

	my $dom_tree = $self->{dom_tree};
	my $globalNode = $dom_tree->getElementsByTagName("vnx")->item(0);
	my $restrictionNode = $restriction_dom_tree->getElementsByTagName("deployment_restrictions")->item(0);
	
	
	# Get the list of VMs in scenario
	#my $virtualmList=$globalNode->getElementsByTagName("vm");
	my @scenarioVmList;
	my %vms;
	#for (my $i=0; $i<$virtualmList->getLength; $i++) {
	foreach my $vm ($globalNode->getElementsByTagName("vm")) {
        #my $vmName = $virtualmList->item($i)->getAttribute("name");
        #@scenarioVmList = (@scenarioVmList, $vm->getAttribute("name"));
        push @scenarioVmList, $vm->getAttribute("name");
		$vms{$vm->getAttribute("name")} = 1;	
	}

    # Get the list of <net> names in scenario
    #my $netNameList=$globalNode->getElementsByTagName("net");
    my @scenarioNetList;
    my %nets;
    #for (my $i=0; $i<$netNameList->getLength; $i++) {
    foreach my $net ($globalNode->getElementsByTagName("net")) {
        #my $netName = $netNameList->item($i)->getAttribute("name");
        push @scenarioNetList, $net->getAttribute("name");
        $nets{$net->getAttribute("name")} = 1;
    }

    # Get the list of host names from cluster
    my %hosts;
    #my @cluster_info = $self->{cluster_info};
    #my $cluster_size = $self->{cluster_size};
    #my @clusterHostList;
    #for (my $i=0; $i<$cluster_size; $i++) {
    foreach my $host (@cluster_hosts) {
        #my $hostname = $self->{cluster_info}[$i]->{_hostname};
        #my $hostname = $self->{cluster_info}[$i];
        #@clusterHostList = (@clusterHostList, $hostname);
        $hosts{$host} = 1;
    }
	
	#
	# Check vms names validity
	#
    # Check that all VM names cited in <vm_deploy_at> tags are valid VMs in scenario 
    foreach my $vm_deploy_at ($restrictionNode->getElementsByTagName("vm_deploy_at"))   {
        unless ($vms{$vm_deploy_at->getAttribute("vm")}) {
            print ("ERROR: VM '" . $vm_deploy_at->getAttribute("vm") ."' cited in <vm_deploy_at> tag in restriction file does not exist in scenario\n");
            return 1;        	
        }	
    }
    # Check that all VM names cited in <affinity> and <antiaffinity> tags are valid VMs in scenario 
    foreach my $tag ($restrictionNode->getElementsByTagName("affinity"), $restrictionNode->getElementsByTagName("antiaffinity")) {
        foreach my $vm ($tag->getElementsByTagName("vm")) {
            unless ($vms{$vm->getFirstChild->getData}) {
                print ("ERROR: VM '" . $vm->getFirstChild->getData ."' cited in <vm_deploy_*> tag in restriction file does not exist in scenario\n");
                return 1;           
            }   
        }
    }	

    #
    # Check net names validity
    #
    # Check that all net names cited in <net_deploy_at> tags are valid nets in scenario 
    foreach my $net_deploy_at ($restrictionNode->getElementsByTagName("net_deploy_at"))   {
        unless ($nets{$net_deploy_at->getAttribute("net")}) {
            print ("ERROR: net '" . $net_deploy_at->getAttribute("net") ."' cited in a <net_deploy_at> tag in restriction file does not exist in scenario\n");
            return 1;           
        }   
    }

    # Check that all net names cited in <net_deploy_together> tags are valid VMs in scenario 
    foreach my $net_deploy_together ($restrictionNode->getElementsByTagName("net_deploy_together")) {
        foreach my $net ($net_deploy_together->getElementsByTagName("net")) {
            unless ($nets{$net->getFirstChild->getData}) {
                print ("ERROR: VM '" . $net->getFirstChild->getData ."' cited in a <$net_deploy_together> tag in restriction file does not exist in scenario\n");
                return 1;           
            }   
        }
    }   

    #
    # Check host names validity
    #
    # Check that all host names cited in <vm_deploy_at> and <net_deploy_at> tags are valid hosts in cluster 
    foreach my $tag ($restrictionNode->getElementsByTagName("vm_deploy_at"), $restrictionNode->getElementsByTagName("net_deploy_at"))   {
        unless ($hosts{$tag->getAttribute("host")}) {
            print ("ERROR: host '" . $tag->getAttribute("host") ."' cited in a <*_deploy_at> tag in restriction file does not exist in cluster\n");
            return 1;           
        }   
    }

    # Check that the number of VMs listed in <antiaffinity> tags is not bigger that cluester size
    foreach my $antiaffinity ($restrictionNode->getElementsByTagName("antiaffinity")) {
        my @antiaffinity = $antiaffinity->getElementsByTagName("vm");
        if ( @antiaffinity > $self->{cluster_size}) {
            print ("ERROR: the number of VMs listed in <antiaffinity> tag (" . @antiaffinity . ") is bigger that cluster size (" . $self->{cluster_size} . ")\n");
            return 1;           
        }
    }   

    return $errorCode;

}


#
# Subroutine to assign virtual machines
#
# Reads the restrictions file and fills the %static_assignment hash according to the rules included in it
# 
sub assign {
	my $self = shift;
		
	my $errorCode = initial_check($self);
	if ($errorCode){
		$static_assignment{"__error__"} = "error";
		return %static_assignment;
	}

    my $restrictionNode = $restriction_dom_tree->getElementsByTagName("deployment_restrictions")->item(0);
    my $dom_tree = $self->{dom_tree};
    my $globalNode = $dom_tree->getElementsByTagName("vnx")->item(0);
    my $virtualmList=$globalNode->getElementsByTagName("vm");
	
	#
    # First step: process <net_deploy_at> tags
    #
    foreach my $net_deploy_at ($restrictionNode->getElementsByTagName("net_deploy_at")) {
    	
    	my $net_name  = $net_deploy_at->getAttribute("net");
        my $host_name = $net_deploy_at->getAttribute("host");
    	
    	# Get the list of VMs connected to that net
    	my ($vms_in_net,$ifs_in_net) = $dh->get_vms_in_a_net ($net_name);
    	
    	foreach my $vm (@$vms_in_net) {
            my $vm_name = $vm->getAttribute("name");
            if ( defined $static_assignment{$vm_name} && $static_assignment{$vm_name} ne $host_name) {
            	# If VM has already assigned to another host, we have a problem...
                print ("ERROR in net_deploy_at: trying to assing VM $vm_name to host $host_name but it was previously assigned to host $static_assignment{$vm_name}\n");
                $static_assignment{"__error__"} = "error";
                return %static_assignment;
            } else {
                $static_assignment{$vm_name} = $host_name;
            }
    	}    	
    }

    wlog (VV, "Static assignment after processing <net_deploy_at> tags");
    dump_static_assignment(VV);

    #
    # Second step: process <vm_deploy_at> tags
    #
    foreach my $vm_deploy_at ($restrictionNode->getElementsByTagName("vm_deploy_at")) {
        
        my $vm_name  = $vm_deploy_at->getAttribute("vm");
        my $host_name = $vm_deploy_at->getAttribute("host");
        
        if ( defined $static_assignment{$vm_name} && $static_assignment{$vm_name} ne $host_name) {
            # If VM has already assigned to another host, we have a problem...
            print ("ERROR in vm_deploy_at: trying to assing VM $vm_name to host $host_name but it was previously assigned to host $static_assignment{$vm_name}\n");
            $static_assignment{"__error__"} = "error";
            return %static_assignment;
        } else {
            $static_assignment{$vm_name} = $host_name;
        }       
    }

    wlog (VV, "Static assignment after processing <vm_deploy_at> tags");
    dump_static_assignment(VV);

    #
    # Third step: process <affinity> tags
    #
    my $i=0;
    foreach my $affinity ($restrictionNode->getElementsByTagName("affinity")) {
        my @vms = $affinity->getElementsByTagName("vm");

        # Check if any of the VMs in <affinity> has already been assigned to a host.
        # In that case, deploy all VMs in <affinity> to thet host.
        # If two or more VMs have been already assigned to different hosts give and error.
        my $host_name;
        my $host_name_vm;
        foreach my $vm (@vms) {
            my $vm_name = $vm->getFirstChild->getData;
            if ( defined $static_assignment{$vm_name} && defined $host_name && $static_assignment{$vm_name} ne $host_name ) {
                print "ERROR: cannot enforce <affinity> rule, VM $vm_name is assigned to host" . $static_assignment{$vm_name} . 
                       " but other VM ($host_name_vm) in <affinity> has already been assigned to host $host_name\n";
	            $static_assignment{"__error__"} = "error";
	            return %static_assignment;
            } elsif ( defined $static_assignment{$vm_name} ) {
            	$host_name = $static_assignment{$vm_name};
            	$host_name_vm = $vm_name;
            }
        }        	

        unless ($host_name) {
        	# No assigment made for any VM. Choose a host and assign all VMs to that host 
            my $cluster_size = $self->{cluster_size};
            $host_name = $self->{cluster_info}[$i % $cluster_size];
        }
        # Assign all VMs to that host
        foreach my $vm (@vms) {
            $static_assignment{$vm->getFirstChild->getData} = $host_name;
        }
        $i++;       	 
    }

    wlog (VV, "Static assignment after processing <affinity> tags");
    dump_static_assignment(VV);
    
    #
    # Fourth step: process <net_deploy_together> tags
    #
    # Same procedure that <net_deploy_at> but the host is not specified
    #
    foreach my $net_deploy_at ($restrictionNode->getElementsByTagName("net_deploy_at")) {
        
        my $net_name  = $net_deploy_at->getAttribute("net");
     
        # Choose deployment host for the net 
        my $host_name = $self->{cluster_info}[$i % $self->{cluster_size}];
        $i++;
     
        # Get the list of VMs connected to that net
        my ($vms_in_net,$ifs_in_net) = $dh->get_vms_in_a_net ($net_name);
        
        foreach my $vm (@$vms_in_net) {
            my $vm_name = $vm->getAttribute("name");
            if ( defined $static_assignment{$vm_name} && $static_assignment{$vm_name} ne $host_name) {
                # If VM has already assigned to another host, we have a problem...
                print ("ERROR in net_deploy_together: trying to assing VM $vm_name to host $host_name but it was previously assigned to host $static_assignment{$vm_name}\n");
                $static_assignment{"__error__"} = "error";
                return %static_assignment;
            } else {
                $static_assignment{$vm_name} = $host_name;
            }
        }       
    }

    wlog (VV, "Static assignment after processing <net_deploy_at> tags");
    dump_static_assignment(VV);

    #
    # Fith step: process <antiaffinity> tags
    #

    foreach my $antiaffinity ($restrictionNode->getElementsByTagName("antiaffinity")) {
    	
    	my %vms_hosts;
    	my @vms = $antiaffinity->getElementsByTagName("vm");
	    # First, check what vms already assigned are assigned to different hosts
	    foreach my $vm (@vms) {
	    	my $vm_name = $vm->getFirstChild->getData;
	    	if (defined $static_assignment{$vm_name} && $vms_hosts{$static_assignment{$vm_name}}) {
                print "ERROR: cannot enforce <antiaffinity> rule, VM $vm_name is assigned to host '" . $static_assignment{$vm_name} . 
                       "' but other VM (" . $vms_hosts{$static_assignment{$vm_name}} . ") in <antiaffinity> has already been assigned to that host\n";
                $static_assignment{"__error__"} = "error";
                return %static_assignment;
	    	} else {
	    		$vms_hosts{$static_assignment{$vm_name}} = $vm_name;
	    	}
	    }
    	# Second, assign remaining vms to different hosts
        foreach my $vm (@vms) {
            my $vm_name = $vm->getFirstChild->getData;
            next if ($static_assignment{$vm_name});
	        # Look for a host not used and assign it to the VM 
            while ( $vms_hosts{ $self->{cluster_info}[$i % $self->{cluster_size}] } ) {
            	$i++;
            }
	        my $host_name = $self->{cluster_info}[$i % $self->{cluster_size}];
            $static_assignment{$vm_name} = $host_name;
	        $i++;
        }    	
    }    

    wlog (VV, "Static assignment after processing <antiaffinity> tags");
    dump_static_assignment(VV);
    	
	return %static_assignment;


=BEGIN    
    #my $net_deploy_at= $restrictionNode->getElementsByTagName("net_deploy_at");
    #if (!($net_deploy_at eq undef)){
    #   for (my $i=0; $i<$net_deploy_at->getLength; $i++) {
    #       my $netName = $net_deploy_at->item($i)->getAttribute("net");
    #       @restrictionNetList = (@restrictionNetList, $netName);
    #   }
    #}
    
    my %netVms;
    my $restrictionNetListSize = @restrictionNetList;
    # Fill %netVms with name of net and the vms that belong to that net
    for (my $i=0; $i<$restrictionNetListSize; $i++) {
        
        my $netRestrictionName = $restrictionNetList[$i];
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
        
    foreach my $net_deploy_at (@net_deploy_at_list) {
    #for (my $i=0; $i<$net_deploy_at->getLength; $i++) {
        my $netName = $net_deploy_at->getAttribute("net");
        my $hostName = $net_deploy_at->getAttribute("host");
        my $vmsToAppend = $netVms{$netName};
        
        my $j = 0;
        while (defined(my $vmToAppend = $vmsToAppend->[$j])) {
            if (!($static_assignment{$vmToAppend} eq $hostName) && !($static_assignment{$vmToAppend} eq undef)){
                print ("ERROR net_deploy_at: Trying to assing vm $vmToAppend to host $hostName but was previously assigned to host $static_assignment{$vmToAppend} ... Aborting\n");
                $static_assignment{"__error__"} = "error";
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
                $static_assignment{"__error__"} = "error";
                return %static_assignment;
            }
            $static_assignment{$vmName} = $hostName;        
        }
    }

    # THIRD RULE    
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
                        $static_assignment{"__error__"} = "error";
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
                $vmName = $vmAffinityList->item($i)->getFirstChild->getData;
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
        
        my $netRestrictionName = $restrictionNetList[$i];
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
        
        my $netRestrictionName = $restrictionNetList[$i];
        #my $netName = $net_deploy_together->item($i)->getAttribute("net");
        my $netVmList = $netVms{$netRestrictionName};
        my $hostName;
        
        my $j = 0;
        while (defined(my $vmName = $netVmList->[$j])) {
            if (!($static_assignment{$vmName} eq undef)) {
                if (!($static_assignment{$vmName} eq $hostName) && !($hostName eq undef) ) {
                    print("ERROR net_deploy_together: Trying to assing vm $vmName to host $hostName but was previously assigned to host $static_assignment{$vmName} ... Aborting\n");
                    $static_assignment{"__error__"} = "error";
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
                            $static_assignment{"__error__"} = "error";
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
                        $static_assignment{"__error__"} = "error";
                        return %static_assignment;
                    }
                    $static_assignment{$vmName} = $hostName;            
                }
            }
        }
    }
    
=END
=cut        


}

sub dump_static_assignment {
	        
    my $verbosity = shift;
    	        
    my @keys = keys (%static_assignment);
    my $j = 0;
    wlog ($verbosity, sprintf ("  %-20s %-20s", 'vm', 'host') );
    while (defined(my $key = $keys[$j])) {
        wlog ($verbosity, sprintf ("  %-20s %-20s", $key, $static_assignment{$key}) );
        $j++;
    }

}



	###########################################################
	# Subroutine to obtain vms to split
	###########################################################
sub remaining {
	my $self = shift;
	
	#my $dom_tree = $self->{dom_tree};
	#my $globalNode = $dom_tree->getElementsByTagName("vnx")->item(0);
	#my $virtualmList=$globalNode->getElementsByTagName("vm");
	my @scenarioVmList;
	#for (my $i=0; $i<$virtualmList->getLength; $i++) {
	foreach my $vm ($self->{dom_tree}->getElementsByTagName("vm")) {
        my $vm_name = $vm->getAttribute("name");
        unless ($static_assignment{$vm_name}){
            push @vms_to_split, $vm_name;
        }
	}
	return @vms_to_split;	
}


1
# Subroutines end
###########################################################