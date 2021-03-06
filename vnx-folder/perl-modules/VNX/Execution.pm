# Execution.pm
#
# This file is a module part of VNUML package.
#
# Author: Fermin Galan Marquez (galan@dit.upm.es), David Fernández (david@dit.upm.es)
# Copyright (C) 2005, 	DIT-UPM
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

# Execution class implementation. The instance of Execution encapsulates methods for
# dealing with execution of commands.

package VNX::Execution;
use VNX::Globals;

use strict;
no strict "subs";	# Needed in deamonize subrutine
use warnings;

use POSIX qw(setsid setuid setgid);	# Needed in deamonize subrutine
use Term::ReadKey;

our @ISA    = qw(Exporter);
our @EXPORT = qw( wlog press_any_key pak change_to_root back_to_user print_current_user root user);



###########################################################################
# CLASS CONSTRUCTOR
#
# Arguments:
#
# - the vnuml_dir directory
# - the execution mode
# - the verb prompt (it only makes sense if EXE_DEBUG and EXE_VERBOSE)
# - the exe_interactive value
# - the uid that will own processes that are executed using execute_bg
# - the mconsole_binary (needed in execute_mconsole method)
#
sub new {
    my $class = shift;
    my $self = {};
    bless $self;

    my @verb_prompt;  # Prompt behaves now as stack implemented with an array 

    $self->{'vnx_dir'} = shift;
    $self->{'exe_mode'} = shift;
#    $self->{'verb_prompt'} = shift;
    unshift (@verb_prompt, shift);
    $self->{'exe_interactive'} = shift;
    $self->{'uid'} = shift;

    $self->{'verb_prompt'} = \@verb_prompt;  

    # This field is not set at construction time, due to the DataHandler object 
    # holding the data is constructed after the Execution object. The
    # set_mconsole_binary method has to be used 
    $self->{'mconsole_binary'} = "";

    $self->{'log_file'} = shift;
#    $self->{'log_fh'} = *LOG_FILE;
    
#    if ($self->{'log_file'}) {
#        print "log file =" . $self->{'log_file'} . "\n";   	
#    	open LOG_FILE, ">" . $self->{'log_file'}
#    	   or $execution->smartdie( "can not open log file (" . $self->{'log_file'} . ") for writting" )
#           unless ($self->{'exe_mode'} eq $EXE_DEBUG );
#    }
   
    return $self;  
}

###########################################################################
# PUBLIC METHODS

# get_exe_mode
#
# Returns the exe_mode
#
sub get_exe_mode {
   my $self = shift;
   return $self->{'exe_mode'};
} 

# get_exe_interactive
#
# Returns the exe_mode
#
sub get_exe_interactive {
   my $self = shift;
   return $self->{'exe_interactive'};
} 

# get_verb_prompt
#
# Returns the exe_mode
#
sub get_verb_prompt {
    my $self = shift;
#   return $self->{'verb_prompt'};
    return @{$self->{'verb_prompt'}}[0];
} 

# set_verb_prompt
#
# Set the verb_prompt
#
sub set_verb_prompt {
    my $self = shift;
    my $verb_prompt = shift;
    unshift (@{$self->{'verb_prompt'}}, $verb_prompt);
    #$self->{'verb_prompt'} = $verb_prompt;
} 

# pop_verb_prompt
#
# Pop a verb_prompt to the stack
#
sub pop_verb_prompt {
    my $self = shift;
    shift (@{$self->{'verb_prompt'}});
    #$self->{'verb_prompt'} = $verb_prompt;
} 

# get_uid
#
# Returns the uid
#
sub get_uid {
   my $self = shift;
   return $self->{'uid'};
} 

# get_logfile
#
# Returns the logfile
#
sub get_logfile {
   my $self = shift;
   return $self->{'log_file'};
} 

# set_mconsole_binary
#
# Returns the uid
#
sub set_mconsole_binary {
   my $self = shift;
   my $mconsole_binary = shift;
   $self->{'mconsole_binary'} = $mconsole_binary;;
}

# execute
#
# Shell commands execution interface. This functions is
# based on the value of global variable $exe_mode
#
# Depending of the number of arguments, execute works in direct
# or or recording mode (execpt for EXE_DEBUG).
#
# * Direct mode: command execution (first argument) throught system
#   Perl function.
# * Recording mode: command execution (first argument) printing it
#   to the flow pointed by the second argument. This function is for
#   dumping commands to a file, that will be executed in another moment (for
#   example, UML boot script)
#
# Interactive mode can be used in addition to direct mode ($exe_interactive)
#
# Verbose output (when $exe_mode has EXE_DEBUG or EXE_VERBOSE)
# goes to standard output. It is prefixed with $verb_prompt
# and, in addition, with D- in debug mode

