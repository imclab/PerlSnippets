#!/usr/bin/perl -w

use Time::HiRes qw(usleep nanosleep);
use Net::Domain qw (hostname hostfqdn hostdomain);

################################################################################
# USER DEFINED VARIABLES
################################################################################

my $master_file = "/usr/master.data";
my $steps = {
	'update' => ['update[]'],
	'stop' => ['stop[Processor3]', 'stop[Processor1]', 'stop[Processor2]'],
	'clean' => ['clean[Processor3]', 'clean[Processor2]'],
	'start' => ['start[Processor2]', 'input[]', 'start[Processor1]', 'pause[5]', 'start[Processor3]', 'pause[5]'],
	'bounce' => ['stop', 'input[Instances have been stopped, next stage will start]', 'start'],
	'clean-bounce' => ['stop', 'pause[2]', 'clean', 'input[Instances have been stopped and cleaned, next stage will start]', 'start']
};



################################################################################
# SCRIPT
################################################################################

my $config = {};

open CONFIG, "<", $master_file or die "can not open $master_file: $!";
while (<CONFIG>) {
	# if not comment or white space and matches pattern
	if($_ !~ /^\s?#/ && $_ !~ /^\s$/ && $_ =~ /([\w\d]*?)\|([\d]*?)\|([\w\d_\.]*)/) {
		my $process = $1;
		my $instance = $2;
		my $version = $3;

		if(!exists($config->{$process})) {
			$config->{$process} = ();
		}

		@{$config->{$process}}[$instance-1] = $version;
	}
}
close(CONFIG);

# validate user input
my $num_args = $#ARGV+1;
if($num_args < 3) {
	print $num_args." arguments is not valid.\n";
	help();
	exit 1;
}

# validate commands
my @in_commands = split(",", $ARGV[0]);
foreach(@in_commands) {
	if(!exists($steps->{$_})) {
		print "$_ is not a valid command\n";
		help();
		exit 1;
	}
}

# validate processes
my @in_processes = split(",", $ARGV[1]);
foreach(@in_processes) {
	if(!exists($config->{$_})) {
		if($_ eq "all") {
			@in_processes = ('Processor1', 'Processor2', 'Processor3');
		} else {
			print "$_ is not a valid process\n";
			help();
			exit 1;
		}
	}
}
my %process_ok = map { $_ => 1 } @in_processes;

# validate insatnces
my @in_instances = split(",", $ARGV[2]);
foreach(@in_instances) {
	if($_ !~ /\d/ || $_ < 0 || $_ > 8) {
		if($_ eq "all") {
			# this only works if you have the same number of instances of each processor
			@in_instances = (1,2,3,4);
		} else {
			print "$_ is not a valid instance\n";
			help();
			exit 1;
		}
	}
}
my %instance_ok = map { $_ => 1 } @in_instances;

# process any other input
my $dont_ask_for_input = 0;
for($i = 3; $i < $num_args ; $i++) {
	if ($ARGV[$i] =~ m/-i/) {
		$dont_ask_for_input = 1;
	} 
}

# work out which environment the script is running in
my $host = hostfqdn();
my $environment;

if ($host =~ m/devBox(\d*?)v\.dev\.sti/) {
	$environment = "Development";
} elsif ($host =~ m/qaBox(\d*?)\.dev\.sti/) {
	$environment = "Qa";
} elsif ($host =~ m/prodBox(\d*?)\.prod\.lava/) {
	$environment = "Production";
} else {
	print "unknown environment\n";
	exit 1;
}

# run the main code
follow_commands(\@in_commands);

print "\n";
print "Bye\n";


################################################################################
# SUBROUTINES
################################################################################

sub follow_commands {
	my ($commands) = @_;
	# variable is local to each command list
	my $skip_mode = 0;

	if(!defined($commands)) {
		print "error has occurred, exiting program\n";
		exit(0);
	}

	foreach my $i (0 .. (@{$commands}-1)) {
		my $com = @{$commands}[$i];
		#print "looking at $i $com\n";

		if($com =~ /(.*?)\[(.*?)\]/) {
			#print "executing $com\n";
			my $command = $1;
			my $args = $2;

			if($args =~ /TT/) {
				if(exists($process_ok{$args})) {
					$skip_mode = 0; 
					#print "do command $com\n";
					&{$command}($args);
				} else {
					$skip_mode = 1;
					#print "skipping command $com\n";
				}
			} else {
				if(!$skip_mode) {
					# look ahead to see if this pause/input can be skipped
					foreach my $j ($i+1 .. (@$commands-1)) {
						if(@{$commands}[$j] =~ /(.*?)\[(.*?)\]/) {
							my $args2 = $2;
							if($args2 =~ /TT/) {
								if(!exists($process_ok{$args2})) {
									$skip_mode = 1;
									#print "can skip ahead\n";
								}
							}
						}
					}

					if(!$skip_mode) {
						#print "skipping command $com\n";
						&{$command}($args);
					}
				}
			}
		} else {
			#print "follow command $com\n";
			follow_commands($steps->{$com}, $skip_mode);
		}
	}
}

