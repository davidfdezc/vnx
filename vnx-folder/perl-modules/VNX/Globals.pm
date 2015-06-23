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
	%opts
	@plugins
	$exemode
	$hypervisor
	$vnxConfigFile
    $uid
    $uid_name
    $vmfs_on_tmp
    $hline
    $hline10
    $hline50
    $hline100

    $VNX_INSTALL_DIR
	$DEFAULT_TMP_DIR
	$DEFAULT_VNX_DIR
	$DEFAULT_VMFS_ON_TMP
	$DEFAULT_CONF_FILE
	$DEFAULT_CLUSTER_CONF_FILE
    $EDIV_SEG_ALGORITHMS_DIR
    $EDIV_LOGS_DIR
    $VNXACED_STATUS_DIR
    $VNXACED_STATUS
    
    $H2VM_BASE_PORT
    $H2VM_PORT 
    $H2VM_BIND_ADDR
    $H2VM_TIMEOUT
    $H2VM_DEFAULT_TIMEOUT 
    	
	$CONS_DISPLAY_DEFAULT
	$CONS_BASE_PORT
	$CONS1_DEFAULT_TYPE
	$CONS_PORT	

	$LIBVIRT_DEFAULT_HYPERVISOR        
    $LIBVIRT_KVM_HYPERVISOR        
    $LIBVIRT_VBOX_HYPERVISOR        
    $DEFAULT_ONE_PASS_AUTOCONF
	$DEFAULT_HOST_PASSTHROUGH
    
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
	ERR
	
	@EXEC_MODES_UML
    @EXEC_MODES_LIBVIRT_KVM_LINUX
    @EXEC_MODES_LIBVIRT_KVM_FREEBSD
	@EXEC_MODES_LIBVIRT_KVM_WINDOWS
	@EXEC_MODES_LIBVIRT_KVM_OLIVE
	@EXEC_MODES_LIBVIRT_KVM_ANDROID
    @EXEC_MODES_LIBVIRT_KVM_WANOS
	@EXEC_MODES_DYNAMIPS
	@EXEC_MODES_LXC

	@EXEC_OSTYPE_UML
    @EXEC_OSTYPE_LIBVIRT_KVM_LINUX  
    @EXEC_OSTYPE_LIBVIRT_KVM_FREEBSD
	@EXEC_OSTYPE_LIBVIRT_KVM_WINDOWS
    @EXEC_OSTYPE_LIBVIRT_KVM_OLIVE
    @EXEC_OSTYPE_LIBVIRT_KVM_ANDROID
    @EXEC_OSTYPE_LIBVIRT_KVM_WANOS
	@EXEC_OSTYPE_DYNAMIPS

);

# Version information
# my $version = "[arroba]PACKAGE_VERSION[arroba]";[JSF]
# my $release = "[arroba]RELEASE_DATE[arroba]";[JSF]
our $version;;
our $release;
our $branch;

# Debug: tracer show stack traces on errors
#our $tracer;

###########################################################
# Global objects

our $execution;     # the VNX::Execution object
our $dh;            # the VNX::DataHandler object
our $bd;            # the VNX::BinariesData object
#our $args;          # the VNX::Arguments object
our %opts = ();     # Command line options hash

our @plugins;       # plugins array
our $exemode;       # Execution mode. It stores the value of $execution->get_exe_mode()
                    # Used just to shorter the print sentences:
                    #    print "..." if ($exemode == $EXE_VERBOSE)
our $hypervisor;    # Hypervisor used for libvirt 	
our $vnxConfigFile; # VNX Configuration file 
our $uid;           # User id of the user that issue the "sudo vnx..." command 
our $uid_name;      # User name associated to $uid 
our $vmfs_on_tmp;   # Loads the value of vmfs_on_tmp global config value
                    # Used to move the cow and sdisk filesystems to the tmp directory
                    # (used to solve a problem in DIT-UPM laboratories, where root user 
                    # cannot write to network-mounted user directories)  
our $hline10 = "----------"; # Just a horizontal line of 10 '-'
our $hline50 = "--------------------------------------------------"; # Just a horizontal line of 50 '-'
our $hline100 = "----------------------------------------------------------------------------------------------------"; # Just a horizontal line of 100 '-'
our $hline = $hline100;
#our $hline = "----------------------------------------------------------------------------------"; # Just a horizontal line...


