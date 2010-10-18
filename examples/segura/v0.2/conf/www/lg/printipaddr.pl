#!/usr/bin/perl
#
# PERL script to show the client IP address (either IPv4 or IPv6) and name inside a web page 
# 
# Author: David Fernandez (david@dit.upm.es)
# Date:   25/1/2003
#
# It can be easily used with Apache server combined with server side includes (SSI)
# Just activate SSI in your apache server and include the following in your web page:
#	<!--#include virtual="/cgi-bin/printipaddr.pl"-->
#

# Configuration
my $DIG = "/usr/bin/dig";   	# Location of DIG tool
my $GREP = "/bin/grep";   	# Location of GREP tool
my $FS  = 2;               	# Font size
my $IPv6color = "green";
my $IPv4color = "red";
my $DEBUG="";   # Change to something different from "" to see some debug traces


if (!$ARGV[0]) { print "Content-type: text/html\n\n"; } # if called with any argument, do not print 
							# the header.

$addr=$ENV{'REMOTE_ADDR'};


if ($DEBUG) { 
	print "<hr>IP address: $addr<hr>"; 
};

# if address is empty, exit
if (!$addr) { print "Error: no address<br>\n"; exit; }

if ($addr =~ /^[a-fA-F0-9:]+$/) {

	#
	# IPv6 Address
	#
        print "<font size=\"$FS\" color=\"$IPv6color\">Your are using <b>IPv6</b>.  ";
        #print "<br>";
	#$FS--;
	print "<font size=\"$FS\">";
        print "(IP addr: <b>$addr</b>" ;
	print ", ";
	#print "<br>";

	#$addr="2001:618:1:8000::5";  # example IPv6 addr with inverse resolution
	#$addr="2001:800:40:2a05:2e0:81ff:fe05:4657";  # example IPv6 addr without inverse resolution


	$domain=`./convert-ipv6-addr.pl $addr`;
	$intdomain="$domain"."ip6.int";
	$arpadomain="$domain"."ip6.arpa";

	#print "$intdomain"; print "<br>"; print "$arpadomain"; print "<br>";

	# Check whether DIG is available
	if (! -x $DIG) { print "Error: No inverse resolution. DIG tool not found!)<br>"; exit; }

	$ipname=`$DIG -t ptr $intdomain 2>&1 | $GREP PTR 2>&1 | $GREP -v "^;" 2>&1`;
	#print "$ipname"; print "<br>";

	if (!$ipname) {
		print "IP name under ip6.int: <b>NONE</b>";
	} else {
		$i = rindex ($ipname, "PTR") + 4;  	# the position of the name inside the string
							# is the position of PTR plus 4
		$name = substr ($ipname, $i);
		print "IP name under ip6.int: <b>$name</b>";
	} 

	$ipname=`$DIG -t ptr $arpadomain 2>&1 | $GREP PTR 2>&1 | $GREP -v "^;" 2>&1`;
	#print "$ipname";
	#print "<br>";
	if (!$ipname) {
		print ", IP name under ip6.arpa: <b>NONE</b>)";
	} else {
		$i = rindex ($ipname, "PTR") + 4;  	# the position of the name inside the string
							# is the position of PTR plus 4
		$name = substr ($ipname, $i);
		print ", IP name under ip6.arpa: <b>$name</b>)";
	} 

} else {

	#
	# IPv4 Address
	#

        print "<font size=\"$FS\" color=\"$IPv4color\">Your are using <b>IPv4</b>.  ";
        # print "<br>";
	#$FS--;
	print "<font size=\"$FS\">";
        print  "(IP addr: <b>$addr</b>" ;
	print ", ";
	#print "<br>";

	# Check whether DIG is available
	if (! -x $DIG) { print "Error: No inverse resolution. DIG tool not found!)<br></font>"; exit; }

	$ipname=`$DIG -x $addr 2>&1 | $GREP PTR 2>&1 | $GREP -v "^;" 2>&1`;
	#print ("IPname= $ipname"); print "<br>";

	if (!$ipname) {
		print "IP name: <b>NONE)</b>";
	} else {

		$i = rindex ($ipname, "PTR") + 4;  	# the position of the name inside the string
							# is the position of PTR plus 4
		$name = substr ($ipname, $i);
		print "IP name: <b>$name</b>)";
	} 
}

print "</font></font>";

