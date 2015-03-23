#!/bin/bash

#NOTE: This script requires curl to be installed.  Also, it does not have to run on the Hue server, it can run anywhere that curl is installed.  As long as that host can reach the Hue server.

# Please change USER to contain the user to login
USER="cconner"

# Please change PASSWORD to contain the password for the above user
PASSWORD="password"

#Please enter the Hue server name below
HUE_SERVER="cdh46-1"

#Please enter the Hue server port below
HUE_PORT="8888"

#Please enter the user name you want to sync
USER_NAME="tuser2"

#Please enter off or on based on if you want to create home directories for new users
CREATE_DIR="on"

POST_STRING="username_pattern=${USER_NAME}&ensure_home_directory=${CREATE_DIR}"

HUE_PASS_URL="${HUE_SERVER}:${HUE_PORT}/accounts/login/"
HUE_LDAP_USER_SYNC_URL="${HUE_SERVER}:${HUE_PORT}/useradmin/users/add_ldap_users"

echo "Running Command:"
echo "curl -i -c /tmp/${USER}_cookie.txt -d \"username=${USER}&password=${PASSWORD}\" \"${HUE_PASS_URL}\""
curl -i -c /tmp/${USER}_cookie.txt -d "username=${USER}&password=${PASSWORD}" "${HUE_PASS_URL}"

echo "Running Command:"
echo "curl -i -b /tmp/${USER}_cookie.txt -d \"${POST_STRING}\" \"${HUE_LDAP_USER_SYNC_URL}\" > /dev/null"
curl -i -b /tmp/${USER}_cookie.txt -d "${POST_STRING}" "${HUE_LDAP_USER_SYNC_URL}" > /dev/null
