#!/usr/bin/perl -w
#
#	DFC Modification: it does not return the "ip6.int" in order to be usable for ip6.arpa also
#
#       Convert valid IPv6 address to ip6.int PTR value.  Convert valid
#       IPv4 address to in-addr.arpa PTR value.  Anything not valid is
#       simply printed as is.  Handles :: notation and embedded IPv4
#       addresses.  If the address is followed by /n, the PTR is
#       truncated to n bits.
#
#       Examples:
#               nslookup -type=any `ip6_int 3ffe::203.34.97.6` looks up
# 6.0.1.6.2.2.b.c.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.e.f.f.3.ip6.int
#               nslookup -type=any `ip6_int fe80::b432:e6ff/10` looks up
# 2.e.f.ip6.int
#               nslookup -type=any `ip6_int ::127.0.0.1` looks up
# 1.0.0.0.0.0.f.7.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.int
#               nslookup -type=any `ip6_int 127.0.0.1` looks up
# 1.0.0.127.in-addr.arpa
#               nslookup -type=any `ip6_int 127.0.0.1/8` looks up
# 127.in-addr.arpa
#
#       Copyright 1997 Keith Owens <kaos@ocs.com.au>.  GPL.
#

require 5;
use strict;
use integer;

my $v6;

if ($#ARGV >= 0 &&
    ($v6 = ($ARGV[0] =~ m;^([0-9a-fA-f:]+)(?::(\d+\.\d+\.\d+\.\d+))?(?:/(\d+))?$;))
     || $ARGV[0] =~ m;^(\d+\.\d+\.\d+\.\d+)(?:/(\d+))?$;) {
	my $valid = 1;
	if ($v6) {
		my (@chunk) = split(/:/, $1, 99);
		my $mask = $3;
		if ($2) {
			my (@v4) = split(/\./, $2);
			$valid = ($v4[0] <= 255 && $v4[1] <= 255 &&
			          $v4[2] <= 255 && $v4[3] <= 255);
			if ($valid) {
				push(@chunk, sprintf("%x%02x", $v4[0], $v4[1]));
				push(@chunk, sprintf("%x%02x", $v4[2], $v4[3]));
			}
		}
		my $pattern = "";
		if ($valid) {
			foreach (@chunk) {
				$pattern .= /^$/ ? 'b' : 'c';
			}
			if ($pattern =~ /^bbc+$/) {
				@chunk = (0, 0, @chunk[2..$#chunk]);
				@chunk = (0, @chunk) while ($#chunk < 7);
			}
			elsif ($pattern =~ /^c+bb$/) {
				@chunk = (@chunk[0..$#chunk-2], 0, 0);
				push(@chunk, 0) while ($#chunk < 7);
			}
			elsif ($pattern =~ /^c+bc+$/) {
				my @left;
				push(@left, shift(@chunk)) while ($chunk[0] ne "");
				shift(@chunk);
				push(@left, 0);
				push(@left, 0) while (($#left + $#chunk) < 6);
				@chunk = (@left, @chunk);
			}
			$valid = $#chunk == 7;
		}
		my $ip6int = "";  # DFC
		#my $ip6int = "ip6.int";
		my $i;
		if ($valid) {
			foreach (@chunk) {
				$i = hex($_);
				if ($i > 65535) {
					$valid = 0;
				}
				else {
					$ip6int = sprintf("%x.%x.%x.%x.",
							  ($i) & 0xf,
							  ($i >> 4) & 0xf,
							  ($i >> 8) & 0xf,
							  ($i >> 12) & 0xf)
						  . $ip6int;
				}
			}
		}
		if ($valid && defined($mask)) {
			$valid = ($mask =~ /^\d+$/ && $mask <= 128);
			if ($valid) {
				$ip6int = substr($ip6int, int((128-$mask)/4)*2);
				if ($mask &= 3) {
					$i = hex(substr($ip6int, 0, 1));
					$i >>= (4-$mask);
					substr($ip6int, 0, 1) = sprintf("%x", $i);
				}
			}
		}
		$ARGV[0] = $ip6int if ($valid);
	}
	else {
		# v4
		my (@v4) = split(/\./, $1);
		my $mask = $2;
		$valid = ($v4[0] <= 255 && $v4[1] <= 255 &&
			  $v4[2] <= 255 && $v4[3] <= 255);
		my $v4 = hex(sprintf("%02X%02X%02X%02X", @v4));
		if ($valid && defined($mask)) {
			$valid = ($mask =~ /^\d+$/ && $mask <= 32);
			if ($valid) {
				$v4 = $v4 & ((~0) << (32-$mask));
				$v4[0] = ($v4 >> 24) & 255;
				$v4[1] = ($v4 >> 16) & 255;
				$v4[2] = ($v4 >> 8) & 255;
				$v4[3] = $v4 & 255;
			}
		}
		else {
			$mask = 32;
		}
		if ($valid) {
			my $i = 4 - int(($mask+7) / 8);
			pop(@v4) while ($i--);
			$ARGV[0] = join('.', reverse(@v4));
			$ARGV[0] .= '.' if ($ARGV[0] ne "");
			$ARGV[0] .= 'in-addr.arpa';
		}
	}
}
print "@ARGV";

