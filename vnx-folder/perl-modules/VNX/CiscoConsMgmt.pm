# CiscoConsMgmt.pm
#
# This file is a module part of VNX package.
#
# Author: David Fernández (david@dit.upm.es)
# Copyright (C) 2012,   DIT-UPM
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

# CiscoExeCmd module provides auxiliar routines to execute commands over Cisco routers. 

package VNX::CiscoConsMgmt;

use strict;
use warnings;

use Net::Telnet;
use Time::HiRes;

my $user_prompt = '[\w.-]+\s*\>\s*$';
my $priv_prompt = '[\w.-]+\s*#\s*$';
my $username_prompt = 'Username:.*$';
my $passwd_prompt = 'Password:.*$';
my $config_prompt = '[\(]config[\w-]*[\)]#$';
my $invalidlogin_prompt = 'Login invalid';
my $initial_prompt ='Press RETURN to get started.';
my $more_prompt ='--More--';
my $bad_passwds ='% Bad passwords';


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
    $self->{'use_ztelnet'} = shift;

    #print "-- new called (host=$self->{'host'},port=$self->{'port'},login=$self->{'login'},passwd=$self->{'passwd'},enable_pass=$self->{'enable_passwd'}\n";

#    $self->{'session'} = new Net::Telnet ( Input_log => "input.log", 
#                                Output_log => "output.log", 
#                                Timeout => 3,
#                                Errmode => 'return');
    return $self;  
}

sub open {

    my $self = shift;
    my $check_tserv_msg = shift;  

    my $res;
    #print "-- open called\n";

    unless (defined $self->{'host'}) {
        print "ERROR: host not defined\n"; return 0;
    }
    unless (defined $self->{'port'}) {
        print "ERROR: port not defined\n"; return 0;
    }
    unless (defined $self->{'login'}) {
        print "ERROR: login username not defined\n"; return 0;
    }
    unless (defined $self->{'passwd'}) {
        print "ERROR: login passwd not defined\n"; return 0;
    }
    unless (defined $self->{'enable_passwd'}) {
        print "ERROR: enable_passwd not defined\n"; return 0;
    }

    if ($self->{'use_ztelnet'}) {

        $self->{'pty'} = &_spawn ( "ztelnet", "--zssh-escape", "^X", $self->{host}, $self->{port});
        $self->{'session'} = new Net::Telnet (-fhopen => $self->{'pty'},
                                Timeout => 3,
                                -cmd_remove_mode => 1,
                                -output_record_separator => "\r",
                                Input_log => "input.log", 
                                Output_log => "output.log", 
                                Dump_Log => "dump.log",
                                Timeout => 3,
                                Errmode => 'return');
        $res = 1;

    } else {

        $self->{'session'} = new Net::Telnet ( Input_log => "input.log", 
                                    Output_log => "output.log", 
                                    Timeout => 3,
                                    Errmode => 'return');

        $res = $self->{session}->open(Host => $self->{host}, Port => $self->{port});

    }

    # send something to the router console to make it react...
    $self->{session}->print("");
    Time::HiRes::sleep(0.3);
    $self->{session}->print("");

    if (defined $check_tserv_msg) {

        print "Checking if the console is free...\n";

        $self->{session}->waitfor(Timeout => 3, String => "Selected hunt group busy");
        if ($self->{session}->timed_out) {
            print "Console free\n"
        } else {
            print "ERROR: console returns 'Selected hunt group busy'\n";
            $res = 0;
        }

    }
    return $res;

}


sub close {

    my $self = shift;
    my $session = $self->{session};

    $session->close();

    if ($self->{'use_ztelnet'}) {
        CORE::close($self->{'pty'})
    }

}

# taken from http://www.perlmonks.org/?node_id=582185
sub _spawn {
        my(@cmd) = @_;
        my($pid, $pty, $tty, $tty_fd);
        ## Create a new pseudo terminal. 
        use IO::Pty ();
        $pty = new IO::Pty
            or die $!;
        ## Execute the program in another process. 
        unless ($pid = fork) {  # child process 
            die "problem spawning program: $!\n" unless defined $pid;
            #print "pid = $pid\n";
            ## Disassociate process from existing controlling terminal. 
            use POSIX ();
            POSIX::setsid
                or die "setsid failed: $!";
            ## Associate process with a new controlling terminal. 
            $tty = $pty->slave;
            $pty->make_slave_controlling_terminal();
            $tty_fd = $tty->fileno;
            CORE::close $pty;
            ## Make stdio use the new controlling terminal. 
            CORE::open STDIN, "<&$tty_fd" or die $!;
            CORE::open STDOUT, ">&$tty_fd" or die $!;
            CORE::open STDERR, ">&STDOUT" or die $!;
            CORE::close $tty;
            ## Execute requested program. 
            exec @cmd
                or die "problem executing $cmd[0]\n";
        } # end child process 
        $pty;
} # end sub spawn


