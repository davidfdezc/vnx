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
# Copyright: (C) 2010 Telefonica Investigacion y Desarrollo, S.A.U.
# Authors: Fco. Jose Martin, Miguel Ferrer, David Fernández
#          Departamento de Ingenieria de Sistemas Telematicos
#          Universidad Politécnica de Madrid
#

###########################################################
# Modules import
###########################################################

use strict;
use XML::DOM;          					# XML management library
use File::Basename;    					# File management library
use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
use EDIV::cluster_host;                 # Cluster Host class
use Socket;								# To resolve hostnames to IPs
use Term::ANSIColor;

###########################################################
# Global variables 
###########################################################

# Cluster
my $cluster_config;    					# AppConfig object to read cluster config
my $phy_hosts;        					# List of cluster members
my @cluster_hosts;						# Cluster host object array to send to segmentator

# Arguments
my $mode = $ARGV[0];
my @hosts = ();
my $i=1;
while ($ARGV[$i] ne '') {
	push (@hosts, $ARGV[$i]);
	$i++;
}


###########################################################
# Main	
###########################################################	

if (!($mode =~ /[0-9]+/)) {
	print "\nediv_monitor.pl monitors the load, scenarios and virtual machines of hosts in an EDIV cluster\n\n";
	print "Usage: ediv_monitor.pl <period> [host list]\n";
	print "       <period> is a number:\n";
	print "             0 -> show the status and exit\n";
	print "             X -> show the status periodically each X seconds\n";
	print "       [host list] is a space separted list of hosts to monitor. If not specified, \n";
	print "                   all the host in the EDIV cluster are monitorized.\n\n";
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



#
# Subroutines
#

#
# Fill the cluster hosts
#
sub fillClusterHosts {
	
	if ($#hosts eq -1) { # hosts array is empty. No hosts specified in command line
	                     # Get the list of hosts from EDIV cluster.conf file
		
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

	} else { # create a cluster with the list of hosts specified in the command line 
		
		foreach my $host (@hosts) {
			my $cluster_host = eval { new cluster_host(); } or die ($@);
			my $packed_ip = gethostbyname($host);
			my $ip = inet_ntoa($packed_ip);
			$cluster_host->hostName("$host");
			$cluster_host->ipAddress("$ip");;
			push(@cluster_hosts, $cluster_host);
		}
		
	}

}

#
# Subroutine to send vn program
#
sub sendVn{
	
	foreach my $physical_host (@cluster_hosts) {
		my $ip = $physical_host->ipAddress;
		print "Copying vn command to $ip...";
		my $scp_command = `scp -2 -o 'StrictHostKeyChecking no' vn root\@$ip:/tmp/`;
		system ($scp_command);
		print "done.\n";
	
	}
}

#
# Subroutine to check cluster hosts
#
sub monitor{

	my @output;
	my $line;
	
	while (1) {
		
		@output = ();

		my $date=`date`;
		push (@output, "Date: " . color ('bold') . "$date" . color('reset') . "\n");

		foreach my $physical_host (@cluster_hosts) {
			my $ip = $physical_host->ipAddress;
			
			my $hostname = $physical_host->hostName;
			if ($hostname eq "") { $hostname=$physical_host->ipAddress };
			
   			push (@output, "Host: " . color ('bold') . "$hostname" . color('reset') . "\n\n");

			my $uptime_command = 'uptime';
			my $uptime = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip $uptime_command`;
			if ($uptime eq '') {
				push (@output, "  ERROR: cannot connect to $hostname.\n\n");
				next;
			}
			push (@output, "  Load:  $uptime\n");

			my $numScenariosCmd = "/tmp/vn console | grep available | awk '{print NF}'";
			my $numScenarios = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip $numScenariosCmd`;
			chomp $numScenarios;
							
			if ($numScenarios < 3) {
				push (@output, "  No active scenarios on this host\n\n");
			} else {
				my $scenarios = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip /tmp/vn console | grep available`;

				push (@output, sprintf "  %-30s%-30s\n", "Scenario", "Virtual machines" );
				push (@output, "  --------------------------------------------------\n");
				for (my $i=3; $i<=$numScenarios; $i++){
					
					my $scenario = `echo "$scenarios" | awk '{print \$$i}'`;
					chomp $scenario;
					chomp $scenario;
					
					my $vms = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip /tmp/vn console $scenario | grep available`;
					$vms =~ s/.*available vms://;
					chomp $vms;
					push (@output, sprintf "  %-30s%-30s\n", $scenario, color('bold') . $vms . color('reset'));
					push (@output, "  --------------------------------------------------\n");
				}
			}	
			push (@output, "\n");
		}
		
		system ("clear");
		print @output;
		if ($mode eq "0") { exit(0) } 
		else              {	sleep ($mode) }
	}
}
#
# Subroutines end
#
