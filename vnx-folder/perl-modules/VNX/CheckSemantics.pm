# CheckSemantics.pm
#
# This file is a module part of VNX package.
#
# Author: Fermin Galan Marquez (galan@dit.upm.es)
# Copyright (C) 2005, 2006	DIT-UPM
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

# CheckSemantincs implements the needed methods to check the VNX XML specification before
# starting processing

package VNX::CheckSemantics;
require(Exporter);

@ISA = qw(Exporter);
@EXPORT = qw(
	validate_xml
	check_doc
);

use strict;
use NetAddr::IP;
use Net::Pcap;
use VNX::Globals;
use VNX::FileChecks;
use VNX::IPChecks;
use VNX::NetChecks;
use VNX::TextManipulation;
use XML::LibXML;


# 
# validate_xml
# 
#   Checks the existence of an XML file and validates it against the XSD .
#
# Arguments:
#   xmlFile: the XML file tio be validated
#
# Returns
#   empty string if no errors found; error messages if the parser finds them
#
sub validate_xml {
	
	my $xmlFile = shift;
	my $xsd;

	# Check file existance
	if (!-e $xmlFile){
		return "$xmlFile does not exists or is not readable\n";
	}

	# Load XML file content
	open INPUTFILE, "$xmlFile";
	my @xmlContent = <INPUTFILE>;
	my $xmlContent = join("",@xmlContent);
	close INPUTFILE;

	# DTD use is deprecated
   	if ($xmlContent =~ /<!DOCTYPE vnx SYSTEM "(.*)">/) { 
          return "parsing based on DTD is not supported; use XSD instead\n";	  
   	}

	# Get XSD file name from the XML
	if ($xmlContent =~ /="(\S*).xsd"/) {
		$xsd = $1 .".xsd";
	}else{
		return "XSD definition not found in XML file: $xsd\n";
	}

	my $schema = XML::LibXML::Schema->new(location => $xsd);
	my $parser = XML::LibXML->new;
	my $doc = $parser->parse_file($xmlFile);
	eval { $schema->validate( $doc ) };

	if ( my $ex = $@ ) {
		return $ex;
	}
	return;
}

# check_doc
#
# Arguments:
#
# - the DataHandler object reference that containts the document to be checked
# - the binaries_path hash reference
#
# Checks additional semantics in VNX file that can not be
# checked during XML validation process.
# Currently this check consist in:
#
#   - 1a. (formerly version checking, now is performed in the main program before calling check_doc)
#   - 1b. <scenario_name> content does not have any whitespace  
#   - 2.  ensure that the <ssh_version> is valid
#   - 3.  check <ssh_key> are valid and readable files
#   - 4.  check <shell> are valid files
#   - 5.  (conditional) tun_device is a valid, readable, writable characters file
#   - 6.  <basedir> are valid and readable directories
#   - 7a. valid network, mask, and offset for vm management
#   - 7b. exactly one <mgmt_net> child for the <vm_mgmt> tag if and only if
#         <vm_mgmt> tag has attribute type "net".
#   - 7c. the address of the mgmt_net is configured on an interface on the host machine
#   - 8a. there are no duplicated net names (<net>) and no name is the reserved word "lo"
#   - 8b. (conditional) capture_expression are right
#   - 8c. capture_expression only used with capture_file
#   - 8d. capture attribute only used with mode="uml_switch" nets
#   - 8e. uml_switch_binary are valid, readable and executable filenames
#   - 8f. external interfaces (external attribute of <net>) are actually physical interfaces
#         (they exist in the OS host enviroment)
#   - 8g. <net type="ppp"> has exactly two virtual machine interfaces connected to it
#   - 8h. 3/5/11: Eliminated to allow dynamips ppp links / only <net type="ppp"> networks has <bw> tag
#   - 8i. sock are readable, writable socket files
#   - 9a. there is not duplicated UML names (<vm>)
#   - 9b. (conditional) there is not <if> with id 0 in any UML (reserved for management),
#         if not <mng_if>no</mng_if> or vmmgmt_type eq 'none'
#   - 9c. there is not duplicated interfaces in the same UML (<if>)
#   - 9d. net attribute of <if> refers to existing <net> or "lo"
#   - 9e. <mac> can not be put within <if net="lo">
#   - 10. to check users and groups
#   - 11. to check <filetree>
#   - 12a. <filesystem> are valid, readable/executable files
#   - 12b. no more than one virtual machine use the same hostfs filesystem
#   - 12c. To check default filesystem type is valid
#   - 13a. <kernel> are valid, readable/executable files
#   - 13b. check the initrd attribute
#   - 13c. check the modules attribute
#   - 14. net attribute of <hostif> refers to existing <net>
#   - 15. there is not duplicated <physicalif> names (we would be defining twice the same thing)
#         and they exists in the OS host enviroment
#   - 16. <ipv4> valid addresses and mask
#   - 17. <ipv6> valid addresses and mask
#   - 18. check IPv4 or IPv6 addresses for destination and gateway in <route> tag
#   - 19. <bw> is an integer number (bps)
#   - 20. To check uniqueness of <console> id attribute in the same scope (<vm_defaults>) or <vm>
#   - 21. To check all the <exec> and <filetree >with the same seq attribute 
#         has also the same user mode attribute
#   - 22. To check user attribute is not used in <exec> within <host>
#   - 23. (formerly to check mode attribute is not used in <exec> within <host>, now mode is no
#         longer an attribute in this tag)
#
#   In addition:
#   - <vm> and <net> names max of $max_name_length characters
#   - <vm> and <net> 'name' attribute and does not have any whitespace
# 
# The functions returns error string describing problem or 1 if all is right
#

# TODO:
# - check that forwarding only appears <=1 times
# - check execution mode:
#       - Olive: only mode="sdisk" allowed
#       - Dynamips: only mode="telnet" allowed
#                   type="file" only allowed with ostype="show|set"

