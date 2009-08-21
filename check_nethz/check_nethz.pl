#!perl

# See  the INSTALL file for installation instructions
#
# Copyright (c) 2009, ETH Zurich.
#
# This module is free software; you can redistribute it and/or modify it
# under the terms of GNU general public license (gpl) version 3.
# See the LICENSE file for details.
#
# RCS information
# enable substitution with:
#   $ svn propset svn:keywords "Id Revision HeadURL Source Date"
#
#   $Id: check_updates 1070 2009-07-22 17:37:54Z corti $
#   $Revision: 1070 $
#   $HeadURL: https://svn.id.ethz.ch/nagios_plugins/check_updates/check_updates $
#   $Date: 2009-07-22 19:37:54 +0200 (Wed, 22 Jul 2009) $

use strict;
use warnings;

use Carp;

use version; our $VERSION = '1.0.0';

use DBI;
use English qw(-no_match_vars);
use Nagios::Plugin::Getopt;
use Nagios::Plugin::Threshold;
use Nagios::Plugin;
use Readonly;

Readonly my $WARNING_UUIDS  => 5000;
Readonly my $CRITICAL_UUIDS => 1000;

# IMPORTANT: Nagios plugins could be executed using embedded perl in this case
#            the main routine would be executed as a subroutine and all the
#            declared subroutines would therefore be inner subroutines
#            This will cause all the global lexical variables not to stay shared
#            in the subroutines!
#
# All variables are therefore declared as package variables...
#
use vars qw(
  $dbh
  $options
  $plugin
  $threshold
  @oks
  @warnings
  @criticals
);

##############################################################################
# Usage     : verbose("some message string", $optional_verbosity_level);
# Purpose   : write a message if the verbosity level is high enough
# Returns   : n/a
# Arguments : message : message string
#             level   : options verbosity level
# Throws    : n/a
# Comments  : n/a
# See also  : n/a
sub verbose {

	# arguments
	my $message = shift;
	my $level   = shift;

	if ( !defined $message ) {
		$plugin->nagios_exit( UNKNOWN,
			q{Internal error: not enough parameters for 'verbose'} );
	}

	if ( !defined $level ) {
		$level = 0;
	}

	if ( $level < $options->verbose ) {
		print $message;
	}

	return;

}

##############################################################################
# Usage     : $dbh = db_connect();
# Purpose   : connect to the nethz DB
# Returns   : database handler
# Arguments : n/a
# Throws    : exits in case of connection errors
# Comments  : n/a
# See also  : n/a
sub db_connect {

	my $dbh = DBI->connect(
		"dbi:Oracle:$options->{dbname}",
		$options->{user},
		$options->{password}
	) or $plugin->nagios_exit( UNKNOWN, 'Cannot connect to DB' );

	# disable auto commit
	$dbh->{AutoCommit} = 0;

	return $dbh;

}


##############################################################################
# Usage     : check_free_uuids
# Purpose   : checks the number of free UUIDs
# Returns   : n/a
# Arguments : n/a
# Throws    : n/a
# Comments  : fills the @criticals, @warnings and @oks lists of messages
# See also  : n/a
sub check_free_uuids {
	
	my $sql = <<'EOT';
SELECT
  max_value - min_value - (
    SELECT
      COUNT(*)
    FROM
      uname u
    WHERE
      u.uuid IS NOT NULL
  ) AS free_uuids
FROM
  nethz_sequences
WHERE
  sequence_name LIKE 'SEQ_UUID'
EOT

	my $sth = $dbh->prepare( $sql );
	
	$sth->execute();
	
	if ($sth->err()) {
		$plugin->nagios_exit( UNKNOWN, 'Query error: ' . $sth->errstr());
	}
	
	 my $res = $sth->fetchrow_hashref;
	 if ($res->{FREE_UUIDS} < $CRITICAL_UUIDS) {
	 	push @criticals, "low number of free UUIDs ($res->{FREE_UUIDS})";
	 } elsif ($res->{FREE_UUIDS} < $WARNING_UUIDS) {
	 	push @warnings, "low number of free UUIDs ($res->{FREE_UUIDS})";
	 } else {
	 	push @oks, "$res->{FREE_UUIDS} free UUIDs";
	 }
	 
	return;	 
	 
}

##############################################################################
# Command line options

$plugin = Nagios::Plugin->new( shortname => 'CHECK_NETHZ' );

$options = Nagios::Plugin::Getopt->new(
	usage   => 'Usage: %s [OPTIONS]',
	version => $VERSION,
	url     => 'https://trac.id.ethz.ch/projects/nagios_plugins',
	blurb   => 'Checks if the nethz DB is in a stable state'
);

$options->arg(
	spec     => 'user|u=s',
	help     => 'DB user',
	required => 1,
);

$options->arg(
	spec     => 'password|p=s',
	help     => 'DB password',
	required => 1,
);

$options->arg(
	spec     => 'dbname|d=s',
	help     => 'DB name',
	required => 1,
);

$options->getopts();

##############################################################################

$dbh = db_connect();

check_free_uuids();

$dbh->disconnect();

##############################################################################

if (@criticals) {
    $plugin->nagios_exit( CRITICAL, join (q{,}, @criticals) );	
} elsif (@warnings) {
    $plugin->nagios_exit( WARNING, join(q{,}, @warnings) );		
}

$plugin->nagios_exit( OK, join ( q{,} , @oks ) );

1;

