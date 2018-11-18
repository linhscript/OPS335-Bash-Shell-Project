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
IP=$(cat /var/named/mydb-for-* | grep ^vm1 | head -1 | awk '{print $4}')
digit=$(cat /var/named/mydb-for-* | grep ^vm2 | head -1 | awk '{print $4}' | cut -d. -f3)


echo "\e[1;35mRestarting Named\e[m"
systemctl restart named
echo -e "\e[32mRestarted Done \e[m"


### Start CONFIGURATION ###

## KINGSTON MACHINE ###

# Network and hostname 

ssh 172.17.15.5 echo kingston.towns.ontario.ops > /etc/hostname
check "ssh 172.17.15.5 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-eth0 > ipconf.txt" "File or directory not exist"
echo "DNS1="172.17.15.2"" >> ipconf.txt
echo "DNS2="172.17.15.3"" >> ipconf.txt
echo "PEERDNS=no" >> ipconf.txt
echo "DOMAIN=towns.ontario.ops" >> ipconf.txt
check "scp ipconf.txt 172.17.15.5:/etc/sysconfig/network-scripts/ifcfg-eth0 > /dev/null" "Can not copy ipconf to KINGSTON"
rm -rf ipconf.txt > /dev/null

# Create user
echo -e "\e[1;35mCreate regular user\e[m"
ssh 172.17.15.5 useradd -m $username 2> /dev/null
ssh 172.17.15.5 '( echo '$username:$password' | chpasswd )'
echo -e "\e[32mUser Created \e[m"

# Install packages
echo -e "\e[1;35mInstall packages\e[m"
check "ssh 172.17.15.5 yum install -y mailx postfix" "Can not install mailx and postfix"
echo -e "\e[32mDone Installation \e[m"
check "ssh 172.17.15.5 systemctl start postfix" "Can not start services on COBURG"
check "ssh 172.17.15.5 systemctl enable postfix" "Can not enable services on COBURG"

# /Etc/main.cf file
cat > main.cf << EOF
queue_directory = /var/spool/postfix
command_directory = /usr/sbin
daemon_directory = /usr/libexec/postfix
data_directory = /var/lib/postfix
mail_owner = postfix
mydomain = towns.ontario.ops
myorigin = \$mydomain
inet_interfaces = all
inet_protocols = all
mydestination =  \$myhostname
unknown_local_recipient_reject_code = 550
relayhost = coburg.towns.ontario.ops
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
debug_peer_level = 2
debugger_command =
	 PATH=/bin:/usr/bin:/usr/local/bin:/usr/X11R6/bin
	 ddd \$daemon_directory/\$process_name \$process_id & sleep 5
sendmail_path = /usr/sbin/sendmail.postfix
newaliases_path = /usr/bin/newaliases.postfix
mailq_path = /usr/bin/mailq.postfix
setgid_group = postdrop
html_directory = no
manpage_directory = /usr/share/man
sample_directory = /usr/share/doc/postfix-2.10.1/samples
readme_directory = /usr/share/doc/postfix-2.10.1/README_FILES
 
EOF

check "scp main.cf 172.17.15.5:/etc/postfix/main.cf" "Can not copy main.cf to kingston "
rm -rf main.cf > /dev/null
sleep 2

# Iptables
ssh 172.17.15.5 iptables -C INPUT -p tcp --dport 143 -s 172.17.15.0/24 -j ACCEPT > /dev/null || ssh 172.17.15.5 iptables -I INPUT -p tcp --dport 143 -s 172.17.15.0/24 -j ACCEPT

## --------KINGSTON DONE------------ ####

## COBURG MACHINE

# Network and hostname 

ssh 172.17.15.6 echo coburg.towns.ontario.ops > /etc/hostname
check "ssh 172.17.15.6 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-eth0 > ipconf.txt" "File or directory not exist"
echo "DNS1="172.17.15.2"" >> ipconf.txt
echo "DNS2="172.17.15.3"" >> ipconf.txt
echo "PEERDNS=no" >> ipconf.txt
echo "DOMAIN=towns.ontario.ops" >> ipconf.txt
check "scp ipconf.txt 172.17.15.6:/etc/sysconfig/network-scripts/ifcfg-eth0 > /dev/null" "Can not copy ipconf to COBURG"
rm -rf ipconf.txt > /dev/null

# Create user
echo -e "\e[1;35mCreate regular user\e[m"
ssh 172.17.15.6 useradd -m $username 2> /dev/null
ssh 172.17.15.6 '( echo '$username:$password' | chpasswd )'
echo -e "\e[32mUser Created \e[m"

# Install packages
echo -e "\e[1;35mInstall packages\e[m"
check "ssh 172.17.15.6 yum install -y mailx postfix dovecot" "Can not install mailx and postfix and dovecot"
echo -e "\e[32mDone Installation \e[m"
check "ssh 172.17.15.6 systemctl start postfix && systemctl start dovecot" "Can not start services on COBURG"
check "ssh 172.17.15.6 systemctl enable postfix && systemctl enable dovecot" "Can not enable services on COBURG"
# /Etc/postfix/main.cf
cat > main.cf << EOF
queue_directory = /var/spool/postfix
command_directory = /usr/sbin
daemon_directory = /usr/libexec/postfix
data_directory = /var/lib/postfix
mail_owner = postfix
mydomain = towns.ontario.ops
myorigin = \$mydomain
inet_interfaces = all
inet_protocols = all
mydestination = \$mydomain,\$myhostname, localhost.\$mydomain, localhost
unknown_local_recipient_reject_code = 550
mynetworks = 172.17.15.0/24, 127.0.0.0/8
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mailbox_command = /usr/libexec/dovecot/dovecot-lda -f "\$SENDER" -a "\$RECIPIENT"
debug_peer_level = 2
debugger_command =
	 PATH=/bin:/usr/bin:/usr/local/bin:/usr/X11R6/bin
	 ddd \$daemon_directory/\$process_name \$process_id & sleep 5
