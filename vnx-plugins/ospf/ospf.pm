# ospf.pm
#
# This file is a plugin of VNX package.
#
# Authors: Miguel Ferrer, Francisco José Martín, David Fernández
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
  finalizePlugin 
);

###########################################################
# Modules to import
###########################################################

use strict;
use XML::DOM;          					# XML management library
use File::Basename;    					# File management library

use Switch;

use Socket;								# To resolve hostnames to IPs

use XML::DOM::ValParser;				# To check DTD


###########################################################
# Global variables 
###########################################################

my $globalNode;
my $valid_fail;

###########################################################
# Plugin functions
###########################################################

#
# initPlugin
#
# To be called always, just before starting procesing the scenario specification
#
# Arguments:
# - the operation mode ("define", "create","execute","shutdown" or "destroy")
# - the plugin configuration file
#
# Returns:
# - an error message or 0 if all is ok
#
#
#
sub initPlugin {
	
	my $self = shift;	
	my $mode = shift;
	my $conf = shift;
	
	print "ospf-plugin> initPlugin (mode=$mode; conf=$conf)\n";

	my $error;
	
	eval{
		$error = &checkConfigFile($conf);
	};
	
	if ($@){
		$error = $@;
	}
	return $error;
}


#
# getFiles
#
# To be called during "x" mode, for each vm in the scenario
#
# Arguments:
# - vm name
# - seq command sequence
# - files_dir
#
# Returns:
# - a hashname which keys are absolute pathnames of files in vm filesystem and
#   values of the pathname of the file in the host filesystem. The file in the
#   host filesytesm is removed after VNUML processed it, so temporal files in 
#   /tmp are preferable)
#
#
sub getFiles{

    my $self = shift;
    my $vm_name = shift;
    my $files_dir = shift;
    my $seq = shift;
    
    print "ospf-plugin> getFiles (vm=$vm_name, seq=$seq)\n";
    my %files;
    
    if (($seq eq "on_boot") || ($seq eq "ospf-on_boot") || 
        ($seq eq "redoconf") || ($seq eq "ospf-redoconf")) { 
    
        my $vm_list=$globalNode->getElementsByTagName("vm");
        
        for (my $m=0; $m<$vm_list->getLength; $m++){
            
            my $vm = $vm_list->item($m);
            
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
# To be called during "-x" mode, for each vm in the scenario
#
# Arguments:
# - vm name
# - seq command sequence
# 
# Returns:
# - list of commands to execute in the virtual machine after <exec> processing
#
#    
sub getCommands{
    
    my $self = shift;
    my $vm_name = shift;
    my $seq = shift;
    
    print "ospf-plugin> getCommands (vm=$vm_name, seq=$seq)\n";
    my @commands;
        
    my $zebra_bin = "";
    my $ospfd_bin = "";

    my $vm_list=$globalNode->getElementsByTagName("vm");
    for (my $m=0; $m<$vm_list->getLength; $m++){
        
        my $vm = $vm_list->item($m);
        
        if ( $vm->getAttribute("name") eq $vm_name){
            
            get_commands ($vm, $vm_name, $seq, \@commands);
        }
    }
    return @commands;   
    
}


#
# finalizePlugin
#
# To be called always, just before ending the procesing the scenario specification
#
# Arguments:
# - none
#
# Returns:
# - none
#
sub finalizePlugin{
    
    print "ospf-plugin> finalizePlugin ()\n";
    
}

###########################################################
# Internal functions
###########################################################

#
# checkConfigFile
#
# Checks existence and semantics in ospf conf file. 
# Currently this check consist in:
#
#   1. Configuration file exists.
#   2. Check DTD.
#
sub checkConfigFile{
    
    # 1. Configuration file exists.
    my $config_file = shift;
    open(FILEHANDLE, $config_file) or {
        return "cannot open config file $config_file\n",
    };
    close (FILEHANDLE);
    
    # 2. Check DTD
    my $parser = new XML::DOM::ValParser;
    my $dom_tree;
    $valid_fail = 0;
    eval {
        local $XML::Checker::FAIL = \&validation_fail;
        $dom_tree = $parser->parsefile($config_file);
    };

    if ($valid_fail) {
        return ("$config_file is not a well-formed OSPF plugin file\n");
    }

    $globalNode = $dom_tree->getElementsByTagName("ospf_conf")->item(0);
    
    return 0;   
}

sub validation_fail {
   my $code = shift;
   # To set flag
   $valid_fail = 1;
   # To print error message
   XML::Checker::print_error ($code, @_);
}


#
# create_config_files
#
# Creates zebra.conf and ospfd.conf files for $vm virtual machine by
# processing the XML config file
#
sub create_config_files {
    
    my $vm        = shift;
    my $vm_name   = shift;
    my $files_dir = shift;
    my $files_ref = shift;
    
    my $zebra_file = $files_dir . "/$vm_name"."_zebra.conf";
    my $ospfd_file = $files_dir . "/$vm_name"."_ospfd.conf";
    #print "ospf-plugin> getBootFiles zebra_file=$zebra_file\n";
            
    my $zebraTagList = $vm->getElementsByTagName("zebra");
    my $zebraTag = $zebraTagList->item($0);
    my $zebra_hostname = $zebraTag->getAttribute("hostname");
    my $zebra_password = $zebraTag->getAttribute("password");
            
    chomp(my $date = `date`);
                        
    # Write the content of zebra.conf file
    open(ZEBRA, "> $zebra_file") or ${$files_ref}{"ERROR"} = "Cannot open $zebra_file file";
    print ZEBRA "! zebra.conf file generated by ospfd.pm VNUML plugin at $date\n";
    print ZEBRA "hostname $zebra_hostname\n";
    print ZEBRA "password $zebra_password\n";
    print ZEBRA "log file /var/log/zebra/zebra.log\n";          
    close (ZEBRA);
                
    # Write the content of ospfd.conf file
    open(OSPFD, "> $ospfd_file") or ${$files_ref}{"ERROR"} = "Cannot open $ospfd_file file";
    print OSPFD "! ospfd.conf file generated by ospfd.pm VNUML plugin at $date\n";
    print OSPFD "hostname $zebra_hostname\n";
    print OSPFD "password $zebra_password\n";
    print OSPFD "log file /var/log/zebra/ospfd.log\n!\n";
    print OSPFD "router ospf\n";
            
    # Process <network> tags
    my $networkTagList = $vm->getElementsByTagName("network");
    for (my $n=0; $n<$networkTagList->getLength; $n++){
        my $networkTag = $networkTagList->item($n);
        my $ipTagList = $networkTag->getElementsByTagName("ip");
                
        my $ipTag = $ipTagList->item($0);
        my $ipMask = $ipTag->getAttribute("mask");
        my $ipData = $ipTag->getFirstChild->getData;
                
        my $areaTagList = $networkTag->getElementsByTagName("area");
        my $areaTag = $areaTagList->item($0);
        my $areaData = $areaTag->getFirstChild->getData;
                
        print OSPFD " network $ipData/$ipMask area $areaData\n";
    }

    # Process <passive_if> tags
    my $passiveif_list = $vm->getElementsByTagName("passive_if");
    for (my $n=0; $n<$passiveif_list->getLength; $n++){
        my $passiveif = $passiveif_list->item($n);
        my $if_name = $passiveif->getFirstChild->getData;

        print OSPFD "passive-interface $if_name\n";        
    }

    print OSPFD "!\n";          
    close (OSPFD);  
            
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
    my $vm_name      = shift;
    my $seq = shift;
    my $commands_ref = shift;

    my $zebra_bin = "";
    my $ospfd_bin = "";
            
    unshift (@{$commands_ref}, "");
            
    my $type = $vm->getAttribute("type");
    my $subtype = $vm->getAttribute("subtype");

    my $zebra_bin_list = $vm->getElementsByTagName("zebra_bin");
    if ($zebra_bin_list->getLength == 1){
        $zebra_bin =  $zebra_bin_list->item($0)->getFirstChild->getData;
    }
    my $ospf_bin_list = $vm->getElementsByTagName("ospfd_bin");
    if ($ospf_bin_list->getLength == 1){
        $ospfd_bin =  $ospf_bin_list->item($0)->getFirstChild->getData;
    }
            
    # Get the binaries pathnames 
    switch ($type) {
        case "quagga"{ 
            switch ($subtype){
                case "lib-install"{ # quagga binaries installed in /usr/lib
                    if ($zebra_bin eq ""){ $zebra_bin = "/usr/lib/quagga/zebra"; }
                    if ($ospfd_bin eq ""){ $ospfd_bin = "/usr/lib/quagga/ospfd"; }
                }
                case "sbin-install"{ # quagga binaries installed in /usr/sbin
                    if ($zebra_bin eq ""){ $zebra_bin = "/usr/sbin/zebra"; }
                    if ($ospfd_bin eq ""){ $ospfd_bin = "/usr/sbin/ospfd"; }
                } else {
                    unshift (@{$commands_ref}, "Unknown subtype value $subtype\n");
                }
            }
        } else {
            unshift (@{$commands_ref}, "Unknown type value $type\n");
        }
    }
       
    # Define the command to execute depending on the $seq value
    if (($seq eq "on_boot") || ($seq eq "ospf-on_boot")){

        push (@{$commands_ref}, "mkdir /var/log/zebra");
        push (@{$commands_ref}, "chown quagga.quagga /var/log/zebra");
        push (@{$commands_ref}, "mkdir /var/run/quagga");
        push (@{$commands_ref}, "chown quagga.quagga /var/run/quagga");
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
        
    }elsif(($seq eq "stop") || ($seq eq "ospf-stop")){
        
        push (@{$commands_ref}, "killall zebra");
        push (@{$commands_ref}, "killall ospfd");
        
    }

}

1;







=BEGIN OLD OLD OLD



###########################################################
# getBootFiles
#
# To be called during "create" mode, for each vm in the scenario
#
# Arguments:
# - vm_name, virtual machine name
# - files_dir, directory where the files returned have to be copied
#
# Returns:
# - a hashname whose:
#      + keys are absolute pathnames of files in vm filesystem and
#      + values are the relative pathname of the file in the host filesystem. The file in the
#   host filesytesm is removed after VNUML processed it, so temporal files in 
#   /tmp are preferable)
###########################################################

sub getBootFiles{
	
	my $self      = shift;
	my $vm_name   = shift;
	my $files_dir = shift;
	
	print "ospf-plugin> getBootFiles (vm=$vm_name, files_dir=$files_dir)\n";
	my %files;
	
	my $vm_list=$globalNode->getElementsByTagName("vm");
	
	for (my $m=0; $m<$vm_list->getLength; $m++){
		
		my $vm = $vm_list->item($m);
		my $node_name = $vm->getAttribute("name");
		
		if ($node_name eq $vm_name){
            create_config_files ($vm, $vm_name, $files_dir, \%files);
		}
	}
		
	return %files;
}


# getBootCommands
#
# To be called during "-t" mode, for each vm in the scenario
#
# Arguments:
# - vm name
# 
# Returns:
# - list of commands to execute in the virtual machine at booting time
#
sub getBootCommands{

    my $self      = shift;
    my $vm_name   = shift;
	
	my @commands;

	print "ospf-plugin> getBootCommands (vm=$vm_name)\n";


	# Return code (OK)
#	unshift (@commands, "");

#	push (@commands, "touch /root/file-created-by-getBootCommands");

#	return @commands;

    my $type;
    my $subtype;
    
    my $zebra_bin = "";
    my $ospfd_bin = "";

    my $vm_list=$globalNode->getElementsByTagName("vm");
    for (my $m=0; $m<$vm_list->getLength; $m++){
        
        my $vm = $vm_list->item($m);
        
        if ( $vm->getAttribute("name") eq $vm_name){

            get_commands ($vm, $vm_name, 'on_boot', \@commands);
            
        }
         
    }
    return @commands;   
}







# deprecated
=BEGIN
sub execVmsToUse {

	my $self = shift;
	my $seq = shift;

	print "ospf-plugin> execVmsToUse (seq=$seq)\n";

    return;  # Delete. It is just to test the behavior when not implemented
    

	# The plugin has nothing to do for VMs with sequences other than
	# start, restart or stop, so in that case it returns an empty list
	unless ($seq eq "start" || $seq eq "ospf-start" || $seq eq "restart" || 
	        $seq eq "ospf-restart" || $seq eq "stop" || $seq eq "ospf-stop" || 
	        $seq eq "redoconf" || $seq eq "ospf-redoconf") {
		return ();
	}
	
	# Return the list of virtual machines included in plugin extended config file
	my @vm_list = ();
    
	my $vm_list=$globalNode->getElementsByTagName("vm");
	my $longitud = $vm_list->getLength;
	
	for (my $m=0; $m<$longitud; $m++){
		
		my $virtualm = $vm_list->item($m);
		push (@vm_list,$virtualm->getAttribute("name"));
	}
	
	return @vm_list;
	
}


###########################################################
# getExecFiles
#
# To be called during "x" mode, for each vm in the scenario
#
# Arguments:
# - vm name
# - seq command sequence
# - files_dir
#
# Returns:
# - a hashname which keys are absolute pathnames of files in vm filesystem and
#   values of the pathname of the file in the host filesystem. The file in the
#   host filesytesm is removed after VNUML processed it, so temporal files in 
#   /tmp are preferable)
#
###########################################################
sub getExecFiles{

	my $self = shift;
	my $vm_name = shift;
    my $files_dir = shift;
	my $seq = shift;
	
	print "ospf-plugin> getExecFiles (vm=$vm_name, seq=$seq)\n";
	my %files;
	
	if (($seq eq "redoconf") || ($seq eq "ospf-redoconf")){	
	

		my $vm_list=$globalNode->getElementsByTagName("vm");
		
		for (my $m=0; $m<$vm_list->getLength; $m++){
			
			my $vm = $vm_list->item($m);
			
			if ($vm->getAttribute("name") eq $vm_name){
                create_config_files ($vm, $vm_name, $files_dir, \%files);
			}
		}
	
	}
	return %files;		
}

###########################################################
# getExecCommands
#
# To be called during "-x" mode, for each vm in the scenario
#
# Arguments:
# - vm name
# - seq command sequence
# 
# Returns:
# - list of commands to execute in the virtual machine after <exec> processing
###########################################################
	
sub getExecCommands{
	
	my $self = shift;
	my $vm_name = shift;
	my $seq = shift;
	
	print "ospf-plugin> getExecCommands (vm=$vm_name, seq=$seq)\n";
	my @commands;
	
	my $type;
	my $subtype;
	
	my $zebra_bin = "";
	my $ospfd_bin = "";

	my $vm_list=$globalNode->getElementsByTagName("vm");
	for (my $m=0; $m<$vm_list->getLength; $m++){
		
		my $vm = $vm_list->item($m);
		
		if ( $vm->getAttribute("name") eq $vm_name){
			
            get_commands ($vm, $vm_name, $seq, \@commands);
		}
	}
	
	return @commands;	
	
}

sub getShutdownFiles{
	
    my $self      = shift;
    my $vm_name   = shift;
    my $files_dir = shift;
    
    print "ospf-plugin> getShutdownFiles (vm=$vm_name, files_dir=$files_dir)\n";
    my %files;
    
    # Directory test: DELETE
    system "touch $files_dir/f1";
    system "touch $files_dir/f2";
    system "mkdir $files_dir/kk";
    system "mkdir $files_dir/kk/d1";
    system "touch $files_dir/kk/f1";
    system "touch $files_dir/kk/f2";
    system "touch $files_dir/kk/d1/f1";

    $files{"/root/shutdown/f1"} = "f1";
    $files{"/root/shutdown/f2"} = "f2";
    $files{"/root/tmp"} = "kk";
    return %files;  

}

sub getShutdownCommands{

	my $self = shift;
	my $vm   = shift;

	my @commands;
	print "ospf-plugin> getShutdownCommands ()\n";

	# Return code (OK)
	unshift (@commands, "");

	push (@commands, "touch /root/file-created-by-getShutdownCommands");

	return @commands;

}

=END
=cut

	