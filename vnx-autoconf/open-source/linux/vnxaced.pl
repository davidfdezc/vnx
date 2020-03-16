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
use constant VNXACED_STATUS_DIR => '/root/.vnx';
use constant VNXACED_STATUS => VNXACED_STATUS_DIR . '/vnxaced.status';
use constant VNXACED_STATUS_TEST_FILE => VNXACED_STATUS_DIR . '/testfs';

use constant FREEBSD_CD_DIR => '/cdrom';
use constant OPENBSD_CD_DIR => '/cdrom';
use constant LINUX_CD_DIR   => '/media/cdrom';

use constant INIT_DELAY   => '10';

# Channel used to send messages from host to virtuqal machine
# Values:
#    - SERIAL: serial line
#    - SHARED_FILE: shared file
use constant H2VM_CHANNEL => 'SERIAL';

use constant LINUX_TTY   => '/dev/ttyS1';
use constant FREEBSD_TTY => '/dev/cuau1';
use constant OPENBSD_TTY => '/dev/tty01';

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

$platform[0] = lc $platform[0];  # Convert to lowercase
$platform[1] = lc $platform[1];  
  
if ($platform[0] eq 'linux'){
    
    $vm_tty = LINUX_TTY;
    if ($platform[1] eq 'ubuntu')    { 
        if ($platform[2] eq '12.04') {
            $mount_cdrom_cmd = 'mount /dev/sr0 /media/cdrom';
            $umount_cdrom_cmd = 'eject /media/cdrom; umount /media/cdrom';                  
        } else {
            $mount_cdrom_cmd  = 'mount /media/cdrom';
            $umount_cdrom_cmd = 'umount /media/cdrom';
        }
    }           
    elsif ($platform[1] eq 'fedora') { 
        $mount_cdrom_cmd = 'udisks --mount /dev/sr0';
        $umount_cdrom_cmd = 'udisks --unmount /dev/sr0';            
    }
    elsif ($platform[1] eq 'centos') { 
        $mount_cdrom_cmd = 'mount /dev/cdrom /media/cdrom';
        $umount_cdrom_cmd = 'eject; umount /media/cdrom';           
    }

    if ($platform[1] eq 'centos' && $platform[2]=~ /^5/ ) {
        $mount_sdisk_cmd  = 'mount /dev/hdb /mnt/sdisk';    	
    } else {
        #$mount_sdisk_cmd  = 'mount /dev/sdb /mnt/sdisk';
        if (-b '/dev/vdb') {
            $mount_sdisk_cmd  = "mount /dev/vdb /mnt/sdisk"
        } elsif (-b '/dev/sdb') {
            $mount_sdisk_cmd  = "mount /dev/sdb /mnt/sdisk"
        } elsif (-b '/dev/hdb') {
            $mount_sdisk_cmd  = "mount /dev/hdb /mnt/sdisk"
        } else {
            wlog (V, "ERROR: linux configuration disk not found (vdb, sdb and hdb not available). Aborting");
            exit (1);
        }
        #$mount_sdisk_cmd  = 'if [ -b /dev/vdb ]; then mount /dev/vdb /mnt/sdisk; elif [ -b /dev/sdb ]; then mount /dev/sdb /mnt/sdisk; elif [ -b /dev/hdb ]; then mount /dev/hdb /mnt/sdisk; fi';
    }

    $umount_sdisk_cmd = 'umount /mnt/sdisk';
    system "mkdir -p /mnt/sdisk";
    $console_ttys = "/dev/ttyS0 /dev/tty1";
    
} elsif ($platform[0] eq 'freebsd'){
    
    $vm_tty = FREEBSD_TTY;
    $mount_cdrom_cmd = 'mount /cdrom';
    $umount_cdrom_cmd = 'umount -f /cdrom';
    #$mount_sdisk_cmd  = 'mount -t msdosfs /dev/ad1 /mnt/sdisk';
    system "fdisk ada1 > /dev/null 2>&1";
    if ($? == 0) {
        $mount_sdisk_cmd = "mount -t msdosfs /dev/ada1 /mnt/sdisk";
    } else {
        system "fdisk vtbd1 > /dev/null 2>&1";
        if ($? == 0) {
            $mount_sdisk_cmd = "mount -t msdosfs /dev/vtbd1 /mnt/sdisk"
        } else {
            wlog (V, "ERROR: openbsd configuration disk not found (ada1 and vtbd1 not available). Aborting");
            exit (1);
        }
    }
    $umount_sdisk_cmd = 'umount /mnt/sdisk';
    system "mkdir -p /mnt/sdisk";
    $console_ttys = "/dev/ttyv0";
    
} elsif ($platform[0] eq 'openbsd'){
    
    $vm_tty = OPENBSD_TTY;
    $mount_cdrom_cmd = 'mount /cdrom';
    $umount_cdrom_cmd = 'umount -f /cdrom';
    #$mount_sdisk_cmd  = 'mount_msdos /dev/wd1i /mnt/sdisk';
    system "fdisk wd1 > /dev/null 2>&1";
    if ($? == 0) {
        $mount_sdisk_cmd = "mount_msdos /dev/wd1i /mnt/sdisk";
    } else {
        system "fdisk sd1 > /dev/null 2>&1";
        if ($? == 0) {
            $mount_sdisk_cmd = "mount_msdos /dev/sd1c /mnt/sdisk"
        } else {
            wlog (V, "ERROR: openbsd configuration disk not found (wd1 and sd1 not available). Aborting");
            exit (1);
        }
    }
    $umount_sdisk_cmd = 'umount /mnt/sdisk';
    system "mkdir -p /mnt/sdisk";
    $console_ttys = "/dev/tty00";
    
} else {
    wlog (V, "ERROR: unknown platform ($platform[0]). Only Linux, FreeBSD and OpenBSD supported.");
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
    # Commented on 19/12/2015 due to problems in Openstack Liberty scenario 
    #close(STDERR);
    #close(STDOUT);
    #close(STDIN);

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
 
        wlog (V, "Checking whether the filesystem is ready for writing");
        if (my $res = wait_till_filesystem_ready_for_writing()) {
            wlog (V, $res);
        	exit(1);
        }
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
    if ($platform[0] eq 'linux'){
        $cd_dir = LINUX_CD_DIR;
    } elsif ($platform[0] eq 'freebsd'){
        $cd_dir = FREEBSD_CD_DIR;
    } elsif ($platform[0] eq 'openbsd'){
        $cd_dir = OPENBSD_CD_DIR;
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
    if ($platform[0] eq 'linux'){
        wlog (V, "     updating vnxaced for Linux...");

        if (-e "$files_dir/install_vnxaced") {
            system "perl $files_dir/uninstall_vnxaced -n";
            $res = system "perl $files_dir/install_vnxaced";
        } elsif (-e "$files_dir/vnxaced-lf/install_vnxaced") {
            system "perl $files_dir/vnxaced-lf/uninstall_vnxaced -n";
            $res = system "perl $files_dir/vnxaced-lf/install_vnxaced";
        }
        
        #if ( ($platform[1] eq 'ubuntu') or   
        #    ($platform[1] eq 'fedora') ) { 
        #   # Use VNXACED based on upstart
        #   system "cp /media/cdrom/vnxaced.pl /usr/local/bin/vnxaced";
        #   system "cp /media/cdrom/linux/upstart/vnxace.conf /etc/init/";
        #} elsif ($platform[1] eq 'centos') { 
        #   # Use VNXACED based on init.d
        #   system "cp -v vnxaced.pl /usr/local/bin/vnxaced";
        #   system "cp -v unix/init.d/vnxace /etc/init.d/";
        #}
    }
    #############################
    # update for FreeBSD        #
    #############################
    elsif ($platform[0] eq 'freebsd'){
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
    } elsif ($platform[0] eq 'openbsd'){
        wlog (V, "     updating vnxdaemon for OpenBSD...");

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
    #if ($platform[0] eq 'linux'){
    #    if ( ($platform[1] eq 'ubuntu') or ($platform[1] eq 'fedora') ) { 
    #        system "service vnxace stop";
    #    } elsif ($platform[1] eq 'centos') { 
    #        system "/etc/init.d/vnxace stop";
    #    }
    #} elsif ($platform[0] eq 'freebsd'){
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
            # vnxace has been started as a daemon with input/output closed
            # We have to use this way to execute the command to avoid 
            # problems. Other ways tested (using exec or system with all kind of 
            # input/output redirections made some commands fail (for example, when 
            # starting apache: the server starts but does not answer requests and 
            # shows an error in logs related to sockets). 
            #exe_cmd_aux ("$cmd");
            
            my $cmd_file = `mktemp /root/.vnx/cmd-XXXXXX`;
            open CMDFILE, ">$cmd_file";
            my @lines = split(/\n/, $cmd);
            foreach my $line (@lines) {
                # Delete ; at the end
                $line =~ s/;$//;
                print CMDFILE $line . "\n";
            }
            close CMDFILE;
            my $res=`bash $cmd_file < /dev/null 2>&1`;
            wlog (V, $res);
            #system ("rm -f $cmd_file");
            #exe_cmd_aux ("$cmd");
            
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
                    if ($platform[0] eq 'linux'){
                        wlog (V, "exec \"setsid sh -c \\\"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] \'$cmd\'\\\"\" < /dev/null > /dev/null 2>&1");
                        exec "setsid sh -c \"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] '$cmd'\" > /dev/null 2>&1 < /dev/null";
                    } elsif ($platform[0] eq 'freebsd'){
                        wlog (V, "system \"detach sh -c \\\"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] \'$cmd\'\\\"\" < /dev/null > /dev/null 2>&1");
                        system "detach sh -c \"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] '$cmd'\" > /dev/null 2>&1 < /dev/null";
                        exit (0);
                    } elsif ($platform[0] eq 'openbsd'){
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
    if ($platform[0] eq 'linux'){
        # Send a message to consoles
        #system "shutdown -k now 'VNX system autoconfiguration in progress...wait until the system reboots...'";

        write_console ("$warn_msg\n");
        my $cmd = "cat " . VNXACED_STATUS; my $status=`$cmd`; 
        wlog (V, "-------------------------\r\nvnxaced.status file:\r\n");
        wlog (V, "$status\r\n"); 
        wlog (V, "-------------------------\r\n"); 

        if    ($platform[1] eq 'ubuntu')   
            { autoconfigure_debian_ubuntu ($dom, '/', 'ubuntu-'. $platform[2], 'yes') }           
        elsif ($platform[1] eq 'debian' || $platform[1] eq 'kali')   
            { autoconfigure_debian_ubuntu ($dom, '/', 'debian', 'yes') }           
        elsif ($platform[1] eq 'fedora')   
            { autoconfigure_redhat ($dom, '/', 'fedora', 'yes') }
        elsif ($platform[1] eq 'centos')   
            { autoconfigure_redhat ($dom, '/', 'centos', 'yes') }
        elsif ($platform[1] eq 'debian-vyos')   
            { autoconfigure_vyos ($dom, '/', 'vyos', 'yes') }

    }
    # autoconfigure for FreeBSD
    elsif ($platform[0] eq 'freebsd') {
        #wlog (V, "calling autoconfigure_freebsd");
        write_console ("$warn_msg\n");
        autoconfigure_freebsd ($dom, '/', 'yes')
    } elsif ($platform[0] eq 'openbsd') {
        #wlog (V, "calling autoconfigure_openbsd");
        write_console ("$warn_msg\n");
        autoconfigure_openbsd ($dom, '/', 'yes')
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

            #$cmd="cp -vR ${source_path}* $root";
	    	if ($platform[0] eq 'openbsd') {
				$cmd="cp -R ${source_path}* $root";
	    	} else {
				$cmd="cp -vR ${source_path}* $root";
	    	}
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
            #$cmd="cp -v ${source_path}* $root";
	    	if ($platform[0] eq 'openbsd') {
				$cmd="cp ${source_path}* $root";
	    	} else {
				$cmd="cp -v ${source_path}* $root";
	    	}
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
			
			if ( -e '/opt/vyatta/etc/version' ) {
				$DIST= "Debian-VyOS"; 
				$REV=`cat /opt/vyatta/etc/version | grep Version | awk '{print \$3}'`;
				$PSEUDONAME = `LANG=C lsb_release -a 2> /dev/null | grep Codename | sed 's/Codename:\\s*//'`;
			} else {
				$DIST= "Debian"; 
				$REV=`cat /etc/debian_version`;
				$PSEUDONAME = `LANG=C lsb_release -a 2> /dev/null | grep Codename | sed 's/Codename:\\s*//'`;
			}
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
    } elsif ( $OS eq "OpenBSD" ) {
            $DIST= "OpenBSD";
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

sub wait_till_filesystem_ready_for_writing {
	
	my $test_file = VNXACED_STATUS_TEST_FILE;
    my $tout = 10;
    my $res;
    {   # Loop till the file system is ready for writing...
        eval {
            $tout--;
            open OFILE, "> ${test_file}" or die "OFILE $!";
        };
        last unless $@;
        if ($@) {
            write_console "$@\n";
            if ($tout) {
                write_console ("Waiting for file $test_file to be ready...");
                sleep 3;
                redo;
            } else {
                $res = 'ERROR: cannot write to filesystem';
                return;
            }
        }
    }
    close OFILE;
    return $res;
}

sub str {
  my $var = shift;
  if ( !defined($var) ) { return '' } else { return $var }
}

#
# Autoconfiguration functions (added at install time by build_vnx_tar script)
#