sub execute {
    my $self = shift;
    my $verb_prompt = shift;
   
    my $exe_mode;
    $exe_mode = $self->{'exe_mode'};
    #my $verb_prompt = $self->{'verb_prompt'};
    #my $verb_prompt = @{$self->{'verb_prompt'}}[0];
    my $exe_interactive = $self->{'exe_interactive'};

    my $retval = 0;	# By default, all right
    if ((my ($command, $CMD_OUT) = @_) == 1) {
        #
        # Direct mode: Direct mode: command execution throught perl system function.
        #
        if ($exe_mode == $EXE_DEBUG) {
            #print "D-" . $verb_prompt . "$command\n";
            $command =~ s/\n/\\n/g;
            print sprintf("D-%-8s %s", $verb_prompt, "$command\n");
        }
        elsif ($exe_mode == $EXE_VERBOSE) {
            #print $verb_prompt . "$command\n";
            my $cmd_line = $command; $cmd_line =~ s/\n/\\n/g;
            #if ( $EXE_VERBOSITY_LEVEL >= VV ) { 
                print_log ($cmd_line, $verb_prompt);
            #}      

#            if ($execution->get_logfile()) { 
#                open LOG_FILE, ">> " . $execution->get_logfile() 
#                    or $execution->smartdie( "can not open log file (" . $execution->get_logfile . ") for writting" );
#                print LOG_FILE sprintf("%-10s %s", $verb_prompt, "$cmd_line\n");
#            } else {
#            	print sprintf("%-10s %s", $verb_prompt, "$cmd_line\n");
#            }
#            close (LOG_FILE);
            
#pak("$command");
            if ( $execution->get_logfile() && ($command !~ m/echo/ ) ) { # "echo .... > file" commands cannot be redirected
                system "$command 2>> " . $execution->get_logfile() . " >> " . $execution->get_logfile();
            } else {
                system "$command";
            }
            $retval = $?;
            if ($exe_interactive) {
                &press_any_key;
            }
        }
        elsif ($exe_mode == $EXE_NORMAL) {
            # system "$command > /dev/null"; # redirection eliminated to avoid problems with commands of type "echo XXXX > file"
            # 
#            # Trick to avoid problems with "echo .... > file" commands
#            #print "command=$command\n";
#            if ($command =~ m/echo/ ) {
            	#print "echo\n";
#                system "$command";
#            } else {
#                #print "NO echo\n";
                # We add parenthesys "()" to the command to avoid 
                # problems in case the command includes i/o redirections
                # (e.g.:    echo ... > file )

#                system "( $command ) > /dev/null 2>&1";
#            }

            system "( $command ) > /dev/null 2>&1";
            $retval = $?;
            if ($exe_interactive) {
                &press_any_key;
            }
        }
    }
    else {
		#
        # Recording mode: dumping commands to a file, that will be executed in another moment 
        #
        wlog (VVV, "command=$command", $verb_prompt);
        #wlog (VVV, "CMD_OUT=$CMD_OUT", $verb_prompt);
        if ($exe_mode == $EXE_DEBUG) {
            #print "D-" . $verb_prompt . "$command\n";
            print sprintf("D-%-8s %s", $verb_prompt, "$command\n");
        }
        elsif ($exe_mode == $EXE_VERBOSE) {
            #print $verb_prompt . "$command\n";
            print $CMD_OUT "$command\n";
            if ( $EXE_VERBOSITY_LEVEL >= VV ) { 
                print_log ($command, $verb_prompt);
            }      
#            if ($execution->get_logfile()) { 
#                open LOG_FILE, ">> " . $execution->get_logfile() 
#                    or $execution->smartdie( "can not open log file (" . $execution->get_logfile . ") for writting" );
#                print LOG_FILE sprintf("%-10s %s", $verb_prompt, "$command\n");
#            } else {
#                print sprintf("%-10s %s", $verb_prompt, "$command\n");
#            }
            close (LOG_FILE);
        }
        elsif ($exe_mode == $EXE_NORMAL) {
            print $CMD_OUT "$command\n";
        }
    }

    return $retval;

}

