# Test Form

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