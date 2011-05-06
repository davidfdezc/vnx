# TextManipulation.pm
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

# This module includes several miscelanous functions to process text.

package VNX::TextManipulation;

use strict;
use warnings;
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw( dec2bin bin2dec text_tag text_tag_multiline clean_line
              chompslash remove_heading_slash
              generate_random_string
              slashed_to_dotted_mask);


# dec2bin and bin2dec adapted from http://perlmonks.thepen.com/2664.html
#
sub dec2bin {
   my $str = unpack("B32", pack("N", shift));
   #$str =~ s/^0+(?=\d)//;   # otherwise you'll get leading zeros
   $str =~ s/^0*(\d{8})$/$1/;	# only the last 8 bits
   return $str;
}
sub bin2dec {
   return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}

# text_tag
#
# Gets text of the Element object that is passed as first argument.
#
# If the Element correpond to and emty tag, this function returns ""
#
sub text_tag {
   my $element = $_[0];
   my @element_children = $element->getChildNodes;
   my $n = @element_children;
   if ($n == "0") {
      return "";
   }
   else {
      my $string = &clean_line($element_children[0]->getNodeValue);
      $string =~ s/\n//g;
      return $string;
   }
}

# text_tag_multiline
#
# Gets text of the Element object that is passed as first argument. The different
# between this function and text_tag is that newlines are not purgued.
#
# If the Element correpond to and emty tag, this function returns ""
#
sub text_tag_multiline {
   my $element = $_[0];
   my @element_children = $element->getChildNodes;
   my $n = @element_children;
   if ($n == "0") {
      return "";
   }
   else {
      return &clean_line($element_children[0]->getNodeValue);
   }
}

# clean_line
#
# Replaces tabs with spaces anywhere
# Removes whitespaces at the beginning and at the end
# Note that this function DOESN'T Remove newlines
#
sub clean_line {
   my $string = shift;
   $string =~ s/\t/ /g;
   $string =~ s/^(\s*)//;
   $string =~ s/(\s*)$//;
   return $string;
}

# chompslash
#
# Removes final slashes from directory names
sub chompslash {
   my $string = shift;
   $string =~ s/\/*$//;
   return $string;
}

# remove_heading_slash
#
# Removes initial slashes (for relative directory names)
sub remove_heading_slash {
   my $string = shift;
   $string =~ s/^\/*//;
   return $string;
}

# generate_random_string
#
# Written by Guy Malachi guy@guymal.com (18 August, 2002),
# taken from http://guymal.com/mycode/generate_random_string/
#
# This function generates random strings of a given length
#
sub generate_random_string {
   my $length_of_randomstring=shift;#the length of the random string to generate

   my @chars=('a'..'z','A'..'Z','0'..'9','_');
   my $random_string;
   foreach (1..$length_of_randomstring) {
      #rand @chars will generate a random number between 0 and scalar@chars
      $random_string.=$chars[rand @chars];
   }
   return $random_string;
}

# slash_to_dotted
#
# The argument is a a number <=32 (for example, "24"). The method returns the 
# equivalent mask in dotted form (for example, "255.255.255.0").
#
# I'm sure this function is well-know and implemented in other places, but
# know I don't have the time to look for :)
#
# Returns a mask in dotted notation or the string "null" in the case of
# problems
#
sub slashed_to_dotted_mask {

   my $mask = shift;
   
   # Check format
   unless ($mask =~ /^(\d+)$/) {
      return "null";
   }
   if ($1 > 32) {
      return "null";
   }
   

   my $s = "null";
   if ($mask > 24) {
      $mask -= 24;
      my $b = "";
      while ($mask !=0) {
         $b .= "1" ;
         $mask = $mask - 1;
      }
      while (length $b < 8) {
         $b .= "0";
      } 
      $s = "255.255.255." . bin2dec($b);
   }
   elsif ($mask > 16) {
      $mask -= 16;
      my $b = "";
      while ($mask !=0) {
         $b .= "1" ;
         $mask = $mask - 1;
      }
      while (length $b < 8) {
         $b .= "0";
      }
      $s = "255.255." . bin2dec($b) . ".0"
   }
   elsif ($mask > 8) {
      $mask -= 8;
      my $b = "";
      while ($mask !=0) {
         $b .= "1" ;
         $mask = $mask - 1;
      }
      while (length $b < 8) {
         $b .= "0";
      }
      $s = "255." . bin2dec($b) . ".0.0"

   }
   else {
      my $b = "";
      while ($mask !=0) {
         $b .= "1" ;
         $mask = $mask - 1;
      }
      while (length $b < 8) {
         $b .= "0";
      }
      $s = bin2dec($b) . ".0.0.0"
   }
   return $s;
}

1;
