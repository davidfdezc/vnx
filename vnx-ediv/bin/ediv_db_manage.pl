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
my $db_type;
my $db_host;
my $db_port;
my $db_user;
my $db_pass;
my $db_connection_info;

my $cluster_file;

my $mode = $ARGV[0];	

###########################################################
# Main	
###########################################################

	# Get DB configuration
&getDBConfiguration;

if ($mode eq "create"){
	print("db_manage: You chose creating the whole database, push ENTER to continue or CONTROL-C to abort\n");
	my $input = <STDIN>;
	&createDB;
} elsif ($mode eq "destroy"){
	print("db_manage: You chose destroying the whole database, push ENTER to continue or CONTROL-C to abort\n");
	my $input = <STDIN>;
	&destroyDB;
} else {
	print ("Sintax: you must choose option 'create' or option 'destroy' as argument");
}

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
	
	$db = "";
	$db_type = $db_config->get("db_type");
	$db_host = $db_config->get("db_host");
	$db_port = $db_config->get("db_port");
	$db_user = $db_config->get("db_user");
	$db_pass = $db_config->get("db_pass");
	$db_connection_info = "DBI:$db_type:database=$db;$db_host:$db_port";	
	
}	

	###########################################################
	# Subroutine to create DB structure
	###########################################################
sub createDB{
	
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	
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
	
	$db_config->file($cluster_file);		# read the default cluster config file
	$db = $db_config->get("db_name");
	$db_connection_info = "DBI:$db_type:database=$db;$db_host:$db_port";
		
	my $query_string = "CREATE DATABASE `$db`";
	my $query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$dbh->disconnect;
	
	$dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	
	$query_string = "SET SQL_MODE=\"NO_AUTO_VALUE_ON_ZERO\"";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "CREATE TABLE IF NOT EXISTS `hosts` (
  					`simulation` text collate utf8_spanish_ci NOT NULL,
  					`local_simulation` text collate utf8_spanish_ci NOT NULL,
 					`host` text collate utf8_spanish_ci NOT NULL,
 					`local_specification` blob,
  					`status` enum('creating','running','purging','destroying') collate utf8_spanish_ci NOT NULL
					) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_spanish_ci;";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "CREATE TABLE IF NOT EXISTS `nets` (
 					`name` text collate utf8_spanish_ci NOT NULL,
  					`simulation` text collate utf8_spanish_ci NOT NULL,
  					`external` text collate utf8_spanish_ci
					) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_spanish_ci;";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "CREATE TABLE IF NOT EXISTS `simulations` (
  					`name` text collate utf8_spanish_ci NOT NULL,
  					`automac_offset` int(11) default NULL,
  					`mgnet_offset` int(11) default NULL
					) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_spanish_ci;";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "CREATE TABLE IF NOT EXISTS `vlans` (
  					`number` int(11) NOT NULL,
  					`simulation` text collate utf8_spanish_ci NOT NULL,
  					`host` text collate utf8_spanish_ci NOT NULL,
  					`external_if` text collate utf8_spanish_ci NOT NULL
					) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_spanish_ci;";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "CREATE TABLE IF NOT EXISTS `vms` (
  					`name` text collate utf8_spanish_ci NOT NULL,
  					`simulation` text collate utf8_spanish_ci NOT NULL,
  					`host` text collate utf8_spanish_ci NOT NULL,
  					`ssh_port` int(11) default NULL
					) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_spanish_ci;";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$dbh->disconnect;
	
}	

	###########################################################
	# Subroutine to destroy DB structure
	###########################################################
sub destroyDB{
	
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	
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
	
	$db_config->file($cluster_file);		# read the default cluster config file
	$db = $db_config->get("db_name");
	
	$query_string = "DROP DATABASE `$db`";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$dbh->disconnect;
	
}

# Subroutines end
###########################################################
