#!/bin/bash

set -ex

# Use the value of the corresponding environment variable, or the
# default if none exists.
: ${VAULTWARDEN_ROOT:="$(realpath "${0%/*}"/..)"}
: ${SQLITE3:="/usr/bin/sqlite3"}
: ${RCLONE:="/usr/local/bin/rclone"}
: ${GPG:="/usr/bin/gpg"}
: ${AGE:="/usr/local/bin/age"}

DATA_DIR="data"
BACKUP_ROOT="${VAULTWARDEN_ROOT}/backup"
BACKUP_TIMESTAMP="$(date '+%Y%m%d-%H%M')"
BACKUP_DIR_NAME="vaultwarden-${BACKUP_TIMESTAMP}"
BACKUP_DIR_PATH="${BACKUP_ROOT}/${BACKUP_DIR_NAME}"
BACKUP_FILE_DIR="archives"
BACKUP_FILE_NAME="${BACKUP_DIR_NAME}.tar.xz"
BACKUP_FILE_PATH="${BACKUP_ROOT}/${BACKUP_FILE_DIR}/${BACKUP_FILE_NAME}"
DB_FILE="db.sqlite3"

source "${BACKUP_ROOT}"/backup.conf

cd "${VAULTWARDEN_ROOT}"
mkdir -p "${BACKUP_DIR_PATH}"

# Back up the database using the Online Backup API (https://www.sqlite.org/backup.html)
# as implemented in the SQLite CLI. However, if a call to sqlite3_backup_step() returns
# one of the transient errors SQLITE_BUSY or SQLITE_LOCKED, the CLI doesn't retry the
# backup step by default; instead, it stops the backup immediately and returns an error.
#
# Encountering this situation is unlikely, but to be on the safe side, the CLI can be
# configured to retry by using the `.timeout <ms>` meta command to set a busy handler
# (https://www.sqlite.org/c3ref/busy_timeout.html), which will keep trying to open a
# locked table until the timeout period elapses.
busy_timeout=30000 # in milliseconds
${SQLITE3} -cmd ".timeout ${busy_timeout}" \
           "file:${DATA_DIR}/${DB_FILE}?mode=ro" \
           ".backup '${BACKUP_DIR_PATH}/${DB_FILE}'"

backup_files=()
for f in attachments config.json rsa_key.der rsa_key.pem rsa_key.pub.der rsa_key.pub.pem sends; do
    if [[ -e "${DATA_DIR}"/$f ]]; then
        backup_files+=("${DATA_DIR}"/$f)
    fi
done
cp -a "${backup_files[@]}" "${BACKUP_DIR_PATH}"
tar -cJf "${BACKUP_FILE_PATH}" -C "${BACKUP_ROOT}" "${BACKUP_DIR_NAME}"
rm -rf "${BACKUP_DIR_PATH}"
md5sum "${BACKUP_FILE_PATH}"
sha1sum "${BACKUP_FILE_PATH}"

if [[ -n ${GPG_PASSPHRASE} ]]; then
    # https://gnupg.org/documentation/manuals/gnupg/GPG-Esoteric-Options.html
    # Note: Add `--pinentry-mode loopback` if using GnuPG 2.1.
    printf '%s' "${GPG_PASSPHRASE}" |
    ${GPG} -c --cipher-algo "${GPG_CIPHER_ALGO}" --batch --passphrase-fd 0 "${BACKUP_FILE_PATH}"
    BACKUP_FILE_NAME+=".gpg"
    BACKUP_FILE_PATH+=".gpg"
    md5sum "${BACKUP_FILE_PATH}"
    sha1sum "${BACKUP_FILE_PATH}"
elif [[ -n ${AGE_PASSPHRASE} ]]; then
    export AGE_PASSPHRASE
    ${AGE} -e -j batchpass -o "${BACKUP_FILE_PATH}.age" "${BACKUP_FILE_PATH}"
    BACKUP_FILE_NAME+=".age"
    BACKUP_FILE_PATH+=".age"
    md5sum "${BACKUP_FILE_PATH}"
    sha1sum "${BACKUP_FILE_PATH}"
fi

# Attempt uploading to all remotes, even if some fail.
set +e

success=0
for dest in "${RCLONE_DESTS[@]}"; do
    if ${RCLONE} -vv --no-check-dest copy "${BACKUP_FILE_PATH}" "${dest}"; then
        (( success++ ))
    fi
done

if [[ ${success} == ${#RCLONE_DESTS[@]} ]]; then
    echo "Backup successfully copied to all destinations."
    exit 0
else
    echo "Backup successfully copied to ${success} of ${#RCLONE_DESTS[@]} destinations."
    exit 1
fi
