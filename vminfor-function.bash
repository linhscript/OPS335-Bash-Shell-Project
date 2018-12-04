function vminfo {

## Config DOMAIN, HOSTNAME, RESOLV File, Disable Network Manager
## Need some arguments such as: IP VM_name DNS1 DNS2 
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
