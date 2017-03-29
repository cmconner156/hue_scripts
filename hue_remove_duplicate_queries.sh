#!/bin/bash
#Test to search for doc1 and doc2

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
  PURGENEW=False
  USERNAME=
  ALLOWDUPES=False
  VERBOSE=
  DESKTOP_DEBUG=false
  GETOPT=`getopt -n $0 -o o,n,u:,d,v,h \
      -l override,purgenew,username:,duplicates,verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -o|--override)
      OVERRIDE=true
      shift
      ;;
    -n|--PURGENEW)
      PURGENEW=True
      shift
      ;;
    -u|--username)
      USERNAME=$2
      shift 2
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

Migrates missing queries and docs:

OPTIONS
   -o|--override           Allow script to run as non-root, must set HUE_CONF_DIR manually before running
   -n|--purgenew	   Will purge all queries that have '(new)' in their name.
   -u|--username <user>    User to check for doc2 entry if not set, then runs for all users.  Slower.
   -d|--duplicates	   Allows duplicate entries to be created.  This will run faster.
   -v|--verbose            Verbose logging, off by default
   -h|--help               Show this message.
EOF
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
    if [[ $(ps -ef | grep [r]unc) ]]
    then
      DESKTOP_LOG_DIR=$(strings /proc/$(ps -ef | grep [r]unc | awk '{print $2}')/environ | grep DESKTOP_LOG_DIR | awk -F\= '{print $2}')
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
  echo "SCRIPT_DIR: ${SCRIPT_DIR}" | tee -a ${LOG_FILE}
  echo "PYTHONPATH: ${PYTHONPATH}" | tee -a ${LOG_FILE}
  
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
      echo "It looks like you are using Oracle as your backend" | tee -a ${LOG_FILE}
      echo "ORACLE_HOME must be set to the correct Oracle client" | tee -a ${LOG_FILE}
      echo "before running this script" | tee -a ${LOG_FILE}
      exit 1
    fi
  fi

  HUE_IGNORE_PASSWORD_SCRIPT_ERRORS=1
  if [[ -z ${HUE_DATABASE_PASSWORD} ]]
  then
    echo "CDH 5.5 and above requires that you set the environment variable:" | tee -a ${LOG_FILE}
    echo "HUE_DATABASE_PASSWORD=<dbpassword>" | tee -a ${LOG_FILE}
    exit 1
  fi
  export CDH_HOME COMMAND HUE_IGNORE_PASSWORD_SCRIPT_ERRORS DESKTOP_DEBUG

  echo "HUE_CONF_DIR: ${HUE_CONF_DIR}" | tee -a ${LOG_FILE}

  echo "Validating DB connectivity" | tee -a ${LOG_FILE}
#  echo "COMMAND: echo \"from django.db import connection; cursor = connection.cursor(); cursor.execute('select count(*) from auth_user')\" | ${TEST_COMMAND}" | tee -a ${LOG_FILE}
#  echo "from django.db import connection; cursor = connection.cursor(); cursor.execute('select count(*) from auth_user')" | ${TEST_COMMAND} | tee -a ${LOG_FILE}
  if [[ $? -ne 0 ]]
  then
    echo "DB connect test did not work, HUE_DATABASE_PASSWORD may not be correct" | tee -a ${LOG_FILE}
    echo "If the next query test fails check password in CM: http://<cmhostname>:7180/api/v5/cm/deployment and search for HUE_SERVER and database to find correct password" | tee -a ${LOG_FILE}
  fi

  env
  echo "COMMAND: ${COMMAND}" | tee -a ${LOG_FILE}

  ${COMMAND} 2>&1 <<EOF | tee -a ${LOG_FILE}
import logging
import json

from django.contrib.auth.models import User
from desktop.models import Document2
from doc2_utils import findMatchingQuery, getSavedQueries

LOG = logging.getLogger(__name__)

username = "${USERNAME}"
if not username:
  users = User.objects.filter()
else:
  users = User.objects.filter(username=username)

total_count = 0
for user in users:
  if ${PURGENEW}:
    matchdocs = []
    queries = getSavedQueries(user=user, name='(new)', include_history=True)
    for query in queries:
      matchdocs.append(query.id)
    LOG.debug("deleting %s queries that contain (new)" % queries.count())
    Document2.objects.filter(id__in=matchdocs).delete()
  queries = getSavedQueries(user=user, include_history=True)
  LOG.debug("user: %s: total queries to go through: %s" % (user.username, queries.count()))
  for query in queries:
    total_count = total_count + 1
    try:
      matchdata = json.loads(query.data)
      matchname = query.name
      matchid = query.id
      if 'snippets' in matchdata:
        matchquery = matchdata['snippets'][0]['statement_raw']
        matchdocs = findMatchingQuery(user=user, id=matchid, name=matchname, query=matchquery, include_history=True, all=True, values=True)
        if matchdocs:
          Document2.objects.filter(id__in=matchdocs).delete()
          LOG.debug("finished query number: %s" % total_count)
    except Document2.DoesNotExist, e:
      pass


EOF

echo "" | tee -a ${LOG_FILE}
echo "Logs can be found in ${DESKTOP_LOG_DIR}"

}

main "$@"
