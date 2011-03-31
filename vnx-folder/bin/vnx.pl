#!/usr/bin/perl 
#!@PERL@
# ---------------------------------------------------------------------------------
# VNX parser. Version 0.14b (based on VNUML 1.9.1)
#
# Authors:        Fermin Galan Marquez (galan@dit.upm.es), Jorge Somavilla (somavilla@dit.upm.es), 
#                 Jorge Rodriguez (jrodriguez@dit.upm.es), David Fernández (david@dit.upm.es)
# Coordinated by: David Fernández (david@dit.upm.es)
# Copyright (C) 2005-2010 DIT-UPM
# 			      Departamento de Ingenieria de Sistemas Telematicos
#			      Universidad Politecnica de Madrid
#			      SPAIN
#			
# Available at:	  http://www.dit.upm.es/vnx 
#
# ----------------------------------------------------------------------------------
#
# VNX is the new version of VNUML tool adapated to use new virtualization platforms, mainly by means of 
# libvirt (libvirt.org), the standard API to control virtual machines in Linux.
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

# Becuase of I'm not a Perl guru (in fact, this program is my first development
# in this language :) is possible that the code wouldn't be too tidy.
# The careful reader will discover many bad habits due to years of C
# programming. How many times had I reinvented the wheel in this code? ;)
#
# Anyway, I really apreciate any comment or suggestion about the
# code (and about the english language :) to galan@dit.upm.es

# A word about SSH!
#
# In order to perfom management task (copy files, execute commands, etc)
# SSH is used from the host to the UMLs. To avoid performing interactive
# authentication procedure (that is, write the password) in each access,
# key configuration is desirable.
#
# To do so, we have to generate the pair of keys in the host. In the case
# of using SSH v1, the command is
#
#    ssh-keygen -t rsa1
#
# This generates a pair of files (in $HOME/.ssh/ by default)
#
#    identity		->	in $HOME/.ssh/ in the host
#    identity.pub	->	append it to $HOME/.ssh/authorized_keys file in the UML
#
# Usually $HOME will be /root
#
# Global tag <ssh_key> can be used pointing to the file identity.pub (absolute
# pathname) in the host, in order to the parser perform automaticly the intallation
# of the key in the authorized_keys of the UMLs.
#
# Anyway, in the first access with SSH to the UMLs, we have to confirm the
# key that authenticates the sshd server (in the UML).
#
# SSHv2 works in the same way, althought it is not yet implemented. If you
# want to considerate this possibility look at man pages of ssh-keygen(1) and
# ssh(1).

# A word about boot process!
#
# The following is a comment to the -t mode.
#
# An auxiliary filesystem is used to configure the uml virtual machine during
# its boot process.  The auxiliary  filesytem is of type iso9660 and is mounted
# on /mnt/vnuml.  The root filesystem's /etc/fstab should contain an entry for this
# auxiliary filesystem:
# /dev/ubdb /mnt/vnuml iso9660 defaults 0 0
#
# In addition, the master filesystem should have a SXXumlboot symlink that
# points to /mnt/vnuml/umlboot, the actual boot script, built by the parser in
# certain cases.
#
# There are three boot modes, depending of the <filesystem> type option.
#
# a) type="direct"
#    The filesystem in the <filesystem> tag is used as the root filesystem.
#
# b) type "cow"
#    A copy-on-write (COW) file based on the filesystem in the <filesystem> tag
#    is created, and this COW is used as the root filesystem.  The base filesystem
#    from the <filesystem> tag is not modified, but its presence is necessary due
#    to the nature of COW mode.
#
# c) type "hostfs"
#    The filesystem is actually a host directory, which content is used as 
#    root filesystem for the virtual machine.
#
# Execpt in the case of "cow" no more than one virtual machine must use the same
# filesystem (otherwise, filesytem corruption would happen).
#
# To summarize, the master filesystem must meet the following requirements for vnuml:
#
# - /mnt/vnuml directory (empty)
# - symlink at rc point (/etc/rc.d/rc3.d/S11umlboot is suggested) pointing to
#   /mnt/vnuml/umlboot
# - /etc/fstab with the following last line:
#	/dev/ubdb /mnt/vnuml iso9660 defaults 0 0
#
# (In fact, /mnt/vnuml can be changed for other empty mount point: it is transparent
# from the point of view of the parser operation)

###########################################################
# Use clauses

# Explicit declaration of pathname for VNUML modules

#use lib "@PERL_MODULES_INSTALLROOT@";[JSF]
use lib "/usr/share/perl5";


use strict;
use warnings;
use XML::DOM;
#use XML::DOM::ValParser;
use File::Basename;
use File::Path;
use Cwd 'abs_path';
#use Getopt::Std;
use Getopt::Long;
use IO::Socket;
#use Net::IPv6Addr;
use NetAddr::IP;
use Data::Dumper;

use XML::LibXML;

use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import

use VNX::Globals;
use VNX::DataHandler;
use VNX::Execution;
use VNX::BinariesData;
use VNX::Arguments;
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

use Error qw(:try);
use Exception::Class ( "Vnx::Exception" =>
		       { description => 'common exception',
                         fields => [ 'context' ]
                         },
		       ); 

#no strict "subs";	# Needed in deamonize subrutine
#use POSIX 'setsid';	# Needed in deamonize subrutine

# see man Exception::Class. a hack to use Exception::Class
# as a base class for Exceptions while using Error.pm, instead
# of its own Error::Simple
push @Exception::Class::Base::ISA, 'Error';

###########################################################
# Constants
# TODO: constant should be included in a .pm that would be loaded from each module
# that needs them
# Moved to VNX::Globals module (DFC 1/1/2010)
#use constant EXE_DEBUG => 0;	#	- does not execute, only shows
#use constant EXE_VERBOSE => 1;	#	- executes and shows
#use constant EXE_NORMAL => 2;	#	- executes

###########################################################
# Set up signal handlers

$SIG{INT} = \&handle_sig;
$SIG{TERM} = \&handle_sig;

###########################################################
# Global objects

# Moved to VNX::Globals module in order to have it shared with
# all packages (DFC 1/1/2010)
#my $execution;   # the VNX::Execution object
#my $dh;          # the VNX::DataHandler object
#my $bd;          # the VNX::BinariesData object
#my $args;        # the VNX::Arguments object
#my @plugins;     # plugins array

###########################################################
# Other global variables

# Version information (variables moved to VNX::Globals)
# my $version = "[arroba]PACKAGE_VERSION[arroba]";[JSF]
# my $release = "[arroba]RELEASE_DATE[arroba]";[JSF]
$version = "1.92beta1";
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

&main;
exit(0);

