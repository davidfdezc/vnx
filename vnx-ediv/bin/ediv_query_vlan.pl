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
# Copyright: (C) 2008 Telefonica Investigacion y Desarrollo, S.A.U.
# Authors: Fco. Jose Martin,
#          Miguel Ferrer
#          Departamento de Ingenieria de Sistemas Telematicos, Universidad Politécnica de Madrid
#

###########################################################
# Modules import
###########################################################
use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import

	# Module to handle databases
use DBI;

###########################################################
# Global variables 
###########################################################

my $db;
my $db_host;
my $db_port;
my $db_user;
my $db_pass;
my $db_connection_info;

my $simulation_name = $ARGV[0];	

###########################################################
# Main	
###########################################################
	
	# Get DB configuration
&getDBConfiguration;

	# Get vlan information
&vlanInfo;

# Main end
###########################################################

###########################################################
# Subroutines
###########################################################

	###########################################################	
	# Subroutine to obtain DB configuration info
	###########################################################
sub getDBConfiguration {
	
	my $db_config = AppConfig->new(
		{
			CASE  => 0,                     # Case insensitive
			ERROR => \&error_management,    # Error control function
			CREATE => 1,    				# Variables that weren't previously defined, are created
			GLOBAL => {
				DEFAULT  => "<unset>",		# Default value for all variables
				ARGCOUNT => ARGCOUNT_ONE,	# All variables contain a single value...
			}
		}
	);
	my $cluster_file;
	$cluster_file = "/etc/ediv/cluster.conf";
	open(FILEHANDLE, $cluster_file) or undef $cluster_file;
	close(FILEHANDLE);
	if ($cluster_file eq undef){
		$cluster_file = "/usr/local/etc/ediv/cluster.conf";
		open(FILEHANDLE, $cluster_file) or die "The cluster configuration file doesn't exist in /etc/ediv or in /usr/local/etc/ediv... Aborting";
		close(FILEHANDLE);
	}
	
	$db_config->file($cluster_file);		# read the default cluster config file
	
		# Create corresponding db objects
	
	$db = $db_config->get("db_name");
	$db_host = $db_config->get("db_host");
	$db_port = $db_config->get("db_port");
	$db_user = $db_config->get("db_user");
	$db_pass = $db_config->get("db_pass");
	$db_connection_info = "DBI:mysql:database=$db;$db_host:$db_port";	
	
}	
	
	###########################################################
	# Subroutine to obtain information of vlans
	###########################################################
sub vlanInfo{
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	
	if ($simulation_name eq undef){
			my $query_string = "SELECT DISTINCT `number`,`simulation` FROM vlans ORDER BY number";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			
			while (@simulations = $query->fetchrow_array()) {
				print ("The vlan $simulations[0] is used by simulation $simulations[1]\n");
			}
			
			$query->finish();
			
		} else {
			my $query_string = "SELECT `number`,`host`,`simulation` FROM vlans WHERE simulation='$simulation_name' ORDER BY number";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			
			while (@simulations = $query->fetchrow_array()) {
				print ("Simulation $simulations[2]: vlan $simulations[0] in host $simulations[1]\n");
			}
						
			$query->finish();
		
		}
	$dbh->disconnect;
}

# Subroutines end
###########################################################
