package Framework;

# NOTE: not currently in working order

use Switch;
use Cwd qw(cwd);
use POSIX qw(dup2);
use Sys::Hostname;
use Storable;

my @reachable = &get_reachable_instances();

sub run_scripts {
	($scripts, $instances, $date, $path, $capture) = @_;

	my @readables = ();
	my $content = "";

	foreach $script (@{$scripts}) {
		foreach $instance (@{$instances}) {
			my $cmd = $script.' -i '.$instance.' -d '.$date.' -p '.$path;
			print "Splitting off $cmd for instance $instance\n";
			pipe my ($readable, $writable) or die "failed to create a pipe: $!\n";
			if($capture) {
				$cmd .= ' > '.$path.'/../out'.$instance;
			}
			print "RUNNING: ".$cmd."\n";
			fork_child(cwd().'/'.$cmd, $readable, $writable);
			close $writable or die "failed to close pipe: $!\n";

			push(@readables, $readable);
		}
	}

	foreach $readable (@readables) {
		while(<$readable>) {
			$content .= $_;
		}
		close $readable or die "failed to close pipe: $!\n";
	}

	return $content;
}

sub consolidate {
	($date, $inital_delay, $retry_attempts, $name) = @_;

	print "Consolidation accross boxes.\n";
	if($inital_delay > 0) {
		print "Sleep for ".$inital_delay." seconds\n";
		sleep($inital_delay);
	}

	my $line = "0";
	while($line ne $date && $retry_attempts-- > 0) {
		print "Sleep for 60 seconds\n";
		sleep(60);

		&set_scp_env();
		my $loc = $path."/".$name.".one";
	        print "scp boxName:$loc $loc\n";
                `/usr/bin/scp boxName:$loc $loc`;

               	if(-e $loc) {
                    open LOG, "<$loc" or die $!;
	                $line = <LOG>;
                }
               	if(defined($line)) {
	                chomp($line);
                } else {
               	        $line = "0";
	        }

                print $line." =? ".$date."\n";
	}
	print "Otherside is ready\n";
}

sub signal {
	($date, $path, $name) = @_;

	open LOG, ">$path/$name.one" or die $!;
	print LOG $date;
	close LOG;
}

sub send_mail {
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
	print SENDMAIL $content;
	close(SENDMAIL);
}

sub fork_child {
	($run, $readable, $writable) = @_;
	my $pid = fork;
	die "Failed to fork: $!\n" if !defined $pid;

	return $pid if $pid != 0;

	# Now we're in the new child process
	if(defined($readable) && defined($writable)) {
		close $readable or die "child failed to close pipe: $!\n";
		dup2(fileno $writable, 1);
		close $writable or die "child failed to close pipe: $!\n";

		exec $run or die "failed to execute: $!\n";
		} else {
			system $run or die "failed to execute: $!\n";
		}

		exit;
	}


sub run_script {
	($data_logic, $biz_logic, $print_logic, $biz_name, $params) = @_;
	my $path = ((defined($params->{'p'})) ? $params->{'p'} : "cache");
	my @dates = split(/,/, $params->{'d'});
	my $instances = $params->{'i'};
	my $dont_run = defined($params->{'n'});
	my $dont_save = defined($params->{'s'});
	my $refresh = defined($params->{'r'});
	my @reachable = &get_reachable_instances();
	my $totals = {};

	# parse instances
	$instances =~ s/\s//;
	my @instances = split(/,/, $instances);

	foreach $date (@dates) {
		my %inst_data = ();

		foreach $i (@instances) {
			my %return = &load($path, $date, $i, $biz_name);
	                $inst_data{$i} = \%return;

	                # if data is already collected then don't try to collect
        	        if(keys(%{$inst_data{$i}}) > 0) {
	                        next;
        	        }

			# collect raw data as requested
			my $data = {};
			$data->{'instance'} = $i;
			$data->{'date'} = $date;
			while(($data_name, $data_ref) = each(%$data_logic)) {
				print $data_name." ".ref($data_ref)."\n";
				if(ref($data_ref) eq 'CODE') {
					$data->{$data_name} = $data_ref->($date, $i, $path, $dont_run);
				} else {
					$data->{$data_name} = $data_ref;
				}
			}

            # save returned data in hash and on disk
	        $inst_data{$i} = $biz_logic->($data);
			if(!$dont_save) {
	        	&save($path, $date, $i, $inst_data{$i}, $biz_name);
			}
        	}


	        while(($i, $data) = each(%inst_data)) {
			#print "Merging in inst ".$i."\n";
			&merge_hash($totals, $data);
	        }
	}

        $print_logic->($totals);
}

