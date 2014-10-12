#!/bin/bash

# vnx_clone_scenario
#
# Simple script to clone a VNX scenario by changing the names of VM, net and scenario by adding a user defined
# prefix. It also changes the vm_mgmt network prefix to avoid overlaping among management IP addresses.
#
# Usage: 

USAGE="vnx_clone_scenario: simple script to clone a VNX scenario by changing 
                    the names of VM, net and scenario by adding a user 
                    defined prefix. It also changes the vm_mgmt network 
                    prefix to avoid overlaping among management IP addresses.

Usage:  vnx_clone_scenario <prefix> <scenario_file>
"

if [ $# -ne 2 ]; then 
  echo " "
  echo "ERROR: illegal number of parameters"
  echo " "
  echo "$USAGE"
  exit 1
fi

prefix=$1
scenario=$2
new_scenario=${prefix}-${scenario}

echo "Creating new scenario..."
cp -v $scenario $new_scenario

mgmt_net=$( sed -n 's/.*<vm_mgmt.*network="\([^"]\+\).*/\1/p' $scenario )
X=$( printf "%d\n" "'$prefix" )
new_mgmt_net="10.$X.0.0"

echo "Management net $mgmt_net changed to $new_mgmt_net"

sed -i -e "s/network=\"$mgmt_net\"/network=\"$new_mgmt_net\"/g" $new_scenario

# Change scenario_name
scen_name=$( sed -n 's/.*<scenario_name>\(.*\)<\/scen.*/\1/p' $scenario )
new_scen_name=${prefix}-${scen_name}
echo "Scenario name $scen_name changed to $new_scen_name"
sed -i -e "s/scenario_name>$scen_name</scenario_name>$new_scen_name</g" $new_scenario

# Change VM names
vm_names=`grep "<vm \+name" $scenario | sed -e 's/.*name="\(\w*\)".*/\1/'`
echo VMs: $vm_names
for vm in $vm_names; do
  echo "    Changing $vm to ${prefix}-${vm}"
  sed -i -e "s/\"$vm\"/\"$prefix-$vm\"/g" $new_scenario
done

# Change net names
net_names=`grep "<net \+name" $scenario | grep -v "managed=[\"|']no" | sed -e 's/.*name="\(\w*\)".*/\1/'`
echo nets: $net_names
for net in $net_names; do
  echo "    Changing $net to ${prefix}-${net}"
  sed -i -e "s/\"$net\"/\"$prefix-$net\"/g" $new_scenario
done

echo "New scenario created: $new_scenario"

