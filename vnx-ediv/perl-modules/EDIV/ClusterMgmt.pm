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
#          David Fernandez
#          Departamento de Ingenieria de Sistemas Telematicos, Universidad Politécnica de Madrid
#

package VNX::ClusterMgmt;

use strict;
use warnings;
use Exporter;
use AppConfig;                          # Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
use Socket;                             # To resolve hostnames to IPs
use VNX::Globals;
use VNX::Execution;
use Data::Dumper;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
    $cluster_conf_file
    $db
    $vlan
    $cluster
    @cluster_hosts
    @cluster_active_hosts
    read_cluster_config
    query_db
    get_vm_host
    reset_database
    delete_scenario_from_database
    get_host_status
    get_host_hostname
    get_host_ipaddr
    get_host_cpu
    get_host_maxvms
    get_host_ifname
    get_host_cpudynamic
    get_host_vnxdir
    get_host_vnxver
    get_host_tmpdir
    get_host_hypervisor
    get_host_serverid
    host_active
);

###########################################################
# Global objects

# Cluster configuration file
#our $cluster_conf_file; 

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
our @cluster_hosts;            # Array with all the host_id's of the hosts in the cluster
our @cluster_active_hosts;     # Array with all the host_id's of the hosts in the cluster which are active

our $cluster = {
    hosts         => { my %hosts }, # Hash that associates host_id with host records
    def_seg_alg   => undef,         # Default segmentation algorithm configured for the cluster 
    mgmt_net      => undef,         # Prefix for the management interfaces
    mgmt_net_mask => undef,         # Prefix mask for the management interfaces
    controller_id => undef,         # Cluster controller Linux host identifier (hostid command)
};