sub merge_hash {
	my ($merged, $data) = @_;
	if(ref($data) ne 'HASH') {
		print "can't merge non hash reference";
		exit;
	}

	while(($name, $item) = each(%$data)) {
		if(ref($item) eq 'ARRAY') {
			#print "MH: array ".$name."\n";
			if(!exists($merged->{$name})) {
				#print "MH: creating array\n";
				$merged->{$name} = [];
			}
			push(@{$merged->{$name}}, @$item);
		}
		elsif(ref($item) eq 'SCALAR') {
			#print "MH: scalar ".$name."\n";
			if(!exists($merged->{$name})) {
				#print "MH: creating scalar\n";
				${$merged->{$name}} = 0;
			}
			${$merged->{$name}} += $$item;
		}
		elsif(ref($item) eq 'HASH') {
			#print "MH: hash ".$name."\n";
			if(!exists($merged->{$name})) {
				#print "MH: creating hash\n";
				$merged->{$name} = {};
			}
			&merge_hash($merged->{$name}, $item);
		}
	}
}

sub get_params {
	my ($required, @other) = @_;
	my @inputs = split(/-/, join("", @other));
	my %params = ();
	my $date = `date +%m%d%y`;
	chop($date);
	$params{'d'} = $date;
	foreach $input (@inputs) {
        	if($input =~ m/(.)(.*)/) {
			$params{$1} = $2;
		}
	}

	if(exists($params{'v'})) {
		while(my ($param, $value) = each(%params)) {
			print $param."=".$value."\n";	
		}
	}

	while($required =~ /(.)/g) {
		if(!exists($params{$1})) {
        		print "Missing ".$1."\n";
		        exit 1;
		}
	}

	our $debug = exists($params{'v'});

	return %params;
}

sub get_logs {
	my ($date, @instances) = @_;
	my @logs = ();
	foreach $instance (@instances) {
		my $log_path = "/var/opt/".$instance."/process/logs";
		my $lsSearch = "$log_path\/*".$date."*";
		my @temp_logs = `ls -rt $lsSearch`;
		push(@logs, @temp_logs);
	}

	return @logs;
}

sub get_reachable_instances {
	my @instances = ();
	my $host_number = substr(hostname(), 7, 1);
	if($host_number > 0 && $host_number < 4) {
		push(@instances, (1, 2, 3));
	} else {
		push(@instances, (4, 5, 6));
	}
	return @instances;
}

sub is_reachable {
	($instance) = @_;

	foreach $reach (@reachable) {
		if($reach == $instance) {
			return 1;
		}
	}
	return 0;
}

sub grab {
	($files, $grep) = @_;
	my @returns = ();
	my @log_files = @{$files};

	if($debug) {
		print "Searching for: ".$grep."\n";
	}

	foreach $file (@log_files) {
		if ($file ne "\n") {
			if($debug) {
				print "Parse logfile ".$file;
			}
			@grep = `grep "$grep" $file`;

			push(@returns, @grep);
		}
	}
	return @returns;
}


