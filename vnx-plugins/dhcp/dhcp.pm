# dhcp.pm
#
# This file is a plugin of VNX package.
#
# Authors: Jorge Somavilla, Miguel Ferrer, Francisco José Martín (VNUML version, 2009)
#          David Fernández (VNX version, 2011)
# Coordinated by: David Fernández (david@dit.upm.es)
#
# Copyright (C) 2011,   DIT-UPM
#           Departamento de Ingenieria de Sistemas Telematicos
#           Universidad Politecnica de Madrid
#           SPAIN
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
#
package dhcp;

@ISA = qw(Exporter);
@EXPORT = qw(
  initPlugin
  getFiles
  getCommands
  getSeqDescriptions
  finalizePlugin 
);


###########################################################
# Modules to import
###########################################################
use strict;
use warnings;
use XML::LibXML;           # XML management library
use File::Basename;        # File management library
use VNX::FileChecks;       # To use get_abs_path
use VNX::CheckSemantics;   # To use validate_xml
use VNX::Globals;          # To use wlog
use VNX::Execution;        # To use wlog
use Socket;                # To resolve hostnames to IPs
use Net::Netmask;
use Switch;
use Data::Dumper;


###########################################################
# Global variables 
###########################################################

# DOM tree for Plugin Configuration File (PCF)
my $pcf_dom;

# Name of PCF main node tag (ex. ospf_conf, dhcp_conf, etc)
my $pcf_main = 'dhcp_conf';

# plugin log prompt
my $prompt='dhcp-plugin:  ';

#
# Command sequences used by DHCP plugin
#
# Used by any vm defined in PCF
my @all_seqs    = qw( on_boot start dhcp-start restart dhcp-restart stop dhcp-stop on_shutdown);
# Used by DHCP servers
my @server_seqs = qw( dhcp-server-start dhcp-server-restart dhcp-server-stop dhcp-server-force-reload);
# Used by DHCP relays
my @relay_seqs  = qw( dhcp-relay-start dhcp-relay-restart dhcp-relay-stop dhcp-relay-force-reload);
# Used by DHCP clients
my @client_seqs = qw( dhcp-client-start dhcp-client-restart dhcp-client-stop);

# Command sequences help description
my %plugin_seq_help = (
'on_boot',                      'Creates DHCP config files and starts services',
'redoconf',                     'Creates DHCP config files',
'start',                        'Starts all DHCP daemons and clients',
'restart',                      'Restarts all DHCP daemons and clients',
'stop',                         'Stops all DHCP daemons and releases client configurations', 
'dhcp-start',                   'Synonym of start',
'dhcp-restart',                 'Synonym of restart',
'dhcp-stop',                    'Synonym of stop',
'on_shutdown',                  'Stops all DHCP daemons',
'dhcp-server-start',            'Starts DHCP servers',
'dhcp-server-restart',          'Restarts DHCP servers',
'dhcp-server-stop',             'Stops DHCP servers',
'dhcp-server-force-reload',     'Restarts DHCP servers using \'force-reload\'', 
'dhcp-relay-start',             'Starts DHCP relays',
'dhcp-relay-restart',           'Restarts DHCP relays',
'dhcp-relay-stop',              'Stops DHCP relays',
'dhcp-relay-force-reload',      'Restarts DHCP relays using \'force-reload\'',
'dhcp-client-start',            'Executes DHCP clients',
'dhcp-client-restart',          'Releases client IP configurations and rexecutes DHCP clients', 
'dhcp-client-stop',             'Releases client IP configurations'
);



###########################################################
# Plugin functions
###########################################################

#
# initPlugin
#
# initPlugin function is called by VNX code for every plugin declared with an <extension> tag
# in the scenario. It is aimed to do plugin specific initialization tasks, for example, 
# the validation of the plugin configuration file (PCF) if it is used. If an error is returned, 
# VNX dies showing the plugin error description returned by this function. 
#
# Arguments:
# - mode, the mode in which VNX is executed. Possible values: "define", "create","execute",
#         "shutdown" or "destroy"
# - pcf, the plugin configuration file (PCF) absolut pathname (empty if configuration file 
#        has not been defined in the scenario).
#
# Returns:
# - error, an empty string if successful initialization, or a string describing the error 
#          in other cases.
#