###########################################################
# THE MAIN PROGRAM
#
sub main {
	
   	print "----------------------------------------------------------------------------------\n";
   	print "Virtual Networks over LinuX (VNX) -- http://www.dit.upm.es/vnx - vnx\@dit.upm.es          \n";
   	print "Version: $version" . "$branch (build on $release)\n";
   	print "----------------------------------------------------------------------------------\n";

   	$ENV{'PATH'} .= ':/bin:/usr/bin/:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin';

   	# DFC 21/2/2011 my $uid = $> == 0 ? getpwnam("vnx") : $>; # uid=vnx if executed as root; userid if executed as user
   	my $uid = $>;
   	my $boot_timeout = 60; # by default, 60 seconds for boot timeout 
   	my $start_time;                   # the moment when the parsers start operation


   	###########################################################
   	# To get the invocation arguments

   	our($opt_t,$opt_s,$opt_p,$opt_r,$opt_d,
      $opt_m,$opt_c,$opt_g,$opt_v,$opt_F,
      $opt_V,$opt_T,$opt_o,$opt_M,$opt_k,
      $opt_i,$opt_B,$opt_S,$opt_w,$opt_e,
      $opt_P,$opt_H,$opt_x,$opt_u,$opt_4,
      $opt_6,$opt_Z,$opt_create,$opt_shutdown,
      $opt_destroy,$opt_define,$opt_undefine,
      $opt_start,$opt_save,$opt_restore,
      $opt_suspend, $opt_resume,$opt_reboot,
      $opt_reset,$opt_execute,$opt_f,$opt_showmap,
      $opt_console,$opt_consoleinfo,$opt_cid,
      $opt_C, $opt_config, $opt_D, $opt_b, $opt_n,
      $opt_no_console);
      
   	Getopt::Long::Configure ("bundling"); # case sensitive single-character options
   	GetOptions('t' => \$opt_t, 's=s' => \$opt_s, 'p=s' => \$opt_p, 
              'r=s' => \$opt_r, 'd' => \$opt_d, 'm=s' => \$opt_m,
              'c=s' => \$opt_c,'T=s' => \$opt_T, 'g' => \$opt_g,
              'v' => \$opt_v, 'F' => \$opt_F, 'V' => \$opt_V, 'version' => \$opt_V,
              'o=s' => \$opt_o,  'M=s' => \$opt_M, 'k' => \$opt_k,
              'i' => \$opt_i, 'B' => \$opt_B, 'S=s' => \$opt_S,
              'w=s' => \$opt_w,'e=s' => \$opt_e, 'P' => \$opt_P,
              'H' => \$opt_H, 'h' => \$opt_H, 'help' => \$opt_H, 
              'x=s' => \$opt_x, 'u=s' => \$opt_u,
              '4' => \$opt_4, '6' => \$opt_6, 'Z' => \$opt_Z,
              'create' => \$opt_create, 'shutdown' => \$opt_shutdown,
              'destroy' => \$opt_destroy, 'define' => \$opt_define,
              'undefine' => \$opt_undefine, 'start' => \$opt_start,
              'save' => \$opt_save, 'restore' => \$opt_restore,
              'suspend' => \$opt_suspend, 'resume' => \$opt_resume,
              'reboot' => \$opt_reboot, 'reset' => \$opt_reset,
              'execute=s' => \$opt_execute, 'f=s' => \$opt_f,
              'show-map' => \$opt_showmap, 'console' => \$opt_console,
              'cid=s' => \$opt_cid, 'console-info' => \$opt_consoleinfo,
              'C|config=s' => \$opt_config, 'D' => \$opt_D, 'b' => \$opt_b,
              'n' => \$opt_n, 'no_console' => \$opt_no_console);

   	# Build the argument object
   	$args = new Arguments(
      	$opt_t,$opt_s,$opt_p,$opt_r,$opt_d,
      	$opt_m,$opt_c,$opt_g,$opt_v,$opt_F,
      	$opt_V,$opt_T,$opt_o,$opt_M,$opt_k,
      	$opt_i,$opt_B,$opt_S,$opt_w,$opt_e,
      	$opt_P,$opt_H,$opt_x,$opt_u,$opt_4,
      	$opt_6,$opt_Z,$opt_create,$opt_shutdown,
      	$opt_destroy,$opt_define,$opt_undefine,
      	$opt_start,$opt_save,$opt_restore,
      	$opt_suspend,$opt_resume,$opt_reboot,
      	$opt_reset,$opt_execute,$opt_f,$opt_showmap,
      	$opt_console,$opt_cid,$opt_consoleinfo,
      	$opt_config, $opt_D, $opt_b, $opt_n,
      	$opt_no_console);

   	# FIXME: as vnumlize process does not work properly in latest kernel/root_fs versions, we disable
   	# it by default
   	$args->set('Z',1);


   	# Set configuration file 
   	if ($opt_config) {
   	  	$vnxConfigFile = $opt_config; 
   	} else {
   		$vnxConfigFile = $DEFAULT_CONF_FILE;
   	}
   	print ("Using configuration file: $vnxConfigFile\n");
   
   	# Check the existance of the VNX configuration file 
   	unless(-e $vnxConfigFile) {
   	 	print "\nERROR: VNX configuration file $vnxConfigFile not found\n\n";
   	 	exit(1);   	 
   	}
   
   	# Set VNX and TMP directories
   	my $tmp_dir=&get_conf_value ($vnxConfigFile, 'general', 'tmp_dir');
   	if (!defined $tmp_dir) {
   		$tmp_dir = $DEFAULT_TMP_DIR;
   	}
   	print ("  TMP dir=$tmp_dir\n");
   	my $vnx_dir=&get_conf_value ($vnxConfigFile, 'general', 'vnx_dir');
   	if (!defined $vnx_dir) {
   		$vnx_dir = &do_path_expansion($DEFAULT_VNX_DIR);
   	} else {
   		$vnx_dir = &do_path_expansion($vnx_dir);
   	}
   	print ("  VNX dir=$vnx_dir\n");
   	print "----------------------------------------------------------------------------------\n";
   	

   	# To check arguments consistency
   	# 0. Check if -f is present
   	if (!($opt_f) && !($opt_V) && !($opt_H) && !($opt_D)) {
   	  	&usage;
      	&vnx_die ("Option -f missing\n");
   	}

   	# 1. To use -t|--create, -x|--execute, -d|--shutdown, -V, -P|--destroy, --define, --start,
   	# --undefine, --save, --restore, --suspend, --resume, --reboot, --reset, --console, --console-info at the same time
   
   	my $how_many_args = 0;
   	my $mode;
   	if ($opt_t||$opt_create) {
      	$how_many_args++;
      	$mode = "t";
   	}
   	if ($opt_s) {
      	# Deprecated, not supported since 1.7.0
      	&vnx_die ("-s mode is no longer supported since version 1.7.0, use -x instead\n");
   	}
   	if ($opt_p) {
      	# Deprecated, not supported since 1.7.0
      	&vnx_die ("-p mode is no longer supported since version 1.7.0, use -x instead\n");
   	}
   	if ($opt_S) {
      	# Deprecated, not supported since 1.8.0
      	&vnx_die ("-S is no longer supported since version 1.8.0\n");
   	}   
   	if ($opt_x||$opt_execute) {
      	$how_many_args++;
      	$mode = "x";
   	}
   	if ($opt_r) {
      	# Deprecated, not supported since 1.7.0
      	&vnx_die ("-r mode is no longer supported since version 1.7.0, use -x instead\n");
   	}
   	if ($opt_d||$opt_shutdown) {
      	$how_many_args++;
      	$mode = "d";
   	}
   	if ($opt_P||$opt_destroy) {
      	$how_many_args++;
      	$mode = "P";
   	}
   	if ($opt_V) {
      	$how_many_args++;
      	$mode = "V";      
   	}
   	if ($opt_H) {
      	$how_many_args++;
      	$mode = "H";
   	}
   	if ($opt_define) {
      	$how_many_args++;
      	$mode = "define";
   	}
   	if ($opt_start) {
      	$how_many_args++;
      	$mode = "start";
   	}
   	if ($opt_undefine) {
      	$how_many_args++;
      	$mode = "undefine";
   	}
   	if ($opt_save) {
      	$how_many_args++;
      	$mode = "save";
   	}
   	if ($opt_restore) {
      	$how_many_args++;
      	$mode = "restore";
   	}
   	if ($opt_suspend) {
      	$how_many_args++;
      	$mode = "suspend";
   	}
   	if ($opt_resume) {
      	$how_many_args++;
      	$mode = "resume";
   	}
   	if ($opt_reboot) {
      	$how_many_args++;
      	$mode = "reboot";
   	}
   	if ($opt_reset) {
      	$how_many_args++;
      	$mode = "reset";
   	}
   	if ($opt_showmap) {
      	$how_many_args++;
      	$mode = "show-map";
   	}
   	if ($opt_console) {
      	$how_many_args++;
      	$mode = "console";
   	}
   	if ($opt_consoleinfo) {
      	$how_many_args++;
      	$mode = "console-info";
   	}

      
   	if ($opt_m) {
      	&vnx_die ("-m switch is no longer supported since version 1.6.0\n");
   	}

   	if ($how_many_args gt 1) {
      	&usage;
      	&vnx_die ("Only one of the following at a time: -t|--create, -x|--execute, -d|--shutdown, -V, -P|--destroy, --define, --start, --undefine, --save, --restore, --suspend, --resume, --reboot, --reset, --showmap or -H\n");
   	}
   	if ( ($how_many_args lt 1) && (!$opt_D) ) {
      	&usage;
      	&vnx_die ("missing -t|--create, -x|--execute, -d|--shutdown, -V, -P|--destroy, --define, --start, --undefine, \n--save, --restore, --suspend, --resume, --reboot, --reset, --show-map, --console, --console-info, -V or -H\n");
   	}
   	if (($opt_F) && (!($opt_d||$opt_shutdown))) { 
      	&usage; 
      	&vnx_die ("Option -F only makes sense with -d|--shutdown mode\n"); 
   	}
   	if (($opt_B) && ($opt_F) && ($opt_d||$opt_shutdown)) {
      	&vnx_die ("Option -F and -B are incompabible\n");
   	}
    if (($opt_o) && (!($opt_t||$opt_create))) {
      	&usage;
      	&vnx_die ("Option -o only makes sense with -t|--create mode\n");
   	}
   	if (($opt_w) && (!($opt_t||$opt_create))) {
      	&usage;
      	&vnx_die ("Option -w only makes sense with -t|--create mode\n");
   	}
  	if (($opt_e) && (!($opt_t||$opt_create))) {
      	&usage;
      	&vnx_die ("Option -e only makes sense with -t|--create mode\n");
   	}
   	if (($opt_Z) && (!($opt_t||$opt_create))) {
      	&usage;
      	&vnx_die ("Option -Z only makes sense with -t|--create mode\n");
   	}
   	if (($opt_4) && ($opt_6)) {
      	&usage;
      	&vnx_die ("-4 and -6 can not be used at the same time\n");
   	}
   	if (($opt_n||$opt_no_console) && (!($opt_t||$opt_create))) {
      	&usage;
      	&vnx_die ("Option -n|--no_console only makes sense with -t|--create mode\n");
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
      	print "                   Version: $version" . "$branch (build on $release)\n";
      	print "\n";
      	#print "Fermin Galan Marquez. galan\@dit.upm.es\n";
      	exit(0);
   	}

   	# Help pseudomode
   	if ($opt_H) {
      	&usage;
      	exit(0);
   	}

   	# 2. Optional arguments
   	$exemode = $EXE_NORMAL;
   	$exemode = $EXE_VERBOSE if ($opt_v);
   	$exemode = $EXE_DEBUG if ($opt_g);
   	chomp(my $pwd = `pwd`);
   	$vnx_dir = &chompslash($opt_c) if ($opt_c);
   	$vnx_dir = "$pwd/$vnx_dir"
		   unless (&valid_absolute_directoryname($vnx_dir));
   	$tmp_dir = &chompslash($opt_T) if ($opt_T);
   	$tmp_dir = "$pwd/$tmp_dir"
		   unless (&valid_absolute_directoryname($tmp_dir));	

   	# Delete LOCK file if -D option included
   	if ($opt_D) {
   	  	print "Deleting ". $vnx_dir . "/LOCK file\n";
	  	system "rm -f $vnx_dir/LOCK"; 
	  	if ($how_many_args lt 1) {
	     	exit(0);
	  	}  
   	}	

   	# DFC 21/2/2011 $uid = getpwnam($opt_u) if ($> == 0 && $opt_u);
   	$boot_timeout = $opt_w if (defined($opt_w));
   	unless ($boot_timeout =~ /^\d+$/) {
      	&vnx_die ("-w value ($opt_w) is not a valid timeout (positive integer)\n");  
   	}

   	# FIXME: $enable_4 and $enable_6 are not necessary, use $args object
   	# instead and avoid redundance
   	my $enable_4 = 1;
   	my $enable_6 = 1;
   	$enable_4 = 0 if ($opt_6);
   	$enable_6 = 0 if ($opt_4);   

   	# 3. To extract and check input
   	my $input;
   	$input = $opt_f if ($opt_f);
   	##$input = $opt_t if ($opt_t); [JSF]
   	##$input = $opt_x if ($opt_x);
   	##$input = $opt_d if ($opt_d);
   	##$input = $opt_P if ($opt_P);

   	# Check for file and cmd_seq, depending the mode
   	my $cmdseq = '';
#   my $input_file;

   	if ($opt_x) {
      	$cmdseq = $opt_x;
   	}elsif ($opt_execute){
   	  	$cmdseq = $opt_execute;
   	}
   
   	$input_file = $input;
 
   	# Reserved words for cmd_seq
   	#if ($cmdseq eq "always") {
   	#   &vnuml_die ("\"always\" is a reserved word and can not be used as cmd_seq\n");
   	#}

   	# Check input file
   	if (! -f $input_file) {
      	&vnx_die ("file $input_file is not valid (perhaps does not exists)\n");
   	}

   	# 4. To check vnx_dir and tmp_dir
   	# Create the working directory, if it doesn't already exist
   	if ($exemode ne $EXE_DEBUG) {
	   	if (! -d $vnx_dir ) {
		   	mkdir $vnx_dir or &vnx_die("Unable to create working directory $vnx_dir: $!\n");
	   	}

# DFC 21/2/2011: changed to simplify the user which executes vnx:
#                   - option -u ignored
# 					- no owner changes in any directory
#					- vnx is executed always as the user that starts it (root if the command is preceded by sudo)
#		if ($> == 0) { # vnx executed as root
#			 my $uid_name = getpwuid($uid);
#			 system("chown $uid $vnx_dir");
#			 $> = $uid;
			 my $uid_name = getpwuid($uid);
			 &vnx_die ("vnx_dir $vnx_dir does not exist or is not readable/executable (user $uid_name)\n") unless (-r $vnx_dir && -x _);
			 &vnx_die ("vnx_dir $vnx_dir is not writeable (user $uid_name)\n") unless ( -w _);
			 &vnx_die ("vnx_dir $vnx_dir is not a valid directory\n") unless (-d _);
#			 $> = 0;
#		}


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
   	$bd = new BinariesData($exemode);

   	# 6a. To check mandatory binaries # [JSF] to be updated with new ones
   	if ($bd->check_binaries_mandatory != 0) {
      &vnx_die ("some required binary files are missing\n");
   	}
  
   	# We need the file to perform some manipulations
   	open INPUTFILE, "$input_file";
   	my @input_file_array = <INPUTFILE>;
   	my $input_file_string = join("",@input_file_array);
   	close INPUTFILE;
   
   	# 7. To check if the DTD file is present
   	my $modeparser;
      
   	if ($input_file_string =~ /<!DOCTYPE vnx SYSTEM "(.*)">/) { 
         &vnx_die ("parsing based on DTD not supported; use XSD instead\n");	  
   	}
	$modeparser = "xsd";

   	# 8. To check version number
   	if ($input_file_string =~ /<version>\s*(\d\.\d+)(\.\d+)?\s*<\/version>/) {
      	my $version_in_file = $1;
      	$version =~ /^(\d\.\d+)/;
      	my $version_in_parser = $1;
      	unless ($version_in_file eq $version_in_parser) {
      		&vnx_die("mayor version numbers of source file ($version_in_file) and parser ($version_in_parser) do not match");
			exit;
      	}
   	} else {
      	&vnx_die("can not find VNX version in $input_file");
   	}

   	# Interactive execution (press a key after each command)
   	my $exeinteractive = $opt_v && $opt_i;

   	# Before building the DOM tree, perform text patern-based version
   	# checking   

   	# To build DOM tree parsing file
   	$valid_fail = 0;
   	my $parser;
   	my $doc;
   	if($modeparser eq "xsd"){
   		my $schemalocation;

	    if ($input_file_string =~ /="(\S*).xsd"/) {
        	$schemalocation = $1 .".xsd";

		}else{
			print "input_file_string = $input_file_string, $schemalocation=schemalocation\n";
			&vnx_die("XSD not found");
		}
		
		my $schema = XML::LibXML::Schema->new(location => $schemalocation);
		
		$parser = XML::LibXML->new;
		#$doc    = $parser->parse_file($document);
		$doc = $parser->parse_file($input_file);
		my $parser2 = new XML::DOM::Parser;
       	$doc = $parser2->parsefile($input_file);
   	}
   
   	# Build the VNX::Execution object
   	$execution = new Execution($vnx_dir,$exemode,"host> ",$exeinteractive,$uid);

   	# Calculate the directory where the input_file lives
   	my $xml_dir = (fileparse(abs_path($input_file)))[1];

   	# Build the VNX::DataHandler object
   	$dh = new DataHandler($execution,$doc,$mode,$opt_M,$cmdseq,$xml_dir,$input_file);
   	$dh->set_boot_timeout($boot_timeout);
   	$dh->set_vnx_dir($vnx_dir);
   	$dh->set_tmp_dir($tmp_dir);
   	$dh->enable_ipv6($enable_6);
   	$dh->enable_ipv4($enable_4);   

   	# User check
   	if (my $err_msg = &check_user) {
      	&vnx_die("$err_msg\n");
   	}

   	# Deprecation warnings
   	&check_deprecated;

   	# Semantic check (in addition to validation)
   	if (my $err_msg = &check_doc($bd->get_binaries_path_ref,$execution->get_uid)) {
      	&vnx_die ("$err_msg\n");
   	}
   
   	# Validate extended XML configuration files
	# Dynamips
	my $extConfFile = $dh->get_default_dynamips();
	#print "*** dynamipsconf=$extConfFile\n";
	if ($extConfFile ne "0"){
		$extConfFile = vmAPI_dynamips->validateExtXMLFiles($extConfFile);	
	}

   	# 6b (delayed because it required the $dh object constructed)
   	# To check optional screen binaries
   	$bd->add_additional_screen_binaries();
   	if (($opt_e) && ($bd->check_binaries_screen != 0)) {
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
   
   # Read global variables from vnx.conf file
   #&get_vnx_config;
  
   # Initialize vmAPI modules
   vmAPI_uml->init;
   vmAPI_libvirt->init;
   vmAPI_dynamips->init;
  
   
   ###########################################################
   # Initialize plugins
 
   # push (@INC, "@DATADIR@/vnuml/plugins");[JSF]
   push (@INC, "/usr/share/vnx/plugins");
  
   my $extension_list = $dh->get_doc->getElementsByTagName("extension");
   for ( my $i = 0; $i < $extension_list->getLength; $i++ ) {
      my $plugin = $extension_list->item($i)->getAttribute("plugin");
      my $conf = $extension_list->item($i)->getAttribute("conf");
      
      # Check configuration file
      my $effective_conf;
      if ($conf =~ /^\//) {
         # Absolute pathname
         $effective_conf = $conf;
      }
      else {
         # Pathname relative to the place where the VNX spec is ($xml_dir)
         $effective_conf = "$xml_dir/$conf";
      }
      
      # Check input file
      if (! -f $effective_conf) {
         &vnx_die ("plugin $plugin configuration file $effective_conf is not valid (perhaps does not exists)\n");
      }
            
      print "Loading pluging $plugin...\n";      
      # Why we are not using 'use'? See the following thread: 
      # http://www.mail-archive.com/beginners%40perl.org/msg87441.html)   
      
      eval "require $plugin";
      eval "import $plugin";      
      if (my $err_msg = $plugin->createPlugin($mode,$effective_conf)) {
         &vnx_die ("plugin $plugin reports error: $err_msg\n");
      }
      push (@plugins,$plugin);
   }
   
   ###########################################################
   # Command execution

   if ($exeinteractive) {
      print "interactive execution is on: pulse a key after each command\n";
   }

   # Lock management
   if (-f $dh->get_vnx_dir . "/LOCK") {
      my $basename = basename $0;
      &vnx_die($dh->get_vnx_dir . "/LOCK exists: another instance of $basename seems to be in execution\nIf you are sure that this can't be happening in your system, do 'rm " . $dh->get_vnx_dir . "/LOCK' and try again\n");
   }
   else {
      $execution->execute($bd->get_binaries_path_ref->{"touch"} . " " . $dh->get_vnx_dir . "/LOCK");
      $start_time = time();
   }

   # Mode selection

   if ($opt_t||$opt_create) {
	   if ($exemode != $EXE_DEBUG && !$opt_M && !$opt_start) {
         $execution->smartdie ("scenario " . $dh->get_scename . " already created\n") 
            if &scenario_exists($dh->get_scename);
      }
      &mode_define;
      &mode_start;
   }
   elsif ($opt_x||$opt_execute) {
      if ($exemode != $EXE_DEBUG) {
         $execution->smartdie ("scenario " . $dh->get_scename . " does not exists: create it with -t before\n")
           unless &scenario_exists($dh->get_scename);
      }

      &mode_x($cmdseq);
   }
   elsif ($opt_d||$opt_shutdown) {
      if ($exemode != $EXE_DEBUG) {
         $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
           unless &scenario_exists($dh->get_scename);
      }
      &mode_d;
#      my $do_not_build_topology = 1;

      
   }
   elsif ($opt_P||$opt_destroy) {  # elsif ($opt_P) { [JSF]
      if ($exemode != $EXE_DEBUG) {
      #   $execution->smartdie ("scenario $scename does not exist\n")
      #     unless &scenario_exists($scename);
      }
      $args->set('F',1);
      &mode_d;		# First, call destroy mode with force flag activated
      &mode_P;		# Second, purge other things
      #&mode_undefine;
   }
   elsif ($opt_define){
      if ($exemode != $EXE_DEBUG && !$opt_M) {
         $execution->smartdie ("scenario " . $dh->get_scename . " already created\n") 
            if &scenario_exists($dh->get_scename);
      }
      &mode_define;
   }
   elsif ($opt_undefine){
      if ($exemode != $EXE_DEBUG && !$opt_M) {
         $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
           unless &scenario_exists($dh->get_scename);
      }
      &mode_undefine;
   }
   elsif ($opt_start) {
      if ($exemode != $EXE_DEBUG) {
         $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
           unless &scenario_exists($dh->get_scename);
      }
      &mode_start;
   }
   elsif ($opt_reset) {
      if ($exemode != $EXE_DEBUG) {
         $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
           unless &scenario_exists($dh->get_scename);
      }
      $args->set('F',1);
      &mode_d;		# First, call destroy mode with force flag activated
      &mode_P;		# Second, purge other things
      sleep(1);     # Let it finish
      &mode_define;
      &mode_start;
   }
   
   elsif ($opt_reboot) {
     if ($exemode != $EXE_DEBUG) {
        $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        unless &scenario_exists($dh->get_scename);
     }
     &mode_d;
     &mode_start;
   }
   
   elsif ($opt_save) {
     if ($exemode != $EXE_DEBUG) {
        $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        unless &scenario_exists($dh->get_scename);
     }
     &mode_save;
   }
   elsif ($opt_restore) {
     if ($exemode != $EXE_DEBUG) {
        $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        unless &scenario_exists($dh->get_scename);
     }
     &mode_restore;
   }
   
   elsif ($opt_suspend) {
     if ($exemode != $EXE_DEBUG) {
        $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        unless &scenario_exists($dh->get_scename);
     }
     &mode_suspend;
   }
   
   elsif ($opt_resume) {
     if ($exemode != $EXE_DEBUG) {
        $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
        unless &scenario_exists($dh->get_scename);
     }
     &mode_resume;
   }
   
   elsif ($opt_showmap) {
#     if ($exemode != $EXE_DEBUG) {
#        $execution->smartdie ("scenario " . $dh->get_scename . " does not exist\n")
#        unless &scenario_exists($dh->get_scename);
#     }
     &mode_showmap;
   }
   
   elsif ($opt_console) {
		&mode_console;
   }
   elsif ($opt_consoleinfo) {
   		&mode_consoleinfo;
   }
   
   
   else {
      $execution->smartdie("if you are seeing this text something terribly horrible has happened...\n");
   }
   
   # Call the finalize subrutine in plugins
   foreach my $plugin (@plugins) {
      $plugin->finalizePlugin;
   }
   
   # Remove lock
   $execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_vnx_dir . "/LOCK");
   my $total_time = time() - $start_time;
   print "Total time elapsed: $total_time seconds\n";

}




sub mode_define {
	
   my $basename = basename $0;
   my $opt_M = $args->get('M');

   unless ($opt_M ){ #|| $do_not_build){
      &build_topology;
   }


    try {

        # 6. Initialize the notify socket
        my ($sock,$notify_ctl) = &UML_notify_init if ($execution->get_exe_mode() ne $EXE_DEBUG);
        # 7. Set appropriate permissions and boot each UML
        # DFC 21/2/2011 &chown_working_dir;
        &xauth_add;

        &define_VMs($sock,$notify_ctl); #,$only_vm_to_define);    
        # 8. Clean up the notify socket
        &UML_notify_cleanup($sock,$notify_ctl) if ($execution->get_exe_mode() ne $EXE_DEBUG);
        
    } 
    catch Vnx::Exception with {
	   my $E = shift;
	   print $E->as_string;
	   print $E->message;
    
    } 
    catch Error with {
	   my $E = shift;
	   print "ERROR: " . $E->text . " at " . $E->file . ", line " .$E->line;
	   print $E->stringify;
    }
}

sub mode_undefine{
   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      # To get name attribute
      my $name = $vm->getAttribute("name");
      my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));

      unless ($vm_hash{$name}){
          next;
      }      
           
      my $status_file = $dh->get_vm_dir($name) . "/status";
         next if (! -f $status_file);
      my $command = $bd->get_binaries_path_ref->{"cat"} . " $status_file";
      chomp(my $status = `$command`);
      if (!(($status eq "shut off")||($status eq "defined"))){
      	$execution->smartdie ("virtual machine $name cannot be undefined from status \"$status\"\n");
      	next;
      }
      # call the corresponding vmAPI
      my $vmType = $vm->getAttribute("type");
      my $error = "vmAPI_$vmType"->undefineVM($name, $merged_type);
      if (!($error eq 0)){print $error}
   }
}

