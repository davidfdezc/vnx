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
    autoconfigure_android
	get_code_of_get_os_distro
	);

use VNX::Execution;
use VNX::FileChecks;
use VNX::Globals;
use VNX::DocumentChecks;
use VNX::TextManipulation;


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
                     "--        Change 'exe_host_cmd' config value in [general] section of /etc/vnc.conf file).");
            return $num_host_execs
        }
            
        my $type = $exec->getAttribute("type");

        # Case 1. Verbatim type
        if ( $type eq "verbatim" ) {

            # To include the command "as is"
            $execution->execute( $logp,  text_tag_multiline($exec) );
            $num_host_execs++;
        }

        # Case 2. File type
        elsif ( $type eq "file" ) {

            # We open file and write commands line by line
            my $include_file = do_path_expansion( text_tag($exec) );
            open INCLUDE_FILE, "$include_file"
              or $execution->smartdie("can not open $include_file: $!");
            while (<INCLUDE_FILE>) {
                chomp;
                $execution->execute( $logp, $_);
            }
            close INCLUDE_FILE;
            $num_host_execs++;
        }

        # Other case. Don't do anything (it would be an error in the XML!)
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

	my $command;
	my $exeLine;
	
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
	
	if ($con_id != 0) {
		my $console_term=&get_conf_value ($vnxConfigFile, 'general', 'console_term', 'root');
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
	}
    wlog (VVV, "exeLine=$exeLine", $logp);
	unless (defined($getLineOnly)) {
        $execution->execute_root($logp, $exeLine .  ">/dev/null 2>&1 &");
		#$execution->execute( $logp, $exeLine .  ">/dev/null 2>&1 &");
	}
	my $win_cfg = get_console_win_info($vm_name, $con_id);
	if (defined($win_cfg)) {
		# Wait for window to be ready
		my $win_str;
		if ($con_id == 0) {
			$win_str = "$vm_name.*- Virt Viewer"
		} else {
            $win_str = "$vm_name.*- console"
		}
		my $timeout = 5;
		while (! `wmctrl -l | grep "$win_str"`) {
            print ".";
			sleep 1;
			$timeout--;
			unless ($timeout) { 
				wlog (V, "time out waiting for console window to be ready ($vm_name, $con_id)", $logp);
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
    my $win_pos; 
    my $desktop;
    my $on_top;
    my $status;
	
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
            wlog (V, "win_cfg def values -> con_id=$con_id - win_pos_def=$win_pos_def:desktop_def=$desktop_def:on_top_def=$on_top_def:status=$status", $logp)
        }

        # Get values specified for this VM
        my @vms;
        if ( $doc->exists("/vnx_cfg/vm[\@name='$vm_name' and \@id='$con_id']") ) {
            # load specific values for this VM and console id 
            @vms = $doc->findnodes("/vnx_cfg/vm[\@name='$vm_name' and \@id='$con_id']");
        } elsif ( $doc->exists("/vnx_cfg/vm[\@name='$vm_name']") ) {
            # load specific values for this VM but generc for any console id 
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


#
# autoconfigure for Ubuntu/Debian
#
sub autoconfigure_debian_ubuntu {
    
    my $dom         = shift; # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $os_type     = shift; # ubuntu or debian
    my $error;
    
    my $logp = "autoconfigure_debian_ubuntu> ";

    wlog (VVV, "rootfs_mdir=$rootfs_mdir", $logp);
    
    # Big danger if rootfs mount directory ($rootfs_mdir) is empty: 
    # host files will be modified instead of rootfs image ones
    unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' && $rootfs_mdir ne '/' ) {
        die;
    }    

    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # Files modified
    my $interfaces_file = "$rootfs_mdir" . "/etc/network/interfaces";
    my $sysctl_file     = "$rootfs_mdir" . "/etc/sysctl.conf";
    my $hosts_file      = "$rootfs_mdir" . "/etc/hosts";
    my $hostname_file   = "$rootfs_mdir" . "/etc/hostname";
    my $resolv_file     = "$rootfs_mdir" . "/etc/resolv.conf";
    my $rules_file      = "$rootfs_mdir" . "/etc/udev/rules.d/70-persistent-net.rules";
    
    # Backup and delete /etc/resolv.conf file
    if (-f $resolv_file ) {
        system "cp $resolv_file ${resolv_file}.bak";
        system "rm -f $resolv_file";
    }
        
    # before the loop, backup /etc/udev/...70
    # and /etc/network/interfaces
    # and erase their contents
    wlog (VVV, "   configuring $rules_file and $interfaces_file...", $logp);
    if (-f $rules_file) {
        system "cp $rules_file $rules_file.backup";
    }
    system "echo \"\" > $rules_file";
    open RULES, ">" . $rules_file or return "error opening $rules_file";
    system "cp $interfaces_file $interfaces_file.backup";
    system "echo \"\" > $interfaces_file";
    open INTERFACES, ">" . $interfaces_file or return "error opening $interfaces_file";

    print INTERFACES "\n";
    print INTERFACES "auto lo\n";
    print INTERFACES "iface lo inet loopback\n";

    # Network routes configuration: we read all <route> tags
    # and store the ip route configuration commands in @ip_routes
    my @ipv4_routes;       # Stores the IPv4 route configuration lines
    my @ipv4_routes_gws;   # Stores the IPv4 gateways of each route
    my @ipv6_routes;       # Stores the IPv6 route configuration lines
    my @ipv6_routes_gws;   # Stores the IPv6 gateways of each route
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ($route_type eq 'ipv4') {
            if ($route eq 'default') {
                #push (@ipv4_routes, "   up route add -net default gw " . $route_gw . "\n");
                push (@ipv4_routes, "   up ip -4 route add default via " . $route_gw . "\n");
            } else {
                #push (@ipv4_routes, "   up route add -net $route gw " . $route_gw . "\n");
                push (@ipv4_routes, "   up ip -4 route add $route via " . $route_gw . "\n");
            }
            push (@ipv4_routes_gws, $route_gw);
        } elsif ($route_type eq 'ipv6') {
            if ($route eq 'default') {
                #push (@ipv6_routes, "   up route -A inet6 add default gw " . $route_gw . "\n");
                push (@ipv6_routes, "   up ip -6 route add default via " . $route_gw . "\n");
            } else {
                #push (@ipv6_routes, "   up route -A inet6 add $route gw " . $route_gw . "\n");
                push (@ipv6_routes, "   up ip -6 route add $route via " . $route_gw . "\n");
            }
            push (@ipv6_routes_gws, $route_gw);
        }
    }   

    # Network interfaces configuration: <if> tags
    my @if_list = $vm->getElementsByTagName("if");
    for (my $j = 0 ; $j < @if_list; $j++){
        my $if  = $if_list[$j];
        my $id  = $if->getAttribute("id");
        my $net = $if->getAttribute("net");
        my $mac = $if->getAttribute("mac");
        $mac =~ s/,//g;

        my $if_name;
        # Special cases: loopback interface and management
        if ( !defined($net) && $id == 0 ) {
        	$if_name = "eth" . $id;
        } elsif ( $net eq "lo" ) {
            $if_name = "lo:" . $id;
        } else {
            $if_name = "eth" . $id;
        }

        print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac .  "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $if_name . "\"\n\n";
        #print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";
        print INTERFACES "\nauto " . $if_name . "\n";

        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");
        my @ipv4_addr_list;
        my @ipv4_mask_list;
        my @ipv6_addr_list;
        my @ipv6_mask_list;

        if ( (@ipv4_tag_list == 0 ) && ( @ipv6_tag_list == 0 ) ) {
            # No addresses configured for the interface. We include the following commands to 
            # have the interface active on start
            if ( $net eq "lo" ) {
	            print INTERFACES "iface " . $if_name . " inet static\n";
            } else {
                print INTERFACES "iface " . $if_name . " inet manual\n";
            }
            print INTERFACES "  up ifconfig " . $if_name . " 0.0.0.0 up\n";
        } else {
            # Config IPv4 addresses
            for ( my $j = 0 ; $j < @ipv4_tag_list ; $j++ ) {

                my $ipv4 = $ipv4_tag_list[$j];
                my $mask = $ipv4->getAttribute("mask");
                my $ip   = $ipv4->getFirstChild->getData;

                if ($ip eq 'dhcp') {
                    print INTERFACES "iface " . $if_name . " inet dhcp\n";                	
                } else {
	                if ($j == 0) {
                        print INTERFACES "iface " . $if_name . " inet static\n";
	                    print INTERFACES "   address " . $ip . "\n";
	                    print INTERFACES "   netmask " . $mask . "\n";
	                } else {
	                    print INTERFACES "   up /sbin/ifconfig " . $if_name . " inet add " . $ip . " netmask " . $mask . "\n";
	                }
	                push (@ipv4_addr_list, $ip);
	                push (@ipv4_mask_list, $mask);
                }
            }
            # Config IPv6 addresses
            for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

                my $ipv6 = $ipv6_tag_list[$j];
                my $ip   = $ipv6->getFirstChild->getData;
                my $mask = $ip;
                $mask =~ s/.*\///;
                $ip =~ s/\/.*//;

                if ($ip eq 'dhcp') {
                        print INTERFACES "iface " . $if_name . " inet6 dhcp\n";                  
                } else {
	                if ($j == 0) {
                        print INTERFACES "iface " . $if_name . " inet6 static\n";
	                    print INTERFACES "   address " . $ip . "\n";
	                    print INTERFACES "   netmask " . $mask . "\n";
	                } else {
	                    print INTERFACES "   up /sbin/ifconfig " . $if_name . " inet6 add " . $ip . "/" . $mask . "\n";
	                }
	                push (@ipv6_addr_list, $ip);
	                push (@ipv6_mask_list, $mask);
                }
            }

            #
            # Include in the interface configuration the routes that point to it
            #
            # IPv4 routes
            for (my $i = 0 ; $i < @ipv4_routes ; $i++){
                my $route = $ipv4_routes[$i];
                chomp($route); 
                for (my $j = 0 ; $j < @ipv4_addr_list ; $j++) {
                    my $ipv4_route_gw = new NetAddr::IP $ipv4_routes_gws[$i];
                    if ($ipv4_route_gw->within(new NetAddr::IP $ipv4_addr_list[$j], $ipv4_mask_list[$j])) {
                        print INTERFACES $route . "\n";
                    }
                }
            }           
            # IPv6 routes
            for (my $i = 0 ; $i < @ipv6_routes ; $i++){
                my $route = $ipv6_routes[$i];
                chomp($route); 
                for (my $j = 0 ; $j < @ipv6_addr_list ; $j++) {
                    my $ipv6_route_gw = new NetAddr::IP $ipv6_routes_gws[$i];
                    if ($ipv6_route_gw->within(new NetAddr::IP $ipv6_addr_list[$j], $ipv6_mask_list[$j])) {
                        print INTERFACES $route . "\n";
                    }
                }
            }           
        }
    }
        
    close RULES;
    close INTERFACES;
        
    # Packet forwarding: <forwarding> tag
    my $ipv4_forwarding = 0;
    my $ipv6_forwarding = 0;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    for (my $j = 0 ; $j < @forwarding_list ; $j++){
        my $forwarding = $forwarding_list[$j];
        my $forwarding_type = $forwarding->getAttribute("type");
        if ($forwarding_type eq "ip"){
            $ipv4_forwarding = 1;
            $ipv6_forwarding = 1;
        } elsif ($forwarding_type eq "ipv4"){
            $ipv4_forwarding = 1;
        } elsif ($forwarding_type eq "ipv6"){
            $ipv6_forwarding = 1;
        }
    }
    wlog (VVV, "   configuring ipv4 ($ipv4_forwarding) and ipv6 ($ipv6_forwarding) forwarding in $sysctl_file...", $logp);
    system "echo >> $sysctl_file ";
    system "echo '# Configured by VNX' >> $sysctl_file ";
    system "echo 'net.ipv4.ip_forward=$ipv4_forwarding' >> $sysctl_file ";
    system "echo 'net.ipv6.conf.all.forwarding=$ipv6_forwarding' >> $sysctl_file ";

    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file", $logp);
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '1i127.0.0.1  localhost.localdomain   localhost' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change /etc/hostname
    system "echo $vm_name > $hostname_file";

    return $error;
    
}


