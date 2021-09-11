#!/bin/bash

#
# purpose:  	find the fastest disk-scheduler.
#           	this script uses dd, hdparm and bonnie++
#           	to measure the hdd/ssd performance of 
#           	each available io scheduler
#
#           	the current io scheduler is restored
#           	after the script completed
#
# author: 	Michael Dinkelaker
#		michael.dinkelaker[at]gmail[dot]com
#
# version:	15-01-09  0.1, initial static version
#		16-09-20  0.2, rewrote the static part
#		16-09-24  0.3b, public release as beta on github
#		16-11-22  0.4, fix program locations. Added trap for INT, TERM, EXIT, KILL signals to remove tmp data
#		16-11-22  0.5, add free space check. 
#		21-09-11  0.6, fix regex for scheduler names with a "-"

clear;
echo -e "Storage-I/O Scheduler Benchmark v0.5\tMichael Dinkelaker 2016"
set -e
#  are we all set? -----------------------------------------------------------------------------------------------------
#  got root?
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 
   exit 1
fi

#  got device id? we need "sda" not "sda5"
DEV_ID=$(echo $1 | sed 's/[^a-z \/]//g')
if [ -z "$DEV_ID" ]; then
    echo "usage: sudo ./sched-bench.sh /dev/sdX"
    exit 1
fi

#  is dev id valid?
if [ ! -b $DEV_ID ]; then
    echo $DEV_ID "seems not be a valid device"
    exit 2
fi

# 0.4 get program locations
bonnie=$(which bonnie++ 2>/dev/null)
hdparm=$(which hdparm 2>/dev/null)
dd=$(which dd 2>/dev/null)
#  dependencies installed?
if [ ! -e $bonnie ] || [ ! -e $hdparm ] || [ ! -e $dd ]; then
    echo "You need to install bonnie++, hdparm and dd (coreutils)"
    exit 3
fi
#  get dev id mount path, where to read/write data to
TARGET_PATH=$(mount | tac | grep -m1 $DEV_ID | cut -d" " -f3)
#  we're good to go! ---------------------------------------------------------------------------------------------------
SDX=$(echo $DEV_ID | cut -f3 -d"/")                                                                                     #  extract sda from /dev/sda
IFS=' '
read -a SCHEDULER <<< $(cat /sys/block/$SDX/queue/scheduler | sed 's/[^a-z A-Z 0-9 -]//g')
RAM_SIZE=$(cat /proc/meminfo | grep "MemTotal" | cut -f2 -d":" | sed 's/[^0-9]//g')                                     #  bonnie++ needs 2x ram-size
T_SIZE=$(awk -M 'BEGIN{ROUNDMODE="u"; OFMT="%.0f"; print '$RAM_SIZE' / 1048576}')
BENCH_SIZE=$(($T_SIZE * 2))
DD_SIZE=$(($BENCH_SIZE * 1024))
#  TODO: add freespace check. find mount point with enough diskspace or exit
FREE_SPACE=$(df -BG $TARGET_PATH | tac | awk {'print $4'} | sed 's/[^0-9]//g' | head -1)
if [ $BENCH_SIZE -ge $FREE_SPACE ]; then
	echo "There is not enough disk space left on $TARGET_PATH. Need $BENCH_SIZE G"
	exit 4
fi
echo "writing all temp data into $TARGET_PATH"
CURRENT_SCHEDULER=$(cat /sys/block/$SDX/queue/scheduler | cut -d "[" -f2 | cut -d "]" -f1)
echo -e "Your current scheduler was: $CURRENT_SCHEDULER"
LB="-------------------------------------------------------------------------------------------------------------"

echo
for test in {1..3};do
    sync
    echo $LB

    for t in "${SCHEDULER[@]}";do
        WORKDIR=$(mktemp -d -p $TARGET_PATH)                                                                            #  make a temp directory
        echo "$t" > /sys/block/$SDX/queue/scheduler
		trap "rm -rf $WORKDIR; echo $SCHEDULER > /sys/block/$SDX/queue/scheduler;exit" INT TERM EXIT KILL
        case "$test" in
            "1")  # bonnie++
                echo
                echo -e "******  bonnie++      $(cat /sys/block/$SDX/queue/scheduler)  ******"
                $bonnie -d $WORKDIR/ -s $BENCH_SIZE"G" -n 0 -q -f -b -u root -m TEST
            ;;

            "2")  # dd
                echo
                echo -e "******  dd      $(cat /sys/block/$SDX/queue/scheduler)  ******"
                $dd if=/dev/zero of=$WORKDIR/ddtest bs=1M count=$DD_SIZE
                sync
                $dd if=$WORKDIR/ddtest of=/dev/zero bs=1M count=$DD_SIZE
            ;;

            "3")  # hdparm
                echo
                echo -e "******  hdparm      $(cat /sys/block/$SDX/queue/scheduler)  ******"
                $hdparm -tT --direct $DEV_ID
            ;;
        esac
		trap - INT TERM EXIT KILL
        sync
    done
done

echo $LB
echo
# restore original scheduler
echo $SCHEDULER > /sys/block/$SDX/queue/scheduler
echo -e "$(cat /sys/block/$SDX/queue/scheduler)"
