#!/bin/bash
#Test DB timings on login

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
  GETOPT=`getopt -n $0 -o o,v,h \
      -l verbose,help \
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

Tests how long DB requests take:

OPTIONS
   -o|--override           Allow script to run as non-root, must set HUE_CONF_DIR manually before running
   -v|--verbose		   Enable verbose logging
   -h|--help               Show this message.
EOF
}

debug()
{
   if [[ ! -z $VERBOSE ]]
   then
      echo "$1" >> ${LOG_FILE}
      echo "$1"
   fi
}

main()
{

  parse_arguments "$@"

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
    DESKTOP_LOG_DIR=${HUE_CONF_DIR}/logs
    if [[ -z ${OVERRIDE} ]]
    then
      echo "Script must be run as root: exiting"
      exit 1
    fi
  else
    DESKTOP_LOG_DIR=$(strings /proc/$(ps -ef | grep [r]unc | awk '{print $2}')/environ | grep DESKTOP_LOG_DIR | awk -F\= '{print $2}')
  fi

  LOG_FILE=${DESKTOP_LOG_DIR}/`basename "$0" | awk -F\. '{print $1}'`.log

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
  export CDH_HOME COMMAND HUE_IGNORE_PASSWORD_SCRIPT_ERRORS

  export CDH_HOME HUE_CONF_DIR ORACLE_HOME LD_LIBRARY_PATH COMMAND DEBUG=true
  if [[ ! -z ${VERBOSE} ]]
  then
    export DESKTOP_DEBUG=true
  fi

  echo "Validating DB connectivity" | tee -a ${LOG_FILE}
  echo "COMMAND: echo \"from django.db import connection; cursor = connection.cursor(); cursor.execute('select count(*) from auth_user')\" | ${TEST_COMMAND}" | tee -a ${LOG_FILE}
  echo "from django.db import connection; cursor = connection.cursor(); cursor.execute('select count(*) from auth_user')" | ${TEST_COMMAND} 2>&1 | tee -a ${LOG_FILE}
  if [[ $? -ne 0 ]]
  then
    echo "DB connect test did not work, HUE_DATABASE_PASSWORD may not be correct" | tee -a ${LOG_FILE}
    echo "If the next query test fails check password in CM: http://<cmhostname>:7180/api/v5/cm/deployment and search for HUE_SERVER and database to find correct password" | tee -a ${LOG_FILE}
  fi

  echo "Running queries to test timings.  See results in ${LOG_FILE}" | tee -a ${LOG_FILE}
  debug "Running ${COMMAND}"
  ${COMMAND} 2>&1 <<EOF | tee -a ${LOG_FILE}
from datetime import datetime, timedelta
from time import mktime
from django.db import connection
import logging

log.warn('HUE_CONF_DIR: ${HUE_CONF_DIR}')
log.warn("DB Engine: %s" % desktop.conf.DATABASE.ENGINE.get())
log.warn("DB Name: %s" % desktop.conf.DATABASE.NAME.get())
log.warn("DB User: %s" % desktop.conf.DATABASE.USER.get())
log.warn("DB Host: %s" % desktop.conf.DATABASE.HOST.get())
log.warn("DB Port: %s" % str(desktop.conf.DATABASE.PORT.get()))
log.warn("Testing database query timings")

count = 1
with open("queries.txt", "r") as ins:
    cursor = connection.cursor()
    for line in ins:
      method, query = line.split('|')
      log.warn("method: %s: query: %s" % (method, query))
      try:
        log.warn("Query %s started" % count)
        starttime = datetime.now()
        cursor.execute(query)
        if method == 'fetchone':
          log.warn("%s rows" % method)
          try:
            row = cursor.fetchone()
          except:
            log.warn("EXCEPTION: fetchone failed")
        if method == 'fetchmany':
          log.warn("%s rows" % method)
          rows = cursor.fetchmany(GET_ITERATOR_CHUNK_SIZE)
          log.warn("Fetched %s rows" % len(rows))
          while rows:
              rows = cursor.fetchmany(GET_ITERATOR_CHUNK_SIZE)
              log.warn("Fetched %s rows" % len(rows))
        endtime = datetime.now()
        timediff = difference_in_seconds = abs(mktime(endtime.timetuple()) - mktime(starttime.timetuple()))
        log.warn("Query %s finished in %s" % (count, timediff))
        count = count + 1
      except:
        log.warn("EXCEPTION: query failed")

EOF

}

main "$@"
