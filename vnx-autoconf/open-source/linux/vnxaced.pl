#!/usr/bin/perl

#
# Name: vnxaced
#
# Description: 
#   vnxaced is the Linux and FreeBSD Autoconfiguration and Command Execution Daemon (ACED) 
#   of VNX project. It reads autoconfiguration or command execution XML files provided
#   to the virtual machine through dynamically mounted cdroms and process them, executing 
#   the needed commands.  
#
# This file is a module part of VNX package.
#
# Authors: Jorge Somavilla (somavilla@dit.upm.es), David Fernández (david@dit.upm.es)
# Copyright (C) 2014,   DIT-UPM
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
#

use strict;
use POSIX;
use Sys::Syslog;
use XML::LibXML;
use IO::Handle;
use File::Basename;
use NetAddr::IP;

my $VNXACED_VER='MM.mm.rrrr';
my $VNXACED_BUILT='DD/MM/YYYY';

use constant VNXACED_PID => '/var/run/vnxaced.pid';
use constant VNXACED_LOG => '/var/log/vnxaced.log';
use constant VNXACED_STATUS => '/root/.vnx/vnxaced.status';

use constant FREEBSD_CD_DIR => '/cdrom';
use constant LINUX_CD_DIR   => '/media/cdrom';

use constant INIT_DELAY   => '10';

# Channel used to send messages from host to virtuqal machine
# Values:
#    - SERIAL: serial line
#    - SHARED_FILE: shared file
use constant H2VM_CHANNEL => 'SERIAL';

use constant LINUX_TTY   => '/dev/ttyS1';
use constant FREEBSD_TTY => '/dev/cuau1';

use constant MSG_FILE => '/mnt/sdisk/cmd/command';

use constant MOUNT => 'YES';  # Controls if mount/umount commands are executed
                              # Set to YES when using CDROM or shared disk with serial line
                              # Set to NO when using shared disk without serial line

# Log levels
use constant N   => 0;
use constant V   => 1;
use constant VV  => 2;
use constant VVV => 3;
use constant ERR => 4;

my @platform;
my $mount_cdrom_cmd;
my $umount_cdrom_cmd; 
my $mount_sdisk_cmd;
my $umount_sdisk_cmd; 
my $console_ttys;

my $DEBUG;
my $VERBOSE;
my $LOGCONSOLE;

my $def_logp = "~~ vnxaced>"; # log prompt

#~~~~~~ Usage & Version messages ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

my $usage = <<EOF;
Usage: vnxaced [-v|--verbose] [-g|--debug]
       vnxaced -V|--version
       vnxaced -h|--help
       vnxaced -m|--monitor
       
EOF

my $version= <<EOF;

----------------------------------------------------------------------------------
Virtual Networks over LinuX (VNX) -- http://www.dit.upm.es/vnx - vnx\@dit.upm.es          
----------------------------------------------------------------------------------
VNX Linux and FreeBSD Autoconfiguration and Command Execution Daemon (VNXACED)
Version: $VNXACED_VER ($VNXACED_BUILT)
EOF


my $vm_tty; # vm tty connected with the host 

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#~~~~~~~~~~           main code         ~~~~~~~~~~~~~~~
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~



# Set INT signal handler
# Commented...seems it provokes problems with upstart...
#$SIG{'INT'} = 'IntHandler';

# Command line arguments process 
if ($#ARGV >= 2) {
    print "$usage";
    exit (1);
}

for (my $i=0; $i <= $#ARGV; $i++) {
        if ( ($ARGV[$i] eq "-g") or ($ARGV[$i] eq "--debug") ) {
                $DEBUG='true';
        } elsif ( ($ARGV[$i] eq "-v") or ($ARGV[$i] eq "--verbose") ) {
                $VERBOSE='true';
        } elsif ( ($ARGV[$i] eq "-V") or ($ARGV[$i] eq "--version") ) {
                print "$version\n";
                exit (0);
        } elsif ( ($ARGV[$i] eq "-h") or ($ARGV[$i] eq "--help") ) {
                print "$version\n";
                print "$usage\n";
                exit (0);
        } elsif ( ($ARGV[$i] eq "-m") or ($ARGV[$i] eq "--monitor") ) {
                my $res=`ps uaxw | grep '/usr/local/bin/vnxaced' | grep -v watch | grep -v grep | grep -v ' -m'`;
                print "$res\n";
                exit (0);
        } else {
                print "Unknown command option: $ARGV[$i]\n";
                print "$usage\n";
                exit (1);
        }
}

system "mkdir -p /root/.vnx";
#unless ( -e VNXACED_LOG )   { system "touch " . VNXACED_LOG }

# Check if status file exists
my $tout = 30;
while ( ! (-e VNXACED_STATUS) ) { 
        # Create status file with default values
        wlog (V, "Creating " . VNXACED_STATUS . " \n");
        system ('echo "verbose=no"    >  ' . VNXACED_STATUS);
        system ('echo "logconsole=no" >> ' . VNXACED_STATUS);
        $tout--;
        if (!$tout) { 
            vnxaced_die ("Cannot create status file " . VNXACED_STATUS . " \n")
        }
        sleep 2;
}

my $verbose_cfg = get_conf_value (VNXACED_STATUS, 'verbose');
if ($verbose_cfg eq 'yes') { $VERBOSE = 'true' }

if ($DEBUG) { print "DEBUG mode\n"; }
if ($VERBOSE) { print "VERBOSE mode\n"; }

my $logconsole_cfg = get_conf_value (VNXACED_STATUS, 'logconsole');
if ($logconsole_cfg eq 'yes') { $LOGCONSOLE = 'true' }

if ($DEBUG)      { print "DEBUG mode\n"; }
if ($VERBOSE)    { print "VERBOSE mode\n"; }
if ($LOGCONSOLE) { print "LOGCONSOLE mode\n"; }

my $os_distro = get_os_distro();
@platform = split(/,/, $os_distro);
    
if ($platform[0] eq 'Linux'){
    
    $vm_tty = LINUX_TTY;
    if ($platform[1] eq 'Ubuntu')    { 
        if ($platform[2] eq '12.04') {
            $mount_cdrom_cmd = 'mount /dev/sr0 /media/cdrom';
            $umount_cdrom_cmd = 'eject /media/cdrom; umount /media/cdrom';                  
        } else {
            $mount_cdrom_cmd  = 'mount /media/cdrom';
            $umount_cdrom_cmd = 'umount /media/cdrom';
        }
    }           
    elsif ($platform[1] eq 'Fedora') { 
        $mount_cdrom_cmd = 'udisks --mount /dev/sr0';
        $umount_cdrom_cmd = 'udisks --unmount /dev/sr0';            
    }
    elsif ($platform[1] eq 'CentOS') { 
        $mount_cdrom_cmd = 'mount /dev/cdrom /media/cdrom';
        $umount_cdrom_cmd = 'eject; umount /media/cdrom';           
    }
    $mount_sdisk_cmd  = 'mount /dev/sdb /mnt/sdisk';
    $umount_sdisk_cmd = 'umount /mnt/sdisk';
    system "mkdir -p /mnt/sdisk";
    $console_ttys = "/dev/ttyS0 /dev/tty1";
    
} elsif ($platform[0] eq 'FreeBSD'){
    
    $vm_tty = FREEBSD_TTY;
    $mount_cdrom_cmd = 'mount /cdrom';
    $umount_cdrom_cmd = 'umount -f /cdrom';
    $mount_sdisk_cmd  = 'mount -t msdosfs /dev/ad1 /mnt/sdisk';
    $umount_sdisk_cmd = 'umount /mnt/sdisk';
    system "mkdir -p /mnt/sdisk";
    $console_ttys = "/dev/ttyv0";
    
} else {
    wlog (V, "ERROR: unknown platform ($platform[0]). Only Linux and FreeBSD supported.");
    exit (1);
}