sub help {
	print "\n";
	print " -- SYNTAX --\n";
	print "\tmaster.pl <command,...> <process,...> <instance,...> [command options]\n";
	print "\n";
	print " -- SAMPLES --\n";
	print "\tmaster.pl bounce all 5\n";
	print "\tmaster.pl stop,clean Processor1,Processor2 1,4\n";
	print "\tmaster.pl update all 8 -v 1.4_G3\n";
	print "\n";
	print " -- OPTIONS --\n";
	print "\t Commands: ".join('|', keys %$steps)."\n";
	print "\tProcesses: ".join('|', keys %$config)."|all\n";
	print "\tInstances: 1|2|3|4|all\n";
}


sub stop {
	(my $process) = @_;
	foreach(@in_instances) {
		my $cmd = "/opt/aee/$process/$config->{$process}[$_-1]/bin/stop.sh $_ $environment $config->{$process}[$_-1]";
		print "# Stopping $process Instance $_\n";
		print "\t".$cmd."\n";
		my $output = `$cmd`;
		parse_output($output);		
		sleep(1);
	}
}

sub clean {
	(my $process) = @_;
	foreach(@in_instances) {
		my $cmd = "/opt/aee/$process/$config->{$process}[$_-1]/bin/clean.sh $_ $environment $config->{$process}[$_-1]";
		print "# Cleaning $process Instance $_\n";
		print "\t".$cmd."\n";
		my $output = `$cmd`;
		parse_output($output);
		sleep(1);
	}
}

sub start {
	(my $process) = @_;
	foreach(@in_instances) {
		my $cmd = "/opt/aee/$process/$config->{$process}[$_-1]/bin/start.sh $_ $environment $config->{$process}[$_-1]";
		print "# Starting $process Instance $_\n";
		print "\t".$cmd."\n";
		my $output = `$cmd`;
		parse_output($output);
		sleep(1);
	}
}

sub parse_output {
	(my $output) = @_;

	my @lines = split("\n", $output);

	foreach my $line (@lines) {
		my @chars = split(//, $line);
		my $inc = 100;
		my $i = $inc;
		my $last = 0;
		if($i >= @chars) {
			print_line($line, $last, length($line));
		}

		while($i < @chars) {
			my $ok = 0;
			while($i > $last) {
				if($chars[$i] eq ' ') {
					$i++;
					print_line($line, $last, $i);
					$last = $i;
					$ok = 1;
				} else {
					$i--;
				}
			}

			if(!$ok) {
				$i = $i + $inc;
				print_line($line, $last, $i);
				$last = $i;
			}

			if($i+$inc > @chars) {
				my $len = @chars;
				print_line($line, $last, $len);
				last;
			} else {
				$i = $i+$inc;
			}
		}
	}
	print "\n\n";
}

sub print_line {
	my ($line, $start, $end) = @_;
	if($start eq 0) {
		print "\t\t> ";
	} else {
		print "\t\t  ";
	}
	print "".substr($line, $start, $end-$start)."\n";
}

sub pause {
	(my $period) = @_;

	print "# Please wait...\n";

	# turn autoflush on
	local $| = 1;

	while($period > 0) {
		print "\t";
		for(my $count = 0; $count < 10; $count++) {
			print " * ";
			usleep(100000);
		}
		$period--;
		print "\n";
	}
	print "\n";
}

sub input {
	(my $text) = @_;

	if (!$dont_ask_for_input) {
		print "\n\n";
		print "# $text\n";
		print "\tPress enter/space to continue...\n";
		while (<STDIN>) {
			last if ($_ =~ /^\s*$/); # Exit if it was just spaces (or just an enter)
		}
	}
}

sub update {
	my $found_input = 0;
	for($i = 3; $i < $num_args ; $i++) {
		if ($ARGV[$i] =~ m/-v/) {
                	$found_input = 1;
		}
		if ($found_input) {
			$found_input = $ARGV[$i];
		}
	}

	print "# Updating to version ".$found_input."\n";

	open CONFIG, ">", $master_file or die "can not open $master_file: $!";
	print CONFIG "# Process|Instance|Version\n";

	while( my($process, $instances) = each(%$config) ) {
		for my $i (0 .. (@{$instances}-1)) {
			my $line;
			if (exists($process_ok{$process}) && exists($instance_ok{$i+1})) {
				$line = $process."|".($i+1)."|".$found_input."\n";

			} else {
				$line = $process."|".($i+1)."|".@{$instances}[$i]."\n";
			}

			print "\t".$line;
			print CONFIG $line;
		}
		print "\n";
		print CONFIG "\n";
	}

	print "\n";
}