sub goto_state {

    my $self = shift;
    my $final_state = shift;
    my $debug = shift;
    unless (defined $debug) { $debug='' }
        
    my $session = $self->{session};

    my $prematch;
    my $match;
    my $state = 'unknown';
    my $passwd_seen;

    print "-- goto_state: let's take the console to $final_state state\n" if $debug;

    # send something to the router console to make it react...
    #$session->print("");
    #Time::HiRes::sleep(0.3);
    #$session->print("");

    # First we take the console to User mode
    do {
        my $i=2;
        do {
            print "-- goto_state: try $i\n" if $debug;
            ($prematch, $match) = $session->waitfor( "/$user_prompt|$priv_prompt|$username_prompt|$passwd_prompt|" . 
                                                     "$config_prompt|$invalidlogin_prompt|$more_prompt|$bad_passwds/" );
            if (defined $match) { print "-- goto_state: match=$match\n" if $debug; }
            $i--;
        } until ( !($session->timed_out) || $i == "0" ); 
 
        if ($session->timed_out) { print "ERROR: Timeout waiting for prompt, exiting!\n"; return "timeout"}

        if ($match =~ m/$username_prompt/) {
            # Username
            unless ( defined $self->{'login'} && $self->{'login'} ne '' ) {
            return 'user_login_needed'; 
            }
            print "-- goto_state: 'Username:' prompt detected, providing username ($self->{login})\n" if $debug;
            $session->print($self->{login});
            $state ='login_sent';
        } 
        elsif ($match =~ m/$passwd_prompt/) {
            # Password
        if ( defined $state && $state eq 'login_sent' ) {
                print "-- goto_state: 'Password:' detected, providing login password ($self->{passwd})\n" if $debug;
                $session->print($self->{passwd});
                $state = 'user_auth_info_sent';
            } else {
                print "-- goto_state: 'Password:' detected in unknown state\n" if $debug;
        # Maybe the console is waiting for enable password but we do not know...
                # we type return three times to change the status and we continue... 
                $session->print(); 
                Time::HiRes::sleep(0.1);
                $session->print();
                Time::HiRes::sleep(0.1);
                $session->print();
            $state = 'unknown';
            }
        } 
        elsif ($match =~ m/$config_prompt/) {
            # Config mode
            print "-- goto_state: router in config mode\n" if $debug;
            $session->print("\cZ");
            $state = 'config';
        }
        elsif ($match =~ m/$user_prompt/) {
            # Non priviledged mode
            print "-- goto_state: router in user mode\n" if $debug;
            #$session->buffer_empty;
            $state = 'user';
        }
        elsif ($match =~ m/$priv_prompt/) {
            # Priviledged mode
            print "-- goto_state: router in priviledged mode; changing to user mode (disable command)\n" if $debug;
            $session->print('disable');
            $state = 'disable_sent';
        }
        elsif ($match =~ m/$invalidlogin_prompt/) {
            # Invalid login
            print "-- goto_state: invalid login\n" if $debug;
            if ($passwd_seen) {
                return 'invalid_login';
            } else {
                #sleep 1;
                $session->print('');
                $passwd_seen = 'true';
            }           
        } 
        elsif ($match =~ m/$more_prompt/) {
            # More mode
            print "-- goto_state: router in More mode\n" if $debug;
            $session->print("q");
            $state = 'more';
        }
        elsif ($match =~ m/$bad_passwds/) {
            # Bad enable password
            print "-- goto_state: bad enable password\n" if $debug;
            if ($passwd_seen) {
                return 'bad_enable_passwd';
            } else {
                $passwd_seen = 'true';
            }
        }
        else {
            $state = 'unknown';
        }
        if (defined $state) { print "-- goto_state: state = $state\n" if $debug; }

    } until ( ($session->timed_out) || $state eq "user" );

    if ($session->timed_out) { 
        return 'timeout'
    } elsif ($state eq "user") { 

        print "-- goto_state: approaching final state...\n" if $debug;

    # Once in User mode, we take the console to $final_state
    if ($final_state eq 'initial') {

            print "-- goto_state: router in User mode; sending exit to go to 'initial state\n" if $debug;
            $session->print('exit');
            print "-- goto_state: router console in initial state\n" if $debug;

        } elsif ($final_state eq 'user') {

            print("-- goto_state: sending 'terminal length 0' command\n") if $debug;
            my @cmdoutput = $session->cmd(String => "terminal length 0", Prompt  => "/$user_prompt/");
            if ($session->timed_out) { return 'timeout' } 
            print "-- goto_state: router console in user mode\n" if $debug;

        } elsif ($final_state eq 'enable') {
            
            my @cmdoutput = $session->cmd(String => "enable", Prompt  => "/$passwd_prompt/");
            if ($session->timed_out) { return 'timeout' }
            $session->print($self->{enable_passwd});
            print("-- goto_state: sending 'enable' password\n") if $debug;
            ($prematch,$match) = $session->waitfor( "/$priv_prompt|$bad_passwds|$passwd_prompt/" );
            if ($session->timed_out) { return 'timeout' }
            print("-- goto_state: match = $match\n") if $debug;
            if ($match =~ m/$priv_prompt/) {
                print("-- goto_state: sending 'terminal length 0' command\n") if $debug;
                @cmdoutput = $session->cmd(String => "terminal length 0", Prompt  => "/$priv_prompt/");
                if ($session->timed_out) { return 'timeout' } 
                print "-- goto_state: router console in priviledge mode\n" if $debug;
            } else {
                return 'bad_enable_passwd';
            }

        } else {

            return "unknown_final_state";

        }

    }
    return;

}

