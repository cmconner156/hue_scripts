#!/bin/bash

export HUE_BIN=/opt/cloudera/parcels/CDH/share/hue/build/env/bin/hue
export JSON_FILE=/tmp/authuser.json
export TXT_FILE=/tmp/authuser.txt
export METHOD="EXTERNAL"

NEW="false"
echo "["
while read -r LINE
do

   if [[ ${LINE} =~ '--' ]]
   then
     NEW="true"
     echo "  {"
     echo "    \"pk\": $ID,"
     echo "    \"model\": \"useradmin.userprofile\","
     echo "    \"fields\": {"
     echo "      \"creation_method\": \"${METHOD}\","
     echo "      \"user\": $ID,"
     echo "      \"home_directory\": \"/user/$USERNAME\""
       echo "  },"
   fi
   if [[ ${NEW} =~ "false" ]]
   then
     if [[ ${LINE} =~ "pk" ]]
     then
       ID=`echo ${LINE} | awk -F: '{print $2}' | awk -F, '{print $1}' | awk '{print $1}'`
     fi 
     if [[ ${LINE} =~ "username" ]]
     then 
       USERNAME=`echo ${LINE} | awk -F: '{print $2}' | awk -F, '{print $1}' | awk -F\" '{print $2}'`
     fi
   fi
   NEW="false"

done < <(cat ${TXT_FILE})


echo "  {"
echo "    \"pk\": $ID,"
echo "    \"model\": \"useradmin.userprofile\","
echo "    \"fields\": {"
echo "      \"creation_method\": \"${METHOD}\","
echo "      \"user\": $ID,"
echo "      \"home_directory\": \"/user/$USERNAME\""
echo "   }"
echo "]"