sendmail_path = /usr/sbin/sendmail.postfix
newaliases_path = /usr/bin/newaliases.postfix
mailq_path = /usr/bin/mailq.postfix
setgid_group = postdrop
html_directory = no
manpage_directory = /usr/share/man
sample_directory = /usr/share/doc/postfix-2.10.1/samples
readme_directory = /usr/share/doc/postfix-2.10.1/README_FILES

EOF

check "scp main.cf 172.17.15.6:/etc/postfix/main.cf" "Can not copy main.cf to coburg "
rm -rf main.cf > /dev/null
sleep 2

# 10-mail.conf
cat > 10-mail.conf << EOF
mail_location = maildir:~/mailboxes:LAYOUT=fs
namespace inbox {
  inbox = yes
}
first_valid_uid = 1000
mbox_write_locks = fcntl

EOF
check "scp 10-mail.conf 172.17.15.6:/etc/dovecot/conf.d/10-mail.conf" "Can not copy 10-mail.conf to coburg "
rm -rf 10-mail.conf > /dev/null
sleep 2

# dovecot.conf
cat > dovecot.conf << EOF
protocols = imap
dict {
  #quota = mysql:/etc/dovecot/dovecot-dict-sql.conf.ext
  #expire = sqlite:/etc/dovecot/dovecot-dict-sql.conf.ext
}
!include conf.d/*.conf
!include_try local.conf
postmaster_address = towns.ontario.ops

EOF
check "scp dovecot.conf 172.17.15.6:/etc/dovecot/dovecot.conf" "Can not copy dovecot.conf to coburg "
rm -rf dovecot.conf > /dev/null
sleep 2

# 10-auth.conf
cat > 10-auth.conf << EOF
ssl = yes
ssl_cert = </etc/pki/dovecot/certs/dovecot.pem
ssl_key = </etc/pki/dovecot/private/dovecot.pem

EOF
check "scp 10-auth.conf  172.17.15.6:/etc/dovecot/conf.d/10-auth.conf" "Can not copy 10-auth.conf  to coburg "
rm -rf 10-auth.conf  > /dev/null
sleep 2

# 10-ssl.conf
cat > 10-ssl.conf << EOF
ssl = yes
ssl_cert = </etc/pki/dovecot/certs/dovecot.pem
ssl_key = </etc/pki/dovecot/private/dovecot.pem

EOF
check "scp 10-ssl.conf 172.17.15.6:/etc/dovecot/conf.d/10-ssl.conf" "Can not copy 10-ssl.conf to coburg "
rm -rf 10-ssl.conf > /dev/null
sleep 2

# Aliases

ssh 172.17.15.6 "sed 's/^#root.*/root = "$username"/' /etc/aliases "


# Iptables
ssh 172.17.15.6 iptables -C INPUT -p tcp --dport 143 -s 172.17.15.0/24 -j ACCEPT > /dev/null || ssh 172.17.15.6 iptables -I INPUT -p tcp --dport 143 -s 172.17.15.0/24 -j ACCEPT

## --------COBURG DONE------------ ####


## MILTON MACHINE
# Network and hostname 

ssh 172.17.15.8 echo milton.towns.ontario.ops > /etc/hostname
check "ssh 172.17.15.8 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-eth0 > ipconf.txt" "File or directory not exist"
echo "DNS1="172.17.15.2"" >> ipconf.txt
echo "DNS2="172.17.15.3"" >> ipconf.txt
echo "PEERDNS=no" >> ipconf.txt
echo "DOMAIN=towns.ontario.ops" >> ipconf.txt
check "scp ipconf.txt 172.17.15.8:/etc/sysconfig/network-scripts/ifcfg-eth0 > /dev/null" "Can not copy ipconf to MILTON"
rm -rf ipconf.txt > /dev/null

# Create user
echo -e "\e[1;35mCreate regular user\e[m"
ssh 172.17.15.8 useradd -m $username 2> /dev/null
ssh 172.17.15.8 '( echo '$username:$password' | chpasswd )'
echo -e "\e[32mUser Created \e[m"

# Install packages
echo -e "\e[1;35mInstall packages\e[m"
check "ssh 172.17.15.8 yum install -y samba*" "Can not install samba"
echo -e "\e[32mDone Installation \e[m"
check "ssh 172.17.15.8 systemctl start postfix && systemctl start dovecot" "Can not start services on COBURG"
check "ssh 172.17.15.8 systemctl enable postfix && systemctl enable dovecot" "Can not enable services on COBURG"


## --------MILTON DONE------------ ####
## TORONTO MACHINE
# MX Record
ssh 172.17.15.2 "sed 's/.*MX.*/town.ontario.ops IN A 10 coburg.towns.ontario.ops.\ntown.ontario.ops IN A 20 kingston.towns.ontario.ops./' /var/named/mydb-for-towns.ontario.ops "


# Set up iptables
#open port smtp
#some people has ens3 network card