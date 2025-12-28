#!/bin/bash
#
# Convenience script for decrypting an age-encrypted archive,
# e.g. for testing a backup file.
#
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <AGE-FILE> <OUT-FILE>"
    exit 0
fi

source backup.conf

if [[ -z ${AGE_PASSPHRASE} ]]; then
    echo "ERROR: Environment variable 'AGE_PASSPHRASE' must be set."
    exit 1
fi

export AGE_PASSPHRASE

AGE_FILE="$1"
OUT_FILE="$2"

age -d -j batchpass -o "${OUT_FILE}" "${AGE_FILE}"
