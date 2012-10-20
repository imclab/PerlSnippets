#!/usr/bin/perl -w

use Class::Struct;

if(scalar(@ARGV) != 2) {
	print "ARGS: file_in file_out\n";
	exit 0;
}

my $file_in = $ARGV[0];
my $file_out = $ARGV[1];
my %attributes = ();

open(SOURCE, "< $file_in") or die "Couldn't open for reading: $!\n";
while(<SOURCE>) {
	if($_ =~ m/<(.*?)\>/i) {
		# remove any newline from end
		chomp($_);
		$attributes{$1} = $_;
	}
}
close(SOURCE);

#open(SOURCE, "> $file_out") or die "Couldn't open for writing: $!\n";
for my $attribute (sort keys %attributes) {
	#print SOURCE $attributes{$attribute}."\n";
	print $attributes{$attribute}."\n";
}
#close(SOURCE);