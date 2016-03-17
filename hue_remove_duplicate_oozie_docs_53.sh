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
import logging
from desktop.models import Document
from django.db import models, transaction

print "Original set of Oozie workflow documents:"
print ""

docs = Document.objects \
    .values('id', 'object_id', 'content_type_id', 'name', 'description') \
    .filter(
        content_type_id = 27L,
    ).order_by('object_id')

for doc in docs:
    print "%s" % doc

print ""
print "Deleting duplicate entries"
print ""

# If there are duplicated document permissions, we'll have an error
# when we try to create this index. So to protect against that, we
# should delete those documents before we create the index.
duplicated_records = Document.objects \
    .values('object_id', 'content_type_id') \
    .annotate(id_count=models.Count('object_id')) \
    .filter(id_count__gt=1)

# Delete all but the first document.
for record in duplicated_records:
    docs = Document.objects \
        .values_list('id', flat=True) \
        .filter(
            object_id = record['object_id'],
            content_type_id = record['content_type_id'],
        )[1:]
    docs = list(docs)
    print "Deleting oozie duplicate: %s" % docs
    Document.objects.filter(id__in=docs).delete()

transaction.commit()

print "New set of Oozie workflow documents, only duplicate entries should be missing:"
print ""

docs = Document.objects \
    .values('object_id', 'content_type_id', 'name', 'description') \
    .filter(
        content_type_id = 27L,
    ).order_by('object_id')

for doc in docs:
    print "%s" % doc

EOF
