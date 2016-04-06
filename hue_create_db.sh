#!/bin/bash
set -x
PARCEL_DIR=/opt/cloudera/parcels/CDH
LOG_FILE=/var/log/hue/`basename "$0" | awk -F\. '{print $1}'`.log
DATABASE=$1
PASSWORD=$2

if [[ -z ${PASSWORD} ]]
then
   PASSWORD="password"
fi

if [[ -z ${DATABASE} ]]
then
   echo "Usage: hue_create_db.sh <database_name> <password>"
   exit 1
fi

HUE_CONF_DIR=/tmp/hue_create_db/${DATABASE}
mkdir -p ${HUE_CONF_DIR}

if [ ! -d "/usr/lib/hadoop" ]
then
   CDH_HOME=$PARCEL_DIR
else
   CDH_HOME=/usr
fi

if [ -d "${CDH_HOME}/lib/hue/build/env/bin" ]
then
   COMMAND="${CDH_HOME}/lib/hue/build/env/bin/hue"
else
   COMMAND="${CDH_HOME}/share/hue/build/env/bin/hue"
fi

ORACLE_HOME=/opt/cloudera/parcels/ORACLE_INSTANT_CLIENT/instantclient_11_2/
LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${ORACLE_HOME}
export CDH_HOME HUE_CONF_DIR ORACLE_HOME LD_LIBRARY_PATH COMMAND PASSWORD DATABASE

cat > ${HUE_CONF_DIR}/hue.ini << EOF
[desktop]
[[database]]
#engine=sqlite3
#name=/var/lib/hue/desktop.db
engine=mysql
host=`hostname`
port=3306
user=${DATABASE}
password=${PASSWORD}
name=${DATABASE}
EOF

cat > ${HUE_CONF_DIR}/create.sql << EOF
drop database if exists ${DATABASE};
create database ${DATABASE};
grant all on *.* to '${DATABASE}'@'%' identified by '${PASSWORD}';
EOF

mysql -uroot -p${PASSWORD} < ${HUE_CONF_DIR}/create.sql

${COMMAND} syncdb --noinput
${COMMAND} migrate --merge

CONSTRAINT_ID=$(mysql -uroot -p${PASSWORD} ${DATABASE} -e "show create table auth_permission" | grep content_type_id_refs_id | awk -Fid_ '{print $3}' | awk -F\` '{print $1}')

cat > ${HUE_CONF_DIR}/prepare.sql << EOF
ALTER TABLE auth_permission DROP FOREIGN KEY content_type_id_refs_id_${CONSTRAINT_ID};
delete from django_content_type;
EOF

mysql -uroot -p${PASSWORD} ${DATABASE} < ${HUE_CONF_DIR}/prepare.sql




