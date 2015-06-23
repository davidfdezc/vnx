# vmAPI_nsrouter.pm
#
# This file is a module part of VNX package.
#
# Authors: David Fernández
# Coordinated by: David Fernández (david@dit.upm.es)
#
# Copyright (C) 2014   DIT-UPM
#           Departamento de Ingenieria de Sistemas Telematicos
#           Universidad Politecnica de Madrid
#           SPAIN
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

package VNX::vmAPI_nsrouter;

use strict;
use warnings;
use Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
  init
  define_vm
  undefine_vm
  start_vm
  shutdown_vm
  suspend_vm
  resume_vm
  save_vm
  restore_vm
  get_state_vm
  execute_cmd
  );


use Sys::Virt;
use Sys::Virt::Domain;
use VNX::Globals;
use VNX::DataHandler;
use VNX::Execution;
use VNX::BinariesData;
use VNX::CheckSemantics;
use VNX::TextManipulation;
use VNX::NetChecks;
use VNX::FileChecks;
use VNX::DocumentChecks;
use VNX::IPChecks;
use VNX::vmAPICommon;
use File::Basename;
use XML::LibXML;


# ---------------------------------------------------------------------------------------
#
# Module vmAPI_nsrouter initialization code 
#
# ---------------------------------------------------------------------------------------
sub init {

    my $logp = "nsrouter-init> ";
    my $error;
    
    return unless ( $dh->any_vmtouse_of_type('nsrouter') );
    
    return $error;
}

# ---------------------------------------------------------------------------------------
#
# define_vm
#
# Defines a nsrouter
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. lxc)
#   - $vm_doc: XML document describing the virtual machines
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub define_vm {

    my $self    = shift;
    my $vm_name = shift;
    my $type    = shift;
    my $vm_doc  = shift;

    my $logp = "nsrouter-define_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);
    my $error;
    my $extConfFile;

    my $doc = $dh->get_doc;                                # scenario global doc
    my $vm = $vm_doc->findnodes("/create_conf/vm")->[0];   # VM node in $vm_doc
    my @vm_ordered = $dh->get_vm_ordered;                  # ordered list of VMs in scenario 
    my $exec_mode   = $dh->get_vm_exec_mode($vm);
    
    # Check if a name space with the same name exists
    if ( `ip netns list | egrep ^$vm_name\$` ) {
        $error = "A Linux name space named $vm_name already exists.";
        return $error;
    }

change_to_root();

    # Create a new name space for the router
    $execution->execute( $logp, $bd->get_binaries_path_ref->{"ip"} . " netns add $vm_name");

    #
    # Configure network interfaces
    #   
    foreach my $if ($vm->getElementsByTagName("if")) {
        my $id  = $if->getAttribute("id");
        my $net = $if->getAttribute("net");
        my $mac = $if->getAttribute("mac");
        my $net_mode = $dh->get_net_mode($net);
        
        $mac =~ s/,//; # TODO: why is there a comma before mac addresses?
        # create veth interface pair
        # ip link add $NS-e1 type veth peer name $NS-eth1 addr 00:01:02:aa:bb:cc
        my $if_name  = "${vm_name}-e$id";
        my $if_name2 = "${vm_name}-eth$id";
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"ip"} . " link add $if_name type veth peer name $if_name2 addr $mac");
        # Move the veth interface router side to router name space
        # ip link set $NS-eth1 netns $NS
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"ip"} . " link set $if_name2 netns $vm_name");
        # Attach interface to bridge  (not needed, done in vnx.pl)
        # brctl addif Net0 $NS-e1 
        #if ($net_mode eq "virtual_bridge") {
        #    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addif $net $if_name");
        #} elsif ($net_mode eq "openvswitch") {
        #    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-port $net $if_name");
        #}
        # Configure router network interface
        # ip netns exec $NS ifconfig $NS-eth1 10.1.1.1/24 up

        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");
        my @ipv4_addr_list;
        my @ipv4_mask_list;
        my @ipv6_addr_list;
        my @ipv6_mask_list;
        if ( (@ipv4_tag_list != 0 ) || ( @ipv6_tag_list != 0 ) ) {
            # Config IPv4 addresses
            for ( my $j = 0 ; $j < @ipv4_tag_list ; $j++ ) {

                my $ipv4 = $ipv4_tag_list[$j];
                my $mask = $ipv4->getAttribute("mask");
                my $ip   = $ipv4->getFirstChild->getData;

                if ($ip eq 'dhcp') {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ifconfig $if_name2 dhcp");
                } else {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ip addr add $ip/$mask dev $if_name2");
                }
            }
            # Config IPv6 addresses
            for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

                my $ipv6 = $ipv6_tag_list[$j];
                my $ip   = $ipv6->getFirstChild->getData;
                my $mask = $ip;
                $mask =~ s/.*\///;
                $ip =~ s/\/.*//;

                if ($ip eq 'dhcp') {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ifconfig $if_name2 inet6 dhcp");
                } else {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ip -6 addr add $ip/$mask dev $if_name2");
                }
            }
        }
        # Set the interface down (start_vm will change it to up)
        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ip link set $if_name2 down");
        # Note: network routers are configured in start_vm, after enablying interfaces
        
        #if ( str($net) eq "lo" ) { next }

