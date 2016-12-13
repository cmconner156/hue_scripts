#!/bin/bash

DESTINATION=/var/log/hue/tcpdumps
SHORTDUR=15
DURATION=3660
ENDFILE=${DESTINATION}/`basename "$0" | awk -F\. '{print $1}'`.finish

mkdir -p /var/log/hue/tcpdumps
touch ${ENDFILE}

while [[ -f ${ENDFILE} ]]
do
   if [[ -z ${PID} ]]
   then
      DURCOUNT=0
      FILENAME=dump.$(date '+%Y%m%d-%H%M')
      /usr/sbin/tcpdump -U -i lo -w ${DESTINATION}/${FILENAME}.dmp 'port 8888' >> /dev/null 2>&1 &
      PID=$!
   else
      DURCOUNT=`expr ${DURCOUNT} + ${SHORTDUR}`
      sleep ${SHORTDUR}
      if [[ ${DURCOUNT} == ${DURATION} ]]
      then
         kill -2 ${PID}
         PID=
      fi
   fi
done

if [[ ! -z ${PID} ]]
then
   kill -2 ${PID}
fi
