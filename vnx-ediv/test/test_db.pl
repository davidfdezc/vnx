#!/usr/bin/perl

# Test database query routines

use strict;
use warnings;
use DBI;                                # Module to handle databases
use VNX::ClusterConfig;
use Data::Dumper;

$cluster_conf_file = "/etc/ediv/cluster.conf";

print "--------------------------------------------------------------------\n";
print "Testing database queries\n\n";
print "Config file = $cluster_conf_file\n";


if (my $res = read_cluster_config) { 
    print "ERROR: $res\n";  
    exit 1; 
}

my $query;
my @response;

$query = "INSERT INTO simulations VALUES ('example','7','22')";
print "\nQuery = $query\n";
query_db ($query);

#$query = "SELECT `name`,`automac_offset`,`mgnet_offset` FROM simulations";
$query = "SELECT * FROM simulations";
print "\nQuery = $query\n";
query_db ($query, \@response);
print "\nResponse=\n" . Dumper(@response) . "\n";

foreach my $row (@response) {
    foreach my $element (@$row) {
        print $element, "\n";
    }
}

print "Number of rows=" . @response . "\n";
for (my $i=0; $i < @response; $i++) {
    print "Response $i ";
    my $row = $response[$i];
    #print "(@row):";
    for (my $j=0; $j < @$row; $j++) {
        #print "  $response[$i][$j],";
        print "  $$row[$j],";
    }
    print "\n";
}

$query = "DELETE FROM simulations WHERE name = 'example'";
print "\nQuery = $query\n";
query_db ($query);

undef @response;
#$query = "SELECT `name` FROM simulations";
$query = "SELECT * FROM simulations";
print "\nQuery = $query\n";
query_db ($query, \@response);

print "Number of rows=" . $#response . "\n";
for (my $i=0; $i <= $#response; $i++) {
    print "Response $i: ";
    my @row = $response[$i];
    for (my $j=0; $j < @row; $j++) {
        #print "  $response[$i][$j],";
        print "  $row[$j],";
    }
    print "\n";
}

print "\n";

sub query_db {
    
    my $query_string = shift;
    my $ref_response = shift;
    
    my $dbh = DBI->connect($db->{conn_info},$db->{user},$db->{pass}) or die "Cannot connect to database" . DBI->errstr;
    my $query = $dbh->prepare($query_string);
    $query->execute();

    if (defined($ref_response)) {
        #my @response=@$ref_response;
        #my $i=0;
        while (my @row = $query->fetchrow_array()) {
=BEGIN
            for (my $j=0; $j <= $#row; $j++) {
                #print '$response[$i][$j] = $row[$j]' . "\n";
                #print "value = $row[$j]\n"; 
                $$ref_response[$i][$j] = $row[$j];
                #print "value2[$i][$j] = $$ref_response[$i][$j]\n"; 
              
            }
            $i++;
=END
=cut            


        	#print "fields num = $#row\n";
        	#foreach my $v (@row) { print "value = $v, "};
            #print "\n";
            #print "resp: @row\n";
        	
            push (@$ref_response, \@row)
                    	
        }
        #print "Number of rows=" . $#response . "\n";
        
                
        #@$ref_response = $query->fetchrow_array();
    }
    #print "Number of rows=" . $#@(ref_response->) . "\n";   
    $query->finish();
    $dbh->disconnect;

}