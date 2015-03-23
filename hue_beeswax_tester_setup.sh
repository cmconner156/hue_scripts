#!/bin/bash

#NOTE: This script requires curl to be installed.  Also, it does not have to run on the Hue server, it can run anywhere that curl is installed.  As long as that host can reach the Hue server.

#Please enter the Hue server name below
HUE_SERVER="cdh412-1"

#Please enter the Hue server port below
HUE_PORT="8888"

HUE_PASS_URL="${HUE_SERVER}:${HUE_PORT}/accounts/login/"
HUE_USER_URL="${HUE_SERVER}:${HUE_PORT}/useradmin/users/new"


echo "curl -i -c /tmp/admin_cookie.txt -d \"username=admin&password=admin\" \"${HUE_PASS_URL}\""
curl -i -c /tmp/admin_cookie.txt -d "username=admin&password=admin" "${HUE_PASS_URL}" > /dev/null

for x in {1..100}
do

   user="test$x"
   echo "running Command:"
   echo "curl --data \"username=${user}&is_active=on&first_name=${user}&last_name=${user}&email=&ensure_home_directory=on&groups=1&password1=password&password2=password\" --dump-header /tmp/${user}_headers.txt -i -b /tmp/admin_cookie.txt \"${HUE_USER_URL}\""
   curl --data "username=${user}&is_active=on&first_name=${user}&last_name=${user}&email=&ensure_home_directory=on&groups=1&password1=password&password2=password" --dump-header /tmp/${user}_headers.txt -i -b /tmp/admin_cookie.txt "${HUE_USER_URL}"
   sudo useradd ${user}

done

