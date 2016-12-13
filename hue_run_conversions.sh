#!/bin/bash
#Runs the document conversions manually
PARCEL_DIR=/opt/cloudera/parcels/CDH

USAGE="usage: $0"

OVERRIDE=$1

if [[ ! ${USER} =~ .*root* ]]
then
  if [[ -z ${OVERRIDE} ]]
  then
    echo "Script must be run as root: exiting"
    exit 1
  fi
fi

if [ ! -d "/usr/lib/hadoop" ]
then
   CDH_HOME=$PARCEL_DIR
else
   CDH_HOME=/usr
fi

if [[ -z ${HUE_CONF_DIR} ]]
then
   if [ -d "/var/run/cloudera-scm-agent/process" ]
   then
      HUE_CONF_DIR="/var/run/cloudera-scm-agent/process/`ls -1 /var/run/cloudera-scm-agent/process | grep HUE_SERVER | sort -n | tail -1 `"
   else
      HUE_CONF_DIR="/etc/hue/conf"
   fi
   export HUE_CONF_DIR
fi

if [ -d "${CDH_HOME}/lib/hue/build/env/bin" ]
then
   COMMAND="${CDH_HOME}/lib/hue/build/env/bin/hue shell"
else
   COMMAND="${CDH_HOME}/share/hue/build/env/bin/hue shell"
fi

if [[ -z ${ORACLE_HOME} ]]
then
   ORACLE_HOME=/opt/cloudera/parcels/ORACLE_INSTANT_CLIENT/instantclient_11_2/
   LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${ORACLE_HOME}
   export ORACLE_HOME LD_LIBRARY_PATH
fi
HUE_IGNORE_PASSWORD_SCRIPT_ERRORS=1
export CDH_HOME COMMAND HUE_IGNORE_PASSWORD_SCRIPT_ERRORS

echo "HUE_CONF_DIR: ${HUE_CONF_DIR}"
echo "COMMAND: ${COMMAND}"

${COMMAND} <<EOF
from desktop.converters import DocumentConverter
from django.contrib.auth.models import User, Group
for user in User.objects.filter():
  print user
  try:
    converter = DocumentConverter(user)
    converter.convert()
  except:
    pass


EOF
