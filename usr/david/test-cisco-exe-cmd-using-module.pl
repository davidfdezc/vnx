#!/usr/bin/perl

use strict;
use VNX::CiscoExeCmd;


my $HOST='localhost';
my $PORT='920';
my $login='root';
my $passwd='xxxx';
my $enable_passwd='xxxx';


my $sess = new CiscoExeCmd ( $HOST, $PORT, $login, $passwd, $enable_passwd );

print "-- host= $sess->{host}\n";
print "-- port= $sess->{port}\n";


my $HOST='localhost';
my $PORT='921';
my $login='root';
my $passwd='xxxx';
my $enable_passwd='xxxx';


my $sess2 = new CiscoExeCmd ( $HOST, $PORT, $login, $passwd, $enable_passwd );

print "-- host= $sess2->{host}\n";
print "-- port= $sess2->{port}\n";


my $res = $sess->open;
if (!$res) { print "ERROR: cannot connect to console\n"; exit }

$res = $sess->goToEnableMode;
if ($res eq 'timeout') {
    print "ERROR: timeout\n"; exit (1) 
}
elsif ($res eq 'invalidlogin') { 
    print "ERROR: invalid login\n"; exit (1) 
}

my @cmdoutput = $sess->exeCmd ("show clock");
print "-- cmd result: \n\n@cmdoutput\n";

@cmdoutput = $sess->exeCmd ("show ip inter brief");
print "-- cmd result: \n\n@cmdoutput\n";

@cmdoutput = $sess->exeCmdFile ("test.conf");
print "-- cmd result: \n\n@cmdoutput\n";

$res = $sess->goToUserMode;
if ($res eq 'timeout') {
    print "ERROR: timeout\n"; exit (1) 
}
elsif ($res eq 'invalidlogin') { 
    print "ERROR: invalid login\n"; exit (1) 
}


$sess->close;
