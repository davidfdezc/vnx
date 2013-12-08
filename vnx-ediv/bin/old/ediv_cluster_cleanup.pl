#!/usr/bin/perl

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

###########################################################
# Modules import
###########################################################

use strict;
use warnings;
use XML::DOM;          					# XML management library
use File::Basename;    					# File management library
use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
use EDIV::cluster_host;                 # Cluster Host class
use Socket;								# To resolve hostnames to IPs
use VNX::Globals;
use VNX::ClusterMgmt;
use VNX::Execution;

# Module to handle databases
use DBI;

###########################################################
# Global variables 
###########################################################

my $host = $ARGV[0];

###########################################################
# Main	
###########################################################

my $cluster_conf_file = "/etc/ediv/cluster.conf";

print "--------------------------------------------------------------------\n";
print "ediv_cluster_cleanup\n\n";
print "Config file = $cluster_conf_file\n";

# Read and parse cluster config
if (my $res = read_cluster_config($cluster_conf_file)) { 
    print "ERROR: $res\n";  
    exit 1; 
}

# Build the VNX::Execution object. Needed to use wlog function
my $execution = new VNX::Execution('',$EXE_NORMAL,"host> ",'',0);

print("You chose cleaning the whole cluster hosts, push ENTER to continue or CONTROL-C to abort\n");
my $input = <STDIN>;    

open STDERR, ">>/dev/null" or die ;

# Clean DB
&cleanDB;

# Delete running simulations.
&deleteSimulations;

# Delete ssh.
&deleteSSH;

# Delete vlans
&deleteVlans;


#
# Subroutine to clean DB
#
sub cleanDB{
		
		my $error;
		$error = query_db ("TRUNCATE TABLE  `hosts`");       #if ($error) { die "** $error" }
        $error = query_db ("TRUNCATE TABLE  `simulations`"); if ($error) { die "** $error" }
        $error = query_db ("TRUNCATE TABLE  `vms`");         if ($error) { die "** $error" }
        $error = query_db ("TRUNCATE TABLE  `vlans`");       if ($error) { die "** $error" }
        $error = query_db ("TRUNCATE TABLE  `nets`");        if ($error) { die "** $error" }

=BEGIN
        my $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass}) or die "DB ERROR: Cannot connect to database. " . DBI->errstr;
	
		my $query_string = "TRUNCATE TABLE  `hosts`";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		
		$query_string = "TRUNCATE TABLE  `simulations`";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		
		$query_string = "TRUNCATE TABLE  `vms`";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		
		$query_string = "TRUNCATE TABLE  `vlans`";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		
		$query_string = "TRUNCATE TABLE  `nets`";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		
		$dbh->disconnect;
=END
=cut
}

#
# Subroutine to delete running simulations
#
sub deleteSimulations{
	
	foreach my $physical_host (@cluster_hosts) {
		my $ip = $physical_host->ipAddress;
		my $kill_command = 'killall linux vnuml';
		my $kill = `ssh -2 -o 'StrictHostKeyChecking no' -X root\@$ip $kill_command`;
		system ($kill);
		my $rm_command = 'rm -rf /root/.vnuml/';
		my $rm = `ssh -2 -o 'StrictHostKeyChecking no' -X root\@$ip $rm_command`;
		system ($rm);
	}
}

#
# Subroutine to delete ssh 
#
sub deleteSSH {

	# VERY DANGEROUS!!!!
	system (`killall ssh`);
}

#
# Subroutine to delete vlans 
#
sub deleteVlans{
	
	my $firstVlan = $vlan->{first};
	my $lastVlan  = $vlan->{last};
	foreach my $physical_host (@cluster_hosts) {
		my $hostname = $physical_host->hostName;
		my $hostIP = $physical_host->ipAddress;
		my $vlan = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$hostIP 'for ((i=$firstVlan;i<=$lastVlan;i++)); do vconfig rem eth1.\$i;  done'";
		system ($vlan);
	}
	
}