sub mode_start {

   my $basename = basename $0;

    try {

        # 6. Initialize the notify socket
        my ($sock,$notify_ctl) = &UML_notify_init if ($execution->get_exe_mode() != $EXE_DEBUG);

#        # 7. Set appropriate permissions and boot each UML
#        &chown_working_dir;
#        &xauth_add;

        &start_VMs($sock,$notify_ctl);
         
#        # 8. Clean up the notify socket
#        &UML_notify_cleanup($sock,$notify_ctl) if ($execution->get_exe_mode() != $EXE_DEBUG);

        # If <host_mapping> is in use and not in debug mode, process /etc/hosts
        my $lines = join "\n", @host_lines;
#        &host_mapping_patch ($lines, $dh->get_scename, "/etc/hosts") if (($dh->get_host_mapping) && ($execution->get_exe_mode() != $EXE_DEBUG));
        &host_mapping_patch ($dh->get_scename, "/etc/hosts") if (($dh->get_host_mapping) && ($execution->get_exe_mode() != $EXE_DEBUG)); # lines in the temp file


        # If -B, block until ready
        if ($args->get('B')) {
            my $time_0 = time();
            my %vm_ips = &get_UML_command_ip("");
            while (!&UMLs_cmd_ready(%vm_ips)) {
                #system($bd->get_binaries_path_ref->{"sleep"} . " $dh->get_delay");
                sleep($dh->get_delay);
                my $time_w = time();
                my $interval = $time_w - $time_0;
                print "$interval seconds elapsed...\n" if ($execution->get_exe_mode() == $EXE_VERBOSE);
                %vm_ips = &get_UML_command_ip("");
            }
        }
        
        my $scename = $dh->get_scename;
       	print "\n-----------------------------------------------------------------------------------------\n";	
		print " Scenario \"$scename\" started\n";
        # Print information about vm consoles
        &print_consoles_info;

#[jsf] movido a print_consoles_info
=BEGIN    	
        # Print information about vm consoles
        my @vm_ordered = $dh->get_vm_ordered;
        my $first = 1;
        my $scename = $dh->get_scename;
        for ( my $i = 0; $i < @vm_ordered; $i++) {
			my $vm = $vm_ordered[$i];
			
			my $name = $vm->getAttribute("name");
			my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
			
			if ($first eq 1){
				&print_console_table_header ($scename);
				$first = 0;
			}

			if ( ($vm->getAttribute("type") eq "libvirt") || ( $vm->getAttribute("type") eq "dynamips") ) {
				my $port;
				my $cons0Cmd;
				my $cons1Cmd;
				my $consFile = $dh->get_vm_dir($name) . "/console";
				&print_console_table_entry ($name, $merged_type, $consFile, $vm->getAttribute("type"));
=BEGIN
			if ($merged_type eq "libvirt-kvm-olive"){
				my $port;
				my $portfile = $dh->get_vm_dir($name) . "/console";
				if (-e $portfile ){
					open (CONPORT, "<$portfile") || die "ERROR: No puedo abrir el fichero $portfile";
					$port= <CONPORT>;
					close (CONPORT);
					printf "%-12s  %-20s  telnet localhost %s\n", $name, $merged_type, $port;
				}else {
					printf "%-12s  %-20s  ERROR: cannot open file $portfile \n", $name, $merged_type;
				}
			
			}
			elsif ( ($vm->getAttribute("type") eq "libvirt") && ( $merged_type ne "libvirt-kvm-olive" ) ) {
# DFC			my $vnc_port = 6900 + $i;
# DFC			print $name . ": " . $vnc_port . "\n";
                my $display=`virsh -c qemu:///system vncdisplay $name`;
                $display =~ s/\s+$//;    # Delete linefeed at the end		
				printf "%-12s  %-20s  virt-viewer %s   or   vncviewer %s\n", $name, $merged_type, $name, $display;
=END


			} elsif ( $vm->getAttribute("type") eq "uml") {
			    # xterm -T uml -e screen -t uml /dev/pts/0
			    my $vnx_dir = $dh->get_vnx_dir;
			    my $pts=`cat $vnx_dir/scenarios/$scename/vms/$name/run/pts`;
			    $pts =~ s/\s+$//;        # Delete linefeed at the end
				printf "%-12s  %-20s  xterm -T %s -e screen -t %s %s\n", $name, $merged_type, $name, $name, $pts;
=BEGIN
			} elsif ( $vm->getAttribute("type") eq "dynamips"){
				my $port;
				#$port = 900 + $i;
				my $portfile = $dh->get_vm_dir($name) . "/console";
				if (-e $portfile ){
					open (CONPORT, "<$portfile") || die "ERROR: No puedo abrir el fichero $portfile";
					$port= <CONPORT>;
					close (CONPORT);
					printf "%-12s  %-20s  telnet localhost %s\n", $name, $merged_type, $port;
				}else {
					printf "%-12s  %-20s  ERROR: cannot open file $portfile \n", $name, $merged_type;
				}
=END
=cut
#			}
#		}
        
    } 
    catch Vnx::Exception with {
	   my $E = shift;
	   print $E->as_string;
	   print $E->message;
    
    } 
    catch Error with {
	   my $E = shift;
	   print "ERROR: " . $E->text . " at " . $E->file . ", line " .$E->line;
	   print $E->stringify;
    }
}


sub mode_reset {
	
   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      # To get name attribute
      my $name = $vm->getAttribute("name");
      my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
      
      unless ($vm_hash{$name}){
          next;
      }
      # call the corresponding vmAPI
      my $vmType = $vm->getAttribute("type");
      my $error = "vmAPI_$vmType"->resetVM($name, $merged_type);
      if (!($error eq 0)){print $error}
   }
}

sub mode_save {

   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;
   my $filename;

   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      # To get name attribute
      my $name = $vm->getAttribute("name");
      my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));

      unless ($vm_hash{$name}){
          next;
      }

      $filename = $dh->get_vm_dir($name) . "/" . $name . "_savefile";

      # call the corresponding vmAPI
      my $vmType = $vm->getAttribute("type");
      my $error = "vmAPI_$vmType"->saveVM($name, $merged_type, $filename);
      if (!($error eq 0)){print $error}

   }
}

sub mode_restore {

   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;
   my $filename;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      # To get name attribute
      my $name = $vm->getAttribute("name");
      my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));

      unless ($vm_hash{$name}){
          next;
      }
      
      $filename = $dh->get_vm_dir($name) . "/" . $name . "_savefile";
      #     call the corresponding vmAPI
      my $vmType = $vm->getAttribute("type");
      my $error = "vmAPI_$vmType"->restoreVM($name, $merged_type, $filename);
      if (!($error eq 0)){print $error}
   }
}

sub mode_suspend {

   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      # To get name attribute
      my $name = $vm->getAttribute("name");
      my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));

      unless ($vm_hash{$name}){
          next;
      }
      
      # call the corresponding vmAPI
      my $vmType = $vm->getAttribute("type");
      my $error = "vmAPI_$vmType"->suspendVM($name, $merged_type);
      if (!($error eq 0)){print $error}
   }
}

sub mode_resume {

   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
   	
      my $vm = $vm_ordered[$i];
      # To get name attribute
      my $name = $vm->getAttribute("name");
      my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));

      unless ($vm_hash{$name}){
          next;
      }
      # call the corresponding vmAPI
      my $vmType = $vm->getAttribute("type");
      my $error = "vmAPI_$vmType"->resumeVM($name, $merged_type);
      if (!($error eq 0)){print $error}
   }
}

sub mode_showmap {

   my $scedir  = $dh->get_sim_dir;
   my $scename = $dh->get_scename;
   #print "**** scedir=$scedir\n"; 
   #print "**** file=$input_file\n"; 
   $execution->execute("vnx2dot ${input_file} > ${scedir}/${scename}.dot");
   $execution->execute("neato -Tpng -o${scedir}/${scename}.png ${scedir}/${scename}.dot");
   
   my $gnome=`w -sh | grep gnome-session`;
   my $viewapp;
   if ($gnome ne "") { $viewapp="gnome-open" }
                else { $viewapp="xdg-open" }
   #$execution->execute("eog ${scedir}/${scename}.png");
   $execution->execute("$viewapp ${scedir}/${scename}.png &");

}

sub mode_console {
	
	my @vm_ordered = $dh->get_vm_ordered;
	my %vm_hash = $dh->get_vm_to_use(@plugins);

 	my $scename = $dh->get_scename;
	for ( my $i = 0; $i < @vm_ordered; $i++) {
		my $vm = $vm_ordered[$i];
			
		my $vmName = $vm->getAttribute("name");
		
      	# We have to process it?
      	unless ($vm_hash{$vmName}) {
      		next;
      	}

		my $cid = $args->get('cid');
		#print "*** cid=$cid\n";     
		
		if (defined $cid) {
			if ($cid !~ /con/) {
				$execution->smartdie ("ERROR: console $cid unknown. Try \"vnx -f file.xml --console-info\" to see console names.\n");
			}
			#print "*** opt_cid=$cid\n";		
			VNX::vmAPICommon->start_console ($vmName, $cid);
		} else {
			VNX::vmAPICommon->start_consoles_from_console_file ($vmName);
		}

=BEGIN      			
		my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
		if ( ($vm->getAttribute("type") eq "libvirt") || ( $vm->getAttribute("type") eq "dynamips") ) {
			my $command = "virt-viewer $vmName &";
			system $command;
		} elsif ( $vm->getAttribute("type") eq "uml") {
			my $vnx_dir = $dh->get_vnx_dir;
			my $pts=`cat $vnx_dir/scenarios/$scename/vms/$vmName/run/pts`;
			$pts =~ s/\s+$//;        # Delete linefeed at the end
			my $command = "xterm -T $vmName -e screen -t $vmName $pts &";
			system $command;
		}
=END
=cut
	}
        
}

sub mode_consoleinfo {
	
	&print_consoles_info;
        
}


####################################################################################
# To create TUN/TAP device if virtual switched network more (<net mode="uml_switch">)
sub configure_switched_networks {

    my $doc = $dh->get_doc;
    my $sim_name = $dh->get_scename;

	# Create the symbolic link to the management switch
	if ($dh->get_vmmgmt_type eq 'net') {
		my $sock = $doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("sock");
		$execution->execute($bd->get_binaries_path_ref->{"ln"} . " -s $sock " . $dh->get_networks_dir .
				"/" . $dh->get_vmmgmt_netname . ".ctl" );
	}

    my $net_list = $doc->getElementsByTagName("net");
    for ( my $i = 0; $i < $net_list->getLength; $i++ ) {

       my $command;
       # We get attributes
       my $name    = $net_list->item($i)->getAttribute("name");
       my $mode    = $net_list->item($i)->getAttribute("mode");
       my $sock    = &do_path_expansion($net_list->item($i)->getAttribute("sock"));
       my $external_if = $net_list->item($i)->getAttribute("external");
       my $vlan    = $net_list->item($i)->getAttribute("vlan");
       $command = $net_list->item($i)->getAttribute("uml_switch_binary");

       # Capture related attributes
       my $capture_file = $net_list->item($i)->getAttribute("capture_file");
       my $capture_expression = $net_list->item($i)->getAttribute("capture_expression");
       my $capture_dev = $net_list->item($i)->getAttribute("capture_dev");

       # FIXME: maybe this checking should be put in CheckSemantics, due to at this
       # point, the parses has done some work that need to be undone before exiting
       # (that is what the &mode_d is for)
       if (-f $capture_file) {
       	  &mode_d;
          $execution->smartdie("$capture_file file already exist. Please remove it manually or specify another capture file in the VNX specification.") 
       }

       my $hub     = $net_list->item($i)->getAttribute("hub");

       # This function only processes uml_switch networks
       if ($mode eq "uml_switch") {
       	
       	  # Some case are not supported in the current version
       	  if ((&vnet_exists_sw($name)) && (&check_net_host_conn($name,$dh->get_doc))) {
       	  	print "VNX warning: switched network $name with connection to host already exits. Ignoring.\n" if ($execution->get_exe_mode() == $EXE_VERBOSE);
       	  }
       	  if ((!($external_if =~ /^$/))) {
       	  	print "VNX warning: switched network $name with external connection to $external_if: not implemented in current version. Ignoring.\n" if ($execution->get_exe_mode() == $EXE_VERBOSE);
       	  }
       	
       	  # If uml_switch does not exists, we create and set up it
          unless (&vnet_exists_sw($name)) {
			if ($sock !~ /^$/) {
				$execution->execute($bd->get_binaries_path_ref->{"ln"} . " -s $sock " . $dh->get_networks_dir . "/$name.ctl" );
			} else {
				 my $hub_str = ($hub eq "yes") ? "-hub" : "";
				 my $sock = $dh->get_networks_dir . "/$name.ctl";
				 unless (&check_net_host_conn($name,$dh->get_doc)) {
					# print "VNX warning: no connection to host from virtualy switched net \"$name\". \n" if ($execution->get_exe_mode() == $EXE_VERBOSE);
					# To start virtual switch
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
				       $extra = $extra . " -scenario_name $sim_name $name";
				    }
				
					if (!$command){
				 		$execution->execute_bg($bd->get_binaries_path_ref->{"uml_switch"} . " -unix $sock $hub_str $extra", '/dev/null');
					}
					else{
						$execution->execute_bg($command . " -unix $sock $hub_str $extra", '/dev/null');
					}
					
					if ($execution->get_exe_mode() != $EXE_DEBUG && !&uml_switch_wait($sock, 5)) {
						&mode_d;
						$execution->smartdie("uml_switch for $name failed to start!");
					}
				 }
				 else {
				 	# Only one modprobe tun in the same execution: after checking tun_device_needed. See mode_t subroutine
                    # -----------------------
					# To start tun module
					#!$execution->execute ($bd->get_binaries_path_ref->{"modprobe"} . " tun") or $execution->smartdie ("module tun can not be initialized: $!");

					# We build TUN device name
					my $tun_if = $name;

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
                       $extra = $extra . " -scenario_name $sim_name $name";
                    }

                    if (!$command){
                       $execution->execute_bg($bd->get_binaries_path_ref->{"uml_switch"} . " -tap $tun_if -unix $sock $hub_str $extra", '/dev/null', $group[2]);
                    }
                    else {
				       $execution->execute_bg($command . " -tap $tun_if -unix $sock $hub_str $extra", '/dev/null', $group[2]);
                    }

					if ($execution->get_exe_mode() != $EXE_DEBUG && !&uml_switch_wait($sock, 5)) {
						&mode_d;
						$execution->smartdie("uml_switch for $name failed to start!");
					}
				}
             }
          }

          # We increase interface use counter of the socket
          &inc_cter("$name.ctl");

                #-------------------------------------
                # VLAN setup, NOT TESTED 
                #-------------------------------------
                #unless ($vlan =~ /^$/ ) {
                #    # configure VLAN on this interface
                #   unless (&check_vlan($tun_if,$vlan)) {
                #	    $execution->execute($bd->get_binaries_path_ref->{"modprobe"} . " 8021q");
                #	   $execution->execute($bd->get_binaries_path_ref->{"vconfig"} . " add $tun_if $vlan");
                # }
                #    my $tun_vlan_if = $tun_if . ".$vlan";
                #    $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $tun_vlan_if 0.0.0.0 $dh->get_promisc() up");
                #    # We increase interface use counter
                #    &inc_cter($tun_vlan_if);
                #}           

      }
      
    }

}

