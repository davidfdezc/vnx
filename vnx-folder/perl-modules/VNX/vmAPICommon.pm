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
	execute_host_command 
	open_console
	start_console
	start_consoles_from_console_file
	get_admin_address
	autoconfigure_debian_ubuntu
	autoconfigure_redhat
    autoconfigure_freebsd
    autoconfigure_openbsd
    autoconfigure_android
    autoconfigure_wanos
    get_os_distro
    get_code_of_get_os_distro
	);

use VNX::Execution;
use VNX::FileChecks;
use VNX::Globals;
use VNX::DocumentChecks;
use VNX::TextManipulation;

my $PERLIB=`perl -e 'use Config; print \$Config{installvendorlib}'`;
require "$PERLIB/VNX/vnx_autoconfigure.pl";

###################################################################
#
sub execute_host_command {

	my $seq  = shift;

    my $logp = "execute_host_command> ";
	my $doc = $dh->get_doc;
	
	my $num_host_execs = 0;

    wlog (VV, "seq=$seq", $logp);
    
	# If host <host> is not present and there are no <exec> tags under <host>, 
	# there is nothing to do
    return $num_host_execs if ( ! $doc->exists("/vnx/host/exec") );

	# Check if the execution of host commands is allowed in config file (/etc/vnx.conf)
	# ..
	# [general]
    # ...
    # exe_host_cmds=no
	#
    my $exe_host_cmds = get_conf_value ($vnxConfigFile, 'general', 'exe_host_cmds', 'root');
    my $exe_allowed = ! empty($exe_host_cmds) && $exe_host_cmds eq 'yes';

    my @execs = $doc->findnodes("/vnx/host/exec[\@seq='$seq']");
    foreach my $exec (@execs) {
        	
        if (!$exe_allowed) {
            wlog (N, "--\n-- ERROR. Host command execution forbidden by configuration.\n" . 
                     "--        Change 'exe_host_cmds' config value in [general] section of /etc/vnx.conf file).");
            return $num_host_execs
        }
            
        my $type = $exec->getAttribute("type");

        #
        # Get the commands to execute
        #
        my $cmds;

        # Case 1. Verbatim type
        if ( $type eq "verbatim" ) {
            $cmds = $exec->textContent;
        }
        # Case 2. File type
        elsif ( $type eq "file" ) {
            my $cmd_file = do_path_expansion( text_tag($exec) );
	        $cmds = do {
                local $/ = undef;
                open my $fh, "<", $cmd_file
                    or vnx_die ("could not open command file $cmd_file $! defined in '$seq' <exec> tag");
                <$fh>;
            };
        }

        # 
        # Process the commands
        #     
        my $new_cmds;
        # Join lines ending with an '\' to have each complete command in a line  
        $cmds =~ s/\\\s*\n\s*/ /g; 
        my @lines = split /\n/, $cmds;
        if ($lines[0]) { $new_cmds = ''} else { $new_cmds = "\n"}
        foreach my $line (@lines) {
            $line =~ s/^\s+//; # delete leading spaces
            $line =~ s/\s+$//; # delete trailing spaces
            next if $line =~ /^#/; # ignore comments
            next if $line =~ /^$/; # ignore empty lines
            $line .= ';' if ( ($line !~ /;$/) && ($line !~ /&$/) );
            #print $line . "\n";
            $new_cmds .= $line . "\n";
        }
        #print $new_cmds . "\n";                

        # Execute the commands
        my $res = $execution->execute_getting_output( $logp,  $new_cmds);
        wlog (N, "---\n$res---", '') if ($res ne '');                
    } 
     
    return $num_host_execs
      
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
	my $vm_name     = shift;
	my $con_id      = shift;
	my $cons_type   = shift;
	my $consPar     = shift;
	my $getLineOnly = shift;

    my $logp = "open_console-$vm_name> ";

	my $command ='';
	my $exeLine;
	
	my $vm = $dh->get_vm_byname ($vm_name);
	my @vm_type = $dh->get_vm_type($vm);

    wlog (VVV, "con_id=$con_id, cons_type=$cons_type, cons_Par=$consPar", $logp);    
	if ($cons_type eq 'vnc_display') {
        $exeLine = "virt-viewer -c $hypervisor $vm_name &";
        #$execution->execute_root( $logp, "virt-viewer -c $hypervisor $vm_name &");
		#return;  			
   	} elsif ($cons_type eq 'libvirt_pts') {
		$command = "virsh -c $hypervisor console $vm_name";
        unless (defined $getLineOnly) {
            # Kill the console if already opened
            #print "`ps uax | grep \"virsh -c $hypervisor console $vm_name\" | awk '{ print \$2 }'`\n";
            my $pids = `ps uax | grep "virsh -c $hypervisor console ${vm_name}\$" | grep -v grep | awk '{ print \$2 }'`;
            $pids =~ s/\R/ /g;
            if ($pids) {
                wlog (V, "killing consoles processes: $pids", $logp);
                system "kill $pids";       
                system "sleep 1";       
            } else {
                wlog (V, "no previous consoles found", $logp);
            }
        }
   	} elsif ($cons_type eq 'uml_pts') {
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
   	} elsif ($cons_type eq 'telnet') {
		$command = "telnet localhost $consPar";		
		
    } elsif ($cons_type eq 'lxc') {
        $command = "lxc-console -n $vm_name";
						
	} else {
		wlog (N, "WARNING (vm=$vm_name): unknown console type ($cons_type)");
	}
	
    my $console_term_mode = str(get_conf_value ($vnxConfigFile, 'general', 'console_term_mode', 'root'));
    my $start_console_as_user = ! empty($console_term_mode) && $console_term_mode eq 'user';
    wlog (VVV, "console_term_mode=$console_term_mode, start_console_as_user=$start_console_as_user, user=" . $>, $logp);	
	
	if ($con_id != 0 or $cons_type eq 'lxc') {
        
        if ($start_console_as_user) {
        	$command = "sudo $command";
        }
		my $console_term=&get_conf_value ($vnxConfigFile, 'general', 'console_term', 'root');
		wlog (VVV, "$vm_name $command console_term = $console_term", $logp);
		if ($console_term eq 'gnome-terminal') {
			$exeLine = "gnome-terminal --title '$vm_name - console #$con_id' -e '$command'";
		} elsif ($console_term eq 'konsole') {
			$exeLine = "konsole --title '$vm_name - console #$con_id' -e $command";
		} elsif ($console_term eq 'xterm') {
			$exeLine = "xterm -rv -sb -rightbar -fa monospace -fs 10 -title '$vm_name - console #$con_id' -e '$command'";
		} elsif ($console_term eq 'roxterm') {
			$exeLine = "roxterm --title '$vm_name - console #$con_id' --hide-menubar -e '$command'";
		} elsif ($console_term eq 'lxterminal') {
			$exeLine = "lxterminal --title '$vm_name - console #$con_id' -e $command";
		} elsif ($console_term eq 'xfce4-terminal') {
            if ($mode eq 'console') {
                $exeLine = "xfce4-terminal --title '$vm_name - console #$con_id' --hide-menubar -e '$command'";
            } else {
                #$exeLine = "xfce4-terminal --title '$vm_name - console #$con_id' --hide-menubar -x expect -c 'spawn $command; sleep 10; send k\\n; sleep 1; send \\003; interact'";
                $exeLine = "xfce4-terminal --title '$vm_name - console #$con_id' --hide-menubar -x expect -c 'spawn $command; sleep 5; send \\015; interact'";
            }
		} else {
			$execution->smartdie ("unknown value ($console_term) of console_term parameter in $vnxConfigFile");
		}
	    wlog (VVV, "exeLine=$exeLine", $logp);
	    unless (defined($getLineOnly)) {
            if ($start_console_as_user) {
my $user= $>;
$> = $uid_orig; wlog (V, "uid=$uid_orig"); #pak();
                wlog (V, "console started as user ($>)", $logp);
                $execution->execute( $logp, $exeLine .  ">/dev/null 2>&1 &");
                #system ("gnome-terminal > /dev/null 2>&1 &");
                #my $res = `gnome-terminal > /dev/null 2>&1 &`;
                #my $res = `gnome-terminal`;
                #my $res = `konsole`;
                #print "res=$res";
                #pak("res=$res\n");
                #$execution->execute( $logp, "gnome-terminal --title 'ubuntu - console #1' -e 'sudo virsh -c qemu:///system console ubuntu'>/dev/null 2>&1 &");
                #$execution->execute( $logp, "xterm &");
change_to_root();
$> = $user;
            } else {
                wlog (VVV, "console started as root", $logp);
                $execution->execute_root($logp, $exeLine .  ">/dev/null 2>&1 &");
            }
	    }
	} else {
    #wlog (VVV, "exeLine=$exeLine", $logp);
	    unless (defined($getLineOnly)) {
	        $execution->execute_root($logp, $exeLine .  ">/dev/null 2>&1 &");
	        #$execution->execute( $logp, $exeLine .  ">/dev/null 2>&1 &");
	    }
	}
	
	my $win_cfg = get_console_win_info($vm_name, $con_id);
    wlog (V, "get_console_win_info returns $win_cfg", $logp);
	unless ( $win_cfg eq ':::') {
		# Wait for window to be ready
		my $win_str;
		if ($vm_type[0] eq 'dynamips') {
			$win_str = "${vm_name}\$"
		} elsif ($vm_type[0] eq 'libvirt') {
	        if ($con_id == 0) {
	            $win_str = "$vm_name.*- Virt Viewer"
	        } else {
	            $win_str = "$vm_name.*- console"
	        }
		} else {
                $win_str = "$vm_name.*- console"
		}
		
		my $timeout = 5;
		while (! `wmctrl -l | grep "$win_str"`) {
            print ".";
			sleep 1;
			$timeout--;
			unless ($timeout) { 
				wlog (V, "time out waiting for console window to be ready ($vm_name, $con_id, $win_str)", $logp);
                return $exeLine;
			} 
		}
		# get window id
		my $win_id = `wmctrl -l | grep "$win_str" | awk '{print \$1}'`;
		chomp ($win_id);
		
        my @win_info = split( /:/, $win_cfg );
        if ($win_info[1]) {
        	# move window to desktop specified
            $execution->execute($logp, "wmctrl -i -r $win_id -t $win_info[1]");
        }
        if ($win_info[0]) {
        	# change window size and position
            $execution->execute($logp, "wmctrl -i -r $win_id -e 0,$win_info[0]");
        }
        $execution->execute($logp, "wmctrl -i -a $win_id");
        if (str($win_info[2]) eq 'yes') {
        	# set the window on_top
            $execution->execute($logp, "wmctrl -i -r $win_id -b toggle,above");
        }
        if (str($win_info[3]) eq 'minimized') {
            # Minimize the window
            $execution->execute($logp, "xdotool windowminimize $win_id");
        }
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

    wlog (VVV, "consId=$consId", $logp);
    
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
		    $con_id =~ s/con//;  # Eliminate the 'con' part and let the number 
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

#
# get_console_win_info
#
# Reads the window configuration file associated with the scenario a looks for
# values for console $con_id of virtual machine $vm_name
#
# Returns a string with the following format:
#  $win_pos:$desktop:$on_top:$status
#
# If a value is not specified, a empty string is returned
# Examples: 
#  0,0,600,400:1:yes:
#  0,0,600,400::no:minimized
#
sub get_console_win_info {
	
	my $vm_name = shift;
	my $con_id  = shift;
	
    my $logp = "get_console_win_pos> ";
	
	my $cfg_file = $dh->get_cfg_file();
    wlog (V, "get_console_win_info -> cfg_file=$cfg_file", $logp);
	my $win_pos_def=''; 
    my $desktop_def='';
    my $on_top_def='';
    my $status_def='';
    my $win_pos=''; 
    my $desktop='';
    my $on_top='';
    my $status='';
	
	if ($cfg_file) {
		
        my $parser = XML::LibXML->new();
        my $doc = $parser->parse_file($cfg_file);

        # Get defaults if specified in .cvnx file
        my @default;
        if( $doc->exists("/vnx_cfg/default[\@id='$con_id']")) {
            # load specific default values for this console id
            @default = $doc->findnodes("/vnx_cfg/default[\@id='$con_id']");
        } elsif ( $doc->exists("/vnx_cfg/default") ) {
            # load general default values for all consoles
            @default = $doc->findnodes("/vnx_cfg/default");
        }
        if (@default) {
            $win_pos_def = str($default[0]->getAttribute('win'));
            $desktop_def = str($default[0]->getAttribute('desktop'));
            $on_top_def  = str($default[0]->getAttribute('ontop'));
            $status_def  = str($default[0]->getAttribute('status'));
            wlog (V, "win_cfg def values -> con_id=$con_id - win_pos_def=$win_pos_def:desktop_def=$desktop_def:on_top_def=$on_top_def:status_def=$status_def", $logp)
        }

        # Get values specified for this VM
        my @vms;
        if ( $doc->exists("/vnx_cfg/vm[\@name='$vm_name' and \@id='$con_id']") ) {
            # load specific values for this VM and console id 
            @vms = $doc->findnodes("/vnx_cfg/vm[\@name='$vm_name' and \@id='$con_id']");
        } elsif ( $doc->exists("/vnx_cfg/vm[\@name='$vm_name']") ) {
            # load specific values for this VM but generic for any console id 
            @vms = $doc->findnodes("/vnx_cfg/vm[\@name='$vm_name']");
        }
        if (@vms) {
            $win_pos = str($vms[0]->getAttribute('win'));
            if ( $win_pos eq '') { $win_pos = $win_pos_def }
            $desktop = str($vms[0]->getAttribute('desktop'));
            if ( $desktop eq '') { $desktop = $desktop_def } 
            $on_top = str($vms[0]->getAttribute('ontop'));
            if ( $on_top eq '' )  { $on_top = $on_top_def   } 
            $status = str($vms[0]->getAttribute('status'));
            if ( $status eq '' )  { $status = $status_def   } 
        }
        wlog (V, "win_cfg final values -> win_pos=$win_pos:desktop=$desktop:on_top=$on_top:status=$status", $logp);
	}
    return str($win_pos) . ":". str($desktop) . ":" . str($on_top) . ":" . str($status);    
}

###################################################################
# get_admin_address
# 
# 
# Arguments:
# - seed: if seed='file' indicates that the address has to be read from the VM file
#                        that stores the management address ($dh->get_vm_dir($vm_name).'/mng_ip') 
#         else ...

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
        my $addr_vm   = get_conf_value ($dh->get_vm_dir($vm_name) . '/mng_ip', '', 'addr_vm');
        my $mask      = get_conf_value ($dh->get_vm_dir($vm_name) . '/mng_ip', '', 'mask');
        my $addr_host = get_conf_value ($dh->get_vm_dir($vm_name) . '/mng_ip', '', 'addr_host');
        if ( $addr_vm && $mask && $addr_host ) {
	        $ip{'vm'} = NetAddr::IP->new($addr_vm,$mask);
	        $ip{'host'} = NetAddr::IP->new($addr_host,$mask);
	        wlog (VVV, "returns: addr_vm=". $ip{'vm'}->addr . ", mask=" . $ip{'vm'}->mask . ", addr_host=" . $ip{'host'}->addr, $logp);
        }
    } else {
    	wlog (VV, "seed=$seed, vm_name=$vm_name, vmmgmt_type=$vmmgmt_type, get_vmmgmt_net/mask=" . $dh->get_vmmgmt_net . "/" . $dh->get_vmmgmt_mask, $logp);
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
	
        } elsif ($vmmgmt_type eq 'net') {
            # vmmgmt type is 'net'
            # don't assign the hostip
            wlog (VV, "get_vmmgmt_hostip=" . $dh->get_vmmgmt_hostip, $logp);

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
            $ip{'vm'}   = NetAddr::IP->new($net)  + $dh->get_vmmgmt_offset + $seed + 1;
            $ip{'host'} = $hostip;
            wlog (VV, "returns: addr_vm=". $ip{'vm'}->addr . ", mask=" . $ip{'vm'}->mask . ", addr_host=" . $ip{'host'}->addr, $logp);
        } else {
            $ip{'vm'}   = NetAddr::IP->new('0.0.0.0');
            $ip{'host'} = NetAddr::IP->new('0.0.0.0');
        }

        if ($vm_name ne '') {
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
        }
        wlog (VV, "returns: addr_vm=". $ip{'vm'}->addr . ", mask=" . $ip{'vm'}->mask . ", addr_host=" . $ip{'host'}->addr, $logp);
    }

    return %ip;
}

