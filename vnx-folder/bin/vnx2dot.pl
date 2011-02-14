#!/usr/bin/perl
#
# Nota:
#  networks -> circle
#  vms -> squares
#  interfaces -> lines

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
 
// Graph of VNUML configuration from $ARGV[0] 
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
    print "$name [label=\"$name\", shape=\"ellipse\", fontcolor=\"$fontcolor\", " . 
          "colorscheme=\"$colorscheme\", color=\"$netcolor\", style=\"filled\" ] ;\n" ;
}


# Virtual machines
print "\n\n// Virtual machines \n" ;
my $vms = $dom->getElementsByTagName ("vm");
$n = $vms->getLength;

for (my $i = 0; $i < $n; $i++) {
    my $vm = $vms->item ($i);
    my $vmname = $vm->getAttribute ("name");
    my $type = $vm->getAttribute ("type");
    my $subtype = $vm->getAttribute ("subtype");
    my $os = $vm->getAttribute ("os");
    #print "vm: $vmname $type-$subtype-$os \n";
    my $ctype;
    if ( ($type eq "uml") || ($type eq "dynamips") ) {
        $ctype=$type;
    } elsif ( ($type eq "libvirt") && ($subtype eq "kvm") ) {
        if ($os eq "windows" ) { $os="win" }
        $ctype="$type-$os";
    } 
    print "\n// Virtual machine $vmname\n" ;
    print "$vmname [label=\"$vmname \\n($ctype)\", shape=\"box\", fontcolor=\"$fontcolor\", " . 
          "colorscheme=\"$colorscheme\", color=\"$vmcolor\", style=\"filled\" ] ;\n" ;

    my $ifs = $vm->getElementsByTagName ("if");
    my $n = $ifs->getLength;
    for (my $j = 0; $j < $n; $j++) {
        my $if = $ifs->item ($j);
        my $id = $if->getAttribute ("id");
        my $net = $if->getAttribute ("net");
        #print "  if: $id $net \n";
        my $ipv4s = $if->getElementsByTagName ("ipv4");
        my $n = $ipv4s->getLength;
        for (my $k = 0; $k < $n; $k++) {
            my $ipv4 = $ipv4s->item ($k)->getChildNodes->item(0);
            my $ip = $ipv4->getNodeValue;
	    # print "    ipv4: $ip\n"; 
            print "//   if $id with IP address $ip connected to network $net\n" ;
            print "$vmname -- $net  [ label = \"$ip\", fontsize=\"9\", style=\"bold\" ];\n" ;
        }
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
    #print "  if: $id $net \n";
    my $ipv4s = $hostif->getElementsByTagName ("ipv4");
    my $n = $ipv4s->getLength;
    for (my $k = 0; $k < $n; $k++) {
        my $ipv4 = $ipv4s->item ($k)->getChildNodes->item(0);
        my $ip = $ipv4->getNodeValue;
        # print "    ipv4: $ip\n";
        print "//   if $id with IP address $ip connected to network $net\n" ;
        print "host -- $net  [ label = \"$ip\", fontsize=\"9\", style=\"bold\" ];\n" ;
    }
}

print "\n}\n" ;







