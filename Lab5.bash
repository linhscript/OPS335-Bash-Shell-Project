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

######## INPUT from USER ###########
list_vms="vm1 vm2"
read -p "What is your Seneca username: " username
read -p "What is your FULL NAME: " fullname
read -s -p "Put your password: " password && echo
read -p "What is your IP Address of VM1: " IP1
read -p "What is your IP Address of VM2: " IP2
digit=$( echo "$IP" | awk -F. '{print $3}' )

#### Checking Internet Connection of HOST###
echo "Checking Internet Connection"
check "ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA, check your Internet connection "

### Checking if VM1 and VM2 are running
echo "Checking running machine"
for i in $list_vms
do 
	if ! virsh list | grep -iqs $i
	then
		echo -e "\e[1;31mMust turn on $i  \e[0m" >&2
		exit 2
	fi

done

### Restarting named service
echo "-------Restarting Named-----------"
systemctl restart named
echo -e "--------\e[32mRestarted Done \e[0m----------"

###--- Checking if can ssh to VM1 and VM2---------
echo "-------Checking SSH Connection---------"
check "ssh -o ConnectTimeout=5 root@$IP1 ls > /dev/null" "Can not SSH to VM1, fix the problem and run the script again "
check "ssh -o ConnectTimeout=5 root@$IP2 ls > /dev/null" "Can not SSH to VM2, fix the problem and run the script again "

###--- Checking VM1 and VM2 can ping google.ca 
echo "-------Pinging GOOGLE.CA from VM2---------"
check "ssh root@$IP1 ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA from VM1, check INTERNET connection then run the script again"
check "ssh root@$IP2 ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA from VM2, check INTERNET connection then run the script again"


echo "#### Checking COMPLETED ####"
########################### Checking COMPLETED ####################

## Installing Samba Package ######
echo 
echo "############ Installing Samba Server ###########"
echo 
check "ssh $IP2 yum install samba* -y" "Can not use Yum to install"
ssh $IP2 systemctl start smb
ssh $IP2 systemctl enable smb
echo -e "\e[32mInstalling Done\e[m"


### Backup config file ###

echo "Backing up configuration file"
if [ ssh $IP2 ! test -f /etc/samba/smb.conf.backup ]
then
	ssh $IP2 "cp /etc/samba/smb.conf /etc/samba/smb.conf.backup"
done
echo -e "\e[32mBacking up Done\e[m"

cat > smb.conf << EOF

[global]
workgroup = WORKGROUP 
server string = $fullname
encrypt passwords = yes
smb passwd file = /etc/samba/smbpasswd
hosts allow = 192.168.$digit. 127.0.0.1 192.168.40.
  
[home]
comment = $fullname
path = /home/$username
public = no
writable = yes
printable = no
create mask = 0765
valid users = $username

[homes]
comment = automatic home share
public = no
writable = yes
printable = no
create mask = 0765
browseable = no

EOF
check "scp smb.conf $IP2:/etc/samba/smb.conf " "Error when trying to copy SMB.CONF"
rm -rf smb.conf

## Selinux allows SMB
ssh IP2 setsebool -P samba_enable_home_dirs on

## Add user and create smb password
useradd -m username 2> /dev/null
echo "test1:$password" | chpasswd


# Config iptables
echo "Adding Firewall Rules"
iptables -A PREROUTING -t nat -p tcp --dport 445 -j DNAT --to 192.168.$digit.3:8445
iptables -I FORWARD -p tcp -d 192.168.$digit.3 --dport 445 -j ACCEPT

ssh IP2 iptables -I INPUT -p tcp --dport 445 -j ACCEPT

echo 
echo -e "\e[32m########## COMPLETED ########\e[0m"
echo "Using these information to login SAMBA"
echo "Username: " $username
echo "Password: " $password

