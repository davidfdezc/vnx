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
#                2011 Dpto. Ingenieria de Sistemas Telematicos - UPM
# Authors: Fco. Jose Martin,
#          Miguel Ferrer
#		   David Fernandez
#          Departamento de Ingenieria de Sistemas Telematicos, Universidad Politécnica de Madrid
#

package VNX::ClusterConfig;

use strict;
use warnings;
use Exporter;
use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
use Socket;								# To resolve hostnames to IPs
use VNX::Globals;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
    $cluster_conf_file
	$db
	$vlan
    $cluster
    @cluster_hosts
    read_cluster_config
);

###########################################################
# Global objects

# Cluster configuration file
our $cluster_conf_file;	

# Database configuration
our $db = {
    name => undef,
    type => undef,
    host => undef,
    port => undef,
    user => undef,
    pass => undef,
    conn_info => undef,
};

# Vlan configuration
our $vlan = {
    first => undef,
    last  => undef,
};

# Cluster hosts configuration
our @cluster_hosts;	
our $cluster = {
    hosts         => { my %hosts }, # Hash that associates host_id with host records
    def_seg_alg   => undef,
    mgmt_net      => undef,
    mgmt_net_mask => undef,
    
};

#
# read_cluster_config
#
# Parse configuration file and load the information on $db, $vlan and $cluster 
# global objects
# 
# Arguments:
# - none
#
# Returns:
# - '' if OK or a string with an error description in case of error 
# 
sub read_cluster_config {

	my $error_management = sub  {
		my $error_msg = shift;
		print "ERROR: when processing $cluster_conf_file file\n       " . $error_msg . "\n";
    };

	my $cluster_config = AppConfig->new(
		{
			CASE  => 0,                     # Case insensitive
			ERROR => $error_management,    # Error control function
			CREATE => 1,    				# Variables that weren't previously defined, are created
			GLOBAL => {
				DEFAULT  => "<unset>",		# Default value for all variables
				ARGCOUNT => ARGCOUNT_ONE,	# All variables contain a single value...
			},
			PEDANTIC => 1
		}
	);
	# Create corresponding cluster host objects
	$cluster_config->define( "cluster_host", { ARGCOUNT => ARGCOUNT_LIST } );	# ...except [CLUSTER] => host
	my $res = $cluster_config->file($cluster_conf_file);		# read the default cluster config file
	unless ($res == 1) {
		return "Error loading $cluster_conf_file cluster configuration file";
	}
	# TODO: check return code 
	
	# Fill database access data  
	#$db->{name} = $cluster_config->get("db_name"); unless ($db->{name}) { return "db_name configuration parameter not found"}
	unless ( $db->{name} = $cluster_config->get("db_name") ) 
		{ return "'name' configuration parameter not found in section [db]"}
	unless ( $db->{type} = $cluster_config->get("db_type") ) 
		{ return "'type' configuration parameter not found in section [db]"}
	unless ( $db->{host} = $cluster_config->get("db_host") ) 
		{ return "'host' configuration parameter not found in section [db]"}
	unless ( $db->{port} = $cluster_config->get("db_port") ) 
		{ return "'port' configuration parameter not found in section [db]"}
	unless ( $db->{user} = $cluster_config->get("db_user") ) 
		{ return "'user' configuration parameter not found in section [db]"}
	unless ( $db->{pass} = $cluster_config->get("db_pass") ) 
		{ return "'pass' configuration parameter not found in section [db]"}
	unless ( $db->{conn_info} = "DBI:$db->{type}:database=$db->{name};$db->{host}:$db->{port}" ) 
	   	{ return "'conn_info' configuration parameter not found in section [db]"}	

	# Fill vlan range data 
	unless ( defined ($vlan->{first} = $cluster_config->get("vlan_first") ) )
		{ return "'first' configuration parameter not found in section [vlan]"}
	unless ( defined ($vlan->{last}  = $cluster_config->get("vlan_last") ) )
		{ return "'last' configuration parameter not found in section [vlan]"}

	my $phy_hosts = ( $cluster_config->get("cluster_host") ); # gets all hosts entries under [cluster]	
	
	#print "Host num: " . scalar(@$phy_hosts) . "\n";
	if ( scalar(@$phy_hosts) == 0 ) { return "No hosts defined in $cluster_conf_file [cluster] section"}
	
	# For each host in the cluster
	foreach my $current_host_id (@$phy_hosts) {

		# Read current host settings from config file
		# Get hostname
		my $cfg_host_name;
		unless ( $cfg_host_name = $cluster_config->get("$current_host_id"."_host_name") )
			{ return "'host_name' configuration parameter not found in section [$current_host_id]";	}
		my $packed_ip = gethostbyname($cfg_host_name);
		unless ( defined($packed_ip) ) {
			return "ERROR: cannot get IP address for host $current_host_id";
		}
		my $ip = inet_ntoa($packed_ip);
		my $host_name = gethostbyaddr($packed_ip, AF_INET);
		if ($host_name eq '') { $host_name = $ip }
		
		my $mem;
		unless ( $mem = $cluster_config->get("$current_host_id"."_mem") )
			{ return "'mem' configuration parameter not found in section [$current_host_id]";	}
		
		my $cpu;
		unless ( $cpu = $cluster_config->get("$current_host_id"."_cpu") )
			{ return "'cpu' configuration parameter not found in section [$current_host_id]";	}

		my $max_vms;
		unless ( defined ($max_vms = $cluster_config->get("$current_host_id"."_max_vms")) )
			{ return "'max_vms' configuration parameter not found in section [$current_host_id]";	}
		
		my $ifname;
		unless ( $ifname = $cluster_config->get("$current_host_id"."_if_name") )
			{ return "'if_name' configuration parameter not found in section [$current_host_id]";	}
		
		my $cpu_dynamic_command = 'cat /proc/loadavg | awk \'{print $1}\'';
		my $cpu_dynamic = `ssh -2 -o 'StrictHostKeyChecking no' -X root\@$ip $cpu_dynamic_command`;
		chomp $cpu_dynamic;
			
		# Get vnx_dir for each host in the cluster 
		my $vnx_dir = `ssh -X -2 -o 'StrictHostKeyChecking no' root\@$ip 'cat /etc/vnx.conf | grep ^vnx_dir'`;
		if ($vnx_dir eq '') { 
			$vnx_dir = $DEFAULT_VNX_DIR
		} else {
			my @aux = split(/=/, $vnx_dir);
			chomp($aux[1]);
			$vnx_dir=$aux[1];
		}	
			
		# Create new cluster host object
		my $cluster_host = eval { new_host VNX::ClusterConfig(); } or die ($@);
			
		# Fill cluster host object with parsed data
		$cluster_host->host_name("$host_name");
		$cluster_host->ip_address("$ip");
		$cluster_host->mem("$mem");
		$cluster_host->cpu("$cpu");
		$cluster_host->max_vms("$max_vms");
		$cluster_host->if_name("$ifname");
		$cluster_host->cpuDynamic("$cpu_dynamic");
		$cluster_host->vnx_dir("$vnx_dir");
		
		# Store the host object inside cluster arrays
		$cluster->{hosts}{$current_host_id} = $cluster_host;
		push(@cluster_hosts, $current_host_id);

	}

	$cluster->{def_seg_alg} = $cluster_config->get("cluster_default_segmentation");
	$cluster->{mgmt_network} = $cluster_config->get("cluster_mgmt_network");
	$cluster->{mgmt_network_mask} = $cluster_config->get("cluster_mgmt_network_mask");

	return;	
}

