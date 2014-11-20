#!/usr/bin/perl 
#!@PERL@
# ---------------------------------------------------------------------------------
# VNX parser. 
#
# Authors:    Fermin Galan Marquez (galan@dit.upm.es), David Fernández (david@dit.upm.es),
#             Jorge Somavilla (somavilla@dit.upm.es), Jorge Rodriguez (jrodriguez@dit.upm.es), 
#             Carlos González (carlosgonzalez@dit.upm.es)
# Coordinated by: David Fernández (david@dit.upm.es)
# Copyright (C) 2005-2014 DIT-UPM
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
use Cwd qw(abs_path getcwd);
use Getopt::Long;
use IO::Socket;
use NetAddr::IP;
use Data::Dumper;
use v5.10;

use XML::LibXML;
use XML::Tidy;

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
use VNX::vmAPI_vbox;
use VNX::vmAPI_nsrouter;

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
#my $curr_uml;

# VNX scenario file
my $input_file;

# Delay between virtual machines startup
#my $vmStartupDelay;

# host log prompt
my $logp = "host> ";

# All modes list
#'define', 'undefine', 'create', 'start', 'shutdown', 'destroy', 'execute', 'modify', 'save', 'restore', 'suspend', 'resume', 'reboot', 'reset', 'show-map', 'console', 'console-info', 'exe-info', 'clean-host', 'create-rootfs', 'modify-rootfs', 'version', 'help', 

# Modes allowed with --scenario|-s option  
my @opt_s_allowed_modes = ('create', 'start', 'shutdown', 'destroy', 'execute', 'exe-cli', 'modify', 'save', 'restore', 
                           'suspend', 'resume', 'reboot', 'reset', 'recreate', 'console', 'console-info', 'exe-info', 'show-map', 'show-status'); 
# Modes allowed with -f option  
my @opt_f_allowed_modes = ('define', 'undefine', 'start', 'create', 'shutdown', 'destroy', 'execute', 'exe-cli', 'save', 'restore',  
                           'suspend', 'resume', 'reboot', 'reset', 'recreate', 'console', 'console-info', 'exe-info', 'show-map', 'show-status'); 

# Modes allowed without -f or -s option  
my @no_opt_f_or_s_allowed_modes = ('version', 'help', 'D', 'show-map', 'show-status', 'clean-host', 'create-rootfs', 'modify-rootfs', 'download-rootfs');

# Modes that do not need exclusive access (no lock file needed)   
my @no_lock_modes = ('show-map', 'show-status'); 

# Modes allowed with rootfs-type
my @opt_rootfstype_modes = ('create-rootfs', 'modify-rootfs'); 

# To store command in "exe-cli" mode
my @exe_cli;


main();
exit(0);


###########################################################
# THE MAIN PROGRAM
#
sub main {
	
   	$ENV{'PATH'} .= ':/bin:/usr/bin/:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin';
   	
   	my $boot_timeout = 60; # by default, 60 seconds for boot timeout 
   	my $start_time;        # the moment when the parsers start operation
    my $xml_dir;

   	###########################################################
   	# To get the invocation arguments
    Getopt::Long::Configure ( qw{no_auto_abbrev no_ignore_case } ); # case sensitive single-character options
    GetOptions (\%opts,
                'define', 'undefine', 'start', 'create|t', 'shutdown|d', 'destroy|P', 'modify|m=s', 'scenario|s=s', 
                'save', 'restore', 'suspend', 'resume', 'reboot', 'reset', 'recreate', 'execute|x=s', 'exe-cli=s{1,}' => \@exe_cli, 
                'show-map:s', 'show-status', 'console:s', 'console-info', 'exe-info', 'clean-host',
                'create-rootfs=s', 'modify-rootfs=s', 'install-media=s', 'update-aced:s', 'mem=s', 'yes|y',
                'rootfs-type=s', 'help|h', 'v', 'vv', 'vvv', 'version|V', 'download-rootfs',
                'f=s', 'c=s', 'T=s', 'config|C=s', 'M=s', 'i', 'g',
                'user|u:s', '4', '6', 'D', 'no-console|n', 'intervm-delay=s',
                'e=s', 'w=s', 'F', 'B', 'o=s', 'Z', 'b', 'arch=s', 'vcpu=s', 'kill|k', 'video=s'
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
   		$vnx_dir = do_path_expansion($DEFAULT_VNX_DIR);
   	} else {
   		$vnx_dir = do_path_expansion($vnx_dir);
   	}
   	unless (valid_absolute_directoryname($vnx_dir) ) {
        vnx_die ("ERROR: $vnx_dir is not an absolute directory name");
   	}
   	pre_wlog ("  VNX dir=$vnx_dir") if (!$opts{b});

   	# To check arguments consistency
   	
   	#pre_wlog("exe-cli=" . join(' ', @exe_cli) );
   	
   	# 1. To use -t|--create, -x|--execute, -d|--shutdown, -V, -P|--destroy, --define, --start,
   	# --undefine, --save, --restore, --suspend, --resume, --reboot, --reset, --console, --console-info at the same time
   
   	my $how_many_args = 0;
   	my $mode_args = '';
   	my $mode;
    if ($opts{'define'})           { $how_many_args++; $mode_args .= 'define ';          $mode = "define";         }
    if ($opts{'undefine'})         { $how_many_args++; $mode_args .= 'undefine ';        $mode = "undefine";       }
    if ($opts{'start'})            { $how_many_args++; $mode_args .= 'start ';           $mode = "start";          }
   	if ($opts{'create'})           { $how_many_args++; $mode_args .= 'create|t ';        $mode = "create";         }
    if ($opts{'shutdown'})         { $how_many_args++; $mode_args .= 'shutdown|d ';      $mode = "shutdown";       }
    if ($opts{'destroy'})          { $how_many_args++; $mode_args .= 'destroy|P ';       $mode = "destroy";        }
    if ($opts{'suspend'})          { $how_many_args++; $mode_args .= 'suspend ';         $mode = "suspend";        }
    if ($opts{'resume'})           { $how_many_args++; $mode_args .= 'resume ';          $mode = "resume";         }
    if ($opts{'save'})             { $how_many_args++; $mode_args .= 'save ';            $mode = "save";           }
    if ($opts{'restore'})          { $how_many_args++; $mode_args .= 'restore ';         $mode = "restore";        }
    if ($opts{'reboot'})           { $how_many_args++; $mode_args .= 'reboot ';          $mode = "reboot";         }
    if ($opts{'reset'})            { $how_many_args++; $mode_args .= 'reset ';           $mode = "reset";          }
    if ($opts{'recreate'})         { $how_many_args++; $mode_args .= 'recreate ';        $mode = "recreate";       }
    if ($opts{'execute'})          { $how_many_args++; $mode_args .= 'execute|x ';       $mode = "execute";        }
    if (@exe_cli)                  { $how_many_args++; $mode_args .= 'exe-cli ';         $mode = "exe-cli";        }
    if ($opts{'modify'})           { $how_many_args++; $mode_args .= 'modify|m ';        $mode = "modify";         }
   	if ($opts{'version'})          { $how_many_args++; $mode_args .= 'version|V ';       $mode = "version";        }
   	if ($opts{'help'})             { $how_many_args++; $mode_args .= 'help|h ';          $mode = "help";           }
   	if (defined($opts{'show-map'})){ $how_many_args++; $mode_args .= 'show-map ';        $mode = "show-map";       }
    if ($opts{'show-status'})      { $how_many_args++; $mode_args .= 'show-status ';     $mode = "show-status";    }
   	if (defined($opts{'console'})) { $how_many_args++; $mode_args .= 'console ';         $mode = "console";        }
   	if ($opts{'console-info'})     { $how_many_args++; $mode_args .= 'console-info ';    $mode = "console-info";   }
    if ($opts{'exe-info'})         { $how_many_args++; $mode_args .= 'exe-info ';        $mode = "exe-info";       }
    if ($opts{'clean-host'})       { $how_many_args++; $mode_args .= 'clean-host ';      $mode = "clean-host";     }
    if ($opts{'create-rootfs'})    { $how_many_args++; $mode_args .= 'create-rootfs ';   $mode = "create-rootfs";  }
    if ($opts{'modify-rootfs'})    { $how_many_args++; $mode_args .= 'modify-rootfs ';   $mode = "modify-rootfs";  }
    if ($opts{'download-rootfs'})  { $how_many_args++; $mode_args .= 'download-rootfs '; $mode = "download-rootfs";}
    chop ($mode_args);
    
   	if ($how_many_args gt 1) {
      	usage();
        vnx_die ("Only one of the following options can be specified at a time: '$mode_args'");
        #vnx_die ("Only one of the following options at a time:\n -t|--create, -x|--execute, -d|--shutdown, " .
      	#          "-V, -P|--destroy, --define, --start,\n --undefine, --save, --restore, --suspend, " .
      	#          "--resume, --reboot, --reset, --showmap, --clean-host, --create-rootfs, --modify-rootfs or -H");
   	}
   	if ( ($how_many_args lt 1) && (!$opts{D}) ) {
      	usage();
      	vnx_die ("missing main mode option. Specify one of the following options: \n" . 
      	          "  -t|--create, -d|--shutdown, -V, -P|--destroy, -m|--modify, --define, --undefine, \n" . 
      	          "  --start, --suspend, --resume, --save, --restore, --reboot, --reset, --recreate,\n" . 
      	          "  -x|--execute, --exe-cli, --show-map, --show-status, --console, --console-info, \n" . 
      	          "  --clean-host, --create-rootfs, --modify-rootfs, -V or -H\n");
   	}

    # 0. Check -f and -s options dependencies
    if  ( $opts{'rootfs-type'}  && ! any_mode_set(\@opt_rootfstype_modes) ) {
        usage();
        vnx_die ("Option --rootfs-type requires any of the following modes: " . print_modes(\@opt_rootfstype_modes) . "\n");
    }
    if  ( $opts{'scenario'}  && ! any_mode_set(\@opt_s_allowed_modes) ) {
        usage();
        vnx_die ("Option -s requires any of the following modes: " . print_modes(\@opt_s_allowed_modes) . "\n");        
    } 
    if  ( $opts{'f'}  && ! any_mode_set(\@opt_f_allowed_modes) ) {
        usage();
        vnx_die ("Option -f requires any of the following modes: " . print_modes(\@opt_f_allowed_modes) . "\n");
    }
    if  ( !$opts{'f'} && !$opts{'scenario'} && ! any_mode_set(\@no_opt_f_or_s_allowed_modes) ) {
        usage();
        vnx_die ("Option -f or -s missing\n");
    }
    if  ( $opts{'scenario'} && $opts{'create'} && !$opts{'M'} ) {
        usage();
        vnx_die ("Option -s combined with --create|-t option is only valid when used together with -M\n");
    }

   	if (($opts{kill}) && (!($opts{'shutdown'}))) { 
      	usage(); 
      	vnx_die ("Option --kill|k only makes sense with -d|--shutdown mode\n"); 
   	}
#   	if (($opts{B}) && ($opts{F}) && ($opts{'shutdown'})) {
#      	vnx_die ("Option -F and -B are incompabible\n");
#   	}
#    if (($opts{o}) && (!($opts{'create'}))) {
#      	usage();
#      	vnx_die ("Option -o only makes sense with -t|--create mode\n");
#   	}
   	if (($opts{w}) && (!($opts{'create'}))) {
      	usage();
      	vnx_die ("Option -w only makes sense with -t|--create mode\n");
   	}
  	if (($opts{e}) && (!($opts{'create'}))) {
      	usage();
      	vnx_die ("Option -e only makes sense with -t|--create mode\n");
   	}
#   	if (($opts{Z}) && (!($opts{'create'}))) {
#      	usage();
#      	vnx_die ("Option -Z only makes sense with -t|--create mode\n");
#   	}
   	if (($opts{4}) && ($opts{6})) {
      	usage();
      	vnx_die ("-4 and -6 can not be used at the same time\n");
   	}
   	if ( $opts{'no-console'} && (!($opts{'create'}) && !($opts{'start'}))) {
      	usage();
      	vnx_die ("Option -n|--no-console only makes sense with -t|--create or --start mode\n");
   	}

    if ( $opts{'modify'} && (!($opts{'scenario'}))) {
        usage();
        vnx_die ("--modify scenario option selected, but no scenario name specified with --scenario|-s option.\n");
    }

    # 2. Optional arguments
    $exemode = $EXE_NORMAL; $EXE_VERBOSITY_LEVEL=N;
    if ($opts{v})   { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=V }
    if ($opts{vv})  { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=VV }
    if ($opts{vvv}) { $exemode = $EXE_VERBOSE; $EXE_VERBOSITY_LEVEL=VVV }
    $exemode = $EXE_DEBUG if ($opts{g});
    chomp(my $pwd = `pwd`);
    $vnx_dir = chompslash($opts{c}) if ($opts{c});
    $vnx_dir = "$pwd/$vnx_dir"
           unless (valid_absolute_directoryname($vnx_dir));
    $tmp_dir = chompslash($opts{T}) if ($opts{T});
    $tmp_dir = "$pwd/$tmp_dir"
           unless (valid_absolute_directoryname($tmp_dir));    

    # DFC 21/2/2011 $uid = getpwnam($opts{u) if ($> == 0 && $opts{u);
    $boot_timeout = $opts{w} if (defined($opts{w}));
    unless ($boot_timeout =~ /^\d+$/) {
        vnx_die ("-w value ($opts{w}) is not a valid timeout (positive integer)\n");  
    }

    # FIXME: $enable_4 and $enable_6 are not necessary, use $args object
    # instead and avoid redundance
    my $enable_4 = 1;
    my $enable_6 = 1;
    $enable_4 = 0 if ($opts{6});
    $enable_6 = 0 if ($opts{4});   
    
    # 3. To extract and check input file
    if ($opts{f}) {
        $input_file = $opts{f};
        $xml_dir = (fileparse(abs_path($input_file)))[1];
    } elsif (defined($opts{'scenario'})){

        my $scename=$opts{'scenario'};
        my $scen_dir="$vnx_dir/scenarios/$scename";
		
        unless (-d $scen_dir) { vnx_die ("ERROR: no scenario named $scename found in $vnx_dir\n") }

        my @files = glob ($scen_dir . "/*.xml");
		
        if ( @files == 0 ) { vnx_die ("ERROR: no scenario XML file not found in $scen_dir\n") }
        elsif ( @files gt 1 ) {
            my $found=0;
            foreach my $file (@files) {
                if (`grep "<scenario_name>$scename<" $file`) {
                    $input_file=$file;
                    $found++;
                }
            }
            if    ($found == 0) { vnx_die ("ERROR: no XML with scenario_name=$scename found in $scen_dir\n") }
            elsif ($found > 1 ) { vnx_die ("ERROR: two or more XML files with scenario_name=$scename found in $scen_dir\n") }
        } else {
            $input_file=$files[0];
        }
		#print "escenario XML file: $input_file\n"
        #$input_file = "$vnx_dir/scenarios/$opts{'scenario'}/$opts{'scenario'}.xml";
        $xml_dir = getcwd();
    } 
    pre_wlog ("  INPUT file: " . $input_file) if ( (!$opts{b}) && ($opts{f} || $opts{scenario}) );

    # Check for file and cmd_seq, depending the mode
    my $cmdseq = '';
    if ($opts{'execute'}) {
        $cmdseq = $opts{'execute'}
    } 
    
    # Reserved words for cmd_seq
    #if ($cmdseq eq "always") {
    #   vnuml_die ("\"always\" is a reserved word and can not be used as cmd_seq\n");
    #}

    # 4. To check vnx_dir and tmp_dir
    # Create the working directory, if it doesn't already exist
    if ($exemode ne $EXE_DEBUG) {
        if (! -d $vnx_dir ) {
            mkdir $vnx_dir or vnx_die("Unable to create working directory $vnx_dir: $!\n");
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
             vnx_die ("vnx_dir $vnx_dir does not exist or is not readable/executable (user $uid_name)\n") unless (-r $vnx_dir && -x _);
             vnx_die ("vnx_dir $vnx_dir is not writeable (user $uid_name)\n") unless ( -w _);
             vnx_die ("vnx_dir $vnx_dir is not a valid directory\n") unless (-d _);
#            $> = 0;
#       }


        if (! -d "$vnx_dir/scenarios") {
            mkdir "$vnx_dir/scenarios" or vnx_die("Unable to create scenarios directory $vnx_dir/scenarios: $!\n");
        }
        if (! -d "$vnx_dir/networks") {
            mkdir "$vnx_dir/networks" or vnx_die("Unable to create networks directory $vnx_dir/networks: $!\n");
        }
    }
    vnx_die ("tmp_dir $tmp_dir does not exist or is not readable/executable\n") unless (-r $tmp_dir && -x _);
    vnx_die ("tmp_dir $tmp_dir is not writeable\n") unless (-w _);
    vnx_die ("tmp_dir $tmp_dir is not a valid directory\n") unless (-d _);

    # 5. To build the VNX::BinariesData object
    $bd = new VNX::BinariesData($exemode);

    # 6a. To check mandatory binaries and perl modules # [JSF] to be updated with new ones
    if ($bd->check_binaries_mandatory != 0) {
      vnx_die ("some required binary files are missing\n");
    }
    if (my $res = $bd->check_perlmods_mandatory) {
      vnx_die ("$res\n");
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
        usage();
        exit(0);
    }

    # Clean host pseudomode
    if ($opts{'clean-host'}) {
        mode_cleanhost($vnx_dir);
        exit(0);
    }
    
    # Create root filesystem pseudomode
    if ($opts{'create-rootfs'}) {
        mode_createrootfs($tmp_dir, $vnx_dir);
        exit(0);
    }

    # Modify root filesystem pseudomode
    if ($opts{'modify-rootfs'}) {
        mode_modifyrootfs($tmp_dir, $vnx_dir);
        exit(0);
    }

    # Download root filesystem pseudomode
    if ($opts{'download-rootfs'}) {
        mode_downloadrootfs();
        exit(0);
    }
    
    # Mode show-status without scenario being specified
    if ($opts{'show-status'} && !$opts{'f'} && !$opts{'scenario'}) {
        mode_showstatus($vnx_dir, 'global');
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
        vnx_die ("file $input_file is not valid (perhaps does not exists)\n");
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
	#$parser->keep_blanks(0);
    my $doc = $parser->parse_file($input_file);
    
    # Look for a windows configuration file associated to the scenario
    #
    my $cfg_file;
    # Check if a <vnx_cfg> tag is included
    if( $doc->exists("/vnx/global/vnx_cfg") ){
        my @cfg_file_tag = $doc->findnodes('/vnx/global/vnx_cfg');
        $cfg_file = $cfg_file_tag[0]->textContent();
        unless (valid_absolute_filename($cfg_file)) {
        	$cfg_file = $xml_dir . "/" . $cfg_file;
        }
        unless (-r $cfg_file) {
            vnx_die ("cannot read windows configuration file ($cfg_file)\n");
        }
    } else { # Check if a file with the same name as the scenario but with .cvnx extension exists
             # in the scenario directory
        $cfg_file = basename($input_file);
        $cfg_file =~ s{\.[^.]+$}{}; # remove extension
        $cfg_file = "${xml_dir}/${cfg_file}.cvnx";
        unless (-e $cfg_file) {
            $cfg_file = '';	
        }
    }
    pre_wlog ("  CFG file: $cfg_file") if ( !$opts{b} && $cfg_file );
   	# Calculate the directory where the input_file lives
   	#my $xml_dir = (fileparse(abs_path($input_file)))[1];

   	# Build the VNX::DataHandler object
   	$dh = new VNX::DataHandler($execution,$doc,$mode,$opts{M},$opts{H},$cmdseq,$xml_dir,$input_file,$cfg_file);
   	$dh->set_boot_timeout($boot_timeout);
   	$dh->set_vnx_dir($vnx_dir);
   	$dh->set_tmp_dir($tmp_dir);
   	$dh->enable_ipv6($enable_6);
   	$dh->enable_ipv4($enable_4);   

   	# User check (deprecated: only root or a user with 'sudo vnx ...' permissions can execute VNX)
   	#if (my $err_msg = check_user) {
    #  	vnx_die("$err_msg\n");
   	#}

   	# Deprecation warnings
   	check_deprecated();

   	# Semantic check (in addition to validation)
   	if (my $err_msg = check_doc($bd->get_binaries_path_ref,$execution->get_uid)) {
      	vnx_die ("$err_msg\n");
   	}
   
   	# Validate extended XML configuration files
	# Dynamips
	my $dmipsConfFile = $dh->get_default_dynamips();
	if ($dmipsConfFile ne "0"){
		$dmipsConfFile = get_abs_path ($dmipsConfFile);
		my $error = validate_xml ($dmipsConfFile);
		if ( $error ) {
	        vnx_die ("Dynamips XML configuration file ($dmipsConfFile) validation failed:\n$error\n");
		}
	}
	# Olive
	my $oliveConfFile = $dh->get_default_olive();
	if ($oliveConfFile ne "0"){
		$oliveConfFile = get_abs_path ($oliveConfFile);
		my $error = validate_xml ($oliveConfFile);
		if ( $error ) {
	        vnx_die ("Olive XML configuration file ($oliveConfFile) validation failed:\n$error\n");
		}
	}
   	# To check optional screen binaries
   	$bd->add_additional_screen_binaries();
   	if (($opts{e}) && ($bd->check_binaries_screen != 0)) {
      	vnx_die ("screen related binary is missing\n");
   	}

   	# To check optional uml_switch binaries 
   	$bd->add_additional_uml_switch_binaries();
   	if (($bd->check_binaries_switch != 0)) {
      	vnx_die ("uml_switch related binary is missing\n");
   	}

   	# To check optional binaries for virtual bridge
   	$bd->add_additional_bridge_binaries();   
   	if ($bd->check_binaries_bridge != 0) {
      	vnx_die ("virtual bridge related binary is missing\n");  
   	}

    # To check xterm binaries
    $bd->add_additional_xterm_binaries();
    if (($bd->check_binaries_xterm != 0)) {
        vnx_die ("xterm related binary is missing\n");
    }

    # To check optional binaries for VLAN support
    $bd->add_additional_vlan_binaries();   
    if ($bd->check_binaries_vlan != 0) {
        vnx_die ("VLAN related binary is missing\n");  
    }   

    # To check optional binaries for LXC support
    $bd->add_additional_lxc_binaries();   
    if ($bd->check_binaries_lxc != 0) {
        vnx_die ("LXC related binary is missing\n");  
    }   

    # To check optional binaries for libvirt support
    $bd->add_additional_libvirt_binaries();   
    if ($bd->check_binaries_libvirt != 0) {
        vnx_die ("Libvirt related binary is missing\n");  
    }   

    # To check optional binaries for KVM support
    $bd->add_additional_kvm_binaries();   
    if ($bd->check_binaries_kvm != 0) {
        vnx_die ("KVM related binary is missing\n");  
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
            $plugin_conf = get_abs_path($plugin_conf);
	        if (! -f $plugin_conf) {
	            vnx_die ("plugin $plugin configuration file $plugin_conf is not valid (perhaps does not exists)\n");
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
         	vnx_die ("plugin $plugin reports error: $err_msg\n");
      	}
      	push (@plugins,$plugin);
   	}

    # Initialize vmAPI modules
    my $init_err;
    if ($init_err=VNX::vmAPI_uml->init)      { vnx_die("Cannot initialize UML module -> $init_err")}
    if ($init_err=VNX::vmAPI_libvirt->init)  { vnx_die("Cannot initialize Libvirt module -> $init_err")}
    if ($init_err=VNX::vmAPI_dynamips->init) { vnx_die("Cannot initialize Dynamips module -> $init_err")}
    if ($init_err=VNX::vmAPI_lxc->init)      { vnx_die("Cannot initialize LXC module -> $init_err")}
    #if ($init_err=VNX::vmAPI_vbox->init)      { vnx_die("Cannot initialize VirtualBox module -> $init_err")}
    if ($init_err=VNX::vmAPI_nsrouter->init) { vnx_die("Cannot initialize Name Spaces routers module -> $init_err")}
    pre_wlog ($hline)  if (!$opts{b});


   	if ($exeinteractive) {
      	wlog (N, "interactive execution is on: press a key after each command");
   	}

   	# Lock management
   	if ( ! any_mode_set(\@no_lock_modes) ) {
   		if (-f $dh->get_vnx_dir . "/LOCK")  {
	      	my $basename = basename $0;
	      	vnx_die($dh->get_vnx_dir . "/LOCK exists: another instance of $basename seems to be in execution\n" . 
	      	    "If you are sure that this can't be happening in your system, delete LOCK file with 'vnx -D' or a 'rm " . 
	      	     $dh->get_vnx_dir . "/LOCK' and try again\n");
	   	}
	   	else {
	      	$execution->execute($logp, $bd->get_binaries_path_ref->{"touch"} . " " . $dh->get_vnx_dir . "/LOCK");
	      	$start_time = time();
	   	}
   	}
   	
   	#
   	# Call to mode handler functions
   	#
    if ($mode eq 'define') {
        mode_define();
    }
    elsif ($mode eq 'undefine') {
        mode_undefine();
    }
    elsif ($mode eq 'start') {
        mode_start();
    }
    elsif ($mode eq 'shutdown') {
    	if ($opts{'kill'}) {
            mode_shutdown('kill');
    	} else {
            mode_shutdown('do_exe_cmds');
    	}
    }
    elsif ($mode eq 'create') {
        mode_define();
        mode_start();
    }
    elsif ($mode eq 'destroy') {
        mode_shutdown('kill');
        mode_undefine();
    }
    elsif ($mode eq 'suspend') {
        mode_suspend();
    }
    elsif ($mode eq 'resume') {
        mode_resume();
    }
    elsif ($mode eq 'save') {
        mode_save();
    }
    elsif ($mode eq 'restore') {
        mode_restore();
    }
    elsif ($mode eq 'reboot') {
        mode_shutdown('do_exe_cmds');
        sleep(3);
        mode_start();
    }
    elsif ($mode eq 'reset') {
        mode_shutdown('kill');
        sleep(3);
        mode_start();
    }
    elsif ($mode eq 'recreate') {
        mode_shutdown('kill');
        mode_undefine();
        sleep(3);    
        mode_define();
        mode_start();
    }
   	elsif ($mode eq 'execute') {
      	mode_execute($cmdseq, 'all');
   	}
    elsif ($mode eq 'exe-cli') {
        mode_execli();
    }
    elsif ($mode eq 'modify') {
        # Modify scenario mode
change_to_root();
        unless ( -f $opts{'modify'} ) {
            vnx_die ("file $opts{'modify'} is not valid (perhaps does not exists)");
        }
back_to_user();
        mode_modify($opts{'modify'}, $vnx_dir);
    }
   	elsif ($mode eq 'show-map') {
     	mode_showmap();
   	}
    elsif ($mode eq 'show-status') {
        mode_showstatus($vnx_dir, 'detailed');
    }
   	elsif ($mode eq 'console') {
     	if ($exemode != $EXE_DEBUG) {
        	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        	unless scenario_exists($dh->get_scename);
     	}
		mode_console();
   	}
   	elsif ($mode eq 'console-info') {
     	if ($exemode != $EXE_DEBUG) {
        	$execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        	unless scenario_exists($dh->get_scename);
     	}
   		mode_consoleinfo();
   	}
    elsif ($mode eq 'exe-info') {
        mode_exeinfo();
    }
    elsif ($mode eq 'save-scenario') {
        mode_savescenario($vnx_dir);
    }
    elsif ($mode eq 'restore-scenario') {
        mode_restorescenario($vnx_dir);
    }
   
    else {
        $execution->smartdie("if you are seeing this text something terribly horrible has happened...\n");
    }

    # Call the finalize subrutine in plugins
    foreach my $plugin (@plugins) {
        $plugin->finalizePlugin;
    }
   
    # Remove lock if used
    if ( ! any_mode_set(\@no_lock_modes) ) {
	    $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_vnx_dir . "/LOCK");
	    unless ($opts{b}) {
	        my $total_time = time() - $start_time;
		    wlog (N, $hline);
		    wlog (N, "Total time elapsed: $total_time seconds");
		    wlog (N, $hline);
	    }
    }
}

#
# any_mode_set
# 
# returns 1 if any of the line commands options passed in an array is set, 0 otherwise 
#
sub any_mode_set {
	
	my $ref_opt_list = shift;
    my @opt_list = @{$ref_opt_list};

    my $res=0;	
	foreach my $opt (@opt_list) {
        if ($opt eq 'exe-cli') {
        	if (@exe_cli)  { return 1 } 
        } else {
            if (defined($opts{$opt}))  { return 1 } 
        }
	}
	return $res;
}

#
# print_modes
# 
# returns a comma separated string of modes passed in an array 
#
sub print_modes {
    
    my $ref_opt_list = shift;
    my @opt_list = @{$ref_opt_list};

    my $res;
    foreach my $opt (@opt_list) { $res .= $opt . "," }
    chop($res);
    return $res;
}

#
# Virtual machines posible states:
#
# - defined
# - undefined
# - running
# - suspended
# - hibernated
#

#
# ------------------------------------------------------------------------------
#                           D E F I N E   M O D E
# ------------------------------------------------------------------------------
# 
# Build network topology (only when -M is not used) and defines VMs by calling 
# vmAPI->define_vm function.
#
# Arguments:
#   - $ref_vm:  reference to an array with the list of VMs to work on. If not specified,
#               it works with all the VMs in scenario or the ones specified in -M option
#               if used. 
#
sub mode_define {
	
    my $ref_vms = shift;    
    my @vm_ordered;
    if ( defined($ref_vms) ) {
    	# List of VMs to use passed as parameter
        @vm_ordered = @{$ref_vms};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @vm_ordered = $dh->get_vm_to_use_ordered;    
    }

    my $logp = "mode_define> ";
    wlog (VVV, "Defining " . get_vmnames(\@vm_ordered), $logp);

    # If not -M option or ref_vms specified, the scenario must not exist
    if ( scenario_exists($dh->get_scename) ) {
        $execution->smartdie ("ERROR, scenario " . $dh->get_scename . " already created\n") if ( !$opts{M} && !defined($ref_vms) )
    }

    # If -M option or ref_vms specified, the scenario must be already created
    unless ( scenario_exists($dh->get_scename) ) {
        $execution->smartdie ("ERROR, scenario " . $dh->get_scename . " not created\n") if ( $opts{M} || defined($ref_vms) )
    }

    # Build the whole bridge based network topology only if -M or ref_vms not specified
    unless ( defined($ref_vms) || $opts{M}) {
        build_topology();
    } else {
    	# We are defining a set of VMs, we create their tun devices if needed
    	create_tun_devices_for_virtual_bridged_networks(\@vm_ordered);
    }

    xauth_add(); # TODO: is this necessary now??

    define_vms(\@vm_ordered);    

}

sub build_topology{

    my $basename = basename $0;
   
    my $logp = "build_topology> ";
    
    # To load tun module if needed
    if (tundevice_needed($dh->get_vmmgmt_type,$dh->get_vm_ordered)) {
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
    chomp (my $now = `LANG=es $command`);
    my $input_file_basename = basename $dh->get_input_file;
    $execution->execute($logp, $bd->get_binaries_path_ref->{"cp"} . " " . $dh->get_input_file . " " . $dh->get_sim_dir);
    $execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " '<'!-- copied by $basename at $now --'>' >> ".$dh->get_sim_dir."/$input_file_basename");       
    $execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " '<'!-- original path: ".abs_path($dh->get_input_file)." --'>' >> ".$dh->get_sim_dir."/$input_file_basename");

    # Copy also the windows configuration file (.cvnx) if it exists
    if ($dh->get_cfg_file()) {
        $execution->execute($logp, $bd->get_binaries_path_ref->{"cp"} . " " . $dh->get_cfg_file() . " " . $dh->get_sim_dir);
    }

    # To make lock file (it exists while scenario is running)
    $execution->execute( $logp, $bd->get_binaries_path_ref->{"touch"} . " " . $dh->get_sim_dir . "/lock");

    if ( $dh->get_vmmgmt_type eq "net" )  {
        # Create the mgmn_net
        my $mgmt_net = $dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("net");
        if (empty($mgmt_net)) { $mgmt_net = $mgmt_net . "-mgmt" };
        my $managed = $dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("managed");

        # If the bridge is not managed (i.e with attribute managed='no') and it 
        # does not exist raise an error
        if ( str($managed) eq 'no' && $mgmt_net ne $mgmt_net . "-mgmt" && ! vnet_exists_br($mgmt_net, 'virtual_bridge') ) {
        	
            $execution->smartdie ("\nERROR: Management bridge $mgmt_net does not exist and it's configured with attribute managed='no'.\n" . 
                                  "       Non-managed bridges are not created/destroyed by VNX. They must exist in advance.")
        }

        unless ( vnet_exists_br($mgmt_net, 'virtual_bridge') || str($managed) eq 'no' ) {
            # If bridged does not exists, we create and set up it
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addbr $mgmt_net");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " stp $mgmt_net off");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $mgmt_net up");      
            
            # Get config host management interface IP address
            my %mng_addr = get_admin_address( 0, '', 'net' );
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " addr add " . 
                                     $mng_addr{'host'}->addr() . "/" . $mng_addr{'vm'}->mask() . " dev $mgmt_net");
                  
        }        
