#!/usr/bin/perl
#
# vnx2dot.pl
#
# This file is a module part of VNX package.
#
# Author: David Fernández (david@dit.upm.es), based on a previous version for VNUML
#         made by Francisco J. Monserrat (RedIRIS)
# Copyright (C) 2011-2014	DIT-UPM
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
#
# vnx2dot.pl creates a graphviz graph from a VNX XML virtual network scenario description
#

#  
# Note:
#  VNX element     is represented as
#  ----------------------------------
#  networks    ->  circle
#  vms         ->  squares
#  interfaces  ->  lines
#

use strict;
use XML::LibXML;
use VNX::DocumentChecks;
use VNX::TextManipulation;

#my $color_scheme="rdbu9";
my $color_scheme="set39";

# Font styles
my $font_name="arial";
my $font_color="#000000";
my $font_node_color="#FFFFFF";

# Net styles
my $net_shape="egg";
my $net_style="filled,diagonals";
#my $net_color="4";
my $net_color="#7c7c7c";
my $net_color2="#b3b3b3";
my $net_fontsize="14";
my $net_fontsize_small="8";

# VM styles
my $vm_shape="oval";
my $vm_style="filled";
#my $vm_color="8";
my $vm_color="5";
my $vm_fontsize="14";

# Host styles
my $host_shape="oval";
my $host_style="filled";
my $host_color="7";

# Edge styles
my $edge_fontsize="7";

my %vm_legend;
my %net_legend;

my $parser = XML::LibXML->new();
my $dom = $parser->parse_file($ARGV[0]);

print<<FIN;
 