sub initPlugin {
    
    my $self = shift;   
    my $mode = shift;
    my $conf = shift;  # Absolute filename of PCF. Empty if PCF not defined 
    
    plog (VVV, "initPlugin (mode=$mode; conf=$conf)");

    # Validate PCF with XSD language definition 
    my $error = validate_xml ($conf);
    if (! $error ) {
    	
    	my $parser = XML::LibXML->new();
        $pcf_dom = $parser->parse_file($conf);
    } 
    return $error;
}

#
# getFiles
#
# getFiles function is called once for each virtual machine defined in a scenario 
# when VNX is executed without using "-M" option, or for each virtual machine specified 
# in "-M" parameter when VNX is invoked with this option. The plugin has to return to 
# VNX the files that wants to be copied to that virtual machine for the command sequence 
# identifier passed.
#
# Arguments:
# - vm_name, the name of the virtual machine for which getFiles is being called
# - seq, the command sequence identifier. The value passed is: 'on_boot', when VNX invoked 
#        in create mode; 'on_shutdown' when shutdown mode; and the value defined in "-x|execute" 
#        option when invoked in execute mode
# - files_dir, the directory where the files to be copied to the virtual machine have 
#              to be passed to VNX
#
# Returns:
# - files, an associative array (hash) containing the files to be copied to the virtual 
#          machine, the location where they have to be copied in the vm and (only for 
#          UNIX-like operating systems) the owner, group and permissions.
#
#          Notes: 
#             + the format of the 'keys' of the hash returned is:
#                  /path/filename-in-vm,owner,group,permissions
#               the owner, group and permissions are optional. The filename has to be
#               an absolut filename.
#             + the value of the 'keys' has to be a relative filename to $files_dir
#               directory
# 
sub getFiles{

    my $self      = shift;
    my $vm_name   = shift;
    my $files_dir = shift;
    my $seq       = shift;
    
    my %files;

    plog (VVV, "getFiles (vm=$vm_name, seq=$seq)");
    
    chomp( my $date = `date` );
    
    if (($seq eq "on_boot") || ($seq eq "dhcp-on_boot") || ($seq eq "redoconf")) { 
    
        foreach my $vm ($pcf_dom->findnodes("/$pcf_main/vm")) {    
            
            if ($vm->getAttribute("name") eq $vm_name){
                
                my $type = $vm->getAttribute("type");
    
                switch ($type) {
    
                    case ["dhcp3","dhcp3-isc"] {
    
                        my $etc_dir ="/etc/dhcp3/";
                        if ($type eq "dhcp3-isc") {
                            $etc_dir = "/etc/dhcp/";
                        }
    
                        # DHCP Server
                        my $server = $vm->findnodes('server')->[0];
                        if ($server) {
    
                            # open filehandle to create dhcpd.conf file
                            my $server_file = $files_dir . "/${vm_name}_server.conf";
                            open( SERVER, ">$server_file" ) or $files{"ERROR"} = "Cannot open $server_file file";
    
                            # server.conf header
                            print SERVER "#\n# server.conf file generated by dhcp.pm VNX plugin \n#   $date\n#\n\n";
                            print SERVER "ddns-update-style none;\n";
                            print SERVER "default-lease-time 120;\n";
                            print SERVER "max-lease-time 120;\n";
                            #print SERVER "log-facility local7;\n\n";
    
					        foreach my $subnet ($server->findnodes('subnet')) {
					        
                                # <network>
					            my $network = $subnet->findnodes('network')->[0];
                                my $net_block = new Net::Netmask($network->textContent());
                                            
                                my $base_ip = $net_block->base();
                                my $mask = $net_block->mask();
                                print SERVER "subnet $base_ip netmask $mask {\n";
					
                                # <range>
                                foreach my $range ($subnet->findnodes('range')) {
                                    my $first_ip = $range->findnodes('first')->[0]->textContent();
                                    my $last_ip  = $range->findnodes('last')->[0]->textContent();
                                    print SERVER "  range $first_ip $last_ip;\n";
                                }
					            
                                # <router>
                                my @routers = $subnet->findnodes('router');
                                if (scalar @routers > 0) {
                                    my $router_line = "  option routers ";
                                    foreach my $router (@routers) {
                                        $router_line .= $router->textContent() . ",";
                                    }
                                    $router_line =~ s/,$//;
                                    print SERVER $router_line . ";\n";
                                }
					
                                # <dns>
                                my @dnss = $subnet->findnodes('dns');
                                if (scalar @dnss > 0) {
                                    my $dns_line = "  option domain-name-servers ";
                                    foreach my $dns (@dnss) {
                                        $dns_line .= $dns->textContent() . ",";
                                    }
                                    $dns_line =~ s/,$//;
                                    print SERVER $dns_line . ";\n";
                                }
					
                                # <domain>
                                my $domain = $subnet->findnodes('domain')->[0];
                                if ($domain) {
                                    print SERVER "  option domain-name \"" . $domain->textContent() . "\";\n"
                                }
					
                                print SERVER "}\n\n";
					
                                foreach my $host ($subnet->findnodes('host')) {
                                    my $hostname = $host->getAttribute("name");
                                    my $hostmac  = $host->getAttribute("mac");
                                    my $hostip   = $host->getAttribute("ip");
                                    # ignore unmatching host declarations
                                    if ( $net_block->match($hostip) ) {
                                        print SERVER "host $hostname {\n  hardware ethernet $hostmac;\n  fixed-address $hostip;\n}\n\n"; 
                                    }
                                }
                            }
                            
                            close(SERVER);
                            $server_file =~ s#$files_dir/##;  # Eliminate the directory to make the filenames relative 
                            $files{"${etc_dir}dhcpd.conf,,,644"} = $server_file;
                        }
    
                        # DHCP Relay    
                        my $relay = $vm->findnodes('relay')->[0];
                        if ($relay) {
    
                            # Build file /etc/default/dhcp3-relay.conf
                            my $relay_file = $files_dir . "/${vm_name}_relay.conf";
                            open( RELAY, ">$relay_file" ) or $files{"ERROR"} = "Cannot open $relay_file file";
                            print RELAY "#\n# relay.conf file generated by dhcp.pm VNX plugin \n#   $date\n#\n\n";
                            my $servers_line = "SERVERS=\"";

                            foreach my $toserver ($relay->findnodes('toserver')) {
                                $servers_line .= $toserver->textContent() . " ";
                            }
                            $servers_line =~ s/ $//;
                            print RELAY $servers_line . "\"\n";
                            close(RELAY);
                            $relay_file =~ s#$files_dir/##;  # Eliminate the directory to make the filenames relative 
                            $files{"/etc/default/dhcp3-relay,,,644"} = $relay_file;
                        }
    
                        # DHCP Client    
                        my $client = $vm->findnodes('client')->[0];
                        if ($client) {
                            # Build file dhclient.conf
                            my $client_file = $files_dir . "/${vm_name}_client.conf";
                            open( CLIENT, ">$client_file" ) or $files{"ERROR"} = "Cannot open $client_file file";
                            print CLIENT "# Configuration file for /sbin/dhclient, which is included in Debian's dhcp3-client package.\n";
                            print CLIENT "#\n# client.conf file generated by dhcp.pm VNX plugin \n#   $date\n#\n\n";
                            print CLIENT "send host-name \"<hostname>\";\n";
                            print CLIENT "request subnet-mask, broadcast-address, time-offset, routers, domain-name, domain-name-servers, domain-search, host-name, netbios-name-servers, netbios-scope, interface-mtu;\n";
                            print CLIENT "retry 10;\n";
                            close(CLIENT);
                            $client_file =~ s#$files_dir/##;  # Eliminate the directory to make the filenames relative 
                            $files{"${etc_dir}dhclient.conf,,,644"} = $client_file;
                            
                        }
                    } else {
                       $files{"ERROR"} = "Unknown type value $type in vm $vm\n";
                    } 
                }
            
            }
        }
    }
    return %files;
          
}


