#!/usr/bin/perl -w

# SPDX-FileCopyrightText: 2010-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# Quick and dirty by :pragma

use LWP::UserAgent::WithCache;

my ($text, $t);

my $debug = 0;

my %cache_opt = (
    'namespace'          => 'lwp-cache',
    'cache_root'         => File::Spec->catfile(File::HomeDir->my_home, '.lwpcache'),
    'default_expires_in' => 60 * 60 * 24 * 100
);
my $ua = LWP::UserAgent::WithCache->new(\%cache_opt);

$ua->agent("Mozilla/5.0");

my $response;
my $page  = 1;
my $pages = undef;
my @quotes;

#print "$#ARGV\n";
#print "$#quotes\n";

while (1) {
    my $arguments = "love you";
    my $author    = "";

    $arguments =~ s/\$nick/me/gi;
    $arguments =~ s/\s/+/g;

    if ($arguments =~ m/\-\-author[\s\+]+(.*)/i) {
        $author = $1;
        $arguments =~ s/\-\-author[\s\+]+(.*)//i;
    }

    # print "search: [$arguments]; author: [$author]\n";
    if ((length $arguments < 4) && ($author eq "")) {
        print "Quote search parameter too small.\n";
        die;
    }

    if ((length $author > 0) && (length $author < 3)) {
        print "Quote author parameter too small.\n";
        die;
    }

    $arguments =~ s/\++$//;
    $author    =~ s/\++$//;

    #    print "http://www.quotationspage.com/search.php3?Search=$arguments&startsearch=Search&Author=$author&C=mgm&C=motivate&C=classic&C=coles&C=poorc&C=lindsly&C=net&C=devils&C=contrib&page=$page\n";
    $response = $ua->get(
        "http://www.quotationspage.com/search.php3?Search=$arguments&startsearch=Search&Author=$author&C=mgm&C=motivate&C=classic&C=coles&C=poorc&C=lindsly&C=net&C=contrib&page=$page"
    );

    if (not $response->is_success) {
        print "Couldn't get quote information.\n";
        die;
    }

    $text = $response->content;

    while ($text =~ m/<dt class="quote"><a.*?>(.*?)<\/a>.*?<dd class="author"><div.*?><a.*?>.*?<b>(.*?)<\/b>/g) {
        $t = "\"$1\" -- $2.";
        push @quotes, $t;
        print "Added '$t'\n" if $debug;
        print "$#quotes\n"   if $debug;
    }

    if ($text =~ m/Page \d+ of (\d+)/) {
        $pages = $1;
        $page++;
        last                                         if $page > $pages;
        print "Pages: $pages; fetching page $page\n" if $debug;
    } else {
        last;
    }

    if ($#quotes < 0) {
        print "No results found.\n";
        die;
    }
}

# print "Total quotes: ", $#quotes + 1, "\n";

if ($#quotes < 0) {
    print "No results found.\n";
    die;
}

$t = $quotes[int rand($#quotes + 1)];

if ($#ARGV > -1) { $t = "" . ($#quotes + 1) . " matching quote" . (($#quotes + 1) != 1 ? "s" : "") . " found. $t"; }

my $quote  = chr(226) . chr(128) . chr(156);
my $quote2 = chr(226) . chr(128) . chr(157);
my $dash   = chr(226) . chr(128) . chr(147);

$t =~ s/<[^>]+>//g;
$t =~ s/<\/[^>]+>//g;
$t =~ s/$quote/"/g;
$t =~ s/$quote2/"/g;
$t =~ s/$dash/-/g;
$t =~ s/&quot;/"/g;
$t =~ s/&amp;/&/g;
$t =~ s/&nsb;/ /g;
$t =~ s/&#39;/'/g;
$t =~ s/&lt;/</g;
$t =~ s/&gt;/>/g;
$t =~ s/<em>//g;
$t =~ s/<\/em>//g;
$t =~ m/"(.*?)"/;

print "$1\n";
