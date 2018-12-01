#!/bin/bash

#############################################################################################################
### INPUT from USER ###
clear
read -p "What is your Seneca username: " username
read -p "What is your FULL NAME: " fullname
read -s -p "Type your normal password: " password && echo
IP=$(cat /var/named/mydb-for-* | grep ^vm1 | head -1 | awk '{print $4}')
digit=$(cat /var/named/mydb-for-* | grep ^vm2 | head -1 | awk '{print $4}' | cut -d. -f3)

### ALL INPUT BEFORE CHECKING #### -------------------
domain="$username.ops"
vms_name=(vm1 vm2 vm3)   
vms_ip=(192.168.$digit.2 192.168.$digit.3 192.168.$digit.4)
		
#### Create Hash Table -------------------------------
		
for (( i=0; i<${#vms_name[@]};i++ ))
do
declare -A dict
	dict+=(["${vms_name[$i]}"]="${vms_ip[$i]}")
done
###############################################################################################################

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
	     		echo $2
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

		### 3.Checking VMs need to be clone and status ----------------------------------

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
	
	echo "Checking SSH,PING,YUM"	
	for ssh_vm in ${!dict[@]} ## -- Checking VMS -- ## KEY
	do
	check "ssh -o ConnectTimeout=5 -oStrictHostKeyChecking=no ${dict[$ssh_vm]} ls > /dev/null" "Can not SSH to $ssh_vm, check and run the script again "
	check "ssh ${dict[$ssh_vm]} ping -c 3 google.ca > /dev/null" "Can not ping GOOGLE.CA from $ssh_vm, check internet connection then run the script again"
	check "ssh ${dict[$ssh_vm]} yum update -y" "Can not YUM UPDATE from $ssh_vm"
	done
	
	### 5.Checking jobs done from Assignment 1 -------------------------

	check "ssh ${vms_ip[0]} host ${vms_name[0]}.$domain > /dev/null 2>&1" "Name service in ${vms_name[0]} is not working"
	
}
require

## Start configuration
## VM1 CONFIGURATION ######

# Installing Package
echo 
echo "############ Installing APACHE Server ###########"
echo 
check "ssh ${dict[vm1]} yum install httpd mariadb-server mariadb policycoreutils-python wget php php-mysql php-fpm php* -y --skip-broken" "Can not use Yum to install"
ssh ${dict[vm1]} "systemctl start httpd && systemctl enable httpd"
ssh ${dict[vm1]} "systemctl start mariadb && systemctl enable mariadb"
echo -e "\e[32mInstalling Done\e[m"

# Config Apache
ssh ${dict[vm1]} "echo "Hello, this is a web page on vm1.youruserid.ops and the current time is Mar 28 22:16:27 EDT 2016!" > /var/www/html/index.html"
if ! grep "Directory.*/html/private" /etc/httpd/conf/httpd.conf
then
cat >> /etc/httpd/conf/httpd.conf <<EOF
<Directory "/var/www/html/private">
  AllowOverride None
  Require ip 192.168.${digit}.0/24
</Directory>
EOF
fi

ssh ${dict[vm1]} mkdir -p /var/www/html/private 2> /dev/null
ssh ${dict[vm1]} "echo "Hello, this is a web page on vm1.youruserid.ops and the current time is <?php system("date"); ?>!" > /var/www/html/index.html"

cat > index.php << EOF
<?php
\$mysqli = new mysqli("localhost", "<$username>", "<$password>");
if (\$mysqli->connect_errno) {
    echo "Failed to connect to MySQL: (" . \$mysqli->connect_errno . ") " . \$mysqli->connect_error;
}
echo \$mysqli->host_info . "\n";
?>
EOF
check "scp index.php ${dict[vm1]}:/var/www/html/private/" "Cannot copy index.php to VM1"
rm -rf index.php

cat > roundcube.bash << EOF

#!/bin/bash
# Config roundcube
if test -d /var/www/html/webmail
then 
	rm -rf /var/www/html/webmail
fi
wget -P /var/www/html/webmail/ https://github.com/roundcube/roundcubemail/releases/download/1.3.8/roundcubemail-1.3.8-complete.tar.gz 
tar xvzf -C /var/www/html/webmail/ roundcubemail-1.3.8-complete.tar.gz --no-same-owner --strip-components 1
semanage fcontext -a -t httpd_log_t '/var/www/html/webmail/temp(/.*)?'
semanage fcontext -a -t httpd_log_t '/var/www/html/webmail/logs(/.*)?'
restorecon -v -R /var/www/html/webmail
setsebool -P httpd_can_network_connect 1
chown -R apache:apache /var/www/html/webmail/temp
chown -R apache:apache /var/www/html/webmail/logs


# Config database roundcube
mysql -u root -p$password -e 'DROP USER 'roundcube'@'localhost';' 2> /dev/null 
mysql -uroot -pH@v@nl1nh << sqlconf
CREATE USER roundcube@localhost identified by '\$password';
CREATE DATABASE IF NOT EXISTS roundcubemail;
GRANT ALL PRIVILEGES ON roundcubemail.* TO roundcube@localhost IDENTIFIED BY '\$password';
FLUSH PRIVILEGES;
sqlconf



EOF

# Remove script after running
scp roundcube.bash ${dict[vm1]}
rm -rf roundcube.bash
ssh ${dict[vm1]} "bash roundcube.bash"
ssh ${dict[vm1]} "rm -rf roundcube.bash"

# File config roundcube 
cat > config.inc.php << EOF
<?php
$config['db_dsnw'] = 'mysql://roundcube:$password@localhost/roundcubemail';
$config['default_host'] = 'vm3.$domain';
$config['smtp_server'] = 'vm2.$domain';
$config['support_url'] = '';
$config['des_key'] = 'LOMmLxXmsYp9XB7m00PA6RXf';
$config['plugins'] = array();

EOF
scp config.inc.php ${dict[vm1]}:/var/www/html/webmail/config/
rm -rf config.inc.php


# Config IPTABLES on VM1
ssh ${dict[vm1]} iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2> /dev/null || ssh ${dict[vm1]} iptables -I INPUT -p tcp --dport 80 -j ACCEPT
ssh ${dict[vm1]} iptables-save > /etc/sysconfig/iptables
ssh ${dict[vm1]} service iptables save