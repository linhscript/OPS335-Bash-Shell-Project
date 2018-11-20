function clone-machine {
	echo "Checking clone machine"
	for vm in ${vms_name[@]}
	do 
		if ! virsh list --all | grep -iqs $vm
		then
			echo "Turning on cloyne"
			virsh start cloyne 2> /dev/null
			while ! eval "ping 172.17.15.100" 
			do
				"Cloyne machine is starting"
			done
			check "ssh -o ConnectTimeout=5 172.17.15.100" "Can not SSH to Cloyne, check and run the script again"
			intcloyne=$( ssh 172.17.15.100 '( ifconfig | grep -B 1 172.17.15 | head -1 | cut -d: -f1 )' )  #### grab interface infor (some one has ens3)
			maccloyne=$(ssh 172.17.15.100 grep "^HW.*" /etc/sysconfig/network-scripts/ifcfg-$intcloyne) #### grab mac address
			ssh 172.17.15.100 "sed 's/'$mac'/#'$mac'/g' /etc/sysconfig/network-scripts/ifcfg-$intcloyne " #ssh to cloyne and comment mac address
			echo -e "\e[32Cloyne machine info has been collected\e[m"
			virsh destroy cloyne			
			echo -e "\e[33mCloning $vm \e[m"
			virt-clone --auto-clone -o cloyne --name $vm
		fi
	done

}	

#Check if it needs to clone any machine =>Yes=> turn on cloyne => ssh to cloyne => Comment Mac address > Turnoff cloyne => Clone machine => Turn on that machine with out turnning on cloyne
#=> ssh to new machine with cloyne ip address => Also dumpxml to get infor => uncomment mac and replace with new mac => Change IP, hostname => restart machine 