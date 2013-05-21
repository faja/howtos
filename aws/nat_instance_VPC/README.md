Subnet: 10.0.0.0/24   
Nat instance: 10.0.0.10


On nat instance
```
# sudo echo 1 > /proc/sys/net/ipv4/ip_forward
# iptables -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
```
You have to disable "Source/Dest Check" on that instance via aws console or api.



On host without public address:
```
# sudo ip route delete default
# sudo ip route add default via 10.0.0.10
```
