# File: Logger.pm
#
# Purpose: Logs text to file and STDOUT.

# SPDX-FileCopyrightText: 2001-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Logger;

use PBot::Imports;

use Scalar::Util qw/openhandle/;
use File::Basename;
use File::Copy;
use Time::HiRes qw/gettimeofday/;
use POSIX;

sub new($class, %args) {
    my $self = bless {}, $class;
    Carp::croak("Missing pbot reference to " . __FILE__) unless exists $args{pbot};
    $self->{pbot} = delete $args{pbot};
    print "Initializing " . __PACKAGE__ . "\n" unless $self->{pbot}->{overrides}->{'general.daemon'};
    $self->initialize(%args);
    return $self;
}

sub initialize($self, %conf) {
    # ensure logfile path was provided
    $self->{logfile} = $conf{filename} // Carp::croak "Missing logfile parameter in " . __FILE__;


    # record start time for later logfile rename in rotation
    $self->{start} = time;

    # get directories leading to logfile
    my $path = dirname $self->{logfile};

    # create log file path
    if (not -d $path) {
        print "Creating new logfile path: $path\n" unless $self->{pbot}->{overrides}->{'general.daemon'};
        mkdir $path or Carp::croak "Couldn't create logfile path: $!\n";
    }

    # open log file with utf8 encoding
    open LOGFILE, ">> :encoding(UTF-8)", $self->{logfile} or Carp::croak "Couldn't open logfile $self->{logfile}: $!\n";
    LOGFILE->autoflush(1);

    # rename logfile to start-time at exit
    $self->{pbot}->{atexit}->register(sub { $self->rotate_log });
}

sub log($self, $text) {
    # get current time
    my ($sec, $usec) = gettimeofday;
    my $time = strftime "%a %b %e %Y %H:%M:%S", localtime $sec;
    $time .= sprintf ".%03d", $usec / 1000;

    # replace potentially log-corrupting characters (colors, gibberish, etc)
    $text =~ s/(\P{PosixGraph})/my $ch = $1; if ($ch =~ m{[\s]}) { $ch } else { sprintf "\\x%02X", ord $ch }/ge;

    # log to file
    print LOGFILE "$time :: $text" if openhandle * LOGFILE;

    # and print to stdout unless daemonized
    print STDOUT "$time :: $text" unless $self->{pbot}->{overrides}->{'general.daemon'};
}

sub rotate_log($self) {
    # get start time
    my $time = localtime $self->{start};
    $time =~ s/\s+/_/g; # replace spaces with underscores

    $self->log("Rotating log to $self->{logfile}-$time\n");

    # rename log to start time
    move($self->{logfile}, $self->{logfile} . '-' . $time);

    # set new start time for next rotation
    $self->{start} = time;
}

1;
