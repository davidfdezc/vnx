#!/usr/bin/perl

use strict;
use POSIX;
use Sys::Syslog;
use XML::DOM;

&main;
exit(0);

sub main{
	
	my $command;
	$command = "date";
	chomp (my $now = `$command`);
	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	print LOG "\n";
	print LOG "\n";
	print LOG "################################################################\n";
	print LOG "#### vnxdaemon log started at $now ####\n";
	print LOG "################################################################\n";
	print LOG "\n";
	close LOG;
	&daemonize;
	&autoconfigure;
	&execute_commands;
}

############### daemonize process ################
sub daemonize {

	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	print LOG "## Daemonizing process ##\n";

	# Fork
	my $pid = fork;
	exit if $pid;
	die "Couldn't fork: $!" unless defined($pid);

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





############### autoconfiguration ##############

sub autoconfigure {

	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	print LOG "## Autoconfiguration ##\n";
	print LOG "\n";

	#search CD-ROMS for vnxboot file
	print LOG "Searching for configuration files in /media/...\n";
	my @files = </media/*>;
	my $vnxboot_file;
	my $continue = 1;
	my $loop_number = 0;
	while ($continue){
		$loop_number++;
		foreach my $file (@files){
#			print LOG "searching in $file...";
			my @files2 = <$file/*>;
			foreach my $file2 (@files2){
				if (!($file2 eq "$file/vnxboot")){
					next;
				}
				print LOG "-> $file2 found\n";
				$vnxboot_file = $file2;
				$continue = 0;
				last;
			}
			if ($continue eq 0){
				last;
			}
			

		}
		if ($loop_number eq 7){
			# after 30 seconds stop looking for vnxboot
			$continue = 0;
		        print LOG "-> search timeout exceeded\n";
		}else{
			sleep 5;
		}
	}



	if ($vnxboot_file eq ""){
		#if $vnxboot_file is empty, do nothing
		#(perhaps user removed the CD with the filesystem)
		print LOG "No vnxboot file found, moving to command execution...\n";
		print LOG "\n";
		close LOG;
	}
	else{
		print LOG "Parsing vnxboot file...\n";
		my $parser       = new XML::DOM::Parser;
		my $dom          = $parser->parsefile($vnxboot_file);
		my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
		my $virtualmTagList = $globalNode->getElementsByTagName("vm");
		my $virtualmTag     = $virtualmTagList->item($0);
		my $vmName       = $virtualmTag->getAttribute("name");


		my $hostname_vm = `hostname`;
		$hostname_vm =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
		$vmName =~ s/^\s*(\S*(?:\s+\S+)*)\s*$/$1/;
		print LOG "Comparing host's ($hostname_vm) and vnxboot file's ($vmName) names...\n";
		# If the vm doesn't have the correct name,
		# start autoconfiguration process
		if (!($hostname_vm eq $vmName)){
			print LOG "-> different\n";
		        print LOG "Starting autoconfiguration...\n";
			my $ifTaglist       = $virtualmTag->getElementsByTagName("if");
	
			# before the loop, backup /etc/udev/...70
			# and /etc/network/interfaces
			# and erase their contents
			my $command;
		        print LOG "Configuring /etc/udev/rules.d/70-persistent-net.rules and /etc/network/interfaces...\n";
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
					print LOG "Configuring ip forwarding in /etc/sysctl.conf...\n";
					system "echo >> /etc/sysctl.conf ";
					system "echo '#### vnxdaemon ####' >> /etc/sysctl.conf ";
					system "echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf ";
					system "echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf ";
				}
			}

		        print LOG "Configuring /etc/hosts and /etc/hostname...\n";
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
			print LOG "Rebooting...\n";
		        close LOG;
			system "reboot";
			sleep 20; # wait for system to reboot
		}
		print LOG "-> equal\n";
		print LOG "No autoconfiguration needed, moving to command execution...\n";
		print LOG "\n";
		close LOG;
	}	
}	


############### command execution ###################
sub execute_commands {

	open LOG, ">>" . "/var/log/vnxdaemon.log" or print "error opening log file";
	print LOG "## Command execution ##\n";
	print LOG "\n";
	system "umount /media/cdrom";

	print LOG "Waiting for commands...\n";
	my @files = </media/*>;
	my $commands_file;
	my $continue;
	while (1){
		$continue = 1;
		system "mount /media/cdrom";
		foreach my $file (@files){
			my @files2 = <$file/*>;
			foreach my $file2 (@files2){
				if ($file2 eq "/media/cdrom/filetree.xml"){
					my $path = $file;
					print LOG "Filetree received in $file2\n";
					&filetree($path);
					print LOG "   Sending 'done' signal to host...\n";
					system "echo 1 > /dev/ttyS0";
					$continue = 0;
					last;

				}elsif ($file2 eq "/media/cdrom/comandos.xml"){
				
					print LOG "Command received in $file2\n";
					$commands_file = $file2;
			
					print LOG "   Parsing commands file...\n";
					my $parser       = new XML::DOM::Parser;
					my $dom          = $parser->parsefile($commands_file);
					my $globalNode   = $dom->getElementsByTagName("comandos")->item(0);
					my $execTagList = $globalNode->getElementsByTagName("exec");
					my $numexec        = $execTagList->getLength;
					for (my $j = 0 ; $j < $numexec ; $j++){
						my $execTag     = $execTagList->item($0);
						my $seq       = $execTag->getAttribute("seq");
						my $type       = $execTag->getAttribute("type");
						my $mode       = $execTag->getAttribute("mode");
						my $command2    = $execTag->getFirstChild->getData;
						if ($mode eq "system"){
							print LOG "   Executing '$command2' in mode 'system'...\n";
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
							print LOG "   Executing '$command2' in mode 'processn'...\n";
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
							print LOG "   Executing '$command2' in mode 'processy'...\n";
							system $command2;
						}else{
							print LOG "   Command mode '$mode' not available...\n";
						}
					}
					print LOG "   Sending 'done' signal to host...\n";
					system "echo 1 > /dev/ttyS0";
				}else{
					# file is neither command nor filetree file
					next;
				}	
			}
			if ($continue eq 0){
				last;
			}
		}
		system "umount /media/cdrom";
		sleep 5;
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


