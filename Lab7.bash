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
	     		echo $2
	     		echo
	     		exit 1
		fi	
	}
		### ALL INPUT BEFORE CHECKING #### -------------------
		

		
		### INPUT from USER ###
		clear
		read -p "What is your Seneca username: " username
		read -p "What is your FULL NAME: " fullname
		read -s -p "Type your normal password: " password && echo
		IP=$(cat /var/named/mydb-for-* | grep ^vm1 | head -1 | awk '{print $4}')
		digit=$(cat /var/named/mydb-for-* | grep ^VM3 | head -1 | awk '{print $4}' | cut -d. -f3)
		domain=$username.ops
		vms_name=(vm3)   
		vms_ip=(192.168.${digit}.4)	
		
		#### Create Hash Table -------------------------------
		
		for (( i=0; i<${#vms_name[@]};i++ ))
		do
			declare -A dict
			dict+=(["${vms_name[$i]}"]="${vms_ip[$i]}")
		done
		
		
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
		read -p "Did you make a backup? Select N to start auto backup [Y/N]:  " choice
		if [[ "$choice" != "Y" && "$choice" != "Yes" && "$choice" != "y" && "$choice" != "yes" ]]
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
	check "ssh -o ConnectTimeout=5 ${dict[$ssh_vm]} ls > /dev/null" "Can not SSH to $ssh_vm, check and run the script again "
	check "ssh ${dict[$ssh_vm]} ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA from $ssh_vm, check internet connection then run the script again"
	check "ssh ${dict[$ssh_vm]} yum update -y" "Can not YUM UPDATE from $ssh_vm"
	done
	
	### 5.Checking jobs done from Assignment 1 -------------------------

	check "ssh ${vms_ip[0]} host ${vms_name[0]}.$domain > /dev/null 2>&1" "Name service in ${vms_name[0]} is not working"
	
}
require

# Start confuguration

## VM3 CONFIGURATION

# Network and hostname 
intVM3=$( ssh 192.168.${digit}.4 '( ip ad | grep -B 2 192.168.${digit} | head -1 | cut -d" " -f2 | cut -d: -f1 )' )
ssh 192.168.${digit}.4 "echo vm3.$domain > /etc/hostname"
check "ssh 192.168.${digit}.4 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-$intVM3 > ipconf.txt" "File or directory not exist"
echo "DNS1="192.168.${digit}.1"" >> ipconf.txt
echo "PEERDNS=no" >> ipconf.txt
echo "DOMAIN=$domain" >> ipconf.txt
check "scp ipconf.txt 192.168.${digit}.4:/etc/sysconfig/network-scripts/ifcfg-$intVM3 > /dev/null" "Can not copy ipconf to VM3"
rm -rf ipconf.txt > /dev/null

# Create user
echo -e "\e[1;35mCreate regular user\e[m"
ssh 192.168.${digit}.4 useradd -m $username 2> /dev/null
ssh 192.168.${digit}.4 '( echo '$username:$password' | chpasswd )'
echo -e "\e[32mUser Created \e[m"

# Install packages
echo -e "\e[1;35mInstall packages\e[m"
check "ssh 192.168.${digit}.4 yum install -y ypbind ypserv" "Can not install ypbind and ypserv"
echo -e "\e[32mDone Installation \e[m"
ssh 192.168.${digit}.4 setenforce permissive
check "ssh 192.168.${digit}.4 systemctl start ypbind" "Can not start services on VM3"
check "ssh 192.168.${digit}.4 systemctl enable ypbind" "Can not enable services on VM3"
check "ssh 192.168.${digit}.4 systemctl start ypserv" "Can not start services on VM3"
check "ssh 192.168.${digit}.4 systemctl enable ypserv" "Can not enable services on VM3"
ssh 192.168.${digit}.4 "echo "192.168.${octet}.1:/home	/home	nfs4	defaults	0 0" >> /etc/fstab "






## HOST MACHINE CONFIGURATION

echo "/home 192.168.${digit}.0/24(rw,no_root_squash,insecure)" > /etc/exports
systemctl enable nfs-server
systemctl start nfs-server
sed -i "/^COMMIT/i -A INPUT -p tcp --dport 2049 -s 192.168.${digit}.0/24 -j ACCEPT" /etc/sysconfig/iptables
iptables -A INPUT -p tcp --dport 2049 -s 192.168.${digit}.0/24 -j ACCEPT

## NOT DONE - BECAREFUL TO RUN
