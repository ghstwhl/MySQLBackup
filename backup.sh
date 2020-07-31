#!/bin/bash

export LOCKBASE=$(basename $0 .sh)
export LOCKFILE="/tmp/${LOCKBASE}.lock"

# Check for running backup, or stale lockfile
if [ -f "${LOCKFILE}" ] ; then
  export LOCKPROC=$(cat "${LOCKFILE}")
  export ISCURRENT=$(ps h --pid "${LOCKPROC}" | wc -l)

  if [ "${ISCURRENT}" == "1" ] ; then
    echo -n "${0}: backup already in progress; skipping"
    exit
  else
    echo "stale lock (proc: ${LOCKPROC}); overwriting and backing up."
    rm "${LOCKFILE}"
  fi
fi

# lockfile checks complete, run the backup
echo "$$" > "${LOCKFILE}"
mkdir -p /var/local/backups/mysql/
/opt/bin/MySQLBackup.pl /var/local/backups/mysql/
find /var/local/backups/mysql/ -type f -mtime +14 -delete
rm "${LOCKFILE}"
