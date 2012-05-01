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
# Copyright (C) 2011, 	DIT-UPM
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
#

use strict;
use POSIX;
use Sys::Syslog;
use XML::DOM;
use IO::Handle;
use File::Basename;

my $VNXACED_VER='MM.mm.rrrr';
my $VNXACED_BUILT='DD/MM/YYYY';

use constant LINUX_TTY   => '/dev/ttyS1';
use constant FREEBSD_TTY => '/dev/cuau1';

use constant VNXACED_PID => '/var/run/vnxaced.pid';
use constant VNXACED_LOG => '/var/log/vnxaced.log';
use constant VNXACED_CID => '/root/.vnx/vnxaced.cid';

use constant FREEBSD_CD_DIR => '/cdrom';
use constant LINUX_CD_DIR   => '/media/cdrom';

use constant INIT_DELAY   => '10';

my @platform;
my $mount_cdrom_cmd;
my $umount_cdrom_cmd; 
my $mount_sdisk_cmd;
my $umount_sdisk_cmd; 

my $DEBUG;
my $VERBOSE;

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
                exit (1);
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

if ($DEBUG) { print "DEBUG mode\n"; }
if ($VERBOSE) { print "VERBOSE mode\n"; }

my $os_distro = get_os_distro();
@platform = split(/,/, $os_distro);
	
