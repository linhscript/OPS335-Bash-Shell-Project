#!/bin/bash

# LIST of choice. One choice at a time
if zenity --list --title="List of works" --radiolist\
 --column="Options" --column="Details" --width=600 --height=400 \
 1 Lab_1\
 2 Lab_2a\
 3 Lab_2b\
 4 Lab_3\
 5 Lab_4a\
 6 Lab_4b\
 7 Lab_5\
 8 Lab_6\
 9 Lab_7\
 10 Lab_8\
 11 Assignment1_Part_1\
 12 Assignment1_Part_2\
 13 Assignment2 > var
then
	ans=$(cut -f1 var)
	if [ -z $ans ]
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

optlst="Lab_1 Lab_2a Lab_2b	Lab_3 Lab_4a Lab_4b Lab_5 Lab_6 Lab_7 Lab_8	Assignment1_Part_1 Assignment1_Part_2 Assignment2"
for i in $optlst
do
	if $i -eq $ans
	then

	fi
done
