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
		vms_name=(vm2 vm3)   
		vms_ip=(192.168.$digit.3 192.168.$digit.4)	
		
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


### Start configuarion VM2: SMTP Machine
# Network and hostname 
intvm2=$( ssh 192.168.$digit.3 '( ip ad | grep -B 2 192.168.$digit | head -1 | cut -d" " -f2 | cut -d: -f1 )' )
ssh 192.168.$digit.3 "echo vm3.$domain > /etc/hostname"
check "ssh 192.168.$digit.3 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-$intvm2 > ipconf.txt" "File or directory not exist"
echo "DNS1="192.168.$digit.1"" >> ipconf.txt
echo "PEERDNS=no" >> ipconf.txt
echo "DOMAIN=$domain" >> ipconf.txt
check "scp ipconf.txt 192.168.$digit.3:/etc/sysconfig/network-scripts/ifcfg-$intvm2 > /dev/null" "Can not copy ipconf to VM2"
rm -rf ipconf.txt > /dev/null

# Create user
echo -e "\e[1;35mCreate regular user\e[m"
ssh 192.168.$digit.3 useradd -m $username 2> /dev/null
ssh 192.168.$digit.3 '( echo '$username:$password' | chpasswd )'
echo -e "\e[32mUser Created \e[m"

# Install packages
echo -e "\e[1;35mInstall packages\e[m"
check "ssh 192.168.$digit.3 yum install -y mailx postfix" "Can not install mailx and postfix"
echo -e "\e[32mDone Installation \e[m"
ssh 192.168.$digit.3 setenforce permissive
check "ssh 192.168.$digit.3 systemctl start postfix" "Can not start services on VM2"
check "ssh 192.168.$digit.3 systemctl enable postfix" "Can not enable services on VM2"

# /Etc/main.cf file
cat > main.cf << EOF
queue_directory = /var/spool/postfix
command_directory = /usr/sbin
daemon_directory = /usr/libexec/postfix
data_directory = /var/lib/postfix
mail_owner = postfix
mydomain = $domain
myorigin = \$mydomain
inet_interfaces = all
inet_protocols = all
mydestination =  \$myhostname
unknown_local_recipient_reject_code = 550
relayhost = vm3.$mydomain
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

check "scp main.cf 192.168.$digit.3:/etc/postfix/main.cf" "Can not copy main.cf to VM2 "
rm -rf main.cf > /dev/null
sleep 2

# Iptables
ssh 192.168.$digit.3 iptables -C INPUT -p tcp --dport 25 -j ACCEPT 2> /dev/null || ssh 192.168.$digit.3 iptables -I INPUT -p tcp --dport 25 -j ACCEPT
ssh 192.168.$digit.3 iptables -C INPUT -p udp --dport 25 -j ACCEPT 2> /dev/null || ssh 192.168.$digit.3 iptables -I INPUT -p udp --dport 25 -j ACCEPT
ssh 192.168.$digit.3 iptables-save > /etc/sysconfig/iptables
ssh 192.168.$digit.3 service iptables save
ssh 192.168.$digit.3 systemctl restart postfix
## --------VM2 DONE------------ ####

######################### VM3 MACHINE

# Network and hostname 
intvm3=$( ssh 192.168.$digit.4 '( ip ad | grep -B 2 192.168.$digit | head -1 | cut -d" " -f2 | cut -d: -f1 )' )
ssh 192.168.$digit.4 "echo vm3.$domain > /etc/hostname"
check "ssh 192.168.$digit.4 grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-$intvm3 > ipconf.txt" "File or directory not exist"
echo "DNS1="192.168.$digit.1"" >> ipconf.txt
echo "PEERDNS=no" >> ipconf.txt
echo "DOMAIN=$domain" >> ipconf.txt
check "scp ipconf.txt 192.168.$digit.4:/etc/sysconfig/network-scripts/ifcfg-$intvm3 > /dev/null" "Can not copy ipconf to VM3"
rm -rf ipconf.txt > /dev/null

# Create user
echo -e "\e[1;35mCreate regular user\e[m"
ssh 192.168.$digit.4 useradd -m $username 2> /dev/null
ssh 192.168.$digit.4 '( echo '$username:$password' | chpasswd )'
echo -e "\e[32mUser Created \e[m"

