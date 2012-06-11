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
use VNX::DocumentChecks;



###########################################################
# Global variables 
###########################################################
	
# Command line options hash
my %opts = ();
	
# Cluster
my $cluster_conf_file;					# Cluster conf file
	
# VLAN Assignment
my $firstVlan;         					# First VLAN number
my $lastVlan;          					# Last VLAN number

# Modes
my $partition_mode;						# Default partition mode
my $mode;								# Running mode
my $configuration;						# =1 if scenario has configuration files
my $no_console; 						# Stores the value of --no-console command line option
	
# Scenario
my $vnx_scenario;						# VNX scenario file name
my %scenario_hash; 						# Scenarios. Every scenario belongs to a host machine
										# Key -> host_id, Value -> XML Scenario							
my $scenario_name;						# Scenario name specified in XML 
my $doc;							    # Dom Tree with scenario specification
my $globalNode;							# Global node from dom tree
my $restriction_file;					# Static assigment file

my %allocation;							# Asignation of virtual machine - host_id

my @vms_to_split;						# VMs that haven't been assigned by static
my %static_assignment;					# VMs that have assigned by static

my @seg_plugins;						# Segmentation modules that are implemented
my $segmentation_module;

my $conf_plugin_file;					# Configuration plugin file
my $vnx_dir;
my $tmp_dir;

my $log_opt ='';                        # Log level option (passed qhen executing vnx remotely on hosts)

# Path for dynamips config file
#my $dynamips_ext_path;

$version = "MM.mm.rrrr"; # major.minor.revision
$release = "DD/MM/YYYY";
$branch = "";

my $hline = "---------------------------------------------------------------------------------------------";
my $SSH_POST_DELAY = 10;

&main;
exit(0);



