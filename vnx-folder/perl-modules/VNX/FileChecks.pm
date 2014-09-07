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

use strict;
use warnings;
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
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
# Check if the argument (string) is a valid absolute filename
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
    my $fname = shift;
    $fname =~ s#~/#~$uid_name/#;
    my @list = bsd_glob($fname, GLOB_TILDE | GLOB_NOCHECK | GLOB_ERR );	
#	my @list = bsd_glob(shift, GLOB_TILDE | GLOB_NOCHECK | GLOB_ERR );
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
# - root:     if defined, we change to root user before reading the config file 
#
sub get_conf_value {

    my $conf_file = shift;
    my $section   = shift;
    my $param     = shift;
    my $root      = shift;

    my $result;

if (defined($root)) {
	change_to_root();
}

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
	$vnx_config->file($conf_file);
if (defined($root)) {
    back_to_user();
}
	if ($section eq '' ) {
    	return $result = $vnx_config->get($param);	
	} else {
    	return $result = $vnx_config->get($section . "_" . $param );			
	}

}

=BEGIN

 20140501: Does not work at all....seems AppConfig is not designed to save values to files...
 
# set_conf_value 
#
# Sets a value to a configuration file
#
# Returns ...
# 
# Parameters:
# - conf_file: confifuration file
# - section:   the section name where the parameter is ('' if global parameter)
# - param:     the parameter name
# - value:     the new value of the parameter
# - root:      if defined, we change to root user before reading the config file 
#
sub set_conf_value {

    my $conf_file = shift;
    my $section   = shift;
    my $param     = shift;
    my $value     = shift;
    my $root      = shift;

    my $result;

print "conf_file=$conf_file, section=$section, param=$param, value=$value\n";
if (defined($root)) {
    change_to_root();
}

    sub error_management2 {
        print "** error writing config value\n";
    }
   
    my $vnx_config = AppConfig->new(
        {   CASE  => 0,                     # Case insensitive
            ERROR => \&error_management2,    # Error control function
            CREATE => 1,                    # Variables that weren't previously defined, are created
            GLOBAL => {
                DEFAULT  => "<undef>",      # Default value for all variables
                ARGCOUNT => ARGCOUNT_ONE,   # All variables contain a single value...
            }
        }
    );

    # read the vnx config file
    $vnx_config->file($conf_file);
    if ($section eq '' ) {
    	print "** no section\n";
    	#$vnx_config->define("$param=s");
        $result = $vnx_config->set($param, $value);
        print "result=$result\n";
    } else {
        $result = $vnx_config->set($section . "_" . $param, $value );            
        print "result=$result\n";
    }
if (defined($root)) {
    back_to_user();
}
    return $result;  

}
=END
=cut

# get_abs_path
# 
#   Converts a relative path to absolute following VNX rules:
#     - if <basedir> tag is specified, then the path is relative to <basedir> value
#     - if <basedir> tag is NOT specified, then the path is relative to the XML file location
#   Besides, it performs tilde (and wildcard) expansion calling do_path_expansion 
#   If the path is already absolute, it does not modify it (only the mentioned expansion).
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
