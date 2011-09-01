#!/usr/bin/perl
#
# vnx2dot.pl
#
# This file is a module part of VNX package.
#
# Author: David Fernández (david@dit.upm.es), based on a previous version for VNUML
#         made by Francisco J. Monserrat (RedIRIS)
# Copyright (C) 2011, 	DIT-UPM
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
use XML::DOM;

#my $colorscheme="rdbu9";
my $colorscheme="set39";
#my $netcolor="4";
my $netcolor="#b3b3b3";
#my $vmcolor="8";
my $vmcolor="5";
my $hostcolor="7";
my $fontcolor="#FFFFFF";

my $parser       = new XML::DOM::Parser;
my $dom          = $parser->parsefile($ARGV[0]);


#open FILE,  $ARGV[0]  || die "Can't open $ARGV[0]\n" ;
#my @conf=<FILE> ;
#close FILE ;

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
 
FIN
 
# OK magic starts!
 
print "// Networks\n" ;
# Networks
my $nets = $dom->getElementsByTagName ("net");
my $n = $nets->getLength;

for (my $i = 0; $i < $n; $i++)
{
    my $net = $nets->item ($i);
    my $name = $net->getAttribute ("name");
    my $name2 = $name;
    $name2 =~ tr/-/_/;    # Graphviz id's do not admit "-"; we translate to "_"
    print "$name2 [label=\"$name\", shape=\"ellipse\", fontcolor=\"$fontcolor\", " . 
          "colorscheme=\"$colorscheme\", color=\"$netcolor\", style=\"filled\" ] ;\n" ;
}

my %legend;

# Virtual machines
print "\n\n// Virtual machines \n" ;
my $vms = $dom->getElementsByTagName ("vm");
$n = $vms->getLength;

for (my $i = 0; $i < $n; $i++) {
    my $vm = $vms->item ($i);
    my $vmname = $vm->getAttribute ("name");
    my $vmname2 = $vmname;
    $vmname2 =~ tr/-/_/;    # Graphviz id's do not admit "-"; we translate to "_"
    my $type = $vm->getAttribute ("type");
    my $subtype = $vm->getAttribute ("subtype");
    my $os = $vm->getAttribute ("os");
    #print "vm: $vmname $type-$subtype-$os \n";
    my $ctype;

#    if ( ($type eq "uml") || ($type eq "dynamips") ) {
#        $ctype=$type;
#    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") ) {
#        if ($os eq "windows" ) { $os="win" }
#        $ctype="$type-$os";
#    } 

    if ($type eq "uml") { 
    	$ctype=$type;
        $legend{"uml"} = "User mode linux"    	 
    } elsif ($type eq "dynamips") { 
        if ($subtype eq "3600") {
            $ctype="dyna1"; 
            $legend{"dyna1"} = "Dynamips C3600 router"       
        } elsif ($subtype eq "7200") {
            $ctype="dyna2"; 
            $legend{"dyna2"} = "Dynamips C7200 router"       
        }
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "linux")) { 
    	$ctype="linux";
        $legend{"linux"} = "libvirt kvm Linux"       
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "freebsd")) { 
        $ctype="freebsd";
        $legend{"freebsd"} = "libvirt kvm FreeBSD"       
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "win")) { 
        $ctype="windows";
        $legend{"windows"} = "libvirt kvm Windows"       
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") && ($os eq "olive")) { 
        $ctype="olive";
        $legend{"olive"} = "libvirt kvm Olive router"       
    } 
    print "\n// Virtual machine $vmname\n" ;
    print "$vmname2 [label=\"$vmname \\n($ctype)\", shape=\"circle\", fontcolor=\"$fontcolor\", " . 
          "colorscheme=\"$colorscheme\", color=\"$vmcolor\", style=\"filled\", margin=\"0\" ] ;\n" ;