######################################################
# To create TUN/TAP devices
sub configure_virtual_bridged_networks {

   # TODO: to considerate "external" atribute when network is "ppp"

   my $doc = $dh->get_doc;
   my @vm_ordered = $dh->get_vm_ordered;

   # 1. Set up tun devices

   for ( my $i = 0; $i < @vm_ordered; $i++) {
      my $vm = $vm_ordered[$i];

      # We get name attribute
      my $name = $vm->getAttribute("name");

      # Only one modprobe tun in the same execution: after checking tun_device_needed. See mode_t subroutine
      # -----------------------
      # To start tun module
      #!$execution->execute ($bd->get_binaries_path_ref->{"modprobe"} . " tun") or $execution->smartdie ("module tun can not be initialized: $!");
     
      # To create management device (id 0), if needed
      my $mng_if_value = &mng_if_value($vm);
      
      if ($dh->get_vmmgmt_type eq 'private' && $mng_if_value ne "no") {
         my $tun_if = $name . "-e0";
         $execution->execute($bd->get_binaries_path_ref->{"tunctl"} . " -u " . $execution->get_uid . " -t $tun_if -f " . $dh->get_tun_device);
      }

      # To get UML's interfaces list
      my $if_list = $vm->getElementsByTagName("if");

      # To process list
      for ( my $j = 0; $j < $if_list->getLength; $j++) {
         my $if = $if_list->item($j);

         # We get attribute
         my $id = $if->getAttribute("id");
	     my $net = $if->getAttribute("net");

         # Only TUN/TAP for interfaces attached to bridged networks
   	     #if (&check_net_br($net)) {
	     if (&get_net_by_mode($net,"virtual_bridge") != 0) {

	        # We build TUN device name
	        my $tun_if = $name . "-e" . $id;

            # To create TUN device
	        $execution->execute($bd->get_binaries_path_ref->{"tunctl"} . " -u " . $execution->get_uid . " -t $tun_if -f " . $dh->get_tun_device);

            # To set up device
            $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $tun_if 0.0.0.0 " . $dh->get_promisc . " up");
                        
	     }
      }
   }
   
   # 2. Create bridges
      
   my $net_list = $doc->getElementsByTagName("net");

   # To process list
   for ( my $i = 0; $i < $net_list->getLength; $i++ ) {

      # We get name attribute
      my $name    = $net_list->item($i)->getAttribute("name");
      my $mode    = $net_list->item($i)->getAttribute("mode");
      my $external_if = $net_list->item($i)->getAttribute("external");
      my $vlan    = $net_list->item($i)->getAttribute("vlan");

      # This function only processes virtual_bridge networks
      if ($mode ne "uml_switch") {

         # If bridged does not exists, we create and set up it
         unless (&vnet_exists_br($name)) {
            $execution->execute($bd->get_binaries_path_ref->{"brctl"} . " addbr $name");
	        if ($dh->get_stp) {
               $execution->execute($bd->get_binaries_path_ref->{"brctl"} . " stp $name on");
	        }
	        else {
               $execution->execute($bd->get_binaries_path_ref->{"brctl"} . " stp $name off");
	        }
	        sleep 1;    # needed in SuSE 8.2
	        $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $name 0.0.0.0 " . $dh->get_promisc . " up");
         }

         # Is there an external interface associated with the network?
         unless ($external_if =~ /^$/) {
            # If there is an external interface associate, to check if VLAN is being used
	        unless ($vlan =~ /^$/ ) {
	           # If there is not any configured VLAN at this interface, we have to enable it
	           unless (&check_vlan($external_if,"*")) {
                  $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $external_if 0.0.0.0 " . $dh->get_promisc . " up");
	           }
	           # If VLAN is already configured at this interface, we haven't to configure it
	           unless (&check_vlan($external_if,$vlan)) {
	              $execution->execute($bd->get_binaries_path_ref->{"modprobe"} . " 8021q");
	              $execution->execute($bd->get_binaries_path_ref->{"vconfig"} . " add $external_if $vlan");
	           }
	           $external_if .= ".$vlan";
	        }
	     
	        # If the interface is already added to the bridge, we haven't to add it
	        my @if_list = &vnet_ifs($name);
	        $_ = "@if_list";
	        unless (/\b($external_if)\b/) {
               $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $external_if 0.0.0.0 " . $dh->get_promisc . " up");
	           $execution->execute($bd->get_binaries_path_ref->{"brctl"} . " addif $name $external_if");
	        }
	        # We increase interface use counter
	        &inc_cter($external_if);
         }
      }
   }
}

######################################################
# To link TUN/TAP to the bridges
sub tun_connect {

   my @vm_ordered = $dh->get_vm_ordered;

   for ( my $i = 0; $i < @vm_ordered; $i++) {
      my $vm = $vm_ordered[$i];

      # We get name attribute
      my $name = $vm->getAttribute("name");

      # To get UML's interfaces list
      my $if_list = $vm->getElementsByTagName("if");

      # To process list
      for ( my $j = 0; $j < $if_list->getLength; $j++) {
         my $if = $if_list->item($j);

         # To get id attribute
         my $id = $if->getAttribute("id");

         # We get net attribute
         my $net = $if->getAttribute("net");
	 
         # Only TUN/TAP for interfaces attached to bridged networks
         #if (&check_net_br($net)) {
         if (&get_net_by_mode($net,"virtual_bridge") != 0) {
	 
	        my $net_if = $name . "-e" . $id;

            # We link TUN/TAP device 
	        $execution->execute($bd->get_binaries_path_ref->{"brctl"} . " addif $net $net_if");
	     }

      }
   }

}

#####################################################
# Host configuration
sub host_config {

   my $doc = $dh->get_doc;

   # If host tag is not present, there is nothing to do
   return if ($doc->getElementsByTagName("host")->getLength eq 0);

   my $host = $doc->getElementsByTagName("host")->item(0);

   # To get host's interfaces list
   my $if_list = $host->getElementsByTagName("hostif");

   # To process list
   for ( my $i = 0; $i < $if_list->getLength; $i++) {
      	my $if = $if_list->item($i);

      	# To get name attribute
      	my $net = $if->getAttribute("net");
      
	  	my $net_mode;
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

		if ($net_mode eq 'uml_switch') {
	  		# Create TUN device
	  		$execution->execute($bd->get_binaries_path_ref->{"tunctl"} . " -t $net -u " . $execution->get_uid . " -f " . $dh->get_tun_device);
		}

      	# Interface configuration
      	# 1a. To process interface IPv4 addresses
      	# The first address have to be assigned without "add" to avoid creating subinterfaces
      	if ($dh->is_ipv4_enabled) {
         	my $ipv4_list = $if->getElementsByTagName("ipv4");
         	my $command = "";
         	for ( my $j = 0; $j < $ipv4_list->getLength; $j++) {
            	my $ip = &text_tag($ipv4_list->item($j));
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
	           		my $ipv4_mask_attr = $ipv4_list->item($j)->getAttribute("mask");
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
                  	 	print "WARNING (host): no mask defined for $ip address of host interface. Using default mask ($ipv4_effective_mask)\n";
	           	}
	       	}
	       
            $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $net $command $ip netmask $ipv4_effective_mask " . $dh->get_promisc);
		    $command = "add";
      	}
   	}

      # 2a. To process interface IPv6 addresses
      my $ipv6_list = $if->getElementsByTagName("ipv6");
      if ($dh->is_ipv6_enabled) {
         for ( my $j = 0; $j < $ipv6_list->getLength; $j++) {
            my $ip = &text_tag($ipv6_list->item($j));
            if (&valid_ipv6_with_mask($ip)) {
	           # Implicit slashed mask in the address
	           $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $net inet6 add $ip");
	        }
	        else {
	           # Check the value of the mask attribute
 	           my $ipv6_effective_mask = "/64"; # Default mask value	       
	           my $ipv6_mask_attr = $ipv6_list->item($j)->getAttribute("mask");
	           if ($ipv6_mask_attr ne "") {
	              # Note that, in the case of IPv6, mask are always slashed
                  $ipv6_effective_mask = $ipv6_mask_attr;
	           }
	           $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $net inet6 add $ip$ipv6_effective_mask");
	           
	        }
	     }
      }
   }

   # To get host's routes list
   my $route_list = $host->getElementsByTagName("route");
   for ( my $i = 0; $i < $route_list->getLength; $i++) {
       my $route_dest = &text_tag($route_list->item($i));;
       my $route_gw = $route_list->item($i)->getAttribute("gw");
       my $route_type = $route_list->item($i)->getAttribute("type");
       # Routes for IPv4
       if ($route_type eq "ipv4") {
          if ($dh->is_ipv4_enabled) {
             if ($route_dest eq "default") {
                $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet add default gw $route_gw");
             } 
             elsif ($route_dest =~ /\/32$/) {
	        # Special case: X.X.X.X/32 destinations are not actually nets, but host. The syntax of
		# route command changes a bit in this case
                $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet add -host $route_dest gw $route_gw");
	     }
	     else {
                $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet add -net $route_dest gw $route_gw");
             }
             #$execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet add $route_dest gw $route_gw");
          }
       }
       # Routes for IPv6
       else {
          if ($dh->is_ipv6_enabled) {
             if ($route_dest eq "default") {
                $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet6 add 2000::/3 gw $route_gw");
             }
             else {
                $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet6 add $route_dest gw $route_gw");
             }
          }
       }
    }

    # Enable host forwarding
    my $forwarding = $host->getElementsByTagName("forwarding");
    if ($forwarding->getLength == 1) {
       my $f_type = $forwarding->item(0)->getAttribute("type");
       $f_type = "ip" if ($f_type =~ /^$/);
       if ($dh->is_ipv4_enabled) {
          $execution->execute($bd->get_binaries_path_ref->{"echo"} . " 1 > /proc/sys/net/ipv4/ip_forward") if ($f_type eq "ip" or $f_type eq "ipv4");
       }
       if ($dh->is_ipv6_enabled) {
          $execution->execute($bd->get_binaries_path_ref->{"echo"} . " 1 > /proc/sys/net/ipv6/conf/all/forwarding") if ($f_type eq "ip" or $f_type eq "ipv6");
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
		$execution->execute($bd->get_binaries_path_ref->{"chown"} . " -R " . $execution->get_uid . " " . $dh->get_vnx_dir);
	}
}

######################################################
# Check to see if any of the UMLs use xterm in console tags
sub xauth_needed {

	my $vm_list = $dh->get_doc->getElementsByTagName("vm");
	for (my $i = 0; $i < $vm_list->getLength; $i++) {
	   my @console_list = $dh->merge_console($vm_list->item($i));
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
		$execution->execute($bd->get_binaries_path_ref->{"echo"} . " add `" .
			 $bd->get_binaries_path_ref->{"xauth"} . " list $ENV{DISPLAY}` | su -s /bin/sh -c " .
			 $bd->get_binaries_path_ref->{"xauth"} . " " . getpwuid($execution->get_uid));
	}
}

# Remove the effective user xauth privileges on the current display
sub xauth_remove {
	if ($> == 0 && $execution->get_uid != 0 && &xauth_needed) {

		$execution->execute("su -s /bin/sh -c '" . $bd->get_binaries_path_ref->{"xauth"} . " remove $ENV{DISPLAY}' " . getpwuid($execution->get_uid));
	}

}

######################################################
# Initialize socket for listening
sub UML_notify_init {
	my $sock;
	my $flags;
	my $notify_ctl;

	my $command = $bd->get_binaries_path_ref->{"mktemp"} . " -p " . $dh->get_tmp_dir . " vnx_notify.ctl.XXXXXX";
	chomp($notify_ctl = `$command`);

	# create socket
	!defined(socket($sock, AF_UNIX, SOCK_DGRAM, 0)) and 
		$execution->smartdie("socket() failed : $!");


	# bind socket to file
	unlink($notify_ctl);
	!defined(bind($sock, sockaddr_un($notify_ctl))) and 
		$execution->smartdie("binding '$notify_ctl' failed : $!");
	
	# give the socket ownership of the effective uid, if the current user is root
	if ($> == 0) {
		$execution->execute($bd->get_binaries_path_ref->{"chown"} . " " . $execution->get_uid . " " . $notify_ctl);
	}

	return ($sock, $notify_ctl);
}

######################################################
# Clean up listen socket
sub UML_notify_cleanup {
	my $sock = shift;
	my $notify_ctl = shift;

	close($sock);
	unlink $notify_ctl;
}


# no utilizado
#sub boot_VMs {
#
#   my $sock = shift;
#   my $notify_ctl = shift;
#   
#   my @vm_ordered = $dh->get_vm_ordered;
#   my %vm_hash = $dh->get_vm_to_use;
#
#   my $dom;
#   
#   # If defined screen configuration file, open it
#   if (($args->get('e')) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
#      open SCREEN_CONF, ">". $args->get('e')
#         or $execution->smartdie ("can not open " . $args->get('e') . ": $!")
#   }
#
#   #contador para management ip, lo necesita el código de bootfiles que está pasado al API.
#   #se pasa al API en la llamada al CreateVM
#   my $manipcounter = 0;
#   
#   my $docstring;
#   
#   for ( my $i = 0; $i < @vm_ordered; $i++) {
#      my $vm = $vm_ordered[$i];
#      my $name = $vm->getAttribute("name");
#      unless ($vm_hash{$name}){
#         next;       
#      }
#      my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
#      $curr_uml = $name;
#      $docstring = &make_vm_API_doc($vm,$notify_ctl,$i);
#      # call the corresponding vmAPI
#      my $vmType = $vm->getAttribute("type");
#      my $error = "vmAPI_$vmType"->createVM($name, $merged_type, $docstring, $execution, $bd, $dh,$sock, $manipcounter);
#      if (!($error eq 0)){print $error}	
#      $manipcounter++;	  
#      undef($curr_uml);
#
#      &change_vm_status($dh,$name,"running");
#      
#   }
#
#   # Close screen configuration file
#   if (($args->get('e')) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
#      close SCREEN_CONF;
#   }
#
#}


sub define_VMs {

   my $sock = shift;
   my $notify_ctl = shift;
   
   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;

   my $dom;
   
   # If defined screen configuration file, open it
   if (($args->get('e')) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
      open SCREEN_CONF, ">". $args->get('e')
         or $execution->smartdie ("can not open " . $args->get('e') . ": $!")
   }

   #management ip counter
   my $manipcounter = 0;
   
   #passed as parameter to API
   #   equal to $manipcounter if no mng_if file found
   #   value "file" if mng_if file found in run dir
   my $manipdata;
   
   my $docstring;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {

      my $vm = $vm_ordered[$i];
      my $name = $vm->getAttribute("name");
      unless ($vm_hash{$name}){
         next;       
      }

      my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
      $curr_uml = $name;
      $docstring = &make_vm_API_doc($vm,$notify_ctl,$i,$manipcounter);	
      # Save the XML <create_conf> file to .vnx/scenarios/<vscenario_name>/vms/$name_cconf.xml
	  open XML_CCFILE, ">" . $dh->get_vm_dir($name) . '/' . $name . '_cconf.xml'
		  or $execution->smartdie("can not open " . $dh->get_vm_dir . '/' . $name . '_cconf.xml' )
		    unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
	  print XML_CCFILE "$docstring\n";
	  close XML_CCFILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
	  
	  # check for existing management ip file stored in run dir
	  if (-f $dh->get_vm_dir($name) . '/mng_ip'){
	  	$manipdata = "file";	  	
	  }else{
	  	$manipdata = $manipcounter;
	  }
        
      # call the corresponding vmAPI
      my $vmType = $vm->getAttribute("type");
      my $error = "vmAPI_$vmType"->defineVM($name, $merged_type, $docstring, $sock, $manipdata);
      if (!($error eq 0)){print $error}
      $manipcounter++ unless ($manipdata eq "file"); #update only if current value has been used
      undef($curr_uml);
      &change_vm_status($name,"defined");

   }

   # Close screen configuration file
   if (($args->get('e')) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
      close SCREEN_CONF;
   }
}

