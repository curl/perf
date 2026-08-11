#!/usr/bin/perl

use JSON;
use Data::Dumper;

my $logdir = "log";

opendir(my $dh, $logdir) || die "Can't open dir: $!";
my @logs = grep { /^perf.*\.log/ && -f "$logdir/$_" } readdir($dh);
closedir $dh;

sub median {
    my @a = @_;
    my @vals = sort {$a <=> $b} @a;
    my $len = @vals;
    if($len%2) { #odd?
        return $vals[int($len/2)];
    }
    else {
        #even
        return ($vals[int($len/2)-1] + $vals[int($len/2)])/2;
    }
}

sub p25 {
    my @a = @_;
    my @vals = sort {$a <=> $b} @a;
    my $i = scalar(@vals) * 0.25;
    return $vals[$i];
}

sub p75 {
    my @a = @_;
    my @vals = sort {$a <=> $b} @a;
    my $i = scalar(@vals) * 0.75;
    return $vals[$i];
}

sub minimum {
    my @a = @_;
    my @vals = sort {$a <=> $b} @a;
    return $vals[0];
}

sub maximum {
    my @a = @_;
    my @vals = sort {$b <=> $a} @a;
    return $vals[0];
}

sub average {
    my @p = @_;
    my $sum;
    for my $y (@p) {
        $sum += $y;
    }
    return $sum / scalar(@p);
}

sub dumpcsv {
    my ($filename, $aref) = @_;
    open(D, ">out/$filename.csv");
    my $index = 0;
    my $av;
    for my $key (sort keys %$aref) {
        my $v = $aref->{$key};
        if($av) {
            $av -= $av/10;
            $av += $v/10;
        }
        else {
            # should be the first only
            $av = $v;
        }
        printf D "%u;%s;%s;%u\n", $index++, $git{$key}, $v, $av;
    }
    close(D);
}

sub gensvg {
    my ($filename, $average) = @_;
    system("gnuplot -c graph.plot out/$filename.csv $average > out/$filename.svg");
}

sub genpercent {
    my ($filename, $p0, $p25, $p50, $p75, $p100) = @_;
    system("gnuplot -c horizontal.plot $p0 $p25 $p50 $p75 $p100 > out/$filename.svg");

}

sub show {
    my ($name, $which, $filename, $unit, %a) = @_;

    my $p0, $p25, $p50, $p75, $p100;
    my $aver;
    print "<a name=\"$filename\"></a>\n";
    print "<h2>$name ($filename)</h2>";
    print "$which is better\n";
    print "<pre>\n";
    printf "%u samples\n", scalar(values %a);
    printf "P0:      %u $unit\n", $p0 = minimum(values %a);
    printf "P25:     %u $unit\n", $p25 = p25(values %a);
    printf "P50:     %u $unit\n", $p50 = median(values %a);
    printf "P75:     %u $unit\n", $p75 = p75(values %a);
    printf "P100:    %u $unit\n", $p100 = maximum(values %a);
    printf "Average: %u $unit\n", $aver = average(values %a);
    printf "Span:    +-%u $unit, ", ($p100 - $p0)/2;
    if($aver) {
        printf "%.3f%% of average\n", ($p100 - $p0)/2 * 100 / $aver;
    }

    print "</pre>\n";
    dumpcsv($filename, \%a);
    gensvg($filename, $aver);
    genpercent("p-$filename", 0+$p0, 0+$p25, 0+$p50, 0+$p75, 0+$p100);

    print "<img width=\"1200\" src=\"$filename.svg\">\n";
    print "<br><img width=\"1200\" src=\"p-$filename.svg\">\n";
}

my @curlv;
my @confopts;

sub scorecard_dldata {
    my (@json) = @_;
    my $j = decode_json(join("", @json));
    my $speed = $$j{'downloads'}{'rows'}[0][1]{'val'};
    my $bytes = $$j{'downloads'}{'rows'}[0][1]{'stats'}{'rss'};
    return (0+$speed, 0+$bytes);
}

sub scorecard_uldata {
    my (@json) = @_;
    my $j = decode_json(join("", @json));
    my $speed = $$j{'uploads'}{'rows'}[0][1]{'val'};
    my $bytes = $$j{'uploads'}{'rows'}[0][1]{'stats'}{'rss'};
    return (0+$speed, 0+$bytes);
}

my $lowspeed = 1000000; # below this value is an error

