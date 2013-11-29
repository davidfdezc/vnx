#!/usr/bin/perl 
#!@PERL@
# ---------------------------------------------------------------------------------
# VNX parser. 
#
# Authors:    Fermin Galan Marquez (galan@dit.upm.es), David Fernández (david@dit.upm.es),
#             Jorge Somavilla (somavilla@dit.upm.es), Jorge Rodriguez (jrodriguez@dit.upm.es), 
# Coordinated by: David Fernández (david@dit.upm.es)
# Copyright (C) 2005-2012 DIT-UPM
#                         Departamento de Ingenieria de Sistemas Telematicos
#                         Universidad Politecnica de Madrid
#                         SPAIN
#			
# Available at:	  http://www.dit.upm.es/vnx 
#
# ----------------------------------------------------------------------------------
#
# VNX is the new version of VNUML tool adapted to use new virtualization platforms, 
# mainly by means of libvirt (libvirt.org), the standard API to control virtual 
# machines in Linux.
# VNUML was developed by DIT-UPM with the partial support from the European 
# Commission in the context of the Euro6IX research project (http://www.euro6ix.org).
#
# ----------------------------------------------------------------------------------
#
#
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# An online copy of the licence can be found at http://www.gnu.org/copyleft/gpl.html
# -----------------------------------------------------------------------------------

###########################################################
# Use clauses

# Explicit declaration of pathname for VNX  modules
#use lib "@PERL_MODULES_INSTALLROOT@";[JSF]
use lib "/usr/share/perl5";


use strict;
use warnings;
use File::Basename;
use File::Path;
use Cwd 'abs_path';
use Getopt::Long;
use IO::Socket;
#use Net::IPv6Addr;
use NetAddr::IP;
use Data::Dumper;

use XML::LibXML;

use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import

# VNX modules
use VNX::Globals;
use VNX::DataHandler;
use VNX::Execution;
use VNX::BinariesData;
use VNX::CheckSemantics;
use VNX::TextManipulation;
use VNX::NetChecks;
use VNX::FileChecks;
use VNX::DocumentChecks;
use VNX::IPChecks;
use VNX::vmAPICommon;
use VNX::vmAPI_uml;
use VNX::vmAPI_libvirt;
use VNX::vmAPI_dynamips;
use VNX::vmAPI_lxc;

use Error qw(:try);
use Exception::Class ( "Vnx::Exception" =>
		       { description => 'common exception',
                         fields => [ 'context' ]
                         },
		       ); 

#use Devel::StackTrace;
#$tracer = Devel::StackTrace->new;

# see man Exception::Class. a hack to use Exception::Class
# as a base class for Exceptions while using Error.pm, instead
# of its own Error::Simple
push @Exception::Class::Base::ISA, 'Error';

###########################################################
# Set up signal handlers

$SIG{INT} = \&handle_sig;
$SIG{TERM} = \&handle_sig;

###########################################################
# Global variables

# Version information (variables moved to VNX::Globals)
# my $version = "[arroba]PACKAGE_VERSION[arroba]";[JSF]
# my $release = "[arroba]RELEASE_DATE[arroba]";[JSF]
#$version = "1.92beta1";
$version = "MM.mm.rrrr"; # major.minor.revision
$release = "DD/MM/YYYY";
$branch = "";

my $valid_fail;	              # flag used to detect error during XML validation   

# List to store host names lines for <host_mapping> processing
my @host_lines;

# Name of UML whose boot process has started but not reached the init program
# (for emergency cleanup).  If the mconsole socket has successfully been initialized
# on the UML then '#' is appended.
my $curr_uml;

# VNX scenario file
my $input_file;

# Delay between virtual machines startup
#my $vmStartupDelay;

# Just a line...
my $hline = "----------------------------------------------------------------------------------";

# host log prompt
my $logp = "host> ";


&main;
exit(0);



###########################################################
# THE MAIN PROGRAM
#
sub main {
	
   	$ENV{'PATH'} .= ':/bin:/usr/bin/:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin';
   	
   	my $boot_timeout = 60; # by default, 60 seconds for boot timeout 
   	my $start_time;        # the moment when the parsers start operation


   	###########################################################
   	# To get the invocation arguments
    Getopt::Long::Configure ( qw{no_auto_abbrev no_ignore_case } ); # case sensitive single-character options
    GetOptions (\%opts,
                'define', 'undefine', 'start', 'create|t', 'shutdown|d', 'destroy|P',
                'save', 'restore', 'suspend', 'resume', 'reboot', 'reset', 'execute|x=s',
                'show-map', 'console:s', 'console-info', 'exe-info', 'clean-host',
                'create-rootfs=s', 'modify-rootfs=s', 'install-media=s', 'update-aced:s', 'mem=s', 'yes|y',
                'help|h', 'v', 'vv', 'vvv', 'version|V',
                'f=s', 'c=s', 'T=s', 'config|C=s', 'M=s', 'i', 'g',
                'user|u:s', '4', '6', 'D', 'no-console|n', 'st-delay=s',
                'e=s', 'w=s', 'F', 'B', 'o=s', 'Z', 'b', 'arch=s', 'vcpu=s' 
    ) or vnx_die("Incorrect usage. Type 'vnx -h' for help"); 

    #
    # Define the user VNX should run as.
    # '-u user' or '--user user' option is use to defines the user VNX is (mostly) run as. By now, VNX has
    # to be run with root priviledges (from a root shell or sudoed) for creating virtual machines and 
    # manipulate bridges and network interfaces.
    #
    # Present behaviour (provisional):
    #   '-u root' or '-u' option absent 
    #      -> VNX runs completely as root
    #   '-u' 
    #      -> VNX runs (mostly) as default user (the user from which sudo was issued) 
    #   '-u user' (NOT implemented yet)     
    #      -> VNX runs (mostly) as 'user'
    #
    my $uid_msg;
    $uid=$ENV{'SUDO_UID'};
    $uid_name=$ENV{'SUDO_USER'};

    # Check if we have root priviledges. Exit if not
    unless ($opts{'version'} or $opts{'help'} or ($#ARGV == -1)) {
	    if ($> ne 0) {
	        my $uname = getpwuid($>);
	        vnx_die ("ERROR: VNX needs to be executed as root or, better, sudoed root (current user=$uname,$>)");
	        exit (1);
	    }    	
    }

    if (defined($opts{'user'})) {
         # option --user specified
        if ($opts{'user'} eq '') {
            # --user option specified but no user name given: run as default user
	        $uid_msg = "  VNX executed as user $uid_name ($uid)\n";
	        $> = $uid;  # Change user to $uid. We only change to root when needed
        } else {
            # --user option specified with user name given: run as user
            #print "$opts{'user'} specified \n";
            if ($opts{'user'} eq 'root') {
                # run as root            	
		        $uid_msg = "  VNX executed as root\n";
		        $uid = 0;
		        $uid_name = 'root';     
            } elsif ($opts{'user'} eq $uid_name) {
                # run as default user. NOT IMPLEMENTED yet
	            $uid_msg = "  VNX executed as user $uid_name ($uid)\n";
	            $> = $uid;  # Change user to $uid. We only change to root when needed
            } else {
                # run as a different user. NOT IMPLEMENTED yet
                vnx_die ("ERROR: running VNX as a user different from root or the current user ($uid_name) not implemented yet.");
            }
        }
    } else {
    	# --user option not specified: run as root
        $uid_msg = "  VNX executed as root\n";
        $uid = 0;
        $uid_name = 'root';     
    }

   	# FIXME: as vnumlize process does not work properly in latest kernel/root_fs versions, we disable
   	# it by default
    #$args->set('Z',1);
    $opts{Z} = '1';
    
    unless ($opts{b}) {
    	print_header();
        print $uid_msg; 
    }

   	# Set configuration file 
   	if ($opts{'config'}) {
   	  	$vnxConfigFile = $opts{'config'}; 
   	} else {
   		$vnxConfigFile = $DEFAULT_CONF_FILE;
   	}
   	pre_wlog ("  CONF file: $vnxConfigFile") if (!$opts{b});
   
# change_to_root() # root permissions needed to read main config file
$>=0;
   	# Check the existance of the VNX configuration file 
   	unless ( (-e $vnxConfigFile) or ($opts{'version'}) or ($opts{'help'}) ) {
        vnx_die ("ERROR: VNX configuration file $vnxConfigFile not found");
   	}
   
   	# Set VNX and TMP directories
   	my $tmp_dir=get_conf_value ($vnxConfigFile, 'general', 'tmp_dir');
   	if (!defined $tmp_dir) {
   		$tmp_dir = $DEFAULT_TMP_DIR;
   	}
   	pre_wlog ("  TMP dir=$tmp_dir") if (!$opts{b});
   	my $vnx_dir=get_conf_value ($vnxConfigFile, 'general', 'vnx_dir');

    # vmfs_on_tmp
    $vmfs_on_tmp=get_conf_value ($vnxConfigFile, 'general', 'vmfs_on_tmp');
    #pre_wlog ("  vmfs_on_tmp=$vmfs_on_tmp") if (!$opts{b});     
    if (!defined $vmfs_on_tmp) {
        $vmfs_on_tmp = $DEFAULT_VMFS_ON_TMP;
    } elsif ( ($vmfs_on_tmp ne 'yes') and ($vmfs_on_tmp ne 'no') ) {
    	vnx_die ("ERROR in $vnxConfigFile: VNX configuration parameter 'general|vmfs_on_tmp'\n value must be 'yes' or 'no'");
    }
    if ($vmfs_on_tmp eq 'yes') {
        pre_wlog ("  VM FS on tmp=yes") if (!$opts{b});     
    }
# back_to_user()
$>=$uid;

   	if (!defined $vnx_dir) {
   		$vnx_dir = &do_path_expansion($DEFAULT_VNX_DIR);
   	} else {
   		$vnx_dir = &do_path_expansion($vnx_dir);
   	}
   	unless (valid_absolute_directoryname($vnx_dir) ) {
        vnx_die ("ERROR: $vnx_dir is not an absolute directory name");
   	}
   	pre_wlog ("  VNX dir=$vnx_dir") if (!$opts{b});

   	# To check arguments consistency
   	# 0. Check if -f is present
   	if ( !($opts{f}) && !($opts{'version'}) && !($opts{'help'}) && !($opts{D}) 
   	                 && !($opts{'clean-host'}) && !($opts{'create-rootfs'}) 
   	                 && !($opts{'modify-rootfs'}) ) {
   	  	&usage;
      	&vnx_die ("Option -f missing\n");
   	}

   	# 1. To use -t|--create, -x|--execute, -d|--shutdown, -V, -P|--destroy, --define, --start,
   	# --undefine, --save, --restore, --suspend, --resume, --reboot, --reset, --console, --console-info at the same time
   
   	my $how_many_args = 0;
   	my $mode_args = '';
   	my $mode;
   	if ($opts{'create'})           { $how_many_args++; $mode_args .= 'create|t ';      $mode = "create";       }
   	if ($opts{'execute'})          { $how_many_args++; $mode_args .= 'execute|x ';     $mode = "execute";	   }
   	if ($opts{'shutdown'})         { $how_many_args++; $mode_args .= 'shutdown|d ';    $mode = "shutdown";     }
   	if ($opts{'destroy'})          { $how_many_args++; $mode_args .= 'destroy|P ';     $mode = "destroy";	   }
   	if ($opts{'version'})          { $how_many_args++; $mode_args .= 'version|V ';     $mode = "version";      }
   	if ($opts{'help'})             { $how_many_args++; $mode_args .= 'help|h ';        $mode = "help";         }
   	if ($opts{'define'})           { $how_many_args++; $mode_args .= 'define ';        $mode = "define";       }
   	if ($opts{'start'})            { $how_many_args++; $mode_args .= 'start ';         $mode = "start";        }
   	if ($opts{'undefine'})         { $how_many_args++; $mode_args .= 'undefine ';      $mode = "undefine";     }
   	if ($opts{'save'})             { $how_many_args++; $mode_args .= 'save ';          $mode = "save";         }
   	if ($opts{'restore'})          { $how_many_args++; $mode_args .= 'restore ';       $mode = "restore";      }
   	if ($opts{'suspend'})          { $how_many_args++; $mode_args .= 'suspend ';       $mode = "suspend";      }
   	if ($opts{'resume'})           { $how_many_args++; $mode_args .= 'resume ';        $mode = "resume";       }
   	if ($opts{'reboot'})           { $how_many_args++; $mode_args .= 'reboot ';        $mode = "reboot";       }
   	if ($opts{'reset'})            { $how_many_args++; $mode_args .= 'reset ';         $mode = "reset";        }
   	if ($opts{'show-map'})         { $how_many_args++; $mode_args .= 'show-map ';      $mode = "show-map";     }
   	if (defined($opts{'console'})) { $how_many_args++; $mode_args .= 'console ';       $mode = "console";      }
   	if ($opts{'console-info'})     { $how_many_args++; $mode_args .= 'console-info ';  $mode = "console-info"; }
    if ($opts{'exe-info'})         { $how_many_args++; $mode_args .= 'exe-info ';      $mode = "exe-info";     }
    if ($opts{'clean-host'})       { $how_many_args++; $mode_args .= 'clean-host ';    $mode = "clean-host";   }
    if ($opts{'create-rootfs'})    { $how_many_args++; $mode_args .= 'create-rootfs '; $mode = "create-rootfs";}
    if ($opts{'modify-rootfs'})    { $how_many_args++; $mode_args .= 'modify-rootfs '; $mode = "modify-rootfs";}
    chop ($mode_args);
    
   	if ($how_many_args gt 1) {
      	&usage;
        &vnx_die ("Only one of the following options can be specified at a time: '$mode_args'");
        #&vnx_die ("Only one of the following options at a time:\n -t|--create, -x|--execute, -d|--shutdown, " .
      	#          "-V, -P|--destroy, --define, --start,\n --undefine, --save, --restore, --suspend, " .
      	#          "--resume, --reboot, --reset, --showmap, --clean-host, --create-rootfs, --modify-rootfs or -H");
   	}
   	if ( ($how_many_args lt 1) && (!$opts{D}) ) {
      	&usage;
      	&vnx_die ("missing main mode option. Specify one of the following options: \n" . 
      	          "  -t|--create, -x|--execute, -d|--shutdown, -V, -P|--destroy, --define, \n" . 
      	          "  --start, --undefine, --save, --restore, --suspend, --resume, --reboot, --reset, \n" . 
      	          "  --show-map, --console, --console-info, --clean-host, --create-rootfs, --modify-rootfs, -V or -H\n");
   	}
   	if (($opts{F}) && (!($opts{'shutdown'}))) { 
      	&usage; 
      	&vnx_die ("Option -F only makes sense with -d|--shutdown mode\n"); 
   	}
   	if (($opts{B}) && ($opts{F}) && ($opts{'shutdown'})) {
      	&vnx_die ("Option -F and -B are incompabible\n");
   	}
#    if (($opts{o}) && (!($opts{'create'}))) {
#      	&usage;
#      	&vnx_die ("Option -o only makes sense with -t|--create mode\n");
#   	}
   	if (($opts{w}) && (!($opts{'create'}))) {
      	&usage;
      	&vnx_die ("Option -w only makes sense with -t|--create mode\n");
   	}
  	if (($opts{e}) && (!($opts{'create'}))) {
      	&usage;
      	&vnx_die ("Option -e only makes sense with -t|--create mode\n");
   	}
#   	if (($opts{Z}) && (!($opts{'create'}))) {
#      	&usage;
#      	&vnx_die ("Option -Z only makes sense with -t|--create mode\n");
#   	}
   	if (($opts{4}) && ($opts{6})) {
      	&usage;
      	&vnx_die ("-4 and -6 can not be used at the same time\n");
   	}
   	if ( $opts{'no-console'} && (!($opts{'create'}))) {
      	&usage;
      	&vnx_die ("Option -n|--no-console only makes sense with -t|--create mode\n");
   	}

    # 2. Optional arguments
    $exemode = $EXE_NORMAL; $EXE_VERBOSITY_LEVEL=N;
    if ($opts{v})   { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=V }
    if ($opts{vv})  { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=VV }
    if ($opts{vvv}) { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=VVV }
    $exemode = $EXE_DEBUG if ($opts{g});
    chomp(my $pwd = `pwd`);
    $vnx_dir = &chompslash($opts{c}) if ($opts{c});
    $vnx_dir = "$pwd/$vnx_dir"
           unless (&valid_absolute_directoryname($vnx_dir));
    $tmp_dir = &chompslash($opts{T}) if ($opts{T});
    $tmp_dir = "$pwd/$tmp_dir"
           unless (&valid_absolute_directoryname($tmp_dir));    


    # DFC 21/2/2011 $uid = getpwnam($opts{u) if ($> == 0 && $opts{u);
    $boot_timeout = $opts{w} if (defined($opts{w}));
    unless ($boot_timeout =~ /^\d+$/) {
        &vnx_die ("-w value ($opts{w}) is not a valid timeout (positive integer)\n");  
    }

    # FIXME: $enable_4 and $enable_6 are not necessary, use $args object
    # instead and avoid redundance
    my $enable_4 = 1;
    my $enable_6 = 1;
    $enable_4 = 0 if ($opts{6});
    $enable_6 = 0 if ($opts{4});   
    
    # Delay between vm startup
#       $vmStartupDelay = $opts{'st-delay'} if ($opts{'st-delay'});
        
    # 3. To extract and check input
    $input_file = $opts{f} if ($opts{f});

    # Check for file and cmd_seq, depending the mode
    my $cmdseq = '';
    if ($opts{'execute'}) {
        $cmdseq = $opts{'execute'}
    } 
    
    # Reserved words for cmd_seq
    #if ($cmdseq eq "always") {
    #   &vnuml_die ("\"always\" is a reserved word and can not be used as cmd_seq\n");
    #}

    # 4. To check vnx_dir and tmp_dir
    # Create the working directory, if it doesn't already exist
    if ($exemode ne $EXE_DEBUG) {
        if (! -d $vnx_dir ) {
            mkdir $vnx_dir or &vnx_die("Unable to create working directory $vnx_dir: $!\n");
        }

# DFC 21/2/2011: changed to simplify the user which executes vnx:
#                   - option -u ignored
#                   - no owner changes in any directory
#                   - vnx is executed always as the user that starts it (root if the command is preceded by sudo)
#       if ($> == 0) { # vnx executed as root
#            my $uid_name = getpwuid($uid);
#            system("chown $uid $vnx_dir");
#            $> = $uid;
#            my $uid_name = getpwuid($uid);
             &vnx_die ("vnx_dir $vnx_dir does not exist or is not readable/executable (user $uid_name)\n") unless (-r $vnx_dir && -x _);
             &vnx_die ("vnx_dir $vnx_dir is not writeable (user $uid_name)\n") unless ( -w _);
             &vnx_die ("vnx_dir $vnx_dir is not a valid directory\n") unless (-d _);
#            $> = 0;
#       }


        if (! -d "$vnx_dir/scenarios") {
            mkdir "$vnx_dir/scenarios" or &vnx_die("Unable to create scenarios directory $vnx_dir/scenarios: $!\n");
        }
        if (! -d "$vnx_dir/networks") {
            mkdir "$vnx_dir/networks" or &vnx_die("Unable to create networks directory $vnx_dir/networks: $!\n");
        }
    }
    &vnx_die ("tmp_dir $tmp_dir does not exist or is not readable/executable\n") unless (-r $tmp_dir && -x _);
    &vnx_die ("tmp_dir $tmp_dir is not writeable\n") unless (-w _);
    &vnx_die ("tmp_dir $tmp_dir is not a valid directory\n") unless (-d _);

    # 5. To build the VNX::BinariesData object
    $bd = new VNX::BinariesData($exemode);

    # 6a. To check mandatory binaries # [JSF] to be updated with new ones
    if ($bd->check_binaries_mandatory != 0) {
      &vnx_die ("some required binary files are missing\n");
    }

    # Interactive execution (press a key after each command)
    my $exeinteractive = ($opts{v} || $opts{vv} || $opts{vvv}) && $opts{i};

    # Build the VNX::Execution object
    $execution = new VNX::Execution($vnx_dir,$exemode,"host> ",$exeinteractive,$uid,$opts{o});

    #
    # Process pseudomodes (modes that do not need a scenario file)
    # 
   	# Version pseudomode
   	if ($opts{'version'}) {
   		print_version();
   	}

    # Help pseudomode
    if ($opts{'help'}) {
        &usage;
        exit(0);
    }

    # Clean host pseudomode
    if ($opts{'clean-host'}) {
        mode_cleanhost($vnx_dir);
        exit(0);
    }
    
    # Create root filesystem pseudomode
    if ($opts{'create-rootfs'}) {
change_to_root();
        unless ( -f $opts{'create-rootfs'} ) {
            vnx_die ("file $opts{'create-rootfs'} is not valid (perhaps does not exists)");
        }
        wlog (VVV, "install-media = $opts{'install-media'}", $logp);
        unless ( $opts{'install-media'} ) {
            vnx_die ("option 'install-media' not defined");
        }
        unless ( $opts{'install-media'} && -f $opts{'install-media'} ) {
            vnx_die ("file $opts{'install-media'} is not valid (perhaps does not exists)");
        }
back_to_user();        
        mode_createrootfs($tmp_dir, $vnx_dir);
        exit(0);
    }

    # Modify root filesystem pseudomode
    if ($opts{'modify-rootfs'}) {
change_to_root();
        unless ( -f $opts{'modify-rootfs'} ) {
            vnx_die ("file $opts{'modify-rootfs'} is not valid (perhaps does not exists)");
        }
back_to_user();
        mode_modifyrootfs($tmp_dir, $vnx_dir);
        exit(0);
    }
    
   	
   	# Delete LOCK file if -D option included
   	if ($opts{D}) {
   	  	pre_wlog ("Deleting ". $vnx_dir . "/LOCK file");
	  	system "rm -f $vnx_dir/LOCK"; 
	  	if ($how_many_args lt 1) {
	     	exit(0);
	  	}  
   	}	


    # Check input file
    if (! -f $input_file ) {
        &vnx_die ("file $input_file is not valid (perhaps does not exists)\n");
    }

   	# 7. To check version number
	# Load XML file content
	open INPUTFILE, "$input_file";
	my @xmlContent = <INPUTFILE>;
	my $xmlContent = join("",@xmlContent);
	close INPUTFILE;

   	if ($xmlContent =~ /<version>\s*(\d\.\d+)(\.\d+)?\s*<\/version>/) {
      	my $version_in_file = $1;
      	$version =~ /^(\d\.\d+)/;
      	my $version_in_parser = $1;
      	unless ($version_in_file eq $version_in_parser) {
      		vnx_die("mayor version numbers of source file ($version_in_file) and parser ($version_in_parser) do not match");
			exit;
      	}
   	} else {
      	vnx_die("can not find VNX version in $input_file");
   	}
  
   	# 8. To check XML file existance and readability and
   	# validate it against its XSD language definition
	my $error;
	$error = validate_xml ($input_file);
	if ( $error ) {
        vnx_die ("XML file ($input_file) validation failed:\n$error\n");
	}

   	# Create DOM tree
	my $parser = XML::LibXML->new();
    my $doc = $parser->parse_file($input_file);
    
       	       	
   	# Calculate the directory where the input_file lives
   	my $xml_dir = (fileparse(abs_path($input_file)))[1];

   	# Build the VNX::DataHandler object
   	$dh = new VNX::DataHandler($execution,$doc,$mode,$opts{M},$opts{H},$cmdseq,$xml_dir,$input_file);
   	$dh->set_boot_timeout($boot_timeout);
   	$dh->set_vnx_dir($vnx_dir);
   	$dh->set_tmp_dir($tmp_dir);
   	$dh->enable_ipv6($enable_6);
   	$dh->enable_ipv4($enable_4);   

   	# User check (deprecated: only root or a user with 'sudo vnx ...' permissions can execute VNX)
   	#if (my $err_msg = &check_user) {
    #  	&vnx_die("$err_msg\n");
   	#}

   	# Deprecation warnings
   	&check_deprecated;

   	# Semantic check (in addition to validation)
   	if (my $err_msg = &check_doc($bd->get_binaries_path_ref,$execution->get_uid)) {
      	&vnx_die ("$err_msg\n");
   	}
   
   	# Validate extended XML configuration files
	# Dynamips
	my $dmipsConfFile = $dh->get_default_dynamips();
	if ($dmipsConfFile ne "0"){
		$dmipsConfFile = get_abs_path ($dmipsConfFile);
		my $error = validate_xml ($dmipsConfFile);
		if ( $error ) {
	        &vnx_die ("Dynamips XML configuration file ($dmipsConfFile) validation failed:\n$error\n");
		}
	}
	# Olive
	my $oliveConfFile = $dh->get_default_olive();
	if ($oliveConfFile ne "0"){
		$oliveConfFile = get_abs_path ($oliveConfFile);
		my $error = validate_xml ($oliveConfFile);
		if ( $error ) {
	        &vnx_die ("Olive XML configuration file ($oliveConfFile) validation failed:\n$error\n");
		}
	}
   	# 6b (delayed because it required the $dh object constructed)
   	# To check optional screen binaries
   	$bd->add_additional_screen_binaries();
   	if (($opts{e}) && ($bd->check_binaries_screen != 0)) {
      	&vnx_die ("screen related binary is missing\n");
   	}

   	# 6c (delayed because it required the $dh object constructed)
   	# To check optional uml_switch binaries 
   	$bd->add_additional_uml_switch_binaries();
   	if (($bd->check_binaries_switch != 0)) {
      	&vnx_die ("uml_switch related binary is missing\n");
   	}

   	# 6d (delayed because it required the $dh object constructed)
   	# To check optional binaries for virtual bridge
   	$bd->add_additional_bridge_binaries();   
   	if ($bd->check_binaries_bridge != 0) {
      	&vnx_die ("virtual bridge related binary is missing\n");  
   	}

    # 6e (delayed because it required the $dh object constructed)
    # To check xterm binaries
    $bd->add_additional_xterm_binaries();
    if (($bd->check_binaries_xterm != 0)) {
        &vnx_die ("xterm related binary is missing\n");
    }

    # 6f (delayed because it required the $dh object constructed)
    # To check optional binaries for VLAN support
    $bd->add_additional_vlan_binaries();   
    if ($bd->check_binaries_vlan != 0) {
        &vnx_die ("VLAN related binary is missing\n");  
    }   

    # Complete fields in Execution object that need the DataHandler and
    # the binaries_path hash built
    $execution->set_mconsole_binary($bd->get_binaries_path_ref->{"uml_mconsole"});
   
    #     
   	# Initialize plugins
    #
    push (@INC, "/usr/share/vnx/plugins");
  
   	foreach my $extension ( $dh->get_doc->getElementsByTagName("extension") ) {
      	my $plugin = $extension->getAttribute("plugin");
      	my $plugin_conf = $extension->getAttribute("conf");
      
        if (defined($plugin_conf)) {
            # Check Plugin Configuration File (PCF) existance
            $plugin_conf = &get_abs_path($plugin_conf);
	        if (! -f $plugin_conf) {
	            &vnx_die ("plugin $plugin configuration file $plugin_conf is not valid (perhaps does not exists)\n");
	        }
        }
              
      	wlog (V, "Loading pluging: $plugin...", $logp);      
      	# Why we are not using 'use'? See the following thread: 
      	# http://www.mail-archive.com/beginners%40perl.org/msg87441.html)   

      	eval "require $plugin";
      	eval "import $plugin";
      	
=BEGIN
      	eval {
    		require $plugin;
    		#$plugin->import();
    		import $plugin;
    		1;
		} or do {
   			my $error = $@;
   			print "** ERROR loading plugin: $error";
		};
=END
=cut	
      	
      	if (my $err_msg = $plugin->initPlugin($mode,$plugin_conf,$doc)) {
         	&vnx_die ("plugin $plugin reports error: $err_msg\n");
      	}
      	push (@plugins,$plugin);
   	}

    # Initialize vmAPI modules
    VNX::vmAPI_uml->init;
    VNX::vmAPI_libvirt->init;
    VNX::vmAPI_dynamips->init;
    VNX::vmAPI_lxc->init;
    pre_wlog ($hline)  if (!$opts{b});


   	if ($exeinteractive) {
      	wlog (N, "interactive execution is on: press a key after each command");
   	}

   	# Lock management
   	if (-f $dh->get_vnx_dir . "/LOCK") {
      	my $basename = basename $0;
      	vnx_die($dh->get_vnx_dir . "/LOCK exists: another instance of $basename seems to be in execution\nIf you are sure that this can't be happening in your system, delete LOCK file with 'vnx -D' or a 'rm " . $dh->get_vnx_dir . "/LOCK' and try again\n");
   	}
   	else {
      	$execution->execute($logp, $bd->get_binaries_path_ref->{"touch"} . " " . $dh->get_vnx_dir . "/LOCK");
      	$start_time = time();
   	}

   	# Mode selection
   	if ($mode eq 'create') {
	   	if ($exemode != $EXE_DEBUG && !$opts{M} && !$opts{'start'}) {
         	$execution->smartdie ("scenario " . $dh->get_scename . " already created\n") 
            	if &scenario_exists($dh->get_scename);
      	}
      	mode_define();
      	mode_start();
   	}
   	elsif ($mode eq 'execute') {
      	if ($exemode != $EXE_DEBUG) {
         	$execution->smartdie ("scenario " . $dh->get_scename . " does not exists: create it with -t before\n")
           		unless &scenario_exists($dh->get_scename);
      	}

      	mode_execute($cmdseq);
   	}
   	elsif ($mode eq 'shutdown') {
      	if ($exemode != $EXE_DEBUG) {
         	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
           		unless &scenario_exists($dh->get_scename);
      	}
      	mode_shutdown();
#      my $do_not_build_topology = 1; 
   	}
   	elsif ($mode eq 'destroy') {  # elsif ($opts{P) { [JSF]
      	#if ($exemode != $EXE_DEBUG) {
      	#   $execution->smartdie ("scenario $scename does not exist\n")
      	#     unless &scenario_exists($scename);
      	#}
      	#$args->set('F',1);
      	$opts{F} = '1';
        mode_shutdown('do_not_exe_cmds');  # First, call destroy mode with force flag activated
      	mode_destroy();		# Second, purge other things
   	}
   	elsif ($mode eq 'define') {
      	if ($exemode != $EXE_DEBUG && !$opts{M}) {
         	$execution->smartdie ("scenario " . $dh->get_scename . " already created\n") 
            	if &scenario_exists($dh->get_scename);
      	}
      	mode_define();
   	}
   	elsif ($mode eq 'undefine') {
      	if ($exemode != $EXE_DEBUG && !$opts{M}) {
         	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
           		unless &scenario_exists($dh->get_scename);
      	}
      	mode_undefine();
   	}
   	elsif ($mode eq 'start') {
      	if ($exemode != $EXE_DEBUG) {
         	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
           		unless &scenario_exists($dh->get_scename);
      	}
      	mode_start();
   	}
   	elsif ($mode eq 'reset') {
      	if ($exemode != $EXE_DEBUG) {
         	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
           		unless &scenario_exists($dh->get_scename);
      	}
      	#$args->set('F',1);
      	$opts{F} = '1';
      	mode_shutdown();		# First, call destroy mode with force flag activated
      	mode_destroy();		# Second, purge other things
      	sleep(1);     # Let it finish
      	mode_define();
      	mode_start();
   	}
   
   	elsif ($mode eq 'reboot') {
     	if ($exemode != $EXE_DEBUG) {
        	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        	unless &scenario_exists($dh->get_scename);
     	}   	
     	mode_shutdown();
     	mode_start();
   	}
   
   	elsif ($mode eq 'save') {
     	if ($exemode != $EXE_DEBUG) {
        	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        	unless &scenario_exists($dh->get_scename);
     	}
     	mode_save();
   	}
   	elsif ($mode eq 'restore') {
     	if ($exemode != $EXE_DEBUG) {
        	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        		unless &scenario_exists($dh->get_scename);
     	}
     	mode_restore();
   	}
   
   	elsif ($mode eq 'suspend') {
     	if ($exemode != $EXE_DEBUG) {
        	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        		unless &scenario_exists($dh->get_scename);
     	}
     	mode_suspend();
   	}
   
   	elsif ($mode eq 'resume') {
     	if ($exemode != $EXE_DEBUG) {
        	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        	unless &scenario_exists($dh->get_scename);
     	}
     	mode_resume();
   	}
   
   	elsif ($mode eq 'show-map') {
#     	if ($exemode != $EXE_DEBUG) {
#        	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
#        	unless &scenario_exists($dh->get_scename);
#     	}
     	mode_showmap();
   	}
   
   	elsif ($mode eq 'console') {
     	if ($exemode != $EXE_DEBUG) {
        	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        	unless &scenario_exists($dh->get_scename);
     	}
		mode_console();
   	}
   	elsif ($mode eq 'console-info') {
     	if ($exemode != $EXE_DEBUG) {
        	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        	unless &scenario_exists($dh->get_scename);
     	}
   		mode_consoleinfo();
   	}
    elsif ($mode eq 'exe-info') {
        mode_exeinfo();
    }
   
    else {
        $execution->smartdie("if you are seeing this text something terribly horrible has happened...\n");
    }

    # Call the finalize subrutine in plugins
    foreach my $plugin (@plugins) {
        $plugin->finalizePlugin;
    }
   
    # Remove lock
    $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_vnx_dir . "/LOCK");
    my $total_time = time() - $start_time;
    wlog (N, $hline);
    wlog (N, "Total time elapsed: $total_time seconds");
    wlog (N, $hline);

}