###########################################################
# THE MAIN PROGRAM
#
sub main {

    my $check_hosts = 'yes'; 
    
	print "\n" . $hline . "\n";
	print "Distributed Virtual Networks over LinuX (EDIV) -- http://www.dit.upm.es/vnx - vnx\@dit.upm.es\n";
	print "Version: $version" . "$branch (built on $release)\n";
	print $hline . "\n";
	
	# Argument handling
    Getopt::Long::Configure ( qw{no_auto_abbrev no_ignore_case} ); # case sensitive single-character options
    GetOptions (\%opts,
                'define', 'undefine', 'start', 'create|t', 'shutdown|d', 'destroy|P',
                'save', 'restore', 'suspend', 'resume', 'reboot', 'reset', 'execute|x=s',
                'show-map', 'console:s', 'console-info', 'exe-info',
                'help|h', 'seg-info', 'seg-alg-info', 
                'check-cluster', 'clean-cluster', 'update-hosts',
                'v', 'vv', 'vvv', 'version|V',
                'f=s', 'C=s', 'a=s', 'r=s', 'M=s', 'H=s', 'n|no-console',
                'create-db', 'reset-db:s', 'delete-db',
                'y'
    ) or ediv_die("Incorrect usage. Type 'ediv -h' for help"); ;

	my $how_many_args = 0;
	if ($opts{'create'}) {
	    $how_many_args++; $mode = "create";	}
	if ($opts{'execute'}) {
	    $how_many_args++; $mode = "execute"; }
	if ($opts{'shutdown'}) {
		$how_many_args++; $mode = "shutdown"; }
	if ($opts{'destroy'}) {
	    $how_many_args++; $mode = "destroy"; }
	if ($opts{'version'}) {
	    $how_many_args++; $mode = "version"; }
	if ($opts{'help'}) {
	    $how_many_args++; $mode = "help"; }
	if ($opts{'define'}) {
	    $how_many_args++; $mode = "define"; }
	if ($opts{'start'}) {
	    $how_many_args++; $mode = "start"; }
	if ($opts{'undefine'}) {
	    $how_many_args++; $mode = "undefine"; }
	if ($opts{'save'}) {
	    $how_many_args++; $mode = "save"; }
	if ($opts{'restore'}) {
	    $how_many_args++; $mode = "restore"; }
	if ($opts{'suspend'}) {
	    $how_many_args++; $mode = "suspend"; }
	if ($opts{'resume'}) {
	    $how_many_args++; $mode = "resume";	}
	if ($opts{'reboot'}) {
	    $how_many_args++; $mode = "reboot";	}
	if ($opts{'reset'}) {
	    $how_many_args++; $mode = "reset"; }
	if ($opts{'show-map'}) {
	    $how_many_args++; $mode = "show-map"; $check_hosts = 'no' }
	if (defined($opts{'console'})) {
		$how_many_args++; $mode = "console"; }
	if ($opts{'console-info'}) {
	    $how_many_args++; $mode = "console-info"; }
    if ($opts{'exe-info'}) {
        $how_many_args++; $mode = "exe-info"; $check_hosts = 'no' }
    if ($opts{'seg-info'}) {
        $how_many_args++; $mode = "seg-info"; }
    if ($opts{'seg-alg-info'}) {
        $how_many_args++; $mode = "seg-alg-info"; $check_hosts = 'no' }
    if ($opts{'check-cluster'}) {
        $how_many_args++; $mode = "check-cluster"; }
    if ($opts{'clean-cluster'}) {
        $how_many_args++; $mode = "clean-cluster"; }
    if ($opts{'update-hosts'}) {
        $how_many_args++; $mode = "update-hosts"; }
    if ($opts{'create-db'}) {
        $how_many_args++; $mode = "create-db"; $check_hosts = 'no' }
    if (defined($opts{'reset-db'})) { 
        $how_many_args++; $mode = "reset-db";  $check_hosts = 'no' }
    if ($opts{'delete-db'}) {
        $how_many_args++; $mode = "delete-db"; $check_hosts = 'no' }
	  
	if ($how_many_args gt 1) {
	    &usage;
	    ediv_die ("Only one of the following at a time: -t|--create, -x|--execute, -d|--shutdown," . 
	               " -V, -P|--destroy, --define, --start, --undefine, --save, --restore, --suspend," .
	               " --resume, --reboot, --reset, --showmap, --seg-info, --check-cluster, " . 
	               "--clean-cluster, --update-hosts, --create-db, --reset-db, --delete-db or -H\n");
	}
    if ($how_many_args lt 1)  {
        &usage;
        ediv_die ("missing -t|--create, -x|--execute, -d|--shutdown, -V, -P|--destroy, --define, --start," .
                  " --undefine, \n--save, --restore, --suspend, --resume, --reboot, --reset, --show-map," . 
                  "--console, --console-info, --seg-info, --check_cluster, --clean-cluster, --update-hosts, " .
                   " --create-db, --reset-db, --delete-db or -H\n");
    }
	
    # Version pseudomode
    if ($opts{'version'}) {
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
    if ($opts{'help'}) {
        &usage;
        exit(0);
    }

    # 2. Optional arguments
    $exemode = $EXE_NORMAL; $EXE_VERBOSITY_LEVEL=N;
    if ($opts{v})   { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=V;   $log_opt = '-v'   }
    if ($opts{vv})  { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=VV;  $log_opt = '-vv'  }
    if ($opts{vvv}) { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=VVV; $log_opt = '-vvv' }
    #$exemode = $EXE_DEBUG if ($opts{g);

    # Create logs directory if not already created
	system ("mkdir -p $EDIV_LOGS_DIR");

    # Set VNX and TMP directories
    $tmp_dir=&get_conf_value ($vnxConfigFile, 'general', 'tmp_dir');
    if (!defined $tmp_dir) {
        $tmp_dir = $DEFAULT_TMP_DIR;
    }
    print "  TMP dir=$tmp_dir\n";
    $vnx_dir=&get_conf_value ($vnxConfigFile, 'general', 'vnx_dir');
    if (!defined $vnx_dir) {
        $vnx_dir = &do_path_expansion($DEFAULT_VNX_DIR);
    } else {
        $vnx_dir = &do_path_expansion($vnx_dir);
    }
    print "  VNX dir=$vnx_dir\n";
    print $hline . "\n";
    # To check vnx_dir and tmp_dir
    # Create the working directory, if it doesn't already exist
    if (! -d $vnx_dir ) {
        mkdir $vnx_dir or &ediv_die("Unable to create working directory $vnx_dir: $!\n");
    }
    ediv_die ("vnx_dir $vnx_dir does not exist or is not readable/executable\n") unless (-r $vnx_dir && -x _);
    ediv_die ("vnx_dir $vnx_dir is not writeable\n") unless ( -w _);
    ediv_die ("vnx_dir $vnx_dir is not a valid directory\n") unless (-d _);
    if (! -d "$vnx_dir/scenarios") {
        mkdir "$vnx_dir/scenarios" or &ediv_die("Unable to create scenarios directory $vnx_dir/scenarios: $!\n");
    }
    if (! -d "$vnx_dir/networks") {
        mkdir "$vnx_dir/networks" or &ediv_die("Unable to create networks directory $vnx_dir/networks: $!\n");
    }
    ediv_die ("tmp_dir $tmp_dir does not exist or is not readable/executable\n") unless (-r $tmp_dir && -x _);
    ediv_die ("tmp_dir $tmp_dir is not writeable\n") unless (-w _);
    ediv_die ("tmp_dir $tmp_dir is not a valid directory\n") unless (-d _);
	
    # Set scenario 
    if ($opts{f}) {
        $vnx_scenario = $opts{f}; 
        print "Using scenario:               $vnx_scenario\n";
    }
    unless ( ($opts{'version'}) or ($opts{'help'}) or ($opts{'seg-alg-info'}) or ($opts{'clean-cluster'})
            or ($opts{'check-cluster'}) or ($opts{'update-hosts'}) or ($opts{'create-db'} 
            or ( defined($opts{'reset-db'}) ) or ($opts{'delete-db'}) ) or (-e $vnx_scenario)) {
        ediv_die ("ERROR: scenario xml file not specified (missing -f option) or not found");
    }
    
    # Set configuration file 
    if ($opts{C}) {
        $cluster_conf_file = $opts{C}; 
    } else {
        $cluster_conf_file = $DEFAULT_CLUSTER_CONF_FILE;
    }
    unless (-e $cluster_conf_file) {
        ediv_die ("ERROR: Cluster configuration file ($cluster_conf_file) not found");
    } else {
        print "Using configuration file:     $cluster_conf_file\n";
    }
    
    # Read cluster configuration file
    if (my $res = read_cluster_config($cluster_conf_file, $check_hosts)) { 
        print "ERROR: $res\n";  
        exit 1; 
    }
    unless ($check_hosts eq 'no') {
	    print "Hosts in cluster:\n";
	    foreach my $host_id (@cluster_hosts) {
	        my $active_host_found;
	        my $status = 'inactive';
	        foreach my $active_host (@cluster_active_hosts) {
	            if ($active_host eq $host_id) { $status = 'active';}
	        }
	        my $msg = sprintf ("    %-24s (%s) vnx_ver=%s", $host_id, $status, get_host_vnxver($host_id));
	        print $msg . "\n";
	    }
	    print "\n";    	
    }

    # Set segmentation algorithm
    if ($opts{a}) {
        $partition_mode = $opts{a}; 
    } else {
        $partition_mode = $cluster->{def_seg_alg};
    }
    print "Using segmentation algorithm: $partition_mode\n";
    print $hline . "\n";

    # Search for static assigment file
    if ($opts{r}) {
        $restriction_file = $opts{r}; 
        unless ( (-e $restriction_file) or ($opts{'version'}) or ($opts{'help'}) ) {
            print "\nERROR: The restriction file $restriction_file doesn't exist... Aborting\n\n";
            exit(1);
        }     
        print "Using restriction file: $restriction_file\n";
    }

    # Search for -n|--no-console tag
    $no_console = '';
    if ($opts{n}) {
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
    unless ( ($mode eq 'seg-alg-info')  or ($mode eq 'check-cluster') or ($mode eq 'clean-cluster') 
             or ($opts{'update-hosts'}) or ($opts{'show-map'})  or ($opts{'exe-info'})  
             or ($mode eq 'create-db')  or ( ($mode eq 'reset-db') && (! $opts{'f'}) ) 
             or ($mode eq 'delete-db')  ) {
	    # init global objects and check VNX scenario correctness 
	    initialize_and_check_scenario ($vnx_scenario); 
    }

    # -M option: check that all vms specified exist in the scenario
    # Not needed; already done in CheckSemantics 

    # -H option: check that host specified exist  
    if ($opts{H}) {

        my @hosts_list = split (/,/, $opts{H});
        foreach my $host (@hosts_list) {
            #print "Checking $host\n";
            my $host_found;
            # Check whether the host exists
            foreach my $host_id (@cluster_hosts) {
                #print "$host_id\n";
                if ($host eq $host_id) { $host_found = 'true'}
            }
            if (!$host_found) {
                ediv_die ("host $host specified in -H option does not exist in cluster")
            }
            # Check whether the host is active
            my $active_host_found;
            foreach my $host_id (@cluster_active_hosts) {
                #print "active:$host_id\n";
                if ($host eq $host_id) { $active_host_found = 'true'}
            }
            if (!$active_host_found) {
                ediv_die ("host $host specified in -H option is not active")
            }           
        }
    }

	# Call mode handler
	if      ( $mode eq 'create' )        { mode_create();
	} elsif ( $mode eq 'execute' )       { mode_execute()
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
    } elsif ( $mode eq 'console' )       { mode_console();
    } elsif ( $mode eq 'console-info' )  { mode_consoleinfo();
    } elsif ( $mode eq 'exe-info' )      { mode_exeinfo();
    } elsif ( $mode eq 'seg-info' )      { mode_seginfo();
    } elsif ( $mode eq 'seg-alg-info' )  { mode_segalginfo();
    } elsif ( $mode eq 'check-cluster' ) { mode_checkcluster();
    } elsif ( $mode eq 'clean-cluster' ) { mode_cleancluster();
    } elsif ( $mode eq 'update-hosts' )  { mode_updatehosts();
    } elsif ( $mode eq 'show-map' )      { mode_showmap();
    } elsif ( $mode eq 'create-db' )     { mode_createdb();
    } elsif ( $mode eq 'reset-db' )      { mode_resetdb();
    } elsif ( $mode eq 'delete-db' )     { mode_deletedb();
	} else {
		# default action: die
		ediv_die ("ERROR: Unknown mode ($mode)\n");
	}
	
    wlog (N, "");
    #wlog (N, "\n---- Succesfully finished ----\n");
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
    #&parseScenario ($vnx_scenario);
    
    # Checking if the scenario already exists
    $error = query_db ("SELECT `name` FROM scenarios WHERE name='$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };

    if ( ( $opts{M} || $opts{H} ) && !defined($db_resp[0]->[0])) {
        
        # ERROR: trying to start a set of VMS of a non-existent scenario
        ediv_die ("ERROR: Scenario $scenario_name is not started. \nCannot use -M or -H options over a non existent scenario.");
        
    } elsif ( ( !$opts{M} && !$opts{H} ) && defined($db_resp[0]->[0]) ) {
        
        # ERROR: trying to create an already existent scenario
        ediv_die ("ERROR: Scenario $scenario_name was already created.");
        
    } elsif ( ( !$opts{M} && !$opts{H} ) && !defined($db_resp[0]->[0])) {
        
        # Creating a new scenario
        $error = query_db ("INSERT INTO scenarios (name,automac_offset,mgnet_offset) VALUES ('$scenario_name','0','0')");
        if ($error) { ediv_die ("$error") };
        
	    # Segmentation processing
	    if (defined($restriction_file)){
	        wlog (VV, "\n  -- Processing segmentation restriction file $restriction_file...\n");
            my $restriction = static->new($restriction_file, $dh->get_doc, @cluster_active_hosts); 
	        %static_assignment = $restriction->assign();
	        if ($static_assignment{"error"} eq "error"){
	            delete_scenario_from_database ($scenario_name);
	            ediv_die("ERROR processing segmentation restriction file");
	        }
	        @vms_to_split = $restriction->remaining();
	    }
	        
	    wlog (VV, "\n  ---- Calling $partition_mode segmentator...\n");
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
	        delete_scenario_from_database ($scenario_name);
	        ediv_die("ERROR: segmentator module $partition_mode not found");
	    }
	        
        my $doc = $dh->get_doc;
        %allocation = $segmentation_module->split(\$doc, \@cluster_active_hosts, \$cluster, \@vms_to_split, \%static_assignment);

        print_vms_allocation();
        #wlog (V, Dumper (%allocation));
	        
	    if (defined($allocation{"error"})){
	            delete_scenario_from_database ($scenario_name);
	            ediv_die("ERROR calling $partition_mode->split function");
	    }

       foreach my $vm (keys(%allocation)) {
            wlog (V, "---- $vm --> $allocation{$vm}")
       }
	        
	    wlog (N, "\n---- Configuring distributed networking in cluster");
	            
	    # Fill the scenario array
	    create_subscenario_docs('yes');
        # Assign first and last VLAN.
        &assignVLAN;
	    # Split into files
	    wlog (VVV, "\n----   Calling fill_subscenario_docs...");
	    fill_subscenario_docs ('yes');
	    # Make a tgz compressed file containing VM execution config 
	    build_scenario_conf();
	    # Send Configuration to each host.
	    send_conf_files();
	    #jsf: código copiado a sub send_conf_files, borrar esta subrutina.    
	    # Send dynamips configuration to each host.
	    #&sendDynConfiguration;
	    wlog (N, "\n----   Sending scenario to cluster hosts and executing it\n");
	    # Send scenario files to the hosts and run them with VNX (-t option)
	    send_and_start_subscenarios();
	      
        # Check if every VM is running and ready
        wlog (N, "\n----   Checking scenario status\n");
        checkFinish();
	            
        # Create a ssh tunnel to access remote VMs
        tunnelize();
        
    } elsif ( ( $opts{M} || $opts{H} ) && defined($db_resp[0]->[0])) {

        #
        # Creating one or more VMs specified with -M or -H options over an existent scenario 
        #
        
        # Get VMs asignation to hosts from the database
        %allocation = get_allocation_from_db();
        
        # Check that all vms in -M and -H option exist and are in inactive state
        my @vms = ediv_get_vm_to_use_ordered(); # List of VMs involved (taking into account -M and -H options)
        for ( my $i = 0; $i < @vms; $i++) {
            
            my $vm = $vms[$i];
            my $vm_name = $vm->getAttribute("name");
	        # Check the status of the vm
	        # If it is already started, finish with an error
	        # VM status: inactive, active, suspended, hibernated
	        $error = query_db ("SELECT `status` FROM vms WHERE name = '$vm_name' AND scenario = '$scenario_name'", \@db_resp);
	        if ($error) { ediv_die ("$error") };
	        if (defined($db_resp[0]->[0])) { 
	            if ( $db_resp[0]->[0] ne 'inactive' ) {
	                ediv_die("\nERROR: virtual machine $vm_name specified with '-M' or '-H'" . 
	                         " option not inactive (status=$db_resp[0]->[0])"); 
	            }
	        } else {
	            ediv_die("ERROR: virtual machine $vm_name specified with '-M' or '-H' option not found"); 
	        }      
        }
        
        my %hosts_involved = get_hosts_involved();
        
        foreach my $host_id (keys %hosts_involved) {
	        
	        # Start the vms located on that host 
            my $host_ip = get_host_ipaddr ($host_id);       
            my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/";
	        my $subscenario_name = get_host_subscenario_name ($host_id, $scenario_name);
            my $local_subscenario_fname = $dh->get_sim_tmp_dir . "/$subscenario_name".".xml";
            my $host_subscenario_fname = $host_tmpdir . "$subscenario_name".".xml";
	        my $subscenario_xml = get_host_subscenario_xml ($host_id, $scenario_name, $local_subscenario_fname);

            wlog (VVV, "--  mode_create: host_id = $host_id, host_ip = $host_ip, host_tmpdir = $host_tmpdir");  
            wlog (VVV, "--  mode_create: subscenario_name = $subscenario_name");  
            wlog (VVV, "--  mode_create: local_subscenario_fname = $local_subscenario_fname");  
            wlog (VVV, "--  mode_create: host_subscenario_fname = $host_subscenario_fname");  

	        unless  ( defined($subscenario_name) && defined($subscenario_xml) ) {
	        	ediv_die ("Cannot get subscenario name or subscenario XML file")
	        }
	        
	        my $scp_command = "scp -2 $local_subscenario_fname root\@$host_ip:$host_tmpdir";
	        &daemonize($scp_command, "$host_id".".log");
	        my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $host_subscenario_fname\'";
	        &daemonize($permissions_command, "$host_id".".log");
	        my $option_M = "-M $hosts_involved{$host_id}";
	        my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx $log_opt -t -f $host_subscenario_fname " . $option_M . "; sleep $SSH_POST_DELAY'";
	        &daemonize($ssh_command, "$host_id".".log");  
        }   

        # Update vm status in db
        for ( my $i = 0; $i < @vms; $i++) {
            my $vm_name = $vms[$i]->getAttribute("name");
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

    # Get VMs asignation to hosts from the database
    %allocation = get_allocation_from_db();
    
    # Checking if the scenario is running
    $error = query_db ("SELECT `scenario` FROM hosts WHERE status = 'running' AND scenario = '$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        ediv_die ("The scenario $scenario_name wasn't running... Aborting");
    }       
        
    # If no -M or -H option, mark scenario as "destroying"
    unless ($opts{M} || $opts{H}){
        $error = query_db ("UPDATE hosts SET status = 'destroying' WHERE status = 'running' AND scenario = '$scenario_name'");
        if ($error) { ediv_die ("$error") };
    }
    
    # Make a tgz compressed file containing VM execution config 
    build_scenario_conf();
        
    # Send Configuration to each host.
    send_conf_files();
        
    # Clear ssh tunnels to access remote VMs
    untunnelize();
        
    # Purge the scenario
    &shutdown_scenario;
    sleep(5);
    
    unless ($opts{M} || $opts{H}) {      
        # Clean scenario from database
        delete_scenario_from_database ($scenario_name);
            
        # Delete files
        delete_dirs();
    }
}

sub mode_destroy {

    my $error;
    my @db_resp;
        
    # Clean and purge scenario temporary files
    wlog (N, "\n---- mode: $mode\n---- Purging scenario $vnx_scenario");

    # Get VMs asignation to hosts from the database
    %allocation = get_allocation_from_db();
        
    # Checking if the scenario is running
    $error = query_db ("SELECT `name` FROM scenarios WHERE name='$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        ediv_die ("The scenario $scenario_name wasn't running... Aborting");
    }

    # If no -M or -H option, mark scenario as "purging"
    unless ($opts{M} || $opts{H}) {      
        $error = query_db ("UPDATE hosts SET status = 'purging' WHERE status = 'running' AND scenario = '$scenario_name'");
        if ($error) { ediv_die ("$error") };
    }
        
    # Make a tgz compressed file containing VM execution config 
    build_scenario_conf();
        
    # Send Configuration to each host.
    send_conf_files();
        
    # Clear ssh tunnels to access remote VMs
    untunnelize();
        
    # Purge the scenario
    &purge_scenario;
    sleep(5);
        
    unless ($opts{M} || $opts{H}) {      
        # Clean scenario from database
        delete_scenario_from_database ($scenario_name);
         
        # Delete files
        delete_dirs('all');

        # Delete scenario directory  
        $execution->execute($bd->get_binaries_path_ref->{"rm"} . " -rf $vnx_dir/scenarios/$scenario_name/*");
        
    }
}

sub mode_execute {

    my $error;
    my @db_resp;
    
    # Execution of commands in VMs mode
    if (!defined($opts{'execute'})) {
        ediv_die ("You must specify the command tag to execute\n");
    }
    wlog (N, "\n---- mode: $mode\n---- Executing commands tagged with '$opts{'execute'}'");

    # Get VMs asignation to hosts from the database
    %allocation = get_allocation_from_db();
        
    # Parse scenario XML
    #&parseScenario;

    # Checking if the scenario is running
    $error = query_db ("SELECT `scenario` FROM hosts WHERE status = 'running' AND scenario = '$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        ediv_die ("The scenario $scenario_name wasn't running... Aborting");
    }
        
    # Make a tgz compressed file containing VM execution config 
    build_scenario_conf();
        
    # Send Configuration to each host.
    send_conf_files();
        
    # Send Configuration to each host.
    wlog (N, "\n---- Sending commands to VMs\n");
    execute_command($opts{'execute'});
	
}

sub mode_others {

    my $error;
    my @db_resp;

    # Processing VMs mode
    wlog (N, "\n---- mode: $mode\n---- ");

    # Get VMs asignation to hosts from the database
    %allocation = get_allocation_from_db();
        
    # quizá el define se podría usar sin la simulacion creada ya, sobraria aqui 
    # Checking if the scenario is running
    $error = query_db ("SELECT `scenario` FROM hosts WHERE status = 'running' AND scenario = '$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        ediv_die ("The scenario $scenario_name wasn't running... Aborting");
    }       
        
    # Make a tgz compressed file containing VM execution config 
    build_scenario_conf();
        
    # Send Configuration to each host.
    send_conf_files();
        
    # Process mode defined in $mode
    &process_other_modes;
}

sub mode_console {

    my $error;
    my @db_resp;
    my $host_ip;
    my $host_id;
    my $scenario;
    
    wlog (N, "\n---- mode: $mode\n---- Executing commands tagged with '$opts{'execute'}'");

    # Get VMs asignation to hosts from the database
    %allocation = get_allocation_from_db();
        
    # Checking if the scenario is running
    $error = query_db ("SELECT `scenario` FROM hosts WHERE status = 'running' AND scenario = '$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        ediv_die ("The scenario $scenario_name wasn't running... Aborting");
    }

    my %hosts_involved = get_hosts_involved();

    foreach my $host_id (keys %hosts_involved) {

        my $host_ip = get_host_ipaddr ($host_id);       
        my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/";
        my $subscenario_name = get_host_subscenario_name ($host_id, $scenario_name);
        my $local_subscenario_fname = $dh->get_sim_tmp_dir . "/$subscenario_name".".xml";
        my $host_subscenario_fname = $host_tmpdir . "$subscenario_name".".xml";
        my $subscenario_xml = get_host_subscenario_xml ($host_id, $scenario_name, $local_subscenario_fname);

        wlog (VVV, "--  mode_console: host_id = $host_id, host_ip = $host_ip, host_tmpdir = $host_tmpdir");  
        wlog (VVV, "--  mode_console: subscenario_name = $subscenario_name");  
        wlog (VVV, "--  mode_console: local_subscenario_fname = $local_subscenario_fname");  
        wlog (VVV, "--  mode_console: host_subscenario_fname = $host_subscenario_fname");  

        unless ( defined($subscenario_name) && defined($subscenario_xml) ) {
            ediv_die ("Cannot get subscenario name or subscenario XML file")
        }

        # Copy subscenario to host
        my $scp_command = "scp -2 $local_subscenario_fname root\@$host_ip:$host_tmpdir";
        &daemonize($scp_command, "$host_id".".log");
        my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $host_subscenario_fname\'";
        &daemonize($permissions_command, "$host_id".".log");

        # Execute VNX console command
        print "\n  ---- Console command in $host_id\n";
        my $option_M = '';
        if ($opts{M} || $opts{H}) { $option_M = "-M $hosts_involved{$host_id}"; }

        my $console_options = "--console";
        if ($opts{'console'} ne '') {
            $console_options .= " $opts{'console'}";
        }
        my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx $log_opt $console_options -f $host_subscenario_fname " . $option_M . "; sleep $SSH_POST_DELAY'";
        &daemonize($ssh_command, "$host_id".".log");  

    }
}

sub mode_consoleinfo {

    wlog (N, "\n---- mode: $mode\n---- Sorry, not implemented yet...");

	
}

sub mode_seginfo {

    # Show segmentation info
    wlog (N, "\n---- mode: $mode\n---- Showing vm's to host mapping for $vnx_scenario");
       
    # Segmentation processing
    if (defined($restriction_file)){
        wlog (VV, "\n  ---- Calling static processor...\n");
        #my $restriction = static->new($restriction_file, $doc, @cluster_active_hosts); 
        my $restriction = static->new($restriction_file, $dh->get_doc, @cluster_active_hosts); 
        
        %static_assignment = $restriction->assign();
        if ($static_assignment{"error"} eq "error"){
            #delete_scenario_from_database ($scenario_name);
            ediv_die("ERROR processing segmentation restrictions file");
        }
        @vms_to_split = $restriction->remaining();
    }
        
    wlog (VV, "\n  ---- Calling segmentator...\n");
   
    # Look for the segmentation module selected and load it 
    push (@INC, "$EDIV_SEG_ALGORITHMS_DIR");
    foreach my $plugin (@seg_plugins){
            
        wlog (VV, " ----   plugin = $plugin");
            
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
       delete_scenario_from_database ($scenario_name);
       ediv_die('Segmentator: your choice ' . "$partition_mode" . " is not a recognized option (yet)");
    }
    
    my $doc = $dh->get_doc;
    %allocation = $segmentation_module->split(\$doc, \@cluster_active_hosts, \$cluster, \@vms_to_split, \%static_assignment);
        
    if (defined($allocation{"error"})){
        ediv_die("ERROR: in segmentation module  $segmentation_module");
    }
    print_vms_allocation();
    
    create_subscenario_docs();
    assignVLAN();
    fill_subscenario_docs();
    foreach my $host_id (@cluster_active_hosts) {
        my $local_subscenario_fname = $dh->get_sim_tmp_dir . $scenario_name . "_" . $host_id . ".xml"; 
        my $host_subdoc = $scenario_hash{$host_id};      
        $host_subdoc->printToFile("$local_subscenario_fname");
    }
}

sub mode_segalginfo {

    # Show segmentation algorithms available
    wlog (N, "\n---- mode: $mode\n---- Showing segmentation algorithms available");

    my $msg = sprintf ("\n     %-24s --> %s", "Algorithm name", "Filename"); wlog (N, $msg);
    wlog (N, "     --------------------------------------------------------------------------------");

    push (@INC, "$EDIV_SEG_ALGORITHMS_DIR");
    foreach my $plugin (@seg_plugins){
         require $plugin;
         import  $plugin;
         my @module_name_split = split(/\./, $plugin);
         my $plugin_withoutpm = $module_name_split[0];
         my $plugin_name = $plugin_withoutpm->name();
         my $msg = sprintf ("     %-28s --> %s", $plugin_name, "$EDIV_SEG_ALGORITHMS_DIR/$plugin");
        wlog (N, $msg);
    }  	
}

sub mode_checkcluster {
	
	# Nothing to do
    wlog (N, "\n---- mode: $mode\n---- Cluster status checked");	
	
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
    wlog (N, "----   - destroy all virtual machines in hosts");
    wlog (N, "----   - delete .vnx directories in hosts");
    wlog (N, "----   - restart libvirt daemon");
    wlog (N, "----   - restart dynamips daemon");    
    wlog (N, "----   - delete EDIV database content");
    if ($opts{H}) {    
        wlog (N, "---- Hosts affected:  " .$opts{H});
    } else {
    	$" = ", ";
        wlog (N, "---- Hosts affected:  @cluster_active_hosts");
    }
    wlog (N, "---- Do you want to continue (yes/no)? ");
    my $line = readline(*STDIN);
    unless ( $line =~ /^yes/ ) {
        wlog (N, "---- Cluster status NOT modified. Exiting");
    } else {

        wlog (N, "---- Restarting cluster status...");
        foreach my $host_id (@cluster_active_hosts){

	        if ($opts{H}) { 
	            my $host_list = $opts{H};
	            unless ($host_list =~ /^$host_id,|,$host_id,|,$host_id$|^$host_id$/) {
	                wlog (N, "----   Host $host_id skipped (not listed in -H option)");
	                next;
	            }
	        }                    

            my $host_ip   = get_host_ipaddr ($host_id);
            my $vnx_dir = get_host_vnxdir ($host_id);
            my $hypervisor = get_host_hypervisor ($host_id);
             
            wlog (N, "---- Host $host_id:");

            my $ssh_cmd = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip 'vnx --clean-host --yes'";
            wlog (N, "----     executing 'vnx --clean-host --yes' in $host_id");  
            system "$ssh_cmd >> /var/log/vnx/$host_id.log 2>&1 ";

=BEGIN
            wlog (N, "----   Killing ALL libvirt virtual machines...");

            # get all virtual machines running with "virsh list"
            # kill then with "virsh destroy vmname" 
            my @virsh_list;
            my $i;
            my $pipe = "ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'virsh -c $hypervisor list' |";
            open VIRSHLIST, "$pipe";
            while (<VIRSHLIST>) {
            	#print "******* $_\n";
                chomp; $virsh_list[$i++] = $_;
            }
            close VIRSHLIST;
            # Ignore first two lines (caption)
            for ( my $j = 2; $j < $i; $j++) {
                $_ = $virsh_list[$j];
                #print "-- $_\n";
                #/^\s+(\S+)\s+(\S+)\s+(\S+)/;
                my @fields = split (/ /, $_);
                #print "-- '$fields[0]' '$fields[1]' '$fields[2]'\n";
                if (defined ($fields[1])) {
                    my $ssh_cmd = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip 'virsh destroy $fields[1]'";
                    wlog (N, "----     killing vm $fields[1] at host $host_id");  
                    system "$ssh_cmd >> /var/log/vnx/$host_id.log 2>&1 ";
                }
            }

            # get all virtual machines in "shut off" state with "virsh list --all"
            # kill then with "virsh undefine vmname" 
            @virsh_list = qw ();
            $i = 0;
            $pipe = "ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'virsh -c $hypervisor list --all' |";
            open VIRSHLIST, "$pipe";
            while (<VIRSHLIST>) {
                chomp; $virsh_list[$i++] = $_;
            }
            close VIRSHLIST;
            # Ignore first two lines (caption)
            for ( my $j = 2; $j < $i; $j++) {
                $_ = $virsh_list[$j];
                /^\s+(\S+)\s+(\S+)\s+(\S+)/;
                if (defined ($2)) {
                    my $ssh_cmd = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip 'virsh undefine $2'";
                    wlog (N, "----     undefining vm $2 at host $host_id");
                    system "$ssh_cmd >> /var/log/vnx/$host_id.log 2>&1 ";
                }
            }
                
            wlog (N, "----   Killing UML virtual machines...");
            my $pids = `ssh pasito "(ps uaxw | grep linux | grep scenarios | grep ubd | grep umid | grep -v grep) | awk '{ print \$2 }'"`;
            print "$pids\n";
            #my $kill_command = 'killall linux scenarios ubd umid';
            #my $kill = `ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip $kill_command`;
            #system ($kill);
            
            wlog (N, "----   Restarting dynamips daemon at host $host_id");  
            my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip '/etc/init.d/dynamips restart'";
            &daemonize($ssh_command, "$host_id".".log");       

            wlog (N, "----   Deleting .vnx directories...");
            if (defined($vnx_dir)) {
                my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip 'rm -rf $vnx_dir/../.vnx/*'";
                &daemonize($ssh_command, "$host_id".".log");       
            }
=END
=cut


        }           

        wlog (N, "---- Deleting EDIV database...");
        reset_database();
    }
}

sub mode_updatehosts {

    my $error;
    my @db_resp;
    my $VNX_TARFILE = "/usr/share/vnx/src/vnx-latest.tgz";
    
    # Update VNX in cluster hosts
    wlog (N, "\n---- mode: $mode\n---- Updating VNX software in cluster hosts:");
    if ($opts{H}) {
        wlog (VVV, "----   option -H $opts{H}", ""); 
    }

    unless (-e "$VNX_TARFILE") {
    	ediv_die ("Cannot update VNX in cluster hosts. $VNX_TARFILE file not found.")
    } 

    #my $controller_id = `hostid`; chomp ($controller_id);
    wlog (V, "----   Controller id = " . $cluster->{controller_id}, "");

    foreach my $host_id (@cluster_active_hosts){

        if ($opts{H}) {
            my $host_list = $opts{H};
            unless ($host_list =~ /^$host_id,|,$host_id,|,$host_id$|^$host_id$/) {
                wlog (N, "----   Host $host_id skipped (not listed in -H option)");
                next;
            }
        }                    
        my $host_ip   = get_host_ipaddr ($host_id);
        my $vnx_dir = get_host_vnxdir ($host_id);
        my $hypervisor = get_host_hypervisor ($host_id);
        my $server_id = get_host_serverid ($host_id);

        if ($server_id eq $cluster->{controller_id}) {
        	# The cluster controller is also a cluster host. Do not update it!!
            wlog (N, "----   Host $host_id ($server_id): skipped (it is the controller)");
            next;        	 
        }            
        wlog (N, "----   Host $host_id ($server_id): updating VNX... ");
        # Create 
        my $host_tmp = get_host_tmpdir($host_id);
        my $update_dir = "$host_tmp/vnx-update-" . int(rand(1000000));

        wlog (V, "----     creating directory $update_dir", "");                         
        my $ssh_cmd = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip '" .
                      "cd $host_tmp;" .
                      "mkdir -vp $update_dir;" .
                      "rm -vrf $update_dir/*;" .
                      "'";
        wlog (VVV, "----     $ssh_cmd", "");                         
        system "$ssh_cmd >> /var/log/vnx/$host_id.log 2>&1 ";

        wlog (V, "----     copying tar file", "");                         
        $ssh_cmd =    "scp $VNX_TARFILE $host_ip:$update_dir";
        wlog (VVV, "----     $ssh_cmd", "");                         
        system "$ssh_cmd >> /var/log/vnx/$host_id.log 2>&1 ";

        wlog (V, "----     uncompressing and installing VNX...", "");                         
        $ssh_cmd =    "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip '" .
                      "cd $update_dir;" .
                      "tar xfvz vnx-latest.tgz;" .
                      "cd vnx-*;" .
                      "./install_vnx;" .
                      "rm -vrf $update_dir/;" .
                      "'";
        wlog (VVV, "----     $ssh_cmd", "");                         
        system "$ssh_cmd >> /var/log/vnx/$host_id.log 2>&1 ";
        wlog (V, "----     ...done", "");                         
    }
}


sub mode_showmap {

    wlog (N, "\n---- mode: $mode\n---- Show scenario $vnx_scenario map");
    print "vnx -f $vnx_scenario --show-map";
    system ("vnx -f $vnx_scenario --show-map > /dev/null 2>&1");	
}

sub mode_exeinfo {

    wlog (N, "\n---- mode: $mode\n---- Show info about scenario commands");
    print "vnx -f $vnx_scenario --exe-info";
    my $res = `vnx -f $vnx_scenario --exe-info`;
    print "$res\n";    
}

#
# Create EDIV database 
#
sub mode_createdb {
    
    wlog (N, "\n---- mode: $mode\n---- Creating EDIV database");
    create_database();

}
    
#
# Reset EDIV database
#
sub mode_resetdb {

    my @tables = qw ( hosts nets scenarios vlans vms ); 

    wlog (N, "\n---- mode: $mode\n---- Reseting database");

    wlog (V, "----   option reset-db='$opts{'reset-db'}'", "");
    if ( defined($opts{'f'}) ) {
        wlog (V, "----   option -f='$opts{'f'}'", "");
    }

    if (   ($opts{'reset-db'} ne '') or ( $opts{'f'} )   ) {

        if ( $opts{'reset-db'} ne '' ) {
            # A scenario identifier has been specified
            # We only delete the entries corresponding to that scenario 
            $scenario_name = $opts{'reset-db'};                     

        } # else:  an scenario has been specified with '-f' option
          # The name of the scenario is already in $scenario_name 
        
        my $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass});
        my $query_string = "SELECT 'name' FROM scenarios WHERE name = '$scenario_name'";
        my $query = $dbh->prepare($query_string);
        $query->execute();
        my $content = $query->fetchrow_array();
        $query->finish();
        $dbh->disconnect;
        
        unless ( defined($content) ) {

            wlog (N, "---- Scenario '$scenario_name' doesn't exist in database");

        } else {
        
            my $answer;
            unless ($opts{'y'}) {
                print("Do you want to delete virtual scenario '$scenario_name' from database (yes/no)? ");
                $answer = readline(*STDIN);
            } else {
            	$answer = 'yes'; 
            }
            unless ( $answer =~ /^yes/ ) {
                wlog (N, "---- Scenario '$scenario_name' NOT deleted from database. Exiting");
            } else {

                wlog (N, "---- Deleting scenario '$scenario_name' from database.");
                delete_scenario_from_database ($scenario_name);

=BEGIN
	            for my $table (@tables) {
                    my $query_string = "DELETE FROM $table WHERE scenario = '$scenario_name'";
	                if (my $query = $dbh->prepare($query_string) ) {
	                    $query->execute();
	                    $query->finish();       
	                } else {
	                   print "Can't delete '$scenario_name' entries in table '$table': $DBI::errstr\n";
	                }
	            }
=END
=cut	                  	                
            }
            #$dbh->disconnect;
        }

    } else {
        
        # No scenario has been specified. We delete the whole database content    	

        my $answer;
        unless ($opts{'y'}) {
            print "---- Do you want to delete the whole database content (yes/no)? ";
            $answer = readline(*STDIN);
        } else {
            $answer = 'yes'; 
        }
        unless ( $answer =~ /^yes/ ) {
            wlog (N, "---- Database content not deleted. Exiting");
        } else {
        
            wlog (N, "---- Deleting whole database content.");
            reset_database();

=BEGIN        
            my $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass});
	        for my $table (@tables) {
	            my $query_string = "TRUNCATE TABLE `$table`;";
	            if (my $query = $dbh->prepare($query_string) ) {
	                $query->execute();
	                $query->finish();       
	            } else {
	               print "Can't delete content of table '$table': $DBI::errstr\n";
	            }
	        }       	        
	        $dbh->disconnect;
=END
=cut
	        
        }
    }

}

