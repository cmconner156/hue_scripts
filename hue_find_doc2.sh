#!/bin/bash
#Checks to make sure certain document for user
#has been converted to doc2

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
  USERNAME=
  TEXT=
  VERBOSE=
  GETOPT=`getopt -n $0 -o o,u:,t:,v,h \
      -l override,username:,text:,verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -o|--override)
      OVERRIDE=true
      shift
      ;;
    -u|--username)
      USERNAME=$2
      shift 2
      ;;
    -t|--text)
      TEXT=$2
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

Checks Hue DB for doc2 entry for specified user:

OPTIONS
   -o|--override           Allow script to run as non-root, must set HUE_CONF_DIR manually before running
   -u|--username <user>    User to check for doc2 entry
   -t|--text <text>        Text to search for such as query name, text in query, workflow name etc
   -v|--verbose            Verbose logging, off by default
   -h|--help               Show this message.
EOF
}

main()
{

  parse_arguments "$@"

  if [[ -z ${USERNAME} ]]
  then
    echo "-u <user> required"
    usage
    exit 1
  fi

  if [[ -z ${TEXT} ]]
  then
    usage
    echo "-t <text> required"
    exit 1
  fi

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
      echo "It looks like you are using Oracle as your backend"
      echo "ORACLE_HOME must be set to the correct Oracle client"
      echo "before running this script"
      exit 1
    fi
  fi

  QUIT_COMMAND="quit"
  PG_ENGINE_CHECK=$(grep engine ${HUE_CONF_DIR}/hue* | grep -i postgres)
  if [[ ! -z ${PG_ENGINE_CHECK} ]]
  then
    QUIT_COMMAND='\q'
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

  echo "HUE_CONF_DIR: ${HUE_CONF_DIR}"

  echo "Validating DB connectivity"
  echo "COMMAND: echo ${QUIT_COMMAND} | ${TEST_COMMAND}"
  echo ${QUIT_COMMAND} | ${TEST_COMMAND}
  if [[ $? -ne 0 ]]
  then
    echo "HUE_DATABASE_PASSWORD is incorrect.  Please check CM: http://${HOSTNAME}:7180/api/v5/cm/deployment and search for HUE_SERVER and database to find correct password"
    exit 1
  fi

  echo "COMMAND: ${COMMAND}"

${COMMAND} 2>&1 <<EOF | tee ${LOG_FILE}
import logging
from desktop.models import Document2
from django.contrib.auth.models import User

username = "${USERNAME}"
text = "${TEXT}"
user = User.objects.get(username=username)

logging.warn("Finding doc2 entries for %s containing string:" % user.username)
logging.warn("%s" % text)

for doc2 in Document2.objects.filter(owner=user):
  if text in doc2.data or text in doc2.name:
    logging.warn("Doc2: %s" % doc2.data)
    logging.warn("")

EOF

unset PGPASSWORD

}

main "$@"
