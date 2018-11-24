#!/bin/bash
##### Check Function
list_vms="toronto ottawa cloyne"
vms="172.17.15.2 172.17.15.3 172.17.15.100"
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

echo -e "\e[1;31m--------WARNING----------"
echo -e "\e[1mBackup your virtual machine to run this script \e[0m"
echo
read -p "Did you make a backup ? [Y/N]: " choice
while [[ "$choice" != "Y" && "$choice" != "Yes" && "$choice" != "y" && "$choice" != "yes" ]]
do
	echo -e "\e[33mGo make a backup \e[0m" >&2
	exit 6
done

########## INPUT from USER #######
read -p "What is your IP Adress of VM1: " IP
fdigit=$( echo "$IP" | awk -F. '{print $1"."$2"."$3}' )
check "ifconfig | grep $fdigit > /dev/null" "Wrong Ip address of VM1"
intvm=$(ifconfig | grep -B 1 $fdigit.1 | head -1 | awk -F: '{print $1}')
echo
intclone=$(ifconfig | grep -B 1 172.17.15.1 | head -1 | awk -F: '{print $1}')
read -p "What is your Matrix account ID: " userid


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
	ssh root@$b useradd -m $userid 2> /dev/null
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

sed -i 's/allow-query.*;$/allow-query {localhost;192.168.40.0\/24;172.17.15.0\/24;'$fdigit'.0\/24;};/' /etc/named.conf
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
echo "Iptables is restarting"
systemctl restart libvirtd
iptables-save > /etc/sysconfig/iptables
service iptables save
sleep 3
echo "####################################"
echo -e "\e[32mAll processes are done. Good luck \e[0m"
echo "####################################"
echo "System is going to reboot in a few seconds"
sleep 10
init 6































