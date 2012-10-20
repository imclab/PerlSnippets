#!/usr/bin/perl -w

use Class::Struct;
use Net::Domain qw (hostname hostfqdn hostdomain);

struct Check => [
	text => '$',
	count => '$',
	sign => '$'
];

################################################################################
# USER DEFINED VARIABLES
################################################################################

my $processes = {
	'Processor1' => [1,2,3,4,5,6,7,8],
	'Processor2' => [1],
	'Processor3', => [1,2],
};

my $checks = {
	'Processor1' => [
		Check->new(text => 'port open', count => '20', sign => '>='),
		Check->new(text => 'Success! Connected to', count => '2', sign => '=='),
		Check->new(text => 'Exception', count => '0', sign => '==')
		],
	'Processor2' => [
		Check->new(text => 'port open', count => '21', sign => '>='),
		Check->new(text => 'starting service', count => '1', sign => '=='),
		Check->new(text => 'registering service', count => '1', sign => '=='),
		Check->new(text => 'starting service on port', count => '1', sign => '=='),
		Check->new(text => 'ERROR', count => '0', sign => '==')
		],
	'Processor3' => [
		Check->new(text => 'starting service on port', count => '1', sign => '=='),
		Check->new(text => 'Exception', count => '0', sign => '==')
		]
};



################################################################################
# SCRIPT
################################################################################

my $host = hostfqdn();
my $environment;
my $emails;

if ($host =~ m/ny6dlqf0(\d*?)v\.dev\.sti/) {
	$environment = "Development";
	$emails = ['dev@benblack86.com'];
} elsif ($host =~ m/ny6qlqf0(\d*?)\.dev\.sti/) {
	$environment = "Qa";
	$emails = ['qa@benblack86.com'];
} elsif ($host =~ m/ny4plqf0(\d*?)\.prod\.lava/) {
	$environment = "Production";
	$emails = ['prod@benblack86.com'];
} else {
	print "unknown environment\n";
	exit 1;
}


my $results = {};
my $errors = 0;
my @email_text = [];

# collect data
while( my($process, $instances) = each %$processes) {
	if (!exists($results->{$process})) {
		$results->{$process} = {};
	}

	foreach $instance (@$instances) {
		if (!exists($results->{$process}->{$instance})) {
			$results->{$process}->{$instance} = [];
		}

		foreach $check (@{$checks->{$process}}) {
			my @grabs = grab($process, $instance, $check->text);
			print "found: ".(@grabs)."\n";
			push(@{$results->{$process}->{$instance}}, \@grabs);
		}
	}
}

# check and print data
while( my($process, $instances) = each %$processes) {
	ep("################################################################################\n");
	ep("# $process\n");
	ep("################################################################################\n");

	foreach $instance (@$instances) {
		ep("Instance $instance\n");
		my $i = 0;
		foreach $check (@{$checks->{$process}}) {

			my $grabs = @{$results->{$process}->{$instance}}[$i];
			my $grabs_count = @$grabs;
			my $error = 0;
			if($check->sign eq '==') {
				if($check->count != $grabs_count) {
					$error = 1;
				}
			} elsif ($check->sign eq '>=') {
				if($grabs_count < $check->count) {
					$error = 1;
				}
			} elsif ($check->sign eq '<=') {
				if($grabs_count > $check->count) {
					$error = 1;
				}
			}

			if ($error) {
				ep("- ERROR [");
			} else {
				ep("- OK [");
			}

			ep($check->text." ".$check->sign." ".$grabs_count);

			if ($error) {
				ep(" <-- should be ".$check->count);
			}

			ep("]\n");

			# print out the first 10 errors as examples
			if ($error) {
				my $break_count = 0;
				foreach $grab (@$grabs) {
					ep("\t$grab");

					$break_count++;

					if ($break_count > 10) {
						ep("\t... please see logs for more\n");
						last;
					}
				}
			}


			$errors = $errors+$error;
			$i = $i+1;
		}
		ep("\n");
	}
}

my $title = "Morning Checkout | Env: ".$environment." | Status: ".($errors ? "ERROR" : "OK");

send_email($title, \@email_text, $emails);





sub ep {
	my ($line) = @_;
	push(@email_text, $line);
}

sub send_email {
	($subject, $content, $tos) = @_;

	my $sendmail = "/usr/sbin/sendmail -t";

	open(SENDMAIL, "|$sendmail") or die "Cannot open $sendmail: $!";
	print SENDMAIL "Reply-to: me\@benblack86.com\n";
	print SENDMAIL "Subject: ".$subject."\n";
	foreach $to (@{$tos}) {
		print "sending to ".$to."\n";
                print SENDMAIL "To: ".$to."\n";
        }
	print SENDMAIL "Content-type: text/plain\n\n";
	shift(@{$content});
	foreach(@{$content}) {
		print SENDMAIL $_;
	}
	close(SENDMAIL);
}

sub grab {
	my ($process, $instance, $grep) = @_;

	my @returns = ();
	my $search = "/use/logs/".$process.$instance."_*";

	print "Searching for: ".$search."\n";

	my @logs = `ls -rt $search`;

	foreach $file (@logs) {
		if ($file ne "\n") {
			@grep = `grep "$grep" $file`;
			push(@returns, @grep);
		}
	}

	return @returns;
}