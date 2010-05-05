#!/usr/bin/perl

use strict;
use POSIX;
use Sys::Syslog;
use XML::DOM;

# Fork
my $pid = fork;
exit if $pid;
die "Couldn't fork: $!" unless defined($pid);

# Convertirse en líder de sesiónº
setsid();

# Cerrar descriptores  (comentados para ver mensajes de pruebas,descomentar)
#close(STDERR);
#close(STDOUT);
#close(STDIN);

# Umask
umask(027);

# Ejecutar en /
chdir("/");



#
#my $count = 0;
my $command;
#my $i = 0;

print "ejecutando touch\n";
$command = "touch /home/vnx/Desktop/hola.txt";
system $command;

#recorrer cederrón buscando vnxboot y abrirlo
print "reading cdroms...\n";
#my @files = </media/*>;
my $vnxboot_file;
#foreach my $file (@files){
#	print "searching in $file...\n";
#	my @files2 = <$file/*>;
#	foreach my $file2 (@files2){
#	if (!($file2 eq "$file/vnxboot")){
#		print "$file2 is not vnx boot file, next.\n";
#		next;
#	}
#	print "$file2 found!\n";
#	$vnxboot_file = $file2;
#	last;
#	}
#}

$vnxboot_file = "/home/vnx/Desktop/vnxboot";


my $parser       = new XML::DOM::Parser;
my $dom          = $parser->parsefile($vnxboot_file);
my $globalNode   = $dom->getElementsByTagName("create_conf")->item(0);
my $virtualmTagList = $globalNode->getElementsByTagName("vm");
my $virtualmTag     = $virtualmTagList->item($0);
my $vmName       = $virtualmTag->getAttribute("name");

my $hostname_vm = `hostname`;

# If the vm doesn't have the correct name,
# start autoconfiguration process

if (!($hostname_vm eq $vmName)){

	my $ifTaglist       = $virtualmTag->getElementsByTagName("if");

	# antes del bucle abrimos /etc/udev/...70
	# y /etc/network/interfaces
	# y borramos su contenido (?)
	my $command;
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
		my $ipv4Taglist = $ifTag->getElementsByTagName("ipv4");
		my $ipv4Tag = $ipv4Taglist->item(0);
		my $mask    = $ipv4Tag->getAttribute("mask");
		my $ip    = $ipv4Tag->getFirstChild->getData;

		print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac . "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"eth" . $id . "\"\n\n";
		print INTERFACES "iface eth" . $id . "inet static\n";
		print INTERFACES "   address " . $ip . "\n";
		print INTERFACES "   netmask " . $mask . "\n";

	}

	my $routeTaglist       = $virtualmTag->getElementsByTagName("route");
	my $routeTag = $routeTaglist->item(0);
	my $route_type    = $routeTag->getAttribute("type");
	my $route_gw    = $routeTag->getAttribute("gw");
	my $route    = $routeTag->getFirstChild->getData;
	print INTERFACES "up route add default gw  " . $route . "\n";
	close RULES;
	close INTERFACES;

	#salvar y cerrar ambos ficheros

	$command = "hostname $vmName";
	system $command;
	my $hosts_file = "/etc/hosts";
	$command = "cp $hosts_file $hosts_file.backup";
	system $command;
	#dangerous!
	#	   $command = "sed \"s/$hostname_vm/$vmName/g $hosts_file > tmp\"";
	#	   system $command;
	#	   $command = "mv tmp $hosts_file";
	#	   system $command;

	#sed '2i\ hola' hostz
	#sed '3 d' hostz

	#insert the new second line
	$command = "sed '2i\127.0.1.1	$vmName' $hosts_file";
	system $command;
	#and delete the third line (former second line)
	$command = "sed '3 d' $hosts_file";
	system $command;
	$command = "shutdown -r now";
	system $command;
   	
}else{
	# command execution
	
	
	
}
   
   

1;




#while (1)
#        {
#        $i++;
#        $command = "echo " . $i . " >" . " ~/Desktop/file";
#        system $command;
##        my $msg = sprintf ("He contado hasta %d", ++$count);
##        openlog('triviald', 'pid', 'user');
##        syslog('info', $msg);
#        sleep(5);
#        }