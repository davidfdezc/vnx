# ospf.pm
#
# This file is a plugin of VNX package.
#
# Authors: Miguel Ferrer, Francisco José Martín (VNUML version, 2009)
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
package ospf;

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
use Switch;
use Data::Dumper;


###########################################################
# Global variables 
###########################################################

# DOM tree for Plugin Configuration File (PCF)
my $pcf_dom;

# Main VNX scenario specification file in DOM format
my $doc;

# Name of PCF main node tag (ex. ospf_conf, dhcp_conf, etc)
my $pcf_main = 'ospf_conf';

# plugin log prompt
my $prompt='ospf-plugin:  ';

#
# Command sequences used by OSPF plugin
#
# Used by any vm defined in PCF
my @all_seqs    = qw(on_boot start stop restart redoconf ospf-on_boot ospf-start ospf-stop ospf-restart ospf-redoconf on_shutdown);

# Command sequences help description
my %plugin_seq_help = (
'on_boot',      'Creates OSPF config files and starts daemons (executed after startup)',
'start',        'Starts OSPF daemons',
'stop',         'Stops OSPF daemons',
'restart',      'Restarts OSPF daemons',
'redoconf',     'Recreate the OSPF config files',
'ospf-on_boot', 'Plugin specific synonym of \'on_boot\'', 
'ospf-start',   'Plugin specific synonym of \'start\'',
'ospf-stop',    'Plugin specific synonym of \'stop\'',
'ospf-restart', 'Plugin specific synonym of \'restart\'',
'ospf-redoconf','Plugin specific synonym of \'redoconf\'',
'on_shutdown',  'Stops OSPF daemons (executed before shutdown)'
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
    $doc  = shift; # Save main doc in global variable 
	
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

    my $self = shift;
    my $vm_name = shift;
    my $files_dir = shift;
    my $seq = shift;
    
    my %files;

    plog (VVV, "getFiles (vm=$vm_name, seq=$seq)");
    
    if (($seq eq "on_boot") || ($seq eq "ospf-on_boot") || 
        ($seq eq "redoconf") || ($seq eq "ospf-redoconf")) { 
    
        foreach my $vm ($pcf_dom->findnodes("/$pcf_main/vm")) {    
            
            if ($vm->getAttribute("name") eq $vm_name){
                create_config_files ($vm, $vm_name, $files_dir, \%files);
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
        
    # Get the virtual machine node whose name is $vm_name
    my $vm = $pcf_dom->findnodes("/$pcf_main/vm[\@name='$vm_name']")->[0];  
    if ($vm) { 
        get_commands ($vm, $seq, \@commands);
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
#               associated values the description of the actions made for that sequence.
#               The value for specia key '_VMLIST' is a comma separated list of the
#               virtual machine names involved in a command sequence when 'seq' parameter
#               is used.
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
        foreach my $vm ($pcf_dom->findnodes('/ospf_conf/vm')) {    
            push (@vm_list, $vm->getAttribute('name'));           
        }
        $seq_desc{'_VMLIST'} = join(',',@vm_list);  
        
    } elsif ( (! $vm_name) && ($seq) ) { # Case 2: return help for this $seq value and
                                         #         the list of vms involved in that $seq 
        # Help for this $seq
        $seq_desc{$seq} = $plugin_seq_help{$seq};
        
        # List of vms involved
        my @vm_list;
        foreach my $vm ($pcf_dom->findnodes('/dhcp_conf/vm')) {    
            push (@vm_list, $vm->getAttribute('name'));           
        }
        $seq_desc{'_VMLIST'} = join(',',@vm_list);
        
    
    } elsif ( ($vm_name) && (!$seq) )  { # Case 3: return the list of commands available
                                         #         for this vm
        my %vm_seqs = get_vm_seqs($vm_name);
        foreach my $key ( keys %vm_seqs ) {
            $seq_desc{"$key"} = $plugin_seq_help{"$key"};
            #wlog (VVV, "case 3: $key $plugin_seq_help{$key}")
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
sub finalizePlugin{
    
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
# create_config_files
#
# Creates zebra.conf and ospfd.conf files for $vm virtual machine by
# processing the XML config file
#
# Example config files for quagga:
# 
# + zebra.conf:
#   !
#   ! zebra.conf file generated by ospfd.pm VNX plugin 
#   !   sáb sep 10 19:42:57 CEST 2011
#   !
#   
#   hostname r1
#   password xxxx
#   log file /var/log/zebra/zebra.log
#   
# + ospfd.conf:
#   !
#   ! ospfd.conf file generated by ospfd.pm VNX plugin 
#   !   sáb sep 10 19:42:57 CEST 2011
#   !
#   
#   hostname r1
#   password xxxx
#   log file /var/log/zebra/ospfd.log
#   !
#   router ospf
#    network 10.0.0.0/16 area 0.0.0.0
#   passive-interface eth1
#   
sub create_config_files {
    
    my $vm        = shift;
    my $vm_name   = shift;
    my $files_dir = shift;
    my $files_ref = shift;
    
    my $zebra_file = $files_dir . "/$vm_name"."_zebra.conf";
    my $ospfd_file = $files_dir . "/$vm_name"."_ospfd.conf";
            
    # Hostname and password
    my $hostname = $vm_name; # Default hostname is vm_name
    my $hostname_tag = $vm->findnodes('hostname')->[0];
    if ($hostname_tag) {
    	$hostname = $hostname_tag->textContent();
    } 
    my $password;
    my $passwd_tag = $vm->findnodes('password')->[0];
    if ($passwd_tag) {
        $password = $passwd_tag->textContent();
    } 
            
    chomp(my $date = `date`);
                        
    # Write zebra.conf header
    open(ZEBRA, "> $zebra_file") or ${$files_ref}{"ERROR"} = "Cannot open $zebra_file file";
    print ZEBRA "!\n! zebra.conf file generated by ospfd.pm VNX plugin \n!   $date\n!\n\n";
    print ZEBRA "hostname $hostname\n";
    if ($password) {
        print ZEBRA "password $password\n";	
    }

    ################################################
    # <lo>
    #    <description>text1</description>
    #    <ip_adress>AA.BB.CC.DD/EE</ip_address>
    # </lo>
    # .........................................
    # interface name
    # description texto1
    # ip address AA.BB.CC.DD/EE
    #
    foreach my $lo ($vm->findnodes('lo')) {
        print ZEBRA "interface lo\n";
        my $description_tag  = $lo->findnodes('description')->[0];
    	if ($description_tag) {
    	   print ZEBRA " description " . $description_tag->textContent() . "\n";
    	}
    	my $ip_address_tag  = $lo->findnodes('ip_address')->[0];
    	if ($ip_address_tag) {
    	   print ZEBRA " ip address " . $ip_address_tag->textContent() . "\n";
    	}
    }
    print ZEBRA "\n";
    #
    #
    ################################################
    
    print ZEBRA "log file /var/log/zebra/zebra.log\n";          
    close (ZEBRA);
                
    # Write ospfd.conf header
    open(OSPFD, "> $ospfd_file") or ${$files_ref}{"ERROR"} = "Cannot open $ospfd_file file";
    print OSPFD "!\n! ospfd.conf file generated by ospfd.pm VNX plugin \n!   $date\n!\n\n";
    print OSPFD "hostname $hostname\n";
    print OSPFD "password $password\n";
    print OSPFD "log file /var/log/zebra/ospfd.log\n!\n";
    
    ################################################
    # <if name="name">
    #    <ip_ospf>option1 text1</ip_ospf>
    #    <ip_ospf>option2 text2</ip_ospf>
    # </if>
    # .........................................
    # interface name
    # ip ospf option1 text1
    # ip ospf option2 text2
    #
    foreach my $if ($vm->findnodes('if')) {
        print OSPFD "interface " . $if->getAttribute('name') . "\n";
        foreach my $ip_ospf_tag ($if->findnodes('ip_ospf')) {
    	   print OSPFD " ip ospf " . $ip_ospf_tag->textContent() . "\n";
        }
        print OSPFD "!\n";
    }
    print OSPFD "!\n";
    #
    #
    ################################################
    
    print OSPFD "router ospf\n";

    # Process <router_id> tag
    foreach my $router_id ($vm->findnodes('router_id')) {
        print OSPFD " ospf router-id " . $router_id->textContent() . "\n";
    }

    # Process <network> tags
    foreach my $network ($vm->findnodes('network')) {
        print OSPFD " network " . $network->textContent() . " area " . $network->getAttribute('area') . "\n";
    }

    # Process <passive_if> tags
    foreach my $passive_if ($vm->findnodes('passive_if')) {
        print OSPFD "passive-interface " . $passive_if->textContent() . "\n";        
    }

    print OSPFD "!\n";
    print OSPFD "line vty\n";
    print OSPFD "!\n";          
    close (OSPFD);  

    # Print zebra.conf and ospfd.conf files to log if VVV
    open FILE, "< $zebra_file"; my $cmd_file = do { local $/; <FILE> }; close FILE;
    plog (VVV, "zebra.conf created for vm $vm_name: \n$cmd_file");
    open FILE, "< $ospfd_file"; $cmd_file = do { local $/; <FILE> }; close FILE;
    plog (VVV, "ospfd.conf created for vm $vm_name: \n$cmd_file");

            
    # Fill the hash with the files created
    $zebra_file =~ s#$files_dir/##;  # Eliminate the directory to make the filenames relative 
    $ospfd_file =~ s#$files_dir/##;   
    ${$files_ref}{"/etc/quagga/zebra.conf,quagga,quagga,644"} = $zebra_file;
    ${$files_ref}{"/etc/quagga/ospfd.conf,quagga,quagga,644"} = $ospfd_file;
        
}


#
# get_commands
#
# Creates zebra.conf and ospfd.conf files for $vm virtual machine by
# processing the XML config file
#
sub get_commands {
    
    my $vm           = shift;
    my $seq          = shift;
    my $commands_ref = shift;

            
    my $vm_name = $vm->getAttribute("name");
    my $vm_type    = $vm->getAttribute("type");
    my $vm_subtype = $vm->getAttribute("subtype");

    # Get the binaries pathnames 
    my $zebra_bin = "";
    my $zebra_bin_tag  = $vm->findnodes('binaries/zebra')->[0];
    if ($zebra_bin_tag) {
    	$zebra_bin = $zebra_bin_tag->textContent();
    }

    my $ospfd_bin = "";
    my $ospfd_bin_tag  = $vm->findnodes('binaries/ospfd')->[0];
    if ($ospfd_bin_tag) {
        $ospfd_bin = $ospfd_bin_tag->textContent();
    }

    if (($zebra_bin eq "") || ($ospfd_bin eq "")) {
	    switch ($vm_type) {
	        case "quagga"{ 
	            switch ($vm_subtype){
	                case "lib-install"{ # quagga binaries installed in /usr/lib
	                    if ($zebra_bin eq ""){ $zebra_bin = "/usr/lib/quagga/zebra"; }
	                    if ($ospfd_bin eq ""){ $ospfd_bin = "/usr/lib/quagga/ospfd"; }
	                }
	                case "sbin-install"{ # quagga binaries installed in /usr/sbin
	                    if ($zebra_bin eq ""){ $zebra_bin = "/usr/sbin/zebra"; }
	                    if ($ospfd_bin eq ""){ $ospfd_bin = "/usr/sbin/ospfd"; }
	                } else {
	                    unshift (@{$commands_ref}, "Unknown subtype value $vm_subtype\n");
	                }
	            }
	        } else {
	            unshift (@{$commands_ref}, "Unknown type value $vm_type\n");
	        }
	    }
    }
       
    # Define the command to execute depending on the $seq value
    if (($seq eq "on_boot") || ($seq eq "ospf-on_boot")){

        push (@{$commands_ref}, "mkdir -v /var/log/zebra");
        push (@{$commands_ref}, "chown quagga.quagga /var/log/zebra");
        push (@{$commands_ref}, "sleep 4");
        push (@{$commands_ref}, "mkdir -v /var/run/quagga");
        push (@{$commands_ref}, "chown quagga.quagga /var/run/quagga");
        push (@{$commands_ref}, "chmod 755 /var/run/quagga");
        push (@{$commands_ref}, "$zebra_bin -d");
        push (@{$commands_ref}, "$ospfd_bin -d");

    } elsif(($seq eq "start") || ($seq eq "ospf-start")){

        push (@{$commands_ref}, "$zebra_bin -d");
        push (@{$commands_ref}, "$ospfd_bin -d");

    } elsif(($seq eq "restart") || ($seq eq "ospf-restart")){
        
        push (@{$commands_ref}, "killall zebra");
        push (@{$commands_ref}, "killall ospfd");

        push (@{$commands_ref}, "mkdir /var/log/zebra");
        push (@{$commands_ref}, "chown quagga.quagga /var/log/zebra");
        push (@{$commands_ref}, "mkdir /var/run/quagga");
        push (@{$commands_ref}, "chown quagga.quagga /var/run/quagga");
        push (@{$commands_ref}, "$zebra_bin -d");
        push (@{$commands_ref}, "$ospfd_bin -d");
        
    }elsif(($seq eq "stop") || ($seq eq "ospf-stop") ||
           ($seq eq "on_shutdown") ){
        
        push (@{$commands_ref}, "killall zebra");
        push (@{$commands_ref}, "killall ospfd");
        
    }
}

#
# get_vm_seqs 
#
# Returns an associative array (hash) with the command sequences that involve a virtual machine
#
sub get_vm_seqs {
    
    my $vm_name = shift;
    
    my %vm_seqs;
    
    my $vm = $pcf_dom->findnodes("/$pcf_main/vm[\@name='$vm_name']")->[0]; 
    if ($vm) {
        foreach my $seq (@all_seqs) { $vm_seqs{$seq} = 'yes'} 
    } 
    return %vm_seqs;    
}


1;
	