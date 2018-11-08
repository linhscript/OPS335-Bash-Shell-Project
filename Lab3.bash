#!/bin/bash

##### Lab 3 ###########
function check() {
	if eval $1
	then
		echo -e "\e[32mOKAY_Babe. Good job \e[0m"
	else
		echo
     		echo
     		echo -e "\e[0;31mWARNING\e[m"
     		echo
     		echo
     		echo $2
     		echo
     		exit 1
	fi	
}
read -p "What is your Seneca username: " $username
read -p "What is your IP Address of VM1" $IP
$digit=$( echo "$IP" | awk -F. '{print $3}' )

##Checking running script by root###
if [ `id -u` -ne 0 ]
then
	echo "Must run this script by root" >&2
	exit 1 
fi

#### Checking Internet Connection###
check "ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA, check your Internet connection "

## Installing BIND Package ######
echo 
echo "############ Installing DNS ###########"
echo 
check "yum install bind* -y" "Can not use Yum to install"
systemctl start named
systemctl enable named
echo -e "\e[32mInstalling Done\e[m"

### Making DNS configuration file ####
cat > /etc/named.conf << EOF
options {
        directory "/var/named/";
        allow-query {127.0.0.1; 192.168.$digit.0/24;};
        forwarders { 192.168.40.2; };
};
zone "." IN {
	type hint;
        file "named.ca";
};
zone "localhost" {
        type master;
        file "named.localhost";
};
zone "$username.ops" {
        type master;
        file "mydb-for-$username-ops";
};
zone "$digit.168.192.in-addr.arpa." {
        type master;
        file "mydb-for-192.168.$digit";
};
EOF

##### Making forward zone file ####

cat > /var/named/mydb-for-$username-ops << EOF
\$TTL    3D
@       IN      SOA     host.$username.ops.      hostmaster.$username.ops.(
                2018042901       ; Serial
                8H      ; Refresh
                2H      ; Retry
                1W      ; Expire
                1D      ; Negative Cache TTL
);
@       IN      NS      host.$username.ops.
host    IN      A       192.168.$digit.1
vm1		IN		A 		192.168.$digit.2
vm2		IN		A 		192.168.$digit.3
vm3		IN		A 		192.168.$digit.4

EOF

##### Making reverse zone file  #####

cat > /var/named/mydb-for-192.168.$digit << EOF

\$TTL    3D
@       IN      SOA     host.$username.ops.      hostmaster.$username.ops.(
                2018042901       ; Serial
                8H      ; Refresh
                2H      ; Retry
                1W      ; Expire
                1D      ; Negative Cache TTL
);
@       IN      NS      host.$username.ops.
1       IN      PTR     host.$username.ops.
2		IN		PTR		vm1.$username.ops.
3		IN		PTR		vm2.$username.ops.
4		IN		PTR		vm3.$username.ops.

EOF
	
echo	
echo -e "###\e[32mFiles Added Done\e[m###"
echo
#### Adding DNS and DOMAIN ####

grep -v -e "^DNS.*" -e "^DOMAIN.*" > /etc/sysconfig/network-scripts/ifcfg-ens33
echo "DNS1=192.168.$digit.1" >> /etc/sysconfig/network-scripts/ifcfg-ens33
echo "DOMAIN=$username.ops" >> /etc/sysconfig/network-scripts/ifcfg-ens33
echo	
echo -e "###\e[32mConfiguration Done\e[m###"
echo

#### Adding rules in IPtables ####

iptables -I INPUT -p tcp --dport 53 -j ACCEPT
iptables -I INPUT -p udp --dport 53 -j ACCEPT
iptables-save > /etc/sysconfig/iptables
	