sub merge_vm_type {
	my $type = shift;
	my $subtype = shift;
	my $os = shift;
	my $merged_type = $type;
	
	if (!($subtype eq "")){
		$merged_type = $merged_type . "-" . $subtype;
		if (!($os eq "")){
			$merged_type = $merged_type . "-" . $os;
		}
	}
	return $merged_type;
	
}

sub start_VMs {

   my $sock = shift; # only needed for uml vms
   my $notify_ctl = shift; # only needed for uml vms
   
   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;
   my $opt_M = $args->get('M');
 
   # If defined screen configuration file, open it
   if (($args->get('e')) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
      open SCREEN_CONF, ">". $args->get('e')
         or $execution->smartdie ("can not open " . $args->get('e') . ": $!")
   }

   #management ip counter needed in API
   my $manipcounter = 0; # only needed for uml vms
   my $docstring; # only needed for uml vms
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {

      my $vm = $vm_ordered[$i];
      my $name = $vm->getAttribute("name");

      unless ($vm_hash{$name}){
         next;       
      }

      my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
      
      # search for <on_boot> tag and if found then process it
      my $on_boot; 
      eval {$on_boot = $vm->getElementsByTagName("on_boot")->item(0)->getFirstChild->getData};
	  # DFC if ($on_boot eq "define"){
	  if (defined $on_boot){
	  	# do not start vm unless specified in -M
      	unless ($opt_M =~ /^$name,|,$name,|,$name$|^$name$/) {
			next;
	    }
	  }

      
      $curr_uml = $name;
      
      $docstring = &make_vm_API_doc($vm,$notify_ctl,$i,$manipcounter); # only needed for uml vms
      
      #check for option -n||--no_console (do not start consoles)
      my $no_console = "0";
      if ($args->get('n')||$args->get('no_console')){
      	$no_console = "1";
      }
       
      # call the corresponding vmAPI
      my $vmType = $vm->getAttribute("type");
      my $error = "vmAPI_$vmType"->startVM($name, $merged_type, $docstring, $sock, $manipcounter, $no_console);
      if (!($error eq 0)){print $error} 
      $manipcounter++;
      undef($curr_uml);
      #&change_vm_status($dh,$name,"running");
      &change_vm_status($name,"running");

   }

   # Close screen configuration file
   if (($args->get('e')) && ($execution->get_exe_mode() != $EXE_DEBUG)) {
      close SCREEN_CONF;
   }

}



#####################################################

# mode_x
#
# exec commands mode
#
sub mode_x {
	my $seq = shift;
	
	my %vm_ips;
	
	# If 'seq' tag is found in any vm, switch value to '1'
	my $seq_found = 0;

   # If -B, block until ready
   if ($args->get('B')) {
      my $time_0 = time();
      %vm_ips = &get_UML_command_ip($seq);
      while (!&UMLs_cmd_ready(%vm_ips)) {
         #system($bd->get_binaries_path_ref->{"sleep"} . " $dh->get_delay");
         sleep($dh->get_delay);
         my $time_f = time();
         my $interval = $time_f - $time_0;
         print "$interval seconds elapsed...\n" if ($execution->get_exe_mode() eq $EXE_VERBOSE);
         %vm_ips = &get_UML_command_ip($seq);
      }
   }
   else {
      %vm_ips = &get_UML_command_ip($seq);
      $execution->smartdie ("some vm is not ready to exec sequence $seq through net. Wait a while and retry...\n") 
         unless &UMLs_cmd_ready(%vm_ips);
   }
   
   
	#my $error = vmAPI->executeCMD($seq, $execution, $bd, $dh,%vm_ips);

	
	#Commands sequence (start, stop or whatever).

	# Previous checkings and warnings
	my @vm_ordered = $dh->get_vm_ordered;
	
		my %vm_hash    = $dh->get_vm_to_use(@plugins);
	
	# First loop: look for uml_mconsole exec capabilities if needed. This
	# loop can cause exit, if capabilities are not accomplished
	for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
		my $vm = $vm_ordered[$i];
		# We get name attribute
		my $name = $vm->getAttribute("name");

		# We have to process it?
		unless ( $vm_hash{$name} ) {
			next;
		}
		
		# 'seq' tag was found
		$seq_found = 1;
		
		my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
		# call the corresponding vmAPI
    	my $vmType = $vm->getAttribute("type");

    	#my $error = "vmAPI_$vmType"->executeCMD($merged_type, $seq, $execution, $bd, $dh, $vm, $name);
    	my $error = "vmAPI_$vmType"->executeCMD($merged_type, $seq, $vm, $name, %vm_ips);
     	if (!($error eq 0)){
     		print $error
		}
	}
	
	if ($seq_found eq 0){
		$execution->smartdie("Sequence $seq not found. Exiting");
	}

	#vmAPI_uml->exec_command_host($seq,$execution,$bd,$dh);
	exec_command_host($seq);
}


#####################################################

# mode_d
#
# Destroy current scenario mode 
sub mode_d {

   # Since version 1.4.0, UML must be halted before the routes to the UMLs disapear with the unconfiguration,
   # to allow SSH halt when <mng_if>no</mng_if> is used. Anyway, problems still, if one VM that is routing
   # traffic to other is halted first, for example.
   
###############################################################

   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;
   my $vmleft = 0;
   my $only_vm = "";
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {

      my $vm = $vm_ordered[$i];
      # To get name attribute
      my $name = $vm->getAttribute("name");

      my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
      
      unless ($vm_hash{$name}){
          $vmleft = 1;
          next;
      }

      if ($args->get('M')){
         $only_vm = $name;  	
      }
      
      if ($args->get('F')){

           # call the corresponding vmAPI
           my $vmType = $vm->getAttribute("type");
           #my $error = "vmAPI_$vmType"->destroyVM($name, $merged_type, $execution, $bd,$dh);
           my $error = "vmAPI_$vmType"->destroyVM($name, $merged_type);
           if (!($error eq 0)){print $error}
      }
      else{
           # call the corresponding vmAPI
           my $vmType = $vm->getAttribute("type");
           #my $error = "vmAPI_$vmType"->shutdownVM($name, $merged_type, $execution, $bd,$dh,$args->get('F'));
           my $error = "vmAPI_$vmType"->shutdownVM($name, $merged_type, $args->get('F'));
           if (!($error eq 0)){print $error}
          
      }

   }
   
#   unless ($args->get('M')){

      # For non-forced mode, we have to wait all UMLs dead before to destroy 
      # TUN/TAP (next step) due to these devices are yet in use
      #
      # Note that -B doensn't affect to this functionallity. UML extinction
      # blocks can't be avoided (is needed to perform bridges and interfaces
      # release)
      my $time_0 = time();
      
      if ((!$args->get('F'))&&($execution->get_exe_mode() != $EXE_DEBUG)) {		

         print "---------- Waiting until virtual machines extinction ----------\n"; #if ($execution->get_exe_mode() == $EXE_VERBOSE);

         while (my $pids = &VM_alive($only_vm)) {
            print "waiting on processes $pids...\n"; #if ($execution->get_exe_mode() == $EXE_VERBOSE);
            #system($bd->get_binaries_path_ref->{"sleep"} . " $dh->get_delay");
            sleep($dh->get_delay);
            my $time_f = time();
            my $interval = $time_f - $time_0;
            print "$interval seconds elapsed...\n"; #if ($execution->get_exe_mode() == $EXE_VERBOSE);
         }       
      }

#      if (($args->get('F'))&(!($args->get('M'))))   {
      if (!($args->get('M')))   {

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
               my $sock = &do_path_expansion($dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("sock"));
               if (-S $sock) {
                  # Destroy the socket
                  &mgmt_sock_destroy($sock,$dh->get_vmmgmt_autoconfigure);
               }
            }
            else {
               print "VNX warning: <mgmt_net> autoconfigure attribute only is used when VNX parser is invoked by root. Ignoring socket autodestruction\n";
            }
         }

         # If <host_mapping> is in use and not in debug mode, process /etc/hosts
         &host_mapping_unpatch ($dh->get_scename, "/etc/hosts") if (($dh->get_host_mapping) && ($execution->get_exe_mode() != $EXE_DEBUG));

         # To remove lock file (it exists while topology is running)
         $execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_sim_dir . "/lock");
      }

}

######################################################
# To restore host configuration

sub host_unconfig {

   my $doc = $dh->get_doc;

   # If host <host> is not present, there is nothing to unconfigure
   return if ($doc->getElementsByTagName("host")->getLength eq 0);

   # To get <host> tag
   my $host = $doc->getElementsByTagName("host")->item(0);

   # To get host routes list
   my $route_list = $host->getElementsByTagName("route");
   for ( my $i = 0; $i < $route_list->getLength; $i++) {
       my $route_dest = &text_tag($route_list->item($i));;
       my $route_gw = $route_list->item($i)->getAttribute("gw");
       my $route_type = $route_list->item($i)->getAttribute("type");
       # Routes for IPv4
       if ($route_type eq "ipv4") {
          if ($dh->is_ipv4_enabled) {
             if ($route_dest eq "default") {
                $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet del $route_dest gw $route_gw");
             } 
             elsif ($route_dest =~ /\/32$/) {
	        # Special case: X.X.X.X/32 destinations are not actually nets, but host. The syntax of
		# route command changes a bit in this case
                $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet del -host $route_dest gw $route_gw");
	     }
             else {
                $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet del -net $route_dest gw $route_gw");
             }
             #$execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet del $route_dest gw $route_gw");
          }
       }
       # Routes for IPv6
       else {
          if ($dh->is_ipv6_enabled) {
             if ($route_dest eq "default") {
                $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet6 del 2000::/3 gw $route_gw");
             }
             else {
                $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet6 del $route_dest gw $route_gw");
             }
          }
       }
   }

   # To get host interfaces list
   my $if_list = $host->getElementsByTagName("hostif");

   # To process list
   for ( my $i = 0; $i < $if_list->getLength; $i++) {
	   	my $if = $if_list->item($i);

	   	# To get name attribute
	   	my $net = $if->getAttribute("net");

	  	my $net_mode;
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

	   	# Destroy the tun device
	   	#print "*** host_unconfig\n";
		if ($net_mode eq 'uml_switch') {
	   		$execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $net down");
			$execution->execute($bd->get_binaries_path_ref->{"tunctl"} . " -d $net -f " . $dh->get_tun_device);
		}
   }

}



######################################################
# To remove external interfaces

