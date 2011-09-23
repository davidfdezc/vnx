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

# Explicit declaration of pathname for EDIV modules
#use lib "/usr/share/perl5";

#use strict;
#use warnings;

use XML::DOM;          					# XML management library
use File::Basename;    					# File management library
use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
use POSIX qw(setsid setuid setgid);
use XML::LibXML;
use Cwd 'abs_path';
use Term::ANSIColor;

use Socket;								# To resolve hostnames to IPs

use DBI;								# Module to handle databases

use EDIV::cluster_host;                 # Cluster Host class 
use EDIV::static;  						# Module that process static assignment 

use VNX::CheckSemantics;
use VNX::Globals;
use VNX::FileChecks;
use VNX::BinariesData;
use VNX::DataHandler;
use VNX::vmAPI_dynamips;


###########################################################
# Global variables 
###########################################################
	
	# Cluster
my $cluster_file;						# Cluster conf file
my $cluster_config;    					# AppConfig object to read cluster config
my $phy_hosts;        					# List of cluster members
my @cluster_hosts;						# Cluster host object array to send to segmentator
	
	# VLAN Assignment
my $firstVlan;         					# First VLAN number
my $lastVlan;          					# Last VLAN number

	# Management Network
my $management_network;					# Management network
my $management_network_mask;			# Mask of management network

	# Modes
my $partition_mode;						# Default partition mode
my $mode;								# Running mode
my $configuration;						# =1 if scenario has configuration files
my $execution_mode;						# Execution command mode
# TODO: -M can specify a list of vms not only one
my $vm_name; 							# VM specified with -M tag
my $no_console; 						# Stores the value of --no-console command line option
	
	# Scenario
my $vnx_scenario;						# VNX scenario to split
my %scenarioHash; 						# Scenarios. Every scenario belongs to a host machine
										# Key -> name of physical hostname, Value -> XML Scenario							
my $scenName;							# Scenario name specified in XML 
my $dom_tree;							# Dom Tree with scenario specification
my $globalNode;							# Global node from dom tree
my $restriction_file;					# Static assigment file

	# Assignation
my %allocation;							# Asignation of virtual machine - physical host

my @vms_to_split;						# VMs that haven't been assigned by static
my %static_assignment;					# VMs that have assigned by estatic

my @plugins;							# Segmentation modules that are implemented
my $segmentation_module;

my $conf_plugin_file;					# Configuration plugin file
	# Database variables
my $db;
my $db_type;
my $db_host;
my $db_port;
my $db_user;
my $db_pass;
my $db_connection_info;	

	# Path for dynamips config file
my $dynamips_ext_path;

my $version = "2.0";
my $release = "DD/MM/YYYY";
my $branch = "";

###########################################################
# Main	
###########################################################


# Argument handling
&parseArguments;	

my $vnxConfigFile = "/etc/vnx.conf";
# Set VNX and TMP directories
my $tmp_dir=&get_conf_value ($vnxConfigFile, 'general', 'tmp_dir');
if (!defined $tmp_dir) {
	$tmp_dir = $DEFAULT_TMP_DIR;
}
#print ("  TMP dir=$tmp_dir\n");
my $vnx_dir=&get_conf_value ($vnxConfigFile, 'general', 'vnx_dir');
if (!defined $vnx_dir) {
	$vnx_dir = &do_path_expansion($DEFAULT_VNX_DIR);
} else {
	$vnx_dir = &do_path_expansion($vnx_dir);
}
#print ("  VNX dir=$vnx_dir\n");

# init global objects and check VNX scenario correctness 
&initAndCheckVNXScenario ($vnx_scenario); 
	
# Get DB configuration
&getDBConfiguration;

# Check which running mode is selected
if ( $mode eq '-t' | $mode eq '--create' ) {
	# Scenario launching mode
	print "\n****** You chose mode -t: scenario launching preparation ******\n";
	
	# Fill the cluster hosts.
	&fillClusterHosts;
	# Parse scenario XML.
	print "\n  **** Parsing scenario ****\n\n";
	&parseScenario ($vnx_scenario);

# JSF: movido a parseScenario, borrar
#	#if dynamips_ext node is present, update path
#    $dynamips_ext_path = "";
#    my $dynamips_extTagList=$dom_tree->getElementsByTagName("dynamips_ext");
#    my $numdynamips_ext = $dynamips_extTagList->getLength;
#    if ($numdynamips_ext == 1) {
#		    my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
#		    $dynamips_ext_path = "$vnx_dir/scenarios/";
#    }



	# Fill segmentation mode.
	&getSegmentationMode;

	# Fill segmentation modules.
	&getSegmentationModules;
	
	# Segmentation processing
	if (!($restriction_file eq undef)){
		print "\n  **** Calling static processor... ****\n\n";
		my $restriction = static->new($restriction_file, $dom_tree, @cluster_hosts); 
	
		%static_assignment = $restriction->assign();
		if ($static_assignment{"error"} eq "error"){
			&cleanDB;
			die();
		}
		@vms_to_split = $restriction->remaining();
	}
	
	print "\n  **** Calling segmentator... ****\n\n";
	my $rdom_tree = \$dom_tree;
	my $rvms_to_split = \@vms_to_split;
	my $rcluster_hosts = \@cluster_hosts;
	my $rstatic_assignment = \%static_assignment;

	push (@INC, "/usr/share/ediv/algorithms/");
	push (@INC, "/usr/local/share/ediv/algorithms/");
	
	foreach $plugin (@plugins){
		
		push (@INC, "/usr/share/perl5/EDIV/SegmentationModules/");
		push (@INC, "/usr/local/share/perl/5.10.1/EDIV/SegmentationModules/");
    	
    	require $plugin;
		import	$plugin;
	

		my @module_name_split = split(/\./, $plugin);
		my $plugin_withoutpm = $module_name_split[$0];

    	my $plugin_name = $plugin_withoutpm->name();
    	
		if ($plugin_name eq $partition_mode) {
			
			$segmentation_module = $plugin_withoutpm;	
		}
    
	}  
	if ($segmentation_module eq undef){
    	print 'Segmentator: your choice ' . "$partition_mode" . " is not a recognized option (yet)\n";
    	&cleanDB;
    	die();
    }
	
	%allocation = $segmentation_module->split($rdom_tree, $rcluster_hosts, $rvms_to_split, $rstatic_assignment);
	
	if ($allocation{"error"} eq "error"){
			&cleanDB;
			die();
	}
	
	print "\n  **** Configuring distributed networking in cluster ****\n";
		
	# Fill the scenario array
	&fillScenarioArray;
	unless ($vm_name){
		# Assign first and last VLAN.
		&assignVLAN;
	}	
	# Split into files
	&splitIntoFiles;
	# Make a tgz compressed file containing VM execution config 
	&getConfiguration;
	# Send Configuration to each host.
	&sendConfiguration;
	#jsf: código copiado a sub sendConfiguration, borrar esta subrutina.	
	# Send dynamips configuration to each host.
	#&sendDynConfiguration;
	print "\n\n  **** Sending scenario to cluster hosts and executing it ****\n\n";
	# Send scenario files to the hosts and run them with VNX (-t option)
	&sendScenarios;
	
	unless ($vm_name){
		# Check if every VM is running and ready
		print "\n\n  **** Checking simulation status ****\n\n";
		&checkFinish;
		
		# Create a ssh tunnel to access remote VMs
		print "\n\n  **** Creating tunnels to access VM ****\n\n";
		&tunnelize;
	}
	
} elsif ( $mode eq '-x' | $mode eq '--execute' | $mode eq '--exe' ) {
	# Execution of commands in VMs mode
	
	if ($execution_mode eq undef){
		die ("You must specify execution command\n");
	}
	print "\n****** You chose mode -x: configuring scenario with command $execution_mode ******\n";
	
	# Fill cluster host
	&fillClusterHosts;
	
	# Parse scenario XML
	&parseScenario;
	
	# Make a tgz compressed file containing VM execution config 
	&getConfiguration;
	
	# Send Configuration to each host.
	&sendConfiguration;
	
	# Send Configuration to each host.
	print "\n **** Sending commands to VMs ****\n";
	&executeConfiguration($execution_mode);
	
} elsif ( $mode eq '-P' | $mode eq '--destroy' ) {
	# Clean and purge scenario temporary files
	print "\n****** You chose mode -P: purging scenario ******\n";	
	
	# Fill cluster host
	&fillClusterHosts;
	
	# Parse scenario XML
	&parseScenario;
	
	# Make a tgz compressed file containing VM execution config 
	&getConfiguration;
	
	# Send Configuration to each host.
	&sendConfiguration;
	
	# Clear ssh tunnels to access remote VMs
	&untunnelize;
	
	# Purge the scenario
	&purgeScenario;
	sleep(5);
	
	unless ($vm_name){	
		# Clean simulation from database
		&cleanDB;
		
		# Delete /tmp files
		&deleteTMP;
	}
	
} elsif ( $mode eq '-d' | $mode eq '--shutdown' ) {
	# Clean and destroy scenario temporary files
	print "\n****** You chose mode -d: destroying scenario ******\n";	
	
	# Fill cluster host
	&fillClusterHosts;
	
	# Parse scenario XML
	&parseScenario;
	
	# Make a tgz compressed file containing VM execution config 
	&getConfiguration;
	
	# Send Configuration to each host.
	&sendConfiguration;
	
	# Clear ssh tunnels to access remote VMs
	&untunnelize;
	
	# Purge the scenario
	&destroyScenario;
	sleep(5);

	unless ($vm_name){		
		# Clean simulation from database
		&cleanDB;
		
		# Delete /tmp files
		&deleteTMP;
	}

} elsif ( $mode eq '--define' | $mode eq '--undefine' | $mode eq '--start' | $mode eq '--save' | 
		$mode eq '--restore' | $mode eq '--suspend' | $mode eq '--resume' | $mode eq '--reboot' ) {
	# Processing VMs mode

	print "\n****** You chose mode $mode ******\n";
	
	# Fill cluster host
	&fillClusterHosts;
	
	# Parse scenario XML
	&parseScenario;
	
	# Make a tgz compressed file containing VM execution config 
	&getConfiguration;
	
	# Send Configuration to each host.
	&sendConfiguration;
	
	# Process mode defined in $mode
	&processMode;

	
} else {
	# default action: die
	die ("Your choice $mode is not a recognized option (yet)\n");
	
}