=BEGIN
        if ($> == 0) {
            my $sock = $dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("sock");
            if (empty($sock)) { $sock = ''}
            else              { do_path_expansion($sock) };
            if (-S $sock) {
                wlog (V, "VNX warning: <mgmt_net> socket already exists. Ignoring socket autoconfiguration", $logp);
            } else {
                # Create the socket
                mgmt_sock_create($sock,$dh->get_vmmgmt_autoconfigure,$dh->get_vmmgmt_hostip,$dh->get_vmmgmt_mask);
            }
        } else {
            wlog (V, "VNX warning: <mgmt_net> autoconfigure attribute only is used when VNX parser is invoked by root. Ignoring socket autoconfiguration", $logp);
        }
=END
=cut        
    }

    # 1. To perform configuration for bridged virtual networks (<net mode="virtual_bridge">) and TUN/TAP for management
    #configure_virtual_bridged_networks();
    create_tun_devices_for_virtual_bridged_networks();
    create_bridges_for_virtual_bridged_networks();

    # 2. Host configuration
    host_config();

    # 3. Set appropriate permissions and perform configuration for switched virtual networks and uml_switches creation (<net mode="uml_switch">)
    # DFC 21/2/2011 chown_working_dir;
    configure_switched_networks();
       
    # 4. To link TUN/TAP to the bridges (for bridged virtual networks only, <net mode="virtual_bridge">)
    # moved to mode_start
    #tun_connect();

    # 5. To create fs, hostsfs and run directories
    #create_dirs();
    
}

sub define_vms {
  
    my $ref_vm_ordered = shift;
    my @vm_ordered = @{$ref_vm_ordered};

    my $logp = "define_vms> ";
    
    my $dom;
   
    # UML: If defined screen configuration file, open it
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
   
    my $vm_doc;
   
    for ( my $i = 0; $i < @vm_ordered; $i++) {

        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);
        my $vm_status = get_vm_status($vm_name);

        # Skip this VM if already defined
        unless ($vm_status eq 'undefined') {
        	wlog (N, "\nERROR: virtual machine '$vm_name' already defined (status=$vm_status)\n");
        	next
        }        

        wlog (VVV, "Processing $vm_name", $logp);
      
        create_vm_dirs($vm_name);
        
        # check for existing management ip file stored in run dir
        # update manipdata for current vm accordingly
        if (-f $dh->get_vm_dir($vm_name) . '/mng_ip'){
            $mngt_ip_data = "file";   
        } else {
            $mngt_ip_data = $mngt_ip_counter;
        }
        
        # Create VM XML definition to be passed to vmAPIs define_vm function
        $vm_doc = make_vmAPI_doc($vm, $merged_type, $mngt_ip_data); 
           
        # call the corresponding vmAPI->define_vm
        my $vm_type = $vm->getAttribute("type");
        wlog (N, "Defining virtual machine '$vm_name' of type '$merged_type'...");
        my $error = "VNX::vmAPI_$vm_type"->define_vm($vm_name, $merged_type, $vm_doc);
        if ($error) {
            wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->define_vm returns '" . $error . "'\n$hline");
            wlog (N, "Virtual machine $vm_name cannot be defined.");
            next
        }
        wlog (N, "...OK");
        $mngt_ip_counter++ unless ($mngt_ip_data eq "file"); # update only if current value has been used
        change_vm_status($vm_name,"defined");

     }

     # UML: Close screen configuration file
     if (($opts{e}) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
        close SCREEN_CONF;
     }
}