# 
# execute_host
#
sub execute_host {
    
    my $self = shift;
    my $verb_prompt = shift;
   
    my $exe_mode;
    $exe_mode = $self->{'exe_mode'};
    #my $verb_prompt = $self->{'verb_prompt'};
    #my $verb_prompt = @{$self->{'verb_prompt'}}[0];
    my $exe_interactive = $self->{'exe_interactive'};

    my $retval = 0; # By default, all right
    if ((my ($command, $CMD_OUT) = @_) == 1) {
        #
        # Direct mode: Direct mode: command execution throught perl system function.
        #
        if ($exe_mode == $EXE_DEBUG) {
            #print "D-" . $verb_prompt . "$command\n";
            $command =~ s/\n/\\n/g;
            print sprintf("D-%-8s %s", $verb_prompt, "$command\n");
        }
        elsif ($exe_mode == $EXE_VERBOSE) {
            #print $verb_prompt . "$command\n";
            my $cmd_line = $command; $cmd_line =~ s/\n/\\n/g;
            #if ( $EXE_VERBOSITY_LEVEL >= VV ) { 
                print_log ($cmd_line, $verb_prompt);
            #}      

#            if ($execution->get_logfile()) { 
#                open LOG_FILE, ">> " . $execution->get_logfile() 
#                    or $execution->smartdie( "can not open log file (" . $execution->get_logfile . ") for writting" );
#                print LOG_FILE sprintf("%-10s %s", $verb_prompt, "$cmd_line\n");
#            } else {
#               print sprintf("%-10s %s", $verb_prompt, "$cmd_line\n");
#            }
#            close (LOG_FILE);
            
#pak("$command");
            if ( $execution->get_logfile() && ($command !~ m/echo/ ) ) { # "echo .... > file" commands cannot be redirected
                system "$command 2>> " . $execution->get_logfile() . " >> " . $execution->get_logfile();
            } else {
                system "$command";
            }
            $retval = $?;
            if ($exe_interactive) {
                &press_any_key;
            }
        }
        elsif ($exe_mode == $EXE_NORMAL) {
            # system "$command > /dev/null"; # redirection eliminated to avoid problems with commands of type "echo XXXX > file"
            # 
#            # Trick to avoid problems with "echo .... > file" commands
#            #print "command=$command\n";
#            if ($command =~ m/echo/ ) {
                #print "echo\n";
#                system "$command";
#            } else {
#                #print "NO echo\n";
                # We add parenthesys "()" to the command to avoid 
                # problems in case the command includes i/o redirections
                # (e.g.:    echo ... > file )

#                system "( $command ) > /dev/null 2>&1";
#            }

            system "( $command ) > /dev/null 2>&1";
            $retval = $?;
            if ($exe_interactive) {
                &press_any_key;
            }
        }
    }

    return $retval;

}

# execute_bg
#
# Execute a command, daemoned.
# 
# First argument is the command line.
# Second argument is the file to redirect output
#
# See sub execute for aditional comments.

sub execute_bg {
   my $self = shift;
   
   my $exe_mode = $self->{'exe_mode'};
   my $exe_interactive = $self->{'exe_interactive'};   
   
   my $command = shift;
   my $output = shift;
   my $gid = shift;

   if ($exe_mode == $EXE_DEBUG) {
      print "D-daemon: $command\n";
   }
   elsif ($exe_mode == $EXE_VERBOSE) {
      print_log ("daemon: $command", "");
      $self->daemonize($command,$output,$gid);
      if ($exe_interactive) {
         &press_any_key;
      }
   }
   elsif ($exe_mode == $EXE_NORMAL) {
      $self->daemonize($command,$output,$gid);
      if ($exe_interactive) {
         &press_any_key;
      }
   }
}

# execute_mconsole
#
# uml_mconsole execution wrapper. Executes a particular command using a exec
# command of uml_mconsole
# 
# Arguments:
#
# - The mconsole socket to use (each vm uses a different one)
# - Command to execute
#

sub execute_mconsole {
   my $self = shift;
   my $verb_prompt = shift;
	
   my $mconsole = shift;
   my $cmd = shift;
   
   $self->execute($verb_prompt, $self->{'mconsole_binary'} . " $mconsole 'exec $cmd' 2>/dev/null");
   #$self->execute($verb_prompt, $self->{'mconsole_binary'} . " $mconsole 'exec $cmd'");
   #$self->execute($verb_prompt, $self->{'mconsole_binary'} . " $mconsole 'exec $cmd' >/dev/null 2>&1 ");
  
}

