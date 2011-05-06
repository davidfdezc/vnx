# vmAPICommon.pm
#
# This file is a module part of VNX package.
#
# Author: David Fernández (david@dit.upm.es)
# Copyright (C) 2010, 	DIT-UPM
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

# vmAPI_common is used to store functions common to two or more vmAPI_* modules 

package VNX::vmAPICommon;

use strict;
use warnings;
use Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(	
	exec_command_host
	open_console
	start_console
	start_consoles_from_console_file
	get_admin_address
	);

use VNX::Execution;
use VNX::FileChecks;
use VNX::Globals;



###################################################################
#
sub exec_command_host {

	my $self = shift;
	my $seq  = shift;

	my $doc = $dh->get_doc;

	# If host <host> is not present, there is nothing to do
	return if ( $doc->getElementsByTagName("host")->getLength eq 0 );

	# To get <host> tag
	my $host = $doc->getElementsByTagName("host")->item(0);

	# To process exec tags of matching commands sequence
	my $command_list = $host->getElementsByTagName("exec");

	# To process list, dumping commands to file
	for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
		my $command = $command_list->item($j);

		# To get attributes
		my $cmd_seq = $command->getAttribute("seq");
		my $type    = $command->getAttribute("type");

		if ( $cmd_seq eq $seq ) {

			# Case 1. Verbatim type
			if ( $type eq "verbatim" ) {

				# To include the command "as is"
				$execution->execute( &text_tag_multiline($command) );
			}

			# Case 2. File type
			elsif ( $type eq "file" ) {

				# We open file and write commands line by line
				my $include_file = &do_path_expansion( &text_tag($command) );
				open INCLUDE_FILE, "$include_file"
				  or $execution->smartdie("can not open $include_file: $!");
				while (<INCLUDE_FILE>) {
					chomp;
					$execution->execute($_);
				}
				close INCLUDE_FILE;
			}

			# Other case. Don't do anything (it would be an error in the XML!)
		}
	}
}


#
# Starts the console of a virtual machine using the application
# defined in VNX_CONFFILE console_term entry
# 
# Parameters:
#   - vmName
#   - con_id
#   - consType
#   - consPar
#   - getLineOnly:   if defined, it just returns the command to open de console but it does 
#                    not execute it
#
sub open_console {
	
	my $self        = shift;
	my $vmName      = shift;
	my $con_id      = shift;
	my $consType    = shift;
	my $consPar     = shift;
	my $getLineOnly = shift;

	my $command;
	if ($consType eq 'vnc_display') {
		$execution->execute("virt-viewer -c $hypervisor $vmName &");
		return;  			
   	} elsif ($consType eq 'libvirt_pts') {
		$command = "virsh -c $hypervisor console $vmName";
   	} elsif ($consType eq 'uml_pts') {
		$command = "screen -t $vmName $consPar";
   	} elsif ($consType eq 'telnet') {
		$command = "telnet localhost $consPar";						
	} else {
		print "WARNING (vm=$vmName): unknown console type ($consType)\n"
	}
	
	my $console_term=&get_conf_value ($vnxConfigFile, 'general', 'console_term');
	my $exeLine;
	#print "*** start_console: $vmName $command console_term = $console_term\n";
	if ($console_term eq 'gnome-terminal') {
		$exeLine = "gnome-terminal --title '$vmName - console #$con_id' -e '$command'";
	} elsif ($console_term eq 'konsole') {
		$exeLine = "konsole --title '$vmName - console #$con_id' -e $command";
	} elsif ($console_term eq 'xterm') {
		$exeLine = "xterm -rv -sb -rightbar -fa monospace -fs 10 -title '$vmName - console #$con_id' -e '$command'";
	} elsif ($console_term eq 'roxterm') {
		$exeLine = "roxterm --title '$vmName - console #$con_id' -e $command";
	} else {
		$execution->smartdie ("unknown value ($console_term) of console_term parameter in $vnxConfigFile");
	}
	if (!defined $getLineOnly) {
		$execution->execute($exeLine .  ">/dev/null 2>&1 &");
	}
	return $exeLine;
}

#
# Start a specific console of a virtual machine
#
# Parameters:
# - vmName
# - consId   (con0, con1, etc)
#
sub start_console {
	
	my $self      = shift;
	my $vmName    = shift;
	my $consId    = shift;

	# Read the console file and start the console with id $consId 
	my $consFile = $dh->get_vm_dir($vmName) . "/run/console";
	open (CONS_FILE, "< $consFile") || $execution->smartdie("Could not open $consFile file.");
	foreach my $line (<CONS_FILE>) {
	    chomp($line);               # remove the newline from $line.
	    my $con_id = $line;
		#$con_id =~ s/con(\d)=.*/$1/;   # get the console id
		$con_id =~ s/=.*//;             # get the console name
	    $line =~ s/con.=//;  		    # eliminate the "conX=" part of the line
		if ($con_id eq $consId) {	
		    #print "** CONS_FILE: $line\n";
		    my @consField = split(/,/, $line);
		    print "** CONS_FILE: $consField[0] $consField[1] $consField[2]\n";
		    #if ($consField[0] eq 'yes') {  # console with display='yes'
		    # We open the console independently of display value
		    open_console ($self, $vmName, $con_id, $consField[1], $consField[2]);
		    return;
			#}
		} 
	}
	print "ERROR: console $consId of virtual machine $vmName does not exist\n";	

}