#
# create_vm_dirs
#
sub create_vm_dirs {

    my $vm_name = shift;
    
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


#
# make_vmAPI_doc
#
# Creates the vm XML specification (<create_conf> element) passed to   
# to vmAPI-->define_vm and copied to ${vm_name}_conf.xml file 
#
# Arguments:
# - $vm_name, the virtual machine name
# - $mngt_ip_data, passed to get_admin_address
#
# Returns:
# - the XML document in DOM tree format
#
sub make_vmAPI_doc {
    
    my $vm           = shift;
    my $merged_type  = shift;
    my $mngt_ip_data = shift;

    my $doc = $dh->get_doc;
    my $vm_name = $vm->getAttribute("name");
    my $dom = XML::LibXML->createDocument( "1.0", "UTF-8" );
   
    my $create_conf_tag = $dom->createElement('create_conf');
    $dom->addChild($create_conf_tag);

    # Insert random id number
    my $fileid_tag = $dom->createElement('id');
    $create_conf_tag->addChild($fileid_tag);
    my $fileid = $vm_name . "-" . generate_random_string(6);
    $fileid_tag->addChild( $dom->createTextNode($fileid) );

    # Create vm tag
    my $vm_tag = $dom->createElement('vm');
    $create_conf_tag->addChild($vm_tag);

    # Set all VM attributes
    # name attribute
    my $vm_order = $dh->get_vm_order($vm_name);
    $vm_tag->setAttribute( name => $vm_name );

    # type, subtype and os attributes
    my @type = $dh->get_vm_type($vm);
    $vm_tag->setAttribute( type => $type[0] );
    $vm_tag->setAttribute( subtype => $type[2] );
    $vm_tag->setAttribute( os => $type[2] );

    # exec mode attribute      
    my $exec_mode   = $dh->get_vm_exec_mode($vm);
    $vm_tag->setAttribute( exec_mode => $exec_mode );

    # arch attribute (default i686)
    my $arch = $vm->getAttribute("arch");
    if (empty($arch)) { $arch = 'i686' }
    $vm_tag->setAttribute( arch => $arch );
 
    # vcpu attribute (default 1 cpu)      
    my $vcpu = $vm->getAttribute("vcpu");
    if (empty($vcpu)) { $vcpu = '1' }
    $vm_tag->setAttribute( vcpu => $vcpu );
 
    # To get filesystem and type
    my $filesystem;
    my $filesystem_type;
    my @filesystem_list = $vm->getElementsByTagName("filesystem");

    # filesystem tag in dom tree        
    my $fs_tag = $dom->createElement('filesystem');
    $vm_tag->addChild($fs_tag);

    if (@filesystem_list == 1) {
        $filesystem = get_abs_path(text_tag($vm->getElementsByTagName("filesystem")->item(0)));
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

    # shareddir tags
    if ($type[0] eq 'lxc') {
	    foreach my $shared_dir ($vm->getElementsByTagName("shareddir")) {
	        my $root    = $shared_dir->getAttribute("root");
	        my $options = $shared_dir->getAttribute("options");
	        my $shared_dir_value = text_tag($shared_dir);
	        my $shared_dir_tag = $dom->createElement('shareddir');
	        $vm_tag->addChild($shared_dir_tag);
	        $shared_dir_tag->addChild($dom->createTextNode($shared_dir_value));
	        $shared_dir_tag->addChild($dom->createAttribute( root => $root));
	        $shared_dir_tag->addChild($dom->createAttribute( options => $options));         
	    }
    } else {
        wlog (N, "WARNING: <shareddir> tag not supported for VM of type $type[0]");
    }       

    # Memory assignment
    my $mem = $dh->get_default_mem;      
    my @mem_list = $vm->getElementsByTagName("mem");
    if (@mem_list == 1) {
        $mem = text_tag($mem_list[0]);
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

    # video tag
    if( $vm->exists("./video") ){
        my $video_type = $vm->findnodes('./video')->[0]->to_literal();
        my $video_tag = $dom->createElement('video');
        $video_tag->appendTextNode($video_type);
        $vm_tag->addChild($video_tag);
        wlog (VVV,"video type set to $video_type", $logp);
    }
   
    # kernel to be booted (only for UML)
    if ($merged_type eq 'uml') {
	    my $kernel;
	    my @params;
	    my @build_params;
	    my  @kernel_list = $vm->getElementsByTagName("kernel");
	      
	    # kernel tag in dom tree
	    my $kernel_tag = $dom->createElement('kernel');
	    $vm_tag->addChild($kernel_tag);
	    if (@kernel_list == 1) {
	        my $kernel_item = $kernel_list[0];
	        $kernel = do_path_expansion(text_tag($kernel_item));         
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
    }
    
    # conf tag
    my $conf;
    my @conf_list = $vm->getElementsByTagName("conf");
    if (@conf_list == 1) {
        # get config file from the <conf> tag
        $conf = get_abs_path ( text_tag($conf_list[0]) );
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
            my $console_value = text_tag($console);
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
    my $mng_if_value = mng_if_value($vm);
    my $mng_if_tag;
    #$mng_if_tag->addChild( $dom->createAttribute( value => $mng_if_value));      
    # aquí es donde hay que meter las ips de gestion
    # si mng_if es distinto de no, metemos un if id 0
    unless ( ($dh->get_vmmgmt_type eq 'none' ) || ($mng_if_value eq "no") ) {
    #if ( (! $dh->get_vmmgmt_type eq 'none' ) && (! $mng_if_value eq "no" ) || 
    #      $merged_type eq 'libvirt-kvm-android') {  # Note: in android we always create the management interface,
                                                    # even if it is not defined. That is to conserve the if names
                                                    # inside the virtual machine (eth0->mgmt, eth1->id=1, etc).
                                                    # As android does not seem to include a 'udev' similar functionality,
                                                    # that is the only way (we know) to maintain names stable...

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
                    wlog (N, "$hline\nWARNING: no name defined for management if (id=0) of vm $vm_name\n$hline");
                } else { last }
            }
        }

        $mng_if_tag = $dom->createElement('if');
        unless  ($merged_type eq 'libvirt-kvm-android' && $dh->get_vmmgmt_type eq 'net') {
            $vm_tag->addChild($mng_if_tag);
        }            

        my $mac = automac($vm_order, 0);
        $mng_if_tag->addChild( $dom->createAttribute( mac => $mac));

	    # Get management bridge name vm_mgmt is of type='net' (used later)
	    my $mgmt_net;
	    if ( $dh->get_vmmgmt_type eq 'net' ) {
	        $mgmt_net = $dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("net");
	        if (empty($mgmt_net)) { $mgmt_net = $mgmt_net . "-mgmt" };
	    } elsif ( $dh->get_vmmgmt_type eq 'private' ){
	    	$mgmt_net = '';
	    }
        $mng_if_tag->addChild( $dom->createAttribute( net => $mgmt_net));

        if (defined $mgmtIfName) {
            $mng_if_tag->addChild( $dom->createAttribute( name => $mgmtIfName));
        }
 
 #       if ($merged_type eq 'libvirt-kvm-android') {
 #           $mng_if_tag->addChild( $dom->createAttribute( id => 1));
 #       } else {
            $mng_if_tag->addChild( $dom->createAttribute( id => 0));
 #       }
        if ( ($dh->get_vmmgmt_type eq 'private') || 
             ( ($dh->get_vmmgmt_type eq 'net') && ( str($dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("config")) eq 'manual') ) ) {
	        my %mng_addr = get_admin_address( $mngt_ip_data, $vm_name, $dh->get_vmmgmt_type );

	        my $ipv4_tag = $dom->createElement('ipv4');
	        $mng_if_tag->addChild($ipv4_tag);
	        my $mng_mask = $mng_addr{'vm'}->mask();
	        $ipv4_tag->addChild( $dom->createAttribute( mask => $mng_mask));
	        my $mng_ip = $mng_addr{'vm'}->addr();
	        $ipv4_tag->addChild($dom->createTextNode($mng_ip));
        } else { 
        	# mgmt interfaces of type 'net' and autoconfigured with dhcp
            my $ipv4_tag = $dom->createElement('ipv4');
            $mng_if_tag->addChild($ipv4_tag);
            $ipv4_tag->addChild($dom->createTextNode('dhcp'));
        }
      
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
            
                $mac = text_tag($mac_list[0]);
                # expandir mac con ceros a:b:c:d:e:f -> 0a:0b:0c:0d:0e:0f
                $mac =~ s/(^|:)(?=[0-9a-fA-F](?::|$))/${1}0/g;
                $mac = "," . $mac;
             
                #$mac = "," . text_tag($mac_list->item(0));
            }
            else {    #my @group = getgrnam("@TUN_GROUP@");
                $mac = automac($vm_order, $id);
            }
             
            # if tags in dom tree 
            my $if_tag = $dom->createElement('if');

            # Dirty hack to change the order of interfaces for Android when mgmt=none 
            if ( $dh->get_vmmgmt_type eq 'none' && $merged_type eq 'libvirt-kvm-android') {
                my $last_node = $vm_tag->lastChild;
                if ( defined($last_node) && $last_node->nodeName eq 'if') { 
                    $vm_tag->insertBefore( $if_tag, $last_node );
                } else {
                $vm_tag->addChild($if_tag);
                }
            } else {
                $vm_tag->addChild($if_tag);
            }

            $if_tag->addChild( $dom->createAttribute( id => $id));
            $if_tag->addChild( $dom->createAttribute( net => $net));
            $if_tag->addChild( $dom->createAttribute( mac => $mac));
 
            my $name = $if->getAttribute("name");
            unless (empty($name)) { 
                $if_tag->addChild( $dom->createAttribute( name => $name)) 
            }
             
            # To process interface IPv4 addresses
            # The first address has to be assigned without "add" to avoid creating subinterfaces
            if ($dh->is_ipv4_enabled) {
                foreach my $ipv4 ($if->getElementsByTagName("ipv4")) {
    
                    my $ip = text_tag($ipv4);
                    my $ipv4_effective_mask = "255.255.255.0"; # Default mask value        
                    if (valid_ipv4_with_mask($ip)) {
                        # Implicit slashed mask in the address
                        $ip =~ /.(\d+)$/;
                        $ipv4_effective_mask = slashed_to_dotted_mask($1);
                        # The IP need to be chomped of the mask suffix
                        $ip =~ /^(\d+).(\d+).(\d+).(\d+).*$/;
                        $ip = "$1.$2.$3.$4";
                    }
                    elsif ($ip ne 'dhcp') { 
                        # Check the value of the mask attribute
                        my $ipv4_mask_attr = $ipv4->getAttribute("mask");
                        if (str($ipv4_mask_attr) ne "") {
                            # Slashed or dotted?
                            if (valid_dotted_mask($ipv4_mask_attr)) {
                                $ipv4_effective_mask = $ipv4_mask_attr;
                            }
                            else {
                                $ipv4_mask_attr =~ /.(\d+)$/;
                                $ipv4_effective_mask = slashed_to_dotted_mask($1);
                            }
                        } else {
                            wlog (N, "$hline\nWARNING (vm=$vm_name): no mask defined for $ip address of interface $id. Using default mask ($ipv4_effective_mask)\n$hline");
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
                   my $ip = text_tag($ipv6);
                   if (valid_ipv6_with_mask($ip)) {
                      # Implicit slashed mask in the address
                      $ipv6_tag->addChild($dom->createTextNode($ip));
                   }
                   else {
                      # Check the value of the mask attribute
                      my $ipv6_effective_mask = "/64"; # Default mask value        
                      my $ipv6_mask_attr = $ipv6->getAttribute("mask");
                      if ( ! empty($ipv6_mask_attr) ) {
                         # Note that, in the case of IPv6, mask are always slashed
                         $ipv6_effective_mask = $ipv6_mask_attr;
                      }
                      $ipv6_tag->addChild($dom->createTextNode("$ip$ipv6_effective_mask"));
                    }          
                }
             }
        }
    }

    # For Android, mgmt interface must be the last one in case of type 'net'
    if (defined($mng_if_tag) && $merged_type eq 'libvirt-kvm-android' && $dh->get_vmmgmt_type eq 'net') {
            $vm_tag->addChild($mng_if_tag);
    }            
     
    # ip routes 
    my @route_list = $dh->merge_route($vm);
    foreach my $route (@route_list) {
        
        my $route_dest = text_tag($route);
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
    
=BEGIN      
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
=END
=cut

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
    # Ex:   <ssh_key>~/.ssh/id_dsa.pub</ssh_key>
#pak ($vm_name);
#print $doc->toString(1);
    if( $doc->exists("/vnx/global/ssh_key") ){
#pak ($vm_name . " ssh_key found");
        my @ssh_key_list = $doc->findnodes('/vnx/global/ssh_key');
        my $ftree_num = $vm_plugin_ftrees+$vm_ftrees+1;
        wlog (VVV,"ssh ftree_num=$ftree_num");
        my $ssh_key_dir = $dh->get_vm_tmp_dir($vm_name) . "/on_boot/filetree/$ftree_num";
        $execution->execute($logp,  "mkdir -p $ssh_key_dir"); # or $execution->smartdie ("cannot create directory $ssh_key_dir for storing ssh keys");
        # Copy ssh key files content to $ssh_key_dir/ssh_keys file
        foreach my $ssh_key (@ssh_key_list) {
            wlog (V, "<ssh_key> file: $ssh_key");
            my $key_file = do_path_expansion( text_tag( $ssh_key ) );
            wlog (V, "<ssh_key> file: $key_file");
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"cat"}
                                 . " $key_file >>" . $ssh_key_dir . "/ssh_keys" );
            # Add the original <ssh> tags to VM xml
            my $new_ssh_key = $ssh_key->cloneNode;
            $new_ssh_key->appendTextNode($key_file);
            $vm_tag->addChild($new_ssh_key);
        }
        
        # Add a <filetree> to copy ssh keys
        my $ftree_tag = XML::LibXML::Element->new('filetree');
        $ftree_tag->setAttribute( seq => "on_boot");
        $ftree_tag->setAttribute( root => "/tmp/" );
        $ftree_tag->appendTextNode ("ssh_keys");            
        $vm_tag->addChild($ftree_tag);
        # And a <exec> command to add it to authorized_keys file in VM
        my $exec_tag = XML::LibXML::Element->new('exec');
        $exec_tag->setAttribute( seq => "on_boot");
        $exec_tag->setAttribute( type => "verbatim" );
        $exec_tag->setAttribute( ostype => "system" );
        $exec_tag->appendTextNode ("mkdir -p /root/.ssh; cat /tmp/ssh_keys >> /root/.ssh/authorized_keys; rm /tmp/ssh_keys");            
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
                my $group = text_tag( $group_list->item($k) );
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
                  do_path_expansion( text_tag( $key_list->item($k) ) );
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"cat"}
                      . " $keyfile >> $sdisk_content"
                      . "keyring_$username" );
            }
        }
=END
=cut
  
    # Save XML document to .vnx/scenarios/<scenario_name>/vms/$vm_name_conf.xml
    my $vm_doc = $dom->toString(1);
    wlog (VVV, $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_conf.xmlfile\n' . $dom->toString(1), $logp);
    open XML_CCFILE, ">" . $dh->get_vm_dir($vm_name) . '/' . $vm_name . '_conf.xml'
        or $execution->smartdie("can not open " . $dh->get_vm_dir . '/' . $vm_name . '_conf.xml' )
        unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
    print XML_CCFILE "$vm_doc\n";
    close XML_CCFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

    #return $vm_doc;
    return $dom;
}


#
# ------------------------------------------------------------------------------
#                           U N D E F I N E   M O D E
# ------------------------------------------------------------------------------
#
# Undefines VMs by calling vmAPI->undefine_vm function (only if they are in defined state) 
# and releases network topology (only when -M is not used) 
#
# Arguments:
#   - $ref_vm:  reference to an array with the list of VMs to work on. If not specified,
#               it works with all the VMs in scenario or the ones specified in -M option
#               if used. 
#
sub mode_undefine{

    my $ref_vms = shift;
    my @vm_ordered;
    if ( defined($ref_vms) ) {
        # List of VMs to use passed as parameter
        @vm_ordered = @{$ref_vms};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @vm_ordered = $dh->get_vm_to_use_ordered;    
    }

    my $logp = "mode_undefine> ";
    wlog (VVV, "Undefining " . get_vmnames(\@vm_ordered), $logp);

    # If scenario does not exist --> error
    #unless ( scenario_exists($dh->get_scename) ) {
    #    $execution->smartdie ("ERROR, scenario " . $dh->get_scename . " not started\n");
    #}

    my $undef_error; 	   
    for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);
        my $vm_status = get_vm_status($vm_name);

        # Raise an error if the VM is not in defined state
        unless ($vm_status eq 'defined') {
            if ($vm_status eq 'undefined') {
                wlog (N, "$hline\nWARNING: virtual machine '$vm_name' already in undefined state\n$hline")
            } else {
                wlog (N, "$hline\nERROR: virtual machine '$vm_name' running (status=$vm_status). Shutdown it before undefining.\n$hline");
                $undef_error = 'true';
                next;
            }
        }        
           
        # call the corresponding vmAPI
        my $vm_type = $vm->getAttribute("type");
        wlog (N, "Undefining virtual machine '$vm_name' of type '$merged_type'...");
        my $error = "VNX::vmAPI_$vm_type"->undefine_vm($vm_name, $merged_type);
        if ($error) {
            wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->undefine_vm returns '" . $error . "'\n$hline");
            if ($error eq "VM $vm_name does not exist" || 
                $error =~ /207-unable to delete VM/ ) {
                change_vm_status($vm_name,"undefined");
            } else {
                wlog (N, "Virtual machine $vm_name cannot be undefined.");
            }
            next
        }
        wlog (N, "...OK");
        
        destroy_vm_interfaces ($vm);                 
        
        change_vm_status($vm_name,"undefined");        
    }
    
    # Delete all supporting scenario files and bridge based network topology, 
    # but only if -M option or ref_vms not specified and no error found when undefining VMs
    unless ( defined($undef_error) || defined($ref_vms) || $opts{M}) {

        # Unmount all under vms mnt directories, just in case...
        $execution->execute($logp, $bd->get_binaries_path_ref->{"umount"} . " " . $dh->get_sim_dir . "/vms/*/mnt");

        # Delete all files in scenario but the scenario map (<scename>.png or svg) 
        #$execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_sim_dir . "/*");
        $execution->execute($logp, $bd->get_binaries_path_ref->{"find"} . " " . $dh->get_sim_dir . "/* " . 
                             "! -name '*.png' ! -name '*.svg' -delete");

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

        destroy_topology();
    }
    
}

#
# destroy_vm_interfaces
#
sub destroy_vm_interfaces {
    
    my $vm = shift;
    
    my $logp = "destroy_vm_interfaces> ";
    
    my $vm_name = $vm->getAttribute("name");
    my $vm_type = $vm->getAttribute("type");
    my $merged_type = $dh->get_vm_merged_type($vm);
            
    wlog (VVV, "vm $vm_name of type $vm_type", $logp);

    # To throw away and remove management device (id 0), if neeed
    my $mng_if_value = mng_if_value($vm);
          
    #if ( ($dh->get_vmmgmt_type eq 'private') && ($mng_if_value ne "no") && ($vm_type ne 'lxc')) {
    #if ( ($dh->get_vmmgmt_type eq 'private') && ($mng_if_value ne "no") && $merged_type ne 'libvirt-kvm-android') {
    if ( ( $dh->get_vmmgmt_type eq 'private' && $mng_if_value ne "no" ) || 
         ( $dh->get_vmmgmt_type eq 'net' && $mng_if_value ne "no" && $merged_type eq 'libvirt-kvm-android') ) {
        my $tun_if = $vm_name . "-e0";
        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $tun_if down");
        #$execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -d $tun_if -f " . $dh->get_tun_device);
        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link del $tun_if ");
    }

    # If VM of type android, destroy the bridgre created for its management interface
    if ( $merged_type eq 'libvirt-kvm-android' &&  $dh->get_vmmgmt_type eq 'private')  {
       $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set ${vm_name}-mgmt down");
       $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " delbr ${vm_name}-mgmt");
    }

    # To get interfaces list
    foreach my $if ($vm->getElementsByTagName("if")) {
    
        # To get attributes
        my $id = $if->getAttribute("id");
        my $net_name = $if->getAttribute("net");
        my $net_mode = $dh->get_net_mode($net_name);
        my $net_if = $vm_name . "-e" . $id;

        wlog (VVV, "if with id=$id connected to net=$net_name ($net_mode)", $logp);
                    
        # Dettach if from bridge
        if ( $net_mode eq "virtual_bridge" ){
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " delif $net_name $net_if");
        } elsif ($net_mode eq "openvswitch"){
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " del-port $net_name $net_if");
        }
        
        # Destroy TUN/TAP interfaces
        #if ( ( ($net_name eq "virtual_bridge") or ($net_name eq "openvswitch") ) && ($vm_type ne 'lxc') ) {
        if ( ($net_mode eq "virtual_bridge") or ($net_mode eq "openvswitch") ) {
            # TUN device name
            my $tun_if = $vm_name . "-e" . $id;
            # To throw away TUN device
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $tun_if down");
            # To remove TUN device
            #$execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -d $tun_if -f " . $dh->get_tun_device);
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link del $tun_if ");
        } 
    }
    
}


sub destroy_topology {

    my $logp = "destroy_topology> ";
     
    # Destroy full topology

    # 2. Remove xauth data
    xauth_remove();

    # 3a. To remote TUN/TAPs devices (for uml_switched networks, <net mode="uml_switch">)
    tun_destroy_switched();
  
    # 3b. To destroy TUN/TAPs devices (for bridged_networks, <net mode="virtual_bridge/openvswitch">)
    tun_destroy();

    # 4. To restore host configuration
    host_unconfig();

    # 5. To remove external interfaces
    external_if_remove();

    # 6. To remove bridges
    bridges_destroy();

    # If the VM management interfaces are of type 'net', destroy the virtual bridge that supports it (if managed)
    if ($dh->get_vmmgmt_type eq "net") {
	    my $mgmt_net = $dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("net");
	    if (empty($mgmt_net)) { $mgmt_net = $mgmt_net . "-mgmt" };
	    my $managed = $dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("managed");
	
	    unless ( str($managed) eq 'no' ) {
	        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $mgmt_net down");
	        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " delbr $mgmt_net");
	    }        
    }      
    
=BEGIN
    if (($dh->get_vmmgmt_type eq "net") && ($dh->get_vmmgmt_autoconfigure ne "")) {
        if ($> == 0) {
            my $sock = $dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("sock");
            if (empty($sock)) { $sock = ''} 
            else              { $sock = do_path_expansion($sock) };
            if (-S $sock) {
                # Destroy the socket
                mgmt_sock_destroy($sock,$dh->get_vmmgmt_autoconfigure);
            }
        }
        else {
            wlog (N, "VNX warning: <mgmt_net> autoconfigure attribute only is used when VNX parser is invoked by root. Ignoring socket autodestruction");
        }
    }
