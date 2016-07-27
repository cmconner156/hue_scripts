#!/bin/bash
# Licensed to Cloudera, Inc. under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  Cloudera, Inc. licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#Cleans up old oozie workflow and beeswax savedqueries to
#prevent the DB from getting too large.


#parse command line arguments
parse_arguments()
{
  # Test that we're using compatible getopt version.
  getopt -T > /dev/null
  if [[ $? -ne 4 ]]; then
    echo "Incompatible getopt version."
    exit 1
  fi

  # Parse short and long option parameters.
  BEESWAX=true
  OOZIE=true
  GETOPT=`getopt -n $0 -o b,o,h \
      -l beeswax,oozie,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -b|--nobeeswax)
      BEESWAX=
      shift
      ;;
    -o|--nooozie)
      OOZIE=
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      exit 1
      ;;
    esac
  done
  #
}

usage()
{
cat << EOF
usage: $0 [options]

Cleans up the oozie_job, beeswax_queryhistory, beeswax_savedquery tables:

OPTIONS
   -b|--nobeeswax          Disables cleaning of beeswax tables.
   -o|--nooozie            Disables cleaning of the oozie tables.
   -h|--help               Show this message.
EOF
}

main()
{

   parse_arguments "$@"

   if [[ ! ${USER} =~ .*root* ]]
   then
      echo "Script must be run as root: exiting"
      exit 1
   fi

   CDH_VERSION=`hadoop version | grep "Hadoop.*cdh.*" | awk -Fcdh '{print $2}'`
   CDH_MAJOR_VER=${CDH_VERSION%%.*}
   CDH_MINOR_VER=${CDH_VERSION:2:1}

   if [[ ${CDH_MAJOR_VER} -ge 5 ]] && [[ ${CDH_MINOR_VER} -ge 5 ]]
   then
      HUE_IGNORE_PASSWORD_SCRIPT_ERRORS=1
      if [[ -z ${HUE_DATABASE_PASSWORD} ]]
      then
         echo "CDH 5.5 and above requires that you set the environment variable:"
         echo "HUE_DATABASE_PASSWORD=<dbpassword>"
         exit 1
      fi
   fi

   PARCEL_DIR=/opt/cloudera/parcels/CDH
   LOG_FILE=/var/log/hue/`basename "$0" | awk -F\. '{print $1}'`.log
   LOG_ROTATE_SIZE=10 #MB before rotating, size in MB before rotating log to .1
   LOG_ROTATE_COUNT=2 #number of log files, so 20MB max
   DATE=`date '+%Y%m%d-%H%M'`
   KEEP_DAYS=7    #Number of days of beeswax and oozie history to keep
   BEESWAX_DELETE_RECORDS=999 #number of beeswax records to delete at a time
                                #to avoid Non Fatal Exception: DatabaseError: too many SQL variables
   WORKFLOW_DELETE_RECORDS=999 #number of workflow records to delete at a time
                                #to avoid Non Fatal Exception: DatabaseError: too many SQL variables
   RESET_COUNT=15              #number of deletion attempts before trying max again
   RESET_MAX=5                 #number of resets permitted

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
   export CDH_HOME HUE_CONF_DIR ORACLE_HOME LD_LIBRARY_PATH COMMAND DEBUG=true DESKTOP_DEBUG=true

${COMMAND} >> /dev/null 2>&1 <<EOF
from beeswax.models import SavedQuery
from datetime import date, timedelta
from oozie.models import Workflow
from django.db.utils import DatabaseError
import desktop.conf
import logging
import logging.handlers
import sys

LOGFILE="${LOG_FILE}"
keepDays = ${KEEP_DAYS}
deleteBeeswaxRecords = ${BEESWAX_DELETE_RECORDS}
deleteWorkflowRecords = ${WORKFLOW_DELETE_RECORDS}
resetCount = ${RESET_COUNT}
resetMax = ${RESET_MAX}
errorCount = 0
checkCount = 0
resets = 0
log = logging.getLogger('')
log.setLevel(logging.INFO)
format = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")

fh = logging.handlers.RotatingFileHandler(LOGFILE, maxBytes=(1048576*${LOG_ROTATE_SIZE}), backupCount=${LOG_ROTATE_COUNT})
fh.setFormatter(format)
log.addHandler(fh)

log.info('HUE_CONF_DIR: ${HUE_CONF_DIR}')
log.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
log.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
log.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
log.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
log.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))
log.info("Cleaning up anything in the Hue tables oozie*, desktop* and beeswax* older than ${KEEP_DAYS} old")

if "${BEESWAX}" == "true":
   totalQuerys = SavedQuery.objects.filter(is_auto=True, mtime__lte=date.today() - timedelta(days=keepDays)).values_list("id", flat=True)
   log.info("Looping through querys. %s querys to be deleted." % totalQuerys.count())
   while totalQuerys.count():
      if deleteBeeswaxRecords < 30 and resets < resetMax:
         checkCount += 1
      if checkCount == resetCount:
         deleteBeeswaxRecords = ${BEESWAX_DELETE_RECORDS}
         resets += 1
         checkCount = 0
      log.info("SavedQuerys left: %s" % totalQuerys.count())
      savedQuerys = SavedQuery.objects.filter(is_auto=True, mtime__lte=date.today() - timedelta(days=keepDays)).values_list("id", flat=True)[:deleteBeeswaxRecords]
      try:
         SavedQuery.objects.filter(pk__in = list(savedQuerys)).delete()
         errorCount = 0
      except DatabaseError, e:
         log.info("Non Fatal Exception: %s: %s" % (e.__class__.__name__, e))
         errorCount += 1
         if errorCount > 9 and deleteBeeswaxRecords == 1:
            raise
         if deleteBeeswaxRecords > 100:
            deleteBeeswaxRecords = max(deleteBeeswaxRecords - 100, 1)
         else:
            deleteBeeswaxRecords = max(deleteBeeswaxRecords - 10, 1)
         log.info("Decreasing max delete records for SavedQuerys to: %s" % deleteBeeswaxRecords)
      totalQuerys = SavedQuery.objects.filter(is_auto=True, mtime__lte=date.today() - timedelta(days=keepDays)).values_list("id", flat=True)

errorCount = 0
checkCount = 0
resets = 0
if "${OOZIE}" == "true":
   totalWorkflows = Workflow.objects.filter(is_trashed=True, last_modified__lte=date.today() - timedelta(days=keepDays)).values_list("id", flat=True)
   log.info("Looping through trashed workflows. %s workflows to be deleted." % totalWorkflows.count())
   while totalWorkflows.count():
      if deleteWorkflowRecords < 30 and resets < resetMax:
         checkCount += 1
      if checkCount == resetCount:
         deleteWorkflowRecords = ${WORKFLOW_DELETE_RECORDS}
         resets += 1
         checkCount = 0
      log.info("Workflows left: %s" % totalWorkflows.count())
      deleteWorkflows = Workflow.objects.filter(is_trashed=True, last_modified__lte=date.today() - timedelta(days=keepDays)).values_list("id", flat=True)[:deleteWorkflowRecords]
      try:
         Workflow.objects.filter(pk__in = list(deleteWorkflows)).delete()
         errorCount = 0
      except DatabaseError, e:
         log.info("Non Fatal Exception: %s: %s" % (e.__class__.__name__, e))
         errorCount += 1
         if errorCount > 9 and deleteWorkflowRecords == 1:
            raise
         if deleteWorkflowRecords > 100:
            deleteWorkflowRecords = max(deleteWorkflowRecords - 100, 1)
         else:
            deleteWorkflowRecords = max(deleteWorkflowRecords - 10, 1)
         log.info("Decreasing max delete records for Workflows to: %s" % deleteWorkflowRecords)
      totalWorkflows = Workflow.objects.filter(is_trashed=True, last_modified__lte=date.today() - timedelta(days=keepDays)).values_list("id", flat=True)

errorCount = 0
checkCount = 0
resets = 0
if "${OOZIE}" == "true":
   totalWorkflows = Workflow.objects.filter(name='', last_modified__lte=date.today() - timedelta(days=keepDays)).values_list("id", flat=True)
   log.info("Looping through duplicate workflows. %s workflows to be deleted." % totalWorkflows.count())
   while totalWorkflows.count():
      if deleteWorkflowRecords < 30 and resets < resetMax:
         checkCount += 1
      if checkCount == resetCount:
         deleteWorkflowRecords = ${WORKFLOW_DELETE_RECORDS}
         resets += 1
         checkCount = 0
      log.info("Workflows left: %s" % totalWorkflows.count())
      deleteWorkflows = Workflow.objects.filter(name='', last_modified__lte=date.today() - timedelta(days=keepDays)).values_list("id", flat=True)[:deleteWorkflowRecords]
      try:
         Workflow.objects.filter(pk__in = list(deleteWorkflows)).delete()
         errorCount = 0
      except DatabaseError, e:
         log.info("Non Fatal Exception: %s: %s" % (e.__class__.__name__, e))
         errorCount += 1
         if errorCount > 9 and deleteWorkflowRecords == 1:
            raise
         if deleteWorkflowRecords > 100:
            deleteWorkflowRecords = max(deleteWorkflowRecords - 100, 1)
         else:
            deleteWorkflowRecords = max(deleteWorkflowRecords - 10, 1)
         log.info("Decreasing max delete records for Workflows to: %s" % deleteWorkflowRecords)
      totalWorkflows = Workflow.objects.filter(name='', last_modified__lte=date.today() - timedelta(days=keepDays)).values_list("id", flat=True)

EOF

}

main "$@"