back_to_user();     

    }                       

    return $error;

}

# ---------------------------------------------------------------------------------------
#
# undefine_vm
#
# Undefines a LXC virtual machine, deleting all associated state and files 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. lxc)
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub undefine_vm {

    my $self      = shift;
    my $vm_name   = shift;
    my $type      = shift;

    my $logp = "nsrouter-undefine_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;
    my $con;

    my $doc = $dh->get_vm_doc($vm_name,'dom');
    my $vm  = $doc->getElementsByTagName("vm")->item(0);    

change_to_root();

    # Destroy the name space for the router
    $execution->execute( $logp, $bd->get_binaries_path_ref->{"ip"} . " netns del $vm_name");

    foreach my $if ($vm->getElementsByTagName("if")) {
        my $id  = $if->getAttribute("id");
        my $if_name  = "${vm_name}-e$id";
        # Destroy the interface 
        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link del $if_name up");
    }
back_to_user();     

    return $error;
}

#---------------------------------------------------------------------------------------
#
# start_vm
#
# Starts a LXC virtual machine. The VM should already be in 'defined' state. 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
#   - $no_consoles: if true, virtual machine consoles are not opened
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub start_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;
    my $no_consoles = shift;

    my $logp = "nsrouter-start_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    my $doc = $dh->get_vm_doc($vm_name,'dom');
    my $vm  = $doc->getElementsByTagName("vm")->item(0);    

    foreach my $if ($vm->getElementsByTagName("if")) {
        my $id  = $if->getAttribute("id");
        my $if_name2 = "${vm_name}-eth$id";
        # Set the interface up 
        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ip link set $if_name2 up");
    }

    #
    # Configure network routes
    #
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ($route_type eq 'ipv4') {
            if ($route eq 'default') {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ip -4 route add default via $route_gw");                 
            } else {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ip -4 route add $route via $route_gw");                 
            }
        } elsif ($route_type eq 'ipv6') {
            if ($route eq 'default') {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ip -6 route add default via $route_gw");                 
            } else {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ip -6 route add $route via $route_gw");                 
            }
        }
    }   
        
    return $error;
}



# ---------------------------------------------------------------------------------------
#
# shutdown_vm
#
# Stops a LXC virtual machine. The VM should be in 'running' state. If $kill is not defined,
# an ordered shutdown request is sent to VM; if $kill is defined, a power-off is issued.  
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub shutdown_vm {

    my $self    = shift;
    my $vm_name = shift;
    my $type    = shift;
    my $kill    = shift;

    my $logp = "nsrouter-shutdown_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    my $doc = $dh->get_vm_doc($vm_name,'dom');
    my $vm  = $doc->getElementsByTagName("vm")->item(0);    

    foreach my $if ($vm->getElementsByTagName("if")) {
        my $id  = $if->getAttribute("id");
        my $if_name2 = "${vm_name}-eth$id";
        # Set the interface down 
        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " netns exec $vm_name ip link set $if_name2 down");
    }
    return $error;
}


