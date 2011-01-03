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
@EXPORT = qw(valid_absolute_directoryname valid_absolute_filename do_path_expansion get_conf_value);

use strict;
use File::Glob ':glob';
use VNX::Globals;
use VNX::Execution;

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
	my @list = bsd_glob(shift, GLOB_TILDE | GLOB_NOCHECK | GLOB_ERR );
	return $list[0];
}

# get_conf_value 
#
# Returns a value from a configuration file made of 'param=value' lines
# Dies (smartly) if the file is not found.
#
sub get_conf_value {

    my $confFile=shift;
    my $param=shift;
#    my $execution=shift;
    my $result="";
    
	unless(-e $confFile){ return $result }
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
 	return $result;
}

1;
