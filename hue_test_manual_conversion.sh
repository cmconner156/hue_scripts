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
  USERNAME=
  TEXT=
  VERBOSE=
  GETOPT=`getopt -n $0 -o o,u:,v,h \
      -l override,username:,verbose,help \
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

  SCRIPT_DIR="$( cd -P "$( dirname "$0" )" && pwd )"
  PYTHONPATH=${SCRIPT_DIR}/lib:${PYTHONPATH}
  export SCRIPT_DIR PYTHONPATH

  if [[ -z ${USERNAME} ]]
  then
    echo "-u <user> required"
    usage
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
    COMMAND="PYTHONPATH=${SCRIPT_DIR}/lib:${PYTHONPATH} ${CDH_HOME}/share/hue/build/env/bin/hue shell"
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

  echo "HUE_CONF_DIR: ${HUE_CONF_DIR}" | tee -a ${LOG_FILE}

  echo "Validating DB connectivity" | tee -a ${LOG_FILE}
#  echo "COMMAND: echo \"from django.db import connection; cursor = connection.cursor(); cursor.execute('select count(*) from auth_user')\" | ${TEST_COMMAND}" | tee -a ${LOG_FILE}
#  echo "from django.db import connection; cursor = connection.cursor(); cursor.execute('select count(*) from auth_user')" | ${TEST_COMMAND} | tee -a ${LOG_FILE}
  if [[ $? -ne 0 ]]
  then
    echo "DB connect test did not work, HUE_DATABASE_PASSWORD may not be correct" | tee -a ${LOG_FILE}
    echo "If the next query test fails check password in CM: http://<cmhostname>:7180/api/v5/cm/deployment and search for HUE_SERVER and database to find correct password" | tee -a ${LOG_FILE}
  fi

  echo "COMMAND: ${COMMAND}" | tee -a ${LOG_FILE}

  ${COMMAND} 2>&1 <<EOF | tee -a ${LOG_FILE}
from django.contrib.auth.models import User
from hue_converters import DocumentConverterHueScripts

DOC2_NAME_INVALID_CHARS = "[<>/~\`u'\xe9'u'\xfa'u'\xf3'u'\xf1'u'\xed']"

username = "${USERNAME}"
#text = "${TEXT}"
user = User.objects.get(username=username)

doc_count = 0
converter = DocumentConverterHueScripts(user)
converter.convertfailed()


EOF

echo "" | tee -a ${LOG_FILE}

}

main "$@"
