#!/usr/bin/perl -w

#
# DIT-UPM Euro6IX Looking Glass
#
# Authors: David Fernandez (david@dit.upm.es) 
#          Maria Jose Perea Moraleda (mjperea@dit.upm.es)
#          Javier Sedano (jsedano@dit.upm.es)
# Date:    8/4/2003
#
# License/Copyright:
#
# This software is distributed under a GNU Public License. It can be freely copied, distributed or modified, 
# as long as the copyright is maintained.
#
# Copyright DIT-UPM, 2003 (www.dit.upm.es)
#

#use strict;

my $DEBUG="";	# Change to something different from "" to see some debug traces

my $version = 'v0.4';
my $date    = '2-Feb-2003';
my $cr      = '(c) DIT-UPM';
my $crmail  = 'david@dit.upm.es';

# Name of the organization
my $title = 'DIT-UPM Euro6IX Looking Glass';
my $htmltitle = 'DIT-UPM Euro6IX Looking Glass';
my $orgname1 = 'Dpto. Ingenier&iacute;a de Sistemas Telem&aacute;ticos';
my $orgname2 = 'Universidad Polit&eacute;cnica de Madrid';
my $orghome = 'http://www.upm.euro6ix.org';
my $logo = '/figures/ditv6-60.gif';

# Location of tools
my $ping  = '/bin/ping'; 			# Location of PING tool
#my $ping  = `which ping`; 			# Location of PING tool
my $ping6 = '/usr/sbin/ping6'; 			# Location of PING6 tool
my $traceroute  = '/usr/sbin/traceroute';	# Location of TRACEROUTE tool
my $traceroute6 = '/usr/sbin/traceroute';	# Location of TRACEROUTE6 tool
my $mtr = `which mtr6`; 			# New location of MTR tool
my $dig = '/usr/bin/dig';			# Location of DIG tool
my $expect = `which expect`; 			# Location of EXPECT tool

# Ping options 
my $NumPings = 5; 		     # Number of pings to send 
my $pingops = "-c $NumPings -w 7";   # "-w n" sets a timeout in case no response is received
                                     # "-c n" sets the number of pings to send

# Traceroute options 
my $DisInverseTransOpt = "-n";	# Command line option to disable inverse translation 
my $trops = "";

# MTR options 
my $mtrops = "--curses --report --report-cycles=5"; # Enable report mode and do 5 tests

# MTR options with IPv6 addresses
my $mtr6ops = "-6 --curses --report --report-cycles=5"; # Enable report mode and do 5 tests


# Interface Colors
my $SepColor="#6666CC"; # other #ccccff"; # other 9999ff"; # other 6666cc";
my $ToolsBarColor="#cc9933";

#
# Possible routers
#
my @routers = ( "Router 1", "Router 2");

# 
# Routers where the commands are executed
# (this is just the description showed; you also have to configure the address in
#  get-router-info-*.exp expect script)
#
my @RouterAddr = ("router 1 r7204.upm.euro6ix.org", "router 2 - r7204.upm.euro6ix.org");
my @RouterDesc = ("DIT-UPM's router connected to MAD6IX", "DIT-UPM's router connected to MAD6IX");

#
# BGP commands
#
my @BGPcommands = ( "show bgp ipv6 summary", "show bgp ipv6", "show bgp ipv6 %prefix%", "show bgp ipv6 neighbors", "show bgp neighbor %prefix% advertised-routes", "show bgp neighbor %prefix% routes", "show bgp summary", "show bgp", "show bgp neighbors");


#
# SHOW commands
#
my @SHOWcommands = ("show ipv6 route %prefix2%",  "show ipv6 route bgp", "show ipv6 route connected", "show ipv6 route local", "show ipv6 route rip", "show ipv6 route static", "show ipv6 route summary" );

#
# DNS query types
#
my @DNSquerytypes = ( "ANY", "A", "AAAA", "PTR", "MX", "NS", "CNAME" );