# Install packages
echo -e "\e[1;35mInstall packages\e[m"
check "ssh 192.168.$digit.4 yum install -y mailx postfix dovecot" "Can not install mailx and postfix and dovecot"
echo -e "\e[32mDone Installation \e[m"
ssh 192.168.$digit.4 setenforce permissive
check "ssh 192.168.$digit.4 systemctl start postfix" "Can not start services on VM3"
check "ssh 192.168.$digit.4 systemctl start dovecot" "Can not start services on VM3"
check "ssh 192.168.$digit.4 systemctl enable postfix" "Can not enable services on VM3"
check "ssh 192.168.$digit.4 systemctl enable dovecot" "Can not enable services on VM3"
# /Etc/postfix/main.cf
cat > main.cf << EOF
queue_directory = /var/spool/postfix
command_directory = /usr/sbin
daemon_directory = /usr/libexec/postfix
data_directory = /var/lib/postfix
mail_owner = postfix
mydomain = $domain
myorigin = \$mydomain
inet_interfaces = all
inet_protocols = all
mydestination = \$mydomain,\$myhostname, localhost.\$mydomain, localhost
unknown_local_recipient_reject_code = 550
mynetworks = 192.168.$digit.0/24, 127.0.0.0/8
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

check "scp main.cf 192.168.$digit.4:/etc/postfix/main.cf" "Can not copy main.cf to VM3 "
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
check "scp 10-mail.conf 192.168.$digit.4:/etc/dovecot/conf.d/10-mail.conf" "Can not copy 10-mail.conf to VM3 "
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
postmaster_address = $domain

EOF
check "scp dovecot.conf 192.168.$digit.4:/etc/dovecot/dovecot.conf" "Can not copy dovecot.conf to VM3 "
rm -rf dovecot.conf > /dev/null	
sleep 2

# 10-auth.conf
cat > 10-auth.conf << EOF
disable_plaintext_auth = no
auth_mechanisms = plain
!include auth-system.conf.ext

EOF
check "scp 10-auth.conf  192.168.$digit.4:/etc/dovecot/conf.d/10-auth.conf" "Can not copy 10-auth.conf  to VM3 "
rm -rf 10-auth.conf  > /dev/null
sleep 2

# 10-ssl.conf
cat > 10-ssl.conf << EOF
ssl = yes
ssl_cert = </etc/pki/dovecot/certs/dovecot.pem
ssl_key = </etc/pki/dovecot/private/dovecot.pem

EOF
check "scp 10-ssl.conf 192.168.$digit.4:/etc/dovecot/conf.d/10-ssl.conf" "Can not copy 10-ssl.conf to VM3 "
rm -rf 10-ssl.conf > /dev/null
sleep 2

# Aliases

ssh 192.168.$digit.4 "sed -i 's/^#root.*/root = "$username"/' /etc/aliases "


# Iptables
echo -e "\e[1;35mAdding iptables rules\e[m"
ssh 192.168.$digit.4 iptables -C INPUT -p tcp --dport 143 -s 192.168.$digit.0/24 -j ACCEPT 2> /dev/null || ssh 192.168.$digit.4 iptables -I INPUT -p tcp --dport 143 -s 192.168.$digit.0/24 -j ACCEPT
ssh 192.168.$digit.4 iptables -C INPUT -p tcp --dport 25 -j ACCEPT 2> /dev/null || ssh 192.168.$digit.4 iptables -I INPUT -p tcp --dport 25 -j ACCEPT
ssh 192.168.$digit.4 iptables -C INPUT -p udp --dport 25 -j ACCEPT 2> /dev/null || ssh 192.168.$digit.4 iptables -I INPUT -p udp --dport 25 -j ACCEPT
ssh 192.168.$digit.4 iptables-save > /etc/sysconfig/iptables
ssh 192.168.$digit.4 service iptables save
ssh 192.168.$digit.4 systemctl restart postfix
ssh 192.168.$digit.4 systemctl restart dovecot

## --------VM3 DONE------------ ####