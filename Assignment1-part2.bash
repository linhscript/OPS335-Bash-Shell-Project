#!/bin/bash

### ALL INPUT BEFORE CHECKING #### -------------------
		domain="towns.ontario.ops"
		vms_name=(toronto ottawa cloyne)   ###-- Put the name in order --  Master Slave Other Machines
		vms_ip=(172.17.15.2 172.17.15.3 172.17.15.100)	
		
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
	     		zenity --error --title="An Error Occurred" --text=$2
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
		zenity --question --title="BACKUP VIRTUAL MACHINES" --text="DO YOU WANT TO MAKE A BACKUP"
		if [ $? -eq 0 ]
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
			## Set clone-machine configuration before cloning
			check "ssh -o ConnectTimeout=8 172.17.15.100 ls > /dev/null" "Can not SSH to Cloyne, check and run the script again"
			intcloyne=$(ssh 172.17.15.100 '( ip ad | grep -B 2 172.17.15 | head -1 | cut -d" " -f2 | cut -d: -f1 )' )  #### grab interface infor (some one has ens3)
			maccloyne=$(ssh 172.17.15.100 grep ".*HWADDR.*" /etc/sysconfig/network-scripts/ifcfg-$intcloyne) #### grab mac address
			check "ssh 172.17.15.100 grep -v -e '.*DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-$intcloyne > ipconf.txt" "File or directory not exist"
			echo "DNS1="172.17.15.2"" >> ipconf.txt
			echo "DNS2="172.17.15.3"" >> ipconf.txt
			echo "PEERDNS=no" >> ipconf.txt
			echo "DOMAIN=towns.ontario.ops" >> ipconf.txt
			sed -i 's/'${maccloyne}'/#'${maccloyne}'/g' ipconf.txt 2> /dev/null  #comment mac address in ipconf.txt file
			check "scp ipconf.txt 172.17.15.100:/etc/sysconfig/network-scripts/ifcfg-$intcloyne > /dev/null" "Can not copy ipconf to Cloyne"
			rm -rf ipconf.txt > /dev/null
			sleep 2
			echo -e "\e[32mCloyne machine info has been collected\e[m"
			virsh suspend cloyne			
		
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
				ssh 172.17.15.100 "sed -i 's/.*HW.*/HWADDR\='${newmac}'/g' /etc/sysconfig/network-scripts/ifcfg-$intcloyne" ## change mac
				ssh 172.17.15.100 "echo $clonevm.towns.ontario.ops > /etc/hostname "  #change host name
				ssh 172.17.15.100 "sed -i 's/'172.17.15.100'/'${dict[$clonevm]}'/' /etc/sysconfig/network-scripts/ifcfg-$intcloyne" #change ip
				echo
				echo -e "\e[32mCloning Done $clonevm\e[m"
				ssh 172.17.15.100 init 6
				fi
			done
				#------------------# reset cloyne machine
				oldmac=$(virsh dumpxml cloyne | grep "mac address" | cut -d\' -f2)
				virsh resume cloyne > /dev/null 2>&1
				while ! eval "ping 172.17.15.100 -c 5 > /dev/null" 
				do
					echo "Cloyne machine is starting"
					sleep 3
				done
				sleep 5
				ssh 172.17.15.100 "sed -i 's/.*HW.*/'${oldmac}'/g' /etc/sysconfig/network-scripts/ifcfg-$intcloyne"
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
	check "ssh -o ConnectTimeout=5 -oStrictHostKeyChecking=no ${dict[$ssh_vm]} ls > /dev/null" "Can not SSH to $ssh_vm, check and run the script again "
	check "ssh ${dict[$ssh_vm]} ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA from $ssh_vm, check internet connection then run the script again"
	check "ssh ${dict[$ssh_vm]} yum update -y" "Can not YUM UPDATE from $ssh_vm"
	done
	
	### 5.Checking jobs done from Assignment 1 -------------------------

	#check "ssh ${vms_ip[0]} host ${vms_name[0]}.$domain > /dev/null 2>&1" "Name service in ${vms_name[0]} is not working"
	
}
require


####FIX FROM HERE -------------------------

##### Check Function
list_vms="toronto ottawa cloyne"
vms="172.17.15.2 172.17.15.3 172.17.15.100"


### Check if you are root ###
if [ `id -u` -ne 0 ]
then
	echo "Must run this script by root" >&2
	exit 1 
fi

### Check vms are online: Toronto, Ottawa
echo "Checking VMs status"

for i in $list_vms
do 
	if ! virsh list | grep -iqs $i
	then
		echo -e "\e[1;31mMust turn on $i  \e[0m" >&2
		exit 2
	fi

done

