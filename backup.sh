#!/bin/bash

set -ex

# Use the value of the corresponding environment variable, or the
# default if none exists.
: ${VAULTWARDEN_ROOT:="$(realpath "${0%/*}"/..)"}
: ${SQLITE3:="/usr/bin/sqlite3"}
: ${RCLONE:="/usr/local/bin/rclone"}

DATA_DIR="data"
BACKUP_ROOT="${VAULTWARDEN_ROOT}/backup"
BACKUP_DIR_NAME="vaultwarden-$(date '+%Y%m%d-%H%M')"
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
# backup step; instead, it simply stops the backup and returns an error. This is unlikely,
# but to minimize the possibility of a failed backup, implement a retry mechanism here.
max_tries=10
tries=0
until ${SQLITE3} "file:${DATA_DIR}/${DB_FILE}?mode=ro" ".backup '${BACKUP_DIR_PATH}/${DB_FILE}'"; do
    if (( ++tries >= max_tries )); then
	echo "Aborting after ${max_tries} failed backup attempts..."
	exit 1
    fi
    echo "Backup failed. Retry #${tries}..."
    rm -f "${BACKUP_DIR_PATH}/${DB_FILE}"
    sleep 1
done

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
    gpg -c --cipher-algo "${GPG_CIPHER_ALGO}" --batch --passphrase-fd 0 "${BACKUP_FILE_PATH}"
    BACKUP_FILE_NAME+=".gpg"
    BACKUP_FILE_PATH+=".gpg"
    md5sum "${BACKUP_FILE_PATH}"
    sha1sum "${BACKUP_FILE_PATH}"
fi

# Attempt uploading to all remotes, even if some fail.
set +e

for dest in "${RCLONE_DESTS[@]}"; do
    ${RCLONE} -vv --no-check-dest copy "${BACKUP_FILE_PATH}" "${dest}"
done
