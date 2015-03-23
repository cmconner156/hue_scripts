#!/bin/bash

HUE_SERVER="cdh46-1"
HUE_PORT="8888"
HUE_PASS_URL="${HUE_SERVER}:${HUE_PORT}/accounts/login/"
HUE_CREATE_URL="${HUE_SERVER}:${HUE_PORT}/jobsub/designs/hive/new"
admin_user="cconner"
admin_pass="password"


curl -i -c ${admin_user}_cookie.txt -d "username=${admin_user}&password=${admin_pass}" "${HUE_PASS_URL}" > /dev/null


while read -r LINE
do

   ACTION=`echo ${LINE} | awk '{print $1}'`
   URL=`echo ${LINE} | awk '{print $2}'`
   HUE_CREATE_URL="http://${HUE_SERVER}:${HUE_PORT}/${URL}"
   echo ${ACTION}
   echo ${HUE_CREATE_URL}

   curl -X ${ACTION} --dump-header ${admin_user}_headers.txt -i -b ${admin_user}_cookie.txt "${HUE_CREATE_URL}" > /dev/null
   
   sleep 1

done < <(cat hbase.txt)
