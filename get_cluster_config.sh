#!/bin/bash

export HUE_CONF_DIR="/var/run/cloudera-scm-agent/process/`ls -1 /var/run/cloudera-scm-agent/process | grep HUE_SERVER | sort -n | tail -1 `"

CLUSTER_NAME=$(hostname | awk -F- '{print $1}')
CONF_DIR_NAME="${CLUSTER_NAME}_hue_conf"
TMP_LOC=/tmp/${CONF_DIR_NAME}

rm -Rf ${TMP_LOC}*

cp -pr ${HUE_CONF_DIR} ${TMP_LOC}
cp -pr /opt/cloudera/security ${TMP_LOC}/
find /usr/share/cmf/lib/ -name "security*.jar" -exec cp {} ${TMP_LOC}/security.jar \;

cd /tmp && zip -r ${CONF_DIR_NAME}.zip ${CONF_DIR_NAME}
echo "Created ${TMP_LOC}.zip"