=END
=cut    

    # If <host_mapping> is in use and not in debug mode, process /etc/hosts
    host_mapping_unpatch ($dh->get_scename, "/etc/hosts") if (($dh->get_host_mapping) && ($execution->get_exe_mode() != $EXE_DEBUG));

    # To remove lock file (it exists while topology is running)
    $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_sim_dir . "/lock");

}

#
# ------------------------------------------------------------------------------
#                           S T A R T   M O D E
# ------------------------------------------------------------------------------
#
# 1 - Starts VMs by calling start_vms,
# 2 - Calls tun_connect to connect VM tuntap interfaces to the bridges (only for the types 
#     of VMS that need it -not for LXC or libvirt-)  
# 3 - Calls set_vlan_link to do some VLAN related tasks 
# 4 - Calls mode_execute to execute 'on_boot' commands
# 5 - Modifies /etc/hosts if <host_mapping> tag is active
# 6 - Print consoles info
#
# Arguments:
#   - $ref_vm:  reference to an array with the list of VMs to work on. If not specified,
#               it works with all the VMs in scenario or the ones specified in -M option
#               if used. 
#
sub mode_start {

    my $ref_vms = shift;
    my @vm_ordered;
    if ( defined($ref_vms) ) {
        # List of VMs to use passed as parameter
        @vm_ordered = @{$ref_vms};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @vm_ordered = $dh->get_vm_to_use_ordered;    
    }

    my $logp = "mode_start> ";
    wlog (VVV, "Starting " . get_vmnames(\@vm_ordered), $logp);

    # If scenario does not exist --> error
    unless ( scenario_exists($dh->get_scename) ) {
        $execution->smartdie ("ERROR, scenario " . $dh->get_scename . " not started\n");
    }

    # Check whether the virtual network topology (bridges and interfaces) is created
    # and if not, rebuild it. It could be the case that the host has been rebooted 
    # with an scenario defined or running, and the bridges and interfaces have been
    # lost after reboot. 
    if (! is_topology_running() ) {
        # Recreate topology
        wlog (V, "Virtual network not created. Restarting topology.", $logp);
        build_topology();
    }

    @vm_ordered = start_vms(\@vm_ordered);
        
    # Configure network related aspects
    tun_connect(\@vm_ordered);
    set_vlan_links(\@vm_ordered);
        
    # Execute 'on_boot' commands
    mode_execute ('on_boot', 'lxc,dynamips', \@vm_ordered);

    if ( !defined($ref_vms) && $dh->get_doc->exists("/vnx/host/exec[\@seq='on_boot']") ) {
        wlog (N, "Calling execute_host_cmd with seq 'on_boot'"); 
        execute_host_command('on_boot');
    }
            
    # If <host_mapping> is in use and not in debug mode, process /etc/hosts
    my $lines = join "\n", @host_lines;
    host_mapping_patch ($dh->get_scename, "/etc/hosts") 
        if (($dh->get_host_mapping) && ($execution->get_exe_mode() != $EXE_DEBUG)); # lines in the temp file

    # UML: If -B, block until ready
    if ($opts{B}) {
        my $time_0 = time();
        my %vm_ips = get_UML_command_ip("");
        while (!UMLs_cmd_ready(%vm_ips)) {
            #system($bd->get_binaries_path_ref->{"sleep"} . " $dh->get_delay");
            sleep($dh->get_delay);
            my $time_w = time();
            my $interval = $time_w - $time_0;
            wlog (N,  "$interval seconds elapsed...");
            %vm_ips = get_UML_command_ip("");
        }
    }
        
    my $scename = $dh->get_scename;
   	wlog (N,"\n" . $hline);
    wlog (N,  " Scenario \"$scename\" started");
    # Print information about vm consoles
    print_consoles_info();
}

#
# is_topology_running()
#
# Returns:
#  - 'true' if all the bridges of the scenario are running 
#  - undef if any bridge is not created
#
sub is_topology_running {
	
	my $logp = "is_topology_running> ";
    my @nets;
    my $doc = $dh->get_doc;
    @nets = $doc->getElementsByTagName("net");   
      
    foreach my $net (@nets) {
        my $net_name    = $net->getAttribute("name");
        my $mode        = $net->getAttribute("mode");
        if ( vnet_exists_br($net_name, $mode) ) {
        	 next 
        } else {
        	wlog (VVV, "Bridge $net_name not created", $logp);
        	return; 
        }	
    }
    return 'true';
}


#
# start_vms
#
# Starts all virtual machines specified in array list pointed by ref_vm_ordered
# by calling vmAPI-->start_vm, configures the IP management interface.
# It waits a time between VMs startup if intervm-delay option specified
# 
sub start_vms {

    my $ref_vm_ordered = shift;
    my @vm_ordered = @{$ref_vm_ordered};
    
    my @vm_failed; 

    my $logp = "start_vms> ";
 
    # Get management bridge name vm_mgmt is of type='net' (used later)
    my $mgmt_net;
    if ( $dh->get_vmmgmt_type eq 'net' ) {
        $mgmt_net = $dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("net");
        if (empty($mgmt_net)) { $mgmt_net = $mgmt_net . "-mgmt" };
    }
  
    # Check whether Network-manager is installed and running
    my $nm_running = 0;
    my $nmcli;
    if ( $nmcli = `which nmcli` ) {
        chomp ($nmcli);
        my $cmd = "LANG=en " . $nmcli . " nm status | grep 'not running'"; 
        $nm_running = system($cmd);
        if ($nm_running) {
            wlog (V, "Network manager is running ($nm_running)", $logp);
        } else {
            wlog (V, "Network manager is NOT running ($nm_running)", $logp);
        }
    }     

    # Start the VMs specified
    for ( my $i = 0; $i < @vm_ordered; $i++) {

        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");
        my $merged_type = $dh->get_vm_merged_type($vm);
        my $vm_status = get_vm_status($vm_name);
      
        # Do not start the VM if -M is not used and the VM has a tag <on_boot> with value 'no'
        unless ($opts{M}) {
	        my $on_boot; 
	        eval {$on_boot = $vm->getElementsByTagName("on_boot")->item(0)->getFirstChild->getData};
	        if ( (defined $on_boot) and ($on_boot eq 'no')) {
	            next;
	        }
        }
      
        #check for option -n||--no-console (do not start consoles)
        my $no_console = "0";
        if ($opts{'no-console'}){
            $no_console = "1";
        }

        # Raise an error if the VM is not in defined state
        unless ($vm_status eq 'defined') {
        	if ($vm_status eq 'undefined') {
                wlog (N, "\nERROR: virtual machine $vm_name is 'undefined'; use --define mode to define it before\n" .
                           "       or --create to define and start it.\n");
        	} elsif ($vm_status eq 'running') {
        		wlog (N, "\nERROR: virtual machine $vm_name already in 'running' state.\n");
            } elsif ($vm_status eq 'suspended') {
                wlog (N, "\nERROR: virtual machine $vm_name in 'suspended' state, use --resume mode to start it.\n");
            } elsif ($vm_status eq 'hibernated') {
                wlog (N, "\nERROR: virtual machine $vm_name in 'hibernated' state, use --restore mode to start it.\n");
            }
            push (@vm_failed, $vm);
            next;
        }        

        # call the vmAPI-->start_vm function
        wlog (N, "Starting virtual machine '$vm_name' of type '$merged_type'...");
        my $error = "VNX::vmAPI_$vm_type"->start_vm($vm_name, $merged_type, $no_console);
        if ($error) {
            wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->start_vm returns '" . $error . "'\n$hline");
            next;
        }
        wlog (N, "...OK");
        change_vm_status($vm_name,"running");
        
        my $mng_if_value = mng_if_value( $vm );
        # Configure management device (id 0), if needed
        #if ( $dh->get_vmmgmt_type eq 'private' && $mng_if_value ne "no" ) {
        if ( $dh->get_vmmgmt_type ne 'none' && $mng_if_value ne "no" ) {

change_to_root();

            if ( $dh->get_vmmgmt_type eq 'net' ) {
            	# Join the management interface to the management bridge
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addif $mgmt_net $vm_name-e0");
            }

            $execution->execute($logp, $bd->get_binaries_path_ref->{"ip"} . " link set dev $vm_name-e0 up");

            # If Network manager is running, we have to release the management interface from being managed by NM. 
            # If not, the managemente IP address assigned dissapears after some seconds (why?)  
            if ($nm_running) {
            	# This line does not work in Ubuntu 14.04
                # my $con_uuid = `nmcli -t -f UUID,DEVICES con status | grep ${vm_name}-e0 | awk 'BEGIN {FS=\":\"} {print \$1}' `;
                my $con_uuid = `LANG=C nmcli dev list iface ${vm_name}-e0 | grep "CONNECTIONS.AVAILABLE-CONNECTIONS" | awk '{print \$2}'`;
                chomp ($con_uuid);
                wlog (V, "con_uuid='$con_uuid'", $logp);
                $execution->execute($logp, $nmcli . " con delete uuid $con_uuid" ) if (!empty($con_uuid));
            }
            # Disable IPv6 autoconfiguration in interface
            $execution->execute($logp, "sysctl -w net.ipv6.conf.${vm_name}-e0.autoconf=0" );
    
            # Configure management IP address
            unless ($dh->get_vmmgmt_type eq 'net') {
	            # As the VM has necessarily been previously defined, the management ip address must be 
	            # already specified in file (get_admin_address has been called from make_vmAPI_doc ) 
	            my %net = get_admin_address( 'file', $vm_name );
	            #$execution->execute($logp,  $bd->get_binaries_path_ref->{"ifconfig"}
	            #    . " $vm_name-e0 " . $net{'host'}->addr() . " netmask " . $net{'host'}->mask() . " up" );
	            my $ip_addr = NetAddr::IP->new($net{'host'}->addr(),$net{'host'}->mask());
	            if ($merged_type  eq 'libvirt-kvm-android') {
	                $execution->execute($logp, $bd->get_binaries_path_ref->{"ip"} . " addr add " . $ip_addr->cidr() . " dev ${vm_name}-mgmt");
	            } else {
	                $execution->execute($logp, $bd->get_binaries_path_ref->{"ip"} . " addr add " . $ip_addr->cidr() . " dev $vm_name-e0");
	            }
            }   
back_to_user();               
        }

        # Disable IPv6 autoconfiguration on host VM interfaces and, if 
        # Network manager is running, prevent it from managing the interfaces.
change_to_root();
        foreach my $if ($vm->getElementsByTagName("if")) {
            my $id = $if->getAttribute("id");
            # Ignore management interface (treated above)
            if ($id eq 0) { next }

            # Disable IPv6 autoconfiguration in interface
            $execution->execute($logp, "sysctl -w net.ipv6.conf.${vm_name}-e${id}.autoconf=0" );

            # Prevent Network manager (if running) from managing VM interfaces
            if ($nm_running) {
                my $con_uuid = `nmcli -t -f UUID,DEVICES con status | grep ${vm_name}-e${id} | awk 'BEGIN {FS=\":\"} {print \$1}' `;
                chomp ($con_uuid);
                wlog (VVV, "con_uuid='$con_uuid'", $logp);
                $execution->execute($logp, $nmcli . " con delete uuid $con_uuid" ) if (!empty($con_uuid));
            }
back_to_user();               
        }
          
        if ( (defined $opts{'intervm-delay'})    # delay has been specified in command line and... 
            && ( $i < @vm_ordered-2 ) ) { # ...it is not the last virtual machine started...
            for ( my $count = $opts{'intervm-delay'}; $count > 0; --$count ) {
                printf "-- Option 'intervm-delay' specified: waiting $count seconds...\n";
                sleep 1;
                print "\e[A";
            }
        }
    }

    # Remove not started VMs from the $vm_ordered list to avoid further processing    
    for my $vm_failed (@vm_failed) {
        for ( my $i = 0; $i < @vm_ordered; $i++) {
            my $vm = $vm_ordered[$i];
            if ( $vm_failed->getAttribute("name") eq $vm->getAttribute("name") ) {
                splice @vm_ordered, $i, 1; # Remove the VM 
            }	
        }
    }
    return @vm_ordered;  # 
}

#
# set_vlan_links
#
# Configure VLANs for the list of VMs specified in $ref_vm_ordered
#
sub set_vlan_links {
    
    my $ref_vm_ordered = shift;
    my @vm_ordered = @{$ref_vm_ordered};

    my $first_time='yes';

    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");

        foreach my $if ($vm->getElementsByTagName("if")){
        	# Activate network links when openvswitch are used
        	if(get_net_by_mode($if->getAttribute("net"),"openvswitch") != 0 && ($first_time eq 'yes')){
                    $first_time='no';
            }
            if ( (get_net_by_mode($if->getAttribute("net"),"openvswitch") != 0)&& $if->getElementsByTagName("vlan")) {
                my $if_id = $if->getAttribute("id");
                my @vlan=$if->getElementsByTagName("vlan");
                my $vlantag= $vlan[0];  
                my $trunk = str($vlantag->getAttribute("trunk"));
                my $port_name="$vm_name"."-e"."$if_id";
                my $vlan_tag_list="";
                my $vlan_number=0;
                foreach my $tag ($vlantag->getElementsByTagName("tag")){
                    my $tag_id=$tag->getAttribute("id");
                    $vlan_tag_list.="$tag_id".",";
                    $vlan_number=$vlan_number+1;    
                }
                $vlan_tag_list =~ s/,$//;  # eliminate final ","
                        
                if ($trunk eq 'yes'){
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set port $port_name "."trunk=$vlan_tag_list");
                } else {
                    if($vlan_number eq 1){
                        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set port $port_name "."tag=$vlan_tag_list");
                    } else {  
                        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set port $port_name "."trunk=$vlan_tag_list");
                    }
                }
            }
        }
    }
    my $doc = $dh->get_doc;
    foreach my $net ($doc->getElementsByTagName("net")) {
        if ($net->getElementsByTagName("connection")){
            foreach my $connection ($doc->getElementsByTagName("connection")) {
                my $port=$connection->getAttribute("name");
                if ($connection->getElementsByTagName("vlan")){
                    my @vlan=$connection->getElementsByTagName("vlan");
                    my $vlan_tag= $vlan[0];
                    my $vlan_tag_list="";
                    foreach my $tag ($vlan_tag->getElementsByTagName("tag")){
                        my $tag_id=$tag->getAttribute("id");
                        $vlan_tag_list.="$tag_id".",";
                    }
                    $vlan_tag_list =~ s/,$//;  # eliminate final ","
                    
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set port $port"."1-0"." trunk=$vlan_tag_list");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set port $port"."0-1"." trunk=$vlan_tag_list");
                }
            }
        }
   				
    }
}


#
# ------------------------------------------------------------------------------
#                         S H U T D O W N   M O D E
# ------------------------------------------------------------------------------
#
# Calls vmAPI-->shutdown_vm function for every VM specified in $ref_vms list. Executes 
# 'on_shutdown' commands in VMs if specified in mode parameter
# 
# Arguments:
#   - $mode:    defines shutdown mode 
#               values: 'do_exe_cmds' -> normal shutdown executing 'on_shutdown' commands  
#                       'do_not_exe_cmds' -> normal shutdown without executing 'on_shutdown' cmds  
#                       'kill' -> power-off  
#   - $ref_vm:  reference to an array with the list of VMs to work on. If not specified,
#               it works with all the VMs in scenario or the ones specified in -M option
#               if used. 
#
sub mode_shutdown {

    my $mode = shift;   # Indicates if 'on_shutdown' commands has to be executed or not
    my $ref_vms = shift;
    my @vm_ordered;
    if ( defined($ref_vms) ) {
        # List of VMs to use passed as parameter
        @vm_ordered = @{$ref_vms};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @vm_ordered = $dh->get_vm_to_use_ordered;    
    }
    
    my $kill;
    if ($mode eq 'kill') { $kill=$mode }

    my $logp = "mode_shutdown> ";
    wlog (VVV, "Shutingdown " . get_vmnames(\@vm_ordered) . " (mode=$mode)", $logp);

    # If scenario does not exist --> error
    unless ( scenario_exists($dh->get_scename) ) {
        $execution->smartdie ("ERROR, scenario " . $dh->get_scename . " not started\n");
    }

#    if ($opts{F}) { wlog (VV, "F flag set", $logp) } 
#    else { wlog (VV, "F flag NOT set", $logp) }

    # Execute on_shutdown commands
    if ($mode eq 'do_exe_cmds' ) {
        mode_execute ('on_shutdown', 'all')
    }

    for ( my $i = 0; $i < @vm_ordered; $i++) {

        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");
        my $merged_type = $dh->get_vm_merged_type($vm);
        my $vm_status = get_vm_status($vm_name);

        # Raise an error if the VM is not in 'running', 'suspended' or 'hibernated' state. 
        unless ( defined($kill) || ($vm_status eq 'running' || $vm_status eq 'suspended' || $vm_status eq 'hibernated') ){
            wlog (N, "\nERROR: cannot shutdown a virtual machine '$vm_name' not in 'running', 'suspended' or 'hibernated' state (status=$vm_status).\n");
            next;
        }        

        # Call the vmAPI-->shutdown_vm function
        if (defined($kill)){
            wlog (N, "Powering off virtual machine '$vm_name' of type '$merged_type'...");
        } else {
            wlog (N, "Shutting down virtual machine '$vm_name' of type '$merged_type'...");
        }
        my $error = "VNX::vmAPI_$vm_type"->shutdown_vm($vm_name, $merged_type, $kill);
        if ($error) {
            wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->shutdown_vm returns '" . $error . "'\n$hline");
            if ($error eq "VM $vm_name does not exist") {
            	change_vm_status($vm_name,"defined");
            } else {
                wlog (N, "Virtual machine $vm_name cannot be shutdown.");
            }
            next
        }
        wlog (N, "...OK");
        change_vm_status($vm_name,"defined");
    }
    
    if ( !defined($ref_vms) && $dh->get_doc->exists("/vnx/host/exec[\@seq='on_shutdown']") ) {
        wlog (N, "Calling execute_host_cmd with seq 'on_shutdown'"); 
        execute_host_command('on_shutdown');
    }
    
   
=BEGIN   
    # UML specific
    # For non-forced mode, we have to wait all UMLs dead before to destroy 
    # TUN/TAP (next step) due to these devices are yet in use
    #
    # Note that -B doensn't affect to this functionallity. UML extinction
    # blocks can't be avoided (is needed to perform bridges and interfaces
    # release)
    my $time_0 = time();
      
    if ((!$opts{kill})&&($execution->get_exe_mode() != $EXE_DEBUG)) {      

        wlog (N, "---------- Waiting until virtual machines extinction ----------");

        my $only_vm = "";  # TODO: probably does not work...revise if UML maintained
        while (my $pids = VM_alive($only_vm)) {
            wlog (N,  "waiting on processes $pids...");;
            #system($bd->get_binaries_path_ref->{"sleep"} . " $dh->get_delay");
            sleep($dh->get_delay);
            my $time_f = time();
            my $interval = $time_f - $time_0;
            wlog (N, "$interval seconds elapsed...");;
        }       
    }
=END
=cut    
    
}