// --------------------------------------------------------------
// Virtual Networks over LinuX (VNX) -- http://www.dit.upm.es/vnx 
// --------------------------------------------------------------
// vnx2dot.pl: graph created from $ARGV[0] scenario 
//
graph G {
overlap=scale
splines=true
sep=.1

 graph [fontname = "$font_name", fontcolor = "$font_color"];
 node  [fontname = "$font_name", fontcolor = "$font_node_color"];
 edge  [fontname = "$font_name", fontcolor = "$font_color"];

FIN
 
 
# Print Title (scenario name)
my $scen_name = $dom->findnodes ('/vnx/global/scenario_name')->to_literal;
print "// Graph Title\n";
print "labelloc=\"t\"\n";
print "label=\"$scen_name\"\n"; 

#
# Draw networks (switches)
#
print "// Networks\n" ;

foreach my $net ($dom->getElementsByTagName ("net")) {
    my $name = $net->getAttribute ("name");
    next if ($name eq "virbr0" || $name eq "lxcbr0");  # Ignore VM connections to external networks 
                                                       # through virbr0 or lxcbr0 to avoid distorting the map
    my $name2 = $name;
    $name2 =~ tr/-/_/;    # Graphviz id's do not admit "-"; we translate to "_"
    my $net_mode = $net->getAttribute ("mode");
    my $net_type = $net->getAttribute ("type");
    if ($net_mode eq 'virtual_bridge') {
        $net_mode = 'vbd';
        $net_legend{"vbd"} = "virtual bridge";    	     
    } elsif ($net_mode eq 'uml_switch') {
        $net_mode = 'usw';
        $net_legend{"usw"} = "uml switch";    	     
    } elsif ($net_mode eq 'openvswitch') {
        $net_mode = 'ovs';
        $net_legend{"ovs"} = "OpenvSwitch";    	     
    } elsif ($net_mode eq 'veth') {
        $net_mode = 'veth';
        $net_legend{"veth"} = "veth direct link";          
    } else {
        $net_mode = '??'
    }
    if ($net_type eq 'p2p') {
        print "$name2 [label=\"$name\\n($net_mode)\", shape=\"point\", " . 
              "fontsize=\"$net_fontsize\", fontstyle=\"bold\", colorscheme=\"$color_scheme\", color=\"$net_color\", style=\"$net_style\" ];\n" ;
    } else {
        print "$name2 [label=\"$name\\n($net_mode)\", shape=\"$net_shape\", " . 
              "fontsize=\"$net_fontsize\", fontstyle=\"bold\", colorscheme=\"$color_scheme\", color=\"$net_color\", style=\"$net_style\" ];\n" ;
    }
}

# Draw level 2 connections between switches
foreach my $net ($dom->getElementsByTagName ("net")) {
    my $name = $net->getAttribute ("name");
    
    foreach my $conn ($net->getElementsByTagName ("connection")) {
        my $net2 = $conn->getAttribute ("net");

        if ($conn->getElementsByTagName("vlan")) {
            my @vlan=$conn->getElementsByTagName("vlan");
            my $vlan_tag_list='';
            foreach my $tag ($vlan[0]->getElementsByTagName("tag")){
                $vlan_tag_list .= $tag->getAttribute("id") .",";
            }
            $vlan_tag_list =~ s/,$//;  # eliminate final ","
            # Check whether the connection is configured as trunk 
            # (two or more VLANs configured or trunk attribute set to 'yes')
            my $trunk = '';
            if ( (str($vlan[0]->getAttribute("trunk")) eq 'yes') || ( $vlan_tag_list =~ m/,/ ) ) { 
                $trunk = 'trunk:';   
            }
            print "$name -- $net2 [ label = \"vlans=[$trunk$vlan_tag_list]\", fontsize=\"8\" ]; \n"; 
        } else {
            print "$name -- $net2 [ label = \"vlans=[*]\", fontsize=\"8\" ]; \n"; 
        }        
    }
}

#
# Draw virtual machines
#
print "\n\n// Virtual machines \n" ;

foreach my $vm ($dom->getElementsByTagName ("vm")) {
    my $vmname = $vm->getAttribute ("name");
    my $vmname2 = $vmname;
    $vmname2 =~ tr/-/_/;    # Graphviz id's do not admit "-"; we translate to "_"
    my $type = $vm->getAttribute ("type");
    my $subtype = $vm->getAttribute ("subtype");
    my $os = $vm->getAttribute ("os");
    #print "vm: $vmname $type-$subtype-$os \n";
    my $ctype;

    # Set legend texts
    if ($type eq "uml") { 
    	$ctype=$type;
        $vm_legend{"uml"} = "User mode linux"    	 
    } elsif ($type eq "dynamips") { 
        if ($subtype eq "3600") {
            $ctype="dyna1"; 
            $vm_legend{"dyna1"} = "Dynamips C3600 router"       
        } elsif ($subtype eq "7200") {
            $ctype="dyna2"; 
            $vm_legend{"dyna2"} = "Dynamips C7200 router"       
        }
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "linux")) { 
    	$ctype="linux";
        $vm_legend{"linux"} = "libvirt KVM Linux"       
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "freebsd")) { 
        $ctype="freebsd";
        $vm_legend{"freebsd"} = "libvirt KVM FreeBSD"       
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "openbsd")) { 
        $ctype="openbsd";
        $vm_legend{"openbsd"} = "libvirt KVM OpenBSD"       
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "netbsd")) { 
        $ctype="netbsd";
        $vm_legend{"netbsd"} = "libvirt KVM NetBSD"       
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "win")) { 
        $ctype="windows";
        $vm_legend{"windows"} = "libvirt KVM Windows"       
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "olive")) { 
        $ctype="olive";
        $vm_legend{"olive"} = "libvirt KVM Olive router"       
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "android")) { 
        $ctype="android";
        $vm_legend{"android"} = "libvirt KVM Android"       
    } elsif ($type eq "lxc") { 
        $ctype=$type;
        $vm_legend{"lxc"} = "Linux Containers"
    } elsif ($type eq "nsrouter") { 
        $ctype=$type;
        $vm_legend{"nsrouter"} = "Name spaces based router"
    }       
    print "\n// Virtual machine $vmname\n" ;
    print "$vmname2 [label=\"$vmname \\n($ctype)\", shape=\"$vm_shape\", " . 
          "fontsize=\"$vm_fontsize\", colorscheme=\"$color_scheme\", color=\"$vm_color\", style=\"$vm_style\", margin=\"0\" ] ;\n" ;
