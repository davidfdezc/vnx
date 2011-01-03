#!/usr/bin/perl

use strict;
use Net::Telnet;

#my $HOST='puerto5.lab.dit.upm.es';
my $HOST='localhost';
#my $PORT='919';
my $PORT='920';
my $login='root';
my $passwd='xxxx';
my $enable_passwd='xxxx';

my $cmd = $ARGV[0];
my @cmdoutput;

my $state;
my $user_prompt = '[\w.-]+\s*\>\s*$';
my $priv_prompt = '[\w.-]+\s*#\s*$';
my $username_prompt = 'Username:.*$';
my $passwd_prompt = 'Password:.*$';
my $config_prompt = '[\(]config[\w-]*[\)]#$';
my $invalidlogin_prompt = 'Login invalid';
my $initial_prompt ='Press RETURN to get started.';
my $prematch;
my $match;

if ($cmd eq "") { print "Usage: xx 'cisco cmd'\n"; exit (1) }

my $session = new Net::Telnet ( Input_log => "input.log", 
                                #Output_log => "output.log", 
                                Timeout => 3,
                                Errmode => 'return');
my $res = $session->open(Host => $HOST, Port => $PORT);

if (!$res) { print "ERROR: cannot connect to console\n"; exit }

$state = &goToEnableMode ($session);
if ($state eq 'timeout') {
    print "ERROR: timeout\n"; exit (1) 
}
elsif ($state eq 'invalidlogin') { 
    print "ERROR: invalid login\n"; exit (1) 
}

print("-- sending command $cmd\n");
@cmdoutput = $session->cmd(String => "$cmd", Prompt  => "/$user_prompt|$priv_prompt|$config_prompt|$initial_prompt/");
print "-- cmd result: \n\n@cmdoutput\n";

#$session->print("$cmd");
#($prematch, $match) = $session->waitfor("/$user_prompt|$priv_prompt|$config_prompt|$initial_prompt/");
#print "-- prematch = $prematch\n"; print "-- match = $match\n";
if ($session->timed_out) { print "ERROR: timeout\n"; exit (1) }

$session->close;

exit;


sub goToEnableMode {

    my $session = shift;

    my $user_prompt='[\w.-]+\s*\>\s*$';
    my $priv_prompt   ='[\w.-]+\s*#\s*$';
    my $username_prompt  ='Username:.*$';
    my $passwd_prompt ='Password:.*$';
    my $config_prompt ='[\(]config[\w-]*[\)]#$';
    my $invalidlogin_prompt ='Login invalid';
    my $more_prompt ='--More--';
    my $prematch;
    my $match;
    my $state;

    print "-- goToEnableMode called\n";
    $session->print("\n");
    do {
        my $i=2;
        do {
            #print "-- try $i\n";
            ($prematch, $match) = $session->waitfor( "/$user_prompt|$priv_prompt|$username_prompt|$passwd_prompt|$config_prompt|$invalidlogin_prompt|$more_prompt/" );
            print "-- match=$match\n";
            $i--;
        } until ( !($session->timed_out) || $i == "0" ); 
 
        if ($session->timed_out) { print "ERROR: Timeout waiting for prompt, exiting!\n"; return "timeout"}

        if ($match =~ m/$username_prompt/) {
            # Username
            print "-- 'Username:' prompt detected, providing username\n";
            $session->print($login);
            $session->waitfor("/$passwd_prompt/");
            if ($session->timed_out) { print "timeout\n"; return "timeout" }
            print "-- 'Password:' detected, providing password\n";
            $session->print($passwd);
            $state = 'userAuthInfoProvided';
        } 
        elsif ($match =~ m/$passwd_prompt/) {
            # Password
            print "-- 'Password:' detected, providing password\n";
            $session->print($passwd);
            $state = 'userAuthInfoProvided';
        } 
        elsif ($match =~ m/$config_prompt/) {
            # Config mode
            print "-- Router in Config mode\n";
            $session->print("\cZ");
            $state = 'config';
        }
        elsif ($match =~ m/$user_prompt/) {
            # Non priviledged mode
            print "-- Router in User mode; changing to priviledged mode (enable command)\n";
            $session->print('enable');
            $session->waitfor("/$passwd_prompt/");
            if ($session->timed_out) { print "timeout\n"; return "timeout" }
            print "-- 'Password:' detected, providing enable password\n";
            $session->print($enable_passwd);
            $state = 'enableSent';
        }
        elsif ($match =~ m/$priv_prompt/) {
            # Priviledged mode
            print "-- Router in Priviledged mode\n";
            $session->buffer_empty;
            $state = 'priviledged';
        }
        elsif ($match =~ m/$invalidlogin_prompt/) {
            $state = 'invalidlogin';
        } 
        elsif ($match =~ m/$more_prompt/) {
            # More mode
            print "-- Router in More mode\n";
            $session->print("q");
            $state = 'more';
        }
        else {
            $state = 'unknown';
        }
        print "-- state = $state\n";

    } until ( ($session->timed_out) || $state eq "priviledged" || $state eq "invalidlogin" );

    if ($session->timed_out) { 
        return 'timeout'
    } elsif ($state eq "invalidlogin") { 
        return 'invalidlogin' 
    } elsif ($state eq "priviledged") { 
        print("-- sending 'terminal length 0' command\n");
        @cmdoutput = $session->cmd(String => "terminal length 0", Prompt  => "/$priv_prompt/");
        #$session->print("terminal length 0");
        #($prematch, $match) = $session->waitfor("/$priv_prompt/");
        #print "-- prematch = $prematch\n"; print "-- match = $match\n";
        if ($session->timed_out) { return 'timeout' } else { return 'priviledged' }
    }

}