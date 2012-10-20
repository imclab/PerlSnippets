#!/usr/bin/perl -w

use Class::Struct;

if(scalar(@ARGV) != 3) {
        print "ARGS: grep filename interval\n";
        exit 0;
}


my $grep = $ARGV[0];
my $file = $ARGV[1];
my $interval = $ARGV[2];

struct Clock => [
        hour => '$',
        min => '$'
];

print "Grepping for ".$grep." in ".$file."\n";

my @lines = `grep "$grep" $file`;

# look at first line to determine where the clock should start
$lines[0] =~ m/(\d\d):(\d\d):/;
my $clock = Clock->new(hour => $1, min => 0);
my @labels = (label(\$clock));
my @times = (0);

foreach my $line (@lines) {
        if($line =~ m/(\d\d):(\d\d):(\d\d).(\d\d\d)/) {
                my $hour = $1;
                my $min = $2;
                #print $hour.$min."\n";

                while($hour > $clock->hour || $min > $clock->min+$interval) {
                        inc(\$clock);
                        push(@labels, label(\$clock));
                        push(@times, 0);
                }

                $times[scalar(@times)-1]++;
        }
}

for (my $i = 0; $i <= scalar(@labels)-1; $i++) {
        print $labels[$i]." > ".$times[$i]."\n";
}




sub inc {
        my ($clock) = @_;
        $clock = ${$clock};
        $clock->min($clock->min + $interval);

        if($clock->min == 60) {
                $clock->min(0);
                $clock->hour($clock->hour+1);
        }
}

sub label {
        my ($clock) = @_;
        return sprintf("%02d", ${$clock}->hour)."".sprintf("%02d", ${$clock}->min);

}