printf("\n****** Succesfully finished ******\n\n");
exit();

# Main end
###########################################################

###########################################################
# Subroutines
###########################################################

	###########################################################
	# Subroutine to obtain the arguments
	###########################################################
sub parseArguments{
	
	my $arg_lenght = $#ARGV +1;
	for ($i==0; $i<$arg_lenght; $i++){
		
		# Search for execution mode
		if ($ARGV[$i] eq '-t' || $ARGV[$i] eq '--create' || $ARGV[$i] eq '-x' || $ARGV[$i] eq '--exe' || 
		$ARGV[$i] eq '--execute' ||	$ARGV[$i] eq '-P' || $ARGV[$i] eq '--destroy' || $ARGV[$i] eq '-d'||
		 $ARGV[$i] eq '--shutdown' ){
			$mode = $ARGV[$i];
			if ($mode eq '-x' | $mode eq '--exe' | $mode eq '--execute'){
				my $execution_mode_arg = $i + 1;
				$execution_mode = $ARGV[$execution_mode_arg];
			}
		}
		# Search for new execution modes
		if ($ARGV[$i] eq '--define' | $ARGV[$i] eq '--undefine' | $ARGV[$i] eq '--start' | $ARGV[$i] eq '--save' | 
		$ARGV[$i] eq '--restore' | $ARGV[$i] eq '--suspend' | $ARGV[$i] eq '--resume' | $ARGV[$i] eq '--reboot'){
			$mode = $ARGV[$i];
		}
		# Search for scenario xml file
		if ($ARGV[$i] eq '-s' | $ARGV[$i] eq '-f'){
			my $vnunl_scenario_arg = $i+1;
			$vnx_scenario = $ARGV[$vnunl_scenario_arg];
			open(FILEHANDLE, $vnx_scenario) or die  "The scenario file $vnx_scenario doesn't exist... Aborting";
			close FILEHANDLE;
			
		}
		# Search for a cluster conf file
		if ($ARGV[$i] eq '-c'){
			my $cluster_conf_arg = $i+1;
			$cluster_file = $ARGV[$cluster_conf_arg];
			open(FILEHANDLE, $cluster_file) or die  "The configuration cluster file $cluster_file doesn't exist... Aborting";
			close FILEHANDLE;
			
		}
		# Search for segmentation algorithm
		if ($ARGV[$i] eq '-a'){
			my $partition_mode_arg = $i +1;
			$partition_mode = $ARGV[$partition_mode_arg];
		}
		# Search for static assigment file
		if ($ARGV[$i] eq '-r'){
			my $restriction_file_arg = $i +1;
			$restriction_file = $ARGV[$restriction_file_arg];
			open(FILEHANDLE, $restriction_file) or die  "The restriction file $restriction_file doesn't exist... Aborting";
			close FILEHANDLE;	
		}
		# Search for -M tag
		if ($ARGV[$i] eq '-M'){
			my $vm_name_arg = $i +1;
			$vm_name = $ARGV[$vm_name_arg];
		}		
		# Search for -n|--no-console tag
		if ($ARGV[$i] eq '-n' || $ARGV[$i] eq '--no-console'){
			$no_console = "--no-console";
		}		
	}
	if ($mode eq undef){
		die ("You didn't specify a valid execution mode (-t, -x, -P, -d)... Aborting");
	}
	if ($vnx_scenario eq undef){
		die ("You didn't specify a valid scenario xml file... Aborting");
	}
	if ($cluster_file eq undef){
		$cluster_file = "/etc/ediv/cluster.conf";
		open(FILEHANDLE, $cluster_file) or undef $cluster_file;
		close(FILEHANDLE);
	}
	if ($cluster_file eq undef){
		$cluster_file = "/usr/local/etc/ediv/cluster.conf";
		open(FILEHANDLE, $cluster_file) or die "The cluster configuration file doesn't exist in /etc/ediv or in /usr/local/etc/ediv... Aborting";
		close(FILEHANDLE);
	}
	print "\n****** Using cluster configuration file: $cluster_file ******\n";
}


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
	# Subroutine to obtain cluster configuration info
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
		my $hostname = gethostbyaddr($packed_ip, AF_INET);
		if ($hostname eq '') { $hostname = $ip }
		my $mem = $cluster_config->get("$current_name"."_mem");
		my $cpu = $cluster_config->get("$current_name"."_cpu");
		my $cpu_dynamic_command = 'cat /proc/loadavg | awk \'{print $1}\'';
		my $cpu_dynamic = `ssh -2 -o 'StrictHostKeyChecking no' -X root\@$ip $cpu_dynamic_command`;
		chomp $cpu_dynamic;
			
		my $max_vhost = $cluster_config->get("$current_name"."_max_vhost");
		my $ifname = $cluster_config->get("$current_name"."_ifname");

		# Get vnx_dir for each host in the cluster 
		my $vnxDir = `ssh -X -2 -o 'StrictHostKeyChecking no' root\@$ip 'cat /etc/vnx.conf | grep ^vnx_dir'`;
		my @aux = split(/=/, $vnxDir);
		chomp($aux[1]);
		$vnxDir=$aux[1];
		if ($vnxDir eq '') { $vnxDir = $DEFAULT_VNX_DIR}
			
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
		$cluster_host->vnxDir("$vnxDir");
			
		# Put the complete cluster host object inside @cluster_hosts array
		push(@cluster_hosts, $cluster_host);
		$i++;
	}
	undef $i;
}
	
	###########################################################
	# Subroutine to obtain segmentation mode 
	###########################################################
sub getSegmentationMode {
	
	if ( !($partition_mode eq undef)) {
		print ("$partition_mode segmentation mode selected\n");
	}else {
		$partition_mode = $cluster_config->get("cluster_default_segmentation");
		print ("Using default partition mode: $partition_mode\n");
	}
}

	###########################################################
	# Subroutine to obtain segmentation modules 
	###########################################################
sub getSegmentationModules {
	
	my @paths;
	push (@paths, "/usr/share/ediv/algorithms/");
	push (@paths, "/usr/local/share/ediv/algorithms/");
	
	foreach $path (@paths){
		opendir(DIRHANDLE, "$path"); 
		foreach $module (readdir(DIRHANDLE)){ 
			if ((!($module eq ".."))&&(!($module eq "."))){
				
				push (@plugins, $module);	
			} 
		} 
		closedir DIRHANDLE;
	} 
	my $plugins_size = @plugins;
	if ($plugins_size == 0){
		&cleanDB;
		die ("Algorithm not found at /usr/share/ediv/algorithms or /usr/local/share/ediv/algorithms .. Aborting");
	}

}

	###########################################################
	# Subroutine to parse XML scenario specification into DOM tree
	###########################################################
