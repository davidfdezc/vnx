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

use strict;
use warnings;
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw( 
    tundevice_needed 
    check_net_host_conn 
    vnet_exists_br
    vnet_exists_sw
    vnet_ifs
    get_next_free_port 
    wait_sock_answer
    recv_sock   
);

use VNX::Globals;
use VNX::DocumentChecks;
use VNX::Execution;

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

    #my $net_list = $dh->get_doc->getElementsByTagName("net");
    #for (my $i = 0; $i < $net_list->getLength; $i++ ) {
    foreach my $net ($dh->get_doc->getElementsByTagName("net")) {
        # Get attributes
        my $name = $net->getAttribute("name");
        my $mode = $net->getAttribute("mode");
   	  
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

    #my $hostif_list = $doc->getElementsByTagName("hostif");
    #for ( my $i = 0 ; $i < $hostif_list->getLength ; $i++ ) {
    foreach my $hostif ($doc->getElementsByTagName("hostif")) {
   	    my $net_name = $hostif->getAttribute("net");
        return 1 if ($net eq $net_name);
    }
    return 0;
}

# vnet_exists_br
#
# If the virtual network (implemented with a bridge) whose name is given
# as first argument exists, returns 1. In other case, returns 0.
#
# It based in `brctl show` parsing.
sub vnet_exists_br {

   my $vnet_name = shift;
   my $mode = shift;
   my $pipe;

   # To get `brctl show`
   my @brctlshow;
   my $line = 0;
   if ($mode eq "virtual_bridge"){
        $pipe = $bd->get_binaries_path_ref->{"brctl"} . " show |";
   } elsif($mode eq "openvswitch"){
        $pipe = $bd->get_binaries_path_ref->{"ovs-vsctl"} . " show |";
   }
   open BRCTLSHOW, "$pipe";
   while (<BRCTLSHOW>) {
      chomp;
      $brctlshow[$line++] = $_;
   }
   close BRCTLSHOW;

   # To look for virtual network processing the list
   # Note that we skip the first line (due to this line is the header of
   # brctl show: bridge name, brige id, etc.)
   for ( my $i = 1; $i < $line; $i++) {
      $_ = $brctlshow[$i];
      # We are interestend only in the first and last "word" of the line
#      /^(\S+)\s.*\s(\S+)$/;   # DFC 14/1/2012: changed; it didn't work because lines can be ended with some spaces
                               #      Besides only the bridge name is needed ($1)    
      /^(\S+)\s.*/;
      if (defined($1) && ($1 eq $vnet_name) ) {
        # If equal, the virtual network has been found
        return 1;
      }
   }

   # If virtual network is not found:
   return 0;

}

# vnet_exists_sw
#
# If the virtual network (implemented with a uml_switch) whose name is given
# as first argument exists, returns 1. In other case, returns 0.
#
sub vnet_exists_sw {

   my $vnet_name = shift;

   # To search for $dh->get_networks_dir()/$vnet_name.ctl socket file
   if (-S $dh->get_networks_dir . "/$vnet_name.ctl") {
      return 1;
   }
   else {
      return 0;
   }
   
}

#
# vnet_ifs
#
# Returns a list in which each element is one of the interfaces (TUN/TAP devices
# or host OS physical interfaces) of the virtual network given as argument.
#
# It based in `brctl show` parsing. Rewritten on 24/11/2013 to avoid problems 
# with regular expressions.
#
sub vnet_ifs {

    my $vnet_name = shift;
    my $mode = shift;
    my @if_list;

    if ($mode eq "virtual_bridge"){

	    # Load the list of bridges
	    my $bridges_list = `brctl show | tail -n +2 | sed -n '/^\\w/p' | awk '{print \$1}'`;
	    $bridges_list =~ s/\R/ /g; # Change newlines to spaces
	    my @bridges = split(' ', $bridges_list);
	    #print "bridges_list=$bridges_list\n";
	
	    # Load the list of bridges + interfaces
	    my $bridges_and_ifs_list = `brctl show | tail -n +2 | awk '{ print \$1; if (\$4!="") print \$4 }'`; 
	    $bridges_and_ifs_list =~ s/\R/ /g; # Change newlines to spaces
	    my @bridges_and_ifs = split(' ', $bridges_and_ifs_list);
	    #print "bridges_and_ifs_list=$bridges_and_ifs_list\n";
	
	    # Fill a hash table with the names of the bridges
	    my %hbridges = ();
	    foreach $b (@bridges) {
	      #print "$b\n";
	      $hbridges{$b}='yes';
	    } 
	
	    my $found = 'false';
	    foreach my $s (@bridges_and_ifs) {
	      	if ( $found eq 'true' ) {
	        	if ( $hbridges{$s} ) { last }
	        	else                 { push (@if_list,$s); }
	      	}
	      	if ($s eq $vnet_name) { $found = 'true' }
	    }
	    return @if_list;
    } elsif ($mode eq "openvswitch") {
        my $pipe;
        my @brctlshow;
        my $line = 0;
        
        $pipe = $bd->get_binaries_path_ref->{"ovs-vsctl"} . " show |";
        open BRCTLSHOW, "$pipe";
        while (<BRCTLSHOW>) {
            chomp;
            $brctlshow[$line++] = $_;
        }
        close BRCTLSHOW; 
        wlog (V, "*************** @brctlshow");  	
        for ( my $i = 1; $i < $line; $i++) {
            $_ = $brctlshow[$i];
            /^ *Bridge "(\S+)"$/;
            if (defined($1) && ($1 eq $vnet_name)) {
                # To push interface into the list
                push (@if_list,$1."-e00");
            }
        }
    }
}

