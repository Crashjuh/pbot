# File: Counter.pm
#
# Purpose: Counts occurrences of phrases or keywords. Can automatically
# respond about specific counters.

# SPDX-FileCopyrightText: 2016-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Counter;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use DBI;
use Time::Duration qw/duration/;
use Time::HiRes qw/gettimeofday/;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { $self->cmd_counteradd(@_) },     'counteradd',     0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_counterdel(@_) },     'counterdel',     0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_counterreset(@_) },   'counterreset',   0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_countershow(@_) },    'countershow',    0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_counterlist(@_) },    'counterlist',    0);
    $self->{pbot}->{commands}->register(sub { $self->cmd_countertrigger(@_) }, 'countertrigger', 1);
    $self->{pbot}->{capabilities}->add('admin', 'can-countertrigger', 1);

    $self->{pbot}->{event_dispatcher}->register_handler('irc.public', sub { $self->on_public(@_) });

    $self->{filename} = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/counters.sqlite3';
    $self->create_database;
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->unregister('counteradd');
    $self->{pbot}->{commands}->unregister('counterdel');
    $self->{pbot}->{commands}->unregister('counterreset');
    $self->{pbot}->{commands}->unregister('countershow');
    $self->{pbot}->{commands}->unregister('counterlist');
    $self->{pbot}->{commands}->unregister('countertrigger');
    $self->{pbot}->{capabilities}->remove('can-countertrigger');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
}

sub create_database {
    my $self = shift;

    eval {
        $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", {RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1, sqlite_unicode => 1})
          or die $DBI::errstr;

        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Counters (
  channel     TEXT,
  name        TEXT,
  description TEXT,
  timestamp   NUMERIC,
  created_on  NUMERIC,
  created_by  TEXT,
  counter     NUMERIC
)
SQL

        $self->{dbh}->do(<<SQL);
CREATE TABLE IF NOT EXISTS Triggers (
  channel     TEXT,
  trigger     TEXT,
  target      TEXT
)
SQL

        $self->{dbh}->disconnect;
    };

    $self->{pbot}->{logger}->log("Counter create database failed: $@") if $@;
}

sub dbi_begin {
    my ($self) = @_;
    eval { $self->{dbh} = DBI->connect("dbi:SQLite:dbname=$self->{filename}", "", "", {RaiseError => 1, PrintError => 0, AutoInactiveDestroy => 1}) or die $DBI::errstr; };

    if ($@) {
        $self->{pbot}->{logger}->log("Error opening Counters database: $@");
        return 0;
    } else {
        return 1;
    }
}

sub dbi_end {
    my ($self) = @_;
    $self->{dbh}->disconnect;
}

sub add_counter {
    my ($self, $owner, $channel, $name, $description) = @_;

    my ($desc, $timestamp) = $self->get_counter($channel, $name);
    if (defined $desc) { return 0; }

    eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Counters (channel, name, description, timestamp, created_on, created_by, counter) VALUES (?, ?, ?, ?, ?, ?, ?)');
        $sth->bind_param(1, lc $channel);
        $sth->bind_param(2, lc $name);
        $sth->bind_param(3, $description);
        $sth->bind_param(4, scalar gettimeofday);
        $sth->bind_param(5, scalar gettimeofday);
        $sth->bind_param(6, $owner);
        $sth->bind_param(7, 0);
        $sth->execute();
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Add counter failed: $@");
        return 0;
    }
    return 1;
}

sub reset_counter {
    my ($self, $channel, $name) = @_;

    my ($description, $timestamp, $counter) = $self->get_counter($channel, $name);
    if (not defined $description) { return (undef, undef); }

    eval {
        my $sth = $self->{dbh}->prepare('UPDATE Counters SET timestamp = ?, counter = ? WHERE channel = ? AND name = ?');
        $sth->bind_param(1, scalar gettimeofday);
        $sth->bind_param(2, ++$counter);
        $sth->bind_param(3, lc $channel);
        $sth->bind_param(4, lc $name);
        $sth->execute();
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Reset counter failed: $@");
        return (undef, undef);
    }
    return ($description, $timestamp);
}