#
# read_cluster_config
#
# Parse configuration file and load the information on $db, $vlan and $cluster 
# global objects
# 
# Arguments:
# - $cluster_conf_file, cluster configuration file
#
# Returns:
# - '' if OK or a string with an error description in case of error 
# 
sub read_cluster_config {

    my $cluster_conf_file = shift;
    
    unless (defined($cluster_conf_file)) { return "configuration file name not defined!"; } 
    unless (-e $cluster_conf_file) { return "configuration file '$cluster_conf_file' doesn't exist!"; } 

    my $error_management = sub  {
        my $error_msg = shift;
        print "ERROR: when processing $cluster_conf_file file\n       " . $error_msg . "\n";
    };

    my $cluster_config = AppConfig->new(
        {
            CASE  => 0,                     # Case insensitive
            ERROR => $error_management,    # Error control function
            CREATE => 1,                    # Variables that weren't previously defined, are created
            GLOBAL => {
                DEFAULT  => "<unset>",      # Default value for all variables
                ARGCOUNT => ARGCOUNT_ONE,   # All variables contain a single value...
            },
            PEDANTIC => 1
        }
    );
    # Create corresponding cluster host objects
    $cluster_config->define( "cluster_host", { ARGCOUNT => ARGCOUNT_LIST } );   # ...except [CLUSTER] => host
    my $res = $cluster_config->file($cluster_conf_file);        # read the default cluster config file
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
            { return "'host_name' configuration parameter not found in section [$current_host_id]"; }
        my $packed_ip = gethostbyname($cfg_host_name);
        unless ( defined($packed_ip) ) {
            return "ERROR: cannot get IP address for host $current_host_id";
        }
        my $ip = inet_ntoa($packed_ip);
        my $host_name = gethostbyaddr($packed_ip, AF_INET);
        unless (defined($host_name)) { $host_name = $ip }
        
        my $mem;
        unless ( $mem = $cluster_config->get("$current_host_id"."_mem") )
            { return "'mem' configuration parameter not found in section [$current_host_id]";   }
        
        my $cpu;
        unless ( $cpu = $cluster_config->get("$current_host_id"."_cpu") )
            { return "'cpu' configuration parameter not found in section [$current_host_id]";   }

        my $max_vms;
        unless ( defined ($max_vms = $cluster_config->get("$current_host_id"."_max_vms")) )
            { return "'max_vms' configuration parameter not found in section [$current_host_id]";   }
        
        my $ifname;
        unless ( $ifname = $cluster_config->get("$current_host_id"."_if_name") )
            { return "'if_name' configuration parameter not found in section [$current_host_id]";   }

        # Create new cluster host object
        my $cluster_host = eval { new_host VNX::ClusterMgmt(); } or die ($@);
            
        # Fill cluster host object with parsed data
        $cluster_host->host_id("$current_host_id");
        $cluster_host->host_name("$host_name");
        $cluster_host->ip_address("$ip");
        $cluster_host->mem("$mem");
        $cluster_host->cpu("$cpu");
        $cluster_host->max_vms("$max_vms");
        $cluster_host->if_name("$ifname");

        print "-- Checking $current_host_id availability...";
        # Check whether the host is active or not
		my $not_active = system ("ssh -2 -o 'StrictHostKeyChecking no' -X root\@$ip uptime > /dev/null 2>&1 ");
		if ($not_active) {
            print "WARNING: cannot connect to host $current_host_id ($res). Marked as inactive.\n";
            $cluster_host->status("inactive");
		} else {
            print "$current_host_id is active\n";
            $cluster_host->status("active");
	        my $cpu_dynamic_command = 'cat /proc/loadavg | awk \'{print $1}\'';
	        my $cpu_dynamic = `ssh -2 -o 'StrictHostKeyChecking no' -X root\@$ip $cpu_dynamic_command`;
	        chomp $cpu_dynamic;
	        $cluster_host->cpu_dynamic("$cpu_dynamic");
	            
	        # Get vnx_dir from host vnx conf file (/etc/vnx.conf) 
	        my $vnx_dir = `ssh -X -2 -o 'StrictHostKeyChecking no' root\@$ip 'cat /etc/vnx.conf | grep ^vnx_dir'`;
	        if ($vnx_dir eq '') { 
	            $vnx_dir = $DEFAULT_VNX_DIR
	        } else {
	            my @aux = split(/=/, $vnx_dir);
	            chomp($aux[1]);
	            $vnx_dir=$aux[1];
	        }   
	        $cluster_host->vnx_dir("$vnx_dir");

            # Get VNX version from host (vnx -V -b command)
            my $vnx_ver = `ssh -X -2 -o 'StrictHostKeyChecking no' root\@$ip 'vnx -V -b'`;
            chomp ($vnx_ver);
            $cluster_host->vnx_ver("$vnx_ver");

            # Get tmp_dir from host vnx conf file (/etc/vnx.conf) 
            my $tmp_dir = `ssh -X -2 -o 'StrictHostKeyChecking no' root\@$ip 'cat /etc/vnx.conf | grep ^tmp_dir'`;
            if ($tmp_dir eq '') { 
                $tmp_dir = $DEFAULT_TMP_DIR
            } else {
                my @aux = split(/=/, $tmp_dir);
                chomp($aux[1]);
                $tmp_dir=$aux[1];
            }   
            $cluster_host->tmp_dir("$tmp_dir");

            # Get hypervisor from host vnx conf file (/etc/vnx.conf) 
            my $hypervisor = `ssh -X -2 -o 'StrictHostKeyChecking no' root\@$ip 'cat /etc/vnx.conf | grep ^hypervisor'`;
            if ($hypervisor eq '') { 
                $hypervisor = $LIBVIRT_DEFAULT_HYPERVISOR
            } else {
                my @aux = split(/=/, $hypervisor);
                chomp($aux[1]);
                $hypervisor=$aux[1];
            }   
            $cluster_host->hypervisor("$hypervisor");

             # Get Linux host identifier (hostid command)
            my $server_id = `ssh -X -2 -o 'StrictHostKeyChecking no' root\@$ip 'hostid'`;
            chomp ($server_id);
            $cluster_host->server_id("$server_id");

		}
                    
        # Store the host object inside cluster arrays
        $cluster->{hosts}{$current_host_id} = $cluster_host;
        push(@cluster_hosts, $current_host_id);
        unless ($not_active) {
            push(@cluster_active_hosts, $current_host_id);
        }
    }

    $cluster->{def_seg_alg} = $cluster_config->get("cluster_default_segmentation");
    $cluster->{mgmt_network} = $cluster_config->get("cluster_mgmt_network");
    $cluster->{mgmt_network_mask} = $cluster_config->get("cluster_mgmt_network_mask");
    my $controller_id = `hostid`;
    chomp ($controller_id);
    $cluster->{controller_id} = $controller_id; 


    return; 
}

