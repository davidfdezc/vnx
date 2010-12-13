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

###########################################################
# Global variables 
###########################################################

	# Cluster
my $cluster_config;    					# AppConfig object to read cluster config
my $phy_hosts;        					# List of cluster members
my @cluster_hosts;						# Cluster host object array to send to segmentator

	# Modes
my $mode = $ARGV[0];
my $host = $ARGV[1];

###########################################################
# Main	
###########################################################	

if (!($mode =~ /[0-9]+/)) {
	print "The first argument must be a number\n";
	exit(1);
}
	# Fill the cluster hosts.
&fillClusterHosts;

	# Send vn
&sendVn;

	# Monitor.
&monitor;

# Main end
###########################################################

###########################################################
# Subroutines
###########################################################

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
	my $cluster_file;
	$cluster_file = "/etc/ediv/cluster.conf";
	open(FILEHANDLE, $cluster_file) or undef $cluster_file;
	close(FILEHANDLE);
	if ($cluster_file eq undef){
		$cluster_file = "/usr/local/etc/ediv/cluster.conf";
		open(FILEHANDLE, $cluster_file) or die "The cluster configuration file doesn't exist in /etc/ediv or in /usr/local/etc/ediv... Aborting";
		close(FILEHANDLE);
	}
	
	$cluster_config->file($cluster_file);		# read the default cluster config file
	
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
	# Subroutine to send vn program
	###########################################################
sub sendVn{
	
	foreach $physical_host (@cluster_hosts) {
		my $ip = $physical_host->ipAddress;
		my $scp_command = `scp -2 -o 'StrictHostKeyChecking no' vn root\@$ip:/tmp/`;
		system ($scp_command);
	
	}
}

	###########################################################
	# Subroutine to check cluster hosts
	###########################################################
sub monitor{

	while (1) {
		
	system ("clear");
		
		if ($host eq undef){
			foreach $physical_host (@cluster_hosts) {
				my $ip = $physical_host->ipAddress;
			
				my $simulations_number_command = "/tmp/vn console | grep available | awk '{print NF}'";
				my $simulations_number = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip $simulations_number_command`;
				chomp $simulations_number;
				
				my $uptime_command = 'uptime';
				my $uptime = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip $uptime_command`;
			
				my $hostname = $physical_host->hostName;
			
				print "Host $hostname status:\n\n";
		
				print "Load:  $uptime\n";
			
				if ($simulations_number < 3) {
					print ("\nThere aren't simulations running\n\n\n");
				}
		
				my $simulations = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip /tmp/vn console | grep available`;
			
				for (my $i=3; $i<=$simulations_number; $i++){
				
					my $simulation = `echo "$simulations" | awk '{print \$$i}'`;
					chomp $simulation;
					chomp $simulation;
				
					print "Virtual machines running at simulation $simulation:\n";
					my $vms = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip /tmp/vn console $simulation | grep available`;
					print "\t $vms\n";
				}	
				print ("\n");
			}
		
			if ($mode eq "0"){
				exit(0);
			} else {
				sleep ($mode);
			}
		} else{;
			
			my $simulations_number_command = "/tmp/vn console | grep available | awk '{print NF}'";
			my $simulations_number = `ssh -2 -o 'StrictHostKeyChecking no' root\@$host $simulations_number_command`;
			chomp $simulations_number;
				
			my $uptime_command = 'uptime';
			my $uptime = `ssh -2 -o 'StrictHostKeyChecking no' root\@$host $uptime_command`;
			
			print "Host $host status:\n\n";
		
			print "Load:  $uptime\n";
			
			if ($simulations_number < 3) {
				print ("\nThere aren't simulations running\n\n\n");
			}
		
			my $simulations = `ssh -2 -o 'StrictHostKeyChecking no' root\@$host /tmp/vn console | grep available`;
			
			for (my $i=3; $i<=$simulations_number; $i++){
				
				my $simulation = `echo "$simulations" | awk '{print \$$i}'`;
				chomp $simulation;
				chomp $simulation;
				
				print "Virtual machines running at simulation $simulation:\n";
				my $vms = `ssh -2 -o 'StrictHostKeyChecking no' root\@$host /tmp/vn console $simulation | grep available`;
				print "\t $vms\n";
			}	
			print ("\n");
		
		
			if ($mode == "0"){
				exit(0);
			} else {
				sleep ($mode);
			}
			
		}

	}
}

# Subroutines end
###########################################################