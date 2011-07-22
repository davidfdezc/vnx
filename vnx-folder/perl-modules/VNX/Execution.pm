# Execution.pm
#
# This file is a module part of VNUML package.
#
# Author: Fermin Galan Marquez (galan@dit.upm.es)
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

use strict;
no strict "subs";	# Needed in deamonize subrutine
use warnings;

use POSIX qw(setsid setuid setgid);	# Needed in deamonize subrutine
use Term::ReadKey;

# TODO: constant should be included in a .pm that would be loaded from each module
# that needs them
use constant EXE_DEBUG => 0;	#	- does not execute, only shows
use constant EXE_VERBOSE => 1;	#	- executes and shows
use constant EXE_NORMAL => 2;	#	- executes

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

   $self->{'vnx_dir'} = shift;
   $self->{'exe_mode'} = shift;
   $self->{'verb_prompt'} = shift;
   $self->{'exe_interactive'} = shift;
   $self->{'uid'} = shift;
   
   # This field is not set at construction time, due to the DataHandler object 
   # holding the data is constructed after the Execution object. The
   # set_mconsole_binary method has to be used 
   $self->{'mconsole_binary'} = "";
   
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

# get_verb_prompt
#
# Returns the exe_mode
#
sub get_verb_prompt {
   my $self = shift;
   return $self->{'verb_prompt'};
} 

# set_verb_prompt
#
# Set the verb_prompt
#
sub set_verb_prompt {
   my $self = shift;
   my $verb_prompt = shift;
   $self->{'verb_prompt'} = $verb_prompt;
} 

# get_uid
#
# Returns the uid
#
sub get_uid {
   my $self = shift;
   return $self->{'uid'};
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
#   dumping commands to a file, that will be executed in another momment (for
#   example, UML boot script)
#
# Interactive mode can be used in addition to direct mode ($exe_interactive)
#
# Verbose output (when $exe_mode has EXE_DEBUG or EXE_VERBOSE)
# goes to standard output. It is prefixed with $verb_prompt
# and, in addition, whit D- in debug mode

sub execute {
   my $self = shift;
   
   my $exe_mode = $self->{'exe_mode'};
   my $verb_prompt = $self->{'verb_prompt'};
   my $exe_interactive = $self->{'exe_interactive'};

   my $retval = 0;	# By default, all right
   if ((my ($command, $CMD_OUT) = @_) == 1) {
      # Direct mode
      if ($exe_mode == EXE_DEBUG) {
         print "D-" . $verb_prompt . "$command\n";
      }
      elsif ($exe_mode == EXE_VERBOSE) {
         print $verb_prompt . "$command\n";
         system $command;
         $retval = $?;
         if ($exe_interactive) {
            &pulse_a_key;
	     }
      }
      elsif ($exe_mode == EXE_NORMAL) {
         system "$command > /dev/null";
         $retval = $?;
         if ($exe_interactive) {
            &pulse_a_key;
	     }
      }
   }
   else {
      # Recording mode
      if ($exe_mode == EXE_DEBUG) {
         print "D-" . $verb_prompt . "$command\n";
      }
      elsif ($exe_mode == EXE_VERBOSE) {
         print $verb_prompt . "$command\n";
         print $CMD_OUT "$command\n";
      }
      elsif ($exe_mode == EXE_NORMAL) {
         print $CMD_OUT "$command\n";
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

   if ($exe_mode == EXE_DEBUG) {
      print "D-daemon: $command\n";
   }
   elsif ($exe_mode == EXE_VERBOSE) {
      print "daemon: $command\n";
      $self->daemonize($command,$output,$gid);
      if ($exe_interactive) {
         &pulse_a_key;
      }
   }
   elsif ($exe_mode == EXE_NORMAL) {
      $self->daemonize($command,$output,$gid);
      if ($exe_interactive) {
         &pulse_a_key;
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
	
   my $mconsole = shift;
   my $cmd = shift;
   
   $self->execute($self->{'mconsole_binary'} . " $mconsole 'exec $cmd' 2>/dev/null");
  
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
      $self->execute("rm -f $vnx_dir/LOCK");
   }
   print "-------------------------------------------------------------------------------\n";
   printf "%s (%s): %s \n", (caller(1))[3], (caller(0))[2], $mess;
   print "-------------------------------------------------------------------------------\n";
   exit 1; 
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
   open STDOUT, ">$output" or die("can't write to $output daemonizing ($command): $!");

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

sub pulse_a_key {

   # Copy-paste from http://perlmonks.thepen.com/33566.html
   # A simpler alternative to this code is <>, but that is ugly :)

   my $key;
   ReadMode 4; # Turn off controls keys
   while (not defined ($key = ReadKey(1))) {
      # No key yet
   }
   ReadMode 0; # Reset tty mode before exiting

}

1;