# execute_getting_output
#
# Shell commands execution interface. This functions is
# similar to 'execute' but it returns the command output instead
# of the command return value
#
# Interactive mode can be used in addition to direct mode ($exe_interactive)
#

sub execute_getting_output {
    my $self = shift;
    my $verb_prompt = shift;
    my $command = shift;
   
    my $exe_mode = $self->{'exe_mode'};
    my $exe_interactive = $self->{'exe_interactive'};

    my $retval = '';	# By default, all right

    if ($exe_mode == $EXE_DEBUG) {
        $command =~ s/\n/\\n/g;
        print sprintf("D-%-8s %s", $verb_prompt, "$command\n");
    }
    elsif ($exe_mode == $EXE_VERBOSE || $exe_mode == $EXE_NORMAL) {

        my $cmd_line = $command; $cmd_line =~ s/\n/\\n/g;
        print_log ($cmd_line, $verb_prompt) if ($exe_mode == $EXE_VERBOSE);      

=BEGIN        
        # This way does not work...commands do not end even when using & to execute in background
        $retval = `( $command ) 2>&1`;
        if ( $execution->get_logfile() ) { # Send output to log file if defined
            system "echo $retval >> " . $execution->get_logfile();
        }
=END
=cut
        
        my $tmp_file = `mktemp --tmpdir=/tmp -t vnx_cmd_output.XXXXXX`;
        system "( $command ) 2>&1 > $tmp_file ";
        # Return command output...
        $retval = `cat $tmp_file`;
        if ( $execution->get_logfile() )  {
            # ...and send it to logfile
            system "cat $tmp_file >> " . $execution->get_logfile();
        }
        # Delete tmp file
        system "rm -f $tmp_file";
        if ($exe_interactive) {
            &press_any_key;
        }
    }
    return $retval;
}


sub root { change_to_root() }

sub change_to_root {
    $>=0;    wlog (VVV, "-- Changed to root", "");
}

sub user { back_to_user() }

sub back_to_user {
    my $user = shift;
    
    if ( defined($user) ) {
        $>=$user; wlog (VVV, "-- Back to user $user", "");
    } else {
        $>=$uid; wlog (VVV, "-- Back to user $uid_name", "");
    }
}

sub print_current_user {
    wlog (VVV, '-- Current user = ' . $>)	
}

sub execute_root {
    my $self = shift;
    change_to_root();
    execute ($self, @_);
    back_to_user();
}

sub execute_bg_root {
    my $self = shift;
    change_to_root();
    execute_bg ($self, @_);
    back_to_user();
}

# smartdie
#
# Wrapper of die Perl function, releasing previously global lock
sub smartdie {
   my $self = shift;
   
   my $vnx_dir = $self->{'vnx_dir'};
   
   my $mess = shift;
   
   if (-f "$vnx_dir/LOCK") {
   	  # Note this 'rm' is not using the path in binaries_path (from VNUML::BinariesData)
   	  # Just a simplification
      $self->execute("smartdie> ", "rm -f $vnx_dir/LOCK");
   }
   print "-------------------------------------------------------------------------------\n";
   printf "ERROR in %s (%s):\n%s \n", (caller(1))[3], (caller(0))[2], $mess;
   print "-------------------------------------------------------------------------------\n";
   exit 1; 
}


sub press_any_key {
	
    my $msg = shift;
    
    my $hline = "----------------------------------------------------------------------------------";
    
    print "$hline\n";
    if ($msg) { print "Execution paused ($msg)\n" }	
    print "Press any key to continue...\n";
    
    # Copy-paste from http://perlmonks.thepen.com/33566.html
    # A simpler alternative to this code is <>, but that is ugly :)

    my $key;
    ReadMode 4; # Turn off controls keys
    while (not defined ($key = ReadKey(1))) {
        # No key yet
    }
    ReadMode 0; # Reset tty mode before exiting
    print "$hline\n";

}

sub pak { 
    my $msg = shift;
    press_any_key ($msg);
}

sub pause_if_interactive {
    my $msg = shift;
    if ($execution->get_exe_interactive) {
        press_any_key($msg);
    }
}

sub pii {
    my $msg = shift;
    pause_if_interactive ($msg);
}	 

