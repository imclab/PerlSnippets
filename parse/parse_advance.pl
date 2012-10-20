#!/usr/bin/perl -w

use Class::Struct;

if(scalar(@ARGV) != 3) {
	print "ARGS: file_in file_out type_id\n";
	exit 0;
}

my $file_in = $ARGV[0];
my $file_out = $ARGV[1];
my $type_id = $ARGV[2];

my %attributes = ();

my %convert = (
	'String' => 'symbol',
	'Double' => 'float',
	'Timestamp' => 'datetime',
	'Date' => 'datetime',
	'Enum' => 'int',
	'Long' => 'long',
	'Object' => 'symbol',
	'Boolean' => 'boolean',
	'Integer' => 'int',
);


struct Attribute => [
	name => '$',
	type => '$',
	line => '$'
];


open(SOURCE, "< $file_in") or die "Couldn't open for reading: $!\n";
while(<SOURCE>) {
	$_ =~ m/name=\"(.*?)\".*?type=\"(.*?)\"/i;
	# remove any newline from end
	chomp($_);
	my $attr = Attribute->new(name => $1, type => $2, line => $_);

	$attributes{$1} = $attr;
}
close(SOURCE);

print "file_out output\n";
#open(SOURCE, "> $file_out") or die "Couldn't open for writing: $!\n";
for my $attribute (sort keys %attributes) {
	#print SOURCE $attributes{$attribute}->line;
	print $attributes{$attribute}->line."\n";
}
#close(SOURCE);

print "\n\nfile_out_q output\n";
#open(SOURCE, "> $file_out"."_q") or die "Couldn't open for writing: $!\n";
for my $attribute (sort keys %attributes) {
	if(exists($convert{$attributes{$attribute}->type})) {
	        #print SOURCE "\t\t<".$attributes{$attribute}->name.$type_id." attrName=\"".$attributes{$attribute}->name."\" typeQ=\"".$convert{$attributes{$attribute}->type}."\" />\n";
			print "\t\t<".$attributes{$attribute}->name.$type_id." attrName=\"".$attributes{$attribute}->name."\" typeQ=\"".$convert{$attributes{$attribute}->type}."\" />\n";
	} else {
		print $attributes{$attribute}->type." not definned in config\n";
	}
}
#close(SOURCE);