#
# autoconfigure for Redhat (Fedora and CentOS)             
#
sub autoconfigure_redhat {

    my $dom = shift;         # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $os_type = shift; # fedora or centos
    my $error;

    my $logp = "autoconfigure_redhat ($os_type)> ";

    # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
    # host files will be modified instead of rootfs image ones
    unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' && $rootfs_mdir ne '/' ) {
        die;
    }    
        
    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # Files modified
    my $sysctl_file     = "$rootfs_mdir" . "/etc/sysctl.conf";
    my $hosts_file      = "$rootfs_mdir" . "/etc/hosts";
    my $hostname_file   = "$rootfs_mdir" . "/etc/hostname";
    my $resolv_file     = "$rootfs_mdir" . "/etc/resolv.conf";
    my $rules_file      = "$rootfs_mdir" . "/etc/udev/rules.d/70-persistent-net.rules";
    my $sysconfnet_file = "$rootfs_mdir" . "/etc/sysconfig/network";
    my $sysconfnet_dir  = "$rootfs_mdir" . "/etc/sysconfig/network-scripts";

    # Delete /etc/resolv.conf file
    if (-f $resolv_file ) {
        system "cp $resolv_file ${resolv_file}.bak";
        system "rm -f $resolv_file";
    }

    system "mv $sysconfnet_file ${sysconfnet_file}.bak";
    system "cat ${sysconfnet_file}.bak | grep -v 'NETWORKING=' | grep -v 'NETWORKING_IPv6=' > $sysconfnet_file";
    system "echo NETWORKING=yes >> $sysconfnet_file";
    system "echo NETWORKING_IPV6=yes >> $sysconfnet_file";

    if (-f $rules_file) {
        system "cp $rules_file $rules_file.backup";
    }
    system "echo \"\" > $rules_file";

    wlog (VVV, "   configuring $rules_file...", $logp);
    open RULES, ">" . $rules_file or return "error opening $rules_file";

    # Delete ifcfg and route files
    system "rm -f $sysconfnet_dir/ifcfg-Auto_eth*"; 
    system "rm -f $sysconfnet_dir/ifcfg-eth*"; 
    system "rm -f $sysconfnet_dir/route-Auto*"; 
    system "rm -f $sysconfnet_dir/route6-Auto*"; 
        
    # Network interfaces configuration: <if> tags
    my @if_list = $vm->getElementsByTagName("if");
    my $first_ipv4_if;
    my $first_ipv6_if;
        
    for (my $i = 0 ; $i < @if_list ; $i++){
        my $if  = $if_list[$i];
        my $id  = $if->getAttribute("id");
        my $net = str($if->getAttribute("net"));
        my $mac = $if->getAttribute("mac");
        $mac =~ s/,//g;
            
        wlog (VVV, "Processing if $id, net=" . str($net) . ", mac=$mac", $logp);            

        my $if_name;
        # Special cases: loopback interface and management
        if ( !defined($net) && $id == 0 ) {
            $if_name = "eth" . $id;
        } elsif ( $net eq "lo" ) {
            $if_name = "lo:" . $id;
        } else {
            $if_name = "eth" . $id;
        }
            
        if ($os_type eq 'fedora') { 
            print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac .  "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $if_name . "\"\n\n";
            #print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";

        } elsif ($os_type eq 'centos') { 
#           print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"" . $if_name . "\"\n\n";
        }

        my $if_file;
        if ($os_type eq 'fedora') { 
            $if_file = "$sysconfnet_dir/ifcfg-Auto_$if_name";
        } elsif ($os_type eq 'centos') {  
            $if_file = "$sysconfnet_dir/ifcfg-$if_name";
        }
        system "echo \"\" > $if_file";
        open IF_FILE, ">" . $if_file or return "error opening $if_file";
    
        if ($os_type eq 'CentOS' || $net eq "lo") { 
            print IF_FILE "DEVICE=$if_name\n";
        }
        if ( $net ne "lo" ) {
            print IF_FILE "HWADDR=$mac\n";
        }
        print IF_FILE "TYPE=Ethernet\n";
        print IF_FILE "BOOTPROTO=none\n";
        print IF_FILE "ONBOOT=yes\n";
        if ($os_type eq 'fedora') { 
            print IF_FILE "NAME=\"Auto $if_name\"\n";
        } elsif ($os_type eq 'centos') { 
            print IF_FILE "NAME=\"$if_name\"\n";
        }
        if ( $net eq "lo" ) {
            print IF_FILE "NM_CONTROLLED=no\n";
        }

        print IF_FILE "IPV6INIT=yes\n";
            
        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");

        # Config IPv4 addresses
        for ( my $j = 0 ; $j < @ipv4_tag_list ; $j++ ) {

            my $ipv4 = $ipv4_tag_list[$j];
            my $mask = $ipv4->getAttribute("mask");
            my $ip   = $ipv4->getFirstChild->getData;

            $first_ipv4_if = "$if_name" unless defined($first_ipv4_if); 

            if ($j == 0) {
                print IF_FILE "IPADDR=$ip\n";
                print IF_FILE "NETMASK=$mask\n";
            } else {
                my $num = $j+1;
                print IF_FILE "IPADDR$num=$ip\n";
                print IF_FILE "NETMASK$num=$mask\n";
            }
        }
        # Config IPv6 addresses
        my $ipv6secs;
        for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

            my $ipv6 = $ipv6_tag_list[$j];
            my $ip   = $ipv6->getFirstChild->getData;

            $first_ipv6_if = "$if_name" unless defined($first_ipv6_if); 

            if ($j == 0) {
                print IF_FILE "IPV6_AUTOCONF=no\n";
                print IF_FILE "IPV6ADDR=$ip\n";
            } else {
                $ipv6secs .= " $ip" if $ipv6secs ne '';
                $ipv6secs .= "$ip" if $ipv6secs eq '';
            }
        }
        if (defined($ipv6secs)) {
            print IF_FILE "IPV6ADDR_SECONDARIES=\"$ipv6secs\"\n";
        }
        close IF_FILE;
    }
    close RULES;

    # Network routes configuration: <route> tags
    if (defined($first_ipv4_if)) {
        my $route4_file = "$sysconfnet_dir/route-Auto_$first_ipv4_if";
        system "echo \"\" > $route4_file";
        open ROUTE_FILE, ">" . $route4_file or return "error opening $route4_file";
    }
    if (defined($first_ipv6_if)) {
        my $route6_file = "$sysconfnet_dir/route6-Auto_$first_ipv6_if";
        system "echo \"\" > $route6_file";
        open ROUTE6_FILE, ">" . $route6_file or return "error opening $route6_file";
    }
            
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list ; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ( $route_type eq 'ipv4' && defined($first_ipv4_if) ) {
            if ($route eq 'default') {
                #print ROUTE_FILE "ADDRESS$j=0.0.0.0\n";
                #print ROUTE_FILE "NETMASK$j=0\n";
                #print ROUTE_FILE "GATEWAY$j=$route_gw\n";
                # Define the default route in $sysconfnet_file
                system "echo GATEWAY=$route_gw >> $sysconfnet_file"; 
            } else {
                my $mask = $route;
                $mask =~ s/.*\///;
                $mask = cidr_to_mask ($mask);
                $route =~ s/\/.*//;
                print ROUTE_FILE "ADDRESS$j=$route\n";
                print ROUTE_FILE "NETMASK$j=$mask\n";
                print ROUTE_FILE "GATEWAY$j=$route_gw\n";
            }
        } elsif ($route_type eq 'ipv6' && defined($first_ipv6_if) ) {
            if ($route eq 'default') {
                print ROUTE6_FILE "2000::/3 via $route_gw metric 0\n";
            } else {
                print ROUTE6_FILE "$route via $route_gw metric 0\n";
            }
        }
    }
    close ROUTE_FILE  if defined($first_ipv4_if);
    close ROUTE6_FILE if defined($first_ipv6_if);
        
    # Packet forwarding: <forwarding> tag
    my $ipv4_forwarding = 0;
    my $ipv6_forwarding = 0;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    for (my $j = 0 ; $j < @forwarding_list ; $j++){
        my $forwarding = $forwarding_list[$j];
        my $forwarding_type = $forwarding->getAttribute("type");
        if ($forwarding_type eq "ip"){
            $ipv4_forwarding = 1;
            $ipv6_forwarding = 1;
        } elsif ($forwarding_type eq "ipv4"){
            $ipv4_forwarding = 1;
        } elsif ($forwarding_type eq "ipv6"){
            $ipv6_forwarding = 1;
        }
    }
    wlog (VVV, "   configuring ipv4 ($ipv4_forwarding) and ipv6 ($ipv6_forwarding) forwarding in $sysctl_file...", $logp);
    system "echo >> $sysctl_file ";
    system "echo '# Configured by VNX' >> $sysctl_file ";
    system "echo 'net.ipv4.ip_forward=$ipv4_forwarding' >> $sysctl_file ";
    system "echo 'net.ipv6.conf.all.forwarding=$ipv6_forwarding' >> $sysctl_file ";

    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file", $logp);
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '1i127.0.0.1  localhost.localdomain   localhost' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change /etc/hostname
    system "echo $vm_name > $hostname_file";

    #system "hostname $vm_name";
    system "mv $sysconfnet_file ${sysconfnet_file}.bak";
    system "cat ${sysconfnet_file}.bak | grep -v HOSTNAME > $sysconfnet_file";
    system "echo HOSTNAME=$vm_name >> $sysconfnet_file";

    return $error;    
}

