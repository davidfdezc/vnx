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

    my $logp = "exec_command_host> ";
	my $doc = $dh->get_doc;

	# If host <host> is not present, there is nothing to do
    return if (!$doc->getElementsByTagName("host"));

	# To get <host> tag
	my $host = $doc->getElementsByTagName("host")->item(0);

	# To process exec tags of matching commands sequence
	#my $command_list = $host->getElementsByTagName("exec");

	# To process list, dumping commands to file
	#for ( my $j = 0 ; $j < $command_list->getLength ; $j++ ) {
	foreach my $command ($host->getElementsByTagName("exec")) {
		#my $command = $command_list->item($j);

		# To get attributes
		my $cmd_seq = $command->getAttribute("seq");
		my $type    = $command->getAttribute("type");

		if ( $cmd_seq eq $seq ) {

			# Case 1. Verbatim type
			if ( $type eq "verbatim" ) {

				# To include the command "as is"
				$execution->execute( $logp,  &text_tag_multiline($command) );
			}

			# Case 2. File type
			elsif ( $type eq "file" ) {

				# We open file and write commands line by line
				my $include_file = &do_path_expansion( &text_tag($command) );
				open INCLUDE_FILE, "$include_file"
				  or $execution->smartdie("can not open $include_file: $!");
				while (<INCLUDE_FILE>) {
					chomp;
					$execution->execute( $logp, $_);
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
#   - vm_name
#   - con_id
#   - consType
#   - consPar
#   - getLineOnly:   if defined, it just returns the command to open de console but it does 
#                    not execute it
#
sub open_console {
	
	my $self        = shift;
	my $vm_name      = shift;
	my $con_id      = shift;
	my $consType    = shift;
	my $consPar     = shift;
	my $getLineOnly = shift;

    my $logp = "open_console-$vm_name> ";

	my $command;
	if ($consType eq 'vnc_display') {
		$execution->execute_root( $logp, "virt-viewer -c $hypervisor $vm_name &");
		return;  			
   	} elsif ($consType eq 'libvirt_pts') {
		$command = "virsh -c $hypervisor console $vm_name";
        unless (defined $getLineOnly) {
            # Kill the console if already opened
            #print "`ps uax | grep \"virsh -c $hypervisor console $vm_name\" | awk '{ print \$2 }'`\n";
            my $pids = `ps uax | grep "virsh -c $hypervisor console $vm_name" | grep -v grep | awk '{ print \$2 }'`;
            $pids =~ s/\R/ /g;
            if ($pids) {
                wlog (V, "killing consoles processes: $pids", $logp);
                system "kill $pids";       
                system "sleep 1";       
            } else {
                wlog (V, "no previous consoles found", $logp);
            }
        }
   	} elsif ($consType eq 'uml_pts') {
        #$command = "screen -t $vm_name $consPar";
        #$command = "microcom -p $consPar";
        #$command = "picocom --noinit $consPar";
        my $emulator_cmd = "picocom --noinit $consPar";
        $command = "expect -c \"spawn $emulator_cmd; sleep 1; send \\\"\n\\\"; interact\"";
        #$command = "minicom -o -p $consPar"; # Console terminals do no die after VMs shutdown
        unless (defined $getLineOnly) {
	        # Kill the console if already opened
	        my $pids = `ps uax | grep -i '$emulator_cmd' | grep -v grep | awk '{ print \$2 }'`;
	        $pids =~ s/\R/ /g;
	        if ($pids) {
	            wlog (V, "killing consoles processes: $pids", $logp);
	            system "kill $pids";       
	            system "sleep 1";       
	        } else {
	            wlog (V, "no previous consoles found", $logp);
	        }
	        # Restart getty on virtual machine
	        my $con_num = $con_id;
	        $con_num =~ s/con//;
	        my $tty = "tty$con_num";

            my $mconsole = $dh->get_vm_run_dir($vm_name) . "/mconsole";
	        $execution->execute_mconsole( $logp,  $mconsole, "exec pkill getty -t $tty > /dev/null " );
	        
            #my $command = $bd->get_binaries_path_ref->{"uml_mconsole"} . " " 
            #               . $dh->get_vm_run_dir($vm_name) . "/mconsole " .
            #               "exec pkill getty -t $tty";
            #               #"exec kill `ps uax | grep getty | grep $tty | grep -v grep | awk '{print \$2}'` 2> /dev/null";
            #wlog (V, "command=$command", $logp);
            #system "$command";
	        
        }
   	} elsif ($consType eq 'telnet') {
		$command = "telnet localhost $consPar";						
	} else {
		wlog (N, "WARNING (vm=$vm_name): unknown console type ($consType)");
	}
	
	my $console_term=&get_conf_value ($vnxConfigFile, 'general', 'console_term', 'root');
	my $exeLine;
	wlog (VVV, "$vm_name $command console_term = $console_term", $logp);
	if ($console_term eq 'gnome-terminal') {
		$exeLine = "gnome-terminal --title '$vm_name - console #$con_id' -e '$command'";
	} elsif ($console_term eq 'konsole') {
		$exeLine = "konsole --title '$vm_name - console #$con_id' -e $command";
	} elsif ($console_term eq 'xterm') {
		$exeLine = "xterm -rv -sb -rightbar -fa monospace -fs 10 -title '$vm_name - console #$con_id' -e '$command'";
	} elsif ($console_term eq 'roxterm') {
		$exeLine = "roxterm --title '$vm_name - console #$con_id' -e $command";
	} else {
		$execution->smartdie ("unknown value ($console_term) of console_term parameter in $vnxConfigFile");
	}
    wlog (VVV, "exeLine=$exeLine", $logp);
	unless (defined($getLineOnly)) {
        $execution->execute_root($logp, $exeLine .  ">/dev/null 2>&1 &");
		#$execution->execute( $logp, $exeLine .  ">/dev/null 2>&1 &");
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
	my $vm_name    = shift;
	my $consId    = shift;

    my $logp = "start_console-$vm_name> ";

	# Read the console file and start the console with id $consId 
	my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
	open (CONS_FILE, "< $consFile") || $execution->smartdie("Could not open $consFile file.");
	foreach my $line (<CONS_FILE>) {
	    chomp($line);               # remove the newline from $line.
	    my $con_id = $line;
		#$con_id =~ s/con(\d)=.*/$1/;   # get the console id
		$con_id =~ s/=.*//;             # get the console name
	    $line =~ s/con.=//;  		    # eliminate the "conX=" part of the line
		if ($con_id eq $consId) {	
		    #wlog (VVV, "CONS_FILE: $line");
		    my @consField = split(/,/, $line);
		    wlog (VVV, "console $con_id of $vm_name: $consField[0] $consField[1] $consField[2]", $logp);
		    #if ($consField[0] eq 'yes') {  # console with display='yes'
		    # We open the console independently of display value
		    open_console ($self, $vm_name, $con_id, $consField[1], $consField[2]);
		    return;
			#}
		} 
	}
	wlog (N, "ERROR: console $consId of virtual machine $vm_name does not exist");	

}

#
# Start all the active consoles of a virtual machine starting from the information
# found in the vm console file
#
sub start_consoles_from_console_file {
	
	my $self      = shift;
	my $vm_name    = shift;

    my $logp = "start_consoles_from_console_file-$vm_name> ";

	# Then, we just read the console file and start the active consoles
	my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
    #open (CONS_FILE, "< $consFile") || $execution->smartdie("Could not open $consFile file.");
    unless ( open (CONS_FILE, "< $consFile") ) { 
    	wlog (N, "ERROR: could not open $consFile file."); 
    	return; 
    };
	foreach my $line (<CONS_FILE>) {
	    chomp($line);               # remove the newline from $line.
	    my $con_id = $line;
		$con_id =~ s/con(\d)=.*/$1/;    # get the console id
	    $line =~ s/con.=//;  		# eliminate the "conX=" part of the line
	    #wlog (VVV, "** CONS_FILE: $line");
	    my @consField = split(/,/, $line);
        wlog (VVV, "console $con_id of $vm_name: $consField[0] $consField[1] $consField[2]", $logp);
	    if ($consField[0] eq 'yes') {  # console with display='yes'
	        open_console ($self, $vm_name, $con_id, $consField[1], $consField[2]);
		} 
	}

}

###################################################################
# get_admin_address
# 
# 
# TODO: OBSOLETED...change this description!  
#
# Examples: 
#   my $net = &get_admin_address( 'file', $vm_name );
#   my $mng_addr = &get_admin_address( $manipcounter, $vm_name, $dh->get_vmmgmt_type );
#
# If $hostnum=1 

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
    my $vm_name = shift;
    my $vmmgmt_type = shift;

    my $logp = "get_admin_address-$vm_name> ";

    my %ip;

    if ($seed eq "file"){
        wlog (VV, "seed=$seed, vm_name=$vm_name", $logp);
        # read management ip value from file
        my $addr_vm   = &get_conf_value ($dh->get_vm_dir($vm_name) . '/mng_ip', '', 'addr_vm');
        my $mask      = &get_conf_value ($dh->get_vm_dir($vm_name) . '/mng_ip', '', 'mask');
        my $addr_host = &get_conf_value ($dh->get_vm_dir($vm_name) . '/mng_ip', '', 'addr_host');
        if ( $addr_vm && $mask && $addr_host ) {
	        $ip{'vm'} = NetAddr::IP->new($addr_vm,$mask);
	        $ip{'host'} = NetAddr::IP->new($addr_host,$mask);
	        wlog (VVV, "returns: addr_vm=". $ip{'vm'}->addr . ", mask=" . $ip{'vm'}->mask . ", addr_host=" . $ip{'host'}->addr, $logp);
        }
    } else {
    	wlog (VV, "seed=$seed, vm_name=$vm_name, vmmgmt_type=$vmmgmt_type", $logp);
        my $net = NetAddr::IP->new($dh->get_vmmgmt_net."/".$dh->get_vmmgmt_mask);
        if ($vmmgmt_type eq 'private') {
            # check to make sure that the address space won't wrap
            if ($dh->get_vmmgmt_offset + ($seed << 2) > (1 << (32 - $dh->get_vmmgmt_mask)) - 3) {
                $execution->smartdie ("IPv4 address exceeded range of available admin addresses. \n");
            }
            # create a private subnet from the seed
            $net += $dh->get_vmmgmt_offset + ($seed << 2);
            $ip{'host'} = NetAddr::IP->new($net->addr()."/30") + 1;
            $ip{'vm'}   = NetAddr::IP->new($net->addr()."/30") + 2;
	
        } else {
            # vmmgmt type is 'net'
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
            $ip{'vm'}   = NetAddr::IP->new($net + $dh->get_vmmgmt_offset + $seed + 1 ."/" . $dh->get_vmmgmt_mask) + 1;
            $ip{'host'} = $hostip;
        }

        # create mng_ip file in run dir
        my $addr_vm_line = "addr_vm=" . $ip{'vm'}->addr();
        my $mask_line = "mask=" . $ip{'host'}->mask();
        my $addr_host_line = "addr_host=" . $ip{'host'}->addr();
        my $mngip_file = $dh->get_vm_dir($vm_name) . '/mng_ip';
        wlog (VV, "mngip_file=$mngip_file", $logp);
        open MNGIP, "> $mngip_file"
            or $execution->smartdie("can not open $mngip_file")
                unless ( $execution->get_exe_mode() eq $EXE_DEBUG );        
        print MNGIP "$addr_vm_line\n$mask_line\n$addr_host_line\n";
        close MNGIP; 
        wlog (VV, "returns: addr_vm=". $ip{'vm'}->addr . ", mask=" . $ip{'vm'}->mask . ", addr_host=" . $ip{'host'}->addr, $logp);
    }

    return %ip;
}

1;