#
# Constructor for host information records
#
sub new_host {
    my ($class) = @_;
    
    my $self = {
        _hostname => undef,		# IP Name of host
        _ipaddress => undef,	# IP Address of host        _mem => undef, 			# RAM MegaBytes
        _cpu => undef,			# Percentage of CPU speed
        _maxvm => undef,		# Maximum virtualized host (0 = unlimited)
        _ifname => undef,		# Network interface of the physical host
        _cpudynamic => undef,	# CPU load in present time
        _vnxdir => undef     	# VNX directory  
    };
    bless $self, $class;
    return $self;
}
	
#
# Accessor methods for the host record fields
#
sub cpuDynamic {
    my ( $self, $cpudynamic ) = @_;
    $self->{_cpudynamic} = $cpudynamic if defined($cpudynamic);
    return $self->{_cpudynamic};
}

sub host_name {
    my ( $self, $host_name ) = @_;
    $self->{_hostname} = $host_name if defined($host_name);
    return $self->{_hostname};
}

sub ip_address {
    my ( $self, $ip_address ) = @_;
    $self->{_ipaddress} = $ip_address if defined($ip_address);
    return $self->{_ipaddress};
}        

sub mem {
    my ( $self, $Mem ) = @_;
    $self->{_mem} = $Mem if defined($Mem);
    return $self->{_mem};
}

sub cpu {
    my ( $self, $CPU ) = @_;
    $self->{_cpu} = $CPU if defined($CPU);
    return $self->{_cpu};
}

sub max_vms {
    my ( $self, $max_vms ) = @_;
    $self->{_maxvm} = $max_vms if defined($max_vms);
    return $self->{_maxvm};
}

sub if_name {
    my ( $self, $if_name ) = @_;
    $self->{_ifname} = $if_name if defined($if_name);
    return $self->{_ifname};
}

sub vnx_dir {
    my ( $self, $vnx_dir ) = @_;
    $self->{_vnxdir} = $vnx_dir if defined($vnx_dir);
    return $self->{_vnxdir};
}

1;
###########################################################
