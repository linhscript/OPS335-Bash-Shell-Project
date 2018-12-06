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
		domain="towns.ontario.ops"
		vms_name=(toronto ottawa kingston coburg milton)   ###-- Put the name in order --  Master Slave Other Machines
		vms_ip=(172.17.15.2 172.17.15.3 172.17.15.5 172.17.15.6 172.17.15.8)	
		
		### INPUT from USER ###
		clear
		read -p "What is your Seneca username: " username
		read -p "What is your FULL NAME: " fullname
		read -s -p "Type your normal password: " password && echo
		IP=$(cat /var/named/mydb-for-* | grep ^vm1 | head -1 | awk '{print $4}')
		digit=$(cat /var/named/mydb-for-* | grep ^vm2 | head -1 | awk '{print $4}' | cut -d. -f3)
		
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
				mkdir -p /backup/full 2> /dev/null
				pv /var/lib/libvirt/images/$bk | gzip | pv  > /backup/full/$bk.backup.gz
			done
		fi

		### 3.Checking VMs need to be clone and status ----------------------------------
	function clone-machine {
		echo -e "\e[1;35mChecking clone machine\e[m"
		count=0
		for vm in ${vms_name[@]}
		do 
			if ! virsh list --all | grep -iqs $vm
			then
				echo "$vm need to be created"
				echo
				echo
				count=1
			fi
		done
		#----------------------------------------# Setup cloyne to be cloneable
		if [ $count -gt 0 ]
		then
			echo -e "\e[35mStart cloning machines\e[m"
			echo
			echo -e "\e[1;32mCloning in progress...\e[m"
			virsh start cloyne 2> /dev/null
			while ! eval "ping 172.17.15.100 -c 5 > /dev/null" 
			do
				echo "Cloyne machine is starting"
				sleep 3
			done
			sleep 5
			check "ssh -o ConnectTimeout=8 172.17.15.100 ls > /dev/null" "Can not SSH to Cloyne, check and run the script again"
			intcloyne=$( ssh 172.17.15.100 '( ip ad | grep -B 2 172.17.15 | head -1 | cut -d" " -f2 | cut -d: -f1 )' )  #### grab interface infor (some one has ens3)
			maccloyne=$(ssh 172.17.15.100 grep ".*HWADDR.*" /etc/sysconfig/network-scripts/ifcfg-$intcloyne) #### grab mac address
			ssh 172.17.15.100 "sed -i 's/${maccloyne}/#${maccloyne}/g' /etc/sysconfig/network-scripts/ifcfg-$intcloyne " #ssh to cloyne and comment mac address
			check "ssh 172.17.15.100 grep -v -e '.*DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-$intcloyne > ipconf.txt" "File or directory not exist"
			echo "DNS1="172.17.15.2"" >> ipconf.txt
			echo "DNS2="172.17.15.3"" >> ipconf.txt
			echo "PEERDNS=no" >> ipconf.txt
			echo "DOMAIN=towns.ontario.ops" >> ipconf.txt
			check "scp ipconf.txt 172.17.15.100:/etc/sysconfig/network-scripts/ifcfg-$intcloyne > /dev/null" "Can not copy ipconf to Cloyne"
			rm -rf ipconf.txt > /dev/null
			sleep 2
			echo -e "\e[32mCloyne machine info has been collected\e[m"
			virsh destroy cloyne			
		
			#---------------------------# Start cloning
			for clonevm in ${!dict[@]} # Key (name vm)
			do 
				if ! virsh list --all | grep -iqs $clonevm
				then
					echo -e "\e[1;35mCloning $clonevm \e[m"
					virt-clone --auto-clone -o cloyne --name $clonevm
				#-----Turn on cloned vm without turning on cloyne machine
				virsh start $clonevm
				while ! eval "ping 172.17.15.100 -c 5 > /dev/null" 
				do
					echo "Clonning machine is starting"
					sleep 3
				done
				#------ get new mac address
				newmac=$(virsh dumpxml $clonevm | grep "mac address" | cut -d\' -f2)
				#-----Replace mac and ip, hostname
				ssh 172.17.15.100 "sed -i 's/.*HW.*/HWADDR\=${newmac}/g' /etc/sysconfig/network-scripts/ifcfg-$intcloyne" ## change mac
				ssh 172.17.15.100 "echo $clonevm.towns.ontario.ops > /etc/hostname "  #change host name
				ssh 172.17.15.100 "sed -i 's/'172.17.15.100'/'${dict[$clonevm]}'/' /etc/sysconfig/network-scripts/ifcfg-$intcloyne" #change ip
				echo
				echo -e "\e[32mCloning Done $clonevm\e[m"
				ssh 172.17.15.100 init 6
				fi
			done
				#------------------# reset cloyne machine
				oldmac=$(virsh dumpxml cloyne | grep "mac address" | cut -d\' -f2)
				virsh start cloyne > /dev/null 2>&1
				while ! eval "ping 172.17.15.100 -c 5 > /dev/null" 
				do
					echo "Cloyne machine is starting"
					sleep 3
				done
				sleep 5
				ssh 172.17.15.100 "sed -i 's/.*HW.*/${oldmac}/g' /etc/sysconfig/network-scripts/ifcfg-$intcloyne"
				ssh 172.17.15.100 init 6
		fi
	}		
	clone-machine

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

function vminfo {

## Config DOMAIN, HOSTNAME, RESOLV File, Disable Network Manager
## Need some arguments such as: IP HOSTNAME DNS1 DNS2 
	if [ "$#" -lt 3 ] || [ "$#" -ge 5 ]
	then
		echo -e "\e[31mMissing or Unneeded arguments\e[m"
		echo "USAGE: $0 IP HOSTNAME(FQDN) DNS1 DNS2(optional)" >&2
		exit 2
	else
		intvm=$( ssh $1 '( ip ad | grep -B 2 192.168.$digit | head -1 | cut -d" " -f2 | cut -d: -f1 )' )
		ssh $1 "echo $2 > /etc/hostname"
		check "ssh $1 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-$intvm > ipconf.txt" "File or directory not exist"
		echo "PEERDNS=no" >> ipconf.txt
		echo "DNS1=$3" >> ipconf.txt
		if [ ! -z "$4" ]
		then
			echo "DNS2=$4" >> ipconf.txt
		fi
		echo "DOMAIN=$domain" >> ipconf.txt
		check "scp ipconf.txt $1:/etc/sysconfig/network-scripts/ifcfg-$intvm > /dev/null" "Can not copy ipconf to VM $2"
		ssh $1 "echo "search $domain" > /etc/resolv.conf"
		ssh $1 "systemctl stop NetworkManager"
		ssh $1 "systemctl disable NetworkManager"
		rm -rf ipconf.txt > /dev/null
	fi
}
