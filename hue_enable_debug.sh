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
  HUE_USER="admin"
  HUE_PASSWORD="admin"
  HOSTNAME=$(hostname)
  PORT=8888
  SSL=
  #This is necessary to handle AD auth, doesn't seem to hurt non-ad auth
  #if they have multiple ldap servers or for some reason the drop down
  #at login says something other than "LDAP", then this must match the drop
  #down
  HUE_AUTH_SERVER="LDAP"
  GETOPT=`getopt -n $0 -o u:,w:,a:,n:,p:,s,q:,h \
      -l hueuser:,huepass:,authserver:,hostname:,port:,ssl,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -u|--hueuser)
      HUE_USER=$2
      shift 2
      ;;
    -w|--huepass)
      HUE_PASSWORD=$2
      shift 2
      ;;
    -a|--authserver)
      HUE_AUTH_SERVER=$2
      shift 2
      ;;
    -n|--hostname)
      HOSTNAME=$2
      shift 2
      ;;
    -p|--port)
      PORT=$2
      shift 2
      ;;
    -s|--ssl)
      SSL=$1
      shift 1
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

Enables Hue debug logging:

OPTIONS
   -u|--hueuser		   Hue username - default admin.
   -w|--huepass		   Hue password - default admin.
   -a|--authserver         This is the Ldap auth server name in the hue.ini if using
                           multiple ldap servers for auth.  Must be set to the auth 
                           server that "hueuser" belongs to.
   -n|--hostname           Hue server
   -p|--port               Hue port
   -s|--ssl                Enable https
   -?|--help               Show this message.
EOF
}

main()
{

   parse_arguments "$@"

   HUE_SERVER=${HOSTNAME}
   HUE_PORT=${PORT}
   COOKIE_JAR=/tmp/cookie.jar

   if [[ ! -z ${SSL} ]]
   then
      HUE_HTTP="https"
   else
      HUE_HTTP="http"
   fi

   HUE_PASS_URL="${HUE_HTTP}://${HUE_SERVER}:${HUE_PORT}/accounts/login/"
   hue_login

   HUE_DEBUG_URL="${HUE_HTTP}://${HUE_SERVER}:${HUE_PORT}/desktop/set_all_debug"

   echo "Enabling Debug logging"   
   do_curl \
        POST \
        "${HUE_DEBUG_URL}" \
        -L -H "X-Requested-With: XMLHttpRequest"

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
      ${CURL} \
         ${CURL_OPTS} \
         -k \
         -e "${HUE_HTTP}://${HUE_SERVER}:${HUE_PORT}/" \
         -b @${COOKIE_JAR} \
         -c ${COOKIE_JAR} \
         -H "X-CSRFToken: ${CSRF_TOKEN}" \
         -X ${METHOD} \
         -s \
         -f \
         ${URL} \
         ${ARGS}
   fi

}

function hue_login() {
   echo "Connect to Hue loging page to get Cookie and CSRF_TOKEN"
   do_curl \
	GET \
	"${HUE_PASS_URL}" \
	-L 2>&1 > /dev/null

   echo "Logging into Hue"
   do_curl \
        POST \
        "${HUE_PASS_URL}" \
        -F username=${HUE_USER} -F password="${HUE_PASSWORD}" -F server="${HUE_AUTH_SERVER}" 2>&1 > /dev/null
}

main "$@"
