package VNX::Globals;

use strict;
use warnings;
use Exporter;
use Readonly;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
	
	$version
	$release
	$branch
	
	$execution
	$dh
	$bd
	$args
	@plugins
	$exemode
	$hypervisor
	$vnxConfigFile

	$DEFAULT_CONF_FILE
	$CONS_DISPLAY_DEFAULT
	$CONS_BASE_PORT
	$CONS1_DEFAULT_TYPE
	$CONS_PORT	

	$LIBVIRT_DEFAULT_HYPERVISOR        

	$DYNAMIPS_DEFAULT_PORT        
	$DYNAMIPS_DEFAULT_IDLE_PC

	$EXE_DEBUG
	$EXE_VERBOSE
	$EXE_NORMAL
);

# Version information
# my $version = "[arroba]PACKAGE_VERSION[arroba]";[JSF]
# my $release = "[arroba]RELEASE_DATE[arroba]";[JSF]
my $version;;
my $release;
my $branch;

###########################################################
# Global objects

our $execution;     # the VNX::Execution object
our $dh;            # the VNX::DataHandler object
our $bd;            # the VNX::BinariesData object
our $args;          # the VNX::Arguments object
our @plugins;       # plugins array
our $exemode;       # Execution mode. It stores the value of $execution->get_exe_mode()
                    # Used just to shorter the print sentences:
                    #    print "..." if ($exemode == $EXE_VERBOSE)
our $hypervisor;    # Hypervisor used for libvirt 	
our $vnxConfigFile; # VNX Configuration file 


# Configuration files
Readonly::Scalar our $DEFAULT_CONF_FILE => '/etc/vnx.conf';

# Console Management
Readonly::Scalar our $CONS_DISPLAY_DEFAULT => 'yes';    # By default consoles are displayed at startup
Readonly::Scalar our $CONS_BASE_PORT       => '12000';  # DFC: base port for consoles. The code looks for a free port starting from this value
Readonly::Scalar our $CONS1_DEFAULT_TYPE   => 'pts';    # Default type for text console <console id="1">
our $CONS_PORT = $CONS_BASE_PORT; # Points to the next port to be used for consoles

# Libvirt
Readonly::Scalar our $LIBVIRT_DEFAULT_HYPERVISOR => 'qemu:///system';        

# Dynamips
Readonly::Scalar our $DYNAMIPS_DEFAULT_PORT    => '7200';        
Readonly::Scalar our $DYNAMIPS_DEFAULT_IDLE_PC => '0x604f8104';  

Readonly::Scalar our $EXE_DEBUG => 0;	#	- does not execute, only shows
Readonly::Scalar our $EXE_VERBOSE => 1;	#	- executes and shows
Readonly::Scalar our $EXE_NORMAL => 2;	#	- executes


1;