#-------------------------------------


#
# Converts a CIDR prefix length to a dot notation mask
#
sub cidr_to_mask {

  my $len=shift;
  my $dec32=2 ** 32;
  # decimal equivalent
  my $dec=$dec32 - ( 2 ** (32-$len));
  # netmask in dotted decimal
  my $mask= join '.', unpack 'C4', pack 'N', $dec;
  return $mask;
}

sub get_os_distro {
    
    my $OS=`uname -s`; chomp ($OS);
    my $REV=`uname -r`; chomp ($REV);
    my $MACH=`uname -m`; chomp ($MACH);
    my $ARCH;
    my $OSSTR;
    my $DIST;
    my $KERNEL;
    my $PSEUDONAME;
        
    if ( $OS eq 'SunOS' ) {
            $OS='Solaris';
            $ARCH=`uname -p`;
            $OSSTR= "$OS,$REV,$ARCH," . `uname -v`;
    } elsif ( $OS eq "AIX" ) {
            $OSSTR= "$OS," . `oslevel` . "," . `oslevel -r`;
    } elsif ( $OS eq "Linux" ) {
            $KERNEL=`uname -r`;
            if ( -e '/etc/redhat-release' ) {
            my $relfile = `cat /etc/redhat-release`;
            my @fields  = split(/ /, $relfile);
                    $DIST = $fields[0];
                    $REV = $fields[2];
                    $PSEUDONAME = $fields[3];
                    $PSEUDONAME =~ s/\(//; $PSEUDONAME =~ s/\)//;
        } elsif ( -e '/etc/SuSE-release' ) {
                    $DIST=`cat /etc/SuSE-release | tr "\n" ' '| sed s/VERSION.*//`;
                    $REV=`cat /etc/SuSE-release | tr "\n" ' ' | sed s/.*=\ //`;
            } elsif ( -e '/etc/mandrake-release' ) {
                    $DIST='Mandrake';
                    $PSEUDONAME=`cat /etc/mandrake-release | sed s/.*\(// | sed s/\)//`;
                    $REV=`cat /etc/mandrake-release | sed s/.*release\ // | sed s/\ .*//`;
            } elsif ( -e '/etc/lsb-release' ) {
                    $DIST= `cat /etc/lsb-release | grep DISTRIB_ID | sed 's/DISTRIB_ID=//'`; 
                    $REV = `cat /etc/lsb-release | grep DISTRIB_RELEASE | sed 's/DISTRIB_RELEASE=//'`;
                    $PSEUDONAME = `cat /etc/lsb-release | grep DISTRIB_CODENAME | sed 's/DISTRIB_CODENAME=//'`;
            } elsif ( -e '/etc/debian_version' ) {
                    $DIST= "Debian"; 
                    $REV=`cat /etc/debian_version`;
                    $PSEUDONAME = `LANG=C lsb_release -a 2> /dev/null | grep Codename | sed 's/Codename:\\s*//'`;
        }
            if ( -e '/etc/UnitedLinux-release' ) {
                    $DIST=$DIST . " [" . `cat /etc/UnitedLinux-release | tr "\n" ' ' | sed s/VERSION.*//` . "]";
            }
        chomp ($KERNEL); chomp ($DIST); chomp ($PSEUDONAME); chomp ($REV);
            $OSSTR="$OS,$DIST,$REV,$PSEUDONAME,$KERNEL,$MACH";
    } elsif ( $OS eq "FreeBSD" ) {
            $DIST= "FreeBSD";
        $REV =~ s/-RELEASE//;
            $OSSTR="$OS,$DIST,$REV,$PSEUDONAME,$KERNEL,$MACH";
    } elsif ( $OS eq "OpenBSD" ) {
            $DIST= "OpenBSD";
        $REV =~ s/-RELEASE//;
            $OSSTR="$OS,$DIST,$REV,$PSEUDONAME,$KERNEL,$MACH";
    }
return $OSSTR;
}

sub get_code_of_get_os_distro {
    
return <<'EOF';
#!/usr/bin/perl

use strict;
use warnings;

my @os_distro = get_os_distro();

print join(", ", @os_distro);

#my @platform = split(/,/, $os_distro);
#print "$platform[0],$platform[1],$platform[2],$platform[3],$platform[4],$platform[5]\n";

sub get_os_distro {

    my $OS=`uname -s`; chomp ($OS);
    my $REV=`uname -r`; chomp ($REV);
    my $MACH=`uname -m`; chomp ($MACH);
    my $ARCH;
    my $OSSTR;
    my $DIST;
    my $KERNEL;
    my $PSEUDONAME;
        
    if ( $OS eq 'SunOS' ) {
            $OS='Solaris';
            $ARCH=`uname -p`;
            $OSSTR= "$OS,$REV,$ARCH," . `uname -v`;
    } elsif ( $OS eq "AIX" ) {
            $OSSTR= "$OS," . `oslevel` . "," . `oslevel -r`;
    } elsif ( $OS eq "Linux" ) {
            $KERNEL=`uname -r`;
            if ( -e '/etc/redhat-release' ) {
            my $relfile = `cat /etc/redhat-release`;
            my @fields  = split(/ /, $relfile);
                    $DIST = $fields[0];
                    $REV = $fields[2];
                    $PSEUDONAME = $fields[3];
                    $PSEUDONAME =~ s/\(//; $PSEUDONAME =~ s/\)//;
        } elsif ( -e '/etc/SuSE-release' ) {
                    $DIST=`cat /etc/SuSE-release | tr "\n" ' '| sed s/VERSION.*//`;
                    $REV=`cat /etc/SuSE-release | tr "\n" ' ' | sed s/.*=\ //`;
            } elsif ( -e '/etc/mandrake-release' ) {
                    $DIST='Mandrake';
                    $PSEUDONAME=`cat /etc/mandrake-release | sed s/.*\(// | sed s/\)//`;
                    $REV=`cat /etc/mandrake-release | sed s/.*release\ // | sed s/\ .*//`;
            } elsif ( -e '/etc/lsb-release' ) {
                    $DIST= `cat /etc/lsb-release | grep DISTRIB_ID | sed 's/DISTRIB_ID=//'`; 
                    $REV = `cat /etc/lsb-release | grep DISTRIB_RELEASE | sed 's/DISTRIB_RELEASE=//'`;
                    $PSEUDONAME = `cat /etc/lsb-release | grep DISTRIB_CODENAME | sed 's/DISTRIB_CODENAME=//'`;
            } elsif ( -e '/etc/debian_version' ) {
                    $DIST= "Debian"; 
                    $REV=`cat /etc/debian_version`;
                    $PSEUDONAME = `LANG=C lsb_release -a 2> /dev/null | grep Codename | sed 's/Codename:\\s*//'`;
        }
            if ( -e '/etc/UnitedLinux-release' ) {
                    $DIST=$DIST . " [" . `cat /etc/UnitedLinux-release | tr "\n" ' ' | sed s/VERSION.*//` . "]";
            }
        chomp ($KERNEL); chomp ($DIST); chomp ($PSEUDONAME); chomp ($REV);
            $OSSTR="$OS,$DIST,$REV,$PSEUDONAME,$KERNEL,$MACH";
    } elsif ( $OS eq "FreeBSD" ) {
            $DIST= "FreeBSD";
        $REV =~ s/-RELEASE//;
            $OSSTR="$OS,$DIST,$REV,$PSEUDONAME,$KERNEL,$MACH";
    } elsif ( $OS eq "OpenBSD" ) {
            $DIST= "OpenBSD";
        $REV =~ s/-RELEASE//;
            $OSSTR="$OS,$DIST,$REV,$PSEUDONAME,$KERNEL,$MACH";
    }
return $OSSTR;
}
EOF
}


1;
