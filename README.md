# MySQLBackup
This script allows you to make date-time stamped backups of individual mysql databases.  Each database backup is a gzip compressed sql script that can be restored/imported via the mysql command line tool.

The tables of each database being backed up are locked, preserving data integrity.  While this does temporarily prevent writes to the tables, the impact is reduced by backing up each database separately.

This script backups all tables accessible to the mysql user that it is configured to use.  That means this script is useful to the sysadmin as well as to regular users who whish to maintain backups of their own mysql databases.

This script requires that your mysql connection information be stored in a my.cnf or .my.cnf file in the home directory of the user used to run this script.   Because it makes an external call to mysqldump, it is inadvisible to hard code the username and password into this script and then call mysqldump with user and pass as command line arguments. Doing that would expose your mysql username and password to anyone logged into the server while the backup was occuring.  

For information on how to create a my.cnf file visit this page: [http://dev.mysql.com/doc/refman/5.0/en/option-files.html](http://dev.mysql.com/doc/refman/5.0/en/option-files.html)

**Usage:**

~~~
mysqlbackup.pl BACKUPDIR
~~~

**Example:**

See `backup.sh` as an example wrapper that can be called from a cron job and checks to make sure there isn't a backup in progress before it runs.

# Version History

***Version .08-beta changes***

* Utilizes [client] section of ~/.my.cnf if present.

***Version .07-beta changes***

* Fixed bad logic in the utility file path code.
* Added a set of common path locations to the search path.
* Removed information_schema from databases backed up.

***Version .06-beta changes***

* Modified sql connect string to no longer specify an initial database.
* Checks to make sure there is a [mysqldump] section in the ~/.my.conf file.

***Version .05-beta changes***

* Initial public release.
* First release without hard coded values for utility locations, usernames, passwords and hosts.
