#!/usr/bin/perl

use strict;
use POSIX;
use Sys::Syslog;
use XML::DOM;


my $name = shift;
my $seq = shift;
my $mode = shift;


if ($name eq ""|$seq eq ""|$mode eq ""){
   print "usage (as root): send_command.pl <vm name> '<command seq>' <mode> \n";
   exit(1);
}

print "\nsending command '$seq' in mode '$mode' to vm '$name'...\n\n";


my $fileid = $name . "-" . &generate_random_string(6);

my $line = "<command><id>$fileid</id><exec mode=" . "\"" . $mode. "\"" . ">$seq</exec></command>";
my $comando = "echo \'" . $line . "\' > /tmp/command.xml";
print "> " . $comando . "\n";
system $comando;

print "> mkdir /tmp/vnx_temp_command_dir\n";
system "mkdir /tmp/vnx_temp_command_dir";

print "> mv /tmp/command.xml /tmp/vnx_temp_command_dir\n";
system "mv /tmp/command.xml /tmp/vnx_temp_command_dir";

print "> mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/vnx_temp_command.iso /tmp/vnx_temp_command_dir/\n";
system "mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet -allow-lowercase -allow-multidot -o /tmp/vnx_temp_command.iso /tmp/vnx_temp_command_dir/";

print "> virsh -c qemu:///system 'attach-disk \"$name\" /tmp/vnx_temp_command.iso hdb --mode readonly --driver file --type cdrom'\n";
system "virsh -c qemu:///system 'attach-disk \"$name\" /tmp/vnx_temp_command.iso hdb --mode readonly --driver file --type cdrom'";

#my $x = <STDIN>;
             
print "> rm -rf /tmp/vnx_temp_command*\n";
system "rm -rf /tmp/vnx_temp_command*";

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