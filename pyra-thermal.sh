#!/bin/sh
# Read core and battery temp and pick approperiate cpu freq and charging rates

# pyra-thermal-ladder: was interval=20, which cannot control
# this machine. Measured: two cores from a 63 C idle reach the
# 100 C passive trip in 16 seconds, so a 20 second poll arrives
# after the trip rather than before it. With the vendor ladder
# that was masked, because the gauge sat above 44 C in ordinary
# use and left the machine permanently pre-capped — measured at
# 750 MHz, where two cores flat out peak at a harmless 74 C.
# Correcting the ladder removes that accident, so the poll has
# to become fast enough to do the job on purpose.
interval=2
core="core_thermal"
battery="bq27421-0"

maxFreq=1500
maxCharge=3000000

setMaxFreq()
{
        if [ "$1" -lt "$maxFreq" ]
        then
                current_maxFreq=$1
        fi
}

setMaxCharge()
{
        if [ "$1" -lt "$maxCharge" ]
        then
                current_maxCharge=$1
        fi
}

doThermal()
{

	current_maxFreq=${maxFreq}
	current_maxCharge=${maxCharge}

        core_temp=$(cat "${core_dev}")
        battery_temp=$(cat "${battery_dev}")
        
	# pyra-thermal-ladder: the ladder below replaces the vendor's. Two
	# changes, both explained in full in the script that applied this.
	#
	# 1. The sensor the vendor calls the battery is bq27421-0, the fuel
	#    gauge, and it
	#    reports the gauge's own die temperature — the mainboard it is
	#    soldered to, not the cell. It rises 2.0 C within ten seconds of one
	#    core being loaded, which no 6000 mAh cell can do. The vendor's rungs
	#    for it start at 44 C, which one core reaches in half a minute, so
	#    it, and not core_thermal, was what capped this machine in ordinary
	#    use. Its rungs are moved to board temperatures that mean something.
	#
	# 2. Neither ladder had hysteresis, so a cap was given back at the first
	#    sample below the threshold that took it, one poll before the heat
	#    that caused it returned. Hence the 1.5/1.25 GHz oscillation.

	# Board rungs, on the fuel gauge die. Chosen so that this ladder is a
	# backstop and core_thermal stays the primary control: the numbers are
	# where the board sits when the SoC is already at the matching rung of
	# the core ladder, measured rather than guessed.
	gaugeHot1=62000
	gaugeHot2=60000
	gaugeHot3=58000
	gaugeHot4=56000
	gaugeHot5=54000

	# How far a temperature must fall below the rung that took a step away
	# before it is given back: one full rung of the core ladder.
	#
	# Sized from the machine rather than from the ladder. This core moves up
	# to 6 C between five-second samples under one core of load and 10 C
	# under two. A 2 C band was tried first, at the vendor's 20-second poll,
	# and is below this controller's noise floor: it released correctly and
	# still crossed the same rung six times in four minutes. A full rung means
	# a release has to undo a whole step's worth of heating. The poll is now
	# 2 seconds (see the interval note at the top of the file), which moves
	# less per sample. The 2 C against 5 C comparison was made at 20 s and
	# has not been repeated at 2 s; 5 C at 2 s is what produced the 87 C
	# two-core result, so it is the tested value, not a derived one.
	#
	# The fine regulation is not this daemon's job in any case. The kernel's
	# step_wise governor polls the same zone every 250 ms; this one is the
	# slower backstop, and it should act like one.
	pyraHyst=5000

	# Two ladders, not one, and the split is the point. Frequency is
	# debounced; charging is not touched by the debounce at all. Evaluating
	# one combined ladder twice would mean a release pass deciding the
	# charge current from a temperature one hysteresis band (5 C by default)
	# higher than the real one, which
	# would clamp the charger to 500 mA at a board temperature where the
	# vendor allows 2 A. Defined here rather than at the top of the file so
	# that this entire change stays one reviewable block.
	# Take the lower of the cap already chosen and the one being asked for.
	# The vendor's setMaxFreq compares against maxFreq instead, which lets a
	# later ladder undo an earlier one's deeper cap; see note 3 above.
	pyraCap()
	{
		if [ "$1" -lt "${current_maxFreq}" ]
		then
			current_maxFreq=$1
		fi
	}

	pyraFreqLadder()
	{
		current_maxFreq=${maxFreq}

		#Check Core, from hottest to coldest. Unchanged: this is the
		#right sensor for CPU heat and these are the right rungs for it.
		if [ "$1" -gt 97000 ]
		then
			pyraCap 250
		elif [ "$1" -gt 92000 ]
		then
			pyraCap 500
		elif [ "$1" -gt 87000 ]
		then
			pyraCap 750
		elif [ "$1" -gt 82000 ]
		then
			pyraCap 1000
		elif [ "$1" -gt 77000 ]
		then
			pyraCap 1250
		fi

		#Check the board, from hottest to coldest. Frequency only: this
		#sensor has nothing to say about the cell.
		if [ "$2" -gt "${gaugeHot1}" ]
		then
			pyraCap 250
		elif [ "$2" -gt "${gaugeHot2}" ]
		then
			pyraCap 500
		elif [ "$2" -gt "${gaugeHot3}" ]
		then
			pyraCap 750
		elif [ "$2" -gt "${gaugeHot4}" ]
		then
			pyraCap 1000
		elif [ "$2" -gt "${gaugeHot5}" ]
		then
			pyraCap 1250
		fi
	}

	# The vendor's charging ladder, thresholds and all, kept in its own
	# function and fed the temperature as read. The first five branches all
	# choose the same current; that redundancy is the vendor's and is left
	# alone so that this reads as a move, not an edit.
	pyraChargeLadder()
	{
		current_maxCharge=${maxCharge}

		if [ "$1" -gt 50000 ]
		then
			setMaxCharge 500000
		elif [ "$1" -gt 49000 ]
		then
			setMaxCharge 500000
		elif [ "$1" -gt 47000 ]
		then
			setMaxCharge 500000
		elif [ "$1" -gt 45000 ]
		then
			setMaxCharge 500000
		elif [ "$1" -gt 44000 ]
		then
			setMaxCharge 500000
		elif [ "$1" -gt 43000 ]
		then
			setMaxCharge 1000000
		elif [ "$1" -gt 42000 ]
		then
			setMaxCharge 2000000
		fi
	}

	# The ladder is fed the hotter of core_thermal and cpu_thermal, not
	# core_thermal alone. The passive trip is on cpu_thermal, and during a
	# fast ramp the two diverge badly: measured on this machine, cpu_thermal
	# read 77.7 C at the moment core_thermal read 67.0 C. Watching only the
	# cooler of the two means acting ten degrees late on the sensor that
	# actually decides whether the trip fires. core_temp itself is left
	# alone so the daemon's own one-shot output still reports what it read.
	if [ -z "${pyraCpuDev+set}" ]
	then
		pyraCpuDev=
		for _pyra_z in /sys/class/thermal/thermal_zone*
		do
			if [ "$(cat "${_pyra_z}/type" 2>/dev/null)" = "cpu_thermal" ]
			then
				pyraCpuDev=${_pyra_z}/temp
			fi
		done
	fi
	pyraHot=${core_temp}
	if [ -n "${pyraCpuDev}" ] && [ -r "${pyraCpuDev}" ]
	then
		_pyra_cpu=$(cat "${pyraCpuDev}" 2>/dev/null || echo 0)
		if [ "${_pyra_cpu}" -gt "${pyraHot}" ]
		then
			pyraHot=${_pyra_cpu}
		fi
	fi

	pyraChargeLadder "${battery_temp}"

	pyraFreqLadder "${pyraHot}" "${battery_temp}"
	if [ "${current_maxFreq}" -gt "${pyraPrevMaxFreq:-${maxFreq}}" ]
	then
		# This pass wants to hand a step back. Only do it once the
		# temperature has fallen clear of the rung that took it, rather
		# than merely back across it.
		pyraFreqLadder "$((pyraHot + pyraHyst))" "$((battery_temp + pyraHyst))"
	fi
	pyraPrevMaxFreq=${current_maxFreq}
        if [ "$daemon" -eq 0 ]
        then
                echo ${core}:${core_temp} ${battery}:${battery_temp}
                echo MaxFreq: ${current_maxFreq} MaxCharge: ${current_maxCharge}
        fi

	# pyra-thermal-fix: cpufreq-set came from cpufrequtils, which is not in
	# trixie and has no candidate version, so this call failed on every
	# cycle since the first boot and the daemon never capped anything.
	# Writing scaling_max_freq is what cpufreq-set -u did, and needs
	# nothing installed. Both cores share one policy on this SoC.
	for _policy in /sys/devices/system/cpu/cpufreq/policy*; do
		[ -w "$_policy/scaling_max_freq" ] || continue
		echo $((current_maxFreq * 1000)) > "$_policy/scaling_max_freq"
	done
       	echo ${current_maxCharge} > /dev/usb_max_current
       	
}

if [ "$1" = "daemon" ]
then
	daemon=1
	shift
else
	daemon=0
fi

for i in /sys/class/thermal/thermal_zone*
do
    name=$(cat ${i}/type)
    if [ "${name}" = "${core}" ]
    then
        core_dev="${i}/temp"
    fi
    
    if [ "${name}" = "${battery}" ]
    then
        battery_dev="${i}/temp"
    fi    
done

if [ -z "${core_dev}" ]
then
        echo could not find ${core}
        exit 1
fi

if [ -z "${battery_dev}" ]
then
        echo could not find ${battery}
        exit 1
fi

#echo $core_dev
#echo $battery_dev

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

