#!/usr/bin/perl

use IO::Socket::UNIX qw( SOCK_STREAM );

sub readResponse;

my $socket_path = '/tmp/socket000';
#my $socket_path = '/root/.vnx/scenarios/simple_juniper/vms/juniper/juniper_socket';
	
my $socket = IO::Socket::UNIX->new(
   Type => SOCK_STREAM,
   Peer => $socket_path,
)
   or die("Can't connect to server: $!\n");

# The shared file system has to be created before starting 
# the virtual machine with the following sentences
# system "qemu-img create jconfig.img 12M";
# system "mkfs.msdos jconfig.img"; 

print "----------------------------\n";
my $i = 0;
while (1) {


        print "\nMenu:\n";
        print " 1 - show interfaces\n";
        print " 2 - set interface fxp0\n";
        print " 3 - override config\n";
        print " 4 - filetree\n";
        print " 5 - multiple commands\n";
        print " 6 - unknown command\n";
        print "\nChoose command:\n";
	$option =  <STDIN>;
	if ($option == 1) {
		system "mount -o loop jconfig.img /mnt/";
		#system "cp config/juniper.conf /mnt/";
		system "cp comandos/command-show.xml /mnt/command.xml";
		system "umount /mnt";
		print "Cmd sent: exeCommand\n";
		print $socket "exeCommand\n";
		readResponse ($socket);
        } 
	elsif ($option == 2) {
		system "mount -o loop jconfig.img /mnt/";
		#system "cp config/juniper.conf /mnt/";
		system "cp comandos/command-set.xml /mnt/command.xml";
		system "umount /mnt";
		print "Cmd sent: exeCommand\n";
		print $socket "exeCommand\n";
		readResponse ($socket);
	}
	elsif ($option == 3) {
		system "mount -o loop jconfig.img /mnt/";
		system "cp config/juniper.conf /mnt/";
		system "cp comandos/command-load.xml /mnt/command.xml";
		system "umount /mnt";
		print "Cmd sent: exeCommand\n";
		print $socket "exeCommand\n";
		readResponse ($socket);
	}
	elsif ($option == 4) {
		system "mount -o loop jconfig.img /mnt/";
		system "cp comandos/command-filetree.xml /mnt/command.xml";
                system "mkdir -p /mnt/destination/1";
		system "cp -r config/* /mnt/destination/1";
		system "umount /mnt";
		print "Cmd sent: exeCommand\n";
		print $socket "exeCommand\n";
		readResponse ($socket);
	}
	elsif ($option == 5) {
		system "mount -o loop jconfig.img /mnt/";
		system "cp config/juniper.conf /mnt/";
		system "cp comandos/commands.xml /mnt/command.xml";
		system "umount /mnt";
		print "Cmd sent: exeCommand\n";
		print $socket "exeCommand\n";
		readResponse ($socket);
	}
	elsif ($option == 6) {
		print "Cmd sent: kk\n";
		print $socket "kk\n";
		readResponse ($socket);
	}
        else {
		print "ERROR\n";
	}

}
$socket->close();

sub readResponse 
{
	my $socket = shift;
        #print "readResponse\n";
	while (1) {
		my $line = <$socket>;
		#chomp ($line);		
		print "** $line";
		last if ( ( $line =~ /^OK/) || ( $line =~ /^NOTOK/) );
	}

	print "----------------------------\n";

}
