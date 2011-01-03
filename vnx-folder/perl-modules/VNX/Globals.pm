package VNX::Globals;

use strict;
use warnings;
use Exporter;
use Readonly;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
	
	$execution
	$dh
	$bd
	$args
	@plugins
	$exemode

	$MAIN_CONF_FILE
	$CONS_DISPLAY_DEFAULT
	$CONS_BASE_PORT
	$CONS1_DEFAULT_TYPE
	$CONS_PORT	
	
	$EXE_DEBUG
	$EXE_VERBOSE
	$EXE_NORMAL
);


###########################################################
# Global objects

our $execution;   # the VNX::Execution object
our $dh;          # the VNX::DataHandler object
our $bd;          # the VNX::BinariesData object
our $args;        # the VNX::Arguments object
our @plugins;     # plugins array
our $exemode;     # Execution mode. It stores the value of $execution->get_exe_mode()
                  # Used just to shorter the print sentences:
                  #    print "..." if ($exemode == $EXE_VERBOSE)


# Configuration files
Readonly::Scalar our $MAIN_CONF_FILE => '/etc/vnx.conf';

# Console Management
Readonly::Scalar our $CONS_DISPLAY_DEFAULT => 'yes';    # By default consoles are displayed at startup
Readonly::Scalar our $CONS_BASE_PORT       => '12000';  # DFC: base port for consoles. The code looks for a free port starting from this value
Readonly::Scalar our $CONS1_DEFAULT_TYPE   => 'pts';    # Default type for text console <console id="1">
our $CONS_PORT = $CONS_BASE_PORT; # Points to the next port to be used for consoles

# Dynamips
Readonly::Scalar our $DYNAMIPS_DEFAULT_PORT => '7200';    # By default consoles are displayed at startup

Readonly::Scalar our $EXE_DEBUG => 0;	#	- does not execute, only shows
Readonly::Scalar our $EXE_VERBOSE => 1;	#	- executes and shows
Readonly::Scalar our $EXE_NORMAL => 2;	#	- executes


1;
