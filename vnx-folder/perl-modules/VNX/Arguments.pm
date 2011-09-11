# Arguments.pm
#
# This file is a module part of VNX package.
#
# Author: Fermin Galan Marquez (galan@dit.upm.es)
# Copyright (C) 2005, 	DIT-UPM
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

# Arguments class implementation. The instance of Arguments encapsulates 
# the main program arguments

package VNX::Arguments;

use strict;
use warnings;

###########################################################################
# CLASS CONSTRUCTOR
#
# Arguments (apart from the firts one, the class itseft): the different
# arguments of the main program.
#
sub new {
    my $class = shift;
    my $self = {};
    bless $self;

    $self->{'define'}       = shift;
    $self->{'undefine'}     = shift;
    $self->{'start'}        = shift;
    $self->{'create'}       = shift;
    $self->{'shutdown'}     = shift;
    $self->{'destroy'}      = shift;
    $self->{'save'}         = shift;
    $self->{'restore'}      = shift;
    $self->{'suspend'}      = shift;
    $self->{'resume'}       = shift;
    $self->{'reboot'}       = shift;
    $self->{'reset'}        = shift;
    $self->{'execute'}      = shift;
    $self->{'show-map'}     = shift;
    $self->{'console'}      = shift;
    $self->{'console-info'} = shift;
    $self->{'exe-info'}     = shift;
    $self->{'help'}         = shift;

    $self->{'f'}      = shift;
    $self->{'c'}      = shift;
    $self->{'T'}      = shift;   
    $self->{'config'} = shift;
    $self->{'v'}      = shift;   
    $self->{'vv'}     = shift;   
    $self->{'vvv'}    = shift;   
    $self->{'V'}      = shift;
    $self->{'M'}      = shift;
    $self->{'i'}      = shift;
    $self->{'g'}      = shift;
    $self->{'u'}      = shift;
    $self->{'4'}      = shift;
    $self->{'6'}      = shift;   
    $self->{'cid'}    = shift;
    $self->{'D'}      = shift;
    $self->{'n'}      = shift;
    $self->{'y'}      = shift;
   
    $self->{'e'} = shift;
    $self->{'w'} = shift;
    $self->{'F'} = shift;
    $self->{'B'} = shift;
    $self->{'o'} = shift;
    $self->{'Z'} = shift;

    return $self;
}

# get
#
# Gets the given argument
#
sub get {
	my $self = shift;
	my $arg = shift;
	return $self->{$arg};
}

# set
#
# Set the given argument
#
sub set {
	my $self = shift;
	my $arg = shift;
	my $value = shift;
	$self->{$arg} = $value;
}

1;