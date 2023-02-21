# File: Weather.pm
#
# Purpose: Weather command. See Wttr.pm for a more featureful command.

# SPDX-FileCopyrightText: 2007-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::Weather;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use PBot::Core::Utils::LWPUserAgentCached;
use XML::LibXML;

sub initialize {
    my ($self, %conf) = @_;

    $self->{pbot}->{commands}->add(
        name   => 'weather',
        help   => 'Provides weather service via AccuWeather',
        subref => sub { $self->cmd_weather(@_) },
    );
}

sub unload {
    my $self = shift;
    $self->{pbot}->{commands}->remove('weather');
}

sub cmd_weather {
    my ($self, $context) = @_;

    my $usage = "Usage: weather (<location> | -u <user account>)";

    my $arguments = $context->{arguments};

    my %opts;

    my ($opt_args, $opt_error) = $self->{pbot}->{interpreter}->getopt(
        $arguments,
        \%opts,
        ['bundling'],
        'u=s',
        'h',
    );

    return $usage                      if $opts{h};
    return "/say $opt_error -- $usage" if defined $opt_error;

    $arguments = "@$opt_args";

    my $user_override = $opts{u};

    if (defined $user_override) {
        my $userdata = $self->{pbot}->{users}->{storage}->get_data($user_override);
        return "No such user account $user_override." if not defined $userdata;
        return "User account does not have `location` set." if not exists $userdata->{location};
        $arguments = $userdata->{location};
    } else {
        if (not length $arguments) {
            $arguments = $self->{pbot}->{users}->get_user_metadata($context->{from}, $context->{hostmask}, 'location') // '';
        }
    }

    if (not length $arguments) { return $usage; }
    return $self->get_weather($arguments);
}

sub get_weather {
    my ($self, $location) = @_;

    my %cache_opt = (
        'namespace'          => 'accuweather',
        'default_expires_in' => 3600
    );

    my $ua       = PBot::Core::Utils::LWPUserAgentCached->new(\%cache_opt, timeout => 10);
    my $response = $ua->get("http://rss.accuweather.com/rss/liveweather_rss.asp?metric=0&locCode=$location");

    my $xml;

    if ($response->is_success) { $xml = $response->decoded_content; }
    else                       { return "Failed to fetch weather data: " . $response->status_line; }

    my $dom = XML::LibXML->load_xml(string => $xml);

    my $result = '';

    foreach my $channel ($dom->findnodes('//channel')) {
        my $title       = $channel->findvalue('./title');
        my $description = $channel->findvalue('./description');

        if ($description eq 'Invalid Location') {
            return
              "Location $location not found. Use \"<city>, <country abbrev>\" (e.g. \"paris, fr\") or a US Zip Code or \"<city>, <state abbrev>, US\" (e.g., \"austin, tx, us\").";
        }

        $title =~ s/ - AccuW.*$//;
        $result .= "Weather for $title: ";
    }

    foreach my $item ($dom->findnodes('//item')) {
        my $title       = $item->findvalue('./title');
        my $description = $item->findvalue('./description');

        if ($title =~ m/^Currently:/) {
            $title = $self->fix_temps($title);
            $result .= "$title; ";
        }

        if ($title =~ m/Forecast$/) {
            $description =~ s/ <img.*$//;
            $description = $self->fix_temps($description);
            $result .= "Forecast: $description";
            last;
        }
    }
    return $result;
}

sub fix_temps {
    my ($self, $text) = @_;
    $text =~ s|(-?\d+)\s*F|my $f = $1; my $c = ($f - 32 ) * 5 / 9; $c = sprintf("%.1d", $c); "${c}C/${f}F"|eg;
    return $text;
}

1;
