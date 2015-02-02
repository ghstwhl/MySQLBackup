#!/usr/bin/perl

#############################################################################
# mysqlbackup.pl  version .08-beta                                          #
#                                                                           #
# History and information:                                                  #
# http://www.ghostwheel.com/merlin/Personal/notes/mysqlbackup/              #
#                                                                           #
# Synapsis:                                                                 #
#   This script allows you to make date-time stamped backups of individual  #
#   mysql databases.  Each database backup is a gzip compressed sql script  #
#   that can be restored/imported via the mysql command line tool.          #
#                                                                           #
#   The tables of each database being backed up are locked, preserving data #
#   integrity.  While this does temporarily prevent writes to the tables,   #
#   the impact is reduced by backing up each database separately.           #
#                                                                           #
#   This script backups all tables accessible to the mysql user that it is  #
#   configured to use.  That means this script is useful to the sysadmin as #
#   well as to regular users who whish to maintain backups of their own     #
#   mysql databases.                                                        #
#                                                                           #
#   This script requires that your mysql connection information be stored   #
#   in a my.cnf or .my.cnf file in the home directory of the user used to   #
#   run this script.   Because it makes an external call to mysqldump, it   #
#   is inadvisible to hard code the username and password into this script  #
#   and then call mysqldump with user and pass as command line arguments.   #
#   Doing that would expose your mysql username and password to anyone      #
#   logged into the server while the backup was occuring.  For information  #
#   on how to create a my.cnf file visit this page:                         #
#   http://dev.mysql.com/doc/refman/5.0/en/option-files.html                #
#                                                                           #
# Usage:                                                                    #
#   mysqlbackup.pl BACKUPDIR                                                #
#                                                                           #
#                                                                           #
#############################################################################
#                                                                           #
#  History:                                                                 #
#                                                                           #
#  .08-beta  Utilizes [client] section of ~/.my.cnf if present.             #
#                                                                           #
#  .07-beta  Fixed bad logic in the utility file path code.                 #
#            Added a set of common path locations to the search path.       #
#            Removed information_schema from databases backed up.           #
#                                                                           #
#  .06-beta  Modified sql connect string to no longer specify an initial    #
#            database.  Checks to make sure there is a [mysqldump]          #
#            section in the ~/.my.conf file.                                #
#                                                                           #
#  .05-beta  Initial public release.  First release without hard coded      #
#            values for utility locations, usernames, passwords and hosts.  #
#                                                                           #
#                                                                           #
#############################################################################
##
##
## * Copyright (c) 2008,2009, Chris O'Halloran
## * All rights reserved.
## *
## * Redistribution and use in source and binary forms, with or without
## * modification, are permitted provided that the following conditions are met:
## *     * Redistributions of source code must retain the above copyright
## *       notice, this list of conditions and the following disclaimer.
## *     * Redistributions in binary form must reproduce the above copyright
## *       notice, this list of conditions and the following disclaimer in the
## *       documentation and/or other materials provided with the distribution.
## *     * Neither the name of Chris O'Halloran nor the
## *       names of any contributors may be used to endorse or promote products
## *       derived from this software without specific prior written permission.
## *
## * THIS SOFTWARE IS PROVIDED BY Chris O'Halloran ''AS IS'' AND ANY
## * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
## * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
## * DISCLAIMED. IN NO EVENT SHALL Chris O'Halloran BE LIABLE FOR ANY
## * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
## * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
## * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
## * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
## * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
## * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use DBI;
use POSIX qw(strftime);

## Here is an example of how to specify a location for a external utilities used by this script.  
#$UtilLocation{'gzip'} = '/usr/bin/gzip';
#$UtilLocation{'mysqldump'} = '/usr/local/bin/mysqldump';


## Let's make sure there is a good PATH in place when this script runs:
$ENV{'PATH'} .= ':/sbin:/bin:/usr/sbin:/usr/bin:/usr/games:/usr/local/sbin:/usr/local/bin:/opt/bin:/opt/sbin:/opt/local/bin:/opt/local/sbin:~/bin';

## Locate the following utilities for use by the script
@Utils = ('gzip', 'mysqldump');
foreach $Util (@Utils) 
	{

    ##  Populate $UtilLocation{$Util} if it isn't set manually
    if ( !(defined($UtilLocation{$Util})) ) 
		{
		($UtilLocation{$Util} = `which $Util`) =~ s/[\n\r]*//g;
		}      

	## If $UtilLocation{$Util} is still not set, we have to abort.	
	if ( !(defined($UtilLocation{$Util})) || $UtilLocation{$Util} eq "" )
		{
		die("Unable to find $Util in the current PATH.\n");
		}
	elsif ( !(-f $UtilLocation{$Util}) )
		{
		die("$UtilLocation{$Util} is not valid.\n");
		}

	}