#
# Start all the active consoles of a virtual machine starting from the information
# found in the vm console file
#
sub start_consoles_from_console_file {
	
	my $self      = shift;
	my $vmName    = shift;

	# Then, we just read the console file and start the active consoles
	my $consFile = $dh->get_vm_dir($vmName) . "/run/console";
	open (CONS_FILE, "< $consFile") || $execution->smartdie("Could not open $consFile file.");
	foreach my $line (<CONS_FILE>) {
	    chomp($line);               # remove the newline from $line.
	    my $con_id = $line;
		$con_id =~ s/con(\d)=.*/$1/;    # get the console id
	    $line =~ s/con.=//;  		# eliminate the "conX=" part of the line
	    #print "** CONS_FILE: $line\n";
	    my @consField = split(/,/, $line);
	    print "** CONS_FILE: $consField[0] $consField[1] $consField[2]\n";
	    if ($consField[0] eq 'yes') {  # console with display='yes'
	        open_console ($self, $vmName, $con_id, $consField[1], $consField[2]);
		} 
	}	

}

###################################################################
# get_admin_address
#
# Returns a four elements list:
#
# - network address
# - network mask
# - IPv4 address of one peer
# - IPv4 address of the other peer
#
# This functions takes a single argument, an integer which acts as counter
# for UML'. It uses NetAddr::IP objects to calculate addresses for TWO hosts,
# whose addresses and mask returns.
#
# Private addresses of 192.168. prefix are used. For now, this is
# hardcoded in this function. It could, and should, i think, become
# part of the VNUML dtd.
#
# In VIRTUAL SWITCH MODE (net_sw) this function ...
# which returns UML ip undefined. Or, if one needs UML ip, function 
# takes two arguments: $vm object and interface id. Interface id zero 
# is reserved for management interface, and is default is none is supplied
#
sub get_admin_address {

   my $seed = shift;
   my $vmmgmt_type = shift;
   my $hostnum = shift;
   my $vmName = shift;
   my $ip;
   
   my $net = NetAddr::IP->new($dh->get_vmmgmt_net."/".$dh->get_vmmgmt_mask);
   if ($vmmgmt_type eq 'private') {
      if ($seed eq "file"){
         #read management ip value from file
         my $addr = &get_conf_value ($dh->get_vm_dir($vmName) . '/mng_ip', '', 'addr');
         my $mask = &get_conf_value ($dh->get_vm_dir($vmName) . '/mng_ip', '', 'mask');
         $ip = NetAddr::IP->new($addr.$mask);
      }else{
         # check to make sure that the address space won't wrap
         if ($dh->get_vmmgmt_offset + ($seed << 2) > (1 << (32 - $dh->get_vmmgmt_mask)) - 3) {
            $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
         }
         # create a private subnet from the seed
         $net += $dh->get_vmmgmt_offset + ($seed << 2);
         $ip = NetAddr::IP->new($net->addr()."/30") + $hostnum;

         # create mng_ip file in vm dir, unless processing the host
         unless ($hostnum eq 1){
         	my $addr_line = "addr=" . $ip->addr();
            my $mask_line = "mask=" . $ip->mask();
            my $mngip_file = $dh->get_vm_dir($vmName) . '/mng_ip';
            $execution->execute($bd->get_binaries_path_ref->{"echo"} . " $addr_line > $mngip_file");
            $execution->execute($bd->get_binaries_path_ref->{"echo"} . " $mask_line >> $mngip_file");
         }
      }     
   } else {
	  # vmmgmt type is 'net'
      if ($seed eq "file"){
         #read management ip value from file
         $ip= &get_conf_value ($dh->get_vm_dir($vmName) . '/mng_ip', '', 'management_ip');
      }else{
         # don't assign the hostip
         my $hostip = NetAddr::IP->new($dh->get_vmmgmt_hostip."/".$dh->get_vmmgmt_mask);
         if ($hostip > $net + $dh->get_vmmgmt_offset &&
            $hostip <= $net + $dh->get_vmmgmt_offset + $seed + 1) {
         $seed++;
         }

         # check to make sure that the address space won't wrap
         if ($dh->get_vmmgmt_offset + $seed > (1 << (32 - $dh->get_vmmgmt_mask)) - 3) {
            $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
         }

         # return an address in the vmmgmt subnet
         $ip = $net + $dh->get_vmmgmt_offset + $seed + 1;
         
         # create mng_ip file in run dir
         my $addr_line = "addr=" . $ip->addr();
         my $mask_line = "addr=" . $ip->mask();
         my $mngip_file = $dh->get_vm_dir($vmName) . '/mng_ip';
         $execution->execute($bd->get_binaries_path_ref->{"echo"} . " $addr_line > $mngip_file");
         $execution->execute($bd->get_binaries_path_ref->{"echo"} . " $mask_line >> $mngip_file");
      }
   }

   return $ip;
}

1;