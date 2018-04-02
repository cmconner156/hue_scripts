#!/bin/bash
#Removes duplicate docs that do not have content_object

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
  VERBOSE=
  DESKTOP_DEBUG=false
  GETOPT=`getopt -n $0 -o o,v,h \
      -l override,verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -o|--override)
      OVERRIDE=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      DESKTOP_DEBUG=true
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

Fixes bad modified timestamps in queries

OPTIONS
   -o|--override           Allow script to run as non-root, must set HUE_CONF_DIR manually before running
   -v|--verbose            Verbose logging, off by default
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
  if [ -d "/var/run/cloudera-scm-agent/process" ]
  then
    if [[ -z ${HUE_CONF_DIR} ]]
    then
      HUE_CONF_DIR="/var/run/cloudera-scm-agent/process/`ls -1 /var/run/cloudera-scm-agent/process | grep HUE_SERVER | sort -n | tail -1 `"
    fi
  else
    HUE_CONF_DIR="/etc/hue/conf"
  fi
  HUE_SUPERVISOR_CONF=$(echo ${HUE_CONF_DIR} | sed "s/process/supervisor\/include/g").conf
  export HUE_CONF_DIR HUE_SUPERVISOR_CONF

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
      DESKTOP_LOG_DIR=$(strings /proc/$(ps -ef | grep "[h]ue\ runc" | awk '{print $2}')/environ | grep DESKTOP_LOG_DIR | awk -F\= '{print $2}')
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
 
  if [ ! -d "/usr/lib/hadoop" ]
  then
    export $(sed "s/,/\\n/g" ${HUE_SUPERVISOR_CONF} | grep PARCELS_ROOT | sed "s/'//g")
    PARCEL_DIR=${PARCELS_ROOT}/CDH
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

#  ${COMMAND} >> /dev/null 2>&1 <<EOF
  ${COMMAND} <<EOF
LOGFILE = "${LOG_FILE}"
logrotatesize=${LOG_ROTATE_SIZE}
backupcount=${LOG_ROTATE_COUNT}

import logging
import logging.handlers
import json
import time
from datetime import datetime
import desktop.conf
from django.db import models
from django.contrib.auth.models import User
from django.contrib.contenttypes.models import ContentType
from desktop.models import Document, Document2

LOG = logging.getLogger()
format = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
fh = logging.handlers.RotatingFileHandler(LOGFILE, maxBytes = (1048576*logrotatesize), backupCount = backupcount)
fh.setFormatter(format)
LOG.addHandler(fh)
LOG.setLevel(logging.INFO)
LOG.info('HUE_CONF_DIR: ${HUE_CONF_DIR}')
LOG.info("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
LOG.info("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
LOG.info("DB User: %s" % desktop.conf.DATABASE.USER.get())
LOG.info("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
LOG.info("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))

model_class = Document2
extra = "workflow2"
qfilter = None

idlist = []

for user in User.objects.filter():
  LOG.warn("Idlist: %s" % idlist)
  LOG.warn("User: user: %s" % user.username)
  docs = Document.objects.documents(user).exclude(name='pig-app-hue-script')
  duplicated_records = Document.objects.values('name', 'owner').annotate(name_count=models.Count('name')).filter(name_count__gt=1, owner = user)
  names = []
  for obj in duplicated_records:
    names.append(obj["name"])
  duplicate_doc_ids = []
  doclist = Document.objects.values('id', 'name', 'owner').filter(owner = user)
  for obj in doclist:
    if obj["name"] in names:
      duplicate_doc_ids.append(obj["id"])
  LOG.warn("Docs: docs: %s" % docs)
  if model_class is not None:
    ct = ContentType.objects.get_for_model(model_class)
    docs = docs.filter(content_type=ct)
  LOG.warn("Past model_class")
  if extra is not None:
    docs = docs.filter(extra=extra)
  LOG.warn("Past extra")
  if qfilter is not None:
    docs = docs.filter(qfilter)
  LOG.warn("Past qfilter")
  LOG.warn("Grabbing only duplicates")
  docs = docs.filter(id__in=duplicate_doc_ids)
  for d in docs:
    try:
      if d.content_object is None:
        LOG.warn("Adding document id %s with name %s and owner %s to idlist" % (d.id, d.name, user.username))
        idlist.append(d.id)
    except:
      pass


LOG.warn("Before deldocs: idlist: %s" % idlist)
deldocs = Document.objects.filter(id__in=idlist)
LOG.warn("Docs to delete are: %s" % deldocs)
deldocs.delete()


EOF

echo ""
echo "Logs can be found in ${DESKTOP_LOG_DIR}"

unset PGPASSWORD

}

main "$@"