$BackupTimeStamp = strftime("%Y-%m-%d_%H-%M", localtime);

if ( defined($ARGV[0]) ) {
	($BackupDir = $ARGV[0]) =~ s/\/$//g;
	if ( !(-d $BackupDir) ) {
		die("$BackupDir is not a directory.\n");
	}
	elsif ( !(-w $BackupDir) ) {
		die("$BackupDir is not not writable.\n");
	}
}
else {
	die("USAGE:  MySQLBackup.pl DESTDIR\n");
}

my %MySQLInfo = &ParseMyCnf;
if ('' eq $MySQLInfo{'filename'} ) {
	die("Unable to locate my.cnf file.\nFor information on how to create a my.cnf file visit this page:\nhttp://dev.mysql.com/doc/refman/5.0/en/option-files.html\n\n");
}

my $DBUser;
my $DBPass;
my $DBHost = 'localhost';
my $DBPort = '3306';

if ('' ne $MySQLInfo{'mysqldump'}{'user'} &&  '' ne $MySQLInfo{'mysqldump'}{'pass'}) {
	$DBUser = $MySQLInfo{'mysqldump'}{'user'};
	$DBPass = $MySQLInfo{'mysqldump'}{'pass'};
	if ('' ne $MySQLInfo{'mysqldump'}{'host'}) {
		$DBHost = $MySQLInfo{'mysqldump'}{'host'};
	}
	if ('' ne $MySQLInfo{'mysqldump'}{'port'}) {
		$DBPort = $MySQLInfo{'mysqldump'}{'port'};
	}
}
elsif ('' ne $MySQLInfo{'client'}{'user'} &&  '' ne $MySQLInfo{'client'}{'password'}) {
	$DBUser = $MySQLInfo{'client'}{'user'};
	$DBPass = $MySQLInfo{'client'}{'password'};
	if ('' ne $MySQLInfo{'client'}{'host'}) {
		$DBHost = $MySQLInfo{'client'}{'host'};
	}
	if ('' ne $MySQLInfo{'client'}{'port'}) {
		$DBPort = $MySQLInfo{'client'}{'port'};
	}
}
else {
	die("Unable to determine login credentials for mysqldump.\nYou must have a [mysqldump] or [client] section with values for user and pass.\nFor information on how to create a my.cnf file visit this page:\nhttp://dev.mysql.com/doc/refman/5.0/en/option-files.html\n\n");
}




my $dbh1 = DBI->connect("DBI:mysql::$DBHost:$DBPort", $DBUser, $DBPass, { AutoCommit => 1 }) || die($DBI::errstr);
   
   
my $ListSearch = $dbh1->prepare("show databases;") || &DBIConnectFailure($DBI::errstr);

$ListSearch->execute;
while ( ($temp1) = $ListSearch->fetchrow_array)
  {
  if ( $temp1 ne "information_schema" )
  	{
	  print "Backing Up $temp1\n";
	  $Backup = "$BackupDir/$temp1-$BackupTimeStamp.sql.gz";
	  system("$UtilLocation{'mysqldump'} --defaults-extra-file=$MySQLInfo{'filename'} --hex-blob --opt --lock-tables $temp1 | $UtilLocation{'gzip'} -c > $Backup");
	 }
  }
$ListSearch->finish;
   
exit;




sub ParseMyCnf {
##  ParseMyCnf
##
##  This is a simple subroutine for parsing the contents of a my.cnf file so that an enlightened MySQL user
##  or administrator doesn't have to hard code their credentials into one of my administrative utils.
##

	
	my %MyConfData;
	my $group;
	my $opt_name;
	my $value;
	my $MyCnfTmp;
	
	my $HomeDir = glob("~");
	foreach $MyCnfTmp ( ("~/my.cnf", "~/.my.cnf" ) ) {
		my $MyCnfTest;
		($MyCnfTest = $MyCnfTmp) =~ s/~/$HomeDir/ex;
		if ( -f $MyCnfTest  && '' eq $MyConfData{'filename'} ) {
			$MyConfData{'filename'} = $MyCnfTest;
		}
	}

	if ( '' ne $MyConfData{'filename'} ) {
		open(MYCNF, $MyConfData{'filename'}) ||  die("Unable to open $MyConfData{'filename'} file\n");
		while (<MYCNF>) {
			my $Line;
			($Line = $_) =~ s/[\n\r]+//g;
		
			if ($Line =~ m/\[([^\]]+)\]/) {
				$group = $1;
			}

			if ($Line =~ m/^(.*)=(.*)$/) {
				$opt_name = $1;
				$value = $2;
				if ( $value =~ m/^['"](.+)['"]$/ ) {
					$value = $1;
				}
				$MyConfData{$group}{$opt_name} = $value;
			}
		}
		close(MYCNF);
	}
	
	return(%MyConfData);
}
