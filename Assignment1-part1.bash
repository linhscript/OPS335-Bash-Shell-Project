#!/bin/bash

### ALL INPUT BEFORE CHECKING #### -------------------
domain=towns.ontario.ops
network=172.17.15 ### User only 3 digits
vms_name=(cloyne)   ## @@@ Master [0] | Slave [1] | SMTP [2] | IMAP [3] | Samba [4]
vms_ip=(172.17.15.100)	
cloningvm=vm3


################### Create Hash Table ######################
		
for (( i=0; i<${#vms_name[@]};i++ ))
do
	declare -A dict
	dict+=(["${vms_name[$i]}"]="${vms_ip[$i]}")
done
		
################ INPUT from USER ########################

clear
if zenity --forms --title="INFORMATION" \
	--text="INPUT USER INFORMATION" \
	--add-entry="Your Seneca Username" \
	--add-entry="Your Full Name" \
	--add-password="Enter your normal password" > var
then
	username=$(cut -d\| -f1 var)
	fullname=$(cut -d\| -f2 var)
	password=$(cut -d\| -f3 var)
	if [ -z $username ] || [ -z "$fullname" ] || [ -z $password ]
	then
		echo
		echo
		echo -e "\e[31mValue is empty. Run the script and input again\e[m"
		exit 2
		rm -rf var
		echo
		echo
	fi
else
echo -e "\e[31mJob cancelled\e[m"
exit 3
rm -rf var
fi	
################ DONE - INPUT from USER ########################


################# GRAB DIGITS FROM IP - REQUIRE LAB 3 DONE #########################
check "cat /var/named/mydb-for-* 2> /dev/null" "LAB 3 HAS NOT DONE YET, CAN NOT FIND mydb-for-id"

IP=$(cat /var/named/mydb-for-* | grep ^vm1 | head -1 | awk '{print $4}')
digit=$(cat /var/named/mydb-for-* | grep ^vm2 | head -1 | awk '{print $4}' | cut -d. -f3)
		

############### CHECKING ALL THE REQUIREMENT BEFORE RUNNING THE SCRIPT ############################
function require {

	################## CHECKING FUNCTION #################

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
	################# DONE - CHECKING FUNTION ###################	



	########## Run script by Root ##################

		if [ `id -u` -ne 0 ]
		then
			echo "Must run this script by root" >&2
			exit 2
		fi

	########## Backing up before runnning the script ############

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
		
	######## CHECKING VM3 STATUS and TURN ON VM3 ################################ 
		echo -e "\e[1;35mChecking $cloningvm status\e[m"
		if ! virsh list | grep -iqs $cloningvm
		then
			virsh start $cloningvm > /dev/null 2>&1
			while ! eval "ping $cloningvm -c 5 > /dev/null"
			do
				echo -e "\e[1;34mMachine $cloningvm is turning on \e[0m" >&2
				sleep 3
			done
		fi

	
	################# SSH, PING and Update Check #########################
	check "ping -c 3 google.ca > /dev/null" "Host machine can not ping GOOGLE.CA, check INTERNET connection then run the script again"

		
	for ssh_vm in ${!dict[@]} ## -- Checking VMS -- ## KEY
	do
	check "ssh -o ConnectTimeout=5 -oStrictHostKeyChecking=no ${dict[$ssh_vm]} ls > /dev/null" "Can not SSH to $ssh_vm, check and run the script again "
	check "ssh ${dict[$ssh_vm]} ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA from $ssh_vm, check internet connection then run the script again"
	check "ssh ${dict[$ssh_vm]} yum update -y" "Can not YUM UPDATE from $ssh_vm"
	done



	########### CLONING VMS FUNCTION START ####################

	function clone-machine {
		echo -e "\e[1;35mChecking clone machine\e[m"
		count=0
		for vm in ${vms_name[@]}
		do 
			if ! virsh list --all | grep -iqs $vm
			then
				echo 
				echo
				echo -e "\e[1;31m$vm need to be created\e[m"
				echo
				echo
				count=1
			fi
		done
		check "yum install virt-clone" "Can not install packages. Check INTERNET connection"
		

		if [ $count -gt 0 ]
		then
			echo
			echo -e "\e[1;32m###### CLONING MACHINES IS PROCESSING... #######\e[m"
			echo
			check "virsh start $cloningvm 2> /dev/null" "Can not start $cloningvm machine"

			############# Set up clone-machine configuration before cloning
			check "ssh -o ConnectTimeout=5 $cloningvm ls > /dev/null" "Can not SSH to $cloningvm, check and run the script again"
			check "ssh $cloningvm yum install mailx" " Can not install mailx"
			ssh $cloningvm "restorecon /etc/resolv.conf"
			ssh $cloningvm "restorecon -v -R /var/spool/postfix/"
			intcloyne=$(ssh $cloningvm '( ip ad | grep -B 2 192.168.$digit | head -1 | cut -d" " -f2 | cut -d: -f1 )' )  #### grab interface infor (some one has ens3)
			maccloyne=$(ssh $cloningvm grep ".*HWADDR.*" /etc/sysconfig/network-scripts/ifcfg-$intcloyne) #### grab mac address
			
			############# INTERFACES COLLECTING
			check "ssh $cloningvm grep -v -e '.*DNS.*' -e 'DOMAIN.*' -e 'DEVICE.*' /etc/sysconfig/network-scripts/ifcfg-$intcloyne > ipconf.txt" "File or directory not exist"
			echo "DOMAIN=$domain" >> ipconf.txt
			echo "DEVICE=$intcloyne" >> ipconf.txt
			sed -i 's/'${maccloyne}'/#'${maccloyne}'/g' ipconf.txt 2> /dev/null  #comment mac address in ipconf.txt file
			check "scp ipconf.txt $cloningvm:/etc/sysconfig/network-scripts/ifcfg-$intcloyne > /dev/null" "Can not copy ipconf to Cloyne"
			rm -rf ipconf.txt > /dev/null
			sleep 2
			echo
			echo -e "\e[32mCloyne machine info has been collected\e[m"
			ssh ${dict[cloyne]} init 6 > /dev/null 2>&1

			while ! eval "ping ${dict[cloyne]} -c 5 > /dev/null" 
			do
				echo "Clonning machine is processing"
				sleep 3
			done
			sleep 3
			virsh suspend cloyne			
		
			############# CLONING PROGRESS BEGIN #####

			for clonevm in ${!dict[@]} # Key (name vm)
			do 
				if ! virsh list --all | grep -iqs $clonevm
				then
					echo -e "\e[1;35mCloning $clonevm \e[m"
					virt-clone --auto-clone -o cloyne --name $clonevm

				#-----Turn on cloned vm without turning on cloyne machine
				virsh start $clonevm
				while ! eval "ping ${dict[cloyne]} -c 5 > /dev/null" 
				do
					echo "Clonning machine is starting"
					sleep 3
				done
				#------ get new mac address
				newmac=$(virsh dumpxml $clonevm | grep "mac address" | cut -d\' -f2)
				#-----Replace mac and ip, hostname
				ssh ${dict[cloyne]} "sed -i 's/.*HW.*/HWADDR\='${newmac}'/g' /etc/sysconfig/network-scripts/ifcfg-$intcloyne" ## change mac
				ssh ${dict[cloyne]} "echo $clonevm.$domain > /etc/hostname "  #change host name
				ssh ${dict[cloyne]} "sed -i 's/'${dict[cloyne]}'/'${dict[$clonevm]}'/' /etc/sysconfig/network-scripts/ifcfg-$intcloyne" #change ip
				echo
				echo -e "\e[32mCloning Done $clonevm\e[m"
				ssh ${dict[cloyne]} init 6 > /dev/null 2>&1
				fi
			done

				echo -e "\e[35mRESET CLOYNE MACHINE TO DEFAULT\e[m"
				#------------------# reset cloyne machine
				oldmac=$(virsh dumpxml cloyne | grep "mac address" | cut -d\' -f2)
				virsh resume cloyne > /dev/null 2>&1
				while ! eval "ping ${dict[cloyne]} -c 5 > /dev/null" 
				do
					echo "Cloyne machine is starting"
					sleep 3
				done
				sleep 5
				ssh ${dict[cloyne]} "sed -i 's/.*HW.*/HWADDR\='${oldmac}'/g' /etc/sysconfig/network-scripts/ifcfg-$intcloyne"
				ssh ${dict[cloyne]} init 6 > /dev/null 2>&1
		fi
	}		
	clone-machine

	################# DONE - CLONING FUNCTION ###################


	### 5.Checking jobs done from Assignment 1 -------------------------

	#check "ssh ${vms_ip[0]} host ${vms_name[0]}.$domain > /dev/null 2>&1" "Name service in ${vms_name[0]} is not working"
	
}
require

#### OUTPUT Function ### 
function status() {
	if eval $1
	then 
		echo -e "\e[32mOK\e[m : $2"
	else
		echo -e "\e[31mnot OK\e[m : $2"
		exit 3
	fi
}

######## Last checking

for check_vm in ${!dict[@]} ## -- Checking VMS -- ## KEY
do
status "ssh -o ConnectTimeout=5 -oStrictHostKeyChecking=no ${dict[$check_vm]} ls > /dev/null" "SSH to $check_vm"
status "ssh ${dict[$check_vm]} ping -c 3 google.ca > /dev/null" "Ping GOOGLE.CA from $check_vm"
done


############################### Start CONFIGURATION #############################

# Create Network 335assign
	## Check the system whether it has 335assign or not

# Generate SSH key with no key
ssh-keygen -f /root/.ssh/id_rsa -t rsa -N ''

# Configuration
# PermitRootLogin Status:

# Firewalld Status: Disable
# Shell Script contents (/root/bin/assnBackup.bash
# Full Backup Status
#Crontab Log 
#Incremental Backup 