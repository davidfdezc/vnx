#!/usr/bin/perl

use strict;
use POSIX;
use Sys::Syslog;
use XML::DOM;
use Cwd;
    

my $name = shift;
my $type = shift;


if (($name eq "")||($type eq "")){
   print " usage (as root):\n    perl update_daemon.pl <vm_name> unix\n      or\n    perl update_daemon.pl <vm_name> freebsd \n";
   exit(1);
}

print "\nupdating vnx daemon in '$name' of type '$type'...\n\n";


my $fileid = $name . "-" . &generate_random_string(6);

my $line = "<vnx_update><id>$fileid</id></vnx_update>";
my $command = "echo \'" . $line . "\' > /tmp/vnx_update.xml";
print "> " . $command . "\n";
system $command;

print "> mkdir /tmp/vnx_temp_update_dir\n";
system "mkdir /tmp/vnx_temp_update_dir";

print "> mv /tmp/vnx_update.xml /tmp/vnx_temp_update_dir\n";
system "mv /tmp/vnx_update.xml /tmp/vnx_temp_update_dir";

print "> cp -r ../../vnx-autoconf/open-source/* /tmp/vnx_temp_update_dir\n";
system "cp -r ../../vnx-autoconf/open-source/* /tmp/vnx_temp_update_dir";

print "> mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/vnx_temp_update.iso /tmp/vnx_temp_update_dir/\n";
system "mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/vnx_temp_update.iso /tmp/vnx_temp_update_dir/";

print "> virsh -c qemu:///system 'attach-disk \"$name\" /tmp/vnx_temp_update.iso hdb --mode readonly --driver file --type cdrom'\n";
system "virsh -c qemu:///system 'attach-disk \"$name\" /tmp/vnx_temp_update.iso hdb --mode readonly --driver file --type cdrom'";

#sleep 6;
#
#print "> mkdir /tmp/vnx_temp_update_dir/vnx_temp_update_empty_dir\n";
#system "mkdir /tmp/vnx_temp_update_dir/vnx_temp_update_empty_dir/";
#

# system "touch /tmp/vnx_temp_update_empty.iso";

#
#print "> mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/vnx_temp_update_empty.iso /tmp/vnx_temp_update_dir/vnx_temp_update_empty_dir/\n";
#system "mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/vnx_temp_update_empty.iso /tmp/vnx_temp_update_dir/vnx_temp_update_empty_dir/";
#
#
#print "> virsh -c qemu:///system 'attach-disk \"$name\" /tmp/vnx_temp_update_empty.iso hdb --mode readonly --driver file --type cdrom'\n";
#system "virsh -c qemu:///system 'attach-disk \"$name\" /tmp/vnx_temp_update_empty.iso hdb --mode readonly --driver file --type cdrom'";

             
print "> rm -rf /tmp/vnx_temp_update*\n";
system "rm -rf /tmp/vnx_temp_update*";

print "\n...done\n\n";
exit(0);


sub generate_random_string {
   my $length_of_randomstring=shift;#the length of the random string to generate

   my @chars=('a'..'z','A'..'Z','0'..'9','_');
   my $random_string;
   foreach (1..$length_of_randomstring) {
      #rand @chars will generate a random number between 0 and scalar@chars
      $random_string.=$chars[rand @chars];
   }
   return $random_string;
}