$|=1;   # forces a flush after every write or print on the currently selected output channel

$ENV{PATH}="";




&PrintHeader ( $htmltitle, $orghome, $logo, $title, $orgname1, $orgname2 );

if ($DEBUG) { print "<font size=1> DEBUG: ping=$ping<br>";}

#
# Parse form data
#
my $ParseRes = &ReadParse;
if ($DEBUG) { print "<font size=1> DEBUG: ParseRes=$ParseRes<br>";}

#
# Show the FORM to select tools and parameters. Show previous values as a default
#

&PrintSeparator ("Tools:", $SepColor);

&PrintMenus ();

if ( ! $ParseRes ) {    # The page is loaded for the first time: no form data

	# Put here hat you want to be shown when the page is loaded for the first time

} else {    # Form data present; process it, execute the command and show the result

	#
	# Parse the query string
	#
	my $qs;
	my $name;
	my $value;

	# DEBUG: print list items of the form data in %in
	if ($DEBUG) {
		print "<hr>";
		print "<font size=1> DEBUG: Decoded query string: ";
    		foreach $key (keys %in) {
        	 	print "  $key= $in{$key},";
    		}
		print "</font><br>";
		print "<hr>";
	}

	if ($in{ir}) {
		$trops = $trops.$DisInverseTransOpt;
	} else {
		$trops = "";
	}

	

	my $command; 

	# Calculate the possition of the select "Router" in the BGP line	
	$n = 0;
	$rbgp=0;
	while ($n <= $#routers) {
		$_ = $routers[$n]; 
		if (/^$in{routerbgp}$/) {
			$rbgp=$n;
		}
		$n = $n + 1;
	}

        $n = 0;
	$rshow=0;
        while ($n <= $#routers) {
                $_ = $routers[$n];
                if (/^$in{routershow}$/) {
                        $rshow=$n;
                }
                $n = $n + 1;
        }
	
	 # Calculate the possition of the select "Router" in the SHOW line

	if ($in{button1} ) { 
		$_ = $in{command1};
	} elsif ($in{button2} ) { 
		$_ = $in{command2};
	} elsif ($in{button3} ) { 
		$_ = $in{command3};
        } elsif ($in{button4} ) {
                $_ = $in{command4};
	} else {
		print "ERROR<br>"
	}

	if (/^ping$/) { 
       		# Check whether PING is available
        	if (! -x $ping) { print "Error: PING tool not found!<br>"; exit; }
		$command = "$ping $pingops $in{addr}"; 
	} elsif (/^ping6$/) { 
       		# Check whether PING6 is available
        	if (! -x $ping6) { print "Error: PING6 tool not found!<br>"; exit; }
		$command = "$ping6 $pingops $in{addr}"; 
	} elsif (/^traceroute$/) { 
       		# Check whether TRACEROUTE is available
        	if (! -x $traceroute) { print "Error: TRACEROUTE tool not found!<br>"; exit; }
		$command = "$traceroute $trops $in{addr}"; 
	} elsif (/^traceroute6$/) { 
       		# Check whether TRACEROUTE6 is available
        	if (! -x $traceroute) { print "Error: TRACEROUTE6 tool not found!<br>"; exit; }
		$command = "$traceroute6 $trops $in{addr}"; 
	} elsif (/^mtr$/) {
                # Check whether MTR is available
                if (! -x $mtr) { print "Error: MTR tool not found!<br>"; exit; }
                $command = "$mtr $mtrops $in{addr}";

	} elsif (/^mtr6$/) { 
       		# Check whether MTR is available
        	if (! -x $mtr) { print "Error: MTR tool not found!<br>"; exit; }
		$command = "$mtr $mtr6ops $in{addr}"; 
	} elsif (/^dns$/) { 
       		# Check whether DIG is available
        	if (! -x $dig) { print "Error: DIG tool not found!<br>"; exit; }
		#if ($in{qt} eq "PTR")  {  # Inverse resolution
			if ($in{dnsaddr} =~ /^[a-fA-F0-9:]+$/) {  # IPv6 address
				$in{qt}=PTR;
				$domain=`./convert-ipv6-addr.pl $in{dnsaddr}`;
				if ($DEBUG) {
					print "dnsaddr=$in{dnsaddr}<br>";
					print "domain=$domain<br>";
				}
				if ( $in{invdomain} eq "ip6.int" ) {
        				$domain="$domain"."ip6.int";
				} else {
        				$domain="$domain"."ip6.arpa";
				}
				$command = "$dig -t $in{qt} $domain"; 
			} else { # IPv4 address
				$domain=`./convert-ipv6-addr.pl $in{dnsaddr}`;
				$command = "$dig -t $in{qt} $domain"; 
			}
		#} else {
		#	$command = "$dig -t $in{qt} $in{dnsaddr}"; 
		#}
	} elsif (/^bgp$/) { 
       		# Check whether EXPECT is available
        	if (! -x $expect) { print "Error: EXPECT tool not found!<br>"; exit; }
		$bgppar = "$in{bgpcmd}";
		$j=$rbgp+1;
		$command = "./get-router-info-$j.exp $bgppar";
		# substitute %prefix% by the prefix value specified
		$_=$in{prefix};
		chop;
		$in{prefix}=$_;
		$command =~ s/%prefix%/$in{prefix}/g;
		
	} elsif (/^show$/) {
                # Check whether EXPECT is available
                if (! -x $expect) { print "Error: EXPECT tool not found!<br>"; exit; }
                $showpar = "$in{showcmd}";
                $command = "./get-router-info.exp $showpar";
                # substitute %prefix% by the prefix value specified
		$command =~ s/%prefix2%/$in{prefix2}/g;
		
	} else { 
		die ("ERROR: unknown command");
	};

	&PrintSeparator ("Results:", $SepColor);

        print "<br>";
        print "<div style=\"margin-left: 30px;\">";

	
        if ( $in{button3} ) {
		$bgppar =~ s/%prefix%/$in{prefix}/g;
		print "<b>Command:</b> &nbsp;&nbsp;&nbsp; <TAB><TAB><b>$bgppar</b><br>";
                # Print router info
                print "<br><b>Router: &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;";
                print "$RouterAddr[$rbgp] ($RouterDesc[$rbgp])</b><br>\n";
        }
	elsif ( $in{button4} ) {
		$showpar =~ s/%prefix%/$in{prefix}/g;
		print "<b>Command:</b> &nbsp;&nbsp;&nbsp; <TAB><TAB><b>$showpar</b><br>";
                # Print router info
                print "<br><b>Router: &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;";
                print "$RouterAddr[$rshow] ($RouterDesc[$rshow])</b><br>\n";
        }
	else {
	        print "<b>Command:</b> &nbsp;&nbsp;&nbsp; <TAB><TAB><b>$command</b><br>";
	}
	print "</div>";
	print "<font size=3>";
	print "<b><PRE style=\"margin-left: 30px;\">";
	$res =  system "$command 2>&1";

	if ($res != 0 ) { print "(res=$res)<br>" };
	print "</PRE></b>";
	print "</font>";

#	if (@ARGV) { $qs = $ARGV[0]; }  # for command line testing only

#	if ((defined $qs) and ($qs ne "" )) {
#	    if ($qs =~ /^t=(.*)/) {
#		$qs=$1;
#	    }
#	    if (($qs =~ /^(\d+\.\d+\.\d+\.\d+)$/) or
#		($qs =~ /^([a-zA-Z0-9][a-zA-Z0-9\.\-_]*)$/)) {
#		$qs = $1;   # unTaint 
#		
#		print "<hr>";
#		print "<b><PRE>";
#		print "$command $in{addr}";
#		system "$command $in{addr}";
#		print "</PRE></b>";
#		print "<hr>";
#	    }
#	}

}


