#!/bin/sh
# Read core and battery temp and pick approperiate cpu freq and charging rates

maxFreq=1500
maxCharge=3000000
interval=1

setMaxFreq()
{
        if [ "$1" -lt "$maxFreq" ]
        then
                maxFreq=$1
        fi
}

setMaxCharge()
{
        if [ "$1" -lt "$maxCharge" ]
        then
                maxCharge=$1
        fi
}

doThermal()
{

	#Check Core, from hottest to coldest
	if [ $core -gt 97000 ]
	then
       		setMaxFreq 250
	elif [ $core -gt 92000 ]
	then
        	setMaxFreq 500
	elif [ $core -gt 87000 ]
	then
        	setMaxFreq 750
	elif [ $core -gt 82000 ]
	then
        	setMaxFreq 1000
	elif [ $core -gt 77000 ]
	then
        	setMaxFreq 1250
	fi

	#Check Battery, from hottest to coldest
	if [ $battery -gt 50000 ]
	then
        	setMaxFreq 250
        	setMaxCharge 500000
	elif [ $battery -gt 49000 ]
	then
        	setMaxFreq 500
        	setMaxCharge 500000
	elif [ $battery -gt 47000 ]
	then
        	setMaxFreq 750
        	setMaxCharge 500000
	elif [ $battery -gt 45000 ]
	then
        	setMaxFreq 1000
        	setMaxCharge 500000
	elif [ $battery -gt 44000 ]
	then
        	setMaxFreq 1250
        	setMaxCharge 500000
	elif [ $battery -gt 43000 ]
	then
        	setMaxCharge 1000000
	elif [ $battery -gt 42000 ]
	then
        	setMaxCharge 2000000
	fi


	if [ $# -eq 0 ]
	then
        	cpufreq-set -u ${maxFreq}MHz
        	echo ${maxCharge} > /dev/usb_max_current
	else
        	echo "Would set cpu to ${maxFreq}mhz and battery limit to ${maxCharge}"
	fi
}

if [ "$1" = "daemon" ]
then
	daemon=1
	shift
else
	daemon=0
fi


core=$1
battery=$2

if [ -z "$core" ]
then
        core=$(cat /sys/class/thermal/thermal_zone2/temp)
fi

if [ -z "$battery" ]
then
        battery=$(cat /sys/class/thermal/thermal_zone3/temp)
fi

if [ "$daemon" -eq 1 ]
then
	while true
	do
		doThermal
		sleep ${interval}
	done
else
	doThermal
fi