sub mode_define {
	
   my $basename = basename $0;

   unless ($opts{M} ){ #|| $do_not_build){
      build_topology();
   }

    try {
        # 7. Set appropriate permissions and boot each UML
        # DFC 21/2/2011 &chown_working_dir;
        &xauth_add; # es necesario??

        define_VMs();    
    } 
    catch Vnx::Exception with {
	   my $E = shift;
	   wlog (N, $E->as_string);
	   wlog (N, $E->message);
    } 
    catch Error with {
	   my $E = shift;
	   wlog (N, "ERROR: " . $E->text . " at " . $E->file . ", line " .$E->line);
	   wlog (N, $E->stringify);
    }
}

sub define_VMs {

   my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   

   my $dom;
   
   # If defined screen configuration file, open it
   if (($opts{e}) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
      open SCREEN_CONF, ">". $opts{e}
         or $execution->smartdie ("can not open " . $opts{e} . ": $!")
   }

   # management ip counter
   my $mngt_ip_counter = 0;
   
   # passed as parameter to API
   #   equal to $mngt_ip_counter if no mng_if file found
   #   value "file" if mng_if file found in run dir
   my $mngt_ip_data;
   
   my $docstring;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {

      my $vm = $vm_ordered[$i];
      my $vm_name = $vm->getAttribute("name");
      my $merged_type = $dh->get_vm_merged_type($vm);
      $curr_uml = $vm_name;
      
      # check for existing management ip file stored in run dir
      # update manipdata for current vm accordingly
      if (-f $dh->get_vm_dir($vm_name) . '/mng_ip'){
         $mngt_ip_data = "file";   
      }else{
         $mngt_ip_data = $mngt_ip_counter;
      }
      
      $docstring = &make_vmAPI_doc($vm,$i,$mngt_ip_data); 
           
      # call the corresponding vmAPI->defineVM
      my $vm_type = $vm->getAttribute("type");
      wlog (N, "Defining virtual machine '$vm_name' of type '$merged_type'...");
      my $error = "VNX::vmAPI_$vm_type"->defineVM($vm_name, $merged_type, $docstring);
      if ($error ne 0) {
          wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->defineVM returns " . $error);
      } else {
          wlog (N, "...OK")
      }
      $mngt_ip_counter++ unless ($mngt_ip_data eq "file"); #update only if current value has been used
      undef($curr_uml);
      &change_vm_status($vm_name,"defined");

   }

   # Close screen configuration file
   if (($opts{e}) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
      close SCREEN_CONF;
   }
}

sub mode_undefine{

    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option
	   
    for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);
           
        my $status_file = $dh->get_vm_dir($vm_name) . "/status";
        next if (! -f $status_file);
        my $command = $bd->get_binaries_path_ref->{"cat"} . " $status_file";
        chomp(my $status = `$command`);
        if (!(($status eq "shut off")||($status eq "defined"))){
            $execution->smartdie ("virtual machine $vm_name cannot be undefined from status \"$status\"\n");
            next;
        }
        # call the corresponding vmAPI
        my $vm_type = $vm->getAttribute("type");
        wlog (N, "Undefining virtual machine '$vm_name' of type '$merged_type'...");
        my $error = "VNX::vmAPI_$vm_type"->undefineVM($vm_name, $merged_type);
        if ($error ne 0) {
            wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->undefineVM returns " . $error);
        } else {
            wlog (N, "...OK")
        }
    }
}

sub mode_start {

   my $basename = basename $0;

    try {

#        # 7. Set appropriate permissions and boot each UML
#        &chown_working_dir;
#        &xauth_add;

        start_VMs();
        set_vlan_links();
         
        # If <host_mapping> is in use and not in debug mode, process /etc/hosts
        my $lines = join "\n", @host_lines;
        &host_mapping_patch ($dh->get_scename, "/etc/hosts") 
            if (($dh->get_host_mapping) && ($execution->get_exe_mode() != $EXE_DEBUG)); # lines in the temp file

        # If -B, block until ready
        if ($opts{B}) {
            my $time_0 = time();
            my %vm_ips = &get_UML_command_ip("");
            while (!&UMLs_cmd_ready(%vm_ips)) {
                #system($bd->get_binaries_path_ref->{"sleep"} . " $dh->get_delay");
                sleep($dh->get_delay);
                my $time_w = time();
                my $interval = $time_w - $time_0;
                wlog (N,  "$interval seconds elapsed...");
                %vm_ips = &get_UML_command_ip("");
            }
        }
        
        my $scename = $dh->get_scename;
       	wlog (N,"\n" . $hline);
		wlog (N,  " Scenario \"$scename\" started");
        # Print information about vm consoles
        &print_consoles_info;
    } 
    catch Vnx::Exception with {
	   my $E = shift;
	   wlog (N,  $E->as_string);
	   wlog (N,  $E->message);    
    } 
    catch Error with {
	   my $E = shift;
	   wlog (N,  "ERROR: " . $E->text . " at " . $E->file . ", line " .$E->line);
	   wlog (N,  $E->stringify);
    }
}

sub set_vlan_links {

    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account
    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        foreach my $if ($vm->getElementsByTagName("if")){
            if ( (get_net_by_mode($if->getAttribute("net"),"openvswitch") != 0)&& $if->getElementsByTagName("vlan")) {
                my $if_id = $if->getAttribute("id");
                my @vlan=$if->getElementsByTagName("vlan");
                my $vlantag= $vlan[0];                          
                my $trunk = $vlantag->getAttribute("trunk");
                my $port_name="$vm_name"."-e"."$if_id";
                my $tagConcatenation="";
                my $vlan_number=0;
                foreach my $tag ($vlantag->getElementsByTagName("tag")){
                    my $tag_id=$tag->getAttribute("id");
                    $tagConcatenation.="$tag_id".",";
                    $vlan_number=$vlan_number+1;    
                }
                        
                if ($trunk eq 'yes'){
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set port $port_name "."trunk=$tagConcatenation");
                } else {
                    if($vlan_number eq 1){
                        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set port $port_name "."tag=$tagConcatenation");
                    } else {  
                        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set port $port_name "."trunk=$tagConcatenation");
                    }

                                
                }
            }
        }
     }
}

sub start_VMs {

    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   
 
    # If defined screen configuration file, open it
    if (($opts{e}) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
        open SCREEN_CONF, ">". $opts{e}
            or $execution->smartdie ("can not open " . $opts{e} . ": $!")
    }

    for ( my $i = 0; $i < @vm_ordered; $i++) {

        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);
      
        # search for <on_boot> tag and if found then process it
        my $on_boot; 
        eval {$on_boot = $vm->getElementsByTagName("on_boot")->item(0)->getFirstChild->getData};
        if ( (defined $on_boot) and ($on_boot eq 'no')) {
            # do not start vm unless specified in -M
            unless ( (defined $opts{M}) && ($opts{M} =~ /^$vm_name,|,$vm_name,|,$vm_name$|^$vm_name$/) ) {
                next;
            }
        }
      
        $curr_uml = $vm_name;
     
        #check for option -n||--no-console (do not start consoles)
        my $no_console = "0";
        if ($opts{'no-console'}){
            $no_console = "1";
        }
      
        # call the corresponding vmAPI
        my $vm_type = $vm->getAttribute("type");
        wlog (N, "Starting virtual machine '$vm_name' of type '$merged_type'...");
        my $error = "VNX::vmAPI_$vm_type"->startVM($vm_name, $merged_type, $no_console);
        if ($error ne 0) {
            wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->startVM returns " . $error);
        } else {
        	wlog (N, "...OK");
        }
 
        my $mng_if_value = &mng_if_value( $vm );
        # To configure management device (id 0), if needed
        if ( $dh->get_vmmgmt_type eq 'private' && $mng_if_value ne "no" ) {
            # As the VM has necessarily been previously defined, the management ip address is already defined in file
            # (get_admin_address has been called from make_vmAPI_doc ) 
            my %net = &get_admin_address( 'file', $vm_name );
            #$execution->execute($logp,  $bd->get_binaries_path_ref->{"ifconfig"}
            #    . " $vm_name-e0 " . $net{'host'}->addr() . " netmask " . $net{'host'}->mask() . " up" );
            my $ip_addr = NetAddr::IP->new($net{'host'}->addr(),$net{'host'}->mask());

change_to_root();
			$execution->execute($logp, $bd->get_binaries_path_ref->{"ip"} . " link set dev $vm_name-e0 up");
			$execution->execute($logp, $bd->get_binaries_path_ref->{"ip"} . " addr add " . $ip_addr->cidr() . " dev $vm_name-e0");
back_to_user();               
        }

        undef($curr_uml);
        &change_vm_status($vm_name,"running");
          
        if ( (defined $opts{'st-delay'})    # delay has been specified in command line and... 
            && ( $i < @vm_ordered-2 ) ) { # ...it is not the last virtual machine started...
            for ( my $count = $opts{'st-delay'}; $count > 0; --$count ) {
                printf "** Waiting $count seconds...\n";
                sleep 1;
                print "\e[A";
            }
        }
    }

    # Close screen configuration file
    if (($opts{e}) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
        close SCREEN_CONF;
    }
}

sub mode_reset {
	
   my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      my $vm_name = $vm->getAttribute("name");
      my $merged_type = $dh->get_vm_merged_type($vm);
      # call the corresponding vmAPI
      my $vm_type = $vm->getAttribute("type");
      wlog (N, "Reseting virtual machine '$vm_name' of type '$merged_type'...");
      my $error = "VNX::vmAPI_$vm_type"->resetVM($vm_name, $merged_type);
      if ($error ne 0) {
          wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->resetVM returns " . $error);
      } else {
          wlog (N, "...OK")
      }
   }
}

sub mode_save {

   my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   
   my $filename;

   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      my $vm_name = $vm->getAttribute("name");
      my $merged_type = $dh->get_vm_merged_type($vm);
      $filename = $dh->get_vm_dir($vm_name) . "/" . $vm_name . "_savefile";

      # call the corresponding vmAPI
      my $vm_type = $vm->getAttribute("type");
      wlog (N, "Pausing virtual machine '$vm_name' of type '$merged_type' and saving state to disk...");
      my $error = "VNX::vmAPI_$vm_type"->saveVM($vm_name, $merged_type, $filename);
      if ($error ne 0) {
        wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->saveVM returns " . $error);
      } else {
        wlog (N, "...OK")
      }
   }
}

sub mode_restore {

   my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   
   my $filename;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      # To get name attribute
      my $vm_name = $vm->getAttribute("name");
      my $merged_type = $dh->get_vm_merged_type($vm);
      $filename = $dh->get_vm_dir($vm_name) . "/" . $vm_name . "_savefile";

      # call the corresponding vmAPI
      my $vm_type = $vm->getAttribute("type");
      wlog (N, "Restoring virtual machine '$vm_name' of type '$merged_type' state from disk...");
      my $error = "VNX::vmAPI_$vm_type"->restoreVM($vm_name, $merged_type, $filename);
      if ($error ne 0) {
          wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->restoreVM returns " . $error);
      } else {
          wlog (N, "...OK")
      }
   }
}

sub mode_suspend {

   my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      my $vm_name = $vm->getAttribute("name");
      my $merged_type = $dh->get_vm_merged_type($vm);

      # call the corresponding vmAPI
      my $vm_type = $vm->getAttribute("type");
      wlog (N, "Suspending virtual machine '$vm_name' of type '$merged_type'...");
      my $error = "VNX::vmAPI_$vm_type"->suspendVM($vm_name, $merged_type);
      if ($error ne 0) {
          wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->suspendVM returns " . $error);
      } else {
          wlog (N, "...OK")
      }
   }
}

sub mode_resume {

   my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      my $vm_name = $vm->getAttribute("name");
      my $merged_type = $dh->get_vm_merged_type($vm);
 
      # call the corresponding vmAPI
      my $vm_type = $vm->getAttribute("type");
      wlog (N, "Resuming virtual machine '$vm_name' of type '$merged_type'...");
      my $error = "VNX::vmAPI_$vm_type"->resumeVM($vm_name, $merged_type);
      if ($error ne 0) {
          wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->resumeVM returns " . $error);
      } else {
          wlog (N, "...OK")
      }
   }
}

sub mode_showmap {

   	my $scedir  = $dh->get_sim_dir;
   	my $scename = $dh->get_scename;
   	if (! -d $dh->get_sim_dir ) {
		mkdir $dh->get_sim_dir or $execution->smartdie ("error making directory " . $dh->get_sim_dir . ": $!");
   	}
   	
	$execution->execute($logp, "vnx2dot ${input_file} > ${scedir}/${scename}.dot");
   	$execution->execute($logp, "neato -Tpng -o${scedir}/${scename}.png ${scedir}/${scename}.dot");
   
   
    # Read png_viewer variable from config file to see if the user has 
    # specified a viewer
    my $pngViewer = &get_conf_value ($vnxConfigFile, 'general', "png_viewer", 'root');
	# If not defined use default values
    if (!defined $pngViewer) { 
   		my $gnome=`w -sh | grep gnome-session`;
   		if ($gnome ne "") { $pngViewer="gnome-open" }
        	         else { $pngViewer="xdg-open" }
    }
   	#$execution->execute($logp, "eog ${scedir}/${scename}.png");
   	wlog (N, "Using '$pngViewer' to show scenario '${scename}' topology map", "host> ");
   	$execution->execute($logp, "$pngViewer ${scedir}/${scename}.png &");

}

sub mode_console {
	
    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   

 	my $scename = $dh->get_scename;
	for ( my $i = 0; $i < @vm_ordered; $i++) {
		my $vm = $vm_ordered[$i];
		my $vm_name = $vm->getAttribute("name");
		
		if ($opts{'console'} eq '') {
            # No console names specified. Start all consoles			
            VNX::vmAPICommon->start_consoles_from_console_file ($vm_name);
		} else {
			# Console names specified (a comma separated list) 
            my @con_names = split( /,/, $opts{'console'} );
            foreach my $cid (@con_names) {
	            if ($cid !~ /^con\d$/) {
	                $execution->smartdie ("ERROR: console $cid unknown. Try \"vnx -f file.xml --console-info\" to see console names.\n");
	            }
	            VNX::vmAPICommon->start_console ($vm_name, $cid);
            }
		}
	}       
}

sub mode_consoleinfo {
	
	print_consoles_info();
        
}

sub mode_exeinfo {

    wlog (N, "\nVNX exe-info mode:");     
 
    if (! $opts{M} ) {

        # Get descriptions of user-defined commands
        my %vm_seqs = $dh->get_seqs();      
           
        if ( keys(%vm_seqs) > 0) {
            wlog (N, "\nUser-defined command sequences for scenario '" . $dh->get_scename . "'");
            wlog (N, $hline);
            foreach my $seq ( keys %vm_seqs ) {
                my $msg = sprintf (" %-24s %s", $seq, get_seq_desc($seq));
                wlog (N, $msg);
            }
        } else {
            wlog (N, "\nNo user-defined commands in scenario " . $dh->get_scename . "'");
        }
 
        # Get descriptions of plugin commands
        foreach my $plugin (@plugins) {
            my %seq_desc = $plugin->getSeqDescriptions('', '');
            if ( keys(%seq_desc) > 1) {
                wlog (N, "\nPlugin '$plugin' command sequences for scenario '" . $dh->get_scename . "'");
                wlog (N, $hline);
                foreach my $seq ( keys %seq_desc ) {
                    unless ($seq eq '_VMLIST') {
                        my $msg = sprintf (" %-24s %s", $seq, $seq_desc{$seq});
                        wlog (N, $msg);
                    }
                }
            } else {
                wlog (N, "\nNo commands defined for scenario " . $dh->get_scename . "' in plugin '$plugin'");
            }
        }
        wlog (N, $hline);
       
       
    } else {
        # -M option used 
        my @vm_ordered = $dh->get_vm_ordered;
        my %vm_hash = $dh->get_vm_to_use;
          
        for ( my $i = 0; $i < @vm_ordered; $i++) {
           
            my $vm = $vm_ordered[$i];
            my $vm_name = $vm->getAttribute("name");
            my $merged_type = $dh->get_vm_merged_type($vm);
            unless ($vm_hash{$vm_name}){  next; }
            
            # Get descriptions of user-defines commands
            my %vm_seqs = $dh->get_seqs($vm);      
             
            wlog (N, "User-defined command sequences for vm '$vm_name'");
            wlog (N, $hline);
            if ( keys(%vm_seqs) > 0) {
                foreach my $seq ( keys %vm_seqs ) {
                    my $msg = sprintf (" %-24s %s", $seq, get_seq_desc($seq));
                    wlog (N, $msg);
                }
            } else {
                wlog (N, "None defined");
            }
            wlog (N, "");
             
            # Get descriptions of plugin commands
            foreach my $plugin (@plugins) {
                wlog (N, "Plugin '$plugin' command sequences for vm '$vm_name'");
                wlog (N, $hline);
                my %seq_desc = $plugin->getSeqDescriptions($vm_name, '');
                if ( keys(%seq_desc) > 1) {
		            foreach my $seq ( keys %seq_desc ) {
                        unless ($seq eq '_VMLIST') {
                            my $msg = sprintf (" %-24s %s", $seq, $seq_desc{$seq});
                            wlog (N, $msg);
                        }
                    }
                } else {
                    wlog (N, "None defined");
                }
                wlog (N, "");
            }
            wlog (N, $hline);
        }           
     }
}

sub mode_cleanhost {

    my $vnx_dir = shift;
    
    # Clean host
    wlog (N, "\nVNX clean-host mode:");     
    
    wlog (N, "\n-------------------------------------------------------------------");
    wlog (N, "---- WARNING - WARNING - WARNING - WARNING - WARNING - WARNING ----");
    wlog (N, "-------------------------------------------------------------------");
    wlog (N, "---- This command will:");
    wlog (N, "----   - destroy all virtual machines in this host (UML, libvirt and dynamips)");
    wlog (N, "----   - delete .vnx directory content");
    wlog (N, "----   - restart libvirt daemon");
    wlog (N, "----   - restart dynamips daemon");
    
    my $answer;
    unless ($opts{'yes'}) {
        print ("---- Do you want to continue (yes/no)? ");
        $answer = readline(*STDIN);
    } else {
        $answer = 'yes'; 
    }
    unless ( $answer =~ /^yes/ ) {
        wlog (N, "---- Host not restarted. Exiting");
    } else {

        wlog (N, "---- Restarting host...");

change_to_root();
        wlog (N, "----   Killing ALL libvirt virtual machines...");
        my @virsh_list;
        my $i;
        my $pipe = "virsh -c $hypervisor list |";
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
                my $res = `virsh destroy $2`;
                wlog (N, "----     killing vm $2...");  
                wlog (N, $res);       
           }
        }

        # get all virtual machines in "shut off" state with "virsh list --all"
        # kill then with "virsh undefine vmname" 
        @virsh_list = qw ();
        $i = 0;
        $pipe = "virsh -c $hypervisor list --all |";
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
                my $res = `virsh undefine $2`;
                wlog (N, "----     undefining vm $2...");
                wlog (N, $res);       
            }
        }
            
        my $res;    
        wlog (N, "----   Killing UML virtual machines...");
        my $pids = `ps uax | grep linux | grep ubd | grep scenarios | grep umid | grep -v grep | awk '{print \$2}'`;
        $pids =~ s/\R/ /g;
        if ($pids) {
            wlog (N, "----     killing UML processes $pids...");
            $res = `echo $pids | xargs kill`;
            wlog (N, $res);       
        }
            
        wlog (N, "----   Restarting libvirt daemon...");  
        $res = `/etc/init.d/libvirt-bin restart`;
        wlog (N, $res);       

        wlog (N, "----   Restarting dynamips daemon...");  
        $res = `/etc/init.d/dynamips restart`;
        wlog (N, $res);       

        wlog (N, "----   Deleting .vnx directory...");
        if (defined($vnx_dir)) {
            $res = `rm -rf $vnx_dir/../.vnx/*`;
            wlog (N, $res);       
        }