&PrintSeparator ("", $SepColor);
# print IP address of user
print "<center>";
system "./printipaddr.pl noheader 2>&1";

print "<br>";
print "<br>";


#
# DEBUG: print list items of all the supplied environment variables
#
if ($DEBUG) {
	print "<hr>";
	print "<br><font size=1>";
	print "DEBUG:  Environment variables<ul>";
	foreach $key (keys %ENV) { print "<li>$key: $ENV{$key}"; }
	print "</ul>";
	print "</font>";
	print "<hr>";
}
#
# End of Main program
#


###
### ReadParse subroutine
###
### Adapted from cgi-lib.pl by S.E.Brenner@bioc.cam.ac.uk
### Copyright 1994 Steven E. Brenner
### http://www.speakeasy.org/~cgires/readparse.html
###
sub ReadParse {
  local (*in) = @_ if @_;
  local ($i, $key, $val);

  ### replaced his MethGet function
  if ( $ENV{'REQUEST_METHOD'} eq "GET" ) {
	$in = $ENV{'QUERY_STRING'};
	if ($DEBUG) { print "<font size=1> DEBUG: in=$in<br>";}
  } elsif ($ENV{'REQUEST_METHOD'} eq "POST") {
	read(STDIN,$in,$ENV{'CONTENT_LENGTH'});
  } else {
     # Added for command line debugging
     # Supply name/value form data as a command line argument
     # Format: name1=value1\&name2=value2\&...
     # (need to escape & for shell)
     # Find the first argument that's not a switch (-)
     $in = ( grep( !/^-/, @ARGV )) [0];
     $in =~ s/\\&/&/g;
  }
    
  @in = split(/&/,$in);
  if ($DEBUG) { print "<font size=1> DEBUG: in[$i]=$in[$i]<br>";}
    
  foreach $i (0 .. $#in) {
	# Convert plus's to spaces
    	$in[$i] =~ s/\+/ /g;
    
    	# Split into key and value.
    	($key, $val) = split(/=/,$in[$i],2); # splits on the first =.
    
    	# Convert %XX from hex numbers to alphanumeric
    	$key =~ s/%(..)/pack("c",hex($1))/ge;
    	$val =~ s/%(..)/pack("c",hex($1))/ge;
    
    	# Associate key and value. \0 is the multiple separator
    	$in{$key} .= "\0" if (defined($in{$key}));
	$in{$key} .= $val;
        if ($DEBUG) { print "<font size=1> DEBUG: \$in{$key} = $val<br>";}
  }
  return length($in);
}  


