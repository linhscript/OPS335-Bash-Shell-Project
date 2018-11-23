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
		digit=$(cat /var/named/mydb-for-* | grep ^vm2 | head -1 | awk '{print $4}' | cut -d. -f3)
		domain=$username.ops
		vms_name=(vm1 vm2 vm3)   
		vms_ip=(192.168.$digit.2 192.168.$digit.3 192.168.$digit.4)	
		
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


## NOT DONE - BECAREFUL TO RUN 