sub parseScenario {
	
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	my $parser = new XML::DOM::Parser;
	$dom_tree = $parser->parsefile($vnx_scenario);
	$globalNode = $dom_tree->getElementsByTagName("vnx")->item(0);
	$scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
	if ($mode eq '-t' | $mode eq '--create') {
		
			# Checking if the simulation already exists
		my $query_string = "SELECT `name` FROM simulations WHERE name='$scenName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();

		if ( !($vm_name) && !($contenido eq undef)) {
			die ("The simulation $scenName was already created... Aborting");
		} 
	
			# Creating simulation in the database
		$query_string = "INSERT INTO simulations (name) VALUES ('$scenName')";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
	} elsif($mode eq '-x' | $mode eq '--exe' | $mode eq '--execute') {
		
			# Checking if the simulation is running
		my $query_string = "SELECT `simulation` FROM hosts WHERE status = 'running' AND simulation = '$scenName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();
		if ($contenido eq undef) {
			die ("The simulation $scenName wasn't running... Aborting");
		} 
		$query->finish();
	} elsif($mode eq '-P' | $mode eq '--destroy') {
		
		# Checking if the simulation is running
		my $query_string = "SELECT `simulation` FROM hosts WHERE (status = 'running' OR status = 'creating') AND simulation = '$scenName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();
		if ($contenido eq undef) {
			die ("The simulation $scenName wasn't running... Aborting");
		}
		$query->finish();
		# If no -M option, mark simulation as "purging"
		unless ($vm_name){
			$query_string = "UPDATE hosts SET status = 'purging' WHERE status = 'running' AND simulation = '$scenName'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			$query->finish();
		}
	} elsif($mode eq '-d' | $mode eq '--shutdown') {
		
		# Checking if the simulation is running
		my $query_string = "SELECT `simulation` FROM hosts WHERE status = 'running' AND simulation = '$scenName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();
		if ($contenido eq undef) {
			die ("The simulation $scenName wasn't running... Aborting");
		}
		# If no -M option, mark simulation as "destroying"
		unless ($vm_name){
			$query->finish();
			$query_string = "UPDATE hosts SET status = 'destroying' WHERE status = 'running' AND simulation = '$scenName'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			$query->finish();
		}
		
	} elsif($mode eq '--define' | $mode eq '--undefine' | $mode eq '--start' | $mode eq '--save' | 
		$mode eq '--restore' | $mode eq '--suspend' | $mode eq '--resume' | $mode eq '--reboot') {
		# quizá el define se podría usar sin la simulacion creada ya, sobraria aqui	
		# Checking if the simulation is running
		my $query_string = "SELECT `simulation` FROM hosts WHERE status = 'running' AND simulation = '$scenName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();
		if ($contenido eq undef) {
			die ("The simulation $scenName wasn't running... Aborting");
		}
		$query->finish();
	}
	 

	#if dynamips_ext node is present, update path
	$dynamips_ext_path = "";
	my $dynamips_extTagList=$dom_tree->getElementsByTagName("dynamips_ext");
	my $numdynamips_ext = $dynamips_extTagList->getLength;
	if ($numdynamips_ext == 1) {
		my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
		$dynamips_ext_path = "$vnx_dir/scenarios/";
	}


	$dbh->disconnect;	
}

	###########################################################
	# Subroutine to read VLAN configuration from cluster config or database
	###########################################################
sub assignVLAN {
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	$firstVlan = $cluster_config->get("vlan_first");
	$lastVlan  = $cluster_config->get("vlan_last");	

	while (1){
			my $query_string = "SELECT `number` FROM vlans WHERE number='$firstVlan'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $contenido = $query->fetchrow_array();
			if ($contenido eq undef){
				last;
			}
			$query->finish();
			$firstVlan++;
			if ($firstVlan >$lastVlan){
				&cleanDB;
				die ("There isn't more free vlans... Aborting");
			}	
	}	
	$dbh->disconnect;
}
	
	###########################################################
	# Subroutine to fill the scenario Array.
	# We clone the original document to perform as a new scenario. 
	# We create an vnx node on every scenario and start adding child nodes to it.
	###########################################################
sub fillScenarioArray {
	
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);	
	my $numberOfHosts = @cluster_hosts;

	# Create a new template document by cloning the scenario tree
	my $templateDoc= $dom_tree->cloneNode("true");
    my $newVnxNode=$templateDoc->getElementsByTagName("vnx")->item(0);
	print $newVnxNode->getNodeTypeName."\n";
	print $newVnxNode->getNodeName."\n";
    for my $kid ($newVnxNode->getChildNodes){
		unless ($kid->getNodeName eq 'global'){
			$newVnxNode->removeChild($kid);
		} 
	}
	# Clone <global> section and add it to template document
#	my $global= $dom_tree->getElementsByTagName("global")->item(0)->cloneNode("true");
#	$global->setOwnerDocument($templateDoc);
#	$newVnxNode->appendChild($global);

#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
	# Create a new document for each host in the cluster by cloning the template document ($templateDoc)
	for ($i=0; $i<$numberOfHosts;$i++){
		
		my $scenarioDoc=$templateDoc->cloneNode("true");
		my $currentHostName=$cluster_hosts[$i]->hostName;
		my $currentHostIP=$cluster_hosts[$i]->ipAddress;

		my $hostScenName=$scenName."_".$currentHostName;
		$scenarioDoc->getElementsByTagName("scenario_name")->item(0)->getFirstChild->setData($hostScenName);
		
		#if dynamips_ext tag is present, update path
		my $dynamips_extTagList=$scenarioDoc->getElementsByTagName("dynamips_ext");
    	my $numdynamips_ext = $dynamips_extTagList->getLength;

# TODO: check in CheckSemantics that dynamips_ext only appears once
    	if ($numdynamips_ext == 1) {	

	   		my $virtualmList=$globalNode->getElementsByTagName("vm");
			my $vmListLength = $virtualmList->getLength;
			my $keep_dynamips_in_scenario = 0;
			for (my $m=0; $m<$vmListLength; $m++){
				my $vm=$virtualmList->item($m);
				my $vmName = $vm->getAttribute("name");
				my $hostName = $allocation{$vmName};
				if ($hostName eq $currentHostName){
					my $vmType = $vm->getAttribute("type");
					if ($vmType eq "dynamips"){
						$keep_dynamips_in_scenario = 1;
					}
				}	
			}
	   		if ($keep_dynamips_in_scenario == 1){
	   			#my $current_host_dynamips_path = $dynamips_ext_path . $hostScenName ."/dynamips-dn.xml";
	   			#print $dynamips_extTagList->item(0)->getFirstChild->getData . "\n";
	   			#print "current_host_dynamips_path=$current_host_dynamips_path\n";<STDIN>;
	   			# las tres lineas de arriba no funcionan, ya que no puedo meter el xml en los
	   			# directorios del escenario antes de crearlo, hay que usar un /tmp:
	   			my $current_host_dynamips_path = "/tmp/dynamips-dn.xml";
	   			$dynamips_extTagList->item(0)->getFirstChild->setData($current_host_dynamips_path);
	   			print $dynamips_extTagList->item(0)->getFirstChild->getData . "\n";
	   		}else{
	#  			my $dynamips_extTag = $dynamips_extTagList->item(0);
	#    		$parentnode = $dynamips_extTag->parentNode;
	#  			$parentnode->removeChild($dynamips_extTag);
				
				foreach my $node ( $scenarioDoc->getElementsByTagName("dynamips_ext") ) {
					$scenarioDoc->getElementsByTagName("global")->item(0)->removeChild($node);
				}

	   		}	

#foreach my $node ( $doc->getChildNodes() ) {
#if ( $node->getNodeType() == ELEMENT_NODE ) {
#remove_comments($node);
#}
#elsif ( $node->getNodeType() == COMMENT_NODE ) {
#$doc->removeChild($node);

#    			for my $kid ($scenarioDoc->getChildNodes){
#    				
#					if ($kid->getName eq "dynamips_ext"){
#						$newVnxNode->removeChild($kid); 
#					}
#				}
    			
#    			$scenarioDoc->removeChild($scenarioDoc->getElementsByTagName("dynamips_ext")->item(0));
#    		}
    	}	
		
		my $basedir_data = "/tmp/";
		eval{
			$scenarioDoc->getElementsByTagName("global")->item(0)->getElementsByTagName("vm_defaults")->item(0)->getElementsByTagName("basedir")->item(0)->getFirstChild->setData($basedir_data);
		};		
		$scenarioHash{$currentHostName} = $scenarioDoc;	
		# Save data into DB
		
		my $query_string = "INSERT INTO hosts (simulation,local_simulation,host,ip,status) VALUES ('$scenName','$hostScenName','$currentHostName','$currentHostIP','creating')";
		print "**** QUERY=$query_string\n";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();

	}
	$dbh->disconnect;
}