sub PrintHeader
  #
  # Show the PAGE HEADER  
  #
  # parameters: $_[0] = HTML title
  # 		$_[1] = Home link
  # 		$_[2] = Logo
  # 		$_[3] = Title
  # 		$_[4] = Organization name 1
  # 		$_[5] = Organization name 2
{

print <<HTML;
Content-type: text/html

  <html><head><title>$_[0]</title></head>
  <body bgcolor="#FFFFEA">
  <font face="Arial" size=2>
  </center>

  <center>
  <table cellpadding="2" cellspacing="2" border="0"
   style="text-align: left; width: 90%;">
    <tbody>
      <tr>

        <td style="vertical-align: top;"><a href="$_[1]"><img src="$_[2]" title="" alt=""
  	 style="border: 0px solid ; "></a><br>
        </td>
        <td style="vertical-align: top; text-align: center;">


        <h3><font face="Arial">$_[3]</font></h3>
        <h4><font face="Arial">$_[4] - $_[5]</font></h4>
        </td>
        <td style="vertical-align: top;"><br>
        </td>
      </tr>
      <tr>
      <td style="vertical-align: top; text-align: center;" rowspan="1" colspan="3">
      <font face="Arial" size="2"><small>&nbsp;<a href=http://www.upm.euro6ix.org>DIT-UPM Looking Glass v0.6<a>. &nbsp;&copy; Copyright DIT-UPM, 2003<br>
      <br>
      </small></font></td>
      <td style="vertical-align: top;"><br>
      </td>
    </tr>
    </tbody>
  </table>
  </center>

HTML
}

