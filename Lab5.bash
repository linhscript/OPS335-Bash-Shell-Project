#!/bin/bash

#### Lab 5 ####
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
##Checking running script by root###
if [ `id -u` -ne 0 ]
then
	echo "Must run this script by root" >&2
	exit 1 
fi

read -p "What is your Seneca username: " username
read -p "What is your IP Address of VM1" IP
digit=$( echo "$IP" | awk -F. '{print $3}' )



#### Checking Internet Connection###
check "ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA, check your Internet connection "

## Installing Samba Package ######
echo 
echo "############ Installing Samba Server ###########"
echo 
check "yum install samba* -y" "Can not use Yum to install"
systemctl start smb
systemctl enable smb
echo -e "\e[32mInstalling Done\e[m"
