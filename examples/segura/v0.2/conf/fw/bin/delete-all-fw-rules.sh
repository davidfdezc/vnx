#!/bin/bash

iptables -F
iptables -X 
for CHAIN in INPUT OUTPUT FORWARD;
do iptables -P $CHAIN ACCEPT; done

iptables -F -t nat
iptables -X -t nat
for CHAIN in PREROUTING POSTROUTING OUTPUT;
do iptables -P $CHAIN ACCEPT -t nat; done

iptables -F -t mangle
iptables -X -t mangle
for CHAIN in PREROUTING INPUT OUTPUT FORWARD POSTROUTING;
do iptables -P $CHAIN ACCEPT -t mangle; done

iptables -F -t raw
iptables -X -t raw
for CHAIN in PREROUTING OUTPUT;
do iptables -P $CHAIN ACCEPT -t raw; done