#
# Delete EDIV database
#
sub mode_deletedb{

    wlog (N, "\n---- mode: $mode\n---- Deleting EDIV database");

    my $answer;
    unless ($opts{'y'}) {
        print("---- Do you want to completely delete EDIV database (yes/no)? ");
        $answer = readline(*STDIN);
    } else {
        $answer = 'yes'; 
    }
    unless ( $answer =~ /^yes/ ) {
        wlog (N, "---- Database not deleted. Exiting");
    } else {
        delete_database();        	    
    }
}

#
# print_vms_allocation
#
# Prints a table with the virtual machine to host assignation
#
sub print_vms_allocation {

    wlog (N, "" );           
    wlog (N, sprintf (" %-16s%-24s%-20s", "VM name", "Type", "Host") );           
    wlog (N, "-------------------------------------------------------" );           
    foreach my $vm_name (keys(%allocation)) {
    	wlog (N, sprintf (" %-16s%-24s%-20s", $vm_name, $dh->get_vm_merged_type ($dh->get_vm_byname ($vm_name)), $allocation{$vm_name}) );
    }
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
		ediv_die ("No segmentation modules found at $EDIV_SEG_ALGORITHMS_DIR... Aborting");
	}

}


sub is_scenario_running {

    my $scenario_name = shift;
    my @db_resp;
    
    # Query the database
    my $error = query_db ("SELECT `name` FROM scenarios WHERE name='$scenario_name'", \@db_resp);
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

	$firstVlan = $vlan->{first};
	$lastVlan  = $vlan->{last};	

	while (1){
        
        my @db_resp;
        my $error = query_db ("SELECT `number` FROM vlans WHERE number='$firstVlan'", \@db_resp);
        if ($error) { ediv_die ("$error") };
        unless ( defined($db_resp[0]->[0]) ) {
            last;
        }       
		$firstVlan++;
		if ($firstVlan >$lastVlan){
            delete_scenario_from_database ($scenario_name);
			ediv_die ("There isn't more free vlans... Aborting");
		}	
	}	
}
	
	
#
# create_subscenario_docs create_subscenario_docs
# 
# It creates a new dom tree for each host to store its subscenario specification
# The new dom trees are stored in $scenario_hash associative array
#
sub create_subscenario_docs {
	
	my $change_db = shift; # if not defined, the database is not changed 

    wlog (VVV, "create_subscenario_docs called");
    #print $dh->get_doc->toString;
	
	# Create a new template document by cloning the scenario tree
    #my $template_doc= $doc->cloneNode("true");
    my $template_doc= $dh->get_doc->cloneNode("true");
    
    my $newVnxNode=$template_doc->getElementsByTagName("vnx")->item(0);
	#print $newVnxNode->getNodeTypeName."\n";
	#print $newVnxNode->getNodeName."\n";
    # Delete all child nodes but the <global> one  
    for my $child ($newVnxNode->getChildNodes){
		unless ($child->getNodeName eq 'global'){
			$newVnxNode->removeChild($child);
		} 
	}
	# Clone <global> section and add it to template document
#	my $global= $doc->getElementsByTagName("global")->item(0)->cloneNode("true");
#	$global->setOwnerDocument($template_doc);
#	$newVnxNode->appendChild($global);

#	my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
	
	# Create a new document for each active host in the cluster by cloning the template document ($template_doc)
    foreach my $host_id (@cluster_active_hosts) {

        my $doc = $template_doc->cloneNode("true");
        my $host_ip = get_host_ipaddr ($host_id);       
        my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/";
        my $subscenario_name = $scenario_name."_" . $host_id;
        
        # Set host subscenario name: original scenario name + _ + host_id
	    $doc->getElementsByTagName("scenario_name")->item(0)->getFirstChild->setData($subscenario_name);
		
		# Check wheter <dynamips_ext> tag is present
	    my $dynamips_extTagList=$doc->getElementsByTagName("dynamips_ext");
        my $numdynamips_ext = $dynamips_extTagList->getLength;

    	if ($numdynamips_ext == 1) { # Can't be > 1 (previously checked on CheckSemantics)	

	   		my $virtualmList=$globalNode->getElementsByTagName("vm");
			my $keep_dynamips_in_scenario = 0;
			for (my $m=0; $m<$virtualmList->getLength; $m++){
				my $vm=$virtualmList->item($m);
				my $vm_name = $vm->getAttribute("name");
				my $vm_host_id = $allocation{$vm_name};
				if ($vm_host_id eq $host_id){
					my $vm_type = $vm->getAttribute("type");
					if ($vm_type eq "dynamips"){
						$keep_dynamips_in_scenario = 1;
					}
				}	
			}
	   		if ($keep_dynamips_in_scenario == 1){
	   			#my $current_host_dynamips_path = $dynamips_ext_path . $subscenario_name ."/dynamips-dn.xml";
	   			#print $dynamips_extTagList->item(0)->getFirstChild->getData . "\n";
	   			#print "current_host_dynamips_path=$current_host_dynamips_path\n";<STDIN>;
	   			# las tres lineas de arriba no funcionan, ya que no puedo meter el xml en los
	   			# directorios del escenario antes de crearlo, hay que usar un /tmp:

	   			#my $current_host_dynamips_path = $host_tmpdir . "/dynamips-dn.xml";
	   			my $host_dyn_name = basename ($dynamips_extTagList->item(0)->getFirstChild->getData);
	   			
	   			$dynamips_extTagList->item(0)->getFirstChild->setData($host_dyn_name);
	   			wlog (V, "-- host_dyn_name = " . $dynamips_extTagList->item(0)->getFirstChild->getData . "\n");
	   		}else{
	#  			my $dynamips_extTag = $dynamips_extTagList->item(0);
	#    		$parentnode = $dynamips_extTag->parentNode;
	#  			$parentnode->removeChild($dynamips_extTag);
				
				foreach my $node ( $doc->getElementsByTagName("dynamips_ext") ) {
					$doc->getElementsByTagName("global")->item(0)->removeChild($node);
				}

	   		}	

    	}	
		
        #my $basedir_data = "/tmp/";
        my $basedir_data = $host_tmpdir;
		eval{
			$doc->getElementsByTagName("global")->item(0)->getElementsByTagName("vm_defaults")->item(0)->getElementsByTagName("basedir")->item(0)->getFirstChild->setData($basedir_data);
		};		
		
		# Store the new document in $scenario_hash array
		$scenario_hash{$host_id} = $doc;	
        wlog (VVV, "---- create_subscenario_docs: assigned scenario for $host_id\n");
		
		if (defined($change_db)) {
	        # Save data into DB
	        my $error = query_db ("INSERT INTO hosts (scenario,local_scenario,host,ip,status) VALUES " 
	                           . "('$scenario_name','$subscenario_name','$host_id','$host_ip','creating')");
	        if ($error) { ediv_die ("$error") }
		}
        
	}
	
}

