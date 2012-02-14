#!/usr/bin/perl

# Test for the VNX::ClusterConfig module

use VNX::ClusterMgmt;

my $cluster_conf_file = "/etc/ediv/cluster.conf";

print "--------------------------------------------------------------------\n";
print "Testing VNX::ClusterConfig module\n\n";
print "Config file = $cluster_conf_file\n";

# Read and parse cluster config
my $date = `date`; chomp($date); print $date . ":    Calling read_cluster_config...\n";
if (my $res = read_cluster_config($cluster_conf_file)) { 
	print "ERROR: $res\n";	
	exit 1; 
}
$date = `date`; chomp($date); print $date . ":    ...done\n";

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
    print "    host_id="    . $cluster->{hosts}{$host}->host_id . "\n";
    print "    status="    .  $cluster->{hosts}{$host}->status . "\n";
	print "    host_name="  . $cluster->{hosts}{$host}->host_name . "\n";
	print "    ip_address=" . $cluster->{hosts}{$host}->ip_address . "\n";
	print "    mem="        . $cluster->{hosts}{$host}->mem . "\n";
	print "    cpu="        . $cluster->{hosts}{$host}->cpu . "\n";
	print "    max_vms="    . $cluster->{hosts}{$host}->max_vms . "\n";
    print "    ifname="     . $cluster->{hosts}{$host}->if_name . "\n";
    print "    vnx_dir="    . $cluster->{hosts}{$host}->vnx_dir . "\n";
    print "    hypervisor=" . $cluster->{hosts}{$host}->hypervisor . "\n";
    print "    server_id="  . $cluster->{hosts}{$host}->server_id . "\n";
	
}

# Print host data of all hosts in a list (useful for ediv_monitor) 
my @host_list = qw(calamar chopito);

print "\nData of host in list: @host_list\n";

foreach $host (@host_list) {
	if (defined( $cluster->{hosts}{calamar})) {
        print_host ($cluster->{hosts}{$host});
	} else {
		print "$host does not belong to cluster\n"		
	}
}

for (my $i = 0; $i < @cluster_hosts; $i++) {
	print "\nhost_name="  . $cluster->{hosts}{$cluster_hosts[$i]}->host_name . "\n";
}

print "--------------------------------------------------------------------\n";

sub print_host {

    my $host_record = shift;

    print "\nData of $host host:\n";
    print "    host_id="    . $host_record->host_id . "\n";
    print "    status="    .  $host_record->status . "\n";
    print "    host_name="  . $host_record->host_name . "\n";
    print "    ip_address=" . $host_record->ip_address . "\n";
    print "    mem="        . $host_record->mem . "\n";
    print "    cpu="        . $host_record->cpu . "\n";
    print "    max_vms="    . $host_record->max_vms . "\n";
    print "    ifname="     . $host_record->if_name . "\n";
    print "    vnx_dir="    . $host_record->vnx_dir . "\n";    
    print "    hypervisor=" . $host_record->hypervisor . "\n";    
    print "    server_id="  . $host_record->server_id . "\n";    
}
