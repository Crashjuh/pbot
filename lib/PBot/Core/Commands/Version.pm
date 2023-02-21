# File: Version.pm
#
# Purpose: The `version` PBot command. It can check against GitHub or a
# user-defined URL for PBot's VERSION.pm file.

# SPDX-FileCopyrightText: 2001-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Commands::Version;
use parent 'PBot::Core::Class';

use PBot::Imports;

use LWP::UserAgent;

sub initialize {
    my ($self, %conf) = @_;

    # register `version` command
    $self->{pbot}->{commands}->register(sub { $self->cmd_version(@_) }, 'version');

    # initialize last_check version data using compile-time constants
    $self->{last_check} = {
        timestamp => 0,
        revision  => PBot::VERSION::BUILD_REVISION,
        date      => PBot::VERSION::BUILD_DATE,
    };
}

sub cmd_version {
    my ($self, $context) = @_;

    my $ratelimit = $self->{pbot}->{registry}->get_value('version', 'check_limit') // 300;

    if (time - $self->{last_check}->{timestamp} >= $ratelimit) {
        $self->{last_check}->{timestamp} = time;

        my $url = $self->{pbot}->{registry}->get_value('version', 'check_url') // 'https://raw.githubusercontent.com/pragma-/pbot/master/lib/PBot/VERSION.pm';

        $self->{pbot}->{logger}->log("Checking $url for new version...\n");

        my $ua       = LWP::UserAgent->new(timeout => 10);
        my $response = $ua->get($url);

        if (not $response->is_success) {
            return "Unable to get version information: " . $response->status_line;
        }

        my $text = $response->decoded_content;
        my ($revision, $date) = $text =~ m/^\s+BUILD_REVISION => (\d+).*^\s+BUILD_DATE\s+=> "([^"]+)"/ms;

        if (not defined $revision or not defined $date) {
            return "Unable to get version information: data did not match expected format";
        }

        $self->{last_check} = { timestamp => time, revision => $revision, date => $date };
    }

    my $target_nick;
    if (length $context->{arguments}) {
        $target_nick = $self->{pbot}->{nicklist}->is_present_similar($context->{from}, $context->{arguments});
    }

    my $result = '/say ';
    $result .= "$target_nick: " if $target_nick;
    $result .= $self->{pbot}->{version}->version;

    if ($self->{last_check}->{revision} > $self->{pbot}->{version}->revision) {
        $result .= "; new version available: $self->{last_check}->{revision} $self->{last_check}->{date}!";
    }

    return $result;
}

1;
