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
# Copyright: (C) 2008 Telefonica Investigacion y Desarrollo, S.A.U.  (VNUML version)
#                2011 Dpto. Ingenieria de Sistemas Telematicos - UPM (VNX version)
# Authors: 	Fco. Jose Martin,
#          	Miguel Ferrer
#			Jorge Somavilla
#			David Fernandez
#          	Departamento de Ingenieria de Sistemas Telematicos, Universidad Politécnica de Madrid
#

###########################################################
# Modules import
###########################################################

# Explicit declaration of pathname for EDIV modules
#use lib "/usr/share/perl5";

use strict;
use warnings;

use XML::DOM;          					# XML management library
use File::Basename;    					# File management library
use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
use POSIX qw(setsid setuid setgid);
use XML::LibXML;
use Cwd 'abs_path';
use Term::ANSIColor;
use Data::Dumper;
use Getopt::Long;


use Socket;								# To resolve hostnames to IPs

use DBI;								# Module to handle databases

use EDIV::static;  						# Module that process static assignment 

use VNX::CheckSemantics;
use VNX::Globals;
use VNX::FileChecks;
use VNX::BinariesData;
use VNX::DataHandler;
use VNX::vmAPI_dynamips;
use VNX::ClusterMgmt;
use VNX::Execution;


###########################################################
# Global variables 
###########################################################
	
# Cluster
my $cluster_conf_file;					# Cluster conf file
	
	# VLAN Assignment
my $firstVlan;         					# First VLAN number
my $lastVlan;          					# Last VLAN number

# Modes
my $partition_mode;						# Default partition mode
my $mode;								# Running mode
my $configuration;						# =1 if scenario has configuration files
# TODO: -M can specify a list of vms not only one
my $vm_name; 							# VM specified with -M tag
my $no_console; 						# Stores the value of --no-console command line option
	
	# Scenario
my $vnx_scenario;						# VNX scenario file name
my %scenarioHash; 						# Scenarios. Every scenario belongs to a host machine
										# Key -> host_id, Value -> XML Scenario							
my $scenario_name;						# Scenario name specified in XML 
my $dom_tree;							# Dom Tree with scenario specification
my $globalNode;							# Global node from dom tree
my $restriction_file;					# Static assigment file

my %allocation;							# Asignation of virtual machine - host_id

my @vms_to_split;						# VMs that haven't been assigned by static
my %static_assignment;					# VMs that have assigned by estatic

my @seg_plugins;							# Segmentation modules that are implemented
my $segmentation_module;

my $conf_plugin_file;					# Configuration plugin file
my $vnx_dir;


	# Path for dynamips config file
my $dynamips_ext_path;

my $version = "2.0";
my $release = "DD/MM/YYYY";
my $branch = "";
my $hline = "----------------------------------------------------------------------------------";


&main;
exit(0);



###########################################################
# THE MAIN PROGRAM
#
sub main {

	print "\n" . $hline . "\n";
	print "Distributed Virtual Networks over LinuX (DVNX) -- http://www.dit.upm.es/vnx - vnx\@dit.upm.es\n";
	print "Version: $version" . "$branch (built on $release)\n";
	print $hline . "\n";
	
	# Argument handling
	our(
	      $opt_define,       # define mode
	      $opt_undefine,     # undefine mode
	      $opt_start,        # start mode
	      $opt_create,       # create mode
	      $opt_shutdown,     # shutdown mode
	      $opt_destroy,      # purge (destroy) mode
	      $opt_save,         # save mode
	      $opt_restore,      # restore mode
	      $opt_suspend,      # suspend mode 
	      $opt_resume,       # resume mode
	      $opt_reboot,       # reboot mode
	      $opt_reset,        # reset mode
	      $opt_execute,      # execute mode
	      $opt_showmap,      # show-map mode
	      $opt_console,      # console mode
	      $opt_consoleinfo,  # console-info mode
	      $opt_exeinfo,      # exe-info mode    
	      $opt_help,         # help mode 
          $opt_seginfo,      # segmentation info         
          $opt_segalginfo,   # segmentation algorithms info         
          $opt_cleancluster, # segmentation algorithms info
	      $opt_v, 
	      $opt_vv,
	      $opt_vvv,          # log trace options
          $opt_V,            # show version 
          $opt_f,            # scenario file 
          $opt_C,            # config file 
          $opt_a,            # segmentation algorithm 
          $opt_r,            # restrictions file 
          $opt_M,            # vm list
          $opt_n             # do not open consoles         
	);
	
	Getopt::Long::Configure ( qw{no_auto_abbrev no_ignore_case} ); # case sensitive single-character options
	GetOptions(  
	           'define'         => \$opt_define,
	           'undefine'       => \$opt_undefine, 
	           'start'          => \$opt_start,
	           't|create'       => \$opt_create, 
	           'd|shutdown'     => \$opt_shutdown,
	           'P|destroy'      => \$opt_destroy, 
	           'save'           => \$opt_save, 
	           'restore'        => \$opt_restore,
	           'suspend'        => \$opt_suspend, 
	           'resume'         => \$opt_resume,
	           'reboot'         => \$opt_reboot, 
	           'reset'          => \$opt_reset,
	           'x|execute=s'    => \$opt_execute, 
	           'show-map'       => \$opt_showmap, 
	           'console'        => \$opt_console,
	           'console-info'   => \$opt_consoleinfo,
	           'exe-info'       => \$opt_exeinfo,
	           'h|H|help'       => \$opt_help, 
               'seg-info'       => \$opt_seginfo,
               'seg-alg-info'   => \$opt_segalginfo,
               'clean-cluster'  => \$opt_cleancluster,
               'v'              => \$opt_v, 
               'vv'             => \$opt_vv,
               'vvv'            => \$opt_vvv,
               'V|version'      => \$opt_V,
               'f=s'            => \$opt_f,
               'C=s'            => \$opt_C,
               'a=s'            => \$opt_a,
               'r=s',           => \$opt_r,
               'M=s',           => \$opt_M,
               'n|no-console'   => \$opt_n 
               
	);
	# Build the argument object
	$args = new VNX::Arguments(
	      $opt_define,       # define mode
	      $opt_undefine,     # undefine mode
	      $opt_start,        # start mode
	      $opt_create,       # create mode
	      $opt_shutdown,     # shutdown mode
	      $opt_destroy,      # purge (destroy) mode
	      $opt_save,         # save mode
	      $opt_restore,      # restore mode
	      $opt_suspend,      # suspend mode 
	      $opt_resume,       # resume mode
	      $opt_reboot,       # reboot mode
	      $opt_reset,        # reset mode
	      $opt_execute,      # execute mode
	      $opt_showmap,      # show-map mode
	      $opt_console,      # console mode
	      $opt_consoleinfo,  # console-info mode
	      $opt_exeinfo,      # exe-info mode    
          $opt_help,         # help mode
          $opt_seginfo,      # segmentation info
          $opt_segalginfo,   # segmentation info
          $opt_cleancluster, # segmentation info
	      $opt_v, 
          $opt_vv,
          $opt_vvv,          # log trace options
	      $opt_V,            # version 
	      $opt_f,            # scenario file
	      $opt_C,            # config file
          $opt_a,            # segmentation algorithm
          $opt_r,            # restrictions file
          $opt_M,            # vm list
          $opt_n             # do not open consoles          
	);
	
	my $how_many_args = 0;
	if ($opt_create) {
	    $how_many_args++; $mode = "create";	}
	if ($opt_execute) {
	    $how_many_args++; $mode = "execute"; }
	if ($opt_shutdown) {
		$how_many_args++; $mode = "shutdown"; }
	if ($opt_destroy) {
	    $how_many_args++; $mode = "destroy"; }
	if ($opt_V) {
	    $how_many_args++; $mode = "version"; }
	if ($opt_help) {
	    $how_many_args++; $mode = "help"; }
	if ($opt_define) {
	    $how_many_args++; $mode = "define"; }
	if ($opt_start) {
	    $how_many_args++; $mode = "start"; }
	if ($opt_undefine) {
	    $how_many_args++; $mode = "undefine"; }
	if ($opt_save) {
	    $how_many_args++; $mode = "save"; }
	if ($opt_restore) {
	    $how_many_args++; $mode = "restore"; }
	if ($opt_suspend) {
	    $how_many_args++; $mode = "suspend"; }
	if ($opt_resume) {
	    $how_many_args++; $mode = "resume";	}
	if ($opt_reboot) {
	    $how_many_args++; $mode = "reboot";	}
	if ($opt_reset) {
	    $how_many_args++; $mode = "reset"; }
	if ($opt_showmap) {
	    $how_many_args++; $mode = "show-map"; }
	if ($opt_console) {
		$how_many_args++; $mode = "console"; }
	if ($opt_consoleinfo) {
	    $how_many_args++; $mode = "console-info"; }
    if ($opt_exeinfo) {
        $how_many_args++; $mode = "exe-info"; }
    if ($opt_seginfo) {
        $how_many_args++; $mode = "seg-info"; }
    if ($opt_segalginfo) {
        $how_many_args++; $mode = "seg-alg-info"; }
    if ($opt_cleancluster) {
        $how_many_args++; $mode = "clean-cluster"; }
	  
	if ($how_many_args gt 1) {
	    &usage;
	    &ediv_die ("Only one of the following at a time: -t|--create, -x|--execute, -d|--shutdown," . 
	               " -V, -P|--destroy, --define, --start, --undefine, --save, --restore, --suspend," .
	               " --resume, --reboot, --reset, --showmap, --seg-info, --clean-cluster or -H\n");
	}
    if ($how_many_args lt 1)  {
        &usage;
        &vnx_die ("missing -t|--create, -x|--execute, -d|--shutdown, -V, -P|--destroy, --define, --start," .
                  " --undefine, \n--save, --restore, --suspend, --resume, --reboot, --reset, --show-map," . 
                  "--console, --console-info, --seg-info, --clean-cluster, -V or -H\n");
    }
	
    # Version pseudomode
    if ($opt_V) {
        my $basename = basename $0;
        print "\n";
        print "                   oooooo     oooo ooooo      ooo ooooooo  ooooo \n";
        print "                    `888.     .8'  `888b.     `8'  `8888    d8'  \n";
        print "                     `888.   .8'    8 `88b.    8     Y888..8P    \n";
        print "                      `888. .8'     8   `88b.  8      `8888'     \n";
        print "                       `888.8'      8     `88b.8     .8PY888.    \n";
        print "                        `888'       8       `888    d8'  `888b   \n";
        print "                         `8'       o8o        `8  o888o  o88888o \n";
        print "\n";
        print "                             Virtual Networks over LinuX\n";
        print "                              http://www.dit.upm.es/vnx      \n";
        print "                                    vnx\@dit.upm.es          \n";
        print "\n";
        print "                 Departamento de Ingeniería de Sistemas Telemáticos\n";
        print "                              E.T.S.I. Telecomunicación\n";
        print "                          Universidad Politécnica de Madrid\n";
        print "\n";
        print "                   Version: $version" . "$branch (built on $release)\n";
        print "\n";
        exit(0);
    }

    # Help pseudomode
    if ($opt_help) {
        &usage;
        exit(0);
    }

    # 2. Optional arguments
    $exemode = $EXE_NORMAL; $EXE_VERBOSITY_LEVEL=N;
    if ($opt_v)   { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=V }
    if ($opt_vv)  { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=VV }
    if ($opt_vvv) { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=VVV }
    #$exemode = $EXE_DEBUG if ($opt_g);
    print "***** verbosity=$EXE_VERBOSITY_LEVEL\n";

    # Check for file and cmd_seq, depending the mode
    my $cmdseq = '';
    if ($opt_execute) {
        $cmdseq = $opt_execute
    } 
	
	# Create logs directory if not already created
	system ("mkdir -p $EDIV_LOGS_DIR");
	
    # Set scenario 
    if ($opt_f) {
        $vnx_scenario = $opt_f; 
        print "Using scenario: $vnx_scenario\n";
    }
    unless ( ($opt_V) or ($opt_help) or ($opt_segalginfo) or ($opt_cleancluster) or (-e $vnx_scenario)) {
        die ("ERROR: scenario xml file not specified (missing -f option) or not found");
    }
    
    # Set configuration file 
    if ($opt_C) {
        $cluster_conf_file = $opt_C; 
    } else {
        $cluster_conf_file = $DEFAULT_CLUSTER_CONF_FILE;
    }
    unless (-e $cluster_conf_file) {
        die ("ERROR: Cluster configuration file ($cluster_conf_file) not found");
    } else {
        print "Using configuration file: $cluster_conf_file\n";
    }

    # Read cluster configuration file
    if (my $res = read_cluster_config($cluster_conf_file)) { 
        print "ERROR: $res\n";  
        exit 1; 
    }

    # Set segmentation algorithm
    if ($opt_a) {
        $partition_mode = $opt_a; 
    } else {
        $partition_mode = $cluster->{def_seg_alg};
    }
    print "Using segmentation algorithm: $partition_mode\n";
    print $hline . "\n";

    # Search for static assigment file
    if ($opt_r) {
        $restriction_file = $opt_r; 
        unless ( (-e $restriction_file) or ($opt_V) or ($opt_help) ) {
            print "\nERROR: The restriction file $restriction_file doesn't exist... Aborting\n\n";
            exit(1);
        }     
        print "Using restriction file: $restriction_file\n";
    }

    # Option -M: vm list
    # TODO: only one vm allowed now. COnvert to process a list of Vms
    if ($opt_M) {
        $vm_name = $opt_M; 
    }    

    # Search for -n|--no-console tag
    $no_console = '';
    if ($opt_n) {
        $no_console = "--no-console";
    }       
        
	my $vnxConfigFile = "/etc/vnx.conf";
	# Set VNX and TMP directories
	my $tmp_dir=&get_conf_value ($vnxConfigFile, 'general', 'tmp_dir');
	if (!defined $tmp_dir) {
		$tmp_dir = $DEFAULT_TMP_DIR;
	}
	#print ("  TMP dir=$tmp_dir\n");
	$vnx_dir=&get_conf_value ($vnxConfigFile, 'general', 'vnx_dir');
	if (!defined $vnx_dir) {
		$vnx_dir = &do_path_expansion($DEFAULT_VNX_DIR);
	} else {
		$vnx_dir = &do_path_expansion($vnx_dir);
	}
	#print ("  VNX dir=$vnx_dir\n");
	
    # Build the VNX::Execution object
    $execution = new VNX::Execution($vnx_dir,$exemode,"host> ",'',$>);
	
    # Load segmentation algorithms array
    load_seg_plugins();

    unless ( ($mode eq 'seg-alg-info') or ($mode eq 'clean-cluster') ) {
	    # init global objects and check VNX scenario correctness 
	    initAndCheckVNXScenario ($vnx_scenario); 
    }

	# Call mode handler
	if      ( $mode eq 'create' )        { mode_create();
	} elsif ( $mode eq 'execute' )       { mode_execute($cmdseq)
	} elsif ( $mode eq 'destroy' )       { mode_destroy()
	} elsif ( $mode eq 'shutdown' )      { mode_shutdown()
	} elsif ( $mode eq 'define' | 
	          $mode eq 'undefine' | 
	          $mode eq 'start' | 
	          $mode eq 'save' | 
			  $mode eq 'restore' | 
			  $mode eq 'suspend' | 
			  $mode eq 'resume' | 
			  $mode eq 'reboot' )        { mode_others()
    } elsif ( $mode eq 'seg-info' )      { mode_seginfo();
    } elsif ( $mode eq 'seg-alg-info' )  { mode_segalginfo();
    } elsif ( $mode eq 'clean-cluster' ) { mode_cleancluster();
    } elsif ( $mode eq 'show-map' )      { mode_showmap();
	} else {
		# default action: die
		die ("ERROR: Unknown mode ($mode)\n");
	}
	
	wlog (N, "\n---- Succesfully finished ----\n");
	exit();

}

