#!/usr/bin/perl -w

use LWP::Simple;

my $url = "http://www.google.com";
my @content = split(/\n/, get($url));

for my $line (@content) {
	print $line;
}