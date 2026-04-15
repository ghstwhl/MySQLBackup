#!/usr/bin/env python3

##############################################################################
# MySQLBackup.py  version 1.0                                                #
#                                                                            #
# Python port of MySQLBackup.pl                                              #
#                                                                            #
# Usage:                                                                     #
#   python MySQLBackup.py DESTDIR                                            #
#   python3 MySQLBackup.py DESTDIR                                           #
#                                                                            #
# Requires no external Python packages.  Uses the mysql and mysqldump       #
# command-line clients, which must already be installed on the system.      #
#                                                                            #
# Your MySQL credentials must be stored in ~/my.cnf or ~/.my.cnf with a    #
# [mysqldump] section (user + password) or a [client] section (user + password).#
# http://dev.mysql.com/doc/refman/5.0/en/option-files.html                  #
##############################################################################

import sys
import os
import subprocess
import shutil
import configparser
from datetime import datetime
from pathlib import Path


def find_utility(name):
    path = shutil.which(name)
    if not path:
        sys.exit("Unable to find {} in the current PATH.".format(name))
    if not os.path.isfile(path):
        sys.exit("{} is not valid.".format(path))
    return path


def parse_my_cnf():
    """Parse ~/my.cnf or ~/.my.cnf, returning a dict keyed by section name."""
    home = Path.home()
    cnf_path = None
    for candidate in [home / 'my.cnf', home / '.my.cnf']:
        if candidate.is_file():
            cnf_path = candidate
            break

    if cnf_path is None:
        return {}

    config = configparser.RawConfigParser(allow_no_value=True)
    try:
        config.read(str(cnf_path))
    except configparser.Error as exc:
        sys.exit("Unable to parse {}: {}".format(cnf_path, exc))

    result = {'filename': str(cnf_path)}
    for section in config.sections():
        result[section] = dict(config.items(section))
    return result


def main():
    # Augment PATH with common utility locations (mirrors Perl script)
    extra_paths = [
        '/sbin', '/bin', '/usr/sbin', '/usr/bin', '/usr/games',
        '/usr/local/sbin', '/usr/local/bin',
        '/opt/bin', '/opt/sbin', '/opt/local/bin', '/opt/local/sbin',
        os.path.expanduser('~/bin'),
    ]
    os.environ['PATH'] = os.environ.get('PATH', '') + ':' + ':'.join(extra_paths)

    gzip_path      = find_utility('gzip')
    mysqldump_path = find_utility('mysqldump')
    mysql_path     = find_utility('mysql')

    if len(sys.argv) < 2:
        sys.exit("USAGE: MySQLBackup.py DESTDIR")

    backup_dir = sys.argv[1].rstrip('/')
    if not os.path.isdir(backup_dir):
        sys.exit("{} is not a directory.".format(backup_dir))
    if not os.access(backup_dir, os.W_OK):
        sys.exit("{} is not writable.".format(backup_dir))

    mysql_info = parse_my_cnf()
    if not mysql_info.get('filename'):
        sys.exit(
            "Unable to locate my.cnf file.\n"
            "For information on how to create a my.cnf file visit:\n"
            "http://dev.mysql.com/doc/refman/5.0/en/option-files.html\n"
        )

    timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M')

    list_result = subprocess.run(
        [mysql_path, '--defaults-extra-file={}'.format(mysql_info['filename']),
         '-N', '-e', 'SHOW DATABASES'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if list_result.returncode != 0:
        sys.exit("Failed to list databases: {}".format(list_result.stderr.decode().strip()))
    databases = [db for db in list_result.stdout.decode().splitlines() if db]

    for db_name in databases:
        if db_name == 'information_schema':
            continue

        print("Backing Up {}".format(db_name))
        backup_file = os.path.join(backup_dir, "{}-{}.sql.gz".format(db_name, timestamp))

        dump_cmd = [
            mysqldump_path,
            '--defaults-extra-file={}'.format(mysql_info['filename']),
            '--hex-blob',
            '--opt',
            '--lock-tables',
            db_name,
        ]

        with open(backup_file, 'wb') as out_fh:
            dump_proc = subprocess.Popen(dump_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            gzip_proc = subprocess.Popen([gzip_path, '-c'], stdin=dump_proc.stdout, stdout=out_fh)
            # Close our copy of dump's stdout so gzip receives EOF when dump exits
            dump_proc.stdout.close()
            gzip_proc.wait()
            dump_stderr = dump_proc.stderr.read()
            dump_proc.wait()

        if dump_proc.returncode != 0:
            print(
                "Warning: mysqldump failed for {}: {}".format(db_name, dump_stderr.decode().strip()),
                file=sys.stderr,
            )


if __name__ == '__main__':
    main()