# ---------------------------------------------------------------------------------------
#
# suspend_vm
#
# Stops a LXC virtual machine and saves its status to memory
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub suspend_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "nsrouter-suspend_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    $error = "suspend_vm for type $type not implemented for '$type'.\n";
    return $error;
}

# ---------------------------------------------------------------------------------------
#
# resume_vm
#
# Restores the status of a virtual machine from memory (previously saved with suspend_vm)
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub resume_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "nsrouter-resume_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    $error = "suspend_vm for type $type not implemented for '$type'.\n";
    return $error;
}

# ---------------------------------------------------------------------------------------
#
# save_vm
#
# Stops a virtual machine and saves its status to disk
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
#   - $filename: the name of the file to save the VM state to
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub save_vm {

    my $self     = shift;
    my $vm_name  = shift;
    my $type     = shift;
    my $filename = shift;

    my $logp = "nsrouter-save_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    $error = "save_vm not implemented for '$type'";
    return $error;
}

# ---------------------------------------------------------------------------------------
#
# restore_vm
#
# Restores the status of a virtual machine from a file previously saved with save_vm
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
#   - $filename: the name of the file with the VM state
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub restore_vm {

    my $self     = shift;
    my $vm_name   = shift;
    my $type     = shift;
    my $filename = shift;

    my $logp = "nsrouter-restore_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    $error = "save_vm not implemented for '$type'";
    return $error;

}


# ---------------------------------------------------------------------------------------
#
# get_state_vm
#
# Returns the status of a VM from the hypervisor point of view 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $ref_hstate: reference to a variable that will hold the state of VM as reported by the hipervisor 
#   - $ref_vstate: reference to a variable that will hold the equivalent VNX state (undefined, defined, 
#                  running, suspended, hibernated) to the state reported by the supervisor (a best effort
#                  mapping among both state spaces is done) 
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub get_state_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $ref_hstate = shift;
    my $ref_vstate = shift;

    my $logp = "nsrouter-get_status_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name ...)", $logp);

    my $error = '';

    my $doc = $dh->get_vm_doc($vm_name,'dom');
    my $vm  = $doc->getElementsByTagName("vm")->item(0);    

    # We check the status of the first interface and return it as a global status
    foreach my $if ($vm->getElementsByTagName("if")) {
        my $id  = $if->getAttribute("id");
        my $if_name2 = "${vm_name}-eth$id";
        # Set the interface down 
        my $state  = `ip netns exec $vm_name ip link show $if_name2 | grep UP`;
        if ($state) {
        	if ($state =~ m/Cannot open network namespace/) {
               $$ref_hstate = 'undefined';
               $$ref_vstate = 'undefined';
        	} else {
               $$ref_hstate = 'running';
               $$ref_vstate = 'running';
        	}
        } else {
            $$ref_hstate = 'defined';
            $$ref_vstate = 'defined';
        }
        last;
    }
    wlog (VVV, "state=$$ref_vstate, hstate=$$ref_hstate, error=$error");
    return $error;
}

# ---------------------------------------------------------------------------------------
#
# execute_cmd
#
# Executes a set of <filetree> and <exec> commands in a virtual mchine
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
#   - $seq: the sequence tag of commands to execute
#   - $vm: the virtual machine XML definition node
#   - $seq: the sequence tag of commands to execute
#   - $plugin_ftree_list_ref: a reference to an array with the plugin <filetree> commands
#   - $plugin_exec_list_ref: a reference to an array with the plugin <exec> commands
#   - $ftree_list_ref: a reference to an array with the user-defined <filetree> commands
#   - $exec_list_ref: a reference to an array with the user-defined <exec> commands
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub execute_cmd {

    my $self    = shift;
    my $vm_name = shift;
    my $merged_type = shift;
    my $seq     = shift;
    my $vm      = shift;
    my $plugin_ftree_list_ref = shift;
    my $plugin_exec_list_ref  = shift;
    my $ftree_list_ref        = shift;
    my $exec_list_ref         = shift;

    my $error;

    my $logp = "nsrouter-execute_cmd-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$merged_type, seq=$seq ...)", $logp);

    $error = "execute_cmd not implemented for $merged_type";

    return $error;
}

1;