# delete file log content without deleting the file
#if (open(LOG, ">>" . VNXACED_LOG)) {
#   truncate LOG,0;
#   close LOG;
#}
chomp (my $now = `date`);
wlog (V, "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
wlog (V, "~~ vnxaced version $VNXACED_VER (built on $VNXACED_BUILT)");
wlog (V, "~~   started at $now");
wlog (V, "~~   OS: $os_distro");
wlog (V, "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

#if (-f VNXACED_PID){
#   my $cmd="cat " . VNXACED_PID;
#   my $pid=`$cmd`; chomp ($pid);
#   wlog (V, "Another instance of vnxaced (PID $pid) seems to be running, killing it... ");
#   system "kill -9 $pid"; 
#   system "rm -f " . VNXACED_PID; 
#}
open my $pids, "ps uax | grep 'perl /usr/local/bin/vnxaced' | grep -v grep | grep -v 'sh -e -c exec' | awk '{print \$2}' |";
while (<$pids>) {
        my $pid=$_; chomp($pid);
    if ($pid ne $$) {
        wlog (V, "Another instance of vnxaced (PID $pid) seems to be running, killing it... ");
            system "kill $pid";
        }
}

# store process pid
system "echo $$ > " . VNXACED_PID;

#wlog (V, "~~ Waiting initial delay of " . INIT_DELAY . " seconds...");
#sleep INIT_DELAY;

if (! $DEBUG) { 
    &daemonize;
}
&listen;
exit(0);

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub IntHandler {
    my $cmd="cat " . VNXACED_PID;
    my $pid=`$cmd`; chomp ($pid);
        print "** pid in pid file = $pid\n";
        print "** my pid = $$\n";
    if ($pid eq $$) { 
        system "rm -f " . VNXACED_PID; 
    }
    wlog (V, "INT signal received. Exiting.");
    exit (0);
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub wlog {

    my $log_level = shift; # Not used, included for compatibility with VNX wlog function
    my $msg = shift;
    my $logp;
    unless (defined($logp)) { $logp = $def_logp }

    if ($DEBUG) { 
        print "$logp $msg\n"; 
    }
    if ($LOGCONSOLE) { 
        write_console ("$logp $msg\r\n"); 
    }
    if (open(LOG, ">>" . VNXACED_LOG)) {
        (*LOG)->autoflush(1);
        print LOG ("$logp $msg\n");
        close LOG;
    }
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub write_console {

    my $msg = shift;
    system "printf \"$def_logp $msg\" | tee -a $console_ttys > /dev/null";

}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#
# exe_mount_cmd
#
# Executes the mount/umount cdrom commands in a silent or verbose way
# Used to debug mount/umount problems
#
sub exe_mount_cmd {

    my $cmd = shift;

    if ( MOUNT eq 'YES' ) {
    
        if ($VERBOSE) {
            my $res=`$cmd`;
            wlog (V, "exe_mount_cmd: $cmd (res=$res)") if ($VERBOSE);
        } else {
            $cmd="$cmd >/dev/null 2>&1";
            system "$cmd";
        }
    }
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub daemonize {
        
    wlog (V, "Daemonizing process... ");

    # Fork
#   my $pid = fork;
#   exit if $pid;
#   die "Couldn't fork: $!" unless defined($pid);

    # Become session leader (independent from shell and terminal)
    setsid();

    # Close descriptors
    close(STDERR);
    close(STDOUT);
    close(STDIN);

    # Set permissions for temporary files
    umask(027);

    # Run in /
    chdir("/");
}


#~~~~~~~~~~~~~~ listen for commands ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub listen {

    my $cmd = "cat " . VNXACED_STATUS; my $status=`$cmd`; 
    wlog (V, "-------------------------\nvnxaced.status file:"); wlog (V, $status); wlog (V, '-------------------------'); 
    #write_console ('-------------------------'); write_console ($status); write_console ('-------------------------');
    #
    # Check if execution of commands with seq='on_boot' is pending. That means
    # that we just started again after autoconfiguration reboot.
    #
    my $on_boot_cmds_pending = get_conf_value (VNXACED_STATUS, 'on_boot_cmds_pending');
    if ($on_boot_cmds_pending eq 'yes') {
 
        wlog (V, "Executing on_boot commands if specified");
        # It's pending, generate an 'exeCommand' to 
        my $exec_mode = get_conf_value (VNXACED_STATUS, 'exec_mode');
        process_cmd ( "exeCommand $exec_mode");
 
    } else {

        wlog (V, "Starting...looking for vnxboot autoconfiguration files...");

        #
        # We have just initiated. We check during INIT_DELAY secs whether an
        # SDISK or CDROM with a vnxboot autoconfiguration file is available:
        #  - if yes -> do autoconfiguration
        #  - if not -> wait for commands sent from the host  
        #
        my $start_time = time();
        while ( time()-$start_time < INIT_DELAY ) {
            
            # Check if a sdisk is available
            exe_mount_cmd ($mount_sdisk_cmd);
            my $files_dir = '/mnt/sdisk';
    
            if ($VERBOSE) {
                my $res=`ls -l $files_dir`; wlog (V, "\n$files_dir content: ~~\n$res~~~~~~~~~~~~~~~~~~~~\n")
            }
            
            my @files = <$files_dir/*>;
            foreach my $file (@files){
                
                my $fname = basename ($file);
                if ( ($fname eq "vnxboot") || ($fname eq "vnxboot.xml") && is_new_file($file) ) {

                    wlog (V, "vnxboot file found...autoconfiguration in progress");

                    if ($VERBOSE) { my $f=`cat $file`; wlog (V, "\n$fname ~~\n$f~~~~~~~~~~~~~~~~~~~~\n"); }
                    chomp (my $now = `date`);                       
                    wlog (V, "$now:");
                    wlog (V, "     configuration file received in $file");
                    set_conf_value (VNXACED_STATUS, 'on_boot_cmds_pending', 'yes');
                    set_conf_value (VNXACED_STATUS, 'exec_mode', 'sdisk');
                    autoconfigure($file);
                              
                }
            }
            exe_mount_cmd ($umount_sdisk_cmd);
            
            # Check if a cdrom is available
            exe_mount_cmd ($mount_cdrom_cmd);
            $files_dir = '/media/cdrom';
    
            if ($VERBOSE) {
                my $res=`ls -l $files_dir`; wlog (V, "\n$files_dir content: ~~\n$res~~~~~~~~~~~~~~~~~~~~\n")
            }
            
            @files = <$files_dir/*>;
            foreach my $file (@files){
                
                my $fname = basename ($file);
                if ( ($fname eq "vnxboot") || ($fname eq "vnxboot.xml") && is_new_file($file) ) {

                    if ($VERBOSE) { my $f=`cat $file`; wlog (V, "\n$fname ~~\n$f~~~~~~~~~~~~~~~~~~~~\n"); }
                    chomp (my $now = `date`);                       
                    wlog (V, "$now:");
                    wlog (V, "     configuration file received in $file");
                    set_conf_value (VNXACED_STATUS, 'on_boot_cmds_pending', 'yes');
                    set_conf_value (VNXACED_STATUS, 'exec_mode', 'cdrom');
                    autoconfigure($file);
                              
                }
            }
            exe_mount_cmd ($umount_cdrom_cmd);
            
            sleep (2);
        }
        wlog (V, "No vnxboot autoconfiguration files found...");
        
    }

    #
    # Main commands processing loop
    #

    if ( H2VM_CHANNEL eq 'SERIAL' ) {

        # Open the TTY for reading commands and process them 
        open (VMTTY, "< $vm_tty") or vnxaced_die ("Couldn't open $vm_tty for reading");
        wlog (V, "Waiting for commands on serial line...");
        while ( chomp( my $line = <VMTTY> ) ) {
            process_cmd ($line);
            wlog (V, "Waiting for commands on serial line...");
        }
    
    } elsif ( H2VM_CHANNEL eq 'SHARED_FILE' ){
        
        my $cmd_file      = MSG_FILE . '.msg';
        my $cmd_file_lock = MSG_FILE . '.lock';
        my $cmd_file_res  = MSG_FILE . '.res';

        while (1) {         
            wlog (V, "Waiting for commands on shared file ($cmd_file)...");
            while ( ! (-e $cmd_file && ! -e $cmd_file_lock ) ) {
                #print "$cmd_file\n";
                sleep 1;
                #print ".";
            }
            my $cmd = `cat $cmd_file`; chomp( $cmd );
            system("rm -f $cmd_file");
            process_cmd ($cmd);

            #sleep 1;
            # Write result
            #$cmd = "touch $cmd_file_lock"; system ($cmd);
            #$cmd = "echo 'OK' > $cmd_file_res"; system ($cmd);
            #$cmd = "rm -f $cmd_file_lock"; system ($cmd);
        }
    }
    
}

sub send_cmd_response {
    
    my $resp = shift;
    
    wlog (V, "     sending response '$resp' to host...\n");
    if ( H2VM_CHANNEL eq 'SERIAL' ) {
        system "echo $resp > $vm_tty";

    } elsif ( H2VM_CHANNEL eq 'SHARED_FILE' ){

        my $cmd_file      = MSG_FILE . '.msg';
        my $cmd_file_lock = MSG_FILE . '.lock';
        my $cmd_file_res  = MSG_FILE . '.res';
    
        #sleep 1;
        # Write result
        my $cmd = "touch $cmd_file_lock"; system ($cmd);
        $cmd = "echo '$resp' > $cmd_file_res"; system ($cmd);
        $cmd = "rm -f $cmd_file_lock"; system ($cmd);

    }       
}

sub process_cmd {
    
    my $line  = shift;
    
    my $res; # Command execution result: OK, NOTOK

    my $cd_dir;
    my $files_dir;
    if ($platform[0] eq 'Linux'){
        $cd_dir = LINUX_CD_DIR;
    } elsif ($platform[0] eq 'FreeBSD'){
        $cd_dir = FREEBSD_CD_DIR;
    }

    wlog (V, "Command received: '$line'");
        
    my @cmd = split(/ /, $line);

    if ($cmd[0] eq "exeCommand") {

        if ( ($cmd[1] eq "cdrom") || ($cmd[1] eq "sdisk") ) {

            if ( $cmd[1] eq "cdrom" ) {
                exe_mount_cmd ($mount_cdrom_cmd);
                $files_dir = $cd_dir;
            } else { # sdisk 
                exe_mount_cmd ($mount_sdisk_cmd);
                $files_dir = '/mnt/sdisk';
            }

            if ($VERBOSE) {
                my $res=`ls -l $files_dir`; wlog (V, "\n$cmd[1] content: ~~\n$res~~~~~~~~~~~~~~~~~~~~\n")
            }

            my @files = <$files_dir/*>;
        
            foreach my $file (@files){
                    
                my $fname = basename ($file);
                if ($fname eq "command.xml"){
                    unless (&is_new_file($file)){
                        next;               
                    }
                    if ($VERBOSE) { my $f=`cat $file`; wlog (V, "\n$fname ~~\n$f~~~~~~~~~~~~~~~~~~~~\n"); }
                    chomp (my $now = `date`);                       
                    wlog (V, "$now:");
                    wlog (V, "     command received in $file");
                    &execute_filetree($file);
                    &execute_commands($file);
                    wlog (V, "     sending 'done' signal to host...\n");
                    send_cmd_response ("OK");
                    #system "echo OK > $vm_tty";
                    
                } elsif ( ($fname eq "vnxboot") || ($fname eq "vnxboot.xml") ) {

                    unless (&is_new_file($file)){
                            
                        # Autoconfiguration is done and the system has restarted 
                        # Check if commands with seq="on_boot" have been executed
                        my $on_boot_cmds_pending = get_conf_value (VNXACED_STATUS, 'on_boot_cmds_pending');
                        if ($on_boot_cmds_pending eq 'yes') {
                            wlog (V, "   executing <filetree> and <exec> commands with seq='on_boot' after restart");
                            # Execute all <filetree> and <exec> commands in vnxboot file            
                            # Execute <filetree> commands
                            &execute_filetree($file);
                            # Execute <exec> commands 
                            &execute_commands($file);
                            # Commands executed, change config
                            set_conf_value (VNXACED_STATUS, 'on_boot_cmds_pending', 'no')
                        }
                        next;               
                    }

                    if ($VERBOSE) { my $f=`cat $file`; wlog (V, "\n$fname ~~\n$f~~~~~~~~~~~~~~~~~~~~\n"); }
                    chomp (my $now = `date`);                       
                    wlog (V, "$now:");
                    wlog (V, "     configuration file received in $file");
                    set_conf_value (VNXACED_STATUS, 'on_boot_cmds_pending', 'yes');
                    set_conf_value (VNXACED_STATUS, 'exec_mode', $cmd[1]);
                    #send_cmd_response ('OK');
                    autoconfigure($file);
    
                } elsif ($fname eq "vnx_update.xml"){
                    unless (&is_new_file($file) eq '1'){
                        next;               
                    }
                    if ($VERBOSE) { my $f=`cat $file`; wlog (V, "\n$fname ~~\n$f~~~~~~~~~~~~~~~~~~~~\n"); }
                    chomp (my $now = `date`);                       
                    wlog (V, "$now:");
                    wlog (V, "     update files received in $file");
                    #send_cmd_response ('OK');
                    autoupdate ($files_dir);
     
                } else {
                    # unknown file, do nothing
                }
            }

            if ( $cmd[1] eq "cdrom" ) {
                exe_mount_cmd ($umount_cdrom_cmd);
            } else { # sdisk 
                exe_mount_cmd ($umount_sdisk_cmd);
            }
               
        } else {
            wlog (V, "ERROR: exec_mode $cmd[1] not supported");
            send_cmd_response ("NOTOK exec_mode $cmd[1] not supported"); 
        }
            
    } elsif ($cmd[0] eq "nop") { # do nothing

        wlog (V, "nop command received. Nothing to do.");
        send_cmd_response ('OK');

    } elsif ($cmd[0] eq "hello") { 

        wlog (V, "hello command received. Sending OK...");
        send_cmd_response ('OK');
        #system "echo OK > $vm_tty";

    } elsif ($cmd[0] eq "halt") { 

        wlog (V, "halt command received. Sending OK and halting...");
        send_cmd_response ('OK');
        #system "echo OK > $vm_tty";
        system "halt -p";

    } elsif ($cmd[0] eq "reboot") { 

        wlog (V, "reboot command received. Sending OK and rebooting...");
        send_cmd_response ('OK');
        #system "echo OK > $vm_tty";
        system "reboot";

    } elsif ($cmd[0] eq "vnxaced_update") { 

        wlog (V, "vnxaced_update command received. Updating and sending OK...");
        
        if ( ($cmd[1] eq "cdrom") || ($cmd[1] eq "sdisk") ) {

            if ( $cmd[1] eq "cdrom" ) {
                exe_mount_cmd ($mount_cdrom_cmd);
                $files_dir = $cd_dir;
            } else { # sdisk 
                exe_mount_cmd ($mount_sdisk_cmd);
                $files_dir = '/mnt/sdisk';
            }

            if ($VERBOSE) {
                my $res=`ls -l $files_dir`; wlog (V, "\n~~ $cmd[1] content: ~~\n$res~~~~~~~~~~~~~~~~~~~~\n")
            }
            
            send_cmd_response ('OK');
            #system "echo OK > $vm_tty";
            autoupdate ($files_dir);             
            
        } else {
            wlog (V, "ERROR: exec_mode $cmd[1] not supported");
            send_cmd_response ("NOTOK exec_mode $cmd[1] not supported");
            #system "echo $msg > $vm_tty";
        }
        
    } else {
        wlog (V, "ERROR: unknown command ($cmd[0])");
        send_cmd_response ("NOTOK unknown command ($cmd[0])");
        
    }   
    
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub autoupdate {
    
    my $files_dir = shift;  
    
    my $res;
    
    #############################
    # update for Linux          #
    #############################
    if ($platform[0] eq 'Linux'){
        wlog (V, "     updating vnxaced for Linux...");

        if (-e "$files_dir/install_vnxaced") {
            system "perl $files_dir/uninstall_vnxaced -n";
            $res = system "perl $files_dir/install_vnxaced";
        } elsif (-e "$files_dir/vnxaced-lf/install_vnxaced") {
            system "perl $files_dir/vnxaced-lf/uninstall_vnxaced -n";
            $res = system "perl $files_dir/vnxaced-lf/install_vnxaced";
        }
        
        #if ( ($platform[1] eq 'Ubuntu') or   
        #    ($platform[1] eq 'Fedora') ) { 
        #   # Use VNXACED based on upstart
        #   system "cp /media/cdrom/vnxaced.pl /usr/local/bin/vnxaced";
        #   system "cp /media/cdrom/linux/upstart/vnxace.conf /etc/init/";
        #} elsif ($platform[1] eq 'CentOS') { 
        #   # Use VNXACED based on init.d
        #   system "cp -v vnxaced.pl /usr/local/bin/vnxaced";
        #   system "cp -v unix/init.d/vnxace /etc/init.d/";
        #}
    }
    #############################
    # update for FreeBSD        #
    #############################
    elsif ($platform[0] eq 'FreeBSD'){
        wlog (V, "     updating vnxdaemon for FreeBSD...");

        if (-e "$files_dir/install_vnxaced") {
            system "$files_dir/uninstall_vnxaced -n";
            $res = system "$files_dir/install_vnxaced";
        } elsif (-e "$files_dir/vnxaced-lf/install_vnxaced") {
            system "$files_dir/vnxaced-lf/uninstall_vnxaced -n";
            $res = system "$files_dir/vnxaced-lf/install_vnxaced";
        }
        #system "cp /cdrom/vnxaced.pl /usr/local/bin/vnxaced";
        #system "cp /cdrom/freebsd/vnxace /etc/rc.d/vnxace";
    }
    
    if ($res != 0) {
        write_console ( "\r\n" );
        write_console ( "   ------------------------------------------------------------------------\r\n" );
        write_console ( "    ERROR: vnxaced not updated. Try to install manually to see errors\r\n" );
        write_console ( "   ------------------------------------------------------------------------\r\n" );
        return;
    }
    
    # Write trace messages to /etc/vnx_rootfs_version, log file and console
    my $vnxaced_vers = `/usr/local/bin/vnxaced -V | grep Version | awk '{printf "%s %s",\$2,\$3}'`;
    chomp (my $date = `date`);
    # vnx_rootfs_version file
    system "printf \"MODDATE=$date\n\" >> /etc/vnx_rootfs_version";
    system "printf \"MODDESC=vnxaced updated to vers $vnxaced_vers\n\" >> /etc/vnx_rootfs_version";
    # vnxaced log file
    wlog (V, "     vnxaced updated to vers $vnxaced_vers");

    # Console messages
    
    write_console ( "\r\n" );
    write_console ( "   ------------------------------------------------------------------------\r\n" );
    write_console ( "         vnxaced updated to vers $vnxaced_vers \r\n" );
    write_console ( "   ------------------------------------------------------------------------\r\n" );
    my $delay=5;
    write_console ( "\n         halting system in $delay seconds" );
        for (my $count = $delay-1; $count >= 0; $count--) {
        sleep 1;
        write_console ( "\b\b\b\b\b\b\b\b\b$count seconds" );
    }
    write_console ( "\r\n\r\n\r\n" );
    
    # Stop VNXACED 
    #if ($platform[0] eq 'Linux'){
    #    if ( ($platform[1] eq 'Ubuntu') or ($platform[1] eq 'Fedora') ) { 
    #        system "service vnxace stop";
    #    } elsif ($platform[1] eq 'CentOS') { 
    #        system "/etc/init.d/vnxace stop";
    #    }
    #} elsif ($platform[0] eq 'FreeBSD'){
    #    system "/etc/rc.d/vnxace stop";
    #}    
    # Delete VNXACE log and .vnx dir
    system "rm -f " . VNXACED_LOG;
    system "touch " . VNXACED_LOG;
    system "rm -f /root/.vnx/*";
    
    # Shutdown system
    # system "vnx_halt -y > /dev/null 2>&1 < /dev/null";  # Does not work....why?
    system "halt -p";
    return;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub is_new_file {

    my $file = shift;

    my $parser    = XML::LibXML->new;
    my $dom       = $parser->parse_file($file);
    my $idTagList = $dom->getElementsByTagName("id");
    my $idTag     = $idTagList->item(0);
    my $new_cid   = $idTag->getFirstChild->getData;
    chomp($new_cid);
#   wlog (V, "sleep 60");
#   sleep 60;
    
    #my $command = "cat /root/.vnx/command_id";
    #chomp (my $old_cid = `$command`);
    
    my $old_cid = get_conf_value (VNXACED_STATUS, 'cmd_id');
    #write_console ("~~ old_cid = '$old_cid'\r\n");
    #write_console ("~~ new_cid = '$new_cid'\r\n");
    
    #wlog (V, "comparing -$old_cid- and -$new_cid-");
    
    if ( ($old_cid ne '') && ($old_cid eq $new_cid)) {
        # file is not new
        wlog (V, "$file file is not new");
        return "0";
    }

    #file is new
    #wlog (V, "file is new");
    #system "echo '$new_cid' > /root/.vnx/command_id";
    my $res = set_conf_value (VNXACED_STATUS, 'cmd_id', $new_cid);
    wlog (V, "Error writing the new comand id value to " . VNXACED_STATUS . " file") 
        if ($res eq 'ERROR'); 
    
    # check it is written correctly
    $new_cid = get_conf_value (VNXACED_STATUS, 'cmd_id');
    #write_console ("~~ cid saved to disk = '$new_cid'\r\n");

    return "1";
}


#~~~~~~~~~~~~~~ command execution ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#
# exe_cmd
#
# Executes the commands received in the commands.xml file according 
# to the value of the ostype parameter of <exec> tag:
#
#   - exec:     commands with no gui; script does not wait for the command 
#               to finish execution (a new process is forked for the command)
#   - system:   commands with no gui; script waits till command ends execution 
#   - xexec:    commands with gui; script does not wait 
#   - xsystem:  commands with gui; script waits
#
sub exe_cmd {

    my $cmd = shift;
    my $ostype = shift;

    wlog (V, "Command output:");
    if ($ostype eq 'system') {
        # Execution mode for commands with no graphical user interface
        if ($DEBUG) {
            # vnxace has been started from the command line with -g option
            # No problems with input/ouptut redirection. We execute it using 
            # backticks to capture output
            my $res=`$cmd`;
            wlog (V, $res);
        } else {
            # vnxace has been started as a deamon with input/output closed
            # We have to use this way to execute the command to avoid 
            # problems. Other ways tested (using exec or system with all kind of 
            # input/output redirections made some commands fail (for example, when 
            # starting apache: the server starts but does not answer requests and 
            # shows an error in logs related to sockets). 
            exe_cmd_aux ("$cmd");
        } 
    } elsif ($ostype eq 'exec') {
        # Execution mode for commands with no graphical user interface using fork and exec
        my $pid2 = fork;
        die "Couldn't fork: $!" unless defined($pid2);
        if ($pid2){
            # parent does nothing
        }else{
            # child executes command and dies
            if ($DEBUG) {
                my $res=`$cmd`;
                wlog (V, $res);
            } else {
                exe_cmd_aux ("$cmd");
                exit (0);
            } 
        }
    } elsif ( ($ostype eq 'xexec') or ($ostype eq 'xsystem') ) { 
        # Execution mode for commands with graphical user interface
        # We execute the commands using the xsu utility described in 
        # http://wiki.tldp.org/Remote-X-Apps.
        # Basically, the applications are executed from the vnxaced
        # script run as root making a 'su' to the user who owns 
        # the DISPLAY :0.0  

        # Guess the user who owns display :0.0
        my $w=`w | grep ' :0 '`;
        my @userOnDisplay0 = split (/ /, $w);
        if (! $userOnDisplay0[0]) {
            wlog (V, "     ERROR: no user logged on display :0.0. Command $cmd not executed.");
        } else {
            wlog (V, "User on display :0.0 -->$userOnDisplay0[0]\n");

            if($ostype eq "xexec"){
                my $pid2 = fork;
                die "Couldn't fork: $!" unless defined($pid2);
                if ($pid2){
                    # parent does nothing
                }else{
                    # child executes command and dies
                    if ($platform[0] eq 'Linux'){
                        wlog (V, "exec \"setsid sh -c \\\"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] \'$cmd\'\\\"\" < /dev/null > /dev/null 2>&1");
                        exec "setsid sh -c \"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] '$cmd'\" > /dev/null 2>&1 < /dev/null";
                    } elsif ($platform[0] eq 'FreeBSD'){
                        wlog (V, "system \"detach sh -c \\\"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] \'$cmd\'\\\"\" < /dev/null > /dev/null 2>&1");
                        system "detach sh -c \"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] '$cmd'\" > /dev/null 2>&1 < /dev/null";
                        exit (0);
                    }
                    
                }

            } elsif($ostype eq "xsystem"){
                wlog (V, "DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] '$cmd' ");
                my $res= `DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] '$cmd' < /dev/null 2>&1`;
                wlog (V, $res);
            }
        }

    } else {
        wlog (V, "   ERROR: command ostype mode '$ostype' unknown, use 'exec', 'system', 'xexec' or 'xsystem'. ");
    }
    wlog (V, "~~~~~~~~~~~~~~~~~~");
}

sub exe_cmd_aux {
    my $cmd = shift;
    open my $command, "$cmd < /dev/null 2>&1 |";
    open my $output, ">> " . VNXACED_LOG;
    while (<$command>) { print $output $_; }
    close $command;
    close $output;
}

#~~~~~~~~~~~~~~ command execution ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#
# execute_commands
#
# Executes the commands received in the commands.xml file 
#

sub execute_commands {

    my $commands_file = shift;

    my $parser       = XML::LibXML->new();
    my $dom          = $parser->parse_file($commands_file);
    #my $parser       = new XML::DOM::Parser;
    #my $dom          = $parser->parsefile($commands_file);
    #my $execTagList = $dom->getElementsByTagName("exec");
    #for (my $j = 0 ; $j < $execTagList->getLength; $j++){

    foreach my $exec ($dom->getElementsByTagName("exec")) {

        #my $execTag    = $execTagList->item($j);
        #my $seq        = $exec->getAttribute("seq");
        #my $type       = $exec->getAttribute("type");
        my $ostype     = $exec->getAttribute("ostype");
        my $command2   = $exec->getFirstChild->getData;
            
        wlog (V, "     executing: '$command2' in ostype mode: '$ostype'");
        exe_cmd ($command2, $ostype);
    }
}

#~~~~~~~~~~~~~~ autoconfiguration ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub autoconfigure {

    my $vnxboot_file = shift;

    my $warn_msg =  <<EOF;
    
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ~~~~~                   WARNING!                   ~~~~~
    ~~~~~     VNX Autoconfiguration in progress...     ~~~~~
    ~~~~~    Wait until the virtual machine reboots    ~~~~~
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
EOF

    my $parser = XML::LibXML->new;
    my $dom    = $parser->parse_file($vnxboot_file);
  
    # autoconfigure for Linux
    if ($platform[0] eq 'Linux'){
        # Send a message to consoles
        #system "shutdown -k now 'VNX system autoconfiguration in progress...wait until the system reboots...'";

        write_console ("$warn_msg\n");
        my $cmd = "cat " . VNXACED_STATUS; my $status=`$cmd`; 
        wlog (V, "-------------------------\r\nvnxaced.status file:\r\n");
        wlog (V, "$status\r\n"); 
        wlog (V, "-------------------------\r\n"); 

        if    ($platform[1] eq 'Ubuntu')   { autoconfigure_debian_ubuntu ($dom, '/', 'ubuntu') }           
        elsif ($platform[1] eq 'Debian')   { autoconfigure_debian_ubuntu ($dom, '/', 'debian') }           
        elsif ($platform[1] eq 'Fedora')   { autoconfigure_redhat ($dom, '/', 'fedora') }
        elsif ($platform[1] eq 'CentOS')   { autoconfigure_redhat ($dom, '/', 'centos') }

    }
    # autoconfigure for FreeBSD
    elsif ($platform[0] eq 'FreeBSD') {
        #wlog (V, "calling autoconfigure_freebsd");
        write_console ("$warn_msg\n");
        autoconfigure_freebsd ($dom, '/')
    }
    
    # Change the message of the day (/etc/motd) to eliminate the
    # message asking to wait for reboot
    #system "sed -i -e '/~~~~~/d' /etc/motd";
    
    # Reboot system
    wlog (V, "   rebooting...\n");
    sleep 5;
    system "shutdown -r now '  VNX:  autoconfiguration finished...rebooting'";
    #sleep 100; # wait for system to reboot
}

#~~~~~~~~~~~~~~ filetree processing ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub execute_filetree {

    my $cmd_file = shift;

    my $cmd_path = dirname($cmd_file);
    
    my $vopt=''; if ($VERBOSE) { $vopt='-v' };

    wlog (V, "processing <filetree> tags in file $cmd_file");

    my $parser = XML::LibXML->new;
    my $dom    = $parser->parse_file($cmd_file);

#    my $filetree_taglist = $dom->getElementsByTagName("filetree");
#    for (my $j = 0 ; $j < $filetree_taglist->size ; $j++){
#
#        # Note DFC 16/12/2012: with LibXML the first element is 1 (not 0)
#        my $filetree_tag = $filetree_taglist->item($j+1);

    my $j = 0;
    foreach my $filetree_tag ($dom->getElementsByTagName("filetree")) {
        
        my $seq          = $filetree_tag->getAttribute("seq");
        my $root         = $filetree_tag->getAttribute("root");
        my $user         = $filetree_tag->getAttribute("user");
        my $group        = $filetree_tag->getAttribute("group");
        my $perms        = $filetree_tag->getAttribute("perms");
        my $source       = $filetree_tag->getFirstChild->getData;
        my $folder = $j + 1;
        $j++;
        my $source_path = $cmd_path . "/filetree/" . $folder . "/";
        wlog (V, "   processing <filetree> tag: seq=$seq, root=$root, " . 
                         "user=$user, group=$group, perms=$perms, source_path=$source_path");

        my $res=`ls -R $source_path`; wlog (V, "cdrom content: $res") if ($VERBOSE);
        # Get the number of files in source dir
        my $num_files=`ls -a1 $source_path | wc -l`;
        if ($num_files < 3) { # count "." and ".."
            wlog (V, "   ERROR in filetree: no files to copy in $source_path (seq=$seq)\n");
            next;
        }
        # Check if files destination (root attribute) is a directory or a file
        my $cmd;
        if ( $root =~ /\/$/ ) {
            # Destination is a directory
            wlog (V, "   Destination is a directory");
            unless (-d $root){
                wlog (V, "   creating unexisting dir '$root'...");
                system "mkdir -p $root";
            }

            $cmd="cp -vR ${source_path}* $root";
            wlog (V, "   Executing '$cmd' ...");
            $res=`$cmd`;
            wlog (V, "Copying filetree files ($root):") if ($VERBOSE);
            wlog (V, "$res") if ($VERBOSE);

            # Change owner and permissions if specified in <filetree>
            my @files= <${source_path}*>;
            foreach my $file (@files) {
                my $fname = basename ($file);
                wlog (V, $file . "," . $fname);
                if ( $user ne ''  ) {
                    $res=`chown -R $vopt $user $root/$fname`; wlog (V, $res) if ($VERBOSE); }
                if ( $group ne '' ) {
                    $res=`chown -R $vopt .$group $root/$fname`; wlog (V, $res) if ($VERBOSE); }
                if ( $perms ne '' ) {
                    $res=`chmod -R $vopt $perms $root/$fname`; wlog (V, $res) if ($VERBOSE); }
            }
            
        } else {
            # Destination is a file
            # Check that $source_path contains only one file
            wlog (V, "   Destination is a file");
            wlog (V, "       source_path=${source_path}");
            wlog (V, "       root=${root}");
            if ($num_files > 3) { # count "." and ".."
                wlog (V, "   ERROR in filetree: destination ($root) is a file and there is more than one file in $source_path (seq=$seq)\n");
                next;
            }
            my $file_dir = dirname($root);
            unless (-d $file_dir){
                wlog (V, "   creating unexisting dir '$file_dir'...");
                system "mkdir -p $file_dir";
            }
            $cmd="cp -v ${source_path}* $root";
            wlog (V, "   Executing '$cmd' ...");
            $res=`$cmd`;
            wlog (V, "Copying filetree file ($root):") if ($VERBOSE);
            wlog (V, "$res") if ($VERBOSE);
            # Change owner and permissions of file $root if specified in <filetree>
            if ( $user ne ''  ) {
                $cmd="chown -R $vopt $user $root";
                $res=`$cmd`; wlog (V, $cmd . "/n" . $res) if ($VERBOSE); }
            if ( $group ne '' ) {
                $cmd="chown -R $vopt .$group $root";
                $res=`$cmd`; wlog (V, $cmd . "/n" . $res) if ($VERBOSE); }
            if ( $perms ne '' ) {
                $cmd="chmod -R $vopt $perms $root";
                $res=`$cmd`; wlog (V, $cmd . "/n" . $res) if ($VERBOSE); }
        }
        wlog (V, "~~~~~~~~~~~~~~~~~~~~");
    }
}






#
# autoconfigure for Ubuntu/Debian
#
sub autoconfigure_debian_ubuntu {
    
    my $dom         = shift; # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $os_type     = shift; # ubuntu or debian
    my $error;
    
    my $logp = "autoconfigure_debian_ubuntu> ";

    wlog (VVV, "rootfs_mdir=$rootfs_mdir", $logp);
    
    # Big danger if rootfs mount directory ($rootfs_mdir) is empty: 
    # host files will be modified instead of rootfs image ones
    unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' ) {
        die;
    }    

    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # Files modified
    my $interfaces_file = "$rootfs_mdir" . "/etc/network/interfaces";
    my $sysctl_file     = "$rootfs_mdir" . "/etc/sysctl.conf";
    my $hosts_file      = "$rootfs_mdir" . "/etc/hosts";
    my $hostname_file   = "$rootfs_mdir" . "/etc/hostname";
    my $resolv_file     = "$rootfs_mdir" . "/etc/resolv.conf";
    my $rules_file      = "$rootfs_mdir" . "/etc/udev/rules.d/70-persistent-net.rules";
    
    # Backup and delete /etc/resolv.conf file
    if (-f $resolv_file ) {
        system "cp $resolv_file ${resolv_file}.bak";
        system "rm -f $resolv_file";
    }
        
    # before the loop, backup /etc/udev/...70
    # and /etc/network/interfaces
    # and erase their contents
    wlog (VVV, "   configuring $rules_file and $interfaces_file...", $logp);
    if (-f $rules_file) {
        system "cp $rules_file $rules_file.backup";
    }
    system "echo \"\" > $rules_file";
    open RULES, ">" . $rules_file or return "error opening $rules_file";
    system "cp $interfaces_file $interfaces_file.backup";
    system "echo \"\" > $interfaces_file";
    open INTERFACES, ">" . $interfaces_file or return "error opening $interfaces_file";

    print INTERFACES "\n";
    print INTERFACES "auto lo\n";
    print INTERFACES "iface lo inet loopback\n";

    # Network routes configuration: we read all <route> tags
    # and store the ip route configuration commands in @ip_routes
    my @ipv4_routes;       # Stores the IPv4 route configuration lines
    my @ipv4_routes_gws;   # Stores the IPv4 gateways of each route
    my @ipv6_routes;       # Stores the IPv6 route configuration lines
    my @ipv6_routes_gws;   # Stores the IPv6 gateways of each route
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ($route_type eq 'ipv4') {
            if ($route eq 'default') {
                #push (@ipv4_routes, "   up route add -net default gw " . $route_gw . "\n");
                push (@ipv4_routes, "   up ip -4 route add default via " . $route_gw . "\n");
            } else {
                #push (@ipv4_routes, "   up route add -net $route gw " . $route_gw . "\n");
                push (@ipv4_routes, "   up ip -4 route add $route via " . $route_gw . "\n");
            }
            push (@ipv4_routes_gws, $route_gw);
        } elsif ($route_type eq 'ipv6') {
            if ($route eq 'default') {
                #push (@ipv6_routes, "   up route -A inet6 add default gw " . $route_gw . "\n");
                push (@ipv6_routes, "   up ip -6 route add default via " . $route_gw . "\n");
            } else {
                #push (@ipv6_routes, "   up route -A inet6 add $route gw " . $route_gw . "\n");
                push (@ipv6_routes, "   up ip -6 route add $route via " . $route_gw . "\n");
            }
            push (@ipv6_routes_gws, $route_gw);
        }
    }   

    # Network interfaces configuration: <if> tags
    my @if_list = $vm->getElementsByTagName("if");
    for (my $j = 0 ; $j < @if_list; $j++){
        my $if  = $if_list[$j];
        my $id  = $if->getAttribute("id");
        my $net = $if->getAttribute("net");
        my $mac = $if->getAttribute("mac");
        $mac =~ s/,//g;

        my $if_name;
        # Special cases: loopback interface and management
        if ( !defined($net) && $id == 0 ) {
            $if_name = "eth" . $id;
        } elsif ( $net eq "lo" ) {
            $if_name = "lo" . $id;
        } else {
            $if_name = "eth" . $id;
        }

        print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac .  "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $if_name . "\"\n\n";
        #print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";
        print INTERFACES "\nauto " . $if_name . "\n";

        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");
        my @ipv4_addr_list;
        my @ipv4_mask_list;
        my @ipv6_addr_list;
        my @ipv6_mask_list;

        if ( (@ipv4_tag_list == 0 ) && ( @ipv6_tag_list == 0 ) ) {
            # No addresses configured for the interface. We include the following commands to 
            # have the interface active on start
            print INTERFACES "iface " . $if_name . " inet manual\n";
            print INTERFACES "  up ifconfig " . $if_name . " 0.0.0.0 up\n";
        } else {
            # Config IPv4 addresses
            for ( my $j = 0 ; $j < @ipv4_tag_list ; $j++ ) {

                my $ipv4 = $ipv4_tag_list[$j];
                my $mask = $ipv4->getAttribute("mask");
                my $ip   = $ipv4->getFirstChild->getData;

                if ($ip eq 'dhcp') {
                        print INTERFACES "iface " . $if_name . " inet dhcp\n";                  
                } else {
                    if ($j == 0) {
                        print INTERFACES "iface " . $if_name . " inet static\n";
                        print INTERFACES "   address " . $ip . "\n";
                        print INTERFACES "   netmask " . $mask . "\n";
                    } else {
                        print INTERFACES "   up /sbin/ifconfig " . $if_name . " inet add " . $ip . " netmask " . $mask . "\n";
                    }
                    push (@ipv4_addr_list, $ip);
                    push (@ipv4_mask_list, $mask);
                }
            }
            # Config IPv6 addresses
            for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

                my $ipv6 = $ipv6_tag_list[$j];
                my $ip   = $ipv6->getFirstChild->getData;
                my $mask = $ip;
                $mask =~ s/.*\///;
                $ip =~ s/\/.*//;

                if ($ip eq 'dhcp') {
                        print INTERFACES "iface " . $if_name . " inet6 dhcp\n";                  
                } else {
                    if ($j == 0) {
                        print INTERFACES "iface " . $if_name . " inet6 static\n";
                        print INTERFACES "   address " . $ip . "\n";
                        print INTERFACES "   netmask " . $mask . "\n";
                    } else {
                        print INTERFACES "   up /sbin/ifconfig " . $if_name . " inet6 add " . $ip . "/" . $mask . "\n";
                    }
                    push (@ipv6_addr_list, $ip);
                    push (@ipv6_mask_list, $mask);
                }
            }

            #
            # Include in the interface configuration the routes that point to it
            #
            # IPv4 routes
            for (my $i = 0 ; $i < @ipv4_routes ; $i++){
                my $route = $ipv4_routes[$i];
                chomp($route); 
                for (my $j = 0 ; $j < @ipv4_addr_list ; $j++) {
                    my $ipv4_route_gw = new NetAddr::IP $ipv4_routes_gws[$i];
                    if ($ipv4_route_gw->within(new NetAddr::IP $ipv4_addr_list[$j], $ipv4_mask_list[$j])) {
                        print INTERFACES $route . "\n";
                    }
                }
            }           
            # IPv6 routes
            for (my $i = 0 ; $i < @ipv6_routes ; $i++){
                my $route = $ipv6_routes[$i];
                chomp($route); 
                for (my $j = 0 ; $j < @ipv6_addr_list ; $j++) {
                    my $ipv6_route_gw = new NetAddr::IP $ipv6_routes_gws[$i];
                    if ($ipv6_route_gw->within(new NetAddr::IP $ipv6_addr_list[$j], $ipv6_mask_list[$j])) {
                        print INTERFACES $route . "\n";
                    }
                }
            }           
        }
    }
        
    close RULES;
    close INTERFACES;
        
    # Packet forwarding: <forwarding> tag
    my $ipv4_forwarding = 0;
    my $ipv6_forwarding = 0;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    for (my $j = 0 ; $j < @forwarding_list ; $j++){
        my $forwarding = $forwarding_list[$j];
        my $forwarding_type = $forwarding->getAttribute("type");
        if ($forwarding_type eq "ip"){
            $ipv4_forwarding = 1;
            $ipv6_forwarding = 1;
        } elsif ($forwarding_type eq "ipv4"){
            $ipv4_forwarding = 1;
        } elsif ($forwarding_type eq "ipv6"){
            $ipv6_forwarding = 1;
        }
    }
    wlog (VVV, "   configuring ipv4 ($ipv4_forwarding) and ipv6 ($ipv6_forwarding) forwarding in $sysctl_file...", $logp);
    system "echo >> $sysctl_file ";
    system "echo '# Configured by VNX' >> $sysctl_file ";
    system "echo 'net.ipv4.ip_forward=$ipv4_forwarding' >> $sysctl_file ";
    system "echo 'net.ipv6.conf.all.forwarding=$ipv6_forwarding' >> $sysctl_file ";

    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file", $logp);
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '1i127.0.0.1  localhost.localdomain   localhost' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change /etc/hostname
    system "echo $vm_name > $hostname_file";

    return $error;
    
}


#
# autoconfigure for Redhat (Fedora and CentOS)             
#
sub autoconfigure_redhat {

    my $dom = shift;         # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $os_type = shift; # fedora or centos
    my $error;

    my $logp = "autoconfigure_redhat ($os_type)> ";

    # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
    # host files will be modified instead of rootfs image ones
    unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' ) {
        die;
    }    
        
    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # Files modified
    my $sysctl_file     = "$rootfs_mdir" . "/etc/sysctl.conf";
    my $hosts_file      = "$rootfs_mdir" . "/etc/hosts";
    my $hostname_file   = "$rootfs_mdir" . "/etc/hostname";
    my $resolv_file     = "$rootfs_mdir" . "/etc/resolv.conf";
    my $rules_file      = "$rootfs_mdir" . "/etc/udev/rules.d/70-persistent-net.rules";
    my $sysconfnet_file = "$rootfs_mdir" . "/etc/sysconfig/network";
    my $sysconfnet_dir  = "$rootfs_mdir" . "/etc/sysconfig/network-scripts";

    # Delete /etc/resolv.conf file
    if (-f $resolv_file ) {
        system "cp $resolv_file ${resolv_file}.bak";
        system "rm -f $resolv_file";
    }

    system "mv $sysconfnet_file ${sysconfnet_file}.bak";
    system "cat ${sysconfnet_file}.bak | grep -v 'NETWORKING=' | grep -v 'NETWORKING_IPv6=' > $sysconfnet_file";
    system "echo NETWORKING=yes >> $sysconfnet_file";
    system "echo NETWORKING_IPV6=yes >> $sysconfnet_file";

    if (-f $rules_file) {
        system "cp $rules_file $rules_file.backup";
    }
    system "echo \"\" > $rules_file";

    wlog (VVV, "   configuring $rules_file...", $logp);
    open RULES, ">" . $rules_file or return "error opening $rules_file";

    # Delete ifcfg and route files
    system "rm -f $sysconfnet_dir/ifcfg-Auto_eth*"; 
    system "rm -f $sysconfnet_dir/ifcfg-eth*"; 
    system "rm -f $sysconfnet_dir/route-Auto*"; 
    system "rm -f $sysconfnet_dir/route6-Auto*"; 
        
    # Network interfaces configuration: <if> tags
    my @if_list = $vm->getElementsByTagName("if");
    my $first_ipv4_if;
    my $first_ipv6_if;
        
    for (my $i = 0 ; $i < @if_list ; $i++){
        my $if  = $if_list[$i];
        my $id  = $if->getAttribute("id");
        my $net = $if->getAttribute("net");
        my $mac = $if->getAttribute("mac");
        $mac =~ s/,//g;
            
        #wlog (VVV, "Processing if $id, net=" . str($net) . ", mac=$mac", $logp);            

        my $if_name;
        # Special cases: loopback interface and management
        if ( !defined($net) && $id == 0 ) {
            $if_name = "eth" . $id;
        } elsif ( $net eq "lo" ) {
            $if_name = "lo" . $id;
        } else {
            $if_name = "eth" . $id;
        }
            
        if ($os_type eq 'fedora') { 
            print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac .  "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $if_name . "\"\n\n";
            #print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";

        } elsif ($os_type eq 'centos') { 
#           print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"" . $if_name . "\"\n\n";
        }

        my $if_file;
        if ($os_type eq 'fedora') { 
           $if_file = "$sysconfnet_dir/ifcfg-Auto_$if_name";
        } elsif ($os_type eq 'centos') { 
            $if_file = "$sysconfnet_dir/ifcfg-$if_name";
        }
        system "echo \"\" > $if_file";
        open IF_FILE, ">" . $if_file or return "error opening $if_file";
    
        if ($os_type eq 'CentOS') { 
            print IF_FILE "DEVICE=$if_name\n";
        }
        print IF_FILE "HWADDR=$mac\n";
        print IF_FILE "TYPE=Ethernet\n";
        #print IF_FILE "BOOTPROTO=none\n";
        print IF_FILE "ONBOOT=yes\n";
        if ($os_type eq 'fedora') { 
            print IF_FILE "NAME=\"Auto $if_name\"\n";
        } elsif ($os_type eq 'centos') { 
            print IF_FILE "NAME=\"$if_name\"\n";
        }

        print IF_FILE "IPV6INIT=yes\n";
            
        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");

        # Config IPv4 addresses
        for ( my $j = 0 ; $j < @ipv4_tag_list ; $j++ ) {

            my $ipv4 = $ipv4_tag_list[$j];
            my $mask = $ipv4->getAttribute("mask");
            my $ip   = $ipv4->getFirstChild->getData;

            $first_ipv4_if = "$if_name" unless defined($first_ipv4_if); 

            if ($j == 0) {
                print IF_FILE "IPADDR=$ip\n";
                print IF_FILE "NETMASK=$mask\n";
            } else {
                my $num = $j+1;
                print IF_FILE "IPADDR$num=$ip\n";
                print IF_FILE "NETMASK$num=$mask\n";
            }
        }
        # Config IPv6 addresses
        my $ipv6secs;
        for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

            my $ipv6 = $ipv6_tag_list[$j];
            my $ip   = $ipv6->getFirstChild->getData;

            $first_ipv6_if = "$if_name" unless defined($first_ipv6_if); 

            if ($j == 0) {
                print IF_FILE "IPV6_AUTOCONF=no\n";
                print IF_FILE "IPV6ADDR=$ip\n";
            } else {
                $ipv6secs .= " $ip" if $ipv6secs ne '';
                $ipv6secs .= "$ip" if $ipv6secs eq '';
            }
        }
        if (defined($ipv6secs)) {
            print IF_FILE "IPV6ADDR_SECONDARIES=\"$ipv6secs\"\n";
        }
        close IF_FILE;
    }
    close RULES;

    # Network routes configuration: <route> tags
    if (defined($first_ipv4_if)) {
        my $route4_file = "$sysconfnet_dir/route-Auto_$first_ipv4_if";
        system "echo \"\" > $route4_file";
        open ROUTE_FILE, ">" . $route4_file or return "error opening $route4_file";
    }
    if (defined($first_ipv6_if)) {
        my $route6_file = "$sysconfnet_dir/route6-Auto_$first_ipv6_if";
        system "echo \"\" > $route6_file";
        open ROUTE6_FILE, ">" . $route6_file or return "error opening $route6_file";
    }
            
    my @route_list = $vm->getElementsByTagName("route");
    for (my $j = 0 ; $j < @route_list ; $j++){
        my $route_tag  = $route_list[$j];
        my $route_type = $route_tag->getAttribute("type");
        my $route_gw   = $route_tag->getAttribute("gw");
        my $route      = $route_tag->getFirstChild->getData;
        if ( $route_type eq 'ipv4' && defined($first_ipv4_if) ) {
            if ($route eq 'default') {
                #print ROUTE_FILE "ADDRESS$j=0.0.0.0\n";
                #print ROUTE_FILE "NETMASK$j=0\n";
                #print ROUTE_FILE "GATEWAY$j=$route_gw\n";
                # Define the default route in $sysconfnet_file
                system "echo GATEWAY=$route_gw >> $sysconfnet_file"; 
            } else {
                my $mask = $route;
                $mask =~ s/.*\///;
                $mask = cidr_to_mask ($mask);
                $route =~ s/\/.*//;
                print ROUTE_FILE "ADDRESS$j=$route\n";
                print ROUTE_FILE "NETMASK$j=$mask\n";
                print ROUTE_FILE "GATEWAY$j=$route_gw\n";
            }
        } elsif ($route_type eq 'ipv6' && defined($first_ipv6_if) ) {
            if ($route eq 'default') {
                print ROUTE6_FILE "2000::/3 via $route_gw metric 0\n";
            } else {
                print ROUTE6_FILE "$route via $route_gw metric 0\n";
            }
        }
    }
    close ROUTE_FILE  if defined($first_ipv4_if);
    close ROUTE6_FILE if defined($first_ipv6_if);
        
    # Packet forwarding: <forwarding> tag
    my $ipv4_forwarding = 0;
    my $ipv6_forwarding = 0;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    for (my $j = 0 ; $j < @forwarding_list ; $j++){
        my $forwarding = $forwarding_list[$j];
        my $forwarding_type = $forwarding->getAttribute("type");
        if ($forwarding_type eq "ip"){
            $ipv4_forwarding = 1;
            $ipv6_forwarding = 1;
        } elsif ($forwarding_type eq "ipv4"){
            $ipv4_forwarding = 1;
        } elsif ($forwarding_type eq "ipv6"){
            $ipv6_forwarding = 1;
        }
    }
    wlog (VVV, "   configuring ipv4 ($ipv4_forwarding) and ipv6 ($ipv6_forwarding) forwarding in $sysctl_file...", $logp);
    system "echo >> $sysctl_file ";
    system "echo '# Configured by VNX' >> $sysctl_file ";
    system "echo 'net.ipv4.ip_forward=$ipv4_forwarding' >> $sysctl_file ";
    system "echo 'net.ipv6.conf.all.forwarding=$ipv6_forwarding' >> $sysctl_file ";

    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file", $logp);
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '1i127.0.0.1  localhost.localdomain   localhost' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change /etc/hostname
    system "echo $vm_name > $hostname_file";

    #system "hostname $vm_name";
    system "mv $sysconfnet_file ${sysconfnet_file}.bak";
    system "cat ${sysconfnet_file}.bak | grep -v HOSTNAME > $sysconfnet_file";
    system "echo HOSTNAME=$vm_name >> $sysconfnet_file";

    return $error;    
}

#
# autoconfigure for FreeBSD             
#
sub autoconfigure_freebsd {

    my $dom = shift;         # DOM object of VM XML specification
    my $rootfs_mdir = shift; # Directory where the rootfs image is mounted
    my $error;

    my $logp = "autoconfigure_freebsd> ";

    # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
    # host files will be modified instead of rootfs image ones
    unless ( defined($rootfs_mdir) && $rootfs_mdir ne '' ) {
        die;
    }    

    my $vm = $dom->findnodes("/create_conf/vm")->[0];
    my $vm_name = $vm->getAttribute("name");

    wlog (VVV, "vm_name=$vm_name, rootfs_mdir=$rootfs_mdir", $logp);

    # IF prefix names assigned to interfaces  
    my $IF_MGMT_PREFIX="re";    # type rtl8139 for management if    
    my $IF_PREFIX="em";         # type e1000 for the rest of ifs   
    
    # Files to modify
    my $hosts_file      = "$rootfs_mdir" . "/etc/hosts";
    my $hostname_file   = "$rootfs_mdir" . "/etc/hostname";
    my $rc_file         = "$rootfs_mdir" . "/etc/rc.conf";

    # before the loop, backup /etc/rc.conf
    wlog (VVV, "   configuring /etc/rc.conf...", $logp);
    system "cp $rc_file $rc_file.backup";

    open RC, ">>" . $rc_file or return "error opening $rc_file";

    chomp (my $now = `date`);

    print RC "\n";
    print RC "#\n";
    print RC "# VNX Autoconfiguration commands ($now)\n";
    print RC "#\n";
    print RC "\n";

    print RC "hostname=\"$vm_name\"\n";
    print RC "sendmail_enable=\"NONE\"\n"; #avoids some startup errors

    # Network interfaces configuration: <if> tags
    my @if_list = $vm->getElementsByTagName("if");
    my $k = 0; # Index to the next $IF_PREFIX interface to be used
    for (my $i = 0 ; $i < @if_list; $i++){
        my $if = $if_list[$i];
        my $id    = $if->getAttribute("id");
        my $net   = $if->getAttribute("net");
        my $mac   = $if->getAttribute("mac");
        $mac =~ s/,//g; 
        
        # IF names
        my $if_orig_name;
        my $if_new_name;
        if ($id eq 0) { # Management interface 
            $if_orig_name = $IF_MGMT_PREFIX . "0";    
            $if_new_name = "eth0";
        } else { 
            my $if_num = $k;
            $k++;
            $if_orig_name = $IF_PREFIX . $if_num;    
            $if_new_name = "eth" . $id;
        }

        print RC "ifconfig_" . $if_orig_name . "_name=\"" . $if_new_name . "\"\n";
    
        my $alias_num=-1;
                
        # IPv4 addresses
        my @ipv4_tag_list = $if->getElementsByTagName("ipv4");
        for ( my $j = 0 ; $j < @ipv4_tag_list ; $j++ ) {

            my $ipv4 = $ipv4_tag_list[$j];
            my $mask = $ipv4->getAttribute("mask");
            my $ip   = $ipv4->getFirstChild->getData;

            if ($alias_num == -1) {
                print RC "ifconfig_" . $if_new_name . "=\"inet " . $ip . " netmask " . $mask . "\"\n";
            } else {
                print RC "ifconfig_" . $if_new_name . "_alias" . $alias_num . "=\"inet " . $ip . " netmask " . $mask . "\"\n";
            }
            $alias_num++;
        }

        # IPv6 addresses
        my @ipv6_tag_list = $if->getElementsByTagName("ipv6");
        for ( my $j = 0 ; $j < @ipv6_tag_list ; $j++ ) {

            my $ipv6 = $ipv6_tag_list[$j];
            my $ip   = $ipv6->getFirstChild->getData;
            my $mask = $ip;
            $mask =~ s/.*\///;
            $ip =~ s/\/.*//;

            if ($alias_num == -1) {
                print RC "ifconfig_" . $if_new_name . "=\"inet6 " . $ip . " prefixlen " . $mask . "\"\n";
            } else {
                print RC "ifconfig_" . $if_new_name . "_alias" . $alias_num . "=\"inet6 " . $ip . " prefixlen " . $mask . "\"\n";
            }
            $alias_num++;
        }
    }
        
    # Network routes configuration: <route> tags
    # Example content:
    #     static_routes="r1 r2"
    #     ipv6_static_routes="r3 r4"
    #     default_router="10.0.1.2"
    #     route_r1="-net 10.1.1.0/24 10.0.0.3"
    #     route_r2="-net 10.1.2.0/24 10.0.0.3"
    #     ipv6_default_router="2001:db8:1::1"
    #     ipv6_route_r3="2001:db8:7::/3 2001:db8::2"
    #     ipv6_route_r4="2001:db8:8::/64 2001:db8::2"
    my @route_list = $vm->getElementsByTagName("route");
    my @routeCfg;           # Stores the route_* lines 
    my $static_routes;      # Stores the names of the ipv4 routes
    my $ipv6_static_routes; # Stores the names of the ipv6 routes
    my $i = 1;
    for (my $j = 0 ; $j < @route_list; $j++){
        my $route_tag = $route_list[$j];
        if (defined($route_tag)){
            my $route_type = $route_tag->getAttribute("type");
            my $route_gw   = $route_tag->getAttribute("gw");
            my $route      = $route_tag->getFirstChild->getData;

            if ($route_type eq 'ipv4') {
                if ($route eq 'default'){
                    push (@routeCfg, "default_router=\"$route_gw\"\n");
                } else {
                    push (@routeCfg, "route_r$i=\"-net $route $route_gw\"\n");
                    $static_routes = ($static_routes eq '') ? "r$i" : "$static_routes r$i";
                    $i++;
                }
            } elsif ($route_type eq 'ipv6') {
                if ($route eq 'default'){
                    push (@routeCfg, "ipv6_default_router=\"$route_gw\"\n");
                } else {
                    push (@routeCfg, "ipv6_route_r$i=\"$route $route_gw\"\n");
                    $ipv6_static_routes = ($ipv6_static_routes eq '') ? "r$i" : "$ipv6_static_routes r$i";
                    $i++;                   
                }
            }
        }
    }
    unshift (@routeCfg, "ipv6_static_routes=\"$ipv6_static_routes\"\n");
    unshift (@routeCfg, "static_routes=\"$static_routes\"\n");
    print RC @routeCfg;

    # Packet forwarding: <forwarding> tag
    my $ipv4_forwarding = 0;
    my $ipv6_forwarding = 0;
    my @forwarding_list = $vm->getElementsByTagName("forwarding");
    for (my $j = 0 ; $j < @forwarding_list ; $j++){
        my $forwarding   = $forwarding_list[$j];
        my $forwarding_type = $forwarding->getAttribute("type");
        if ($forwarding_type eq "ip"){
            $ipv4_forwarding = 1;
            $ipv6_forwarding = 1;
        } elsif ($forwarding_type eq "ipv4"){
            $ipv4_forwarding = 1;
        } elsif ($forwarding_type eq "ipv6"){
            $ipv6_forwarding = 1;
        }
    }
    if ($ipv4_forwarding == 1) {
        wlog (VVV, "   configuring ipv4 forwarding...", $logp);
        print RC "gateway_enable=\"YES\"\n";
    }
    if ($ipv6_forwarding == 1) {
        wlog (VVV, "   configuring ipv6 forwarding...", $logp);
        print RC "ipv6_gateway_enable=\"YES\"\n";
    }

    close RC;
       
    # Configuring /etc/hosts and /etc/hostname
    wlog (VVV, "   configuring $hosts_file and $hostname_file", $logp);
    system "cp $hosts_file $hosts_file.backup";
    # Delete loopback entries (127.0.0.1 and 127.0.1.1)
    system "sed -i -e '/127.0.0.1/d' -e '/127.0.1.1/d' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '1i127.0.0.1  localhost.localdomain   localhost' $hosts_file";
    # Insert the new 127.0.0.1 line
    system "sed -i -e '2i\ 127.0.1.1  $vm_name' $hosts_file";
    # Change /etc/hostname
    system "echo $vm_name > $hostname_file";

    return $error;            
}

#
# get_os_distro
#
# Detects which OS, release, distribution name, etc 
# This is an improved adaptation to perl of the following script: 
#   http://www.unix.com/unix-advanced-expert-users/21468-machine.html?t=21468#post83185
#
# Output examples:
#     Linux,Ubuntu,10.04,lucid,2.6.32-28-generic,x86_64
#     Linux,Fedora,14,Laughlin,2.6.35.11-83.fc14.i386,i386
#     FreeBSD,FreeBSD,8.1,,,i386
#
sub get_os_distro {

    my $OS=`uname -s`; chomp ($OS);
    my $REV=`uname -r`; chomp ($REV);
    my $MACH=`uname -m`; chomp ($MACH);
    my $ARCH;
    my $OSSTR;
    my $DIST;
    my $KERNEL;
    my $PSEUDONAME;
        
    if ( $OS eq 'SunOS' ) {
            $OS='Solaris';
            $ARCH=`uname -p`;
            $OSSTR= "$OS,$REV,$ARCH," . `uname -v`;
    } elsif ( $OS eq "AIX" ) {
            $OSSTR= "$OS," . `oslevel` . "," . `oslevel -r`;
    } elsif ( $OS eq "Linux" ) {
            $KERNEL=`uname -r`;
            if ( -e '/etc/redhat-release' ) {
            my $relfile = `cat /etc/redhat-release`;
            my @fields  = split(/ /, $relfile);
                    $DIST = $fields[0];
                    $REV = $fields[2];
                    $PSEUDONAME = $fields[3];
                    $PSEUDONAME =~ s/\(//; $PSEUDONAME =~ s/\)//;
        } elsif ( -e '/etc/SuSE-release' ) {
                    $DIST=`cat /etc/SuSE-release | tr "\n" ' '| sed s/VERSION.*//`;
                    $REV=`cat /etc/SuSE-release | tr "\n" ' ' | sed s/.*=\ //`;
            } elsif ( -e '/etc/mandrake-release' ) {
                    $DIST='Mandrake';
                    $PSEUDONAME=`cat /etc/mandrake-release | sed s/.*\(// | sed s/\)//`;
                    $REV=`cat /etc/mandrake-release | sed s/.*release\ // | sed s/\ .*//`;
            } elsif ( -e '/etc/lsb-release' ) {
                    $DIST= `cat /etc/lsb-release | grep DISTRIB_ID | sed 's/DISTRIB_ID=//'`; 
                    $REV = `cat /etc/lsb-release | grep DISTRIB_RELEASE | sed 's/DISTRIB_RELEASE=//'`;
                    $PSEUDONAME = `cat /etc/lsb-release | grep DISTRIB_CODENAME | sed 's/DISTRIB_CODENAME=//'`;
            } elsif ( -e '/etc/debian_version' ) {
                    $DIST= "Debian"; 
                    $REV=`cat /etc/debian_version`;
                    $PSEUDONAME = `LANG=C lsb_release -a 2> /dev/null | grep Codename | sed 's/Codename:\\s*//'`;                    
        }
            if ( -e '/etc/UnitedLinux-release' ) {
                    $DIST=$DIST . " [" . `cat /etc/UnitedLinux-release | tr "\n" ' ' | sed s/VERSION.*//` . "]";
            }
        chomp ($KERNEL); chomp ($DIST); chomp ($PSEUDONAME); chomp ($REV);
            $OSSTR="$OS,$DIST,$REV,$PSEUDONAME,$KERNEL,$MACH";
    } elsif ( $OS eq "FreeBSD" ) {
            $DIST= "FreeBSD";
        $REV =~ s/-RELEASE//;
            $OSSTR="$OS,$DIST,$REV,$PSEUDONAME,$KERNEL,$MACH";
    }
return $OSSTR;
}

#
# Converts a CIDR prefix length to a dot notation mask
#
sub cidr_to_mask {

  my $len=shift;
  my $dec32=2 ** 32;
  # decimal equivalent
  my $dec=$dec32 - ( 2 ** (32-$len));
  # netmask in dotted decimal
  my $mask= join '.', unpack 'C4', pack 'N', $dec;
  return $mask;
}

#
# Reads a value from a configuration file made of "param=value" lines
# 
# Returns '' if the parameter is not found or when problems reading the file
sub get_conf_value {

    my $cfg_file = shift;
    my $param = shift;

    open FILE, "< $cfg_file" or return '';
    my @lines = <FILE>;
    foreach my $line (@lines){
        if (($line =~ /$param/) && !($line =~ /^#/)){
            my @config = split(/=/, $line);
            my $result = $config[1];
            chomp ($result);
            $result =~ s/\s+//g;
            close FILE;
            return $result;
        }
    }
}

#
# Changes a value from a configuration file made of "param=value" lines
# 
# Returns '' if OK, 'ERROR' if there are problems reading or writing the files
sub set_conf_value {

    my $cfg_file = shift;
    my $param = shift;
    my $new_value = shift;
    my $param_found;

    my $tout = 10;
    {   # Loop till the file system is ready for writing...
        # It seems that at startup the filesystem is initially mounted read-only, so 
        # the second open (OFILE) can fail
        eval {
            $tout--;
            open IFILE, "< $cfg_file"     or die "IFILE $!";
            open OFILE, "> $cfg_file.new" or die "OFILE $!";
        };
        last unless $@;
        if ($@) {
            write_console "$@\n";
            if ($tout) {
                write_console ("Waiting for file $cfg_file to be ready...");
                sleep 5;
                redo;
            } else {
                return '';
            }
        }
    }

    while (my $line = <IFILE>) {
        if ($line =~ /^$param/) {
            $line =~ s/^$param=.*/$param=$new_value/g;
            $param_found = 'true';
        }
        print OFILE $line or return ''; 
    }
    unless ($param_found) {
    #print "not found \n";
        #print "$param=$new_value\n";        
    print OFILE "$param=$new_value\n" or return '';
    }
    close IFILE;
    close OFILE;

    system ("mv $cfg_file.new $cfg_file");
    #my $cmd = "cat " . VNXACED_STATUS; my $status=`$cmd`; 
    #write_console ('-------------------------'); write_console ($status); write_console ('-------------------------');
    return 'OK';
}

sub vnxaced_die {
    my $err_msg = shift;

    wlog (V, $err_msg); 
    die "$err_msg\n";

}

1;