#
# getCommands
#
# getCommands function is called once for each virtual machine in the scenario 
# when VNX is executed without using "-M" option, or for each virtual machine 
# specified in "-M" parameter when VNX is invoked with this option. The plugin 
# has to provide VNX the list of commands that have to be executed on that 
# virtual machine for the command sequence identifier passed.
# 
# Arguments:
# - vm_name, the name of the virtual machine for which getCommands is being called
# - seq, the command sequence identifier. The value passed is: 'on_boot', when 
#        VNX is invoked in create mode; 'on_shutdown' when shutdown mode; and 
#        the value defined in "-x" option when invoked in execute mode
# 
# Returns:
# - commands, an array containing the commands to be executed on the virtual 
#             machine. The first position of the array has to be empty if no error 
#             occurs, or contain a string describing the error in other cases
#
sub getCommands{
    
    my $self = shift;
    my $vm_name = shift;
    my $seq = shift;
    
    plog (VVV, "getCommands (vm=$vm_name, seq=$seq)");
    
    my @commands;

    unshift( @commands, "" );

    foreach my $vm ($pcf_dom->findnodes("/$pcf_main/vm")) {    
            
        if ($vm->getAttribute("name") eq $vm_name){
            
            plog (VVV, "getCommands: $vm_name found");
            my $type = $vm->getAttribute("type");
            
            switch ($type) {

                case ["dhcp3","dhcp3-isc"] {
                	
                	my $dhcp_server_cmd ="/etc/init.d/dhcp3-server";
                	my $dhcp_relay_cmd  ="/etc/init.d/dhcp3-relay";
					if ($type eq "dhcp3-isc") {
						$dhcp_server_cmd = "/etc/init.d/isc-dhcp-server";
						$dhcp_relay_cmd  = "/etc/init.d/isc-dhcp-relay";						
					}
					
                    my $server  = $vm->findnodes('server')->[0];
                    my $relay   = $vm->findnodes('relay')->[0];
                    my @clients = $vm->findnodes('client');
                   		
		            switch ($seq){

		                case ["on_boot", "start", "dhcp-start"] {    
		                    # Start server, relay and clients in the virtual machine, if any
		                    if ($server) {
		                        push( @commands, "$dhcp_server_cmd start" );
		                    }
		                    if ($relay) {
		                        push( @commands, "$dhcp_relay_cmd start" );
		                    }
		                    foreach my $client (@clients) {
                                foreach my $if ($client->findnodes('if')) {
                                    push(@commands,"dhclient ". $if->textContent());
		                        }
		                    }
		                }
		                    
		                case ["restart","dhcp-restart"] {
		                	
		                    # Restart server, relay and clients in the virtual machine, if any  
		                    if ($server) {
		                        push( @commands, "$dhcp_server_cmd restart" );
		                    }
		                    if ($relay) {
		                        push( @commands, "$dhcp_relay_cmd restart" );
		                    }
                            foreach my $client (@clients) {
                                foreach my $if ($client->findnodes('if')) {
                                    push(@commands,"dhclient -r");
                                    push(@commands,"killall dhclient");
                                    push(@commands,"dhclient " . $if->textContent());
		                        }
		                    }
		                    
		                }
		                
		                case ["stop","dhcp-stop"]{  
		                    # Stop server and relay in the virtual machine, if any
		                    if ($server) {
		                        push( @commands, "$dhcp_server_cmd stop" );
		                    }
		                    if ($relay) {
		                        push( @commands, "$dhcp_relay_cmd stop" );
		                    }
                            foreach my $client (@clients) {
                                foreach my $if ($client->findnodes('if')) {
                                    push(@commands,"dhclient -r");
                                    push(@commands,"killall dhclient");
		                        }
		                    }
		                }
		                
		                case ("dhcp-server-start"){
		                    # Start the server in the virtual machine. Return error if there isn't any. 
		                    if (! $server) {
		                        unshift( @commands, "$vm is not configured as a dhcp server. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
		                        push( @commands, "$dhcp_server_cmd start" );
		                    }
		                }
		                
		                case ("dhcp-relay-start"){
		                    # Start the relay in the virtual machine. Return error if there isn't any.
		                    if (! $relay) {
		                        unshift( @commands, "$vm is not configured as a dhcp relay. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
		                        push( @commands, "$dhcp_relay_cmd start" );
		                    }                                       
		                }
		                
		                case ("dhcp-client-start"){
		                    # Start the clients in the virtual machine. Return error if there aren't any.
		                    if (scalar @clients == 0 ) {
		                        unshift( @commands, "$vm is not configured as a dhcp client. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
                                foreach my $client (@clients) {
                                    foreach my $if ($client->findnodes('if')) {
                                        push(@commands,"dhclient " . $if->textContent());
		                            }
		                        }
		                    }
		                }
		                
		                case ("dhcp-server-restart"){
		                    # Restart the server in the virtual machine. Return error if there isn't any. 
		                    if (! $server) {
		                        unshift( @commands, "$vm is not configured as a dhcp server. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
		                        push( @commands, "$dhcp_server_cmd restart" );
		                    }
		                }
		                
		                case ("dhcp-relay-restart"){
		                    # Restart the relay in the virtual machine. Return error if there isn't any.
		                    if (! $relay == 0 ) {
		                        unshift( @commands, "$vm is not configured as a dhcp relay. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
		                        push( @commands, "$dhcp_relay_cmd restart" );
		                    }                                       
		                }
		                
		                case ("dhcp-client-restart"){
		                    # Start the clients in the virtual machine. Return error if there aren't any.
		                    if (scalar @clients == 0 ) {
		                        unshift( @commands, "$vm is not configured as a dhcp client. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
                                foreach my $client (@clients) {
                                    foreach my $if ($client->findnodes('if')) {
		                                push(@commands,"dhclient -r");
		                                push(@commands,"killall dhclient");
		                                push(@commands,"dhclient " . $if->textContent());
		                            }
		                        }
		    
		                    }
		                }
		                
		                case ("dhcp-server-stop"){
		                    # Stop the server in the virtual machine. Return error if there isn't any. 
		                    if (! $server) {
		                        unshift( @commands, "$vm is not configured as a dhcp server. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
		                        push( @commands, "$dhcp_server_cmd stop" );
		                    }
		                
		                }
		                
		                case ("dhcp-relay-stop"){
		                    # Stop the relay in the virtual machine. Return error if there isn't any. 
		                    if (! $relay) {
		                        unshift( @commands, "$vm is not configured as a dhcp relay. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
		                        push( @commands, "$dhcp_relay_cmd stop" );
		                    }
		                
		                }
		                
		                case ("dhcp-client-stop"){
		                    # Start the clients in the virtual machine. Return error if there aren't any.
                            if (scalar @clients == 0 ) {
		                        unshift( @commands, "$vm is not configured as a dhcp client. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
                                foreach my $client (@clients) {
                                    foreach my $if ($client->findnodes('if')) {
		                                push(@commands,"dhclient -r");
		                                push(@commands,"killall dhclient");
		                            }
		                        }
		    
		                    }
		                }
		                
		                case ("dhcp-server-force-reload"){
		                    # Force reload of the server in the virtual machine. Return error if there isn't any. 
		                    if (! $server) {
		                        unshift( @commands, "$vm is not configured as a dhcp server. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
		                        push( @commands, "$dhcp_server_cmd force-reload" );
		                    }
		                
		                }
		                
		                case ("dhcp-relay-force-reload"){
		                    # Force reload of the relay in the virtual machine. Return error if there isn't any. 
		                    if (! $server) {
		                        unshift( @commands, "$vm is not configured as a dhcp relay. Choose the appropriate virtual machine with flag -M name" );
		                    } else {
		                        push( @commands, "$dhcp_relay_cmd force-reload" );
		                    }
		                
		                }
		                
                        case ("on_shutdown"){
                            # Force reload of the relay in the virtual machine. Return error if there isn't any. 
		                    if ($server) {
		                        push( @commands, "$dhcp_server_cmd stop" );
		                    }
		                    if ($relay) {
		                        push( @commands, "$dhcp_relay_cmd stop" );
		                    }
                        }
                    }
                } else {
                    unshift( @commands, "Unknown type value $type in vm $vm\n");
                }
            }
        }
    }        
    return @commands;
}


#
# getSeqDescriptions
#
# Returns a description of the command sequences offered by the plugin
# 
# Parameters:
#  - vm_name, the name of a virtual machine (optional)
#  - seq, a sequence value (optional)
#
# Returns:
#  - %seq_desc, an associative array (hash) whose keys are command sequences and the 
#               associated values the description of the actions made for that sequence
#               The value for specia key '_VMLIST' is a comma separated list of the
#               virtual machine names involved in a command sequence
#
sub getSeqDescriptions {
	
	my $self = shift;
	my $vm_name = shift;
	my $seq = shift;
	
	my %seq_desc;

	if ( (! $vm_name) && (! $seq) ) {   # Case 1: return all plugin sequences help

		foreach my $key ( keys %plugin_seq_help ) {
		   $seq_desc{$key} = $plugin_seq_help{$key};
		}
        my @vm_list;
        foreach my $vm ($pcf_dom->findnodes("/$pcf_main/vm")) {    
            push (@vm_list, $vm->getAttribute('name'));           
        }
        $seq_desc{'_VMLIST'} = join(',',@vm_list);	
		
	} elsif ( (! $vm_name) && ($seq) ) { # Case 2: return help for this $seq value and
	                                     #         the list of vms involved in that $seq 
        # Help for this $seq
        $seq_desc{$seq} = $plugin_seq_help{$seq};
        
        # List of vms involved
        my @vm_list;
        foreach my $vm ($pcf_dom->findnodes("/$pcf_main/vm")) {    
            push (@vm_list, $vm->getAttribute('name'));           
        }
        $seq_desc{'_VMLIST'} = join(',',@vm_list);
        
	
    } elsif ( ($vm_name) && (!$seq) )  { # Case 3: return the list of commands available
                                         #         for this vm
        my %vm_seqs = get_vm_seqs($vm_name);
        foreach my $key ( keys %vm_seqs ) {
            $seq_desc{"$key"} = $plugin_seq_help{"$key"};
            #plog (VVV, "case 3: $key $plugin_seq_help{$key}")
        }
        $seq_desc{'_VMLIST'} = $vm_name;
                                         
    } elsif ( ($vm_name) && ($seq) )   { # Case 4: return help for this $seq value only if
                                         #         vm $vm_name is affected for that $seq 
        $seq_desc{$seq} = $plugin_seq_help{$seq};
        $seq_desc{'_VMLIST'} = $vm_name;
                                          
    }
	
    return %seq_desc;	
	
}


#
# finalizePlugin
#
# finalizePlugin function is called before sending the shutdown signal to the virtual machines. 
# Note: finalizePlugin is not called when "-P|destroy" option is used, as that mode deletes any 
# changes made to the virtual machines.
#
# Arguments:
# - none
#
# Returns:
# - none
#
sub finalizePlugin {
    
    plog (VVV, "finalizePlugin ()");

}

###########################################################
# Internal functions
###########################################################

# 
# plog
# 
# Just calls VNX wlog function adding plugin prompt
#
# Call with: 
#    plog (N, "log message")    --> log msg written always  
#    plog (V, "log message")    --> only if -v,-vv or -vvv option selected
#    plog (VV, "log message")   --> only if -vv or -vvv option selected
#    plog (VVV, "log message")  --> only if -vvv option selected

sub plog {
	my $msg_level = shift;   # Posible values: V, VV, VVV
    my $msg       = shift;
    wlog ($msg_level, $prompt . $msg);
}


#
# get_vm_seqs 
#
# Returns an associative array (hash) with the command sequences that involve a virtual machine
#
sub get_vm_seqs {
    
    my $vm_name = shift;
    
    my %vm_seqs;
    
    # Get the virtual machine node whose name is $vm_name  
    my $vm = $pcf_dom->findnodes("/$pcf_main/vm[\@name='$vm_name']")->[0];  
    if ($vm) { 
    	# vm exists in PCF. Add sequence names
    	# general sequences
        foreach my $seq (@all_seqs) { $vm_seqs{$seq} = 'yes'} 

	    # DHCP server sequences
	    my $server  = $vm->findnodes('server')->[0];
	    if ($server) {
	        foreach my $seq (@server_seqs) { $vm_seqs{$seq} = 'yes'} 
	    }
        # DHCP relay sequences
	    my $relay   = $vm->findnodes('relay')->[0];
	    if ($relay) {
	        foreach my $seq (@relay_seqs) { $vm_seqs{$seq} = 'yes'} 
	    }
        # DHCP client sequences
	    my @clients = $vm->findnodes('client');
	    if (scalar @clients > 0) {
	        foreach my $seq (@client_seqs) { $vm_seqs{$seq} = 'yes'} 
	    }
	        
    }
    return %vm_seqs;    
}


1;