sub external_if_remove {

   my $doc = $dh->get_doc;

   # To get list of defined <net>
   my $net_list = $doc->getElementsByTagName("net");

   # To process list, decreasing use counter of external interfaces
   for ( my $i = 0; $i < $net_list->getLength; $i++ ) {
      my $net = $net_list->item($i);

      # To get name attribute
      my $name = $net->getAttribute("name");

      # We check if there is an associated external interface
      my $external_if = $net->getAttribute("external");
      next if ($external_if =~ /^$/);

      # To check if VLAN is being used
      my $vlan = $net->getAttribute("vlan");
      $external_if .= ".$vlan" unless ($vlan =~ /^$/);

      # To decrease use counter
      &dec_cter($external_if);

      # To clean up not in use physical interfaces
      if (&get_cter($external_if) == 0) {
         $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $name 0.0.0.0 " . $dh->get_promisc . " up");
         $execution->execute($bd->get_binaries_path_ref->{"brctl"} . " delif $name $external_if");
	 unless ($vlan =~ /^$/) {
	    $execution->execute($bd->get_binaries_path_ref->{"vconfig"} . " rem $external_if");
	 }
	 else {
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
		$execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f $socket_file");
	}

   my $net_list = $doc->getElementsByTagName("net");

   for ( my $i = 0 ; $i < $net_list->getLength; $i++ ) {

      # We get attributes
      my $name    = $net_list->item($i)->getAttribute("name");
      my $mode    = $net_list->item($i)->getAttribute("mode");
      my $sock    = $net_list->item($i)->getAttribute("sock");
      my $vlan    = $net_list->item($i)->getAttribute("vlan");
      my $cmd;
      
      # This function only processes uml_switch networks
      if ($mode eq "uml_switch") {

         # Decrease the use counter
         &dec_cter("$name.ctl");
            
         # Destroy the uml_switch only when no other concurrent scenario is using it
         if (&get_cter ("$name.ctl") == 0) {
         	my $socket_file = $dh->get_networks_dir() . "/$name.ctl";
         	# Casey (rev 1.90) proposed to use -f instead of -S, however 
         	# I've performed some test and it fails... let's use -S?
     		#if ($sock eq '' && -f $socket_file) {
			if ($sock eq '' && -S $socket_file) {
				$cmd = $bd->get_binaries_path_ref->{"kill"} . " `" .
					$bd->get_binaries_path_ref->{"lsof"} . " -t $socket_file`";
				$execution->execute($cmd);
				sleep 1;
			}
	        $execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f $socket_file");
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

      # To get name attribute
      my $name = $vm->getAttribute("name");

      # To throw away and remove management device (id 0), if neeed
      #my $mng_if_value = &mng_if_value($dh,$vm);
      my $mng_if_value = &mng_if_value($vm);
      
      if ($dh->get_vmmgmt_type eq 'private' && $mng_if_value ne "no") {
         my $tun_if = $name . "-e0";
         $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $tun_if down");
         $execution->execute($bd->get_binaries_path_ref->{"tunctl"} . " -d $tun_if -f " . $dh->get_tun_device);
      }

      # To get UML's interfaces list
      my $if_list = $vm->getElementsByTagName("if");

      # To process list
      for ( my $j = 0; $j < $if_list->getLength; $j++) {
         my $if = $if_list->item($j);

         # To get attributes
         my $id = $if->getAttribute("id");
         my $net = $if->getAttribute("net");

         # Only exists TUN/TAP in a bridged network
         #if (&check_net_br($net)) {
         if (&get_net_by_mode($net,"virtual_bridge") != 0) {
            # To build TUN device name
            my $tun_if = $name . "-e" . $id;

            # To throw away TUN device
            $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $tun_if down");

            # To remove TUN device
            #print "*** tun_destroy\n";
            $execution->execute($bd->get_binaries_path_ref->{"tunctl"} . " -d $tun_if -f " . $dh->get_tun_device);

         }

      }

   }

}

######################################################
# To remove bridges

sub bridges_destroy {

   my $doc = $dh->get_doc;

   # To get list of defined <net>
   my $net_list = $doc->getElementsByTagName("net");

   # To process list, decreasing use counter of external interfaces
   for ( my $i = 0; $i < $net_list->getLength; $i++ ) {

      # To get attributes
      my $name = $net_list->item($i)->getAttribute("name");
      my $mode = $net_list->item($i)->getAttribute("mode");

      # This function only processes uml_switch networks
      if ($mode ne "uml_switch") {

         # Set bridge down and remove it only in the case there isn't any associated interface 
         if (&vnet_ifs($name) == 0) {
            $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $name down");
            $execution->execute($bd->get_binaries_path_ref->{"brctl"} . " delbr $name");
         }
      }
   }
}




sub mode_P {
   
   my $vm_left = 0;
   my @vm_ordered = $dh->get_vm_ordered;
   my %vm_hash = $dh->get_vm_to_use;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {

        my $vm = $vm_ordered[$i];

        # To get name attribute
        my $name = $vm->getAttribute("name");
        my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
        unless ($vm_hash{$name}){
            $vm_left = 1;
            next;
        }
        # call the corresponding vmAPI
        my $vmType = $vm->getAttribute("type");
        
        my $error = "vmAPI_$vmType"->undefineVM($name, $merged_type);
        if (!($error eq 0)){print $error}
 
    }
    if ( ($vm_left eq 0) && (!$args->get('M') ) ) {
        # 3. Delete supporting scenario files...
	#    ...but only if -M option is not active (DFC 27/01/2010)

        $execution->execute($bd->get_binaries_path_ref->{"rm"} . " -rf " . $dh->get_sim_dir . "/*");
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
	my $net_list = $doc->getElementsByTagName("net");
	for (my $i = 0; $i < $net_list->getLength; $i++) {
		if ($net_list->item($i)->getAttribute("mode") ne "uml_switch") {
			my $name = $net_list->item($i)->getAttribute("name");
			return "$name is a bridge_virtual net and only uml_switch virtual networks can be used by no-root users when running $basename";
		}
	}
	
    # Search for managemente interfaces (management interfaces needs ifconfig in the host
    # side, and no-root user can not use it)
	#my $name = &at_least_one_vm_with_mng_if($dh,$dh->get_vm_ordered);
	my $name = &at_least_one_vm_with_mng_if($dh->get_vm_ordered);
    if ($dh->get_vmmgmt_type eq 'private' && $name ne '') {
    	return "private vm management is enabled, and only root can configure management interfaces\n
		Try again using <mng_if>no</mng_if> for virtual machine $name or use net type vm management";
    }

    # Search for host configuration (no-root user can not perform any configuration in the host)
    my $host_list = $doc->getElementsByTagName("host");
    if ($host_list->getLength == 1) {
    	return "only root user can perform host configuration. Try again removing <host> tag.";
    }
    
    # Search for host_mapping (no-root user can not touch /etc/host)
    my $host_map_list = $doc->getElementsByTagName("host_mapping");
    if ($host_map_list->getLength == 1) {
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
	
    # By the moment, no check is required
    
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
		my $name = $vm->getAttribute("name");

		if ($only_vm ne '' && $only_vm ne $name){
			next;
		}

		my $pid_file = $dh->get_run_dir($name) . "/pid";
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
   $execution->execute($bd->get_binaries_path_ref->{"mv"} . " $file_name $file_bk");
   $execution->execute($bd->get_binaries_path_ref->{"cat"} . " " . $dh->get_tmp_dir . "/hostfile.1 " . $dh->get_tmp_dir . "/hostfile.2 " . $dh->get_tmp_dir . "/hostfile.3 > $file_name");

   $execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/hostfile.1 " . $dh->get_tmp_dir . "/hostfile.2 " . $dh->get_tmp_dir . "/hostfile.3");

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

   # DEBUG
   #print "--filename: $file_name\n";
   #print "--scename:  $scename\n";

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
   $execution->execute($bd->get_binaries_path_ref->{"mv"} . " $file_name $file_bk");
   $execution->execute($bd->get_binaries_path_ref->{"cat"} . " " . $dh->get_tmp_dir . "/hostfile.1 " . $dh->get_tmp_dir . "/hostfile.2 " . $dh->get_tmp_dir . "/hostfile.3 > $file_name");
   $execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_tmp_dir . "/hostfile.1 " . $dh->get_tmp_dir . "/hostfile.2 " . $dh->get_tmp_dir . "/hostfile.3");

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
   
   my $pipe = $bd->get_binaries_path_ref->{"ps"} . " --no-headers -p $pids_string 2> /dev/null|";   ## Avoiding strange warnings in the ps list
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
# Result
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
#   are considered (this use to be the case when invoked from mode_x). If a 
#   empty command sequence is passed, then all vms are considered, no matter 
#   if they have <exec> tags (this use to be the case when invoked from mode_t).

sub get_UML_command_ip {

   my $seq = shift;
   
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
      my $name = $vm->getAttribute("name");
	 
	  # If seq not empty then check vm only uses exec_mode="net"
	  unless ($seq eq "") {

		unless (defined &get_vm_exec_mode($vm) && &get_vm_exec_mode($vm) eq "net") {
	        $counter++;
	        next;
	     }
	  }
	 
      # To look for UMLs IP in -M list
      if ($vm_hash{$name}) {

         if ($execution->get_exe_mode() == $EXE_DEBUG) {
            $vm_ips{$name} = "(undefined in debug time)";
	       $counter++;
               next;
            }
	    
            # By default, until assinged, there is no IP address for this machine
            $vm_ips{$name} = "0"; 
	 
            # To check whether management interface exists
            #if ($dh->get_vmmgmt_type eq 'none' || &mng_if_value($dh,$vm) eq "no") {
            if ($dh->get_vmmgmt_type eq 'none' || &mng_if_value($vm) eq "no") {
	 
               # There isn't management interface, check <if>s in the virtual machine
               my $ip_candidate = "0";
               
               # Note that disabling IPv4 didn't assign addresses in scenario
               # interfaces, so the search can be avoided
               if ($dh->is_ipv4_enabled) {
                  my $if_list = $vm->getElementsByTagName("if");
                  for ( my $i = 0; $i < $if_list->getLength; $i++ ) {
                     my $if = $if_list->item($i);
                     my $id = $if->getAttribute("id");
                     my $ipv4_list = $if->getElementsByTagName("ipv4");
                     for ( my $i = 0; $i < $ipv4_list->getLength; $i++ ) {
                        my $ip = &text_tag($ipv4_list->item($i));
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
                           print "$name sshd is ready (socket style): $ip_effective (if id=$id)\n" if ($execution->get_exe_mode() == $EXE_VERBOSE);
                           last;
                        }
                     }
		             # If some IP was found, we don't need to search for more
		             last if ($ip_candidate ne "0");
                  }
               }
	           if ($ip_candidate eq "0") {
                  print "$name sshd is not ready (socket style)\n" if ($execution->get_exe_mode() == $EXE_VERBOSE);
	           }
               $vm_ips{$name} = $ip_candidate;
            }
            else {
               # There is a management interface
               print "*** get_admin_address($counter, $dh->get_vmmgmt_type, 2)\n";
               my $net = &get_admin_address($counter, $dh->get_vmmgmt_type, 2);
               if (!&socket_probe($net->addr(),"22")) {
                  print "$name sshd is not ready (socket style)\n" if ($execution->get_exe_mode() == $EXE_VERBOSE);
                  return %vm_ips;	# Premature exit
               }
               else {
                  print "$name sshd is ready (socket style): ".$net->addr()." (mng_if)\n" if ($execution->get_exe_mode() == $EXE_VERBOSE);
                  $vm_ips{$name} = $net->addr();
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

      my $automac_list = $doc->getElementsByTagName("automac");
      # If tag is not in use, return empty string
      if ($automac_list->getLength == 0) {
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
      my $mac = "02:fd:$upper_offset:$lower_offset:$ante_lower:$lower";
      # expandir mac con ceros a:b:c:d:e:f -> 0a:0b:0c:0d:0e:0f
      $mac =~ s/(^|:)(?=[0-9a-fA-F](?::|$))/${1}0/g;
      $mac = "," . $mac;
      print "*** MAC=$mac\n";
      return $mac 

}

sub automac_OLD {

      my $ante_lower = shift;
      my $lower = shift;

      my $doc = $dh->get_doc;

      my $automac_list = $doc->getElementsByTagName("automac");
      # If tag is not in use, return empty string
      if ($automac_list->getLength == 0) {
         return "";
      }

           # Assuming offset is in the 0-65535 range
      #my $upper_offset = dec2hex(int($dh->get_automac_offset / 256));
      #my $lower_offset = dec2hex($dh->get_automac_offset % 256);
      
      # JSF 16/11
      my $upper_offset = sprintf("%x",int($dh->get_automac_offset / 256));
      my $lower_offset = sprintf("%x",$dh->get_automac_offset % 256);

      # DFC 26/11/2010: En Ubuntu 10.04 y con las versiones 0.8.3, 0.8.4 y 0.8.5 hay un problema 
      # de conectividad entre máquinas virtuales. Cuando se arrancan los ejemplos simple_*
      # las vm tienen conectividad con el host pero no entre ellas.
      # Parece que tienen que ver con la elección de las direcciones MAC en los interfaces
      # tun/tap (ver https://bugs.launchpad.net/ubuntu/+source/libvirt/+bug/579892)
      # Una solución temporal es cambiar las direcciones a un número más bajo: fe:fd -> 02:fd
      # return ",fe:fd:$upper_offset:$lower_offset:$ante_lower:$lower";
      return ",02:fd:$upper_offset:$lower_offset:$ante_lower:$lower";

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
   my $phyif_list = $doc->getElementsByTagName("physicalif");

   # To process list
   for ( my $i = 0; $i < $phyif_list->getLength; $i++ ) {
      my $phyif = $phyif_list->item($i);

      my $name = $phyif->getAttribute("name");
      if ($name eq $interface) {
      	 my $type = $phyif->getAttribute("type");
      	 if ($type eq "ipv6") {
      	 	#IPv6 configuration
      	 	my $ip = $phyif->getAttribute("ip");
      	 	my $gw = $phyif->getAttribute("gw");
      	 	$execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $interface add $ip");
      	 	unless ($gw =~ /^$/ ) {
               $execution->execute($bd->get_binaries_path_ref->{"route"} . " -A inet6 add 2000::/3 gw $gw");	        
      	 	}
      	 }
      	 else {
      	 	#IPv4 configuration
      	 	my $ip = $phyif->getAttribute("ip");
	        my $gw = $phyif->getAttribute("gw");
   	        my $mask = $phyif->getAttribute("mask");
            $mask="255.255.255.0" if ($mask =~ /^$/);
	        $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $interface $ip netmask $mask");
       	 	unless ($gw =~ /^$/ ) {
	           $execution->execute($bd->get_binaries_path_ref->{"route"} . " add default gw $gw");
       	 	}
      	 }
      }
   }
}

# exists_scenario
#
# Returns true if the scenario (first argument) is currently running
#
# In the current version, this check is perform looking for the lock file
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
   my $net_list = $doc->getElementsByTagName("net");

   # To process list
   for ( my $i = 0; $i < $net_list->getLength; $i++ ) {
   	  my $net = $net_list->item($i);
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

# vnet_exists_br
#
# If the virtual network (implemented with a bridge) whose name is given
# as first argument exists, returns 1. In other case, returns 0.
#
# It based in `brctl show` parsing.
sub vnet_exists_br {

   my $vnet_name = shift;

   # To get `brctl show`
   my @brctlshow;
   my $line = 0;
   my $pipe = $bd->get_binaries_path_ref->{"brctl"} . " show |";
   open BRCTLSHOW, "$pipe";
   while (<BRCTLSHOW>) {
      chomp;
      $brctlshow[$line++] = $_;
   }
   close BRCTLSHOW;

   # To look for virtual network processing the list
   # Note that we skip the first line (due to this line is the header of
   # brctl show: bridge name, brige id, etc.)
   for ( my $i = 1; $i < $line; $i++) {
      $_ = $brctlshow[$i];
      # We are interestend only in the first and last "word" of the line
      /^(\S+)\s.*\s(\S+)$/;
      if ($1 eq $vnet_name) {
      	# If equal, the virtual network has been found
      	return 1;
      }
   }

   # If virtual network is not found:
   return 0;

}

# vnet_exists_sw
#
# If the virtual network (implemented with a uml_switch) whose name is given
# as first argument exists, returns 1. In other case, returns 0.
#
sub vnet_exists_sw {

   my $vnet_name = shift;

   # To search for $dh->get_networks_dir()/$vnet_name.ctl socket file
   if (-S $dh->get_networks_dir . "/$vnet_name.ctl") {
      return 1;
   }
   else {
      return 0;
   }
   
}

# vnet_ifs
#
# Returns a list in which each element is one of the interfaces (TUN/TAP devices
# or host OS physical interfaces) of the virtual network given as argument.
#
# It based in `brctl show` parsing.
sub vnet_ifs {

   my $vnet_name = shift;
   my @if_list;

   # To get `brctl show`
   my @brctlshow;
   my $line = 0;
   my $pipe = $bd->get_binaries_path_ref->{"brctl"} . " show |";
   open BRCTLSHOW, "$pipe";
   while (<BRCTLSHOW>) {
      chomp;
      $brctlshow[$line++] = $_;
   }
   close BRCTLSHOW;

   # To look for virtual network processing the list
   # Note that we skip the first line (due to this line is the header of
   # brctl show: bridge name, brige id, etc.)
   for ( my $i = 1; $i < $line; $i++) {
      $_ = $brctlshow[$i];
      # Some brctl versions seems to show a different message when no
      # interface is used in a virtual bridge. Skip those
      unless (/Function not implemented/) {
         # We are interestend only in the first and last "word" of the line
         /^(\S+)\s.*\s(\S+)$/;
         if ($1 eq $vnet_name) {
      	    # To push interface into the list
            push (@if_list,$2);

	        # Internal loop (it breaks when a line not only with the interface name is found)
      	    for ( my $j = $i+1; $j < $line; $j++) {
	           $_ = $brctlshow[$j];
	           if (/^(\S+)\s.*\s(\S+)$/) {
	              last;
	           }
	           # To push interface into the list
	           /.*\s(\S+)$/;
	           push (@if_list,$1);
            }
            
	        # The end...
	        last;
	     }	     
      }
   }

   # To return list
   return @if_list;

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

   # To get `cat /proc/net/vlan/config`
   my @catconfig;
   my $line = 0;
   my $pipe = $bd->get_binaries_path_ref->{"cat"} . " /proc/net/vlan/config |";
   open CATCONFIG, "$pipe";
   while (<CATCONFIG>) {
      chomp;
      $catconfig[$line++] = $_;
   }
   close CATCONFIG;

   # To get pair interfaz-vlan
   # Note that we skip the first line, due to this is the hader of the config file
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
      $execution->execute($bd->get_binaries_path_ref->{"echo"} . " " . $dh->get_scename . "> " . $dh->get_networks_dir . "/$file");
   }
   else {
      my $command = $bd->get_binaries_path_ref->{"cat"} . " " . $dh->get_networks_dir . "/$file";
      my $value = `$command`;
      chomp ($value);
      $execution->execute($bd->get_binaries_path_ref->{"echo"} . " \"$value " . $dh->get_scename . "\"". "> " . $dh->get_networks_dir . "/$file");
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
         $execution->execute($bd->get_binaries_path_ref->{"rm"} . " -f " . $dh->get_networks_dir . "/$file");
      }
      else {
         $execution->execute($bd->get_binaries_path_ref->{"echo"} . " $value > " . $dh->get_networks_dir . "/$file");
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
      $execution->execute ($bd->get_binaries_path_ref->{"rm"} . " -f $status_file");
   }
   else {
      $execution->execute($bd->get_binaries_path_ref->{"echo"} . " $status > $status_file"); 
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
   my $exec_list = $vm->getElementsByTagName("exec");
   for (my $i = 0 ; $i < $exec_list->getLength; $i++) {
      if ($exec_list->item($i)->getAttribute("seq") eq $seq) {
         if ($exec_list->item($i)->getAttribute("user") ne "") {
            $username = $exec_list->item($i)->getAttribute("user");
            last;
         }
      }
   }

   # If not found in <exec>, try with <filetree>   
   if ($username eq "") {
      my $filetree_list = $vm->getElementsByTagName("filetree");
      for (my $i = 0 ; $i < $filetree_list->getLength; $i++) {
         if ($filetree_list->item($i)->getAttribute("seq") eq $seq) {
            if ($filetree_list->item($i)->getAttribute("user") ne "") {
               $username = $filetree_list->item($i)->getAttribute("user");
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

# get_vm_exec_mode
#
# Arguments:
# - a virtual machine node
#
# Returns the corresponding mode for the command executions in the virtual
# machine issued as argument. If no exec_mode is found (note that exec_mode attribute in
# <vm> is optional), the default is retrieved from the DataHandler object
#
sub get_vm_exec_mode {

   my $vm = shift;
   if (defined $vm->getAttribute("mode") && $vm->getAttribute("mode") ne "") {
      return $vm->getAttribute("mode");
   }
   else {
      return $dh->get_default_exec_mode;
   }
      
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
   $user = $args->get('u') if ($args->get('u'));

   # Slashed or dotted mask?
   my $effective_mask;
   if (&valid_dotted_mask($mask)) {
      $effective_mask = $mask;
   }
   else {
      $effective_mask = &slashed_to_dotted_mask($mask);
   }

   $execution->execute($bd->get_binaries_path_ref->{"tunctl"} . " -u $user -t $tap");
   $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $tap $hostip netmask $effective_mask up");
   #$execution->execute_bg($bd->get_binaries_path_ref->{"su"} . " -pc '".$bd->get_binaries_path_ref->{"uml_switch"}." -tap $tap -unix $socket < /dev/null > /dev/null &' $user");
   $execution->execute_bg($bd->get_binaries_path_ref->{"uml_switch"}." -tap $tap -unix $socket",'/dev/null');
   sleep 1;
   $execution->execute($bd->get_binaries_path_ref->{"chmod"} . " g+rw $socket");
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
   
   $execution->execute($bd->get_binaries_path_ref->{"kill"} . " `".$bd->get_binaries_path_ref->{"lsof"}." -t $socket`");
   $execution->execute($bd->get_binaries_path_ref->{"rm"} . " $socket");
   $execution->execute($bd->get_binaries_path_ref->{"ifconfig"} . " $tap down");
   $execution->execute($bd->get_binaries_path_ref->{"tunctl"} . " -d $tap");
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
   printf "ERROR in %s (%s): %s \n", (caller(1))[3], (caller(0))[2], $mess;
   exit 1;
}

# execute a smart die
sub handle_sig {
	# Reset alarm, if one has been set
	alarm 0;
	if ($args->get('t')) {
		&mode_d;
	}
	if (defined($execution)) {
		$execution->smartdie("Signal received. Exiting");
	}
	else {
		&vnx_die("Signal received. Exiting.");
	}
}


sub create_dirs {

   my $doc = $dh->get_doc;
   my @vm_ordered = $dh->get_vm_ordered; 
   for ( my $i = 0; $i < @vm_ordered; $i++) {
      my $vm = $vm_ordered[$i];

      # We get name attribute
      my $name = $vm->getAttribute("name");

	  # create fs, hostsfs and run directories, if they don't already exist
	  if ($execution->get_exe_mode() != $EXE_DEBUG) {
		  if (! -d $dh->get_vm_dir ) {
			  mkdir $dh->get_vm_dir or $execution->smartdie ("error making directory " . $dh->get_vm_dir . ": $!");

		  }
		  mkdir $dh->get_vm_dir($name);
		  mkdir $dh->get_fs_dir($name);
		  mkdir $dh->get_hostfs_dir($name);
		  mkdir $dh->get_run_dir($name);
		  mkdir $dh->get_mnt_dir($name);
		  mkdir $dh->get_vm_tmp_dir($name);		  
	  }
   }
}



####################

sub build_topology{
   my $basename = basename $0;
   my $opt_M = shift;
    try {
            # To load tun module if needed
            #if (&tundevice_needed($dh,$dh->get_vmmgmt_type,$dh->get_vm_ordered)) {
            if (&tundevice_needed($dh->get_vmmgmt_type,$dh->get_vm_ordered)) {
                if (! -e "/dev/net/tun") {
                    !$execution->execute ($bd->get_binaries_path_ref->{"modprobe"} . " tun") or $execution->smartdie ("module tun can not be initialized: $!");
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
            $execution->execute($bd->get_binaries_path_ref->{"cp"} . " " . $dh->get_input_file . " " . $dh->get_sim_dir);
            $execution->execute($bd->get_binaries_path_ref->{"echo"} . " '<'!-- copied by $basename at $now --'>' >> ".$dh->get_sim_dir."/$input_file_basename");       
            $execution->execute($bd->get_binaries_path_ref->{"echo"} . " '<'!-- original path: ".abs_path($dh->get_input_file)." --'>' >> ".$dh->get_sim_dir."/$input_file_basename");

            # To make lock file (it exists while topology is running)
            $execution->execute ($bd->get_binaries_path_ref->{"touch"} . " " . $dh->get_sim_dir . "/lock");

            # Create the mgmn_net socket when <vmmgnt type="net">, if needed
            if (($dh->get_vmmgmt_type eq "net") && ($dh->get_vmmgmt_autoconfigure ne "")) {
                if ($> == 0) {
                    my $sock = &do_path_expansion($dh->get_doc->getElementsByTagName("mgmt_net")->item(0)->getAttribute("sock"));
                        if (-S $sock) {
                            print "VNX warning: <mgmt_net> socket already exists. Ignoring socket autoconfiguration\n";
                        }
                        else {
                        # Create the socket
                        &mgmt_sock_create($sock,$dh->get_vmmgmt_autoconfigure,$dh->get_vmmgmt_hostip,$dh->get_vmmgmt_mask);
                        }
                }
                else {
                    print "VNX warning: <mgmt_net> autoconfigure attribute only is used when VNX parser is invoked by root. Ignoring socket autoconfiguration\n";
                }
            }

            # 1. To perform configuration for bridged virtual networks (<net mode="virtual_bridge">) and TUN/TAP for management
            &configure_virtual_bridged_networks;

            # 2. Host configuration
            &host_config;

            # 3. Set appropriate permissions and perform configuration for switched virtual networks and uml_switches creation (<net mode="uml_switch">)
            # DFC 21/2/2011 &chown_working_dir;
            &configure_switched_networks;
	   
            # 4. To link TUN/TAP to the bridges (for bridged virtual networks only, <net mode="virtual_bridge">)
            &tun_connect;

            # 5. To create fs, hostsfs and run directories
            &create_dirs;
       
   }
	
}


# make_vm_API_doc
#
# Argument:
# - the virtual machine name
# - the notify_ctl
# - the virtual machine number
#
# Creates the <create_conf> element containing the XML vm definition 
# which is passed to vmAPIs 
# 

sub make_vm_API_doc {
	
   my $vm = shift;
   my $notify_ctl = shift;
   my $i = shift;
   my $manipcounter = shift;
   my $dom;


   
   $dom = XML::LibXML->createDocument( "1.0", "UTF-8" );
   
   my $create_conf_tag = $dom->createElement('create_conf');
   $dom->addChild($create_conf_tag);
   
   # We get name attribute
   my $name = $vm->getAttribute("name");

   # Insert random id number
   my $fileid_tag = $dom->createElement('id');
   $create_conf_tag->addChild($fileid_tag);
   my $fileid = $name . "-" . &generate_random_string(6);
   $fileid_tag->addChild( $dom->createTextNode($fileid) );
   
   
   my $vm_tag = $dom->createElement('vm');
   $create_conf_tag->addChild($vm_tag);
   
   $vm_tag->addChild( $dom->createAttribute( name => $name));
 
   # To get filesystem and type
   my $filesystem;
   my $filesystem_type;
   my $filesystem_list = $vm->getElementsByTagName("filesystem");

   # filesystem tag in dom tree        
   my $fs_tag = $dom->createElement('filesystem');
   $vm_tag->addChild($fs_tag);

   if ($filesystem_list->getLength == 1) {
      $filesystem = &do_path_expansion(&text_tag($vm->getElementsByTagName("filesystem")->item(0)));
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
   my $mem_list = $vm->getElementsByTagName("mem");
   if ($mem_list->getLength == 1) {
      $mem = &text_tag($mem_list->item(0));
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
   
   ## conf for dynamips
   
   #my $dynamips = $dh->get_default_mem;      
#   my $conf_dynamips_list = $vm->getElementsByTagName("dynamips_conf");
#   if ($conf_dynamips_list->getLength == 1) {
#   		my $conf_dynamips = &text_tag($conf_dynamips_list->item(0));
#  		my $conf_dynamips_tag = $dom->createElement('dynamips_conf');
#   		$vm_tag->addChild($conf_dynamips_tag);
#   		$conf_dynamips_tag->addChild($dom->createTextNode($conf_dynamips));
#   }
  
#   my $ext_dynamips = $dh->get_default_dynamips();
#  #  my $ext_dynamips_list = $vm->getElementsByTagName("dynamips_ext");
#   if (!($ext_dynamips eq "")) {
#   		#my $ext_dynamips = &text_tag($ext_dynamips_list->item(0));
#  		my $ext_dynamips_tag = $dom->createElement('dynamips_ext');
#   		$vm_tag->addChild($ext_dynamips_tag);
#   		$ext_dynamips_tag->addChild($dom->createTextNode($ext_dynamips));
#   }

   # kernel to be booted
   my $kernel;
   my @params;
   my @build_params;
   my $kernel_list = $vm->getElementsByTagName("kernel");
      
   # kernel tag in dom tree
   my $kernel_tag = $dom->createElement('kernel');
   $vm_tag->addChild($kernel_tag);
   if ($kernel_list->getLength == 1) {
      my $kernel_item = $kernel_list->item(0);
      $kernel = &do_path_expansion(&text_tag($kernel_item));         
      # to dom tree
      $kernel_tag->addChild($dom->createTextNode($kernel));         
   }
   else {    	
      # include a 'default' in dom tree
      $kernel_tag->addChild($dom->createTextNode('default'));
         
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
            if ($console_port ne "") {
                $console_tag->addChild($dom->createAttribute( port => $console_port));
            }  
     }
   }

#   if (@console_list > 0) {
#     my $xterm_used = 0;
#     foreach my $console (@console_list) {
#	  		my $console_id    = $console->getAttribute("id");
#		 	my $console_value = &text_tag($console);
#            my $console_tag = $dom->createElement('console');
#            $vm_tag->addChild($console_tag);
#            $console_tag->addChild($dom->createTextNode($console_value));
#            $console_tag->addChild($dom->createAttribute( id => $console_id));
#			# Optional attributes: display and port            
#            my $console_display = $console->getAttribute("display");
#            
#            # If "no_console" options are found, do not launch consoles,
#            # if not, look for tag "display" for the vm and, if found, process it.
#            
#            my $opt_n = $args->get('n');
#            my $opt_no_console = $args->get('no_console');
#            if ($opt_n||$opt_no_console){
#            	$console_tag->addChild($dom->createAttribute( display => "no"));
#            	para("1");
#            }elsif($console_display ne ""){
#                $console_tag->addChild($dom->createAttribute( display => $console_display));
#            }
#            my $console_port = $console->getAttribute("port");
#            if ($console_port ne "") {
#                $console_tag->addChild($dom->createAttribute( port => $console_port));
#            }  
#     }
#   }   

#####

=BEGIN
   # To get display_console tag from scenario
   my $display_console_list = $vm->getElementsByTagName("display_console");
   my $display_console = "yes";
   if ($display_console_list->getLength == 1) {
      $display_console = &text_tag($display_console_list->item(0));
   }
   # display_console tag to vmAPI dom tree        
   my $display_console_tag = $dom->createElement('display_console');
   $vm_tag->addChild($display_console_tag);
   $display_console_tag->addChild($dom->createTextNode($display_console)); 
=END
=cut
   
   # To process all interfaces
   # To get UML's interfaces list
   my $if_list = $vm->getElementsByTagName("if");
   my $longitud = $if_list->getLength;

   # To process list, we ignore interface zero since it
   # gets setup as necessary management interface
   for ( my $j = 0; $j < $if_list->getLength; $j++) {
      
      my $if = $if_list->item($j);
    
      # To get attributes
      my $id = $if->getAttribute("id");
      my $net = $if->getAttribute("net");


      # To get MAC address
      my $mac_list = $if->getElementsByTagName("mac");
      my $mac;
      # If <mac> is not present, we ask for an automatic one (if
      # <automac> is not enable may be null; in this case UML 
      # autoconfiguration based in IP address of the interface 
      # is used -but it doesn't work with IPv6!)
      if ($mac_list->getLength == 1) {
      	
         $mac = &text_tag($mac_list->item(0));
         # expandir mac con ceros a:b:c:d:e:f -> 0a:0b:0c:0d:0e:0f
         $mac =~ s/(^|:)(?=[0-9a-fA-F](?::|$))/${1}0/g;
         $mac = "," . $mac;
         
         #$mac = "," . &text_tag($mac_list->item(0));
      }
      else {	  #my @group = getgrnam("@TUN_GROUP@");
         $mac = &automac($i+1, $id);
         # DFC: Moved to automac function 
         #$mac =~ s/,//;
         # expandir mac con ceros a:b:c:d:e:f -> 0a:0b:0c:0d:0e:0f
         #$mac =~ s/(^|:)(?=[0-9a-fA-F](?::|$))/${1}0/g;
         #$mac = "," . $mac;
	        
      }
         
      # if tags in dom tree 
      my $if_tag = $dom->createElement('if');
      $vm_tag->addChild($if_tag);
      $if_tag->addChild( $dom->createAttribute( id => $id));
      $if_tag->addChild( $dom->createAttribute( net => $net));
      $if_tag->addChild( $dom->createAttribute( mac => $mac));
      try {
      	my $name = $if->getAttribute("name");
      	$if_tag->addChild( $dom->createAttribute( name => $name));
      } 
      catch Error with {
      	
      } ;
         
      # To process interface IPv4 addresses
      # The first address has to be assigned without "add" to avoid creating subinterfaces
      if ($dh->is_ipv4_enabled) {
         my $ipv4_list = $if->getElementsByTagName("ipv4");
         #my $command = "";
         for ( my $j = 0; $j < $ipv4_list->getLength; $j++) {

            my $ip = &text_tag($ipv4_list->item($j));
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
               my $ipv4_mask_attr = $ipv4_list->item($j)->getAttribute("mask");
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
                  	 print "WARNING (vm=$name): no mask defined for $ip address of interface $id. Using default mask ($ipv4_effective_mask)\n";
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
	        my $ipv6_list = $if->getElementsByTagName("ipv6");
	        for ( my $j = 0; $j < $ipv6_list->getLength; $j++) {
	           my $ipv6_tag = $dom->createElement('ipv6');
               $if_tag->addChild($ipv6_tag);
	           my $ip = &text_tag($ipv6_list->item($j));
	           if (&valid_ipv6_with_mask($ip)) {
	              # Implicit slashed mask in the address
	              $ipv6_tag->addChild($dom->createTextNode($ip));
	           }
	           else {
	              # Check the value of the mask attribute
 	              my $ipv6_effective_mask = "/64"; # Default mask value	       
	              my $ipv6_mask_attr = $ipv6_list->item($j)->getAttribute("mask");
	              if ($ipv6_mask_attr ne "") {
	                 # Note that, in the case of IPv6, mask are always slashed
                     $ipv6_effective_mask = $ipv6_mask_attr;
	              }
	              
                  $ipv6_tag->addChild($dom->createTextNode("$ip$ipv6_effective_mask"));
	            }	       
	        }
	     }
      }
      
     
      #rutas de la máquina.
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
      my $forwarding_list = $vm->getElementsByTagName("forwarding");
      if ($forwarding_list->getLength == 1) {
         $f_type = $forwarding_list->item(0)->getAttribute("type");
         $f_type = "ip" if ($f_type =~ /^$/);
      }
      if ($f_type ne ""){
         my $forwarding_tag = $dom->createElement('forwarding');
         $vm_tag->addChild($forwarding_tag);
         $forwarding_tag->addChild( $dom->createAttribute( type => $f_type));
      }
      # Management interface, if needed
      #my $mng_if_value = &mng_if_value($dh,$vm);
      my $mng_if_value = &mng_if_value($vm);
      #$mng_if_tag->addChild( $dom->createAttribute( value => $mng_if_value));      
      # aquí es donde hay que meter las ips de gestion
      # si mng_if es distinto de no, metemos un if id 0
      unless ( ($dh->get_vmmgmt_type eq 'none' ) || ($mng_if_value eq "no") ) {
        my $mng_if_tag = $dom->createElement('if');
      	$vm_tag->addChild($mng_if_tag);
      	my $mac = &automac($i+1, 0);
      
        $mng_if_tag->addChild( $dom->createAttribute( mac => $mac));
        print "***2 get_admin_address($manipcounter, $dh->get_vmmgmt_type, 2)\n";
      	my $mng_addr = &get_admin_address( $manipcounter, $dh->get_vmmgmt_type, 2, $name );
      	$mng_if_tag->addChild( $dom->createAttribute( id => 0));
      	my $ipv4_tag = $dom->createElement('ipv4');
      	$mng_if_tag->addChild($ipv4_tag);
      	my $mng_mask = $mng_addr->mask();
      	$ipv4_tag->addChild( $dom->createAttribute( mask => $mng_mask));
      	my $mng_ip = $mng_addr->addr();
        $ipv4_tag->addChild($dom->createTextNode($mng_ip));
      
      }
      
	  # my @group = getgrnam("@TUN_GROUP@");
      my @group = getgrnam("uml-net");

      # flag 'o' tag in dom tree 
      my $o_flag_tag = $dom->createElement('o_flag');
      $vm_tag->addChild($o_flag_tag);      
      my $o_flag = "";
      if ($args->get('o')) {
      	$o_flag = $args->get('o');
      }     
      $o_flag_tag->addChild($dom->createTextNode($o_flag));

      # flag 'e' tag in dom tree 
      my $e_flag_tag = $dom->createElement('e_flag');
      $vm_tag->addChild($e_flag_tag);
      my $e_flag = "";
      if ($args->get('e')) {
      	$e_flag = $args->get('e');
      }     
      $e_flag_tag->addChild($dom->createTextNode($e_flag));

      # flag 'Z' tag in dom tree
      my $Z_flag_tag = $dom->createElement('Z_flag');
      $vm_tag->addChild($Z_flag_tag);
      my $Z_flag;
      if ($args->get('Z')) {
      	$Z_flag = 1;
      }else{
      	$Z_flag = 0;
      }      
      $Z_flag_tag->addChild($dom->createTextNode($Z_flag));

      # flag 'F' tag in dom tree
      my $F_flag_tag = $dom->createElement('F_flag');
      $vm_tag->addChild($F_flag_tag);
      my $F_flag;
      if ($args->get('F')) {
      	$F_flag = 1;
      }else{
      	$F_flag = 0;
      }      
      $F_flag_tag->addChild($dom->createTextNode($F_flag));

      # 'group2' tag in dom tree (luego se usa $group[2])
      #my $group2_tag = $dom->createElement('group2');
      #$vm_tag->addChild($group2_tag);
      #$group2_tag->addChild($dom->createTextNode($args->get('group2')));

      # 'notify_ctl' tag in dom tree
      my $notify_ctl_tag = $dom->createElement('notify_ctl');
      $vm_tag->addChild($notify_ctl_tag);
      $notify_ctl_tag->addChild($dom->createTextNode($notify_ctl));

      my $format = 1;
	  
      # dom es un XML::LibXML::Document; 
      my $docstring = $dom->toString($format);
      
      return $docstring;
}



sub para {
	my $mensaje = shift;
	my $var = shift;
	print "************* $mensaje *************\n";
	if (defined $var){
	   print $var . "\n";	
	}
	print "*********************************\n";
	<STDIN>;
}

#
# print_console_table_header: print the header of the console command's table
#                             printed at the end of vnx execution with -t option 
sub print_console_table_header {

#	my $scename=shift;
#	
#	print "-----------------------------------------------------------------------------------------\n";	
#	print " Scenario \"$scename\" started\n";
	print "\n";	
	printf " %-12s| %-20s| %s\n", "VM_NAME", "TYPE", "CONSOLE ACCESS COMMAND";	
	print "-----------------------------------------------------------------------------------------\n";	
}  

#
# print_console_table_entry: prints the information about the consoles of a virtual machine
#
sub print_console_table_entry {

    my $vmName=shift;
    my $merged_type=shift;
    my $consFile=shift;
    my $type=shift;
    my $briefFormat=shift;
	
	my @cons = qw(con0 con1 con2 con3);
	my $con;
	my @consDesc;
	
	foreach $con (@cons) {
		my $conData= &get_conf_value ($consFile, '', $con);
		#print "** $consFile $con conData=$conData\n";
		my $console_term=&get_conf_value ($vnxConfigFile, 'general', 'console_term');
		if (defined $conData) {
			if (defined $briefFormat) {
				#print "** conData=$conData\n";
			    my @consField = split(/,/, $conData);
			    if ($consField[1] eq "vnc_display") {
	 				push (@consDesc, "$con,virt-viewer -c $hypervisor $vmName");		    	
			    } elsif ($consField[1] eq "telnet") {
	 				push (@consDesc, "$con,telnet localhost $consField[2]");		    	   	
			    } elsif ($consField[1] eq "libvirt_pts") {
	 				push (@consDesc, "$con,virsh -c $hypervisor console $vmName");		    	   		    	
			    } elsif ($consField[1] eq "uml_pts") {
			    	my $conLine = VNX::vmAPICommon->open_console ($vmName, $con, $consField[1], $consField[2], 'yes');
	 				#push (@consDesc, "$con:  '$console_term -T $vmName -e screen -t $vmName $consField[2]'");
	 				push (@consDesc, "$con,$conLine");
			    } else {
			    	print ("ERROR: unknown console type ($consField[1]) in $consFile");
			    }
			} else {
				#print "** conData=$conData\n";
			    my @consField = split(/,/, $conData);
			    if ($consField[1] eq "vnc_display") {
	 				push (@consDesc, "$con:  'virt-viewer -c $hypervisor $vmName' or 'vncviewer $consField[2]'");		    	
			    } elsif ($consField[1] eq "telnet") {
	 				push (@consDesc, "$con:  'telnet localhost $consField[2]'");		    	   	
			    } elsif ($consField[1] eq "libvirt_pts") {
	 				push (@consDesc, "$con:  'virsh -c $hypervisor console $vmName' or 'screen $consField[2]'");		    	   		    	
			    } elsif ($consField[1] eq "uml_pts") {
			    	my $conLine = VNX::vmAPICommon->open_console ($vmName, $con, $consField[1], $consField[2], 'yes');
	 				#push (@consDesc, "$con:  '$console_term -T $vmName -e screen -t $vmName $consField[2]'");
	 				push (@consDesc, "$con:  '$conLine'");
			    } else {
			    	print ("ERROR: unknown console type ($consField[1]) in $consFile");
			    }
			}
		}
	}
	if (defined $briefFormat) {
		foreach (@consDesc) {
			printf "CON,%s,%s,%s\n", $vmName, $merged_type, $_;
		}
	} else {
		printf " %-12s| %-20s| %s\n", $vmName, $merged_type, $consDesc[0];
		shift (@consDesc);
		foreach (@consDesc) {
			printf " %-12s| %-20s| %s\n", "", "", $_;
		}
		print "-----------------------------------------------------------------------------------------\n";	
	}
	#printf "%-12s  %-20s  ERROR: cannot open file $portfile \n", $name, $merged_type;
}

sub print_consoles_info{
	
	my $opt_M = $args->get('M');
	my $briefFormat = $args->get('b');

	# Print information about vm consoles
    my @vm_ordered = $dh->get_vm_ordered;
	my %vm_hash = $dh->get_vm_to_use;
    
    my $first = 1;
    my $scename = $dh->get_scename;
    for ( my $i = 0; $i < @vm_ordered; $i++) {
		my $vm = $vm_ordered[$i];
		
		my $vmName = $vm->getAttribute("name");

      	# Do we have to process it?
      	unless ($vm_hash{$vmName}) {
      		next;
      	}    

		my $merged_type = &merge_vm_type($vm->getAttribute("type"),$vm->getAttribute("subtype"),$vm->getAttribute("os"));
			
		if ( ($first eq 1) && (! $briefFormat ) ){
			&print_console_table_header ($scename);
			$first = 0;
		}

		my $port;
		my $cons0Cmd;
		my $cons1Cmd;
		my $consFile = $dh->get_run_dir($vmName) . "/console";
		&print_console_table_entry ($vmName, $merged_type, $consFile, $vm->getAttribute("type"), $briefFormat);

	}
	
}





sub get_admin_address {

   my $seed = shift;
   my $vmmgmt_type = shift;
   my $hostnum = shift;
   my $vmName = shift;
   my $ip;

   my $net = NetAddr::IP->new($dh->get_vmmgmt_net."/".$dh->get_vmmgmt_mask);
   if ($vmmgmt_type eq 'private') {
      if ($seed eq "file"){
         #read management ip value from file
         my $addr = &get_conf_value ($dh->get_vm_dir($vmName) . '/mng_ip', '', 'addr');
         my $mask = &get_conf_value ($dh->get_vm_dir($vmName) . '/mng_ip', '', 'mask');
         $ip = NetAddr::IP->new($addr.$mask);
      }else{
         # check to make sure that the address space won't wrap
         if ($dh->get_vmmgmt_offset + ($seed << 2) > (1 << (32 - $dh->get_vmmgmt_mask)) - 3) {
            $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
         }
         # create a private subnet from the seed
         $net += $dh->get_vmmgmt_offset + ($seed << 2);
         $ip = NetAddr::IP->new($net->addr()."/30") + $hostnum;

         # create mng_ip file in vm dir, unless processing the host
         unless ($hostnum eq 1){
         	my $addr_line = "addr=" . $ip->addr();
            my $mask_line = "mask=" . $ip->mask();
            my $mngip_file = $dh->get_vm_dir($vmName) . '/mng_ip';
            $execution->execute($bd->get_binaries_path_ref->{"echo"} . " $addr_line > $mngip_file");
            $execution->execute($bd->get_binaries_path_ref->{"echo"} . " $mask_line >> $mngip_file");
         }
      }     
   } else {
	  # vmmgmt type is 'net'
      if ($seed eq "file"){
         #read management ip value from file
         $ip= &get_conf_value ($dh->get_vm_dir($vmName) . '/mng_ip', '', 'management_ip');
      }else{
         # don't assign the hostip
         my $hostip = NetAddr::IP->new($dh->get_vmmgmt_hostip."/".$dh->get_vmmgmt_mask);
         if ($hostip > $net + $dh->get_vmmgmt_offset &&
            $hostip <= $net + $dh->get_vmmgmt_offset + $seed + 1) {
         $seed++;
         }

         # check to make sure that the address space won't wrap
         if ($dh->get_vmmgmt_offset + $seed > (1 << (32 - $dh->get_vmmgmt_mask)) - 3) {
            $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
         }

         # return an address in the vmmgmt subnet
         $ip = $net + $dh->get_vmmgmt_offset + $seed + 1;
         
         # create mng_ip file in run dir
         my $addr_line = "addr=" . $ip->addr();
         my $mask_line = "addr=" . $ip->mask();
         my $mngip_file = $dh->get_vm_dir($vmName) . '/mng_ip';
         $execution->execute($bd->get_binaries_path_ref->{"echo"} . " $addr_line > $mngip_file");
         $execution->execute($bd->get_binaries_path_ref->{"echo"} . " $mask_line >> $mngip_file");
      }
   }
   return $ip;
}






=BEGIN
sub get_vnx_config {
	
	my $vnx_config = AppConfig->new(
		{
			CASE  => 0,                     # Case insensitive
#			ERROR => \&error_management,    # Error control function
			CREATE => 1,    				# Variables that weren't previously defined, are created
			GLOBAL => {
				DEFAULT  => "<unset>",		# Default value for all variables
				ARGCOUNT => ARGCOUNT_ONE,	# All variables contain a single value...
			}
		}
	);
	my $vnxconf_file;
	$vnxconf_file = "/etc/vnx.conf";
	open(FILEHANDLE, $vnxconf_file) or undef $vnxconf_file;
	close(FILEHANDLE);

	# Uncomment to make vnx.conf file obligatory, and to add a fallback path.
	#	if ($vnxconf_file eq undef){
	#		$vnxconf_file = "*path*/cluster.conf";
	#		open(FILEHANDLE, $vnxconf) or die "The vnx configuration file doesn't exist in /etc/ or in *path*... Aborting";
	#		close(FILEHANDLE);
	#	}
	
	# read the vnx config file
	$vnx_config->file($vnxconf_file);
	
	# Create corresponding objects
	$console_exe = $vnx_config->get("general_console_exe");
	$dynamips_port = $vnx_config->get("dynamips_port");
	$dynamips_idle_pc = $vnx_config->get("dynamips_idle_pc");
	
	# NOTE: The block name and an underscore are then prefixed
	# to the names of all variables subsequently referenced in that block. 
	# In order to read from the file the variable 'var1' of block 'block2', e.g.:
	# ...
	# [block2]
    # var1 = 20
	# ...
	# The line would be:
	# $XXX = $vnx_config->get("block2_var1");

}
=END
=cut  


####################
# usage
#
# Prints program usage message
sub usage {
	my $basename = basename $0;
	print "Usage: vnx -f VNX_file [-t|--create] [-o prefix] [-c vnx_dir] [-u user]\n";
#	print "                 [-T tmp_dir] [-i] [-w timeout] [-B] [-Z]\n";
	print "                 [-T tmp_dir] [-i] [-w timeout] [-B]\n";
	print "                 [-e screen_file] [-4] [-6] [-v] [-g] [-M vm_list] [-D]\n";
	print "       vnx -f VNX_file [-x|--execute cmd_seq] [-T tmp_dir] [-M vm_list] [-i] [-B] [-4] [-6] [-v] [-g]\n";
	print "       vnx -f VNX_file [-d|--shutdown] [-c vnx_dir] [-F] [-T tmp_dir] [-i] [-B] [-4] [-6] [-v] [-g]\n";
	print "       vnx -f VNX_file [-P|--destroy] [-T tmp_file] [-i] [-v] [-u user] [-g]\n";
	print "       vnx -f VNX_file [--define] [-M vm_list] [-v] [-u user] [-i]\n";
	print "       vnx -f VNX_file [--start] [-M vm_list] [-v] [-u user] [-i]\n";
	print "       vnx -f VNX_file [--undefine] [-M vm_list] [-v] [-u user] [-i]\n";
	print "       vnx -f VNX_file [--save] [-M vm_list] [-v] [-u user] [-i]\n";
	print "       vnx -f VNX_file [--restore] [-M vm_list] [-v] [-u user] [-i]\n";
	print "       vnx -f VNX_file [--suspend] [-M vm_list] [-v] [-u user] [-i]\n";
	print "       vnx -f VNX_file [--resume] [-M vm_list] [-v] [-u user] [-i]\n";
	print "       vnx -f VNX_file [--reboot] [-M vm_list] [-v] [-u user] [-i]\n";
	print "       vnx -f VNX_file [--reset] [-M vm_list] [-v] [-u user] [-i]\n";
	print "       vnx -f VNX_file [--show-map] \n";
	print "       vnx -h\n";
	print "       vnx -V\n";
	print "\n";
	print "Mode:\n";
	print "       -t|--create, build topology, or create virtual machine (if -M), using VNX_file as source.\n";
	print "       -x cmd_seq, execute the cmd_seq command sequence, using VNX_file as source.\n";
	print "       -d|--shutdown, destroy current scenario, or virtual machine (if -M), using VNX_file as source.\n";
	print "       -P|--destroy, purge scenario, or virtual machine (if -M), (warning: it will remove cowed filesystems!)\n";
	print "       --define, define all machines, or the ones speficied (if -M), using VNX_file as source.\n";
	print "       --undefine, undefine all machines, or the ones speficied (if -M), using VNX_file as source.\n";
	print "       --start, start all machines, or the ones speficied (if -M), using VNX_file as source.\n";
	print "       --save, save all machines, or the ones speficied (if -M), using VNX_file as source.\n";
	print "       --restore, restore all machines, or the ones speficied (if -M), using VNX_file as source.\n";
	print "       --suspend, suspend all machines, or the ones speficied (if -M), using VNX_file as source.\n";
	print "       --resume, resume all machines, or the ones speficied (if -M), using VNX_file as source.\n";
	print "       --reboot, reboot all machines, or the ones speficied (if -M), using VNX_file as source.\n";
	print "       --show-map, shows a map of the network build using graphviz.\n";
	print "\n";
	print "Pseudomode:\n";
	print "       -V, show program version and exit.\n";
	print "       -H, show this help message and exit.\n";
	print "\n";
	print "Options:\n";
	print "       -o prefix, dump UML boot messages output to files (using given prefix in pathname)\n";
	print "       -c vnx_dir, vnx working directory (default is ~/.vnx)\n";
	print "       -u user, if run as root, UML and uml_switch processes will be owned by this user instead (default [arroba]VNX_USER[arroba])\n";
	print "       -F, force stopping of UMLs (warning: UML filesystems may be corrupted)\n";
	print "       -w timeout, waits timeout seconds for a UML to boot before prompting the user for further action; a timeout of 0 indicates no timeout (default is 30)\n";
	print "       -B, blocking mode\n";
#	print "       -Z, avoids filesystem VNXzation\n";
	print "       -e screen_file, make screen configuration file for pts devices\n";
	print "       -i, interactive execution (in combination with -v mode)\n";
	print "       -4, process only IPv4 related tags (and not process IPv6 related tags)\n";
	print "       -6, process only IPv6 related tags (and not process IPv4 related tags)\n";
	print "       -v, verbose mode on\n";
	print "       -g, debug mode on (overrides verbose)\n";
	print "       -T tmp_dir, temporal files directory (default is /tmp)\n";
	print "       -M vm_list, start/stop/restart scenario in vm_list UMLs (a list of names separated by ,)\n";
   	print "       -C|--config config_file, use config_file as configuration file instead of default one (/etc/vnx.conf)\n";
   	print "       -D, delete LOCK file\n";
   	print "       -n|--no_console, do not display the console of any vm. To be used with -t|--create options";
   	print "\n";
   

}