back_to_user();        

    }
}

sub mode_createrootfs {

    my $tmp_dir = shift;
    my $vnx_dir = shift;

    my $sdisk_fname;  # shared disk complete file name 
    my $h2vm_port;    # host tcp port used to access the the host-to-VM comms channel 
    my $vm_libirt_xml_hdb;
    my $mem;          # Memory assigned to the virtual machine
    my $default_mem   = "512M";
    my $arch;         # Virtual machine architecture type (32 or 64 bits)
    my $default_arch  = "i686";
    my $vcpu;         # Number of virtual CPUs 
    my $default_vcpu = "1";
 
    my $instal_cdrom = $opts{'install-media'};
    if (! -e $instal_cdrom) {
    	vnx_die ("installation cdrom image ($instal_cdrom) not found");
    }
 
    # Set memory value
    if ($opts{'mem'}) {
        $mem = $opts{'mem'}
    } else {
        $mem = $default_mem;
    }
    # Convert <mem> tag value to Kilobytes (only "M" and "G" letters are allowed) 
    if ((($mem =~ /M$/))) {
        $mem =~ s/M//;
        $mem = $mem * 1024;
    } elsif ((($mem =~ /G$/))) {
        $mem =~ s/G//;
        $mem = $mem * 1024 * 1024;
    } else {
        vnx_die ("Incorrect memory specification ($mem). Use 'M' or 'G' to specify Mbytes or Gbytes. Ej: 512M, 1G ");
    }

    # Set architecture type (32 or 64 bits)
    if ($opts{'arch'}) {
        $arch = $opts{'arch'};
        unless ( $arch eq 'i686' or $arch eq 'x86_64') { vnx_die ("ERROR: Unkwon value ($arch) for --arch option" ) }
    } else {
        $arch = $default_arch;
    }
    
    # Set virtual cpus number (>=1)
    if ($opts{'vcpu'}) {
        $vcpu = $opts{'vcpu'};
        unless ( $vcpu ge 1 ) { vnx_die ("ERROR: Number of virtual CPUs specified in vcpu option must be >=1" ) }
    } else {
        $vcpu = $default_vcpu;
    }

    my $rootfs_name = basename $opts{'create-rootfs'};
    $rootfs_name .= "-" . int(rand(10000));

    # Create a temp directory to store everything
    my $base_dir = `mktemp --tmpdir=$tmp_dir -td vnx_create_rootfs.XXXXXX`;
    chomp ($base_dir);
    my $rootfs_fname = `readlink -f $opts{'create-rootfs'}`; chomp ($rootfs_fname);
    my $cdrom_fname  = `readlink -f $opts{'install-media'}`; chomp ($cdrom_fname);
    my $vm_xml_fname = "$base_dir/${rootfs_name}.xml";

    # Get a free port for h2vm channel
    $h2vm_port = get_next_free_port (\$VNX::Globals::H2VM_PORT);    

    if (! -e $rootfs_fname) {
        vnx_die ("root filesystem file ($rootfs_name) not found.\n" .
                 "Create it first with 'qemu-img' command, e.g:\n" .
                 "  qemu-img create -f qcow2 rootfs_file.qcow2 8G");
    }
        
=BEGIN   
    # virt-install -n freebsd -r 512 --vcpus=1 --accelerate -v -c /almacen/iso/FreeBSD-9.1-RELEASE-amd64-disc1.iso -w bridge:virbr0 --vnc --disk path=vnx_rootfs_kvm_freebsd64-9.1-v025m3.qcow2,size=12,format=qcow2 --arch x86_64
    my $cmd = "virt-install --connect $hypervisor -n $rootfs_name -r $mem --vcpus=$vcpu " .
              "--arch $arch --accelerate -v -c $cdrom_fname -w network=default --vnc " .
              "--disk path=$rootfs_fname,format=qcow2 --arch x86_64 " . 
              "--serial pty --serial tcp,host=:$h2vm_port,mode=bind,protocol=telnet";
=END
=cut

    $vm_libirt_xml_hdb =  <<EOF;
<disk type='file' device='cdrom'>
    <source file='$cdrom_fname'/>
    <target dev='hdb'/>
</disk>
EOF


    # Create the VM libvirt XML
    #
    # Variables:
    #  $rootfs_name, rootfs file name
    #  $rootfs_fname, rootfs complete file name (with path)
    #  $vm_libirt_xml_hdb;

    my $vm_libirt_xml = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<domain type="kvm" xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0">
  <name>$rootfs_name</name>
  <memory>$mem</memory>
  <vcpu>$vcpu</vcpu>
  <os>
    <type arch='$arch'>hvm</type>
    <boot dev='cdrom'/>
    <boot dev='hd'/>
  </os>
  <features>
     <pae/>
     <acpi/>
     <apic/>
  </features>
  <clock sync="localtime"/>
  <devices>
    <emulator>/usr/bin/kvm</emulator>
    <disk type='file' device='disk'>
      <source file='$rootfs_fname'/>
      <target dev='hda'/>
      <driver name="qemu" type="qcow2"/>
    </disk>
    $vm_libirt_xml_hdb
    <interface type='network'>
      <source network='default'/>
    </interface>
    <graphics type='vnc'/>
    <serial type="pty">
      <target port="0"/>
     </serial>
     <console type="pty">
      <target port="0"/>
     </console>
     <serial type="tcp">
         <source mode="bind" host="127.0.0.1" service="$h2vm_port"/>
         <protocol type="telnet"/>
         <target port="1"/>
     </serial>
  </devices>
</domain>

EOF
    
    # Create XML file
    open (XMLFILE, "> $vm_xml_fname") or vnx_die ("cannot open file $vm_xml_fname");
    print XMLFILE "$vm_libirt_xml";
    wlog (VVV, "-- Libvirt XML file:\n$vm_libirt_xml");
    close (XMLFILE); 

change_to_root();
    wlog (N, "-- Starting a virtual machine with root filesystem $opts{'create-rootfs'}");
    system "virsh create $vm_xml_fname"; 
    system "virt-viewer $rootfs_name &"; 
back_to_user();

}

sub mode_modifyrootfs {
	
    my $tmp_dir = shift;
    my $vnx_dir = shift;

    my $sdisk_fname; # shared disk complete file name 
    my $h2vm_port;   # host tcp port used to access the the host-to-VM comms channel 
    my $vm_libirt_xml_hdb;
    my $mem;          # Memory assigned to the virtual machine
    my $default_mem   = "512M";
    my $arch;         # Virtual machine architecture type (32 or 64 bits)
    my $default_arch  = "i686";
    my $vcpu;        # Number of virtual CPUs 
    my $default_vcpu = "1";
 
    use constant USE_CDROM_FORMAT => 0;  # 
    
    # Set memory value
    if ($opts{'mem'}) {
        $mem = $opts{'mem'}
    } else {
        $mem = $default_mem;
    }
    # Convert <mem> tag value to Kilobytes (only "M" and "G" letters are allowed) 
    if ((($mem =~ /M$/))) {
        $mem =~ s/M//;
        $mem = $mem * 1024;
    } elsif ((($mem =~ /G$/))) {
        $mem =~ s/G//;
        $mem = $mem * 1024 * 1024;
    } else {
    	vnx_die ("Incorrect memory specification ($mem). Use 'M' or 'G' to specify Mbytes or Gbytes. Ej: 512M, 1G ");
    }

    # Set architecture type (32 or 64 bits)
    if ($opts{'arch'}) {
        $arch = $opts{'arch'};
        unless ( $arch eq 'i686' or $arch eq 'x86_64') { vnx_die ("ERROR: Unkwon value ($arch) for --arch option" ) }
    } else {
        $arch = $default_arch;
    }

    # Set virtual cpus number (>=1)
    if ($opts{'vcpu'}) {
        $vcpu = $opts{'vcpu'};
        unless ( $vcpu ge 1 ) { vnx_die ("ERROR: Number of virtual CPUs specified in vcpu option must be >=1" ) }
    } else {
        $vcpu = $default_vcpu;
    }
    
    my $rootfs_name = basename $opts{'modify-rootfs'};
    $rootfs_name .= "-" . int(rand(10000));

    # Create a temp directory to store everything
    my $base_dir = `mktemp --tmpdir=$tmp_dir -td vnx_modify_rootfs.XXXXXX`;
    chomp ($base_dir);
    my $rootfs_fname = `readlink -f $opts{'modify-rootfs'}`; chomp ($rootfs_fname);
    my $vm_xml_fname = "$base_dir/${rootfs_name}.xml";

    if ( defined($opts{'update-aced'}) ) {

        wlog (N, "mode_modifyrootfs: update-aced option selected ($opts{'update-aced'})");
  	    #
	    # Create shared disk with latest versions of VNXACE daemon
	    #
        my $content_dir;
        my $make_iso_cmd;
        my $sdisk_mount;
        
if (USE_CDROM_FORMAT) {

        # Check mkisofs or genisoimage binary is available
        $make_iso_cmd = 'mkisofs';
        my $fail = system ("which $make_iso_cmd > /dev/null");
        if ($fail) { # Try genisoimage 
            wlog (N, "mkisofs not found; trying genisoimage");
            $make_iso_cmd = 'genisoimage';
            $fail = system("which $make_iso_cmd > /dev/null");
            if ($fail) { 
               vnx_die ("ERROR: neither mkisofs nor genisoimage binaries found\n"); 
            }
        } 
        my $where = `which $make_iso_cmd`;
        chomp($where);
        $make_iso_cmd = $where;
        wlog (VVV, "make_iso_cmd=$make_iso_cmd", $logp);

        # Create temp directory to store VNXACED
        my $content_dir="$base_dir/iso-content";
        wlog (N, "Creating iso-content temp directory ($content_dir)...");
        system "mkdir $content_dir";
	
} else {

        # Create the shared filesystem 
        $sdisk_fname = $base_dir . "/sdisk.img";
        # TODO: change the fixed 50M to something configurable
        $execution->execute($logp,  $bd->get_binaries_path_ref->{"qemu-img"} . " create $sdisk_fname 50M" );
        # format shared disk as msdos partition
        $execution->execute($logp,  $bd->get_binaries_path_ref->{"mkfs.msdos"} . " $sdisk_fname" ); 
        # Create mount directory
        $sdisk_mount = "$base_dir/mnt/";
        $execution->execute($logp,  "mkdir -p $sdisk_mount");
        # Mount the shared disk to copy filetree files
        $execution->execute($logp,  $bd->get_binaries_path_ref->{"mount"} . " -o loop " . $sdisk_fname . " " . $sdisk_mount );

        # Set content directory
        $content_dir="$sdisk_mount";
	
}	    
  
	    # Calculate VNX aced dir
	    my $vnxaced_dir = $VNX_INSTALL_DIR . "/aced"; 
	    wlog (VVV, "VNX aced dir=$vnxaced_dir", $logp);

	    my $aced_tar_file;
	    if ($opts{'update-aced'} eq '') {
	        # ACED tar file not specified: we copy all the latest versions found in vnx/aced directory
	        my $aced_dir = abs_path( "${vnxaced_dir}" );
            my $found = 0;
            
            # Linux/FreeBSD
	        my @files = <${aced_dir}/vnx-aced-lf-*>; 
	        @files = reverse sort @files;
	        $aced_tar_file = $files[0];
	        if (defined($aced_tar_file) && $aced_tar_file ne ''){
	            system "mkdir $content_dir/vnxaced-lf";
	            system "tar xfz $aced_tar_file -C $content_dir/vnxaced-lf --strip-components=1";
                wlog (N, "-- Copied $aced_tar_file to shared disk (directory vnxaced-lf)...");
	            $found = 1;
	        }
            # Olive
            @files = <${aced_dir}/vnx-aced-olive-*>; 
            @files = reverse sort @files;
            $aced_tar_file = $files[0];
            if (defined($aced_tar_file) && $aced_tar_file ne ''){
                system "mkdir $content_dir/vnxaced-olive";
                system "tar xfz $aced_tar_file -C $content_dir/vnxaced-olive --strip-components=1";
                wlog (N, "-- Copied $aced_tar_file to shared disk (directory vnxaced-olive)...");
                $found = 1;
            }
            # Windows
            @files = <${aced_dir}/vnx-aced-win-*>; 
            @files = reverse sort @files;
            $aced_tar_file = $files[0];
            if (defined($aced_tar_file) && $aced_tar_file ne ''){
                system "mkdir $content_dir/vnxaced-win";
                system "cp $aced_tar_file $content_dir/vnxaced-win";
                wlog (N, "-- Copied $aced_tar_file to shared disk (directory vnxaced-win)...");
                $found = 1;
            }
            if (!$found) {
                vmx_die ("No VNXACED file specified and no VNXACE tar files found in $aced_dir\n");
            }
	        
	    } else {
	        my $aced_tar_file = abs_path($opts{'update-aced'});
	        if (! -e $aced_tar_file) {
	            vnx_die ("VNXACE tar file ($aced_tar_file) not found");
	            exit (1);
	        }
            if ($aced_tar_file =~ /vnx-aced-lf/) {         # Linux/FreeBSD
                system "mkdir $content_dir/vnxaced-lf";
                system "tar xfz $aced_tar_file -C $content_dir/vnxaced-lf --strip-components=1";
            } elsif ($aced_tar_file =~ /vnx-aced-olive/) { # Olive
                system "mkdir $content_dir/vnxaced-olive";
                system "tar xfz $aced_tar_file -C $content_dir/vnxaced-olive --strip-components=1";
            } elsif ($aced_tar_file =~ /vnx-aced-win/) {   # Windows
                system "mkdir $content_dir/vnxaced-win";
                system "cp $aced_tar_file $content_dir/vnxaced-win";
            } else {
                system "cp $aced_tar_file $content_dir";            	
            }
	    }

if (USE_CDROM_FORMAT) {

        wlog (N, "-- Creating iso filesystem...");
        wlog (VVV, "--    $make_iso_cmd -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet " .
              " -allow-lowercase -allow-multidot -d -o $base_dir/vnx_update.iso $content_dir", $logp);
        system "$make_iso_cmd -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet " .
              " -allow-lowercase -allow-multidot -d -o $base_dir/vnx_update.iso $content_dir";
        #print "--   rm -rf $content_dir\n";
        system "rm -rf $content_dir";
        
        $sdisk_fname = "$base_dir/vnx_update.iso";

} else {

        # Unmount shared disk
        $execution->execute($logp,  $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_mount );
        # sdisk_fname already set

}

	    $vm_libirt_xml_hdb = <<EOF;
<disk type="file" device="disk">
    <source file="$sdisk_fname"/>
    <target dev="hdb"/>
</disk>
EOF

    } else {
    	$vm_libirt_xml_hdb = "";
    }

    # Get a free port for h2vm channel
    $h2vm_port = get_next_free_port (\$VNX::Globals::H2VM_PORT);    

    # Create the VM libvirt XML
    #
    # Variables:
    #  $rootfs_name, rootfs file name
    #  $rootfs_fname, rootfs complete file name (with path)
    #  $sdisk_fname; # shared disk complete file name 
    #  $h2vm_port;   # host tcp port used to access the the host-to-VM comms channel 
    #  $vm_libirt_xml_hdb;

    my $vm_libirt_xml = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<domain type="kvm" xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0">
  <name>$rootfs_name</name>
  <memory>$mem</memory>
  <vcpu>$vcpu</vcpu>
  <os>
    <type arch='$arch'>hvm</type>
    <boot dev='hd'/>
    <boot dev='cdrom'/>
  </os>
  <features>
     <pae/>
     <acpi/>
     <apic/>
  </features>
  <clock sync="localtime"/>
  <devices>
    <emulator>/usr/bin/kvm</emulator>
    <disk type='file' device='disk'>
      <source file='$rootfs_fname'/>
      <target dev='hda'/>
      <driver name="qemu" type="qcow2"/>
    </disk>
    $vm_libirt_xml_hdb
    <interface type='network'>
      <source network='default'/>
    </interface>
    <graphics type='vnc'/>
    <serial type="pty">
      <target port="0"/>
     </serial>
     <console type="pty">
      <target port="0"/>
     </console>
     <serial type="tcp">
         <source mode="bind" host="127.0.0.1" service="$h2vm_port"/>
         <protocol type="telnet"/>
         <target port="1"/>
     </serial>
  </devices>
</domain>

EOF

    
    # Create XML file
    open (XMLFILE, "> $vm_xml_fname") or vnx_die ("cannot open file $vm_xml_fname");
    print XMLFILE "$vm_libirt_xml";
    wlog (VVV, "-- Libvirt XML file:\n$vm_libirt_xml");   
    close (XMLFILE); 

change_to_root();
    wlog (N, "-- Starting a virtual machine with root filesystem $opts{'modify-rootfs'}");
    system "virsh create $vm_xml_fname"; 
    system "virt-viewer $rootfs_name &"; 
    
    # Wait till the VM has started
    my $vmsocket = IO::Socket::INET->new(
                    Proto    => "tcp",
                    PeerAddr => "localhost",
                    PeerPort => "$h2vm_port",
                ) or vnx_die ("Can't connect to virtual machine H2VM port: $!\n");

    $vmsocket->flush; # delete socket buffers, just in case...  
    print $vmsocket "hello\n";
    wlog (N, "-- Waiting for virtual machine to start...");
    
    #print $vmsocket "nop\n";

    my $t = time();
    my $timeout = 120; # secs

    while (1) {
    	
        $vmsocket->flush;
        print $vmsocket "hello\n";
    	my $res = recv_sock ($vmsocket);
    	wlog (VVV, "    res=$res", $logp);
    	last if ( $res =~ /^OK/);
    	if ( time() - $t > $timeout) {
    		vnx_die ("Timeout waiting for virtual machine to start.")
    	}
    }     
    wlog (N, "-- Virtual machine started OK.");
    
    # Update VNXACED if requested
    if ( defined($opts{'update-aced'}) ) {
    
        if (!$opts{yes}) {
            wlog (N, "-- Do you want to update VNXACED in virtual machine (y/n)?");
            my $line = readline(*STDIN);
            unless ( $line =~ /^[yY]/ ) {
                wlog (N, "-- VNXACED not updated");
                exit (0);
            } 
        }    
        wlog (N, "-- Updating VNXACED...VM should now be updated and halted. If not, update VNXACED manually.");
        print $vmsocket "vnxaced_update sdisk\n";
    
    }
    back_to_user();    
}


#
# get_seq_desc
#
# Returns the text value of an <seq_help> tag with sequence = $seq
# or none if not found 
#
sub get_seq_desc {
       
    my $seq = shift;

    my $doc = $dh->get_doc;
    #my $exechelp_list = $doc->getElementsByTagName("seq_help");
    #for ( my $j = 0 ; $j < $exechelp_list->getLength ; $j++ ) {
    foreach my $exechelp ($doc->getElementsByTagName("seq_help")) {     	
        #my $exechelp = $exechelp_list->item($j);
        #wlog (VVV, $exechelp->toString());
        if ($exechelp->getAttribute('seq') eq $seq) {
            return text_tag($exechelp);        	
        } 
    }
}



####################################################################################
# To create TUN/TAP device if virtual switched network more (<net mode="uml_switch">)
sub configure_switched_networks {

    my $doc = $dh->get_doc;
    my $sim_name = $dh->get_scename;

	# Create the symbolic link to the management switch
	if ($dh->get_vmmgmt_type eq 'net') {
		my $sock = $doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("sock");
		$execution->execute($logp, $bd->get_binaries_path_ref->{"ln"} . " -s $sock " . $dh->get_networks_dir .
				"/" . $dh->get_vmmgmt_netname . ".ctl" );
	}

    #my $net_list = $doc->getElementsByTagName("net");
    #for ( my $i = 0; $i < $net_list->getLength; $i++ ) {
    foreach my $net ($doc->getElementsByTagName("net")) {

       my $command;
       # We get attributes
       my $net_name = $net->getAttribute("name");
       my $mode     = $net->getAttribute("mode");
       my $sock     = $net->getAttribute("sock");
       unless (empty($sock)) { $sock = do_path_expansion($sock) };
       my $external_if = $net->getAttribute("external");
       my $vlan     = $net->getAttribute("vlan");
       $command     = $net->getAttribute("uml_switch_binary");

       # Capture related attributes
       my $capture_file = $net->getAttribute("capture_file");
       my $capture_expression = $net->getAttribute("capture_expression");
       my $capture_dev = $net->getAttribute("capture_dev");

       # FIXME: maybe this checking should be put in CheckSemantics, due to at this
       # point, the parses has done some work that need to be undone before exiting
       # (that is what the mode_shutdown() is for)
       if (!empty($capture_file) && -f $capture_file) {
       	  mode_shutdown();
          $execution->smartdie("$capture_file file already exist. Please remove it manually or specify another capture file in the VNX specification.") 
       }

       my $hub = $net->getAttribute("hub");

       # This function only processes uml_switch networks
       if ($mode eq "uml_switch") {
       	
       	  # Some case are not supported in the current version
       	  if ((&vnet_exists_sw($net_name)) && (&check_net_host_conn($net_name,$dh->get_doc))) {
       	  	wlog (N, "VNX warning: switched network $net_name with connection to host already exits. Ignoring.");
       	  }
          #if ((!($external_if =~ /^$/))) {
          unless ( empty($external_if) ) {
       	  	wlog (N, "VNX warning: switched network $net_name with external connection to $external_if: not implemented in current version. Ignoring.");
       	  }
       	
       	  # If uml_switch does not exists, we create and set up it
          unless (&vnet_exists_sw($net_name)) {
			unless (empty($sock)) {
				$execution->execute($logp, $bd->get_binaries_path_ref->{"ln"} . " -s $sock " . $dh->get_networks_dir . "/$net_name.ctl" );
			} else {
				 my $hub_str = ($hub eq "yes") ? "-hub" : "";
				 my $sock = $dh->get_networks_dir . "/$net_name.ctl";
				 unless (&check_net_host_conn($net_name,$dh->get_doc)) {
					# print "VNX warning: no connection to host from virtualy switched net \"$net_name\". \n" if ($execution->get_exe_mode() == $EXE_VERBOSE);
					# To start virtual switch
					my $extra ='';
					if ($capture_file) {
						$extra = $extra . " -f \"$capture_file\"";

				 		$execution->execute_bg($bd->get_binaries_path_ref->{"rm"} . " -rf $capture_file", '/dev/null');

						if ($capture_expression){ 
							$extra = $extra . " -expression \"$capture_expression\""; 
						}
					}

					if ($capture_dev){
                       $extra = $extra . " -dev \"$capture_dev\"";
                    }
				
				    if ($capture_dev || $capture_file) {
				       $extra = $extra . " -scenario_name $sim_name $net_name";
				    }
				
					if (!$command){
				 		$execution->execute_bg($bd->get_binaries_path_ref->{"uml_switch"} . " -unix $sock $hub_str $extra", '/dev/null');
					}
					else{
						$execution->execute_bg($command . " -unix $sock $hub_str $extra", '/dev/null');
					}
					
					if ($execution->get_exe_mode() != $EXE_DEBUG && !&uml_switch_wait($sock, 5)) {
						mode_shutdown();
						$execution->smartdie("uml_switch for $net_name failed to start!");
					}
				 }
				 else {
				 	# Only one modprobe tun in the same execution: after checking tun_device_needed. See mode_t subroutine
                    # -----------------------
					# To start tun module
					#!$execution->execute( $logp, $bd->get_binaries_path_ref->{"modprobe"} . " tun") or $execution->smartdie ("module tun can not be initialized: $!");

					# We build TUN device name
					my $tun_if = $net_name;

					# To start virtual switch
					#my @group = getgrnam("@TUN_GROUP@");
					my @group = getgrnam("uml-net");
					
					my $extra;

                    if ($capture_file) {
                       $extra = $extra . " -f \"$capture_file\"";
                       $execution->execute_bg($bd->get_binaries_path_ref->{"rm"} . " -rf $capture_file", '/dev/null');
                       if ($capture_expression){
                          $extra = $extra . " -expression \"$capture_expression\"";
                       }
                    }

                    if ($capture_dev){
			           $extra = $extra . " -dev \"$capture_dev\"";
                    }

                    if ($capture_dev || $capture_file) {
                       $extra = $extra . " -scenario_name $sim_name $net_name";
                    }

                    if (!$command){
                       $execution->execute_bg($bd->get_binaries_path_ref->{"uml_switch"} . " -tap $tun_if -unix $sock $hub_str $extra", '/dev/null', $group[2]);
                    }
                    else {
				       $execution->execute_bg($command . " -tap $tun_if -unix $sock $hub_str $extra", '/dev/null', $group[2]);
                    }

					if ($execution->get_exe_mode() != $EXE_DEBUG && !&uml_switch_wait($sock, 5)) {
						mode_shutdown();
						$execution->smartdie("uml_switch for $net_name failed to start!");
					}
				}
             }
          }

          # We increase interface use counter of the socket
          &inc_cter("$net_name.ctl");

                #-------------------------------------
                # VLAN setup, NOT TESTED 
                #-------------------------------------
                #unless ($vlan =~ /^$/ ) {
                #    # configure VLAN on this interface
                #   unless (&check_vlan($tun_if,$vlan)) {
                #	    $execution->execute($logp, $bd->get_binaries_path_ref->{"modprobe"} . " 8021q");
                #	   $execution->execute($logp, $bd->get_binaries_path_ref->{"vconfig"} . " add $tun_if $vlan");
                # }
                #    my $tun_vlan_if = $tun_if . ".$vlan";
                #    $execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $tun_vlan_if 0.0.0.0 $dh->get_promisc() up");
                #    # We increase interface use counter
                #    &inc_cter($tun_vlan_if);
                #}           

      }
      
    }

}

