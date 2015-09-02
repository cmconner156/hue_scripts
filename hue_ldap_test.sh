#!/bin/bash
#NOTE: This script requires ldapsearch to be installed

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
  OUTPUT_DIR_BASE=/tmp/hue_ldap_test
  TEST_USER=${USER}
  GETOPT=`getopt -n $0 -o o:,u:,h \
      -l outdir:,user:,help \
      -- "$@"`
  eval set -- "$GETOPT"
  while true;
  do
    case "$1" in
    -o|--outdir)
      OUTPUT_DIR_BASE=$2
      shift 2
      ;;
    -u|--user)
      TEST_USER=$2
      shift 2
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

Tests Hue Server Ldap Config:

OPTIONS
   -o|--outdir <outdir>    Location to dump collected data - default /tmp/hue_collect_data.
   -h|--help               Show this message.
EOF
}

main()
{

   parse_arguments "$@"
   TMP_ENV_FILE=${OUTPUT_DIR_BASE}/hue_tmp_env.sh
   mkdir -p ${OUTPUT_DIR_BASE}
   LDAPSEARCH=$(which ldapsearch)

   if [[ ! ${USER} =~ .*root* ]]
   then
      echo "Script must be run as root: exiting"
      exit 1
   fi

   if [[ ! -f ${LDAPSEARCH} ]]
   then
      echo "ldapsearch not found, please install ldapsearch"
      exit 1
   else
      LDAPSEARCH_COMMAND="${LDAPSEARCH} -LLL"
   fi

   AGENT_PROCESS_DIR="/var/run/cloudera-scm-agent/process"
   PARCEL_DIR=/opt/cloudera/parcels/CDH
   ORACLE_HOME=/opt/cloudera/parcels/ORACLE_INSTANT_CLIENT/instantclient_11_2/
   LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${ORACLE_HOME}
#   LOG_FILE=/var/log/hue/`basename "$0" | awk -F\. '{print $1}'`.log
#   LOG_ROTATE_SIZE=10 #MB before rotating, size in MB before rotating log to .1
#   LOG_ROTATE_COUNT=2 #number of log files, so 20MB max
   DATE=`date '+%Y%m%d-%H%M'`

   if [ ! -d "/usr/lib/hadoop" ]
   then
      CDH_HOME=$PARCEL_DIR
   else
      CDH_HOME=/usr
   fi

   if [ -d "${AGENT_PROCESS_DIR}" ]
   then
      HUE_CONF_DIR="${AGENT_PROCESS_DIR}/`ls -1 ${AGENT_PROCESS_DIR} | grep HUE | sort -n | tail -1 `"
   else
      HUE_CONF_DIR="/etc/hue/conf"
   fi

   if [ -d "${CDH_HOME}/lib/hue/build/env/bin" ]
   then
      COMMAND="${CDH_HOME}/lib/hue/build/env/bin/hue shell"
   else
      COMMAND="${CDH_HOME}/share/hue/build/env/bin/hue shell"
   fi

   export CDH_HOME HUE_CONF_DIR ORACLE_HOME LD_LIBRARY_PATH COMMAND

   ${COMMAND} <<EOF
import desktop.conf
#import pprint
#pp = pprint.PrettyPrinter(indent=4)

def write_property( hue_ldap_conf_file, ldap_config, property_name):
  if property_name != "bind_password":
    try:
      func = getattr(ldap_config, "%s" % (property_name.upper()))
    except AttributeError:
      print 'function not found "%s" ()' % (property_name.upper().get())
    else:
      property_value=func.get()
  else:
    property_value = desktop.conf.get_ldap_bind_password(ldap_config)
#  print property_value
  hue_ldap_conf_file.write("%s=%s\n" % (property_name,property_value))
  return

hue_ldap_conf_file = open('${TMP_ENV_FILE}', 'w')
hue_ldap_conf_file.write("#!/bin/bash\n")
server = None
ldap_config = desktop.conf.LDAP.LDAP_SERVERS.get()[server] if server else desktop.conf.LDAP
pp.pprint(ldap_config.__dict__)

write_property( hue_ldap_conf_file, ldap_config, "ldap_url")
write_property( hue_ldap_conf_file, ldap_config, "bind_dn")
#write_property( hue_ldap_conf_file, ldap_config, "bind_password")
write_property( hue_ldap_conf_file, ldap_config, "ldap_cert")
write_property( hue_ldap_conf_file, ldap_config, "search_bind_authentication")
write_property( hue_ldap_conf_file, ldap_config, "base_dn")
EOF

source ${TMP_ENV_FILE}

if [[ -z ${ldap_url} ]]
then
   echo "Required attribute ldap_url is not set"
   exit 1
else

   LDAPSEARCH_COMMAND="${LDAPSEARCH_COMMAND} -H ${ldap_url}"
fi

if [[ ! -z ${bind_dn} ]]
then
#   if [[ -z ${bind_password} ]]
#   then
#      echo "if bind_dn is set, then bind_password is required"
#      exit 1
#   fi
   LDAPSEARCH_COMMAND="${LDAPSEARCH_COMMAND} -x -D ${bind_dn} -W"
fi

if [[ -z ${base_dn} ]]
then
   echo "Required attribute bind_dn is not set"
   exit 1
else
   LDAPSEARCH_COMMAND="${LDAPSEARCH_COMMAND} -b ${base_dn}"
fi

LDAPSEARCH_COMMAND="${LDAPSEARCH_COMMAND} \"(sAMAccountName=${TEST_USER})\" \"dn sAMAccountName\""

#example command
#ldapsearch -LLL -H ldap://conner-linux -b "dc=test,dc=com" -x -D cn=manager,dc=test,dc=com -w password "(cn=tuser5)"
#current config
#'ldap_url': 'ldaps://w2k8-ad2.ad2.test.com:3269', 
#'search_bind_authentication': 'true'
#'create_users_on_login': 'true'
#'base_dn': 'dc=ad2,dc=test,dc=com'
#'bind_dn': 'cn=Administrator,cn=users,dc=ad2,dc=test,dc=com'
#'bind_password': 'Password1'
#'users': {}
#'groups': {}},
echo "Running ldapsearch command:"
echo "${LDAPSEARCH_COMMAND}"
if [[ ! -z ${bind_dn} ]]
then
   echo "You will be prompted for the password for the bind user: ${bind_dn}"
fi
${LDAPSEARCH_COMMAND}
#cat ${TMP_ENV_FILE}
rm -Rf ${OUTPUT_DIR_BASE}

}

#function do_curl() {

#   METHOD=$1
#   shift
#   URL=$1
#   shift
#   ARGS=$@

#   CURL=$(which curl)
#   if [ ! -f ${CURL} ]
#   then
#      echo "curl not found, unable to run any curl commands"
#   else
#   fi

#}

main "$@"