#
# Constructor for host information records
#
sub new_host {
    my ($class) = @_;
    
    my $self = {
        _hostid => undef,       # host identifier 
        _status => undef,       # active or inactive
        _hostname => undef,     # IP Name of host
        _ipaddress => undef,    # IP Address of host        _mem => undef,          # RAM MegaBytes
        _cpu => undef,          # Percentage of CPU speed
        _maxvm => undef,        # Maximum virtualized host (0 = unlimited)
        _ifname => undef,       # Network interface of the physical host
        _cpudynamic => undef,   # CPU load in present time
        _vnxdir => undef,       # VNX directory  
        _tmpdir => undef,       # TMP directory  
        _hypervisor => undef,   # hypervisor used by libvirt  
        _vnxver => undef,       # VNX version  
        _serverid => undef      # Linux server id (hostid command)  
    };
    bless $self, $class;
    return $self;
}
    
#
# Internat accessor methods for the host record fields
#

sub host_id {
    my ( $self, $host_id ) = @_;
    $self->{_hostid} = $host_id if defined($host_id);
    return $self->{_hostid};
}

sub status {
    my ( $self, $status ) = @_;
    $self->{_status} = $status if defined($status);
    return $self->{_status};
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

sub cpu_dynamic {
    my ( $self, $cpudynamic ) = @_;
    $self->{_cpudynamic} = $cpudynamic if defined($cpudynamic);
    return $self->{_cpudynamic};
}

sub vnx_dir {
    my ( $self, $vnx_dir ) = @_;
    $self->{_vnxdir} = $vnx_dir if defined($vnx_dir);
    return $self->{_vnxdir};
}

sub vnx_ver {
    my ( $self, $vnx_ver ) = @_;
    $self->{_vnxver} = $vnx_ver if defined($vnx_ver);
    return $self->{_vnxver};
}

sub tmp_dir {
    my ( $self, $tmp_dir ) = @_;
    $self->{_tmpdir} = $tmp_dir if defined($tmp_dir);
    return $self->{_tmpdir};
}

sub hypervisor {
    my ( $self, $hypervisor ) = @_;
    $self->{_hypervisor} = $hypervisor if defined($hypervisor);
    return $self->{_hypervisor};
}

sub server_id {
    my ( $self, $server_id ) = @_;
    $self->{_serverid} = $server_id if defined($server_id);
    return $self->{_serverid};
}

# Fuctions to simplify access to hosts info by host_id

sub get_host_status {
	my $host_id = shift;
	return $cluster->{hosts}{$host_id}->status
}

sub get_host_hostname {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->host_name
}

sub get_host_ipaddr {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->ip_address
}

sub get_host_cpu {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->cpu
}

sub get_host_maxvms {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->max_vms
}

sub get_host_ifname {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->if_name
}

sub get_host_cpudynamic {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->cpu_dynamic
}

sub get_host_vnxdir {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->vnx_dir
}

sub get_host_vnxver {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->vnx_ver
}

sub get_host_tmpdir {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->tmp_dir
}

sub get_host_hypervisor {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->hypervisor
}

sub get_host_serverid {
    my $host_id = shift;
    return $cluster->{hosts}{$host_id}->server_id
}

sub host_active {
    my $host_id = shift;
    return ($cluster->{hosts}{$host_id}->status eq 'active')
}

#
# query_db
#
# Make a query to EDIV database 
#
# Arguments:
# - query_string, a string with an SQL query
# - ref_response (optional), a reference to an array were the result of the query will be stored  
#
# Returns:
# - '' if no error; or a string describing the error in other cases 
#
# Example 1:
# 
#   $query = "INSERT INTO scenarios VALUES ('example','7','22')";
#   $error = query_db ($query);
#   if ($error) { die "** $error" }
# 
# Example 2:
#
#   my @response;
#   $query = "SELECT * FROM scenarios";
#   $error = query_db ($query, \@response);
#   if ($error) { die "** $error" }
#
#   print it with Dumper
#   print "Response:\n"; 
#   print "Number of rows=" . @response . "\n";
#   foreach my $row (@response) {
#       print "Row:  ";
#       foreach my $field (@$row) {
#           if (defined($field)) { print $field . " "} else {print "undefined "; }
#       }
#       print "\n";
#   }

sub query_db {
    
    my $query_string = shift;
    my $ref_response = shift;
    my $error;
    
    wlog (VVV, "----", "");
    #wlog (VVV, "$query_string", "DB Query: "); 

    # Log traces (only the first 12 lines printed)
    my $j=0;
    foreach my $l (split /\n/ ,$query_string) {
        wlog (VVV, "$l", "DB Query: ");
        if (++$j > 12 ) { last };
    }

    my $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass}) 
       or return "DB ERROR: Cannot connect to database. " . DBI->errstr;
    my $query = $dbh->prepare($query_string) 
       or return "DB ERROR: Cannot prepare query to database. " . DBI->errstr;
    $query->execute()
       or return "DB ERROR: Cannot execute query to database. " . DBI->errstr;

    if (defined($ref_response)) {
        # Reset array
        @$ref_response = ();
        wlog (VVV, " ", "DB Response:");
        my $i=0;
        while (my @row = $query->fetchrow_array()) {
            push (@$ref_response, \@row);
            my $line;
            foreach my $field (@row) { 
            	unless (defined($field)) { $field='undef' }
            	if (defined($line)) {$line .= ", $field"} else {$line = $field} 
            } 
            # Log traces (only the first 12 lines printed)
            my $j=0;
            foreach my $l (split /\n/ ,$line) {
                wlog (VVV, "$l", "  Row$i: ");
                if (++$j > 12 ) { last };
            }
        }
        #wlog (VVV, " " . Dumper (@$ref_response), "DB Response:");
    }
    wlog (VVV, "----", "");
    $query->finish();
    $dbh->disconnect;

    return '';

}