#
# Split the original scenario xml file into several smaller files for each host physical machine.
#
sub splitIntoFiles {

	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	# We explore the vms on the node and call vmPlacer to place them on the scenarios	
	my $virtualmList=$globalNode->getElementsByTagName("vm");

	my $vmListLength = $virtualmList->getLength;
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;

	# Add VMs to corresponding subscenario specification file
	for (my $m=0; $m<$vmListLength; $m++){
		
		my $vm = $virtualmList->item($m);
		my $vmName = $vm->getAttribute("name");
		my $hostName = $allocation{$vmName};
		
		#print "**** $vmName\n";
		#añadimos type para base de datos
		my $vmType = $vm->getAttribute("type");

		#print "*** OLD: \n";
		#print $vm->toString;

		my $newVirtualM=$vm->cloneNode("true");
		
		#print "\n*** NEW: \n";
		#print $newVirtualM->toString;
		#print "***\n";
		
		$newVirtualM->setOwnerDocument($scenarioHash{$hostName});

		my $vnxNode=$scenarioHash{$hostName}->getElementsByTagName("vnx")->item(0);
			
		$vnxNode->setOwnerDocument($scenarioHash{$hostName});
		
		$vnxNode->appendChild($newVirtualM);
		#print $vnxNode->toString;
		#print "***\n";

		unless ($vm_name){
				# Creating virtual machines in the database

			my $query_string = "SELECT `name` FROM vms WHERE name='$vmName'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $contenido = $query->fetchrow_array();
			if ( !($contenido eq undef)) {
				&cleanDB;
				die ("The vm $vmName was already created... Aborting");
			}
			$query->finish();

			#añadimos type
			#$query_string = "INSERT INTO vms (name,simulation,host) VALUES ('$vmName','$scenName','$hostName')";
			$query_string = "INSERT INTO vms (name,type,simulation,host) VALUES ('$vmName','$vmType','$scenName','$hostName')";

		print "**** QUERY=$query_string\n";
			$query = $dbh->prepare($query_string);
			$query->execute();
			$query->finish();

		}		
	}

	# We add the corresponding nets to subscenario specification file
	my $nets= $globalNode->getElementsByTagName("net");
	
	# For exploring all the nets on the global scenario
	for (my $h=0; $h<$nets->getLength; $h++) {
		
		my $currentNet=$nets->item($h);
		my $nameOfNet=$currentNet->getAttribute("name");

		# For exploring each scenario on scenarioarray	
		foreach $hostName (keys(%scenarioHash)) {
			
			my $currentScenario = $scenarioHash{$hostName};		
			my $currentVMList = $currentScenario->getElementsByTagName("vm");
			my $netFlag = 0; # 1 indicates that the current net we are dealing with is already on this scenario.

			# For exploring the vms on each scenario	
			for (my $n=0; $n<$currentVMList->getLength; $n++){
				my $currentVM=$currentVMList->item($n);
				my $interfaces=$currentVM->getElementsByTagName("if");
				
				# For exploring all the interfaces on each vm.
				for (my $k=0; $k<$interfaces->getLength; $k++){
					my $netName = $interfaces->item($k)->getAttribute("net");
					if ($nameOfNet eq $netName){
						if ($netFlag==0){
							my $netToAppend=$currentNet->cloneNode("true");
							$netToAppend->setOwnerDocument($currentScenario);
							
							my $firstVM=$currentScenario->getElementsByTagName("vm")->item(0);
							$currentScenario->getElementsByTagName("vnx")->item(0)->insertBefore($netToAppend, $firstVM);
									
							$netFlag=1;
						}
					}
				}
			}				
		}
	}
	$dbh->disconnect;
	unless ($vm_name){
		&netTreatment;
		&setAutomac;
	}
}

	###########################################################
	# Subroutine to process nets to configure them for distributed operation
	###########################################################
sub netTreatment {
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
	# 1. Make a list of nets to handle
	my %nets_to_handle;
	my $nets= $globalNode->getElementsByTagName("net");
	
		# For exploring all the nets on the global scenario
	for (my $h=0; $h<$nets->getLength; $h++) {
		
		my $currentNet=$nets->item($h);
		my $nameOfNet=$currentNet->getAttribute("name");
		
			#Creating virtual nets in the database
		my $query_string = "SELECT `name` FROM nets WHERE name='$nameOfNet'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();
		if ( !($contenido eq undef)) {
			print ("INFO: The net $nameOfNet was already created...");
		}
		$query->finish();
		$query_string = "INSERT INTO nets (name,simulation) VALUES ('$nameOfNet','$scenName')";
		$query = $dbh->prepare($query_string);
		$query->execute();	
		$query->finish();
		
			# For exploring each scenario on scenarioarray	
		my @net_host_list;
		foreach $hostName (keys(%scenarioHash)) {
			my $currentScenario = $scenarioHash{$hostName};
			my $currentScenario_nets = $currentScenario->getElementsByTagName("net");
			for (my $j=0; $j<$currentScenario_nets->getLength; $j++) {
				my $currentScenario_net = $currentScenario_nets->item($j);
				
				if ( ($currentScenario_net->getAttribute("name")) eq ($nameOfNet)) {
					push(@net_host_list, $hostName);
				} 
			}							
		}
		my $net_size = @net_host_list;
		if ($net_size > 1) {
			$nets_to_handle{$nameOfNet} = [@net_host_list];
		}
	}
	
	# 2. Modify the nets	
	my %commands;
	my %commands_off;

	my $current_vlan = $firstVlan;
	foreach $net_name (keys(%nets_to_handle)) {
		# 2.1 VLAN and bridge assignation
		
		while (1){
			my $query_string = "SELECT `number` FROM vlans WHERE number='$current_vlan'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $contenido = $query->fetchrow_array();
			if ($contenido eq undef){
				last;
			}
			$query->finish();
			$current_vlan++;
			
			if ($current_vlan >$lastVlan){
				&cleanDB;
				die ("There isn't more free vlans... Aborting");
			}	
		}
	
		my $current_net = $nets_to_handle{$net_name};
		my $net_vlan = $current_vlan;
		
		# 2.2 Use previous data to modify subscenario
		foreach $hostName (keys(%scenarioHash)) {
			my $external;
			my $command_list;
			foreach $physical_host (@cluster_hosts) {
				if ($physical_host->hostName eq $hostName) {
					$external = $physical_host->ifName;
				}				
			}
			my $currentScenario = $scenarioHash{$hostName};
			for (my $k=0; defined($current_net->[$k]); $k++) {
				if ($current_net->[$k] eq $hostName) {
					my $currentScenario_nets = $currentScenario->getElementsByTagName("net");
					for (my $l=0; $l<$currentScenario_nets->getLength; $l++) {
						my $currentNet = $currentScenario_nets->item($l);
						my $currentNetName = $currentNet->getAttribute("name");
						if ($net_name eq $currentNetName) {
							my $treated_net = $currentNet->cloneNode("true");
							$treated_net->setAttribute("external", "$external.$net_vlan");
							$treated_net->setAttribute("mode", "virtual_bridge");
							$treated_net->setOwnerDocument($currentScenario);
							$currentScenario->getElementsByTagName("vnx")->item(0)->replaceChild($treated_net, $currentNet);
							
								# Adding external interface to virtual net
							
							$query_string = "UPDATE nets SET external = '$external.$net_vlan' WHERE name='$currentNetName'";
							$query = $dbh->prepare($query_string);
							$query->execute();
							$query->finish();
							
							$query_string = "INSERT INTO vlans (number,simulation,host,external_if) VALUES ('$net_vlan','$scenName','$hostName','$external')";
							$query = $dbh->prepare($query_string);
							$query->execute();
							$query->finish();
		
							my $vlan_command = "vconfig add $external $net_vlan\nifconfig $external.$net_vlan 0.0.0.0 up\n";
							$commands{$hostName} = $commands{$hostName}."$vlan_command";						
						}
					}
				}
			}
		}
	}
	
	# 3. Configure nets of cluster machines
	foreach $hostName (keys(%commands)){
		my $host_ip;
		foreach $physical_host (@cluster_hosts) {
			if ($physical_host->hostName eq $hostName) {
				$host_ip = $physical_host->ipAddress;
			}				
		}
		
		my $host_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip '$commands{$hostName}'";
		&daemonize($host_command, "/tmp/$hostName"."_log");
	}
	$dbh->disconnect;
}

	###########################################################
	# Subroutine to set the proper value on automac offset
	###########################################################
