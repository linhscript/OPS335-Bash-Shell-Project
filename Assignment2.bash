#!/bin/bash

############### CHECKING ALL THE REQUIREMENT BEFORE RUNNING THE SCRIPT ############################
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
function require {
	### ALL INPUT BEFORE CHECKING #### -------------------
	domain="towns.ontario.ops"
	vms_name=(toronto ottawa kingston coburg milton)   ###-- Put the name in order --  Master Slave Other Machines
	vms_ip=(172.17.15.2 172.17.15.3 172.17.15.5 172.17.15.6 172.17.15.8)	
	
	#### Create Hash Table -------------------------------
	
	for (( i=0; i<${#vms_name[@]};i++ ))
	do
		declare -A dict+=( [${vms_name[$i]}]=${vms_ip[$i]} )
	done
	
	### 1.Backing up before runnning the script ------------------

	echo -e "\e[1;31m--------WARNING----------"
	echo -e "\e[1mBackup your virtual machine to run this script \e[0m"
	echo
	read -p "Did you make a backup ?. If NO, It will do it for you. [Y/N]: " choice
	while [[ "$choice" != "Y" && "$choice" != "Yes" && "$choice" != "y" && "$choice" != "yes" ]]
	do
		echo -e "\e[33mBacking up in process \e[0m" >&2
		for shut in $(virsh list --name)  ## --- shutdown vms to backup --- ###
		do
			virsh shutdown $shut
			while virsh list | grep -iqs $shut
			do
				echo $shut is being shutdown. Wait
                sleep 3
			done
		done
		yum install pv -y > /dev/null
		
		for bk in $(ls /var/lib/libvirt/images/ | grep -v vm* | grep \.qcow2$)
		do
			echo "Backing up bk"
			pv /var/lib/libvirt/images/$bk | gzip | pv  > /backup/full/$bk.backup.gz
		done
	done

	### 2.Run script by Root ---------------------------------------------
	if [ `id -u` -ne 0 ]
	then
		echo "Must run this script by root" >&2
		exit 2
	fi

	### 3.Checking VMs need to be online ----------------------------------

	echo "Checking VMs status"
	for vm in ${vms_name[@]}
	do 
		if ! virsh list | grep -iqs $vm
		then
			echo -e "\e[1;31mMust turn on $vm  \e[0m" >&2
			exit 3
		fi
	done
	
	### 4.SSH and Pinging and Update Check ------------------------------------

	check "ping -c 3 google.ca > /dev/null" "Host machine can not ping GOOGLE.CA, check INTERNET connection then run the script again"
		
	for ssh_vm in ${dict[@]} ## -- Checking VMS -- ##
	do
	check "ssh -o ConnectTimeout=5 $ssh_vm ls > /dev/null" "Can not SSH to ${!dict[$ssh_vm]}, check and run the script again "
	check "ssh $ssh_vm ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA from ${!dict[$ssh_vm]}, check internet connection then run the script again"
	check "ssh $ssh_vm yum update -y" "Can not YUM UPDATE from ${!dict[$ssh_vm]}"
	done
	
	### 5.Checking jobs done from Assignment 1 -------------------------

	check "ssh ${vms_ip[0]} host ${vms_name[0]}.$domain > /dev/null 2>&1" "Name service in ${vms_name[0]} is not working"
	
}

########## INPUT from USER ####### --------------------------------

read -p "What is your Seneca username: " username
read -p "What is your FULL NAME: " fullname
read -s -p "Type your normal password: " password && echo
IP1=$(cat /var/named/mydb-for-* | grep ^vm1 | head -1 | awk '{print $4}')
IP2=$(cat /var/named/mydb-for-* | grep ^vm2 | head -1 | awk '{print $4}')
digit=$(cat /var/named/mydb-for-* | grep ^vm2 | head -1 | awk '{print $4}' | cut -d. -f3)


echo "-------Restarting Named-----------"
systemctl restart named
echo -e "--------\e[32mRestarted Done \e[0m----------"


### Start CONFIGURATION ###