#
# Mode handler functions
#
sub mode_create {

    my $error;
    my @db_resp;
       
    # Scenario launching mode
    wlog (N, "\n---- mode: $mode\n---- Creating scenario $vnx_scenario");
        
    # Parse scenario XML.
    #wlog (VV, "\n  **** Parsing scenario ****\n");
    &parseScenario ($vnx_scenario);
    
    # Checking if the simulation already exists
    $error = query_db ("SELECT `name` FROM simulations WHERE name='$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };

    if ( $vm_name && !defined($db_resp[0]->[0])) {
        
        # ERROR: trying to start a vm of a non-existent scenario
        die ("ERROR: Scenario $scenario_name not found. Cannot use -M $vm_name option over a non existent scenario.");
        
    } elsif ( !$vm_name && defined($db_resp[0]->[0])) {
        
        # ERROR: trying to create an already existent scenario
        die ("ERROR: Scenario $scenario_name was already created.");
        
    } elsif ( !$vm_name && !defined($db_resp[0]->[0])) {
        
        # Creating a new scenario
        $error = query_db ("INSERT INTO simulations (name,automac_offset,mgnet_offset) VALUES ('$scenario_name','0','0')");
        if ($error) { ediv_die ("$error") };
        
	    # Segmentation processing
	    if (defined($restriction_file)){
	        wlog (VV, "\n  -- Precessing segmentation restriction file $restriction_file... ****\n");
            #my $restriction = static->new($restriction_file, $dom_tree, @cluster_active_hosts); 
            my $restriction = static->new($restriction_file, $dh->get_doc, @cluster_active_hosts); 
	        %static_assignment = $restriction->assign();
	        if ($static_assignment{"error"} eq "error"){
	            delete_scenario_from_database ($scenario_name);
	            die();
	        }
	        @vms_to_split = $restriction->remaining();
	    }
	        
	    wlog (VV, "\n  ---- Calling $partition_mode segmentator... ****\n");
	    # Look for the segmentation module selected and load it 
	    push (@INC, "$EDIV_SEG_ALGORITHMS_DIR");
	    foreach my $plugin (@seg_plugins){
	            
	        wlog (VV, "-- plugin = $plugin");
	        require $plugin;
	        import  $plugin;
	        my @module_name_split = split(/\./, $plugin);
	        my $plugin_withoutpm = $module_name_split[0];
	        my $plugin_name = $plugin_withoutpm->name();
	        if ($plugin_name eq $partition_mode) {
	            $segmentation_module = $plugin_withoutpm;   
	        }
	    }  
	    unless (defined($segmentation_module)) {
	        wlog (N, "ERROR: segmentator module $partition_mode not found");
	        delete_scenario_from_database ($scenario_name);
	        die();
	    }
	        
        #%allocation = $segmentation_module->split(\$dom_tree, \@cluster_active_hosts, \$cluster, \@vms_to_split, \%static_assignment);
        my $dom_tree = $dh->get_doc;
        %allocation = $segmentation_module->split(\$dom_tree, \@cluster_active_hosts, \$cluster, \@vms_to_split, \%static_assignment);
	        
	    if (defined($allocation{"error"})){
	            delete_scenario_from_database ($scenario_name);
	            die();
	    }
	        
	    wlog (N, "\n  ---- Configuring distributed networking in cluster ****");
	            
	    # Fill the scenario array
	    fillScenarioArray('yes');
	    unless ($vm_name){
	        # Assign first and last VLAN.
	        &assignVLAN;
	    }   
	    # Split into files
	    wlog (VVV, "****************************** Calling splitIntoFiles...");
	    &splitIntoFiles ('yes');
	    # Make a tgz compressed file containing VM execution config 
	    &getConfiguration;
	    # Send Configuration to each host.
	    &sendConfiguration;
	    #jsf: código copiado a sub sendConfiguration, borrar esta subrutina.    
	    # Send dynamips configuration to each host.
	    #&sendDynConfiguration;
	    wlog (N, "\n\n  **** Sending scenario to cluster hosts and executing it ****\n");
	    # Send scenario files to the hosts and run them with VNX (-t option)
	    &sendScenarios;
	      
	    unless ($vm_name){
	        # Check if every VM is running and ready
	        wlog (N, "\n\n  **** Checking simulation status ****\n");
	        &checkFinish;
	            
	        # Create a ssh tunnel to access remote VMs
	        wlog (N, "\n\n  **** Creating tunnels to access VM ****\n");
	        &tunnelize;
	    }
        
    } elsif ( $vm_name && defined($db_resp[0]->[0])) {

        # Creating a vm over an existent scenario 
        
        # Check the status of the vm
        # If it is already started, finish with an error
        # VM status: inactive, active, suspended, hibernated
        $error = query_db ("SELECT `status` FROM vms WHERE name = '$vm_name' AND simulation = '$scenario_name'", \@db_resp);
        if ($error) { ediv_die ("$error") };
        if (defined($db_resp[0]->[0])) { 
        	if ( $db_resp[0]->[0] ne 'inactive' ) {
	            wlog (N, "ERROR: virtual machine $vm_name specified in '-M' option not inactive (status=$db_resp[0]->[0])");
	            die(); 
        	}
        } else {
        	wlog (N, "ERROR: virtual machine $vm_name specified in '-M' option not found");
        	die(); 
        }      
        
        # get the host where the vm is running
        my $host_id = get_vm_host($vm_name);
        my $host_ip   = get_host_ipaddr ($host_id);            
        my $host_name = get_host_hostname ($host_id);
        
        # Start the vm
        my $subscenario_name = get_host_subscenario_name ($host_name, $scenario_name);
        my $subscenario_fname = "/tmp/$subscenario_name".".xml";
        my $subscenario_xml = get_host_subscenario_xml ($host_name, $scenario_name, $subscenario_fname);
        if ( (defined($subscenario_name)) && (defined($subscenario_xml)) ) {

            my $scp_command = "scp -2 $subscenario_fname root\@$host_ip:/tmp/";
            &daemonize($scp_command, "$host_name"."_log");
    
            my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $subscenario_fname\'";
            &daemonize($permissions_command, "$host_name"."_log");
            
            my $option_M = "-M $vm_name";
            my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx -v -t -f $subscenario_fname " . $option_M . "'";
            &daemonize($ssh_command, "$host_name"."_log");  
            
            # update vm status in db
            # TODO: update all vms when -M allows a list of vms
            my $error = query_db ("UPDATE vms SET status = 'active' WHERE name='$vm_name'");
            if ($error) { ediv_die ("$error") };

        }        
    }
	
}

sub mode_shutdown {

    my $error;
    my @db_resp;

    # Clean and destroy scenario temporary files
    wlog (N, "\n---- mode: $mode\n---- Shutdowning scenario $vnx_scenario");
        
    # Parse scenario XML
    #&parseScenario; 
    
    # Checking if the simulation is running
    $error = query_db ("SELECT `simulation` FROM hosts WHERE status = 'running' AND simulation = '$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        die ("The simulation $scenario_name wasn't running... Aborting");
    }       
        
    # If no -M option, mark simulation as "destroying"
    unless ($vm_name){
        $error = query_db ("UPDATE hosts SET status = 'destroying' WHERE status = 'running' AND simulation = '$scenario_name'");
        if ($error) { ediv_die ("$error") };
    }
    
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
        delete_scenario_from_database ($scenario_name);
            
        # Delete /tmp files
        &deleteTMP;
    }
}