sub delete_counter {
    my ($self, $channel, $name) = @_;

    my ($description, $timestamp) = $self->get_counter($channel, $name);
    if (not defined $description) { return 0; }

    eval {
        my $sth = $self->{dbh}->prepare('DELETE FROM Counters WHERE channel = ? AND name = ?');
        $sth->bind_param(1, lc $channel);
        $sth->bind_param(2, lc $name);
        $sth->execute();
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Delete counter failed: $@");
        return 0;
    }
    return 1;
}

sub list_counters {
    my ($self, $channel) = @_;

    my $counters = eval {
        my $sth = $self->{dbh}->prepare('SELECT name FROM Counters WHERE channel = ?');
        $sth->bind_param(1, lc $channel);
        $sth->execute();
        return $sth->fetchall_arrayref();
    };

    if ($@) { $self->{pbot}->{logger}->log("List counters failed: $@"); }
    return map { $_->[0] } @$counters;
}

sub get_counter {
    my ($self, $channel, $name) = @_;

    my ($description, $time, $counter, $created_on, $created_by) = eval {
        my $sth = $self->{dbh}->prepare('SELECT description, timestamp, counter, created_on, created_by FROM Counters WHERE channel = ? AND name = ?');
        $sth->bind_param(1, lc $channel);
        $sth->bind_param(2, lc $name);
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        return ($row->{description}, $row->{timestamp}, $row->{counter}, $row->{created_on}, $row->{created_by});
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Get counter failed: $@");
        return undef;
    }
    return ($description, $time, $counter, $created_on, $created_by);
}

sub add_trigger {
    my ($self, $channel, $trigger, $target) = @_;

    my $exists = $self->get_trigger($channel, $trigger);
    if (defined $exists) { return 0; }

    eval {
        my $sth = $self->{dbh}->prepare('INSERT INTO Triggers (channel, trigger, target) VALUES (?, ?, ?)');
        $sth->bind_param(1, lc $channel);
        $sth->bind_param(2, lc $trigger);
        $sth->bind_param(3, lc $target);
        $sth->execute();
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Add trigger failed: $@");
        return 0;
    }
    return 1;
}

sub delete_trigger {
    my ($self, $channel, $trigger) = @_;

    my $target = $self->get_trigger($channel, $trigger);
    if (not defined $target) { return 0; }

    my $sth = $self->{dbh}->prepare('DELETE FROM Triggers WHERE channel = ? AND trigger = ?');
    $sth->bind_param(1, lc $channel);
    $sth->bind_param(2, lc $trigger);
    $sth->execute();
    return 1;
}

sub list_triggers {
    my ($self, $channel) = @_;

    my $triggers = eval {
        my $sth = $self->{dbh}->prepare('SELECT trigger, target FROM Triggers WHERE channel = ?');
        $sth->bind_param(1, lc $channel);
        $sth->execute();
        return $sth->fetchall_arrayref({});
    };

    if ($@) { $self->{pbot}->{logger}->log("List triggers failed: $@"); }
    return @$triggers;
}

sub get_trigger {
    my ($self, $channel, $trigger) = @_;

    my $target = eval {
        my $sth = $self->{dbh}->prepare('SELECT target FROM Triggers WHERE channel = ? AND trigger = ?');
        $sth->bind_param(1, lc $channel);
        $sth->bind_param(2, lc $trigger);
        $sth->execute();
        my $row = $sth->fetchrow_hashref();
        return $row->{target};
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Get trigger failed: $@");
        return undef;
    }
    return $target;
}

sub cmd_counteradd {
    my ($self, $context) = @_;
    return "Internal error." if not $self->dbi_begin;
    my ($channel, $name, $description);

    if ($context->{from} !~ m/^#/) {
        ($channel, $name, $description) = split /\s+/, $context->{arguments}, 3;
        if (not defined $channel or not defined $name or not defined $description or $channel !~ m/^#/) {
            return "Usage from private message: counteradd <channel> <name> <description>";
        }
    } else {
        $channel = $context->{from};
        ($name, $description) = split /\s+/, $context->{arguments}, 2;
        if (not defined $name or not defined $description) { return "Usage: counteradd <name> <description>"; }
    }

    my $result;
    if   ($self->add_counter($context->{hostmask}, $channel, $name, $description)) { $result = "Counter added."; }
    else                                                                             { $result = "Counter '$name' already exists."; }
    $self->dbi_end;
    return $result;
}

