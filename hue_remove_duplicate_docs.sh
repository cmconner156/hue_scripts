#!/bin/bash
#Removes any duplicate document entries.
PARCEL_DIR=/opt/cloudera/parcels/CDH

USAGE="usage: $0"

if [[ ! ${USER} =~ .*root* ]]
then
   echo "Script must be run as root: exiting"
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
   HUE_CONF_DIR="/var/run/cloudera-scm-agent/process/`ls -1 /var/run/cloudera-scm-agent/process | grep HUE_SERVER | sort -n | tail -1 `"
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
import logging
from desktop.models import DocumentPermission
from django.db import models, transaction

# If there are duplicated document permissions, we'll have an error
# when we try to create this index. So to protect against that, we
# should delete those documents before we create the index.
duplicated_records = DocumentPermission.objects \
    .values('doc_id', 'perms') \
    .annotate(id_count=models.Count('id')) \
    .filter(id_count__gt=1)

# Delete all but the first document.
for record in duplicated_records:
    docs = DocumentPermission.objects \
        .values_list('id', flat=True) \
        .filter(
            doc_id=record['doc_id'],
            perms=record['perms'],
        )[1:]
    docs = list(docs)
    logging.warn('Deleting permissions %s' % docs)
    DocumentPermission.objects.filter(id__in=docs).delete()

transaction.commit()

EOF
