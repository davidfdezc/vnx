#!/usr/bin/perl

use strict;
use POSIX;
use Sys::Syslog;
#use XML::DOM;
use Cwd;

    

my $name = shift;
my $acetarfile = shift;

if ($name eq ""){
   print " Usage (as root): vnx_update_aced <vm_name> [<aced_tar_file>]\n";
   exit(1);
}

# Move to the upper directory where this script is
$0 =~ /(.*)\// and chdir "$1/..";
my $vnxdir=`pwd`;
chomp ($vnxdir);
print "-- Current dir=$vnxdir\n";

print "\n-- Updating VNX daemon in virtual machine '$name'...\n\n";

#chdir ("ace");
#system "pwd";

my $tmpdir = `mktemp -td vnx_update_daemon.XXXXXX`;
chomp ($tmpdir);
print "-- Creating temp directory ($tmpdir)...\n";

# system "mkdir /tmp/vnx_temp_update_dir";
system "mkdir $tmpdir/iso-content";
my $tmpisodir="$tmpdir/iso-content";
print "-- iso-content temp directory ($tmpisodir)...\n";

my $fileid = $name . "-" . &generate_random_string(6);

my $line = "<vnx_update><id>$fileid</id></vnx_update>";
my $command = "echo \'" . $line . "\' > $tmpisodir/vnx_update.xml";
print "> " . $command . "\n";
system $command;

#print "> mv /tmp/vnx_update.xml /tmp/vnx_temp_update_dir\n";
#system "mv /tmp/vnx_update.xml /tmp/vnx_temp_update_dir";

if ($acetarfile eq ""){
	my $acetarfile=`ls $vnxdir/ace/vnx-ace-lf-*.tgz`; 
	chomp ($acetarfile);
}
print "-- acetarfile ($acetarfile)...\n";

system "tar xfvz $acetarfile -C $tmpisodir --strip-components=1";

#print "> cp -r ../../vnx-autoconf/open-source/* /tmp/vnx_temp_update_dir\n";
#system "cp -r ../../vnx-autoconf/open-source/* /tmp/vnx_temp_update_dir";

print "mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet " .
       " -allow-lowercase -allow-multidot -d -o $tmpdir/vnx_update.iso $tmpisodir\n";
system "mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet " .
       " -allow-lowercase -allow-multidot -d -o $tmpdir/vnx_update.iso $tmpisodir";
print "-- rm -rf $tmpisodir\n";
system "rm -rf $tmpisodir";


print "> virsh -c qemu:///system 'attach-disk \"$name\" $tmpdir/vnx_update.iso" .
      "  hdb --mode readonly --driver file --type cdrom'\n";
system "virsh -c qemu:///system 'attach-disk \"$name\" $tmpdir/vnx_update.iso " . 
      "hdb --mode readonly --driver file --type cdrom'";

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