sub setAutomac {
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	my $VmOffset;
	my $MgnetOffset;
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
	my $query_string = "SELECT `automac_offset` FROM simulations ORDER BY `automac_offset` DESC LIMIT 0,1";
	my $query = $dbh->prepare($query_string);
	$query->execute();
	my $contenido = $query->fetchrow_array();
	if ( $contenido eq undef) {
		$VmOffset = 0;
	} else {
		$VmOffset = $contenido; # we hope this is enough
	}

	$query_string = "SELECT `mgnet_offset` FROM simulations ORDER BY `mgnet_offset` DESC LIMIT 0,1";
	$query = $dbh->prepare($query_string);
	$query->execute();
	my $contenido1 = $query->fetchrow_array();
	if ( $contenido1 eq undef) {
		$MgnetOffset = 0;
	} else {
		$MgnetOffset = $contenido1; # we hope this is enough
	}
	$query->finish();
	
	$management_network = $cluster_config->get("cluster_mgmt_network");
	$management_network_mask = $cluster_config->get("cluster_mgmt_network_mask");
	
	foreach $hostName (keys(%scenarioHash)) {
		
		my $currentScenario = $scenarioHash{$hostName};
		my $automac=$currentScenario->getElementsByTagName("automac")->item(0);
		if (!($automac)){
			$automac=$currentScenario->createElement("automac");
			$currentScenario->getElementsByTagName("global")->item(0)->appendChild($automac);
			
		}
		
		$automac->setAttribute("offset", $VmOffset);
		$VmOffset +=150;  #JSF temporalmente cambiado, hasta que arregle el ""FIXMEmac"" de vnx
		#$VmOffset +=5;
		
		my $management_net=$currentScenario->getElementsByTagName("vm_mgmt")->item(0);
		
			# If management network doesn't exist, create it
		if (!($management_net)) {
			$management_net = $currentScenario->createElement("vm_mgmt");
			$management_net->setAttribute("type", "private");
			my $vm_defaults_node = $currentScenario->getElementsByTagName("vm_defaults")->item(0);
			$currentScenario->getElementsByTagName("global")->item(0)->insertBefore($management_net, $vm_defaults_node);
		}
			# If management network is type 'none', change it
		if ($management_net->getAttribute("type") eq "none") {
			$management_net->setAttribute("type", "private");
		}
			# Change management network properties for avoid overlaps (ALWAYS)
		$management_net->setAttribute("network", $management_network);
		$management_net->setAttribute("mask", $management_network_mask);
		$management_net->setAttribute("offset",$MgnetOffset);
		foreach $virtual_machine (keys(%allocation)) {
			if ($allocation{$virtual_machine} eq $hostName) {
				$MgnetOffset += 4; # Uses mask /30 with a point-to-point management network
			}				
		}
			# If management network doesn't use host_mapping, activate it
		my $host_mapping_property = $currentScenario->getElementsByTagName("host_mapping")->item(0);
		if (!($host_mapping_property)) {
			$host_mapping_property = $currentScenario->createElement("host_mapping");
			$currentScenario->getElementsByTagName("vm_mgmt")->setOwnerDocument($currentScenario);
			$currentScenario->getElementsByTagName("vm_mgmt")->item(0)->appendChild($host_mapping_property);
		}
		
		#my $net_offset = $currentScenario->getElementsByTagName("vm_mgmt")->item(0);
		#$net_offset->setAttribute("offset", $MgnetOffset);
		#$net_offset->setAttribute("mask","16");
		
#		foreach $virtual_machine (keys(%allocation)) {
#			if ($allocation{$virtual_machine} eq $hostName) {
#				$MgnetOffset += 4; # Uses mask /30 with a point-to-point management network
#			}				
#		}	
	}
	$query_string = "UPDATE simulations SET automac_offset = '$VmOffset' WHERE name='$scenName'";
	$query = $dbh->prepare($query_string);
	$query->execute();	
	$query->finish();
	
		
	$query_string = "UPDATE simulations SET mgnet_offset = '$MgnetOffset' WHERE name='$scenName'";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$dbh->disconnect;
	
}

	###########################################################
	# Subroutine to send scenario files to hosts
	###########################################################
sub sendScenarios {
	my $dbh;
	my $host_ip;
	foreach $hostName (keys(%scenarioHash)) {
	
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		my $currentScenario = $scenarioHash{$hostName};
		foreach $physical_host (@cluster_hosts) {
			if ($physical_host->hostName eq $hostName) {
				$host_ip = $physical_host->ipAddress;
			}				
		}
	
		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){	
			my $query_string = "SELECT `host` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $host_of_vm = $query->fetchrow_array();
			unless ($hostName eq $host_of_vm){
				next;
			}
		}
		
		my $hostScenName = $currentScenario->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
#		my $scenName = $filename;

		my $hostScenFileName = "/tmp/$hostScenName".".xml";
		$currentScenario->printToFile("$hostScenFileName");
		print "**** /tmp/$hostScenFileName \n";
		system ("cat /tmp/$hostScenFileName");
			# Save the local specification in DB	
		open(FILEHANDLE, $hostScenFileName) or die  'cannot open file!';
		my $fileData;
		read (FILEHANDLE,$fileData, -s FILEHANDLE);

		# We scape the "\" before writing the scenario to the ddbb
   		$fileData =~ s/\\/\\\\/g; 
		my $query_string = "UPDATE hosts SET local_specification = '$fileData' WHERE local_simulation='$hostScenName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		close (FILEHANDLE);
		
		my $scp_command = "scp -2 $hostScenFileName root\@$host_ip:/tmp/";
		&daemonize($scp_command, "/tmp/$hostName"."_log");
		my $permissions_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip \'chmod -R 777 $hostScenFileName\'";
		&daemonize($permissions_command, "/tmp/$hostName"."_log"); 
#VNX		my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnumlparser.pl -Z -u root -v -t $filename -o /dev/null\'";
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnx -f $hostScenFileName -v -t -o /dev/null\ " 
		                  . $option_M . " " . $no_console . "'";
		&daemonize($ssh_command, "/tmp/$hostName"."_log");		
	}
	$dbh->disconnect;
}

	###########################################################
	# Subroutine to check propper finishing of launching mode (-t)
	# Uses $vnx_dir/simulations/<simulacion>/vms/<vm>/status file
	###########################################################
sub checkFinish {

	my $dbh;
	my $host_ip;
	my $hostName;
	my $scenario;
	my $file;
	
	# Get vnx_dir for each host in the cluster 
#	foreach $physical_host(@cluster_hosts){
#		$host_ip = $physical_host->ipAddress;
#		$hostName = $physical_host->hostName;
#		my $vnxDirHost = `ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'cat /etc/vnx.conf | grep ^vnx_dir'`;
#		chomp ($vnxDirHost);
#		my @aux = split(/=/, $vnxDirHost);
#		$vnxDirHost=$aux[1];
#		print "*** " . $physical_host->hostName . ":" . $physical_host->vnxDir. "\n";		
#	}

	my @output1;
	my @output2;
	my $notAllRunning = "yes";
	while ($notAllRunning) {
		$notAllRunning = '';
		@output1 = ();
		@output2 = ();
		my $date=`date`;
		push (@output1, "\nScenario: " . color ('bold') . $scenName . color('reset') . "\n");			
		push (@output1, "\nDate: " . color ('bold') . "$date" . color('reset') . "\n");
		push (@output1, sprintf (" %-24s%-24s%-20s%-40s\n", "VM name", "Host", "Status", "Status file"));			
		push (@output1, sprintf ("---------------------------------------------------------------------------------------------------------------\n"));			

		foreach $physical_host(@cluster_hosts){
			$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
			$host_ip = $physical_host->ipAddress;
			$hostName = $physical_host->hostName;
			
			foreach $vms (keys (%allocation)){
				if ($allocation{$vms} eq $hostName){
					my $statusFile = $physical_host->vnxDir . "/scenarios/" . $scenName . "_" . $hostName . "/vms/$vms/status";
					my $status_command = "ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'cat $statusFile 2> /dev/null'";
					my $status = `$status_command`;
					chomp ($status);
					if (!$status) { $status = "undefined" }
					push (@output2, color ('bold'). sprintf (" %-24s%-24s%-20s%-40s\n", $vms, $hostName, $status, $statusFile) . color('reset'));
					if (!($status eq "running")) {
						$notAllRunning = "yes";
					}
				}
			}
		}
		system "clear";
		print @output1;
		print sort(@output2);
		printf "---------------------------------------------------------------------------------------------------------------\n";			
		sleep 2;
	}

	foreach $physical_host(@cluster_hosts){
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		$host_ip = $physical_host->ipAddress;
		$hostName = $physical_host->hostName;
		
		my $query_string = "SELECT `local_simulation` FROM hosts WHERE status = 'creating' AND host = '$hostName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$scenario = $query->fetchrow_array();
		$query->finish();
		chomp($scenario);
		$dbh->disconnect;
		
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		$query_string = "UPDATE hosts SET status = 'running' WHERE status = 'creating' AND host = '$hostName'";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		$dbh->disconnect;
	}

=BEGIN	
	foreach $physical_host(@cluster_hosts){
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		$host_ip = $physical_host->ipAddress;
		$hostName = $physical_host->hostName;
		
		my $query_string = "SELECT `local_simulation` FROM hosts WHERE status = 'creating' AND host = '$hostName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$scenario = $query->fetchrow_array();
		$query->finish();
		chomp($scenario);
		$dbh->disconnect;
		
		open STDERR, "/dev/null";
		foreach $vms (keys (%allocation)){
			if ($allocation{$vms} eq $hostName){
				
				my $statusFile = $physical_host->vnxDir . "/scenarios/$scenario/vms/$vms/status";
				print ("Checking $vms status ($statusFile)\n");
				my $status_command = "ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'cat $statusFile'";
				my $status = `$status_command`;
				chomp ($status);

				while (!($status eq "running")) {
					print ("\t $vms still booting, waiting...(status=$status)\n");
					#print "*** $status_command\n"; 
					$status = `$status_command`;
					chomp ($status);
					sleep(5);
				}
				print ("\t $vms running\n");
			}
		}
		close STDERR;
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		$query_string = "UPDATE hosts SET status = 'running' WHERE status = 'creating' AND host = '$hostName'";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		$dbh->disconnect;
	}
=END
=cut
}

	###########################################################
	# Subroutine to execute purge mode in cluster
	###########################################################
