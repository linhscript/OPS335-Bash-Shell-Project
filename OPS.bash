#!/bin/bash

# LIST of choice. One choice at a time
if zenity --list --title="List of works" --radiolist\
 --column="Options" --column="Details" --width=300 --height=500 \
 1 Lab1\
 2 Lab2a\
 3 Lab2b\
 4 Lab3\
 5 Lab4a\
 6 Lab4b\
 7 Lab5\
 8 Lab6\
 9 Lab7\
 10 Lab8\
 11 Assignment1-part1\
 12 Assignment1-part2\
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

optlst="Lab1 Lab2a Lab2b Lab3 Lab4a Lab4b Lab5 Lab6 Lab7 Lab8 Assignment1-part1 Assignment1-part2 Assignment2"
for i in $optlst
do
	if [ "$i" = "$ans" ]
	then
		clear
		echo -e "\e[31mStarting $i\e[m"
		echo
		souce <(curl -s https://raw.githubusercontent.com/linhvanha/OPS335/master/$i.bash)
	fi
done