#
# configure_virtual_bridged_networks
#
# To create TUN/TAP devices
sub configure_virtual_bridged_networks {

    # TODO: to considerate "external" atribute when network is "ppp"

    my $doc = $dh->get_doc;
    my @vm_ordered = $dh->get_vm_ordered;

    # 1. Set up tun devices

    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];

        # We get name and type attribute
        my $vm_name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");

        # Only one modprobe tun in the same execution: after checking tun_device_needed. See mode_t subroutine
        # -----------------------
        # To start tun module
        #!$execution->execute( $logp, $bd->get_binaries_path_ref->{"modprobe"} . " tun") or $execution->smartdie ("module tun can not be initialized: $!");
     
        # To create management device (id 0), if needed
        # The name of the if is: $vm_name . "-e0"
        my $mng_if_value = &mng_if_value($vm);
      
        if ( ($dh->get_vmmgmt_type eq 'private') && ($mng_if_value ne "no") && ($vm_type ne 'lxc')) {
            my $tun_if = $vm_name . "-e0";
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -u " . $execution->get_uid . " -t $tun_if -f " . $dh->get_tun_device);
        }

        # To get interfaces list
        foreach my $if ($vm->getElementsByTagName("if")) {          

            # We get attribute
            my $id = $if->getAttribute("id");
            my $net = $if->getAttribute("net");

            # Only TUN/TAP for interfaces attached to bridged networks
            # We do not create tap interfaces for libvirt VMs. It is done by libvirt 
            #if (&check_net_br($net)) {
            if ( ($vm_type ne 'libvirt') && ($vm_type ne 'lxc') && ( &get_net_by_mode($net,"virtual_bridge") != 0 ) ) {

                # We build TUN device name
                my $tun_if = $vm_name . "-e" . $id;

                # To create TUN device
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -u " . $execution->get_uid . " -t $tun_if -f " . $dh->get_tun_device);

                # To set up device
                #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $tun_if 0.0.0.0 " . $dh->get_promisc . " up");
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set dev $tun_if up");
                        
            }
        }
    }
   
   # 2. Create bridges
      
     # To process list
    foreach my $net ($doc->getElementsByTagName("net")) {

      # We get name attribute
      my $net_name    = $net->getAttribute("name");
      my $mode        = $net->getAttribute("mode");
      my $external_if = $net->getAttribute("external");
      my $vlan        = $net->getAttribute("vlan");

      # This function only processes virtual_bridge networks
        #Carlos modifications(añadido parametro de entrada mode)
      unless (&vnet_exists_br($net_name,$mode)) {
        if ($mode eq "virtual_bridge") {
         # If bridged does not exists, we create and set up it
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addbr $net_name");
            if ($dh->get_stp) {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " stp $net_name on");
            }else {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " stp $net_name off");
            }

       }elsif ($mode eq "openvswitch") {
         # If bridged does not exists, we create and set up it
    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-br $net_name");
        if($net->getAttribute("controller") ){
            my $controller = $net->getAttribute("controller");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set-controller $net_name $controller");
            }
        
    }
      sleep 1;    # needed in SuSE 8.2
            
            #
            # Create a tap interface with a "low" mac address and join it to the bridge to 
            # obligue the bridge to use that mac address.
            # See http://backreference.org/2010/07/28/linux-bridge-mac-addresses-and-dynamic-ports/
            #
            # Generate a random mac address under prefix 02:00:00 
            my @chars = ( "a" .. "f", "0" .. "9");
            my $brtap_mac = "020000" . join("", @chars[ map { rand @chars } ( 1 .. 6 ) ]);
            $brtap_mac =~ s/(..)/$1:/g;
            chop $brtap_mac;                       
            # Create tap interface
            my $brtap_name = "$net_name-e00";
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -u " . $execution->get_uid . " -t $brtap_name -f " . $dh->get_tun_device);
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $brtap_name address $brtap_mac");                       
            # Join the tap interface to bridge
            #Carlos modifications
            if ($mode eq "virtual_bridge") {
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addif $net_name $brtap_name");
        }elsif ($mode eq "openvswitch") {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-port $net_name $brtap_name");
        }
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $brtap_name up");                       
            
            # Bring the bridge up
            #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $net_name 0.0.0.0 " . $dh->get_promisc . " up");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $net_name up");         
         }
        
         # Is there an external interface associated with the network?
         #unless ($external_if =~ /^$/) {
         unless (empty($external_if)) {
            # If there is an external interface associate, to check if VLAN is being used
            #unless ($vlan =~ /^$/ ) {
            unless (empty($vlan) ) {
               # If there is not any configured VLAN at this interface, we have to enable it
               unless (&check_vlan($external_if,"*")) {
                  #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $external_if 0.0.0.0 " . $dh->get_promisc . " up");
                  $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $external_if up");
               }
               # If VLAN is already configured at this interface, we haven't to configure it
               unless (&check_vlan($external_if,$vlan)) {
                  $execution->execute_root($logp, $bd->get_binaries_path_ref->{"modprobe"} . " 8021q");
                  $execution->execute_root($logp, $bd->get_binaries_path_ref->{"vconfig"} . " set_name_type DEV_PLUS_VID_NO_PAD");
                  $execution->execute_root($logp, $bd->get_binaries_path_ref->{"vconfig"} . " add $external_if $vlan");
               }
               $external_if .= ".$vlan";
               #$external_if .= ":$vlan";
            }
         
            # If the interface is already added to the bridge, we haven't to add it
        #Carlos modifications(añadido parametro de entrada mode)
            my @if_list = &vnet_ifs($net_name,$mode);
            wlog (VVV, "vnet_ifs returns @if_list", $logp);
            $_ = "@if_list";
            unless (/\b($external_if)\b/) {
               $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $external_if up");
               #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $external_if 0.0.0.0 " . $dh->get_promisc . " up");
        #Carlos modifications
        if ($mode eq "virtual_bridge") {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addif $net_name $external_if");
        }elsif ($mode eq "openvswitch") {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-port $net_name $external_if");
            }
        }
            # We increase interface use counter
            &inc_cter($external_if);
         }
      
   }
    #Wait until all the openvswitches are created, then establish all the declared links between those switches
    foreach my $net ($doc->getElementsByTagName("net")) {
        my $net_name    = $net->getAttribute("name");
        foreach my $connection ($net->getElementsByTagName("connection")) {
            my $net_to_connect=$connection->getAttribute("net");
            my $interfaceName=$connection->getAttribute("name");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-port $net_name $interfaceName"."1-0");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set interface $interfaceName"."1-0 type=patch options:peer=$interfaceName"."0-1");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-port  $net_to_connect $interfaceName"."0-1");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set interface $interfaceName"."0-1 type=patch options:peer=$interfaceName"."1-0");
        }
    }
}

=BEGIN
#
# configure_virtual_bridged_networks
#
# To create TUN/TAP devices
sub configure_virtual_bridged_networks {

    # TODO: to considerate "external" atribute when network is "ppp"

    my $doc = $dh->get_doc;
    my @vm_ordered = $dh->get_vm_ordered;

    # 1. Set up tun devices

    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];

        # We get name and type attribute
        my $vm_name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");

        # Only one modprobe tun in the same execution: after checking tun_device_needed. See mode_t subroutine
        # -----------------------
        # To start tun module
        #!$execution->execute( $logp, $bd->get_binaries_path_ref->{"modprobe"} . " tun") or $execution->smartdie ("module tun can not be initialized: $!");
     
        # To create management device (id 0), if needed
        # The name of the if is: $vm_name . "-e0"
        my $mng_if_value = &mng_if_value($vm);
      
        if ($dh->get_vmmgmt_type eq 'private' && $mng_if_value ne "no") {
            my $tun_if = $vm_name . "-e0";
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -u " . $execution->get_uid . " -t $tun_if -f " . $dh->get_tun_device);
        }

        # To get interfaces list
        foreach my $if ($vm->getElementsByTagName("if")) {      	

            # We get attribute
            my $id = $if->getAttribute("id");
            my $net = $if->getAttribute("net");

            # Only TUN/TAP for interfaces attached to bridged networks
            # We do not create tap interfaces for libvirt or LXC VMs. It is done by libvirt/lxc 
            #if (&check_net_br($net)) {
            if ( ($vm_type ne 'libvirt') && ($vm_type ne 'lxc') && ( &get_net_by_mode($net,"virtual_bridge") != 0 ) ) {
            #if ( ( &get_net_by_mode($net,"virtual_bridge") != 0 ) ) {

                # We build TUN device name
                my $tun_if = $vm_name . "-e" . $id;

                # To create TUN device
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -u " . $execution->get_uid . " -t $tun_if -f " . $dh->get_tun_device);

                # To set up device
                #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $tun_if 0.0.0.0 " . $dh->get_promisc . " up");
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set dev $tun_if up");
                        
            }
        }
    }
   
   # 2. Create bridges
      
    # To process list
   	foreach my $net ($doc->getElementsByTagName("net")) {

      # We get name attribute
      my $net_name    = $net->getAttribute("name");
      my $mode        = $net->getAttribute("mode");
      my $external_if = $net->getAttribute("external");
      my $vlan        = $net->getAttribute("vlan");

      # This function only processes virtual_bridge networks
        unless (&vnet_exists_br($net_name), $mode) {

            if ($mode eq "virtual_bridge") {

         # If bridged does not exists, we create and set up it
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addbr $net_name");
	        if ($dh->get_stp) {
               $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " stp $net_name on");
	        }
	        else {
               $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " stp $net_name off");
	        }
        } elsif ($mode eq "openvswitch") {
            # If bridged does not exists, we create and set up it
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-br $net_name");
            if($net->getAttribute("controller") ){
                my $controller = $net->getAttribute("controller");
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set-controller $net_name $controller");
            }
        }
        
        sleep 1;    # needed in SuSE 8.2
            
            #
            # Create a tap interface with a "low" mac address and join it to the bridge to 
            # obligue the bridge to use that mac address.
            # See http://backreference.org/2010/07/28/linux-bridge-mac-addresses-and-dynamic-ports/
            #
            # Generate a random mac address under prefix 02:00:00 
            my @chars = ( "a" .. "f", "0" .. "9");
            my $brtap_mac = "020000" . join("", @chars[ map { rand @chars } ( 1 .. 6 ) ]);
            $brtap_mac =~ s/(..)/$1:/g;
            chop $brtap_mac;                       
            # Create tap interface
            my $brtap_name = "$net_name-e00";
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -u " . $execution->get_uid . " -t $brtap_name -f " . $dh->get_tun_device);
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $brtap_name address $brtap_mac");                       
            # Join the tap interface to bridge
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addif $net_name $brtap_name");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $brtap_name up");                       
            
            # Bring the bridge up
            #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $net_name 0.0.0.0 " . $dh->get_promisc . " up");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $net_name up");	        
         }

         # Is there an external interface associated with the network?
         #unless ($external_if =~ /^$/) {
         unless (empty($external_if)) {
            # If there is an external interface associate, to check if VLAN is being used
            #unless ($vlan =~ /^$/ ) {
            unless (empty($vlan) ) {
	           # If there is not any configured VLAN at this interface, we have to enable it
	           unless (&check_vlan($external_if,"*")) {
                  #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $external_if 0.0.0.0 " . $dh->get_promisc . " up");
                  $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $external_if up");
	           }
	           # If VLAN is already configured at this interface, we haven't to configure it
	           unless (&check_vlan($external_if,$vlan)) {
	              $execution->execute_root($logp, $bd->get_binaries_path_ref->{"modprobe"} . " 8021q");
	              $execution->execute_root($logp, $bd->get_binaries_path_ref->{"vconfig"} . " set_name_type DEV_PLUS_VID_NO_PAD");
	              $execution->execute_root($logp, $bd->get_binaries_path_ref->{"vconfig"} . " add $external_if $vlan");
	           }
               $external_if .= ".$vlan";
               #$external_if .= ":$vlan";
	        }
	     
	        # If the interface is already added to the bridge, we haven't to add it
	        my @if_list = &vnet_ifs($net_name);
	        wlog (VVV, "vnet_ifs returns @if_list", $logp);
	        $_ = "@if_list";
	        unless (/\b($external_if)\b/) {
               $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $external_if up");
               #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $external_if 0.0.0.0 " . $dh->get_promisc . " up");
	           $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addif $net_name $external_if");
	        }
	        # We increase interface use counter
	        &inc_cter($external_if);
         }
      }
   }
}
=END
=cut



######################################################
# To link TUN/TAP to the bridges
sub tun_connect {

    my @vm_ordered = $dh->get_vm_ordered;

    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];

        # We get name attribute
        my $vm_name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");

        # To get UML's interfaces list
        #my $if_list = $vm->getElementsByTagName("if");

        # To process list
        #for ( my $j = 0; $j < $if_list->getLength; $j++) {
      	foreach my $if ($vm->getElementsByTagName("if")) {
            #my $if = $if_list->item($j);

            # To get id attribute
            my $id = $if->getAttribute("id");

            # We get net attribute
            my $net = $if->getAttribute("net");
	 
            # Only TUN/TAP for interfaces attached to bridged networks
            # We do not add tap interfaces for libvirt or lxc VMs. It is done by libvirt/lxc 
            #if (&check_net_br($net)) {
            if (($vm_type ne 'libvirt') && ($vm_type ne 'lxc') && ( &get_net_by_mode($net,"virtual_bridge") != 0) ) {
            #if ( ( &get_net_by_mode($net,"virtual_bridge") != 0) ) {
	 
                my $net_if = $vm_name . "-e" . $id;

                # We link TUN/TAP device 
                #$execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addif $net $net_if");
                if (get_net_by_mode($net,"virtual_bridge") != 0) {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addif $net $net_if");
                } elsif (get_net_by_mode($net,"openvswitch") != 0) {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-port $net $net_if");
                }
                
            }

        }
    }

}

#####################################################
# Host configuration
sub host_config {

    my $doc = $dh->get_doc;

    # If host tag is not present, there is nothing to do
    return if (!$doc->getElementsByTagName("host"));

    my $host = $doc->getElementsByTagName("host")->item(0);

    # To get host's interfaces list
    foreach my $if ($host->getElementsByTagName("hostif")) {

        # To get name and mode attribute
      	my $net = $if->getAttribute("net");
	  	my $net_mode = $dh->get_net_mode ($net);
	  	wlog (VVV, "hostif: net=$net, net_mode=$net_mode", $logp);
	  	
		if ($net_mode eq 'uml_switch') {
			# Create TUN device
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -t $net -u " . $execution->get_uid . " -f " . $dh->get_tun_device);
        }
        hostif_addr_conf ($if, $net, 'add');
    }

    # To get host's routes list
    foreach my $route ($host->getElementsByTagName("route")) {
        my $route_dest = &text_tag($route);;
        my $route_gw = $route->getAttribute("gw");
        my $route_type = $route->getAttribute("type");
        # Routes for IPv4
        if ($route_type eq "ipv4") {
            if ($dh->is_ipv4_enabled) {
                if ($route_dest eq "default") {
                    #$execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet add default gw $route_gw");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " -4 route add default via $route_gw");
                } elsif ($route_dest =~ /\/32$/) {
                    # Special case: X.X.X.X/32 destinations are not actually nets, but host. The syntax of
                    # route command changes a bit in this case
                    #$execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet add -host $route_dest gw $route_gw");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " -4 route add $route_dest via $route_gw");
                } else {
                    #$execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet add -net $route_dest gw $route_gw");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " -4 route add $route_dest via $route_gw");
                }
                #$execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet add $route_dest gw $route_gw");
            }
        }
        # Routes for IPv6
        else {
            if ($dh->is_ipv6_enabled) {
                if ($route_dest eq "default") {
                    #$execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet6 add 2000::/3 gw $route_gw");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " -6 route add default via $route_gw");
                } else {
                    #$execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet6 add $route_dest gw $route_gw");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " -6 route add $route_dest via $route_gw");
                }
            }
        }
    }

    # Enable host forwarding
    my @forwarding = $host->getElementsByTagName("forwarding");
    if (@forwarding == 1) {
        my $f_type = $forwarding[0]->getAttribute("type");
        $f_type = "ip" if (empty($f_type));
        # TODO: change this. When not in VERBOSE mode, echos are redirected to null and do not work... 
        if ($dh->is_ipv4_enabled) {
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"echo"} . " 1 > /proc/sys/net/ipv4/ip_forward") if ($f_type eq "ip" or $f_type eq "ipv4");
        }
        if ($dh->is_ipv6_enabled) {
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"echo"} . " 1 > /proc/sys/net/ipv6/conf/all/forwarding") if ($f_type eq "ip" or $f_type eq "ipv6");
        }
    }

}

#
# Adds or deletes the host interface addresses
#
sub hostif_addr_conf {
    
    my $if  = shift;    
    my $net = shift;
    my $cmd = shift; # add or del

    my $ext_if = $dh->get_net_extif ($net);

    # Interface configuration
    # 1a. To process interface IPv4 addresses
    if ($dh->is_ipv4_enabled) {

        #my $ipv4_list = $if->getElementsByTagName("ipv4");
        #for ( my $j = 0; $j < $ipv4_list->getLength; $j++) {
        foreach my $ipv4 ($if->getElementsByTagName("ipv4")) {
            my $ip = &text_tag($ipv4);
            my $ipv4_effective_mask = "255.255.255.0"; # Default mask value
            my $ip_addr;       
            if (&valid_ipv4_with_mask($ip)) {
                # Implicit slashed mask in the address
                $ip_addr = NetAddr::IP->new($ip);
            } else {
                # Check the value of the mask attribute
                my $ipv4_mask_attr = $ipv4->getAttribute("mask");
                if ($ipv4_mask_attr ne "") {
                    # Slashed or dotted?
                    if (&valid_dotted_mask($ipv4_mask_attr)) {
                        $ipv4_effective_mask = $ipv4_mask_attr;
                    } else {
                        $ipv4_mask_attr =~ /.(\d+)$/;
                        $ipv4_effective_mask = &slashed_to_dotted_mask($1);
                    }
                } else {
                    wlog (N, "WARNING (host): no mask defined for $ip address of host interface. Using default mask ($ipv4_effective_mask)");
                }
                $ip_addr = NetAddr::IP->new($ip, $ipv4_effective_mask);
            }
            if ( ($ext_if) && ($cmd eq 'add') ) {
            	# Delete the address from the external interface before configuring it in the network bridge.
            	# If not done, connectivity problems will arise... 
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " addr del " . $ip_addr->cidr() . " dev $ext_if");
            }
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " addr $cmd " . $ip_addr->cidr() . " dev $net");
         }
    }

    # 2a. To process interface IPv6 addresses
    #my $ipv6_list = $if->getElementsByTagName("ipv6");
    if ($dh->is_ipv6_enabled) {
            
        #for ( my $j = 0; $j < $ipv6_list->getLength; $j++) {
        foreach my $ipv6 ($if->getElementsByTagName("ipv6")) {
            my $ip = &text_tag($ipv6);
            if (&valid_ipv6_with_mask($ip)) {
                # Implicit slashed mask in the address
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " addr $cmd $ip dev $net");
            } else {
                # Check the value of the mask attribute
                my $ipv6_effective_mask = "/64"; # Default mask value          
                my $ipv6_mask_attr = $ipv6->getAttribute("mask");
                if ($ipv6_mask_attr ne "") {
                    # Note that, in the case of IPv6, mask are always slashed
                    $ipv6_effective_mask = $ipv6_mask_attr;
                }
	            if ( ($ext_if) && ($cmd eq 'add') ) {
	                # Delete the address from the external interface before configuring it in the network bridge.
	                # If not done, connectivity problems will arise... 
	                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " addr del $ip$ipv6_effective_mask dev $ext_if");
	            }
                #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $net inet6 add $ip$ipv6_effective_mask");
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " addr $cmd $ip$ipv6_effective_mask dev $net");
            }
        }
    }
}

######################################################
# Wait for socket file to appear indicating that uml_switch process has successfully started
sub uml_switch_wait {
	my $sock = shift;
	my $timeout = shift;
	my $time = 0;

	do {
		if (-S $sock) {
			return 1;
		}
		sleep 1;
	} while ($time++ < $timeout);
	return 0;
}

######################################################
# Chown all vnx working files to a non-privileged user (if user is root)
sub chown_working_dir {
	if ($> == 0) {
		$execution->execute($logp, $bd->get_binaries_path_ref->{"chown"} . " -R " . $execution->get_uid . " " . $dh->get_vnx_dir);
	}
}

######################################################
# Check to see if any of the UMLs use xterm in console tags
sub xauth_needed {

	#my $vm_list = $dh->get_doc->getElementsByTagName("vm");
	#for (my $i = 0; $i < $vm_list->getLength; $i++) {
	foreach my $vm ($dh->get_doc->getElementsByTagName("vm")) {
	   my @console_list = $dh->merge_console($vm);
	   foreach my $console (@console_list) {
          if (&text_tag($console) eq 'xterm') {
		     return 1;
		  }
	   }
	}
	
	return 0;
}

######################################################
# Give the effective user xauth privileges on the current display
sub xauth_add {
	if ($> == 0 && $execution->get_uid != 0 && &xauth_needed) {
		$execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " add `" .
			 $bd->get_binaries_path_ref->{"xauth"} . " list $ENV{DISPLAY}` | su -s /bin/sh -c " .
			 $bd->get_binaries_path_ref->{"xauth"} . " " . getpwuid($execution->get_uid));
	}
}

# Remove the effective user xauth privileges on the current display
sub xauth_remove {
	if ($> == 0 && $execution->get_uid != 0 && &xauth_needed) {

		$execution->execute($logp, "su -s /bin/sh -c '" . $bd->get_binaries_path_ref->{"xauth"} . " remove $ENV{DISPLAY}' " . getpwuid($execution->get_uid));
	}

}


#
# mode_execute
#
# exec commands mode
#
sub mode_execute {

    my $seq = shift;
	
	my %vm_ips;
	
    my $num_plugin_ftrees = 0;
    my $num_plugin_execs  = 0;
    my $num_ftrees = 0;
    my $num_execs  = 0;

   	# If -B, block until ready
   	if ($opts{B}) {
      	my $time_0 = time();
      	%vm_ips = &get_UML_command_ip($seq);
      	while (!&UMLs_cmd_ready(%vm_ips)) {
         	#system($bd->get_binaries_path_ref->{"sleep"} . " $dh->get_delay");
         	sleep($dh->get_delay);
         	my $time_f = time();
         	my $interval = $time_f - $time_0;
         	wlog (V, "$interval seconds elapsed...", $logp);
         	%vm_ips = &get_UML_command_ip($seq);
      	}
   	} else {
      	%vm_ips = &get_UML_command_ip($seq);
    	$execution->smartdie ("some vm is not ready to exec sequence $seq through net. Wait a while and retry...\n") 
    		unless &UMLs_cmd_ready(%vm_ips);
   	}
   
	# Previous checkings and warnings
    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   
	
	# First loop: 
	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
		my $vm = $vm_ordered[$i];
		my $vm_name = $vm->getAttribute("name");

        my @plugin_ftree_list = ();
        my @plugin_exec_list = ();
        my @ftree_list = ();
        my @exec_list = ();

        # Get all the <filetree> and <exec> commands to be executed for sequence $seq
        my ($vm_plugin_ftrees, $vm_plugin_execs, $vm_ftrees, $vm_execs) = 
              get_vm_ftrees_and_execs($vm, $vm_name, 'execute', $seq,  
                   \@plugin_ftree_list, \@plugin_exec_list, \@ftree_list, \@exec_list );

        $num_plugin_ftrees += $vm_plugin_ftrees;
        $num_plugin_execs  += $vm_plugin_execs;
        $num_ftrees += $vm_ftrees;
        $num_execs  += $vm_execs;
          
        if ($vm_plugin_ftrees + $vm_plugin_execs + $vm_ftrees + $vm_execs > 0) { 
            wlog (N, "Calling executeCMD for vm '$vm_name' with seq '$seq'..."); 
            wlog (VVV, "   plugin_filetrees=$vm_plugin_ftrees, plugin_execs=$vm_plugin_execs, user-defined_filetrees=$vm_ftrees, user-defined_execs=$vm_execs", $logp);
	        my $merged_type = $dh->get_vm_merged_type($vm);
			# call the corresponding vmAPI
	    	my $vm_type = $vm->getAttribute("type");
	
	    	my $error = "VNX::vmAPI_$vm_type"->executeCMD(
	    	                         $vm_name, $merged_type, $seq, $vm,  
	    	                         \@plugin_ftree_list, \@plugin_exec_list, 
	    	                         \@ftree_list, \@exec_list);
	        if ($error ne 0) {
	            wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->executeCMD returns " . $error);
	        } else {
	            wlog (N, "...OK");
	        }
            
        }
	}

    wlog (VVV, "Total number of commands executed for seq $seq:", $logp);
    wlog (VVV, "   plugin_filetrees=$num_plugin_ftrees, plugin_execs=$num_plugin_execs, user-defined_filetrees=$num_ftrees, user-defined_execs=$num_execs", $logp);
	if ($num_plugin_ftrees + $num_plugin_execs + $num_ftrees + $num_execs == 0) {
        wlog(N, "--");
		wlog(N, "-- ERROR: no commands found for tag '$seq'");
        wlog(N, "--");
	}

	exec_command_host($seq);
}


