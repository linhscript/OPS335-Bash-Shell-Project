function vminfo {

## Config DOMAIN, HOSTNAME, RESOLV File, Disable Network Manager
	intvm=$( ssh 192.168.$digit.${i} '( ip ad | grep -B 2 192.168.$digit | head -1 | cut -d" " -f2 | cut -d: -f1 )' )
	ssh 192.168.$digit.${i} "echo vm$(($i-1)).$domain > /etc/hostname"
	check "ssh 192.168.$digit.${i} grep -v -e '^DNS.*' -e 'DOMAIN.*' /etc/sysconfig/network-scripts/ifcfg-$intvm > ipconf.txt" "File or directory not exist"
	echo "DNS1="192.168.$digit.1"" >> ipconf.txt
	echo "PEERDNS=no" >> ipconf.txt
	echo "DOMAIN=$domain" >> ipconf.txt
	check "scp ipconf.txt 192.168.$digit.${i}:/etc/sysconfig/network-scripts/ifcfg-$intvm > /dev/null" "Can not copy ipconf to VM${i}"
	rm -rf ipconf.txt > /dev/null
	ssh 192.168.$digit.${i} "echo "search $domain" > /etc/resolv.conf"
	ssh 192.168.$digit.${i} "echo "nameserver 192.168.${digit}.1" >> /etc/resolv.conf"

}