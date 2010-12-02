# DocumentChecks.pm
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

# DocumentChecks implementes several functions related with checks in the XML VNUML
# document

package VNX::DocumentChecks;
require(Exporter);

@ISA = qw(Exporter);
@EXPORT = qw( vm_has_tag 
              at_least_one_vm_without_mng_if 
              at_least_one_vm_with_mng_if 
              mng_if_value);

use strict;
use VNX::TextManipulation;

# vm_has_tag
#
# Returs true if the vm node passed as first argument has the tag specified int
# second argument (one ocurrence). In addition:
#
# - If the second attribute is "filetree", the third attribute is used  to check the 'seq' attribute
# - If the second attribute is "exec", the third third attribute is used to check the 'seq' attribute
#
sub vm_has_tag {

   my $vm = shift;
   my $tag = shift;



   # Search for tag
   my $tag_list = $vm->getElementsByTagName($tag);
   
   if ($tag_list->getLength != 0) {

      # Special case: filetree
      if ($tag eq "filetree") {
         my $seq = shift;
         for ( my $i = 0; $i < $tag_list->getLength; $i++ ) {
	        my $seq_at_string = $tag_list->item($i)->getAttribute("seq");
	        
	        # JSF 02/12/10: we accept several commands in the same seq tag,
			# separated by spaces
			my @seqs = split(' ',$seq_at_string);
			foreach my $seq_at (@seqs) {
	        
		        # FIXME: review the "always" thing
		        #return 1 if (($seq_at eq $seq) || ($seq_at eq "always"));
		        return 1 if ($seq_at eq $seq);
			}
	     }
      }
      # Special case: exec
      elsif ($tag eq "exec") {
         my $seq = shift;
         for ( my $i = 0; $i < $tag_list->getLength; $i++ ) {
	        my $seq_at_string = $tag_list->item($i)->getAttribute("seq");
	        
	        
	        # JSF 02/12/10: we accept several commands in the same seq tag,
			# separated by spaces
			my @seqs = split(' ',$seq_at_string);
			foreach my $seq_at (@seqs) {
	        
	        
	        return 1 if (($seq_at eq $seq));
			}
         }
      }
      else {
         return 1;
      }
   }

   # Any other case, tag not found
   return 0;

}

# at_least_one_vm_without_mng_if
#
# Arguments:
# - the DataHandler object describin the VNUML XML specification
# - the list of node machines
#
# Return:
# 
#    the name of the first <vm> with <mng_if>no</mng_if>
#    "", otherwise
#
# Dual function of at_least_one_vm_with_mng_if
#    
sub at_least_one_vm_without_mng_if {
   
   my $dh = shift;
   my @vm_ordered = @_;   
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
     my $vm = $vm_ordered[$i];
     return $vm->getAttribute("name") if (&mng_if_value($dh,$vm) eq "no");
   }
   return "";

}

# at_least_one_vm_with_mng_if
#
# Arguments:
# - The DataHandler object describin the VNUML XML specification
# - the list of node machines
#
# Return:
# 
#    the name of the first <vm> without <mng_if>no</mng_if>
#    "", otherwise
#
# Dual function of at_least_one_vm_without_mng_if
#
sub at_least_one_vm_with_mng_if {
 
   my $dh = shift;  
   my @vm_ordered = @_;   
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
     my $vm = $vm_ordered[$i];
     return $vm->getAttribute("name") if (&mng_if_value($dh,$vm) ne "no");
   }
   return "";

}

# mng_if_value
#
# Return the mng_if_value of the vm node passed as argument
#
# Arguments:
#	- The DataHandler object describin the VNUML XML specification
#   - the virtual machine
#    
sub mng_if_value {

   my $dh = shift;
   my $vm = shift;

   my $mng_if_value = $dh->get_default_mng_if;
   my $mng_if_list = $vm->getElementsByTagName("mng_if");
   if ($mng_if_list->getLength == 1) {
      $mng_if_value = &text_tag($mng_if_list->item(0));
   }

   return $mng_if_value;

}

1;
