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

EOF