=BEGIN
#
# ------------------------------------------------------------------------------
#                           D E S T R O Y   M O D E
# ------------------------------------------------------------------------------
#
# Arguments:
#   - $ref_vm:  reference to an array with the list of VMs to work on. If not specified,
#               it works with all the VMs in scenario or the ones specified in -M option
#               if used. 
#
sub mode_destroy {
   
    my $ref_vms = shift;
    my @vm_ordered;
    if ( defined($ref_vms) ) {
        # List of VMs to use passed as parameter
        @vm_ordered = @{$ref_vms};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @vm_ordered = $dh->get_vm_to_use_ordered;    
    }

    my $logp = "mode_destroy> ";
    wlog (VVV, "Destroying " . get_vmnames(\@vm_ordered), $logp);

    # If scenario does not exist --> error
    #unless ( scenario_exists($dh->get_scename) ) {
    #    $execution->smartdie ("ERROR, scenario " . $dh->get_scename . " not started\n");
    #}
   
    for ( my $i = 0; $i < @vm_ordered; $i++) {

        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");
        my $merged_type = $dh->get_vm_merged_type($vm);
        my $vm_status = get_vm_status($vm_name);

        # Raise an error if the VM is 'undefined'
        if ( $vm_status eq 'undefined' ){
            #wlog (N, "\nWARNING: virtual machine '$vm_name' is already 'undefined'\n");
            next;
        }        

        # call the corresponding vmAPI
        wlog (N, "Destroying virtual machine '$vm_name' of type '$merged_type'...");
        my $error = "VNX::vmAPI_$vm_type"->destroy_vm($vm_name, $merged_type);
        if ( ($error) && ($error ne "VM $vm_name does not exist") ) {
            wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->destroy_vm returns '" . $error . "'\n$hline");
            next;
        }
        wlog (N, "...OK");
        change_vm_status($vm_name,"defined");
                 
    }
    if ( defined($ref_vms) ) {
        mode_undefine(\@vm_ordered)
    } else {
    	mode_undefine()
    }    
}
=END
=cut


#
# ------------------------------------------------------------------------------
#                           M O D I F Y   M O D E
# ------------------------------------------------------------------------------
#
sub mode_modify {

    my $mod_file=shift;
    my $vnx_dir=shift;

    my $logp = "mode_modify> ";
    
    my $scename = $dh->get_scename;
    
    wlog (V, "scenario=$scename, mod_file=$mod_file", $logp);
    
    # Check whether scenario is started and running
    
    #unless ( -f $vnx_dir . "/scenarios/" . $scename . "/lock") {
    unless ( -f $dh->get_sim_dir($scename) . "/lock") {
        vnx_die ("scenario $scename not running; cannot modify");
    }
    
    my $scen_xml = "${vnx_dir}/scenarios/${scename}/${scename}.xml";
    my $doc = $dh->get_doc;

    my $parser = XML::LibXML->new();
    my $mod_doc = $parser->parse_file($mod_file);
    wlog (VVV, "XML Modifications document:\n" . $mod_doc->toString());
   
	my @operations = $mod_doc->getDocumentElement()->nonBlankChildNodes();
	foreach my $operation (@operations){
	   my $opName = $operation->nodeName;
	   if($opName eq "add_net"){
	       modify_add_net($doc, $operation);
	   }
       if($opName eq "del_net"){
           modify_del_net($doc, $operation);
       }
       if($opName eq "up_net"){
           modify_updown_net($doc, $operation, 'up');
       }
       if($opName eq "down_net"){
           modify_updown_net($doc, $operation, 'down');
       }
	   if($opName eq "add_vm"){ 
	       modify_add_vm($doc, $operation);
	   }
       if($opName eq "del_vm"){
           modify_del_vm($doc, $operation);
       }
	   if($opName eq "vm"){
	       my $vmName = $operation->getAttribute('name');
	       print "<$opName $vmName>:\n";
	       #$nodeVNX=modifyVMElement($nodeVNX, $operation);
	       print "\n";
	   }
	   if($opName eq "modify_vm"){
	       print "<$opName>:\n";
	       #$nodeVNX=modifyVMAttributes($nodeVNX, $operation);
	       print "\n";
	   }
	   #add other operations here
	}

    #wlog (VVV, "Scenario $scename XML specification after modifications:\n" . $doc->toString(2));
    # Save scenario to $vnx_dir/scenario/$scename
    #$scen_xml="/tmp/" . $scename . ".xml"; # BORRAR
    $doc->toFile($scen_xml);
    # Pretty print XML specification
    my $tidy_obj = XML::Tidy->new('filename' => "$scen_xml");
    $tidy_obj->tidy();
    $tidy_obj->write();    
    
    # Regenerate scenario map if already generated
    if ( -f "$vnx_dir/scenarios/${scename}/${scename}.png" ) {
        wlog (VVV, "regenerating png scenario map.", $logp);
        mode_showmap ('png', 'no'); 
    } elsif ( -f "$vnx_dir/scenarios/${scename}/${scename}.svg" ) {
        wlog (VVV, "regenerating svg scenario map.", $logp);
        mode_showmap ('svg', 'no'); 
    }
    
}

sub modify_add_net {

  my($doc, $add_net) = @_;
  my $logp = "modify_add_net> ";

  my $net_name = $add_net->getAttribute('name');
  if( $doc->exists("/vnx/net[\@name='$net_name']") ){
      print "\nERROR: cannot add net $net_name to scenario " . $dh->get_scename . " (a net $net_name already exists)\n";
  } else {
      wlog (N, "Adding $net_name to scenario " . $dh->get_scename . ".", $logp);
      
      # Add net to specification  
      $add_net->setNodeName('net');
      my @nets = $doc->findnodes('/vnx/net');
      $doc->getDocumentElement()->insertAfter($add_net, $nets[$#nets]);

      # Add new Net
      @nets = ($add_net);
      create_bridges_for_virtual_bridged_networks(\@nets);
      
  }
}

sub modify_del_net {

    my($doc, $del_net) = @_;
    my $logp = "modify_del_net> ";

    my $net_name = $del_net->getAttribute('name');
    
    if( ! $doc->exists("/vnx/net[\@name='$net_name']") ){
        print "\nERROR: cannot del net $net_name from scenario " . $dh->get_scename . " (no network named $net_name exists)\n";
    } else {
              
        my @nets = $doc->findnodes("/vnx/net[\@name='$net_name']");
        my $del = $del_net->getAttribute('del');
        wlog (N, "Deleting $net_name from scenario " . $dh->get_scename . " (del=$del).", $logp);
        
        if($del eq "no"){
            if( $doc->exists("/vnx/vm/if[\@net='$net_name']") || $doc->exists("/vnx/host/hostif[\@net='$net_name']") ){
                print "\nERROR: cannot del net $net_name in scenario " . $dh->get_scename . " (a VM is still connected to $net_name)\n";
            } else {
                # Delete Net
                bridges_destroy(\@nets);
                # Remove net from XML doc
                $doc->getDocumentElement->removeChild($nets[0]);
            }

        } elsif ($del eq "if"){
            my $bool = $doc->exists("/vnx/vm/if[\@net='$net_name']");
            if($bool == 1){
                my @ifs = $doc->findnodes("/vnx/vm/if[\@net='$net_name']");
                foreach my $if (@ifs){
                    my $if_parent = $if->parentNode;
                    my $parent_name = $if_parent->getAttribute('name');
                    my $if_id = $if->getAttribute('id'); 
                    $if_parent->removeChild($if);
                    print "IF id=$if_id that connects to $net_name in vm $parent_name is eliminated.\n";
                }     
            }
            my $bool_hostif = $doc->exists("/vnx/host/hostif[\@net='$net_name']");
            if ($bool_hostif == 1){
                my @hosts = $doc->findnodes("/vnx/host");
                my @hostifs = $doc->findnodes("/vnx/host/hostif[\@net='$net_name']");
                $hosts[0]->removeChild($hostifs[0]);
                print "The hostif connected to the net $net_name is eliminated\n";
            } 
            my @nets = $doc->findnodes("/vnx/net[\@name='$net_name']");
            $doc->getDocumentElement->removeChild($nets[0]);
            print "The net $net_name is deleted successfully.\n";

        } elsif ($del eq "vm"){
            if( $doc->exists("/vnx/vm/if[\@net='$net_name']") ){
            	# Some VMs connected to net, we shutdown/destroy them
                my @ifs = $doc->findnodes("/vnx/vm/if[\@net='$net_name']");
                my @del_vms;
                foreach my $if (@ifs){
                	my $vm = $if->parentNode;
                    my $vm_name = $vm->getAttribute('name');
                    my $if_id = $if->getAttribute('id'); 
                    wlog (VVV, "Interface $if_id of VM $vm_name connected to $net_name.", $logp);
                    push (@del_vms, $vm);
                }     
                    
                my $mode = $del_net->getAttribute('mode');
                if ( $mode eq 'shutdown' ) {
                    wlog (N, "Shutting-down VMs " . get_vmnames(\@del_vms,',') ." from scenario " . $dh->get_scename . ".", $logp);
                    mode_shutdown('do_exe_cmds', \@del_vms);
                } 
                elsif ( $mode eq 'destroy' ) {
                    wlog (N, "Destroying VM " . get_vmnames(\@del_vms,',') . " from scenario " . $dh->get_scename . ".", $logp);
                    mode_shutdown('kill', \@del_vms);
                    mode_undefine(\@del_vms);
                } 
                else {
                    wlog (N, "\nERROR: unknown mode ($mode) in <del_vm> tag.", $logp);
                }

                # Delete VMs from XML doc
                foreach my $vm (@del_vms) {                    
                    $doc->getDocumentElement->removeChild($vm);
                }
            }

            # Host interfaces TBC            
            #my $bool_hostif = $doc->exists("/vnx/host/hostif[\@net='$net_name']");
            #if ($bool_hostif == 1){
            #    my @hosts = $doc->findnodes("/vnx/host");
            #    $doc->getDocumentElement->removeChild($hosts[0]);
            #    print "host connected the net $net_name is eliminated\n";
            #} 
 
            # Delete Net
            bridges_destroy(\@nets);
            # Remove net from XML doc
            $doc->getDocumentElement->removeChild($nets[0]);
        }
      
  }
}

sub modify_updown_net {

    my($doc, $add_net, $cmd) = @_;
    my $logp = "modify_updown_net> ";

    my $net_name = $add_net->getAttribute('name');
    if( ! $doc->exists("/vnx/net[\@name='$net_name']") ){
        print "\nERROR: cannot modify net $net_name status. Net does not exist in scenario " . $dh->get_scename . ".\n";
    } else {
        wlog (N, "Changing status of net $net_name to $cmd.", $logp);

        # Change net status
        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set dev $net_name " . $cmd);
      
      
  }
}


sub modify_add_vm {

    my($doc, $add_vm) = @_;
    my $logp = "modify_add_vm> ";

    my $vm_name = $add_vm->getAttribute('name');
  
    # Check Add the new vm if it isn't existed
    if($doc->exists("/vnx/vm[\@name='$vm_name']")){
        print "\nERROR: cannot add VM $vm_name to scenario " . $dh->get_scename . " (vm $vm_name already exists)\n";
    } else {
    	wlog (N, "Adding $vm_name to scenario " . $dh->get_scename . ".", $logp); 
  	
        # Add VM to specification  	
        $add_vm->setNodeName('vm');
        my @vms = $doc->findnodes('/vnx/vm');
        $doc->getDocumentElement()->insertAfter($add_vm, $vms[$#vms]);

        # Add new VM
        @vms = ($add_vm);
        create_tun_devices_for_virtual_bridged_networks(\@vms);
        mode_define(\@vms);               
        mode_start(\@vms);               
    }     
}

sub modify_del_vm {

    my($doc, $del_vm) = @_;
    my $logp = "modify_del_net> ";

    my $vm_name = $del_vm->getAttribute('name');
    if( ! $doc->exists("/vnx/vm[\@name='$vm_name']") ) {
        print "\nERROR: cannot del VM $vm_name from scenario " . $dh->get_scename . " (VM does not exists)\n";
    } else {
        my $mode = $del_vm->getAttribute('mode');
        wlog (N, "Deleting VM $vm_name from scenario " . $dh->get_scename . ".", $logp);
        my @del_vms = $doc->findnodes("/vnx/vm[\@name='$vm_name']");
        
        if ( $mode eq 'shutdown' ) {
            mode_shutdown('do_exe_cmds', \@del_vms);
        } 
        elsif ( $mode eq 'destroy' ) {
            mode_shutdown('kill', \@del_vms);
            mode_undefine(\@del_vms);
        } 
        else {
            wlog (N, "\nERROR: unknown mode ($mode) in <del_vm> tag.", $logp);
        }

        # Remove VM from XML doc
        $doc->getDocumentElement->removeChild($del_vms[0]);

    }
}

#
# ------------------------------------------------------------------------------
#                           S U S P E N D   M O D E
# ------------------------------------------------------------------------------
#
sub mode_suspend {

   my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process having into account -M option   
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
    
      my $vm = $vm_ordered[$i];
      my $vm_name = $vm->getAttribute("name");
      my $merged_type = $dh->get_vm_merged_type($vm);
      
      if ($exemode != $EXE_DEBUG) {
            $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
                unless scenario_exists($dh->get_scename);
      }

      # call the corresponding vmAPI
      my $vm_type = $vm->getAttribute("type");
      wlog (N, "Suspending virtual machine '$vm_name' of type '$merged_type'...");
      my $error = "VNX::vmAPI_$vm_type"->suspend_vm($vm_name, $merged_type);
      if ($error) {
          wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->suspend_vm returns '" . $error . "'\n$hline");
          next
      }
      wlog (N, "...OK");
      change_vm_status($vm_name,"suspended");
   }
}

#
# ------------------------------------------------------------------------------
#                           R E S U M E   M O D E
# ------------------------------------------------------------------------------
#
sub mode_resume {

   my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process having into account -M option   
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
    
      my $vm = $vm_ordered[$i];
      my $vm_name = $vm->getAttribute("name");
      my $merged_type = $dh->get_vm_merged_type($vm);
 
      if ($exemode != $EXE_DEBUG) {
         $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
         unless scenario_exists($dh->get_scename);
      }
 
      # call the corresponding vmAPI
      my $vm_type = $vm->getAttribute("type");
      wlog (N, "Resuming virtual machine '$vm_name' of type '$merged_type'...");
      my $error = "VNX::vmAPI_$vm_type"->resume_vm($vm_name, $merged_type);
      if ($error) {
          wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->resume_vm returns '" . $error . "'\n$hline");
          next
      }
      wlog (N, "...OK");
      change_vm_status($vm_name,"running");
   }
}


#
# ------------------------------------------------------------------------------
#                           S A V E   M O D E
# ------------------------------------------------------------------------------
#
sub mode_save {

   my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process having into account -M option   
   my $filename;

   for ( my $i = 0; $i < @vm_ordered; $i++) {
    
      my $vm = $vm_ordered[$i];
      my $vm_name = $vm->getAttribute("name");
      my $merged_type = $dh->get_vm_merged_type($vm);
      $filename = $dh->get_vm_dir($vm_name) . "/" . $vm_name . "_savefile";

      if ($exemode != $EXE_DEBUG) {
          $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
             unless scenario_exists($dh->get_scename);
      }

      # call the corresponding vmAPI
      my $vm_type = $vm->getAttribute("type");
      wlog (N, "Pausing virtual machine '$vm_name' of type '$merged_type' and saving state to disk...");
      my $error = "VNX::vmAPI_$vm_type"->save_vm($vm_name, $merged_type, $filename);
      if ($error) {
        wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->save_vm returns '" . $error . "'\n$hline");
        next
      }
      wlog (N, "...OK");
      change_vm_status($vm_name,"hibernated");
   }
}

#
# ------------------------------------------------------------------------------
#                           R E S T O R E   M O D E
# ------------------------------------------------------------------------------
#
sub mode_restore {

    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process having into account -M option   
    my $filename;

    if ($exemode != $EXE_DEBUG) {
        $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
            unless scenario_exists($dh->get_scename);
    }
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
    
      my $vm = $vm_ordered[$i];
      # To get name attribute
      my $vm_name = $vm->getAttribute("name");
      my $merged_type = $dh->get_vm_merged_type($vm);
      $filename = $dh->get_vm_dir($vm_name) . "/" . $vm_name . "_savefile";

      # call the corresponding vmAPI
      my $vm_type = $vm->getAttribute("type");
      wlog (N, "Restoring virtual machine '$vm_name' of type '$merged_type' state from disk...");
      my $error = "VNX::vmAPI_$vm_type"->restore_vm($vm_name, $merged_type, $filename);
      if ($error) {
          wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->restore_vm returns '" . $error . "'\n$hline");
          next
      }
      wlog (N, "...OK");
      change_vm_status($vm_name,"running");
   }
}

#
# ------------------------------------------------------------------------------
#                           R E S E T   M O D E
# ------------------------------------------------------------------------------
#
sub mode_reset {
	
    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process having into account -M option   
   
    if ($exemode != $EXE_DEBUG) {
        $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
            unless scenario_exists($dh->get_scename);
    }
   
    for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);
        # call the corresponding vmAPI
        my $vm_type = $vm->getAttribute("type");
        wlog (N, "Reseting virtual machine '$vm_name' of type '$merged_type'...");
        my $error = "VNX::vmAPI_$vm_type"->reset_vm($vm_name, $merged_type);
        if ($error) {
            wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->reset_vm returns '" . $error . "'\n$hline");
            next
        }
        wlog (N, "...OK");
        change_vm_status($vm_name,"running");
    }
}



#
# ------------------------------------------------------------------------------
#                           S H O W M A P  M O D E
# ------------------------------------------------------------------------------
#
sub mode_showmap {

    # Optional parameters
    my $map_format_par = shift;
    my $show = shift;

   	my $scedir  = $dh->get_sim_dir;
   	my $scename = $dh->get_scename;
   	if (! -d $dh->get_sim_dir ) {
		mkdir $dh->get_sim_dir or $execution->smartdie ("error making directory " . $dh->get_sim_dir . ": $!");
   	}
   	
    my $map_format;
   	if (defined($map_format_par)) {
   		$map_format = $map_format_par;   		
   	} else {
	    # Guess map format (svg and png allowed; defaults to svg)
	    $map_format = $opts{'show-map'};
	    if ($map_format eq '') { $map_format = 'svg' };
	    if ( ($map_format ne 'png') && ($map_format ne 'svg') ) {
	        $execution->smartdie ("ERROR: format $map_format not supported in 'show-map' mode\n");          
	    } 
   	}
    wlog (V, "map_format=$map_format");
   	
	$execution->execute($logp, "vnx2dot ${input_file} > ${scedir}/${scename}.dot");

    if ($map_format eq 'png') {
        
       	$execution->execute($logp, "neato -Tpng -o${scedir}/${scename}.png ${scedir}/${scename}.dot");

        if ( !defined($show) || $show eq 'yes' ) {
	        # Read png_viewer variable from config file to see if the user has 
	        # specified a viewer
	        my $png_viewer = get_conf_value ($vnxConfigFile, 'general', "png_viewer", 'root');
	    	# If not defined use default values
	        if (!defined $png_viewer) { 
	       		my $gnome=`w -sh | grep gnome-session`;
	       		if ($gnome ne "") { $png_viewer="gnome-open" }
	            	         else { $png_viewer="xdg-open" }
	        }
	       	#$execution->execute($logp, "eog ${scedir}/${scename}.png");
	       	wlog (N, "Using '$png_viewer' to show scenario '${scename}' topology map", "host> ");
	        $execution->execute($logp, "$png_viewer ${scedir}/${scename}.png &");
        }       

    } elsif ($map_format eq 'svg') {
        
   	    $execution->execute($logp, "neato -Tsvg -o${scedir}/${scename}.svg ${scedir}/${scename}.dot");

        if ( !defined($show) || $show eq 'yes' ) {
	        # Read svg_viewer variable from config file to see if the user has 
	        # specified a viewer
	        my $svg_viewer = get_conf_value ($vnxConfigFile, 'general', "svg_viewer", 'root');
	    	# If not defined use default values
	        if (!defined $svg_viewer) { 
	       		my $gnome=`w -sh | grep gnome-session`;
	       		if ($gnome ne "") { $svg_viewer="gnome-open" }
	            	         else { $svg_viewer="xdg-open" }
	        }
	       	wlog (N, "Using '$svg_viewer' to show scenario '${scename}' topology map", "host> ");
	        $execution->execute($logp, "$svg_viewer ${scedir}/${scename}.svg &");
        }
    }

}

