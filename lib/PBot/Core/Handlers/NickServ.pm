# File: NickServ.pm
#
# Purpose: Handles NickServ-related IRC events.

# SPDX-FileCopyrightText: 2005-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Handlers::NickServ;

use PBot::Imports;
use parent 'PBot::Core::Class';

sub initialize($self, %conf) {
    # NickServ-related IRC events get priority 10
    # priority is from 0 to 100 where 0 is highest and 100 is lowest
    $self->{pbot}->{event_dispatcher}->register_handler('irc.welcome',       sub { $self->on_welcome       (@_) }, 10);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.notice',        sub { $self->on_notice        (@_) }, 10);
    $self->{pbot}->{event_dispatcher}->register_handler('irc.nicknameinuse', sub { $self->on_nicknameinuse (@_) }, 10);
}

sub on_welcome($self, $event_type, $event) {
    # if not using SASL, identify the old way by msging NickServ or some services bot
    if (not $self->{pbot}->{irc_capabilities}->{sasl}) {
        if (length $self->{pbot}->{registry}->get_value('irc', 'identify_password')) {
            my $nickserv = $self->{pbot}->{registry}->get_value('general', 'identify_nick')    // 'NickServ';
            my $command  = $self->{pbot}->{registry}->get_value('general', 'identify_command') // 'identify $nick $password';

            $self->{pbot}->{logger}->log("Identifying with $nickserv . . .\n");

            my $botnick  = $self->{pbot}->{registry}->get_value('irc', 'botnick');
            my $password = $self->{pbot}->{registry}->get_value('irc', 'identify_password');

            $command =~ s/\$nick\b/$botnick/g;
            $command =~ s/\$password\b/$password/g;

            $event->{conn}->privmsg($nickserv, $command);
        } else {
            $self->{pbot}->{logger}->log("No identify password; skipping identification to services.\n");
        }

        # auto-join channels unless general.autojoin_wait_for_nickserv is true
        if (not $self->{pbot}->{registry}->get_value('general', 'autojoin_wait_for_nickserv')) {
            $self->{pbot}->{logger}->log("Autojoining channels immediately; to wait for services set general.autojoin_wait_for_nickserv to 1.\n");
            $self->{pbot}->{channels}->autojoin;
        } else {
            $self->{pbot}->{logger}->log("Waiting for services identify response before autojoining channels.\n");
        }

        return 1;
    }

    # event not handled
    return undef;
}

sub on_notice($self, $event_type, $event) {
    my ($nick, $user, $host, $to, $text)  = (
        $event->nick,
        $event->user,
        $event->host,
        $event->to,
        $event->{args}[0],
    );

    my $nickserv = $self->{pbot}->{registry}->get_value('general', 'identify_nick') // 'NickServ';

    # notice from NickServ
    if (lc $nick eq lc $nickserv) {
        # log notice
        $self->{pbot}->{logger}->log("NOTICE from $nick!$user\@$host to $to: $text\n");

        # if we have enabled NickServ GUARD protection and we're not identified yet,
        # NickServ will warn us to identify -- this is our cue to identify.
        if ($text =~ m/This nickname is registered/) {
            if (length $self->{pbot}->{registry}->get_value('irc', 'identify_password')) {
                $self->{pbot}->{logger}->log("Identifying with NickServ . . .\n");
                $event->{conn}->privmsg("nickserv", "identify " . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));
            }
        }
        elsif ($text =~ m/You are now identified/) {
            # we have identified with NickServ
            if ($self->{pbot}->{registry}->get_value('irc', 'randomize_nick')) {
                # if irc.randomize_nicks was enabled, we go ahead and attempt to
                # change to our real botnick. we don't auto-join channels just yet in case
                # the nick change fails.
                $event->{conn}->nick($self->{pbot}->{registry}->get_value('irc', 'botnick'));
            } else {
                # otherwise go ahead and autojoin channels now
                $self->{pbot}->{channels}->autojoin;
            }
        }
        elsif ($text =~ m/has been ghosted/) {
            # we have ghosted someone using our botnick, let's attempt to regain it now
            $event->{conn}->nick($self->{pbot}->{registry}->get_value('irc', 'botnick'));
        }

        return 1;
    }

    # event not handled
    return undef;
}

sub on_nicknameinuse($self, $event_type, $event) {
    my (undef, $nick, $msg) = $event->args;
    my $from = $event->from;

    $self->{pbot}->{logger}->log("Received nicknameinuse for nick $nick from $from: $msg\n");

    # attempt to use NickServ GHOST command to kick nick off
    $event->{conn}->privmsg("nickserv", "ghost $nick " . $self->{pbot}->{registry}->get_value('irc', 'identify_password'));

    return 1;
}

1;