#
# autoconfigure for FreeBSD             
#
sub autoconfigure_freebsd {

    my $dom = shift;         # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $error;

    my $logp = "autoconfigure_freebsd> ";

    # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
    # host files will be modified instead of rootfs image ones
    unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' && $rootfs_mdir ne '/' ) {
        die;
    }    

    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # IF prefix names assigned to interfaces  
    my $IF_MGMT_PREFIX="re";    # type rtl8139 for management if    
    my $IF_PREFIX="em";         # type e1000 for the rest of ifs   
    
    # Files to modify
    my $hosts_file      = "$rootfs_mdir" . "/etc/hosts";
    my $hostname_file   = "$rootfs_mdir" . "/etc/hostname";
    my $rc_file         = "$rootfs_mdir" . "/etc/rc.conf";

    # before the loop, backup /etc/rc.conf
    wlog (VVV, "   configuring /etc/rc.conf...", $logp);
    system "cp $rc_file $rc_file.backup";

    open RC, ">>" . $rc_file or return "error opening $rc_file";

    chomp (my $now = `date`);

    print RC "\n";
    print RC "#\n";
    print RC "# VNX Autoconfiguration commands ($now)\n";
    print RC "#\n";
    print RC "\n";

    print RC "hostname=\"$vm_name\"\n";
    print RC "sendmail_enable=\"NONE\"\n"; #avoids some startup errors

    # Network interfaces configuration: <if> tags
    my @if_list = $vm->getElementsByTagName("if");
    my $k = 0; # Index to the next $IF_PREFIX interface to be used
    for (my $i = 0 ; $i < @if_list; $i++){
        my $if = $if_list[$i];
        my $id    = $if->getAttribute("id");
        my $net   = $if->getAttribute("net");
        my $mac   = $if->getAttribute("mac");
        $mac =~ s/,//g; 
        
        # IF names
        my $if_orig_name;
        my $if_new_name;
        if ($id eq 0) { # Management interface 
            $if_orig_name = $IF_MGMT_PREFIX . "0";    
            $if_new_name = "eth0";
        } else { 
            my $if_num = $k;
            $k++;
            $if_orig_name = $IF_PREFIX . $if_num;    
            $if_new_name = "eth" . $id;
        }

        print RC "ifconfig_" . $if_orig_name . "_name=\"" . $if_new_name . "\"\n";
    
        my $alias_num=-1;
                
        # IPv4 addresses
        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        for ( my $j = 0 ; $j < @ipv4_tag_list ; $j++ ) {

            my $ipv4 = $ipv4_tag_list[$j];
            my $mask = $ipv4->getAttribute("mask");
            my $ip   = $ipv4->getFirstChild->getData;

            if ($alias_num == -1) {
                print RC "ifconfig_" . $if_new_name . "=\"inet " . $ip . " netmask " . $mask . "\"\n";
            } else {
                print RC "ifconfig_" . $if_new_name . "_alias" . $alias_num . "=\"inet " . $ip . " netmask " . $mask . "\"\n";
            }
            $alias_num++;
        }

        # IPv6 addresses
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");
        for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

            my $ipv6 = $ipv6_tag_list[$j];
            my $ip   = $ipv6->getFirstChild->getData;
            my $mask = $ip;
            $mask =~ s/.*\///;
            $ip =~ s/\/.*//;

            if ($alias_num == -1) {
                print RC "ifconfig_" . $if_new_name . "=\"inet6 " . $ip . " prefixlen " . $mask . "\"\n";
            } else {
                print RC "ifconfig_" . $if_new_name . "_alias" . $alias_num . "=\"inet6 " . $ip . " prefixlen " . $mask . "\"\n";
            }
            $alias_num++;
        }
    }
        
    # Network routes configuration: <route> tags
    # Example content:
    #     static_routes="r1 r2"
    #     ipv6_static_routes="r3 r4"
    #     default_router="10.0.1.2"
    #     route_r1="-net 10.1.1.0/24 10.0.0.3"
    #     route_r2="-net 10.1.2.0/24 10.0.0.3"
    #     ipv6_default_router="2001:db8:1::1"
    #     ipv6_route_r3="2001:db8:7::/3 2001:db8::2"
    #     ipv6_route_r4="2001:db8:8::/64 2001:db8::2"
    my @route_list = $vm->getElementsByTagName("route");
    my @routeCfg;           # Stores the route_* lines 
    my $static_routes;      # Stores the names of the ipv4 routes
    my $ipv6_static_routes; # Stores the names of the ipv6 routes
    my $i = 1;
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag = $route_list[$j];
        if (defined($route_tag)){
            my $route_type = $route_tag->getAttribute("type");
            my $route_gw   = $route_tag->getAttribute("gw");
            my $route      = $route_tag->getFirstChild->getData;

            if ($route_type eq 'ipv4') {
                if ($route eq 'default'){
                    push (@routeCfg, "default_router=\"$route_gw\"\n");
                } else {
                    push (@routeCfg, "route_r$i=\"-net $route $route_gw\"\n");
                    $static_routes = ($static_routes eq '') ? "r$i" : "$static_routes r$i";
                    $i++;
                }
            } elsif ($route_type eq 'ipv6') {
                if ($route eq 'default'){
                    push (@routeCfg, "ipv6_default_router=\"$route_gw\"\n");
                } else {
                    push (@routeCfg, "ipv6_route_r$i=\"$route $route_gw\"\n");
                    $ipv6_static_routes = ($ipv6_static_routes eq '') ? "r$i" : "$ipv6_static_routes r$i";
                    $i++;                   
                }
            }
        }
    }
    unshift (@routeCfg, "ipv6_static_routes=\"$ipv6_static_routes\"\n");
    unshift (@routeCfg, "static_routes=\"$static_routes\"\n");
    print RC @routeCfg;

    # Packet forwarding: <forwarding> tag
    my $ipv4_forwarding = 0;
    my $ipv6_forwarding = 0;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    for (my $j = 0 ; $j < @forwarding_list ; $j++){
        my $forwarding   = $forwarding_list[$j];
        my $forwarding_type = $forwarding->getAttribute("type");
        if ($forwarding_type eq "ip"){
            $ipv4_forwarding = 1;
            $ipv6_forwarding = 1;
        } elsif ($forwarding_type eq "ipv4"){
            $ipv4_forwarding = 1;
        } elsif ($forwarding_type eq "ipv6"){
            $ipv6_forwarding = 1;
        }
    }
    if ($ipv4_forwarding == 1) {
        wlog (VVV, "   configuring ipv4 forwarding...", $logp);
        print RC "gateway_enable=\"YES\"\n";
    }
    if ($ipv6_forwarding == 1) {
        wlog (VVV, "   configuring ipv6 forwarding...", $logp);
        print RC "ipv6_gateway_enable=\"YES\"\n";
    }

    close RC;
       
    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file", $logp);
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '1i127.0.0.1  localhost.localdomain   localhost' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change /etc/hostname
    system "echo $vm_name > $hostname_file";

    return $error;            
}