#
# ------------------------------------------------------------------------------
#                           S H O W S T A T U S   M O D E
# ------------------------------------------------------------------------------
#
sub mode_showstatus {
	
	my $vnx_dir = shift;
	my $type = shift;

    wlog (VVV, "mode_showstatus: mode=$type");
    if ($type eq 'global') {

        if ( system "ls $vnx_dir/scenarios/*/lock > /dev/null 2>&1" ) {
            wlog (N, "\nVNX show-status mode:  No active scenarios found\n$hline");     
        	
        } else {
	        wlog (N, "\nVNX show-status mode:  Scenarios created (lock file found)\n$hline");     
            wlog (N, sprintf (" %-30s %-20s", 'Scenario name', 'Command to get detailed info') );
            wlog (N, sprintf (" %-30s %-20s", '-------------', '---------------------------') );
	            
	        my $res = `ls $vnx_dir/scenarios/`;
	        #print "$res\n";
	        
	        opendir (DIR, "$vnx_dir/scenarios") or vnx_die ($!);
	        my @dir = readdir DIR;
	        foreach my $scen (@dir) {
	            #print "Checking $vnx_dir/scenarios/$scen/lock\n";
	            if (-f "$vnx_dir/scenarios/$scen/lock" ) {
                    wlog (N, sprintf (" %-30s %-20s", $scen, "vnx -s $scen -b --show-status" ) );
	            }
	        }        
	        closedir DIR;
            wlog (N, "$hline\n");
        }
    	
    } else {
        
        my $doc = $dh->get_doc;
        my $scename = $dh->get_scename;

	    if ( -f $dh->get_sim_dir($scename) . "/lock") {
	        wlog (N, "\nVNX show-status mode:  Scenario $scename (running)\n$hline");     
	
	        wlog (N, sprintf (" %-20s %-20s %-14s %-20s", 'VM name', 'Type', 'VNX status', 'Hypervisor status') );
	        wlog (N, sprintf (" %-20s %-20s %-14s %-20s", '-------', '----', '----------', '-----------------') );
	    
	        my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process having into account -M option   
	        for ( my $i = 0; $i < @vm_ordered; $i++) {
	            my $vm = $vm_ordered[$i];
	            my $vm_name = $vm->getAttribute("name");
	            my $vm_type = $vm->getAttribute("type");
	            my $merged_type = $dh->get_vm_merged_type($vm);
	            my $status = get_vm_status($vm_name);
	            
	            my $state;
	            my $hstate;
	            my $error = "VNX::vmAPI_${vm_type}"->get_state_vm($vm_name, \$state, \$hstate);
	            if ($error) {
	                wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->get_state_vm returns '" . $error . "'\n$hline");
	                $hstate = '--';
	            }
	            wlog (N, sprintf (" %-20s %-20s %-14s %-20s", $vm_name, $merged_type, $status, $hstate) );  
	        }
	        wlog (N, "$hline\n");
	    } else {
	        wlog (N, "\nVNX show-status mode:  Scenario $scename not started\n$hline\n");
	    }            
    	
    }

}

#
# ------------------------------------------------------------------------------
#                           E X E I N F O   M O D E
# ------------------------------------------------------------------------------
#
sub mode_exeinfo {
 
    my $doc = $dh->get_doc;
    
    wlog (N, "\nVNX exe-info mode:\n") unless $opts{'b'};     
    
    my @seqs;   # Array to store seqs when -b (brief) format selected

    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process having into account -M option   
    for ( my $i = 0; $i < @vm_ordered; $i++) {
               
        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);
        #unless ($vm_hash{$vm_name}){  next; }
            
        # Get descriptions of user-defines commands
        my %vm_seqs = $dh->get_seqs($vm);      
             
        wlog (N, "VM $vm_name user-defined commands:") unless $opts{'b'};
        wlog (N, $hline) unless $opts{'b'};
        if ( keys(%vm_seqs) > 0) {
            wlog (N, sprintf (" %-24s%s", 'Seq', 'Description') ) unless $opts{'b'};
            wlog (N, sprintf (" %-24s%s", '---', '-----------') ) unless $opts{'b'};
            foreach my $seq ( keys %vm_seqs ) {
                print sprintf (" %-24s", $seq) unless $opts{'b'};
                print format_text($dh->get_seq_desc($seq), 80, 22) unless $opts{'b'};
                push (@seqs, $seq);
            }
        } else {
            wlog (N, "None defined") unless $opts{'b'};
        }
        wlog (N, "") unless $opts{'b'};
             
        # Get descriptions of plugin commands
        foreach my $plugin (@plugins) {
            wlog (N, "VM $vm_name plugin '$plugin' commands") unless $opts{'b'};
            wlog (N, $hline) unless $opts{'b'};
            my %seq_desc = $plugin->getSeqDescriptions($vm_name, '');
            if ( keys(%seq_desc) > 1) {
                wlog (N, sprintf (" %-24s %s", 'Seq', 'Description') ) unless $opts{'b'};
                wlog (N, sprintf (" %-24s %s", '---', '-----------') ) unless $opts{'b'};
		        foreach my $seq ( keys %seq_desc ) {
                    unless ($seq eq '_VMLIST') {
                        my $msg = sprintf (" %-24s %s", $seq, $seq_desc{$seq});
                        wlog (N, $msg) unless $opts{'b'};
                        push (@seqs, $seq);
                    }
                }
            } else {
                wlog (N, "None defined") unless $opts{'b'};
            }
            wlog (N, "") unless $opts{'b'};
        }
        
        #wlog (N, $hline);
    }           

    # Show command sequences defined (<com-seq> tags)
    if ( $doc->exists("/vnx/global/cmd-seq") ) {
        wlog (N, "Global user defined command sequences ") unless $opts{'b'};
        wlog (N, $hline) unless $opts{'b'};
        
=BEGIN        
        wlog (N, sprintf (" %-24s", 'Seq') );
        wlog (N, sprintf (" %-24s", '---') );
        foreach my $cmd_seq ( $doc->findnodes("/vnx/global/cmd-seq") ) {
            my $seq_str = $cmd_seq->getFirstChild->getData;
            my $seq = $cmd_seq->getAttribute("seq");
            wlog (N, sprintf (" %-24s %-12s %-s" , $seq, 'Defined as:',  $seq_str) );
            wlog (N, sprintf (" %-24s %-12s %-s", ''   , 'Expanded as:', cmdseq_expand($seq_str) ) );
            wlog (N, sprintf (" %-24s %-12s %-s", ''   , 'Description:', $dh->get_seq_desc($seq) ) );
        }        
        wlog (N, $hline);
=END
=cut
        foreach my $cmd_seq ( $doc->findnodes("/vnx/global/cmd-seq") ) {
            my $seq_str = $cmd_seq->getFirstChild->getData;
            my $seq = $cmd_seq->getAttribute("seq");

            wlog (N, sprintf ("%-24s", "Seq: $seq") ) unless $opts{'b'};

            wlog (N, sprintf ("  %-12s %-s", 'Defined as:',  $seq_str) ) unless $opts{'b'};
            wlog (N, sprintf ("  %-12s %-s", 'Expanded as:', cmdseq_expand($seq_str) ) ) unless $opts{'b'};
            print sprintf ("  %-12s ", 'Description:') unless $opts{'b'};
            print format_text($dh->get_seq_desc($seq), 80, 12) unless $opts{'b'};
            print "\n" unless $opts{'b'};
            push (@seqs, $seq);
        }        
        #wlog (N, $hline);

    }
    if ($opts{'b'}) { print join(" ", @seqs); }
}

sub format_text {
	my $text = shift;
	my $width = shift;
	my $indent = shift;
	
    my $indent_str = sprintf ("%${indent}s", '');
    return `echo "$text" | fmt -t -w $width | sed '2,100s/^/$indent_str/'`;
}

#
# ------------------------------------------------------------------------------
#                        C L E A N H O S T   M O D E
# ------------------------------------------------------------------------------
#
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

#
# ------------------------------------------------------------------------------
#                           C O N S O L E   M O D E
# ------------------------------------------------------------------------------
#
sub mode_console {
    
    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process having into account -M option   

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


#
# ------------------------------------------------------------------------------
#                     C R E A T E R O O T F S   M O D E
# ------------------------------------------------------------------------------
#
sub mode_createrootfs {

    my $tmp_dir = shift;
    my $vnx_dir = shift;

    my $sdisk_fname;  # shared disk complete file name 
    my $h2vm_port;    # host tcp port used to access the the host-to-VM comms channel 
    my $vm_libirt_xml_hdb;
    my $video_mode;   # Libvirt video mode 
    my $default_video_mode = "cirrus";
    my @allowed_video_types = qw/vga cirrus vmvga xen vbox qxl/;
    my $mem;          # Memory assigned to the virtual machine
    my $default_mem   = "512M";
    my $arch;         # Virtual machine architecture type (32 or 64 bits)
    my $default_arch  = "i686";
    my $vcpu;         # Number of virtual CPUs 
    my $default_vcpu = "1";
 
 
    my $rootfs = $opts{'create-rootfs'};
    my $install_media = $opts{'install-media'};
    
    # Set rootfs type     
    my $rootfs_type;
    if (!$opts{'rootfs-type'} || $opts{'rootfs-type'} eq 'libvirt-kvm' ) {
            # If no type was specified, we set it to the default value
            $rootfs_type = 'libvirt-kvm';   
    } elsif ( $opts{'rootfs-type'} eq 'lxc' ) {
        vnx_die ("'lxc' VM type not supported in --create-rootfs mode.");
    } else {
        vnx_die ("Incorrect type ($opts{'rootfs-type'}) specified for --rootfs-type");
    }

change_to_root();
    unless ( -f $rootfs ) {
        vnx_die ("file $rootfs is not valid\n(it does not exists or it is not a plain file)");
    }
    wlog (VVV, "install-media = $install_media", $logp);
    unless ( $install_media ) {
        vnx_die ("option 'install-media' not defined");
    }
    unless ( $install_media && -f $install_media ) {
        vnx_die ("file $install_media is not valid (perhaps does not exists)");
    }
back_to_user();        
  
    # Set video mode
    if ($opts{'video'}) {
        if ( grep( /^$opts{'video'}$/, @allowed_video_types ) ) {
            $video_mode = $opts{'video'}
        } else {
            vnx_die ("Incorrect video mode ($opts{'video'}). Allowed video_mode values: " . join(", ", @allowed_video_types));        
        }
#        given ($opts{'video'}) {
#            when (@allowed_video_types) { $video_mode = $opts{'video'} }
#            default { vnx_die ("Incorrect video mode ($opts{'video'}). Allowed video_mode values: " . join(", ", @allowed_video_types)); } 
#        }
    } else {
        $video_mode = $default_video_mode;
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

    my $rootfs_name = basename $rootfs;
    $rootfs_name .= "-" . int(rand(10000));

    # Create a temp directory to store everything
    my $base_dir = `mktemp --tmpdir=$tmp_dir -td vnx_create_rootfs.XXXXXX`;
    chomp ($base_dir);
    my $rootfs_fname = `readlink -f $rootfs`; chomp ($rootfs_fname);
    my $cdrom_fname  = `readlink -f $install_media`; chomp ($cdrom_fname);
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
     <video>
       <model type="$video_mode"/>
     </video>
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
    wlog (N, "-- Starting a virtual machine with root filesystem $rootfs");
    system "virsh create $vm_xml_fname"; 
    system "virt-viewer $rootfs_name &"; 
back_to_user();

}

#
# ------------------------------------------------------------------------------
#                    M O D I F Y R O O T F S   M O D E
# ------------------------------------------------------------------------------
#
sub mode_modifyrootfs {

    my $tmp_dir = shift;
    my $vnx_dir = shift;

    my $sdisk_fname; # shared disk complete file name 
    my $h2vm_port;   # host tcp port used to access the the host-to-VM comms channel 
    my $vm_libirt_xml_hdb;
    my $video_mode;   # Libvirt video mode 
    my $default_video_mode = "cirrus";
    my @allowed_video_types = qw/vga cirrus vmvga xen vbox qxl/;
    my $mem;          # Memory assigned to the virtual machine
    my $default_mem   = "512M";
    my $arch;         # Virtual machine architecture type (32 or 64 bits)
    my $default_arch  = "i686";
    my $vcpu;        # Number of virtual CPUs 
    my $default_vcpu = "1";
 
    use constant USE_CDROM_FORMAT => 0;  # 
    
    my $rootfs = $opts{'modify-rootfs'};
    $rootfs =~ s/\/$//; # Drop trailing slash if it exists

change_to_root();
    unless ( -f $rootfs || -d $rootfs ) {
        vnx_die ("file or directory $opts{'modify-rootfs'} is not valid.");
    }
back_to_user();
    
    # Set rootfs type     
    my $rootfs_type;
    if (!$opts{'rootfs-type'}) {
    	# No type specified. Let's try to guess the type... 
    	if (-d $rootfs  && -f $rootfs . "/config" && -d $rootfs . "/rootfs" ) {
    		
    		# Get the rootfs directory pointed by config file 
    		my $lxc_rootfs_config_line = `cat $rootfs/config | grep '^lxc.rootfs'`;
    		chomp ($lxc_rootfs_config_line);
            my @fields = split /=/, $lxc_rootfs_config_line; 
            my $rootfs_dir = $fields[1];
            $rootfs_dir =~ s/^\s//; # Delete leading spaces

            # Check if it exists
            unless (-d $rootfs_dir ) {
                vnx_die ("rootfs directory $rootfs_dir specified in 'lxc.rootfs' line\nof $rootfs/config file does not exist or it is not a directory.");
            } 
            
            # And check if it points to the rootfs directory under $rootfs to avoid stupid errors 
            # when copying or moving LXC images...
            unless ( `stat -c "%d:%i" $rootfs/rootfs` eq `stat -c "%d:%i" $rootfs_dir`) {
                pre_wlog ("$hline\nWARNING!\nlxc.rootfs line in LXC config file:\n" . 
                          "  $lxc_rootfs_config_line\ndoes not point to rootfs subdirectory under the directory specified:\n  $rootfs/rootfs\n$hline");
			    my $answer;
			    unless ($opts{'yes'}) {
			        print ("Do you want to continue (yes/no)? ");
			        $answer = readline(*STDIN);
			    } else {
			        $answer = 'yes'; 
			    }
			    unless ( $answer =~ /^yes/ ) {
			        pre_wlog ("Exiting...\n$hline");
			        exit;
			    }
            }
            $rootfs_type = 'lxc';   
    	} else {
	        # Set it to default value
	        $rootfs_type = 'libvirt-kvm';   
    	}
    } elsif ( $opts{'rootfs-type'} ne 'libvirt-kvm' && $opts{'rootfs-type'} ne 'lxc' ) {
        vnx_die ("Incorrect type ($opts{'rootfs-type'}) specified for --rootfs-type");
    } else {
        $rootfs_type = $opts{'rootfs-type'};   
    }

    # Set video mode
    if ($opts{'video'}) {
        if ( grep( /^$opts{'video'}$/, @allowed_video_types ) ) {
            $video_mode = $opts{'video'}
        } else {
            vnx_die ("Incorrect video mode ($opts{'video'}). Allowed video_mode values: " . join(", ", @allowed_video_types));        
        }
#        given ($opts{'video'}) {
#            when (@allowed_video_types) { $video_mode = $opts{'video'} }
#            default { vnx_die ("Incorrect video mode ($opts{'video'}). Allowed video_mode values: " . join(", ", @allowed_video_types)); } 
#        }
    } else {
        $video_mode = $default_video_mode;
    }
           
    # Set memory value
    if ($opts{'mem'}) {
        $mem = $opts{'mem'};
        pre_wlog ("WARNING: --mem option ignored for LXC VMs") if (!$rootfs_type eq 'lxc');
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
    
    my $rootfs_name = basename $rootfs;
    $rootfs_name .= "-" . int(rand(10000));

    if ( $rootfs_type eq 'lxc' ) {

        pre_wlog ("Modifying LXC rootfs...");
        
        # Check if LXC config file exists
        vnx_die ("ERROR: cannot start LXC VM. Config file (" . $rootfs . "/config) not found." ) unless (-f $rootfs . "/config");
        
        # Generate random id (http://answers.oreilly.com/topic/416-how-to-generate-random-numbers-in-perl/)
        my @chars = ( "A" .. "Z", "a" .. "z", 0 .. 9 );
        my $id = join("", @chars[ map { rand @chars } ( 1 .. 8 ) ]);

        pre_wlog ("...vnx-$id");

        
        my $res = $execution->execute( $logp, "lxc-start -n vnx-$id -f $rootfs/config");
        if ($res) { 
            wlog (N, "$res", $logp)
        }
            
    } elsif ( $rootfs_type eq 'libvirt-kvm' ) {

	    # Create a temp directory to store everything
	    my $base_dir = `mktemp --tmpdir=$tmp_dir -td vnx_modify_rootfs.XXXXXX`;
	    chomp ($base_dir);
	    my $rootfs_fname = `readlink -f $rootfs`; chomp ($rootfs_fname);
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
     <video>
       <model type="$video_mode"/>
     </video>
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
	    wlog (N, "-- Starting a virtual machine with root filesystem $rootfs");
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

}

#
# ------------------------------------------------------------------------------
#                    M O D I F Y R O O T F S   M O D E
# ------------------------------------------------------------------------------
#
sub mode_downloadrootfs {
	
	exec('vnx_download_rootfs');
	
} 


#
# ------------------------------------------------------------------------------
#                         S A V E  S C E N A R I O  M O D E
# ------------------------------------------------------------------------------
#
sub mode_savescenario {
    
    my $vnx_dir = shift;
     
    wlog (N, "\nVNX save-scenario mode:");
    
    my $scen_name = $opts{'scenario'};
    my $scen_dir = "$vnx_dir/scenarios/$scen_name/${scen_name}.xml";
  
    # Steps
    # - Unmount everything under $scen_dir (in LXC, overlay filesystems remain mounted in defined state)
    
    # - Calculate md5sums of the filesystems used, to check in destination machine that they are the same.
    #   Save the md5sum values in a file (which one?)
    
    # - Create a tgz file with all the content under $scen_dir       



    # Ideas: 
    # - pack the rootfs's also 
    
}

#
# ------------------------------------------------------------------------------
#                       R E S T O R E  S C E N A R I O  M O D E
# ------------------------------------------------------------------------------
#
sub mode_restorecenario {
 
    my $doc = $dh->get_doc;
    
    wlog (N, "\nVNX restore-scenario mode:");     

}

#
# ------------------------------------------------------------------------------
#

# 
# configure_switched_networks
#
# To create TUN/TAP device if virtual switched network more (<net mode="uml_switch">)
#
sub configure_switched_networks {

    my $doc = $dh->get_doc;
    my $scename = $dh->get_scename;

	# Create the symbolic link to the management switch
#	if ($dh->get_vmmgmt_type eq 'net') {
#		my $sock = $doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("sock");
#		$execution->execute($logp, $bd->get_binaries_path_ref->{"ln"} . " -s $sock " . $dh->get_networks_dir .
#				"/" . $dh->get_vmmgmt_netname . ".ctl" );
#	}

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
            mode_shutdown('do_exe_cmds');
            $execution->smartdie("$capture_file file already exist. Please remove it manually or specify another capture file in the VNX specification.") 
        }

        my $hub = $net->getAttribute("hub");

        # This function only processes uml_switch networks
        if ($mode eq "uml_switch") {
       	
            # Some case are not supported in the current version
            if ((vnet_exists_sw($net_name)) && (check_net_host_conn($net_name,$dh->get_doc))) {
                wlog (N, "VNX warning: switched network $net_name with connection to host already exits. Ignoring.");
            }
            #if ((!($external_if =~ /^$/))) {
            unless ( empty($external_if) ) {
                wlog (N, "VNX warning: switched network $net_name with external connection to $external_if: not implemented in current version. Ignoring.");
            }
       	
            # If uml_switch does not exists, we create and set up it
            unless (vnet_exists_sw($net_name)) {
                unless (empty($sock)) {
                    $execution->execute($logp, $bd->get_binaries_path_ref->{"ln"} . " -s $sock " . $dh->get_networks_dir . "/$net_name.ctl" );
                } else {
                    my $hub_str = ($hub eq "yes") ? "-hub" : "";
                    my $sock = $dh->get_networks_dir . "/$net_name.ctl";
                    unless (check_net_host_conn($net_name,$dh->get_doc)) {
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
                            $extra = $extra . " -scenario_name $scename $net_name";
                        }
				
                        if (!$command){
                            $execution->execute_bg($bd->get_binaries_path_ref->{"uml_switch"} . " -unix $sock $hub_str $extra", '/dev/null');
                        }
                        else{
                            $execution->execute_bg($command . " -unix $sock $hub_str $extra", '/dev/null');
                        }
					
                        if ($execution->get_exe_mode() != $EXE_DEBUG && !uml_switch_wait($sock, 5)) {
                            mode_shutdown('do_exe_cmds');
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
                            $extra = $extra . " -scenario_name $scename $net_name";
                        }

                        if (!$command){
                            $execution->execute_bg($bd->get_binaries_path_ref->{"uml_switch"} . " -tap $tun_if -unix $sock $hub_str $extra", '/dev/null', $group[2]);
                        }
                        else {
                            $execution->execute_bg($command . " -tap $tun_if -unix $sock $hub_str $extra", '/dev/null', $group[2]);
                        }

                        if ($execution->get_exe_mode() != $EXE_DEBUG && !uml_switch_wait($sock, 5)) {
                            mode_shutdown('do_exe_cmds');
                            $execution->smartdie("uml_switch for $net_name failed to start!");
                        }
                    }
                }
            }

            # We increase interface use counter of the socket
            inc_cter("$net_name.ctl");

                #-------------------------------------
                # VLAN setup, NOT TESTED 
                #-------------------------------------
                #unless ($vlan =~ /^$/ ) {
                #    # configure VLAN on this interface
                #   unless (check_vlan($tun_if,$vlan)) {
                #	    $execution->execute($logp, $bd->get_binaries_path_ref->{"modprobe"} . " 8021q");
                #	   $execution->execute($logp, $bd->get_binaries_path_ref->{"vconfig"} . " add $tun_if $vlan");
                # }
                #    my $tun_vlan_if = $tun_if . ".$vlan";
                #    $execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $tun_vlan_if 0.0.0.0 $dh->get_promisc() up");
                #    # We increase interface use counter
                #    inc_cter($tun_vlan_if);
                #}           

        }
      
    }
}

#
# create_tun_devices_for_virtual_bridged_networks
#
# To create TUN/TAP devices
#
sub create_tun_devices_for_virtual_bridged_networks  {

    # TODO: to considerate "external" atribute when network is "ppp"

    my $ref_vms = shift;
    my @vm_ordered;
    if ( defined($ref_vms) ) {
        # List of VMs to use passed as parameter
        @vm_ordered = @{$ref_vms};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @vm_ordered = $dh->get_vm_to_use_ordered;    
    }

    my $logp = "create_tun_devices_for_virtual_bridged_networks> ";

    my $doc = $dh->get_doc;
    #my @vm_ordered = $dh->get_vm_ordered;

    # 1. Set up tun devices

    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");
        my $merged_type = $dh->get_vm_merged_type($vm);

        # To create management device (id 0), if needed
        # The name of the if is: $vm_name . "-e0"
        my $mng_if_value = mng_if_value($vm);
      
        #if ( ($dh->get_vmmgmt_type eq 'private') && ($mng_if_value ne "no") && ($vm_type ne 'lxc') && $merged_type ne 'libvirt-kvm-android' ) {

        if ( ($mng_if_value ne "no") && 
             ( ($dh->get_vmmgmt_type eq 'private' && $merged_type ne 'libvirt-kvm-android') ||
               ($dh->get_vmmgmt_type eq 'net'     && $merged_type eq 'libvirt-kvm-android') ) &&
             ($vm_type ne 'lxc') && ($vm_type ne 'nsrouter')) {

        #if ( ($dh->get_vmmgmt_type eq 'private') && ($mng_if_value ne "no") && ($vm_type ne 'lxc') ) {
            my $tun_if = $vm_name . "-e0";
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -u " . $execution->get_uid . " -t $tun_if -f " . $dh->get_tun_device);
        }

	    # If VM is of type android, create a bridge its management interface
	    if ( $merged_type  eq 'libvirt-kvm-android' && $dh->get_vmmgmt_type eq 'private' )  {
	        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addbr ${vm_name}-mgmt");
	        $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set ${vm_name}-mgmt up");
	    }

        # To get interfaces list
        foreach my $if ($vm->getElementsByTagName("if")) {

            # We get attribute
            my $id = $if->getAttribute("id");
            my $net = $if->getAttribute("net");

            # Only TUN/TAP for interfaces attached to bridged networks
            # We do not create tap interfaces for libvirt or LXC VMs. It is done by libvirt/LXC
            if ( ($vm_type ne 'libvirt') && ($vm_type ne 'lxc') && ($vm_type ne 'nsrouter') && ( get_net_by_mode($net,"virtual_bridge") != 0 ) ) {

                # We build TUN device name
                my $tun_if = $vm_name . "-e" . $id;

                # To create TUN device
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -u " . $execution->get_uid . " -t $tun_if -f " . $dh->get_tun_device);

                # To set up device
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set dev $tun_if up");
            }
        }
    }
}