sub mode_destroy {

    my $error;
    my @db_resp;
        
    # Clean and purge scenario temporary files
    wlog (N, "\n---- mode: $mode\n---- Purging scenario $vnx_scenario");
        
    # Parse scenario XML
    #&parseScenario;

    # Checking if the simulation is running
    $error = query_db ("SELECT `name` FROM simulations WHERE name='$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        die ("The simulation $scenario_name wasn't running... Aborting");
    }

    # If no -M option, mark simulation as "purging"
    unless ($vm_name){
        $error = query_db ("UPDATE hosts SET status = 'purging' WHERE status = 'running' AND simulation = '$scenario_name'");
        if ($error) { ediv_die ("$error") };
    }
        
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
        delete_scenario_from_database ($scenario_name);
         
        # Delete /tmp files
        &deleteTMP;
    }
}

sub mode_execute {

    my $cmdseq = shift;
    my $error;
    my @db_resp;
    
    # Execution of commands in VMs mode
    if (!defined($cmdseq)) {
        die ("You must specify the command tag to execute\n");
    }
    wlog (N, "\n---- mode: $mode\n---- Executing commands tagged with '$cmdseq'");
        
    # Parse scenario XML
    #&parseScenario;

    # Checking if the simulation is running
    $error = query_db ("SELECT `simulation` FROM hosts WHERE status = 'running' AND simulation = '$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        die ("The simulation $scenario_name wasn't running... Aborting");
    }
        
    # Make a tgz compressed file containing VM execution config 
    &getConfiguration;
        
    # Send Configuration to each host.
    &sendConfiguration;
        
    # Send Configuration to each host.
    wlog (N, "\n **** Sending commands to VMs ****");
    &executeConfiguration($cmdseq);
	
}

sub mode_others {

    my $error;
    my @db_resp;

    # Processing VMs mode
    wlog (N, "\n---- mode: $mode\n---- ");
        
    # Parse scenario XML
    #&parseScenario;
    
    # quizá el define se podría usar sin la simulacion creada ya, sobraria aqui 
    # Checking if the simulation is running
    $error = query_db ("SELECT `simulation` FROM hosts WHERE status = 'running' AND simulation = '$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        die ("The simulation $scenario_name wasn't running... Aborting");
    }       
        
    # Make a tgz compressed file containing VM execution config 
    &getConfiguration;
        
    # Send Configuration to each host.
    &sendConfiguration;
        
    # Process mode defined in $mode
    &processMode;
}

sub mode_seginfo {

    # Show segmentation info
    wlog (N, "\n---- mode: $mode\n---- Show vms to hosts mapping for $vnx_scenario");
       
    # Parse scenario XML.
    #wlog (VV, "\n  **** Parsing scenario ****\n");
    #&parseScenario ($vnx_scenario);
    
    # Segmentation processing
    if (defined($restriction_file)){
        wlog (VV, "\n  **** Calling static processor... ****\n");
        #my $restriction = static->new($restriction_file, $dom_tree, @cluster_active_hosts); 
        my $restriction = static->new($restriction_file, $dh->get_doc, @cluster_active_hosts); 
        
        %static_assignment = $restriction->assign();
        if ($static_assignment{"error"} eq "error"){
            delete_scenario_from_database ($scenario_name);
            die();
        }
        @vms_to_split = $restriction->remaining();
    }
        
    wlog (VV, "\n  **** Calling segmentator... ****\n");
   
    # Look for the segmentation module selected and load it 
    push (@INC, "$EDIV_SEG_ALGORITHMS_DIR");
    foreach my $plugin (@seg_plugins){
            
        wlog (VV, "** plugin = $plugin");
            
        require $plugin;
        import  $plugin;
   
        my @module_name_split = split(/\./, $plugin);
        my $plugin_withoutpm = $module_name_split[0];
        my $plugin_name = $plugin_withoutpm->name();
        if ($plugin_name eq $partition_mode) {
            $segmentation_module = $plugin_withoutpm;   
        }
    }  
    unless (defined($segmentation_module)) {
       wlog (N, 'Segmentator: your choice ' . "$partition_mode" . " is not a recognized option (yet)");
       delete_scenario_from_database ($scenario_name);
       die();
    }
    
    my $dom_tree = $dh->get_doc;
    %allocation = $segmentation_module->split(\$dom_tree, \@cluster_active_hosts, \$cluster, \@vms_to_split, \%static_assignment);
        
    if (defined($allocation{"error"})){
            wlog (N, "ERROR: in segmentation module  $segmentation_module");
            die();
    }
    fillScenarioArray();
    assignVLAN();
    splitIntoFiles();
    foreach my $host_id (@cluster_active_hosts) {
        my $subscenario_fname = "/tmp/" . $scenario_name . "_" . $host_id . ".xml"; 
        my $currentScenario = $scenarioHash{$host_id};      
        $currentScenario->printToFile("$subscenario_fname");
    }
}

sub mode_segalginfo {

    # Show segmentation algorithms available
    wlog (N, "\n---- mode: $mode\n---- Showing segmentation algorithms available");

    my $msg = sprintf ("\n     %-24s --> %s", "Algorithm name", "Filename"); wlog (N, $msg);
    wlog (N, "     --------------------------------------------------------------------------------");

    #push (@INC, "$EDIV_SEG_ALGORITHMS_DIR");
    foreach my $plugin (@seg_plugins){
        my @module_name_split = split(/\./, $plugin);
        my $plugin_withoutpm = $module_name_split[0];
        my $plugin_name = $plugin_withoutpm->name();
        my $msg = sprintf ("     %-24s --> %s", $plugin_name, "$EDIV_SEG_ALGORITHMS_DIR/$plugin");
        wlog (N, $msg);
    }  	
}

