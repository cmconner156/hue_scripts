#!/bin/bash
#Run query using Hue code outside of Hue

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
  DESKTOP_DEBUG=
  TABLE="default.sample_07"
  USERNAME="admin"
  GETOPT=`getopt -n $0 -o t:,u:o,v,h \
      -l table:,username:,override,verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -t|--table)
      TABLE=$2
      shift 2
      ;;
    -u|--username)
      USERNAME=$2
      shift 2
      ;;
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

Run query using Hue code outside of Hue

OPTIONS
   -u|--username	   Username of a user to run the query as, default: admin
   -q|--query              Query to run, should spawn MR job, default: select count(*) from default.sample_07;
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

  rm -f /var/lib/hue/hue_run_query.end
  while [ ! -f "/var/lib/hue/hue_run_query.end" ]
  do
  
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
      if [[ $(ps -ef | grep [r]unc) ]]
      then
        DESKTOP_LOG_DIR=$(strings /proc/$(ps -ef | grep [r]unc | awk '{print $2}')/environ | grep DESKTOP_LOG_DIR | awk -F\= '{print $2}')
        export $(sed "s/,/\\n/g" ${HUE_SUPERVISOR_CONF} | grep DESKTOP_LOG_DIR | sed "s/'//g")
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
    LOG_FILE=${DESKTOP_LOG_DIR}/`basename "$0" | awk -F\. '{print $1}'`
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
      HUE_HOME="${CDH_HOME}/lib/hue"
    else
      HUE_HOME="${CDH_HOME}/share/hue"
    fi
    HUE_BIN="${HUE_HOME}/build/env/bin"
    COMMAND="${HUE_BIN}/hue shell"
    TEST_COMMAND="${HUE_BIN}/hue dbshell"
    PYTHON="${HUE_BIN}/python"

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

    while read -r ENV
    do
      export $ENV
    done < <(grep environment ${HUE_SUPERVISOR_CONF} | awk -Fenvironment\= '{print $2}' | sed "s/,/\\n/g" | grep -v CM_STATUS | sed "s/'//g")


    DATE=$(date '+%Y%m%d-%H%M%S')
    PID=$(ps -ef | grep [r]unc | awk '{print $2}')
    top -b -n 1 -u hue > ${DESKTOP_LOG_DIR}/top_${DATE}.log

    netstat -anp | grep ${PID} >> ${DESKTOP_LOG_DIR}/netstat_${DATE}.log

    timeout 15s /usr/bin/strace -f -v -p ${PID} -o ${DESKTOP_LOG_DIR}/strace_${DATE}.log -T -t &

    LSOF=$(which lsof)
    if [ -f ${LSOF} ]
    then
      ${LSOF} -P -p ${PID} ${ARGS} >> ${DESKTOP_LOG_DIR}/lsof_${DATE}.log
    fi

    sudo -E -u hue /bin/bash -c "DESKTOP_DEBUG=true ${PYTHON} ${SCRIPT_DIR}/hue_run_query.py ${LOG_FILE}_${DATE} ${HUE_HOME} ${USERNAME} '${TABLE}'" > /dev/null 2>&1

    sleep 300

  done

  unset PGPASSWORD

}

main "$@"