sub check_doc {
	
	my $max_name_length = 12;
	
	# Get arguments
#	my $dh= shift;
	my $bp = shift;
	my $uid = shift;
	
	my $doc = $dh->get_doc;
	my @vm_ordered = $dh->get_vm_ordered;

	my $is_root = $> == 0 ? 1 : 0;
	my $uid_name = $is_root ? getpwuid($uid) : getpwuid($>);
    
    # 1b. <scenario_name> content does not have any whitespace
    return "simulaton name \"".$dh->get_scename."\" can not containt whitespaces"
      if ($dh->get_scename =~ /\s/);
    
	# 2. Check ssh_version
    return $dh->get_ssh_version . " is not a valid ssh version"
		unless ($dh->get_ssh_version eq '1' || $dh->get_ssh_version eq '2');

    # 3. To check <ssh_key>
    my $ssh_key_list = $doc->getElementsByTagName("ssh_key");
    for (my $i = 0; $i < $ssh_key_list->getLength; $i++) {
	   my $ssh_key = &do_path_expansion(&text_tag($ssh_key_list->item($i)));
	   return "$ssh_key is not a valid absolute filename" unless &valid_absolute_filename($ssh_key);
	   return "$ssh_key (ssh key file) does not exist or is not readable" unless (-r $ssh_key);
    }

    # 4. To check <shell>
    my $shell_list = $doc->getElementsByTagName("shell");
    for (my $i = 0; $i < $shell_list->getLength; $i++) {
	   my $shell = &do_path_expansion(&text_tag($shell_list->item($i)));
	   return "$shell (shell) is not a valid absolute filename" unless &valid_absolute_filename($shell);
    }

    # 5. To check <tun_device>
    #my $tun_device_list = $doc->getElementsByTagName("tun_device");
    #if ($tun_device_list->getLength != 0) {
    #   my $tun_device = &text_tag($tun_device_list->item(0));
    #   return "$tun_device is not a valid absolute filename" unless &valid_absolute_filename($tun_device);
    #}
    #if (&tundevice_needed($dh,$dh->get_vmmgmt_type,$dh->get_vm_ordered)) {
    if (&tundevice_needed($dh->get_vmmgmt_type,$dh->get_vm_ordered)) {
       return $dh->get_tun_device . " (tun_device) is not a valid absolute filename" 
          unless &valid_absolute_filename($dh->get_tun_device);
       return  $dh->get_tun_device . " (tun_device) does not exist or is not readable (user $uid_name)"
          unless (-r $dh->get_tun_device);
       return  $dh->get_tun_device . " (tun_device) is not writeable (user $uid_name)"
          unless (-w _);
       return $dh->get_tun_device . " (tun_device) is not a valid character device file" 
          unless (-c _);
    }

    # 6. To check <basedir>
    my $basedir_list = $doc->getElementsByTagName("basedir");
    for (my $i = 0; $i < $basedir_list->getLength; $i++) {
	   my $basedir = &do_path_expansion(&text_tag($basedir_list->item($i)));
       return $basedir . " (basedir) is not a valid absolute directory name" 
         unless &valid_absolute_directoryname($basedir);
       return $basedir . " (basedir) does not exist or is not readable (user $uid_name)"
         unless (-d $basedir);
    }   

	# 7. To check <vm_mgmt>
	
	# 7a. Valid network, mask and offset
	if ($dh->get_vmmgmt_type ne 'none') {
		return "<vm_mgmt> network attribute \"".$dh->get_vmmgmt_net."\" is invalid"
			unless (&valid_ipv4($dh->get_vmmgmt_net));
		return "<vm_mgmt> mask attribute \"".$dh->get_vmmgmt_mask."\" is invalid (must be between 8 and 30)"
			unless ($dh->get_vmmgmt_mask =~ /^\d+$/ && $dh->get_vmmgmt_mask >= 8 && $dh->get_vmmgmt_mask <= 30);
		return "<vm_mgmt> offset attribute ".$dh->get_vmmgmt_offset." is too large for mask ".$dh->get_vmmgmt_mask
			if ($dh->get_vmmgmt_mask !~ /^\d+$/ || $dh->get_vmmgmt_offset > (1 << (32 - $dh->get_vmmgmt_mask)) - 3);
	}
	if ($dh->get_vmmgmt_type eq 'private') {
		return "<vm_mgmt> offset attribute must be a multiple of 4 for private management" if ($dh->get_vmmgmt_offset % 4 != 0);
	}
	my $vmmgmt_list = $doc->getElementsByTagName("vm_mgmt");
	my $vmmgmt_net_list;
	my $vmmgmt_net_list_len = 0;
	my $vmmgmt_hostmap_list;
	# DFC 31/3/2011: <vm_mgmt> made compulsory to simplify 
	if ($vmmgmt_list->getLength == 0) {
		return "<vm_mgmt> tag missing"
	} elsif ($vmmgmt_list->getLength == 1) {
		$vmmgmt_net_list = $vmmgmt_list->item(0)->getElementsByTagName("mgmt_net");
		$vmmgmt_net_list_len = $vmmgmt_net_list->getLength;
		$vmmgmt_hostmap_list = $vmmgmt_list->item(0)->getElementsByTagName("host_mapping");
	} else {
		return "tag <vm_mgmt> duplicated"
	}
	
    # 7b. exactly one <mgmt_net> child for the <vm_mgmt> tag if and only if
    # <vm_mgmt> tag has attribute type "net".	
	if ($dh->get_vmmgmt_type eq 'net') {
		return "<vm_mgmt> element of type=\"net\" must have exactly one <mgmt_net> child element"
		if ($vmmgmt_net_list_len != 1);
		my $sock = &do_path_expansion($vmmgmt_net_list->item(0)->getAttribute("sock"));
		
		# The sock file checking is avoid when autoconfigure attribute is in use
		# and involing user is root
		unless (($dh->get_vmmgmt_autoconfigure ne "") && ($is_root)) {
		   $> = $uid if ($is_root);
		   return "$sock (sock) does not exist or is not readable (user $uid_name)" unless (-r $sock);
		   return "$sock (sock) is not writeable (user $uid_name)" unless (-w _);
		   return "$sock (sock) is not a valid socket" unless (-S _);
		   $> = 0 if ($is_root);
		   
		   # 7c. the address of the mgmt_net is configured on an interface on the host machine
		   return "No interface on the host is configured for VM management with address " . $dh->get_vmmgmt_hostip . "/" . $dh->get_vmmgmt_mask
		      unless (&hostip_exists($dh->get_vmmgmt_hostip, $dh->get_vmmgmt_mask));
		}		

	} else {
		return "<vm_mgmt> may only have a <mgmt_net> child if attribute type=\"net\"" if ($vmmgmt_net_list_len > 0);
	}
	return "<vm_mgmt> may not have a <host_mapping> child if attribute type=\"none\""
		if (defined($vmmgmt_hostmap_list) && $vmmgmt_hostmap_list->getLength > 0 && $dh->get_vmmgmt_type eq 'none');

   # 8. To check <net>
   # Hash for duplicated names detection
   my %net_names;
   
   # Hash for duplicated physical interface detection
   my %phyif_names;

   # To get list of defined <net>
   my $net_list = $doc->getElementsByTagName("net");

   # To process list
   for ( my $i = 0; $i < $net_list->getLength; $i++ ) {
      my $net = $net_list->item($i);

      # To get name attribute
      my $name = $net->getAttribute("name");
      
      # To check name length
      my $upper = $max_name_length + 1;
      return "net name $name is too long: max $max_name_length characters"
         if ($name =~ /^.{$upper,}$/);
         
      # To check name has no whitespace
      return "net name \"$name\" can not containt whitespaces"
      	if ($name =~ /\s/);

      # To get mode attribute
      my $mode = $net->getAttribute("mode");

      # 8a. there are no duplicated net names (<net>) and no name is the reserved word "lo"
      if (defined($net_names{$name})) {
         return "duplicated net name: $name";
      }
      elsif ($name eq "lo") {
      	return "\"lo\" is a reserved word that can not be used as <net> name (you can simply use \"lo_\" instead)";
      }
	  elsif ($name =~ /_Mgmt$/) {
		return "the suffix \"_Mgmt\" has been designated for management networks and cannot be used in a <net> tag";
	  }
      else {
         $net_names{$name} = 1;
      }

      my $capture_file = $net->getAttribute("capture_file");
      my $capture_expression = $net->getAttribute("capture_expression");
      my $capture_dev = $net->getAttribute("capture_dev");

      #8b. capture_expression is right
      if ($capture_expression ne "") {
         my ($err, $result);
         my $dev = Net::Pcap::lookupdev(\$err);

         my $filter;
         my $pcap_t = Net::Pcap::open_live($dev, 1024, 1, 0, \$err);
         if ($is_root) {
            $result = Net::Pcap::compile($pcap_t, \$filter, $capture_expression, 0, 0);
         }
         if ($result == -1) {
            return "net $name capture filter expression \"$capture_expression\" not valid\n";
         }
      }

      #8c. capture_expression only used with capture_file
      return "expression \"$capture_expression\" has no sense without a capture_file attribute in net $name" if (($capture_expression) && !($capture_file));
      
      #8d. capture attribute only used with mode="uml_switch" nets
      return "capture atributes in net $name only make sense in mode=\"uml_switch\" nets" if ((($capture_expression) || ($capture_file) || ($capture_dev)) && !($mode eq "uml_switch"));

      my $umlswitch_binary = &do_path_expansion($net->getAttribute("uml_switch_binary"));

      #8e. uml_switches are valid, readable and executable filenames
      if ($umlswitch_binary !~ /^$/) {
         $> = $uid if ($is_root);
         return "$umlswitch_binary (umlswitch_binary) is not a valid absolute filename" unless &valid_absolute_filename($umlswitch_binary);
         return "$umlswitch_binary (umlswitch_binary) is not readable or executable (user $uid_name)" unless (-r $umlswitch_binary && -x $umlswitch_binary);
		 $> = 0 if ($is_root);
       }

      # 8f. To check external attribute (if present)
      # (this method is not very strong, only existence and duplication is 
      # checked; a best checking would be to analyze the full information 
      # returned by ifconfig command) 

      my $external_if = $net->getAttribute("external");
      unless ($external_if =~ /^$/) {
	    #print $bp->{"ifconfig"} . " $external_if &> /dev/null\n";
	    
	    # DFC (30/3/2011): only check the interface existance not the subinterface 
	    # (we eliminate the .XXX from the interface name) 
		my $external_base_if = $external_if;
		$external_base_if =~ s/\..*//;
	    if (system($bp->{"ifconfig"} . " $external_base_if 2&> /dev/null")) {
	      return "in network $name, $external_base_if does not exist";
	    } 
	    # Check the VLAN attribute (to compose the physical name, for 
	    # duplication checking)
	    my $vlan = $net->getAttribute("vlan");
	    my $phy_name;
	    unless ($vlan =~ /^$/) {
	    	$phy_name = "$external_if.$vlan";
	    }
	    else {
	    	$phy_name = "$external_if";
	    }
	    
	    if (defined($phyif_names{$phy_name})) {
	    	return "two networks are attemping to use the same external physical interface: $phy_name";
	    }
	    else {
	    	$phyif_names{$phy_name} = 1;
	    }
      }
      
      # 8g. To check only two virtual machines for PPP nets
      my $type = $net->getAttribute("type");
      if ($type eq "ppp") {
         # Get all the ifs of the scenario
         my $machines = 0;
         my $if_list = $doc->getElementsByTagName("if");
         for ( my $j = 0; $j < $if_list->getLength; $j++ ) {
         	if ($if_list->item($j)->getAttribute("net") eq $name) {
         		$machines++;
         		last if ($machines > 3);
         	}
         }
         return "PPP $name net is connected to just one interface: PPP networks must be connected to exactly two interfaces" if ($machines < 2);
         return "PPP $name net is connected to more than two interface: PPP networks must be connected to exactly two interfaces"if ($machines > 2);         
      }
      
      if ($type ne "ppp") {
         #8h. To check no-PPP networks doesn't have <bw> tag
         my $bw_list = $net->getElementsByTagName("bw");
         return "net $name is not a PPP network and only PPP networks can have a <bw> tag" if ($bw_list->getLength != 0)
      }
      else {
         # DFC 3/5/11: relaxed to allow PPP links in dynamips withouth <bw> tag
         #8h. To check PPP networks has <bw> tag
         #my $bw_list = $net->getElementsByTagName("bw");
         #return "net $name is a PPP network and PPP networks must have a <bw> tag" if ($bw_list->getLength == 0)
      }

      # 8i. Check sock files
      my $sock = &do_path_expansion($net->getAttribute("sock"));
	  if ($sock !~ /^$/) {
		$> = $uid if ($is_root);
		return "$sock (sock) does not exist or is not readable (user $uid_name)" unless (-r $sock);
		return "$sock (sock) is not writeable (user $uid_name)" unless (-w _);
		return "$sock (sock) is not a valid socket" unless (-S _);
		$> = 0 if ($is_root);
	  }
      
   }
   
   # 9. To check <vm> and <if>
   
   # Hash for duplicated names detection
   my %vm_names;

   # Avoid duplicated hostfs directories
   my %hostfs_paths;
   
   for ( my $i = 0; $i < @vm_ordered; $i++) {
      my $vm = $vm_ordered[$i];

      # To get name attribute
      my $name = $vm->getAttribute("name");
      
      # To get type attribute
      my $vm_type = $vm->getAttribute("type");		         

      # To check name length
      my $upper = $max_name_length + 1;
      return "vm name $name is too long: max $max_name_length characters"
         if ($name =~ /^.{$upper,}$/);

      # To check name has no whitespace
      return "vm name \"$name\" can not containt whitespaces"
      	if ($name =~ /\s/);

      # Calculate the efective basedir (laterly used for <filetree> checkings)
      my $effective_basedir = $dh->get_default_basedir;
      my $basedir_list = $vm->getElementsByTagName("basedir");
      if ($basedir_list->getLength == 1) {
         $effective_basedir = &text_tag($basedir_list->item(0));
      }

      # 9a. To check if the same name has been seen before
      if (defined($vm_names{$name})) {
         return "duplicated vm name: $name";
      }
      else {
         $vm_names{$name} = 1;
      }

      # Hash for duplicated ids detection
      my %if_ids_eth;
      my %if_ids_lo;

      # To get UML's interfaces list
      my $if_list = $vm->getElementsByTagName("if");

      # To process list
      for ( my $j = 0; $j < $if_list->getLength; $j++) {
         my $if = $if_list->item($j);

         # To get id attribute
         my $id = $if->getAttribute("id");
         
         # To get net attribute
         my $net = $if->getAttribute("net");

         # To check <mng_if>
	     my $mng_if_value = $dh->get_default_mng_if;
	     my $mng_if_list = $vm->getElementsByTagName("mng_if");
	     if ($mng_if_list->getLength == 1) {
            $mng_if_value = &text_tag($mng_if_list->item(0));
		 }

         # 9b. To check id 0 is not used
         return "if id 0 in vm $name is not allowed while vm management is enabled unless <mng_if> is used"
            if (($id == 0) && $dh->get_vmmgmt_type ne 'none' && ($mng_if_value ne "no"));

         # 9c. To check if the same id has been seen before
         if ($net eq "lo") {
            if (defined($if_ids_lo{$id})) {
               return "duplicated if id $id inside vm $name (for lo interfaces)";
            }
            else {
               $if_ids_lo{$id} = 1;
            }
         }
         else {
            if (defined($if_ids_eth{$id})) {
               return "duplicated if id $id inside vm $name (for eth interfaces)";
            }
            else {
               $if_ids_eth{$id} = 1;
            }
         }

         # 9d. To check that there is a net with this name or "lo"
         unless (($net eq "lo") || ($net_names{$net} == 1)) {
            return "net $net defined for interface $id of virtual machine $name is not valid: it must be defined in a <net> tag (or use \"lo\")";
         }
         
         # 9e. <mac> can not be put within <if net="lo">
         if ($net eq "lo") {
         	my $mac_list = $if->getElementsByTagName("mac");
         	if ($mac_list->getLength != 0) {
         		return "<if net=\"lo\"> can not nests <mac> tag";
         	}
         } 
         # 9f. check that uml_switch is only used with uml vms, that is, an interface
         #     of a libvirt or dynamips machine cannot be connected to a uml_switch
	     for ( my $i = 0; $i < $net_list->getLength; $i++ ) {
      		 my $net_def = $net_list->item($i);
      		 my $net_id = $net_def->getAttribute("id");
      		 my $net_name = $net_def->getAttribute("name");
      		 my $net_mode = $net_def->getAttribute("mode");
      		 if ($net_name eq $net) {
      		 	if ( (($vm_type eq 'libvirt') or ($vm_type eq 'dynamips')) and ($net_mode eq 'uml_switch') ){
	         	 	return "vm '$name' of type '$vm_type' is not allowed to connect its interface '$id' to network '$net' based on 'uml_switch'";
      		 	}
      		 }
	     }
         
      }

	  #10. Check users and groups
      my $user_list = $vm->getElementsByTagName("user");
	  for (my $j = 0; $j < $user_list->getLength; $j++) {
		 my $user = $user_list->item($j);
		 my $username = $user->getAttribute("username");
		 my $effective_group = $user->getAttribute("group");
		 return "Invalid username $username"
			 unless ($username =~ /[A-Za-z0-9_]+/);
		 my $group_list = $user->getElementsByTagName("group");
		 my %user_groups;
		 for (my $k = 0; $k < $group_list->getLength; $k++) {
			my $group = &text_tag($group_list->item($k));
			$user_groups{$group} = 1;
			return "Invalid group $group for user $username"
				unless ($group =~ /[A-Za-z0-9_]+/);
		 }
         return "Effective group " . $effective_group . " does not exist as a <group> tag for user $username"
             unless ($user_groups{$effective_group} eq '' || $user_groups{$effective_group});
	  }

      #11. To check <filetree>
      my $filetree_list = $vm->getElementsByTagName("filetree");

      # To process list
      for ( my $j = 0; $j < $filetree_list->getLength; $j++) {
         my $filetree = &text_tag($filetree_list->item($j));
         my $root = $filetree_list->item($j)->getAttribute("root");
         # Calculate the efective filetree
         my $filetree_effective;
         if ($filetree =~ /^\//) {
            # Absolute pathname
            $filetree_effective = &do_path_expansion($filetree);
         }
         else {
         	# Relative pahtname
         	if ($effective_basedir eq "") {
         	   # Relative to xml_dir
         	   $filetree_effective = &do_path_expansion(&chompslash($dh->get_xml_dir) . "/$filetree");
         	}
         	else {
               # Relative to basedir
               $filetree_effective = &do_path_expansion(&chompslash($effective_basedir) . "/$filetree");
         	}
         }
                 
         # Checkings
         return "$filetree (filetree) is not a valid absolute directory name" 
            unless &valid_absolute_directoryname($filetree_effective);
         return "$filetree_effective (filetree) is not readable/executable (user $uid_name)"
            unless (-r $filetree_effective && -x _);
            #unless (-r $filetree_effective );
         return "$filetree (filetree) is not a valid directory"
            unless (-d _);
         return "$root (root) is not a valid absolute directory name" unless &valid_absolute_directoryname($root);
      }
      # vm type attribute is requiered; subtype and os are optional or not depending on the type value
	  my $vm_subtype = $vm->getAttribute("subtype");		         
	  my $vm_os = $vm->getAttribute("os");		         
	  if ($vm_type eq "libvirt") {
		  if ( ($vm_subtype eq '') or ($vm_os eq '') ) {
			  return "missing 'subtype' and/or 'os' attribute for libvirt vm $name";
		  }
	  } elsif ($vm_type eq "dynamips") {
		  if ($vm_subtype eq '') {
		  	  return "missing 'subtype' attribute for dynamips vm $name";
	  	  }
	  }

   }

   #12. To check <filesystem>
   $> = $uid if ($is_root);
   my $filesystem_list = $doc->getElementsByTagName("filesystem");
   for ( my $i = 0 ; $i < $filesystem_list->getLength; $i++) {
      my $filesystem = &do_path_expansion(&text_tag($filesystem_list->item($i)));
      my $filesystem_type = $filesystem_list->item($i)->getAttribute("type");
      if ($filesystem_type eq "hostfs") {         	
         # 12a. <filesystem> are valid, readable/executable files
         return "$filesystem (filesystem) is not a valid absolute directory name" unless &valid_absolute_directoryname($filesystem);
         return "$filesystem (filesystem) is not does not exist or is not readable (user $uid_name)" unless (-d $filesystem);
         return "$filesystem (filesystem) is not readable/executable (user $uid_name)" unless (-r _ && -x _);
         # 12b. no more than one virtual machine use the same hostfs filesystem
         if ($hostfs_paths{&chompslash($filesystem)} == 1) {
            return "the same hostfs directory (" . &chompslash($filesystem) . ") is being used in more than one virtual machine";
         }
         else {
            $hostfs_paths{&chompslash($filesystem)} = 1;
         }
         	
      }
      else {
         #12a (again). <filesystem> are valid, readable/executable files
         # DFC 25/4/2011: allowed relative filesystem paths following rules descried in FileChecks->get_abs_path
         $filesystem = &get_abs_path ($filesystem);
         # return "$filesystem (filesystem) is not a valid absolute filename" unless &valid_absolute_filename($filesystem);
         return "$filesystem (filesystem) does not exist or is not readable (user $uid_name)" unless (-r $filesystem);
         if ($filesystem_type eq "direct") {
            return "$filesystem (filesystem) is not writeable (user $uid_name)" unless (-w $filesystem);
         }
      }
   }

   #12c. To check default filesystem type is valid
   if ($dh->get_default_filesystem_type eq "direct" ||
      $dh->get_default_filesystem_type eq "hostfs") {
      return "default filesystem type " . $dh->get_default_filesystem_type . " is forbidden";
   }

   #13. To check <kernel>
   my $kernel_list = $doc->getElementsByTagName("kernel");
   for ( my $i = 0 ; $i < $kernel_list->getLength; $i++) {
      my $kernel = $kernel_list->item(0);
      my $kernel_exe = &do_path_expansion(&text_tag($kernel));
      my $kernel_initrd = &do_path_expansion($kernel->getAttribute("initrd"));
      my $kernel_modules = &do_path_expansion($kernel->getAttribute("modules"));
      # 13a. <kernel> are valid, readable/executable files
      return "$kernel_exe (kernel) is not a valid absolute filename" unless &valid_absolute_filename($kernel_exe);
      return "$kernel_exe (kernel) does not exist or is not readable/executable (user $uid_name)" unless (-r $kernel_exe && -x _);
      # 13b. initrd checking
      if ($kernel_initrd !~ /^$/) {
         return "$kernel_initrd (initrd) is not a valid absolute filename" unless &valid_absolute_filename($kernel_initrd);
         return "$kernel_initrd (initrd) does not exist or is not readable (user $uid_name)" unless (-r $kernel_initrd);
      }
      # 13c. modules checking
	  if ($kernel_modules !~ /^$/) {
         return "$kernel_modules (modules) is not a valid absolute directory" unless &valid_absolute_directoryname($kernel_modules);
         return "$kernel_modules (modules) does not exist or is not readable (user $uid_name)" unless (-d $kernel_modules);
         return "$kernel_modules (modules) is not readable/executable (user $uid_name)" unless (-r $kernel_modules && -x $kernel_modules);
      }      
   }
   $> = 0 if ($is_root);

   # 14. To check <hostif>
   my $hostif_list = $doc->getElementsByTagName("hostif");

   # To process list
   for ( my $i = 0; $i < $hostif_list->getLength; $i++) {
      my $hostif = $hostif_list->item($i);

      # To get net attribute
      my $net = $hostif->getAttribute("net");

      # To check that there is a net with this name
      unless ($net_names{$net} == 1) {
	    return "hostif net $net is not valid: it must be defined in a <net> tag";
      }

   }

   # 15. To check <physicalif>
   # Hash for duplicated names detection
   my %phyif_names_ipv4;
   my %phyif_names_ipv6;

   # To get list of defined <net>
   my $phyif_list = $doc->getElementsByTagName("physicalif");

   # To process list
   for ( my $i = 0; $i < $phyif_list->getLength; $i++ ) {
      my $phyif = $phyif_list->item($i);

      # To get name and type attribute
      my $name = $phyif->getAttribute("name");
      my $type = $phyif->getAttribute("type");

      if ($type eq "ipv6") {
         # IPv6 interface
         
         # To check if the same name has been seen before in IPv6 configurations
         if ($phyif_names_ipv6{$name} == 1) {
            return "duplicated physicalif name for IPv6 configuration: $name";
         }
         else {
            $phyif_names_ipv6{$name} = 1;
         }
         
         # It exists?         
         if (system($bp->{"ifconfig"} . " $name 2&> /dev/null")) {
	        return "physicalif $name does not exists";
         }         
         
         # To get ip attribute
         my $ip = $phyif->getAttribute("ip");
      
         # To check if valid IPv6 address
         unless (&valid_ipv6_with_mask($ip)) {
            return "'$ip' is not a valid IPv6 address with mask (/64 for example) in a <physicalif> ip";
         }
         
         # To get gw attribute
         my $gw = $phyif->getAttribute("gw");
         
         # To check if valid IPv6 address
         # Note the empty gw is allowable. This attribute is #IMPLIED in DTD and
         # the physicalif_config in vnumlparser.pl deals rightfully with emtpy values
         unless ($gw =~ /^$/ ) {
            unless (&valid_ipv6($gw)) {
               return "'$gw' is not a valid IPv6 address in a <physicalif> gw";
            }
         }
         
      }
      else {
      	 # IPv4 interface
      	 
         # To check if the same name has been seen before in IPv4 configurations
         if ($phyif_names_ipv4{$name} == 1) {
            return "duplicated physicalif name for IPv4 configuration: $name";
         }
         else {
            $phyif_names_ipv4{$name} = 1;
         }

         # It exists?
         if (system($bp->{"ifconfig"} . " $name 2&> /dev/null")) {
	        return "physicalif $name does not exists";
         }

         # To get ip attribute
         my $ip = $phyif->getAttribute("ip");
      
         # To check if valid IPv4 address
         unless (&valid_ipv4($ip)) {
            return "'$ip' is not a valid IPv4 address in a <physicalif> ip";
         }

         # To get mask attribute
         my $mask = $phyif->getAttribute("mask");
         $mask="255.255.255.0" if ($mask =~ /^$/);

         # To check if valid IPv4 mask
         unless (&valid_ipv4_mask($mask)) {
            return "'$mask' is not a valid IPv4 netmask in a <physicalif> mask attribute";
         }
         
         # To get gw attribute
         my $gw = $phyif->getAttribute("gw");
         
         # To check if valid IPv4 address
         # Note the empty gw is allowable. This attribute is #IMPLIED in DTD and
         # the physicalif_config in vnumlparser.pl deals rightfully with emtpy values
         unless ($gw =~ /^$/ ) {
            unless (&valid_ipv4($gw)) {
               return "'$gw' is not a valid IPv4 address in a <physicalif> gw";
            }
         }
      }
   }

   # 16. To check IPv4 addresses
   my $ipv4_list = $doc->getElementsByTagName("ipv4");
   for ( my $i = 0; $i < $ipv4_list->getLength; $i++ ) {
      my $ipv4 = &text_tag($ipv4_list->item($i));
      my $mask = $ipv4_list->item($i)->getAttribute("mask");
      if ($mask eq '') {
         # Doesn't has mask attribute, mask would be implicit in address
         unless (&valid_ipv4($ipv4) || &valid_ipv4_with_mask($ipv4)) {
            return "'$ipv4' is not a valid IPv4 address (Z.Z.Z.Z) or IPv4 address with implicit mask (Z.Z.Z.Z/M, M<=32) in a <ipv4>";
         }
      }
      else {
         unless (&valid_ipv4_mask($mask)) {
            return "'$mask' is not a valid IPv4 netmask in a <ipv4> mask attribute";
         }
         if (&valid_ipv4_with_mask($ipv4)) {
            return "mask attribute and implicit mask (Z.Z.Z.Z/M, M<=32) are not simultanelly allowed in <ipv4>";
         }
         unless (&valid_ipv4($ipv4)) {
            return "'$ipv4' is not a valid IPv4 address (Z.Z.Z.Z) in a <ipv4>";
         }
      }
   }

   # 17. To check IPv6 addresses
   my $ipv6_list = $doc->getElementsByTagName("ipv6");
   for ( my $i = 0; $i < $ipv6_list->getLength; $i++ ) {
      my $ipv6 = &text_tag($ipv6_list->item($i));
      my $mask = $ipv6_list->item($i)->getAttribute("mask");      
      if ($mask eq '') {
         # Doesn't has mask attribute, mask would be implicit in address
         unless (&valid_ipv6($ipv6) || &valid_ipv6_with_mask($ipv6)) {
            return "'$ipv6' is not a valid IPv6 address (Z:Z:Z:Z:Z:Z:Z:Z) or IPv6 address with implicit mask (Z:Z:Z:Z:Z:Z:Z:Z/M, M<=128) in a <ipv6>";
         }
      }
      else {
         unless (&valid_ipv6_mask($mask)) {
            return "'$mask' is not a valid IPv6 netmask in a <ipv6> mask attribute";
         }
         if (&valid_ipv6_with_mask($ipv6)) {
            return "mask attribute and implicit mask (Z:Z:Z:Z:Z:Z:Z:Z/M, M<=129) are not simultanelly allowed in <ipv6>";
         }
         unless (&valid_ipv6($ipv6)) {
            return "'$ipv6' is not a valid IPv4 address (Z:Z:Z:Z:Z:Z:Z:Z) in a <ipv6>";
         }
      }
      
   }

   # 18. To check addresses related with <route> tag
   my $route_list = $doc->getElementsByTagName("route");
   for ( my $i = 0; $i < $route_list->getLength; $i++ ) {
      my $route_dest = &text_tag($route_list->item($i));
      my $route_gw = $route_list->item($i)->getAttribute("gw");
      my $route_type = $route_list->item($i)->getAttribute("type");
      if ($route_type eq "ipv4") {
         unless (($route_dest eq "default")||(&valid_ipv4_with_mask($route_dest))) {
            return "'$route_dest' is not a valid IPv4 address with mask (Z.Z.Z.Z/M) in a <route>";
         }
         unless (&valid_ipv4($route_gw)) {
            return "'$route_gw' is not a valid IPv4 address (Z.Z.Z.Z) for a <route> gw";
         }
      }
      elsif ($route_type eq "ipv6") {
         unless (($route_dest eq "default")||(&valid_ipv6_with_mask($route_dest))) {
            return "'$route_dest' is not a valid IPv6 address with mask (only Z:Z:Z:Z:Z:Z:Z:Z/M is supported by the time) in a <route>";
         }
         unless (&valid_ipv6($route_gw)) {
            return "'$route_gw' is not a valid IPv6 address (only Z:Z:Z:Z:Z:Z:Z:Z is supported by the time) in a <route> gw";
         } 
      }
      else {
         return "$route_type is not a valid <route> type";
      }

   }

   # 19. To check <bw>
   my $bw_list = $doc->getElementsByTagName("bw");
   for ( my $i = 0; $i < $bw_list->getLength; $i++ ) {
      my $bw = &text_tag($bw_list->item($i));
      return "<bw> value $bw is not a valid integer number" unless ($bw =~ /^\d+$/);
   }
   
   # 20. To check uniqueness of <console> id attribute in the same scope
   # (<vm_defaults>) or <vm>
   my $vm_defaults_list = $doc->getElementsByTagName("vm_defaults");
   if ($vm_defaults_list->getLength == 1) {
   	   my $console_list = $vm_defaults_list->item(0)->getElementsByTagName("console");
   	   my %console_ids;
   	   for (my $i = 0; $i < $console_list->getLength; $i++) {
   	   	   my $id = $console_list->item($i)->getAttribute("id");
   	   	   if (exists $console_ids{$id} && $console_ids{$id} == 1) {
   	   	      return "console id $id duplicated in <vm_defaults>";
   	   	   }
   	   	   else {
   	   	      $console_ids{$id} = 1;
   	   	   }
   	   }
   }
   my $vm_list = $doc->getElementsByTagName("vm");
   for (my $i = 0 ; $i < $vm_list->getLength; $i++) {
   	   my $name = $vm_list->item($i)->getAttribute("name");
   	   my $console_list = $vm_list->item($i)->getElementsByTagName("console");
   	   my %console_ids;
   	   for (my $j = 0; $j < $console_list->getLength; $j++) {
   	   	   my $id = $console_list->item($j)->getAttribute("id");
   	   	   if (exists $console_ids{$id} && $console_ids{$id} == 1) {
   	   	      return "console id $id duplicated in virtual machine $name";
   	   	   }
   	   	   else {
   	   	      $console_ids{$id} = 1;
   	   	   }
   	   }
   }

   # 21. To check all the <exec> and <filetree> with the same seq attribute 
   # has also the same user attribute
   $vm_list = $doc->getElementsByTagName("vm");
   for (my $i = 0 ; $i < $vm_list->getLength; $i++) {
   	   my $name = $vm_list->item($i)->getAttribute("name");
   	   my %seq_users;
   	   
   	   # Checks for <exec>
   	   my $exec_list = $vm_list->item($i)->getElementsByTagName("exec");
   	   for (my $j = 0; $j < $exec_list->getLength; $j++) {
   	   	   my $seq = $exec_list->item($j)->getAttribute("seq");
   	   	   my $user = $exec_list->item($j)->getAttribute("user");

   	   	   if (defined($seq_users{$seq})) {
   	   	      if ($seq_users{$seq} ne $user) {
   	   	         return "all tags (<exec> and <filetree>) in the command sequence '$seq' must has the same user in virtual machine $name";
   	   	      }
   	   	   }
   	   	   else {
   	   	      $seq_users{$seq} = $user;
   	   	   }
   	   }

   	   # Checks for <filetree>  	   
   	   my $filetree_list = $vm_list->item($i)->getElementsByTagName("filetree");
   	   for (my $j = 0; $j < $filetree_list->getLength; $j++) {
   	   	   my $seq = $filetree_list->item($j)->getAttribute("seq");
   	   	   my $user = $filetree_list->item($j)->getAttribute("user");

   	   	   if (defined($seq_users{$seq})) {
   	   	      if ($seq_users{$seq} ne $user) {
   	   	         return "all tags (<exec> and <filetree>) using command sequence '$seq' must has the same user in virtual machine $name";
   	   	      }
   	   	   }
   	   	   else {
   	   	      $seq_users{$seq} = $user;
   	   	   }
   	   }   	   
   }
   
   # 22. To check user attribute is not used in <ecex> within <host>
   my $host_list = $doc->getElementsByTagName("host");
   if ($host_list->getLength > 0) {
      my $exec_list = $host_list->item(0)->getElementsByTagName("exec");
      for (my $i = 0; $i < $exec_list->getLength; $i++) {
      	 my $seq = $exec_list->item($i)->getAttribute("seq");
         if ($exec_list->item($i)->getAttribute("user") ne "") {
            return "the use of user attribute in <exec> is forbidden within <host> in command sequence '$seq'";
         }
      }
   }

	# 23. To check that <mem> tag is specified in Megabytes or Gigabytes
	my $mem_list = $doc->getElementsByTagName("mem");
	for (my $j = 0; $j < $mem_list->getLength; $j++) {
      	my $mem = &text_tag($mem_list->item($j));
		if ( $mem !~ /[MG]$/ ) {
			return "<mem> tag sintax error ($mem); memory values must end with 'M' or 'G'";
		}
	}

	# DYNAMIPS checks

	# - check that dynamips_ext only appears <=1 times
   my $dynext_list = $doc->getElementsByTagName("dynamips_ext");
   if ($dynext_list->getLength > 1) {
			return "duplicated <dynamips_ext> tag. Only one allowed";
   }
   
   
   	# - check the correctness of dynamips interface names (e0/0, s0/1, fa0/2, etc)
   	# - check that if a dynamips vm has an if which is a serial line interface (e.g s1/0) connected to a net:
   	#         - the net has exactly two interfaces connected
   	#         - the net type is ppp
   	#         - the other end is a dynamips router and the interface connected is also a serial line
	# Virtual machines loop
	$vm_list = $doc->getElementsByTagName ("vm");
	for (my $i = 0; $i < $vm_list->getLength; $i++) {

	    my $vm = $vm_list->item ($i);
	    my $name = $vm->getAttribute ("name");
	    my $type = $vm->getAttribute ("type");
		if ( $type eq 'dynamips') {
			# Network interfaces loop
	        my $if_list = $vm->getElementsByTagName ("if");
	        for (my $j = 0; $j < $if_list->getLength; $j++) {
	            my $if = $if_list->item ($j);
	            my $id = $if->getAttribute ("id");
	            my $net = $if->getAttribute ("net");
	            my $ifName = $if->getAttribute ("name");
				# Check if name attribute exists
	            if (!$ifName) {
					return "missing dynamips interface name (id=$id, vm=$name)";
	            }
	            # Check $ifName correctness
           		if ($ifName !~ /[sefgSEFG].*[0-9]\/[0-9]/ ) {
					return "incorrect dynamips interface name (id=$id, name=$ifName, vm=$name)";
           		}
	            # 
	            if ($ifName =~ /[sS].*/) { 
	            	# Interface is a serial line (e.g. s1/0)
					# No need to check that length of @vms == 2; already done in 8g
					# Check that if is connected to a ppp <net>
					if ($dh->get_net_type($net) ne 'ppp') {
						return "serial line dynamips interface $ifName of $name must be connected to a <net> of type 'ppp'.";
					}	            	
					# Get ifs connected to that <net>
	            	my ($vms,$ifs) = $dh->get_vms_in_a_net ($net);
	            	#foreach $vm (@$vms) { print "********* vm= " . $vm->getAttribute ("name") . "\n"}
	            	#foreach $if (@$ifs) { print "********* if= " . $if->getAttribute ("name") . "\n"}
	        		for (my $i = 0; $i < scalar @$vms; $i++) {
	            		if (@$vms[$i]->getAttribute ("type") ne 'dynamips') {
							return "all interfaces connected to <net> $net must be dynamips serial lines (" . 
							        @$vms[$i]->getAttribute ("name") . " is not of type dynamips)";
	            		}
	            		if (@$ifs[$i]->getAttribute ("name") !~ /[sS].*/) {
							return "all interfaces connected to <net> $net must be dynamips serial lines (" .
							        @$ifs[$i]->getAttribute ("name") . " of " . @$vms[$i]->getAttribute ("name") . 
							        " is not a serial line)";
	            		}
	        		}
	            }
	        }
		}
	}

   return 0;

}

#
# hostip_exists
#
# Parameters:
#  - ip address
#  - mask
#
# returns true if an interface on the host machine
# is configured with the provided IP address and mask
#
sub hostip_exists {
	my $hostip = shift;
	my $hostmask = shift;
	my $ip = NetAddr::IP->new($hostip,$hostmask);

	my $found_address = 0;
	my $pipe_cmd = "ifconfig|";
	open (my $pipe, $pipe_cmd);
	while (<$pipe>) {
		if (/addr:(\d+\.\d+\.\d+\.\d+).+Mask:(\d+\.\d+\.\d+\.\d+)/) {
			my $ifip = NetAddr::IP->new($1,$2);
			if ($ifip == $ip) {
				$found_address = 1;
				last;
			}
		}
	}
	close($pipe);
	return $found_address;
}

1;
