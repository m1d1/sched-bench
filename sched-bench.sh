#!/bin/bash

#
# purpose:  find the fastest disk-scheduler.
#           this script uses dd, hdparm and bonnie++
#           to measure the hdd/ssd performance of 
#           each available io scheduler
#
#           the current io scheduler is restored
#           after the script completed
#
# author: 	Michael Dinkelaker
#		    michael.dinkelaker[at]gmail[dot]com
#
# version:	15-01-09	0.1, initial static version
#           16-09-20    0.2, rewrote the static part
#           16-09-24    0.3b, public release as beta on github

clear;
echo -e "Storage-I/O Scheduler Benchmark v0.3b\tMichael Dinkelaker 2016"

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

#  dependencies installed?
if [ ! -e /usr/bin/bonnie++ ] || [ ! -e /usr/bin/hdparm ] || [ ! -e /bin/dd ]; then
    echo "You need to install bonnie++, hdparm and dd (coreutils)"
    exit 3
fi

#  get dev id mount path, where to read/write data to
TARGET_PATH=$(mount | tac | grep -m1 $DEV_ID | cut -d" " -f3)
#  TODO: add freespace check. find mount point with enough diskspace or exit
#  FREE_SPACE=$(df -h $TARGET_PATH  | grep "$SDX" | cut -d"G" -f3 | sed 's/[^0-9]//g')


#  we're good to go! ---------------------------------------------------------------------------------------------------

SDX=$(echo $DEV_ID | cut -f3 -d"/")                                                                                     #  extract sda from /dev/sda
CURRENT_SCHEDULER=$(cat /sys/block/$SDX/queue/scheduler | cut -d "[" -f2 | cut -d "]" -f1)
echo -e "current scheduler: $CURRENT_SCHEDULER"
IFS=' '
read -a SCHEDULER <<< $(cat /sys/block/$SDX/queue/scheduler | sed 's/[^a-z A-Z 0-9]//g')
RAM_SIZE=$(cat /proc/meminfo | grep "MemTotal" | cut -f2 -d":" | sed 's/[^0-9]//g')                                     #  bonnie++ needs 2x ram-size
T_SIZE=$(awk -M 'BEGIN{ROUNDMODE="u"; OFMT="%.0f"; print '$RAM_SIZE' / 1048576}')
BENCH_SIZE=$(($T_SIZE * 2))
DD_SIZE=$(($BENCH_SIZE * 1024))
LB="-------------------------------------------------------------------------------------------------------------"

echo
for test in {1..3};do
    sync
    echo $LB

    for t in "${SCHEDULER[@]}";do
        WORKDIR=$(mktemp -d -p $TARGET_PATH)                                                                            #  make a temp directory
        echo $t > /sys/block/$SDX/queue/scheduler

        case "$test" in

            "1")  # bonnie++
                echo
                echo -e "******  bonnie++      $(cat /sys/block/$SDX/queue/scheduler)  ******"
                bonnie++ -d $WORKDIR/ -s $BENCH_SIZE"G" -n 0 -q -f -b -u root -m TEST
            ;;

            "2")  # dd
                echo
                echo -e "******  dd      $(cat /sys/block/$SDX/queue/scheduler)  ******"
                dd if=/dev/zero of=$WORKDIR/ddtest bs=1M count=$DD_SIZE
                sync
                dd if=$WORKDIR/ddtest of=/dev/zero bs=1M count=$DD_SIZE
            ;;

            "3")  # hdparm
                echo
                echo -e "******  hdparm      $(cat /sys/block/$SDX/queue/scheduler)  ******"
                hdparm -tT --direct $DEV_ID
            ;;
        esac
        rm -rf $WORKDIR                                                                                                 # delete temp dir
        sync
    done
done

echo $LB
echo
# restore original scheduler
echo $SCHEDULER > /sys/block/$SDX/queue/scheduler
echo -e "$(cat /sys/block/$SDX/queue/scheduler)"
