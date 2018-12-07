#---------------------------------------#
 # OPS335CEF - Assignment 2  Check Script#
  #                                       #
   #    (Q ' ')> Fall 2018 <(' ' Q)        #
    #                                       #
     #                           Test   #
      #---------------------------------------#

#set -x

#-------User Input start --------------

section=""   # class section

#while [ -z "$section" ]
#do
	section=$(whiptail --menu "~ OPS335 - Assignment 2 ~" 15 30 3 \
			C "Section C" \
			E "Section E" \
			F "Section F" 3>&1 1>&2 2>&3)
	[ $? -ne 0 ] && exit 1
#done

#-------User Input end ----------------


#-------Settings start ----------------

	#----------------------------
 	# Assignment Specific Settings
 	#----------------------------

assignment="A2"

remoteIPs="172.17.15.2 172.17.15.5 172.17.15.6 172.17.15.8"
remoteHostnames="toronto kingston coburg milton"

sambaSharedDirectories="/documents/{shared,private}"

# Server Functions

masterdnsIP="172.17.15.2"
smtpIP="172.17.15.5"
imapIP="172.17.15.6"
sambaIP="172.17.15.8"

#remoteNetDevice="eth0" # some students has ens?? instead
	
zone1="towns.ontario.ops"

	#----------------------------
	# Instructor Information
	#----------------------------

matrixHostname="matrix.senecac.on.ca"


instructorEmail="test@senecacollege.ca"
EmailSubject="OPS335S$section$section-$assignment"


	#----------------------------
	# Color Settings
	#----------------------------

colorFAIL='\e[1;31m'  #Red
colorPASS='\e[1;34m'  #Green
colorRST='\e[0m'

#--------Settings end -----------------


#------- Functions start --------------
echo_pass()
{
	echo -e "$colorPASS$1$colorRST"
}

echo_fail()
{
	echo -e "$colorFAIL$1$colorRST"
}

# Exit Program if check fails

prerequisite_check_exit()
{
	if ( ! eval "$1" > /dev/null 2>&1 )
	then
		echo " [ $(echo_fail X ) ] $2 "
		exit 1
	fi 
	echo " [ $(echo_pass OK) ] $2 "
}

# Suspend Program if check fails

prerequisite_check_suspend()
{
	while ( ! eval "$1" > /dev/null 2>&1 )
	do
		echo " [ $(echo_fail X )  ] $2 "
		echo   - Type \"$(echo_pass fg)\" to resume once issue is resolved
		kill -TSTP $$
	done
	echo " [ $(echo_pass OK) ] $2 "
}

# Parse /etc/named.conf into single-line format to make options easier to be read by check scripts

