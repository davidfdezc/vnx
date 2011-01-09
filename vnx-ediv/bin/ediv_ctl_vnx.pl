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

use XML::DOM;          					# XML management library
use File::Basename;    					# File management library
use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
use POSIX qw(setsid setuid setgid);


use Socket;								# To resolve hostnames to IPs

use DBI;								# Module to handle databases

use EDIV::cluster_host;                 # Cluster Host class 
use EDIV::static;  						# Module that process static assignment 

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
my $vm_name; # máquina especificada con tag -M
	
	# Scenario
my $vnuml_scenario;						# VNUML scenario to split
my %scenarioHash; 						# Scenarios. Every scenario belongs to a host machine
										# Key -> name of physical hostname, Value -> XML Scenario							
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

###########################################################
# Main	
###########################################################

	# Argument handling
	&parseArguments;	
	
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
	&parseScenario;

# JSF: metido en parse scenario, si funciona borrar
#	#if dynamips_ext node is present, update path
#    $dynamips_ext_path = "";
#    my $dynamips_extTagList=$dom_tree->getElementsByTagName("dynamips_ext");
#    my $numdynamips_ext = $dynamips_extTagList->getLength;
#    if ($numdynamips_ext == 1) {
#		    my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
#		    $dynamips_ext_path = "/root/.vnx/scenarios/";
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
	
	#TODO: código copiado a sub sendConfiguration, si funciona borrar esta subrutina.	
	# Send dynamips configuration to each host.
	#&sendDynConfiguration;
	
	print "\n\n  **** Sending scenario to cluster hosts and executing it ****\n\n";
	# Send scenario files to the hosts and run them with VNUML (-t option)
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
			$vnuml_scenario = $ARGV[$vnunl_scenario_arg];
			open(FILEHANDLE, $vnuml_scenario) or die  "The scenario file $vnuml_scenario doesn't exist... Aborting";
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
	}
	if ($mode eq undef){
		die ("You didn't specify a valid execution mode (-t, -x, -P, -d)... Aborting");
	}
	if ($vnuml_scenario eq undef){
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
	$dom_tree = $parser->parsefile($vnuml_scenario);
	$globalNode = $dom_tree->getElementsByTagName("vnx")->item(0);
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
	if ($mode eq '-t' | $mode eq '--create') {
		
			# Checking if the simulation already exists
		my $query_string = "SELECT `name` FROM simulations WHERE name='$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();

		if ( !($vm_name) && !($contenido eq undef)) {
			die ("The simulation $simulation_name was already created... Aborting");
		} 
	
			# Creating simulation in the database
		$query_string = "INSERT INTO simulations (name) VALUES ('$simulation_name')";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
	} elsif($mode eq '-x' | $mode eq '--exe' | $mode eq '--execute') {
		
			# Checking if the simulation is running
		my $query_string = "SELECT `simulation` FROM hosts WHERE status = 'running' AND simulation = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();
		if ($contenido eq undef) {
			die ("The simulation $simulation_name wasn't running... Aborting");
		} 
		$query->finish();
	} elsif($mode eq '-P' | $mode eq '--destroy') {
		
			# Checking if the simulation is running
		my $query_string = "SELECT `simulation` FROM hosts WHERE status = 'running' AND simulation = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();
		if ($contenido eq undef) {
			die ("The simulation $simulation_name wasn't running... Aborting");
		}
		$query->finish();
		# If no -M option, mark simulation as "purging"
		unless ($vm_name){
			$query_string = "UPDATE hosts SET status = 'purging' WHERE status = 'running' AND simulation = '$simulation_name'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			$query->finish();
		}
	} elsif($mode eq '-d' | $mode eq '--shutdown') {
		
			# Checking if the simulation is running
		my $query_string = "SELECT `simulation` FROM hosts WHERE status = 'running' AND simulation = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();
		if ($contenido eq undef) {
			die ("The simulation $simulation_name wasn't running... Aborting");
		}
		# If no -M option, mark simulation as "destroying"
		unless ($vm_name){
			$query->finish();
			$query_string = "UPDATE hosts SET status = 'destroying' WHERE status = 'running' AND simulation = '$simulation_name'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			$query->finish();
		}
		
	} elsif($mode eq '--define' | $mode eq '--undefine' | $mode eq '--start' | $mode eq '--save' | 
		$mode eq '--restore' | $mode eq '--suspend' | $mode eq '--resume' | $mode eq '--reboot') {
		# quizá el define se podría usar sin la simulacion creada ya, sobraria aqui	
		# Checking if the simulation is running
		my $query_string = "SELECT `simulation` FROM hosts WHERE status = 'running' AND simulation = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();
		if ($contenido eq undef) {
			die ("The simulation $simulation_name wasn't running... Aborting");
		}
		$query->finish();
	}
	 

	#if dynamips_ext node is present, update path
	$dynamips_ext_path = "";
	my $dynamips_extTagList=$dom_tree->getElementsByTagName("dynamips_ext");
	my $numdynamips_ext = $dynamips_extTagList->getLength;
	if ($numdynamips_ext == 1) {
		my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
		$dynamips_ext_path = "/root/.vnx/scenarios/";
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
	# We create an vnuml node on every scenario and start adding child nodes to it.
	###########################################################
sub fillScenarioArray {
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);	
	my $numberOfHosts = @cluster_hosts;

	my $nuevoNodo= $dom_tree->cloneNode("true");

    my $nuevoVNUML=$nuevoNodo->getElementsByTagName("vnx")->item(0);
    for my $kid ($nuevoVNUML->getChildNodes){
		$nuevoVNUML->removeChild($kid); 
	}

	my $global= $dom_tree->getElementsByTagName("global")->item(0)->cloneNode("true");

#	$global->setOwnerDocument($nuevoNodo);
	$nuevoVNUML->appendChild($global);




	my $data=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
	for ($i=0; $i<$numberOfHosts;$i++){
		my $scenarioNode=$nuevoNodo->cloneNode("true");
		my $currentHostName=$cluster_hosts[$i]->hostName;
		

		my $newdata=$data."_".$currentHostName;
		$scenarioNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->setData($newdata);
		
		#if dynamips_ext node is present, update path
		my $dynamips_extTagList=$scenarioNode->getElementsByTagName("dynamips_ext");
    	my $numdynamips_ext = $dynamips_extTagList->getLength;
    	if ($numdynamips_ext == 1) {	
    		my $virtualmList=$globalNode->getElementsByTagName("vm");
			my $longitud = $virtualmList->getLength;
			my $keep_dynamips_in_scenario = 0;
			for (my $m=0; $m<$longitud; $m++){
				my $virtualm=$virtualmList->item($m);
				my $virtualm_name = $virtualm->getAttribute("name");
				my $host_name = $allocation{$virtualm_name};
				if ($host_name eq $currentHostName){
					my $virtualm_type = $virtualm->getAttribute("type");
					if ($virtualm_type eq "dynamips"){
						$keep_dynamips_in_scenario = 1;
					}
				}	
			}
    		if ($keep_dynamips_in_scenario == 1){
    			#my $current_host_dynamips_path = $dynamips_ext_path . $newdata ."/dynamips-dn.xml";
    			#print $dynamips_extTagList->item(0)->getFirstChild->getData . "\n";
    			#print "current_host_dynamips_path=$current_host_dynamips_path\n";<STDIN>;
    			# las tres lineas de arriba no funcionan, ya que no puedo meter el xml en los
    			# directorios del escenario antes de crearlo, hay que usar un /tmp:
    			my $current_host_dynamips_path = "/tmp/dynamips-dn.xml";
    			$dynamips_extTagList->item(0)->getFirstChild->setData($current_host_dynamips_path);
    			print $dynamips_extTagList->item(0)->getFirstChild->getData . "\n";
    		}else{
#    			my $dynamips_extTag = $dynamips_extTagList->item(0);
#    			$parentnode = $dynamips_extTag->parentNode;
#    			$parentnode->removeChild($dynamips_extTag);
				
				foreach my $node ( $scenarioNode->getElementsByTagName("dynamips_ext") ) {
					$scenarioNode->getElementsByTagName("global")->item(0)->removeChild($node);
				}
    			
    		}	
    			




#foreach my $node ( $doc->getChildNodes() ) {
#if ( $node->getNodeType() == ELEMENT_NODE ) {
#remove_comments($node);
#}
#elsif ( $node->getNodeType() == COMMENT_NODE ) {
#$doc->removeChild($node);

#    			for my $kid ($scenarioNode->getChildNodes){
#    				
#					if ($kid->getName eq "dynamips_ext"){
#						$nuevoVNUML->removeChild($kid); 
#					}
#				}
    			
#    			$scenarioNode->removeChild($scenarioNode->getElementsByTagName("dynamips_ext")->item(0));
#    		}
    	}	
		
		my $basedir_data = "/tmp/";
		eval{
			$scenarioNode->getElementsByTagName("global")->item(0)->getElementsByTagName("vm_defaults")->item(0)->getElementsByTagName("basedir")->item(0)->getFirstChild->setData($basedir_data);
		};		
		$scenarioHash{$currentHostName} = $scenarioNode;	
		# Save data into DB
		
		my $query_string = "INSERT INTO hosts (simulation,local_simulation,host,status) VALUES ('$data','$newdata','$currentHostName','creating')";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
	}
	$dbh->disconnect;
}

	###########################################################
	# Split the original scenario xml file into several smaller files for each host physical machine.
	###########################################################
sub splitIntoFiles {
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		# We explore the vms on the node and call vmPlacer to place them on the scenarios	
	my $virtualmList=$globalNode->getElementsByTagName("vm");


	my $longitud = $virtualmList->getLength;
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;

		# Add VMs to corresponding subscenario specification file
	for (my $m=0; $m<$longitud; $m++){
		
		my $virtualm=$virtualmList->item($m);
		my $virtualm_name = $virtualm->getAttribute("name");
		my $host_name = $allocation{$virtualm_name};

		my $newVirtualM=$virtualm->cloneNode("true");
		$newVirtualM->setOwnerDocument($scenarioHash{$host_name});

		my $vnumlNode=$scenarioHash{$host_name}->getElementsByTagName("vnx")->item(0);
			
		$vnumlNode->setOwnerDocument($scenarioHash{$host_name});

		$vnumlNode->appendChild($newVirtualM);


		unless ($vm_name){
				# Creating virtual machines in the database

			my $query_string = "SELECT `name` FROM vms WHERE name='$virtualm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $contenido = $query->fetchrow_array();
			if ( !($contenido eq undef)) {
				&cleanDB;
				die ("The vm $virtualm_name was already created... Aborting");
			}
			$query->finish();
			$query_string = "INSERT INTO vms (name,simulation,host) VALUES ('$virtualm_name','$simulation_name','$host_name')";
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
		foreach $host_name (keys(%scenarioHash)) {
			
			my $currentScenario = $scenarioHash{$host_name};		
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
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
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
		$query_string = "INSERT INTO nets (name,simulation) VALUES ('$nameOfNet','$simulation_name')";
		$query = $dbh->prepare($query_string);
		$query->execute();	
		$query->finish();
		
			# For exploring each scenario on scenarioarray	
		my @net_host_list;
		foreach $host_name (keys(%scenarioHash)) {
			my $currentScenario = $scenarioHash{$host_name};
			my $currentScenario_nets = $currentScenario->getElementsByTagName("net");
			for (my $j=0; $j<$currentScenario_nets->getLength; $j++) {
				my $currentScenario_net = $currentScenario_nets->item($j);
				
				if ( ($currentScenario_net->getAttribute("name")) eq ($nameOfNet)) {
					push(@net_host_list, $host_name);
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
		foreach $host_name (keys(%scenarioHash)) {
			my $external;
			my $command_list;
			foreach $physical_host (@cluster_hosts) {
				if ($physical_host->hostName eq $host_name) {
					$external = $physical_host->ifName;
				}				
			}
			my $currentScenario = $scenarioHash{$host_name};
			for (my $k=0; defined($current_net->[$k]); $k++) {
				if ($current_net->[$k] eq $host_name) {
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
							
							$query_string = "INSERT INTO vlans (number,simulation,host,external_if) VALUES ('$net_vlan','$simulation_name','$host_name','$external')";
							$query = $dbh->prepare($query_string);
							$query->execute();
							$query->finish();
		
							my $vlan_command = "vconfig add $external $net_vlan\nifconfig $external.$net_vlan 0.0.0.0 up\n";
							$commands{$host_name} = $commands{$host_name}."$vlan_command";						
						}
					}
				}
			}
		}
	}
	
	# 3. Configure nets of cluster machines
	foreach $host_name (keys(%commands)){
		my $host_ip;
		foreach $physical_host (@cluster_hosts) {
			if ($physical_host->hostName eq $host_name) {
				$host_ip = $physical_host->ipAddress;
			}				
		}
		
		my $host_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip '$commands{$host_name}'";
		&daemonize($host_command, "/tmp/$host_name"."_log");
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
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
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
	
	foreach $host_name (keys(%scenarioHash)) {
		my $currentScenario = $scenarioHash{$host_name};
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
			if ($allocation{$virtual_machine} eq $host_name) {
				$MgnetOffset += 4; # Uses mask /30 with a point-to-point management network
			}				
		}
			# If management network doesn't use host_mapping, activate it
		my $host_mapping_property = $currentScenario->getElementsByTagName("host_mapping")->item(0);
		if (!($host_mapping_property)) {
			$host_mapping_property = $currentScenario->createElement("host_mapping");
			$currentScenario->getElementsByTagName("vm_mgmt")->item(0)->appendChild($host_mapping_property);
		}
		
		#my $net_offset = $currentScenario->getElementsByTagName("vm_mgmt")->item(0);
		#$net_offset->setAttribute("offset", $MgnetOffset);
		#$net_offset->setAttribute("mask","16");
		
#		foreach $virtual_machine (keys(%allocation)) {
#			if ($allocation{$virtual_machine} eq $host_name) {
#				$MgnetOffset += 4; # Uses mask /30 with a point-to-point management network
#			}				
#		}	
	}
	$query_string = "UPDATE simulations SET automac_offset = '$VmOffset' WHERE name='$simulation_name'";
	$query = $dbh->prepare($query_string);
	$query->execute();	
	$query->finish();
		
	$query_string = "UPDATE simulations SET mgnet_offset = '$MgnetOffset' WHERE name='$simulation_name'";
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
	foreach $host_name (keys(%scenarioHash)) {
	
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		my $currentScenario = $scenarioHash{$host_name};
		foreach $physical_host (@cluster_hosts) {
			if ($physical_host->hostName eq $host_name) {
				$host_ip = $physical_host->ipAddress;
			}				
		}
	
		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){	
			my $query_string = "SELECT `host` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $host_of_vm = $query->fetchrow_array();
			unless ($host_name eq $host_of_vm){
				next;
			}
		}
		
		my $filename = $currentScenario->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
		my $simulation_name = $filename;
		$filename = "/tmp/$filename".".xml";
		$currentScenario->printToFile("$filename");
		
			# Save the local specification in DB	
		open(FILEHANDLE, $filename) or die  'cannot open file!';
		my $file_data;
		read (FILEHANDLE,$file_data, -s FILEHANDLE);

		my $query_string = "UPDATE hosts SET local_specification = '$file_data' WHERE local_simulation='$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		close (FILEHANDLE);
		
		my $scp_command = "scp -2 $filename root\@$host_ip:/tmp/";
		&daemonize($scp_command, "/tmp/$host_name"."_log");
		my $permissions_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip \'chmod -R 777 $filename\'";
		&daemonize($permissions_command, "/tmp/$host_name"."_log"); 
#VNX		my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnumlparser.pl -Z -u root -v -t $filename -o /dev/null\'";
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnx -f $filename -u root -v -t -o /dev/null\ " . $option_M . "'";
		&daemonize($ssh_command, "/tmp/$host_name"."_log");		
	}
	$dbh->disconnect;
}

	###########################################################
	# Subroutine to check propper finishing of launching mode (-t)
	# Uses /root/.vnuml/simulations/<simulacion>/vms/<vm>/status file
	###########################################################
sub checkFinish {
	my $dbh;
	my $host_ip;
	my $host_name;
	my $scenario;
	my $file;
	foreach $physical_host(@cluster_hosts){
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		$host_ip = $physical_host->ipAddress;
		$host_name = $physical_host->hostName;
		
		my $query_string = "SELECT `local_simulation` FROM hosts WHERE status = 'creating' AND host = '$host_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$scenario = $query->fetchrow_array();
		$query->finish();
		chomp($scenario);
		$dbh->disconnect;
		
		open STDERR, "/dev/null";
		foreach $vms (keys (%allocation)){
			if ($allocation{$vms} eq $host_name){
				print ("Checking $vms status\n");
				my $status_command = "ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'cat /root/.vnx/scenarios/$scenario/vms/$vms/status'";
				my $status = `$status_command`;
				chomp ($status);

				while (!($status eq "running")) {
					print ("\t $vms still booting, waiting...\n");
					$status_command = "ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'cat /root/.vnx/scenarios/$scenario/vms/$vms/status'";
					$status = `$status_command`;
					chomp ($status);
					sleep(5);
				}
				print ("\t $vms running\n");
			}
		}
		close STDERR;
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		$query_string = "UPDATE hosts SET status = 'running' WHERE status = 'creating' AND host = '$host_name'";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		$dbh->disconnect;
	}
}

	###########################################################
	# Subroutine to execute purge mode in cluster
	###########################################################
sub purgeScenario {
	my $dbh;
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	my $host_ip;
	my $host_name;

	my $scenario;
	foreach $physical_host (@cluster_hosts) {
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		my $vlan_command;
		$host_ip = $physical_host->ipAddress;			
		$host_name = $physical_host->hostName;


		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){
			my $query_string = "SELECT `host` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $host_of_vm = $query->fetchrow_array();

			unless ($host_name eq $host_of_vm){
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

		my $query_string = "SELECT `local_simulation` FROM hosts WHERE status = '$simulation_status' AND host = '$host_name' AND simulation = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_name = $query->fetchrow_array();
		$query->finish();

		my $query_string = "SELECT `local_specification` FROM hosts WHERE status = '$simulation_status' AND host = '$host_name' AND simulation = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_bin = $query->fetchrow_array();
		$query->finish();
		
		$scenario_name = "/tmp/$scenario_name".".xml";
		open(FILEHANDLE, ">$scenario_name") or die 'cannot open file';
		print FILEHANDLE "$scenario_bin";
		close (FILEHANDLE);
	
		my $scp_command = "scp -2 $scenario_name root\@$host_ip:/tmp/";
		&daemonize($scp_command, "/tmp/$host_name"."_log");

		my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $scenario_name\'";
		&daemonize($permissions_command, "/tmp/$host_name"."_log");
		
		print "\n  **** Stopping simulation and network restoring in $host_name ****\n";
#VNX		my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnumlparser.pl -u root -v -P $scenario_name'";
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx -u root -v -P -f $scenario_name " . $option_M . "'";
		&daemonize($ssh_command, "/tmp/$host_name"."_log");	


		unless ($vm_name){
			#Clean vlans
			$query_string = "SELECT `number`, `external_if` FROM vlans WHERE host = '$host_name' AND simulation = '$simulation_name'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			
			while (@vlans = $query->fetchrow_array()) {
				$vlan_command = $vlan_command . "vconfig rem $vlans[1].$vlans[0]\n";
			}
			$query->finish();
			$vlan_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip '$vlan_command'";
			&daemonize($vlan_command, "/tmp/$host_name"."_log");
		}	
	}
	$dbh->disconnect;	
}

	###########################################################
	# Subroutine to execute destroy mode in cluster
	###########################################################
sub destroyScenario {
	my $dbh;
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	my $host_ip;
	my $host_name;

	my $scenario;
	foreach $physical_host (@cluster_hosts) {
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		my $vlan_command;
		$host_ip = $physical_host->ipAddress;			
		$host_name = $physical_host->hostName;		
		
		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){
			my $query_string = "SELECT `host` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $host_of_vm = $query->fetchrow_array();
			unless ($host_name eq $host_of_vm){
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
		
		my $query_string = "SELECT `local_simulation` FROM hosts WHERE status = '$simulation_status' AND host = '$host_name' AND simulation = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_name = $query->fetchrow_array();
		$query->finish();
		my $query_string = "SELECT `local_specification` FROM hosts WHERE status = '$simulation_status' AND host = '$host_name' AND simulation = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_bin = $query->fetchrow_array();
		$query->finish();
		
		$scenario_name = "/tmp/$scenario_name".".xml";
		open(FILEHANDLE, ">$scenario_name") or die 'cannot open file';
		print FILEHANDLE "$scenario_bin";
		close (FILEHANDLE);
		
		my $scp_command = "scp -2 $scenario_name root\@$host_ip:/tmp/";
		&daemonize($scp_command, "/tmp/$host_name"."_log");

		my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $scenario_name\'";
		&daemonize($permissions_command, "/tmp/$host_name"."_log");


				
		print "\n  **** Stopping simulation and network restoring in $host_name ****\n";
#VNX		my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnumlparser.pl -u root -v -d $scenario_name'";
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx -u root -v -d -f $scenario_name " . $option_M . "'";
		&daemonize($ssh_command, "/tmp/$host_name"."_log");	
		
		
		unless ($vm_name){
			#Clean vlans
			$query_string = "SELECT `number`, `external_if` FROM vlans WHERE host = '$host_name' AND simulation = '$simulation_name'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			
			while (@vlans = $query->fetchrow_array()) {
				$vlan_command = $vlan_command . "vconfig rem $vlans[1].$vlans[0]\n";
			}
			$query->finish();
			$vlan_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip '$vlan_command'";
			&daemonize($vlan_command, "/tmp/$host_name"."_log");
		}	
	}
	$dbh->disconnect;	
}

	###########################################################
	# Subroutine to clean simulation from DB
	###########################################################
sub cleanDB {
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
		
	my $query_string = "DELETE FROM hosts WHERE simulation = '$simulation_name'";
	my $query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "DELETE FROM nets WHERE simulation = '$simulation_name'";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "DELETE FROM simulations WHERE name = '$simulation_name'";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "DELETE FROM vlans WHERE simulation = '$simulation_name'";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "DELETE FROM vms WHERE simulation = '$simulation_name'";
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
	my $host_name;
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	foreach $physical_host (@cluster_hosts) {
		$host_ip = $physical_host->ipAddress;
		$host_name = $physical_host->hostName;
		print "\n  **** Cleaning $host_name tmp directory ****\n";
		if (!($conf_plugin_file eq undef)){
			my $rm_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'rm -rf /tmp/$simulation_name"."_$host_name.xml /tmp/conf.tgz /tmp/$conf_plugin_file'";
			&daemonize($rm_command, "/tmp/$host_name"."_log");
		}else {
			my $rm_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'rm -rf /tmp/$simulation_name"."_$host_name.xml /tmp/conf.tgz'";
			&daemonize($rm_command, "/tmp/$host_name"."_log");
		}
	}			
}

	###########################################################
	# Subroutine to create tgz file with configuration of VMs
	 ###########################################################
sub getConfiguration {
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
			   push(@directories_list, $filetree);
			}
			
			#JSF añadido para tags <exec>
			my $execList = $currentVM->getElementsByTagName("exec");
			my $execListLength = $execList->getLength;
			for (my $m=0; $m<$execListLength; $m++){
			   my $exec = $execList->item($m)->getFirstChild->getData;
			   push(@exec_list, $exec);
			}
		
	}
	if (!($basedir eq "")) {
		chdir $basedir;
	}
#	if (!($directories_list[0] eq undef)){
	if (@directories_list){
		my $tgz_name = "/tmp/conf.tgz"; 
		my $tgz_command = "tar czf $tgz_name @directories_list";
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
			my $dynamips_user_path = $dom_tree->getElementsByTagName("dynamips_ext")->item(0)->getFirstChild->getData;
			
			#my $scp_command = "scp -2 $dynamips_user_path root\@$hostIP:$dynamips_ext_path".$filename."/dynamips-dn.xml";
			my $scp_command = "scp -2 $dynamips_user_path root\@$hostIP:/tmp/dynamips-dn.xml";
			system($scp_command);
		}
	}


	if ((!($plugin eq undef)) && (!($conf_plugin eq undef))){
		print "\n\n  **** Sending configuration to cluster hosts ****\n\n";
		
		my $path;
		my @scenario_name_split = split("/",$vnuml_scenario);
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
#TODO: código copiado a sub sendConfiguration, si funciona borrar esta subrutina.
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
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	foreach $physical_host (@cluster_hosts) {	
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		my $host_name = $physical_host->hostName;
		my $hostIP = $physical_host->ipAddress;
		
		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){
			my $query_string = "SELECT `host` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $host_of_vm = $query->fetchrow_array();
			unless ($host_name eq $host_of_vm){
				next;
			}
		}
		
		my $query_string = "SELECT `local_specification` FROM hosts WHERE status = 'running' AND host = '$hostname' AND simulation = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_bin = $query->fetchrow_array();

		$query->finish();
					
		$query_string = "SELECT `local_simulation` FROM hosts WHERE status = 'running' AND host = '$hostname' AND simulation = '$simulation_name'";
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
		my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$hostIP \'vnx -f $scenario_name -v -u root -x $execution_mode " . $option_M . "'"; 
		&daemonize($execution_command, "/tmp/$hostname"."_log");
	}
	$dbh->disconnect;
}

	###########################################################
	# Subroutine to create tunnels to operate remote VMs from a local port
	###########################################################
sub tunnelize {	
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	my $localport = 64000;

	foreach $vm (keys (%allocation)) {
		my $hostname = $allocation{$vm};
		
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
		system("ssh -2 -q -f -N -o \"StrictHostKeyChecking no\" -L $localport:$vm:22 $hostname");	
		my $query_string = "UPDATE vms SET ssh_port = '$localport' WHERE name='$vm'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();	
		
		if ($localport > 65535) {
			die ("Not enough ports available but the simulation is running... you can't access to VMs using tunnels.");
		}	
	}
	
	$query_string = "SELECT `name`,`host`,`ssh_port` FROM vms WHERE simulation = '$simulation_name' ORDER BY `name`";
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
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	
	$query_string = "SELECT `ssh_port` FROM vms WHERE simulation = '$simulation_name' ORDER BY `ssh_port`";
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
    system("$command") == 0			or die "Could not execute $command!";
    exit();
}

	###########################################################
	# Subroutine to execute execution mode in cluster
	###########################################################
sub processMode {
	
	#my $execution_mode = shift;
	my $dbh;
	my $simulation_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	foreach $physical_host (@cluster_hosts) {	
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		my $host_name = $physical_host->hostName;
		my $hostIP = $physical_host->ipAddress;
		
		# If vm specified with -M is not running in current host, check the next one.

		if ($vm_name){
			my $query_string = "SELECT `host` FROM vms WHERE name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			my $host_of_vm = $query->fetchrow_array();

			unless ($host_name eq $host_of_vm){
				next;
			}
		}

		
		my $query_string = "SELECT `local_specification` FROM hosts WHERE status = 'running' AND host = '$host_name' AND simulation = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $scenario_bin = $query->fetchrow_array();

		$query->finish();
					
		$query_string = "SELECT `local_simulation` FROM hosts WHERE status = 'running' AND host = '$host_name' AND simulation = '$simulation_name'";
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
		my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$hostIP \'vnx -f $scenario_name -v -u root $mode " . $option_M . "'"; 
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