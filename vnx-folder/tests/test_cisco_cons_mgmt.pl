#!/usr/bin/perl

use strict;
use VNX::CiscoConsMgmt;

#use FindBin;                 # locate this script
#use lib "$FindBin::Bin../tests";  # use the parent directory
#use CiscoExeCmd;


#my $HOST='localhost';
#my $HOST='puerto5';
my $HOST=$ARGV[0];
#my $PORT='12000';
#my $PORT='906';
my $PORT=$ARGV[1];
my $login=$ARGV[2];
my $passwd=$ARGV[3];
my $enable_passwd=$ARGV[4];

my $state=$ARGV[5];

unless (defined $ARGV[5]) { 
	print "\nERROR in parameters. Usage:\n" .
	      "test_cisco_cons_mgmt <host> <port> <login> <passwd> <enable_passwd> <state>\n" .
	      "                     state = (initial, user, enable)\n";
	exit (1);
}


my $sess = new VNX::CiscoConsMgmt ( $HOST, $PORT, $login, $passwd, $enable_passwd, 'use_ztelnet' );
#my $sess = new VNX::CiscoExeCmd ( $HOST, $PORT, $login, $passwd, $enable_passwd );
#my $sess = new CiscoExeCmd ( $HOST, $PORT, $login, $passwd, $enable_passwd );

print "-- host= $sess->{host}\n";
print "-- port= $sess->{port}\n";

my $res = $sess->open ('tserv');
#print "res=$res\n"; 
if (!$res) { print "ERROR: cannot connect to console\n"; exit }

$res = $sess->goto_state ($state, 'debug');
#$res = $sess->goto_initial_state ('debug');
#$res = $sess->goto_enable_mode;
if ($res eq 'timeout') {
    print "ERROR: timeout\n"; exit (1)
} elsif ($res eq 'invalid_login') {
    print "ERROR: invalid login\n"; exit (1)
} elsif ($res eq 'bad_enable_passwd') {
    print "ERROR: invalid enable password\n"; exit (1)
} elsif ($res eq 'user_login_needed') {
    print "ERROR: user login needed but none provided\n"; exit (1)
}

$sess->close;

    
    