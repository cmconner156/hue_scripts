#! /usr/bin/env bash

# This file is auto-generated. DO NOT EDIT.
set -x

# Linked 6 to stdout
exec 6>&1
## Close STDOUT file descriptor
#exec 1<&-
## Close STDERR FD
#exec 2<&-

export LOG_DIR=${HOME}/altscript
mkdir -p ${LOG_DIR}
chmod 700 ${LOG_DIR}
export LOG_FILE=${LOG_DIR}/$(basename $0)-$(date "+%s").log
touch ${LOG_FILE}
# Open STDOUT as $LOG_FILE file for read and write.
exec 1<>$LOG_FILE

# Redirect STDERR to STDOUT
exec 2>&1

env

ALIAS=$1
if [ "${ALIAS}" = "" ]; then
    echo "Alias not provided" >&2
    exit 1
fi

JARDIR=${CMF_SERVER_ROOT:-/usr/share/cmf}/lib/
${JAVA_HOME}/bin/java -cp "${JARDIR}"/security*.jar com.cloudera.enterprise.crypto.JceksPasswordExtractor "{{CMF_CONF_DIR}}/{{keystoreFileName}}" "${ALIAS}"

# Restore stdout and close 6
exec 1>&6 6>&-
set +x

exec ${JAVA_HOME}/bin/java -cp "${JARDIR}"/security*.jar com.cloudera.enterprise.crypto.JceksPasswordExtractor "{{CMF_CONF_DIR}}/{{keystoreFileName}}" "${ALIAS}"