#
# mode_shutdown
#
# Destroy current scenario mode
#
sub mode_shutdown {

    my $do_not_exe_cmds = shift;   # If set, do not execute 'on_shutdown' commands

    if (defined ($do_not_exe_cmds)) {
        wlog (V, "do_not_exe_cmds set", "mode_shutdown> ");
    } else {
    	wlog (V, "do_not_exe_cmds NOT set", "mode_shutdown> ");
    }
    if ($opts{F}) {
        wlog (V, "F flag set", "mode_shutdown> ");
    } else {
        wlog (V, "F flag NOT set", "mode_shutdown> ");
    }
    
    my $seq = 'on_shutdown';

    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   
    my $only_vm = "";
   	
    my $num_plugin_ftrees = 0;
    my $num_plugin_execs  = 0;
    my $num_ftrees = 0;
    my $num_execs  = 0;
   
    for ( my $i = 0; $i < @vm_ordered; $i++) {

        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");

        my $merged_type = $dh->get_vm_merged_type($vm);

        unless ($opts{F} || defined($do_not_exe_cmds) ){

            my @plugin_ftree_list = ();
	        my @plugin_exec_list = ();
	        my @ftree_list = ();
	        my @exec_list = ();
	
            # Get all the <filetree> and <exec> commands to be executed for $seq='on_shutdown'
	        my ($vm_plugin_ftrees, $vm_plugin_execs, $vm_ftrees, $vm_execs) = 
	              get_vm_ftrees_and_execs($vm, $vm_name, 'shutdown', $seq,  
	                   \@plugin_ftree_list, \@plugin_exec_list, \@ftree_list, \@exec_list );

	        $num_plugin_ftrees += $vm_plugin_ftrees;
	        $num_plugin_execs  += $vm_plugin_execs;
	        $num_ftrees += $vm_ftrees;
	        $num_execs  += $vm_execs;
	          
	        if ( $vm_plugin_ftrees + $vm_plugin_execs + $vm_ftrees + $vm_execs > 0) { 
	            wlog (VVV, "Calling executeCMD for vm $vm_name with seq $seq to execute:", $logp); 
	            wlog (VVV, "   plugin_filetrees=$vm_plugin_ftrees, plugin_execs=$vm_plugin_execs, user-defined_filetrees=$vm_ftrees, user-defined_execs=$vm_execs", $logp);
	            # call the corresponding vmAPI
	            my $vm_type = $vm->getAttribute("type");
                wlog (N, "Executing '$seq' commands on virtual machine $vm_name of type $merged_type...");
	            my $error = "VNX::vmAPI_$vm_type"->executeCMD(
	                                     $vm_name, $merged_type, $seq, $vm,  
	                                     \@plugin_ftree_list, \@plugin_exec_list, 
	                                     \@ftree_list, \@exec_list);
                if ($error ne 0) {
                    wlog (N, "VNX::vmAPI_${vm_type}->executeCMD returns " . $error);
	            } else {
	                wlog (N, "...OK")
	            }
	        }
	    }

	    if ($num_plugin_ftrees + $num_plugin_execs + $num_ftrees + $num_execs == 0) {
	        wlog(V, "Nothing to execute for VM $vm_name with seq=$seq", $logp);
	    } else {
	        wlog (VVV, "Total num of commands executed for VM $vm_name with seq=$seq:", $logp);
	        wlog (VVV, "   plugin_filetrees=$num_plugin_ftrees, plugin_execs=$num_plugin_execs, user-defined_filetrees=$num_ftrees, user-defined_execs=$num_execs", $logp);	    	
	    }

      	if ($opts{M}){
         	$only_vm = $vm_name;  	
      	}
      
      	if ($opts{F}){

         	# call the corresponding vmAPI
           	my $vm_type = $vm->getAttribute("type");
            wlog (N, "Releasing virtual machine '$vm_name' of type '$merged_type'...");
           	my $error = "VNX::vmAPI_$vm_type"->destroyVM($vm_name, $merged_type);
            if ($error ne 0) {
                wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->destroyVM returns " . $error);
            } else {
            	wlog (N, "...OK")
            }
      	}
      	else{
           	# call the corresponding vmAPI
           	my $vm_type = $vm->getAttribute("type");
           	wlog (N, "Shutdowning virtual machine '$vm_name' of type '$merged_type'...");
           	my $error = "VNX::vmAPI_$vm_type"->shutdownVM($vm_name, $merged_type, $opts{F});
            if ($error ne 0) {
                wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->shutdownVM returns " . $error);
            } else {
                wlog (N, "...OK")
            }
    	}
    	
    	Time::HiRes::sleep(0.2); # Sometimes libvirt 0.9.3 gives an error when shutdown VMs too fast...
    	
   	}
   
#   unless ($opts{M}){

	# For non-forced mode, we have to wait all UMLs dead before to destroy 
    # TUN/TAP (next step) due to these devices are yet in use
    #
    # Note that -B doensn't affect to this functionallity. UML extinction
    # blocks can't be avoided (is needed to perform bridges and interfaces
    # release)
    my $time_0 = time();
      
    if ((!$opts{F})&&($execution->get_exe_mode() != $EXE_DEBUG)) {		

    	wlog (N, "---------- Waiting until virtual machines extinction ----------");

        while (my $pids = &VM_alive($only_vm)) {
            wlog (N,  "waiting on processes $pids...");;
            #system($bd->get_binaries_path_ref->{"sleep"} . " $dh->get_delay");
            sleep($dh->get_delay);
            my $time_f = time();
            my $interval = $time_f - $time_0;
            wlog (N, "$interval seconds elapsed...");;
        }       
  	}

#    if (($opts{F})&(!($opts{M})))   {

    if (!($opts{M}))   {

         # 1. To stop UML
         #   &halt;

         # 2. Remove xauth data
         &xauth_remove;

         # 3a. To remote TUN/TAPs devices (for uml_switched networks, <net mode="uml_switch">)
         &tun_destroy_switched;
  
         # 3b. To destroy TUN/TAPs devices (for bridged_networks, <net mode="virtual_bridge">)
         &tun_destroy;

         # 4. To restore host configuration
         &host_unconfig;

         # 5. To remove external interfaces
         &external_if_remove;

         # 6. To remove bridges
         &bridges_destroy;

         # Destroy the mgmn_net socket when <vmmgnt type="net">, if needed
         if (($dh->get_vmmgmt_type eq "net") && ($dh->get_vmmgmt_autoconfigure ne "")) {
            if ($> == 0) {
               my $sock = $dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("sock");
               if (empty($sock)) { $sock = ''} 
               else              { $sock = do_path_expansion($sock) };
               if (-S $sock) {
                  # Destroy the socket
                  &mgmt_sock_destroy($sock,$dh->get_vmmgmt_autoconfigure);
               }
            }
            else {
               wlog (N, "VNX warning: <mgmt_net> autoconfigure attribute only is used when VNX parser is invoked by root. Ignoring socket autodestruction");
            }
         }

         # If <host_mapping> is in use and not in debug mode, process /etc/hosts
         &host_mapping_unpatch ($dh->get_scename, "/etc/hosts") if (($dh->get_host_mapping) && ($execution->get_exe_mode() != $EXE_DEBUG));

         # To remove lock file (it exists while topology is running)
         $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_sim_dir . "/lock");
    }

}


#
# get_vm_ftrees_and_execs
#
# Returns the <filetree>'s and <exec>'s to execute in a specific situation:  
#   - call to mode_exec with a $seq specified by the user
#   - call to mode_shutdown with an implicit $seq='on_shutdown'
#
# The source files specified in <filetree> commands are copied to:
#   $dh->get_vm_tmp_dir($vm_name) . "/$seq/filetree/$dst_num"
# being $dst_num the order number of the filetree (starting from 1)
#
#
# Parameters:
#   - $mode, 'define', 'exec' or 'shutdown'
#   - $seq 
#   - \@plugin_ftree_list
#   - \@plugin_exec_list
#   - \@ftree_list
#   - \@exec_list
# 
# Return:
#   - ($vm_plugin_ftrees, $vm_plugin_execs, $vm_ftrees, $vm_execs)
#   - all the <filetree> and <exec> tags returned in the arrays passed by reference
#
sub get_vm_ftrees_and_execs {

    my $vm      = shift;
    my $vm_name = shift;
    my $mode    = shift; 
    my $seq     = shift; 
    my $plugin_ftree_list_ref = shift;
    my $plugin_exec_list_ref  = shift;
    my $ftree_list_ref        = shift;
    my $exec_list_ref         = shift;

    my $vm_plugin_ftrees = 0; 
    my $vm_plugin_execs  = 0; 
    my $vm_ftrees = 0; 
    my $vm_execs  = 0; 
    
    my $merged_type = $dh->get_vm_merged_type($vm);
    
    # Plugin operations:
    #  1 - for each active plugin, call: $plugin->getFiles
    #  2 - create a list of <filetree> commands to copy all the files 
    #      returned and pass it as a parameter to executeCMD
    #  3 - for each active plugin, call: $plugin->getCommands
    #  4 - create a list of <exec> command returned 
    #      to pass it as a parameter to executeCMD
        
    my $dst_num = 1;    # Name of the directory where each specific file/dir will be copied
                        # in the shared disk. See filetree processing for details       
        
    # Create the XML doc to store the <filetree>'s and <exec>'s returned
    # by the calls to get*Files and get*Commands
    #my $xdoc = XML::DOM::Document->new;
    #my $xdoc = XML::LibXML->createDocument( "1.0", "UTF-8" );

    #my $plugin_cmds = $xdoc->createElement('plugin_cmds');
    #$xdoc->appendChild($plugin_cmds);
        
    foreach my $plugin (@plugins) {
            
	    #  1 - for each active plugin, call: $plugin->get*Files for define mode
        # Create temp directory for plugins files
        my $files_dir = $dh->get_vm_tmp_dir($vm_name) . "/plugins/$plugin/$vm_name/";
        $execution->execute($logp, "mkdir -p $files_dir");
        $execution->execute($logp, "rm -rf $files_dir/*");

        my %files;            


        # Call the getFiles plugin function
        %files = $plugin->getFiles($vm_name, $files_dir, $seq);

        if (defined($files{"ERROR"}) && $files{"ERROR"} ne "") {
            $execution->smartdie("plugin $plugin getFiles($vm_name) in mode=$mode and sequence=$seq error: ".$files{"ERROR"});
        }

        if (keys(%files) > 0 ) {
            my $res=`tree $files_dir`; 
            wlog (VVV, "getFiles returns " . keys(%files) . " files/dirs for vm $vm_name:\n $res", $logp);
        } else {
            wlog (VVV, "getFiles returns no files/dirs for vm $vm_name", $logp);
        }
                
        if (keys(%files) > 0 ) { 
            $vm_plugin_ftrees += keys(%files);
        }
        
        #  2 - create a list of <filetree> commands to copy all the files 
        #      returned and pass it as a parameter to executeCMD
        foreach my $key ( keys %files ) {   
               
            # $key holds a comma separated list with the destination file/dir in the VM and the user, group and permissions
            # $files{$key} holds the pathname of the file/dir in the host
            
            my @file = split( /,/, $key );  # $files[0] -> dst
                                            # $files[1] -> user
                                            # $files[2] -> group
                                            # $files[3] -> perms
            wlog (VVV, "**** dst=$file[0], user=$file[1], group=$file[2], perms=$file[3], ", $logp);                                                           
            # Check whether file/dir uses a relative path
            $execution->smartdie ("file/dir $files{$key} returned by $plugin->getFiles (vm=$vm_name, seq=$seq) uses an absolut path (should be relative to files_dir directory)")       
                if ( $files{$key} =~ /^\// );
            # Check whether file/dir exists
            $execution->smartdie ("file/dir $files_dir$files{$key} returned by plugin $plugin->getFiles does not exist")        
                unless ( -e "$files_dir$files{$key}" );
            
            wlog (VVV, "Creating <filetree> tag for plugin file/dir $key", $logp);
                
            # Create the <filetree> tag
            #   Format: <filetree seq="plugin-$plugin" root="$key">$files{$key}</filetree>
            my $ftree_tag = XML::LibXML::Element->new('filetree');
            $ftree_tag->setAttribute( seq => "$seq");
            if ( -d "$files_dir$files{$key}" )  {   # If $files{$key} is a directory...
                if ( $merged_type eq "libvirt-kvm-windows" ) { # Windows vm
                    if  ( !( $file[0] =~ /\$/ ) ) {     # ...and $file[0] (dst dir) does not end with a "\"
                        # Add a slash; <filetree> root attribute must be a directory
                        $ftree_tag->setAttribute( root => "$file[0]\\" );
                    }
                } else { # not windows
                    if  ( !( $file[0] =~ /\/$/ ) ) {     # ...and $file[0] (dst dir) does not end with a "/"
                        # Add a slash; <filetree> root attribute must be a directory
                        $ftree_tag->setAttribute( root => "$file[0]/" );
                    }
                }
            } else { # $files{$key} is not a directory...
                $ftree_tag->setAttribute( root => "$file[0]" );
            }           
            $ftree_tag->appendTextNode ("$files{$key}");            
            if ($file[1]) {
                $ftree_tag->setAttribute( user => "$file[1]" );
            }
            if ($file[2]) {
                $ftree_tag->setAttribute( group => "$file[2]" );
            }
            if ($file[3]) {
                $ftree_tag->setAttribute( perms => "$file[3]" );
            }
             
            # Add the filetree node to the list passed to executeCMD
            push (@{$plugin_ftree_list_ref}, $ftree_tag);
                
            # Copy the file/dir to "filetree/$dst_num" dir
            my $dst_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq/filetree/$dst_num";
            
            $execution->execute($logp, "mkdir -p $dst_dir");
            if ( -d "$files_dir$files{$key}" ) { # It is a directory
                $execution->execute($logp, "cp -r $files_dir$files{$key}/* $dst_dir");
            } else { # It is a file
                $execution->execute($logp, "cp $files_dir$files{$key} $dst_dir");
            }
              
            $dst_num++;
        }           

        #  3 - for each active plugin, call $plugin->get*Commands 
        my @commands;            
        # Call the getCommands plugin function
        @commands = $plugin->getCommands($vm_name,$seq);
        my $error = shift(@commands);
        if ($error ne "") {
            $execution->smartdie("plugin $plugin getCommands($vm_name,$seq) error: $error");
        }

        wlog (VVV, "getCommands returns " . scalar(@commands) . " commands", $logp);
        if (scalar(@commands) > 0) { 
            $vm_plugin_execs  += scalar(@commands);
        } 
           
        #  4 - add <exec> commands for every command returned by get*Command
        foreach my $cmd (@commands) {
            wlog (VVV, "Creating <exec> tag for plugin command '$cmd'", $logp);
    
            # Create the <exec> tag
            #   Format: <exec seq="$seq" type="verbatim" ostype="??">$cmd</exec>
            my $exec_tag = XML::LibXML::Element->new('exec');
            $exec_tag->setAttribute( seq => "$seq");
            $exec_tag->setAttribute( type => "verbatim");
            $exec_tag->setAttribute( ostype => "system");
            $exec_tag->appendTextNode("$cmd");
           
            # Add the filetree node to the list passed to executeCMD
            push (@{$plugin_exec_list_ref}, $exec_tag);
        }
    }

    # Get the <filetree> and <exec> tags with sequence $seq and add them to the 
    # lists passed to executeCMD

    # <filetree>
    my @filetree_list = $dh->merge_filetree($vm);
    foreach my $filetree (@filetree_list) {
            
        my $filetree_seq_string = $filetree->getAttribute("seq");
                
        # We accept several commands in the same seq tag, separated by commas
        my @filetree_seqs = split(',',$filetree_seq_string);
        foreach my $filetree_seq (@filetree_seqs) {

            # Remove leading or trailing spaces
            $filetree_seq =~ s/^\s+//;
            $filetree_seq =~ s/\s+$//;
                
            if ( $filetree_seq eq $seq ) {
                    
                # $seq matches, copy the filetree node to the list      
                my $root = $filetree->getAttribute("root");
                my $value = &text_tag($filetree);

                # Add the filetree node to the list passed to executeCMD
                my $filetree_clon = $filetree->cloneNode(1);
                push (@{$ftree_list_ref}, $filetree_clon);
    
                # Copy the files/dirs to "filetree/$dst_num" dir
                my $src = &get_abs_path ($value);
                #$src = &chompslash($src);
                if ( -d $src ) {   # If $src is a directory...
                
	                if ( $merged_type eq "libvirt-kvm-windows" ) { # Windows vm
	                    if  ( !( $root =~ /\$/ ) ) {     # ...and $file[0] (dst dir) does not end with a "\"
	                        # Add a slash; <filetree> root attribute must be a directory
                            wlog (N, "WARNING: root attribute must be a directory (end with a \"\\\") in " . $filetree->toString(1));
                            $filetree->setAttribute( root => "$root\\" );
	                    }
	                } else { # not windows
	                    if  ( !( $root =~ /\/$/ ) ) {     # ...and $file[0] (dst dir) does not end with a "/"
	                        # Add a slash; <filetree> root attribute must be a directory
		                    wlog (N, "WARNING: root attribute must be a directory (end with a \"/\") in " . $filetree->toString(1));
		                    $filetree->setAttribute( root => "$root/" );
	                    }
	                }
                } 
                    
                my $dst_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq/filetree/$dst_num";
                $execution->execute($logp, "mkdir -p $dst_dir");
	            if ( -d "$src" ) { # It is a directory
                    $execution->execute($logp, $bd->get_binaries_path_ref->{"cp"} . " -r $src/* $dst_dir");
	            } else { # It is a file
                    $execution->execute($logp, $bd->get_binaries_path_ref->{"cp"} . " $src $dst_dir");
	            }
                
                $dst_num++;
                $vm_ftrees++; 
            }
        }
    }

    my $ftrees_files_dir = $dh->get_vm_tmp_dir($vm_name);
    my $res=`tree $ftrees_files_dir`; 
    wlog (VVV, "temporary filetrees directory content for sequence $seq \n $res");

    # <exec>
    foreach my $command ($vm->getElementsByTagName("exec")) {
    
        # To get attributes
        my $cmd_seq_string = $command->getAttribute("seq");
  
        # We accept several commands in the same seq tag, separated by commas
        my @cmd_seqs = split(',',$cmd_seq_string);
        foreach my $cmd_seq (@cmd_seqs) {
            
            # Remove leading or trailing spaces
            $cmd_seq =~ s/^\s+//;
            $cmd_seq =~ s/\s+$//;
    
            if ( $cmd_seq eq $seq ) {

                # Read values of <exec> tag
                my $type = $command->getAttribute("type");
                my $mode = $command->getAttribute("mode");
                my $ostype = $command->getAttribute("ostype");
                my $value = &text_tag($command);

                wlog (VVV, "Creating <exec> tag for user-defined command '$value'", $logp);

                # Case 1. Verbatim type
                if ( $type eq "verbatim" ) {  
                        
                    # Including command "as is"
                    # Create the new node
                    my $new_exec = XML::LibXML::Element->new('exec');
                    $new_exec->setAttribute( seq => $seq);
                    $new_exec->setAttribute( type => $type);
                    $new_exec->setAttribute( ostype => $ostype);
                    $new_exec->appendTextNode( $value );
  
                    # Add the exec node to the list passed to executeCMD
                    push (@{$exec_list_ref}, $new_exec);
                }

                # Case 2. File type
                elsif ( $type eq "file" ) {
                    # We open the file and write commands line by line
                    my $include_file = &do_path_expansion( &text_tag($command) );
                    open INCLUDE_FILE, "$include_file" or $execution->smartdie("can not open $include_file: $!");
                    while (<INCLUDE_FILE>) {
                        chomp;

                        # Create a new node
                        my $new_exec = XML::LibXML::Element->new('exec');
                        $new_exec->setAttribute( seq => $seq);
                        $new_exec->setAttribute( type => $type);
                        $new_exec->setAttribute( ostype => $ostype);
                        $new_exec->appendTextNode( $_ );
        
                        # Add the exec node to the list passed to executeCMD
                        push (@{$exec_list_ref}, $new_exec);
                    }
                    close INCLUDE_FILE;
                }

                #$any_cmd = 1;
                $vm_execs++;

            }
        }
    }
   
    return ($vm_plugin_ftrees, $vm_plugin_execs, $vm_ftrees, $vm_execs);
    
}



######################################################
# To restore host configuration

sub host_unconfig {

   my $doc = $dh->get_doc;

   # If host <host> is not present, there is nothing to unconfigure
   return if (!$doc->getElementsByTagName("host"));

   # To get <host> tag
   my $host = $doc->getElementsByTagName("host")->item(0);

    # To get host routes list
    foreach my $route ($host->getElementsByTagName("route")) {
        my $route_dest = &text_tag($route);;
        my $route_gw = $route->getAttribute("gw");
        my $route_type = $route->getAttribute("type");
        # Routes for IPv4
        if ($route_type eq "ipv4") {
          if ($dh->is_ipv4_enabled) {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " -4 route del $route_dest via $route_gw");
=BEGIN    	
             if ($route_dest eq "default") {
                $execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet del $route_dest gw $route_gw");
             } elsif ($route_dest =~ /\/32$/) {
	            # Special case: X.X.X.X/32 destinations are not actually nets, but host. The syntax of
		        # route command changes a bit in this case
                $execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet del -host $route_dest gw $route_gw");
	         } else {
                $execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet del -net $route_dest gw $route_gw");
             }
             #$execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet del $route_dest gw $route_gw");
=END
=cut
          }

        }
        # Routes for IPv6
        else {
            if ($dh->is_ipv6_enabled) {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " -6 route del $route_dest via $route_gw");
                #if ($route_dest eq "default") {
                #    $execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet6 del 2000::/3 gw $route_gw");
                #} else {
                #    $execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet6 del $route_dest gw $route_gw");
                #}
            }
       }
   }

    # To get host interfaces list
   	foreach my $if ($host->getElementsByTagName("hostif")) {

	   	# To get name and mode attribute
	   	my $net = $if->getAttribute("net");
        my $net_mode = $dh->get_net_mode ($net);

=BEGIN
	  	# To get list of defined <net>
   	  	my $net_list = $doc->getElementsByTagName("net");
   	  	for ( my $i = 0; $i < $net_list->getLength; $i++ ) {
      		my $neti = $net_list->item($i);
      		# To get name attribute
		    my $net_name = $neti->getAttribute("name");
		    if ($net_name eq $net) {
		    	$net_mode = $neti->getAttribute("mode");
		    	#print "**** hostif:   $net_name, $net_mode\n"
		    }
   	  	}
=END
=cut

        # Delete host if addresses
        hostif_addr_conf ($if, $net, 'del');

	   	# Destroy the tun device
		if ($net_mode eq 'uml_switch') {
	   		#$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $net down");
	   		$execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $net down");           
			$execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -d $net -f " . $dh->get_tun_device);
        }
    }

}



######################################################
# To remove external interfaces

sub external_if_remove {

    my $doc = $dh->get_doc;

    # To get list of defined <net>
    foreach my $net ($doc->getElementsByTagName("net")) {

        # To get name attribute
        my $net_name = $net->getAttribute("name");

        # We check if there is an associated external interface
        my $external_if = $net->getAttribute("external");
        next if (empty($external_if));

        # To check if VLAN is being used
        my $vlan = $net->getAttribute("vlan");
        $external_if .= ".$vlan" unless (empty($vlan));

        # To decrease use counter
        &dec_cter($external_if);
        
        my $mode = $net->getAttribute("mode");
        # To clean up not in use physical interfaces
        if (&get_cter($external_if) == 0) {
            #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $net_name 0.0.0.0 " . $dh->get_promisc . " up");
            #$execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $net_name up");         
            if ($mode eq "virtual_bridge") {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " delif $net_name $external_if");
            } elsif ($mode eq "openvswitch") {         
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " del-port $net_name $external_if");
            }
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " delif $net_name $external_if");
            unless (empty($vlan)) {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"vconfig"} . " rem $external_if");
            } else { # No vlan associated to external if
                # Note that now the interface has no IP address nor mask assigned, it is
                # unconfigured! Tag <physicalif> is checked to try restore the interface
                # configuration (if it exists)
                &physicalif_config($external_if);
            }
        }
    }
}

######################################################
# To remove TUN/TAPs devices

sub tun_destroy_switched {

    my $doc = $dh->get_doc;

    # Remove the symbolic link to the management switch socket
    if ($dh->get_vmmgmt_type eq 'net') {
        my $socket_file = $dh->get_networks_dir . "/" . $dh->get_vmmgmt_netname . ".ctl";
        $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -f $socket_file");
    }

    #my $net_list = $doc->getElementsByTagName("net");

    #for ( my $i = 0 ; $i < $net_list->getLength; $i++ ) {
   	foreach my $net ($doc->getElementsByTagName("net")) {

        # We get attributes
        my $net_name = $net->getAttribute("name");
        my $mode     = $net->getAttribute("mode");
        my $sock     = $net->getAttribute("sock");
        my $vlan     = $net->getAttribute("vlan");
        my $cmd;
      
        # This function only processes uml_switch networks
        if ($mode eq "uml_switch") {

            # Decrease the use counter
            &dec_cter("$net_name.ctl");
            
            # Destroy the uml_switch only when no other concurrent scenario is using it
            if (&get_cter ("$net_name.ctl") == 0) {
                my $socket_file = $dh->get_networks_dir() . "/$net_name.ctl";
                # Casey (rev 1.90) proposed to use -f instead of -S, however 
                # I've performed some test and it fails... let's use -S?
                #if ($sock eq '' && -f $socket_file) {
                if ($sock eq '' && -S $socket_file) {
                    $cmd = $bd->get_binaries_path_ref->{"kill"} . " `" .
                        $bd->get_binaries_path_ref->{"lsof"} . " -t $socket_file`";
                    $execution->execute($logp, $cmd);
				    sleep 1;
                }
                $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -f $socket_file");
            }
        }
    }
}

######################################################
# To remove TUN/TAPs devices

sub tun_destroy {

    my @vm_ordered = $dh->get_vm_ordered;

    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];

        # To get name and type attribute
        my $vm_name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");

        # To throw away and remove management device (id 0), if neeed
        #my $mng_if_value = &mng_if_value($dh,$vm);
        my $mng_if_value = &mng_if_value($vm);
      
        if ( ($dh->get_vmmgmt_type eq 'private') && ($mng_if_value ne "no") && ($vm_type ne 'lxc')) {
            my $tun_if = $vm_name . "-e0";
            #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $tun_if down");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $tun_if down");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -d $tun_if -f " . $dh->get_tun_device);
        }

        # To get interfaces list
        foreach my $if ($vm->getElementsByTagName("if")) {

            # To get attributes
            my $id = $if->getAttribute("id");
            my $net = $if->getAttribute("net");

            # Only exists TUN/TAP in a bridged network
            #if (&check_net_br($net)) {
            if (&get_net_by_mode($net,"virtual_bridge") != 0) {
	            # To build TUN device name
	            my $tun_if = $vm_name . "-e" . $id;
	
	            # To throw away TUN device
	            #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $tun_if down");
	            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $tun_if down");
	
	            # To remove TUN device
	            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -d $tun_if -f " . $dh->get_tun_device);

            }

        }

    }

}

######################################################
# To remove bridges

sub bridges_destroy {

    my $doc = $dh->get_doc;

    wlog (VVV, "bridges_destroy called", $logp);
    # To get list of defined <net>
   	foreach my $net ($doc->getElementsByTagName("net")) {

        # To get attributes
        my $net_name = $net->getAttribute("name");
        my $mode = $net->getAttribute("mode");

    	wlog (VVV, "net=$net_name", $logp);
    	
        # This function only processes uml_switch networks
        if ($mode ne "uml_switch") {

            # Set bridge down and remove it only in the case there isn't any associated interface 
            my @br_ifs =&vnet_ifs($net_name,$mode);  
            wlog (N, "OVS a eliminar @br_ifs", $logp);
	    	wlog (VVV, "br_ifs=@br_ifs", $logp);

            if ( (@br_ifs == 1) && ( $br_ifs[0] eq "${net_name}-e00" ) ) {
         	
                # Destroy the tap associated with the bridge
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set ${net_name}-e00 down");
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -d ${net_name}-e00");
            
                # Destroy the bridge
                #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $net_name down");
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $net_name down");
                #$execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " delbr $net_name");
                if ($mode eq "virtual_bridge") {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " delbr  $net_name");
                } elsif ($mode eq "openvswitch") {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " del-br $net_name");
                }
            }
        }
    }
}