sub goto_initial_state {

    my $self = shift;
    my $debug = shift;

    return $self->goto_state ('initial', $debug);


    unless (defined $debug) { $debug='' }
        
    my $session = $self->{session};

    my $prematch;
    my $match;
    my $state;

    print "-- go_to_initial_state: called\n" if $debug;
    #$session->print("q\n");
    ##$session->print("q");
    $session->print("");
    Time::HiRes::sleep(0.3);
    $session->print("");
    print "-- go_to_initial_state: called\n" if $debug;
    do {
        my $i=2;
        do {
            print "-- go_to_initial_state: try $i\n" if $debug;
            ($prematch, $match) = $session->waitfor( "/$user_prompt|$priv_prompt|$username_prompt|$passwd_prompt|$config_prompt|$invalidlogin_prompt|$more_prompt|$bad_passwds/" );
            print "-- go_to_initial_state: match=$match\n" if $debug;
            $i--;
        } until ( !($session->timed_out) || $i == "0" ); 
 
        if ($session->timed_out) { print "ERROR: Timeout waiting for prompt, exiting!\n"; return "timeout"}

        if ($match =~ m/$username_prompt/) {
            # Username
            unless ( defined $self->{'login'} && $self->{'login'} ne '' ) {
            return 'user_login_needed'; 
            }
            print "-- go_to_initial_state: 'Username:' prompt detected, providing username ($self->{login})\n" if $debug;
            $session->print($self->{login});
            $session->waitfor("/$passwd_prompt/");
            if ($session->timed_out) { print "timeout\n"; return "timeout" }
            print "-- go_to_initial_state: 'Password:' detected, providing password\n" if $debug;
            $session->print($self->{passwd});
            $state = 'user_auth_info_sent';
        } 
        elsif ($match =~ m/$passwd_prompt/) {
            # Password
            print "-- go_to_initial_state: 'Password:' detected, providing password ($self->{enable_passwd})\n" if $debug;
            $session->print($self->{enable_passwd});
            $state = 'user_auth_info_sent';
        } 
        elsif ($match =~ m/$config_prompt/) {
            # Config mode
            print "-- go_to_initial_state: Router in Config mode\n" if $debug;
            $session->print("\cZ");
            $state = 'config';
        }
        elsif ($match =~ m/$user_prompt/) {
            # Non priviledged mode
            print "-- go_to_initial_state: Router in User mode; sending exit\n" if $debug;
            $session->print('exit');
            #$session->waitfor("/$passwd_prompt|$priv_prompt/");
            #if ($session->timed_out) { print "timeout\n"; return "timeout" }
            #print "-- 'Password:' detected, providing enable password\n";
            #$session->print($self->{enable_passwd});
            $state = 'exitSent';
        }
        elsif ($match =~ m/$priv_prompt/) {
            # Priviledged mode
            print "-- go_to_initial_state: Router in Priviledged mode; sending exit\n" if $debug;
            $session->buffer_empty;
            $session->print('exit');
            $state = 'exitSent';
        }
        elsif ($match =~ m/$invalidlogin_prompt/) {
            return 'invalid_login';
        } 
        elsif ($match =~ m/$more_prompt/) {
            # More mode
            print "-- go_to_initial_state: Router in More mode\n" if $debug;
            $session->print("q");
            $state = 'more';
        }
        elsif ($match =~ m/$bad_passwds/) {
            print "-- go_to_initial_state: Bad enable password\n" if $debug;
            return 'bad_enable_passwd';
        }
        else {
            $state = 'unknown';
        }
        print "-- go_to_initial_state: state = $state\n" if $debug;

    } until ( ($session->timed_out) || $state eq "exitSent" );

    if ($session->timed_out) { 
        return 'timeout'
    } elsif ($state eq "exitSent") { 

    }

}