sub purgeScenario {
	my $dbh;
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	my $host_ip;
	my $hostName;

	my $scenario;
	foreach $physical_host (@cluster_hosts) {
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		my $vlan_command;
		$host_ip = $physical_host->ipAddress;			
		$hostName = $physical_host->hostName;


		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){
			my $query_string = "SELECT `host` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $host_of_vm = $query->fetchrow_array();

			unless ($hostName eq $host_of_vm){
				next;
			}
		}
	
		# If vm specified with -M, do not switch simulation status to "purging".
		my $simulation_status;
		if ($vm_name){
			$simulation_status = "running";
		}else{
			$simulation_status = "purging";
		}

		my $query_string = "SELECT `local_simulation` FROM hosts WHERE status = '$simulation_status' AND host = '$hostName' AND simulation = '$scenName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_name = $query->fetchrow_array();
		$query->finish();

		$query_string = "SELECT `local_specification` FROM hosts WHERE status = '$simulation_status' AND host = '$hostName' AND simulation = '$scenName'";
		$query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_bin = $query->fetchrow_array();
		$query->finish();
		
		$scenario_name = "/tmp/$scenario_name".".xml";
		open(FILEHANDLE, ">$scenario_name") or die 'cannot open file';
		print FILEHANDLE "$scenario_bin";
		close (FILEHANDLE);
	
		my $scp_command = "scp -2 $scenario_name root\@$host_ip:/tmp/";
		&daemonize($scp_command, "/tmp/$hostName"."_log");

		my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $scenario_name\'";
		&daemonize($permissions_command, "/tmp/$hostName"."_log");
		
		print "\n  **** Stopping simulation and network restoring in $hostName ****\n";
#VNX		my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnumlparser.pl -u root -v -P $scenario_name'";
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx -v -P -f $scenario_name " . $option_M . "'";
		&daemonize($ssh_command, "/tmp/$hostName"."_log");	


		unless ($vm_name){
			#Clean vlans
			$query_string = "SELECT `number`, `external_if` FROM vlans WHERE host = '$hostName' AND simulation = '$scenName'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			
			while (@vlans = $query->fetchrow_array()) {
				$vlan_command = $vlan_command . "vconfig rem $vlans[1].$vlans[0]\n";
			}
			$query->finish();
			$vlan_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip '$vlan_command'";
			&daemonize($vlan_command, "/tmp/$hostName"."_log");
		}	
	}
	$dbh->disconnect;	
}

	###########################################################
	# Subroutine to execute destroy mode in cluster
	###########################################################
sub destroyScenario {
	my $dbh;
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	my $host_ip;
	my $hostName;

	my $scenario;
	foreach $physical_host (@cluster_hosts) {
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		my $vlan_command;
		$host_ip = $physical_host->ipAddress;			
		$hostName = $physical_host->hostName;		
		
		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){
			my $query_string = "SELECT `host` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $host_of_vm = $query->fetchrow_array();
			unless ($hostName eq $host_of_vm){
				next;
			}
		}	
		
		# If vm specified with -M, do not switch simulation status to "destroying".
		my $simulation_status;
		if ($vm_name){
			$simulation_status = "running";
		}else{
			$simulation_status = "destroying";
		}
		
		my $query_string = "SELECT `local_simulation` FROM hosts WHERE status = '$simulation_status' AND host = '$hostName' AND simulation = '$scenName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_name = $query->fetchrow_array();
		$query->finish();
		$query_string = "SELECT `local_specification` FROM hosts WHERE status = '$simulation_status' AND host = '$hostName' AND simulation = '$scenName'";
		$query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_bin = $query->fetchrow_array();
		$query->finish();
		
		$scenario_name = "/tmp/$scenario_name".".xml";
		open(FILEHANDLE, ">$scenario_name") or die 'cannot open file';
		print FILEHANDLE "$scenario_bin";
		close (FILEHANDLE);
		
		my $scp_command = "scp -2 $scenario_name root\@$host_ip:/tmp/";
		&daemonize($scp_command, "/tmp/$hostName"."_log");

		my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $scenario_name\'";
		&daemonize($permissions_command, "/tmp/$hostName"."_log");


				
		print "\n  **** Stopping simulation and network restoring in $hostName ****\n";
#VNX		my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnumlparser.pl -u root -v -d $scenario_name'";
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx -v -d -f $scenario_name " . $option_M . "'";
		&daemonize($ssh_command, "/tmp/$hostName"."_log");	
		
		
		unless ($vm_name){
			#Clean vlans
			$query_string = "SELECT `number`, `external_if` FROM vlans WHERE host = '$hostName' AND simulation = '$scenName'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			
			while (@vlans = $query->fetchrow_array()) {
				$vlan_command = $vlan_command . "vconfig rem $vlans[1].$vlans[0]\n";
			}
			$query->finish();
			$vlan_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip '$vlan_command'";
			&daemonize($vlan_command, "/tmp/$hostName"."_log");
		}	
	}
	$dbh->disconnect;	
}

	###########################################################
	# Subroutine to clean simulation from DB
	###########################################################
sub cleanDB {
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
		
	my $query_string = "DELETE FROM hosts WHERE simulation = '$scenName'";
	my $query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "DELETE FROM nets WHERE simulation = '$scenName'";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "DELETE FROM simulations WHERE name = '$scenName'";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "DELETE FROM vlans WHERE simulation = '$scenName'";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "DELETE FROM vms WHERE simulation = '$scenName'";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$dbh->disconnect;
}

	###########################################################
	# Subroutine to clean /tmp files
	###########################################################
sub deleteTMP {
	my $host_ip;
	my $hostName;
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	foreach $physical_host (@cluster_hosts) {
		$host_ip = $physical_host->ipAddress;
		$hostName = $physical_host->hostName;
		print "\n  **** Cleaning $hostName tmp directory ****\n";
		if (!($conf_plugin_file eq undef)){
			my $rm_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'rm -rf /tmp/$scenName"."_$hostName.xml /tmp/conf.tgz /tmp/$conf_plugin_file'";
			&daemonize($rm_command, "/tmp/$hostName"."_log");
		}else {
			my $rm_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'rm -rf /tmp/$scenName"."_$hostName.xml /tmp/conf.tgz'";
			# DFC comentado temporalmente...  &daemonize($rm_command, "/tmp/$hostName"."_log");
		}
	}			
}

	###########################################################
	# Subroutine to create tgz file with configuration of VMs
	 ###########################################################