# Configuration files and directories
Readonly::Scalar our $VNX_INSTALL_DIR => '/usr/share/vnx';
Readonly::Scalar our $DEFAULT_TMP_DIR => '/tmp';
Readonly::Scalar our $DEFAULT_CONF_FILE => '/etc/vnx.conf';
Readonly::Scalar our $DEFAULT_VNX_DIR => '~/.vnx';
Readonly::Scalar our $DEFAULT_VMFS_ON_TMP => 'no';
Readonly::Scalar our $DEFAULT_CLUSTER_CONF_FILE => '/etc/vnx.conf';  # '/etc/ediv/cluster.conf';
Readonly::Scalar our $EDIV_SEG_ALGORITHMS_DIR => '/usr/share/vnx/lib/seg-alg';
Readonly::Scalar our $EDIV_LOGS_DIR => '/var/log/vnx';
Readonly::Scalar our $VNXACED_STATUS_DIR => '/root/.vnx';
Readonly::Scalar our $VNXACED_STATUS => $VNXACED_STATUS_DIR . '/vnxaced.status';


# Host to virtual machines communication channel
Readonly::Scalar our $H2VM_BASE_PORT => '13000';     # Initial TCP port for host to virtual machines channels 
                                                     # (used when USE_UNIX_SOCKETS=0 in vmAPI_libvirt)
our $H2VM_PORT = $H2VM_BASE_PORT;                    # Points to the next TCP port to be used for H2VM channels
Readonly::Scalar our $H2VM_BIND_ADDR => '127.0.0.1'; # Address to listen for H2VM channels
Readonly::Scalar our $H2VM_DEFAULT_TIMEOUT => '60';  # Default maximum time waiting for an answer in H2VM channel 
our $H2VM_TIMEOUT = $H2VM_DEFAULT_TIMEOUT;           # Maximum time waiting for an answer in H2VM channel 

# Console Management
Readonly::Scalar our $CONS_DISPLAY_DEFAULT => 'yes';    # By default consoles are displayed at startup
Readonly::Scalar our $CONS_BASE_PORT       => '12000';  # Initial TCP port for consoles. The code looks for a free port starting from this value
Readonly::Scalar our $CONS1_DEFAULT_TYPE   => 'pts';    # Default type for text console <console id="1">
our $CONS_PORT = $CONS_BASE_PORT; # Points to the next TCP port to be used for consoles

# Libvirt
Readonly::Scalar our $LIBVIRT_DEFAULT_HYPERVISOR => 'qemu:///system';        
Readonly::Scalar our $LIBVIRT_KVM_HYPERVISOR => 'qemu:///system';        
Readonly::Scalar our $LIBVIRT_VBOX_HYPERVISOR => 'vbox:///system'; 
Readonly::Scalar our $DEFAULT_ONE_PASS_AUTOCONF => 'no'; 
Readonly::Scalar our $DEFAULT_HOST_PASSTHROUGH => 'no'; 
       

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
use constant ERR => 4;

# Allowed and default modes in exec_mode attribute of <vm> tag for each virtual machine type
# Default mode is always the first value in array
our @EXEC_MODES_UML                 = qw( mconsole net sdisk);
our @EXEC_MODES_LIBVIRT_KVM_LINUX   = qw( sdisk cdrom net );
our @EXEC_MODES_LIBVIRT_KVM_FREEBSD = qw( sdisk cdrom net );
our @EXEC_MODES_LIBVIRT_KVM_WINDOWS = qw( cdrom sdisk );
our @EXEC_MODES_LIBVIRT_KVM_OLIVE   = qw( sdisk net );
our @EXEC_MODES_LIBVIRT_KVM_ANDROID = qw( adb );
our @EXEC_MODES_LIBVIRT_KVM_WANOS   = qw( sdisk );
our @EXEC_MODES_DYNAMIPS            = qw( telnet );
our @EXEC_MODES_LXC            		= qw( lxc-attach );

# Allowed and default ostypes in <exec> tags for each virtual machine type
# Default mode is always the first value in array
our @EXEC_OSTYPE_UML                 = qw( system );
our @EXEC_OSTYPE_LIBVIRT_KVM_LINUX   = qw( system exec xsystem xexec );
our @EXEC_OSTYPE_LIBVIRT_KVM_FREEBSD = qw( system exec xsystem xexec );
our @EXEC_OSTYPE_LIBVIRT_KVM_WINDOWS = qw( cmd system exec );
our @EXEC_OSTYPE_LIBVIRT_KVM_OLIVE   = qw( show set load system );
our @EXEC_OSTYPE_LIBVIRT_KVM_ANDROID = qw( system );
our @EXEC_OSTYPE_LIBVIRT_KVM_WANOS   = qw( sdisk );
our @EXEC_OSTYPE_DYNAMIPS            = qw( show set load );

1;