sub goto_enable_mode {

    my $self = shift;
    my $debug = shift;

    return $self->goto_state ('enable', $debug);

    unless (defined $debug) { $debug='' }
        
    my $session = $self->{session};

    my $prematch;
    my $match;
    my $state;

    print "-- goto_enable_mode: called\n" if $debug;
    #$session->print("q\n");
    ##$session->print("q");
    $session->print("");
    Time::HiRes::sleep(0.3);
    $session->print("");
    print "-- goto_enable_mode: called\n" if $debug;
    do {
        my $i=2;
        do {
            print "-- goto_enable_mode: try $i\n" if $debug;
            ($prematch, $match) = $session->waitfor( "/$user_prompt|$priv_prompt|$username_prompt|$passwd_prompt|$config_prompt|$invalidlogin_prompt|$more_prompt|$bad_passwds/" );
            print "-- goto_enable_mode: match=$match\n" if $debug;
            $i--;
        } until ( !($session->timed_out) || $i == "0" ); 
 
        if ($session->timed_out) { print "ERROR: Timeout waiting for prompt, exiting!\n"; return "timeout"}

        if ($match =~ m/$username_prompt/) {
            # Username
            unless ( defined $self->{'login'} && $self->{'login'} ne '' ) {
            return 'user_login_needed'; 
            }
            print "-- goto_enable_mode: 'Username:' prompt detected, providing username ($self->{login})\n" if $debug;
            $session->print($self->{login});
            $session->waitfor("/$passwd_prompt/");
            if ($session->timed_out) { print "timeout\n"; return "timeout" }
            print "-- goto_enable_mode: 'Password:' detected, providing password\n" if $debug;
            $session->print($self->{passwd});
            $state = 'user_auth_info_sent';
        } 
        elsif ($match =~ m/$passwd_prompt/) {
            # Password
            print "-- goto_enable_mode: 'Password:' detected, providing password ($self->{enable_passwd})\n" if $debug;
            $session->print($self->{enable_passwd});
            $state = 'user_auth_info_sent';
        } 
        elsif ($match =~ m/$config_prompt/) {
            # Config mode
            print "-- goto_enable_mode: Router in Config mode\n" if $debug;
            $session->print("\cZ");
            $state = 'config';
        }
        elsif ($match =~ m/$user_prompt/) {
            # Non priviledged mode
            print "-- goto_enable_mode: Router in User mode; changing to priviledged mode (enable command)\n" if $debug;
            $session->print('enable');
            #$session->waitfor("/$passwd_prompt|$priv_prompt/");
            #if ($session->timed_out) { print "timeout\n"; return "timeout" }
            #print "-- 'Password:' detected, providing enable password\n";
            #$session->print($self->{enable_passwd});
            $state = 'enable_sent';
        }
        elsif ($match =~ m/$priv_prompt/) {
            # Priviledged mode
            print "-- goto_enable_mode: Router in Priviledged mode\n" if $debug;
            $session->buffer_empty;
            $state = 'priviledged';
        }
        elsif ($match =~ m/$invalidlogin_prompt/) {
            return 'invalid_login';
        } 
        elsif ($match =~ m/$more_prompt/) {
            # More mode
            print "-- goto_enable_mode: Router in More mode\n" if $debug;
            $session->print("q");
            $state = 'more';
        }
        elsif ($match =~ m/$bad_passwds/) {
            print "-- goto_enable_mode: Bad enable password\n" if $debug;
            return 'bad_enable_passwd';
        }
        else {
            $state = 'unknown';
        }
        print "-- goto_enable_mode: state = $state\n" if $debug;

    } until ( ($session->timed_out) || $state eq "priviledged" );

    if ($session->timed_out) { 
        return 'timeout'
    } elsif ($state eq "priviledged") { 
        print("-- goto_enable_mode: sending 'terminal length 0' command\n") if $debug;
        my @cmdoutput = $session->cmd(String => "terminal length 0", Prompt  => "/$priv_prompt/");
        #$session->print("terminal length 0");
        #($prematch, $match) = $session->waitfor("/$priv_prompt/");
        print "-- goto_enable_mode: prematch = $prematch\n" if $debug; 
        print "-- goto_enable_mode: match = $match\n" if $debug;
        if ($session->timed_out) { return 'timeout' } else { return 'priviledged' }
    }

}