#
# get_vm_host
#
# Returns the host assigned to a VM
# 
sub get_vm_host {

    my $vm_name = shift;
    my $error;
    my @db_resp;

    $error = query_db ("SELECT `host` FROM vms WHERE name='$vm_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    if (defined($db_resp[0]->[0])) {
        return $db_resp[0]->[0];  
    } else {
        wlog (N, "ERROR (get_vm_host): cannot get the host assigned to vm $vm_name from database");
    }
}

#
# reset_database
#
# Deletes the whole database content
#
sub reset_database {
        
        my $error;
        $error = query_db ("TRUNCATE TABLE  `hosts`");       if ($error) { die "** $error" }
        $error = query_db ("TRUNCATE TABLE  `scenarios`"); if ($error) { die "** $error" }
        $error = query_db ("TRUNCATE TABLE  `vms`");         if ($error) { die "** $error" }
        $error = query_db ("TRUNCATE TABLE  `vlans`");       if ($error) { die "** $error" }
        $error = query_db ("TRUNCATE TABLE  `nets`");        if ($error) { die "** $error" }
}

#
# delete_scenario_from_database
#
# Deletes a secenario from database tables
#
sub delete_scenario_from_database {
    
    my $scenario_name = shift;
    
    wlog (V, "-- delete_scenario_from_database called");
    my $error;
    
    $error = query_db ("DELETE FROM hosts WHERE scenario = '$scenario_name'");
    if ($error) { ediv_die ("$error") };
    
    $error = query_db ("DELETE FROM nets WHERE scenario = '$scenario_name'");
    if ($error) { ediv_die ("$error") };
    
    $error = query_db ("DELETE FROM scenarios WHERE name = '$scenario_name'"); 
    if ($error) { ediv_die ("$error") }

    $error = query_db ("DELETE FROM vlans WHERE scenario = '$scenario_name'"); 
    if ($error) { ediv_die ("$error") }
    
    $error = query_db ("DELETE FROM vms WHERE scenario = '$scenario_name'"); 
    if ($error) { ediv_die ("$error") }
}
1;
###########################################################
