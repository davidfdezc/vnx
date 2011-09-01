# Globals.pm
#
# This file is a module part of VNX package.
#
# Authors: David Fernández, Jorge Somavilla
# Coordinated by: David Fernández (david@dit.upm.es)
#
# Copyright (C) 2011, 	DIT-UPM
# 			Departamento de Ingenieria de Sistemas Telematicos
#			Universidad Politecnica de Madrid
#			SPAIN
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
#

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

	$DEFAULT_TMP_DIR
	$DEFAULT_VNX_DIR
	$DEFAULT_CONF_FILE
	$CONS_DISPLAY_DEFAULT
	$CONS_BASE_PORT
	$CONS1_DEFAULT_TYPE
	$CONS_PORT	

	$LIBVIRT_DEFAULT_HYPERVISOR        

	$DYNAMIPS_DEFAULT_PORT        
	$DYNAMIPS_DEFAULT_IDLE_PC
	$SERLINE_BASE_PORT
	$SERLINE_PORT	

	$EXE_DEBUG
	$EXE_VERBOSE
	$EXE_NORMAL

    $EXE_VERBOSITY_LEVEL	
	N
	V
	VV
	VVV
	
	@EXEC_MODES_UML
	@EXEC_MODES_LIBVIRT_KVM_LINUX
	@EXEC_MODES_LIBVIRT_KVM_WINDOWS
	@EXEC_MODES_LIBVIRT_KVM_OLIVE
	@EXEC_MODES_DYNAMIPS

	@EXEC_OSTYPE_UML
	@EXEC_OSTYPE_LIBVIRT_KVM_LINUX
	@EXEC_OSTYPE_LIBVIRT_KVM_WINDOWS
	@EXEC_OSTYPE_LIBVIRT_KVM_OLIVE
	@EXEC_OSTYPE_DYNAMIPS

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


# Configuration files and directories
Readonly::Scalar our $DEFAULT_TMP_DIR => '/tmp';
Readonly::Scalar our $DEFAULT_CONF_FILE => '/etc/vnx.conf';
Readonly::Scalar our $DEFAULT_VNX_DIR => '~/.vnx';

# Console Management
Readonly::Scalar our $CONS_DISPLAY_DEFAULT => 'yes';    # By default consoles are displayed at startup
Readonly::Scalar our $CONS_BASE_PORT       => '12000';  # Initial TCP port for consoles. The code looks for a free port starting from this value
Readonly::Scalar our $CONS1_DEFAULT_TYPE   => 'pts';    # Default type for text console <console id="1">
our $CONS_PORT = $CONS_BASE_PORT; # Points to the next TCP port to be used for consoles

# Libvirt
Readonly::Scalar our $LIBVIRT_DEFAULT_HYPERVISOR => 'qemu:///system';        

# Dynamips
Readonly::Scalar our $DYNAMIPS_DEFAULT_PORT    => '7200';        
Readonly::Scalar our $DYNAMIPS_DEFAULT_IDLE_PC => '0x604f8104';
Readonly::Scalar our $SERLINE_BASE_PORT        => '12000';  # DFC: initial port for the UDP ports using in dynamips serial line emulation
our $SERLINE_PORT = $SERLINE_BASE_PORT; # Points to the next UDP port to be used for serial line emulation


# Execution modes
Readonly::Scalar our $EXE_DEBUG => 0;	    #	- does not execute, only shows
Readonly::Scalar our $EXE_VERBOSE => 1;	    #	- executes and shows
Readonly::Scalar our $EXE_NORMAL => 2;	    #	- executes

# Log verbosity levels (short format)
our $EXE_VERBOSITY_LEVEL;
use constant N   => 0;
use constant V   => 1;
use constant VV  => 2;
use constant VVV => 3;


# Allowed and default modes in <exec> and <filetree> tags for each virtual machine type
# Default mode is always the first value in array
our @EXEC_MODES_UML                 = qw( mconsole net);
our @EXEC_MODES_LIBVIRT_KVM_LINUX   = qw( cdrom net sdisk );
our @EXEC_MODES_LIBVIRT_KVM_WINDOWS = qw( cdrom sdisk );
our @EXEC_MODES_LIBVIRT_KVM_OLIVE   = qw( sdisk net );
our @EXEC_MODES_DYNAMIPS            = qw( telnet );

# Allowed and default ostypes in <exec> tags for each virtual machine type
# Default mode is always the first value in array
our @EXEC_OSTYPE_UML                 = qw( system );
our @EXEC_OSTYPE_LIBVIRT_KVM_LINUX   = qw( system exec xsystem xexec );
our @EXEC_OSTYPE_LIBVIRT_KVM_WINDOWS = qw( cmd system exec );
our @EXEC_OSTYPE_LIBVIRT_KVM_OLIVE   = qw( show set load system );
our @EXEC_OSTYPE_DYNAMIPS            = qw( show set load );

1;
