# dummy.pm
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
# The dummy plugin example

package dummy;

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
my $pcf_main = 'dummy_conf';

# plugin log prompt
my $prompt='dummy-plugin:  ';

#
# Command sequences used by OSPF plugin
#
# Used by any vm defined in PCF
my @all_seqs    = qw(on_boot start stop on_shutdown);

# Command sequences help description
my %plugin_seq_help = (
'on_boot',      'on_boot help',
'start',        'Start help',
'stop',         'Stops help',
'on_shutdown',  'on_shutdown help)'
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
# - doc, the VNX scenario main specification in DOM format
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

    chomp( my $date = `date` );
    
    if (($seq eq "on_boot") || ($seq eq "start")) {

	    # Get the virtual machine node whose name is $vm_name
	    my $vm = $pcf_dom->findnodes("/$pcf_main/vm[\@name='$vm_name']")->[0];  
	    if ($vm) {             
	
			plog (VVV, "getFiles: vm $vm_name found in config file");
	        # open filehandle to create dhcpd.conf file
	        my $cfg_file = $files_dir . "/${vm_name}.conf";
	        open( CONFIG_FILE, ">$cfg_file" ) or $files{"ERROR"} = "Cannot open $cfg_file file";
	    
	    	my $tag1_value;
	    	my $tag1 = $vm->findnodes('tag1')->[0];
		    if ($tag1) {
	    		$tag1_value = $tag1->textContent();
	    	} 
	    	my $tag2_value;
	    	my $tag2 = $vm->findnodes('tag2')->[0];
		    if ($tag2) {
	    		$tag2_value = $tag2->textContent();
	    	} 

    		plog (V, "getFiles: $doc");
	    	# Find vm IP address in main scenario file
	    	#my $ipv4_tag = $doc->findnodes("/vnx/vm[\@name='$vm_name']/if[\@id='1']/ipv4")->[0];  
	    	my $ipv4_tag = $doc->findnodes("/vnx/vm[\@name='$vm_name']/if[\@id='1']")->[0];  
	    	my $ipaddr_value = $ipv4_tag->textContent();
	    
	        print CONFIG_FILE "#\n# $vm_name config file generated by dummy.pm VNX plugin \n#   $date\n#\n\n";
	        print CONFIG_FILE "tag1=$tag1_value\n";
	        print CONFIG_FILE "tag2=$tag2_value\n";
	        print CONFIG_FILE "ipaddr=$ipaddr_value\n";
	        close(CONFIG_FILE);
	        $cfg_file =~ s#$files_dir/##;  # Eliminate the directory to make the filenames relative         
	        $files{"/tmp/" . $vm_name . "_cfg_file,vnx,vnx,644"} = $cfg_file;
			
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
		plog (VVV, "getFiles: vm $vm_name found in config file");
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


1;
    