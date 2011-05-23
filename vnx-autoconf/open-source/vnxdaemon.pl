#!/usr/bin/perl

use strict;
use POSIX;
use Sys::Syslog;
use XML::DOM;

use constant LINUX_TTY => '/dev/ttyS1';
use constant FREEBSD_TTY => '/dev/cuau1';

my @platform;
my $mountCmd;
my $umountCmd; 


sleep 10;
&main;
exit(0);

sub main{

	my $command;

	#detect platform (values: 'Linux', 'FreeBSD')
	#$command = "uname";
	#chomp ($platform = `$command`);
		
	@platform = split(/,/, &getOSDistro);
	
	if ($platform[0] eq 'Linux'){
		if ($platform[1] eq 'Ubuntu')    { 
			$mountCmd = 'mount /media/cdrom';
			$umountCmd = 'umount /media/cdrom';
		}			
		elsif ($platform[1] eq 'Fedora') { 
			$mountCmd = 'udisks --mount /dev/sr0';
			$umountCmd = 'udisks --unmount /dev/sr0';			
		}
	} elsif ($platform[0] eq 'FreeBSD'){
		$mountCmd = 'mount /cdrom';
		$umountCmd = 'umount -f /cdrom';
	}
	
	# if this is the first run...
	unless (-f "/root/.vnx/LOCK"){
		# generate LOCK file
		system "mkdir -p /root/.vnx/";
		system "touch /root/.vnx/LOCK";
		# generate run dir
		#system "mkdir -p /var/run/vnxdaemon/";
		# remove residual log file
		system "rm -f /var/log/vnxdaemon.log";
		# remove residual PID file
		system "rm -f /var/run/vnxdaemon.pid";
		# generate new log file
		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		print LOG "\n";
		print LOG "\n";
		$command = "date";
		chomp (my $now = `$command`);
		print LOG "#########################################################################\n";
		print LOG "#### vnxdaemon log sequence started at $now  ####\n";
		print LOG "#########################################################################\n";
		close LOG;
	}

	if (-f "/var/run/vnxdaemon.pid"){
		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		print LOG "Another instance of vnxdaemon (PID " . "/var/run/vnxdaemon.pid" . ") seems to be running, aborting current execution (PID $$)\n";
		exit 1;
	}
	

	&daemonize;
	&listen;
	

}


############### daemonize process ################

sub daemonize {
		
	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	print LOG "\n";	
	print LOG "## Daemonizing process ##\n";

	# Fork
#	my $pid = fork;
#	exit if $pid;
#	die "Couldn't fork: $!" unless defined($pid);

	# store process pid
	system "echo $$ > /var/run/vnxdaemon.pid";

	# Become session leader (independent from shell and terminal)
	setsid();

	# Close descriptors
	#close(STDERR);
	#close(STDOUT);
	close(STDIN);

	# Set permissions for temporary files
	umask(027);

	# Run in /
	chdir("/");

	print LOG "\n";
	close LOG;
}



############### listen for events ################