sub cmd_counterdel {
    my ($self, $context) = @_;
    return "Internal error." if not $self->dbi_begin;
    my ($channel, $name);

    if ($context->{from} !~ m/^#/) {
        ($channel, $name) = split /\s+/, $context->{arguments}, 2;
        if (not defined $channel or not defined $name or $channel !~ m/^#/) { return "Usage from private message: counterdel <channel> <name>"; }
    } else {
        $channel = $context->{from};
        ($name) = split /\s+/, $context->{arguments}, 1;
        if (not defined $name) { return "Usage: counterdel <name>"; }
    }

    my $result;
    if   ($self->delete_counter($channel, $name)) { $result = "Counter removed."; }
    else                                          { $result = "No such counter."; }
    $self->dbi_end;
    return $result;
}

sub cmd_counterreset {
    my ($self, $context) = @_;
    return "Internal error." if not $self->dbi_begin;
    my ($channel, $name);

    if ($context->{from} !~ m/^#/) {
        ($channel, $name) = split /\s+/, $context->{arguments}, 2;
        if (not defined $channel or not defined $name or $channel !~ m/^#/) { return "Usage from private message: counterreset <channel> <name>"; }
    } else {
        $channel = $context->{from};
        ($name) = split /\s+/, $context->{arguments}, 1;
        if (not defined $name) { return "Usage: counterreset <name>"; }
    }

    my $result;
    my ($description, $timestamp) = $self->reset_counter($channel, $name);
    if (defined $description) {
        my $ago = duration gettimeofday - $timestamp;
        $result = "It had been $ago since $description.";
    } else {
        $result = "No such counter.";
    }

    $self->dbi_end;
    return $result;
}

sub cmd_countershow {
    my ($self, $context) = @_;
    return "Internal error." if not $self->dbi_begin;
    my ($channel, $name);

    if ($context->{from} !~ m/^#/) {
        ($channel, $name) = split /\s+/, $context->{arguments}, 2;
        if (not defined $channel or not defined $name or $channel !~ m/^#/) { return "Usage from private message: countershow <channel> <name>"; }
    } else {
        $channel = $context->{from};
        ($name) = split /\s+/, $context->{arguments}, 1;
        if (not defined $name) { return "Usage: countershow <name>"; }
    }

    my $result;
    my ($description, $timestamp, $counter, $created_on) = $self->get_counter($channel, $name);
    if (defined $description) {
        my $ago = duration gettimeofday - $timestamp;
        $created_on = duration gettimeofday - $created_on;
        $result     = "It has been $ago since $description. It has been reset $counter time" . ($counter == 1 ? '' : 's') . " since its creation $created_on ago.";
    } else {
        $result = "No such counter.";
    }

    $self->dbi_end;
    return $result;
}

sub cmd_counterlist {
    my ($self, $context) = @_;
    return "Internal error." if not $self->dbi_begin;
    my $channel;

    if ($context->{from} !~ m/^#/) {
        if (not length $context->{arguments} or $context->{arguments} !~ m/^#/) { return "Usage from private message: counterlist <channel>"; }
        $channel = $context->{arguments};
    } else {
        $channel = $context->{from};
    }

    my @counters = $self->list_counters($channel);

    my $result;
    if (not @counters) { $result = "No counters available for $channel."; }
    else {
        my $comma = '';
        $result = "Counters for $channel: ";
        foreach my $counter (sort @counters) {
            $result .= "$comma$counter";
            $comma = ', ';
        }
    }

    $self->dbi_end;
    return $result;
}

sub cmd_countertrigger {
    my ($self, $context) = @_;
    return "Internal error." if not $self->dbi_begin;
    my $command;
    ($command, $context->{arguments}) = split / /, $context->{arguments}, 2;

    my ($channel, $result);

    given ($command) {
        when ('list') {
            if ($context->{from} =~ m/^#/) { $channel = $context->{from}; }
            else {
                ($channel) = split / /, $context->{arguments}, 1;
                if ($channel !~ m/^#/) {
                    $self->dbi_end;
                    return "Usage from private message: countertrigger list <channel>";
                }
            }

            my @triggers = $self->list_triggers($channel);

            if (not @triggers) { $result = "No counter triggers set for $channel."; }
            else {
                $result = "Triggers for $channel: ";
                my $comma = '';
                foreach my $trigger (@triggers) {
                    $result .= "$comma$trigger->{trigger} -> $trigger->{target}";
                    $comma = ', ';
                }
            }
        }

        when ('add') {
            if ($context->{from} =~ m/^#/) { $channel = $context->{from}; }
            else {
                ($channel, $context->{arguments}) = split / /, $context->{arguments}, 2;
                if ($channel !~ m/^#/) {
                    $self->dbi_end;
                    return "Usage from private message: countertrigger add <channel> <regex> <target>";
                }
            }

            my ($trigger, $target) = split / /, $context->{arguments}, 2;

            if (not defined $trigger or not defined $target) {
                if   ($context->{from} !~ m/^#/) { $result = "Usage from private message: countertrigger add <channel> <regex> <target>"; }
                else                  { $result = "Usage: countertrigger add <regex> <target>"; }
                $self->dbi_end;
                return $result;
            }

            my $exists = $self->get_trigger($channel, $trigger);

            if (defined $exists) {
                $self->dbi_end;
                return "Trigger already exists.";
            }

            if   ($self->add_trigger($channel, $trigger, $target)) { $result = "Trigger added."; }
            else                                                   { $result = "Failed to add trigger."; }
        }

        when ('delete') {
            if ($context->{from} =~ m/^#/) { $channel = $context->{from}; }
            else {
                ($channel, $context->{arguments}) = split / /, $context->{arguments}, 2;
                if ($channel !~ m/^#/) {
                    $self->dbi_end;
                    return "Usage from private message: countertrigger delete <channel> <regex>";
                }
            }

            my ($trigger) = split / /, $context->{arguments}, 1;

            if (not defined $trigger) {
                if   ($context->{from} !~ m/^#/) { $result = "Usage from private message: countertrigger delete <channel> <regex>"; }
                else                  { $result = "Usage: countertrigger delete <regex>"; }
                $self->dbi_end;
                return $result;
            }

            my $target = $self->get_trigger($channel, $trigger);

            if (not defined $target) { $result = "No such trigger."; }
            else {
                $self->delete_trigger($channel, $trigger);
                $result = "Trigger deleted.";
            }
        }

        default { $result = "Usage: countertrigger <list/add/delete> [arguments]"; }
    }

    $self->dbi_end;
    return $result;
}

sub on_public {
    my ($self, $event_type, $event) = @_;
    my ($nick, $user, $host, $msg) = ($event->nick, $event->user, $event->host, $event->args);
    my $channel = $event->{to}[0];

    return 0 if $event->{interpreted};

    if ($self->{pbot}->{ignorelist}->is_ignored($channel, "$nick!$user\@$host")) {
        return 0;
    }

    if (not $self->dbi_begin) { return 0; }

    my @triggers = $self->list_triggers($channel);

    my $hostmask = "$nick!$user\@$host";

    foreach my $trigger (@triggers) {
        eval {
            my $message;

            if   ($trigger->{trigger} =~ m/^\^/) { $message = "$hostmask $msg"; }
            else                                 { $message = $msg; }

            my $silent = 0;

            if ($trigger->{trigger} =~ s/:silent$//i) { $silent = 1; }

            if ($message =~ m/$trigger->{trigger}/i) {
                my ($desc, $timestamp) = $self->reset_counter($channel, $trigger->{target});

                if (defined $desc) {
                    if (not $silent and gettimeofday - $timestamp >= 60 * 60) {
                        my $ago = duration gettimeofday - $timestamp;
                        $event->{conn}->privmsg($channel, "It had been $ago since $desc.");
                    }
                }
            }
        };

        if ($@) { $self->{pbot}->{logger}->log("Skipping bad trigger $trigger->{trigger}: $@"); }
    }
    $self->dbi_end;
    return 0;
}

1;