sub print_title {
	($title) = @_;
	print ''.('#'x(94))."\n";
	print "#### ".$title.(' 'x(84-length($title)))." ####\n";
	print ''.('#'x(94))."\n";
	print "\n";
}

sub print_bar {
	($title) = @_;
	if(defined($title)) {
		print "-- ".$title." ".('-'x(90-length($title)))."\n";
	} else {
		print ''.('-'x(94))."\n";
	}
}

@percentiles = qw(0 10 25 50 75 90 95 99 100);

sub print_percentile_title {
	printf("%-14s", "");
	foreach $x (@percentiles) {
        	printf("%-8s", $x);
	}
	print "VOLUME\n";
}

sub print_percentile {
	my ($name, $numbers) = @_;
	if(scalar @{$numbers} > 0) {
		my @bag = sort{ $a <=> $b } @{$numbers};

		printf("%-14s", $name);

		foreach $x (@percentiles) {
			$val=percentile($x, \@bag );
			chomp($val);
			printf("%-8s", $val);
		}

		print $#bag+1;
		print "\n";
	}
}


#Assumes a sorted array is passed in along with the percentile required from the numbers
sub percentile {
	my ($p, $aref) = @_;
	my $percentile = int($p * $#{$aref}/100);
	#print "POSITION=".$percentile.",PERCENTILE=".$p.",NUM=".$#{$aref}."\n";
	return @$aref[$percentile];
}


sub get_time {
	my $time = 0;
	if($_[0] =~ m/.*?\|(\d*?:\d*?:\d*?:\d*?)\|/) {
		#print $1."\n";
		@timesegs = split( /:/, $1);
		$time = ($timesegs[0]*60*60*1000)+($timesegs[1]*60*1000)+($timesegs[2]*1000)+($timesegs[3]);
	}
	$time;
}

sub get_timestamp {
	($log) = @_;
	if($log =~ m/.*?\|(\d*?:\d*?:\d*?:\d*?)\|/) {
		return $1;
	}
	return 0;
}

sub timestamp_to_mills {
	($timestamp) = @_;
	if($timestamp =~ m/(\d\d):(\d\d):(\d\d):(.*)/) {
		return time_to_mills($1, $2, $3, $4);
	}
	return 0;
}

sub time_to_mills {
	($hour, $min, $sec, $mill) = @_;
	return ($hour*60*60*1000)+($min*60*1000)+($sec*1000)+$mill;
}


sub get_key {
	my ($id1, $id2) = @_;
	if($id1 ge $id2) {
		return $id1."#".$id2;
	} else {
		return $id2."#".$id1;
	}
}


sub parse_order {
	my ($order) = @_;

	my @pairs = split(//, $order);
	my %tags = ();

	foreach $pair (@pairs) {
		if($pair =~ m/(.*?)=(.*)/) {
			$tags{$1} = $2;
		}
	}

	return %tags;
}

sub load {
	my ($path, $date, $instance, $name) = @_;
	my $full_path = $path."/".$date."_".$instance."_".$name;

	if(!(-e $path."/".$date."_".$instance."_".$name)) {
		if(!&is_reachable($instance)) {
			&set_scp_env();
			`scp eqliqap4p:$full_path $full_path`;
		}
	}

	if(-e $path."/".$date."_".$instance."_".$name) {
		return %{retrieve($path."/".$date."_".$instance."_".$name)};
	}

	print "Cache doesn't exist: ".$path."/".$date."_".$instance."_".$name."\n";
	return ();
}

sub save {
	my ($path, $date, $instance, $reference, $name) = @_;
	unless(-d $path) {
		mkdir $path;
	}
	store($reference, $path."/".$date."_".$instance."_".$name);
}

sub set_scp_env {
	$ENV{'SSH2_SFTP_LOG_FACILITY'} = '0';
	$ENV{'LANG'} = 'en_US.UTF-8';
	$ENV{'SHELL'} = '/bin/ksh';
	$ENV{'TERM'} = 'xterm';
}

1