sub getConfiguration {
	print "*** getConfiguration\n";
	
	my $basedir = "";
	eval {
		$basedir = $globalNode->getElementsByTagName("global")->item(0)->getElementsByTagName("vm_defaults")->item(0)->getElementsByTagName("basedir")->item(0)->getFirstChild->getData;
	};
	my @directories_list;
	my @exec_list;
	my $currentVMList = $globalNode->getElementsByTagName("vm");


	my $currentVMListLength = $currentVMList->getLength;
	for (my $n=0; $n<$currentVMListLength; $n++){
		
			my $currentVM=$currentVMList->item($n);
			my $nameOfVM=$currentVM->getAttribute("name");	
			my $filetreeList = $currentVM->getElementsByTagName("filetree");
			my $filetreeListLength = $filetreeList->getLength;
			for (my $m=0; $m<$filetreeListLength; $m++){
			   my $filetree = $filetreeList->item($m)->getFirstChild->getData;
			   print "*** getConfiguration: added $filetree\n";
			   push(@directories_list, $filetree);
			}
			
			#JSF añadido para tags <exec>
			my $execList = $currentVM->getElementsByTagName("exec");
			my $execListLength = $execList->getLength;
			for (my $m=0; $m<$execListLength; $m++){
			   my $exec = $execList->item($m)->getFirstChild->getData;
			   print "*** getConfiguration: added $exec\n";
			   push(@exec_list, $exec);
			}
		
	}
	
	# Look for configuration files defined for dynamips vms
	my $extConfFile = $dh->get_default_dynamips();
	# If the extended config file is defined, look for <conf> tags inside
	if ($extConfFile ne '0'){
		$extConfFile = &get_abs_path ($extConfFile);
		print "** extConfFile=$extConfFile\n";
		my $parser    = new XML::DOM::Parser;
		my $dom       = $parser->parsefile($extConfFile);
		my $conf_list = $dom->getElementsByTagName("conf");
   		for ( my $i = 0; $i < $conf_list->getLength; $i++) {
      		my $confi = $conf_list->item($i)->getFirstChild->getData;
			print "*** adding dynamips conf file=$confi\n";
			push(@directories_list, $confi);		
	 	}
	}
	
	if (!($basedir eq "")) {
		chdir $basedir;
	}
#	if (!($directories_list[0] eq undef)){
	if (@directories_list){
		my $tgz_name = "/tmp/conf.tgz"; 
		my $tgz_command = "tar czfv $tgz_name @directories_list";
		system ($tgz_command);
		$configuration = 1;	
	}
	#JSF añadido para tags <exec>
	elsif (@exec_list){
		$configuration = 2;
	}

# JSF: (corregido) por algún motivo solo se permite la ejecucion de comandos ($configuration = 1) si hay un tag filetree
# debería permitirse también si hay algún exec (?). Añadiendo la linea de debajo (es mia) se puede ejecutar ahora mismo:
# $configuration = 1;	
}

	###########################################################
	# Subroutine to copy VMs execution mode configuration to cluster machines
	###########################################################
sub sendConfiguration {
	if ($configuration == 1){
		print "\n\n  **** Sending configuration to cluster hosts ****\n\n";
		foreach $physical_host (@cluster_hosts) {		
			my $hostname = $physical_host->hostName;
			my $hostIP = $physical_host->ipAddress;
			my $tgz_name = "/tmp/conf.tgz";
			my $scp_command = "scp -2 $tgz_name root\@$hostIP:/tmp/";	
			system($scp_command);
			my $tgz_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$hostIP \'tar xzf $tgz_name -C /tmp'";
			&daemonize($tgz_command, "/tmp/$hostname"."_log");
		}
	}
	my $plugin;
	my $conf_plugin;
	eval {
		$plugin = $globalNode->getElementsByTagName("global")->item(0)->getElementsByTagName("extension")->item(0)->getAttribute("plugin");
		$conf_plugin = $globalNode->getElementsByTagName("global")->item(0)->getElementsByTagName("extension")->item(0)->getAttribute("conf");
	};
	
	# código de sendDynConfiguration
	if ($dynamips_ext_path ne ""){
		print "\n\n  **** Sending dynamips configuration file to cluster hosts ****\n\n";
		foreach $physical_host (@cluster_hosts) {
			my $hostname = $physical_host->hostName;
			#my $currentScenario = $scenarioHash{$hostname};
			#&para("$currentScenario");
			#my $filename = $currentScenario->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
			my $hostIP = $physical_host->ipAddress;
			my $dynamips_user_path = &get_abs_path ( $dom_tree->getElementsByTagName("dynamips_ext")->item(0)->getFirstChild->getData );
			print "** dynamips_user_path=$dynamips_user_path\n";
			#my $scp_command = "scp -2 $dynamips_user_path root\@$hostIP:$dynamips_ext_path".$filename."/dynamips-dn.xml";
			my $scp_command = "scp -2 $dynamips_user_path root\@$hostIP:/tmp/dynamips-dn.xml";
			system($scp_command);
		}
	}


	if ((!($plugin eq undef)) && (!($conf_plugin eq undef))){
		print "\n\n  **** Sending configuration to cluster hosts ****\n\n";
		
		my $path;
		my @scenario_name_split = split("/",$vnx_scenario);
		my $scenario_name_split_size = @scenario_name_split;
		
		for (my $i=1; $i<($scenario_name_split_size -1); $i++){
			my $part = $scenario_name_split[$i];
			$path = "$path" .  "/$part";
		}
		
		if ($path eq undef){
			$conf_plugin_file = $conf_plugin;
		} else{
			$conf_plugin_file = "$path" . "/" . "$conf_plugin";
		}
	
		foreach $physical_host (@cluster_hosts) {
			my $hostname = $physical_host->hostName;
			my $hostIP = $physical_host->ipAddress;
			my $scp_command = "scp -2 $conf_plugin_file root\@$hostIP:/tmp";
			system($scp_command);
		}
		$configuration = 1;
	}
}

	###########################################################
	# Subroutine to copy dynamips configuration file to cluster machines
	###########################################################
#TODO: código copiado a sub sendConfiguration, borrar esta subrutina.
sub sendDynConfiguration {
	if ($dynamips_ext_path ne ""){
		print "\n\n  **** Sending dynamips configuration file to cluster hosts ****\n\n";
		foreach $physical_host (@cluster_hosts) {
			my $hostname = $physical_host->hostName;
			my $currentScenario = $scenarioHash{$hostname};
			my $filename = $currentScenario->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
			my $hostIP = $physical_host->ipAddress;
			my $dynamips_user_path = $dom_tree->getElementsByTagName("dynamips_ext")->item(0)->getFirstChild->getData;
			
			#my $scp_command = "scp -2 $dynamips_user_path root\@$hostIP:$dynamips_ext_path".$filename."/dynamips-dn.xml";
			my $scp_command = "scp -2 $dynamips_user_path root\@$hostIP:/tmp/dynamips-dn.xml";
			system($scp_command);
		}
	}
}



	###########################################################
	# Subroutine to execute execution mode in cluster
	###########################################################
sub executeConfiguration {
	
	if (!($configuration)){
		die ("This scenario doesn't support mode -x")
	}
	my $execution_mode = shift;
	my $dbh;
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	foreach $physical_host (@cluster_hosts) {	
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		my $hostName = $physical_host->hostName;
		my $hostIP = $physical_host->ipAddress;
		
		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){
			my $query_string = "SELECT `host` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $host_of_vm = $query->fetchrow_array();
			unless ($hostName eq $host_of_vm){
				next;
			}
		}
		
		my $query_string = "SELECT `local_specification` FROM hosts WHERE status = 'running' AND host = '$hostName' AND simulation = '$scenName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_bin = $query->fetchrow_array();

		print $scenario_bin . "\n";

		$query->finish();
					
		$query_string = "SELECT `local_simulation` FROM hosts WHERE status = 'running' AND host = '$hostName' AND simulation = '$scenName'";
		$query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_name = $query->fetchrow_array();
print "*****SELECT `local_simulation` FROM hosts WHERE status = 'running' AND host = '$hostName' AND simulation = '$scenName'\n";
print "scenario name:'$scenario_name'\n";

		$query->finish();
	
		$scenario_name = "/tmp/$scenario_name".".xml";
		open(FILEHANDLE, ">$scenario_name") or die 'cannot open file';
		print FILEHANDLE "$scenario_bin";
		close (FILEHANDLE);
		
		my $scp_command = "scp -2 $scenario_name root\@$hostIP:/tmp/";
		&daemonize($scp_command, "/tmp/$hostName"."_log");
		my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$hostIP \'chmod -R 777 $scenario_name\'";	
		&daemonize($permissions_command, "/tmp/$hostName"."_log"); 		
#VNX	my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$hostIP \'vnumlparser.pl -u root -v -x $execution_mode\@$scenario_name'";
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$hostIP \'vnx -f $scenario_name -v -x $execution_mode " . $option_M . "'"; 
		&daemonize($execution_command, "/tmp/$hostName"."_log");
	}
	$dbh->disconnect;
}

	###########################################################
	# Subroutine to create tunnels to operate remote VMs from a local port
	###########################################################