#    print "$vmname2 [label=\"$vmname\", shape=\"circle\", fontcolor=\"$font_color\", " . 
#          "colorscheme=\"$color_scheme\", color=\"$vm_color\", style=\"filled\" ] ;\n" ;

    foreach my $if ($vm->getElementsByTagName ("if")) {
        my $id = $if->getAttribute ("id");
        my $net = $if->getAttribute ("net");
	    my $net2 = $net;
    	$net2 =~ tr/-/_/;        
        #print "  if: $id $net \n";

        if ($id == 0) { next } # Skip management interfaces
        
        if ($net eq 'lo') {
        	print "lo_$vmname [shape=\"point\", width=0.15, label=\"lo\", tooltip=\"$vmname loopback interface\"];"
        };

        if ($net eq 'virbr0' || $net eq 'lxcbr0') {
#            print "${net}_${vmname} [shape=\"point\", width=0.15, label=\"$net\", tooltip=\"Connection to external bridge ($net)\"];";
            my $vmname2 = $vmname;
            $vmname2 =~ tr/-/_/;    # Graphviz id's do not admit "-"; we translate to "_"
            print "${net}_${vmname2} [shape=\"$net_shape\", width=0.15, label=\"$net\", tooltip=\"Connection to external bridge ($net)\", " .
                   "fontsize=\"$net_fontsize_small\", fontstyle=\"bold\", colorscheme=\"$color_scheme\", color=\"$net_color2\", style=\"$net_style\" ];";
        };

#    print "$name2 [label=\"$name\\n($net_mode)\", shape=\"$net_shape\", " . 
#          "fontsize=\"$net_fontsize\", fontstyle=\"bold\", colorscheme=\"$color_scheme\", color=\"$net_color\", style=\"$net_style\" ];\n" ;
        
        my $ipaddrs;
        foreach my $ipv4s ($if->getElementsByTagName ("ipv4")) {
            my $ipv4 = $ipv4s->getChildNodes->[0];
            $ipaddrs = $ipaddrs . ' \n' . $ipv4->textContent;
        }
        foreach my $ipv6s ($if->getElementsByTagName ("ipv6")) {
            my $ipv6 = $ipv6s->getChildNodes->[0];
            $ipaddrs = $ipaddrs . ' \n' . $ipv6->textContent;
        }
       
        if ($if->getElementsByTagName("vlan")) {
            my @vlan=$if->getElementsByTagName("vlan");
            my $vlan_tag_list='';
            foreach my $tag ($vlan[0]->getElementsByTagName("tag")){
                $vlan_tag_list .= $tag->getAttribute("id") .",";
            }
            $vlan_tag_list =~ s/,$//;  # eliminate final ","
            # Check whether the connection is configured as trunk 
            # (two or more VLANs configured or trunk attribute set to 'yes')
            my $trunk = '';
            if ( (str($vlan[0]->getAttribute("trunk")) eq 'yes') || ( $vlan_tag_list =~ m/,/ ) ) { 
                $trunk = 'trunk:';   
            }
            print "//   if $id with IP addresses $ipaddrs connected to network $net\n" ;
            #print "$vmname2 -- $net2  [ label = \"$ipaddrs\", fontsize=\"9\", style=\"bold\" ];\n" ;
            print "$vmname2 -- $net2  [ label = \"$ipaddrs\\nvlans=[$trunk$vlan_tag_list]\", fontsize=\"$edge_fontsize\" ];\n" ;            
        } else {
            if ($net eq 'lo') {
	            print "//   interface $id with IP addresses $ipaddrs connected to network $net\n" ;
	            print "$vmname2 -- lo_$vmname [ label = \"$ipaddrs\", fontsize=\"$edge_fontsize\", len=\"0.8\" ];\n" ;                        
            } elsif ($net eq 'virbr0' || $net eq 'lxcbr0') {
                print "//   interface $id with IP addresses $ipaddrs connected to network $net\n" ;
                print "$vmname2 -- ${net}_${vmname} [ label = \"$ipaddrs\", fontsize=\"$edge_fontsize\", len=\"0.8\" ];\n" ;                        
            } else {
	            print "//   interface $id with IP addresses $ipaddrs connected to network $net\n" ;
	            print "$vmname2 -- $net2  [ label = \"$ipaddrs\", fontsize=\"$edge_fontsize\" ];\n" ;                        
            }            
        }        
        
    }
}

#
# Draw host node if connected to the scenario
#
my @hostifs = $dom->getElementsByTagName ("hostif");