if ($platform[0] eq 'Linux'){
	
    $vm_tty = LINUX_TTY;
	if ($platform[1] eq 'Ubuntu')    { 
		$mount_cdrom_cmd  = 'mount /media/cdrom';
        if ($platform[2] eq '12.04') {
            $umount_cdrom_cmd = 'eject; umount /media/cdrom';
        } else {
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

} elsif ($platform[0] eq 'FreeBSD'){

    $vm_tty = FREEBSD_TTY;
	$mount_cdrom_cmd = 'mount /cdrom';
	$umount_cdrom_cmd = 'umount -f /cdrom';

} else {
	write_log ("ERROR: unknown platform ($platform[0]). Only Linux and FreeBSD supported.");
	exit (1);
}

# delete file log content without deleting the file
#if (open(LOG, ">>" . VNXACED_LOG)) {
#	truncate LOG,0;
# 	close LOG;
#}
chomp (my $now = `date`);
write_log ("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
write_log ("~~ vnxaced version $VNXACED_VER (built on $VNXACED_BUILT)");
write_log ("~~   started at $now");
write_log ("~~   OS: $os_distro");
write_log ("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

#if (-f VNXACED_PID){
#	my $cmd="cat " . VNXACED_PID;
#	my $pid=`$cmd`; chomp ($pid);
#	write_log ("Another instance of vnxaced (PID $pid) seems to be running, killing it... ");
#	system "kill -9 $pid"; 
#	system "rm -f " . VNXACED_PID; 
#}
open my $pids, "ps uax | grep 'perl /usr/local/bin/vnxaced' | grep -v grep | grep -v 'sh -e -c exec' | awk '{print \$2}' |";
while (<$pids>) {
        my $pid=$_; chomp($pid);
	if ($pid ne $$) {
		write_log ("Another instance of vnxaced (PID $pid) seems to be running, killing it... ");
        	system "kill $pid";
        }
}

# store process pid
system "echo $$ > " . VNXACED_PID;

write_log ("~~ Waiting initial delay of " . INIT_DELAY . " seconds...");
sleep INIT_DELAY;

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
	write_log ("INT signal received. Exiting.");
	exit (0);
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub write_log {

    my $msg = shift;

	if ($DEBUG) { 
   		print "$msg\n"; 
	} else {
        	if (open(LOG, ">>" . VNXACED_LOG)) {
			(*LOG)->autoflush(1);
               	 	print LOG ("$msg\n");
                	close LOG;
        	}
	}
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

	if ($VERBOSE) {
		my $res=`$cmd`;
		write_log ("exe_mount_cmd: $cmd (res=$res)") if ($VERBOSE);
	} else {
		$cmd="$cmd >/dev/null 2>&1";
		system "$cmd";
	}
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub daemonize {
		
	write_log ("~~ Daemonizing process... ");

	# Fork
#	my $pid = fork;
#	exit if $pid;
#	die "Couldn't fork: $!" unless defined($pid);

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


#~~~~~~~~~~~~~~ listen for events ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub listen {

	write_log ("~~ Waiting for commands...");
	system "mkdir -p /root/.vnx";
	my @files;
	my $cd_dir;
	my $files_dir;
	if ($platform[0] eq 'Linux'){
		$cd_dir = LINUX_CD_DIR;
	} elsif ($platform[0] eq 'FreeBSD'){
		$cd_dir = FREEBSD_CD_DIR;
	}
    #my $lscmd = "ls -l $cd_dir";
	my $commands_file;
	
	# JSF: comentado porque al rearrancar el servicio a mano pinta error por pantalla si
	# no esta montado el CD-ROM. Si no da errores de otro tipo se podra quitar del todo.
	#system "umount -f /cdrom";

	#sleep 5;
	#exe_mount_cmd ($mount_cdrom_cmd);

    # Open the TTY for reading commands
    open (VMTTY, "< $vm_tty") or vnxaced_die ("Couldn't open $vm_tty for reading");

    while ( chomp( my $line = <VMTTY> ) ) {

        write_log ("Command received: $line");
		
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
			        my $res=`ls -l $files_dir`; write_log ("\n~~ $cmd[1] content: ~~\n$res~~~~~~~~~~~~~~~~~~~~\n")
			    }

		        my @files = <$files_dir/*>;
		
		        foreach my $file (@files){
		            
		            my $fname = basename ($file);
		            if ($fname eq "command.xml"){
		                unless (&is_new_file($file)){
		                    next;               
		                }
		                if ($VERBOSE) { my $f=`cat $file`; write_log "\n~~ $fname ~~\n$f~~~~~~~~~~~~~~~~~~~~\n"; }
		                chomp (my $now = `date`);                       
		                write_log ("~~ $now:");
		                write_log ("     command received in $file");
		                &execute_filetree($file);
		                &execute_commands($file);
		                write_log ("     sending 'done' signal to host...\n");
		                system "echo OK > $vm_tty";
		            
		            }elsif ( ($fname eq "vnxboot") || ($fname eq "vnxboot.xml") ) {
		                unless (&is_new_file($file)){
		                    
		                    # Autoconfiguration is done and the system has restarted 
		                    # Check whether the <exec> commands with seq="on_boot" have been executed
		                    my $on_boot_cmd_exec = get_conf_value (VNXACED_CID, 'on_boot_cmds_executed');
		                    unless ($on_boot_cmd_exec eq 'yes') {
		                        write_log ("executing <filetree> and <exec> commands after restart");
		                        # Execute all <filetree> and <exec> commands in vnxboot file            
		                        # Execute <filetree> commands
		                        &execute_filetree($file);
		                        # Execute <exec> commands 
		                        &execute_commands($file);
		                        # Commands executed, change config
		                        set_conf_value (VNXACED_CID, 'on_boot_cmds_executed', 'yes')
		                    }
		                    next;               
		                }
		                if ($VERBOSE) { my $f=`cat $file`; write_log "\n~~ $fname ~~\n$f~~~~~~~~~~~~~~~~~~~~\n"; }
		                chomp (my $now = `date`);                       
		                write_log ("~~ $now:");
		                write_log ("     configuration file received in $file");
		                &autoconfigure($file);
		
		            }elsif ($fname eq "vnx_update.xml"){
		                unless (&is_new_file($file) eq '1'){
		                    next;               
		                }
		                if ($VERBOSE) { my $f=`cat $file`; write_log "\n~~ $fname ~~\n$f~~~~~~~~~~~~~~~~~~~~\n"; }
		                chomp (my $now = `date`);                       
		                write_log ("~~ $now:");
		                write_log ("     update files received in $file");
		                &autoupdate;
		
		            }else {
		                # unknown file, do nothing
		            }
		        }
		        
                if ( $cmd[1] eq "cdrom" ) {
                    exe_mount_cmd ($umount_cdrom_cmd);
                } else { # sdisk 
                    exe_mount_cmd ($umount_sdisk_cmd);
                }
            	
            } elsif ($cmd[0] eq "nop") { # do nothing
                write_log ("nop command received")
            } else {
            	write_log ("ERROR: exec_mode $cmd[1] not supported")
            }
			
		} else {
			write_log ("ERROR: unknown command ($cmd[0])");
		}
		
	}
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub autoupdate {
	
	#############################
	# update for Linux          #
	#############################
	if ($platform[0] eq 'Linux'){
		write_log ("     updating vnxaced for Linux...");
		system "perl /media/cdrom/uninstall_vnxaced -n";
		system "perl /media/cdrom/install_vnxaced";
		#if ( ($platform[1] eq 'Ubuntu') or   
        # 	 ($platform[1] eq 'Fedora') ) { 
        #	# Use VNXACED based on upstart
		#	system "cp /media/cdrom/vnxaced.pl /usr/local/bin/vnxaced";
		#	system "cp /media/cdrom/linux/upstart/vnxace.conf /etc/init/";
		#} elsif ($platform[1] eq 'CentOS') { 
		#	# Use VNXACED based on init.d
		#	system "cp -v vnxaced.pl /usr/local/bin/vnxaced";
		#	system "cp -v unix/init.d/vnxace /etc/init.d/";
		#}
	}
	#############################
	# update for FreeBSD        #
	#############################
	elsif ($platform[0] eq 'FreeBSD'){
		write_log ("     updating vnxdaemon for FreeBSD...");
		system "/cdrom/uninstall_vnxaced -n";
		system "/cdrom/install_vnxaced";
		#system "cp /cdrom/vnxaced.pl /usr/local/bin/vnxaced";
		#system "cp /cdrom/freebsd/vnxace /etc/rc.d/vnxace";
	}
    # Write trace messages to /etc/vnx_rootfs_version, log file and console
    my $vnxaced_vers = `/usr/local/bin/vnxaced -V | grep Version | awk '{printf "%s %s",\$2,\$3}'`;
    chomp (my $date = `date`);
    # vnx_rootfs_version file
    system "printf \"MODDATE=$date\n\" >> /etc/vnx_rootfs_version";
    system "printf \"MODDESC=vnxaced updated to vers $vnxaced_vers\n\" >> /etc/vnx_rootfs_version";
    # vnxaced log file
    write_log ("     vnxaced updated to vers $vnxaced_vers");
    # Console
	system "printf \"\r\n\" >> /dev/console";
	system "printf \"   ------------------------------------------------------------------------\r\n\" >> /dev/console";
	system "printf \"         vnxaced updated to vers $vnxaced_vers \r\n\" >> /dev/console";
	system "printf \"   ------------------------------------------------------------------------\r\n\" >> /dev/console";
	my $delay=5;
	system "printf \"\n         halting system in $delay seconds\" >> /dev/console";
		for (my $count = $delay-1; $count >= 0; $count--) {
		sleep 1;
		system "printf \"\b\b\b\b\b\b\b\b\b$count seconds\" >> /dev/console";
    }
    system "printf \"\r\n\r\n\r\n\" >> /dev/console";

    # Shutdown system
	system "halt -p";
	return;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub is_new_file {

	my $file = shift;

	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($file);
	my $idTagList = $dom->getElementsByTagName("id");
	my $idTag     = $idTagList->item(0);
	my $new_cid    = $idTag->getFirstChild->getData;
	chomp($new_cid);
#	write_log ("sleep 60");
#	sleep 60;
	
	#my $command = "cat /root/.vnx/command_id";
	#chomp (my $old_cid = `$command`);
	
	my $old_cid = get_conf_value (VNXACED_CID, 'cmd_id');
	
	#write_log ("comparing -$old_cid- and -$new_cid-");
	
	if ( ($old_cid ne '') && ($old_cid eq $new_cid)) {
		# file is not new
		#write_log ("file is not new");
		return "0";
	}

	#file is new
	#write_log ("file is new");
	#system "echo '$new_cid' > /root/.vnx/command_id";
	my $res = set_conf_value (VNXACED_CID, 'cmd_id', $new_cid);
	write_log ("Error writing the new comand id value to " . VNXACED_CID . " file") 
	    if ($res eq 'ERROR'); 
	
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

    write_log ("~~ Command output:");
	if ($ostype eq 'system') {
		# Execution mode for commands with no graphical user interface
		if ($DEBUG) {
			# vnxace has been started from the command line with -g option
      		# No problems with input/ouptut redirection. We execute it using 
			# backticks to capture output
			my $res=`$cmd`;
            write_log ($res);
		} else {
			# vnxace has been started as a deamon with input/output closed
			# We have to use this way to execute the command to avoid 
			# problems. Other ways tested (using exec or system with all kind of 
			# input/output redirections made some commands fail (for example, when 
			# starting apache: the server starts but does not answer requests and 
			# shows and error in logs related to sockets). 
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
            	write_log ($res);
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
			write_log ("     ERROR: no user logged on display :0.0. Command $cmd not executed.");
		} else {
			write_log "User on display :0.0 -->$userOnDisplay0[0]\n";

			if($ostype eq "xexec"){
				my $pid2 = fork;
				die "Couldn't fork: $!" unless defined($pid2);
				if ($pid2){
		        	# parent does nothing
				}else{
		        	# child executes command and dies
		        	if ($platform[0] eq 'Linux'){
		        		write_log ("exec \"setsid sh -c \\\"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] \'$cmd\'\\\"\" < /dev/null > /dev/null 2>&1");
                    	exec "setsid sh -c \"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] '$cmd'\" > /dev/null 2>&1 < /dev/null";
		        	} elsif ($platform[0] eq 'FreeBSD'){
		        		write_log ("system \"detach sh -c \\\"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] \'$cmd\'\\\"\" < /dev/null > /dev/null 2>&1");
                    	system "detach sh -c \"DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] '$cmd'\" > /dev/null 2>&1 < /dev/null";
                    	exit (0);
		        	}
                    
				}

			} elsif($ostype eq "xsystem"){
       			write_log ("DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] '$cmd' ");
       			my $res= `DISPLAY=:0.0 /usr/local/bin/xsu $userOnDisplay0[0] '$cmd' < /dev/null 2>&1`;
                write_log ($res);
   			}
		}

	} else {
		write_log ("   ERROR: command ostype mode '$ostype' unknown, use 'exec', 'system', 'xexec' or 'xsystem'. ");
	}
    write_log ("~~~~~~~~~~~~~~~~~~");
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
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($commands_file);
	my $execTagList = $dom->getElementsByTagName("exec");
	for (my $j = 0 ; $j < $execTagList->getLength; $j++){
		my $execTag    = $execTagList->item($j);
		my $seq        = $execTag->getAttribute("seq");
		my $type       = $execTag->getAttribute("type");
		my $ostype     = $execTag->getAttribute("ostype");
		my $command2   = $execTag->getFirstChild->getData;
			
		write_log ("     executing: '$command2' in ostype mode: '$ostype'");
		exe_cmd ($command2, $ostype);
	}
}

#~~~~~~~~~~~~~~ autoconfiguration ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub autoconfigure {

	my $vnxboot_file = shift;

	# autoconfigure for Linux             #
	if ($platform[0] eq 'Linux'){
		# Send a message to consoles
		#system "shutdown -k now 'VNX system autoconfiguration in progress...wait until the system reboots...'";
		
		if ($platform[1] eq 'Ubuntu')    { &autoconfigure_ubuntu ($vnxboot_file)}			
		elsif ( ($platform[1] eq 'Fedora') or ($platform[1] eq 'CentOS') ) { &autoconfigure_fedora ($vnxboot_file)}
	}
	# autoconfigure for FreeBSD           #
	elsif ($platform[0] eq 'FreeBSD'){
		write_log ("calling autoconfigure_freebsd");
		&autoconfigure_freebsd ($vnxboot_file)
	}
	
	# Change the message of the day (/etc/motd) to eliminate the
	# message asking to wait for reboot
	#system "sed -i -e '/~~~~~/d' /etc/motd";
	
	# Reboot system
	write_log ("   rebooting...\n");
	sleep 5;
	system "shutdown -r now '  VNX:  autoconfiguration finished...rebooting'";
	sleep 100; # wait for system to reboot
}


#
# autoconfigure for Ubuntu             
#
sub autoconfigure_ubuntu {
	
	my $vnxboot_file = shift;

	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($vnxboot_file);
	my $global_node   = $dom->getElementsByTagName("create_conf")->item(0);
	my $virtualmTagList = $global_node->getElementsByTagName("vm");
	my $virtualmTag     = $virtualmTagList->item(0);
	my $vm_name       = $virtualmTag->getAttribute("name");

	my $hostname_vm = `hostname`;
	$hostname_vm =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	$vm_name =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	# If the vm doesn't have the correct name,
	# start autoconfiguration process
	if (!($hostname_vm eq $vm_name)){
		write_log ("   host name ($hostname_vm) and name in vnxboot file ($vm_name) are different. starting autoconfiguration...");

		my $ifTaglist       = $virtualmTag->getElementsByTagName("if");

        # Delete /etc/resolv.conf file
        system "rm -f /etc/resolv.conf";
        
		# before the loop, backup /etc/udev/...70
		# and /etc/network/interfaces
		# and erase their contents
		write_log ("   configuring /etc/udev/rules.d/70-persistent-net.rules and /etc/network/interfaces...");
		my $rules_file = "/etc/udev/rules.d/70-persistent-net.rules";
		system "cp $rules_file $rules_file.backup";
		system "echo \"\" > $rules_file";
		open RULES, ">" . $rules_file or print "error opening $rules_file";
		my $interfaces_file = "/etc/network/interfaces";
		system "cp $interfaces_file $interfaces_file.backup";
		system "echo \"\" > $interfaces_file";
		open INTERFACES, ">" . $interfaces_file or print "error opening $interfaces_file";

		print INTERFACES "\n";
		print INTERFACES "auto lo\n";
		print INTERFACES "iface lo inet loopback\n";

		# Network interfaces configuration: <if> tags
		my $numif        = $ifTaglist->getLength;
		for (my $j = 0 ; $j < $numif ; $j++){
			my $ifTag = $ifTaglist->item($j);
			my $id    = $ifTag->getAttribute("id");
			my $net   = $ifTag->getAttribute("net");
			my $mac   = $ifTag->getAttribute("mac");
			$mac =~ s/,//g;

			my $ifName;
			# Special case: loopback interface
			if ( $net eq "lo" ) {
				$ifName = "lo:" . $id;
			} else {
				$ifName = "eth" . $id;
			}

			print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac . 	"\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $ifName . "\"\n\n";
			#print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";
			print INTERFACES "auto " . $ifName . "\n";

			my $ipv4Taglist = $ifTag->getElementsByTagName("ipv4");
			my $ipv6Taglist = $ifTag->getElementsByTagName("ipv6");

			if ( ($ipv4Taglist->getLength == 0 ) && ( $ipv6Taglist->getLength == 0 ) ) {
				# No addresses configured for the interface. We include the following commands to 
				# have the interface active on start
				print INTERFACES "iface " . $ifName . " inet manual\n";
				print INTERFACES "  up ifconfig " . $ifName . " 0.0.0.0 up\n";
			} else {
				# Config IPv4 addresses
				for ( my $j = 0 ; $j < $ipv4Taglist->getLength ; $j++ ) {

					my $ipv4Tag = $ipv4Taglist->item($j);
					my $mask    = $ipv4Tag->getAttribute("mask");
					my $ip      = $ipv4Tag->getFirstChild->getData;

					if ($j == 0) {
						print INTERFACES "iface " . $ifName . " inet static\n";
						print INTERFACES "   address " . $ip . "\n";
						print INTERFACES "   netmask " . $mask . "\n";
					} else {
						print INTERFACES "   up /sbin/ifconfig " . $ifName . " inet add " . $ip . " netmask " . $mask . "\n";
					}
				}
				# Config IPv6 addresses
				for ( my $j = 0 ; $j < $ipv6Taglist->getLength ; $j++ ) {

					my $ipv6Tag = $ipv6Taglist->item($j);
					my $ip    = $ipv6Tag->getFirstChild->getData;
              		my $mask = $ip;
                	$mask =~ s/.*\///;
                	$ip =~ s/\/.*//;

					if ($j == 0) {
						print INTERFACES "iface " . $ifName . " inet6 static\n";
						print INTERFACES "   address " . $ip . "\n";
						print INTERFACES "   netmask " . $mask . "\n\n";
					} else {
						print INTERFACES "   up /sbin/ifconfig " . $ifName . " inet6 add " . $ip . "/" . $mask . "\n";
					}
				}
			}
		}
		
		# Network routes configuration: <route> tags
		my $routeTaglist = $virtualmTag->getElementsByTagName("route");
		my $numRoutes    = $routeTaglist->getLength;
		for (my $j = 0 ; $j < $numRoutes ; $j++){
			my $routeTag = $routeTaglist->item($j);
			my $routeType = $routeTag->getAttribute("type");
			my $routeGw   = $routeTag->getAttribute("gw");
			my $route     = $routeTag->getFirstChild->getData;
			if ($routeType eq 'ipv4') {
				if ($route eq 'default') {
					print INTERFACES "   up route add -net default gw " . $routeGw . "\n";
				} else {
					print INTERFACES "   up route add -net $route gw " . $routeGw . "\n";
				}
			} elsif ($routeType eq 'ipv6') {
				if ($route eq 'default') {
					print INTERFACES "   up route -A inet6 add default gw " . $routeGw . "\n";
				} else {
					print INTERFACES "   up route -A inet6 add $route gw " . $routeGw . "\n";
				}
			}
		}		
		
		close RULES;
		close INTERFACES;
		
		# Packet forwarding: <forwarding> tag
		my $ipv4Forwarding = 0;
		my $ipv6Forwarding = 0;
		my $forwardingTaglist = $virtualmTag->getElementsByTagName("forwarding");
		my $numforwarding = $forwardingTaglist->getLength;
		for (my $j = 0 ; $j < $numforwarding ; $j++){
			my $forwardingTag   = $forwardingTaglist->item($j);
			my $forwarding_type = $forwardingTag->getAttribute("type");
			if ($forwarding_type eq "ip"){
				$ipv4Forwarding = 1;
				$ipv6Forwarding = 1;
			} elsif ($forwarding_type eq "ipv4"){
				$ipv4Forwarding = 1;
			} elsif ($forwarding_type eq "ipv6"){
				$ipv6Forwarding = 1;
			}
		}
		write_log ("   configuring ipv4 ($ipv4Forwarding) and ipv6 ($ipv6Forwarding) forwarding in /etc/sysctl.conf...");
		system "echo >> /etc/sysctl.conf ";
		system "echo '#### vnxdaemon ####' >> /etc/sysctl.conf ";
		system "echo 'net.ipv4.ip_forward=$ipv4Forwarding' >> /etc/sysctl.conf ";
		system "echo 'net.ipv6.conf.all.forwarding=$ipv6Forwarding' >> /etc/sysctl.conf ";

		# Configuring /etc/hosts and /etc/hostname
		write_log ("   configuring /etc/hosts and /etc/hostname...");
		my $hosts_file = "/etc/hosts";
		my $hostname_file = "/etc/hostname";
		system "cp $hosts_file $hosts_file.backup";

		#/etc/hosts: insert the new first line
		system "sed '1i\ 127.0.0.1	$vm_name	localhost.localdomain	localhost' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: and delete the second line (former first line)
		system "sed '2 d' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: insert the new second line
		system "sed '2i\ 127.0.1.1	$vm_name' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: and delete the third line (former second line)
		system "sed '3 d' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hostname: insert the new first line
		system "sed '1i\ $vm_name' $hostname_file > /tmp/hostname.tpm";
		system "mv /tmp/hostname.tpm $hostname_file";

		#/etc/hostname: and delete the second line (former first line)
		system "sed '2 d' $hostname_file > /tmp/hostname.tpm";
		system "mv /tmp/hostname.tpm $hostname_file";

		system "hostname $vm_name";
	}
	
}

#
# autoconfigure for Fedora             
#
sub autoconfigure_fedora {

	my $vnxboot_file = shift;
	
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($vnxboot_file);
	my $global_node   = $dom->getElementsByTagName("create_conf")->item(0);
	my $virtualmTagList = $global_node->getElementsByTagName("vm");
	my $virtualmTag     = $virtualmTagList->item(0);
	my $vm_name       = $virtualmTag->getAttribute("name");

	my $hostname_vm = `hostname`;
	$hostname_vm =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	$vm_name =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	# If the vm doesn't have the correct name,
	# start autoconfiguration process
	if (!($hostname_vm eq $vm_name)){
		write_log ("   host name ($hostname_vm) and name in vnxboot file ($vm_name) are different. starting autoconfiguration...");

		my $ifTaglist       = $virtualmTag->getElementsByTagName("if");


		system "mv /etc/sysconfig/network /etc/sysconfig/network.bak";
		system "cat /etc/sysconfig/network.bak | grep -v 'NETWORKING=' | grep -v 'NETWORKING_IPv6=' > /etc/sysconfig/network";
		system "echo NETWORKING=yes >> /etc/sysconfig/network";
		system "echo NETWORKING_IPV6=yes >> /etc/sysconfig/network";

		# before the loop, backup /etc/udev/...70
		# and erase their contents
		my $rules_file;
#		if ($platform[1] eq 'Fedora') { 
			$rules_file = "/etc/udev/rules.d/70-persistent-net.rules";
			system "cp $rules_file $rules_file.backup";
			system "echo \"\" > $rules_file";

		write_log ("   configuring $rules_file...");
		open RULES, ">" . $rules_file or print "error opening $rules_file";
#		} elsif ($platform[1] eq 'CentOS') { 
#			$rules_file = "/etc/udev/rules.d/60-net.rules";
#			system "cp $rules_file $rules_file.backup";
#		}

		# Network interfaces configuration: <if> tags
		my $numif        = $ifTaglist->getLength;
		#my $firstIf;
		my $firstIPv4If;
		my $firstIPv6If;
		
		for (my $i = 0 ; $i < $numif ; $i++){
			my $ifTag = $ifTaglist->item($i);
			my $id    = $ifTag->getAttribute("id");
			my $net   = $ifTag->getAttribute("net");
			my $mac   = $ifTag->getAttribute("mac");
			$mac =~ s/,//g;
			#if ($i == 0) { $firstIf = "eth$id"};
			
			my $ifName;
			# Special case: loopback interface
			if ( $net eq "lo" ) {
				$ifName = "lo:" . $id;
			} else {
				$ifName = "eth" . $id;
			}
			
			if ($platform[1] eq 'Fedora') { 
				print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac . 	"\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $ifName . "\"\n\n";
				#print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";

			} elsif ($platform[1] eq 'CentOS') { 
#				print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"" . $ifName . "\"\n\n";
			}


			my $ifFile;
			if ($platform[1] eq 'Fedora') { 
				$ifFile = "/etc/sysconfig/network-scripts/ifcfg-Auto_$ifName";
			} elsif ($platform[1] eq 'CentOS') { 
				$ifFile = "/etc/sysconfig/network-scripts/ifcfg-$ifName";
			}
			system "echo \"\" > $ifFile";
			open IF_FILE, ">" . $ifFile or print "error opening $ifFile";
	
			if ($platform[1] eq 'CentOS') { 
				print IF_FILE "DEVICE=$ifName\n";
			}
			print IF_FILE "HWADDR=$mac\n";
			print IF_FILE "TYPE=Ethernet\n";
			#print IF_FILE "BOOTPROTO=none\n";
			print IF_FILE "ONBOOT=yes\n";
			if ($platform[1] eq 'Fedora') { 
				print IF_FILE "NAME=\"Auto $ifName\"\n";
			} elsif ($platform[1] eq 'CentOS') { 
				print IF_FILE "NAME=\"$ifName\"\n";
			}

			print IF_FILE "IPV6INIT=yes\n";
			
			my $ipv4Taglist = $ifTag->getElementsByTagName("ipv4");
			my $ipv6Taglist = $ifTag->getElementsByTagName("ipv6");

			# Config IPv4 addresses
			for ( my $j = 0 ; $j < $ipv4Taglist->getLength ; $j++ ) {

				my $ipv4Tag = $ipv4Taglist->item($j);
				my $mask    = $ipv4Tag->getAttribute("mask");
				my $ip      = $ipv4Tag->getFirstChild->getData;

				$firstIPv4If = "$ifName" if $firstIPv4If==''; 

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
			for ( my $j = 0 ; $j < $ipv6Taglist->getLength ; $j++ ) {

				my $ipv6Tag = $ipv6Taglist->item($j);
				my $ip    = $ipv6Tag->getFirstChild->getData;

				$firstIPv6If = "$ifName" if $firstIPv6If==''; 

				if ($j == 0) {
					print IF_FILE "IPV6_AUTOCONF=no\n";
					print IF_FILE "IPV6ADDR=$ip\n";
				} else {
					$ipv6secs .= " $ip" if $ipv6secs ne '';
					$ipv6secs .= "$ip" if $ipv6secs eq '';
				}
			}
			if ($ipv6secs ne '') {
				print IF_FILE "IPV6ADDR_SECONDARIES=\"$ipv6secs\"\n";
			}
			close IF_FILE;
		}
		close RULES;

		# Network routes configuration: <route> tags
		my $routeFile = "/etc/sysconfig/network-scripts/route-Auto_$firstIPv4If";
		system "echo \"\" > $routeFile";
		open ROUTE_FILE, ">" . $routeFile or print "error opening $routeFile";
		my $route6File = "/etc/sysconfig/network-scripts/route6-Auto_$firstIPv6If";
		system "echo \"\" > $route6File";
		open ROUTE6_FILE, ">" . $route6File or print "error opening $route6File";
		
		my $routeTaglist = $virtualmTag->getElementsByTagName("route");
		my $numRoutes    = $routeTaglist->getLength;
		for (my $j = 0 ; $j < $numRoutes ; $j++){
			my $routeTag = $routeTaglist->item($j);
			my $routeType = $routeTag->getAttribute("type");
			my $routeGw   = $routeTag->getAttribute("gw");
			my $route     = $routeTag->getFirstChild->getData;
			if ($routeType eq 'ipv4') {
				if ($route eq 'default') {
					print ROUTE_FILE "ADDRESS$j=0.0.0.0\n";
					print ROUTE_FILE "NETMASK$j=0\n";
					print ROUTE_FILE "GATEWAY$j=$routeGw\n";
				} else {
              		my $mask = $route;
                	$mask =~ s/.*\///;
                	$mask = cidr_to_mask ($mask);
                	$route =~ s/\/.*//;
					print ROUTE_FILE "ADDRESS$j=$route\n";
					print ROUTE_FILE "NETMASK$j=$mask\n";
					print ROUTE_FILE "GATEWAY$j=$routeGw\n";
				}
			} elsif ($routeType eq 'ipv6') {
				if ($route eq 'default') {
					print ROUTE6_FILE "2000::/3 via $routeGw metric 0\n";
				} else {
					print ROUTE6_FILE "$route via $routeGw metric 0\n";
				}
			}
		}
		close ROUTE_FILE;
		close ROUTE6_FILE;
		
		# Packet forwarding: <forwarding> tag
		my $ipv4Forwarding = 0;
		my $ipv6Forwarding = 0;
		my $forwardingTaglist = $virtualmTag->getElementsByTagName("forwarding");
		my $numforwarding = $forwardingTaglist->getLength;
		for (my $j = 0 ; $j < $numforwarding ; $j++){
			my $forwardingTag   = $forwardingTaglist->item($j);
			my $forwarding_type = $forwardingTag->getAttribute("type");
			if ($forwarding_type eq "ip"){
				$ipv4Forwarding = 1;
				$ipv6Forwarding = 1;
			} elsif ($forwarding_type eq "ipv4"){
				$ipv4Forwarding = 1;
			} elsif ($forwarding_type eq "ipv6"){
				$ipv6Forwarding = 1;
			}
		}
		write_log ("   configuring ipv4 ($ipv4Forwarding) and ipv6 ($ipv6Forwarding) forwarding in /etc/sysctl.conf...");
		system "echo >> /etc/sysctl.conf ";
		system "echo '#### vnxdaemon ####' >> /etc/sysctl.conf ";
		system "echo 'net.ipv4.ip_forward=$ipv4Forwarding' >> /etc/sysctl.conf ";
		system "echo 'net.ipv6.conf.all.forwarding=$ipv6Forwarding' >> /etc/sysctl.conf ";

		# Configuring /etc/hosts and /etc/hostname
		write_log ("   configuring /etc/hosts and /etc/hostname...");
		my $hosts_file = "/etc/hosts";
		my $hostname_file = "/etc/hostname";
		system "cp $hosts_file $hosts_file.backup";

		#/etc/hosts: insert the new first line
		system "sed '1i\ 127.0.0.1	$vm_name	localhost.localdomain	localhost' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: and delete the second line (former first line)
		system "sed '2 d' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: insert the new second line
		system "sed '2i\ 127.0.1.1	$vm_name' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: and delete the third line (former second line)
		system "sed '3 d' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hostname: insert the new first line
		system "sed '1i\ $vm_name' $hostname_file > /tmp/hostname.tpm";
		system "mv /tmp/hostname.tpm $hostname_file";

		#/etc/hostname: and delete the second line (former first line)
		system "sed '2 d' $hostname_file > /tmp/hostname.tpm";
		system "mv /tmp/hostname.tpm $hostname_file";

		system "hostname $vm_name";
		system "mv /etc/sysconfig/network /etc/sysconfig/network.bak";
		system "cat /etc/sysconfig/network.bak | grep -v HOSTNAME > /etc/sysconfig/network";
		system "echo HOSTNAME=$vm_name >> /etc/sysconfig/network";
	}
	
}

#
# autoconfigure for FreeBSD             
#
sub autoconfigure_freebsd {
	
	my $vnxboot_file = shift;

	write_log ("~~ autoconfigure_freebsd");
	
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($vnxboot_file);
	my $global_node   = $dom->getElementsByTagName("create_conf")->item(0);
	my $virtualmTagList = $global_node->getElementsByTagName("vm");
	my $virtualmTag     = $virtualmTagList->item(0);
	my $vm_name       = $virtualmTag->getAttribute("name");

	my $hostname_vm = `hostname -s`;
	$hostname_vm =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	$vm_name =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	# If the vm doesn't have the correct name,
	# start autoconfiguration process
	if (!($hostname_vm eq $vm_name)){
		write_log ("   host name ($hostname_vm) and name in vnxboot file ($vm_name) are different. starting autoconfiguration...");
		my $ifTaglist       = $virtualmTag->getElementsByTagName("if");

		# before the loop, backup /etc/rc.conf
		my $command;
		write_log ("   configuring /etc/rc.conf...");
		my $rc_file = "/etc/rc.conf";
		$command = "cp $rc_file $rc_file.backup";
		system $command;

		open RC, ">>" . $rc_file or write_log ("error opening $rc_file");

		chomp (my $now = `date`);

		print RC "\n";
		print RC "##############################################################\n";
		print RC "## vnx autoconfiguration ($now)     ##\n";
		print RC "##############################################################\n";
		print RC "\n";

		print RC "hostname=\"$vm_name\"\n";
		print RC "sendmail_enable=\"NONE\"\n"; #avoids some startup errors

		# Network interfaces configuration: <if> tags
		my $numif        = $ifTaglist->getLength;
		for (my $i = 0 ; $i < $numif ; $i++){
			my $ifTag = $ifTaglist->item($i);
			my $id    = $ifTag->getAttribute("id");
			my $net   = $ifTag->getAttribute("net");
			my $mac   = $ifTag->getAttribute("mac");
			$mac =~ s/,//g;

			print RC "ifconfig_re". $i . "_name=\"net" . $id . "\"\n";
#			print RC "ifconfig_net" . $id . "=\"inet " . $ip . " netmask " . $mask . " ether " . $mac . "\"\n";
			#system "echo 'ifconfig net$id ether $mask' > /etc/start_if.net$id";
	
			my $alias_num=-1;
				
			# IPv4 addresses
			my $ipv4Taglist = $ifTag->getElementsByTagName("ipv4");
			for ( my $j = 0 ; $j < $ipv4Taglist->getLength ; $j++ ) {

				my $ipv4Tag = $ipv4Taglist->item($j);
				my $mask    = $ipv4Tag->getAttribute("mask");
				my $ip      = $ipv4Tag->getFirstChild->getData;

				if ($alias_num == -1) {
					print RC "ifconfig_net" . $id . "=\"inet " . $ip . " netmask " . $mask . "\"\n";
				} else {
					print RC "ifconfig_net" . $id . "_alias" . $alias_num . "=\"inet " . $ip . " netmask " . $mask . "\"\n";
				}
				$alias_num++;
			}

			# IPv6 addresses
			my $ipv6Taglist = $ifTag->getElementsByTagName("ipv6");
			for ( my $j = 0 ; $j < $ipv6Taglist->getLength ; $j++ ) {

				my $ipv6Tag = $ipv6Taglist->item($j);
				my $ip    = $ipv6Tag->getFirstChild->getData;
           		my $mask = $ip;
               	$mask =~ s/.*\///;
               	$ip =~ s/\/.*//;

				if ($alias_num == -1) {
					print RC "ifconfig_net" . $id . "=\"inet6 " . $ip . " prefixlen " . $mask . "\"\n";
				} else {
					print RC "ifconfig_net" . $id . "_alias" . $alias_num . "=\"inet6 " . $ip . " prefixlen " . $mask . "\"\n";
				}
				$alias_num++;
			}
		}
		
		# Network routes configuration: <route> tags
		my $routeTaglist       = $virtualmTag->getElementsByTagName("route");
		my $numroute        = $routeTaglist->getLength;

		# Example content:
		# 	  static_routes="r1 r2"
		#	  ipv6_static_routes="r3 r4"
		# 	  default_router="10.0.1.2"
		# 	  route_r1="-net 10.1.1.0/24 10.0.0.3"
		#     route_r2="-net 10.1.2.0/24 10.0.0.3"
		# 	  ipv6_default_router="2001:db8:1::1"
		#	  ipv6_route_r3="2001:db8:7::/3 2001:db8::2"
		#	  ipv6_route_r4="2001:db8:8::/64 2001:db8::2"
		my @routeCfg;           # Stores the route_* lines 
		my $static_routes;      # Stores the names of the ipv4 routes
		my $ipv6_static_routes; # Stores the names of the ipv6 routes
		my $i = 1;
		for (my $j = 0 ; $j < $numroute ; $j++){
			my $routeTag = $routeTaglist->item($j);
			if (defined($routeTag)){
				my $routeType = $routeTag->getAttribute("type");
				my $routeGw   = $routeTag->getAttribute("gw");
				my $route     = $routeTag->getFirstChild->getData;

				if ($routeType eq 'ipv4') {
					if ($route eq 'default'){
						push (@routeCfg, "default_router=\"$routeGw\"\n");
					} else {
						push (@routeCfg, "route_r$i=\"-net $route $routeGw\"\n");
						$static_routes = ($static_routes eq '') ? "r$i" : "$static_routes r$i";
						$i++;
					}
				} elsif ($routeType eq 'ipv6') {
					if ($route eq 'default'){
						push (@routeCfg, "ipv6_default_router=\"$routeGw\"\n");
					} else {
						push (@routeCfg, "ipv6_route_r$i=\"$route $routeGw\"\n");
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
		my $ipv4Forwarding = 0;
		my $ipv6Forwarding = 0;
		my $forwardingTaglist = $virtualmTag->getElementsByTagName("forwarding");
		my $numforwarding = $forwardingTaglist->getLength;
		for (my $j = 0 ; $j < $numforwarding ; $j++){
			my $forwardingTag   = $forwardingTaglist->item($j);
			my $forwarding_type = $forwardingTag->getAttribute("type");
			if ($forwarding_type eq "ip"){
				$ipv4Forwarding = 1;
				$ipv6Forwarding = 1;
			} elsif ($forwarding_type eq "ipv4"){
				$ipv4Forwarding = 1;
			} elsif ($forwarding_type eq "ipv6"){
				$ipv6Forwarding = 1;
			}
		}
		if ($ipv4Forwarding == 1) {
			write_log ("   configuring ipv4 forwarding...");
			print RC "gateway_enable=\"YES\"\n";
		}
		if ($ipv6Forwarding == 1) {
			write_log ("   configuring ipv6 forwarding...");
			print RC "ipv6_gateway_enable=\"YES\"\n";
		}
		
		# Configuring /etc/hosts and /etc/hostname
		write_log ("   configuring /etc/hosts");
		my $hosts_file = "/etc/hosts";
		$command = "cp $hosts_file $hosts_file.backup";
		system $command;

		system "echo '127.0.0.1	$vm_name	localhost.localdomain	localhost' > /etc/hosts";
		system "echo '127.0.1.1	$vm_name' >> /etc/hosts";

		#/etc/hosts: insert the new first line
#		system "sed '1i\ 127.0.0.1	$vm_name	localhost.localdomain	localhost' $hosts_file > /tmp/hosts.tmp";
#		system "mv /tmp/hosts.tmp $hosts_file";
#	
#		#/etc/hosts: and delete the second line (former first line)
#		system "sed '2 d' $hosts_file > /tmp/hosts.tmp";
#		system "mv /tmp/hosts.tmp $hosts_file";
#	
#		#/etc/hosts: insert the new second line
#		system "sed '2i\ 127.0.1.1	$vm_name' $hosts_file > /tmp/hosts.tmp";
#		system "mv /tmp/hosts.tmp $hosts_file";
#	
#		#/etc/hosts: and delete the third line (former second line)
#		system "sed '3 d' $hosts_file > /tmp/hosts.tmp";
#		system "mv /tmp/hosts.tmp $hosts_file";
	}
	
}


#~~~~~~~~~~~~~~ filetree processing ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub execute_filetree {

	my $cmd_file = shift;

	my $cmd_path = dirname($cmd_file);

    write_log ("~~ processing <filetree> tags in file $cmd_file");

	my $parser           = new XML::DOM::Parser;
	my $dom              = $parser->parsefile($cmd_file);
	my $filetree_taglist = $dom->getElementsByTagName("filetree");
	for (my $j = 0 ; $j < $filetree_taglist->getLength ; $j++){
		my $filetree_tag = $filetree_taglist->item($j);
		my $seq          = $filetree_tag->getAttribute("seq");
        my $root         = $filetree_tag->getAttribute("root");
        my $user         = $filetree_tag->getAttribute("user");
        my $group        = $filetree_tag->getAttribute("group");
        my $perms        = $filetree_tag->getAttribute("perms");
		my $folder = $j + 1;
		my $source_path = $cmd_path . "/filetree/" . $folder . "/";
        write_log ("~~   processing <filetree> tag: seq=$seq, root=$root, " . 
                         "user=$user, group=$group, perms=$perms, source_path=$source_path");

		my $res=`ls -R $source_path`; write_log ("cdrom content: $res") if ($VERBOSE);
		# Get the number of files in source dir
		my $num_files=`ls -a1 $source_path | wc -l`;
		if ($num_files < 3) { # count "." and ".."
        	write_log ("~~   ERROR in filetree: no files to copy in $source_path (seq=$seq)\n");
        	next;
		}
		# Check if files destination (root attribute) is a directory or a file
		my $cmd;
		if ( $root =~ /\/$/ ) {
			# Destination is a directory
        	write_log ("~~   Destination is a directory");
			unless (-d $root){
				write_log ("~~   creating unexisting dir '$root'...");
				system "mkdir -p $root";
			}
			# Change owner and permissions if specified in <filetree>
			$cmd="cp -vR ${source_path}* $root";
	        write_log ("~~   Executing '$cmd' ...");
	        $res=`$cmd`;
	        write_log ("Copying filetree files:") if ($VERBOSE);
	        write_log ("$res") if ($VERBOSE);
			if ( $user ne ''  ) { system "chown -R $user $root/*"}
            if ( $group ne '' ) { system "chown -R .$group $root/*"}
			if ( $perms ne '' ) { system "chmod -R $perms $root/*"}
			
		} else {
			# Destination is a file
			# Check that $source_path contains only one file
        	write_log ("~~   Destination is a file");
			if ($num_files > 3) { # count "." and ".."
        		write_log ("~~   ERROR in filetree: destination ($root) is a file and there is more than one file in $source_path (seq=$seq)\n");
        		next;
			}
			my $file_dir = dirname($root);
			unless (-d $file_dir){
				write_log ("~~   creating unexisting dir '$file_dir'...");
				system "mkdir -p $file_dir";
			}
			$cmd="cp -v ${source_path}* $root";
            write_log ("~~   Executing '$cmd' ...");
            $res=`$cmd`;
            write_log ("Copying filetree files:") if ($VERBOSE);
            write_log ("$res") if ($VERBOSE);
            # Change owner and permissions if specified in <filetree>
            if ( $user ne ''  ) { system "chown -R $user $root"}
            if ( $group ne '' ) { system "chown -R .$group $root"}
            if ( $perms ne '' ) { system "chmod -R $perms $root"}
		}
		write_log ("~~~~~~~~~~~~~~~~~~~~");
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
#	  Linux,Fedora,14,Laughlin,2.6.35.11-83.fc14.i386,i386
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

    open IFILE, "< $cfg_file";
    open OFILE, "> $cfg_file.new" or return 'ERROR';
    print "going while...\n";
    while (my $line = <IFILE>) {
        print "while $line ...\n";
        if ($line =~ /^$param/) {
            $line =~ s/^$param=.*/$param=$new_value/g;
            $param_found = 'true';
        }
        print OFILE $line; 
    }
    unless ($param_found) {
	print "not found \n";
        print "$param=$new_value\n";        
	print OFILE "$param=$new_value\n";
    }
    close IFILE;
    close OFILE;

    system ("mv $cfg_file.new $cfg_file");
    return $new_value;
}

sub vnxaced_die {
    my $err_msg = shift;

    write_log ($err_msg); 
    die "$err_msg\n";

}

1;
