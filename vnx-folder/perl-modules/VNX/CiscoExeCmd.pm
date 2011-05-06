# CiscoExeCmd.pm
#
# This file is a module part of VNX package.
#
# Author: David Fernández (david@dit.upm.es)
# Copyright (C) 2010, 	DIT-UPM
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

# CiscoExeCmd module provides auxiliar routines to execute commands over Cisco routers. 

package VNX::CiscoExeCmd;

use strict;
use warnings;

use Net::Telnet;

my $user_prompt = '[\w.-]+\s*\>\s*$';
my $priv_prompt = '[\w.-]+\s*#\s*$';
my $username_prompt = 'Username:.*$';
my $passwd_prompt = 'Password:.*$';
my $config_prompt = '[\(]config[\w-]*[\)]#$';
my $invalidlogin_prompt = 'Login invalid';
my $initial_prompt ='Press RETURN to get started.';
my $more_prompt ='--More--';

###########################################################################
# CLASS CONSTRUCTOR
#
# Arguments:
#
# - host
# - port
# - login
# - passwd
# - enable_passwd
#
sub new {
    my $class = shift;
    my $self = {};
    bless $self;

    #print "-- new called (host\n";
    $self->{'host'} = shift;
    $self->{'port'} = shift;
    $self->{'login'} = shift;
    $self->{'passwd'} = shift;
    $self->{'enable_passwd'} = shift;
    #print "-- new called (host=$self->{'host'},port=$self->{'port'},login=$self->{'login'},passwd=$self->{'passwd'},enable_pass=$self->{'enable_passwd'}\n";

    $self->{'session'} = new Net::Telnet ( Input_log => "input.log", 
                                #Output_log => "output.log", 
                                Timeout => 3,
                                Errmode => 'return');
    return $self;  
}

sub open {

    my $self = shift;
    #print "-- open called\n";

    my $res = $self->{session}->open(Host => $self->{host}, Port => $self->{port});
    return $res;

}

sub goToEnableMode {

    my $self = shift;
    my $session = $self->{session};

    my $prematch;
    my $match;
    my $state;

    #print "-- goToEnableMode called\n";
    $session->print("q\n");
    do {
        my $i=2;
        do {
            #print "-- try $i\n";
            ($prematch, $match) = $session->waitfor( "/$user_prompt|$priv_prompt|$username_prompt|$passwd_prompt|$config_prompt|$invalidlogin_prompt|$more_prompt/" );
            #print "-- match=$match\n";
            $i--;
        } until ( !($session->timed_out) || $i == "0" ); 
 
        if ($session->timed_out) { print "ERROR: Timeout waiting for prompt, exiting!\n"; return "timeout"}

        if ($match =~ m/$username_prompt/) {
            # Username
            #print "-- 'Username:' prompt detected, providing username ($self->{login})\n";
            $session->print($self->{login});
            $session->waitfor("/$passwd_prompt/");
            if ($session->timed_out) { print "timeout\n"; return "timeout" }
            #print "-- 'Password:' detected, providing password\n";
            $session->print($self->{passwd});
            $state = 'userAuthInfoProvided';
        } 
        elsif ($match =~ m/$passwd_prompt/) {
            # Password
            #print "-- 'Password:' detected, providing password\n";
            $session->print($self->{passwd});
            $state = 'userAuthInfoProvided';
        } 
        elsif ($match =~ m/$config_prompt/) {
            # Config mode
            #print "-- Router in Config mode\n";
            $session->print("\cZ");
            $state = 'config';
        }
        elsif ($match =~ m/$user_prompt/) {
            # Non priviledged mode
            #print "-- Router in User mode; changing to priviledged mode (enable command)\n";
            $session->print('enable');
            #$session->waitfor("/$passwd_prompt|$priv_prompt/");
            #if ($session->timed_out) { print "timeout\n"; return "timeout" }
            #print "-- 'Password:' detected, providing enable password\n";
            #$session->print($self->{enable_passwd});
            $state = 'enableSent';
        }
        elsif ($match =~ m/$priv_prompt/) {
            # Priviledged mode
            #print "-- Router in Priviledged mode\n";
            $session->buffer_empty;
            $state = 'priviledged';
        }
        elsif ($match =~ m/$invalidlogin_prompt/) {
            $state = 'invalidlogin';
        } 
        elsif ($match =~ m/$more_prompt/) {
            # More mode
            #print "-- Router in More mode\n";
            $session->print("q");
            $state = 'more';
        }
        else {
            $state = 'unknown';
        }
        #print "-- state = $state\n";

    } until ( ($session->timed_out) || $state eq "priviledged" || $state eq "invalidlogin" );

    if ($session->timed_out) { 
        return 'timeout'
    } elsif ($state eq "invalidlogin") { 
        return 'invalidlogin' 
    } elsif ($state eq "priviledged") { 
        #print("-- sending 'terminal length 0' command\n");
        my @cmdoutput = $session->cmd(String => "terminal length 0", Prompt  => "/$priv_prompt/");
        #$session->print("terminal length 0");
        #($prematch, $match) = $session->waitfor("/$priv_prompt/");
        #print "-- prematch = $prematch\n"; print "-- match = $match\n";
        if ($session->timed_out) { return 'timeout' } else { return 'priviledged' }
    }

}

sub goToUserMode {

    my $self = shift;
    my $session = $self->{session};

    my $res = $self->goToEnableMode;
    $self->exeCmd ("disable");
    return $res;

}

sub exeCmd {

    my $self = shift;
    my $cmd = shift;
    my $session = $self->{session};

    #print("-- exeCmd: $cmd\n");
    my @cmdoutput = $session->cmd(String => "$cmd", Prompt  => "/$user_prompt|$priv_prompt|$config_prompt|$initial_prompt/");
    return @cmdoutput;

    #$session->print("$cmd");
    #($prematch, $match) = $session->waitfor("/$user_prompt|$priv_prompt|$config_prompt|$initial_prompt/");
    #print "-- prematch = $prematch\n"; print "-- match = $match\n";
    #if ($session->timed_out) { print "ERROR: timeout\n"; exit (1) }

}

sub exeCmdFile {

    my $self = shift;
    my $cmdFile = shift;
    my $session = $self->{session};
    my $command_tag;
    my @cmdfileoutput;
    my @cmdoutput;

    CORE::open (INCLUDE_FILE, "$cmdFile") or return "ERROR: cannot open $cmdFile";
    while (<INCLUDE_FILE>) {
	# Se van ejecutando linea por linea
	chomp;
	$command_tag = $_;
	#print "-- cmdFile: $command_tag\n";
	# Execute command
        @cmdoutput = $self->exeCmd ("$command_tag");
	# Add command output to @cmdfileoutput
        @cmdfileoutput = (@cmdfileoutput, "$command_tag\n", @cmdoutput);
    }
    close INCLUDE_FILE;
    return @cmdfileoutput;

}

sub close {

    my $self = shift;
    my $session = $self->{session};

    $session->close();

}

1;