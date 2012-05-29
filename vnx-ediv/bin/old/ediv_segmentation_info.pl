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
use POSIX qw(setsid setuid setgid);

use Socket;								# To resolve hostnames to IPs

use EDIV::cluster_host;                 # Cluster Host class 
#use EDIV::splitter;						# Module that assigns vm to host
use EDIV::static;  						# Module that process static assignment 


###########################################################
# Global variables 
###########################################################
	
	# Cluster
my $cluster_config;    					# AppConfig object to read cluster config
my $phy_hosts;        					# List of cluster members
my @cluster_hosts;						# Cluster host object array to send to segmentator
	

	# Modes
my $partition_mode = $ARGV[1];			# Default partition mode
my $configuration;						# =1 if scenario has configuration files
	
	# Scenario
my $vnuml_scenario;						# VNUML scenario to split
my %scenarioHash; 						# Scenarios. Every scenario belongs to a host machine
										# Key -> name of physical hostname, Value -> XML Scenario							
my $dom_tree;							# Dom Tree with scenario specification
my $globalNode;							# Global node from dom tree

	# Assignation
my %allocation;							# Asignation of virtual machine - physical host

my @vms_to_split;						# VMs that haven't been assigned by static
my %static_assignment;					# VMs that have assigned by estatic


###########################################################
# Main
###########################################################

# Fill the cluster hosts.
	&fillClusterHosts;

# Parse scenario XML.
	&parseScenario;


	
my $restriction_file = $ARGV[2];
if (!($restriction_file eq undef)){
	my $restriction = static->new($restriction_file, $dom_tree, @cluster_hosts); 
	
	%static_assignment = $restriction->assign();
	if ($static_assignment{"error"} eq "error"){
		&cleanDB;
		die();
	}
	@vms_to_split = $restriction->remaining();
}

my $rdom_tree = \$dom_tree;
my $rpartition_mode = \$partition_mode;
my $rvms_to_split = \@vms_to_split;
my $rcluster_hosts = \@cluster_hosts;
my $rstatic_assignment = \%static_assignment;

%allocation = splitter->split($rdom_tree, $rpartition_mode, $rcluster_hosts, $rvms_to_split, $rstatic_assignment);
	
###########################################################
# Subroutines
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
		my $mem = $cluster_config->get("$current_name"."_mem");
		my $cpu = $cluster_config->get("$current_name"."_cpu");
		my $cpu_dynamic_command = 'cat /proc/loadavg | awk \'{print $1}\'';
		my $cpu_dynamic = `ssh -2 -o 'StrictHostKeyChecking no' -X root\@$ip $cpu_dynamic_command`;
		chomp $cpu_dynamic;
			
		my $max_vhost = $cluster_config->get("$current_name"."_max_vhost");
		my $ifname = $cluster_config->get("$current_name"."_ifname");
			
		# Create new cluster host object
		my $cluster_host = eval { new cluster_host(); } or die ($@);
			
		# Fill cluster host object with parsed data
		$cluster_host->hostName("$hostname");
		$cluster_host->ipAddress("$ip");
		$cluster_host->mem("$mem");
		$cluster_host->cpu("$cpu");
		$cluster_host->maxVhost("$max_vhost");
		$cluster_host->ifName("$ifname");
		$cluster_host->cpuDynamic("$cpu_dynamic");
			
		# Put the complete cluster host object inside @cluster_hosts array
		push(@cluster_hosts, $cluster_host);
		$i++;
	}
	undef $i;
}

sub parseScenario {
	$vnuml_scenario = $ARGV[0];
	my $parser = new XML::DOM::Parser;
	$dom_tree = $parser->parsefile($vnuml_scenario);
	$globalNode = $dom_tree->getElementsByTagName("vnuml")->item(0);
	my $simulation_name=$globalNode->getElementsByTagName("simulation_name")->item(0)->getFirstChild->getData;	
}