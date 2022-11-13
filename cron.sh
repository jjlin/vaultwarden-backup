#!/bin/bash

# Use the value of the corresponding environment variable, or the
# default if none exists.
: ${VAULTWARDEN_ROOT:="$(realpath "${0%/*}"/..)"}

BACKUP_ROOT="${VAULTWARDEN_ROOT}/backup"
BACKUP_LOGS="${BACKUP_ROOT}/logs"
BACKUP_TIMESTAMP="$(date '+%Y%m%d-%H%M')"

if "${BACKUP_ROOT}"/backup.sh >"${BACKUP_ROOT}"/backup.log 2>&1; then
    RESULT="success"
    EXITCODE=0
else
    RESULT="failure"
    EXITCODE=1
fi

cp -a "${BACKUP_ROOT}"/backup.log "${BACKUP_LOGS}"/backup-${RESULT}-${BACKUP_TIMESTAMP}.log
exit ${EXITCODE}
