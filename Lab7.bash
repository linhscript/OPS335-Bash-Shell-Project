#!/bin/bash

### ALL INPUT BEFORE CHECKING #### -------------------
	
		
		### INPUT from USER ###
clear
read -p "What is your Seneca username: " username
read -p "What is your FULL NAME: " fullname
read -s -p "Type your normal password: " password && echo
IP=$(cat /var/named/mydb-for-* | grep ^vm1 | head -1 | awk '{print $4}')
digit=$(cat /var/named/mydb-for-* | grep ^vm2 | head -1 | awk '{print $4}' | cut -d. -f3)

domain="$username.ops"
vms_name=(vm1 vm2 vm3)   ###-- Put the name in order --  Master Slave Other Machines
vms_ip=(192.168.$digit.2 192.168.$digit.3 192.168.$digit.4)
		
		#### Create Hash Table -------------------------------
		
for (( i=0; i<${#vms_name[@]};i++ ))
do
	declare -A dict
	dict+=(["${vms_name[$i]}"]="${vms_ip[$i]}")
done
############### CHECKING ALL THE REQUIREMENT BEFORE RUNNING THE SCRIPT ############################
function require {
	function check() {
		if eval $1
		then
			echo -e "\e[32mOK. GOOD \e[0m"
		else
			echo
	     		echo
	     		echo -e "\e[0;31mWARNING\e[m"
	     		echo
	     		echo
	     		zenity --error --title="An Error Occurred" --text="$2"
	     		echo
	     		exit 1
		fi	
	}
		
		### 1.Run script by Root ---------------------------------------------

		if [ `id -u` -ne 0 ]
		then
			echo "Must run this script by root" >&2
			exit 2
		fi

		### 2.Backing up before runnning the script ------------------

		echo -e "\e[1;31m--------WARNING----------"
		echo -e "\e[1mBackup your virtual machine to run this script \e[0m"
		echo
		if zenity --question --title="BACKUP VIRTUAL MACHINES" --text="DO YOU WANT TO MAKE A BACKUP"
		then
			echo -e "\e[1;35mBacking up in process. Wait... \e[0m" >&2
			for shut in $(virsh list --name)  ## --- shutdown vms to backup --- ###
			do
				virsh shutdown $shut
				while virsh list | grep -iqs $shut
				do
					echo $shut is being shutdown to backup. Wait
	                sleep 3
				done
			done
			yum install pv -y  > /dev/null 2>&1
			
			for bk in $(ls /var/lib/libvirt/images/ | grep -v vm* | grep \.qcow2$)
			do
				echo "Backing up $bk"
				mkdir -p /backup/full 2> /dev/null
				pv /var/lib/libvirt/images/$bk | gzip | pv  > /backup/full/$bk.backup.gz
			done
		fi

	########################################
	echo -e "\e[1;35mChecking VMs status\e[m"
	for vm in ${!dict[@]}
	do 
		if ! virsh list | grep -iqs $vm
		then
			virsh start $vm > /dev/null 2>&1
			while ! eval "ping ${dict[$vm]} -c 5 > /dev/null" 
			do
				echo -e "\e[1;34mMachine $vm is turning on \e[0m" >&2
				sleep 3
			done
		fi
	done
	
	### 4.SSH and Pinging and Update Check ------------------------------------
	echo -e "\e[1;35mRestarting Named\e[m"
	systemctl restart named
	echo -e "\e[32mRestarted Done \e[m"

	check "ping -c 3 google.ca > /dev/null" "Host machine can not ping GOOGLE.CA, check INTERNET connection then run the script again"
		
	for ssh_vm in ${!dict[@]} ## -- Checking VMS -- ## KEY
	do
	check "ssh -o ConnectTimeout=5 -oStrictHostKeyChecking=no ${dict[$ssh_vm]} ls > /dev/null" "Can not SSH to $ssh_vm, check and run the script again "
	check "ssh ${dict[$ssh_vm]} ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA from $ssh_vm, check internet connection then run the script again"
	#check "ssh ${dict[$ssh_vm]} yum update -y" "Can not YUM UPDATE from $ssh_vm"
	done
	

}
require

function vminfo {

## Config DOMAIN, HOSTNAME, RESOLV File, Disable Network Manager
## Need some arguments such as: IP VM_name DNS1 DNS2 
	if [ "$#" -lt 3 ] || [ "$#" -ge 5 ]
	then
		echo -e "\e[31mMissing or Unneeded arguments\e[m"
		echo "USAGE: $0 IP HOSTNAME(FQDN) DNS1 DNS2(optional)" >&2
		exit 2
	else
		intvm=$( ssh $1 '( ip ad | grep -B 2 192.168.$digit | head -1 | cut -d" " -f2 | cut -d: -f1 )' )
		ssh $1 "echo $2.$domain > /etc/hostname"
		check "ssh $1 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-$intvm > ipconf.txt" "File or directory not exist"
		echo "PEERDNS=no" >> ipconf.txt
		echo "DNS1=$3" >> ipconf.txt
		if [ ! -z "$4" ]
		then
			echo "DNS2=$4" >> ipconf.txt
		fi
		echo "DOMAIN=$domain" >> ipconf.txt
		check "scp ipconf.txt $1:/etc/sysconfig/network-scripts/ifcfg-$intvm > /dev/null" "Can not copy ipconf to VM $2"
		ssh $1 "echo -e 'search $domain\nnameserver $3' > /etc/resolv.conf"
		ssh $1 "systemctl stop NetworkManager"
		ssh $1 "systemctl disable NetworkManager"
		rm -rf ipconf.txt > /dev/null
	fi
}
#----------------------------------------------------------------------------------------------------------------------------------------
# Start configuration


## HOST MACHINE
# Pre-config
yum install -y nfs-utils
echo "/home 192.168.$digit.0/24(rw,no_root_squash,insecure)" > /etc/exports
systemctl enable nfs-server
systemctl start nfs-server
iptables -C INPUT -p tcp --dport 2049 -s 192.168.$digit.0/24 -j ACCEPT 2> /dev/null || iptables -I INPUT -p tcp --dport 2049 -s 192.168.$digit.0/24 -j ACCEPT

# Install package
echo -e "\e[1;35mInstall package\e[m"
check "yum install ypserv ypbind -y"

# /etc/sysconfig/network
grep -v -e ".*NISDOMAIN.*" -e ".*YPSERV.*" /etc/sysconfig/network > network
cat >> network << EOF
NISDOMAIN="$username.ops"
YPSERV_ARGS="-p 783"" >
EOF
check "scp network /etc/sysconfig/network" "/etc/sysconfig/network failed"
rm -rf network

nisdomainname $username.ops
systemctl enable rhel-domainname
systemctl start rhel-domainname

# /etc/yp.conf
grep -v -e "^domain.*" /etc/yp.conf > yp.conf
cat >> yp.conf << EOF
domain $username.ops server 127.0.0.1
EOF
check "scp yp.conf /etc/yp.conf" "/etc/yp.conf failed"
rm -rf yp.conf

# /var/yp/securenets
cat > /var/yp/securenets << EOF
host 127.0.0.1
255.255.255.0   192.168.$digit.0
EOF

# service YPSERV
systemctl start ypserv.service
systemctl enable ypserv.service

# Backup NIS DB
if [ ! -f /var/yp/Makefile.orig ] 
then
	cp /var/yp/Makefile /var/yp/Makefile.orig
fi

# Create user test lab7
echo -e "\e[1;35mCreate user test lab7 - testlab7\e[m"
useradd -m testlab7 2> /dev/null
echo testlab7:$password | chpasswd
echo -e "\e[32mUser testlab7 Created \e[m"

# Make config

make -C /var/yp/

# Enable YPBIND SERVICE
systemctl start ypbind
systemctl enable ypbind


## VM3 CONFIGURATION---------------------------------------------------------
echo -e "\e[1;35mStart config VM3\e[m"
# Network and hostname 
vminfo ${dict[vm3]} vm3 192.168.$digit.1 ## Need some arguments such as: IP HOSTNAME DNS1 DNS2 

# Create user
echo -e "\e[1;35mCreate regular user\e[m"
ssh ${dict[vm3]} useradd -m $username 2> /dev/null
ssh ${dict[vm3]} '( echo '$username:$password' | chpasswd )'
echo -e "\e[32mUser Created \e[m"

# Create user test lab7
echo -e "\e[1;35mCreate user test lab7 - testlab7\e[m"
ssh ${dict[vm3]} useradd -m testlab7 2> /dev/null
ssh ${dict[vm3]} '( echo 'testlab7:$password' | chpasswd )'
echo -e "\e[32mUser testlab7 Created \e[m"

# Install packages
echo -e "\e[1;35mInstall packages\e[m"
check "ssh ${dict[vm3]} yum install -y ypbind ypserv" "Can not install ypbind and ypserv"
echo -e "\e[32mDone Installation \e[m"

# # Config SELINUX
echo -e "\e[1;35mSELINUX CONFIG\e[m"
ssh ${dict[vm3]} "echo "192.168.${digit}.1:/home	/home	nfs4	defaults	0 0" >> /etc/fstab "
ssh ${dict[vm3]} "setsebool -P use_nfs_home_dirs 1"
ssh ${dict[vm3]} "nisdomainname $username.ops"
ssh ${dict[vm3]} "setenforce permissive"


# /Etc/yp.conf on client machine
check "ssh ${dict[vm3]} grep -v -e '^domain.*' /etc/yp.conf > yp.conf" "Grep Failed on VM3"
cat >> yp.conf << EOF
domain $username.ops server 192.168.$digit.1
EOF
check "scp yp.conf ${dict[vm3]}:/etc/yp.conf" "/etc/yp.conf failed"
rm -rf yp.conf


## IPTABLES CLIENT MACHINE
echo -e "\e[1;35mVM3 IPTABLES\e[m"
ssh ${dict[vm3]} iptables -C INPUT -p tcp --dport 783  -j ACCEPT 2> /dev/null || ssh ${dict[vm3]} iptables -I INPUT -p tcp --dport 783 -j ACCEPT
ssh ${dict[vm3]} iptables -C INPUT -p udp --dport 783  -j ACCEPT 2> /dev/null || ssh ${dict[vm3]} iptables -I INPUT -p udp --dport 783 -j ACCEPT
ssh ${dict[vm3]} iptables -C INPUT -p tcp --dport 111  -j ACCEPT 2> /dev/null || ssh ${dict[vm3]} iptables -I INPUT -p tcp --dport 111 -j ACCEPT
ssh ${dict[vm3]} iptables -C INPUT -p udp --dport 111  -j ACCEPT 2> /dev/null || ssh ${dict[vm3]} iptables -I INPUT -p udp --dport 111 -j ACCEPT


# Config nsswitch.conf
echo -e "\e[1;35mNSSwitch\e[m"

ssh ${dict[vm3]} "sed -i 's/^passwd.*/passwd:      nis files/' /etc/nsswitch.conf"
ssh ${dict[vm3]} "sed -i 's/^shadow.*/shadow:      nis files/' /etc/nsswitch.conf"
ssh ${dict[vm3]} "sed -i 's/^group.*/group:      nis files/' /etc/nsswitch.conf"


check "ssh ${dict[vm3]} systemctl start ypbind" "Can not start services on VM3"
check "ssh ${dict[vm3]} systemctl enable ypbind" "Can not enable services on VM3"

