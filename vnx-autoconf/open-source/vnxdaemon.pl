#!/usr/bin/perl

use strict;
use POSIX;
use Sys::Syslog;
use XML::DOM;

my $platform;

sleep 15;
&main;
exit(0);

sub main{

	#detect platform (values: 'Linux', 'FreeBSD')
	my $command;
	$command = "uname";
	chomp ($platform = `$command`);
	
	# if this is the first run...
	unless (-f "/root/.vnx/LOCK"){
		# generate LOCK file
		system "mkdir -p /root/.vnx/";
		system "touch /root/.vnx/LOCK";
		# generate run dir
		#system "mkdir -p /var/run/vnxdaemon/";
		# remove residual log file
		system "rm -f /var/log/vnxdaemon.log";
		# generate new log file
		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		print LOG "\n";
		print LOG "\n";
		$command = "date";
		chomp (my $now = `$command`);
		print LOG "#########################################################################\n";
		print LOG "#### vnxdaemon log sequence started at $now  ####\n";
		print LOG "#########################################################################\n";
		print LOG "\n";
		close LOG;
	}

	if (-f "/var/run/vnxdaemon.pid"){
		system "touch /home/vnx/muero";
		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		print LOG "Another instance of vnxdaemon seems to be running, aborting execution (PID $$)\n";
		exit 1;
	}
	

	&daemonize;
	&listen;
	

}






############### daemonize process ################