sub single {
    my ($log) = @_;
    open(F, "<$log") || return;
    my @h1pj;
    my @h2pj;
    my @h3pj;
    my @h1puj;
    my @h2puj;
    my @h3puj;
    my $git = "";
    my $scan = "";

    # always just keep the latest of these
    undef @curlv;
    undef @confopts;

    while(<F>) {
        if(!$scan && /^(.*) git pull/) {
            $scan = $1;
        }
        if(/^100G: bytes\/sec: ([0-9.]+)/) {
            $h1serial{$scan} = $1;
        }
        elsif(/^mem: Maximum allocated: ([0-9.]+)/) {
            $maxalloc{$scan} = $1;
        }
        elsif(/^mem: Allocations: ([0-9.]+)/) {
            $allocations{$scan} = $1;
        }
        elsif(/^h1p:(.*)/) {
            push @h1pj, $1; # json
        }
        elsif(/^h2p:(.*)/) {
            push @h2pj, $1;
        }
        elsif(/^h3p:(.*)/) {
            push @h3pj, $1;
        }
        elsif(/^h1pu:(.*)/) {
            push @h1puj, $1; # json
        }
        elsif(/^h2pu:(.*)/) {
            push @h2puj, $1;
        }
        elsif(/^h3pu:(.*)/) {
            push @h3puj, $1;
        }
        elsif(/^git commit: (.*)/) {
            $git{$scan} = $1;
        }
        elsif(/^curl-V: (.*)/) {
            push @curlv, $1;
        }
        elsif(/^confopts: (.*)/) {
            push @confopts, $1;
        }
    }
    close(F);
    # Downloads
    if($h1pj[0]) {
        my ($speed, $mem) = scorecard_dldata(@h1pj);
        if($speed > $lowspeed) {
            $h1p{$scan} = $speed;
            $h1pbytes{$scan} = $mem;
        }
    }
    if($h2pj[0]) {
        my ($speed, $mem) = scorecard_dldata(@h2pj);
        if($speed > $lowspeed) {
            $h2p{$scan} = $speed;
            $h2pbytes{$scan} = $mem;
        }
    }
    if($h3pj[0]) {
        my ($speed, $mem) = scorecard_dldata(@h3pj);
        if($speed > $lowspeed) {
            $h3p{$scan} = $speed;
            $h3pbytes{$scan} = $mem;
        }
    }

    # Uploads
    if($h1puj[0]) {
        my ($speed, $mem) = scorecard_uldata(@h1puj);
        if($speed > $lowspeed) {
            $h1pu{$scan} = $speed;
            $h1pubytes{$scan} = $mem;
        }
    }

    if($h2puj[0]) {
        my ($speed, $mem) = scorecard_uldata(@h2puj);
        if($speed > $lowspeed) {
            $h2pu{$scan} = $speed;
            $h2pubytes{$scan} = $mem;
        }
    }

    if($h3puj[0]) {
        my ($speed, $mem) = scorecard_uldata(@h3puj);
        if($speed > $lowspeed) {
            $h3pu{$scan} = $speed;
            $h3pubytes{$scan} = $mem;
        }
    }
}

for my $l (sort @logs) {
    single("$logdir/$l");
}

show("Download speed 100G single transfer HTTP://",
     "higher",
     "100G-speed",
     "bytes/sec", %h1serial);
show("Allocations for a single HTTP transfer",
     "lower",
     "single-numallocs",
     "allocs", %allocations);
show("Allocated memory for a single HTTP transfer",
     "lower",
     "single-maxalloc",
     "bytes", %maxalloc);
show("Download speed parallel HTTP/1 (100x500MB)",
     "higher",
     "h1parallel-speed",
     "bytes/sec", %h1p);
show("Download speed parallel HTTP/2 (100x500MB)",
     "higher",
     "h2parallel-speed",
     "bytes/sec", %h2p);
show("Download speed parallel HTTP/3 (100x500MB)",
     "higher",
     "h3parallel-speed",
     "bytes/sec", %h3p);
show("Memory use RSS for parallel HTTP/1 (100x500MB)",
     "lower",
     "h1parallel-mem",
     "bytes", %h1pbytes);
show("Memory use RSS for parallel HTTP/2 (100x500MB)",
     "lower",
     "h2parallel-mem",
     "bytes", %h2pbytes);
show("Memory use RSS for parallel HTTP/3 (100x500MB)",
     "lower",
     "h3parallel-mem",
     "bytes", %h3pbytes);
show("Upload speed parallel HTTP/1 (100x500MB)",
     "higher",
     "h1parallel-upload-speed",
     "bytes/sec", %h1pu);
show("Upload speed parallel HTTP/2 (100x500MB)",
     "higher",
     "h2parallel-upload-speed",
     "bytes/sec", %h2pu);
show("Upload speed parallel HTTP/3 (100x500MB)",
     "higher",
     "h3parallel-upload-speed",
     "bytes/sec", %h3pu);
show("Memory use RSS for parallel upload HTTP/1 (100x500MB)",
     "lower",
     "h1parallel-upload-mem",
     "bytes", %h1pubytes);
show("Memory use RSS for parallel upload HTTP/2 (100x500MB)",
     "lower",
     "h2parallel-upload-mem",
     "bytes", %h2pubytes);
show("Memory use RSS for parallel upload HTTP/3 (100x500MB)",
     "lower",
     "h3parallel-upload-mem",
     "bytes", %h3pubytes);

print "<h3> configure</h3>";
print @confopts;
print "<h3> curl -V</h3>\n";
for my $c (@curlv) {
    print "$c<br>\n";
}