=BEGIN
sub vnet_ifs {

	my $vnet_name = shift;
	my @if_list;

	# To get `brctl show`
	my @brctlshow;
	my $line = 0;
	my $pipe = $bd->get_binaries_path_ref->{"brctl"} . " show |";
	open BRCTLSHOW, "$pipe";
	while (<BRCTLSHOW>) {
		chomp;
		$brctlshow[$line++] = $_;
	}
	close BRCTLSHOW;

	for ( my $i = 1; $i < $line; $i++) {
		wlog (VVV, "lines$i= $brctlshow[$i]");
	}

	# To look for virtual network processing the list
	# Note that we skip the first line (due to this line is the header of
	# brctl show: bridge name, brige id, etc.)
	for ( my $i = 1; $i < $line; $i++) {
		wlog (VVV, "line $i = $brctlshow[$i]");
		#$_ = $brctlshow[$i];
		$_ = $brctlshow[$i];
		# Some brctl versions seems to show a different message when no
		# interface is used in a virtual bridge. Skip those
		unless (/Function not implemented/) {
			# We are interestend only in the first and last "word" of the line
			/^(\S+)\s.*\s(\S+)$/;
			wlog (VVV, "line=$i, first=$1, last=$2");
			wlog (VVV, "nextline=$brctlshow[$i+1]");
			if (defined($1) && ($1 eq $vnet_name) ) {
            	# To push interface into the list
            	wlog (VVV, "match");
            	push (@if_list,$2);

            	# Internal loop (it breaks when a line with bridge name is found)
				for ( my $j = $i+1; $j < $line; $j++) {
					wlog (VVV, "line $j = $brctlshow[$j]");
					$_ = $brctlshow[$j];
					wlog (VVV, "\$_= $_");
					
					/^(\S+)\s.*\s(\S+)$/;
					wlog (VVV, "line $j = $brctlshow[$j]");
					wlog (VVV, "line=$j, first=$1, last=$2");
					#if (/^(\S+)\s.*\s(\S+)$/) 
					if (defined($1)) {
						last;
					}
					# To push interface into the list
					/.*\s(\S+)$/;
					push (@if_list,$1);
				}
            
				# The end...
				last;
         	}       
		}
	}
	# To return list
	return @if_list;
}
=END
=cut

sub get_next_free_port {

change_to_root();
    my $port_ref = shift;   
    my $port;
    while ( !system("fuser -s -v -n tcp $$port_ref") ) {
        #wlog (VV, "get_next_free_port: port " . $$port_ref . " used, trying next...");
        $$port_ref++;
    }
    $port = $$port_ref;
    $$port_ref++;
    #wlog (VV, "get_next_free_port: using port $$port_ref");
back_to_user();    
    
    return $port;
}

#
# wait_sock_answer
#
sub wait_sock_answer {

    my $socket = shift;
    my $timeout = 30;

    wlog (VVV, "wait_sock_answer called... $socket");

    eval {
        local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
        alarm $timeout;

        while (1) {
            my $line = <$socket>;
            chomp ($line);
            my $pline = $line; $pline =~ s/^[\W]+//; # Eliminate trailing control non ascii characters for printing
            wlog (N, "** $pline", ""); # if ($exemode == $EXE_VERBOSE)
            last if ( ( $line =~ /^OK/) || ( $line =~ /^NOTOK/) 
                      || ( $line =~ /^finished/)  # for old linux daemons (deprecated)  
                      || ( $line =~ /^1$/));      # for windows ace (deprecated)
        }
        alarm 0;
    };
    if ($@) {
        die unless $@ eq "alarm\n";   # propagate unexpected errors
        # timed out
        wlog (N, "ERROR: timeout waiting for response on VM socket");
    }
    else {
        # didn't
    }

}

#
# recv_sock
#
sub recv_sock {

    my $socket = shift;
    my $timeout = 15;
    my $line;
    
    wlog (VVV, "recv_sock called... $socket");

    eval {
        local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
        alarm $timeout;
        $line = <$socket>;
        wlog (VVV, "line=$line", "");
        alarm 0;
    };
    if ($@) {
        die unless $@ eq "alarm\n";   # propagate unexpected errors
        # timed out
        wlog (N, "ERROR: timeout waiting for response on VM socket");
        return '';
    }
    else {
        return "$line";
    }
}


1;