echo "-------Restarting Named-----------"
systemctl restart named
echo -e "--------\e[32mRestarted Done \e[0m----------"

############################# VM CONFIGURATION ####################



###--- Checking if can ssh to Toronto or Ottawa or Cloyne
echo "-------Checking SSH TORONTO---------"
check "ssh -o ConnectTimeout=5 root@172.17.15.2 ls > /dev/null" "Can not SSH to TORONTO, check and run the script again "

echo "-------Checking SSH OTTAWA---------"
check "ssh -o ConnectTimeout=5 root@172.17.15.3 ls > /dev/null " "Can not SSH to TORONTO, check and run the script again  "

echo "-------Checking SSH CLOYNE---------"
check "ssh -o ConnectTimeout=5 root@172.17.15.100 ls > /dev/null" "Can not SSH to TORONTO, check and run the script again  "


### Check if vms can ping google.ca or not, Create User

echo "-------Check internet connection------"
for b in $vms
do
	ssh root@$b useradd -m $username 2> /dev/null
	check "ssh root@$b 'echo 'nameserver 8.8.8.8' >> /etc/resolv.conf '" "Can not copy 8.8.8.8 to your /etc/resolv.conf"
	check "ssh root@$b ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA from $b, check internet connection then run the script again"
	check "ssh root@$b test -f /etc/sysconfig/network-scripts/ifcfg-eth0 > /dev/null" "You dont have eth0 interface in $b vm"
done


### Install bind package
echo "Install bind package and update system"
for c in $vms
do
	echo "Updating system"
	ssh $c yum update -y 
	echo "Installing bind on $c"
	sleep 2
	echo "Installing rsync on $c"
	ssh $c yum install -y rsync
	sleep 2
	ssh $c yum install -y bind* 
	echo -e "############\e[32mInstalling Done \e[0m###############"
done

echo
echo
### Config Toronto machine
echo "################################################"
echo "############Start configuring Toronto###########"
echo "################################################"

#### Etc/named file
cat > named.conf << EOF
options {
	directory "/var/named";
        allow-query { localhost;any;};
        forwarders {172.17.15.1;};
        allow-recursion {localhost;172.17.15.0/24;};
};

zone "." IN {
	type hint;
        file "named.ca";
};

zone "towns.ontario.ops" IN {
        type master;
        file "mydb-for-towns.ontario.ops";
        allow-update {none;};
        allow-transfer {172.17.15.3;};
};
zone "15.17.172.in-addr.arpa." IN{
        type master;
        file "mydb-for-172.17.15";
        allow-update {none;};
        allow-transfer {172.17.15.3;};

};
EOF

####-- Forward Zone
echo "Copying named.conf"
check "scp named.conf root@172.17.15.2:/etc > /dev/null " "Error when copying named.conf file to TORONTO"
rm -rf named.conf > /dev/null
echo "Copying forward zone"
cat > 'mydb-for-towns.ontario.ops' << EOF
\$TTL    3D
@	IN	SOA     toronto.towns.ontario.ops.	hostmaster.towns.ontario.(
        2018191002	 ; Serial
                2D	; Refresh
                6H	; Retry
                1W	; Expire
                1D	; Negative Cache TTL
);
@               IN	NS	toronto.towns.ontario.ops.
@               IN	NS	ottawa.towns.ontario.ops.
toronto         IN	A	172.17.15.2
ottawa          IN	A	172.17.15.3
york            IN	A	172.17.15.1
cloyne          IN	A	172.17.15.100
kingston        IN	A	172.17.15.5
coburg          IN	A	172.17.15.6
milton          IN	A	172.17.15.8
towns.ontario.ops.	IN	MX	10 kingston.towns.ontario.ops.

EOF
check "scp 'mydb-for-towns.ontario.ops' root@172.17.15.2:/var/named/ > /dev/null" "Error when copying FORWARD Zone file to TORONTO"
rm -rf 'mydb-for-towns.ontario.ops' > /dev/null
####---Reverse Zone---
echo
echo "Copying reverse zone"
cat > 'mydb-for-172.17.15' << EOF
\$TTL    3D
@	IN	SOA     toronto.towns.ontario.ops.	hostmaster.towns.ontario.(
        2018191003	 ; Serial
                2D	; Refresh
                6H	; Retry
                1W	; Expire
                1D	; Negative Cache TTL
);
@               IN	NS	toronto.towns.ontario.ops.
@               IN	NS	ottawa.towns.ontario.ops.
2               IN	PTR     toronto.towns.ontario.ops.
3               IN	PTR     ottawa.towns.ontario.ops.
1               IN	PTR     york.towns.ontario.ops.
100             IN	PTR     cloyne.towns.ontario.ops.
5               IN	PTR     kingston.towns.ontario.ops.
6               IN	PTR     coburg.towns.ontario.ops.
8               IN	PTR     milton.towns.ontario.ops.