sub tunnelize {	
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	my $localport = 64000;

	foreach $vm_name (keys (%allocation)) {
		my $hostname = $allocation{$vm_name};
		
		# continue only if type of vm is "uml"
		my $query_string = "SELECT `type` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $type_of_vm = $query->fetchrow_array();
		unless($type_of_vm eq "uml"){
			next;
		}	
		
		while (1){
			my $query_string = "SELECT `ssh_port` FROM vms WHERE ssh_port='$localport'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $contenido = $query->fetchrow_array();
			if ($contenido eq undef){
				last;
			}
			$query->finish();
			$localport++;
			
		}
		system("ssh -2 -q -f -N -o \"StrictHostKeyChecking no\" -L $localport:$vm_name:22 $hostname");

	
		my $query_string = "UPDATE vms SET ssh_port = '$localport' WHERE name='$vm_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();	
		
		if ($localport > 65535) {
			die ("Not enough ports available but the simulation is running... you can't access to VMs using tunnels.");
		}	
	}
	
	$query_string = "SELECT `name`,`host`,`ssh_port` FROM vms WHERE simulation = '$scenName' ORDER BY `name`";
	$query = $dbh->prepare($query_string);
	$query->execute();
			
	while (@ports = $query->fetchrow_array()) {
		print ("\tTo access VM $ports[0] at $ports[1] use local port $ports[2]\n");
	
	}
	$query->finish();
	print "\n\tUse command ssh -2 root\@localhost -p <port> to access VMs\n";
	print "\tOr ediv_console.pl console <simulation_name> <vm_name>\n";
	print "\tWhere <port> is a port number of the previous list\n";
	print "\tThe port list can be found running ediv_console.pl info\n";
	$dbh->disconnect;
}

	###########################################################
	# Subroutine to remove tunnels
	###########################################################
sub untunnelize {
	print "\n  **** Cleaning tunnels to access remote VMs ****\n\n";
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	
	$query_string = "SELECT `ssh_port` FROM vms WHERE simulation = '$scenName' ORDER BY `ssh_port`";
	$query = $dbh->prepare($query_string);
	$query->execute();
			
	while (@ports = $query->fetchrow_array()) {
		my $kill_command = "kill -9 `ps auxw | grep -i \"ssh -2 -q -f -N\" | grep -i $ports[0] | awk '{print \$2}'`";
		&daemonize($kill_command, "/dev/null");
	}
	
	$query->finish();
	$dbh->disconnect();
}

	###########################################################
	# Subroutine to launch background operations
	###########################################################
sub daemonize {	
	print("\n");
    my $command = shift;
    my $output = shift;
    print("Backgrounded command:\n$command\n------> Log can be found at: $output\n");
    defined(my $pid = fork)			or die "Can't fork: $!";
    return if $pid;
    chdir '/tmp'					or die "Can't chdir to /: $!";
    open STDIN, '/dev/null'			or die "Can't read /dev/null: $!";
    open STDOUT, ">>$output"		or die "Can't write to $output: $!";
    open STDERR, ">>$output"		or die "Can't write to $output: $!";
    setsid							or die "Can't start a new session: $!";
    system("$command") == 0			or print "ERROR: Could not execute $command!";
    exit();
}

	###########################################################
	# Subroutine to execute execution mode in cluster
	###########################################################
sub processMode {
	
	#my $execution_mode = shift;
	my $dbh;
#	my $scenName=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	foreach $physical_host (@cluster_hosts) {	
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		my $hostName = $physical_host->hostName;
		my $hostIP = $physical_host->ipAddress;
		
		# If vm specified with -M is not running in current host, check the next one.

		if ($vm_name){
			my $query_string = "SELECT `host` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $host_of_vm = $query->fetchrow_array();

			unless ($hostName eq $host_of_vm){
				next;
			}
		}

		
		my $query_string = "SELECT `local_specification` FROM hosts WHERE status = 'running' AND host = '$hostName' AND simulation = '$scenName'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_bin = $query->fetchrow_array();

		$query->finish();
					
		$query_string = "SELECT `local_simulation` FROM hosts WHERE status = 'running' AND host = '$hostName' AND simulation = '$scenName'";
		$query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_name = $query->fetchrow_array();

		$query->finish();
	
		$scenario_name = "/tmp/$scenario_name".".xml";
		open(FILEHANDLE, ">$scenario_name") or die 'cannot open file';
		print FILEHANDLE "$scenario_bin";
		close (FILEHANDLE);
	
		my $scp_command = "scp -2 $scenario_name root\@$hostIP:/tmp/";
		&daemonize($scp_command, "/tmp/$hostname"."_log");
		my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$hostIP \'chmod -R 777 $scenario_name\'";	
		&daemonize($permissions_command, "/tmp/$hostname"."_log"); 		
#VNX	my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$hostIP \'vnumlparser.pl -u root -v -x $execution_mode\@$scenario_name'";
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$hostIP \'vnx -f $scenario_name -v $mode " . $option_M . "'"; 
		&daemonize($execution_command, "/tmp/$hostname"."_log");
	}
	$dbh->disconnect;
}

# Subroutines end
###########################################################

sub para {
	my $mensaje = shift;
	my $var = shift;
	print "************* $mensaje *************\n";
	if (defined $var){
	   print $var . "\n";	
	}
	<STDIN>;
}

# 
# checkVNXScenario: checks scenario file semantics using the same code used in VNX
#
sub initAndCheckVNXScenario {
	
	my $input_file = shift;
	
	print "** scenario=$input_file\n";

   	my $vnx_dir = &do_path_expansion($DEFAULT_VNX_DIR);
   	my $tmp_dir = "/tmp";
   	my $uid = $>;
   
	my $exemode = $EXE_NORMAL;
	# Build the VNX::BinariesData object
	my $bd = new VNX::BinariesData($exemode);
	
   	# 7. To check version number
	# Load XML file content
	open INPUTFILE, "$input_file";
   	my @input_file_array = <INPUTFILE>;
   	my $input_file_string = join("",@input_file_array);
   	close INPUTFILE; 
   	
   	if ($input_file_string =~ /<version>\s*(\d\.\d+)(\.\d+)?\s*<\/version>/) {
      	my $version_in_file = $1;
      	$version =~ /^(\d\.\d+)/;
      	my $version_in_parser = $1;
      	unless ($version_in_file eq $version_in_parser) {
      		&ediv_die("mayor version numbers of source file ($version_in_file) and parser ($version_in_parser) do not match");
			exit;
      	}
   	} else {
      	&ediv_die("can not find VNX version in $input_file");
   	}
   	
  	# 8. To check XML file existance and readability and
   	# validate it against its XSD language definition
	my $error;
	$error = validate_xml ($input_file);
	if ( $error ) {
        &vnx_die ("XML file ($input_file) validation failed:\n$error\n");
	}

   	# Create DOM tree
	my $parser = new XML::DOM::Parser;
    my $doc = $parser->parsefile($input_file);   	
   
	# Build the VNX::Execution object
	$execution = new VNX::Execution($vnx_dir,$exemode,"host> ",'',$uid);

   	# Calculate the directory where the input_file lives
   	my $xml_dir = (fileparse(abs_path($input_file)))[1];

	# Build the VNX::DataHandler object
   	$dh = new VNX::DataHandler($execution,$doc,'','','',$xml_dir,$input_file);
   	#$dh->set_boot_timeout($boot_timeout);
   	$dh->set_vnx_dir($vnx_dir);
   	$dh->set_tmp_dir($tmp_dir);
   	#$dh->enable_ipv6($enable_6);
   	#$dh->enable_ipv4($enable_4);   

   	# Semantic check (in addition to validation)
   	if (my $err_msg = &check_doc($bd->get_binaries_path_ref,$execution->get_uid)) {
      	&ediv_die ("$err_msg\n");
   	}

   	# Validate extended XML configuration files
	# Dynamips
	my $dmipsConfFile = $dh->get_default_dynamips();
	if ($dmipsConfFile ne "0"){
		$dmipsConfFile = get_abs_path ($dmipsConfFile);
		my $error = validate_xml ($dmipsConfFile);
		if ( $error ) {
	        &ediv_die ("Dynamips XML configuration file ($dmipsConfFile) validation failed:\n$error\n");
		}
	}
	
}

# ediv_die
#
# Wrapper of die Perl function. It is based on the old smartdie, now moved to the
# VNX::Execution class in Execution.pm. Note that, this funcion does not release
# the LOCK file (as smartdie does): it is intented to be used in the early stages
# of vnumlparser.pl execution, when the VNX::Execution object has not been construsted.
#
sub ediv_die {
   my $mess = shift;
   printf "%s (%s): %s \n", (caller(1))[3], (caller(0))[2], $mess;
   exit 1;
}
