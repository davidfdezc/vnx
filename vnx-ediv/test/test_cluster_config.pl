#!/usr/bin/perl

# Test for the VNX::ClusterConfig module

use VNX::ClusterConfig;

$cluster_conf_file = "/etc/ediv/cluster.conf";

print "--------------------------------------------------------------------\n";
print "Testing VNX::ClusterConfig module\n\n";
print "Config file = $cluster_conf_file\n";


if (my $res = read_cluster_config) { 
	print "ERROR: $res\n";	
	exit 1; 
}

# database config
print "\nDatabase config:\n";
print "    Name: " . $db->{name} . "\n";
print "    Type: " . $db->{type} . "\n";
print "    Host: " . $db->{host} . "\n";
print "    Port: " . $db->{port} . "\n";
print "    User: " . $db->{user} . "\n";
print "    Pass: " . $db->{pass} . "\n";
print "    Conn_info: " . $db->{conn_info} . "\n";

# vlan config
print "\nVlan config:\n";
print "    First: " . $vlan->{first} . "\n";
print "    Last:  " . $vlan->{last}  . "\n";

# Print all host names
print "\nNames of hosts included in [cluster] section of $cluster_conf_file:\n";
foreach $host (keys %{ $cluster->{hosts} }) {
	print "    $host\n";
}

# 
print "\nCluster config:\n";
print "    Default seg alg="     . $cluster->{def_seg_alg} . "\n";
print "    Management Net="      . $cluster->{mgmt_network} . "\n";
print "    Management Net mask=" . $cluster->{mgmt_network_mask} . "\n";

# Access to each hosts data
foreach $host (keys %{ $cluster->{hosts} }) {
	print "\nData of $host host:\n";
	print "    host_name="  . $cluster->{hosts}{$host}->host_name . "\n";
	print "    ip_address=" . $cluster->{hosts}{$host}->ip_address . "\n";
	print "    mem="        . $cluster->{hosts}{$host}->mem . "\n";
	print "    cpu="        . $cluster->{hosts}{$host}->cpu . "\n";
	print "    max_vms="    . $cluster->{hosts}{$host}->max_vms . "\n";
	print "    ifname="     . $cluster->{hosts}{$host}->if_name . "\n";
}

# Print host data of all hosts in a list (useful for ediv_monitor) 
my @host_list = qw(calamar chopito);

print "\nData of host in list: @host_list\n";

foreach $host (@host_list) {
	if (defined( $cluster->{hosts}{calamar})) {
		print "\nData of $host:\n";
		print "    host_name="  . $cluster->{hosts}{$host}->host_name . "\n";
		print "    ip_address=" . $cluster->{hosts}{$host}->ip_address . "\n";
		print "    mem="        . $cluster->{hosts}{$host}->mem . "\n";
		print "    cpu="        . $cluster->{hosts}{$host}->cpu . "\n";
		print "    max_vms="    . $cluster->{hosts}{$host}->max_vms . "\n";
		print "    ifname="     . $cluster->{hosts}{$host}->if_name . "\n";	
	} else {
		print "$host does not belong to cluster\n"		
	}
}

for (my $i = 0; $i < @cluster_hosts; $i++) {
	print "\nhost_name="  . $cluster->{hosts}{$cluster_hosts[$i]}->host_name . "\n";
}

print "--------------------------------------------------------------------\n";


