#!/usr/bin/perl

# vnx_update_aced
#
# This file is a module part of VNX package.
#
# Author: Jorge Somavilla, David Fernández (david@dit.upm.es)
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

# vnx_update_aced script allows to automatically update the ACE daemons in rootfile systems 

use strict;
use POSIX;
use Sys::Syslog;
#use XML::DOM;
use Cwd qw(cwd getcwd abs_path);
use File::Basename;
   

my $vmName = shift;
my $aceTarFile = shift;

if ($vmName eq ""){
   print " Usage (as root): vnx_update_aced <vm_name> [<aced_tar_file>]\n";
   exit(1);
}

my $curDir=getcwd();
print "-- Current dir=$curDir\n";
my $vnxBinDir = dirname ( abs_path($0) );
print "-- VNX bin dir=$vnxBinDir\n";

if ($aceTarFile eq ""){
	# ACE tar file not specified: we use the latest version found in vnx/aced directory
	my $aceDir = abs_path( "$vnxBinDir/../aced/" );
 	my @files = <$aceDir/vnx-aced-lf-*>; 
	@files = reverse sort @files;
	$aceTarFile = $files[0];
	if ($aceTarFile eq ""){
		print "\n-- ERROR: ACE tar file not specified and no ACE tar files found in $aceDir\n\n";
	}
} else {
	my $absFName = abs_path($aceTarFile);
	if (! -e $absFName) {
		print "\n-- ERROR: ACE tar file ($aceTarFile) not found\n\n";
		exit (1);
	} else {
		$aceTarFile = $absFName;
	}
}

print "-- ACE tar file=$aceTarFile\n";

print "\n-- Updating VNX daemon in virtual machine '$vmName'...\n\n";

my $tmpdir = `mktemp -td vnx_update_daemon.XXXXXX`;
chomp ($tmpdir);
print "-- Creating temp directory ($tmpdir)...\n";

system "mkdir $tmpdir/iso-content";
my $tmpisodir="$tmpdir/iso-content";
print "-- Creating iso-content temp directory ($tmpisodir)...\n";

my $fileid = $vmName . "-" . &generate_random_string(6);

my $line = "<vnx_update><id>$fileid</id></vnx_update>";
my $command = "echo \'" . $line . "\' > $tmpisodir/vnx_update.xml";
print "-- Creating vnx_update.xml file...\n";
print "--    $line\n";
system $command;

print "-- Creating $aceTarFile tar file...\n";
system "tar xfvz $aceTarFile -C $tmpisodir --strip-components=1";

print "-- Creating iso filesystem...\n";
print "--    mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet " .
       " -allow-lowercase -allow-multidot -d -o $tmpdir/vnx_update.iso $tmpisodir\n";
system "mkisofs -nobak -follow-links -max-iso9660-filename -allow-leading-dots -pad -quiet " .
       " -allow-lowercase -allow-multidot -d -o $tmpdir/vnx_update.iso $tmpisodir";
#print "--   rm -rf $tmpisodir\n";
system "rm -rf $tmpisodir";

print "-- Attaching cdrom to $vmName virtual machine...\n";
# DFC 12/7/2011: option "--driver file" eliminated to make it work with libvirt 0.9.3
print "--   virsh -c qemu:///system 'attach-disk \"$vmName\" $tmpdir/vnx_update.iso" .
      "  hdb --mode readonly --type cdrom'\n";
system "virsh -c qemu:///system 'attach-disk \"$vmName\" $tmpdir/vnx_update.iso " . 
      "hdb --mode readonly --type cdrom'";

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
