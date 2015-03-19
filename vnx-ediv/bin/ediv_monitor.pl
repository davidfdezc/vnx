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
use warnings;
use XML::DOM;          					# XML management library
use File::Basename;    					# File management library
use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
#use EDIV::cluster_host;                 # Cluster Host class
use Socket;								# To resolve hostnames to IPs
use Term::ANSIColor;
use VNX::ClusterMgmt;

###########################################################
# Global variables 
###########################################################

# Cluster
#my $cluster_config;    					# AppConfig object to read cluster config
#my $phy_hosts;        					# List of cluster members
#my @cluster_hosts;						# Cluster host object array to send to segmentator

$cluster_conf_file = "/etc/ediv/cluster.conf";

# Arguments
my $mode = $ARGV[0];
my @host_list = ();
my $i=1;
while (defined($ARGV[$i])) {
	push (@host_list, $ARGV[$i]);
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

# Read and parse cluster config
if (my $res = read_cluster_config($cluster_conf_file)) { 
    print "ERROR: $res\n";  
    exit 1; 
}

# Send vn
&sendVn;

# Monitor.
&monitor;

# Main end
###########################################################


#
# Subroutine to send vn program
#
sub sendVn{
	
	foreach my $host (@cluster_hosts) {
		if ( ($#host_list ge 0) &&  # host_list array is empty. No hosts specified in command line
		     ( ) ) {
		}	
		my $ip = $cluster->{hosts}{$host}->ip_address;
		print "Copying vn command to $ip...";
		my $scp_command = `scp -2 -o 'StrictHostKeyChecking no' /usr/bin/vn root\@$ip:/tmp/`;
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

		foreach my $host (@cluster_hosts) {
			my $ip = $cluster->{hosts}{$host}->ip_address;
			
			my $hostname = $cluster->{hosts}{$host}->host_name;
			if ($hostname eq "") { $hostname = $cluster->{hosts}{$host}->ip_address };
			
   			push (@output, "Host: " . color ('bold') . "$hostname" . color('reset') . "\n\n");

			my $uptime_command = 'uptime';
			my $uptime = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip $uptime_command`;
			if ($uptime eq '') {
				push (@output, "  ERROR: cannot connect to $hostname.\n\n");
				next;
			}
			push (@output, "  Load:  $uptime\n");

			my $numScenariosCmd = "/tmp/vn console 2>&1 | grep available | awk '{print NF}'";
			my $numScenarios = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip $numScenariosCmd`;
			chomp $numScenarios;
            if ($numScenarios eq '') {
            	$numScenarios = 0;
            }							
			if ( $numScenarios < 3) {
				push (@output, "  No active scenarios on this host\n\n");
			} else {
				my $scenarios = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip /tmp/vn console | grep available`;

				push (@output, sprintf "  %-40s%-30s\n", "Scenario", "Virtual machines" );
				push (@output, "  --------------------------------------------------------------------------------\n");
				for (my $i=3; $i<=$numScenarios; $i++){
					
					my $scenario = `echo "$scenarios" | awk '{print \$$i}'`;
					chomp $scenario;
					chomp $scenario;
					
					my $vms = `ssh -2 -o 'StrictHostKeyChecking no' root\@$ip /tmp/vn console $scenario | grep available`;
					$vms =~ s/.*available vms://;
					chomp $vms;
					push (@output, sprintf "  %-40s%-30s\n", $scenario, color('bold') . $vms . color('reset'));
					push (@output, "  --------------------------------------------------------------------------------\n");
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
