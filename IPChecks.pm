# IPChecks.pm
#
# This file is a module part of VNUML package.
#
# Author: Fermin Galan Marquez (galan@dit.upm.es)
# Copyright (C) 2005, 	DIT-UPM
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

# IPChecks implementes several functions related with file checks

package VNUML::IPChecks;
require(Exporter);

@ISA = qw(Exporter);
@EXPORT = qw(valid_ipv4 valid_ipv4_with_mask 
             valid_ipv4_mask valid_ipv6_mask valid_dotted_mask valid_slashed_mask 
             valid_ipv6 valid_ipv6_with_mask );

use strict;
use Net::IPv6Addr;
use NetAddr::IP;
use VNUML::TextManipulation;

# valid_ipv4
#
# Check if the argument (string) is a valid representation of IPv4 address.
#
# Return 1 if valid, 0 otherwise
#
sub valid_ipv4 {
   my $ip = shift;

   if ($ip =~ /^(25[0-5]|2[0-4]\d|1\d\d|\d\d|\d)\.(25[0-5]|2[0-4]\d|1\d\d|\d\d|\d)\.(25[0-5]|2[0-4]\d|1\d\d|\d\d|\d)\.(25[0-5]|2[0-4]\d|1\d\d|\d\d|\d)$/) {
      return 1;
   }
   else {
      return 0;
   }
}

# valid_ipv4_with_mask
#
# Check if the argument (string) is a valid representation of IPv4 address, with a mask (after /) suffix.
#
# Return 1 if valid, 0 otherwise
#
sub valid_ipv4_with_mask {
   my $ip = shift;

   if ($ip =~ /^(25[0-5]|2[0-4]\d|1\d\d|\d\d|\d)\.(25[0-5]|2[0-4]\d|1\d\d|\d\d|\d)\.(25[0-5]|2[0-4]\d|1\d\d|\d\d|\d)\.(25[0-5]|2[0-4]\d|1\d\d|\d\d|\d)\/(3[0-2]|[1-2]\d|\d)$/) {
      return 1;
   }
   else {
      return 0;
   }
}

# valid_ipv4_mask
#
# Check if the argument (string) is a valid representation of and IPv4 mask,
# either in dotted or slashed notation
#
# Return 1 if valid, 0 otherwise
#
sub valid_ipv4_mask {
	
   my $mask = shift;
   
   return (&valid_dotted_mask($mask) || &valid_slashed_mask($mask,32));

}

# valid_ipv6_mask
#
# Check if the argument (string) is a valid representation of and IPv6 mask,
# in slashed notation
#
# Return 1 if valid, 0 otherwise
#
sub valid_ipv6_mask {
	
   my $mask = shift;
   
   return &valid_slashed_mask($mask,128);

}

# valid_dotted_mask
#
# Check if the argument (string) is a valid representation of a IPv4 mask, in dot notation
#
# For example "255.255.255.192" is a well-formed mask, "255.0.255.192" isn't
#
# Return 1 if valid, 0 otherwise
#
sub valid_dotted_mask {

   my $mask = shift;

   # This function is based converting the mask to a binary string and check if the ones (1) are
   # all in a row. OK, it's dirty but it works :) Anybody can suggest a smarter solution? 

   # Check if valid in dot notation
   unless (&valid_ipv4($mask)) {
      return 0;
   }

   # Convert to binary
   $mask =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/;
   my $binary_string = &dec2bin($1) . &dec2bin($2) . &dec2bin($3) . &dec2bin($4);

   # Check binary string
   unless ($binary_string =~ /^1+0*$/) {
      return 0;
   }

   return 1;

}

# valid_slashed_mask
#
# Check if the argument (string) is a valid representation of a IP mask
# in slashed notation (for example, "/24", "/64"). The second argument
# is the maximun allowed value for mask and will be 32 for IPv4 checkings
# and 128 for IPv4 checkings.
#
# Return 1 if valid, 0 otherwise
#
sub valid_slashed_mask {

   my $mask = shift;
   my $length = shift;

   # split IP and mask
   unless ($mask =~ /^\/(\d+)$/) {
      return 0;
   }
   
   # Length checking
   if ($1 > $length) {
      return 0;
   }
   
   return 1;
}

# valid_ipv6
#
# Check if the argument (string) is a valid representation of IPv6 address.
#
# Return 1 if valid, 0 otherwise
#
sub valid_ipv6 {
   my $ip = shift;

   if (Net::IPv6Addr::ipv6_chkip($ip)) {
      return 1;
   }
   else {
      return 0;
   }

}

# valid_ipv6_with_mask
#
# Check if the argument (string) is a valid representation of IPv6 address, with mask (after /) suffix
#
# Return 1 if valid, 0 otherwise
#
sub valid_ipv6_with_mask {

   my $addr = shift;

   # split IP and mask
   unless ($addr =~ /^(.*)\/(12[0-8]|1[0-1]\d|\d\d|\d)$/) {
      return 0;
   }

   # check IP
   my $ip = $1;

   if (Net::IPv6Addr::ipv6_chkip($ip)) {
      return 1;
   }
   else {
      return 0;
   }

}

1;