#    print "$vmname2 [label=\"$vmname\", shape=\"circle\", fontcolor=\"$fontcolor\", " . 
#          "colorscheme=\"$colorscheme\", color=\"$vmcolor\", style=\"filled\" ] ;\n" ;

    my $ifs = $vm->getElementsByTagName ("if");
    my $n = $ifs->getLength;
    for (my $j = 0; $j < $n; $j++) {
        my $if = $ifs->item ($j);
        my $id = $if->getAttribute ("id");
        my $net = $if->getAttribute ("net");
	    my $net2 = $net;
    	$net2 =~ tr/-/_/;        
        #print "  if: $id $net \n";
        my $ipaddrs;
        my $ipv4s = $if->getElementsByTagName ("ipv4");
        my $n = $ipv4s->getLength;
        for (my $k = 0; $k < $n; $k++) {
            my $ipv4 = $ipv4s->item ($k)->getChildNodes->item(0);
            $ipaddrs = $ipaddrs . ' \n' . $ipv4->getNodeValue;
        }
        my $ipv6s = $if->getElementsByTagName ("ipv6");
        $n = $ipv6s->getLength;
        for (my $k = 0; $k < $n; $k++) {
            my $ipv6 = $ipv6s->item ($k)->getChildNodes->item(0);
            $ipaddrs = $ipaddrs . ' \n' . $ipv6->getNodeValue;
        }
        print "//   if $id with IP addresses $ipaddrs connected to network $net\n" ;
        print "$vmname2 -- $net2  [ label = \"$ipaddrs\", fontsize=\"9\", style=\"bold\" ];\n" ;
    }
}

my $hostifs = $dom->getElementsByTagName ("hostif");
$n = $hostifs->getLength;

if ($n > 0) {
    print "\n// Host\n" ;
    print "host [label=\"host\", shape=\"box\", fontcolor=\"$fontcolor\", " . 
          "colorscheme=\"$colorscheme\", color=\"$hostcolor\", style=\"filled\" ] ;\n" ;
}

for (my $j = 0; $j < $n; $j++) {
    my $hostif = $hostifs->item ($j);
    my $id = $hostif->getAttribute ("id");
    my $net = $hostif->getAttribute ("net");
    my $net2 = $net;
   	$net2 =~ tr/-/_/;        

=BEGIN
    #print "  if: $id $net \n";
    my $ipv4s = $hostif->getElementsByTagName ("ipv4");
    my $n = $ipv4s->getLength;
    for (my $k = 0; $k < $n; $k++) {
        my $ipv4 = $ipv4s->item ($k)->getChildNodes->item(0);
        my $ip = $ipv4->getNodeValue;
        # print "    ipv4: $ip\n";
        print "//   if $id with IP address $ip connected to network $net\n" ;
        print "host -- $net2  [ label = \"$ip\", fontsize=\"9\", style=\"bold\" ];\n" ;
    }
=END
=cut

    my $ipaddrs;
    my $ipv4s = $hostif->getElementsByTagName ("ipv4");
    my $n = $ipv4s->getLength;
    for (my $k = 0; $k < $n; $k++) {
        my $ipv4 = $ipv4s->item ($k)->getChildNodes->item(0);
        $ipaddrs = $ipaddrs . ' \n' . $ipv4->getNodeValue;
    }
    my $ipv6s = $hostif->getElementsByTagName ("ipv6");
    $n = $ipv6s->getLength;
    for (my $k = 0; $k < $n; $k++) {
        my $ipv6 = $ipv6s->item ($k)->getChildNodes->item(0);
        $ipaddrs = $ipaddrs . ' \n' . $ipv6->getNodeValue;
    }
    print "//   if $id with IP addresses $ipaddrs connected to network $net\n" ;
    print "host -- $net2  [ label = \"$ipaddrs\", fontsize=\"9\", style=\"bold\" ];\n" ;

}

# print Legend

print<<END;
bigger [
fontsize=8
shape=record
label="{Virtual machines types |\\l\\
END
foreach my $key (keys %legend) {
    print "$key = $legend{$key} \\l\\\n";
}
print "}\"];\n";


print "\n}\n" ;







