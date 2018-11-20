function clone-machine {
	echo "Checking clone machine"
	count=0
	for vm in ${vms_name[@]}
	do 
		if ! virsh list --all | grep -iqs $vm
		then
			echo "$vm need to be created"
			echo
			echo
			$count++
		fi
	done
	#----------------------------------------# Setup cloyne to be cloneable
	if [ $count -gt 0 ]
	then
		echo -e "\e[35mtart cloning machines\e[m"
		echo
		echo "Cloning in progress..."
		virsh start cloyne 2> /dev/null
		while ! eval "ping 172.17.15.100 -c 5" 
		do
			echo "Cloyne machine is starting"
			sleep 3
		done
		check "ssh -o ConnectTimeout=5 172.17.15.100" "Can not SSH to Cloyne, check and run the script again"
		intcloyne=$( ssh 172.17.15.100 '( ifconfig | grep -B 1 172.17.15 | head -1 | cut -d: -f1 )' )  #### grab interface infor (some one has ens3)
		maccloyne=$(ssh 172.17.15.100 grep "^HW.*" /etc/sysconfig/network-scripts/ifcfg-$intcloyne) #### grab mac address
		ssh 172.17.15.100 "sed 's/'$mac'/#'$mac'/g' /etc/sysconfig/network-scripts/ifcfg-$intcloyne " #ssh to cloyne and comment mac address
		check "ssh 172.17.15.5 grep -v -e '.*DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-$intcloyne > ipconf.txt" "File or directory not exist"
		echo "DNS1="172.17.15.2"" >> ipconf.txt
		echo "DNS2="172.17.15.3"" >> ipconf.txt
		echo "PEERDNS=no" >> ipconf.txt
		echo "DOMAIN=towns.ontario.ops" >> ipconf.txt
		check "scp ipconf.txt 172.17.15.100:/etc/sysconfig/network-scripts/ifcfg-$intcloyne > /dev/null" "Can not copy ipconf to Cloyne"
		rm -rf ipconf.txt > /dev/null
		sleep 2
		echo -e "\e[32Cloyne machine info has been collected\e[m"
		virsh destroy cloyne			
	fi
	#---------------------------# Start cloning
	for clonevm in ${!dict[@]} # Key (name vm)
	do 
		if ! virsh list --all | grep -iqs $clonevm
		then
			echo -e "\e[33mCloning $clonevm \e[m"
			virt-clone --auto-clone -o cloyne --name $clonevm
		fi
		#-----Turn on cloned vm without turning on cloyne machine
		virsh start $clonevm
		while ! eval "ping 172.17.15.100 -c 5" 
		do
			echo "Cloyne machine is starting"
			sleep 3
		done
		#------ get new mac address
		newmac=$(virsh dumpxml $clonevm | grep "mac address" | cut -d\' -f2)
		#-----Replace mac and ip, hostname
		ssh 172.17.15.100 "sed 's/'$mac'/'$newmac'/g' /etc/sysconfig/network-scripts/ifcfg-$intcloyne"
		ssh 172.17.15.100 "echo $clonevm.towns.ontario.ops > /etc/hostname "
		ssh 172.17.15.100 "sed 's/'172.17.15.100'/'${dict[$clonevm]}'/' /etc/sysconfig/network-scripts/ifcfg-$intcloyne"
		echo
		echo -e "\e[32mCloning Done $clonevm\e[m"
		init 6
	done


}	

#Check if it needs to clone any machine =>Yes=> turn on cloyne => ssh to cloyne => Comment Mac address > Turnoff cloyne => Clone machine => Turn on that machine with out turnning on cloyne
#=> ssh to new machine with cloyne ip address => Also dumpxml to get infor => uncomment mac and replace with new mac => Change IP, hostname => restart machine 
		