parseDNS()
{
        local file="$1"

        local running_total=0
        local prefix=""


        while IFS= read -r line
        do
                if [ -n "$line" ] && [[ ! "$line" =~ ^(\t|[[:space:]])*[#] ]]
                then
                        if [ $running_total -le 1 ]
                        then
                                echo ""
                                echo -n "$prefix"
                        fi

                        for word in $line
                        do
                                if [ $running_total -eq 0 ]
                                then
                                        if [ -n "$prefix" ]
                                        then
                                                prefix+=" "
                                        fi
                                        prefix+=$(echo $word | sed 's/{.*//;s/}.*//')
                                fi

                        if [[ "$word" =~ \{ ]]
                        then
                                if [ $running_total -eq 0 ]
                                then
                                        word=$(echo $word| tr -d '{')
                                fi

                                running_total=$((running_total+1))
                        fi

                        if [[ "$word" =~ \} ]]
                        then
                                running_total=$((running_total-1))
                                if [ $running_total -eq 0 ]
                                then
                                        prefix=""
                                        echo -e "\n==================================="
                                        word=""
                                fi
                        fi

                        if [ -n "$word" ]
                        then
                                echo -n "$word "
                        fi

                done

        fi
        done < <(echo "$*")
}



#------- Functions end ----------------

# ------ Error Checking start --------- 
#
# Checks following before generating report:
# - logged in as root 
# - mailx is installed
# - vm is running
# - ssh No Password Login from host to root@vm (implies PermitRootLogin yes)
# - vm has internet connectivity
# - username, full name verified by matrix

prerequisite_check_exit "id -u | grep ^0$" "logged in as root"

for remoteHostname in $remoteHostnames
do
	prerequisite_check_suspend "virsh domstate $remoteHostname | head -1 | grep ^running$" "vm $remoteHostname running"
done

prerequisite_check_suspend "rpm -qi mailx" "mailx installed"

# Connectivity Check

for remoteIP in $remoteIPs
do
	# Add VMs to known_hosts
	ssh-keygen -R $remoteIP &> /dev/null
	ssh-keyscan -t rsa $remoteIP >> ~/.ssh/known_hosts 2> /dev/null

	prerequisite_check_suspend "ssh -oBatchMode=yes $remoteIP exit" "ssh $remoteIP login without password"
	prerequisite_check_suspend "ssh -oBatchMode=yes $remoteIP ping -c 1 8.8.8.8 > /dev/null" "VM $remoteIP has internet connection"
done

#: <<'+'

senecaLogin="$(who am i | awk '{print $1}')"
#fullName="$(grep $senecaLogin /etc/passwd | cut -d: -f5)"

read -p "Enter your Seneca Login: " -e -i "$senecaLogin" senecaLogin

senecaLogin=${senecaLogin:-$(who am i | awk '{print $1}')}

fullName=$(ssh -q $senecaLogin@$matrixHostname "ypcat passwd | grep $senecaLogin | cut -d: -f5")

read -p "Enter your Full Name: " -e -i "$fullName" fullName

while [ -z "$fullName" ]
do
	echo " [ $(echo_fail X )  ] Full Name cannot be empty "
	read -p "Enter your Full Name: " -e -i "$fullName" fullName
done

#+

# ------ Error Checking end --------- 

itemCount=1
totalItemCount=65 #varies, 65 + number of samba users
ppid=$$

# Run command, print exit status with formatting

getCommandExitCode()
{
	echo "# $1"
	
	if [ -z "$2" ]
	then
		eval "$1" > /dev/null 2>&1
	else
		ssh $2 "$1 > /dev/null 2>&1"
	fi	

	echo "$((itemCount++)),$?"
	kill -SIGUSR1 $ppid
}


# Run command, print output with formatting

getCommandOutput()
{
	echo "# $1"

	if [ -z "$2" ]
	then
		eval "$1" 2>&1 | sed "s/^\s*/$itemCount,/"
	else
		ssh $2 "$1 2>&1" | sed "s/^\s*/$itemCount,/"
	fi
	
	kill -SIGUSR1 $ppid
	itemCount=$((itemCount+1))
}

getReport()
{

cat <<+
#--------------------------
0,Student Name=$fullName
0,Seneca Login=$senecaLogin
#--------------------------
+
#----------------remoteHosts-------------------------
for remoteIP in $remoteIPs
do
	echo "#--------------------------"
	echo "#     $remoteIP"
	echo "#--------------------------"
	getCommandOutput "hostname" $remoteIP
	getCommandExitCode "yum check-update" $remoteIP					
	getCommandExitCode "grep \$(grep ^HOME /etc/default/useradd | cut -d= -f2) /etc/passwd" $remoteIP
	getCommandOutput "getenforce" $remoteIP
	getCommandOutput "systemctl is-enabled iptables" $remoteIP
	getCommandOutput "systemctl is-enabled postfix" $remoteIP
	getCommandOutput "systemctl is-enabled dovecot" $remoteIP
	getCommandOutput "systemctl is-enabled smb" $remoteIP
	getCommandOutput "systemctl is-active firewalld iptables postfix dovecot smb" $remoteIP
	getCommandOutput "grep -E -v \"(^[[:space:]]*#|^$)\" /etc/sysconfig/network-scripts/ifcfg-\$(ls -d /sys/class/net/e* | awk -F/ '{print \$NF}')" $remoteIP
	getCommandOutput "iptables -vnL INPUT" $remoteIP
	getCommandOutput "iptables -vnL FORWARD" $remoteIP
	getCommandOutput "iptables -vnL OUTPUT" $remoteIP
	getCommandOutput "cat /etc/hosts" $remoteIP


	# Check masterDNS for MX record
	# Check SMTP Server for postconf
	# Check SMTP/IMAP Server for postconf, doveconf, aliases
	# Check Samba Server for smb.conf / linux permissions
	
	if [ "$remoteIP" == "$masterdnsIP" ]
	then
	
        	echo "#--------------------------"
        	echo "#      /etc/named.conf"
        	echo "#--------------------------"

        	# Obtain correct filename from /etc/named.conf for each zone
        	# Capture content of the respective zone file

        	namedConf="$(ssh $remoteIP 'cat /etc/named.conf')"
        	namedConfParsed=`parseDNS "$namedConf"`

        	echo "$namedConfParsed"

        	directory=$(echo "$namedConfParsed" | grep options.*directory | sed 's/options.*directory//' | awk -F\" '{print $2}')


        	zone1File=$(echo "$namedConfParsed" | grep "$zone1.*file" | sed 's/^.*file//' | awk -F\" '{print $2}')

                getCommandOutput "cat $directory/${zone1File}" $remoteIP

	elif [ "$remoteIP" == "$smtpIP" ]
	then
		getCommandOutput "postconf myhostname mydomain myorigin mydestination inet_interfaces mynetworks relayhost mailbox_command" $remoteIP	

	elif [ "$remoteIP" == "$imapIP" ]
	then
		getCommandOutput "postconf myhostname mydomain myorigin mydestination inet_interfaces mynetworks relayhost mailbox_command home_mailbox" $remoteIP	
		getCommandOutput "doveconf ssl disable_plaintext_auth mail_location" $remoteIP	
	
		getCommandOutput "cat /etc/aliases" $remoteIP

	elif [ "$remoteIP" == "$sambaIP" ]
	then
		getCommandOutput "cat /etc/samba/smb.conf" $remoteIP
		getCommandOutput "pdbedit -L" $remoteIP
		
		smbUsers="$(ssh $remoteIP "pdbedit -L | grep :$ | cut -d: -f1")"			
	
		for smbUser in $smbUsers
		do
			getCommandOutput "id $(echo $smbUser | cut -d: -f1)" $remoteIP
		done
	
		getCommandOutput "ls -ldZ $sambaSharedDirectories/*" $remoteIP
	fi

done



#----------------localHost----------------------------

	echo ""
	echo "#--------------------------"
	echo "#      localhost"
   	echo "#--------------------------"
	getCommandOutput "ls -l /backup/full"
}



tempFile=$(mktemp)

stty -echo

echo "--- Generating Report ---"

tput civis


#echo "$(getReport)"
echo "$(getReport)" > $tempFile &
PID=$!


	#=======================
	# Signal Traps Functions
	#=======================

addItemCount()
{
	itemCount=$((itemCount+1))
}


sigint_message ()
{
	kill -9 $PID	

	echo ""
	echo_fail "Check Script Cancelled"
	echo ""

	exit 1
}


onExit()
{
	[ -f $tempFile ] && rm $tempFile	
	tput cvvis
	stty echo
}

	#===================
	# Signal Traps
	#===================

trap sigint_message 2
trap onExit EXIT
trap addItemCount USR1


echo ""
echo "An actual progress bar this time ... :p"
echo ""

	#=====================================
	# Calculate total number of task
	# - task total = 65 + # of Samba Users
	#=====================================

smbUsers="$(ssh $sambaIP "pdbedit -L | grep :$ | cut -d: -f1")"	
totalItemCount=$(($totalItemCount+$(echo "$smbUsers" | wc -l)))	


while [ -d /proc/$PID ]
do
	echo -n "Progress: $itemCount/$totalItemCount"
	echo " ($(echo "scale=4; $itemCount/$totalItemCount*100" | bc | sed 's/00$//')%)"

	sleep 0.1
	tput cuu1 && tput el
done

mail -s "$EmailSubject-$senecaLogin" -a $tempFile -c $senecaLogin@myseneca.ca $instructorEmail < $tempFile



echo ""
echo_pass "~ Pika Pika ~"
echo ""
echo "Good luck on Final Exam :)     Merry Christmas"
echo ""
sudo -u $(who am i | awk '{print $1}') notify-send 'Assignment Check Script' "Completed"

