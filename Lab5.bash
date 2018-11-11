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
read -p "What is your FULL NAME: " fullname
read -p "What is your IP Address of VM1" IP
digit=$( echo "$IP" | awk -F. '{print $3}' )

########## List VM1 and VM2 ############
vmip="192.168.$digit.2 192.168.$digit.3"


#### Checking Internet Connection###
check "ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA, check your Internet connection "

## Installing Samba Package ######
echo 
echo "############ Installing Samba Server ###########"
echo 
check "ssh 192.168.$digit.3 yum install samba* -y" "Can not use Yum to install"
systemctl start smb
systemctl enable smb
echo -e "\e[32mInstalling Done\e[m"


### Backup config file ###

echo "Backing up configuration file"
if [ ! -f /etc/samba/smb.conf.backup ]
then
	cp /etc/samba/smb.conf /etc/samba/smb.conf.backup
done
echo -e "\e[32mBacking up Done\e[m"

cat > /etc/samba/smb.conf << EOF

[global]
workgroup = WORKGROUP 
server string = $fullname
encrypt passwords = yes
smb passwd file = /etc/samba/smbpasswd
  
[home]
comment = "put your real name here without the quotes"
path = /home/<yourSenecaID>
public = no
writable = yes
printable = no
create mask = 0765

[homes]
comment = automatic home share
public = no
writable = yes
printable = no
create mask = 0765
browseable = no

EOF