#
# create_bridges_for_virtual_bridged_networks
#
# Create and configure virtual bridges for virtual_bridge and openvswitch based networks
#
sub create_bridges_for_virtual_bridged_networks  {
   
    my $ref_nets = shift;
    my @nets;
    my $doc = $dh->get_doc;
    if ( defined($ref_nets) ) {
        # List of nets to use passed as parameter
        @nets = @{$ref_nets};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @nets = $doc->getElementsByTagName("net");    
    }
      
    # Create bridges and join interfaces
    foreach my $net (@nets) {

        # We get name attribute
        my $net_name    = $net->getAttribute("name");
        my $mode        = $net->getAttribute("mode");
        my $external_if = $net->getAttribute("external");
        my $vlan        = $net->getAttribute("vlan");
        my $managed     = $net->getAttribute("managed");

        my $ovs_exists = vnet_exists_br($net_name, 'openvswitch');
        my $vb_exists  = vnet_exists_br($net_name, 'virtual_bridge');
        
        wlog (VVV, "vnet_exists_br($net_name, 'openvswitch') returns '" . $ovs_exists, $logp);
        wlog (VVV, "vnet_exists_br($net_name, 'virtual_bridge') returns '" . $vb_exists, $logp);

        if ( $ovs_exists && $mode eq 'virtual_bridge' ) {
            $execution->smartdie ("\nERROR: Cannot create virtual bridge $net_name. An Openvswitch with the same name already exists.")
        } elsif ( $vb_exists && $mode eq 'openvswitch' ) {
            $execution->smartdie ("\nERROR: Cannot create an Openvswitch with name $net_name. A virtual bridge with the same name already exists.")
        }
        
        # If the bridge is non-managed (i.e with attribute managed='no') and it 
        # does not exist raise an error
        if ( str($managed) eq 'no' && ! vnet_exists_br($net_name, $mode) ) {
        	$execution->smartdie ("\nERROR: Bridge $net_name does not exist and it's configured with attribute managed='no'.\n" . 
        	                      "       Non-managed bridges are not created/destroyed by VNX. They must exist in advance.")
        }
        
        unless ( vnet_exists_br($net_name, $mode) || str($managed) eq 'no' ) {
            if ($mode eq "virtual_bridge") {
                # If bridged does not exists, we create and set up it
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addbr $net_name");
                if ($dh->get_stp) {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " stp $net_name on");
                }else {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " stp $net_name off");
                }

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
                if ($mode eq "virtual_bridge") {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addif $net_name $brtap_name");
                } elsif ($mode eq "openvswitch") {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-port $net_name $brtap_name");
                }
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $brtap_name up");
                
                # Disable IPv6 autoconfiguration in bridge
                $execution->execute($logp, "sysctl -w net.ipv6.conf.${brtap_name}.autoconf=0" );

            } elsif ($mode eq "openvswitch") {
                # If bridged does not exists, we create and set up it
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-br $net_name");
                if($net->getAttribute("controller") ){
                    my $controller = $net->getAttribute("controller");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set-controller $net_name $controller");
                }
                if($net->getAttribute("of_version") ){
                    my $of_version = $net->getAttribute("of_version");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " set bridge $net_name protocols=$of_version");
                }
        
            }
                        
            # Bring the bridge up
            #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $net_name 0.0.0.0 " . $dh->get_promisc . " up");
            $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $net_name up");      
            
            # Disable IPv6 autoconfiguration in bridge
            $execution->execute($logp, "sysctl -w net.ipv6.conf.${net_name}.autoconf=0" );
        }
        
        # Is there an external interface associated with the network?
        unless (empty($external_if)) {
            # If there is an external interface associate, to check if VLAN is being used
            unless (empty($vlan) ) {
                # If there is not any configured VLAN at this interface, we have to enable it
                unless (check_vlan($external_if,"*")) {
                    #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $external_if 0.0.0.0 " . $dh->get_promisc . " up");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $external_if up");
                }
                # If VLAN is already configured at this interface, we haven't to configure it
                unless (check_vlan($external_if,$vlan)) {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"modprobe"} . " 8021q");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"vconfig"} . " set_name_type DEV_PLUS_VID_NO_PAD");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"vconfig"} . " add $external_if $vlan");
                }
                $external_if .= ".$vlan";
                #$external_if .= ":$vlan";
            }
         
            # If the interface is already added to the bridge, we haven't to add it
            # Carlos modifications(añadido parametro de entrada mode)
            my @if_list = vnet_ifs($net_name,$mode);
            wlog (VVV, "vnet_ifs returns @if_list", $logp);
            $_ = "@if_list";
            unless (/\b($external_if)\b/) {
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set $external_if up");
                #$execution->execute($logp, $bd->get_binaries_path_ref->{"ifconfig"} . " $external_if 0.0.0.0 " . $dh->get_promisc . " up");
                #Carlos modifications
                if ($mode eq "virtual_bridge") {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"brctl"} . " addif $net_name $external_if");
                } elsif ($mode eq "openvswitch") {
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ovs-vsctl"} . " add-port $net_name $external_if");
                }
            }
            # We increase interface use counter
            inc_cter($external_if);
        }
    }

    # Wait until all the openvswitches are created, then establish all the declared links between those switches
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


#
# tun_connect
#
# To link TUN/TAP to the bridges
#
# Connect VM tuntap interfaces to the bridges (only for the types 
# of VMS that need it -not for LXC or libvirt-)
# 
sub tun_connect {

    my $ref_vm_ordered = shift;
    my @vm_ordered = @{$ref_vm_ordered};

    my $logp = "tun_connect> ";

    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");

        wlog (VVV, "Procesing $vm_name", $logp);

        # To process list
      	foreach my $if ($vm->getElementsByTagName("if")) {

            my $id = $if->getAttribute("id");
            my $net = $if->getAttribute("net");
	 
            # Only TUN/TAP for interfaces attached to bridged networks
            # We do not add tap interfaces for libvirt or lxc VMs. It is done by libvirt/lxc 
            if ( ($vm_type ne 'libvirt') && ($vm_type ne 'lxc') && ( get_net_by_mode($net,"virtual_bridge") != 0)  || 
                 (($vm_type eq 'lxc') && get_net_by_mode($net,"openvswitch") != 0) ) {
                # If condition explained for dummies like me: 
                #     if    (vm is neither libvirt nor lxc and switch is virtual_bridge) 
                #        or (vm is lxc and switch is openvswitch) then
	 
                my $net_if = $vm_name . "-e" . $id;

                # We link TUN/TAP device 
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
        my $route_dest = text_tag($route);;
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

        foreach my $ipv4 ($if->getElementsByTagName("ipv4")) {
            my $ip = text_tag($ipv4);
            my $ipv4_effective_mask = "255.255.255.0"; # Default mask value
            my $ip_addr;       
            if (valid_ipv4_with_mask($ip)) {
                # Implicit slashed mask in the address
                $ip_addr = NetAddr::IP->new($ip);
            } else {
                # Check the value of the mask attribute
                my $ipv4_mask_attr = $ipv4->getAttribute("mask");
                if ($ipv4_mask_attr ne "") {
                    # Slashed or dotted?
                    if (valid_dotted_mask($ipv4_mask_attr)) {
                        $ipv4_effective_mask = $ipv4_mask_attr;
                    } else {
                        $ipv4_mask_attr =~ /.(\d+)$/;
                        $ipv4_effective_mask = slashed_to_dotted_mask($1);
                    }
                } elsif ($ip ne 'dhcp') { 
                    wlog (N, "$hline\nWARNING: no mask defined for $ip address of host interface. Using default mask ($ipv4_effective_mask)\n$hline");
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
            my $ip = text_tag($ipv6);
            if (valid_ipv6_with_mask($ip)) {
                # Implicit slashed mask in the address
                $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " addr $cmd $ip dev $net");
            } else {
                # Check the value of the mask attribute
                my $ipv6_effective_mask = "/64"; # Default mask value          
                my $ipv6_mask_attr = $ipv6->getAttribute("mask");
                if ( !empty($ipv6_mask_attr) ) {
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

	foreach my $vm ($dh->get_doc->getElementsByTagName("vm")) {
	   my @console_list = $dh->merge_console($vm);
	   foreach my $console (@console_list) {
          if (text_tag($console) eq 'xterm') {
		     return 1;
		  }
	   }
	}
	return 0;
}

######################################################
# Give the effective user xauth privileges on the current display
sub xauth_add {
	if ($> == 0 && $execution->get_uid != 0 && xauth_needed) {
		$execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " add `" .
			 $bd->get_binaries_path_ref->{"xauth"} . " list $ENV{DISPLAY}` | su -s /bin/sh -c " .
			 $bd->get_binaries_path_ref->{"xauth"} . " " . getpwuid($execution->get_uid));
	}
}

# Remove the effective user xauth privileges on the current display
sub xauth_remove {
	if ($> == 0 && $execution->get_uid != 0 && xauth_needed) {

		$execution->execute($logp, "su -s /bin/sh -c '" . $bd->get_binaries_path_ref->{"xauth"} . " remove $ENV{DISPLAY}' " . getpwuid($execution->get_uid));
	}

}

#
# cmdseq_expand
#
# Given a comma separated 'seq' value list, it looks iteratively for <cmd-seq> tags 
# that match the values on that list and substitute them for the seq values defined 
# <cmd-seq> tags. 
#
sub cmdseq_expand {
	
    my $seq_str  = shift; # comma separated 'seq' values

    my $doc = $dh->get_doc;

    my @seqs = split /,/, $seq_str; 
    foreach my $seq (@seqs) {

	    if( $doc->exists("/vnx/global/cmd-seq[\@seq='$seq']") ){
	        my @cmd_seq = $doc->findnodes("/vnx/global/cmd-seq[\@seq='$seq']");
	        my $new_seq = $cmd_seq[0]->getFirstChild->getData;
	        wlog (VVV, "<cmd_seq> found for seq '$seq'; substituting by '$new_seq'", $logp);
	        my $new_seq_expanded = cmdseq_expand ($new_seq);
	        $seq_str =~ s/$seq/$new_seq_expanded/;
	    }

    }
    return $seq_str;
}

#
# ------------------------------------------------------------------------------
#                           E X E C U T E   M O D E
# ------------------------------------------------------------------------------
#
# exec commands mode
#
# Arguments:
#   - $seq_str: comma separated list of command tags
#   - $type:    restrict command execution to virtual machines of type $type. Use 'all'
#               for no restriction. 
#   - $ref_vm:  reference to an array with the list of VMs to work on. If not specified,
#               it works with all the VMs in scenario or the ones specified in -M option
#               if used. 
#
sub mode_execute {

    my $seq_str  = shift;
    my $type = shift;

    my $ref_vms = shift;
    my @vm_ordered;
    if ( defined($ref_vms) ) {
        # List of VMs to use passed as parameter
        @vm_ordered = @{$ref_vms};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @vm_ordered = $dh->get_vm_to_use_ordered;    
    }

    if ($exemode != $EXE_DEBUG) {
        $execution->smartdie ("cannot execute commands '$seq_str'; scenario " . $dh->get_scename . " is not started\n")
            unless scenario_exists($dh->get_scename);
    }

    my $doc = $dh->get_doc;

    my $seq_str_expanded = cmdseq_expand ($seq_str);
    wlog (V, "Command sequence '$seq_str' expanded to '$seq_str_expanded'", $logp);

    # $seq_str_expanded is a comma separated list of command tags
    my @seqs = split /,/, $seq_str_expanded; 

    foreach my $seq (@seqs) {

        #print "**** $seq\n";    	
		my %vm_ips;
		
	    my $num_plugin_ftrees = 0;
	    my $num_plugin_execs  = 0;
	    my $num_ftrees = 0;
        my $num_execs  = 0;
        my $num_host_execs = 0;
	
	   	# If -B, block until ready
	   	if ($opts{B}) {
	      	my $time_0 = time();
	      	%vm_ips = get_UML_command_ip($seq);
	      	while (!UMLs_cmd_ready(%vm_ips)) {
	         	#system($bd->get_binaries_path_ref->{"sleep"} . " $dh->get_delay");
	         	sleep($dh->get_delay);
	         	my $time_f = time();
	         	my $interval = $time_f - $time_0;
	         	wlog (V, "$interval seconds elapsed...", $logp);
	         	%vm_ips = get_UML_command_ip($seq);
	      	}
	   	} else {
	      	%vm_ips = get_UML_command_ip($seq);
	    	$execution->smartdie ("some vm is not ready to exec sequence $seq through net. Wait a while and retry...\n") 
	    		unless UMLs_cmd_ready(%vm_ips);
	   	}
	   
		# First loop: 
		for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
			my $vm = $vm_ordered[$i];
			my $vm_name = $vm->getAttribute("name");
	        my $merged_type = $dh->get_vm_merged_type($vm);
	        my $vm_type = $vm->getAttribute("type");
	
	        # If parameter $type is different from 'all', only execute commands for the 
	        # VM types indicated by $type
            if ( $type ne 'all')  {
				next unless ($type =~ /(^${vm_type},)|(,${vm_type},)|(,${vm_type}$)/);
            }
	
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
	            wlog (N, "Calling execute_cmd for vm '$vm_name' with seq '$seq'..."); 
	            wlog (VVV, "   plugin_filetrees=$vm_plugin_ftrees, plugin_execs=$vm_plugin_execs, user-defined_filetrees=$vm_ftrees, user-defined_execs=$vm_execs", $logp);
				# call the corresponding vmAPI
		    	my $error = "VNX::vmAPI_$vm_type"->execute_cmd(
		    	                         $vm_name, $merged_type, $seq, $vm,  
		    	                         \@plugin_ftree_list, \@plugin_exec_list, 
		    	                         \@ftree_list, \@exec_list);
		        if ($error) {
		            wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->execute_cmd returns '" . $error . "'\n$hline");
		        } else {
		            wlog (N, "...OK");
		        }
	            
	        }
		}
	
        if ( $type eq 'all' && !defined($ref_vms) && $doc->exists("/vnx/host/exec[\@seq='$seq']") ) {
            wlog (N, "Calling execute_host_cmd with seq '$seq'"); 
            $num_host_execs = execute_host_command($seq);
        }

	    wlog (VVV, "Total number of commands executed for seq $seq:", $logp);
	    wlog (VVV, "   plugin_filetrees=$num_plugin_ftrees, plugin_execs=$num_plugin_execs,", $logp); 
	    wlog (VVV, "   user-defined_filetrees=$num_ftrees, user-defined_execs=$num_execs,", $logp);
	    wlog (VVV, "   host-user-defined-execs=$num_host_execs", $logp);
		if ( ($num_plugin_ftrees + $num_plugin_execs + $num_ftrees + $num_execs + $num_host_execs == 0) && ($seq ne 'on_boot') && ($seq ne 'on_shutdown')) {
			wlog(N, "--\n-- ERROR: no commands executed for tag '$seq'");
		}
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
    #      returned and pass it as a parameter to execute_cmd
    #  3 - for each active plugin, call: $plugin->getCommands
    #  4 - create a list of <exec> command returned 
    #      to pass it as a parameter to execute_cmd
        
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
            wlog (VVV, "getFiles returns '" . keys(%files) . " files/dirs for vm $vm_name:\n $res", $logp);
        } else {
            wlog (VVV, "getFiles returns no files/dirs for vm $vm_name", $logp);
        }
                
        if (keys(%files) > 0 ) { 
            $vm_plugin_ftrees += keys(%files);
        }
        
        #  2 - create a list of <filetree> commands to copy all the files 
        #      returned and pass it as a parameter to execute_cmd
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
             
            # Add the filetree node to the list passed to execute_cmd
            push (@{$plugin_ftree_list_ref}, $ftree_tag);
                
            # Copy the file/dir to "filetree/$dst_num" dir
            my $dst_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq/filetree/$dst_num";
            
            $execution->execute($logp, "mkdir -p $dst_dir");
            $execution->execute($logp, "rm -rf $dst_dir/*");
            
            if ( -d "$files_dir$files{$key}" ) { # It is a directory
                $execution->execute($logp, "cp -r $files_dir$files{$key}/* $dst_dir");
            } else { # It is a file
                $execution->execute($logp, "cp $files_dir$files{$key} $dst_dir");
            }
            $dst_num++;
        }           

        # Delete plugin returned files from tmp dir
        $execution->execute($logp, "rm -rf $files_dir/*");

        #  3 - for each active plugin, call $plugin->get*Commands 
        my @commands;            
        # Call the getCommands plugin function
        @commands = $plugin->getCommands($vm_name,$seq);
        my $error = shift(@commands);
        if ($error ne "") {
            $execution->smartdie("plugin $plugin getCommands($vm_name,$seq) error: $error");
        }

        wlog (VVV, "getCommands returns '" . scalar(@commands) . " commands", $logp);
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
           
            # Add the filetree node to the list passed to execute_cmd
            push (@{$plugin_exec_list_ref}, $exec_tag);
        }
    }

    # Get the <filetree> and <exec> tags with sequence $seq and add them to the 
    # lists passed to execute_cmd

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
                my $value = text_tag($filetree);

                # Add the filetree node to the list passed to execute_cmd
                my $filetree_clon = $filetree->cloneNode(1);
                push (@{$ftree_list_ref}, $filetree_clon);
    
                # Copy the files/dirs to "filetree/$dst_num" dir
                my $src = get_abs_path ($value);
                #$src = chompslash($src);
                if ( -d $src ) {   # If $src is a directory...
                
	                if ( $merged_type eq "libvirt-kvm-windows" ) { # Windows vm
	                    if  ( !( $root =~ /\$/ ) ) {     # ...and $file[0] (dst dir) does not end with a "\"
	                        # Add a slash; <filetree> root attribute must be a directory
                            wlog (N, "$hline\nWARNING: root attribute must be a directory (end with a \"\\\") in " . $filetree->toString(1) . "\n$hline");
                            $filetree->setAttribute( root => "$root\\" );
	                    }
	                } else { # not windows
	                    if  ( !( $root =~ /\/$/ ) ) {     # ...and $file[0] (dst dir) does not end with a "/"
	                        # Add a slash; <filetree> root attribute must be a directory
		                    wlog (N, "$hline\nWARNING: root attribute must be a directory (end with a \"/\") in " . $filetree->toString(1) . "\n$hline");
		                    $filetree->setAttribute( root => "$root/" );
	                    }
	                }
                } 
                    
                my $dst_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq/filetree/$dst_num";
                $execution->execute($logp, "mkdir -p $dst_dir");
	            if ( -d "$src" ) { # It is a directory
                    $execution->execute($logp, $bd->get_binaries_path_ref->{"cp"} . " -a ${src}* $dst_dir");
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
                my $value = text_tag($command);

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
  
                    # Add the exec node to the list passed to execute_cmd
                    push (@{$exec_list_ref}, $new_exec);
                }

                # Case 2. File type
                elsif ( $type eq "file" ) {
                    # We open the file and write commands line by line
                    my $include_file = do_path_expansion( text_tag($command) );
                    open INCLUDE_FILE, "$include_file" or $execution->smartdie("can not open $include_file: $!");
                    while (<INCLUDE_FILE>) {
                        chomp;

                        # Create a new node
                        my $new_exec = XML::LibXML::Element->new('exec');
                        $new_exec->setAttribute( seq => $seq);
                        $new_exec->setAttribute( type => $type);
                        $new_exec->setAttribute( ostype => $ostype);
                        $new_exec->appendTextNode( $_ );
        
                        # Add the exec node to the list passed to execute_cmd
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


#
# ------------------------------------------------------------------------------
#                           E X E C L I   M O D E
# ------------------------------------------------------------------------------
#
# execute commands in VMs directly specified in command line
#
# Arguments:
#   -  
#
sub mode_execli {

    #my $seq_str  = shift;
    #my $type = shift;

    my $ref_vms = shift;
    my @vm_ordered;
    if ( defined($ref_vms) ) {
        # List of VMs to use passed as parameter
        @vm_ordered = @{$ref_vms};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @vm_ordered = $dh->get_vm_to_use_ordered;    
    }

    if ($exemode != $EXE_DEBUG) {
        $execution->smartdie ("cannot execute commands on scenario " . $dh->get_scename . " (not started)\n")
            unless scenario_exists($dh->get_scename);
    }

    wlog (N, "\nVNX exe-cli mode:\n$hline");     

    my $cmd = join(" ",@exe_cli);
    wlog (N, "Executing '$cmd' command on VMs: " . get_vmnames(\@vm_ordered, ",") . "\n");     

    my $vm_name = "test";

    my $exec_tag = XML::LibXML::Element->new('exec');
    $exec_tag->setAttribute('seq', 'exe-cli');
    $exec_tag->setAttribute('type', 'verbatim');
    $exec_tag->setAttribute('ostype', 'system');
    $exec_tag->appendTextNode($cmd);

    wlog (VVV,  "exec tag: " . $exec_tag->toString(1));

    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];
        my $vm_name = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);
        my $vm_status = get_vm_status($vm_name);
        my $vm_type = $vm->getAttribute("type");

        # Skip this VM if not running
        unless ($vm_status eq 'running') {
            wlog (N, "\nERROR: cannot execute command on virtual machine '$vm_name' (not running, status=$vm_status)\n");
            next
        }        

        my @plugin_ftree_list = ();
        my @plugin_exec_list = ();
        my @ftree_list = ();
        my @exec_list = ();
        $exec_list[0] = $exec_tag;

        wlog (N, "Calling execute_cmd for vm '$vm_name'..."); 
        my $error = "VNX::vmAPI_$vm_type"->execute_cmd(
                                         $vm_name, $merged_type, 'exe-cli', $vm,  
                                         \@plugin_ftree_list, \@plugin_exec_list, 
                                         \@ftree_list, \@exec_list);
        if ($error) {
            wlog (N, "$hline\nERROR: VNX::vmAPI_${vm_type}->execute_cmd returns '" . $error . "'\n$hline");
        } else {
            wlog (N, "...OK");
        }
    }    	
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
        my $route_dest = text_tag($route);;
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
        dec_cter($external_if);
        
        my $mode = $net->getAttribute("mode");
        # To clean up not in use physical interfaces
        if (get_cter($external_if) == 0) {
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
                physicalif_config($external_if);
            }
        }
    }
}

