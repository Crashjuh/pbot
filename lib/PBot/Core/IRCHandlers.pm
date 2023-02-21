# File: IRCHandlers.pm
#
# Purpose: Pipes the PBot::Core::IRC default handler through PBot::Core::EventDispatcher,
# and registers default IRC handlers.

# SPDX-FileCopyrightText: 20001-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::IRCHandlers;
use parent 'PBot::Core::Class';

use PBot::Imports;

use Data::Dumper;

sub initialize {
    # nothing to do here
}

# this default handler prepends 'irc.' to the event-name and then dispatches
# the event to the rest of PBot via PBot::Core::EventDispatcher.

sub default_handler {
    my ($self, $conn, $event) = @_;

    # add conn to event object so we can access it within handlers
    $event->{conn} = $conn;

    my $result = $self->{pbot}->{event_dispatcher}->dispatch_event(
        "irc.$event->{type}",
        $event
    );

    # log event if it was not handled and logging is requested
    if (not defined $result and $self->{pbot}->{registry}->get_value('irc', 'log_default_handler')) {
        $Data::Dumper::Sortkeys = 1;
        $Data::Dumper::Indent   = 2;
        $Data::Dumper::Useqq    = 1;
        delete $event->{conn}; # don't include conn in dump
        $self->{pbot}->{logger}->log(Dumper $event);
    }
}

# registers handlers with a PBot::Core::IRC connection

sub add_handlers {
    my ($self) = @_;

    # set up handlers for the IRC engine
    $self->{pbot}->{conn}->add_default_handler(
        sub { $self->default_handler(@_) }, 1);

    # send these events to on_init()
    $self->{pbot}->{conn}->add_handler([251, 252, 253, 254, 255, 302],
        sub { $self->{pbot}->{handlers}->{modules}->{Server}->on_init(@_) });

    # ignore these events
    $self->{pbot}->{conn}->add_handler(
        [
            'myinfo',
            'whoisserver',
            'whoiscountry',
            'whoischannels',
            'whoisidle',
            'motdstart',
            'endofmotd',
            'away',
        ],
        sub { }
    );
}

# replace randomized gibberish in certain hostmasks with identifying information

sub normalize_hostmask {
    my ($self, $nick, $user, $host) = @_;

    if ($host =~ m{^(gateway|nat)/(.*)/x-[^/]+$}) {
        $host = "$1/$2/x-$user";
    }

    $host =~ s{/session$}{/x-$user};

    return ($nick, $user, $host);
}

1;
