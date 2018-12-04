#!/bin/bash

### ALL INPUT BEFORE CHECKING #### -------------------

        
        ### INPUT from USER ###
clear
read -p "What is your Seneca username: " username
read -p "What is your FULL NAME: " fullname
read -s -p "Type your normal password: " password && echo
read -p "What is your IP Address of VM1: " IP
digit=$( echo "$IP" | awk -F. '{print $3}' )

domain="$username.ops"
vms_name=(vm1 vm2 vm3)   
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
    check "ssh ${dict[$ssh_vm]} "echo nameserver 8.8.8.8 >> /etc/resolv.conf"" "Can not add 8.8.8.8 to $vm"
    check "ssh ${dict[$ssh_vm]} ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA from $ssh_vm, check internet connection then run the script again"
    check "ssh ${dict[$ssh_vm]} yum update -y" "Can not YUM UPDATE from $ssh_vm"
    done
    
    ### 5.Checking jobs done from Assignment 1 -------------------------

    #check "ssh ${vms_ip[0]} host ${vms_name[0]}.$domain > /dev/null 2>&1" "Name service in ${vms_name[0]} is not working"
    
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
        ssh $1 "echo "search $domain" > /etc/resolv.conf"
        ssh $1 "echo nameserver $3 >> /etc/resolv.conf"
        ssh $1 "systemctl stop NetworkManager"
        ssh $1 "systemctl disable NetworkManager"
        rm -rf ipconf.txt > /dev/null
    fi
}
#----------------------------------------------------------------------------------------------------------------------------------------------

## START CONFIGURATION


virsh start vm1 > /dev/null 2>&1
virsh start vm2 > /dev/null 2>&1
virsh start vm3 > /dev/null 2>&1

## Installing BIND Package ######
echo 
echo "############ Installing DNS ###########"
echo 
check "yum install bind* -y" "Can not use Yum to install"
systemctl start named
systemctl enable named
echo -e "\e[32mInstalling Done\e[m"

### Making DNS configuration file ####
cat > /etc/named.conf << EOF
options {
        directory "/var/named/";
        allow-query {127.0.0.1; 192.168.$digit.0/24;};
        forwarders { 192.168.40.2; };
};
zone "." IN {
	type hint;
        file "named.ca";
};
zone "localhost" {
        type master;
        file "named.localhost";
};
zone "$username.ops" {
        type master;
        file "mydb-for-$username-ops";
};
zone "$digit.168.192.in-addr.arpa." {
        type master;
        file "mydb-for-192.168.$digit";
};
EOF

##### Making forward zone file ####

cat > /var/named/mydb-for-$username-ops << EOF
\$TTL    3D
@       IN      SOA     host.$username.ops.      hostmaster.$username.ops.(
                2018042901       ; Serial
                8H      ; Refresh
                2H      ; Retry
                1W      ; Expire
                1D      ; Negative Cache TTL
);
@       IN      NS      host.$username.ops.
host    IN      A       192.168.$digit.1
vm1		IN		A 		192.168.$digit.2
vm2		IN		A 		192.168.$digit.3
vm3		IN		A 		192.168.$digit.4

EOF

##### Making reverse zone file  #####

cat > /var/named/mydb-for-192.168.$digit << EOF

\$TTL    3D
@       IN      SOA     host.$username.ops.      hostmaster.$username.ops.(
                2018042901       ; Serial
                8H      ; Refresh
                2H      ; Retry
                1W      ; Expire
                1D      ; Negative Cache TTL
);
@       IN      NS      host.$username.ops.
1       IN      PTR     host.$username.ops.
2		IN		PTR		vm1.$username.ops.
3		IN		PTR		vm2.$username.ops.
4		IN		PTR		vm3.$username.ops.

EOF
	
echo	
echo -e "###\e[32mFiles Added Done\e[m###"
echo
#### Adding DNS and DOMAIN ####


if [ ! -f /etc/sysconfig/network-scripts/ifcfg-ens33.backup ]
then
	cp /etc/sysconfig/network-scripts/ifcfg-ens33 /etc/sysconfig/network-scripts/ifcfg-ens33.backup
fi
grep -v -i -e "^DNS.*" -e "^DOMAIN.*" /etc/sysconfig/network-scripts/ifcfg-ens33 > ipconf.txt
scp ipconf.txt /etc/sysconfig/network-scripts/ifcfg-ens33
echo "DNS1=192.168.$digit.1" >> /etc/sysconfig/network-scripts/ifcfg-ens33
echo "DOMAIN=$username.ops" >> /etc/sysconfig/network-scripts/ifcfg-ens33
echo host.$domain > /etc/hostname
rm -rf ipconf.txt


#### Adding rules in IPtables ####
grep -v ".*INPUT.*dport 53.*" /etc/sysconfig/iptables > iptables.txt
scp iptables.txt /etc/sysconfig/iptables
iptables -I INPUT -p tcp --dport 53 -j ACCEPT
iptables -I INPUT -p udp --dport 53 -j ACCEPT
iptables-save > /etc/sysconfig/iptables
service iptables save
rm -rf iptables.txt

### Remove hosts in the previous lab ###
grep -v -i -e ".*vm.*" /etc/hosts > host.txt
scp host.txt /etc/hosts
echo "search $domain" > /etc/resolv.conf
echo "nameserver 192.168.${digit}.1" >> /etc/resolv.conf


systemctl restart iptables
systemctl restart named


clear
echo	
echo -e "###\e[32mConfiguration Done\e[m###"
echo

### CONFIG USERNAME, HOSTNAME, DOMAIN VM1,2,3
for vm in ${!dict[@]}
do
    echo "CONFIGURING $vm"
    echo "Just waiting...."
    vminfo ${dict[$vm]} $vm 192.168.$digit.1 ## Need some arguments such as: IP HOSTNAME DNS1 DNS2 
done

echo -e "\e[1;32m COMPLETED\e[m"