sub mode_destroy {
   
   my $vm_left = 0;
   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {

        my $vm = $vm_ordered[$i];

        # To get name attribute
        my $vm_name = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);
        unless ($vm_hash{$vm_name}){
            $vm_left = 1;
            next;
        }
        # call the corresponding vmAPI
        my $vm_type = $vm->getAttribute("type");
        wlog (N, "Undefining virtual machine '$vm_name' of type '$merged_type'...");
        my $error = "VNX::vmAPI_$vm_type"->undefineVM($vm_name, $merged_type);
        if ($error ne 0) {
            wlog (N, "...ERROR: VNX::vmAPI_${vm_type}->undefineVM returns " . $error);
        } else {
            wlog (N, "...OK")
        }
 
    }
    if ( ($vm_left eq 0) && (!$opts{M} ) ) {
        # 3. Delete supporting scenario files...
        #    ...but only if -M option is not active (DFC 27/01/2010)

        # Delete all files in scenario but the scenario map (<scename>.png) 
        #$execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_sim_dir . "/*");
        $execution->execute($logp, $bd->get_binaries_path_ref->{"find"} . " " . $dh->get_sim_dir . "/* ! -name *.png -delete");

        if ($vmfs_on_tmp eq 'yes') {
                $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " 
                                     . $dh->get_tmp_dir() . "/.vnx/" . $dh->get_scename  . "/*");
        }        

        # Delete network/$net.ports files of ppp networks
        my $doc = $dh->get_doc;
		foreach my $net ($doc->getElementsByTagName ("net")) {
            my $type = $net->getAttribute ("type");
            if ($type eq 'ppp') {
		        $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_networks_dir 
		                             . "/" . $net->getAttribute ("name") . ".ports");
            }
        }      
    }
}


#######################################################

# Additional functions

# check_user
#
# Check if the user that runs the script will have suitables privileges
# 
# - root users always can run vnumlparser.pl
# - no-root users can run vnumlparser.pl if:
#      + using only uml_switch networks
#      + not using <vm_mgmt type="private">
#      + not using <host>
#      + not using <host_mapping>
#
# Return 0, if the user can run the script or a message error in other case
#
sub check_user {
	
    my $doc = $dh->get_doc;
    my $basename = basename $0;
	
	# In debug mode, anyone can run the script
	return 0 if ($execution->get_exe_mode() == $EXE_DEBUG);
	
	# Root user alwais can run the script
	return 0 if ($> == 0);
	
	# Search for not uml_switch networks
	#my $net_list = $doc->getElementsByTagName("net");
	#for (my $i = 0; $i < $net_list->getLength; $i++) {
	foreach my $net ($doc->getElementsByTagName("net")) {
		if ($net->getAttribute("mode") ne "uml_switch") {
			my $net_name = $net->getAttribute("name");
			return "$net_name is a bridge_virtual net and only uml_switch virtual networks can be used by no-root users when running $basename";
		}
	}
	
    # Search for managemente interfaces (management interfaces needs ifconfig in the host
    # side, and no-root user can not use it)
	#my $net_name = &at_least_one_vm_with_mng_if($dh,$dh->get_vm_ordered);
	my $net_name = &at_least_one_vm_with_mng_if($dh->get_vm_ordered);
    if ($dh->get_vmmgmt_type eq 'private' && $net_name ne '') {
    	return "private vm management is enabled, and only root can configure management interfaces\n
		Try again using <mng_if>no</mng_if> for virtual machine $net_name or use net type vm management";
    }

    # Search for host configuration (no-root user can not perform any configuration in the host)
    my @host_list = $doc->getElementsByTagName("host");
    if (@host_list == 1) {
    	return "only root user can perform host configuration. Try again removing <host> tag.";
    }
    
    # Search for host_mapping (no-root user can not touch /etc/host)
    my @host_map_list = $doc->getElementsByTagName("host_mapping");
    if (@host_map_list == 1) {
    	return "only root user can perform host mapping configuration. Try again removing <host_mapping> tag.";
    }
	
	return 0;

}

# check_deprecated
#
# Check deprecated tags and print information in case something is found.
#
sub check_deprecated {
	
    my $doc = $dh->get_doc;
    
    if (defined $opts{cid}) {
    	vnx_die ("\n  'cid' option is deprecated. Use '--console con_name' to specify console names.")
    }
    
    
}




# get_kernel_pids;
#
# Return a list with the list of PID of UML kernel processes
#
sub get_kernel_pids {

    my $only_vm = shift;
	my @pid_list;
	   
	foreach my $vm ($dh->get_vm_ordered) {
		# Get name attribute
		my $vm_name = $vm->getAttribute("name");

		if ($only_vm ne '' && $only_vm ne $vm_name){
			next;
		}

		my $pid_file = $dh->get_vm_run_dir($vm_name) . "/pid";
		next if (! -f $pid_file);
		my $command = $bd->get_binaries_path_ref->{"cat"} . " $pid_file";
		chomp(my $pid = `$command`);
		push(@pid_list, $pid);
	}
	return @pid_list;
}




# hosts_mapping_patch
#
# Inserts UMLs names in the /etc/hosts file, when <host_mapping> is presented
# Arguments:
#
#    - First: lines to add, in a string
#    - Second: scenario name
#    - Third: name file (usually /etc/hosts)
# 
# A VNUML sections is inserted in the /etc/hosts file with the following structure:
# 
# VNUML BEGIN -- DO NO EDIT!!!
#
# BEGIN: sim_name_1
# (names)
# END: sim_name_1
#
# BEGIN: sim_name_2
# (names)
# END: sim_name_2
#
# (...)
#
# VNUML END
#
# The function is not much smart. I would like to hear suggestions about... :)
#
sub host_mapping_patch {

#   my $lines = shift;
   my $sim_name = shift;
   my $file_name = shift;

   # DEBUG
   #print "--filename: $file_name\n";
   #print "--scename:  $scename\n";

change_to_root();
   # Openning files
   open HOST_FILE, "$file_name"
      or $execution->smartdie ("can not open $file_name: $!");
   open FIRST, ">" . $dh->get_tmp_dir . "/hostfile.1"
      or $execution->smartdie ("can not open " . $dh->get_tmp_dir . "/hostfile.1 for writting: $!");
   open SECOND, ">" . $dh->get_tmp_dir . "/hostfile.2"
      or $execution->smartdie ("can not open " . $dh->get_tmp_dir . "/hostfile.2 for writting: $!");
   open THIRD, ">" . $dh->get_tmp_dir . "/hostfile.3"
      or $execution->smartdie ("can not open " . $dh->get_tmp_dir . "/hostfile.3 for writting: $!");

   # Status list:
   # 
   # 0 -> before VNUML section
   # 1 -> inside VNUML section, before scenario subsection
   # 2 -> inside simultaion subsection
   # 3 -> after scenario subsection, inside VNUML section
   # 4 -> after VNUML section
   my $status = 0;

   while (<HOST_FILE>) {
      # DEBUG
      #print "$_";
      #print "--status: $status\n";
      if ($status == 0) {
         print FIRST $_;
	     $status = 1 if (/^\# VNX BEGIN/);
      }
      elsif ($status == 1) {
         if (/^\# BEGIN: $sim_name$/) {
	    $status = 2;
	 }
	 elsif (/^\# VNX END/) {
	    $status = 4;
	    print THIRD $_;
	 }
	 else {
            print FIRST $_;
	 }
      }
      elsif ($status == 2) {
         if (/^\# END: $sim_name$/) {
	    $status = 3;
	 }
      }
      elsif ($status == 3) {
         print THIRD $_;
	     $status = 4 if (/^\# VNX END/);
      }
      elsif ($status == 4) {
         print THIRD $_;
      }
   }
   close HOST_FILE;

   # Check the final status when the hosts file has ended
   if ($status == 0) {
      # No VNUML section found
      print FIRST "\# VNX BEGIN -- DO NOT EDIT!!!\n";
      print FIRST "\n";
      print THIRD "\n";
      print THIRD "\# VNX END\n";
   }
   elsif ($status == 1) {
     # Found VNUML BEGIN but not found VNUML END. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 2) {
     # Found simultaion subsection BEGIN, but not found the end. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 3) {
     # Found VNUML BEGIN but not found VNUML END. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 4) {
     # Doing nothing
   }
   
   # Second fragment
   my $command = $bd->get_binaries_path_ref->{"cat"} . " " . $dh->get_sim_dir . "/hostlines";
   chomp (my $lines = `$command`);
   $command = $bd->get_binaries_path_ref->{"date"};
   chomp (my $now = `$command`);
   print SECOND "\# BEGIN: $sim_name\n";
   print SECOND "\# topology built: $now\n";
   print SECOND "$lines\n";
   print SECOND "\# END: $sim_name\n";
   
   # Append of fragments
   close FIRST;
   close SECOND;
   close THIRD;

   # Replace the old file
   my $dir_name = dirname $file_name;
   my $basename = basename $file_name;
   my $file_bk = "$dir_name/$basename.vnx.old";
   $execution->execute($logp, $bd->get_binaries_path_ref->{"mv"} . " $file_name $file_bk");
   $execution->execute($logp, $bd->get_binaries_path_ref->{"cat"} . " " . $dh->get_tmp_dir . "/hostfile.1 " . $dh->get_tmp_dir . "/hostfile.2 " . $dh->get_tmp_dir . "/hostfile.3 > $file_name");

   $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/hostfile.1 " . $dh->get_tmp_dir . "/hostfile.2 " . $dh->get_tmp_dir . "/hostfile.3");
back_to_user();
}

# hosts_mapping_unpatch
#
# Removes UMLs names in the /etc/hosts file, when <host_mapping> is presented
# Arguments:
#
#    - First: scenario name
#    - Second: name file (usually /etc/hosts)
#    
sub host_mapping_unpatch {

   my $sim_name = shift;
   my $file_name = shift;

change_to_root();

   # Openning files
   open HOST_FILE, "$file_name"
      or $execution->smartdie ("can not open $file_name: $!");
   open FIRST, ">" . $dh->get_tmp_dir . "/hostfile.1"
      or $execution->smartdie ("can not open " . $dh->get_vnx_dir . "/hostfile.1 for writting: $!");
   open SECOND, ">" . $dh->get_tmp_dir . "/hostfile.2"
      or $execution->smartdie ("can not open " . $dh->get_vnx_dir . "/hostfile.2 for writting: $!");
   open THIRD, ">" . $dh->get_tmp_dir . "/hostfile.3"
      or $execution->smartdie ("can not open " . $dh->get_vnx_dir . "/hostfile.3 for writting: $!");

    # Status list:
    # 
    # 0 -> before VNUML section
    # 1 -> inside VNUML section, before scenario subsection
    # 2 -> inside simultaion subsection
    # 3 -> after scenario subsection, inside VNUML section
    # 4 -> after VNUML section
    my $status = 0;

    while (<HOST_FILE>) {
        # DEBUG
        #print "$_";
        #print "--status: $status\n";
        if ($status == 0) {
            print FIRST $_;
            $status = 1 if (/^\# VNX BEGIN/);
        }
        elsif ($status == 1) {
            if (/^\# BEGIN: $sim_name$/) {
                $status = 2;
            }
            elsif (/^\# VNX END/) {
                $status = 4;
                print THIRD $_;
            }
            else {
                print FIRST $_;
            }
        }
        elsif ($status == 2) {
            if (/^\# END: $sim_name$/) {
                $status = 3;
            }
        }
        elsif ($status == 3) {
            print THIRD $_;
            $status = 4 if (/^\# VNX END/);
        }
        elsif ($status == 4) {
            print THIRD $_;
        }
    }
    close HOST_FILE;

   # Check the final status when the hosts file has ended
   if ($status == 0) {
      # No VNUML section found
      print FIRST "\# VNX BEGIN -- DO NOT EDIT!!!\n";
      print FIRST "\n";
      print THIRD "\n";
      print THIRD "\# VNX END\n";
   }
   elsif ($status == 1) {
     # Found VNUML BEGIN but not found VNUML END. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 2) {
     # Found simultaion subsection BEGIN, but not found the end. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 3) {
     # Found VNUML BEGIN but not found VNUML END. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 4) {
     # Doing nothing
   }
   
   # Second fragment
   my $command = $bd->get_binaries_path_ref->{"date"};
   chomp (my $now = `$command`);
   print SECOND "\# BEGIN: $sim_name\n";
   print SECOND "\# topology destroyed: $now\n";
   print SECOND "\# END: $sim_name\n";
   
   # Append of fragments
   close FIRST;
   close SECOND;
   close THIRD;
   
   # Replace the old file
   my $dir_name = dirname $file_name;
   my $basename = basename $file_name;
   my $file_bk = "$dir_name/$basename.vnx.old";
   $execution->execute($logp, $bd->get_binaries_path_ref->{"mv"} . " $file_name $file_bk");
   $execution->execute($logp, $bd->get_binaries_path_ref->{"cat"} . " " . $dh->get_tmp_dir . "/hostfile.1 " . $dh->get_tmp_dir . "/hostfile.2 " . $dh->get_tmp_dir . "/hostfile.3 > $file_name");
   $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/hostfile.1 " . $dh->get_tmp_dir . "/hostfile.2 " . $dh->get_tmp_dir . "/hostfile.3");

back_to_user();
}


# VM_alive
#
# Returns 1 if there is a running UML in the process space
# of the operating system, 0 in the other case.
# Is based in a greped ps (doing the same with a pidof is not
# possible since version 1.2.0)
#
# This functions is similar to UMLs_ready function
sub VM_alive {

   my $only_vm = shift;
   my @pids = &get_kernel_pids($only_vm);
   if ($#pids < 0) {
	   return 0;
   }
   my $pids_string = join(" ",@pids);
   
   my $pipe = $bd->get_binaries_path_ref->{"ps"} . " --no-headers -p $pids_string | grep -v '<defunct>' 2> /dev/null|";   ## Avoiding strange warnings in the ps list
   open my $ps_list, "$pipe";
   if (<$ps_list>) {
	  close $ps_list;
      return $pids_string;
   }
   close $ps_list;
   return 0;


}

# socket_probe
#
# Attempt a "socket probe" against host and port given as arguments.
#
# Result:
#    1, if the probe results successful
#    0, otherwise
#
# Arguments:
#    host
#    port
#
sub socket_probe {

    my $host = shift;
    my $port = shift;
    
    my $success = 0;
    my $socket;
    if ($socket = IO::Socket::INET->new(Proto => "tcp", PeerAddr => "$host", PeerPort => "$port")) {
       $success = 1;
       close $socket;
    }

    return $success;
   
}

# UMLs_cmd_ready
#
# Check the availability of UMLs for commands (through ssh), based on the IP
# hash passed as argument, get_UML_command_ip.
#
# Argument:
#    the IP hash generated by get_UML_command_ip
#
# Result:
#    1 if all the UMLs are ready
#    0 otherwise
 
sub UMLs_cmd_ready {
   
    my %vm_ips = @_;
    
    # In debug mode, this check makes no sense, so always is true
    return 1 if ($execution->get_exe_mode() == $EXE_DEBUG);

    # The presence of a "0" means that one vm cannot be reached
    foreach my $key (keys %vm_ips) {
       return 0 if ($vm_ips{$key} eq "0");
    }
    return 1;
   
}

# get_UML_command_ip 
#
# Return a hash with the names of the IP needed to contact with the
# virtual machines (keys are names of the virtual machines). If a
# machine hasn't be contacted, there is a "0" for this machine and
# a premature exit happens.
#
# "ssh probes" are used against the management interface 
# (if <mng_if>no</mng_if> is not present) or againts the different
# <ipv4> addresses in the <if> of the virtual machines
#
# Argument:
# - a command sequence. Only vms using <exec mode="net"> for that sequence
#   are considered (this use to be the case when invoked from mode_execute). If a 
#   empty command sequence is passed, then all vms are considered, no matter 
#   if they have <exec> tags (this use to be the case when invoked from mode_t).

sub get_UML_command_ip {

   my $seq = shift;
   
   my $logp = "get_UML_command_ip> ";
   
   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use(@plugins);

   # Virtual machine IP hash
   my %vm_ips;
   
   # UMLs counter (used to generate IPv4 management addresses)
   my $counter = 0;

   # To process list
   for ( my $i = 0; $i < @vm_ordered; $i++) {
      my $vm = $vm_ordered[$i];

      # To get name attribute
      my $vm_name = $vm->getAttribute("name");
	 
	  # If seq not empty then check vm only uses exec_mode="net"
	  unless ($seq eq "") {

		my $exec_mode = $dh->get_vm_exec_mode($vm);
		#unless (defined &get_vm_exec_mode($vm) && &get_vm_exec_mode($vm) eq "net") {
		unless (defined $exec_mode && $exec_mode eq "net") {
	        $counter++;
	        next;
	     }
	  }
	 
      # To look for UMLs IP in -M list
      if ($vm_hash{$vm_name}) {

         if ($execution->get_exe_mode() == $EXE_DEBUG) {
            $vm_ips{$vm_name} = "(undefined in debug time)";
	       $counter++;
               next;
            }
	    
            # By default, until assinged, there is no IP address for this machine
            $vm_ips{$vm_name} = "0"; 
	 
            # To check whether management interface exists
            #if ($dh->get_vmmgmt_type eq 'none' || &mng_if_value($dh,$vm) eq "no") {
            if ($dh->get_vmmgmt_type eq 'none' || &mng_if_value($vm) eq "no") {
	 
               # There isn't management interface, check <if>s in the virtual machine
               my $ip_candidate = "0";
               
               # Note that disabling IPv4 didn't assign addresses in scenario
               # interfaces, so the search can be avoided
               if ($dh->is_ipv4_enabled) {
                  foreach my $if ($vm->getElementsByTagName("if")) {
                     my $id = $if->getAttribute("id");
                     foreach my $ipv4 ($if->getElementsByTagName("ipv4")) {
                        my $ip = &text_tag($ipv4);
                        my $ip_effective;
                        # IP could end in /mask, so we are prepared to remove the suffix
                        # in that case
                        if (&valid_ipv4_with_mask($ip)) {
                           $ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+).*$/;
                           $ip_effective = "$1.$2.$3.$4";
                        }
                        else {
                           $ip_effective = $ip;
                        }
                        if (&socket_probe($ip_effective,"22")) {
                           $ip_candidate = $ip_effective;
                           wlog (V, "$vm_name sshd is ready (socket style): $ip_effective (if id=$id)", $logp);
                           last;
                        }
                     }
		             # If some IP was found, we don't need to search for more
		             last if ($ip_candidate ne "0");
                  }
               }
	           if ($ip_candidate eq "0") {
                  wlog (V, "$vm_name sshd is not ready (socket style)");
	           }
               $vm_ips{$vm_name} = $ip_candidate;
            }
            else {
               # There is a management interface
               #print "*** get_admin_address($counter, $dh->get_vmmgmt_type, 2)\n";
               my %net = &get_admin_address('file', $vm_name, $dh->get_vmmgmt_type);
               if (!&socket_probe($net{'vm'}->addr(),"22")) {
                  wlog (V, "$vm_name sshd is not ready (socket style)", $logp);
                  return %vm_ips;	# Premature exit
               }
               else {
                  wlog (V, "$vm_name sshd is ready (socket style): ".$net{'host'}->addr()." (mng_if)", $logp);
                  $vm_ips{$vm_name} = $net{'vm'}->addr();
               }
            }
         }
         $counter++;
      }
      # All UMLs ready
      return %vm_ips;

}

# automac
#
# Returns and automatic generated MAC address, using
# two arguments. If <automac> is not in use, returns
# an empty string.
#
# The two argument have to be always diferent in each
# call to the functions, to guarantee uniqueness of
# the MAC in the scenario.
#
# Note that the use of this function limits a maximum
# of 255 UMLs with 255 interfaces each one (a more than
# reasonable limit, I think :)
#
# $automac_offset is used to complete MAC address
sub automac {

      my $ante_lower = shift;
      my $lower = shift;

      my $doc = $dh->get_doc;

      my @automac_list = $doc->getElementsByTagName("automac");
      # If tag is not in use, return empty string
      if (@automac_list == 0) {
         return "";
      }

           # Assuming offset is in the 0-65535 range
      #my $upper_offset = dec2hex(int($dh->get_automac_offset / 256));
      #my $lower_offset = dec2hex($dh->get_automac_offset % 256);
      
      # JSF 16/11
      my $upper_offset = sprintf("%x",int($dh->get_automac_offset / 256));
      my $lower_offset = sprintf("%x",$dh->get_automac_offset % 256);
      
      # JSF 23/3 ubuntu no levantaba la interfaz de gestión porque
      # no todos los campos tenían dos cifras, con esto se pasa de
      # 02:fd:0:0:1:0 a 02:fd:00:00:01:00 
      #$upper_offset = sprintf("%02d", $upper_offset);
      #$lower_offset = sprintf("%02d", $lower_offset);
      #$ante_lower = sprintf("%02d", $ante_lower);
      #$lower = sprintf("%02d", $lower);

      # DFC 26/11/2010: En Ubuntu 10.04 y con las versiones 0.8.3, 0.8.4 y 0.8.5 hay un problema 
      # de conectividad entre máquinas virtuales. Cuando se arrancan los ejemplos simple_*
      # las vm tienen conectividad con el host pero no entre ellas.
      # Parece que tienen que ver con la elección de las direcciones MAC en los interfaces
      # tun/tap (ver https://bugs.launchpad.net/ubuntu/+source/libvirt/+bug/579892)
      # Una solución temporal es cambiar las direcciones a un número más bajo: fe:fd -> 02:fd
      # return ",fe:fd:$upper_offset:$lower_offset:$ante_lower:$lower";
      #my $mac = "fe:fd:$upper_offset:$lower_offset:$ante_lower:$lower";
      my $mac = "02:fd:$upper_offset:$lower_offset:$ante_lower:$lower";
      # expandir mac con ceros a:b:c:d:e:f -> 0a:0b:0c:0d:0e:0f
      $mac =~ s/(^|:)(?=[0-9a-fA-F](?::|$))/${1}0/g;
      $mac = "," . $mac;
      #print "*** MAC=$mac\n";
      return $mac 

}


# JSF 16/11: no necesaria
# From: http://www.dreamincode.net/code/snippet60.htm
#
sub dec2hex {

   my $decnum = $_[0];
  
   my $hexnum;
   my $tempval;
   
   # Special case not covered by the copy-pasted algorithm
   return "0" if ($decnum == 0);
   
   while ($decnum != 0) {
      # get the remainder (modulus function) by dividing by 16
      $tempval = $decnum % 16;
      
      # convert to the appropriate letter if the value is greater than 9
      if ($tempval > 9) {
         $tempval = chr($tempval + 87);
      }
      # 'concatenate' the number to what we have so far in what will
      # be the final variable
      $hexnum = $tempval . $hexnum;
      
      # new actually divide by 16, and keep the integer value of the answer
      $decnum = int($decnum / 16);
       
      # if we cant divide by 16, this is the last step
      if ($decnum < 16) {
         # convert to letters again..
         if ($decnum > 9) {
         $decnum = chr($decnum + 87);
      }
    
      # add this onto the final answer.. 
      # reset decnum variable to zero so loop
      # will exit
      $hexnum = $decnum . $hexnum; 
      $decnum = 0
      }
   }
   return $hexnum;
}
      


# physicalif_config
#
# Tries to configure the physical interface whose name is given
# as first argument. To do so, it uses information stored in
# <physicalif> attributes. This functions is used only with -d mode
sub physicalif_config {

   my $interface = shift;

   my $doc = $dh->get_doc;

    # To get list of defined <physicalif>
    #my $phyif_list = $doc->getElementsByTagName("physicalif");

    # To process list
    #for ( my $i = 0; $i < $phyif_list->getLength; $i++ ) {
    foreach my $phyif ($doc->getElementsByTagName("physicalif")) {
        #my $phyif = $phyif_list->item($i);

        my $name = $phyif->getAttribute("name");
        if ($name eq $interface) {
            my $type = $phyif->getAttribute("type");
            if ($type eq "ipv6") {
                #IPv6 configuration
                my $ip = $phyif->getAttribute("ip");
                my $gw = $phyif->getAttribute("gw");
                #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $interface add $ip");
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " addr add $ip dev $interface");
                unless (empty($gw)) {
                    #$execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " -A inet6 add 2000::/3 gw $gw");            
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " -6 route add default via $gw");            
            }
        }
        else {
            #IPv4 configuration
      	 	my $ip = $phyif->getAttribute("ip");
	        my $gw = $phyif->getAttribute("gw");
   	        my $mask = $phyif->getAttribute("mask");
            $mask="255.255.255.0" if (empty($mask));
            my $ip_addr = NetAddr::IP->new($ip,$mask);
            #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $interface $ip netmask $mask");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " addr add " . $ip_addr->cidr() . " dev $interface");
       	 	unless (empty($gw)) {
                #$execution->execute($logp, $bd->get_binaries_path_ref->{"route"} . " add default gw $gw");
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " -4 route add default via $gw");
       	 	}
      	 }
      }
   }
}

# exists_scenario
#
# Returns true if the scenario (first argument) is currently running
#
# In the current version, this check is performed looking for the lock file
# in the directory that stores scenario files
sub scenario_exists {

   my $scenario = shift;
   if ( -f $dh->get_sim_dir . "/lock") {
   	return 1;
   }
   else {
   	return 0;
   }

}


# get_net_by_mode
#
# Returns a network whose name is the first argument and whose mode is second
# argument (may be "*" if the type doesn't matter). If there is no net with
# the given constrictions, 0 value is returned
#
# Note the default mode is "virtual_bridge"
#
sub get_net_by_mode {
   
   my $name_target = shift;
   my $mode_target = shift;
   
   my $doc = $dh->get_doc;
   
    # To get list of defined <net>
   	foreach my $net ($doc->getElementsByTagName("net")) {
        my $name = $net->getAttribute("name");
        my $mode = $net->getAttribute("mode");

        if (($name_target eq $name) && (($mode_target eq "*") || ($mode_target eq $mode))) {
            return $net;
        }
        # Special case (implicit virtual_bridge)
        if (($name_target eq $name) && ($mode_target eq "virtual_bridge") && ($mode eq "")) {
            return $net;
        }
    }
   
    return 0;	
}


