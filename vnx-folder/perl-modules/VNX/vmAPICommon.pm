# vmAPICommon.pm
#
# This file is a module part of VNX package.
#
# Author: David Fernández (david@dit.upm.es)
# Copyright (C) 2010, 	DIT-UPM
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

# vmAPI_common is used to store functions common to two or more vmAPI_* modules 

package VNX::vmAPICommon;
require(Exporter);

@ISA    = qw(Exporter);
@EXPORT = qw(	start_console
				start_consoles_from_console_file
);

use strict;
use warnings;
use VNX::Execution;
use VNX::FileChecks;
use VNX::Globals;

#my $DEF_CONS_DISPLAY = 'yes';  # By default consoles are displayed at startup
#use constant DEF_CONS_DISPLAY => 'yes';  # By default consoles are displayed at startup
#use constant VNX_CONFFILE => '/etc/vnx.conf';

#
# Starts the console of a virtual machine using the application
# defined in VNX_CONFFILE console_exe entry
#
sub start_console {
	
	my $self      = shift;
	my $vmName    = shift;
	my $command   = shift;
#    my $execution = shift;

	#my $console_exe=&get_conf_value ($VNX::Globals::MAIN_CONF_FILE, 'console_exe', $execution);
	my $console_exe=&get_conf_value ($VNX::Globals::MAIN_CONF_FILE, 'console_exe');
	#print "*** console_exe = $console_exe\n";
	if ($console_exe eq 'gnome-terminal') {
		$execution->execute("gnome-terminal --title '$vmName - console #1' -e '$command' >/dev/null 2>&1 &");
	} elsif ($console_exe eq 'xterm') {
		$execution->execute("xterm -title '$vmName - console #1' -e '$command' >/dev/null 2>&1 &");
	} else {
		$execution->smartdie ("unknown value ($console_exe) of console_exe entry in VNX_CONFFILE");
	}
}

#
# Start all the active consoles of a virtual machine starting from the information
# found in the vm console file
#
sub start_consoles_from_console_file {
	
	my $self      = shift;
	my $vmName    = shift;
	my $consFile  = shift;
#    my $execution = shift;

	# Then, we just read the console file and start the active consoles
	open (CONS_FILE, "< $consFile") || $execution->smartdie("Could not open $consFile file.");
	foreach my $line (<CONS_FILE>) {
	    chomp($line);               # remove the newline from $line.
	    $line =~ s/con.=//;  		# eliminate the "conX=" part of the line
	    # do line-by-line processing.
	    #print "** CONS_FILE: $line\n";
	    my @consField = split(/,/, $line);
	    #print "** CONS_FILE: $consField[0] $consField[1] $consField[2]\n";
	    if ($consField[0] eq 'yes') {  # console with display='yes'
	   		if ($consField[1] eq 'vnc_display') {
				$execution->execute("virt-viewer $vmName &");  			
	   		} elsif ($consField[1] eq 'pts') {
				VNX::vmAPICommon->start_console ($vmName, "virsh console $vmName", $execution);
	   		} elsif ($consField[1] eq 'telnet') {
				VNX::vmAPICommon->start_console ($vmName, "telnet localhost $consField[2]", $execution);						
			} else {
				print "WARNING (vm=$vmName): unknown console type ($consField[0])\n"
			}
		} 
	}	

}


1;