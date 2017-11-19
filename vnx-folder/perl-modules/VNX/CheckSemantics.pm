# CheckSemantics.pm
#
# This file is a module part of VNX package.
#
# Authors: Fermin Galan Marquez (galan@dit.upm.es), David Fernandez (david@dit.upm.es)
# Copyright (C) 2005-2016 DIT-UPM
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

use strict;
use warnings;
use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(
	validate_xml
	check_doc
	);

use NetAddr::IP;
use Net::Pcap;
use VNX::Globals;
use VNX::FileChecks;
use VNX::IPChecks;
use VNX::NetChecks;
use VNX::TextManipulation;
use XML::LibXML;
use VNX::vmAPICommon;
use VNX::Execution;
use VNX::DocumentChecks;
use Cwd qw(abs_path);


# 
# validate_xml
# 
#   Checks the existence of an XML file and validates it against the XSD .
#
# Arguments:
#   xmlFile: the XML file to be validated
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

	if ( $@ ) {
		return $@;
	} else {
        return;
	}
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
#   - 9a. there is not duplicated vm names (<vm>)
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
#   - <vm> and <net> names max of $MAX_NAME_LENGTH characters
#   - <vm> and <net> 'name' attribute and does not have any whitespace
# 
#   - Check that files specified in <conf> tag exist and are readable

# The functions returns error string describing problem or 1 if all is right
#

# TODO:
# - check that forwarding only appears <=1 times
# - check execution mode:
#       - Olive: only mode="sdisk" allowed
#       - Dynamips: only mode="telnet" allowed
#                   type="file" only allowed with ostype="show|set"
# - dynamips: if management network is defined, then the name of the mgmt if has to be defined with:
#                    <if id="0" net="vm_mgmt" name="e0/0">
#             this <if> should not have address associated
# - dynamips: check that the names of interfaces are not repeated
# # - cmd-seq: check that command sequence tags are unique and they are not used in exec or filetree seq values 


