#!/bin/bash
### ALL INPUT BEFORE CHECKING #### -------------------
		### INPUT from USER ###
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
	if [ -z $username ] || [ -z $fullname ] || [ -z $password ]
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
	   		echo $2
	   		echo
	   		exit 1
	fi	

}
# Autostart Toronto
virsh start milton > /dev/null 2>&1
virsh start toronto > /dev/null 2>&1
echo -e "\e[35mTurn on AutoStart Toronto\e[m"
virsh autostart toronto

# Remove /document
ssh 172.17.15.8 "rm -rf /documents"

# Create SAMBA users,folders,groups,add user to group, give permissons
miltonusers="$username-1 $username-2 $username-admin"
for users in $miltonusers
do
	# Create regular user
	echo -e "\e[1;35mCreate user $users\e[m"
	ssh 172.17.15.8 useradd -m $users 2> /dev/null
	ssh 172.17.15.8 '( echo '$users:$password' | chpasswd )'

	ssh 172.17.15.8 mkdir -p /documents/private/$users 2> /dev/null
done
ssh 172.17.15.8 mkdir -p /documents/shared/readonly 2> /dev/null
ssh 172.17.15.8 mkdir -p /documents/shared/readwrite 2> /dev/null
# Restart service
ssh 172.17.15.8 systemctl restart smb

# Overwrite SMB.CONF

cat > smb.conf << EOF

[global]
workgroup = WORKGROUP 
server string = $fullname-Assignment2
encrypt passwords = yes
smb passwd file = /etc/samba/smbpasswd
hosts allow = 172.17.15. 127.0.0.1
  
[$username-1]
comment = Assignment2
path = /documents/private/$username-1
public = no
writable = yes
printable = no
create mask = 0765
valid users = $username-1 $username-admin

[$username-2]
comment = Assignment2
path = /documents/private/$username-2
public = no
writable = yes
printable = no
create mask = 0765
valid users = $username-2 $username-admin

[$username-admin]
comment = Assignment2
path = /documents/private/$username-admin
public = no
writable = yes
printable = no
create mask = 0765
valid users = $username-admin

[readonly]
comment = Assignment2
path = /documents/shared/readonly
public = no
writable = yes
read list = $username-1 $username-2
write list = $username-admin
printable = no


[readwrite]
comment = Assignment2
path = /documents/shared/readwrite
public = no
writable = yes
printable = no
create mask = 0765
valid users = $username-1 $username-2 $username-admin 

EOF
check "scp smb.conf 172.17.15.8:/etc/samba/smb.conf " "Error when trying to copy SMB.CONF"
rm -rf smb.conf

# Restart service
check "ssh 172.17.15.8 systemctl restart smb" "Can not restart SMB Service"