if (@hostifs > 0) {
    print "\n// Host\n" ;
#    print "host [label=\"host\", shape=\"$host_shape\", " . 
#          "colorscheme=\"$color_scheme\", color=\"$host_color\", style=\"$host_style\" ] ;\n" ;
}

my $i;

foreach my $hostif (@hostifs) { 

    print "host$i [label=\"host\", shape=\"$host_shape\", " . 
          "colorscheme=\"$color_scheme\", color=\"$host_color\", style=\"$host_style\" ] ;\n" ;

    my $id = $hostif->getAttribute ("id");
    my $net = $hostif->getAttribute ("net");
    my $net2 = $net;
   	$net2 =~ tr/-/_/;        

    my $ipaddrs;
    foreach my $ipv4s ($hostif->getElementsByTagName ("ipv4")) {    	
        my $ipv4 = $ipv4s->getChildNodes->[0];
        $ipaddrs = $ipaddrs . ' \n' . $ipv4->textContent;
    }
    foreach my $ipv6s ($hostif->getElementsByTagName ("ipv6")) {        
        my $ipv6 = $ipv6s->getChildNodes->[0];
        $ipaddrs = $ipaddrs . ' \n' . $ipv6->textContent;
    }

    if ($hostif->getElementsByTagName("vlan")) {
        my @vlan=$hostif->getElementsByTagName("vlan");
        my $vlan_tag_list='';
        foreach my $tag ($vlan[0]->getElementsByTagName("tag")){
            $vlan_tag_list .= $tag->getAttribute("id") .",";
        }
        $vlan_tag_list =~ s/,$//;  # eliminate final ","
        # Check whether the connection is configured as trunk 
        # (two or more VLANs configured or trunk attribute set to 'yes')
        my $trunk = '';
        if ( (str($vlan[0]->getAttribute("trunk")) eq 'yes') || ( $vlan_tag_list =~ m/,/ ) ) { 
            $trunk = 'trunk:';   
        }
        print "//   if $id with IP addresses $ipaddrs connected to network $net\n" ;
        print "host$i -- $net2  [ label = \"$ipaddrs\\nvlans=[$trunk$vlan_tag_list]\", fontsize=\"$edge_fontsize\" ];\n" ;
    } else {
        print "//   if $id with IP addresses $ipaddrs connected to network $net\n" ;
        print "host$i -- $net2  [ label = \"$ipaddrs\", fontsize=\"$edge_fontsize\" ];\n" ;
    }        
    
    $i++;

}


#
# print vm and net legends
#

# Example legend table
# label=<<TABLE ALIGN="LEFT">
# <TR><TD ALIGN="LEFT" BGCOLOR="#AAAAAA">Virtual machines types</TD></TR>
# <TR><TD ALIGN="LEFT">lxc = Linux Containers </TD></TR>
# <TR><TD ALIGN="LEFT" BGCOLOR="#AAAAAA">Network types</TD></TR>
# <TR><TD ALIGN="LEFT">ovs = OpenvSwitch</TD></TR>
# </TABLE>>

print<<END;
bigger [
fontsize=8
shape=none
fontcolor="$font_color"
END
print "label=<<TABLE border=\"0\" cellborder=\"1\" cellspacing=\"0\">";

# Virtual machine types
print "<TR><TD ALIGN=\"LEFT\" BGCOLOR=\"#FFFF99\"><b>Virtual machines types</b></TD></TR>";
foreach my $key (keys %vm_legend) {
    print "<TR><TD ALIGN=\"LEFT\">$key = $vm_legend{$key}</TD></TR>";
}

# Network types
print "<TR><TD ALIGN=\"LEFT\" BGCOLOR=\"#FFFF99\">Network types</TD></TR>";
foreach my $key (keys %net_legend) {
    print "<TR><TD ALIGN=\"LEFT\">$key = $net_legend{$key}</TD></TR>";
}

print "</TABLE>>]";


=BEGIN
print<<END;
bigger [
fontsize=8
shape=record
label="{Virtual machines types |\\l\\
END
foreach my $key (keys %vm_legend) {
    print "$key = $vm_legend{$key} \\l\\\n";
}
#print "}\"];\n";

print "| Network types |\\l\\";
foreach my $key (keys %net_legend) {
    print "$key = $net_legend{$key} \\l\\\n";
}
print "}\"];\n";
=END
=cut

print "\n}\n" ;