sub PrintSeparator
  # parameters: $_[0] = title to show 
  #             $_[1] = background color
{
  if ($_[0]) {  # print a separator line with a title
    print <<HTML;
  	<center>
	<table cellpadding="2" cellspacing="2" border="0"
	 style="text-align: center; width: 95%;">
	<tbody> <tr>
	<td style="vertical-align: top; background-color: $_[1];"><small><span
	style="font-weight: bold; color: rgb(255, 255, 255);">
        $_[0]</span></small><br>
	</td> </tr>
	</tbody>
	</table>
  	</center>
HTML

  }
  else {  # print a thin separator line
    print <<HTML;
  	<center>
        <font face="Arial" size="-5")>	
        <table cellpadding="0" cellspacing="0" border="0"
         style="text-align: left; width: 95%;">
	<tbody> <tr>
	<td height="6" style="vertical-align: top; background-color: $_[1];">
        <small><small><small><small><small><small>
        </small></small></small></small></small></small></td>
	</tr> </tbody> 	
        </table> </font>
  	</center>
HTML

  }

}


sub PrintMenus
  # parameters: $_[0] = ??
  #             $_[1] = ??
{

print <<HTML;
<center>
<br>Please, select tool and parameters and press the start button<br>
</center>

<center>
<table cellpadding="2" cellspacing="2" border="3"
 style="text-align: left; width: 90%; margin-left: auto; margin-right: auto;">
  <tbody>
    <tr style="font-family: helvetica,arial,sans-serif; font-weight: bold;">
      <td
 style="vertical-align: top; background-color: $ToolsBarColor;"><small
 style="color: rgb(255, 255, 255);"><small>Network trace commands:</small></small><br>
      </td>
      <td
 style="vertical-align: top; background-color: $ToolsBarColor;"><small
 style="color: rgb(255, 255, 255);"><small>DNS commands:</small></small><br>
      </td>
    </tr>
HTML

#
# Network trace tools menu
#
print <<HTML;
    <tr style="font-family: helvetica,arial,sans-serif; font-weight: bold;">
      <td style="vertical-align: center; background-color: rgb(255, 255, 255); width: 50%;">
<!-- Network trace tools form -->
<form METHOD="GET"  ACTION="/cgi-bin/ntools.pl">
<font size=1 color=black>
HTML

my $o1=""; my $o2=""; my $o3=""; my $o4=""; my $o5=""; my $o6=""; my $o7="";
$_ = $in{command1};
if (/^ping$/) {
	$o1 = "SELECTED";
} elsif (/^ping6$/) {
	$o2 = "SELECTED";
} elsif (/^traceroute$/) {
	$o3 = "SELECTED";
} elsif (/^traceroute6$/) {
	$o4 = "SELECTED";
} elsif (/^mtr$/) {
	$o5 = "SELECTED";
} elsif (/^mtr6$/) {
        $o6 = "SELECTED";
} elsif (/^show$/) {
        $o7 = "SELECTED";
} else {
};

my $ir="";
$_ = $in{ir};
if (/yes$/)  { $ir="CHECKED"; }

print <<HTML;
<b>Tool:&nbsp;&nbsp;&nbsp;&nbsp;</b> 
     <SELECT NAME="command1">
         <OPTION $o1>ping
         <OPTION $o2>ping6
         <OPTION $o3>traceroute
         <OPTION $o4>traceroute6
         <OPTION $o5>mtr
         <OPTION $o6>mtr6

	  
     </SELECT>
&nbsp;&nbsp;&nbsp;
<b>Disable inverse resolution:</b> 
     <INPUT TYPE="checkbox" NAME="ir" VALUE="yes" $ir>
&nbsp;&nbsp;&nbsp;<br><br>
<b>Address/Name:</b> 
     <input name=addr value="$in{addr}" size=38>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<br>
<center>
<INPUT TYPE="SUBMIT" name="button1" value="    Start    ">
</center>
</font>
</div>
      </td>
HTML

#
# DNS tools menu
#
print <<HTML;
      <td style="vertical-align: top; background-color: rgb(255, 255, 255);">
<!-- DNS tools form -->
<font size=1 color=black>
<b>Tool:&nbsp;&nbsp;&nbsp;&nbsp;</b> 
     <SELECT NAME="command2">
         <OPTION $o6>dns
     </SELECT>
&nbsp;&nbsp;&nbsp;
<b>Query type:</b> 
     <SELECT NAME="qt">
HTML

# print DNS query types list 
my $selected = "";
foreach $cmd (@DNSquerytypes)
{
	$_ = $in{qt};      
	if (/^$cmd$/) { 
       	  $selected = "SELECTED";
	} else {
	  $selected=""
	}
	print "<OPTION $selected>$cmd\n";
}

if ( $in{invdomain} eq "ip6.int" ) {
	$arpa = ""; $int = "CHECKED";
} else {
	$arpa = "CHECKED"; $int = "";
}


print <<HTML;
     </SELECT>
&nbsp;&nbsp;&nbsp;<br><br>
<b>Address/Name:</b> 
     <input name=dnsaddr value="$in{dnsaddr}" size=38>
&nbsp;&nbsp;&nbsp;<br>
<b>Inverse resolution under: &nbsp; &nbsp; &nbsp; &nbsp;</b> 
ip6.arpa <INPUT TYPE="radio" NAME="invdomain" VALUE="ip6.arpa" $arpa>
ip6.int  <INPUT TYPE="radio" NAME="invdomain" VALUE="ip6.int" $int>
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<br>
<center>
<INPUT TYPE="SUBMIT" name="button2" value="    Start    ">
</center>
</font>
</div>
      </td>
    </tr>
HTML


##
## BGP related tools menu
##
#print <<HTML;
#    <tr style="font-family: helvetica,arial,sans-serif; font-weight: bold;">
#      <td
# style="vertical-align: top; background-color: $ToolsBarColor;" colspan="2"><small
# style="color: rgb(255, 255, 255);"><small>BGP related commands:</small></small><br>
#      </td>
#    <tr
# style="font-family: helvetica,arial,sans-serif; font-weight: bold;">
#      <td style="vertical-align: top; background-color: rgb(255, 255, 255);" colspan="2">
#
#<!-- Network trace tools form -->
#<font size=1 color=black>
#<b>Tool:&nbsp;&nbsp;&nbsp;&nbsp;</b> 
#     <SELECT NAME="command3">
#         <OPTION $o6>bgp
#
#     </SELECT>
#&nbsp;
#<b>Router:</b>
#     <SELECT  NAME="routerbgp">
#HTML
#
## print routers list
#my $selected = "";
#foreach $rt (@routers)
#{
#
#        $_ = $in{routerbgp};
#        if (/^$rt$/) {
#          $selected = "SELECTED";
#        } else {
#          $selected=""
#        }
#        print "<OPTION $selected>$rt\n";
#}
#print <<HTML;
#     </SELECT>
#
#&nbsp;
#<b>BGP command:</b> 
#     <SELECT NAME="bgpcmd">
#
#HTML
#
## Print BGP commands
##my $obgpcmd1=""; my $o2=""; my $o3=""; my $o4=""; my $o5=""; my $o6=""; my $o7="";
##$_ = $in{command};      
##if (/^ping$/) { 
##        $o1 = "SELECTED";
##} elsif (/^ping6$/) { 
##        $o2 = "SELECTED";
##} elsif (/^traceroute$/) {
##        $o3 = "SELECTED";
##} elsif (/^traceroute6$/) {
##        $o4 = "SELECTED";
##} elsif (/^dns$/) {
##        $o5 = "SELECTED";
##} elsif (/^bgp$/) {
##        $o6 = "SELECTED";
##} elsif (/^show$/) {
##        $o7 = "SELECTED";
##} else {
##};    
#
## print BGP command list 
#my $selected = "";
#foreach $cmd (@BGPcommands)
#{
##	$_ = $in{bgpcmd};      
##	if (/^$cmd$/) { 
##       	  $selected = "SELECTED";
##	} else {
##	  $selected=""
##	}
#	print "<OPTION $selected>$cmd\n";
#}
#
#
#print <<HTML;
#     </SELECT>
#HTML
#print <<HTML;
#&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
#<b>Prefix:</b> 
#     <input name=prefix value="$in{prefix}">
#&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
#<INPUT TYPE="SUBMIT" name="button3" value="    Start    "><br>
#</font>
#</div>
#      </td>
#    </tr>
#HTML
#
##
## SHOW related tools menu
##
#print <<HTML;
#    <tr style="font-family: helvetica,arial,sans-serif; font-weight: bold;">
#      <td
# style="vertical-align: top; background-color: $ToolsBarColor;" colspan="2"><small
# style="color: rgb(255, 255, 255);"><small>Routing display commands:</small></small><br>
#      </td>
#    <tr
# style="font-family: helvetica,arial,sans-serif; font-weight: bold;">
#      <td style="vertical-align: top; background-color: rgb(255, 255, 255);" colspan="2">
#
#
#<!-- Route show tools form -->
#<font size=1 color=black>
#<b>Tool:&nbsp;&nbsp;&nbsp;&nbsp;</b>
#     <SELECT NAME="command4">
#         <OPTION $o7>show
#	 
#
#     </SELECT>
#
#&nbsp;
#<b>Router:</b>
#     <SELECT  NAME="routershow">
#HTML
#
#
## print routers list
#my $selected = "";
#foreach $rt (@routers)
#{
#
##        $_ = $in{routershow};
##        if (/^$rt$/) {
##          $selected = "SELECTED";
##        } else {
##          $selected=""
##        }
#        print "<OPTION $selected>$rt\n";
#}
#
#print <<HTML;
#     </SELECT>
#
#
#
#
#
#
#
#<b>SHOW command:</b>
#     <SELECT NAME="showcmd">
#HTML
#
#
## Print SHOW commands
##my $oshcmd1=""; my $o2=""; my $o3=""; my $o4=""; my $o5=""; my $o6=""; my $o7="";
##$_ = $in{command};
##if (/^ping$/) {
##        $o1 = "SELECTED";
##} elsif (/^ping6$/) {
##        $o2 = "SELECTED";
##} elsif (/^traceroute$/) {
##        $o3 = "SELECTED";
##} elsif (/^traceroute6$/) {
##        $o4 = "SELECTED";
##} elsif (/^dns$/) {
##        $o5 = "SELECTED";
##} elsif (/^bgp$/) {
##        $o6 = "SELECTED";
##} elsif (/^show$/) {
##        $o7 = "SELECTED";
##} else {
##};
#
#
## print show command list
#my $selected = "";
#foreach $cmd (@SHOWcommands)
#{
##        $_ = $in{showcmd};
##        if (/^$cmd$/) {
##          $selected = "SELECTED";
##        } else {
##          $selected=""
##        }
#        print "<OPTION $selected>$cmd\n";
#}
#print <<HTML;
#
#     </SELECT>
#&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
#<b>Prefix:</b>
#      <input name=prefix value 2="$in{prefix2}">
#&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
#<INPUT TYPE="SUBMIT" name="button4" value="    Start    ">
#</font>

print <<HTML;   # AÑADIDO
</form>
</div>
      </td>
    </tr>


  </tbody>
</table>
</center>

<br>
HTML
}