# check_vlan
#
# This function uses two arguments. First is the name of a physical
# interface. Second is a VLAN identifier.
#
# Function returns 1 if interface has the VLAN configured, 0 in other case.
#
# The `*` can be used as wildcard. Ej: check_vlan("*","5") returns 1
# if VLAN 5 is configured in at least one interface. check_vlan("eth1","*")
# returns 1 if eth1 interface has any VLAN configured.
#
# check_vlan("*","*") always returns 1. This is a dummy use of the function.
#
# It based in `cat /proc/net/vlan/config` parsing.
sub check_vlan {

   my $if_name= shift;
   my $vlan_number = shift;

change_to_root();
   # To get `cat /proc/net/vlan/config`
   my @catconfig;
   my $line = 0;
   my $pipe = $bd->get_binaries_path_ref->{"cat"} . " /proc/net/vlan/config | grep -v Name-Type |";
   open CATCONFIG, "$pipe";
   while (<CATCONFIG>) {
      chomp;
      $catconfig[$line++] = $_;
   }
   close CATCONFIG;

   # To get pair interfaz-vlan
   # Note that we skip the first line, due to this is the header of the config file
   for ( my $i = 1; $i < $line; $i++) {
      $_ = $catconfig[$i];

      # We are interested in the last two fields of the list
      /.*\s(\S+)\s.*\s(\S+)$/;

      #print "DEBUG $if_name, $vlan_number: <$1> <$2>\n";

      # The "atoms" of the checking, set to their initial values
      my $if_ok = ($if_name eq "*") ? 1 : 0;
      my $vlan_ok = ($vlan_number eq "*") ? 1 : 0;

      # To check the line
      $vlan_ok = 1 if ($vlan_number eq $1);
      $if_ok = 1 if ($if_name eq $2);

      if ($vlan_ok && $if_ok) {
         return 1;
      }

   }

back_to_user();

   # VLAN not found in interface:
   return 0;

}

# inc_cter
#
# Increases "file counter" (used to store the usage of physical if, uml_switch
# sockets, etc.), whose name is given as first argument. 
#
# This counter is stored in a file with the name of the interface
# (for example, "eth0" or "eth1.22"), sufixed by ".cter" in the working 
# directory of vnumlparser.pl (by default, ~/.vnuml). The content of this 
# file is a list of all scenarios are currently using this interface as a brigde.
#
sub inc_cter {

   my $file = shift;
   $file .= ".cter";

   unless (-f $dh->get_networks_dir . "/$file") {
      $execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " " . $dh->get_scename . "> " . $dh->get_networks_dir . "/$file");
   }
   else {
      my $command = $bd->get_binaries_path_ref->{"cat"} . " " . $dh->get_networks_dir . "/$file";
      my $value = `$command`;
      chomp ($value);
      $execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " \"$value " . $dh->get_scename . "\"". "> " . $dh->get_networks_dir . "/$file");
   }

}

# dec_cter
#
# Dual function of inc_cter
sub dec_cter {

   my $file = shift;
   $file .= ".cter";

   if (-f $dh->get_networks_dir . "/$file") {

      my $command = $bd->get_binaries_path_ref->{"cat"} . " " . $dh->get_networks_dir . "/$file";
      my $value = `$command`; 
      chomp ($value);
      my $scename = $dh->get_scename;

     if ($value =~ /^$scename /) {
        # $scename is at the beginning of line
        $value =~ s/^$scename //;
      } elsif ($value =~ / $scename$/) {
        # at the end
        $value =~ s/ $scename$//;
      } elsif ($value =~ / $scename /) {
        # in the middle
        $value =~ s/$scename //;
      } elsif ($value =~ /^$scename$/) {
        # it is the only one
        $value =~ s/^$scename$//;
      } else {
        # not found
      }

      if ($value eq "") {
         $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_networks_dir . "/$file");
      }
      else {
         $execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " $value > " . $dh->get_networks_dir . "/$file");
      }

   }

}

# get_cter
#
# Returns counter value.
sub get_cter {

   my $file = shift;
   $file .= ".cter";

   unless (-f $dh->get_networks_dir . "/$file") {
      return 0;
   }
   else {
      # FIXME: this should be improved to return the number of scenarios using
      # the interface. However, currently get_cter is only checked againts 0, so
      # it works
      #my $command = $bd->get_binaries_path_ref->{"cat"} . " " . $dh->get_networks_dir . "/$file";
      #my $value = `$command`;
      #return $value;
      return 1;
   }

}

# change_vm_status
#
# Argument:
# - the DataHandler
# - the virtual machine name 
# - the target status ("booting", "running", "executing", "dying", etc.)
#
# Changes current status file to the target one specified as argument. The
# special target REMOVE (uppercase) deletes the file
#
sub change_vm_status {

#   my $dh = shift;
   my $vm = shift;
   my $status = shift;

   my $status_file = $dh->get_vm_dir($vm) . "/status";

   if ($status eq "REMOVE") {
      $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -f $status_file");
   }
   else {
      $execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " $status > $status_file"); 
   }
}

# get_user_in_seq
#
# Arguments:
# - a virtual machine node
# - a sequence
#
# Returns the corresponding user for the given execution sequence in the
# given virtual machine. In no user is found (note that user attribute in
# <exec>/<filetree>) is optional), "root" is returned as default.
#
sub get_user_in_seq {

    my $vm = shift;
    my $seq = shift;

    my $username = "";

    # Lookinf for in <exec>   
    #my $exec_list = $vm->getElementsByTagName("exec");
    #for (my $i = 0 ; $i < $exec_list->getLength; $i++) {
    foreach my $exec ($vm->getElementsByTagName("exec")) {
        if ($exec->getAttribute("seq") eq $seq) {
            if ($exec->getAttribute("user") ne "") {
                $username = $exec->getAttribute("user");
                last;
            }
        }
    }

    # If not found in <exec>, try with <filetree>   
    if ($username eq "") {
        #my $filetree_list = $vm->getElementsByTagName("filetree");
        #for (my $i = 0 ; $i < $filetree_list->getLength; $i++) {
        foreach my $filetree ($vm->getElementsByTagName("filetree")) {
            if ($filetree->getAttribute("seq") eq $seq) {
                if ($filetree->getAttribute("user") ne "") {
                    $username = $filetree->getAttribute("user");
                    last;
                }
            }
        }
    }

    # If no mode was found in <exec> or <filetree>, use default   
    if ($username eq "") {
        $username = "root";
    }
   
    return $username;
      
}


# mgmt_sock_create
#
# List is a helper funtion to create. Note that only root can do so
# The code is the same that the user is supposed to use when no
# autoconfigure="on" is used in <mgmt_net> and described in
# http://jungla.dit.upm.es/~vnuml/doc/current/tutorial/index.html#executing_commands
#
# Arguments:
# - socket file
# - interface (tap device)
# - IP address to assign to interface
# - mask
#
sub mgmt_sock_create {
   my $socket = shift;
   my $tap = shift;
   my $hostip = shift;
   my $mask = shift;  
   
   my $user = "vnx";
   $user = $opts{u} if ($opts{u});

   # Slashed or dotted mask?
   my $effective_mask;
   if (&valid_dotted_mask($mask)) {
      $effective_mask = $mask;
   }
   else {
      $effective_mask = &slashed_to_dotted_mask($mask);
   }

   $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -u $user -t $tap");

   #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $tap $hostip netmask $effective_mask up");
   my $ip_addr = NetAddr::IP->new($hostip,$effective_mask);
   $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set dev $tap up");
   $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " addr add " . $ip_addr->cidr() . " dev $tap");
   #$execution->execute_bg($bd->get_binaries_path_ref->{"su"} . " -pc '".$bd->get_binaries_path_ref->{"uml_switch"}." -tap $tap -unix $socket < /dev/null > /dev/null &' $user");
   $execution->execute_bg_root($bd->get_binaries_path_ref->{"uml_switch"}." -tap $tap -unix $socket",'/dev/null');
   sleep 1;
   $execution->execute_root($logp, $bd->get_binaries_path_ref->{"chmod"} . " g+rw $socket");
}

# mgmt_sock_destroy
#
# Dual fuction of mgmt_sock_create
#
# Arguments:
# - socket file
# - interface (tap device)
#
sub mgmt_sock_destroy {
   my $socket = shift;
   my $tap = shift;
   
   $execution->execute_root($logp, $bd->get_binaries_path_ref->{"kill"} . " `".$bd->get_binaries_path_ref->{"lsof"}." -t $socket`");
   $execution->execute_root($logp, $bd->get_binaries_path_ref->{"rm"} . " $socket");
   #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $tap down");
   $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set dev $tap down");
   $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -d $tap");
}


# validation_fail
#
# This function is a handler that triggers XML validator parser
# when errors are detected.
#sub validation_fail {
#   my $code = shift;
#   # To set flag
#   $valid_fail = 1;
#   # To print error message
#   XML::Checker::print_error ($code, @_);
#}

# vnx_die
#
# Wrapper of die Perl function. It is based on the old smartdie, now moved to the
# VNX::Execution class in Execution.pm. Note that, this funcion does not release
# the LOCK file (as smartdie does): it is intented to be used in the early stages
# of vnumlparser.pl execution, when the VNX::Execution object has not been construsted.
#
sub vnx_die {
   my $mess = shift;
   printf "--------------------------------------------------------------------------------\n";
   printf "ERROR in %s (%s):\n%s \n", (caller(1))[3], (caller(0))[2], $mess;
   printf "--------------------------------------------------------------------------------\n";
   exit 1;   
}

# execute a smart die
sub handle_sig {
	# Reset alarm, if one has been set
	alarm 0;
	if ($opts{'create'}) {
		mode_shutdown('do_not_exe_cmds');  #
	}
	if (defined($execution)) {
		$execution->smartdie("Signal received. Exiting");
	}
	else {
		vnx_die("Signal received. Exiting.");
	}
}

#
# create_dirs
#
sub create_dirs {

    my $doc = $dh->get_doc;
    my @vm_ordered = $dh->get_vm_ordered; 
    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];

        # We get name attribute
        my $vm_name = $vm->getAttribute("name");

        # create fs, hostsfs and run directories, if they don't already exist
        if ($execution->get_exe_mode() != $EXE_DEBUG) {
            if (! -d $dh->get_vm_dir ) {
                mkdir $dh->get_vm_dir or $execution->smartdie ("error making directory " . $dh->get_vm_dir . ": $!");
            }
            mkdir $dh->get_vm_dir($vm_name);
            mkdir $dh->get_vm_fs_dir($vm_name);
            mkdir $dh->get_vm_hostfs_dir($vm_name);
            mkdir $dh->get_vm_run_dir($vm_name);
            mkdir $dh->get_vm_mnt_dir($vm_name);
            mkdir $dh->get_vm_tmp_dir($vm_name);
            
            if ($vmfs_on_tmp eq 'yes') {
            	$execution->execute($logp,  "mkdir -p " . $dh->get_vm_fs_dir_ontmp($vm_name) );
            }
        }
    }
}



####################

sub build_topology{
   my $basename = basename $0;
   
   my $logp = "build_topology> ";
    
    try {
            # To load tun module if needed
            #if (&tundevice_needed($dh,$dh->get_vmmgmt_type,$dh->get_vm_ordered)) {
            if (&tundevice_needed($dh->get_vmmgmt_type,$dh->get_vm_ordered)) {
                if (! -e "/dev/net/tun") {
                    !$execution->execute_root( $logp, $bd->get_binaries_path_ref->{"modprobe"} . " tun") or $execution->smartdie ("module tun can not be initialized: $!");
                }
            }

            # To make directory to store files related with the topology
            if (! -d $dh->get_sim_dir && $execution->get_exe_mode != $EXE_DEBUG) {
                mkdir $dh->get_sim_dir or $execution->smartdie ("error making directory " . $dh->get_sim_dir . ": $!");
            }
            # To copy the scenario file
            my $command = $bd->get_binaries_path_ref->{"date"};
            chomp (my $now = `$command`);
            my $input_file_basename = basename $dh->get_input_file;
            $execution->execute($logp, $bd->get_binaries_path_ref->{"cp"} . " " . $dh->get_input_file . " " . $dh->get_sim_dir);
            $execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " '<'!-- copied by $basename at $now --'>' >> ".$dh->get_sim_dir."/$input_file_basename");       
            $execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " '<'!-- original path: ".abs_path($dh->get_input_file)." --'>' >> ".$dh->get_sim_dir."/$input_file_basename");

            # To make lock file (it exists while topology is running)
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"touch"} . " " . $dh->get_sim_dir . "/lock");

            # Create the mgmn_net socket when <vmmgnt type="net">, if needed
            if (($dh->get_vmmgmt_type eq "net") && ($dh->get_vmmgmt_autoconfigure ne "")) {
                if ($> == 0) {
                    my $sock = $dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("sock");
                    if (empty($sock)) { $sock = ''}
                    else              { do_path_expansion($sock) };
                    if (-S $sock) {
                        wlog (V, "VNX warning: <mgmt_net> socket already exists. Ignoring socket autoconfiguration", $logp);
                    }
                    else {
                        # Create the socket
                        mgmt_sock_create($sock,$dh->get_vmmgmt_autoconfigure,$dh->get_vmmgmt_hostip,$dh->get_vmmgmt_mask);
                    }
                }
                else {
                    wlog (V, "VNX warning: <mgmt_net> autoconfigure attribute only is used when VNX parser is invoked by root. Ignoring socket autoconfiguration", $logp);
                }
            }

            # 1. To perform configuration for bridged virtual networks (<net mode="virtual_bridge">) and TUN/TAP for management
            configure_virtual_bridged_networks();

            # 2. Host configuration
            host_config();

            # 3. Set appropriate permissions and perform configuration for switched virtual networks and uml_switches creation (<net mode="uml_switch">)
            # DFC 21/2/2011 &chown_working_dir;
            configure_switched_networks();
	   
            # 4. To link TUN/TAP to the bridges (for bridged virtual networks only, <net mode="virtual_bridge">)
            tun_connect();

            # 5. To create fs, hostsfs and run directories
            create_dirs();
       
   }
	
}


# make_vmAPI_doc
#
# Creates the vm XML specification (<create_conf> element) passed to   
# to vmAPI-->defineVM and copied to ${vm_name}_cconf.xml file 
#
# Arguments:
# - $vm_name, the virtual machine name
# - $vm_order, the order number of the vm (used to generate mac addresses)
# - $mngt_ip_data, passed to get_admin_address
#
# Returns:
# - the XML document in text format
#
sub make_vmAPI_doc {
	
   	my $vm           = shift;
   	my $vm_order     = shift;
   	my $mngt_ip_data = shift;

   	my $dom;
   
   	$dom = XML::LibXML->createDocument( "1.0", "UTF-8" );
   
   	my $create_conf_tag = $dom->createElement('create_conf');
   	$dom->addChild($create_conf_tag);
   
   	# We get name attribute
   	my $vm_name = $vm->getAttribute("name");

   	# Insert random id number
   	my $fileid_tag = $dom->createElement('id');
   	$create_conf_tag->addChild($fileid_tag);
   	my $fileid = $vm_name . "-" . generate_random_string(6);
   	$fileid_tag->addChild( $dom->createTextNode($fileid) );
      
   	my $vm_tag = $dom->createElement('vm');
   	$create_conf_tag->addChild($vm_tag);
   
   	$vm_tag->addChild( $dom->createAttribute( name => $vm_name));
 
   	# To get filesystem and type
   	my $filesystem;
   	my $filesystem_type;
   	my @filesystem_list = $vm->getElementsByTagName("filesystem");

   	# filesystem tag in dom tree        
   	my $fs_tag = $dom->createElement('filesystem');
   	$vm_tag->addChild($fs_tag);

   	if (@filesystem_list == 1) {
      	# $filesystem = &do_path_expansion(&text_tag($vm->getElementsByTagName("filesystem")->item(0)));
      	$filesystem = &get_abs_path(&text_tag($vm->getElementsByTagName("filesystem")->item(0)));
      	$filesystem_type = $vm->getElementsByTagName("filesystem")->item(0)->getAttribute("type");

      	# to dom tree
      	$fs_tag->addChild( $dom->createAttribute( type => $filesystem_type));
      	$fs_tag->addChild($dom->createTextNode($filesystem));       
   	}
   	else {
      	$filesystem = $dh->get_default_filesystem;
      	$filesystem_type = $dh->get_default_filesystem_type;

      	#to dom tree
      	$fs_tag->addChild( $dom->createAttribute( type => $filesystem_type));
      	$fs_tag->addChild($dom->createTextNode($filesystem));
   	}

   	# Memory assignment
   	my $mem = $dh->get_default_mem;      
   	my @mem_list = $vm->getElementsByTagName("mem");
   	if (@mem_list == 1) {
      	$mem = &text_tag($mem_list[0]);
   	}
   
	# Convert <mem> tag value to Kilobytes (only "M" and "G" letters are allowed) 
	if ((($mem =~ /M$/))) {
	 	$mem =~ s/M//;
		$mem = $mem * 1024;
	} elsif ((($mem =~ /G$/))) {
	    $mem =~ s/G//;
		$mem = $mem * 1024 * 1024;
	}
   
   	# mem tag in dom tree
	my $mem_tag = $dom->createElement('mem');
   	$vm_tag->addChild($mem_tag);
   	$mem_tag->addChild($dom->createTextNode($mem));
   
   	# kernel to be booted
   	my $kernel;
   	my @params;
   	my @build_params;
   	my  @kernel_list = $vm->getElementsByTagName("kernel");
      
   	# kernel tag in dom tree
   	my $kernel_tag = $dom->createElement('kernel');
   	$vm_tag->addChild($kernel_tag);
   	if (@kernel_list == 1) {
      	my $kernel_item = $kernel_list[0];
      	$kernel = &do_path_expansion(&text_tag($kernel_item));         
      	# to dom tree
      	$kernel_tag->addChild($dom->createTextNode($kernel));
        # Set kernel attributes      	
        #if ( $kernel_item->getAttribute("initrd") !~ /^$/ ) {
        unless ( empty($kernel_item->getAttribute("initrd")) ) {
            $kernel_tag->addChild($dom->createAttribute( initrd => $kernel_item->getAttribute("initrd")));
        }
        #if ( $kernel_item->getAttribute("devfs") !~ /^$/ ) {
        unless ( empty($kernel_item->getAttribute("devfs")) ) {
            $kernel_tag->addChild($dom->createAttribute( devfs => $kernel_item->getAttribute("devfs")));
        }
        #if ( $kernel_item->getAttribute("root") !~ /^$/ ) {
        unless ( empty($kernel_item->getAttribute("root"))) {
            $kernel_tag->addChild($dom->createAttribute( root => $kernel_item->getAttribute("root")));
        }
        #if ( $kernel_item->getAttribute("modules") !~ /^$/ ) {
        unless ( empty($kernel_item->getAttribute("modules")) ) {
            $kernel_tag->addChild($dom->createAttribute( modules => $kernel_item->getAttribute("modules")));
        }
        if ( $kernel_item->getAttribute("trace") eq "on" ) {
            $kernel_tag->addChild($dom->createAttribute( trace => $kernel_item->getAttribute("trace")));
        }
   	}
   	else {    	
      	# include a 'default' in dom tree
      	$kernel_tag->addChild($dom->createTextNode('default'));
   	}
   	
   	# conf tag
   	my $conf;
   	my @conf_list = $vm->getElementsByTagName("conf");
   	if (@conf_list == 1) {
		# get config file from the <conf> tag
      	$conf = &get_abs_path ( &text_tag($conf_list[0]) );
   		#print "***  conf=$conf\n";
	   	# create <conf> tag in dom tree
		my $conf_tag = $dom->createElement('conf');
	   	$vm_tag->addChild($conf_tag);
	   	$conf_tag->addChild($dom->createTextNode($conf));
   	}
   
   	# Add console tags
   	# Get the array of consoles for that VM
   	my @console_list = $dh->merge_console($vm);

   	if (@console_list > 0) {
     	my $xterm_used = 0;
     	foreach my $console (@console_list) {
	  		my $console_id    = $console->getAttribute("id");
		 	my $console_value = &text_tag($console);
            my $console_tag = $dom->createElement('console');
            $vm_tag->addChild($console_tag);
            $console_tag->addChild($dom->createTextNode($console_value));
            $console_tag->addChild($dom->createAttribute( id => $console_id));
			# Optional attributes: display and port            
            my $console_display = $console->getAttribute("display");
            if ($console_display ne "") {
                $console_tag->addChild($dom->createAttribute( display => $console_display));
            }
            my $console_port = $console->getAttribute("port");
            unless (empty($console_port)) {
                $console_tag->addChild($dom->createAttribute( port => $console_port));
            }  
		}
	}

	# Management interface, if needed
    my $mng_if_value = &mng_if_value($vm);
    #$mng_if_tag->addChild( $dom->createAttribute( value => $mng_if_value));      
    # aquí es donde hay que meter las ips de gestion
    # si mng_if es distinto de no, metemos un if id 0
    unless ( ($dh->get_vmmgmt_type eq 'none' ) || ($mng_if_value eq "no") ) {

		# Some virtual machine types, e.g. Dynamips, need
		# to specify the name of the mgmt interface with a tag like this:
		#       <if id="0" net="vm_mgmt" name="e0/0">
   		my $mgmtIfName;
   		foreach my $if ($vm->getElementsByTagName("if")) {
      		my $id = $if->getAttribute("id");
      		#print "**** If id=$id\n";
      		
			if ($id == 0) { 
	      		$mgmtIfName = $if->getAttribute("name");
				#print "**** mgmtIfName=$mgmtIfName\n";
    	  		my $net = $if->getAttribute("net");
				if ($mgmtIfName eq ''){
					wlog (N, "WARNING: no name defined for management if (id=0) of vm $vm_name");
				} else { last }
			}
   		}

    	my $mng_if_tag = $dom->createElement('if');
    	$vm_tag->addChild($mng_if_tag);

      	my $mac = &automac($vm_order+1, 0);
        $mng_if_tag->addChild( $dom->createAttribute( mac => $mac));

		if (defined $mgmtIfName) {
        	$mng_if_tag->addChild( $dom->createAttribute( name => $mgmtIfName));
		}


      	my %mng_addr = &get_admin_address( $mngt_ip_data, $vm_name, $dh->get_vmmgmt_type);
      	$mng_if_tag->addChild( $dom->createAttribute( id => 0));

      	my $ipv4_tag = $dom->createElement('ipv4');
      	$mng_if_tag->addChild($ipv4_tag);
      	my $mng_mask = $mng_addr{'vm'}->mask();
      	$ipv4_tag->addChild( $dom->createAttribute( mask => $mng_mask));
      	my $mng_ip = $mng_addr{'vm'}->addr();
        $ipv4_tag->addChild($dom->createTextNode($mng_ip));
      
	}
   
   	# To process all interfaces
   	# To process list, we ignore interface zero since it
   	# gets setup as necessary management interface
   	foreach my $if ($vm->getElementsByTagName("if")) {
      
      	# To get attributes
      	my $id = $if->getAttribute("id");
      	my $net = $if->getAttribute("net");

		# Ignore if with id=0; it is the mgmt interface which is configured above 
		if ($id > 0) { 
	
	      	# To get MAC address
	      	my @mac_list = $if->getElementsByTagName("mac");
	      	my $mac;
	      	# If <mac> is not present, we ask for an automatic one (if
	      	# <automac> is not enable may be null; in this case UML 
	      	# autoconfiguration based in IP address of the interface 
	      	# is used -but it doesn't work with IPv6!)
	      	if (@mac_list == 1) {
	      	
	         	$mac = &text_tag($mac_list[0]);
	         	# expandir mac con ceros a:b:c:d:e:f -> 0a:0b:0c:0d:0e:0f
	         	$mac =~ s/(^|:)(?=[0-9a-fA-F](?::|$))/${1}0/g;
	         	$mac = "," . $mac;
	         
	         	#$mac = "," . &text_tag($mac_list->item(0));
	      	}
	      	else {	  #my @group = getgrnam("@TUN_GROUP@");
	         	$mac = &automac($vm_order+1, $id);
	      	}
	         
	      	# if tags in dom tree 
	      	my $if_tag = $dom->createElement('if');
	      	$vm_tag->addChild($if_tag);
	      	$if_tag->addChild( $dom->createAttribute( id => $id));
	      	$if_tag->addChild( $dom->createAttribute( net => $net));
	      	$if_tag->addChild( $dom->createAttribute( mac => $mac));
            
            if (get_net_by_mode($net,"virtual_bridge") != 0){
                $if_tag->addChild( $dom->createAttribute( netType => "virtual_bridge"));
            } elsif(get_net_by_mode($net,"openvswitch") != 0){
                $if_tag->addChild( $dom->createAttribute( netType => "openvswitch"));
            }

	      	try {
	      		my $name = $if->getAttribute("name");
	      		unless (empty($name)) { 
	      			$if_tag->addChild( $dom->createAttribute( name => $name)) 
	      		};
	      	} 
	      	catch Error with {
	      	
	      	} ;
	         
	      	# To process interface IPv4 addresses
	      	# The first address has to be assigned without "add" to avoid creating subinterfaces
	      	if ($dh->is_ipv4_enabled) {
	         	foreach my $ipv4 ($if->getElementsByTagName("ipv4")) {
	
	            	my $ip = &text_tag($ipv4);
	            	my $ipv4_effective_mask = "255.255.255.0"; # Default mask value	       
	            	if (&valid_ipv4_with_mask($ip)) {
	               		# Implicit slashed mask in the address
	               		$ip =~ /.(\d+)$/;
	               		$ipv4_effective_mask = &slashed_to_dotted_mask($1);
	               		# The IP need to be chomped of the mask suffix
	               		$ip =~ /^(\d+).(\d+).(\d+).(\d+).*$/;
	               		$ip = "$1.$2.$3.$4";
	            	}
	            	else { 
	               		# Check the value of the mask attribute
	               		my $ipv4_mask_attr = $ipv4->getAttribute("mask");
	               		if ($ipv4_mask_attr ne "") {
	                  		# Slashed or dotted?
	                  		if (&valid_dotted_mask($ipv4_mask_attr)) {
	                  	 		$ipv4_effective_mask = $ipv4_mask_attr;
	                  		}
	                  		else {
	                     		$ipv4_mask_attr =~ /.(\d+)$/;
	                     		$ipv4_effective_mask = &slashed_to_dotted_mask($1);
	                  		}
	               		} else {
	                  	 	wlog (N, "WARNING (vm=$vm_name): no mask defined for $ip address of interface $id. Using default mask ($ipv4_effective_mask)");
	               		}
	            	}
		       
	            	my $ipv4_tag = $dom->createElement('ipv4');
	            	$if_tag->addChild($ipv4_tag);
	            	# TODO: cambiar para que el formato sea siempre x.x.x.x/y
	            	# Hay que hacer cambios en los demonios de autoconfig
	            	# Lineas originales:
	            	$ipv4_tag->addChild( $dom->createAttribute( mask => $ipv4_effective_mask));
	            	$ipv4_tag->addChild($dom->createTextNode($ip));
	            	# Nuevas lineas para usar /24:
	            	#$ip = NetAddr::IP->new ($ip, $ipv4_effective_mask)->cidr();
	            	#$ipv4_tag->addChild($dom->createTextNode($ip));
	               
	            }
			}
		     
		# To process interface IPv6 addresses
	  	     if ($dh->is_ipv6_enabled) {
		        foreach my $ipv6 ($if->getElementsByTagName("ipv6")) {
		           my $ipv6_tag = $dom->createElement('ipv6');
	               $if_tag->addChild($ipv6_tag);
		           my $ip = &text_tag($ipv6);
		           if (&valid_ipv6_with_mask($ip)) {
		              # Implicit slashed mask in the address
		              $ipv6_tag->addChild($dom->createTextNode($ip));
		           }
		           else {
		              # Check the value of the mask attribute
	 	              my $ipv6_effective_mask = "/64"; # Default mask value	       
		              my $ipv6_mask_attr = $ipv6->getAttribute("mask");
		              if ($ipv6_mask_attr ne "") {
		                 # Note that, in the case of IPv6, mask are always slashed
	                     $ipv6_effective_mask = $ipv6_mask_attr;
		              }
		              
	                  $ipv6_tag->addChild($dom->createTextNode("$ip$ipv6_effective_mask"));
		            }	       
		     	}
	  	     }
   		}
	}
      
     
 	# ip routes 
  	my @route_list = $dh->merge_route($vm);
   	foreach my $route (@route_list) {
      	
		my $route_dest = &text_tag($route);
    	my $route_gw = $route->getAttribute("gw");
     	my $route_type = $route->getAttribute("type");       
    	my $route_tag = $dom->createElement('route');
    	$vm_tag->addChild($route_tag);
       
     	$route_tag->addChild( $dom->createAttribute( type => $route_type));
     	$route_tag->addChild( $dom->createAttribute( gw => $route_gw));
      	$route_tag->addChild($dom->createTextNode($route_dest));
	}
    
    # Forwarding
    my $f_type = $dh->get_default_forwarding_type;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    if (@forwarding_list == 1) {
   		$f_type = $forwarding_list[0]->getAttribute("type");
        $f_type = "ip" if (empty($f_type));
  	}
  	if ($f_type ne ""){
    	my $forwarding_tag = $dom->createElement('forwarding');
    	$vm_tag->addChild($forwarding_tag);
   		$forwarding_tag->addChild( $dom->createAttribute( type => $f_type));
 	}
      
	# my @group = getgrnam("@TUN_GROUP@");
    my @group = getgrnam("uml-net");

    # flag 'o' tag in dom tree 
    my $o_flag_tag = $dom->createElement('o_flag');
    $vm_tag->addChild($o_flag_tag);      
    my $o_flag = "";
    if ($opts{o}) {
     	$o_flag = $opts{o};
    }     
    $o_flag_tag->addChild($dom->createTextNode($o_flag));

    # flag 'e' tag in dom tree 
    my $e_flag_tag = $dom->createElement('e_flag');
    $vm_tag->addChild($e_flag_tag);
    my $e_flag = "";
    if ($opts{e}) {
    	$e_flag = $opts{e};
    }     
    $e_flag_tag->addChild($dom->createTextNode($e_flag));

    # flag 'Z' tag in dom tree
    my $Z_flag_tag = $dom->createElement('Z_flag');
    $vm_tag->addChild($Z_flag_tag);
    my $Z_flag;
    if ($opts{Z}) {
      	$Z_flag = 1;
    }else{
      	$Z_flag = 0;
    }      
    $Z_flag_tag->addChild($dom->createTextNode($Z_flag));

    # flag 'F' tag in dom tree
    my $F_flag_tag = $dom->createElement('F_flag');
    $vm_tag->addChild($F_flag_tag);
    my $F_flag;
    if ($opts{F}) {
      	$F_flag = 1;
    }else{
      	$F_flag = 0;
    }      
    $F_flag_tag->addChild($dom->createTextNode($F_flag));


    my @plugin_ftree_list = ();
    my @plugin_exec_list = ();
    my @ftree_list = ();
    my @exec_list = ();
    
    # Get all the <filetree> and <exec> commands to be executed for $seq='on_boot'
    my ($vm_plugin_ftrees, $vm_plugin_execs, $vm_ftrees, $vm_execs) = 
          get_vm_ftrees_and_execs($vm, $vm_name, 'define', 'on_boot',  
               \@plugin_ftree_list, \@plugin_exec_list, \@ftree_list, \@exec_list );

    wlog (VVV, "make_vmAPI_doc: XML created for vm $vm_name with seq 'on_boot' commands included", "$vm_name> ", $logp); 
    wlog (VVV, "                plugin_filetrees=$vm_plugin_ftrees, plugin_execs=$vm_plugin_execs, user-defined_filetrees=$vm_ftrees, user-defined_execs=$vm_execs", "$vm_name> ", $logp);


    # Copy all the <filetree> and <exec> to the create_conf XML document
    # 1 - Plugins <filetree> tags
    foreach my $filetree (@plugin_ftree_list) {
        $vm_tag->addChild($filetree);
        wlog (VVV, "make_vmAPI_doc: adding plugin filetree " . $filetree->toString(1) . " to create_conf", "$vm_name> ", $logp);
    }
    foreach my $exec (@plugin_exec_list) {
        $vm_tag->addChild($exec);
        wlog (VVV, "make_vmAPI_doc: adding plugin exec " . $exec->toString(1) . " to create_conf", "$vm_name> ", $logp);
    }
    foreach my $filetree (@ftree_list) {
        $vm_tag->addChild($filetree);
        wlog (VVV, "make_vmAPI_doc: adding user defined ftree " . $filetree->toString(1) . " to create_conf", "$vm_name> ", $logp);
    }
    foreach my $exec (@exec_list) {
        $vm_tag->addChild($exec);
        wlog (VVV, "make_vmAPI_doc: adding user defined exec " . $exec->toString(1) . " to create_conf", "$vm_name> ", $logp);
    }
  
    # <ssh_key> tag
    my @ssh_key_list = $dh->get_doc->getElementsByTagName("global")->item(0)->getElementsByTagName("ssh_key");
    unless (@ssh_key_list == 0) {
	    my $ftree_num = $vm_ftrees+1;
	    my $ssh_key_dir = $dh->get_vm_tmp_dir($vm_name) . "/on_boot/filetree/$ftree_num";
        $execution->execute($logp,  "mkdir -p $ssh_key_dir"); # or $execution->smartdie ("cannot create directory $ssh_key_dir for storing ssh keys");
	    # Copy ssh key files content to $ssh_key_dir/ssh_keys file
	    foreach my $ssh_key (@ssh_key_list) {
	        my $key_file = do_path_expansion( text_tag( $ssh_key ) );
	        wlog (V, "<ssh_key> file: $key_file");
	        $execution->execute( $logp, $bd->get_binaries_path_ref->{"cat"}
	                             . " $key_file >>" . $ssh_key_dir . "/ssh_keys" );
	    }
	    # Add a <filetree> to copy ssh keys
        my $ftree_tag = XML::LibXML::Element->new('filetree');
        $ftree_tag->setAttribute( seq => "on_boot");
        $ftree_tag->setAttribute( root => "/tmp" );
        $ftree_tag->appendTextNode ("ssh_keys");            
        $vm_tag->addChild($ftree_tag);
        # And a <exec> command to add it to authorized_keys file in VM
        my $exec_tag = XML::LibXML::Element->new('exec');
        $exec_tag->setAttribute( seq => "on_boot");
        $exec_tag->setAttribute( type => "verbatim" );
        $exec_tag->setAttribute( ostype => "system" );
        $exec_tag->appendTextNode ("cat /tmp/ssh_keys >> /root/.ssh/authorized_keys; rm /tmp/ssh_keys");            
        $vm_tag->addChild($exec_tag);
    }
  
=BEGIN 
# Original code of ssh key management
# TODO: process the ssh keys in <user> tag

        # Next install vm-specific keys and add users and groups
        my @user_list = $dh->merge_user($vm);
        foreach my $user (@user_list) {
            my $username      = $user->getAttribute("username");
            my $initial_group = $user->getAttribute("group");
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"touch"} 
                  . " $sdisk_content"
                  . "group_$username" );
            my $group_list = $user->getElementsByTagName("group");
            for ( my $k = 0 ; $k < $group_list->getLength ; $k++ ) {
                my $group = &text_tag( $group_list->item($k) );
                if ( $group eq $initial_group ) {
                    $group = "*$group";
                }
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"echo"}
                      . " $group >> $sdisk_content"
                      . "group_$username" );
            }
            my $key_list = $user->getElementsByTagName("ssh_key");
            for ( my $k = 0 ; $k < $key_list->getLength ; $k++ ) {
                my $keyfile =
                  &do_path_expansion( &text_tag( $key_list->item($k) ) );
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"cat"}
                      . " $keyfile >> $sdisk_content"
                      . "keyring_$username" );
            }
        }
