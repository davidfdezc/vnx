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

my $mode = $ARGV[0];
my $scenario_name = $ARGV[1];
my $vm_name = $ARGV[2];	

#
# Main	
#


=BEGIN No terminado todavía...

help:

ediv_console.pl shows information about virtual machines consoles

Usage:
  ediv_console.pl info

  ediv_console.pl info [scenario name]

  ediv_console.pl info [scenario name] [virtual machine]

  ediv_console.pl console [scenario name] [virtual machine]


print "mode=$mode\n";
if (!($mode =~ /^info$|^console$/)) {
	print "\nediv_console.pl shows information about virtual machines consoles \n\n";
	print "Usage:\n";
	print "" ediv_console.pl info [scenario name] [virtual machine]\n";
	
	exit(1);
}
=END
=cut


	# Get DB configuration
&getDBConfiguration;

if ($mode eq "info") {	
		
		# Get tunnels information
	&tunnelsInfo;
} elsif ($mode eq "console"){
	
		# Open console to virtual machine
	&console;
} else{
	print "Your choice $mode is not a recognized option (yet)\n";
}
#
# Main end
#

###########################################################
# Subroutines
###########################################################

#
# Subroutine to obtain DB configuration info
#
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
	$db_type = $db_config->get("db_type");
	$db_host = $db_config->get("db_host");
	$db_port = $db_config->get("db_port");
	$db_user = $db_config->get("db_user");
	$db_pass = $db_config->get("db_pass");
	$db_connection_info = "DBI:$db_type:database=$db;$db_host:$db_port";	
	
}	
	
#
# Subroutine to obtain information of tunnels
#
sub tunnelsInfo{
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);
	
	if ($scenario_name eq undef){
		my $query_string = "SELECT `name`,`host`,`ssh_port`,`simulation`,`type` FROM vms";
		my $query = $dbh->prepare($query_string);
		$query->execute();
			
		while (@ports = $query->fetchrow_array()) {
			if ($ports[4] eq "uml"){
				print ("Simulation $ports[3]: To access VM $ports[0] at $ports[1] use local port $ports[2]\n");
			}else{
				print ("Simulation $ports[3]: To access VM $ports[0] at $ports[1] execute command 'ediv_console.pl console $ports[3] $ports[0]'\n");
			}
		}
		
		$query->finish();
		
	} else{
		if ($vm_name eq undef){
			my $query_string = "SELECT `name`,`host`,`ssh_port`,`simulation`,`type` FROM vms WHERE simulation='$scenario_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			
			while (@ports = $query->fetchrow_array()) {
				if ($ports[4] eq "uml"){
					print ("Simulation $ports[3]: To access VM $ports[0] at $ports[1] use local port $ports[2]\n");
				}else{
					print ("Simulation $ports[3]: To access VM $ports[0] at $ports[1] execute command 'ediv_console.pl console $ports[3] $ports[0]'\n");
				}
			}
			
			$query->finish();
			
		} else{
			my $query_string = "SELECT `name`,`host`,`ssh_port`,`simulation`,`type` FROM vms WHERE simulation='$scenario_name' AND name='$vm_name'";
			my $query = $dbh->prepare($query_string);
			$query->execute();
			
			my @ports = $query->fetchrow_array();			
			if ($ports[4] eq "uml"){
				print ("Simulation $ports[3]: To access VM $ports[0] at $ports[1] use local port $ports[2]\n");
			}else{
				print ("Simulation $ports[3]: To access VM $ports[0] at $ports[1] execute command 'ediv_console.pl console $ports[3] $ports[0]'\n");
			}
						
			$query->finish();
		}
	}
	$dbh->disconnect;
}
	
#
# Subroutine to connect to one virtual machine
#
sub console {
	my $dbh = DBI->connect($db_connection_info,$db_user,$db_pass);

	my $query_string = "SELECT `type` FROM vms WHERE simulation='$scenario_name' AND name='$vm_name'";
	my $query = $dbh->prepare($query_string);
	$query->execute();
	my $vm_type = $query->fetchrow_array();
	$query->finish;
	
	my $query_string = "SELECT `host` FROM vms WHERE simulation='$scenario_name' AND name='$vm_name'";
	my $query = $dbh->prepare($query_string);
	$query->execute();
	my $vm_host = $query->fetchrow_array();
	$query->finish;

	if ($vm_type eq undef){
			print ("The virtual machine $vm_name from simulation $scenario_name doesn't exist\nYou can execute ediv_query_status.pl for a list of virtual machines\n");

	}elsif ($vm_type eq "uml"){

    	  		
		my $query_string = "SELECT `ssh_port` FROM vms WHERE simulation='$scenario_name' AND name='$vm_name'";

		my $query = $dbh->prepare($query_string);
		$query->execute();
		my $port = $query->fetchrow_array();

		$query->finish;
		
		if ($port eq undef){
			print ("The virtual machine $vm_name from simulation $scenario_name doesn't exist\nYou can execute ediv_query_status.pl to see that virtual machines exist\n");
		} else {
			my $ssh_command = "ssh -2 -o 'StrictHostKeyChecking no' root\@localhost -p $port";
			system ($ssh_command);	
		}

    }else{
    	#for non-uml vms, execute the display command in their host
		my $ssh_command = &build_display_command($dbh);
		&daemonize($ssh_command, "/tmp/$vm_host"."_log");
    }
    
    $dbh->disconnect;
}

sub build_display_command {
	
	my $dbh = shift;

	my $query_string = "SELECT `host` FROM vms WHERE simulation='$scenario_name' AND name='$vm_name'";
		my $query = $dbh->prepare($query_string);
	$query->execute();
	my $vm_host = $query->fetchrow_array();
	$query->finish;
	
	$query_string = "SELECT `ip` FROM hosts WHERE simulation='$scenario_name' AND host='$vm_host'";
		$query = $dbh->prepare($query_string);
	$query->execute();
	my $host_ip = $query->fetchrow_array();
	$query->finish;
	
	$filename = "/tmp/$scenario_name" . "_" . "$vm_host".".xml";
	
    return "ssh -2 -q -o 'StrictHostKeyChecking no' -X root\@$host_ip \'vnx -f $filename -v -u root --console -M $vm_name'"; 
}

	###########################################################
	# Subroutine to launch background operations
	###########################################################
sub daemonize {	
	print("\n");
    my $command = shift;
    my $output = shift;
    print("Backgrounded command:\n$command\n------> Log can be found at: $output\n");
    defined(my $pid = fork)			or die "Can't fork: $!";
    return if $pid;
    chdir '/tmp'					or die "Can't chdir to /: $!";
    open STDIN, '/dev/null'			or die "Can't read /dev/null: $!";
    open STDOUT, ">>$output"		or die "Can't write to $output: $!";
    open STDERR, ">>$output"		or die "Can't write to $output: $!";
    setsid							or die "Can't start a new session: $!";
    system("$command") == 0			or die "Could not execute $command!";
    exit();
}
