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

use XML::DOM;          					# XML management library
use File::Basename;    					# File management library
use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
use EDIV::cluster_host;                 # Cluster Host class
use Socket;								# To resolve hostnames to IPs

	# Module to handle databases
use DBI;

###########################################################
# Global variables 
###########################################################

	# DB
my $db;
my $db_type;
my $db_host;
my $db_port;
my $db_user;
my $db_pass;
my $db_connection_info;

	# Cluster
my $cluster_file;						# Cluster configuration file
my $cluster_config;    					# AppConfig object to read cluster config
my $phy_hosts;        					# List of cluster members
my @cluster_hosts;						# Cluster host object array to send to segmentator

my $host = $ARGV[0];

###########################################################
# Main	
###########################################################



print("ediv_cluster_cleanup: You chose cleaning the whole cluster hosts, push ENTER to continue or CONTROL-C to abort\n");
my $input = <STDIN>;	

	# Fill the cluster hosts.
&fillClusterHosts;

	# Get DB configuration
&getDBConfiguration;

open STDERR, ">>/dev/null" or die ;
	# Clean DB
&cleanDB;

	# Delete running simulations.
&deleteSimulations;

	# Delete ssh.
&deleteSSH;

	# Delete vlans
&deleteVlans;

# Main end
###########################################################

###########################################################
# Subroutines
###########################################################

	###########################################################
	# Subroutine to obtain DB configuration info
	###########################################################
sub getDBConfiguration {
	
	my $db_config = AppConfig->new(
		{
			CASE  => 0,                     # Case insensitive
			ERROR => \&error_management,    # Error control function
			CREATE => 1,    				# Variables that weren't previously defined, are created
			GLOBAL => {
				DEFAULT  => "<unset>",		# Default value for all variables
				ARGCOUNT => ARGCOUNT_ONE,	# All variables contain a single value...
			}
		}
	);
	$db_config->file($cluster_file);		# read the default cluster config file
	
		# Create corresponding cluster host objects
	
	$db = $db_config->get("db_name");
	$db_type = $db_config->get("db_type");
	$db_host = $db_config->get("db_host");
	$db_port = $db_config->get("db_port");
	$db_user = $db_config->get("db_user");
	$db_pass = $db_config->get("db_pass");
	$db_connection_info = "DBI:$db_type:database=$db;$db_host:$db_port";	
	
}	

	###########################################################
	# Subroutine to clean DB
	###########################################################
sub cleanDB{
		
		my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		
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
}
	
	###########################################################
	# Fill the cluster hosts
	###########################################################
sub fillClusterHosts {
	
	$cluster_config = AppConfig->new(
		{
			CASE  => 0,                     # Case insensitive
			ERROR => \&error_management,    # Error control function
			CREATE => 1,    				# Variables that weren't previously defined, are created
			GLOBAL => {
				DEFAULT  => "<unset>",		# Default value for all variables
				ARGCOUNT => ARGCOUNT_ONE,	# All variables contain a single value...
			}
		}
	);
	$cluster_config->define( "cluster_host", { ARGCOUNT => ARGCOUNT_LIST } );	# ...except [CLUSTER] => host
	
	$cluster_file = "/etc/ediv/cluster.conf";
	open(FILEHANDLE, $cluster_file) or undef $cluster_file;
	close(FILEHANDLE);
	if ($cluster_file eq undef){
		$cluster_file = "/usr/local/etc/ediv/cluster.conf";
		open(FILEHANDLE, $cluster_file) or die "The cluster configuration file doesn't exist in /etc/ediv or in /usr/local/etc/ediv... Aborting";
		close(FILEHANDLE);
	}
	$cluster_config->file($cluster_file);							# read the default cluster config file
	
		# Create corresponding cluster host objects
	
	$phy_hosts = ( $cluster_config->get("cluster_host") );
	
		# Per cluster existing host
	my $i=0;
	while (defined(my $current_name = $phy_hosts->[$i])) {
	
		# Read current cluster host settings
		my $name = $current_name;
		my $packed_ip = gethostbyname($current_name);
		my $ip = inet_ntoa($packed_ip);
		my $hostname = gethostbyaddr($packed_ip, AF_INET);;
		my $ifname = $cluster_config->get("$current_name"."_ifname");
			
		# Create new cluster host object
		my $cluster_host = eval { new cluster_host(); } or die ($@);
			
		# Fill cluster host object with parsed data
		$cluster_host->hostName("$hostname");
		$cluster_host->ipAddress("$ip");;
		$cluster_host->ifName("$ifname");

			
		# Put the complete cluster host object inside @cluster_hosts array
		push(@cluster_hosts, $cluster_host);
		$i++;
	}
	undef $i;
}

	###########################################################
	# Subroutine to delete running simulations
	###########################################################
sub deleteSimulations{
	
	foreach $physical_host (@cluster_hosts) {
		my $ip = $physical_host->ipAddress;
		my $kill_command = 'killall linux vnuml';
		my $kill = `ssh -2 -o 'StrictHostKeyChecking no' -X root\@$ip $kill_command`;
		system ($kill);
		my $rm_command = 'rm -rf /root/.vnuml/';
		my $rm = `ssh -2 -o 'StrictHostKeyChecking no' -X root\@$ip $rm_command`;
		system ($rm);
	}
}

	###########################################################
	# Subroutine to delete ssh 
	###########################################################
sub deleteSSH {

	# VERY DANGEROUS!!!!
	system (`killall ssh`);
}

	###########################################################
	# Subroutine to delete vlans 
	###########################################################
sub deleteVlans{
	
	my $firstVlan = $cluster_config->get("vlan_first");
	my $lastVlan = $cluster_config->get("vlan_last");
	foreach $physical_host (@cluster_hosts) {
		my $hostname = $physical_host->hostName;
		my $hostIP = $physical_host->ipAddress;
		my $vlan = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$hostIP 'for ((i=$firstVlan;i<=$lastVlan;i++)); do vconfig rem eth1.\$i;  done'";
		system ($vlan);
	}
	
}

# Subroutines end
###########################################################