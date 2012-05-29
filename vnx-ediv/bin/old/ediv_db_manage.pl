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

use strict;
use warnings;
use AppConfig;         					# Config files management library
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
use DBI;
use VNX::ClusterMgmt;


#
# Main	
#

my $cluster_file;
my $mode = $ARGV[0];    
$cluster_conf_file = "/etc/ediv/cluster.conf";

# Read and parse cluster config
if (my $res = read_cluster_config($cluster_conf_file, 'no')) { 
    print "ERROR: $res\n";  
    exit 1; 
}

if ($mode eq "create"){
	print("db_manage: You chose creating the whole database, push ENTER to continue or CONTROL-C to abort\n");
	my $input = <STDIN>;
	create_db();
} elsif ($mode eq "destroy"){
    print("db_manage: You chose destroying the whole database, push ENTER to continue or CONTROL-C to abort\n");
    my $input = <STDIN>;
    destroy_db();
} elsif ($mode eq "reset"){
    print("db_manage: You chose reseting the whole database, push ENTER to continue or CONTROL-C to abort\n");
    my $input = <STDIN>;
    reset_db();
} else {
	print ("Sintax: you must choose option 'create' or option 'destroy' as argument");
}


#
# Subroutine to create DB structure
#
sub create_db{
	
    my $dbh;
    my $query_string;
    my $query;

	print "db type=$db->{type},db_connection_info=$db->{conn_info}\n";
    
    if ($db->{type} eq 'sqlite') {

        $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass});
    	
    } else {
		
        #$dbh = DBI->connect($db_connection_info,$db->{user},$db->{pass});
        my $db_conn_info = "DBI:$db->{type}:database=;$db->{host}:$db->{port}";
        $dbh = DBI->connect($db_conn_info,$db->{user},$db->{pass});
		print "Creating database...\n";
		$query_string = "CREATE DATABASE `$db->{name}`";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();

        # Disconnect and reconnect specifying the database to use 
        $dbh->disconnect;
        $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass});
    }
    
	
	#$query_string = "SET SQL_MODE=\"NO_AUTO_VALUE_ON_ZERO\"";
	#$query = $dbh->prepare($query_string);
	#$query->execute();
	#$query->finish();
	
#	$query_string = "CREATE TABLE IF NOT EXISTS `hosts` (
#  					`scenario` text collate utf8_spanish_ci NOT NULL,
#  					`local_scenario` text collate utf8_spanish_ci NOT NULL,
# 					`host` text collate utf8_spanish_ci NOT NULL,
# 					`local_specification` blob,
# 					`ip` text collate utf8_spanish_ci NOT NULL,
#  					`status` enum('creating','running','purging','destroying') collate utf8_spanish_ci NOT NULL
#					) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_spanish_ci;";
    $query_string = "CREATE TABLE IF NOT EXISTS `hosts` (
                    `scenario` TEXT,
                    `local_scenario` TEXT,
                    `host` TEXT,
                    `local_specification` BLOB,
                    `ip` TEXT,
                    `status` TEXT    
                    )";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();

#    $query_string = "CREATE TABLE IF NOT EXISTS `nets` (
#                    `name` text collate utf8_spanish_ci NOT NULL,
#                    `scenario` text collate utf8_spanish_ci NOT NULL,
#                    `external` text collate utf8_spanish_ci
#                    ) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_spanish_ci;";
    $query_string = "CREATE TABLE IF NOT EXISTS `nets` (
                    `name` text NOT NULL,
                    `scenario` text NOT NULL,
                    `external` text
                    )";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "CREATE TABLE IF NOT EXISTS `scenarios` (
  					`name` text NOT NULL,
  					`automac_offset` int(11) default NULL,
  					`mgnet_offset` int(11) default NULL
					)";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "CREATE TABLE IF NOT EXISTS `vlans` (
  					`number` int(11) NOT NULL,
  					`scenario` text NOT NULL,
  					`host` text  NOT NULL,
  					`external_if` text  NOT NULL
					)";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$query_string = "CREATE TABLE IF NOT EXISTS `vms` (
  					`name` text NOT NULL,
                    `type` text  NOT NULL,
                    `subtype` text  NOT NULL,
                    `os` text  NOT NULL,
                    `status` text  NOT NULL,
  					`scenario` text  NOT NULL,
  					`host` text  NOT NULL,
  					`ssh_port` int(11) default NULL
					)";
	$query = $dbh->prepare($query_string);
	$query->execute();
	$query->finish();
	
	$dbh->disconnect;
	
}	

#
# Subroutine to destroy DB structure
#
sub destroy_db{
	
    my $query;
    my $query_string;

    print "db_connection_info=$db->{conn_info}\n";
    my $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass});
	
    if ($db->{type} ne 'sqlite') {
		$query_string = "DROP DATABASE `$db->{name}`";
		$query = $dbh->prepare($query_string);
		$query->execute();
		$query->finish();
		$dbh->disconnect;
    } else {
    	# SQlite: delete TABLES 
    	my @tables = qw ( hosts nets scenarios vlans vms ); 

        for my $table (@tables) {
	        $query_string = "DROP TABLE `$table`";
	        if ($query = $dbh->prepare($query_string) ) {
	            $query->execute();
	            $query->finish();       
	        } else {
	           print "Can't delete table '$table': $DBI::errstr\n";
	        }
        }
    }
	
    $dbh->disconnect;
}

#
# Subroutine to reset DB structure
#
sub reset_db{
    
    my $query;
    my $query_string;

    print "db_connection_info=$db->{conn_info}\n";
    my $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass});
    
    if ($db->{type} ne 'sqlite') {
        $query_string = "DROP DATABASE `$db->{name}`";
        $query = $dbh->prepare($query_string);
        $query->execute();
        $query->finish();
        $dbh->disconnect;
    } else {
        # SQlite: delete TABLES 
        my @tables = qw ( hosts nets scenarios vlans vms ); 

        for my $table (@tables) {
            $query_string = "DROP TABLE `$table`";
            if ($query = $dbh->prepare($query_string) ) {
                $query->execute();
                $query->finish();       
            } else {
               print "Can't delete table '$table': $DBI::errstr\n";
            }
        }
    }
    
    $dbh->disconnect;
}