sub goto_user_mode {

    my $self = shift;
    my $debug = shift;

    return $self->goto_state ('user', $debug);



    unless (defined $debug) { $debug='' }

    

        
    my $session = $self->{session};

    my $prematch;
    my $match;
    my $state;

    print "-- goto_user_mode: called\n" if $debug;
    #$session->print("q\n");
    ##$session->print("q");
    $session->print("");
    Time::HiRes::sleep(0.3);
    $session->print("");
    print "-- goto_user_mode: called\n" if $debug;
    do {
        my $i=2;
        do {
            print "-- goto_user_mode: try $i\n" if $debug;
            ($prematch, $match) = $session->waitfor( "/$user_prompt|$priv_prompt|$username_prompt|$passwd_prompt|" . 
                                                     "$config_prompt|$invalidlogin_prompt|$more_prompt|$bad_passwds/" );
            print "-- goto_user_mode: match=$match\n" if $debug;
            $i--;
        } until ( !($session->timed_out) || $i == "0" ); 
 
        if ($session->timed_out) { print "ERROR: Timeout waiting for prompt, exiting!\n"; return "timeout"}

        if ($match =~ m/$username_prompt/) {
            # Username
            unless ( defined $self->{'login'} && $self->{'login'} ne '' ) {
            return 'user_login_needed'; 
            }
            print "-- goto_user_mode: 'Username:' prompt detected, providing username ($self->{login})\n" if $debug;
            $session->print($self->{login});
            $state ='login_sent';
        } 
        elsif ($match =~ m/$passwd_prompt/) {
            # Password
        if ( $state eq 'login_sent' ) {
                print "-- goto_user_mode: 'Password:' detected, providing password ($self->{passwd})\n" if $debug;
                $session->print($self->{passwd});
                $state = 'user_auth_info_sent';
            } elsif ( $state eq 'login_sent' ) {
                print "-- goto_user_mode: 'Password:' detected, providing enable password ($self->{enable_passwd})\n" if $debug;
                $session->print($self->{enable_passwd});
                $state = 'user_auth_info_sent';
            }
        } 
        elsif ($match =~ m/$config_prompt/) {
            # Config mode
            print "-- goto_user_mode: Router in Config mode\n" if $debug;
            $session->print("\cZ");
            $state = 'config';
        }
        elsif ($match =~ m/$user_prompt/) {
            # Non priviledged mode
            print "-- goto_user_mode: Router in User mode; changing to priviledged mode (enable command)\n" if $debug;
            $session->buffer_empty;
            $state = 'user';
        }
        elsif ($match =~ m/$priv_prompt/) {
            # Priviledged mode
            print "-- goto_user_mode: Router in Priviledged mode\n" if $debug;
            print "-- goto_user_mode: Router in priviledged mode; changing to user mode (disable command)\n" if $debug;
            $session->print('disable');
            $state = 'disable_sent';
        }
        elsif ($match =~ m/$invalidlogin_prompt/) {
            return 'invalid_login';
        } 
        elsif ($match =~ m/$more_prompt/) {
            # More mode
            print "-- goto_user_mode: Router in More mode\n" if $debug;
            $session->print("q");
            $state = 'more';
        }
        elsif ($match =~ m/$bad_passwds/) {
            print "-- goto_user_mode: Bad enable password\n" if $debug;
            return 'bad_enable_passwd';
        }
        else {
            $state = 'unknown';
        }
        print "-- goto_user_mode: state = $state\n" if $debug;

    } until ( ($session->timed_out) || $state eq "user" );

    if ($session->timed_out) { 
        return 'timeout'
    } elsif ($state eq "user") { 
        print("-- goto_user_mode: sending 'terminal length 0' command\n") if $debug;
        my @cmdoutput = $session->cmd(String => "terminal length 0", Prompt  => "/$user_prompt/");
        if ($session->timed_out) { return 'timeout' } else { return 'user' }
    }


}


