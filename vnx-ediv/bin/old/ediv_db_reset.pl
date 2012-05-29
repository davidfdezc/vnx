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

my $simulation_name = $ARGV[0];
my $db;
my $db_type;
my $db_host;
my $db_port;
my $db_user;
my $db_pass;
my $db_connection_info;	

###########################################################
# Main	
###########################################################

	# Get DB configuration
&getDBConfiguration;

	# Clean DB
&cleanDB;

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
	
		# Create corresponding cluster host objects
	
	$db = $db_config->get("db_name");
	$db_type = $db_config->get("db_type");
	$db_host = $db_config->get("db_host");
	$db_port = $db_config->get("db_port");
	$db_user = $db_config->get("db_user");
	$db_pass = $db_config->get("db_pass");
	$db_connection_info = "DBI:$db_type:database=$db;$db_host:$db_port";	
	
}	

	###########################################################	
	# Subroutine to clean DB
	###########################################################
sub cleanDB{

	if ($simulation_name eq undef){
		print("db_reset: You chose cleaning the whole database, push ENTER to continue or CONTROL-C to abort\n");
		my $input = <STDIN>;
		
		my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		
		my $query_string = "TRUNCATE TABLE  `hosts`";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		
		$query_string = "TRUNCATE TABLE  `simulations`";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		
		$query_string = "TRUNCATE TABLE  `vms`";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		
		$query_string = "TRUNCATE TABLE  `vlans`";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		
		$query_string = "TRUNCATE TABLE  `nets`";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		
		$dbh->disconnect;
	} else {
		my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
		
		my $query_string = "SELECT 'name' FROM simulations WHERE name = '$simulation_name'";
		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $contenido = $query->fetchrow_array();
		$query->finish();
		
		if ($contenido eq undef){
			print ("db_reset: Simulation $simulation_name doesn't exist at database\n");
		} else{
		
			print("db_reset: You chose cleaning simulation $simulation_name from database, push ENTER to continue or CONTROL-C to abort\n");
			my $input = <STDIN>;
		
			my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
				
			$query_string = "DELETE FROM hosts WHERE simulation = '$simulation_name'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			$query->finish();
	
			$query_string = "DELETE FROM nets WHERE simulation = '$simulation_name'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			$query->finish();
	
			$query_string = "DELETE FROM simulations WHERE name = '$simulation_name'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			$query->finish();
	
			$query_string = "DELETE FROM vlans WHERE simulation = '$simulation_name'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			$query->finish();
	
			$query_string = "DELETE FROM vms WHERE simulation = '$simulation_name'";
			$query = $dbh->prepare($query_string);
			$query->execute();
			$query->finish();
		}
	
		$dbh->disconnect;
		
	}
}

# Subroutines end
###########################################################