=END
=cut
  
    # Save XML document to .vnx/scenarios/<scenario_name>/vms/$vm_name_cconf.xml
    my $docstring = $dom->toString(1);
    wlog (VVV, $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_cconf.xmlfile\n' . $dom->toString(1), $logp);
    open XML_CCFILE, ">" . $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_cconf.xml'
        or $execution->smartdie("can not open " . $dh->get_vm_dir . '/' . $vm_name . '_cconf.xml' )
        unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
    print XML_CCFILE "$docstring\n";
    close XML_CCFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

    return $docstring;
}

#
# print_console_table_header: print the header of the console command's table
#                             printed at the end of vnx execution with -t option 
sub print_console_table_header {

	wlog (N, "");	
	wlog (N, sprintf (" %-12s| %-20s| %s", "VM_NAME", "TYPE", "CONSOLE ACCESS COMMAND") );	
	wlog (N, "-----------------------------------------------------------------------------------------");	
}  

#
# print_console_table_entry: prints the information about the consoles of a virtual machine
#
sub print_console_table_entry {

    my $vm_name=shift;
    my $merged_type=shift;
    my $consFile=shift;
    my $type=shift;
    my $briefFormat=shift;
	
	my @cons = qw(con0 con1 con2 con3);
	my $con;
	my @consDesc;
	
	if (-e $consFile) {
		foreach $con (@cons) {
			my $conData= &get_conf_value ($consFile, '', $con);
			#print "** $consFile $con conData=$conData\n";
			my $console_term=&get_conf_value ($vnxConfigFile, 'general', 'console_term', 'root');
			if (defined $conData) {
				if (defined $briefFormat) {
					#print "** conData=$conData\n";
				    my @consField = split(/,/, $conData);
				    if ($consField[1] eq "vnc_display") {
		 				push (@consDesc, "$con,virt-viewer -c $hypervisor $vm_name");		    	
				    } elsif ($consField[1] eq "telnet") {
		 				push (@consDesc, "$con,telnet localhost $consField[2]");		    	   	
				    } elsif ($consField[1] eq "libvirt_pts") {
		 				push (@consDesc, "$con,virsh -c $hypervisor console $vm_name");		    	   		    	
				    } elsif ($consField[1] eq "uml_pts") {
				    	my $conLine = VNX::vmAPICommon->open_console ($vm_name, $con, $consField[1], $consField[2], 'yes');
		 				#push (@consDesc, "$con:  '$console_term -T $vm_name -e screen -t $vm_name $consField[2]'");
		 				push (@consDesc, "$con,$conLine");
                    } elsif ($consField[1] eq "lxc") {
                        push (@consDesc, "$con:  'lxc-console -n $vm_name'");                                                       
				    } else {
				    	wlog (N, "ERROR: unknown console type ($consField[1]) in $consFile");
				    }
				} else {
					#print "** conData=$conData\n";
				    my @consField = split(/,/, $conData);
				    if ($consField[1] eq "vnc_display") {
		 				push (@consDesc, "$con:  'virt-viewer -c $hypervisor $vm_name' or 'vncviewer $consField[2]'");		    	
				    } elsif ($consField[1] eq "telnet") {
		 				push (@consDesc, "$con:  'telnet localhost $consField[2]'");		    	   	
				    } elsif ($consField[1] eq "libvirt_pts") {
		 				push (@consDesc, "$con:  'virsh -c $hypervisor console $vm_name' or 'screen $consField[2]'");		    	   		    	
				    } elsif ($consField[1] eq "uml_pts") {
				    	my $conLine = VNX::vmAPICommon->open_console ($vm_name, $con, $consField[1], $consField[2], 'yes');
		 				#push (@consDesc, "$con:  '$console_term -T $vm_name -e screen -t $vm_name $consField[2]'");
		 				push (@consDesc, "$con:  '$conLine'");
                    } elsif ($consField[1] eq "lxc") {
                        push (@consDesc, "$con:  'lxc-console -n $vm_name'");                               		 				
				    } else {
				    	wlog (N, "ERROR: unknown console type ($consField[1]) in $consFile");
				    }
				}
			}
		}
	} else {
		push (@consDesc, "No consoles defined");
	}
	if (defined $briefFormat) {
		foreach (@consDesc) {
			wlog (N, sprintf ("CON,%s,%s,%s", $vm_name, $merged_type, $_) );
		}
	} else {
		$consDesc[0] =~ s/\n/\\n/g;
		wlog (N, sprintf (" %-12s| %-20s| %s", $vm_name, $merged_type, $consDesc[0]) );
		shift (@consDesc);
		foreach my $cons (@consDesc) {
			$cons =~ s/\n/\\n/g;
			wlog (N, sprintf (" %-12s| %-20s| %s", "", "", $cons) );
		}
		wlog (N, "-----------------------------------------------------------------------------------------");	
	}
	#printf "%-12s  %-20s  ERROR: cannot open file $portfile \n", $name, $merged_type;
}

sub print_consoles_info{
	
	my $briefFormat = $opts{b};

	# Print information about vm consoles
    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process havin into account -M option   
    
    my $first = 1;
    my $scename = $dh->get_scename;
    for ( my $i = 0; $i < @vm_ordered; $i++) {
		my $vm = $vm_ordered[$i];
		my $vm_name = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);
			
		if ( ($first eq 1) && (! $briefFormat ) ){
			&print_console_table_header ($scename);
			$first = 0;
		}

		my $port;
		my $cons0Cmd;
		my $cons1Cmd;
		my $consFile = $dh->get_vm_run_dir($vm_name) . "/console";
		print_console_table_entry ($vm_name, $merged_type, $consFile, $vm->getAttribute("type"), $briefFormat);

	}
	
}

sub print_version {
	
    if ($opts{b}) { 
        # Brief format 
        pre_wlog ("$version,$release");
        exit(0);
    } else {
        # Extended format
        my $basename = basename $0;
        pre_wlog ("");
        pre_wlog ("                   oooooo     oooo ooooo      ooo ooooooo  ooooo ");
        pre_wlog ("                    `888.     .8'  `888b.     `8'  `8888    d8'  ");
        pre_wlog ("                     `888.   .8'    8 `88b.    8     Y888..8P    ");
        pre_wlog ("                      `888. .8'     8   `88b.  8      `8888'     ");
        pre_wlog ("                       `888.8'      8     `88b.8     .8PY888.    ");
        pre_wlog ("                        `888'       8       `888    d8'  `888b   ");
        pre_wlog ("                         `8'       o8o        `8  o888o  o88888o ");
        pre_wlog ("");
        pre_wlog ("                             Virtual Networks over LinuX");
        pre_wlog ("                              http://www.dit.upm.es/vnx      ");
        pre_wlog ("                                    vnx\@dit.upm.es          ");
        pre_wlog ("");
        pre_wlog ("                 Departamento de Ingeniería de Sistemas Telemáticos");
        pre_wlog ("                              E.T.S.I. Telecomunicación");
        pre_wlog ("                          Universidad Politécnica de Madrid");
        pre_wlog ("");
        pre_wlog ("                   Version: $version" . "$branch (built on $release)");
        pre_wlog ("");
        exit(0);
    }           
}

#
# pre_wlog
#
# Used to print to standard output and log file before Execution object is created
# and normal wlog sub can be used
# 
sub pre_wlog {

    my $msg = shift;
	
    print $msg . "\n";
     
    if ($opts{o}) {
        open LOG_FILE, ">> " . $opts{o} 
            or vnx_die( "can not open log file ($opts{o}) for writting" );
        print LOG_FILE $msg . "\n";
    }
    close (LOG_FILE)
}


sub print_header {
	
    pre_wlog ("\n" . $hline);
    pre_wlog ("Virtual Networks over LinuX (VNX) -- http://www.dit.upm.es/vnx - vnx\@dit.upm.es");
    pre_wlog ("Version: $version" . "$branch (built on $release)");
    pre_wlog ($hline);
    
}

####################
# usage
#
# Prints program usage message
sub usage {
	
	my $basename = basename $0;

my $usage = <<EOF;

Usage: 
  [sudo] vnx -f VNX_file --create          [-M vm_list] [options]
  [sudo] vnx -f VNX_file --execute cmd_seq [-M vm_list] [options]
  [sudo] vnx -f VNX_file --shutdown        [-M vm_list] [options]
  [sudo] vnx -f VNX_file --destroy         [-M vm_list] [options]
  [sudo] vnx -f VNX_file --define          [-M vm_list] [options]
  [sudo] vnx -f VNX_file --start           [-M vm_list] [options]
  [sudo] vnx -f VNX_file --undefine        [-M vm_list] [options]
  [sudo] vnx -f VNX_file --save            [-M vm_list] [options]
  [sudo] vnx -f VNX_file --restore         [-M vm_list] [options]
  [sudo] vnx -f VNX_file --suspend         [-M vm_list] [options]
  [sudo] vnx -f VNX_file --resume          [-M vm_list] [options]
  [sudo] vnx -f VNX_file --reboot          [-M vm_list] [options]
  [sudo] vnx -f VNX_file --reset           [-M vm_list] [options]
  [sudo] vnx -f VNX_file --show-map 
  vnx -h
  vnx -V
  [sudo] vnx --clean-host
  [sudo] vnx --create-rootfs ROOTFS_file --install-media MEDIA_file 
  [sudo] vnx --modify-rootfs ROOTFS_file [--update-aced]

Main modes:
  --create|-t   -> create the complete scenario defined in VNX_file, or just
                   start the virtual machines (VM) specified with -M option.
  --execute|-x cmd_seq -> execute the commands tagged 'cmd_seq' in VNX_file.
  --shutdown|-d -> destroy current scenario, or the VMs specified in -M option.
  --destroy|-P  -> purge (destroy) the whole scenario, or just the VMs 
                   specified in -M option, (Warning: it will remove VM COWed
                   filesystems! Any changes in VMs will be lost).
  --define      -> define (but not start) the whole scenario, or just the VMs
                   speficied in -M option.
  --undefine    -> undefine the scenario or the VMs speficied with -M. 
  --start       -> start the scenario or the VMs speficied with -M.
  --save        -> save the scenario to disk or the VMs speficied with -M.
  --restore     -> restore the scenario from disk or the VMs speficied with -M.
  --suspend     -> suspend the scenario to memory or the VMs speficied with -M.
  --resume      -> resume the scenario from memory or the VMs speficied with -M.
  --reboot      -> reboot the scenario or the VMs speficied with -M.

Virtual machines list specification:
  -M vm_list    -> list of VM names separated by ','
	
Console management modes:
  --console-info       -> shows information about all virtual machine consoles 
                          or the one specified with -M option.
  --console-info -b    -> same info about consoles in a compact format
  --console            -> opens the consoles of all vms or just the ones 
                          speficied with -M. Only consoles with display="yes" 
                          in VNX_file are opened.
  --console --cid conX -> opens 'conX' console (being conX the id of a console:
                          con0, con1, etc) of all vms, or the defined with -M.                              
  Examples:
    vnx -f ex1.xml --console
    vnx -f ex1.xml --console con0 -M A --> open console 0 of vm A of scenario ex1.xml

Other modes:
  --show-map      -> shows a map of the network scenarios build using graphviz.
  --exe-info      -> show information about the commands available in VNX_file.
  --create-rootfs -> starts a virtual machine to create a rootfs. 
                     Use --install-media option to specify installation media.
  --modify-rootfs -> starts a virtual machine using the rootfs specified in
                     order to modify it (install software, modify config, etc).
  --clean-host    -> WARNING! WARNING! WARNING!
                     This option completely restarts the host status.
                     It kills (power-off) all libvirt, UML and dynamips virtual
                     machines, even those not started with VNX. Besides, it 
                     restarts libvirt and dynamips daemons and deletes '.vnx' 
                     directory. Unless '--yes|-y' option specified, it asks 
                     for confirmation.
                     WARNING! WARNING! WARNING!

Pseudomodes:
  -V, show program version and exit.
  -H, show this help message and exit.

General options:
  -c vnx_dir -> vnx working directory (default is ~/.vnx)
  -v         -> verbose mode
  -vv        -> more verbose mode
  -vvv       -> even more verbose mode
  -T tmp_dir -> temporal files directory (default is /tmp)
  -C|--config cfgfile -> use cfgfile as configuration file instead of default 
                one (/etc/vnx.conf)
  -D         -> delete VNX LOCK file (\$vnx_dir/LOCK). If combined with a mode 
                command, deletes the lock file before executing the command. 
  -n|--no-console -> do not display the console of any vm. To be used with 
                -t|--create options
  -y|--st-delay num -> wait num secs. between virtual machines startup 
                (0 by default)
  -o logfile -> save log traces to 'logfile'

User options:
  -u user -> Defines the user VNX is (mostly) run as. By now, VNX has to be
             run with root priviledges (from a root shell or sudoed) for 
             creating virtual machines and manipulate bridges and network 
             interfaces.
             
  Present behaviour (provisional):
    - '-u root' or '-u' option absent 
          -> VNX runs completely as root
    - '-u' 
          -> VNX runs (mostly) as default user (the user from which sudo was 
             issued) 
    - '-u user' (NOT implemented yet)     
          -> VNX runs (mostly) as 'user'

UML specific options:
  -F         -> force stopping of UMLs (warning: UML filesystems may be corrupted)
  -w timeout -> waits timeout seconds for a UML to boot before prompting the user 
                for further action; a timeout of 0 indicates no timeout (default is 30)
  -B         -> blocking mode
  -e screen_file  -> make screen configuration file for pts devices

Options specific to create|modify-rootfs modes:
  --install-media -> install media (iso file) used to create a VM in create-rootfs mode
  --mem           -> memory to assign to the VM being created or modified (e.g. 512M or 1G)
  --arch          -> architecture (i686 or x86_64) of the VM being created or modified
  --vcpu          -> number of virtual cpus to assign to the VM being created or modified (>=1)

EOF

print "$usage\n";   


#
# OLD USAGE. Kept for reference
#
my $usage_alloptions = <<EOF;

Usage: vnx -f VNX_file [-t|--create] [-o prefix] [-c vnx_dir] [-u user]
                 [-T tmp_dir] [-i] [-w timeout] [-B]
                 [-e screen_file] [-4] [-6] [-v] [-g] [-M vm_list] [-D]
       vnx -f VNX_file [-x|--execute cmd_seq] [-T tmp_dir] [-M vm_list] [-i] [-B] [-4] [-6] [-v] [-g]
       vnx -f VNX_file [-d|--shutdown] [-c vnx_dir] [-F] [-T tmp_dir] [-i] [-B] [-4] [-6] [-v] [-g]
       vnx -f VNX_file [-P|--destroy] [-T tmp_file] [-i] [-v] [-u user] [-g]
       vnx -f VNX_file [--define] [-M vm_list] [-v] [-u user] [-i]
       vnx -f VNX_file [--start] [-M vm_list] [-v] [-u user] [-i]
       vnx -f VNX_file [--undefine] [-M vm_list] [-v] [-u user] [-i]
       vnx -f VNX_file [--save] [-M vm_list] [-v] [-u user] [-i]
       vnx -f VNX_file [--restore] [-M vm_list] [-v] [-u user] [-i]
       vnx -f VNX_file [--suspend] [-M vm_list] [-v] [-u user] [-i]
       vnx -f VNX_file [--resume] [-M vm_list] [-v] [-u user] [-i]
       vnx -f VNX_file [--reboot] [-M vm_list] [-v] [-u user] [-i]
       vnx -f VNX_file [--reset] [-M vm_list] [-v] [-u user] [-i]
       vnx -f VNX_file [--show-map] 
       vnx -h
       vnx -V

Main modes:
       -t|--create   -> build topology, or create virtual machine (if -M), using VNX_file as source.
       -x|--execute cmd_seq -> execute the cmd_seq command sequence, using VNX_file as source.
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
            vnx -f ex1.xml --console
            vnx -f ex1.xml --console con0 -M A --> open console 0 of vm A of scenario ex1.xml

Other modes:
       --show-map    -> shows a map of the network scenarios build using graphviz.

Pseudomode:
       -V, show program version and exit.
       -H, show this help message and exit.

Options:
       -o prefix       -> dump UML boot messages output to files (using given prefix in pathname)
       -c vnx_dir      -> vnx working directory (default is ~/.vnx)
       -u user         -> if run as root, UML and uml_switch processes will be owned by this 
                          user instead (default [arroba]VNX_USER[arroba])
       -F              -> force stopping of UMLs (warning: UML filesystems may be corrupted)
       -w timeout      -> waits timeout seconds for a UML to boot before prompting the user 
                          for further action; a timeout of 0 indicates no timeout (default is 30)
       -B              -> blocking mode
       -e screen_file  -> make screen configuration file for pts devices
       -i              -> interactive execution (in combination with -v mode)
       -4              -> process only IPv4 related tags (and not process IPv6 related tags)
       -6              -> process only IPv6 related tags (and not process IPv4 related tags)
       -v              -> verbose mode on
       -g              -> debug mode on (overrides verbose)
       -T tmp_dir      -> temporal files directory (default is /tmp)
       -M vm_list      -> start/stop/restart scenario in vm_list (a list of names separated by ,)
       -C|--config cfgfile -> use cfgfile as configuration file instead of default one (/etc/vnx.conf)
       -D              -> delete LOCK file
       -n|--no-console -> do not display the console of any vm. To be used with -t|--create options
       --st-delay num -> wait num secs. between virtual machines startup (0 by default)

EOF



}