sub exeCmd {

    my $self = shift;
    my $cmd = shift;
    my $session = $self->{session};

    #print("-- exeCmd: $cmd\n");
    my @cmdoutput = $session->cmd(Timeout => 15, String => "$cmd", Prompt  => "/$user_prompt|$priv_prompt|$config_prompt|$initial_prompt/");
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
    CORE::close INCLUDE_FILE;
    return @cmdfileoutput;

}

sub copy_file {
 
    my $self = shift;
    my $src_file = shift;
    my $dst_file = shift;
    my $debug = shift;
    unless (defined $debug) { $debug='' }

    my $prematch;
    my $match;
    my $sess = $self->{'session'};
    
    # Copy file is only possible when using ztelnet
    unless ($self->{'use_ztelnet'}) { return 'ztelnet_not_active' }

    print "-- copy_file: called src_file=$src_file, dst_file=$dst_file\n" if $debug; 
    unless ( -e $src_file ) {
        return "file_not_found";
    }
    unless ($dst_file =~ m/^(nvram:\w+|flash:\w+)/) {
        print "error_dst_file\n";
    }

    #my $cmd = "/root/tests/cisco-copy-file.exp $self->{host} $self->{port} $src_file $dst_file";
    #print "Executing: $cmd\n";
    #my $res = `$cmd`;
    #print "res =  $res\n";

    # Delete destination file
    $sess->print("delete $dst_file");
    ($prematch, $match) = $sess->waitfor( "/Delete filename/" );
    if (defined $match) { print "-- copy_file: match=$match\n" if $debug; }
    $sess->print("");
    ($prematch, $match) = $sess->waitfor( "/Delete/" );
    if (defined $match) { print "-- copy_file: match=$match\n" if $debug; }
    $sess->print("");
    ($prematch, $match) = $sess->waitfor( "/#/" );
    if (defined $match) { print "-- copy_file: match=$match\n" if $debug; }

    # Instruct router to receive file with xmodem
    $sess->print("copy xmodem: $dst_file");
    ($prematch, $match) = $sess->waitfor( "/Destination filename/" );
    if (defined $match) { print "-- copy_file: match=$match\n" if $debug; }
    $sess->print("");
    ($prematch, $match) = $sess->waitfor( "/Erase flash|Begin the Xmodem/" );
    if (defined $match) { print "-- copy_file: match=$match\n" if $debug; }
    if ($match =~ m/Erase flash/) {
        $sess->print("n");
        ($prematch, $match) = $sess->waitfor( "/Begin the Xmodem/" );
        if (defined $match) { print "-- copy_file: match=$match\n" if $debug; }
    }
    Time::HiRes::sleep(0.3);
  
    # Send ztelnet escape character (^X)
    my $escape = "\cX";
    $sess->put("\cX");
    ($prematch, $match) = $sess->waitfor( "/zssh >/" );
    if ($sess->timed_out) { return 'timeout' }
    if (defined $match) { print "-- copy_file: match=$match\n" if $debug; }
    $sess->print("sz -Xvv $src_file");
    for (my $i=1; $i<=3; $i++)  {
        ($prematch, $match) = $sess->waitfor(Timeout => 10, Match => "/Transfer complete|NAK|Transfer incomplete|$priv_prompt/" );
        if (defined $match) { print "-- copy_file: match=$match\n" if $debug; }
        #if ($sess->timed_out) { return 'timeout' }
        if ($match =~ m/Transfer complete/) { 
            print "copy_file: $src_file copied succesfully to $dst_file\n";
            my @cmdoutput = $sess->cmd(String => "", Prompt  => "/$priv_prompt/");
            return; 
        } elsif ($match =~ m/Transfer incomplete/) { 
            print "copy_file: ERROR, cannot copy $src_file copied succesfully to $dst_file\n";
            return 'not_copied'
        }
    }
    print "copy_file: ERROR, cannot copy $src_file copied succesfully to $dst_file\n";
    return 'not_copied'
}

1;