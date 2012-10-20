#!/usr/bin/perl -w

foreach (sort keys %ENV) {
    print "$_ = $ENV{$_}\n";
}