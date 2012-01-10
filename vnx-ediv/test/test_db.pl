#!/usr/bin/perl

# Test database query routines

use strict;
use warnings;
use DBI;                                # Module to handle databases
use VNX::ClusterConfig;
use Data::Dumper;

$cluster_conf_file = "/etc/ediv/cluster.conf";

print "-----------------------------------------------\n";
print "Testing database queries\n\n";
print "Config file = $cluster_conf_file\n";


if (my $res = read_cluster_config) { 
    print "ERROR: $res\n";  
    exit 1; 
}

my $query;
my @response;
my $error;

$query = "INSERT INTO simulations VALUES ('example','7','22')";
print "\n-------------------------------------------\nQuery = $query\n";
$error = query_db ($query);
if ($error) { die "** $error" }

#$query = "SELECT `name`,`automac_offset`,`mgnet_offset` FROM simulations";
$query = "SELECT * FROM simulations";
print "\n-------------------------------------------\nQuery = $query\n";
$error = query_db ($query, \@response);
if ($error) { die "** $error" }

# Response comes in a two dimensional array 

# print it with Dumper
print "\n-------------------------------------------\nResponse:\n" 
      . Dumper(@response) . "\n";

# one way of walking through the array 
print "\n-------------------------------------------\nResponse:\n"; 
print "Number of rows=" . @response . "\n";
foreach my $row (@response) {
	print "Row:  ";
    foreach my $field (@$row) {
        if (defined($field)) { print $field . " "} else {print "undefined "; }
    }
    print "\n";
}

# another way...
print "\n-------------------------------------------\nResponse:\n";
print "Number of rows=" . @response . "\n";
for (my $i=0; $i < @response; $i++) {
    print "Row $i: ";
    my $row = $response[$i];
    #print "(@row):";
    for (my $j=0; $j < @$row; $j++) {
        #print "  $response[$i][$j],";
        if (defined($$row[$j])) { print $$row[$j] . " "} else {print "undefined "; }
    }
    print "\n";
}

$query = "DELETE FROM simulations WHERE name = 'example'";
print "\n-------------------------------------------\nQuery = $query\n";
$error = query_db ($query);
if ($error) { die "** $error" }

@response = ();
#$query = "SELECT `name` FROM simulations";
$query = "SELECT * FROM simulations";
print "\n-------------------------------------------\nQuery = $query\n";
$error = query_db ($query, \@response);
if ($error) { die "** $error" }

print "\n-------------------------------------------\nResponse:\n" 
      . Dumper(@response) . "\n";

print "\n-------------------------------------------\nResponse:\n"
      . $response[0]->[0] . "\n" . $response[0]->[1] . "\n" . $response[0]->[2] . "\n";

print "\n";

sub query_db {
    
    my $query_string = shift;
    my $ref_response = shift;
    my $error;
    
    my $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass}) 
       or return "DB ERROR: Cannot connect to database. " . DBI->errstr;
    my $query = $dbh->prepare($query_string) 
       or return "DB ERROR: Cannot prepare query to database. " . DBI->errstr;
    $query->execute()
       or return "DB ERROR: Cannot execute query to database. " . DBI->errstr;

    if (defined($ref_response)) {
        while (my @row = $query->fetchrow_array()) {
            push (@$ref_response, \@row)
        }
    }
    $query->finish();
    $dbh->disconnect;

    return '';

}