sub listen {


	#############################
	# listen for Linux          #
	#############################
	if ($platform[0] eq 'Linux'){

		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		print LOG "## Listening ##\n\n";
		system "mkdir -p /root/.vnx";
		my @files = </media/*>;
		my $commands_file;
		sleep 5;
		#system "mount /media/cdrom";
		system "$mountCmd";
		while (1){
			foreach my $file (@files){
				my @files2 = <$file/*>;
				foreach my $file2 (@files2){
					if ($file2 eq "/media/cdrom/command.xml"){
						unless (&check_if_new_file($file2,"command")){
							next;				
						}
						my $path = $file;
						my $command = "date +%X";
						chomp (my $now = `$command`);						
						print LOG "   $now\n";
						print LOG "   command received in $file2\n";
						&filetree($path);
						&execute_commands($file2);
						print LOG "   sending 'done' signal to host...\n\n";
						system "echo finished! > " . LINUX_TTY;
						
					}elsif ($file2 eq "/media/cdrom/vnxboot"){
						unless (&check_if_new_file($file2,"create_conf")){
							next;				
						}
						my $command = "date +%X";
						chomp (my $now = `$command`);						
						print LOG "   $now\n";
						print LOG "   configuration file received in $file2\n";
						&autoconfigure($file2);
						print LOG "\n";
					}elsif ($file2 eq "/media/cdrom/vnx_update.xml"){
						unless (&check_if_new_file($file2,"vnx_update") eq '1'){
							next;				
						}
						my $command = "date +%X";
						chomp (my $now = `$command`);						
						print LOG "   $now\n";
						print LOG "   update files received in $file2\n";
						&autoupdate;
						print LOG "\n";

					}else {
						# unknown file, do nothing
					}
				}
			}
			#system "umount /media/cdrom";
			system "$umountCmd";
			sleep 5;
			#system "mount /media/cdrom";
			system "$mountCmd";
		}

	}

	#############################
	# listen for FreeBSD        #
	#############################
	elsif ($platform[0] eq 'FreeBSD'){
		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		print LOG "## Listening ##\n\n";
		system "mkdir -p /root/.vnx";
		my @files = </*>;
		my $commands_file;
		
		# JSF: comentado porque al rearrancar el servicio a mano pinta error por pantalla si
		# no esta montado el CD-ROM. Si no da errores de otro tipo se podra quitar del todo.
		#system "umount -f /cdrom";
		sleep 5;
		#system "mount /cdrom";
		system "$mountCmd";
		while (1){

			foreach my $file (@files){
				my @files2 = <$file/*>;

				foreach my $file2 (@files2){
					
					if ($file2 eq "/media/cdrom/command.xml"){
						unless (&check_if_new_file($file2,"command")){
							next;				
						}
						my $path = $file;
						my $command = "date +%X";
						chomp (my $now = `$command`);						
						print LOG "   $now\n";
						print LOG "   command received in $file2\n";
						&filetree($path);
						&execute_commands($file2);
						print LOG "   sending 'done' signal to host...\n\n";
						system "echo finished! > " . FREEBSD_TTY;
					
					}elsif ($file2 eq "/cdrom/vnxboot"){
						unless (&check_if_new_file($file2,"create_conf")){
							next;				
						}
						my $command = "date +%X";
						chomp (my $now = `$command`);						
						print LOG "   $now\n";
						print LOG "   configuration file received in $file2\n";
						&autoconfigure($file2);
						print LOG "\n";

					}elsif ($file2 eq "/cdrom/vnx_update.xml"){
						unless (&check_if_new_file($file2,"vnx_update") eq '1'){
							next;				
						}
						my $command = "date +%X";
						chomp (my $now = `$command`);						
						print LOG "   $now\n";
						print LOG "   update files received in $file2\n";
						&autoupdate;
						print LOG "\n";

					}else {
						# unknown file, do nothing
					}
				}
			}
			#system "umount -f /cdrom";
			system "$umountCmd";
			sleep 5;
			#system "mount /cdrom";
			system "$mountCmd";
		}
	}
}


sub autoupdate {
	
	#############################
	# update for Linux          #
	#############################
	if ($platform[0] eq 'Linux'){
		print LOG "   updating vnxdaemon for Linux\n";
		system "cp /media/cdrom/vnxdaemon.pl /etc/init.d/";
		system "cp /media/cdrom/unix/* /etc/init/";
	}
	#############################
	# update for FreeBSD        #
	#############################
	elsif ($platform[0] eq 'FreeBSD'){
		print LOG "   updating vnxdaemon for FreeBSD\n";
		system "cp /cdrom/vnxdaemon.pl /usr/sbin/";
		system "cp /cdrom/freebsd/* /etc/rc.d/vnxdaemon";
	}
	system "rm /root/.vnx/LOCK";
	sleep 1;
	#system "reboot";
	system "shutdown -r now '  VNX:  autoconfiguration daemon updated...rebooting'";
	return;
}


############### check id of a file ################

sub check_if_new_file {
open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	my $file = shift;
	my $type = shift;	
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($file);
	my $globalNode   = $dom->getElementsByTagName($type)->item(0);

	my $idTagList = $globalNode->getElementsByTagName("id");
	my $idTag     = $idTagList->item(0);
	my $newid    = $idTag->getFirstChild->getData;
	chomp($newid);
#	print LOG "sleep 60\n";
#	sleep 60;
	
	my $command = "cat /root/.vnx/command_id";
	chomp (my $oldid = `$command`);
	
#	print LOG "comparando -$oldid- y -$newid-\n";
	
	if ($oldid eq $newid){
		# file is not new
		return "0";
	}

	#file is new
	system "echo '$newid' > /root/.vnx/command_id";
	return "1";
}


############### command execution ##############

sub execute_commands {

	

	#######################################
	# execute_commands for Linux          #
	#######################################
	if ($platform[0] eq 'Linux'){
		my $commands_file = shift;
		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		my $parser       = new XML::DOM::Parser;
		my $dom          = $parser->parsefile($commands_file);
		my $globalNode   = $dom->getElementsByTagName("command")->item(0);
		my $execTagList = $globalNode->getElementsByTagName("exec");
		my $numexec        = $execTagList->getLength;
		for (my $j = 0 ; $j < $numexec ; $j++){
			my $execTag     = $execTagList->item($j);
			my $seq       = $execTag->getAttribute("seq");
			my $type       = $execTag->getAttribute("type");
			my $mode       = $execTag->getAttribute("mode");
			my $command2    = $execTag->getFirstChild->getData;
			
			if ($mode eq "exec"){
				print LOG "   executing: '$command2'\n   in mode: 'exec'\n";
				# Fork
				my $pid2 = fork;
				die "Couldn't fork: $!" unless defined($pid2);
				if ($pid2){
					# parent does nothing
				}else{
					# child executes command and dies
					#exec "xterm -display :0.0 -e $command2";					
					exec "DISPLAY=:0.0 $command2";

				}
			}elsif($mode eq "system"){
					print LOG "   executing: '$command2'\n   in mode: 'system'\n";
					#system $command2;
					system "DISPLAY=:0.0 $command2";
			}else{
				print LOG "   command mode '$mode' not available, use \"exec\" or \"system\" instead. Aborting execution...\n";
			}
					
			
#			if ($mode eq "system"){
#				print LOG "   executing: '$command2'\n   in mode: 'system'\n";
#				# Fork
#				my $pid2 = fork;
#				die "Couldn't fork: $!" unless defined($pid2);
#				if ($pid2){
#					# parent does nothing
#				}else{
#					# child executes command and dies
#					#exec "xterm -display :0.0 -e $command2";
#					exec "DISPLAY=:0.0 $command2";
#				}
#			}elsif($mode eq "processn"){
#				print LOG "   executing: '$command2'\n   in mode: 'processn'\n";
#				# Fork
#				my $pid2 = fork;
#				die "Couldn't fork: $!" unless defined($pid2);
#				if ($pid2){
#					# parent does nothing
#				}else{
#					# child executes command and dies
#					exec $command2;
#				}
#			}elsif($mode eq "processy"){
#				print LOG "   executing: '$command2'\n   in mode: 'processy'\n";
#				system $command2;
#			}else{
#				print LOG "   Command mode '$mode' not available. Aborting execution...\n";
#			}
		}
	}

	#######################################
	# execute_commands for FreeBSD        #
	#######################################
	elsif ($platform[0] eq 'FreeBSD'){
		my $commands_file = shift;
		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		my $parser       = new XML::DOM::Parser;
		my $dom          = $parser->parsefile($commands_file);
		my $globalNode   = $dom->getElementsByTagName("command")->item(0);
		my $execTagList = $globalNode->getElementsByTagName("exec");
		my $numexec        = $execTagList->getLength;
		for (my $j = 0 ; $j < $numexec ; $j++){
			my $execTag     = $execTagList->item($j);
			my $seq       = $execTag->getAttribute("seq");
			my $type       = $execTag->getAttribute("type");
			my $mode       = $execTag->getAttribute("mode");
			my $command2    = $execTag->getFirstChild->getData;


			if ($mode eq "exec"){
				print LOG "   executing: '$command2'\n   in mode: 'exec'\n";
				# Fork
				my $pid2 = fork;
				die "Couldn't fork: $!" unless defined($pid2);
				if ($pid2){
					# parent does nothing
				}else{
					# child executes command and dies
					#exec "xterm -display :0.0 -e $command2";
					exec "DISPLAY=:0.0 $command2";
					#exec $command2;
				}
			}elsif($mode eq "system"){
					print LOG "   executing: '$command2'\n   in mode: 'system'\n";
					system "DISPLAY=:0.0 $command2";
			}else{
				print LOG "   command mode '$mode' not available, use \"exec\" or \"system\" instead. Aborting execution...\n";
			}


#			if ($mode eq "system"){
#				print LOG "   executing: '$command2'\n   in mode: 'system'\n";
#				# Fork
#				#my $pid2 = fork;
#				#die "Couldn't fork: $!" unless defined($pid2);
#				#if ($pid2){
#					# parent does nothing
#				#}else{
#					# child executes command and dies
#					system "su - vnx -c \"$command2\"";
#					system $command2;
#					system "$command2";
#					system "xterm -e $command2";
#					system "xterm --display:0.0 -e $command2";
#					exec "xterm -e $command2";
#					exec "xterm --display:0.0 -e $command2";
#				#}
#			}elsif($mode eq "processn"){
#				print LOG "   executing: '$command2'\n   in mode: 'processn'\n";
#				# Fork
#				my $pid2 = fork;
#				die "Couldn't fork: $!" unless defined($pid2);
#				if ($pid2){
#					# parent does nothing
#				}else{
#					# child executes command and dies
#					exec $command2;
#				}
#			}elsif($mode eq "processy"){
#				print LOG "   executing: '$command2'\n   in mode: 'processy'\n";
#				system $command2;
#			}else{
#				print LOG "   Command mode '$mode' not available. Aborting execution...\n";
#			}
			
			
			
		}


	}

}


############### autoconfiguration ##############

sub autoconfigure {

	my $vnxboot_file = shift;
	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";

	# autoconfigure for Linux             #
	if ($platform[0] eq 'Linux'){
		if ($platform[1] eq 'Ubuntu')    { &autoconfigureUbuntu ($vnxboot_file)}			
		elsif ($platform[1] eq 'Fedora') { &autoconfigureFedora ($vnxboot_file)}
	}
	# autoconfigure for FreeBSD           #
	elsif ($platform[0] eq 'FreeBSD'){
		print LOG "calling autoconfigureFreeBSD\n";
		&autoconfigureFreeBSD ($vnxboot_file)
	}
}


#
# autoconfigure for Ubuntu             
#
sub autoconfigureUbuntu {
	
	my $vnxboot_file = shift;

	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($vnxboot_file);
	my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
	my $virtualmTagList = $globalNode->getElementsByTagName("vm");
	my $virtualmTag     = $virtualmTagList->item(0);
	my $vmName       = $virtualmTag->getAttribute("name");

	my $hostname_vm = `hostname`;
	$hostname_vm =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	$vmName =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	# If the vm doesn't have the correct name,
	# start autoconfiguration process
	if (!($hostname_vm eq $vmName)){
		print LOG "   host name ($hostname_vm) and name in vnxboot file ($vmName) are different. starting autoconfiguration...\n";

		my $ifTaglist       = $virtualmTag->getElementsByTagName("if");

		# before the loop, backup /etc/udev/...70
		# and /etc/network/interfaces
		# and erase their contents
		print LOG "   configuring /etc/udev/rules.d/70-persistent-net.rules and /etc/network/interfaces...\n";
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
		print LOG "   configuring ipv4 ($ipv4Forwarding) and ipv6 ($ipv6Forwarding) forwarding in /etc/sysctl.conf...\n";
		system "echo >> /etc/sysctl.conf ";
		system "echo '#### vnxdaemon ####' >> /etc/sysctl.conf ";
		system "echo 'net.ipv4.ip_forward=$ipv4Forwarding' >> /etc/sysctl.conf ";
		system "echo 'net.ipv6.conf.all.forwarding=$ipv6Forwarding' >> /etc/sysctl.conf ";

		# Configuring /etc/hosts and /etc/hostname
		print LOG "   configuring /etc/hosts and /etc/hostname...\n";
		my $hosts_file = "/etc/hosts";
		my $hostname_file = "/etc/hostname";
		system "cp $hosts_file $hosts_file.backup";

		#/etc/hosts: insert the new first line
		system "sed '1i\ 127.0.0.1	$vmName	localhost.localdomain	localhost' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: and delete the second line (former first line)
		system "sed '2 d' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: insert the new second line
		system "sed '2i\ 127.0.1.1	$vmName' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: and delete the third line (former second line)
		system "sed '3 d' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hostname: insert the new first line
		system "sed '1i\ $vmName' $hostname_file > /tmp/hostname.tpm";
		system "mv /tmp/hostname.tpm $hostname_file";

		#/etc/hostname: and delete the second line (former first line)
		system "sed '2 d' $hostname_file > /tmp/hostname.tpm";
		system "mv /tmp/hostname.tpm $hostname_file";

		system "hostname $vmName";
		print LOG "   rebooting...\n\n";
		close LOG;
		sleep 5;
		#system "reboot";
		system "shutdown -r now '  VNX:  autoconfiguration finished...rebooting'";
		sleep 100; # wait for system to reboot
	}
	close LOG;	
	
}

#
# autoconfigure for Fedora             
#
sub autoconfigureFedora {

	my $vnxboot_file = shift;
	
	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($vnxboot_file);
	my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
	my $virtualmTagList = $globalNode->getElementsByTagName("vm");
	my $virtualmTag     = $virtualmTagList->item(0);
	my $vmName       = $virtualmTag->getAttribute("name");

	my $hostname_vm = `hostname`;
	$hostname_vm =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	$vmName =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	# If the vm doesn't have the correct name,
	# start autoconfiguration process
	if (!($hostname_vm eq $vmName)){
		print LOG "   host name ($hostname_vm) and name in vnxboot file ($vmName) are different. starting autoconfiguration...\n";

		my $ifTaglist       = $virtualmTag->getElementsByTagName("if");


		system "mv /etc/sysconfig/network /etc/sysconfig/network.bak";
		system "cat /etc/sysconfig/network.bak | grep -v 'NETWORKING=' | grep -v 'NETWORKING_IPv6=' > /etc/sysconfig/network";
		system "echo NETWORKING=yes >> /etc/sysconfig/network";
		system "echo NETWORKING_IPV6=yes >> /etc/sysconfig/network";

		# before the loop, backup /etc/udev/...70
		# and /etc/network/interfaces
		# and erase their contents
		print LOG "   configuring /etc/udev/rules.d/70-persistent-net.rules and /etc/network/interfaces...\n";
		my $rules_file = "/etc/udev/rules.d/70-persistent-net.rules";
		system "cp $rules_file $rules_file.backup";
		system "echo \"\" > $rules_file";
		open RULES, ">" . $rules_file or print "error opening $rules_file";

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
			
			print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac . 	"\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $ifName . "\"\n\n";
			#print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";

			my $ifFile = "/etc/sysconfig/network-scripts/ifcfg-Auto_$ifName";
			system "echo \"\" > $ifFile";
			open IF_FILE, ">" . $ifFile or print "error opening $ifFile";
	
			print IF_FILE "HWADDR=$mac\n";
			print IF_FILE "TYPE=Ethernet\n";
			#print IF_FILE "BOOTPROTO=none\n";
			print IF_FILE "ONBOOT=yes\n";
			print IF_FILE "NAME=\"Auto $ifName\"\n";
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
                	$mask = cidr2Mask ($mask);
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
		print LOG "   configuring ipv4 ($ipv4Forwarding) and ipv6 ($ipv6Forwarding) forwarding in /etc/sysctl.conf...\n";
		system "echo >> /etc/sysctl.conf ";
		system "echo '#### vnxdaemon ####' >> /etc/sysctl.conf ";
		system "echo 'net.ipv4.ip_forward=$ipv4Forwarding' >> /etc/sysctl.conf ";
		system "echo 'net.ipv6.conf.all.forwarding=$ipv6Forwarding' >> /etc/sysctl.conf ";

		# Configuring /etc/hosts and /etc/hostname
		print LOG "   configuring /etc/hosts and /etc/hostname...\n";
		my $hosts_file = "/etc/hosts";
		my $hostname_file = "/etc/hostname";
		system "cp $hosts_file $hosts_file.backup";

		#/etc/hosts: insert the new first line
		system "sed '1i\ 127.0.0.1	$vmName	localhost.localdomain	localhost' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: and delete the second line (former first line)
		system "sed '2 d' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: insert the new second line
		system "sed '2i\ 127.0.1.1	$vmName' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hosts: and delete the third line (former second line)
		system "sed '3 d' $hosts_file > /tmp/hosts.tmp";
		system "mv /tmp/hosts.tmp $hosts_file";

		#/etc/hostname: insert the new first line
		system "sed '1i\ $vmName' $hostname_file > /tmp/hostname.tpm";
		system "mv /tmp/hostname.tpm $hostname_file";

		#/etc/hostname: and delete the second line (former first line)
		system "sed '2 d' $hostname_file > /tmp/hostname.tpm";
		system "mv /tmp/hostname.tpm $hostname_file";

		system "hostname $vmName";
		system "mv /etc/sysconfig/network /etc/sysconfig/network.bak";
		system "cat /etc/sysconfig/network.bak | grep -v HOSTNAME > /etc/sysconfig/network";
		system "echo HOSTNAME=$vmName >> /etc/sysconfig/network";
		
		print LOG "   rebooting...\n\n";
		close LOG;
		sleep 5;
		system "reboot";
		sleep 100; # wait for system to reboot
	}
	close LOG;	
	
}

#
# autoconfigure for FreeBSD             
#
sub autoconfigureFreeBSD {
	
	my $vnxboot_file = shift;

	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	print LOG "begin of autoconfigureFreeBSD\n";
	
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($vnxboot_file);
	my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
	my $virtualmTagList = $globalNode->getElementsByTagName("vm");
	my $virtualmTag     = $virtualmTagList->item(0);
	my $vmName       = $virtualmTag->getAttribute("name");

	my $hostname_vm = `hostname -s`;
	$hostname_vm =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	$vmName =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
	# If the vm doesn't have the correct name,
	# start autoconfiguration process
	if (!($hostname_vm eq $vmName)){
		print LOG "   host name ($hostname_vm) and name in vnxboot file ($vmName) are different. starting autoconfiguration...\n";
		my $ifTaglist       = $virtualmTag->getElementsByTagName("if");

		# before the loop, backup /etc/rc.conf
		my $command;
		print LOG "   configuring /etc/rc.conf...\n";
		my $rc_file = "/etc/rc.conf";
		$command = "cp $rc_file $rc_file.backup";
		system $command;

		open RC, ">>" . $rc_file or print LOG "error opening $rc_file";

		$command = "date";
		chomp (my $now = `$command`);

		print RC "\n";
		print RC "##############################################################\n";
		print RC "## vnx autoconfiguration ($now)     ##\n";
		print RC "##############################################################\n";
		print RC "\n";

		print RC "hostname=\"$vmName\"\n";
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
			print LOG "   configuring ipv4 forwarding...\n";
			print RC "gateway_enable=\"YES\"\n";
		}
		if ($ipv6Forwarding == 1) {
			print LOG "   configuring ipv6 forwarding...\n";
			print RC "ipv6_gateway_enable=\"YES\"\n";
		}
		
		# Configuring /etc/hosts and /etc/hostname
		print LOG "   configuring /etc/hosts\n";
		my $hosts_file = "/etc/hosts";
		$command = "cp $hosts_file $hosts_file.backup";
		system $command;

		system "echo '127.0.0.1	$vmName	localhost.localdomain	localhost' > /etc/hosts";
		system "echo '127.0.1.1	$vmName' >> /etc/hosts";

		#/etc/hosts: insert the new first line
#		system "sed '1i\ 127.0.0.1	$vmName	localhost.localdomain	localhost' $hosts_file > /tmp/hosts.tmp";
#		system "mv /tmp/hosts.tmp $hosts_file";
#	
#		#/etc/hosts: and delete the second line (former first line)
#		system "sed '2 d' $hosts_file > /tmp/hosts.tmp";
#		system "mv /tmp/hosts.tmp $hosts_file";
#	
#		#/etc/hosts: insert the new second line
#		system "sed '2i\ 127.0.1.1	$vmName' $hosts_file > /tmp/hosts.tmp";
#		system "mv /tmp/hosts.tmp $hosts_file";
#	
#		#/etc/hosts: and delete the third line (former second line)
#		system "sed '3 d' $hosts_file > /tmp/hosts.tmp";
#		system "mv /tmp/hosts.tmp $hosts_file";

		system "hostname $vmName";
		print LOG "   rebooting...\n\n";
		close LOG;
		sleep 5;
		system "reboot";
		sleep 100; # wait for system to reboot
	}
	close LOG;
	
}



################ filetree processing ################

sub filetree {
	my $path = shift;

	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	my $filetree_file = $path . "/command.xml";
	my @files_array = <$path/*>;
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($filetree_file);
	my $globalNode   = $dom->getElementsByTagName("command")->item(0);
	my $filetreeTagList = $globalNode->getElementsByTagName("filetree");
	my $numfiletree        = $filetreeTagList->getLength;
	for (my $j = 0 ; $j < $numfiletree ; $j++){
		my $filetreeTag     = $filetreeTagList->item(0);
		my $seq       = $filetreeTag->getAttribute("seq");
		my $root       = $filetreeTag->getAttribute("root");
		my $folder = $j + 1;
		my $source_path = $path . "/destination/" . $folder . "/*";
		unless (-d $root){
			print LOG "   creating unexisting dir '$root'...\n";
			system "mkdir -p $root";
		}
		print LOG "   executing 'cp -R $source_path $root'...\n";
		system "cp -R $source_path $root";
			
	}
}

#
# Detects which OS, release, distribution name, etc 
# This is an improved adaptation to perl the script found here: 
#   http://www.unix.com/unix-advanced-expert-users/21468-machine.html?t=21468#post83185
#
# Output examples:
#     Linux,Ubuntu,10.04,lucid,2.6.32-28-generic,x86_64
#	  Linux,Fedora,14,Laughlin,2.6.35.11-83.fc14.i386,i386
#     FreeBSD,FreeBSD,8.1,,,i386
#
sub getOSDistro {

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
sub cidr2Mask {

  my $len=shift;
  my $dec32=2 ** 32;
  # decimal equivalent
  my $dec=$dec32 - ( 2 ** (32-$len));
  # netmask in dotted decimal
  my $mask= join '.', unpack 'C4', pack 'N', $dec;
  return $mask;
}


1;