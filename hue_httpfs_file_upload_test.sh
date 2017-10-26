#!/bin/bash
set -x

#parse command line arguments
parse_arguments()
{
  # Test that we're using compatible getopt version.
  getopt -T > /dev/null
  if [[ $? -ne 4 ]]; then
    echo "Incompatible getopt version."
    exit 1
  fi

  GETOPT=`getopt -n $0 -o u:,f:,v,h \
      -l user:,file:,verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -u|--user)
      HTTPFS_USER=$2
      shift 2
      ;;
    -f|--file)
      FILE=$2
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
  if [[ -z ${HTTPFS_USER} ]]
  then
    HTTPFS_USER="admin"
  fi
  if [[ -z ${FILE} ]]
  then
    echo "-f file required, please specify"
    usage
    exit 1
  fi

}

usage()
{
cat << EOF
usage: $0 [options]

Tests uploading a file to HTTPFS using Hue creds:

OPTIONS
   -u|--user		   Hue username - default admin.
   -f|--file		   Test file to upload - required
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

   LOG_FILE=/tmp/hue_httpfs_file_upload_test.log
   
   FILEPATH=${FILE}
   FILE=$(urlencode "$(basename ${FILE})$(date +%s)")
   
   CM_CONFIG_FILE='/etc/cloudera-scm-agent/config.ini'
   if [[ -f ${CM_CONFIG_FILE} ]]
   then
      CM_SUPERVISOR_DIR=$(grep agent_wide_credential_cache_location /etc/cloudera-scm-agent/config.ini | grep -v "\#" | awk -F= '{print $2}')
      if [[ -z ${CM_SUPERVISOR_DIR} ]]
      then
         CM_SUPERVISOR_DIR="/var/run/cloudera-scm-agent"
      fi
      CM_SUPERVISOR_DIR="${CM_SUPERVISOR_DIR}/supervisor/include"
      CM_HUE_STRING="HUE_SERVER"
      CM_KT_RENEWER_STRING="KT_RENEWER"
      HUE_ENV_CONF=$(ls -1 ${CM_SUPERVISOR_DIR}/*${CM_HUE_STRING}*)
      export HUE_CONF_DIR=$(grep directory ${HUE_ENV_CONF} | awk -F= '{print $2}')
      KT_ENV_CONF=$(ls -1 ${CM_SUPERVISOR_DIR}/*${CM_KT_RENEWER_STRING}*)
      export KT_CONF_DIR=$(grep directory ${KT_ENV_CONF} | awk -F= '{print $2}')
   else
      export HUE_CONF_DIR=/etc/hue/conf
      export KT_CONF_DIR=/var/lib/hue
   fi   


   export KT_PRINC=$(klist -ekt ${KT_CONF_DIR}/hue.keytab | grep "hue\/" | awk '{print $4}' | tail -1)
   kinit -kt ${KT_CONF_DIR}/hue.keytab ${KT_PRINC}
   klist -e #just to make sure you have Hue princ

   HTTPFS_HTTP=$(get_base_url $HUE_CONF_DIR "webhdfs_url")

   GETFILESTATUS_USER_URL="${HTTPFS_HTTP}/webhdfs/v1/user?op=GETFILESTATUS&user.name=hue&doas=${HTTPFS_USER}"
   GETFILESTATUS_HOME_URL="${HTTPFS_HTTP}/webhdfs/v1/user/${HTTPFS_USER}?op=GETFILESTATUS&user.name=hue&doas=${HTTPFS_USER}"
   CHECKACCESS_URL="${HTTPFS_HTTP}/webhdfs/v1/user/${HTTPFS_USER}?op=CHECKACCESS&fsaction=rw-&user.name=hue&doas=${HTTPFS_USER}"
   GETFILESTATUS_FILE_URL="${HTTPFS_HTTP}/webhdfs/v1/user/${HTTPFS_USER}/${FILE}.tmp?op=GETFILESTATUS&user.name=hue&doas=${HTTPFS_USER}"
   PUT_CREATE_FILE_URL="${HTTPFS_HTTP}/webhdfs/v1/user/${HTTPFS_USER}/${FILE}.tmp?permission=0660&op=CREATE&user.name=hue&overwrite=false&doas=${HTTPFS_USER}"
   GETFILESTATUS_CREATED_URL="${HTTPFS_HTTP}/webhdfs/v1/user/${HTTPFS_USER}/${FILE}.tmp?op=GETFILESTATUS&user.name=hue&doas=${HTTPFS_USER}"
   POST_APPEND_FILE_URL="${HTTPFS_HTTP}/webhdfs/v1/user/${HTTPFS_USER}/${FILE}.tmp?op=APPEND&user.name=hue&doas=${HTTPFS_USER}"

   PYTHON_REQUESTS="python-requests/2.10.0"
   HEADER_CONTENT_TYPE="Content-Type:application/octet-stream"
   HEADER_0CONTENT="Content-Length:0"

   echo 2>&1 | tee -a ${LOG_FILE}
   echo "Test FILE UPLOAD GETFILESTATUS_USER" 2>&1 | tee -a ${LOG_FILE}
   echo "${GETFILESTATUS_USER_URL}" 2>&1 | tee -a ${LOG_FILE}
   do_curl \
        GET \
        "${GETFILESTATUS_USER_URL}" \
	-v -L -A "${PYTHON_REQUESTS}" \

   echo 2>&1 | tee -a ${LOG_FILE}
   echo "Test FILE UPLOAD GETFILESTATUS_HOME" 2>&1 | tee -a ${LOG_FILE}
   echo "${GETFILESTATUS_HOME_URL}" 2>&1 | tee -a ${LOG_FILE}
   do_curl \
        GET \
        "${GETFILESTATUS_HOME_URL}" \
	-v -L -A "${PYTHON_REQUESTS}" \

   echo 2>&1 | tee -a ${LOG_FILE}
   echo "Test FILE UPLOAD CHECkACCESS" 2>&1 | tee -a ${LOG_FILE}
   echo "${CHECKACCESS_URL}" 2>&1 | tee -a ${LOG_FILE}
   do_curl \
        GET \
        "${CHECKACCESS_URL}" \
	-v -L -A "${PYTHON_REQUESTS}" \

   echo 2>&1 | tee -a ${LOG_FILE}
   echo "Test FILE UPLOAD GETFILESTATUS_FILE" 2>&1 | tee -a ${LOG_FILE}
   echo "${GETFILESTATUS_FILE_URL}" 2>&1 | tee -a ${LOG_FILE}
   do_curl \
        GET \
        "${GETFILESTATUS_FILE_URL}" \
	-v -L -A "${PYTHON_REQUESTS}" \

   echo 2>&1 | tee -a ${LOG_FILE}
   echo "Test FILE UPLOAD PUT_CREATE_FILE" 2>&1 | tee -a ${LOG_FILE}
   echo "${PUT_CREATE_FILE_URL}" 2>&1 | tee -a ${LOG_FILE}
   do_curl \
        PUT \
        "${PUT_CREATE_FILE_URL}" \
	-v -L -A "${PYTHON_REQUESTS}" \
	-H "${HEADER_0CONTENT}" \
	-H ${HEADER_CONTENT_TYPE} \

   echo 2>&1 | tee -a ${LOG_FILE}
   echo "Test FILE UPLOAD GETFILESTATUS_CREATED" 2>&1 | tee -a ${LOG_FILE}
   echo "${GETFILESTATUS_CREATED_URL}" 2>&1 | tee -a ${LOG_FILE}
   do_curl \
        GET \
        "${GETFILESTATUS_CREATED_URL}" \
	-v -L -A "${PYTHON_REQUESTS}" \
   
   echo 2>&1 | tee -a ${LOG_FILE}
   echo "Test FILE UPLOAD POST_APPEND_FILE" 2>&1 | tee -a ${LOG_FILE}
   echo "${POST_APPEND_FILE_URL}" 2>&1 | tee -a ${LOG_FILE}
   do_curl \
        POST \
        "${POST_APPEND_FILE_URL}" \
	-v -L -A "${PYTHON_REQUESTS}" \
	-H "${HEADER_CONTENT_TYPE}" \
	-T ${FILEPATH} \

}

function do_curl() {

   METHOD=$1
   shift
   URL=$1
   shift
   ARGS="$@"

   CURL=$(which curl)
   if [ -z ${COOKIE_JAR} ]
   then
      COOKIE_JAR=/tmp/cookie.jar
   fi
   if [ ! -f ${CURL} ]
   then
      echo "curl not found, unable to run any curl commands"
   else
      debug "Connecting to ${URL}"
      debug "${CURL} \
         ${CURL_OPTS} \
         --negotiate -u : \
         --silent \
         -k \
         -e \"${HTTPFS_HTTP}/\" \
         -b @${COOKIE_JAR} \
         -c ${COOKIE_JAR} \
         -X ${METHOD} \
         -f \
         ${URL} \
         ${ARGS}" 2>&1 | tee -a ${LOG_FILE}

      ${CURL} \
         ${CURL_OPTS} \
         --negotiate -u : \
         --silent \
         -k \
         -e "${HTTPFS_HTTP}" \
         -b @${COOKIE_JAR} \
         -c ${COOKIE_JAR} \
         -X ${METHOD} \
         -f \
         ${URL} \
         ${ARGS} 2>&1 | tee -a ${LOG_FILE}
   fi

}

debug()
{
   if [[ ! -z $VERBOSE ]]
   then
      echo "$1"
   fi
}

urlencode() {
    # urlencode <string>
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C

    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done

    LC_COLLATE=$old_lc_collate
}

function get_base_url() {
  HUE_CONF_DIR=$1
  shift
  CHECKSTRING=$1
  shift
  BASE_URL=$(grep ${CHECKSTRING} ${HUE_CONF_DIR}/hue_safety_valve_server.ini | tail -1) 
  if [[ -z ${BASE_URL} ]]
  then
    BASE_URL=$(grep ${CHECKSTRING} ${HUE_CONF_DIR}/hue_safety_valve.ini | tail -1) 
  fi
  if [[ -z ${BASE_URL} ]]
  then
    BASE_URL=$(grep ${CHECKSTRING} ${HUE_CONF_DIR}/hue.ini | tail -1) 
  fi
  echo ${BASE_URL} | awk -F= '{print $2}' | awk -F\/ '{print $1"/"$2"/"$3}'
}

main "$@"
