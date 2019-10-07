#!/bin/bash

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
  ATEST=
  VERBOSE=
  GETOPT=`getopt -n $0 -o a:,v,h \
      -l atest:,verbose,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -a|--atest)
      ATEST=$2
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

Tests SPNEGO connectivity to each service:

OPTIONS
   -a|--atest <none>       Sample var
   -v|--verbose 	   Verbose logging, off by default
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

   AGENT_PROCESS_DIR="/var/run/cloudera-scm-agent/process"

   if [ ! -d "/usr/lib/hadoop" ]
   then
      CDH_HOME=$PARCEL_DIR
   else
      CDH_HOME=/usr
   fi

   if [ -d ${AGENT_PROCESS_DIR} ]
   then
      HUE_CONF_DIR="${AGENT_PROCESS_DIR}/`ls -1 ${AGENT_PROCESS_DIR} | grep HUE_SERVER | sort -n | tail -1 `"
      KT_CONF_DIR="${AGENT_PROCESS_DIR}/`ls -1 ${AGENT_PROCESS_DIR} | grep KT_RENEWER | sort -n | tail -1 `"
   else
      HUE_CONF_DIR="/etc/hue/conf"
      KT_CONF_DIR="/etc/hue/conf"
   fi

   if [[ ! -f ${HUE_CONF_DIR}/hue.ini ]]
   then
      echo "Script must be run on a Hue server as it uses Hue's config"
   fi

   SECURE=`grep -A1 "hadoop.security.authentication" /etc/hadoop/conf/core-site.xml | tail -1 | awk -F\> '{print $2}' | awk -F\< '{print $1}'`
   if [[ ${SECURE} =~ .*kerberos.* ]]
   then
     TICKET_CACHE="/var/run/hue/hue_krb5_ccache"
     if [[ -f ${TICKET_CACHE} ]]
     then
       export KRB5CCNAME=${TICKET_CACHE}
     else
       PRINCIPAL=$(klist -ekt hue.keytab | grep 'hue/' | tail -1 | awk '{print $4}')
       kinit -kt ${KT_CONF_DIR}/hue.keytab ${PRINCIPAL}
     fi
     OPTIONS="${OPTIONS} --negotiate -u :"
     klist
   fi
   
   HTTP_HOST=$(get_property http_host)
   HTTP_PORT=$(get_property http_port)
   declare -A service_property_names
   service_property_names[httpfs]="webhdfs_url"
   service_property_names[rm]="resourcemanager_api_url"
   service_property_names[jhs]="history_server_api_url"
   service_property_names[oozie]="oozie_url"
   service_property_names[solr]="solr_url"

   declare -A service_test_url
   service_test_url[httpfs]="/?op=GETHOMEDIRECTORY"
   service_test_url[rm]="/ws/v1/cluster"
   service_test_url[jhs]="/ws/v1/history"
   service_test_url[oozie]="/v1/admin/status"
   service_test_url[solr]="/admin/cores?action=STATUS"

   test_service httpfs ${OPTIONS}
   echo
   test_service rm ${OPTIONS}
   echo
   test_service jhs ${OPTIONS}
   echo
   test_service oozie ${OPTIONS}
   echo
   test_service solr ${OPTIONS}
   echo

}

function test_service() {

   SERVICE=$1
   shift

   OPTIONS=$2
   shift

   TESTURL=${service_test_url[${SERVICE}]}
   URLBASE=`echo $(get_property ${service_property_names[${SERVICE}]}) | sed "s%/$%%g"`
   URL=${URLBASE}${TESTURL}
   if [[ ! -z ${URLBASE} ]]
   then
      echo "Testing SPNEGO auth for ${SERVICE} against ${URL}"
      do_curl \
         GET \
         "${URL}" \
         ${OPTIONS}
      echo
   fi

}

function get_property() {

   PROPERTY=$1
   shift

   VALUE=`grep ${PROPERTY} ${HUE_CONF_DIR}/hue_safety_valve.ini | awk -F\= '{print $2}'`

   if [[ -z ${VALUE} ]]
   then
      VALUE=`grep ${PROPERTY} ${HUE_CONF_DIR}/hue_safety_valve_server.ini | awk -F\= '{print $2}'`
   fi

   if [[ -z ${VALUE} ]]
   then
      VALUE=`grep ${PROPERTY} ${HUE_CONF_DIR}/hue.ini | awk -F\= '{print $2}'`
   fi

   echo ${VALUE}
}

function do_curl() {

   METHOD=$1
   shift
   URL=$1
   shift
   ARGS=$@

   CURL=$(which curl)
   if [ -z ${COOKIE_JAR} ]
   then
      COOKIE_JAR=/tmp/cookie.jar
   fi
   if [ -f ${COOKIE_JAR} ]
   then
      CSRF_TOKEN=`grep ${HOSTNAME} ${COOKIE_JAR} | grep csrftoken | cut -f 7`
   fi
   if [ ! -f ${CURL} ]
   then
      echo "curl not found, unable to run any curl commands"
   else
      if [[ -z ${VERBOSE} ]]
      then
         ${CURL} \
            ${CURL_OPTS} \
            -k \
            --negotiate \
            -u : \
            -e "http://${HTTP_HOST}:${HTTP_PORT}/" \
            -b @${COOKIE_JAR} \
            -c ${COOKIE_JAR} \
            -H "X-CSRFToken: ${CSRF_TOKEN}" \
            -X ${METHOD} \
            -s \
            -f \
            ${URL} \
            ${ARGS}
       else
         ${CURL} \
            ${CURL_OPTS} \
            -k \
            --negotiate \
            -u : \
            -e "http://${HTTP_HOST}:${HTTP_PORT}/" \
            -b @${COOKIE_JAR} \
            -c ${COOKIE_JAR} \
            -H "X-CSRFToken: ${CSRF_TOKEN}" \
            -X ${METHOD} \
            -s \
            -f \
            -v \
            ${URL} \
            ${ARGS}
       fi
   fi

}

main "$@"
