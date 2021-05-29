## Overview

**Note: Vaultwarden was formerly known as bitwarden_rs.**

This repo contains my automated setup for SQLite-based Vaultwarden backups.
It's designed solely to meet my own backup requirements (i.e., not to be
general purpose):

1. Generate a single archive with a complete backup of all Vaultwarden data
   and config on a configurable schedule.

2. Retain backup archives on the local Vaultwarden host for a configurable
   number of days.

3. Upload encrypted copies of the backup archives to one or more object
   storage services using [rclone](https://rclone.org/). The retention policy
   is configured at the storage service level.

Feel free to use or modify this setup to fit your own needs.

Note: This single-archive backup scheme isn't space-efficient if your vault
includes large file attachments, as they will be re-uploaded with each backup.
If this is an issue, you might consider modifying the script to use
[restic](https://restic.net/) instead.

## Prerequisites

1. A standard Unix-like (preferably Linux) host running Vaultwarden. I don't
   know much about Synology or other such environments.

2. A [cron](https://en.wikipedia.org/wiki/Cron) daemon. This is used to run
   backup actions on a scheduled basis.

3. An `sqlite3` binary (https://sqlite.org/cli.html). This is used to back up
   the SQLite database. This can be installed via the `sqlite3` package on
   Debian/Ubuntu or the `sqlite` package on RHEL/CentOS/Fedora.

4. An `rclone` binary (https://rclone.org/). This is used to copy the backup
   archives to cloud storage. This can be installed via the `rclone` package
   on Debian/Ubuntu and RHEL/CentOS/Fedora ([EPEL](https://fedoraproject.org/wiki/EPEL)
   required for RHEL/CentOS), but as rclone changes more rapidly, it's probably
   best to just use the latest binary from https://rclone.org/downloads/.

5. An account at one or more cloud storage services
   [supported](https://rclone.org/overview/) by rclone. If you don't have one
   yet, [Backblaze B2](https://www.backblaze.com/b2/cloud-storage.html)
   offers 10 GB of free object storage.

6. Optionally, a `gpg` (GnuPG 2.x) binary (https://gnupg.org/). This can be
   installed via the `gnupg` package on Debian/Ubuntu or the `gnupg2` package
   on RHEL/CentOS/Fedora.

## Usage

1. Start by cloning this repo to the directory containing your Vaultwarden
   data directory, under the name `backup`. In my setup, it looks like this:

       $HOME/vaultwarden  # Top-level Vaultwarden directory
       ├── backup         # This backup repo
       └── data           # Vaultwarden data directory

2. Copy the `backup.conf.template` file to `backup.conf`.

   1. If you want encrypted backup archives, change the `GPG_PASSPHRASE`
      variable; if you don't, change it to be blank.

      This passphrase is used to encrypt the backup archives, which may
      contain somewhat sensitive data in plaintext in `config.json` (the
      password entries themselves are already encrypted by Bitwarden). It
      should be something easy enough for you to remember, but complex enough
      to deter, for example, any unscrupulous cloud storage personnel who
      might be snooping around. As this passphrase is stored on disk in
      plaintext, it definitely should not be your Bitwarden master passphrase
      or anything similar.

      [rclone crypt](https://rclone.org/crypt/) is another option for encrypted
      archives. If you prefer to use this method, just set `GPG_PASSPHRASE` to
      be blank, configure rclone crypt appropriately, and use the crypt remote
      in `RCLONE_DESTS`.

   2. Change `RCLONE_DESTS` to your list of rclone destinations. You'll have
      to [configure](https://rclone.org/docs/) rclone appropriately first.

   3. Note that `backup.conf` is simply sourced into the `backup.sh` script, so
      you can add arbitrary environment variables into `backup.conf` as needed.
      This can be useful for configuring any tools called from `backup.sh`,
      such as `rclone`.

3. Modify the `backup/crontab` file as needed.

   1. If `$HOME/vaultwarden` isn't your top-level Vaultwarden directory, adjust
      the paths in this file accordingly.

   2. Review the backup schedule. I generate backup archives hourly, but you
      might prefer to do this less frequently to save space.

   3. Review the local retention policy. I delete files older than 14 days
      (`-mtime +14`). Adjust this if needed.

   4. Review the SQLite [VACUUM](https://sqlite.org/lang_vacuum.html) schedule,
      or remove the job if you don't want vacuuming. Vacuuming compacts the
      database file so that operations are faster and backups are smaller.

4. Install the crontab under a user (typically your normal login) that can
   read your Vaultwarden data. For most users, running `crontab -e` and
   pasting in the contents of the crontab file should work.

5. If you use GnuPG 2.1 or later, see the note about `--pinentry-mode loopback`
   in `backup.sh`.

If everything is working properly, you should see the following:

1. Backup archives generated under `backup/archives`.
2. Encrypted backup archives uploaded to your configured rclone destination(s).
3. A log of the last backup at `backup/backup.log`.

For example:
```
$HOME/vaultwarden/backup
├── archives
│   ├── vaultwarden-20210101-0000.tar.xz
│   ├── vaultwarden-20210101-0000.tar.xz.gpg
│   ├── vaultwarden-20210101-0100.tar.xz
│   ├── vaultwarden-20210101-0100.tar.xz.gpg
│   └── ...
├── backup.conf
├── backup.conf.template
├── backup.log
├── backup.sh
├── crontab
├── LICENSE
└── README.md
```