#
# fill_subscenario_docs
#
# Fill the subscenario docs by spliting the original scenario XML file following segmentator 
# split rules stored in %allocation array.
# Subscenario docs are stored in %scenario_hash
#
sub fill_subscenario_docs {

    my $change_db = shift; # if not defined, the database is not changed 

    my $error; 
    my @db_resp;
    
    wlog (VVV, "-- fill_subscenario_docs called");
    
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
		
		$newVirtualM->setOwnerDocument($scenario_hash{$host_id});

		my $vnxNode=$scenario_hash{$host_id}->getElementsByTagName("vnx")->item(0);
			
		$vnxNode->setOwnerDocument($scenario_hash{$host_id});
		
		$vnxNode->appendChild($newVirtualM);
		#print $vnxNode->toString;
		#print "***\n";

		#unless ($vm_name){
			# Creating virtual machines in the database
            wlog (VVV, "** fill_subscenario_docs: Creating virtual machine $vm_name in db");

            if (defined($change_db)) {
		        $error = query_db ("SELECT `name` FROM vms WHERE name='$vm_name'", \@db_resp);
		        if ($error) { ediv_die ("$error") };
		        if ( defined($db_resp[0]->[0]) ) {
	                delete_scenario_from_database ($scenario_name);
	                ediv_die ("The vm $vm_name was already created... Aborting");
		        }
		        # Register the new vm in the database
	            $error = query_db ("INSERT INTO vms (name,type,subtype,os,status,scenario,host) " . 
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
		foreach my $host_id (keys(%scenario_hash)) {
			
			my $host_subdoc = $scenario_hash{$host_id};		
			my $currentVMList = $host_subdoc->getElementsByTagName("vm");
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
							$netToAppend->setOwnerDocument($host_subdoc);
							
							my $firstVM=$host_subdoc->getElementsByTagName("vm")->item(0);
							$host_subdoc->getElementsByTagName("vnx")->item(0)->insertBefore($netToAppend, $firstVM);
									
							$netFlag=1;
						}
					}
				}
			}				
		}
	}
	if (defined($change_db)) {
        unless ($opts{M} || $opts{H}){      
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
        $error = query_db ("INSERT INTO nets (name,scenario) VALUES ('$nameOfNet','$scenario_name')");
        if ($error) { ediv_die ("$error") };
		#$query_string = "INSERT INTO nets (name,scenario) VALUES ('$nameOfNet','$scenario_name')";
        		
        # For exploring each scenario on scenarioarray	
		my @net_host_list;
		foreach my $host_id (keys(%scenario_hash)) {
			my $host_subdoc = $scenario_hash{$host_id};
			my $host_subdoc_nets = $host_subdoc->getElementsByTagName("net");
			for (my $j=0; $j<$host_subdoc_nets->getLength; $j++) {
				my $host_subdoc_net = $host_subdoc_nets->item($j);
				
				if ( ($host_subdoc_net->getAttribute("name")) eq ($nameOfNet)) {
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
				ediv_die ("There isn't more free vlans... Aborting");
			}	
		}
	
		my $current_net = $nets_to_handle{$net_name};
		my $net_vlan = $current_vlan;
		
		# 2.2 Use previous data to modify subscenario
		foreach my $host_id (keys(%scenario_hash)) {

			my $command_list;
            my $external = get_host_ifname ($host_id);
			my $host_subdoc = $scenario_hash{$host_id};
			for (my $k=0; defined($current_net->[$k]); $k++) {
				if ($current_net->[$k] eq $host_id) {
					my $host_subdoc_nets = $host_subdoc->getElementsByTagName("net");
					for (my $l=0; $l<$host_subdoc_nets->getLength; $l++) {
						my $currentNet = $host_subdoc_nets->item($l);
						my $currentNetName = $currentNet->getAttribute("name");
						if ($net_name eq $currentNetName) {
							my $treated_net = $currentNet->cloneNode("true");
                            $treated_net->setAttribute("external", "$external.$net_vlan");
                            #$treated_net->setAttribute("external", "$external:$net_vlan");
							$treated_net->setAttribute("mode", "virtual_bridge");
							$treated_net->setOwnerDocument($host_subdoc);
							$host_subdoc->getElementsByTagName("vnx")->item(0)->replaceChild($treated_net, $currentNet);
							
							# Adding external interface to virtual net
                            $error = query_db ("UPDATE nets SET external = '$external.$net_vlan' WHERE name='$currentNetName'");
                            #$error = query_db ("UPDATE nets SET external = '$external:$net_vlan' WHERE name='$currentNetName'");
				            if ($error) { ediv_die ("$error") };
							
                            $error = query_db ("INSERT INTO vlans (number,scenario,host,external_if) VALUES ('$net_vlan','$scenario_name','$host_id','$external')");
                            if ($error) { ediv_die ("$error") };
		
                            #my $vlan_command = "vconfig add $external $net_vlan\nifconfig $external.$net_vlan 0.0.0.0 up\n";
                            my $vlan_command = "vconfig add $external $net_vlan\n" .
                                               "ip link set $external.$net_vlan up\n";
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
		&daemonize($host_command, "$host_id".".log");
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
	
    $error = query_db ("SELECT `automac_offset` FROM scenarios ORDER BY `automac_offset` DESC LIMIT 0,1", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        $VmOffset = 0;
    } else {
        $VmOffset = $db_resp[0]->[0]; # we hope this is enough
    }

    $error = query_db ("SELECT `mgnet_offset` FROM scenarios ORDER BY `mgnet_offset` DESC LIMIT 0,1", \@db_resp);
    if ($error) { ediv_die ("$error") };
    unless ( defined($db_resp[0]->[0]) ) {
        $MgnetOffset = 0;
    } else {
        $MgnetOffset = $db_resp[0]->[0]; # we hope this is enough
    }
	
	my $management_network = $cluster->{mgmt_network};
	my $management_network_mask = $cluster->{mgmt_network_mask};
	
	foreach my $host_id (keys(%scenario_hash)) {
		
		my $host_subdoc = $scenario_hash{$host_id};
		my $automac=$host_subdoc->getElementsByTagName("automac")->item(0);
		if (!($automac)){
			$automac=$host_subdoc->createElement("automac");
			$host_subdoc->getElementsByTagName("global")->item(0)->appendChild($automac);
			
		}
		
		$automac->setAttribute("offset", $VmOffset);
		$VmOffset +=150;  #JSF temporalmente cambiado, hasta que arregle el ""FIXMEmac"" de vnx
		#$VmOffset +=5;
		
		my $management_net=$host_subdoc->getElementsByTagName("vm_mgmt")->item(0);
		
			# If management network doesn't exist, create it
		if (!($management_net)) {
			$management_net = $host_subdoc->createElement("vm_mgmt");
			$management_net->setAttribute("type", "private");
			my $vm_defaults_node = $host_subdoc->getElementsByTagName("vm_defaults")->item(0);
			$host_subdoc->getElementsByTagName("global")->item(0)->insertBefore($management_net, $vm_defaults_node);
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
		my $host_mapping_property = $host_subdoc->getElementsByTagName("host_mapping")->item(0);
		if (!($host_mapping_property)) {
			$host_mapping_property = $host_subdoc->createElement("host_mapping");
			$host_subdoc->getElementsByTagName("vm_mgmt")->setOwnerDocument($host_subdoc);
			$host_subdoc->getElementsByTagName("vm_mgmt")->item(0)->appendChild($host_mapping_property);
		}
		
		#my $net_offset = $host_subdoc->getElementsByTagName("vm_mgmt")->item(0);
		#$net_offset->setAttribute("offset", $MgnetOffset);
		#$net_offset->setAttribute("mask","16");
		
#		foreach $virtual_machine (keys(%allocation)) {
#			if ($allocation{$virtual_machine} eq $host_name) {
#				$MgnetOffset += 4; # Uses mask /30 with a point-to-point management network
#			}				
#		}	
	}
	
    $error = query_db ("UPDATE scenarios SET automac_offset = '$VmOffset' WHERE name='$scenario_name'");
    if ($error) { ediv_die ("$error") };
	
    $error = query_db ("UPDATE scenarios SET mgnet_offset = '$MgnetOffset' WHERE name='$scenario_name'");
    if ($error) { ediv_die ("$error") };
	
}

#
# send_and_start_subscenarios 
#
# Subroutine to send scenario files to hosts
#
sub send_and_start_subscenarios {
	
	my @db_resp;
	
    my %hosts_involved = get_hosts_involved();

    foreach my $host_id (keys %hosts_involved) {
	
	    wlog (VVV, "\n---- send_and_start_subscenarios: $host_id");
	
        my $host_ip = get_host_ipaddr ($host_id);       
        my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/";
        my $subscenario_name = get_host_subscenario_name ($host_id, $scenario_name);
        my $local_subscenario_fname = $dh->get_sim_tmp_dir . "/$subscenario_name".".xml";
        my $host_subscenario_fname = $host_tmpdir . "$subscenario_name".".xml";
        my $host_subdoc = $scenario_hash{$host_id};

        # Write XML spec to file
        $host_subdoc->printToFile("$local_subscenario_fname");
		# Store the local specification to DB	
        my $subscenario_xml = $host_subdoc->toString;
   		$subscenario_xml =~ s/\\/\\\\/g;  # We scape the "\" before writing the scenario to the ddbb
        my $error = query_db ("UPDATE hosts SET local_specification = '$subscenario_xml' WHERE local_scenario='$subscenario_name'");
        if ($error) { ediv_die ("$error") };
		
		my $scp_command = "scp -2 $local_subscenario_fname root\@$host_ip:$host_tmpdir";
		&daemonize($scp_command, "$host_id".".log");
		my $permissions_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip \'chmod -R 777 $host_subscenario_fname\'";
		&daemonize($permissions_command, "$host_id".".log"); 
		my $option_M = '';
		if ($opts{M} || $opts{H}) { $option_M = "-M $hosts_involved{$host_id}"; }
		my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnx -f $host_subscenario_fname $log_opt -t -o /dev/null\ " 
		                  . $option_M . " " . $no_console . "; sleep $SSH_POST_DELAY'";
		&daemonize($ssh_command, "$host_id".".log");		
	}
}

#
# checkFinish
#
# Subroutine to check propper finishing of launching mode (-t)
# Uses $vnx_dir/scenarios/<simulacion>/vms/<vm>/status file
#
sub checkFinish {

	my $dbh;
	my $host_ip;
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
        push (@output1, sprintf (" %-24s%-24s%-20s\n", "VM name", "Host", "Status"));           
        push (@output1, sprintf ("----------------------------------------------------------------------\n"));         

		foreach my $host_id (@cluster_active_hosts){

            my $host_ip = get_host_ipaddr ($host_id);
            foreach my $vm_name (keys (%allocation)){
                wlog (VVV, "---- vm=$vm_name, host_id=$host_id");
                if ($allocation{$vm_name} eq $host_id){
                    my $statusFile = get_host_vnxdir($host_id) . "/scenarios/" 
                                    . $scenario_name . "_" . $host_id . "/vms/$vm_name/status";
                    my $status_command = "ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'cat $statusFile 2> /dev/null'";
                    wlog (VVV, "---- Executing: $status_command");
                    my $status = `$status_command`;
                    chomp ($status);
                    wlog (VVV, "---- Executing: status=$status");
                    if (!$status) { $status = "undefined" }
                    #push (@output2, color ('bold'). sprintf (" %-24s%-24s%-20s%-40s\n", $vm_name, $host_id, $status, $statusFile) . color('reset'));
                    push (@output2, color ('bold'). sprintf (" %-24s%-24s%-20s\n", $vm_name, $host_id, $status) . color('reset'));
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
	
		    #$error = query_db ("SELECT `local_scenario` FROM hosts WHERE status = 'creating' AND host = '$host_name'", \@db_resp);
		    #if ($error) { ediv_die ("$error") };
		    #if ( defined($db_resp[0]->[0]) ) {
		    #	 $scenario = $db_resp[0]->[0];
		    #	 chomp($scenario);
	        #}
			#my $query_string = "SELECT `local_scenario` FROM hosts WHERE status = 'creating' AND host = '$host_name'";
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
		
		my $query_string = "SELECT `local_scenario` FROM hosts WHERE status = 'creating' AND host = '$host_name'";
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
# purge_scenario
#
# Subroutine to execute purge mode in cluster
#
sub purge_scenario {

	my $host_ip;
	my $host_id;
	my @db_resp;
    my $error;
	my $scenario;
	
    my %hosts_involved = get_hosts_involved();

    foreach my $host_id (keys %hosts_involved) {

		my $vlan_command;

        my $host_ip = get_host_ipaddr ($host_id);       
        my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/";
        my $subscenario_name = get_host_subscenario_name ($host_id, $scenario_name);
        my $local_subscenario_fname = $dh->get_sim_tmp_dir . "/$subscenario_name".".xml";
        my $host_subscenario_fname = $host_tmpdir . "$subscenario_name".".xml";

        wlog (VVV, "--  purge_scenario: host_id = $host_id, host_ip = $host_ip, host_tmpdir = $host_tmpdir");  
        wlog (VVV, "--  purge_scenario: subscenario_name = $subscenario_name");  
        wlog (VVV, "--  purge_scenario: local_subscenario_fname = $local_subscenario_fname");  
        wlog (VVV, "--  purge_scenario: host_subscenario_fname = $host_subscenario_fname");  

        my $subscenario_xml = get_host_subscenario_xml ($host_id, $scenario_name, $local_subscenario_fname);

        unless ( defined($subscenario_name) && defined($subscenario_xml) ) {
            ediv_die ("Cannot get subscenario name or subscenario XML file")
        }

		# If vm specified with -M, do not switch scenario status to "purging".
		my $scenario_status;
        if ($opts{M} || $opts{H}) {      
			$scenario_status = "running";
		}else{
			$scenario_status = "purging";
		}

        my $scp_command = "scp -2 $local_subscenario_fname root\@$host_ip:$host_tmpdir";
        &daemonize($scp_command, "$host_id".".log");
        my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $host_subscenario_fname\'";
        &daemonize($permissions_command, "$host_id".".log");
        wlog (N, "---- Stopping scenario and network restoring in $host_id");
        my $option_M = '';
        if ($opts{M} || $opts{H}) { $option_M = "-M $hosts_involved{$host_id}"; }
        my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx $log_opt -P -f $host_subscenario_fname " . $option_M . "; sleep $SSH_POST_DELAY'";
        &daemonize($ssh_command, "$host_id".".log");  

        unless ($opts{M} || $opts{H}){      
            #Clean vlans
            $error = query_db ("SELECT `number`, `external_if` FROM vlans WHERE host = '$host_id' AND scenario = '$scenario_name'", \@db_resp);
            if ($error) { ediv_die ("$error") };
            foreach my $vlans (@db_resp) {
                $vlan_command = $vlan_command . "vconfig rem $$vlans[1].$$vlans[0]\n";
            }
            $vlan_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip '$vlan_command'";
            &daemonize($vlan_command, "$host_id".".log");
        }   

	}
	
    # Update vm status in db
    my @vms = ediv_get_vm_to_use_ordered(); # List of VMs involved (taking into account -M and -H options)
    for ( my $i = 0; $i < @vms; $i++) {
        my $vm_name = $vms[$i]->getAttribute("name");
        my $error = query_db ("UPDATE vms SET status = 'inactive' WHERE name='$vm_name'");
        if ($error) { ediv_die ("$error") };
    }        
	
}

#
# shutdown_scenario
#
# Subroutine to execute destroy mode in cluster
#
sub shutdown_scenario {
	
	my $host_ip;
	my $host_id;
    my $error;
    my @db_resp;
    
	my $scenario;

    my %hosts_involved = get_hosts_involved();
    wlog (VVV, "\n---- shutdown_scenario: hosts_involved" . Dumper (%hosts_involved));        
    
            
    foreach my $host_id (keys %hosts_involved) {

        wlog (V, "----   shutdown_scenario: $host_id");        
			
		my $vlan_command;

        my $host_ip = get_host_ipaddr ($host_id);       
        my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/";
        my $subscenario_name = get_host_subscenario_name ($host_id, $scenario_name);
        my $local_subscenario_fname = $dh->get_sim_tmp_dir . "/$subscenario_name".".xml";
        my $host_subscenario_fname = $host_tmpdir . "$subscenario_name".".xml";
        my $subscenario_xml = get_host_subscenario_xml ($host_id, $scenario_name, $local_subscenario_fname);

        wlog (VVV, "--  shutdown_scenario: host_id = $host_id, host_ip = $host_ip, host_tmpdir = $host_tmpdir");  
        wlog (VVV, "--  shutdown_scenario: subscenario_name = $subscenario_name");  
        wlog (VVV, "--  shutdown_scenario: local_subscenario_fname = $local_subscenario_fname");  
        wlog (VVV, "--  shutdown_scenario: host_subscenario_fname = $host_subscenario_fname");  

        unless ( defined($subscenario_name) && defined($subscenario_xml) ) {
            ediv_die ("Cannot get subscenario name or subscenario XML file")
        }

		# If vm specified with -M, do not switch scenario status to "destroying".
		my $scenario_status;
        if ($opts{M} || $opts{H}){      
			$scenario_status = "running";
		}else{
			$scenario_status = "destroying";
		}
		
        my $scp_command = "scp -2 $local_subscenario_fname root\@$host_ip:/tmp/";
        &daemonize($scp_command, "$host_id".".log");
        my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $host_subscenario_fname\'";
        &daemonize($permissions_command, "$host_id".".log");
        wlog (N, "\n---- Stopping scenario and network restoring in $host_id\n");
        my $option_M = '';
        if ($opts{M} || $opts{H}) { $option_M = "-M $hosts_involved{$host_id}"; }
        wlog (V, "---- shutdown_scenario: $option_M");        
            
        my $ssh_command =  "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'vnx $log_opt -d -f $host_subscenario_fname " . $option_M . "; sleep $SSH_POST_DELAY'";
        &daemonize($ssh_command, "$host_id".".log");
				
        unless ($opts{M} || $opts{H}){      
			#Clean vlans
	        $error = query_db ("SELECT `number`, `external_if` FROM vlans WHERE host = '$host_id' AND scenario = '$scenario_name'", \@db_resp);
	        if ($error) { ediv_die ("$error") };
			foreach my $vlans (@db_resp) {
                 $vlan_command = $vlan_command . "vconfig rem $$vlans[1].$$vlans[0]\n";
                 #$vlan_command = $vlan_command . "vconfig rem $$vlans[1]:$$vlans[0]\n";
			}
			$vlan_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip '$vlan_command'";
			&daemonize($vlan_command, "$host_id".".log");
		}	
	}
	
    # Update vm status in db
    my @vms = ediv_get_vm_to_use_ordered(); # List of VMs involved (taking into account -M and -H options)
    for ( my $i = 0; $i < @vms; $i++) {
        my $vm_name = $vms[$i]->getAttribute("name");
        my $error = query_db ("UPDATE vms SET status = 'inactive' WHERE name='$vm_name'");
        if ($error) { ediv_die ("$error") };
    }        
	
}

#
# delete_dirs
#
# Subroutine to clean files
#
sub delete_dirs {

    my $delete_all = shift;
    
	foreach my $host_id (@cluster_active_hosts) {
		
        my $host_ip   = get_host_ipaddr ($host_id); 
        wlog (N, "\n-- Cleaning $host_id directories");
        if ($delete_all) {
            my $host_dir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name";
            my $rm_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'rm -rf $host_dir/*'";
            &daemonize($rm_command, "$host_id".".log");
        } else {
            my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp";
            my $rm_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'rm -rf $host_tmpdir/*'";
            &daemonize($rm_command, "$host_id".".log");
        }         
	}	
}

#
# Subroutine to create tgz file with configuration of VMs
#
sub build_scenario_conf {
	
	wlog (VVV, "-- build_scenario_conf");
	
	my $basedir = "";
	eval {
		$basedir = $globalNode->getElementsByTagName("global")->item(0)->getElementsByTagName("vm_defaults")->item(0)->getElementsByTagName("basedir")->item(0)->getFirstChild->getData;
	};
	my @filetrees;
	my @execs;

    my @vms = ediv_get_vm_to_use_ordered(); # List of VMs involved (taking into account -M and -H options)
    for ( my $i = 0; $i < @vms; $i++) {
            
        my $vm = $vms[$i];
        my $vm_name=$vm->getAttribute("name");	
        my $vm_type=$vm->getAttribute("type");  

        # <filetree> tags
        my $filetree_list = $vm->getElementsByTagName("filetree");
        for (my $m=0; $m<$filetree_list->getLength; $m++){
            my $filetree = $filetree_list->item($m)->getFirstChild->getData;
            wlog (VVV, "-- build_scenario_conf: added $filetree");
            push(@filetrees, $filetree);
        }
			
        # <exec> tags
        my $exec_list = $vm->getElementsByTagName("exec");
        for (my $m=0; $m<$exec_list->getLength; $m++){

            my $exec_ostype=$exec_list->item($m)->getAttribute("ostype");  
            wlog (VVV, "-- build_scenario_conf: exec_ostype=$exec_ostype");
            
            # Get dynamips config files
            if ($vm_type eq "dynamips" && $exec_ostype eq 'load') {
	            my $exec = $exec_list->item($m)->getFirstChild->getData;
	            $exec =~ s/merge //;
	            wlog (VVV, "-- build_scenario_conf: added $exec");
	            push(@execs, $exec);
            } 
        
        }
	}
	
	# Look for configuration files defined for dynamips vms
	my $ext_conf_file = $dh->get_default_dynamips();
	# If the extended config file is defined, look for <conf> tags inside
	if ($ext_conf_file ne '0'){
		$ext_conf_file = &get_abs_path ($ext_conf_file);
		wlog (VVV, "-- build_scenario_conf: ext_conf_file=$ext_conf_file");
		my $parser    = new XML::DOM::Parser;
		my $dom       = $parser->parsefile($ext_conf_file);
		my $conf_list = $dom->getElementsByTagName("conf");
   		for ( my $i = 0; $i < $conf_list->getLength; $i++) {
      		my $confi = $conf_list->item($i)->getFirstChild->getData;
			wlog (VVV, "-- build_scenario_conf: adding dynamips conf file=$confi");
			push(@filetrees, $confi);		
	 	}
	}
	
	unless ($basedir eq "") {
		chdir $basedir;
	}
    if (@filetrees or @execs){
        my $tgz_name = $dh->get_sim_tmp_dir . "/conf.tgz"; 
        my $tgz_command = "tar czfv $tgz_name @filetrees @execs";
        system ($tgz_command);
    }

	if (@filetrees){
		#my $tgz_name = $dh->get_sim_tmp_dir . "/conf.tgz"; 
		#my $tgz_command = "tar czfv $tgz_name @filetrees";
		#system ($tgz_command);
		$configuration = 1;	
	}
	#JSF añadido para tags <exec>
	elsif (@execs){
		$configuration = 2;
	}

# JSF: (corregido) por algún motivo solo se permite la ejecucion de comandos ($configuration = 1) si hay un tag filetree
# debería permitirse también si hay algún exec (?). Añadiendo la linea de debajo (es mia) se puede ejecutar ahora mismo:
# $configuration = 1;	
}

#
# send_conf_files
#
# Subroutine to copy VMs execution mode configuration to cluster machines
#
sub send_conf_files {

	if ($configuration == 1){
		print "\n---- Sending configuration to cluster hosts\n";
		foreach my $host_id (@cluster_active_hosts) {	
	        my $host_ip   = get_host_ipaddr ($host_id);
            my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/";
            my $local_tgz_name = $dh->get_sim_tmp_dir . "/conf.tgz";
            my $remote_tgz_name = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/conf.tgz";
			my $scp_command = "scp -2 $local_tgz_name root\@$host_ip:$host_tmpdir";	
			system($scp_command);
			my $tgz_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'tar xzf $remote_tgz_name -C $host_tmpdir'";
			&daemonize($tgz_command, "$host_id".".log");
		}
	}
	my $plugin;
	my $conf_plugin;
	eval {
		$plugin = $globalNode->getElementsByTagName("global")->item(0)->getElementsByTagName("extension")->item(0)->getAttribute("plugin");
		$conf_plugin = $globalNode->getElementsByTagName("global")->item(0)->getElementsByTagName("extension")->item(0)->getAttribute("conf");
	};
	
	# Send dynamips extended configuration file if it exists

	if (defined $dh->get_doc->getElementsByTagName("dynamips_ext") && 
	    $dh->get_doc->getElementsByTagName("dynamips_ext")->getLength == 1) { # Can't be > 1 (previously checked on CheckSemantics)  
#	if ($dynamips_ext_path ne ""){
        foreach my $host_id (@cluster_active_hosts) {  
            wlog (V, "\n---- Sending dynamips configuration file to host $host_id\n");
	        my $host_ip  = get_host_ipaddr ($host_id);         
            my $host_dir = get_host_vnxdir ($host_id) . "/scenarios/${scenario_name}/tmp/";
            my $dyn_ext_conf_path = &get_abs_path ( $dh->get_doc->getElementsByTagName("dynamips_ext")->item(0)->getFirstChild->getData );
            my $dyn_ext_conf_name = basename ($dyn_ext_conf_path);
            wlog (V, "-- host_dir=$host_dir");
            wlog (V, "-- dyn_ext_conf_path=$dyn_ext_conf_path");
            wlog (V, "-- dyn_ext_conf_name=$dyn_ext_conf_name");
			my $scp_command = "scp -2 $dyn_ext_conf_path root\@$host_ip:$host_dir/$dyn_ext_conf_name";
			system($scp_command);
		}
	}

	if ( defined($plugin) && defined($conf_plugin) ){
		print "\n---- Sending configuration to cluster hosts\n";
		
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
            my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/";
			my $scp_command = "scp -2 $conf_plugin_file root\@$host_ip:$host_tmpdir";
			system($scp_command);
		}
		$configuration = 1;
	}
}


#
# execute_command
#
# Subroutine to execute execution mode in cluster
#
sub execute_command {

    my $error;
    my @db_resp;
    my $seq = $opts{'execute'};
    	
	if (!($configuration)){
		ediv_die ("This scenario doesn't support mode -x")
	}
	my $dbh;

    my %hosts_involved = get_hosts_involved();

    foreach my $host_id (keys %hosts_involved) {

        my $host_ip = get_host_ipaddr ($host_id);       
        my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/";
        my $subscenario_name = get_host_subscenario_name ($host_id, $scenario_name);
        my $local_subscenario_fname = $dh->get_sim_tmp_dir . "/$subscenario_name".".xml";
        my $host_subscenario_fname = $host_tmpdir . "$subscenario_name".".xml";
        my $subscenario_xml = get_host_subscenario_xml ($host_id, $scenario_name, $local_subscenario_fname);

        wlog (VVV, "--  mode_execute: host_id = $host_id, host_ip = $host_ip, host_tmpdir = $host_tmpdir");  
        wlog (VVV, "--  mode_execute: subscenario_name = $subscenario_name");  
        wlog (VVV, "--  mode_execute: local_subscenario_fname = $local_subscenario_fname");  
        wlog (VVV, "--  mode_execute: host_subscenario_fname = $host_subscenario_fname");  

        unless  ( defined($subscenario_name) && defined($subscenario_xml) ) {
            ediv_die ("Cannot get subscenario name or subscenario XML file")
        }
		
		# Check if there are any <exec> or <filetree> tags with seq=$opts{'execute'} in this host
		if (is_host_involved_in_seq($seq, $subscenario_xml)) {

            wlog (VVV, "--  mode_execute: commands with sequence '$seq' found in host $host_id, executing...");  
			
			my $scp_command = "scp -2 $local_subscenario_fname root\@$host_ip:$host_tmpdir";
			&daemonize($scp_command, "$host_id".".log");
			my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $host_subscenario_fname\'";	
			&daemonize($permissions_command, "$host_id".".log"); 		
	        my $option_M = '';
	        if ($opts{M} || $opts{H}) { $option_M = "-M $hosts_involved{$host_id}"; }
			my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnx -f $host_subscenario_fname $log_opt -x $seq " . $option_M . "; sleep $SSH_POST_DELAY'"; 
			&daemonize($execution_command, "$host_id".".log");
            
        } else {
            wlog (VVV, "--  mode_execute: no commands with sequence '$seq' found in host $host_id, skipping...");  
        }
   }
}

# 
# is_host_involved_in_seq
#
# returns true if an <exec> or <filetree> tag with sequence=$seq is founf in a XML scenario
#
sub is_host_involved_in_seq {
	
	my $seq = shift;
	my $subscenario_xml = shift;

    my $parser = new XML::DOM::Parser;
    my $doc = $parser->parse($subscenario_xml); 
    my $vm_list = $doc->getElementsByTagName("vm");
    
    for (my $i = 0; $i < $vm_list->getLength; $i++) {

        my $vm = $vm_list->item($i);
        # check <filetree> tags
        my $filetree_list = $vm->getElementsByTagName("filetree");
        for (my $m=0; $m<$filetree_list->getLength; $m++){
            if ($filetree_list->item($m)->getAttribute('seq') eq $seq ) {
            	return "true";
            }
        }
        # check <exec> tags
        my $exec_list = $vm->getElementsByTagName("exec");
        for (my $m=0; $m<$exec_list->getLength; $m++){
            if ($exec_list->item($m)->getAttribute('seq') eq $seq ) {
                return "true";
            }
        }
    }
    return '';
}

#
# get_host_subscenario_xml
#
# Retrieves the subscenario XML specification for a host from the database. 
# 
# Arguments:
# - host_id
# - subscenario_name, the name of the subscenario (scenario_host_id)
# - subscenario_fname (optional), if set, the XML spec is written to $subscenario_fname file
#
# Returns:
# - XML specification
# 
sub get_host_subscenario_xml {

    my $host_id = shift;
    my $subscenario_name = shift;
    my $subscenario_fname = shift;
    
    my $error;
    my @db_resp;
    
    # Get subscenario XML from DB 
    $error = query_db ("SELECT `local_specification` FROM hosts WHERE host = '$host_id' " . 
                       "AND scenario = '$subscenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    if (defined($db_resp[0]->[0])) {

        if (defined($subscenario_fname)) {
            # Copy the XML to a $scenario_fname        	
            open(FILEHANDLE, "> $subscenario_fname") or ediv_die ("cannot open file $subscenario_fname");
            print FILEHANDLE "$db_resp[0]->[0]";
            close (FILEHANDLE);        	
        }
        return $db_resp[0]->[0];  
        
    } else {
    	wlog (N, "ERROR (get_host_subscenario_xml): cannot get subscenario xml " .
    	         "from database for scenario $scenario_name and host $host_id");
    	return undef;
    }
}

#
# get_host_subscenario_name
#
# Returns the subscenario XML specification for a host
# 
sub get_host_subscenario_name {

    my $host_id = shift;
    my $scenario_name = shift;
    my $error;
    my @db_resp;
    
    $error = query_db ("SELECT `local_scenario` FROM hosts WHERE host = '$host_id' " . 
                       "AND scenario = '$scenario_name'", \@db_resp);
    if ($error) { ediv_die ("$error") };
    if (defined($db_resp[0]->[0])) {
        return $db_resp[0]->[0];  
    } else {
        wlog (N, "ERROR (get_host_subscenario_name): cannot get subscenario name from database for scenario $scenario_name and host $host_id");
        return undef;
    }
}


#
# tunnelize
#
# Subroutine to create tunnels to operate remote VMs from a local port
#
sub tunnelize {	

	my $localport = 64000;
	my $error;
	my @db_resp;

    wlog (VVV, "--  tunnelize: called");  

    # Are management network interfaces created for the scenario? 
    if ( $dh->get_vmmgmt_type ne 'none' ) {
    	
        wlog (N, "\n-- Creating tunnels to access VM management interfaces");  
        wlog (N, "-- ");  
        wlog (N, "-- " . sprintf("  %-16s %-16s  %s", "To access VM", "at Host", "use command") );  
        wlog (N, "-- " . sprintf(" ---------------------------------------------------------------") );  

        my @vms = ediv_get_vm_to_use_ordered(); # List of VMs involved (taking into account -M and -H options)
        for ( my $i = 0; $i < @vms; $i++) {

            my $vm = $vms[$i];
            my $vm_name = $vm->getAttribute("name");

	        my $mng_if_value = mng_if_value( $vm );
	        if ( $mng_if_value ne "no" ) {
	        	
	            # Create tunnel to remotely access the VM
                my $host_id = $allocation{$vm_name};
                my $host_ip = get_host_ipaddr($host_id);
                my $vm_type = $vm->getAttribute("type");
                my $vm_merged_type = $dh->get_vm_merged_type($vm);

                wlog (VVV, "-- $host_id, $vm_name, $vm_type");

                # Get a free localport
		        while (1){
		            $error = query_db ("SELECT `ssh_port` FROM vms WHERE ssh_port='$localport'", \@db_resp);
		            if ($error) { ediv_die ("$error") };
		            unless (defined($db_resp[0]->[0])) {
		               last;  
		            }
		            $localport++;
		        }

                if ( ($vm_merged_type eq "libvirt-kvm-linux")   || 
                     ($vm_merged_type eq "libvirt-kvm-freebsd") || 
                     ($vm_merged_type eq "libvirt-kvm-olive")   ||
                     ($vm_merged_type eq "uml") )    {

	                wlog (VV, "--   Executing:  ssh -2 -q -f -N -o \"StrictHostKeyChecking no\" -L $localport:$vm_name:22 $host_ip", "" );
	                system("ssh -2 -q -f -N -o \"StrictHostKeyChecking no\" -L $localport:$vm_name:22 $host_ip" );
                    wlog (N, "-- " . sprintf("  %-16s %-16s  %s", $vm_name, $host_id, "ssh root\@localhost -p $localport") );  
                     	
                } elsif ( ($vm_merged_type eq 'dynamips-3600') || ($vm_merged_type eq 'dynamips-7200') ) {

                    # Get con1 port
                    my $cons_file = get_host_vnxdir($host_id) . "/scenarios/${scenario_name}_${host_id}/vms/$vm_name/run/console";
                    my $cmd = "ssh -X -2 -o 'StrictHostKeyChecking no' root\@$host_ip 'cat $cons_file | grep con1 2> /dev/null'";
                    wlog (VVV, "---- Executing: $cmd");
                    my $con1_data = `$cmd`; chomp ($con1_data);
                    wlog (VVV, "---- Executing: con1_data=$con1_data");
				    #my $conData = &get_conf_value ($consFile, '', 'con1');         
				    $con1_data =~ s/con.=//;          # eliminate the "conX=" part of the line
				    my @con1_fields = split(/,/, $con1_data);
				    my $port=$con1_fields[2];
                    
	                wlog (VV, "--   Executing:  ssh -2 -q -f -N -o \"StrictHostKeyChecking no\" -L $localport:localhost:$port $host_ip", "" );
	                system("ssh -2 -q -f -N -o \"StrictHostKeyChecking no\" -L $localport:localhost:$port $host_ip" );
                    wlog (N, "-- " . sprintf("  %-16s %-16s  %s", $vm_name, $host_id, "telnet localhost $localport") );  
                	
                }
		
		        $error = query_db ("UPDATE vms SET ssh_port = '$localport' WHERE name='$vm_name'");
		        if ($error) { ediv_die ("$error") };
		        
		        if ($localport > 65535) {
		            ediv_die ("--   Not enough ports available. The scenario is running but you won't be able to access some VMs using tunnels.");
		        }   
	        }
        }

	    #$error = query_db ("SELECT `name`,`host`,`ssh_port` FROM vms WHERE scenario = '$scenario_name' ORDER BY `name`", \@db_resp);
	    #if ($error) { ediv_die ("$error") };
	    #foreach my $ports (@db_resp) {
	    #    if (defined($$ports[2])) {
	    #        wlog (N, "----    To access VM $$ports[0] at $$ports[1] use local port $$ports[2]\n");
	    #    }
	    #}
	    #print "\n\tUse command ssh -2 root\@localhost -p <port> to access VMs\n";
	    #print "\tOr ediv_console.pl console <scenario_name> <vm_name>\n";
	    #print "\tWhere <port> is a port number of the previous list\n";
	    #print "\tThe port list can be found running ediv_console.pl info\n";

    }
	
	
}

#
# Subroutine to remove tunnels
#
sub untunnelize {
	
	my $error;
	my @db_resp;
	
	wlog (N, "\n-- Cleaning tunnels to access VM management interfaces");  
	
    $error = query_db ("SELECT `ssh_port` FROM vms WHERE scenario = '$scenario_name' ORDER BY `ssh_port`", \@db_resp);
    if ($error) { ediv_die ("$error") };
    foreach my $ports (@db_resp) {
        wlog (VVV, "ports=\n" . Dumper(@db_resp));
        my $pids = `ps auxw | grep -i \"ssh -2 -q -f -N -o StrictHost\" | grep -i $$ports[0] | awk '{print \$2}'`;
        wlog (VV, "--   Executing:  kill -9 $pids", "" );
        system ("kill -9 $pids");
        #&daemonize($kill_command, "/dev/null");
    }
}

#
# Subroutine to launch background operations
#
sub daemonize {	
    my $command = shift;
    my $output = shift;
    unless ($output eq '/dev/null') { $output = "$EDIV_LOGS_DIR/$output" }
    wlog (V, "Backgrounded command:\n$command\n------> Log can be found at: $output", "");
    defined(my $pid = fork)		or ediv_die("Can't fork: $!");
    return if $pid;
    chdir $tmp_dir			    or ediv_die("Can't chdir to /: $!");
    open STDIN, '/dev/null'		or ediv_die("Can't read /dev/null: $!");
    open STDOUT, ">> $output"	or ediv_die("Can't write to $output: $!");
    open STDERR, ">> $output"	or ediv_die("Can't write to $output: $!");
    setsid						or ediv_die("Can't start a new session: $!");
    system("$command") == 0		or print "ERROR: Could not execute $command!";
    exit();
}

#
# Subroutine to execute execution mode in cluster
#
sub process_other_modes {
	
	my $error;
	my @db_resp;
    
    my %hosts_involved = get_hosts_involved();

    # foreach my $host_id (@cluster_active_hosts) {
    foreach my $host_id (keys %hosts_involved) {

        my $host_ip = get_host_ipaddr ($host_id);       
        my $host_tmpdir = get_host_vnxdir ($host_id) . "/scenarios/$scenario_name/tmp/";
        my $subscenario_name = get_host_subscenario_name ($host_id, $scenario_name);
        my $local_subscenario_fname = $dh->get_sim_tmp_dir . "/$subscenario_name".".xml";
        my $host_subscenario_fname = $host_tmpdir . "$subscenario_name".".xml";
        my $subscenario_xml = get_host_subscenario_xml ($host_id, $scenario_name, $local_subscenario_fname);

        wlog (VVV, "--  mode_create: host_id = $host_id, host_ip = $host_ip, host_tmpdir = $host_tmpdir");  
        wlog (VVV, "--  mode_create: subscenario_name = $subscenario_name");  
        wlog (VVV, "--  mode_create: local_subscenario_fname = $local_subscenario_fname");  
        wlog (VVV, "--  mode_create: host_subscenario_fname = $host_subscenario_fname");  

        unless  ( defined($subscenario_name) && defined($subscenario_xml) ) {
            ediv_die ("Cannot get subscenario name or subscenario XML file")
        }

		open(FILEHANDLE, ">$local_subscenario_fname") or ediv_die('cannot open file');
		print FILEHANDLE "$subscenario_xml";
		close (FILEHANDLE);
		
		my $scp_command = "scp -2 $local_subscenario_fname root\@$host_ip:$host_tmpdir";
		&daemonize($scp_command, "$host_id".".log");
			
		my $permissions_command = "ssh -2 -X -o 'StrictHostKeyChecking no' root\@$host_ip \'chmod -R 777 $host_subscenario_fname\'";
			
		&daemonize($permissions_command, "$host_id".".log"); 		
        my $option_M = '';
        if ($opts{M} || $opts{H}) { $option_M = "-M $hosts_involved{$host_id}"; }
		my $execution_command = "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnx -f $host_subscenario_fname $log_opt $mode " . $option_M . "; sleep $SSH_POST_DELAY'"; 
		&daemonize($execution_command, "$host_id".".log");
    }
}


# 
# initialize_and_check_scenario
#
# Does some initialization tasks and checks scenario file semantics 
#
sub initialize_and_check_scenario {
	
	my $input_file = shift;
	
	wlog (V, "---- initialize_and_check_scenario called: $input_file");
 
	# Build the VNX::BinariesData object
	$bd = new VNX::BinariesData($exemode);
    if ($bd->check_binaries_mandatory != 0) {
      &ediv_die ("some required binary files are missing\n");
    }
	
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
    my $doc = $parser->parsefile($input_file);   	
    $globalNode = $doc->getElementsByTagName("vnx")->item(0);
    $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;

    #print "****\n" . $doc->toString . "\n*****\n";   
	# Build the VNX::Execution object
	#$execution = new VNX::Execution($vnx_dir,$exemode,"host> ",'',$uid);

   	# Calculate the directory where the input_file lives
   	my $xml_dir = (fileparse(abs_path($input_file)))[1];

	# Build the VNX::DataHandler object
    $dh = new VNX::DataHandler($execution,$doc,$mode,$opts{M},$opts{H},$opts{'execute'},$xml_dir,$input_file);
   	
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
	my $dyn_conf_file = $dh->get_default_dynamips();
	if ($dyn_conf_file ne "0"){
		$dyn_conf_file = get_abs_path ($dyn_conf_file);
		my $error = validate_xml ($dyn_conf_file);
		if ( $error ) {
	        &ediv_die ("Dynamips XML configuration file ($dyn_conf_file) validation failed:\n$error\n");
		}
	}
	
=BEGIN	
    # if dynamips_ext node is present, update path
    $dynamips_ext_path = "";
    #my $dynamips_extTagList=$doc->getElementsByTagName("dynamips_ext");
    my $dynamips_extTagList=$dh->get_doc->getElementsByTagName("dynamips_ext");
    my $numdynamips_ext = $dynamips_extTagList->getLength;
    if ($numdynamips_ext == 1) {
        my $scenario_name=$globalNode->getElementsByTagName("scenario_name")->item(0)->getFirstChild->getData;
        $dynamips_ext_path = "$vnx_dir/scenarios/";
    }
=END
=cut    

    # Create the scenario working directory, if it doesn't already exist
    if (! -d "$vnx_dir/scenarios/$scenario_name" ) {
        mkdir "$vnx_dir/scenarios/$scenario_name" 
           or ediv_die("Unable to create scenario $scenario_name working directory $vnx_dir/$scenario_name: $!\n");
    }
    if (! -d "$vnx_dir/scenarios/$scenario_name/tmp" ) {
        mkdir "$vnx_dir/scenarios/$scenario_name/tmp" 
           or ediv_die("Unable to create scenario $scenario_name tmp directory $vnx_dir/$scenario_name/tmp: $!\n");
    }
    
    # Create scenario directories in every active cluster host
    foreach my $host_id (@cluster_active_hosts){
        my $host_ip = get_host_ipaddr ($host_id);
        my $host_vnxdir = get_host_vnxdir ($host_id);

        # Create directory $vnx_dir/$scenario_name and $vnx_dir/$scenario_name_$host_id 
        my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' -X root\@$host_ip " . 
                          "'mkdir -p $host_vnxdir/scenarios/${scenario_name}/tmp $host_vnxdir/scenarios/${scenario_name}_${host_id}'";
        wlog (V, "----   Creating scenario directories in active hosts");  
        &daemonize($ssh_command, "$host_id".".log");       

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
   printf "--------------------------------------------------------------------------------------------\n";
   printf "%s (%s): %s \n", (caller(1))[3], (caller(0))[2], $mess;
   printf "--------------------------------------------------------------------------------------------\n";
   exit 1;
}


# 
# get_hosts_involved
#
# Returns an associative array with the list of hosts involved in the current
# execution taking into account the -M and -H options. The keys of the array are the 
# hosts_id of the hosts involved and the values are a comma separated list
# of the vms involved which run on each host. 
#
sub get_hosts_involved {
	
    my %hosts_involved;

    wlog (VVV, "get_host_involved: allocation array ->" );
    foreach my $vm (keys(%allocation)) { wlog (V, "   $vm --> $allocation{$vm}") }
                
    my @vms = ediv_get_vm_to_use_ordered(); # List of VMs involved (taking into account -M and -H options)
    
    for ( my $i = 0; $i < @vms; $i++) {

        # get the host where the vm is running
        my $vm_name = $vms[$i]->getAttribute("name");
        wlog (V, "get_host_involved:  vm=$vm_name");
        #my $host_id = get_vm_host($vm_name);
        my $host_id = $allocation{$vm_name};
        wlog (V, "get_host_involved:  vm=$vm_name, host=$host_id");

        # add it to the list
        if (defined($hosts_involved{$host_id}) ) {
        	wlog (V, "get_host_involved:  adding ,$vm_name");
            $hosts_involved{$host_id} .= ",$vm_name"; 
        } else {
            wlog (V, "get_host_involved:  adding $vm_name");
            $hosts_involved{$host_id} = "$vm_name"; 
        }
    }            

    return %hosts_involved;
}            

#
# ediv_get_vm_to_use_ordered
#
# Returns an array with the vm names of the scenario to be used having 
# into account -M and -H option 
#
# Arguments:
# - none
#
# Returns:
# - @vms_ordered
#
sub ediv_get_vm_to_use_ordered {
    
    #my @plugins = @_;
   
    # The array to be returned at the end
    my @vms_ordered;
    wlog (VVV, "ediv_get_vm_to_use_ordered: opts{H}=$opts{H}") if defined($opts{H});
    wlog (VVV, "ediv_get_vm_to_use_ordered: opts{M}=$opts{M}") if defined($opts{M});
    
    my @vms = $dh->get_vm_ordered;
    for ( my $i = 0; $i < @vms; $i++) {
        my $name = $vms[$i]->getAttribute("name");
        my $host = $allocation{$name};
        wlog (VVV, "ediv_get_vm_to_use_ordered: checking $name at $host");
        if ($opts{M}) { # VNX has been invoked with option -M
                                    # Only select the vm if its name is on 
                                    # the comma separated list after "-M" 
            wlog (VVV, "ediv_get_vm_to_use_ordered: option -M $opts{M}"); 
            my $vm_list = $opts{M};
            if ($vm_list =~ /^$name,|,$name,|,$name$|^$name$/) {
                push (@vms_ordered, $vms[$i]);
                wlog (VVV, "ediv_get_vm_to_use_ordered:   added $name (M)");
                next; 
            } 
        } 
        if ($opts{H}) {
        	wlog (VVV, "ediv_get_vm_to_use_ordered: option -H $opts{H}"); 
            my $host_list = $opts{H};
            if ($host_list =~ /^$host,|,$host,|,$host$|^$host$/) {
                push (@vms_ordered, $vms[$i]);
                wlog (VVV, "ediv_get_vm_to_use_ordered:   added $name (H)");
            }
        }                    
        if ( !$opts{M} && !$opts{H} ) { # Neither -M nor -H option specified, always select the VM
            push (@vms_ordered, $vms[$i]);
        }
    }
    return @vms_ordered;
}

#
# get_allocation_from_db
#
# Gets VMs asignation to hosts from the database
#
sub get_allocation_from_db {

    my %allocation;

	my @vms = $dh->get_vm_ordered;
    for ( my $i = 0; $i < @vms; $i++) {
    	
        my $vm_name = $vms[$i]->getAttribute("name");
        my $host_id = get_vm_host ($vm_name);
        $allocation{$vm_name} = $host_id;
        wlog (VVV, "** get_allocation_from_db: $vm_name -> $host_id");
    }
    return %allocation;
	
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
       --console-info     -> shows information about all virtual machine consoles or the 
                             one specified with -M option.
       --console-info -b  -> the same but the information is provided in a compact format
       --console          -> opens the consoles of all vms, or just the ones speficied if -M is used. 
                             Only the consoles defined with display="yes" in VNX_file are opened.
       --console conX     -> opens 'conX' console (being conX the id of a console: con0, con1, etc) 
                             of all vms, or just the ones speficied if -M is used.                              
       Examples:
            ediv -f ex1.xml --console
            ediv -f ex1.xml --console --cid con0 -M A --> open console 0 of vm A of scenario ex1.xml

Cluster management modes:
       --check-cluster -> checks the status of each host in cluster and shows VNX version installed
       --update-host   -> updates the VNX software in the cluster hosts (install the version in the controller)
                          By default, updates all cluster hosts. If '-H host_list' is used, only the hosts
                          specified are updated 
       --clean-cluster -> completely resets the cluster, destroying all virtual machines in every host
                          (even those not started with VNX!), deleting EDIV database content and deleting
                          VNX working directory in every host.
                          WARNING!!: use this option with care. Confirmation is requested before proceeding.   

Database management modes:
       --create-db    -> creates EDIV database 
       --reset-db     -> deletes EDIV database content:
                            - with no aditional parameters, deletes the whole database content
                            - if a scenario name or scenario XML file is specified, only the 
                              database entries belonging to that scenario are deleted. For example:
                                 vnx --reset-db scenario1
                                 vnx --resed-db -f scenario1.xml
       --delete-db    -> completely deletes EDIV database 
       -y             -> use this option to disable interactive mode

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