EOF
check "scp 'mydb-for-172.17.15' root@172.17.15.2:/var/named/ > /dev/null " "Error when copying Reverse Zone file to TORONTO"
rm -rf 'mydb-for-172.17.15' > /dev/null
echo "Running iptables"
cat > ruleto.bash << EOF
#!/bin/bash

systemctl start iptables
systemctl enable iptables
sleep 2
iptables -t filter -F
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p icmp -s 172.17.15.0/24 -j ACCEPT
iptables -A INPUT -p tcp -s 172.17.15.1 --dport 22 -j ACCEPT
iptables -A INPUT -j DROP

iptables -A FORWARD -j DROP
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -j ACCEPT

echo "search towns.ontario.ops" > /etc/resolv.conf
echo "nameserver 172.17.15.2" >> /etc/resolv.conf
echo "toronto.towns.ontario.ops" > /etc/hostname

systemctl stop NetworkManager
systemctl disable NetworkManager
systemctl start named
systemctl enable named
sleep 3

iptables-save > /etc/sysconfig/iptables
service iptables save > /dev/null 2>&1
sleep 3



EOF

#### Network Configuration for TORONTO ######
check "ssh root@172.17.15.2 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-eth0 > ipconto.txt" "File or directory not exist"
echo "DNS1="127.0.0.1"" >> ipconto.txt
echo "PEERDNS=no" >> ipconto.txt
echo "DOMAIN=towns.ontario.ops" >> ipconto.txt
check "scp ipconto.txt root@172.17.15.2:/etc/sysconfig/network-scripts/ifcfg-eth0 > /dev/null" "Go find the errors yourself :D"
rm -rf ipconto.txt > /dev/null

check "scp ruleto.bash root@172.17.15.2:/root" "So tired to check all the errors"
rm -rf ruleto.bash > /dev/null
check "ssh root@172.17.15.2 bash ruleto.bash " "Can not excute script on Toronto machince, go there physically and run it"
echo -e "#########\e[32mToronto Done \e[0m#################"
sleep 2


### Ottawa Configuration###
echo "################################################"
echo "##############Configuring Ottawa################"
echo "################################################"
### Etc/named.conf

cat > named.conf << EOF
options {
	directory "/var/named";
        allow-query { localhost; 172.17.15.0/24; };
        recursion no;
};


zone "." IN {
	type hint;
        file "named.ca";
};

zone "towns.ontario.ops" IN {
        type slave;
        masters {172.17.15.2;};
        masterfile-format text;
        file "slaves/mydb-for-towns.ontario.ops";
        allow-update {none;};
};

zone "15.17.172.in-addr.arpa." IN {
        type slave;
        masters {172.17.15.2;};
        masterfile-format text;
        file "slaves/mydb-for-172.17.15";
        allow-update {none;};

};

EOF
check "scp named.conf root@172.17.15.3:/etc > /dev/null " "Error when copying Named.conf file to OTTAWA"
rm -rf named.conf > /dev/null

### IPTables in Ottawa

cat > ruleot.bash << EOF
#!/bin/bash
systemctl start iptables
systemctl enable iptables
sleep 2
iptables -t filter -F
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p udp --dport 53 -s 172.17.15.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -s 172.17.15.0/24 -j ACCEPT
iptables -A INPUT -p icmp -s 172.17.15.0/24 -j ACCEPT
iptables -A INPUT -p tcp -s 172.17.15.1 --dport 22 -j ACCEPT
iptables -A INPUT -j DROP

iptables -A FORWARD -j DROP
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -j ACCEPT

echo "ottawa.towns.ontario.ops" > /etc/hostname
echo "search towns.ontario.ops" > /etc/resolv.conf
echo "nameserver 172.17.15.2" >> /etc/resolv.conf

systemctl start named
systemctl enable named
systemctl stop NetworkManager
systemctl disable NetworkManager
sleep 3

iptables-save > /etc/sysconfig/iptables
service iptables save > /dev/null 2>&1
sleep 3


EOF

#### Network Configuration for OTTAWA ######
check "ssh root@172.17.15.3 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-eth0 > ipconot.txt " "Can not obtain ipconfig from OTTAWA"
echo "DNS1="127.0.0.1"" >> ipconot.txt
echo "DNS2="172.17.15.2"" >> ipconot.txt
echo "PEERDNS=no" >> ipconot.txt
echo "DOMAIN=towns.ontario.ops" >> ipconot.txt
check "scp ipconot.txt root@172.17.15.3:/etc/sysconfig/network-scripts/ifcfg-eth0 " "Can not copy ipconfig file to OTTAWA"
rm -rf ipconot.txt > /dev/null

