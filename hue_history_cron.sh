#!/bin/bash
#Clean up old history to keep DB from growing too large

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
  OVERRIDE=
  BEESWAX=true
  OOZIE=true
  KEEP_DAYS=14
  VERBOSE=
  DESKTOP_DEBUG=false
  GETOPT=`getopt -n $0 -o b,z,o,d:,v,h \
      -l nobeeswax,nooozie,override,days:,verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -o|--override)
      OVERRIDE=true
      shift
      ;;
    -b|--nobeeswax)
      BEESWAX=$2
      shift
      ;;
    -o|--nooozie)
      OOZIE=$2
      shift
      ;;
    -d|--days)
      KEEP_DAYS=$2
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
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
   -o|--override           Allow script to run as non-root, must set HUE_CONF_DIR manually before running
   -b|--nobeeswax          Disables cleaning of beeswax tables.
   -o|--nooozie            Disables cleaning of the oozie tables.
   -d|--days		   Number of days of old data to keep.  Default 14.
   -v|--verbose		   Enable verbose logging
   -h|--help               Show this message.
EOF
}

debug()
{
   if [[ ! -z $VERBOSE ]]
   then
      echo "$1" >> ${LOG_FILE}
   fi
}

main()
{

  parse_arguments "$@"

  SCRIPT_DIR="$( cd -P "$( dirname "$0" )" && pwd )"
  PYTHONPATH=${SCRIPT_DIR}/lib:${PYTHONPATH}
  export SCRIPT_DIR PYTHONPATH

  #SET IMPORTANT ENV VARS
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

  if [[ ! ${USER} =~ .*root* ]]
  then
    if [[ -z ${OVERRIDE} ]]
    then
      echo "Script must be run as root: exiting"
      exit 1
    fi
  else
    if [[ $(ps -ef | grep "[h]ue runc" | awk '{print }') ]]
    then
      DESKTOP_LOG_DIR=$(strings /proc/$(ps -ef | grep "[h]ue runc" | awk '{print }' | awk '{print $2}')/environ | grep DESKTOP_LOG_DIR | awk -F\= '{print $2}')
    fi
  fi

  if [[ -z ${DESKTOP_LOG_DIR} ]]
  then
    DESKTOP_LOG_DIR=${HUE_CONF_DIR}/logs
  fi
  if [[ ! -f ${DESKTOP_LOG_DIR} ]]
  then
    mkdir -p ${DESKTOP_LOG_DIR}
  fi
  LOG_FILE=${DESKTOP_LOG_DIR}/`basename "$0" | awk -F\. '{print $1}'`.log
  LOG_ROTATE_SIZE=10 #MB before rotating, size in MB before rotating log to .1
  LOG_ROTATE_COUNT=5 #number of log files, so 20MB max

  PARCEL_DIR=/opt/cloudera/parcels/CDH
  if [ ! -d "/usr/lib/hadoop" ]
  then
    CDH_HOME=$PARCEL_DIR
  else
    CDH_HOME=/usr
  fi

  if [ -d "${CDH_HOME}/lib/hue/build/env/bin" ]
  then
    COMMAND="${CDH_HOME}/lib/hue/build/env/bin/hue shell"
    TEST_COMMAND="${CDH_HOME}/lib/hue/build/env/bin/hue dbshell"
  else
    COMMAND="${CDH_HOME}/share/hue/build/env/bin/hue shell"
    TEST_COMMAND="${CDH_HOME}/share/hue/build/env/bin/hue dbshell"
  fi

  ORACLE_ENGINE_CHECK=$(grep engine ${HUE_CONF_DIR}/hue* | grep -i oracle)
  if [[ ! -z ${ORACLE_ENGINE_CHECK} ]]
  then
    if [[ -z ${ORACLE_HOME} ]]
    then
      ORACLE_PARCEL=/opt/cloudera/parcels/ORACLE_INSTANT_CLIENT/instantclient_11_2
      if [[ -d ${ORACLE_PARCEL} ]]
      then
        ORACLE_HOME=${ORACLE_PARCEL}
        LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${ORACLE_HOME}
        export LD_LIBRARY_PATH ORACLE_HOME
      fi
    fi
    if [[ -z ${ORACLE_HOME} ]]
    then
      echo "It looks like you are using Oracle as your backend"
      echo "ORACLE_HOME must be set to the correct Oracle client"
      echo "before running this script"
      exit 1
    fi
  fi

  HUE_IGNORE_PASSWORD_SCRIPT_ERRORS=1
  if [[ -z ${HUE_DATABASE_PASSWORD} ]]
  then
    echo "CDH 5.5 and above requires that you set the environment variable:"
    echo "HUE_DATABASE_PASSWORD=<dbpassword>"
    exit 1
  fi
  PGPASSWORD=${HUE_DATABASE_PASSWORD}
  export CDH_HOME COMMAND HUE_IGNORE_PASSWORD_SCRIPT_ERRORS PGPASSWORD

  debug "Validating DB connectivity"
#  echo "COMMAND: echo \"from django.db import connection; cursor = connection.cursor(); cursor.execute('select count(*) from auth_user')\" | ${TEST_COMMAND}" | tee -a ${LOG_FILE}
#  echo "from django.db import connection; cursor = connection.cursor(); cursor.execute('select count(*) from auth_user')" | ${TEST_COMMAND} | tee -a ${LOG_FILE}

  QUIT_COMMAND="quit"
  PG_ENGINE_CHECK=$(grep engine ${HUE_CONF_DIR}/hue* | grep -i postgres)
  if [[ ! -z ${PG_ENGINE_CHECK} ]]
  then
    QUIT_COMMAND='\q'
  fi

#  echo "Running echo ${QUIT_COMMAND} | ${TEST_COMMAND}"
#  echo ${QUIT_COMMAND} | ${TEST_COMMAND}
  if [[ $? -ne 0 ]]
  then
    echo "HUE_DATABASE_PASSWORD is incorrect.  Please check CM: http://${HOSTNAME}:7180/api/v5/cm/deployment and search for HUE_SERVER and database to find correct password"
    exit 1
  fi

  BEESWAX_DELETE_RECORDS=999 #number of beeswax records to delete at a time
                                #to avoid Non Fatal Exception: DatabaseError: too many SQL variables
  WORKFLOW_DELETE_RECORDS=999 #number of workflow records to delete at a time
                                #to avoid Non Fatal Exception: DatabaseError: too many SQL variables
  RESET_COUNT=15              #number of deletion attempts before trying max again
  RESET_MAX=5                 #number of resets permitted

debug "Running ${COMMAND}"
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

fh = logging.handlers.RotatingFileHandler(LOGFILE, maxBytes = (1048576*logrotatesize), backupCount = backupcount)
fh.setFormatter(format)
log.addHandler(fh)

log.info('HUE_CONF_DIR: ${HUE_CONF_DIR}')
log.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
log.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
log.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
log.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
log.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))
log.info("Cleaning up anything in the Hue tables oozie*, desktop* and beeswax* older than %s old" % keepDays)

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

echo ""
echo "Logs can be found in ${DESKTOP_LOG_DIR}"

unset PGPASSWORD

}

main "$@"
