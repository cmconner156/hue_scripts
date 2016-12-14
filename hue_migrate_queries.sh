#!/bin/bash
#Changes owner of Search Dashboard
PARCEL_DIR=/opt/cloudera/parcels/CDH

USAGE="usage: $0"

LOG_FILE=/var/log/hue/`basename "$0" | awk -F\. '{print $1}'`.log

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

${COMMAND} 2>&1 <<EOF | tee ${LOG_FILE}
from django.contrib.auth.models import User
from desktop.converters import DocumentConverter
from beeswax.models import SavedQuery, HQL, IMPALA, RDBMS
import re

DOC2_NAME_INVALID_CHARS = "[<>/~\`]"

count = 0
for user in User.objects.filter():
  print "Migrated %s queries" % count
  print
  print "Migrating queries for user: %s" % user.username
  converter = DocumentConverter(user)
  docs = converter._get_unconverted_docs(SavedQuery).filter(extra__in=[HQL, IMPALA, RDBMS])
  count = 0
  for doc in docs:
    count = count + 1
    doc.name = re.sub(DOC2_NAME_INVALID_CHARS, '', doc.name)
    doc.content_object.name = re.sub(DOC2_NAME_INVALID_CHARS, '', doc.content_object.name)
    doc.save()
    doc.content_object.save()
    print "Migrating query : %s" % doc.name


EOF