check "scp ruleot.bash root@172.17.15.3:/root " "Can not copy bash script to OTTAWA"
rm -rf ruleot.bash > /dev/null
check "ssh root@172.17.15.3 bash ruleot.bash " "Can not excute the script on OTTAWA"
echo -e "##################\e[32mOttawa Done \e[0m######################"
sleep 2


####Configuring Cloyne Machine
echo "################################################"
echo "##############Configuring CLOYNE################"
echo "################################################"
cat > rulecl.bash << EOF
#!/bin/bash

systemctl start iptables
systemctl enable iptables
sleep 2

iptables -t filter -F
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p icmp -s 172.17.15.0/24 -j ACCEPT
iptables -A INPUT -p tcp -s 172.17.15.1 --dport 22 -j ACCEPT
iptables -A INPUT -j DROP

iptables -A FORWARD -j DROP
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -j ACCEPT

echo "search towns.ontario.ops" > /etc/resolv.conf
echo "nameserver 172.17.15.2" >> /etc/resolv.conf
echo "nameserver 172.17.15.3" >> /etc/resolv.conf

systemctl stop NetworkManager
systemctl disable NetworkManager

echo "cloyne.towns.ontario.ops" > /etc/hostname

iptables-save > /etc/sysconfig/iptables
service iptables save > /dev/null 2>&1
sleep 3


EOF

#### Network Configuration for CLOYNE ######
check "ssh root@172.17.15.100 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-eth0 > ipconcl.txt " "Error when obtaining ipconfig file to Cloyne"
echo "DNS1="172.17.15.2"" >> ipconcl.txt
echo "DNS2="172.17.15.3"" >> ipconcl.txt
echo "PEERDNS=no" >> ipconcl.txt
echo "DOMAIN=towns.ontario.ops" >> ipconcl.txt
check "scp ipconcl.txt root@172.17.15.100:/etc/sysconfig/network-scripts/ifcfg-eth0 > /dev/null " "Error when copying ipconfig file to CLOYNE"
rm -rf ipconcl.txt > /dev/null

check "scp rulecl.bash root@172.17.15.100:/root > /dev/null" "Error when copy the script to Cloyne"
rm -rf rulecl.bash > /dev/null
check "ssh root@172.17.15.100 bash rulecl.bash " "Error when trying to excute script file from CLOYNE"
echo -e "##############\e[32mCloyne Done \e[0m###############"
sleep 2
echo 
echo


####### Configuring C7Host #####
echo "################################################"
echo "##############Configuring C7Host################"
echo "################################################"
echo "Config named.conf of C7Host"

sed -i 's/allow-query.*;$/allow-query {localhost;192.168.40.0\/24;172.17.15.0\/24;'$digit'.0\/24;};/' /etc/named.conf
sed -i 's/forwarders.*;$/forwarders { 192.168.40.2;172.17.15.2;172.17.15.3; };/' /etc/named.conf

###Backing up system, make new folders
for f in $list_vms
do
	check "mkdir -p /backup/incremental/cloning-source/$f > /dev/null " "Can not create folders"
done

### Im so lazy to find the shorter way
### Crontab
crontab -l | { cat; echo "0 * * * * rsync -avz 172.17.15.2:/etc /backup/incremental/cloning-source/toronto"; } | crontab -
crontab -l | { cat; echo "0 * * * * rsync -avz 172.17.15.3:/etc /backup/incremental/cloning-source/ottawa"; } | crontab -
crontab -l | { cat; echo "0 * * * * rsync -avz 172.17.15.100:/etc /backup/incremental/cloning-source/cloyne"; } | crontab -
rsync -avz 172.17.15.2:/etc /backup/incremental/cloning-source/toronto >> test.txt
rsync -avz 172.17.15.3:/etc /backup/incremental/cloning-source/ottawa >> test.txt
rsync -avz 172.17.15.100:/etc /backup/incremental/cloning-source/cloyne >> test.txt
#### Reboot system

echo "Shutting down all VMs in progress"
for e in $list_vms
do 
	virsh shutdown $e
	while [ "$(virsh domstate $e | head -1 | grep ^running$ )" == "running" ]
	do
  		echo "Wait until vm $e is down"
        sleep 1
        
	done

done
####Reset iptables on C7Host
#echo "Iptables is restarting"
#systemctl restart libvirtd
#iptables-save > /etc/sysconfig/iptables
#service iptables save
sleep 3
echo "####################################"
echo -e "\e[32mAll processes are done. Good luck \e[0m"
#echo "####################################"
#echo "System is going to reboot in a few seconds"
#sleep 10
#init 6