sub daemonize {
		
	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
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
	close(STDERR);
	close(STDOUT);
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
	if ($platform eq 'Linux'){

		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		print LOG "## Listening ##\n\n";
		system "mkdir /root/.vnx";
		my @files = </media/*>;
		my $commands_file;
		sleep 5;
		system "mount /media/cdrom";
		while (1){
			foreach my $file (@files){
				my @files2 = <$file/*>;
				foreach my $file2 (@files2){
					if ($file2 eq "/media/cdrom/filetree.xml"){
						unless (&check_if_new_file($file2,"filetrees")){

							next;				
						}
						my $path = $file;
						print LOG "   filetree received in $file2\n";
						&filetree($path);
						print LOG "   sending 'done' signal to host...\n\n";
						system "echo 1 > /dev/ttyS0";
					}elsif ($file2 eq "/media/cdrom/command.xml"){
						unless (&check_if_new_file($file2,"command")){
							next;				
						}
						print LOG "   command received in $file2\n";
						&execute_commands($file2);
						print LOG "   sending 'done' signal to host...\n\n";
						system "echo 1 > /dev/ttyS0";
					}elsif ($file2 eq "/media/cdrom/vnxboot"){
						unless (&check_if_new_file($file2,"create_conf")){
							next;				
						}
						print LOG "   configuration file received in $file2\n";
						&autoconfigure($file2);
						print LOG "\n";
					}elsif ($file2 eq "/media/cdrom/vnx_update.xml"){
						unless (&check_if_new_file($file2,"vnx_update") eq '1'){
							next;				
						}
						print LOG "   update files received in $file2\n";
						&autoupdate;
						print LOG "\n";

					}else {
						# unknown file, do nothing
					}
				}
			}
			system "umount /media/cdrom";
			sleep 5;
			system "mount /media/cdrom";
		}

	}

	#############################
	# listen for FreeBSD        #
	#############################
	elsif ($platform eq 'FreeBSD'){
		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		print LOG "## Listening ##\n\n";
		system "mkdir /root/.vnx";
		my @files = </*>;
		my $commands_file;
		system "umount -f /cdrom";
		sleep 5;
		system "mount /cdrom";
		while (1){

			foreach my $file (@files){
				my @files2 = <$file/*>;

				foreach my $file2 (@files2){

					if ($file2 eq "/cdrom/filetree.xml"){
						unless (&check_if_new_file($file2,"filetrees")){
							next;				
						}
						my $path = $file;
						print LOG "   filetree received in $file2\n";
						&filetree($path);
						print LOG "   sending 'done' signal to host....\n\n";
						system "echo 1 > /dev/cuau0";

					}elsif ($file2 eq "/cdrom/command.xml"){
						unless (&check_if_new_file($file2,"command")){
							next;				
						}
						print LOG "   command received in $file2\n";
						&execute_commands($file2);
						print LOG "   sending 'done' signal to host...\n\n";
						system "echo 1 > /dev/cuau0";

					}elsif ($file2 eq "/cdrom/vnxboot"){
						unless (&check_if_new_file($file2,"create_conf")){
							next;				
						}
						print LOG "   configuration file received in $file2\n";
						&autoconfigure($file2);
						print LOG "\n";

					}elsif ($file2 eq "/cdrom/vnx_update.xml"){
						unless (&check_if_new_file($file2,"vnx_update") eq '1'){
							next;				
						}
						print LOG "   update files received in $file2\n";
						&autoupdate;
						print LOG "\n";

					}else {
						# unknown file, do nothing
					}
				}
			}
			system "umount -f /cdrom";
			sleep 5;
			system "mount /cdrom";
		}
	}
}


sub autoupdate {
	
	#############################
	# update for Linux          #
	#############################
	if ($platform eq 'Linux'){
		print LOG "   updating vnxdaemon for Linux\n";
		system "cp /media/cdrom/vnxdaemon.pl /etc/init.d/";
		system "cp /media/cdrom/unix/* /etc/init/";
	}
	#############################
	# update for FreeBSD        #
	#############################
	elsif ($platform eq 'FreeBSD'){
		print LOG "   updating vnxdaemon for FreeBSD\n";
		system "cp /cdrom/vnxdaemon.pl /usr/sbin/";
		system "cp /cdrom/freebsd/* /etc/rc.d/vnxdaemon";
	}
	system "rm /root/.vnx/LOCK";
	#system "reboot";
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
	my $idTag     = $idTagList->item($0);
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
	if ($platform eq 'Linux'){
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
			if ($mode eq "system"){
				print LOG "   executing: '$command2'\n   in mode: 'system'\n";
				# Fork
				my $pid2 = fork;
				die "Couldn't fork: $!" unless defined($pid2);
				if ($pid2){
					# parent does nothing
				}else{
					# child executes command and dies
					exec "xterm -display :0.0 -e $command2";
				}
				}elsif($mode eq "processn"){
					print LOG "   executing: '$command2'\n   in mode: 'processn'\n";
					# Fork
					my $pid2 = fork;
					die "Couldn't fork: $!" unless defined($pid2);
				if ($pid2){
					# parent does nothing
				}else{
					# child executes command and dies
					exec $command2;
				}
				}elsif($mode eq "processy"){
				print LOG "   executing: '$command2'\n   in mode: 'processy'\n";
				system $command2;
			}else{
				print LOG "   Command mode '$mode' not available. Aborting execution...\n";
			}
		}
	}

	#######################################
	# execute_commands for FreeBSD        #
	#######################################
	elsif ($platform eq 'FreeBSD'){
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
			if ($mode eq "system"){
				print LOG "   executing: '$command2'\n   in mode: 'system'\n";
				# Fork
				#my $pid2 = fork;
				#die "Couldn't fork: $!" unless defined($pid2);
				#if ($pid2){
					# parent does nothing
				#}else{
					# child executes command and dies
					system "su - vnx -c \"$command2\"";
					system $command2;
					system "$command2";
					system "xterm -e $command2";
					system "xterm --display:0.0 -e $command2";
					exec "xterm -e $command2";
					exec "xterm --display:0.0 -e $command2";
				#}
			}elsif($mode eq "processn"){
				print LOG "   executing: '$command2'\n   in mode: 'processn'\n";
				# Fork
				my $pid2 = fork;
				die "Couldn't fork: $!" unless defined($pid2);
				if ($pid2){
					# parent does nothing
				}else{
					# child executes command and dies
					exec $command2;
				}
			}elsif($mode eq "processy"){
				print LOG "   executing: '$command2'\n   in mode: 'processy'\n";
				system $command2;
			}else{
				print LOG "   Command mode '$mode' not available. Aborting execution...\n";
			}
		}


	}

}


############### autoconfiguration ##############

sub autoconfigure {

	my $vnxboot_file = shift;
	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";


	#######################################
	# autoconfigure for Linux             #
	#######################################
	if ($platform eq 'Linux'){
		
		#my $vnxboot_file = shift;
		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		my $parser       = new XML::DOM::Parser;
		my $dom          = $parser->parsefile($vnxboot_file);
		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
		my $virtualmTagList = $globalNode->getElementsByTagName("vm");
		my $virtualmTag     = $virtualmTagList->item($0);
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
			my $command;
			print LOG "   configuring /etc/udev/rules.d/70-persistent-net.rules and /etc/network/interfaces...\n";
			my $rules_file = "/etc/udev/rules.d/70-persistent-net.rules";
			$command = "cp $rules_file $rules_file.backup";
			system $command;
			$command = "echo \"\" > $rules_file";
			system $command;
			open RULES, ">" . $rules_file or print "error opening $rules_file";
				my $interfaces_file = "/etc/network/interfaces";
			$command = "cp $interfaces_file $interfaces_file.backup";
			system $command;
			$command = "echo \"\" > $interfaces_file";
			system $command;
			open INTERFACES, ">" . $interfaces_file or print "error opening $interfaces_file";
			print INTERFACES "\n";
			print INTERFACES "auto lo\n";
			print INTERFACES "iface lo inet loopback\n";
			my $numif        = $ifTaglist->getLength;
			for (my $j = 0 ; $j < $numif ; $j++){
				my $ifTag = $ifTaglist->item($j);
				my $id    = $ifTag->getAttribute("id");
				my $net   = $ifTag->getAttribute("net");
				my $mac   = $ifTag->getAttribute("mac");
				$mac =~ s/,//g;
				my $ipv4Taglist = $ifTag->getElementsByTagName("ipv4");
				my $ipv4Tag = $ipv4Taglist->item(0);
				my $mask    = $ipv4Tag->getAttribute("mask");
				my $ip    = $ipv4Tag->getFirstChild->getData;

				#print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac . 	"\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"eth" . $id . "\"\n\n";

				print RULES "KERNEL==\"eth*\", SYSFS{address}==\"" . $mac . "\", NAME=\"eth" . $id ."\"\n\n";

				print INTERFACES "auto eth" . $id . "\n";
				print INTERFACES "iface eth" . $id . " inet static\n";
				print INTERFACES "   address " . $ip . "\n";
				print INTERFACES "   netmask " . $mask . "\n\n";

			}

			my $routeTaglist       = $virtualmTag->getElementsByTagName("route");
			my $routeTag = $routeTaglist->item(0);
			if (defined($routeTag)){
				my $route_type    = $routeTag->getAttribute("type");
				my $route_gw    = $routeTag->getAttribute("gw");
				my $route    = $routeTag->getFirstChild->getData;
				print INTERFACES "up route add default gw " . $route_gw . "\n";
			}
	
			close RULES;
			close INTERFACES;

			my $forwardingTaglist       = $virtualmTag->getElementsByTagName("forwarding");
			my $numforwarding = $forwardingTaglist->getLength;
			if ($numforwarding eq 1){
				my $forwardingTag = $forwardingTaglist->item(0);
				my $forwarding_type    = $forwardingTag->getAttribute("type");
				if ($forwarding_type eq "ip"){
					print LOG "   configuring ip forwarding in /etc/sysctl.conf...\n";
					system "echo >> /etc/sysctl.conf ";
					system "echo '#### vnxdaemon ####' >> /etc/sysctl.conf ";
					system "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf ";
					system "echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf ";
				}
			}

			print LOG "   configuring /etc/hosts and /etc/hostname...\n";
			my $hosts_file = "/etc/hosts";
			my $hostname_file = "/etc/hostname";
			$command = "cp $hosts_file $hosts_file.backup";
			system $command;
	

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
			system "reboot";
			sleep 100; # wait for system to reboot
		}
		close LOG;

	}

	#######################################
	# autoconfigure for FreeBSD           #
	#######################################
	elsif ($platform eq 'FreeBSD'){
		#my $vnxboot_file = shift;
		open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
		my $parser       = new XML::DOM::Parser;
		my $dom          = $parser->parsefile($vnxboot_file);
		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
		my $virtualmTagList = $globalNode->getElementsByTagName("vm");
		my $virtualmTag     = $virtualmTagList->item($0);
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

			# configure network
			my $numif        = $ifTaglist->getLength;
			for (my $j = 0 ; $j < $numif ; $j++){
				my $ifTag = $ifTaglist->item($j);
				my $id    = $ifTag->getAttribute("id");
				my $net   = $ifTag->getAttribute("net");
				my $mac   = $ifTag->getAttribute("mac");
				$mac =~ s/,//g;
				my $ipv4Taglist = $ifTag->getElementsByTagName("ipv4");
				my $ipv4Tag = $ipv4Taglist->item(0);
				my $mask    = $ipv4Tag->getAttribute("mask");
				my $ip    = $ipv4Tag->getFirstChild->getData;


				print RC "ifconfig_re". $j . "_name=\"net" . $id . "\"\n";
	#			print RC "ifconfig_net" . $id . "=\"inet " . $ip . " netmask " . $mask . " ether " . $mac . "\"\n";
				print RC "ifconfig_net" . $id . "=\"inet " . $ip . " netmask " . $mask . "\"\n";
				system "echo 'ifconfig net$id ether $mask' > /etc/start_if.net$id";
			
			}
		
			my $routeTaglist       = $virtualmTag->getElementsByTagName("route");
			my $numroute        = $routeTaglist->getLength;
			my $first_no_default = 1;
			for (my $j = 0 ; $j < $numroute ; $j++){
				my $routeTag = $routeTaglist->item($j);
				if (defined($routeTag)){
					my $route_type    = $routeTag->getAttribute("type");
					my $route_gw    = $routeTag->getAttribute("gw");
					my $route    = $routeTag->getFirstChild->getData;
					if ($route eq 'default'){
						print RC "defaultrouter=\"" . $route_gw . "\"\n";
					}
					else {
						if ($first_no_default eq 1){
							print RC "static_routes=\"lan\"\n";
							$first_no_default = 0;
						}
						print RC "route_lan=\"-net " . $route . " " . $route_gw . "\"\n";
					}
				}
			
			}

			my $forwardingTaglist       = $virtualmTag->getElementsByTagName("forwarding");
			my $numforwarding = $forwardingTaglist->getLength;
			if ($numforwarding eq 1){
				my $forwardingTag = $forwardingTaglist->item(0);
				my $forwarding_type    = $forwardingTag->getAttribute("type");
				if ($forwarding_type eq "ip"){
					print LOG "   configuring ip forwarding...\n";
					print RC "gateway_enable=\"YES\"\n";
				}
			}

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
			system "reboot";
			sleep 100; # wait for system to reboot
		}
		close LOG;

	}


}



################ filetree processing ################

sub filetree {
	my $path = shift;

	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	print LOG "   Parsing filetree file...\n";
	my $filetree_file = $path . "/filetree.xml";
	my @files_array = <$path/*>;
	my $parser       = new XML::DOM::Parser;
	my $dom          = $parser->parsefile($filetree_file);
	my $globalNode   = $dom->getElementsByTagName("filetrees")->item(0);
	my $filetreeTagList = $globalNode->getElementsByTagName("filetree");
	my $numfiletree        = $filetreeTagList->getLength;
	for (my $j = 0 ; $j < $numfiletree ; $j++){
		my $filetreeTag     = $filetreeTagList->item($0);
		my $seq       = $filetreeTag->getAttribute("seq");
		my $root       = $filetreeTag->getAttribute("root");
		my $folder = $j + 1;
		my $source_path = $path . "/destination/" . $folder . "/*";
		print LOG "   Executing 'cp -R $source_path $root'...\n";
		system "cp -R $source_path $root";
			
	}
}


1;
