#!/usr/bin/perl -w

use Class::Struct;

struct GC_Time => [
        start => '$',
        end => '$'
];

# script is not 100% accurate and only works if events are happening in milliseconds

$gc_map_inst_1 = &create_gc_map(1, ".");
$gc_map_inst_2 = &create_gc_map(2, ".");

print "Did GC interfer at time 14:53:13.012-845: ".affected_by_gc("14:53:13:012", "14:53:13:845", $gc_map_inst_1)."\n";
print "Did GC interfer at time 14:53:14.000-900: ".affected_by_gc("14:53:14:000", "14:53:14:900", $gc_map_inst_1)."\n";

print "Did GC interfer at time 13:39:47.400-500: ".affected_by_gc("13:39:47:400", "13:39:47:500", $gc_map_inst_2)."\n";
print "Did GC interfer at time 13:39:47.700-925: ".affected_by_gc("13:39:47:700", "13:40:47:925", $gc_map_inst_2)."\n";


sub create_gc_map {
	my ($instance, $path) = @_;

	my $full_path = $path."/gc_instance_".$instance.".data*";
	my @logs = `ls -rt $full_path`;
	foreach $log (@logs) {
		@grep = `grep "\\[GC \\[" $log`;

		foreach $line (@grep) {
			if($line =~ m/T(\d\d):(\d\d):(\d\d).(\d\d\d).*?real=(.*?) secs/) {
				my $mills = &time_to_mills($1, $2, $3, $4);
				$gc_map{$1.":".$2.":".$3} = GC_Time->new(start => $mills, end => ($mills+$5*1000));
			}
		}
	}

	return \%gc_map;
}

sub time_to_mills {
        ($hour, $min, $sec, $mill) = @_;
        return ($hour*60*60*1000)+($min*60*1000)+($sec*1000)+$mill;
}

sub timestamp_to_mills {
        ($timestamp) = @_;
        if($timestamp =~ m/(\d\d):(\d\d):(\d\d):(.*)/) {
                return time_to_mills($1, $2, $3, $4);
        }
        return 0;
}

sub affected_by_gc {
	($start, $end, $gc_map) = @_;
	my $found;

	if($start =~ m/(\d\d:\d\d:\d\d)/) {
		if(exists($gc_map->{$1})) {
			$found = $gc_map->{$1};
		} elsif($end =~ m/(\d\d:\d\d:\d\d)/) {
			if(exists($gc_map->{$1})) {
				$found = $gc_map->{$1};
			}
		}
	}
	if(defined($found)) {
		#print &timestamp_to_mills($start)." <= ".$found->end." && ".&timestamp_to_mills($end)." >= ".$found->start."\n";
		if(&timestamp_to_mills($start) <= $found->end && &timestamp_to_mills($end) >= $found->start) {
			return 1;
		}
	}
	return 0;
}