sub mode_cleancluster {

    my $error;
    my @db_resp;
    
    # Clean cluster
    wlog (N, "\n---- mode: $mode\n---- Cleaning cluster");

    wlog (N, "\n-------------------------------------------------------------------");
    wlog (N, "---- WARNING - WARNING - WARNING - WARNING - WARNING - WARNING ----");
    wlog (N, "-------------------------------------------------------------------");
    wlog (N, "---- This command will:");
    wlog (N, "----   - destroy all virtual machines in every host in the cluster");
    wlog (N, "----   - delete EDIV database");
    wlog (N, "----   - delete .vnx directories");
    wlog (N, "---- Do you want to continue (yes/no)?");
    my $line = readline(*STDIN);
    unless ( $line =~ /^yes/ ) {
        wlog (N, "---- Cluster not restarted. Exiting");
    } else {

        wlog (N, "---- Restarting cluster...");
        foreach my $host_id (@cluster_active_hosts){
            my $host_ip   = get_host_ipaddr ($host_id);
            my $host_name = get_host_hostname ($host_id);
            my $vnx_dir = get_host_vnxdir ($host_id);
            my $hypervisor = get_host_hypervisor ($host_id);
             
            wlog (N, "---- Host $host_name:");

            wlog (N, "----   Killing libvirt virtual machines...");
            my @virsh_list;
            my $i;
            my $pipe = "ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'virsh -c $hypervisor list' |";
            open VIRSHLIST, "$pipe";
            while (<VIRSHLIST>) {
                chomp; $virsh_list[$i++] = $_;
            }
            close VIRSHLIST;
            # Ignore first two lines (caption)
            for ( my $j = 2; $j < $i; $j++) {
                $_ = $virsh_list[$j];
                #print "-- $_\n";
                /^\s+(\S+)\s+(\S+)\s+(\S+)/;
                if (defined ($2)) {
                    my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip 'virsh destroy $2'";
                    wlog (N, "----     killing vm $2 at host $host_name");  
                    &daemonize($ssh_command, "$host_id"."_log");       
                }
            }
                
            wlog (N, "----   Killing uml virtual machines...(not implemented yet)");
            wlog (N, "----   Restarting dynamips daemon at host $host_name");  
            my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip '/etc/init.d/dynamips restart'";
            &daemonize($ssh_command, "$host_id"."_log");       

            wlog (N, "----   Deleting .vnx directories...");
            if (defined($vnx_dir)) {
                my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip 'rm -rf $vnx_dir/../.vnx/*'";
                &daemonize($ssh_command, "$host_id"."_log");       
            }

        }           

        wlog (N, "---- Deleting EDIV database...");
        reset_database();;
    }
}

sub mode_showmap {

    wlog (N, "\n---- mode: $mode\n---- Show scenario $vnx_scenario map");
    #print "vnx -f $vnx_scenario --show-map";
    system ("vnx -f $vnx_scenario --show-map > /dev/null 2>&1");	
}

#
# load_seg_plugins
#
# Subroutine to load available segmentation modules into @seg_plugins array 
#
sub load_seg_plugins {
	
	my @paths;
	
    wlog (VV, " load_seg_plugins called");
	
	push (@paths, "$EDIV_SEG_ALGORITHMS_DIR");
	#push (@paths, "/usr/local/share/ediv/algorithms/");
	
	foreach my $path (@paths){
		opendir(DIRHANDLE, "$path"); 
		foreach my $module (readdir(DIRHANDLE)){ 
			if ((!($module eq ".."))&&(!($module eq "."))){
				push (@seg_plugins, $module);	
                wlog (VV, " Segmentation module $module added to seg_plugins")
			} 
		} 
		closedir DIRHANDLE;
	} 
	my $seg_plugins_size = @seg_plugins;
	if ($seg_plugins_size == 0){
        delete_scenario_from_database ($scenario_name);
		die ("No segmentation modules found at $EDIV_SEG_ALGORITHMS_DIR... Aborting");
	}

}

#
# parseScenario
#
# Subroutine to parse XML scenario specification into DOM tree
#
sub parseScenario {
	
	my $parser = new XML::DOM::Parser;
	$dom_tree = $parser->parsefile($vnx_scenario);
	$globalNode = $dom_tree->getElementsByTagName("vnx")->item(0);
	$scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;

#   my $error;
#   my @db_resp;
#	if ($mode eq 'create') {
#	} elsif($mode eq 'execute') {
#	} elsif($mode eq 'destroy') {
#	} elsif($mode eq 'shutdown') {
#	} elsif($mode eq 'define' | $mode eq 'undefine' | $mode eq 'start' | $mode eq 'save' | 
#		$mode eq 'restore' | $mode eq 'suspend' | $mode eq 'resume' | $mode eq 'reboot') {
#	}

	#if dynamips_ext node is present, update path
#	$dynamips_ext_path = "";
#	my $dynamips_extTagList=$dom_tree->getElementsByTagName("dynamips_ext");
#	my $numdynamips_ext = $dynamips_extTagList->getLength;
#	if ($numdynamips_ext == 1) {
#		my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
#		$dynamips_ext_path = "$vnx_dir/scenarios/";
#	}
}

sub is_scenario_running {

    my $scenario_name = shift;
    my @db_resp;
    
    # Query the database
    my $error = query_db ("SELECT `name` FROM simulations WHERE name='$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    if ( defined($db_resp[0]->[0]) ) {
    	return 1
    } else {
    	return 0
    }	
}

#
# assignVLAN
#
# Subroutine to read VLAN configuration from cluster config or database
#
sub assignVLAN {
	#my $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass});
	$firstVlan = $vlan->{first};
	$lastVlan  = $vlan->{last};	

	while (1){
        
        my @db_resp;
        my $error = query_db ("SELECT `number` FROM vlans WHERE number='$firstVlan'", \@db_resp);
        if ($error) { ediv_die ("$error") };
        unless ( defined($db_resp[0]->[0]) ) {
            last;
        }       
		#my $query_string = "SELECT `number` FROM vlans WHERE number='$firstVlan'";
		#my $query = $dbh->prepare($query_string);
		#$query->execute();
		#my $contenido = $query->fetchrow_array();
		#unless (defined($contenido)) {
		#	last;
		#}
		#$query->finish();
		$firstVlan++;
		if ($firstVlan >$lastVlan){
            delete_scenario_from_database ($scenario_name);
			die ("There isn't more free vlans... Aborting");
		}	
	}	
	#$dbh->disconnect;
}
	
	
#
# fillScenarioArray create_subscenario_docs
# 
# It creates a new dom tree for each host to store its subscenario specification
# The new dom trees are stored in $scenarioHash associative array
#
sub fillScenarioArray {
	
	my $change_db = shift; # if not defined, the database is not changed 

    #print $dh->get_doc->toString;
	
	# Create a new template document by cloning the scenario tree
    #my $templateDoc= $dom_tree->cloneNode("true");
    my $templateDoc= $dh->get_doc->cloneNode("true");
    
    my $newVnxNode=$templateDoc->getElementsByTagName("vnx")->item(0);
	#print $newVnxNode->getNodeTypeName."\n";
	#print $newVnxNode->getNodeName."\n";
    # Delete all child nodes but the <global> one  
    for my $child ($newVnxNode->getChildNodes){
		unless ($child->getNodeName eq 'global'){
			$newVnxNode->removeChild($child);
		} 
	}
	# Clone <global> section and add it to template document
#	my $global= $dom_tree->getElementsByTagName("global")->item(0)->cloneNode("true");
#	$global->setOwnerDocument($templateDoc);
#	$newVnxNode->appendChild($global);

#	my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
	# Create a new document for each active host in the cluster by cloning the template document ($templateDoc)
    foreach my $host_id (@cluster_active_hosts) {

        my $scenarioDoc=$templateDoc->cloneNode("true");
        my $current_host_ip   = get_host_ipaddr ($host_id);
        # Set host subscenario name: original scenario name + _ + host_id
        my $host_scen_name = $scenario_name."_" . $host_id; 
	    $scenarioDoc->getElementsByTagName("scenario_name")->item(0)->getFirstChild->setData($host_scen_name);
        wlog (VVV, "** host_id = $host_id, current_host_ip = $current_host_ip, host_scen_name=$host_scen_name");  
		
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
				my $vm_name = $vm->getAttribute("name");
				my $host_name = $allocation{$vm_name};
				if ($host_name eq $host_id){
					my $vm_type = $vm->getAttribute("type");
					if ($vm_type eq "dynamips"){
						$keep_dynamips_in_scenario = 1;
					}
				}	
			}
	   		if ($keep_dynamips_in_scenario == 1){
	   			#my $current_host_dynamips_path = $dynamips_ext_path . $host_scen_name ."/dynamips-dn.xml";
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

    	}	
		
		my $basedir_data = "/tmp/";
		eval{
			$scenarioDoc->getElementsByTagName("global")->item(0)->getElementsByTagName("vm_defaults")->item(0)->getElementsByTagName("basedir")->item(0)->getFirstChild->setData($basedir_data);
		};		
		
		# Store the new document in $scenarioHash array
		$scenarioHash{$host_id} = $scenarioDoc;	
        wlog (VVV, "---- fillScenarioArray: assigned scenario for $host_id\n");
		
		if (defined($change_db)) {
	        # Save data into DB
	        my $error = query_db ("INSERT INTO hosts (simulation,local_simulation,host,ip,status) VALUES " 
	                           . "('$scenario_name','$host_scen_name','$host_id','$current_host_ip','creating')");
	        if ($error) { die "** $error" }
		}
        
	}
	#wlog (VVV, "****** fillScenarioArray:\n" . Dumper(keys(%scenarioHash)) );
	
}

