# FileChecks.pm
#
#
#
# This file is a module part of VNUML package.
#
# Author: Fermin Galan Marquez (galan@dit.upm.es)
# Copyright (C) 2005, 	DIT-UPM
# 			Departamento de Ingenieria de Sistemas Telematicos
#			Universidad Politecnica de Madrid
#			SPAIN
########################
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

# FileChecks implementes several funcitons related with file checks

package VNX::FileChecks;
#package FileChecks;
require(Exporter);

@ISA = qw(Exporter);
@EXPORT = qw(
  valid_absolute_directoryname 
  valid_absolute_filename 
  do_path_expansion 
  get_conf_value
  get_abs_path
);

use strict;
use File::Glob ':glob';
use VNX::Globals;
use VNX::Execution;
use VNX::TextManipulation;
use AppConfig;
use AppConfig qw(:expand :argcount);    # AppConfig module constants import
use File::HomeDir;


# valid_absolute_directoryname
#
# Check if the argument (string) if a valid absolute directory name
#
# Return 1 if valid, 0 otherwise
#
# Note that a valid_absolute_directoryname is always a valid_absolute_filename
#
sub valid_absolute_directoryname {

   my $test_name = shift;

   if ($test_name =~ /^\/((\w|\.|-)+\/)*((\w|\.|-)+)?$/) {
      return 1;
     # FIXME format must be C:\path\path2 (no \\ allowed yet)
   }elsif($test_name =~ /^(\w:\\)((\w|\.|-)+\\)*((\w|\.|-)+)?$/){
   	  return 1;
   }
   else {
      return 0;
   }

}

# valid_absolute_filename
#
# Check if the argument (string) if a valid absolute filename
#
# Return 1 if valid, 0 otherwise
#
sub valid_absolute_filename {

   my $test_name = shift;
   
   if ($test_name =~ /^\/((\w|\.|-)+\/)*(\w|\.|-)+$/) {
      return 1;
   }
   else {
      return 0;
   }    

}

# do_path_expansion
#
# performs tilde (and wildcard) expansion and returns the expansion
# if there is more than one match, then it will return just the first
#

sub do_path_expansion {
	
	my $path = shift;

	# Note: we manually substitute the ~/ to avoid using /root/.vnx directory
	#       when vnx is invoked from a user shell where a "sudo su" has been issued
	my $home    = File::HomeDir->users_home($uid_name);
	$path =~ s#~/#$home/#;
	
	my @list = bsd_glob($path, GLOB_TILDE | GLOB_NOCHECK | GLOB_ERR );
	return $list[0];
}

# get_conf_value 
#
# Returns the value from a configuration file with the following format:
#     
#    param1=value
#    param2=value
#
#    [section1]
#    param1=value
#    param2=value
#
#    [section2]
#    param1=value
#    param2=value
#
# Returns undef if the value is not found
# 
# Parameters:
# - confFile: confifuration file
# - section:  the section name where the parameter is ('' if global parameter)
# - param:    the parameter name
#
sub get_conf_value {

    my $confFile = shift;
    my $section  = shift;
    my $param    = shift;

    my $result;

	sub error_management {
		#print "** error reading config value: $section $param\n";
	}
   
	my $vnx_config = AppConfig->new(
		{	CASE  => 0,                     # Case insensitive
			ERROR => \&error_management,    # Error control function
			CREATE => 1,    				# Variables that weren't previously defined, are created
			GLOBAL => {
				DEFAULT  => "<undef>",		# Default value for all variables
				ARGCOUNT => ARGCOUNT_ONE,	# All variables contain a single value...
			}
		}
	);

	# read the vnx config file
	$vnx_config->file($confFile);
	if ($section eq '' ) {
    	return $result = $vnx_config->get($param);	
	} else {
    	return $result = $vnx_config->get($section . "_" . $param );			
	}
=BEGIN
	#unless(-e $confFile){ return $result }
	open FILE, "< $confFile" or $execution->smartdie("$confFile not found");
	my @lines = <FILE>;
	foreach my $line (@lines){
	    if (($line =~ /$param/) && !($line =~ /^#/)){ 
			my @config1 = split(/=/, $line);
			my @config2 = split(/#/,$config1[1]);
			$result = $config2[0];
			chop $result;
			$result =~ s/\s+//g;
	    }
	}
=END
=cut
}

# get_abs_path
# 
#   Converts a relative path to absolute following VNX rules:
#     - if <basedir> tag is specified, then the path is relative to <basedir> value
#     - if <basedir> tag is NOT specified, then the path is relative to the XML file location
#   Beside, it performs tilde (and wildcard) expansion calling do_path_expansion 
#   If the path is already absolute, it does not modify it (only the mentioned expansion ).
# 
# Arguments:
#   pathname
#
# Result:
#   absolut pathname
# 
sub get_abs_path {
	
	my $path = shift;
	if ($path =~ /^\//) {
    	# Absolute pathname
		$path = &do_path_expansion($path);
    } else {
        # Relative pathname; we convert it to absolute
   		my $basedir = $dh->get_default_basedir;
		if ( $basedir eq "" ) {
			# No <basedir> tag defined: relative to xml_dir
			$path = &do_path_expansion( &chompslash( $dh->get_xml_dir ) . "/$path" );
		}
		else {
			# <basedir> tag defined: relative to basedir value
			$path = &do_path_expansion(	&chompslash($basedir) . "/$path" );
		}
	}			
}

1;