# wlog 
#
# Write log message depending on the verbosity level ($execution->get_exe_mode()).
# Adds a "\n" to the end of the message. Uses the $execution object, so it cannot be
# called before $execution is initialized.
# 
# Call with: 
#    wlog (N, "log message")  
#    wlog (V, "log message", "prompt> ")  
#    wlog (VV, "log message", "prompt> ")  
#    wlog (VVV, "log message", "prompt> ")
#  
sub wlog {
	
	my $msg_level = shift;   # Posible values: N, ERR, V, VV, VVV
	my $msg       = shift;
	my $prompt    = shift;

    unless ( defined($prompt) or ($msg_level == N) or ($msg_level == ERR)) {
    	#$prompt = "vnx-log-$EXE_VERBOSITY_LEVEL>";  
    	$prompt = $execution->get_verb_prompt();
    }

    my $exe_mode = $execution->get_exe_mode();
	
	#print "~~ wlog: msg_level=$msg_level, exe_mode=$exe_mode, EXE_VERBOSITY_LEVEL=$EXE_VERBOSITY_LEVEL\n";		
    if ($msg_level == N) {
        print "$msg\n"; 
        if ($execution->get_logfile()) { print_log ($msg, ""); }
    } elsif ($msg_level == ERR) {
        print "$hline\nERROR: $msg\n$hline\n"; 
        if ($execution->get_logfile()) { print_log ("$hline\nERROR: $msg\n$hline", ""); }
    } elsif ( ($exe_mode == $EXE_DEBUG) || ( ($exe_mode == $EXE_VERBOSE) && ( $msg_level <= $EXE_VERBOSITY_LEVEL ) ) ) { 
		#print "$prompt$msg\n";		
		print_log ($msg, $prompt);		
#        if ($execution->get_logfile() && ($exe_mode != $EXE_DEBUG)) { 
#            print LOG_FILE sprintf("%-10s %s", $prompt, "$msg\n");
#        } else {
#            print sprintf("%-10s %s", $prompt, "$msg\n");
#        }
	}  
	close (LOG_FILE);
	
}

sub print_log {

    my $msg = shift;
    my $prompt = shift;
    my $line;

    if ($prompt ne "") {
    	$line = sprintf("%-10s %s", $prompt, "$msg");
    } else {
    	$line = $msg;
    }
    if ($execution->get_logfile() && ($execution->get_exe_mode() != $EXE_DEBUG) ) { 
        open LOG_FILE, ">> " . $execution->get_logfile() 
            or $execution->smartdie( "cannot open log file (" . $execution->get_logfile . ") for writting" );
        print LOG_FILE "$line\n";
    } else {
        print "$line\n";
    }
    close (LOG_FILE);
}

###########################################################################
# PRIVATE METHODS (it only must be used from this class itsefl)

sub daemonize {
   my $self = shift;

   # Thanks to http://www.webreference.com/perl/tutorial/9 for the code :)

   my $command = shift;
   my $output = shift;
   my $my_gid = shift;

   defined(my $pid = fork) or $self->smartdie->("can't fork daemonizing ($command): $!");
   return if $pid;

#   umask 0;

   # Ensure that this process isn't a process group leader
   setsid or die "can't start a new session daemonizing ($command): $!";

   # Redirect file handles (as original user, so files can be created, if necessary)
   open STDIN, '/dev/null' or die("can't read /dev/null daemonizing ($command): $!");
   open STDOUT, ">>$output" or die("can't write to $output daemonizing ($command): $!");

   # Change real/effective user of this process
   my ($name,$passwd,$uid,$gid,$quota,$comment,$gcos,$dir,$shell,$expire) = getpwuid($self->get_uid);
   if (defined($my_gid) && $my_gid ne '') {
	   setgid($my_gid) or die "can't setgid to group ".getgrgid($my_gid).": $!";
   } else {
	   setgid($gid) or die "can't setgid to group ".getgrgid($gid).": $!";
   }

   # Change real/effective user id of this process
   setuid($uid) or die "can't setuid to user $name: $!";

   # Set the home directory to that of the current user
   $ENV{HOME} = $dir;

   # Change working directory to / now (don't change before now, so relative $output path will work)
   chdir '/' or die "Can't chdir to /: $!";

   # Duplicate stderr to stdout last, so messages prior to now will be shown on the console
   open STDERR, ">&STDOUT" or die("can't dup stdout daemonizing ($command): $!");

   exec $command;
   die "Could not execute $command!";
}

1;
