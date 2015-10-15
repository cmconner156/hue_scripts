#!/bin/bash
#This script will check CM to see if Hue is using too much memory
#then will restart if necessary.  It will only restart one Hue
#instance at a time for High Availability.  It requires a
#CM admin user and password.  This script will encode the password
#in a file.  NOTE: this script should be owned by root and have 700
#permissions.

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
  CM_HOSTNAME="localhost"
  CM_PORT="7180"
  CM_USERNAME="admin"
  CM_PASSWORD_INPUT=
  KILL_ME=5000
  VERBOSE=
  LOG_FILE=/var/log/hue/`basename "$0" | awk -F\. '{print $1}'`.log
  ROTATE_SIZE=10
  TMP_LOCATION=/tmp/`basename "$0" | awk -F\. '{print $1}'`
  ENCODE_LOCATION=/var/lib/hue

  GETOPT=`getopt -n $0 -o c:,p:,u:,w:,n,m:,s:,t:,l:,v,h \
      -l cmhost:,cmport:,cmuser:,cmpass:,newpass,killmem:,rotatesize:,tmploc:,encodeloc:,verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -c|--cmhost)
      CM_HOSTNAME=$2
      shift 2
      ;;
    -p|--cmport)
      CM_PORT=$2
      shift 2
      ;;
    -u|--cmuser)
      CM_USERNAME=$2
      shift 2
      ;;
    -w|--cmpass)
      CM_PASSWORD_INPUT=$2
      shift 2
      ;;
    -n|--newpass)
      NEW_PASS=1
      shift
      ;;
    -m|--killmem)
      KILL_ME=$2
      shift 2
      ;;
    -r|--rotatesize)
      ROTATE_SIZE=$2
      shift 2
      ;;
    -t|--tmploc)
      TMP_LOCATION=$2
      shift 2
      ;;
    -l|--encodeloc)
      ENCODE_LOCATION=$2
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=1
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

  ENC_PASSWORD_FILE=${ENCODE_LOCATION}/`basename "$0" | awk -F\. '{print $1}'`.enc
}

usage() {
cat << EOF
usage: $0 [options]

Restarts Hue instances with high memory utilization through CM:

OPTIONS
   -c|--cmhost <hostname>      Host where CM is running - default localhost.
   -p|--cmport <port>          Port CM is running on - default 7180.
   -u|--cmuser <cm_user>       Admin User in CM - default admin.
   -w|--cmpass <user_pass>     Admin User password in CM, required on first run, no default. Will prompt
                               if not provided through this flag. Future runs will use
                               encrypted version in <enc_loc>/`basename "$0" | awk -F\. '{print $1}'`.enc
   -n|--newpass                Prompt for a new password.
   -m|--killmem <mem_mb>       Memory threshold to kill Hue in MB - default 5000.
   -s|--rotatesize <log_mb>    Size of log file before rotating in MB - default 10.
   -t|--tmploc <tmp_loc>       Location to store tmp data - default /tmp/`basename "$0" | awk -F\. '{print $1}'`.
   -l|--encodeloc <enc_loc>    Location to store encoded password in file - default /var/lib/hue.
   -v|--verbose                Enable verbose logging.
   -h|--help                   Show this message.
EOF
}

main() {

   parse_arguments "$@"

   if [[ ! ${USER} =~ .*root* ]]
   then
      echo "Script must be run as root: exiting"
      exit 1
   fi

   if [[ ! -d ${ENCODE_LOCATION} ]]
   then
      mkdir -p ${ENCODE_LOCATION}
   fi

   if [[ ! -z ${CM_PASSWORD_INPUT} ]]
   then
      log "New password provided"
      echo ${CM_PASSWORD_INPUT} | base64 > ${ENC_PASSWORD_FILE}
      chown root:root ${ENC_PASSWORD_FILE}
      chmod 600 ${ENC_PASSWORD_FILE}
   fi

   if [[ -z ${CM_PASSWORD_INPUT} ]]
   then
      if [[ ! -f ${ENC_PASSWORD_FILE} ]] || [[ ! -z ${NEW_PASS} ]]
      then
         message "CM Admin user password required on first run"
         read -s -p "Please enter password:" CM_PASSWORD_INPUT
         log "New password provided"
         echo ${CM_PASSWORD_INPUT} | base64 > ${ENC_PASSWORD_FILE}
         chown root:root ${ENC_PASSWORD_FILE}
         chmod 600 ${ENC_PASSWORD_FILE}
      fi
   fi

   if [[ ! -f ${ENC_PASSWORD_FILE} ]]
   then
      message "CM Admin password has not been provided and this is"
      message "is first run of the script.  Please run again and"
      message "provide password."
      exit 1
   else
      CM_PASSWORD=`cat ${ENC_PASSWORD_FILE} | base64 --decode`
   fi

   DATE=`date '+%Y%m%d-%H%M'`
   YEAR=`date '+%Y'`
   MONTH=`date '+%m'`
   DAY=`date '+%d'`
   HOUR=`date '+%H'`
   MINUTE=`date '+%M'`
   YEAR_PRIOR=`date --date='1 minutes ago' '+%Y'`
   MONTH_PRIOR=`date --date='1 minutes ago' '+%m'`
   DAY_PRIOR=`date --date='1 minutes ago' '+%d'`
   HOUR_PRIOR=`date --date='1 minutes ago' '+%H'`
   MINUTE_PRIOR=`date --date='1 minutes ago' '+%M'`
   MEM_JSON_FILE=${TMP_LOCATION}/mem.json
   MB_BYTES="1048576"

   mkdir -p ${TMP_LOCATION}

   if [[ -f ${LOG_FILE} ]]
   then
      LOG_SIZE=`du -sm ${LOG_FILE} | awk '{print $1}'`
      if [[ ${LOG_SIZE} -gt ${ROTATE_SIZE} ]]
      then
         mv ${LOG_FILE} ${LOG_FILE}.1
      fi
   fi

   MEM_API_URL="/api/v6/timeseries?query=select+mem_rss+where+roleType+%3D+HUE_SERVER&contentType=application%2Fjson&from=${YEAR_PRIOR}-${MONTH_PRIOR}-${DAY_PRIOR}T${HOUR_PRIOR}%3A${MINUTE_PRIOR}%3A00.000Z&to=${YEAR}-${MONTH}-${DAY}T${HOUR}%3A${MINUTE}%3A00.000Z"
   #Get memory usage for all Hue roles:
   log "Getting memory config"
   RESULTS=`curl -s -X GET -u ${CM_USERNAME}:${CM_PASSWORD} -i -o ${MEM_JSON_FILE} "http://${CM_HOSTNAME}:${CM_PORT}${MEM_API_URL}"`
   log ${RESULTS}
   if [[ ! -z `grep "Bad credentials" ${MEM_JSON_FILE}` ]]
   then
      message "Invalid CM User and Password, please run with -n or -w flag to provide new password"
      rm -f ${ENC_PASSWORD_FILE}
      exit 1
   fi

   while read -r LINE
   do
      if  [[ ${LINE} =~ .*clusterName* ]]
      then
         CLUSTERNAME=`echo ${LINE} | awk -F\" '{print $4}'`
      fi
      if  [[ ${LINE} =~ .*serviceName* ]]
      then
         SERVICENAME=`echo ${LINE} | awk -F\" '{print $4}'`
      fi
      if  [[ ${LINE} =~ .*roleName* ]]
      then
         ROLENAME=`echo ${LINE} | awk -F\" '{print $4}'`
      fi
      if  [[ ${LINE} =~ .*value* ]]
      then
         MEM=`echo ${LINE} | awk '{print $3}' | awk -F, '{print $1}'`
         MEM=`printf "%.f" $MEM` # convert from scientific to decimal
         MEM_MB=`expr ${MEM} / ${MB_BYTES}`
         log "${DATE} - ROLENAME: ${ROLENAME} - MEM: ${MEM} - MEM_MB: ${MEM_MB} - SCRIPT_MAX: ${KILL_ME}MB" 
         if [ ${MEM_MB} -gt ${KILL_ME} ]
         then
            log "${DATE} - Restart the Hue Process : Too much memory - Script Max: ${KILL_ME}MB - Hue Current: ${MEM_MB}MB - ROLENAME: ${ROLENAME}"
            RESTART_API_URL="/api/v8/clusters/${CLUSTERNAME}/services/${SERVICENAME}/roleCommands/restart"
            RESULTS=`curl -s -X POST -u ${CM_USERNAME}:${CM_PASSWORD} -i -H "content-type:application/json" -d "{\"items\" : [\"${ROLENAME}\"]}" "http://${CM_HOSTNAME}:${CM_PORT}${RESTART_API_URL}"`
            log ${RESULTS}
            exit 0
         fi
      fi
   done < <(cat ${MEM_JSON_FILE})

   rm -Rf ${MEM_JSON_FILE}
}

debug()
{

  if [[ ! -z $VERBOSE ]]
  then
    echo "$1" >> ${LOG_FILE}
  fi

}

message()
{
  echo "$1" >> ${LOG_FILE}
  echo "$1"
}

log()
{
  echo "$1" >> ${LOG_FILE}
}

main "$@"