######################################################
# To remove TUN/TAPs devices

sub tun_destroy_switched {

    my $doc = $dh->get_doc;

    # Remove the symbolic link to the management switch socket
#    if ($dh->get_vmmgmt_type eq 'net') {
#        my $socket_file = $dh->get_networks_dir . "/" . $dh->get_vmmgmt_netname . ".ctl";
#        $execution->execute($logp, $bd->get_binaries_path_ref->{"rm"} . " -f $socket_file");
#    }

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
            dec_cter("$net_name.ctl");
            
            # Destroy the uml_switch only when no other concurrent scenario is using it
            if (get_cter ("$net_name.ctl") == 0) {
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

    my $ref_vms = shift;
    my @vm_ordered;
    if ( defined($ref_vms) ) {
        # List of VMs to use passed as parameter
        @vm_ordered = @{$ref_vms};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @vm_ordered = $dh->get_vm_to_use_ordered;    
    }

    my $logp = "tun_destroy> ";

    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];

        # To get name and type attribute
        my $vm_name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");

        # To throw away and remove management device (id 0), if neeed
        my $mng_if_value = mng_if_value($vm);
      
        if ( ($dh->get_vmmgmt_type eq 'private') && ($mng_if_value ne "no") && ($vm_type ne 'lxc') && ($vm_type ne 'nsrouter')) {
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
            if ( ( get_net_by_mode($net,"virtual_bridge") != 0) && ( $vm_type ne 'lxc') && ($vm_type ne 'nsrouter') ) {
	            # TUN device name
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

    my $ref_nets = shift;
    my @nets;
    my $doc = $dh->get_doc;
    if ( defined($ref_nets) ) {
        # List of nets to use passed as parameter
        @nets = @{$ref_nets};  
    } else {
        # List not specified, get the list of vms 
        # to process having into account -M option
        @nets = $doc->getElementsByTagName("net");    
    }

    my $logp = "bridges_destroy> ";
    wlog (VVV, "bridges_destroy called", $logp);
    # To get list of defined <net>
   	foreach my $net (@nets) {

        # To get attributes
        my $net_name = $net->getAttribute("name");
        my $mode = $net->getAttribute("mode");
        my $managed     = str($net->getAttribute("managed"));

    	wlog (VVV, "net=$net_name, mode=$mode, managed='" . $managed . "'", $logp);
    	
        if ( !($managed eq 'no') && ($mode ne "uml_switch") ) {
            # Set bridge down and remove it only in the case there isn't any associated interface 
            my @br_ifs = vnet_ifs($net_name,$mode);  
            #wlog (N, "OVS a eliminar @br_ifs", $logp);
	    	wlog (VVV, "br_ifs=@br_ifs", $logp);

            if ( (@br_ifs == 0) || (@br_ifs == 1) && ( $br_ifs[0] eq "${net_name}-e00" ) ) {
         	
                if ($mode eq "virtual_bridge") {
                    # Destroy the tap associated with the bridge
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"ip"} . " link set ${net_name}-e00 down");
                    $execution->execute_root($logp, $bd->get_binaries_path_ref->{"tunctl"} . " -d ${net_name}-e00");
                }            
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


#######################################################

# Additional functions

=BEGIN
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
	#my $net_name = at_least_one_vm_with_mng_if($dh,$dh->get_vm_ordered);
	my $net_name = at_least_one_vm_with_mng_if($dh->get_vm_ordered);
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
=END
=cut

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
# Inserts VMs names in the /etc/hosts file, when <host_mapping> is presented
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
   my $scename = shift;
   my $file_name = shift;

   # DEBUG
   my $logp = "host_mapping_patch> ";
   wlog (VVV, "--filename: $file_name", $logp);
   wlog (VVV, "--scename:  $scename", $logp);
	
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
   # 0 -> before VNX section
   # 1 -> inside VNX section, before scenario subsection
   # 2 -> inside simultaion subsection
   # 3 -> after scenario subsection, inside VNX section
   # 4 -> after VNX section
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
         if (/^\# BEGIN: $scename$/) {
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
         if (/^\# END: $scename$/) {
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
      # No VNX section found
      print FIRST "\# VNX BEGIN -- DO NOT EDIT!!!\n";
      print FIRST "\n";
      print THIRD "\n";
      print THIRD "\# VNX END\n";
   }
   elsif ($status == 1) {
     # Found VNX BEGIN but not found VNX END. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 2) {
     # Found simultaion subsection BEGIN, but not found the end. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 3) {
     # Found VNX BEGIN but not found VNX END. Buggy situation? Trying to do the best
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
   print SECOND "\# BEGIN: $scename\n";
   print SECOND "\# topology built: $now\n";
   print SECOND "$lines\n";
   print SECOND "\# END: $scename\n";
   
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

   my $scename = shift;
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
    # 0 -> before VNX section
    # 1 -> inside VNX section, before scenario subsection
    # 2 -> inside simultaion subsection
    # 3 -> after scenario subsection, inside VNX section
    # 4 -> after VNX section
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
            if (/^\# BEGIN: $scename$/) {
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
            if (/^\# END: $scename$/) {
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
      # No VNX section found
      print FIRST "\# VNX BEGIN -- DO NOT EDIT!!!\n";
      print FIRST "\n";
      print THIRD "\n";
      print THIRD "\# VNX END\n";
   }
   elsif ($status == 1) {
     # Found VNX BEGIN but not found VNX END. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 2) {
     # Found simultaion subsection BEGIN, but not found the end. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 3) {
     # Found VNX BEGIN but not found VNX END. Buggy situation? Trying to do the best
     print THIRD "\n";
     print THIRD "\# VNX END\n";
   }
   elsif ($status == 4) {
     # Doing nothing
   }
   
   # Second fragment
   my $command = $bd->get_binaries_path_ref->{"date"};
   chomp (my $now = `$command`);
   print SECOND "\# BEGIN: $scename\n";
   print SECOND "\# topology destroyed: $now\n";
   print SECOND "\# END: $scename\n";
   
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
   my @pids = get_kernel_pids($only_vm);
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
            if ($dh->get_vmmgmt_type eq 'none' || mng_if_value($vm) eq "no") {
	 
               # There isn't management interface, check <if>s in the virtual machine
               my $ip_candidate = "0";
               
               # Note that disabling IPv4 didn't assign addresses in scenario
               # interfaces, so the search can be avoided
               if ($dh->is_ipv4_enabled) {
                  foreach my $if ($vm->getElementsByTagName("if")) {
                     my $id = $if->getAttribute("id");
                     foreach my $ipv4 ($if->getElementsByTagName("ipv4")) {
                        my $ip = text_tag($ipv4);
                        my $ip_effective;
                        # IP could end in /mask, so we are prepared to remove the suffix
                        # in that case
                        if (valid_ipv4_with_mask($ip)) {
                           $ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+).*$/;
                           $ip_effective = "$1.$2.$3.$4";
                        }
                        else {
                           $ip_effective = $ip;
                        }
                        if (socket_probe($ip_effective,"22")) {
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
               my %net = get_admin_address('file', $vm_name, $dh->get_vmmgmt_type);
               if (!socket_probe($net{'vm'}->addr(),"22")) {
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
##
# $automac_offset is used to complete MAC address
sub automac {

      my $ante_lower = sprintf("%x", shift);
      my $lower = sprintf("%x", shift);

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
# - the virtual machine name 
# - the target status
#
# Changes current status file to the target one specified as argument. The
# special target REMOVE (uppercase) deletes the file
#
sub change_vm_status {

    my $vm_name = shift;
    my $status = shift;

    my $logp = "change_vm_status> ";
    
   my $status_file = $dh->get_vm_dir($vm_name) . "/status";

   if ($status eq "REMOVE") {
      $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -f $status_file");
   }
   else {
      $execution->execute($logp, $bd->get_binaries_path_ref->{"echo"} . " $status > $status_file"); 
   }
   wlog (V, "status of VM $vm_name changed to $status");
}

# get_vm_status
#
# Argument:
# - the virtual machine name 
#
sub get_vm_status {

    my $vm_name = shift;
    my $status = 'undefined';
   
    my $status_file = $dh->get_vm_dir($vm_name) . "/status";
    if (-r $status_file) {
    	$status = `cat $status_file`;
    	chomp ($status);
    }
    return $status;
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

=BEGIN
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
   if (valid_dotted_mask($mask)) {
      $effective_mask = $mask;
   }
   else {
      $effective_mask = slashed_to_dotted_mask($mask);
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
=END
=cut

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
   printf "$hline\n";
   printf "ERROR in %s (%s):\n%s \n", (caller(1))[3], (caller(0))[2], $mess;
   printf "$hline\n";
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
			my $conData= get_conf_value ($consFile, '', $con);
			#print "** $consFile $con conData=$conData\n";
			my $console_term=get_conf_value ($vnxConfigFile, 'general', 'console_term', 'root');
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
    my @vm_ordered = $dh->get_vm_to_use_ordered;  # List of vms to process having into account -M option   
    
    my $first = 1;
    my $scename = $dh->get_scename;
    for ( my $i = 0; $i < @vm_ordered; $i++) {
		my $vm = $vm_ordered[$i];
		my $vm_name = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);
			
		if ( ($first eq 1) && (! $briefFormat ) ){
			print_console_table_header ($scename);
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
        pre_wlog ("                             Virtual Networks over LinuX         ");
        pre_wlog ("                                 http://vnx.dit.upm.es           ");
        pre_wlog ("                                    vnx\@dit.upm.es              ");
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
  [sudo] vnx -f VNX_file --define          [-M vm_list] [options]
  [sudo] vnx -f VNX_file --undefine        [-M vm_list] [options]
  [sudo] vnx -f VNX_file --start           [-M vm_list] [options]
  [sudo] vnx -f VNX_file --shutdown --kill [-M vm_list] [options]
  [sudo] vnx -f VNX_file --create          [-M vm_list] [options]
  [sudo] vnx -f VNX_file --destroy         [-M vm_list] [options]
  [sudo] vnx -f VNX_file --save            [-M vm_list] [options]
  [sudo] vnx -f VNX_file --restore         [-M vm_list] [options]
  [sudo] vnx -f VNX_file --suspend         [-M vm_list] [options]
  [sudo] vnx -f VNX_file --resume          [-M vm_list] [options]
  [sudo] vnx -f VNX_file --reboot          [-M vm_list] [options]
  [sudo] vnx -f VNX_file --reset           [-M vm_list] [options]
  [sudo] vnx -f VNX_file --execute cmd_seq [-M vm_list] [options]
  [sudo] vnx -f VNX_file --exe-cli cmd     [-M vm_list] [options]
  [sudo] vnx -f VNX_file --show-map [svg|png]
  [sudo] vnx -f VNX_file --show-status [-b]
  vnx -h
  vnx -V
  [sudo] vnx --show-status
  [sudo] vnx --clean-host
  [sudo] vnx --create-rootfs ROOTFS_file --install-media MEDIA_file 
  [sudo] vnx --modify-rootfs ROOTFS_file [--update-aced]

Main modes:
  --define      -> define (but not start) the whole scenario, or just the VMs
                   speficied in -M option.
  --undefine    -> undefine the scenario or the VMs speficied with -M. 
  --start       -> start the scenario or the VMs speficied with -M.
  --shutdown|-d -> destroy current scenario, or the VMs specified in -M option.
  --create|-t   -> create the complete scenario defined in VNX_file, or just
                   start the virtual machines (VM) specified with -M option.
  --destroy|-P  -> purge (destroy) the whole scenario, or just the VMs 
                   specified in -M option, (Warning: it will remove VM COWed
                   filesystems! Any changes in VMs will be lost).
  --save        -> save the scenario to disk or the VMs speficied with -M.
  --restore     -> restore the scenario from disk or the VMs speficied with -M.
  --suspend     -> suspend the scenario to memory or the VMs speficied with -M.
  --resume      -> resume the scenario from memory or the VMs speficied with -M.
  --reboot      -> reboot the scenario or the VMs speficied with -M.
  --execute|-x cmd_seq -> execute the commands tagged 'cmd_seq' in VNX_file.
  --exe-cli cmd -> execute the command specified in all VMS or the ones specified in -M option.

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
  --show-map [format] -> shows a map of the network scenarios build using graphviz.
                     png and svg formats supported (defaults to svg).
  --show-status   -> shows the scenarios started (if no scenario specified) or the status 
                      of the VMs of the scenario specified.
  --exe-info      -> show information about the commands available in VNX_file.
  --create-rootfs -> starts a virtual machine to create a rootfs. 
                     Use --install-media option to specify installation media.
  --modify-rootfs -> starts a virtual machine using the rootfs specified in
                     order to modify it (install software, change config, etc).
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
  --intervm-delay num -> wait num secs. between virtual machines startup 
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
       --intervm-delay num -> wait num secs. between virtual machines startup (0 by default)

EOF



}