#
# autoconfigure for Android
#
sub autoconfigure_android {
    
    my $dom         = shift; # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $os_type     = shift; # ubuntu or debian
    my $error;
    
    my $logp = "autoconfigure_android> ";

    wlog (VVV, "rootfs_mdir=$rootfs_mdir", $logp);
    
    # Big danger if rootfs mount directory ($rootfs_mdir) is empty: 
    # host files will be modified instead of rootfs image ones
    unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' && $rootfs_mdir ne '/' ) {
        die;
    }    

    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # Files modified
    my $sysctl_file     = "$rootfs_mdir" . "/system/etc/sysctl.conf";
    my $build_prop_file = "$rootfs_mdir" . "/system/build.prop";
    my $init_sh         = "$rootfs_mdir" . "/system/etc/init.sh";
    my $hosts_file      = "$rootfs_mdir" . "/system/etc/hosts";
    
        
    # Network routes configuration: we read all <route> tags
    # and store the ip route configuration commands in @ip_routes
    my @ipv4_routes;       # Stores the IPv4 route configuration lines
    my @ipv4_routes_gws;   # Stores the IPv4 gateways of each route
    my @ipv6_routes;       # Stores the IPv6 route configuration lines
    my @ipv6_routes_gws;   # Stores the IPv6 gateways of each route
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ($route_type eq 'ipv4') {
            if ($route eq 'default') {
                push (@ipv4_routes, "ip route add default via " . $route_gw . "\n");
            } else {
                push (@ipv4_routes, "ip route add $route via " . $route_gw . "\n");
            }
            push (@ipv4_routes_gws, $route_gw);
        } elsif ($route_type eq 'ipv6') {
            if ($route eq 'default') {
                push (@ipv6_routes, "route -A inet6 add default gw " . $route_gw . "\n");
            } else {
                push (@ipv6_routes, "   up route -A inet6 add $route gw " . $route_gw . "\n");
            }
            push (@ipv6_routes_gws, $route_gw);
        }
    }   

    # Network interfaces configuration: <if> tags
    my @ipv4_ifs;       # Stores the IPv4 interfaces configuration lines
    my @ipv6_ifs;       # Stores the IPv6 interfaces configuration lines
    
    my @if_list = $vm->getElementsByTagName("if");
    for (my $j = 0 ; $j < @if_list; $j++){
        my $if  = $if_list[$j];
        my $id  = $if->getAttribute("id");
        my $net = $if->getAttribute("net");
        my $mac = $if->getAttribute("mac");
        $mac =~ s/,//g;

        if ($id gt 2) { next };

        my $if_name;
        # Special cases: loopback interface and management
#        if ( !defined($net) && $id == 0 ) {
#            $if_name = "eth" . $id;
#        } elsif ( $net eq "lo" ) {
#            $if_name = "lo:" . $id;
#        } else {
            #$if_name = "eth" . $id;
            
        if ($dh->get_vmmgmt_type eq 'net') {
            if ($id=="0") {
                $if_name = "eth1";
            } elsif ($id=="1") {
                $if_name = "eth0";
            }
        } elsif ($dh->get_vmmgmt_type eq 'private') {
            $if_name = "eth" . $id;
        } else {
            if ($id=="1") {
                $if_name = "eth1";
            } elsif ($id=="2") {
                $if_name = "eth0";
            }        	
        }

        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");
        my @ipv4_addr_list;
        my @ipv4_mask_list;
        my @ipv6_addr_list;
        my @ipv6_mask_list;

        if ( (@ipv4_tag_list == 0 ) && ( @ipv6_tag_list == 0 ) ) {
            # No addresses configured for the interface. We include the following commands to 
            # have the interface active on start
            #if ( $net eq "lo" ) {
            #    push (@ipv4_ifs, "iface " . $if_name . " inet static\n");
            #} else {
            #    push (@ipv4_ifs, "iface " . $if_name . " inet manual\n");
            #}
        } else {
            # Config IPv4 addresses
            for ( my $k = 0 ; $k < @ipv4_tag_list ; $k++ ) {

                my $ipv4 = $ipv4_tag_list[$k];
                my $mask = $ipv4->getAttribute("mask");
                my $ip   = $ipv4->getFirstChild->getData;

                if ($ip eq 'dhcp') {
                    #push (@ipv4_ifs, "netcfg " . $if_name . " dhcp\n");         
                    #push (@ipv4_ifs, "start dhcpd_${if_name}:${if_name}\n"); 
                    #push (@ipv4_ifs, "dhcpcd -LK -d ${if_name}\n");       
                    #push (@ipv4_ifs, "setprop net.dns${j} \\\`getprop dhcp.eth${j}.dns1\\\`\n");
                } else {
                	
                    push (@ipv4_ifs, "ip link set " . $if_name . " up\n");
                    push (@ipv4_ifs, "ip addr add dev " . $if_name . " $ip/$mask\n");
                    #push (@ipv4_ifs, "ifconfig " . $if_name . " $ip netmask $mask\n");
                    push (@ipv4_addr_list, $ip);
                    push (@ipv4_mask_list, $mask);
                }                
                
            }
            # Config IPv6 addresses
            for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

                my $ipv6 = $ipv6_tag_list[$j];
                my $ip   = $ipv6->getFirstChild->getData;
                my $mask = $ip;
                $mask =~ s/.*\///;
                $ip =~ s/\/.*//;

                if ($ip eq 'dhcp') {
                    push (@ipv4_ifs, "netcfg " . $if_name . " dhcp\n"); # TODO: investigate command...                  
                } else {
                	push (@ipv6_ifs, "ifconfig " . $if_name . " $ip netmask $mask\n");
                    push (@ipv6_addr_list, $ip);
                    push (@ipv6_mask_list, $mask);
                }
            }

        }
    }
        
    # Packet forwarding: <forwarding> tag
    my $ipv4_forwarding = 0;
    my $ipv6_forwarding = 0;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    for (my $j = 0 ; $j < @forwarding_list ; $j++){
        my $forwarding = $forwarding_list[$j];
        my $forwarding_type = $forwarding->getAttribute("type");
        if ($forwarding_type eq "ip"){
            $ipv4_forwarding = 1;
            $ipv6_forwarding = 1;
        } elsif ($forwarding_type eq "ipv4"){
            $ipv4_forwarding = 1;
        } elsif ($forwarding_type eq "ipv6"){
            $ipv6_forwarding = 1;
        }
    }
    wlog (VVV, "   configuring ipv4 ($ipv4_forwarding) and ipv6 ($ipv6_forwarding) forwarding in $sysctl_file...", $logp);
    system "echo >> $sysctl_file ";
    system "echo '# Configured by VNX' >> $sysctl_file ";
    system "echo 'net.ipv4.ip_forward=$ipv4_forwarding' >> $sysctl_file ";
    system "echo 'net.ipv6.conf.all.forwarding=$ipv6_forwarding' >> $sysctl_file ";
    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $build_prop_file", $logp);
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "echo \"127.0.0.1  localhost $vm_name\" >> $hosts_file";
    # Insert the new 127.0.0.1 line
    #system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change hostname in /system/build.prop
    system "echo \"net.hostname=$vm_name\" >> $build_prop_file";

    # Configuring init.sh
    foreach my $if (@ipv4_ifs) {
    	print $if;
        system "echo \"$if\" >> $init_sh";
    }
    foreach my $if (@ipv6_ifs) {
        system "echo \"$if\" >> $init_sh";
    }
    foreach my $route (@ipv4_routes) {
        system "echo \"$route\" >> $init_sh";
    }
    foreach my $route (@ipv6_routes) {
        system "echo \"$route\" >> $init_sh";
    }
    system "sed -i -e 's/return 0//' $init_sh";
    system "echo \"return 0\" >> $init_sh";
    return $error;
    
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
    }
return $OSSTR;
}
EOF
}


1;