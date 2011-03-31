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

package cluster_host;

###########################################################
# Modules import
########################################################

use strict;

###########################################################
# Subroutines
###########################################################

	###########################################################
	# Constructor
	###########################################################
sub new {
    my ($class) = @_;
    
    my $self = {
        _hostname => undef,		# Name of host
        _ipaddress => undef,	# IP Address
        _mem => undef, 			# RAM MegaBytes
        _cpu => undef,			# Percentage of CPU speed
        _maxvhost => undef,		# Maximum virtualized host (0 = unlimited)
        _ifname => undef,		# Network interface of the physical host
        _cpudynamic => undef,	# CPU load in present time
        _vnxdir => undef     	# VNX directory  
    };
    bless $self, $class;
    return $self;
}
	
	###########################################################
	# Accessor method for the dynamic CPU load
	###########################################################
sub cpuDynamic {
    my ( $self, $cpudynamic ) = @_;
    $self->{_cpudynamic} = $cpudynamic if defined($cpudynamic);
    return $self->{_cpudynamic};
}

	###########################################################
	# Accessor method for the Name of the cluster host
	###########################################################
sub hostName {
    my ( $self, $hostName ) = @_;
    $self->{_hostname} = $hostName if defined($hostName);
    return $self->{_hostname};
}
	
	###########################################################
	# Accessor method for cluster host IP address
	###########################################################
sub ipAddress {
    my ( $self, $ipAddress ) = @_;
    $self->{_ipaddress} = $ipAddress if defined($ipAddress);
    return $self->{_ipaddress};
}        
	###########################################################
	# Accessor method for cluster host memory
	###########################################################
sub mem {
    my ( $self, $Mem ) = @_;
    $self->{_mem} = $Mem if defined($Mem);
    return $self->{_mem};
}
	###########################################################
	# Accessor method for CPU speed
	###########################################################
sub cpu {
    my ( $self, $CPU ) = @_;
    $self->{_cpu} = $CPU if defined($CPU);
    return $self->{_cpu};
}
	###########################################################
	# Accessor method for maximum virtualized host in this cluster host
	###########################################################
sub maxVhost {
    my ( $self, $maxVhost ) = @_;
    $self->{_maxvhost} = $maxVhost if defined($maxVhost);
    return $self->{_maxvhost};
}

	###########################################################	
	# Accessor method for the network interface
	###########################################################
sub ifName {
    my ( $self, $if ) = @_;
    $self->{_ifname} = $if if defined($if);
    return $self->{_ifname};
}

	###########################################################	
	# Accessor method for the network interface
	###########################################################
sub vnxDir {
    my ( $self, $vnxdir ) = @_;
    $self->{_vnxdir} = $vnxdir if defined($vnxdir);
    return $self->{_vnxdir};
}

1;
# Subroutines end
###########################################################