sub check_doc {
	
	my $MAX_NAME_LENGTH = 12;
	
	# Get arguments
	my $bp = shift;
	my $uid = shift;
	
	#
	# To check that a tag occurs 0 or 1 times
	#
	sub check_tag_occurs_once_at_most {
		
		my $node = shift;
		my $tag  = shift;

        my @aux = $node->findnodes($tag);
        if ( @aux > 1 ) {
        	my $section_msg;
        	if ($node->nodeName() eq 'global') {
        		$section_msg = "<global> section";
        	} elsif ($node->nodeName() eq 'vm') {
                $section_msg = "<vm name='" . $node->getAttribute('name') .  "'> definition";        		
        	}
        	return "more than one <$tag> tag defined in $section_msg" 
        } else { 
        	return 
        }	
		
	}
	
	
	my $doc = $dh->get_doc;
	my @vm_ordered = $dh->get_vm_ordered;

	my $is_root = $> == 0 ? 1 : 0;
	my $uid_name = $is_root ? getpwuid($uid) : getpwuid($>);
    
    # Check the number a times (minOccurs, maxOccurs) a tag can appear in <global> tag
    # It has to be done manually: it is not checked by the XSD after having changed
    # the list of VM elements from xs:sequence to xs:choice         
    #
    my @aux = $doc->findnodes('vnx/global');
    if ( @aux > 1 ) { return "more than one <global> tag defined" }
    elsif ( @aux == 1 ) {
    	my $global = $aux[0];
        if ( $_ = check_tag_occurs_once_at_most ($global, 'version') )       { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($global, 'scenario_name') ) { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($global, 'ssh_version') ) { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($global, 'automac') ) { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($global, 'netconfig') ) { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($global, 'vm_mgmt') ) { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($global, 'tun_device') ) { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($global, 'vm_defaults') ) { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($global, 'vnx_cfg') ) { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($global, 'dynamips_ext') ) { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($global, 'olive_ext') ) { return $_ };       	    
    }
    
    # 1b. <scenario_name> content does not have any whitespace
    return "simulaton name \"".$dh->get_scename."\" can not containt whitespaces"
      if ($dh->get_scename =~ /\s/);
    
	# 2. Check ssh_version
    return $dh->get_ssh_version . " is not a valid ssh version"
		unless ($dh->get_ssh_version eq '1' || $dh->get_ssh_version eq '2');

    # 3. To check <ssh_key>
    foreach my $ssh_key ($doc->getElementsByTagName("ssh_key")) {
	   my $ssh_key = &do_path_expansion(text_tag($ssh_key));
	   return "$ssh_key is not a valid absolute filename" unless &valid_absolute_filename($ssh_key);
	   unless (-r $ssh_key) {
root();
	       if (-r $ssh_key) {
                return "$ssh_key (ssh key file) does not exist or is not readable" unless (-r $ssh_key);
	       }	
user();
	   }
    }

    # 4. To check <shell>
    foreach my $shell ($doc->getElementsByTagName("shell")) {
        my $shell = &do_path_expansion(text_tag($shell));
        return "$shell (shell) is not a valid absolute filename" unless &valid_absolute_filename($shell);
    }

    # 5. To check <tun_device>
    #my $tun_device_list = $doc->getElementsByTagName("tun_device");
    #if ($tun_device_list->getLength != 0) {
    #   my $tun_device = text_tag($tun_device_list->item(0));
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
    foreach my $basedir ($doc->getElementsByTagName("basedir")) {
        my $basedir = &do_path_expansion(text_tag($basedir));
        return $basedir . " (basedir) is not a valid absolute directory name" 
            unless &valid_absolute_directoryname($basedir);
        return $basedir . " (basedir) does not exist or is not readable (user $uid_name)"
            unless (-d $basedir);
    }   

	# 7. To check <vm_mgmt>
	
	# 7a. Valid network, mask and offset
	if ($dh->get_vmmgmt_type ne 'none') {
		return "<vm_mgmt> network attribute \"".$dh->get_vmmgmt_net."\" is invalid"
			unless (valid_ipv4($dh->get_vmmgmt_net));
		return "<vm_mgmt> mask attribute \"".$dh->get_vmmgmt_mask."\" is invalid (must be between 8 and 30)"
			unless ($dh->get_vmmgmt_mask =~ /^\d+$/ && $dh->get_vmmgmt_mask >= 8 && $dh->get_vmmgmt_mask <= 30);
		return "<vm_mgmt> offset attribute ".$dh->get_vmmgmt_offset." is too large for mask ".$dh->get_vmmgmt_mask
			if ($dh->get_vmmgmt_mask !~ /^\d+$/ || $dh->get_vmmgmt_offset > (1 << (32 - $dh->get_vmmgmt_mask)) - 3);
	}
	if ($dh->get_vmmgmt_type eq 'private') {
		return "<vm_mgmt> offset attribute must be a multiple of 4 for private management" if ($dh->get_vmmgmt_offset % 4 != 0);
	}
	my @vmmgmt_list = $doc->getElementsByTagName("vm_mgmt");
	my @vmmgmt_net_list;
	my $vmmgmt_net_list_len = 0;
	my @vmmgmt_hostmap_list;
	# DFC 31/3/2011: <vm_mgmt> made compulsory to simplify 
	if (@vmmgmt_list == 0) {
		return "<vm_mgmt> tag missing"
	} elsif (@vmmgmt_list == 1) {
		@vmmgmt_net_list = $vmmgmt_list[0]->getElementsByTagName("mgmt_net");
		$vmmgmt_net_list_len = @vmmgmt_net_list;
		@vmmgmt_hostmap_list = $vmmgmt_list[0]->getElementsByTagName("host_mapping");
	} else {
		return "tag <vm_mgmt> duplicated"
	}
	
    # 7b. exactly one <mgmt_net> child for the <vm_mgmt> tag if and only if
    # <vm_mgmt> tag has attribute type "net".	
	if ($dh->get_vmmgmt_type eq 'net') {
		return "<vm_mgmt> element of type=\"net\" must have exactly one <mgmt_net> child element"
		  if ($vmmgmt_net_list_len != 1);
        my $config = str($vmmgmt_net_list[0]->getAttribute("config"));
        if ( ($config eq 'dhcp') && (@vmmgmt_hostmap_list > 0) ) {
            return "<host_mapping/> and <mgmt_net config='dhcp'> are not compatible. Use config='manual' to allow <host_mapping/> option"
        }

=BEGIN
        my $sock = $vmmgmt_net_list[0]->getAttribute("sock");
        unless (empty($sock)) {
	        my $sock = &do_path_expansion($sock);
	        # The sock file checking is avoided when autoconfigure attribute is in use
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
        }
=END
=cut        
        

	} else {
		return "<vm_mgmt> may only have a <mgmt_net> child if attribute type=\"net\"" if ($vmmgmt_net_list_len > 0);
	}
	return "<vm_mgmt> may not have a <host_mapping> child if attribute type=\"none\""
		if (@vmmgmt_hostmap_list > 0 && $dh->get_vmmgmt_type eq 'none');

    # 8. To check <net>
    # Hash for duplicated names detection
    my %net_names;
    # Hash for duplicated bridge MAC address detection
    my %mac_addrs;
   
    # Hash for duplicated physical interface detection
    my %phyif_names;

    # Process <net> list
    foreach my $net ($doc->getElementsByTagName("net")) {

        # To get name, type and mode attribute
        my $name = $net->getAttribute("name");
        my $type = $net->getAttribute("type");
        my $mode = $net->getAttribute("mode");
      
        # To check name length
        my $upper = $MAX_NAME_LENGTH + 1;
        return "net name $name is too long: max $MAX_NAME_LENGTH characters"
            if ($name =~ /^.{$upper,}$/);
         
        # To check name has no whitespace
        return "net name \"$name\" can not containt whitespaces"
            if ($name =~ /\s/);

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
        if (defined($capture_expression)) {
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

        my $umlswitch_binary = $net->getAttribute("uml_switch_binary");

        #8e. uml_switches are valid, readable and executable filenames
        #if ($umlswitch_binary !~ /^$/) {
        unless (empty($umlswitch_binary)) {
            my $umlswitch_binary = &do_path_expansion($umlswitch_binary);
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
        #unless ($external_if =~ /^$/) {
        unless (empty($external_if)) {
            #print $bp->{"ifconfig"} . " $external_if &> /dev/null\n";
	    
		    # DFC (30/3/2011): only check the interface existance not the subinterface 
		    # (we eliminate the .XXX from the interface name) 
			my $external_base_if = $external_if;
			$external_base_if =~ s/\..*//;
		    if (system($bp->{"ifconfig"} . " $external_base_if > /dev/null 2>&1")) {
		      return "in network $name, $external_base_if does not exist";
		    } 
		    # Check the VLAN attribute (to compose the physical name, for 
		    # duplication checking)
		    my $vlan = $net->getAttribute("vlan");
		    my $phy_name;
            #unless ($vlan =~ /^$/) {
            unless (empty($vlan)) {
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
      if (empty($type)) {
      	 $type = "lan"; # default value
      	 $net->setAttribute("type", "lan")
      }
      if ($type eq "ppp" || $type eq "p2p") {
         # Get all the ifs of the scenario
         my $machines = 0;
         foreach my $if ($doc->getElementsByTagName("if")) {
            if ($if->getAttribute("net") eq $name) {
                $machines++;
         		last if ($machines > 3);
         	}
         }
         # Eliminated. It caused problems when using EDIV
         return "net $name of type $type is connected to just one interface: ppp/p2p networks must be connected to exactly two interfaces" if ($machines < 2);
         return "net $name of type $type is connected to more than two interface: ppp/p2p networks must be connected to exactly two interfaces"if ($machines > 2);         
      } elsif ($type eq "lan") {
         #8h. To check no-PPP networks doesn't have <bw> tag
         my @bw_list = $net->getElementsByTagName("bw");
         return "net $name is not a PPP network and only PPP networks can have a <bw> tag" if (@bw_list != 0)
      }
#      else {
         # DFC 3/5/11: relaxed to allow PPP links in dynamips withouth <bw> tag
         #8h. To check PPP networks has <bw> tag
         #my $bw_list = $net->getElementsByTagName("bw");
         #return "net $name is a PPP network and PPP networks must have a <bw> tag" if ($bw_list->getLength == 0)
#      }

        # Check related to <net mode='veth' type 'p2p'..:>
        if ($mode eq 'veth' && $type ne 'p2p') {
        	return "type $type incorrect for net $name. Type must be 'p2p' for nets of type 'veth'"
        }

        if ($type eq 'p2p' && $mode ne 'veth') {
            return "error in net $name, type $type only supported for mode 'veth'"
        }    

        # 8i. Check sock files
        my $sock = $net->getAttribute("sock");
        #if ($sock !~ /^$/) {
        unless (empty($sock)) {
            my $sock = &do_path_expansion($sock);
            $> = $uid if ($is_root);
            return "$sock (sock) does not exist or is not readable (user $uid_name)" unless (-r $sock);
            return "$sock (sock) is not writeable (user $uid_name)" unless (-w _);
            return "$sock (sock) is not a valid socket" unless (-S _);
            $> = 0 if ($is_root);
        }
	  
        # 8j. Check 'controller' and 'of_version' attributes 
        my $controller = $net->getAttribute("controller");
        my $of_version = $net->getAttribute("of_version");
      
        if ( !empty($controller) && $mode ne 'openvswitch' ) {
            return "'controller' attribute can only be used in 'openvswitch' based networks (used in <net name='$name'>)"
        }
        if ( !empty($of_version) && $mode ne 'openvswitch' ) {
            return "'of_version' attribute can only be used in 'openvswitch' based networks (used in <net name='$name'>)"
        } 
        if ( !empty($of_version) && $of_version ne 'OpenFlow10' && $of_version ne 'OpenFlow12' && $of_version ne 'OpenFlow13' ) {
            return "incorrect value in <net> 'of_version' attribute. Valid values: OpenFlow10, OpenFlow12, OpenFlow13"
        } 
      
        # 8k. Check 'hwaddr' attributes 
        my $hwaddr = $net->getAttribute("hwaddr");
        if ( !empty($hwaddr) && $mode eq 'openvswitch' ) {
            return "incorrect MAC address ($hwaddr) specified in attribute 'hwaddr' of net '$name'" 
                unless ( $hwaddr =~ /^([0-9a-fA-F]{2}:){5}([0-9a-fA-F]{2})$/ );
        }        
        if ( !empty($hwaddr) && $mode ne 'openvswitch' ) {
            return "incorrect use of attribute 'hwaddr' in net '$name' of mode '$mode'\n'hwaddr' can only be used when mode='openvswitch'" 
        }     
        if ( defined($hwaddr) ) {
            if ( defined($mac_addrs{$hwaddr}) ) {
                return "duplicated MAC address ($hwaddr) specified in nets '$name' and '$mac_addrs{$hwaddr}'";
            } else {
                $mac_addrs{$hwaddr} = $name;
            }       	
        }

        # 8l. Check 'fail_mode' attributes 
        my $fail_mode = $net->getAttribute("fail_mode");
        if ( !empty($fail_mode) && $mode eq 'openvswitch' ) {
            return "incorrect value ($fail_mode) for 'fail_mode' attribute of net '$name'. Correct values: secure|standalone" 
                unless ( $fail_mode eq 'secure' || $fail_mode eq 'standalone' );
        }
        if ( !empty($hwaddr) && $mode ne 'openvswitch' ) {
            return "incorrect use of attribute 'fail_mode' in net '$name' of mode '$mode'\n'fail_mode' can only be used when mode='openvswitch'" 
        }     
      
        # 8m. Check <connection> tags
        foreach my $connection ($net->getElementsByTagName("connection")) {
            my $net_to_connect=$connection->getAttribute("net");
            my $if_name=$connection->getAttribute("name");
            my $conn_type=$connection->getAttribute("type");
            # Set default value
            unless ( defined($conn_type) ) {
                $conn_type = 'veth'; 
                $connection->setAttribute('type', $conn_type);
            }
            unless ($conn_type eq 'veth' or $conn_type eq 'ovs-patch') {
                return "incorrect value ($conn_type) for 'type' attribute in <connection> tag of <net name='$name'>";
            }
            if ( $name eq $net_to_connect ) {
                return "incorrect <connection> tag in <net name='$name'>; switch loop detected";
            }
        }
       
        # 8n. Check <net stp=...> attribute
        if(my $stp = $net->getAttribute("stp") ){
            if ( $stp ne 'on' && $stp ne 'off') {
                return "incorrect value ($stp) for 'stp' attribute in <net name=\"$name\"> tag";
            }      
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
      my $upper = $MAX_NAME_LENGTH + 1;
      return "vm name $name is too long: max $MAX_NAME_LENGTH characters"
         if ($name =~ /^.{$upper,}$/);

      # To check name has no whitespace
      return "vm name \"$name\" can not containt whitespaces"
      	if ($name =~ /\s/);

      # Calculate the efective basedir (lately used for <filetree> checkings)
      my $effective_basedir = $dh->get_default_basedir;
      my @basedir_list = $vm->getElementsByTagName("basedir");
      if (@basedir_list == 1) {
         $effective_basedir = text_tag($basedir_list[0]);
      }

        # 9a. To check if the same name has been seen before
        if (defined($vm_names{$name})) {
            return "duplicated vm name: $name";
        }
        else {
            $vm_names{$name} = 1;
        }

        # Check the number a times (minOccurs, maxOccurs) a tag can appear
        # It has to be done manually: it is not checked by the XSD after having changed
        # the list of VM elements from xs:sequence to xs:choice         
        #
        if ( $_ = check_tag_occurs_once_at_most ($vm, 'filesystem') ) { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($vm, 'mem') )        { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($vm, 'video') )      { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($vm, 'kernel') )     { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($vm, 'conf') )       { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($vm, 'shell') )      { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($vm, 'basedir') )    { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($vm, 'mng_if') )     { return $_ };       
        if ( $_ = check_tag_occurs_once_at_most ($vm, 'on_boot') )    { return $_ };       

        # Hash for duplicated ids detection
        my %if_ids_eth;
        my %if_ids_lo;

        foreach my $if ($vm->getElementsByTagName("if")) {
            #my $if = $if_list->item($j);

            # To get id attribute
            my $id = $if->getAttribute("id");
         
            # To get net attribute
            my $net = $if->getAttribute("net");

            # To check <mng_if>
            my $mng_if_value = $dh->get_default_mng_if;
            my @mng_if_list = $vm->getElementsByTagName("mng_if");
            if (@mng_if_list == 1) {
                $mng_if_value = text_tag($mng_if_list[0]);
            }

            # 9b. To check id 0 is not used
            # DFC 5/5/2011: relaxed to allow define the mngt if name in dynamips routers
            # return "if id 0 in vm $name is not allowed while vm management is enabled unless <mng_if> is used"
            #   if (($id == 0) && $dh->get_vmmgmt_type ne 'none' && ($mng_if_value ne "no"));

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
            unless (($net eq "lo") || ($net eq "vm_mgmt") || (defined($net_names{$net}))) {
                return "net $net defined for interface $id of virtual machine $name is not valid: it must be defined in a <net> tag (or use \"lo\")";
            }
         
            # 9e. <mac> can not be put within <if net="lo">
            if ($net eq "lo") {
                my @mac_list = $if->getElementsByTagName("mac");
                if (@mac_list != 0) {
                    return "<if net=\"lo\"> can not nests <mac> tag";
                }
            } 
            # 9f. check that uml_switch is only used with uml vms, that is, an interface
            #     of a libvirt or dynamips machine cannot be connected to a uml_switch
            #for ( my $i = 0; $i < $net_list->getLength; $i++ ) {
            foreach my $net_def ($doc->getElementsByTagName("net")) {
                #my $net_def = $net_list->item($i);
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
	  foreach my $user ($vm->getElementsByTagName("user")) {
		 my $username = $user->getAttribute("username");
		 my $effective_group = $user->getAttribute("group");
		 return "Invalid username $username"
			 unless ($username =~ /[A-Za-z0-9_]+/);
		 my %user_groups;
		 foreach my $group ($user->getElementsByTagName("group")) {
			my $group = text_tag($group);
			$user_groups{$group} = 1;
			return "Invalid group $group for user $username"
				unless ($group =~ /[A-Za-z0-9_]+/);
		 }
         return "Effective group " . $effective_group . " does not exist as a <group> tag for user $username"
             unless ($user_groups{$effective_group} eq '' || $user_groups{$effective_group});
	  }

        #11. To check <filetree>
        foreach my $ftree ($vm->getElementsByTagName("filetree")) {      	
            my $filetree = text_tag($ftree);
            my $root = $ftree->getAttribute("root");
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
            # Changed to allow individual files in filetrees
            if (-d $filetree_effective) { # It is a directory
                return "$filetree_effective (filetree) directory is not readable/executable (user $uid_name)"
                unless (-r $filetree_effective && -x _);
            } elsif (-f $filetree_effective) { # It is a file
                return "$filetree_effective (filetree) file is not readable (user $uid_name)"
                unless (-r $filetree_effective);
            } else {
                return "$filetree (filetree) is not a valid file or directory"
            }

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
        # vm arch attribute is only allowed for libvirt VMs and lxc
        my $vm_arch = $vm->getAttribute("arch");               
        #if ($vm_arch ne '') { # A value for arch is specified
        unless (empty($vm_arch)) { # A value for arch is specified

            if ($vm_type eq "libvirt" || $vm_type eq "lxc") {
                if ( ($vm_arch ne 'i686') && ($vm_arch ne 'x86_64') ) {
                    return "invalid attribute value (arch='$vm_arch') in VM '$name'. Valid values: i686, x86_64";
                }        	
            } else {
                return "invalid attribute 'arch' in <vm name='$name'> tag. 'arch' only allowed for libvirt virtual machines";
            }
        } else { # arch not specified

            if ($vm_type eq "libvirt") {
                # set default value to i686
                $vm->setAttribute( 'arch', "i686" );
            }
        }
      
        # vm vcpu attribute only allowed (by now) for libvirt VMs and LXC
        my $vm_vcpu = $vm->getAttribute("vcpu");               
        unless (empty($vm_vcpu)) { # A value for vcpu is specified

            if ($vm_type eq "libvirt") {
                if ( ($vm_vcpu < 1) ) {
                    return "Number of virtual CPUs ($vm_vcpu) specified in vcpu option of VM '$name' must be >=1";
                }           
            } elsif ($vm_type eq "lxc") {
                # TODO: check that it is a comma separated list of cores           
            } else {
                return "invalid attribute 'vcpu' in <vm name='$name'> tag. 'vcpu' only allowed for libvirt or lxc virtual machines";
            }
        } else { # vcpu not specified

            if ($vm_type eq "libvirt") {
                # set default value to i686
                $vm->setAttribute( 'vcpu', 1 );
            }
        }

        # vm vcpu_quota attribute only allowed for  LXC
        my $vm_vcpu_quota = $vm->getAttribute("vcpu_quota");               
        unless (empty($vm_vcpu_quota)) { # A value for vcpu_quota has been specified

            if ($vm_type eq "lxc") {
            	if ( ! $vm_vcpu_quota =~ /1?[0-9]?[0-9]?%/) {
                #if ( ($vm_vcpu_quota < 0) || ($vm_vcpu_quota > 100) ) {
                    return "Incorrect virtual CPU quota atribute value ($vm_vcpu_quota) specified for VM '$name' (must be in the range [0-100])";
                }           
            } else {
                return "invalid attribute 'vcpu_quota' in <vm name='$name'> tag. 'vcpu' only allowed for libvirt or lxc virtual machines";
            }
        }
        
        # Check <shareddir> tags
        foreach my $shared_dir ($vm->getElementsByTagName("shareddir")) {
            my $root    = $shared_dir->getAttribute("root");
            my $options = $shared_dir->getAttribute("options");
            my $shared_dir_value = text_tag($shared_dir);
            if ( $root !~ /^\// ) {
            	return "root attribute value ('$root') in <shareddir> tag of VM '$name' must be an absolute path."
            }
            my $abs_shareddir = get_abs_path($shared_dir_value);
            if (! -d $abs_shareddir) {
                return "shared directory ($shared_dir_value) in <shareddir> tag of VM '$name' does not exist or is not accesible."
            }            
        }
        
    }

    #12. To check <filesystem>
    $> = $uid if ($is_root);
    
    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];
        my $name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");               
 
        if( $vm->exists("filesystem") ){
            my @fsystem = $vm->findnodes("filesystem");
            my $filesystem = get_abs_path($fsystem[0]->getFirstChild->getData);
            my $filesystem_type = str($fsystem[0]->getAttribute("type"));

            # 12a. <filesystem> are valid, readable/executable files
            if ($vm_type eq 'lxc') {
                return "LXC filesystem ($filesystem) does not point to a valid directory" unless (-d $filesystem);
            } elsif ( ($vm_type eq 'libvirt') || ($vm_type eq 'dynamips') || ($vm_type eq 'uml') ) {
                return "$vm_type filesystem ($filesystem) is a directory (it must be a file)" if (-d $filesystem);
                return "filesystem ($filesystem) does not exist or is not readable (user $uid_name)" unless (-r $filesystem);
                if ($filesystem_type eq "direct") {
                    return "filesystem ($filesystem) is not writeable (user $uid_name)" unless (-w $filesystem);
                }
            } 
        }
    }
    
    # Check that each filesystem used in direct mode is only used by one vm
    my %direct_fss = ();
    foreach my $fsystem ( $doc->findnodes("/vnx/vm/filesystem[\@type='direct']") ) {
        my $filesystem = get_abs_path($fsystem->getFirstChild->getData);
        if ( defined($direct_fss{$filesystem}) ) {
            return "filesystem ($filesystem) used in 'direct' mode in two or more VMs"
        } 
        $direct_fss{$filesystem} = 'yes';
    }    
    
=BEGIN    
    foreach my $fsystem ($doc->getElementsByTagName("filesystem")) {   	
        my $filesystem = &do_path_expansion(text_tag($fsystem));
        my $filesystem_type = str($fsystem->getAttribute("type"));
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
            $filesystem = get_abs_path ($filesystem);
            # return "$filesystem (filesystem) is not a valid absolute filename" unless &valid_absolute_filename($filesystem);
            return "$filesystem (filesystem) does not exist or is not readable (user $uid_name)" unless (-r $filesystem);
            if ($filesystem_type eq "direct") {
                return "$filesystem (filesystem) is not writeable (user $uid_name)" unless (-w $filesystem);
            }
        }
    }
=END
=cut

    # Check if <filesystem> tags inside <vm> include the 'type' attribute
    foreach my $fsystem ($doc->findnodes('vnx/vm/filesystem')) {    
        if ( ! defined($fsystem->getAttribute('type')) ) {
        	my $vm_name = $fsystem->parentNode()->getAttribute('name');
        	return "<filesystem> tag in VM '$vm_name' does not include compulsory 'type' attribute";
        }
    }


   #12c. To check default filesystem type is valid
   if ($dh->get_default_filesystem_type eq "direct" ||
      $dh->get_default_filesystem_type eq "hostfs") {
      return "default filesystem type " . $dh->get_default_filesystem_type . " is forbidden";
   }

   #13. To check <kernel>
   foreach my $kernel ($doc->getElementsByTagName("kernel")) {
      #my $kernel = $kernel_list->item(0);
      # 13a. <kernel> are valid, readable/executable files
      my $kernel_exe = &do_path_expansion(text_tag($kernel));
      return "$kernel_exe (kernel) is not a valid absolute filename" unless &valid_absolute_filename($kernel_exe);
      return "$kernel_exe (kernel) does not exist or is not readable/executable (user $uid_name)" unless (-r $kernel_exe && -x _);
      # 13b. initrd checking
      my $kernel_initrd = $kernel->getAttribute("initrd");
      #if ($kernel_initrd !~ /^$/) {
      unless (empty($kernel_initrd)) {
         $kernel_initrd = &do_path_expansion($kernel_initrd);
         return "$kernel_initrd (initrd) is not a valid absolute filename" unless &valid_absolute_filename($kernel_initrd);
         return "$kernel_initrd (initrd) does not exist or is not readable (user $uid_name)" unless (-r $kernel_initrd);
      }
      # 13c. modules checking
      my $kernel_modules = $kernel->getAttribute("modules");
	  #if ($kernel_modules !~ /^$/) {
      unless (empty($kernel_modules)) {	  	
         $kernel_modules = &do_path_expansion($kernel_modules);
         return "$kernel_modules (modules) is not a valid absolute directory" unless &valid_absolute_directoryname($kernel_modules);
         return "$kernel_modules (modules) does not exist or is not readable (user $uid_name)" unless (-d $kernel_modules);
         return "$kernel_modules (modules) is not readable/executable (user $uid_name)" unless (-r $kernel_modules && -x $kernel_modules);
      }      
   }
   $> = 0 if ($is_root);

    # 14. To check <hostif>
    foreach my $hostif ($doc->getElementsByTagName("hostif")) {
        #my $hostif = $hostif_list->item($i);

        # To get net attribute
        my $net = $hostif->getAttribute("net");

        # To check that there is a net with this name
        unless (defined($net_names{$net})) {
            return "hostif net $net is not valid: it must be defined in a <net> tag";
        }

    }

   # 15. To check <physicalif>
   # Hash for duplicated names detection
   my %phyif_names_ipv4;
   my %phyif_names_ipv6;

   # To get list of defined <net>
   foreach my $phyif ($doc->getElementsByTagName("physicalif")) {

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
         if (system($bp->{"ifconfig"} . " $name > /dev/null 2>&1")) {
	        return "physicalif $name does not exists";
         }         
         
         # To get ip attribute
         my $ip = $phyif->getAttribute("ip");
      
         # To check if valid IPv6 address
         unless (valid_ipv6_with_mask($ip)) {
            return "'$ip' is not a valid IPv6 address with mask (/64 for example) in a <physicalif> ip";
         }
         
         # To get gw attribute
         my $gw = $phyif->getAttribute("gw");
         
         # To check if valid IPv6 address
         # Note the empty gw is allowable. This attribute is #IMPLIED in DTD and
         # the physicalif_config in vnumlparser.pl deals rightfully with emtpy values
         #unless ($gw =~ /^$/ ) {
         unless (empty($gw)) {
            unless (valid_ipv6($gw)) {
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
         if (system($bp->{"ifconfig"} . " $name > /dev/null 2>&1")) {
	        return "physicalif $name does not exists";
         }

         # To get ip attribute
         my $ip = $phyif->getAttribute("ip");
      
         # To check if valid IPv4 address
         unless (valid_ipv4($ip)) {
            return "'$ip' is not a valid IPv4 address in a <physicalif> ip";
         }

         # To get mask attribute
         my $mask = $phyif->getAttribute("mask");
         $mask="255.255.255.0" if (empty($mask));

         # To check if valid IPv4 mask
         unless (valid_ipv4_mask($mask)) {
            return "'$mask' is not a valid IPv4 netmask in a <physicalif> mask attribute";
         }
         
         # To get gw attribute
         my $gw = $phyif->getAttribute("gw");
         
         # To check if valid IPv4 address
         # Note the empty gw is allowable. This attribute is #IMPLIED in DTD and
         # the physicalif_config in vnumlparser.pl deals rightfully with emtpy values
         #unless ($gw =~ /^$/ ) {
         unless (empty($gw)) {
            unless (valid_ipv4($gw)) {
               return "'$gw' is not a valid IPv4 address in a <physicalif> gw";
            }
         }
      }
   }

    # 16. To check IPv4 addresses
    foreach my $ipv4s ($doc->getElementsByTagName("ipv4")) {
        my $ipv4 = text_tag($ipv4s);
        if ($ipv4 =~ /^dhcp/) { 
            my @aux = split(',', $ipv4);
            if ( defined ($aux[1]) ) {
                unless (valid_ipv4($aux[1])) {
                    return "'$aux[1]' found in <ipv4> tag is not a valid IPv4 address (Z.Z.Z.Z).";
                }                
            }
        } else {
            my $mask = $ipv4s->getAttribute("mask");
            if (empty($mask)) {
                # Doesn't has mask attribute, mask would be implicit in address
                unless (valid_ipv4($ipv4) || valid_ipv4_with_mask($ipv4)) {
                    return "'$ipv4' is not a valid IPv4 address (Z.Z.Z.Z) or IPv4 address with implicit mask (Z.Z.Z.Z/M, M<=32) in a <ipv4>";
                }
            } else {
                unless (valid_ipv4_mask($mask)) {
                    return "'$mask' is not a valid IPv4 netmask in a <ipv4> mask attribute";
                }
                if (valid_ipv4_with_mask($ipv4)) {
                    return "mask attribute and implicit mask (Z.Z.Z.Z/M, M<=32) are not simultanelly allowed in <ipv4>";
                }
                unless (valid_ipv4($ipv4)) {
                    return "'$ipv4' is not a valid IPv4 address (Z.Z.Z.Z) in a <ipv4>";
                }
            }
        }
   }

   # 17. To check IPv6 addresses
   foreach my $ipv6s ($doc->getElementsByTagName("ipv6")) {
      my $ipv6 = text_tag($ipv6s);
      if ($ipv6 eq 'dhcp') { next }
      my $mask = $ipv6s->getAttribute("mask");      
      if (empty($mask)) {
         # Doesn't has mask attribute, mask would be implicit in address
         unless (valid_ipv6($ipv6) || valid_ipv6_with_mask($ipv6)) {
            return "'$ipv6' is not a valid IPv6 address (Z:Z:Z:Z:Z:Z:Z:Z) or IPv6 address with implicit mask (Z:Z:Z:Z:Z:Z:Z:Z/M, M<=128) in a <ipv6>";
         }
      }
      else {
         unless (valid_ipv6_mask($mask)) {
            return "'$mask' is not a valid IPv6 netmask in a <ipv6> mask attribute";
         }
         if (valid_ipv6_with_mask($ipv6)) {
            return "mask attribute and implicit mask (Z:Z:Z:Z:Z:Z:Z:Z/M, M<=129) are not simultanelly allowed in <ipv6>";
         }
         unless (valid_ipv6($ipv6)) {
            return "'$ipv6' is not a valid IPv4 address (Z:Z:Z:Z:Z:Z:Z:Z) in a <ipv6>";
         }
      }
      
   }

   # 18. To check addresses related with <route> tag
   foreach my $route ($doc->getElementsByTagName("route")) {
      my $route_dest = text_tag($route);
      my $route_gw = $route->getAttribute("gw");
      my $route_type = $route->getAttribute("type");
      if ($route_type eq "ipv4") {
         unless (($route_dest eq "default")||(valid_ipv4_with_mask($route_dest))) {
            return "'$route_dest' is not a valid IPv4 address with mask (Z.Z.Z.Z/M) in a <route>";
         }
         unless (valid_ipv4($route_gw)) {
            return "'$route_gw' is not a valid IPv4 address (Z.Z.Z.Z) for a <route> gw";
         }
      }
      elsif ($route_type eq "ipv6") {
         unless (($route_dest eq "default")||(valid_ipv6_with_mask($route_dest))) {
            return "'$route_dest' is not a valid IPv6 address with mask (only Z:Z:Z:Z:Z:Z:Z:Z/M is supported by the time) in a <route>";
         }
         unless (valid_ipv6($route_gw)) {
            return "'$route_gw' is not a valid IPv6 address (only Z:Z:Z:Z:Z:Z:Z:Z is supported by the time) in a <route> gw";
         } 
      }
      else {
         return "$route_type is not a valid <route> type";
      }

   }

   # 19. To check <bw>
   foreach my $bw_tag ($doc->getElementsByTagName("bw")) {
      my $bw = text_tag($bw_tag);
      return "<bw> value $bw is not a valid integer number" unless ($bw =~ /^\d+$/);
   }
   
    # 20. To check uniqueness of <console> id attribute in the same scope
    # (<vm_defaults>) or <vm>
    my @vm_defaults_list = $doc->getElementsByTagName("vm_defaults");
    if (@vm_defaults_list == 1) {
        my %console_ids;
        foreach my $console ($vm_defaults_list[0]->getElementsByTagName("console")) {
            my $id = $console->getAttribute("id");
            if (exists $console_ids{$id} && $console_ids{$id} == 1) {
                return "console id $id duplicated in <vm_defaults>";
            } else {
                $console_ids{$id} = 1;
            }
        }
    }
    if (@vm_defaults_list == 1) {
        foreach my $vm ($doc->getElementsByTagName("vm")) {
            my $name = $vm->getAttribute("name");
            my %console_ids;
            foreach my $console ($vm_defaults_list[0]->getElementsByTagName("console")) {
                my $id = $console->getAttribute("id");
                if (exists $console_ids{$id} && $console_ids{$id} == 1) {
                    return "console id $id duplicated in virtual machine $name";
                } else {
                    $console_ids{$id} = 1;
                }
            }
        }
    }

   # 21. To check all the <exec> and <filetree> with the same seq attribute 
   # has also the same user attribute
   # ELIMINATED
       
    foreach my $vm ($doc->getElementsByTagName("vm")) {
   	    my $name = $vm->getAttribute("name");
   	    my %seq_users;

        my $type = $vm->getAttribute("type");
   	    unless ($type eq 'uml') {
   	    	next;
   	    } 
        my $merged_type = $dh->get_vm_merged_type ($vm);
   	   
   	   # Checks for <exec>
   	   foreach my $exec ($vm->getElementsByTagName("exec")) {
   	   	   my $seq = $exec->getAttribute("seq");
   	   	   my $user = $exec->getAttribute("user");

   	   	   if (defined($seq_users{$seq})) {
   	   	      if ($seq_users{$seq} ne $user) {
   	   	         #return "all tags (<exec> and <filetree>) in the command sequence '$seq' must have the same user in virtual machine $name";
   	   	      }
   	   	   }
   	   	   else {
   	   	      $seq_users{$seq} = $user;
   	   	   }
   	   }

        # Checks for <filetree>  	   
        foreach my $filetree ($vm->getElementsByTagName("filetree")) { 
            my $seq = $filetree->getAttribute("seq");
            my $user = $filetree->getAttribute("user");

            if (defined($seq_users{$seq})) {
                if ($seq_users{$seq} ne $user) {
                    #return "all tags (<exec> and <filetree>) using command sequence '$seq' must have the same user in virtual machine $name";
                }
            }
            else {
                $seq_users{$seq} = $user;
            }
            # 21a. To check that attributes "group" and "perms" of <filetree>'s are only used in linux and FreeBSD VMs
            my $group = $filetree->getAttribute("group");
            my $perms = $filetree->getAttribute("perms");
            #wlog (VVV, "**** group=$group, perms=$perms, merged_type=$merged_type\n");
            return "group and perms attribute of <filetree> tag can only be used in Linux or FreeBSD virtual machines"
                #if ( ( $group ne '' || $perms ne '' ) && ( ( $merged_type ne 'libvirt-kvm-linux') 
                if ( ( !empty($group) || !empty($perms) ) && ( ( $merged_type ne 'libvirt-kvm-linux') 
                    && ( $merged_type ne 'libvirt-kvm-freebsd') 
                    && ( $merged_type ne 'libvirt-kvm-openbsd') 
                    && ( $merged_type ne 'libvirt-kvm-netbsd') 
                    && ( $merged_type ne 'uml')) ); 
        
   	   }   	   
   }
   
   # 22. To check user attribute is not used in <exec> within <host>
   my @host_list = $doc->getElementsByTagName("host");
   if (@host_list > 0) {
      foreach my $exec ($host_list[0]->getElementsByTagName("exec")) {
      	 my $seq = $exec->getAttribute("seq");
         unless (empty ($exec->getAttribute("user") ) ) {
            return "the use of user attribute in <exec> is forbidden within <host> in command sequence '$seq'";
         }
      }
   }

	# 23. To check that <mem> tag is specified in Megabytes or Gigabytes
	foreach my $mem_tag ($doc->getElementsByTagName("mem")) {
      	my $mem = text_tag($mem_tag);
		if ( $mem !~ /[MG]$/ ) {
			return "<mem> tag sintax error ($mem); memory values must end with 'M' or 'G'";
		}
	}

	# DYNAMIPS checks

	# - check that dynamips_ext only appears <=1 times
    my @dynext_list = $doc->getElementsByTagName("dynamips_ext");
    if (@dynext_list > 1) {
			return "duplicated <dynamips_ext> tag. Only one allowed";
   }
   
   
   	# - check the correctness of dynamips interface names (e0/0, s0/1, fa0/2, etc)
    # - check that interfaces names are unique
   	# - check that if a dynamips vm has an if which is a serial line interface (e.g s1/0) connected to a net:
   	#         - the net has exactly two interfaces connected
   	#         - the net type is ppp
   	#         - the other end is a dynamips router and the interface connected is also a serial line
	# Virtual machines loop
	foreach my $vm ($doc->getElementsByTagName ("vm")) {

	    my $name = $vm->getAttribute ("name");
	    my $type = $vm->getAttribute ("type");
		if ( $type eq 'dynamips') {
			# Network interfaces loop
            my %if_names;
	        foreach my $if ($vm->getElementsByTagName ("if")) {
	            my $id = $if->getAttribute ("id");
	            my $net = $if->getAttribute ("net");
	            my $ifName = $if->getAttribute ("name");
				# Check if name attribute exists
	            if (!$ifName) {
					return "missing dynamips interface name (id=$id, vm=$name)";
	            }
	            # Check if name uniqueness 
                if (exists $if_names{$ifName}) {
                    return "duplicated dynamips interface name (id=$id, if=$ifName, vm=$name)";
                } else {
                    $if_names{$ifName} = 1;
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


	# Check the vm names in -M option correspond to vms defined in the scenario or the host
	my $opt_M = $dh->{'vm_to_use'};
	if ($opt_M) {
		my @vms = split (/,/, $opt_M);
		foreach my $vmName (@vms) {
		   	my %vm_hash = $dh->get_vm_to_use;
		   	my $vmFound;
		   	if ($vmName eq 'host') {
                $vmFound = 'true';		   	    
		   	} else {
    		   	for ( my $i = 0; $i < @vm_ordered; $i++) {
    		      my $vm = $vm_ordered[$i];
    		      my $name = $vm->getAttribute("name");
    		      if ($vmName eq $name) { $vmFound = 'true'}
    		   	}
		   	}
		   	if (!$vmFound) {
		   		return "virtual machine $vmName specified in -M option does not exist"
		   	}
		}
	}
	
	# Check that files specified in <conf> tag exist and are readable
    foreach my $conf ($doc->getElementsByTagName("conf")) {
       $conf = get_abs_path (text_tag($conf));
       # <conf> are valid, readable/executable files
       return "$conf (conf) does not exist or is not readable/executable (user $uid_name)" unless (-r $conf);
    }
	       
 	# Check exec_mode attribute of <vm> and ostype attribute of <exec> mode in relation with the VM type and set default 
 	# values if not specified in the XML file
    # For each virtual machine 
    foreach my $vm ($doc->getElementsByTagName("vm")) {
        my $vmName = $vm->getAttribute("name");
        my $merged_type = $dh->get_vm_merged_type($vm);

        # Check exec_mode attribute of <vm>
        my $exec_mode = $vm->getAttribute("exec_mode");

        if (empty($exec_mode)) { # Set default value
               wlog (VV, "exec_mode not specified for vm $vmName. Using default: " . $dh->get_vm_exec_mode($vm), "check_doc>");
               $vm->setAttribute( 'exec_mode', $dh->get_vm_exec_mode($vm) );
        } else {
	        if ($merged_type eq 'uml') {
				if ( "@EXEC_MODES_UML" !~ $exec_mode )  { 
					return "incorrect value ($exec_mode) of exec_mode attribute in <vm> tag of vm $vmName"; }      
	        } elsif ($merged_type eq 'libvirt-kvm-linux') {
				if ( "@EXEC_MODES_LIBVIRT_KVM_LINUX" !~ $exec_mode )  {
					return "incorrect value ($exec_mode) of exec_mode attribute in <vm> tag of vm $vmName"; }      
			} elsif ($merged_type eq 'libvirt-kvm-freebsd') {
				if ( "@EXEC_MODES_LIBVIRT_KVM_FREEBSD" !~ $exec_mode )  {
					return "incorrect value ($exec_mode) of exec_mode attribute in <vm> tag of vm $vmName"; }      
		} elsif ($merged_type eq 'libvirt-kvm-openbsd') {
				if ( "@EXEC_MODES_LIBVIRT_KVM_OPENBSD" !~ $exec_mode )  {
					return "incorrect value ($exec_mode) of exec_mode attribute in <vm> tag of vm $vmName"; }      
	        } elsif ($merged_type eq 'libvirt-kvm-windows') {
				if ( "@EXEC_MODES_LIBVIRT_KVM_WINDOWS" !~ $exec_mode )  {
					return "incorrect value ($exec_mode) of exec_mode attribute in <vm> tag of vm $vmName"; }      
	        } elsif ($merged_type eq 'libvirt-kvm-olive') {
				if ( "@EXEC_MODES_LIBVIRT_KVM_OLIVE" !~ $exec_mode )  {
					return "incorrect value ($exec_mode) of exec_mode attribute in <vm> tag of vm $vmName"; }      
	        } elsif ( ($merged_type eq 'dynamips-3600') or ($merged_type eq 'dynamips-7200') )  {
				if ( "@EXEC_MODES_DYNAMIPS" !~ $exec_mode )  {
					return "incorrect value ($exec_mode) of exec_mode attribute in <vm> tag of vm $vmName"; }      
            } elsif ($merged_type eq 'libvirt-kvm-wanos') {
                if ( "@EXEC_MODES_LIBVIRT_KVM_WANOS" !~ $exec_mode )  {
                    return "incorrect value ($exec_mode) of exec_mode attribute in <vm> tag of vm $vmName"; }      
	        }
        } 

        # For each <exec> in the vm
        foreach my $cmd ($vm->getElementsByTagName("exec")) {
            my $cmdMode = $cmd->getAttribute("mode"); # mode attribute eliminated from <exec>
            my $cmdOSType = $cmd->getAttribute("ostype");
            #wlog (VVV, "-- vm=$vmName,type=$merged_type, exec_mode=$cmdMode, exec_ostype=$cmdOSType\n");

            if ($merged_type eq 'uml') {
            	if (empty($cmdOSType)) { # Set default value 
            		$cmd->setAttribute( 'ostype', "$EXEC_OSTYPE_UML[0]" );
            	} elsif ( "@EXEC_OSTYPE_UML" !~ $cmdOSType )  {
       				return "incorrect ostype ($cmdOSType) in <exec> tag of vm $vmName (" . $cmd->toString . ")"; }     	

            } elsif ($merged_type eq 'libvirt-kvm-linux') {
            	if (empty($cmdOSType)) { # Set default value 
            		$cmd->setAttribute( 'ostype', "$EXEC_OSTYPE_LIBVIRT_KVM_LINUX[0]" );
            	} elsif ( "@EXEC_OSTYPE_LIBVIRT_KVM_LINUX" !~ $cmdOSType )  {
       				return "incorrect ostype ($cmdOSType) in <exec> tag of vm $vmName (" . $cmd->toString . ")"; }

            } elsif ($merged_type eq 'libvirt-kvm-freebsd') {
                if (empty($cmdOSType)) { # Set default value 
                    $cmd->setAttribute( 'ostype', "$EXEC_OSTYPE_LIBVIRT_KVM_FREEBSD[0]" );
                } elsif ( "@EXEC_OSTYPE_LIBVIRT_KVM_FREEBSD" !~ $cmdOSType )  {
                    return "incorrect ostype ($cmdOSType) in <exec> tag of vm $vmName (" . $cmd->toString . ")"; }

            } elsif ($merged_type eq 'libvirt-kvm-openbsd') {
                if (empty($cmdOSType)) { # Set default value 
                    $cmd->setAttribute( 'ostype', "$EXEC_OSTYPE_LIBVIRT_KVM_OPENBSD[0]" );
                } elsif ( "@EXEC_OSTYPE_LIBVIRT_KVM_OPENBSD" !~ $cmdOSType )  {
                    return "incorrect ostype ($cmdOSType) in <exec> tag of vm $vmName (" . $cmd->toString . ")"; }

            } elsif ($merged_type eq 'libvirt-kvm-netbsd') {
                if (empty($cmdOSType)) { # Set default value 
                    $cmd->setAttribute( 'ostype', "$EXEC_OSTYPE_LIBVIRT_KVM_NETBSD[0]" );
                } elsif ( "@EXEC_OSTYPE_LIBVIRT_KVM_NETBSD" !~ $cmdOSType )  {
                    return "incorrect ostype ($cmdOSType) in <exec> tag of vm $vmName (" . $cmd->toString . ")"; }

            } elsif ($merged_type eq 'libvirt-kvm-windows') {
            	if (empty($cmdOSType)) { # Set default value 
            		$cmd->setAttribute( 'ostype', "$EXEC_OSTYPE_LIBVIRT_KVM_WINDOWS[0]" );
            	} elsif ( "@EXEC_OSTYPE_LIBVIRT_KVM_WINDOWS" !~ $cmdOSType )  {
       				return "incorrect ostype ($cmdOSType) in <exec> tag of vm $vmName (" . $cmd->toString . ")"; }     	

            } elsif ($merged_type eq 'libvirt-kvm-olive') {
            	if (empty($cmdOSType)) { # Set default value 
            		$cmd->setAttribute( 'ostype', "$EXEC_OSTYPE_LIBVIRT_KVM_OLIVE[0]" );
            	} elsif ( "@EXEC_OSTYPE_LIBVIRT_KVM_OLIVE" !~ $cmdOSType )  {
       				return "incorrect ostype ($cmdOSType) in <exec> tag of vm $vmName (" . $cmd->toString . ")"; }     	

            } elsif ( ($merged_type eq 'dynamips-3600') or ($merged_type eq 'dynamips-7200') )  {
            	if (empty($cmdOSType)) { # Set default value 
            		$cmd->setAttribute( 'ostype', "$EXEC_OSTYPE_DYNAMIPS[0]" );
            		#wlog (VVV, "-- ostype set to $EXEC_OSTYPE_DYNAMIPS[0]")
            	} elsif ( "@EXEC_OSTYPE_DYNAMIPS" !~ $cmdOSType )  {
       				return "incorrect ostype ($cmdOSType) in <exec> tag of vm $vmName (" . $cmd->toString . ")"; }     	

            }
            
        }               
	}

    #
    # Check allowed network configurations for Android VMs
    # Due to the lack of 'udev' mechanism to name interfaces in Android X86 and the restrictions found 
    # configuring network interfaces (for example, dhcp only worked in eth1), not all configurations 
    # are possible. 
    #
    # The list of tested and allowd configs follows:
    #   - mgmt = none
    #       + config1: no interfaces 
    #       + config2: if(id=1)->dhcp 
    #       + config3: if(id=1)->static 
    #       + config4: if(id=1)->dhcp and if(id=2)->static
    #   - mgmt = net
    #       + config5: no interfaces 
    #       + config6: if(id=1)->static 
    #   - mgmt = private
    #       + config7: no interfaces 
    #       + config8: if(id=1)->dhcp 
    #       + config9: if(id=1)->dhcp and if(id=2)->static
    #
    for ( my $i = 0; $i < @vm_ordered; $i++) {
        my $vm = $vm_ordered[$i];
        my $name = $vm->getAttribute("name");
        my $vm_type = $vm->getAttribute("type");               
        my $merged_type = $dh->get_vm_merged_type ($vm);
        
        if ($merged_type eq 'libvirt-kvm-android') {
        	
        	my %ifs;
        	foreach my $if ($vm->getElementsByTagName("if")) {
                my $id = $if->getAttribute("id");
                if ($id > 2) { return "only interfaces with id=[1-2] allowed in Android VMs "}
                my @ipv4s = $if->findnodes('ipv4');
                if (@ipv4s > 1) { return "only one IPv4 per interface supported in Android VMs (error in interface $id of $name)" }
                if( $if->exists("ipv6") ){ return "no IPv6 addresses supported in Android VMs (error in interface $id of $name)" }
  
                if ( text_tag($ipv4s[0]) eq 'dhcp') { $ifs{$id} = 'dhcp' }
                else { $ifs{$id} = 'static' }
        	}        	
        	
        	if ($dh->get_vmmgmt_type eq 'net') {
                if (str($ifs{1}) eq 'dhcp') { return "no DHCP configuration allowed when mgmt='net' (error in interface 1 of $name)" } 
                if (defined($ifs{2}))  { return "only one interface allowed when mgmt='net' (error in interface 2 of $name)"}
        	} elsif ($dh->get_vmmgmt_type eq 'private') {
                if ($ifs{2} eq 'dhcp')  { return "only one interface allowed when mgmt='net' (error in interface 2 of $name)"}
        	} else { # $dh->get_vmmgmt_type eq none
                if ( (str($ifs{1}) eq 'static' && str($ifs{2}) eq 'dhcp') ||
                     (str($ifs{1}) eq 'dhcp' && str($ifs{2}) eq 'dhcp') )
                 { return "incorrect interfaces configuration (only the interface with id=2 can be configured with DHCP)" }
                if ( defined($ifs{2}) and !defined($ifs{1})) { return "interface 2 cannot be used if interface 2 is not defined (error in VM $name)"}  
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
