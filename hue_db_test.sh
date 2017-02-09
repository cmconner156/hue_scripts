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
  VERBOSE=
  GETOPT=`getopt -n $0 -o v,h \
      -l verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
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
   LOG_DIR=/var/log/hue
   if [[ ! -d ${LOG_DIR} ]]
   then
      mkdir -p ${LOG_DIR}
      chown -R hue:hue ${LOG_DIR}
   fi
   LOG_FILE=${LOG_DIR}/`basename "$0" | awk -F\. '{print $1}'`.log
   LOG_ROTATE_SIZE=10 #MB before rotating, size in MB before rotating log to .1
   LOG_ROTATE_COUNT=2 #number of log files, so 20MB max
   DATE=`date '+%Y%m%d-%H%M'`
#   KEEP_DAYS=7    #Number of days of beeswax and oozie history to keep
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

   for config in $(grep engine= ${HUE_CONF_DIR}/hue* | sort -n)
   do
      ENGINE=$(echo ${config} | awk -F: '{print $2}')
   done
   
   if [[ ${ENGINE} =~ .*oracle.* ]]
   then
      if [[ -z ${ORACLE_HOME} ]]
      then
         ORACLE_HOME=/opt/cloudera/parcels/ORACLE_INSTANT_CLIENT/instantclient_11_2/
      fi
      LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${ORACLE_HOME}
      if [[ ! -d ${ORACLE_HOME} ]]
      then
         echo "Your engine is Oracle, you must set ORACLE_HOME correctly before running this script"
         echo "Current ORACLE_HOME: ${ORACLE_HOME}"
         exit 0
      fi
   fi

   export CDH_HOME HUE_CONF_DIR ORACLE_HOME LD_LIBRARY_PATH COMMAND DEBUG=true
   if [[ ! -z ${VERBOSE} ]]
   then
      export DESKTOP_DEBUG=true
   fi

   debug "Running echo \"from django.db import connection; cursor = connection.cursor(); cursor.execute('select count(*) from auth_user')\" | ${COMMAND}"
   echo "from django.db import connection; cursor = connection.cursor(); cursor.execute('select count(*) from auth_user')" | ${COMMAND}
   if [[ $? -ne 0 ]]
   then
      echo "HUE_DATABASE_PASSWORD is incorrect.  Please check CM: http://<cmhostname>:7180/api/v5/cm/deployment and search for HUE_SERVER and database to find correct password"
      exit 1
   fi

debug "Running ${COMMAND}"
${COMMAND} >> /dev/null 2>&1 <<EOF
from datetime import datetime, timedelta
from time import mktime
from django.db import connection
import logging
import logging.handlers

LOGFILE="${LOG_FILE}"
GET_ITERATOR_CHUNK_SIZE = 100

log = logging.getLogger('')
log.setLevel(logging.DEBUG)
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
log.info("Testing database query timings")

count = 1
with open("queries.txt", "r") as ins:
    cursor = connection.cursor()
    for line in ins:
      method, query = line.split('|')
      log.info("method: %s: query: %s" % (method, query))
      try:
        log.info("Query %s started" % count)
        starttime = datetime.now()
        cursor.execute(query)
        if method == 'fetchone':
          log.info("%s rows" % method)
          try:
            row = cursor.fetchone()
          except:
            log.info("EXCEPTION: fetchone failed")
        if method == 'fetchmany':
          log.info("%s rows" % method)
          rows = cursor.fetchmany(GET_ITERATOR_CHUNK_SIZE)
          log.info("Fetched %s rows" % len(rows))
          while rows:
              rows = cursor.fetchmany(GET_ITERATOR_CHUNK_SIZE)
              log.info("Fetched %s rows" % len(rows))
        endtime = datetime.now()
        timediff = difference_in_seconds = abs(mktime(endtime.timetuple()) - mktime(starttime.timetuple()))
        log.info("Query %s finished in %s" % (count, timediff))
        count = count + 1
      except:
        log.info("EXCEPTION: query failed")

EOF

}

main "$@"