#
# splitIntoFiles
#
# Split the original scenario xml file into several smaller files for each host.
#
sub splitIntoFiles {

    my $change_db = shift; # if not defined, the database is not changed 

    my $error; 
    my @db_resp;
    
    wlog (VVV, "-- splitIntoFiles called");
    
    #print $globalNode->toString;
    #print $dh->get_doc->toString;
    
	# We explore the vms on the node and call vmPlacer to place them on the scenarios	
	my $virtualmList=$globalNode->getElementsByTagName("vm");

	my $vmListLength = $virtualmList->getLength;

	# Add VMs to corresponding subscenario specification file
	for (my $m=0; $m<$vmListLength; $m++){
		
		my $vm      = $virtualmList->item($m);
		my $vm_name = $vm->getAttribute("name");
		my $host_id = $allocation{$vm_name};
		
		#añadimos type para base de datos
        my $vm_type    = $vm->getAttribute("type");
        my $vm_subtype = $vm->getAttribute("subtype");
        my $vm_os      = $vm->getAttribute("os");
        wlog (V, "---- $vm_name of type $vm_type allocated to host $host_id");

		#print "*** OLD: \n";
		#print $vm->toString;

		my $newVirtualM = $vm->cloneNode("true");
		
		#print "\n*** NEW: \n";
		#print $newVirtualM->toString;
		#print "***\n";
		
		$newVirtualM->setOwnerDocument($scenarioHash{$host_id});

		my $vnxNode=$scenarioHash{$host_id}->getElementsByTagName("vnx")->item(0);
			
		$vnxNode->setOwnerDocument($scenarioHash{$host_id});
		
		$vnxNode->appendChild($newVirtualM);
		#print $vnxNode->toString;
		#print "***\n";

		#unless ($vm_name){
			# Creating virtual machines in the database
            wlog (VVV, "** splitIntoFiles: Creating virtual machine $vm_name in db");

            if (defined($change_db)) {
		        $error = query_db ("SELECT `name` FROM vms WHERE name='$vm_name'", \@db_resp);
		        if ($error) { ediv_die ("$error") };
		        if ( defined($db_resp[0]->[0]) ) {
	                delete_scenario_from_database ($scenario_name);
	                die ("The vm $vm_name was already created... Aborting");
		        }
		        # Register the new vm in the database
	            $error = query_db ("INSERT INTO vms (name,type,subtype,os,status,simulation,host) " . 
	                               "VALUES ('$vm_name','$vm_type','$vm_subtype','$vm_os','inactive','$scenario_name','$host_id')");
	            if ($error) { ediv_die ("$error") };
            }
	}

	# We add the corresponding nets to subscenario specification file
	my $nets= $globalNode->getElementsByTagName("net");
	
	# For exploring all the nets on the global scenario
	for (my $h=0; $h<$nets->getLength; $h++) {
		
		my $currentNet=$nets->item($h);
		my $nameOfNet=$currentNet->getAttribute("name");

		# For exploring each scenario on scenarioarray	
		foreach my $host_id (keys(%scenarioHash)) {
			
			my $currentScenario = $scenarioHash{$host_id};		
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
	if (defined($change_db)) {
	    unless ($vm_name){
	        &netTreatment;
	        &setAutomac;
	    }
	}
}

#
# netTreatment
#
# Subroutine to process nets to configure them for distributed operation
#
sub netTreatment {

    my $error; 
    my @db_resp;

	# 1. Make a list of nets to handle
	my %nets_to_handle;
	my $nets= $globalNode->getElementsByTagName("net");
	
	# For exploring all the nets on the global scenario
	for (my $h=0; $h<$nets->getLength; $h++) {
		
		my $currentNet=$nets->item($h);
		my $nameOfNet=$currentNet->getAttribute("name");
		
		# Creating virtual nets in the database
	    $error = query_db ("SELECT `name` FROM nets WHERE name='$nameOfNet'", \@db_resp);
	    if ($error) { ediv_die ("$error") };
	    if ( defined($db_resp[0]->[0]) ) {
	        print ("INFO: The net $nameOfNet was already created...");
        }
        $error = query_db ("INSERT INTO nets (name,simulation) VALUES ('$nameOfNet','$scenario_name')");
        if ($error) { ediv_die ("$error") };
		#$query_string = "INSERT INTO nets (name,simulation) VALUES ('$nameOfNet','$scenario_name')";
        		
        # For exploring each scenario on scenarioarray	
		my @net_host_list;
		foreach my $host_id (keys(%scenarioHash)) {
			my $currentScenario = $scenarioHash{$host_id};
			my $currentScenario_nets = $currentScenario->getElementsByTagName("net");
			for (my $j=0; $j<$currentScenario_nets->getLength; $j++) {
				my $currentScenario_net = $currentScenario_nets->item($j);
				
				if ( ($currentScenario_net->getAttribute("name")) eq ($nameOfNet)) {
					push(@net_host_list, $host_id);
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
	foreach my $net_name (keys(%nets_to_handle)) {
		# 2.1 VLAN and bridge assignation
		
		while (1){
	        $error = query_db ("SELECT `number` FROM vlans WHERE number='$current_vlan'", \@db_resp);
	        if ($error) { ediv_die ("$error") };
	        unless ( defined($db_resp[0]->[0]) ) {
	            last;
	        }
			$current_vlan++;
			
			if ($current_vlan >$lastVlan){
                delete_scenario_from_database ($scenario_name);
				die ("There isn't more free vlans... Aborting");
			}	
		}
	
		my $current_net = $nets_to_handle{$net_name};
		my $net_vlan = $current_vlan;
		
		# 2.2 Use previous data to modify subscenario
		foreach my $host_id (keys(%scenarioHash)) {

			my $command_list;
            my $external = get_host_ifname ($host_id);
			my $currentScenario = $scenarioHash{$host_id};
			for (my $k=0; defined($current_net->[$k]); $k++) {
				if ($current_net->[$k] eq $host_id) {
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
				            $error = query_db ("UPDATE nets SET external = '$external.$net_vlan' WHERE name='$currentNetName'");
				            if ($error) { ediv_die ("$error") };
							
                            $error = query_db ("INSERT INTO vlans (number,simulation,host,external_if) VALUES ('$net_vlan','$scenario_name','$host_id','$external')");
                            if ($error) { ediv_die ("$error") };
		
							my $vlan_command = "vconfig add $external $net_vlan\nifconfig $external.$net_vlan 0.0.0.0 up\n";
							$commands{$host_id} = defined ($commands{$host_id}) ? $commands{$host_id}."$vlan_command" 
							                                                    : "$vlan_command";						
						}
					}
				}
			}
		}
	}
	
	# 3. Configure nets of cluster machines
	foreach my $host_id (keys(%commands)){
		my $host_ip = get_host_ipaddr ($host_id);
		my $host_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip '$commands{$host_id}'";
		&daemonize($host_command, "$host_id"."_log");
	}
}

#
# setAutomac
#
# Subroutine to set the proper value on automac offset
#
sub setAutomac {
	
	my $error;
	my @db_resp;
	
	my $VmOffset;
	my $MgnetOffset;
#	my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
    $error = query_db ("SELECT `automac_offset` FROM simulations ORDER BY `automac_offset` DESC LIMIT 0,1", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        $VmOffset = 0;
    } else {
        $VmOffset = $db_resp[0]->[0]; # we hope this is enough
    }

    $error = query_db ("SELECT `mgnet_offset` FROM simulations ORDER BY `mgnet_offset` DESC LIMIT 0,1", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        $MgnetOffset = 0;
    } else {
        $MgnetOffset = $db_resp[0]->[0]; # we hope this is enough
    }
	
	my $management_network = $cluster->{mgmt_network};
	my $management_network_mask = $cluster->{mgmt_network_mask};
	
	foreach my $host_id (keys(%scenarioHash)) {
		
		my $currentScenario = $scenarioHash{$host_id};
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
		foreach my $virtual_machine (keys(%allocation)) {
			if ($allocation{$virtual_machine} eq $host_id) {
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
#			if ($allocation{$virtual_machine} eq $host_name) {
#				$MgnetOffset += 4; # Uses mask /30 with a point-to-point management network
#			}				
#		}	
	}
	
    $error = query_db ("UPDATE simulations SET automac_offset = '$VmOffset' WHERE name='$scenario_name'");
    if ($error) { ediv_die ("$error") };
	
    $error = query_db ("UPDATE simulations SET mgnet_offset = '$MgnetOffset' WHERE name='$scenario_name'");
    if ($error) { ediv_die ("$error") };
	
}

#
# sendScenarios 
#
# Subroutine to send scenario files to hosts
#
sub sendScenarios {
	
	my @db_resp;
	
	#wlog (VVV, "** " . Dumper(%scenarioHash));
	foreach my $host_id (keys(%scenarioHash)) {
	
	    wlog (VVV, "**** sendScenarios: $host_id");
	
		#my $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass});
		my $currentScenario = $scenarioHash{$host_id};
        my $host_ip = get_host_ipaddr ($host_id);
	
		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){	
            unless ($host_id eq get_vm_host ($vm_name) ) {
                next;
            }
		}
		
		my $host_scen_name = $currentScenario->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
#		my $scenario_name = $filename;

		my $hostScenFileName = "/tmp/$host_scen_name".".xml";
		$currentScenario->printToFile("$hostScenFileName");
		#print "**** $hostScenFileName \n";
		#system ("cat $hostScenFileName");
			# Save the local specification in DB	
		open(FILEHANDLE, $hostScenFileName) or die  'cannot open file!';
		my $fileData;
		read (FILEHANDLE,$fileData, -s FILEHANDLE);

		# We scape the "\" before writing the scenario to the ddbb
   		$fileData =~ s/\\/\\\\/g; 
        my $error = query_db ("UPDATE hosts SET local_specification = '$fileData' WHERE local_simulation='$host_scen_name'");
        if ($error) { ediv_die ("$error") };
		close (FILEHANDLE);
		
		my $scp_command = "scp -2 $hostScenFileName root\@$host_ip:/tmp/";
		&daemonize($scp_command, "$host_id"."_log");
		my $permissions_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip \'chmod -R 777 $hostScenFileName\'";
		&daemonize($permissions_command, "$host_id"."_log"); 
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnx -f $hostScenFileName -v -t -o /dev/null\ " 
		                  . $option_M . " " . $no_console . "'";
		&daemonize($ssh_command, "$host_id"."_log");		
	}
}

#
# checkFinish
#
# Subroutine to check propper finishing of launching mode (-t)
# Uses $vnx_dir/simulations/<simulacion>/vms/<vm>/status file
#
sub checkFinish {

	my $dbh;
	my $host_ip;
	my $host_name;
	my $scenario;
	my $file;
	
	my @output1;
	my @output2;
	my $notAllRunning = "yes";
	while ($notAllRunning) {
		$notAllRunning = '';
		@output1 = ();
		@output2 = ();
		my $date=`date`;
		push (@output1, "\nScenario: " . color ('bold') . $scenario_name . color('reset') . "\n");			
		push (@output1, "\nDate: " . color ('bold') . "$date" . color('reset') . "\n");
        #push (@output1, sprintf (" %-24s%-24s%-20s%-40s\n", "VM name", "Host", "Status", "Status file"));           
        #push (@output1, sprintf ("---------------------------------------------------------------------------------------------------------------\n"));         
        push (@output1, sprintf (" %-24s%-24s%-20s%-40s\n", "VM name", "Host", "Status"));           
        push (@output1, sprintf ("----------------------------------------------------------------------\n"));         

		foreach my $host_id (@cluster_active_hosts){

            my $host_ip = get_host_ipaddr ($host_id);
            foreach my $vm_name (keys (%allocation)){
                wlog (VVV, "** vm=$vm_name, host_id=$host_id");
                if ($allocation{$vm_name} eq $host_id){
                    my $statusFile = get_host_vnxdir($host_id) . "/scenarios/" 
                                    . $scenario_name . "_" . $host_id . "/vms/$vm_name/status";
                    my $status_command = "ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'cat $statusFile 2> /dev/null'";
                    wlog (VVV, "** Executing: $status_command");
                    my $status = `$status_command`;
                    chomp ($status);
                    wlog (VVV, "** Executing: status=$status");
                    if (!$status) { $status = "undefined" }
                    #push (@output2, color ('bold'). sprintf (" %-24s%-24s%-20s%-40s\n", $vm_name, $host_id, $status, $statusFile) . color('reset'));
                    push (@output2, color ('bold'). sprintf (" %-24s%-24s%-20s%-40s\n", $vm_name, $host_id, $status) . color('reset'));
                    if (!($status eq "running")) {
                        $notAllRunning = "yes";
                    } else {
                    	# update status in database
				        my $error = query_db ("UPDATE vms SET status = 'active' WHERE name='$vm_name'");
				        if ($error) { ediv_die ("$error") };
                    }
                }
            }
		}
		system "clear";
		print @output1;
		print sort(@output2);
        printf "----------------------------------------------------------------------\n";         
        #printf "---------------------------------------------------------------------------------------------------------------\n";         
		sleep 2;
	}

    my $error;
    my @db_resp;
    
	foreach my $host_id (@cluster_active_hosts){
        $error = query_db ("UPDATE hosts SET status = 'running' WHERE status = 'creating' AND host = '$host_id'");
        if ($error) { ediv_die ("$error") };
		
			#$host_ip   = $cluster->{hosts}{$host_id}->ip_address;
			#$host_name = $cluster->{hosts}{$host_id}->host_name;
	
		    #$error = query_db ("SELECT `local_simulation` FROM hosts WHERE status = 'creating' AND host = '$host_name'", \@db_resp);
		    #if ($error) { ediv_die ("$error") };
		    #if ( defined($db_resp[0]->[0]) ) {
		    #	 $scenario = $db_resp[0]->[0];
		    #	 chomp($scenario);
	        #}
			#my $query_string = "SELECT `local_simulation` FROM hosts WHERE status = 'creating' AND host = '$host_name'";
			#my $query = $dbh->prepare($query_string);
			#$query->execute();
			#$scenario = $query->fetchrow_array();
			#$query->finish();
			#chomp($scenario);
			#$dbh->disconnect;
			
			#$query_string = "UPDATE hosts SET status = 'running' WHERE status = 'creating' AND host = '$host_name'";
			#$query = $dbh->prepare($query_string);
			#$query->execute();
			#$query->finish();
			#$dbh->disconnect;
	}

=BEGIN	
	foreach $host(@cluster_hosts){
		$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		$host_ip = $cluster->{hosts}{$host}->ip_address;
		$host_name = $cluster->{hosts}{$host}->host_name;
		
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
				
				my $statusFile = $host->vnxDir . "/scenarios/$scenario/vms/$vms/status";
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
		$query_string = "UPDATE hosts SET status = 'running' WHERE status = 'creating' AND host = '$host_name'";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		$dbh->disconnect;
	}
=END
=cut
}

#
# purgeScenario
#
# Subroutine to execute purge mode in cluster
#
sub purgeScenario {

	my $host_ip;
	my $host_name;
	
	my @db_resp;
    my $error;

	my $scenario;
	foreach my $host_id (@cluster_active_hosts) {

		my $vlan_command;
		$host_ip   = get_host_ipaddr ($host_id);			
		$host_name = get_host_hostname ($host_id);

		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){
            unless ($host_name eq get_vm_host ($vm_name) ) {
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

        my $subscenario_name = get_host_subscenario_name ($host_name, $scenario_name);
        my $subscenario_fname = "/tmp/$subscenario_name".".xml";
        my $subscenario_xml = get_host_subscenario_xml ($host_name, $scenario_name, $subscenario_fname);
        if ( (defined($subscenario_name)) && (defined($subscenario_xml)) ) {
        	
#	        wlog (VVV, "** subscenario_name=$subscenario_name, scenario_fname = $subscenario_fname");
#	        open(FILEHANDLE, ">$subscenario_fname") or die 'cannot open file';
#	        print FILEHANDLE "$subscenario_xml";
#	        close (FILEHANDLE);
	        
	        my $scp_command = "scp -2 $subscenario_fname root\@$host_ip:/tmp/";
	        &daemonize($scp_command, "$host_name"."_log");
	
	        my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $subscenario_fname\'";
	        &daemonize($permissions_command, "$host_name"."_log");
	        
	        print "\n  **** Stopping simulation and network restoring in $host_name ****\n";
	        my $option_M = "";
	        if ($vm_name){$option_M="-M $vm_name";}
	        my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx -v -P -f $subscenario_fname " . $option_M . "'";
	        &daemonize($ssh_command, "$host_name"."_log");  
        	
        	# update vm status in db
        	# TODO: update all vms when -M allows a list of vms
            my $error = query_db ("UPDATE vms SET status = 'inactive' WHERE name='$vm_name'");
            if ($error) { ediv_die ("$error") };
        	
        } else {
            wlog (V, "No subscenario entries found for scenario $vnx_scenario in host $host_id")        	
        }

        unless ($vm_name){
            #Clean vlans
            $error = query_db ("SELECT `number`, `external_if` FROM vlans WHERE host = '$host_name' AND simulation = '$scenario_name'", \@db_resp);
            if ($error) { ediv_die ("$error") };
            foreach my $vlans (@db_resp) {
                $vlan_command = $vlan_command . "vconfig rem $$vlans[1].$$vlans[0]\n";
            }
            $vlan_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip '$vlan_command'";
            &daemonize($vlan_command, "$host_name"."_log");
        }   

	}
}

#
# destroyScenario
#
# Subroutine to execute destroy mode in cluster
#
sub destroyScenario {
	
	my $host_ip;
	my $host_name;
    my $error;
    my @db_resp;
    
	my $scenario;
	foreach my $host_id (@cluster_active_hosts) {
			
		my $vlan_command;
        $host_ip   = get_host_ipaddr ($host_id);            
        $host_name = get_host_hostname ($host_id);
			
		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){
            unless ($host_name eq get_vm_host ($vm_name) ) {
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
		
        my $subscenario_name = get_host_subscenario_name ($host_name, $scenario_name);
        my $subscenario_fname = "/tmp/$subscenario_name".".xml";
        my $subscenario_xml = get_host_subscenario_xml ($host_name, $scenario_name, $subscenario_fname);
        if ( (defined($subscenario_name)) && (defined($subscenario_xml)) ) {
        
#			wlog (VVV, "** subscenario_name=$subscenario_name, scenario_fname = $subscenario_fname");
#			open(FILEHANDLE, ">$subscenario_fname") or die 'cannot open file';
#			print FILEHANDLE "$subscenario_xml";
#			close (FILEHANDLE);
	        		
			my $scp_command = "scp -2 $subscenario_fname root\@$host_ip:/tmp/";
			&daemonize($scp_command, "$host_name"."_log");
	
			my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $subscenario_fname\'";
			&daemonize($permissions_command, "$host_name"."_log");
					
			print "\n  **** Stopping simulation and network restoring in $host_name ****\n";
			my $option_M = "";
			if ($vm_name){$option_M="-M $vm_name";}
			my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx -v -d -f $subscenario_fname " . $option_M . "'";
			&daemonize($ssh_command, "$host_name"."_log");

            # update vm status in db
            # TODO: update all vms when -M allows a list of vms
            my $error = query_db ("UPDATE vms SET status = 'inactive' WHERE name='$vm_name'");
            if ($error) { ediv_die ("$error") };
				
        } else {
            wlog (V, "No subscenario entries found for scenario $vnx_scenario")         
        }

		unless ($vm_name){
			#Clean vlans
	        $error = query_db ("SELECT `number`, `external_if` FROM vlans WHERE host = '$host_name' AND simulation = '$scenario_name'", \@db_resp);
	        if ($error) { ediv_die ("$error") };
			foreach my $vlans (@db_resp) {
			     $vlan_command = $vlan_command . "vconfig rem $$vlans[1].$$vlans[0]\n";
			}
			$vlan_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip '$vlan_command'";
			&daemonize($vlan_command, "$host_name"."_log");
		}	
	}
}

#
# deleteTMP
#
# Subroutine to clean /tmp files
#
sub deleteTMP {
	my $host_ip;
	my $host_name;
	foreach my $host_id (@cluster_active_hosts) {
		
        $host_ip   = get_host_ipaddr ($host_id);            
        $host_name = get_host_hostname ($host_id);
        print "\n  **** Cleaning $host_name tmp directory ****\n";
		if (defined($conf_plugin_file)){
			my $rm_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'rm -rf /tmp/$scenario_name"."_$host_name.xml /tmp/conf.tgz /tmp/$conf_plugin_file'";
			&daemonize($rm_command, "$host_name"."_log");
		}else {
			my $rm_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'rm -rf /tmp/$scenario_name"."_$host_name.xml /tmp/conf.tgz'";
			# DFC comentado temporalmente...  &daemonize($rm_command, "/tmp/$host_name"."_log");
		}
	}			
}

#
# Subroutine to create tgz file with configuration of VMs
#
sub getConfiguration {
	
	wlog (VVV, "*** getConfiguration");
	
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
			   wlog (VVV, "*** getConfiguration: added $filetree");
			   push(@directories_list, $filetree);
			}
			
			#JSF añadido para tags <exec>
			my $execList = $currentVM->getElementsByTagName("exec");
			my $execListLength = $execList->getLength;
			for (my $m=0; $m<$execListLength; $m++){
			   my $exec = $execList->item($m)->getFirstChild->getData;
			   wlog (VVV, "*** getConfiguration: added $exec");
			   push(@exec_list, $exec);
			}
		
	}
	
	# Look for configuration files defined for dynamips vms
	my $extConfFile = $dh->get_default_dynamips();
	# If the extended config file is defined, look for <conf> tags inside
	if ($extConfFile ne '0'){
		$extConfFile = &get_abs_path ($extConfFile);
		wlog (VVV, "** extConfFile=$extConfFile");
		my $parser    = new XML::DOM::Parser;
		my $dom       = $parser->parsefile($extConfFile);
		my $conf_list = $dom->getElementsByTagName("conf");
   		for ( my $i = 0; $i < $conf_list->getLength; $i++) {
      		my $confi = $conf_list->item($i)->getFirstChild->getData;
			wlog (VVV, "*** adding dynamips conf file=$confi");
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

#
# sendConfiguration
#
# Subroutine to copy VMs execution mode configuration to cluster machines
#
sub sendConfiguration {
	if ($configuration == 1){
		print "\n\n  **** Sending configuration to cluster hosts ****\n\n";
		foreach my $host_id (@cluster_active_hosts) {	
	        my $host_ip   = get_host_ipaddr ($host_id);            
	        my $host_name = get_host_hostname ($host_id);
			my $tgz_name = "/tmp/conf.tgz";
			my $scp_command = "scp -2 $tgz_name root\@$host_ip:/tmp/";	
			system($scp_command);
			my $tgz_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'tar xzf $tgz_name -C /tmp'";
			&daemonize($tgz_command, "$host_name"."_log");
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
        foreach my $host_id (@cluster_active_hosts) {  
	        my $host_ip   = get_host_ipaddr ($host_id);            
	        my $host_name = get_host_hostname ($host_id);
            #my $dynamips_user_path = &get_abs_path ( $dom_tree->getElementsByTagName("dynamips_ext")->item(0)->getFirstChild->getData );
            my $dynamips_user_path = &get_abs_path ( $dh->get_doc->getElementsByTagName("dynamips_ext")->item(0)->getFirstChild->getData );
			print "** dynamips_user_path=$dynamips_user_path\n";
			#my $scp_command = "scp -2 $dynamips_user_path root\@$host_ip:$dynamips_ext_path".$filename."/dynamips-dn.xml";
			my $scp_command = "scp -2 $dynamips_user_path root\@$host_ip:/tmp/dynamips-dn.xml";
			system($scp_command);
		}
	}


	if ( defined($plugin) && defined($conf_plugin) ){
		print "\n\n  **** Sending configuration to cluster hosts ****\n\n";
		
		my $path;
		my @scenario_name_split = split("/",$vnx_scenario);
		my $scenario_name_split_size = @scenario_name_split;
		
		for (my $i=1; $i<($scenario_name_split_size -1); $i++){
			my $part = $scenario_name_split[$i];
			$path = "$path" .  "/$part";
		}
		
		unless (defined($path)) {
			$conf_plugin_file = $conf_plugin;
		} else{
			$conf_plugin_file = "$path" . "/" . "$conf_plugin";
		}
	
        foreach my $host_id (@cluster_active_hosts) {  
	        my $host_ip   = get_host_ipaddr ($host_id);            
	        my $host_name = get_host_hostname ($host_id);
			my $scp_command = "scp -2 $conf_plugin_file root\@$host_ip:/tmp";
			system($scp_command);
		}
		$configuration = 1;
	}
}


#
# executeConfiguration
#
# Subroutine to execute execution mode in cluster
#
sub executeConfiguration {

    my $error;
    my @db_resp;
    	
	if (!($configuration)){
		die ("This scenario doesn't support mode -x")
	}
	my $cmdseq = shift;
	my $dbh;
#	my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
    foreach my $host_id (@cluster_active_hosts) {  
        my $host_ip   = get_host_ipaddr ($host_id);            
        my $host_name = get_host_hostname ($host_id);
			
		# If vm specified with -M is not running in current host, check the next one.
		if ($vm_name){
            unless ($host_name eq get_vm_host ($vm_name) ) {
                next;
            }
		}
			
        my $subscenario_name = get_host_subscenario_name ($host_name, $scenario_name);
        my $subscenario_fname = "/tmp/$subscenario_name".".xml";
        my $subscenario_xml = get_host_subscenario_xml ($host_name, $scenario_name, $subscenario_fname);
        print "scenario bin:'$subscenario_xml'\n";
        print "subscenario name:'$subscenario_name'\n";
		
#		wlog (VVV, "** subscenario_name=$subscenario_name, scenario_fname = $subscenario_fname");
#		open(FILEHANDLE, ">$subscenario_fname") or die 'cannot open file';
#		print FILEHANDLE "$subscenario_xml";
#		close (FILEHANDLE);
 #       para();
	        		
		my $scp_command = "scp -2 $subscenario_fname root\@$host_ip:/tmp/";
		&daemonize($scp_command, "$host_name"."_log");
		my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $subscenario_fname\'";	
		&daemonize($permissions_command, "$host_name"."_log"); 		
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnx -f $subscenario_fname -v -x $cmdseq " . $option_M . "'"; 
		&daemonize($execution_command, "$host_name"."_log");
   }
}

#
# get_host_subscenario_xml
#
# Returns the subscenario XML specification for a host
# 
sub get_host_subscenario_xml {

    my $host_name = shift;
    my $subscenario_name = shift;
    my $subscenario_fname = shift;
    
    my $error;
    my @db_resp;
    
    $error = query_db ("SELECT `local_specification` FROM hosts WHERE host = '$host_name' " . 
                       "AND simulation = '$subscenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    if (defined($db_resp[0]->[0])) {

        if (defined($subscenario_fname)) {
            # Copy the XML to a $scenario_fname        	
            open(FILEHANDLE, "> $subscenario_fname") or die 'cannot open file';
            print FILEHANDLE "$db_resp[0]->[0]";
            close (FILEHANDLE);        	
        }
        return $db_resp[0]->[0];  
        
    } else {
    	wlog (N, "ERROR (get_host_subscenario_xml): cannot get subscenario xml " .
    	         "from database for scenario $scenario_name and host $host_name");
    	return undef;
    }
}

#
# get_host_subscenario_name
#
# Returns the subscenario XML specification for a host
# 
sub get_host_subscenario_name {

    my $host_name = shift;
    my $scenario_name = shift;
    my $error;
    my @db_resp;
    
    $error = query_db ("SELECT `local_simulation` FROM hosts WHERE host = '$host_name' " . 
                       "AND simulation = '$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    if (defined($db_resp[0]->[0])) {
        return $db_resp[0]->[0];  
    } else {
        wlog (N, "ERROR (get_host_subscenario_name): cannot get subscenario name from database for scenario $scenario_name and host $host_name");
        return undef;
    }
}


#
# tunnelize
#
# Subroutine to create tunnels to operate remote VMs from a local port
#
sub tunnelize {	

#	my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	my $localport = 64000;
	my $error;
	my @db_resp;

    #print "** %allocation:\n" . Dumper (%allocation) . "\n";

	foreach $vm_name (keys (%allocation)) {
		
		my $host_name = $allocation{$vm_name};

		# continue only if type of vm is "uml"
        $error = query_db ("SELECT `type` FROM vms WHERE name='$vm_name'", \@db_resp);
        if ($error) { ediv_die ("$error") };
        my $vm_type;
        if (defined($db_resp[0]->[0])) {
           $vm_type = $db_resp[0]->[0];  
        }
        wlog (VVV, "** $host_name, $vm_name, $vm_type");
		unless($vm_type eq "uml"){
			next;
		}	
		
		while (1){
	        $error = query_db ("SELECT `ssh_port` FROM vms WHERE ssh_port='$localport'", \@db_resp);
	        if ($error) { ediv_die ("$error") };
	        unless (defined($db_resp[0]->[0])) {
	           last;  
	        }
			$localport++;
			
		}
		system("ssh -2 -q -f -N -o \"StrictHostKeyChecking no\" -L $localport:$vm_name:22 $host_name");

        $error = query_db ("UPDATE vms SET ssh_port = '$localport' WHERE name='$vm_name'");
        if ($error) { ediv_die ("$error") };
		
		if ($localport > 65535) {
			die ("Not enough ports available but the simulation is running... you can't access to VMs using tunnels.");
		}	
	}
	
    $error = query_db ("SELECT `name`,`host`,`ssh_port` FROM vms WHERE simulation = '$scenario_name' ORDER BY `name`", \@db_resp);
    if ($error) { ediv_die ("$error") };
    foreach my $ports (@db_resp) {
        if (defined($$ports[2])) {
            print ("\tTo access VM $$ports[0] at $$ports[1] use local port $$ports[2]\n");
        }
    }
	print "\n\tUse command ssh -2 root\@localhost -p <port> to access VMs\n";
	print "\tOr ediv_console.pl console <simulation_name> <vm_name>\n";
	print "\tWhere <port> is a port number of the previous list\n";
	print "\tThe port list can be found running ediv_console.pl info\n";
	
}

#
# Subroutine to remove tunnels
#
sub untunnelize {
	
	my $error;
	my @db_resp;
	
	print "\n  **** Cleaning tunnels to access remote VMs ****\n\n";
#	my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
    $error = query_db ("SELECT `ssh_port` FROM vms WHERE simulation = '$scenario_name' ORDER BY `ssh_port`", \@db_resp);
    if ($error) { ediv_die ("$error") };
    foreach my $ports (@db_resp) {
        wlog (VVV, "ports=\n" . Dumper(@db_resp));
        my $kill_command = "kill -9 `ps auxw | grep -i \"ssh -2 -q -f -N\" | grep -i $$ports[0] | awk '{print \$2}'`";
        &daemonize($kill_command, "/dev/null");
    }
}

#
# Subroutine to launch background operations
#
sub daemonize {	
	print("\n");
    my $command = shift;
    my $output = shift;
    print("Backgrounded command:\n$command\n------> Log can be found at: $EDIV_LOGS_DIR/$output\n");
    defined(my $pid = fork)			or die "Can't fork: $!";
    return if $pid;
    chdir '/tmp'					or die "Can't chdir to /: $!";
    open STDIN, '/dev/null'			or die "Can't read /dev/null: $!";
    open STDOUT, ">>$EDIV_LOGS_DIR/$output"		or die "Can't write to $output: $!";
    open STDERR, ">>$EDIV_LOGS_DIR/$output"		or die "Can't write to $output: $!";
    setsid							or die "Can't start a new session: $!";
    system("$command") == 0			or print "ERROR: Could not execute $command!";
    exit();
}

#
# Subroutine to execute execution mode in cluster
#
sub processMode {
	
	my $error;
	my @db_resp;
	
	#my $cmdseq = shift;
	
    foreach my $host_id (@cluster_active_hosts) {  

        my $host_ip   = get_host_ipaddr ($host_id);            
        my $host_name = get_host_hostname ($host_id);
			
		# If vm specified with -M is not running in current host, check the next one.
	
		if ($vm_name){
            unless ($host_name eq get_vm_host($vm_name) ) {
                next;
            }
		}
	
		my $subscenario_xml = get_host_scenario_xml ($host_name, $scenario_name);
        my $subscenario_name = get_host_scenario_name ($host_name, $scenario_name);
		my $subscenario_fname = "/tmp/$subscenario_name".".xml";
		open(FILEHANDLE, ">$subscenario_fname") or die 'cannot open file';
		print FILEHANDLE "$subscenario_xml";
		close (FILEHANDLE);
		
		my $scp_command = "scp -2 $subscenario_fname root\@$host_ip:/tmp/";
		&daemonize($scp_command, "$host_name"."_log");
			
		my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $subscenario_fname\'";
			
		&daemonize($permissions_command, "$host_name"."_log"); 		
#VNX	my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnumlparser.pl -u root -v -x $cmdseq\@$scenario_name'";
		my $option_M = "";
		if ($vm_name){$option_M="-M $vm_name";}
		my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnx -f $subscenario_fname -v $mode " . $option_M . "'"; 
		&daemonize($execution_command, "$host_name"."_log");
    }
}

# TODO: delete and use Execution::pak
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
	
	print "---- initAndCheckVNXScenario called: $input_file\n";
   	my $vnx_dir = &do_path_expansion($DEFAULT_VNX_DIR);
   	my $tmp_dir = "/tmp";
   	#my $uid = $>;
   
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
        &ediv_die ("XML file ($input_file) validation failed:\n$error\n");
	}

   	# Create DOM tree and set globalNode and scenario name
	my $parser = new XML::DOM::Parser;
    my $dom_tree = $parser->parsefile($input_file);   	
    $globalNode = $dom_tree->getElementsByTagName("vnx")->item(0);
    $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;

    #print "**********************************************\n" . $dom_tree->toString;   
	# Build the VNX::Execution object
	#$execution = new VNX::Execution($vnx_dir,$exemode,"host> ",'',$uid);

   	# Calculate the directory where the input_file lives
   	my $xml_dir = (fileparse(abs_path($input_file)))[1];

	# Build the VNX::DataHandler object
   	$dh = new VNX::DataHandler($execution,$dom_tree,'','','',$xml_dir,$input_file);
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
	
    # if dynamips_ext node is present, update path
    $dynamips_ext_path = "";
    #my $dynamips_extTagList=$dom_tree->getElementsByTagName("dynamips_ext");
    my $dynamips_extTagList=$dh->get_doc->getElementsByTagName("dynamips_ext");
    my $numdynamips_ext = $dynamips_extTagList->getLength;
    if ($numdynamips_ext == 1) {
        my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
        $dynamips_ext_path = "$vnx_dir/scenarios/";
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
   printf "----------------------------------------------------------------------------------\n";
   printf "%s (%s): %s \n", (caller(1))[3], (caller(0))[2], $mess;
   printf "----------------------------------------------------------------------------------\n";
   exit 1;
}


####################
# usage
#
# Prints program usage message
sub usage {
    
    my $basename = basename $0;
    
my $usage = <<EOF;

Usage: ediv -f VNX_file [-t|--create] [-a segmentation_mode] [-c vnx_dir] 
                 [-T tmp_dir] [-i] [-w timeout] [-B]
                 [-e screen_file] [-4] [-6] [-v] [-g] [-M vm_list] [-D]
       ediv -f VNX_file [-x|--execute cmd_seq] [-T tmp_dir] [-M vm_list] [-i] [-B] [-4] [-6] [-v] [-g]
       ediv -f VNX_file [-d|--shutdown] [-c ediv_dir] [-F] [-T tmp_dir] [-i] [-B] [-4] [-6] [-v] [-g]
       ediv -f VNX_file [-P|--destroy] [-T tmp_file] [-i] [-v] [-g]
       ediv -f VNX_file [--define] [-M vm_list] [-v] [-i]
       ediv -f VNX_file [--start] [-M vm_list] [-v] [-i]
       ediv -f VNX_file [--undefine] [-M vm_list] [-v] [-i]
       ediv -f VNX_file [--save] [-M vm_list] [-v] [-i]
       ediv -f VNX_file [--restore] [-M vm_list] [-v] [-i]
       ediv -f VNX_file [--suspend] [-M vm_list] [-v] [-i]
       ediv -f VNX_file [--resume] [-M vm_list] [-v] [-i]
       ediv -f VNX_file [--reboot] [-M vm_list] [-v] [-i]
       ediv -f VNX_file [--reset] [-M vm_list] [-v] [-i]
       ediv -f VNX_file [--show-map] 
       ediv -f VNX_file [--show-map] [-a segmentation_mode] 
       ediv -h
       ediv -V

Main modes:
       -t|--create   -> build topology, or create virtual machine (if -M), using VNX_file as source.
       -x cmd_seq    -> execute the cmd_seq command sequence, using VNX_file as source.
       -d|--shutdown -> destroy current scenario, or virtual machine (if -M), using VNX_file as source.
       -P|--destroy  -> purge scenario, or virtual machine (if -M), (warning: it will remove cowed 
                        filesystems!)
       --define      -> define all machines, or the ones speficied (if -M), using VNX_file as source.
       --undefine    -> undefine all machines, or the ones speficied (if -M), using VNX_file as source.
       --start       -> start all machines, or the ones speficied (if -M), using VNX_file as source.
       --save        -> save all machines, or the ones speficied (if -M), using VNX_file as source.
       --restore     -> restore all machines, or the ones speficied (if -M), using VNX_file as source.
       --suspend     -> suspend all machines, or the ones speficied (if -M), using VNX_file as source.
       --resume      -> resume all machines, or the ones speficied (if -M), using VNX_file as source.
       --reboot      -> reboot all machines, or the ones speficied (if -M), using VNX_file as source.
    
Console management modes:
       --console-info       -> shows information about all virtual machine consoles or the 
                               one specified with -M option.
       --console-info -b    -> the same but the information is provided in a compact format
       --console            -> opens the consoles of all vms, or just the ones speficied if -M is used. 
                               Only the consoles defined with display="yes" in VNX_file are opened.
       --console --cid conX -> opens 'conX' console (being conX the id of a console: con0, con1, etc) 
                               of all vms, or just the ones speficied if -M is used.                              
       Examples:
            ediv -f ex1.xml --console
            ediv -f ex1.xml --console --cid con0 -M A --> open console 0 of vm A of scenario ex1.xml

Other modes:
       --show-map     -> shows a map of the network scenarios build using graphviz.
       --exe-info     -> show information about the commands available
       --seg-info     -> show scenario segmentation result (vm to cluster host mapping)
       --seg-alg-info -> show segmentation algorithms available

Pseudomodes:
       -V, show program version and exit.
       -H, show this help message and exit.

Options:
       -c vnx_dir      -> vnx working directory (default is ~/.vnx)
       -F              -> force stopping of UMLs (warning: UML filesystems may be corrupted)
       -w timeout      -> waits timeout seconds for a UML to boot before prompting the user 
                          for further action; a timeout of 0 indicates no timeout (default is 30)
       -B              -> blocking mode
       -e screen_file  -> make screen configuration file for pts devices
       -v              -> verbose mode on
       -vv             -> more verbose mode on
       -vvv            -> even more verbose mode on
       -T tmp_dir      -> temporal files directory (default is /tmp)
       -M vm_list      -> start/stop/restart scenario in vm_list (a list of names separated by ,)
       -C|--config cfgfile -> use cfgfile as configuration file instead of default one (/etc/vnx.conf)
       -D              -> delete LOCK file
       -n|--noconsole -> do not display the console of any vm. To be used with -t|--create options
       -y|--st-delay num -> wait num secs. between virtual machines startup (0 by default)

EOF


print "$usage\n";   

}

