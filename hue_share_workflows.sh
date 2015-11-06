#!/bin/bash
#Shares workflows with new group to avoid loss when migrating to Ldap Auth
PARCEL_DIR=/opt/cloudera/parcels/CDH

USERNAME=$1
GROUP=$2
PERMISSION=$3
USAGE="usage: hue_share_workflows.sh <workflow_owner_username> <hue_group_to_share_with> <permission_read_or_write>"

if [[ -z ${USERNAME} ]]
then
  echo "No workflow_owner_username specified:"
  echo ${USAGE}
  exit 1
fi

if [[ -z ${GROUP} ]]
then
  echo "No hue_group_to_share_with specified:"
  echo ${USAGE}
  exit 1
fi

if [[ "${PERMISSION}" != +(read|write) ]]
then
  echo "permission read_or_write not specified or not set to read or write:"
  echo ${USAGE}
  exit 1
fi

if [ ! -d "/usr/lib/hadoop" ]
then
   CDH_HOME=$PARCEL_DIR
else
   CDH_HOME=/usr
fi

if [ -d "/var/run/cloudera-scm-agent/process" ]
then
   HUE_CONF_DIR="/var/run/cloudera-scm-agent/process/`ls -1 /var/run/cloudera-scm-agent/process | grep HUE | sort -n | tail -1 `"
else
   HUE_CONF_DIR="/etc/hue/conf"
fi

if [ -d "${CDH_HOME}/lib/hue/build/env/bin" ]
then
   COMMAND="${CDH_HOME}/lib/hue/build/env/bin/hue shell"
else
   COMMAND="${CDH_HOME}/share/hue/build/env/bin/hue shell"
fi

ORACLE_HOME=/opt/cloudera/parcels/ORACLE_INSTANT_CLIENT/instantclient_11_2/
LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${ORACLE_HOME}
export CDH_HOME HUE_CONF_DIR ORACLE_HOME LD_LIBRARY_PATH COMMAND

echo "HUE_CONF_DIR: ${HUE_CONF_DIR}"
echo "COMMAND: ${COMMAND}"

${COMMAND} <<EOF
username = "${USERNAME}"
group = "${GROUP}"
permission = "${PERMISSION}"
from desktop.models import Document
from oozie.models import Workflow
from django.contrib.auth.models import User, Group
user = User.objects.get(username=username)
group = Group.objects.get(name=group)
group_id = str(group.id)
data = {}
data[permission] = {}
#data[permission]['user_ids'] = {}
data[permission]['group_ids'] = group_id
workflows = Document.objects.available(Workflow, user)
for job in workflows:
  if job.managed:
    doc = Document.objects.link(job, owner=job.owner, name=job.name, description=job.description)
    print "Sharing doc_id: " + str(doc.id) + " from user: " + user.username + " to group: " + group.name
    print "With data: " + str(data)
    print ""
    doc.sync_permissions(data)

EOF
