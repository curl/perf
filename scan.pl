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
    my ($filename, $bar, $aref) = @_;
    open(D, ">out/$filename.csv");
    my $index = 0;
    my $av;
    my $prevc = "";
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
        if($stake{$key, $filename, 'val'}) {
            # there is a specific stake for this test in this build
            $bar = $stake{$key, $filename, 'val'};
        }
        my $commit = $git{$key};
        if($commit eq $prevc) {
            $commit = "";
        }
        else {
            $prevc = $commit;
        }
        printf D "%u;%s;%s;%u;%s\n", $index++, $commit, $v, $av, $bar;
    }
    close(D);
}

sub gensvg {
    my ($filename, $suffix, $average) = @_;
    system("gnuplot -c graph.plot out/$filename.csv $average > out/$filename-$suffix.svg");
}

sub genpercent {
    my ($filename, $suffix, $p0, $p25, $p50, $p75, $p100, $aver) = @_;
    system("gnuplot -c horizontal.plot $p0 $p25 $p50 $p75 $p100 $aver > out/$filename-$suffix.svg");

}

sub deltaopinion {
    my ($delta, $which) = @_;
    if($delta) {
        my $m = $delta;
        if($which eq "lower") {
            $m *= -1;
        }
        if($m < 0) {
            return "current results are BETTER";
        }
        return "current results are worse";
    }
    return "";
}

sub showval {
    my ($val) = @_;
    my $v = int($val);
    if($val < 1000000) {
        # less than a million
        return "$v";
    }
    elsif($val < 10000000) {
        my $s = sprintf("%.2f", $val / 1000);
        return "$v ($s K)";
    }
    elsif(($val/1000000) < 1000) {
        my $s = sprintf("%.2f", $val / 1000000);
        return "$v ($s M)";
    }
    else {
        my $s = sprintf("%.2f", $val / 1000000000);
        return "$v ($s G)";
    }
}

sub show {
    my ($name, $which, $filename, $unit, %a) = @_;

    my ($p0, $p25, $p50, $p75, $p100);
    my $aver;
    my $bar = $stake{"default", $filename, 'val'};
    print "<h2>$name <a name=\"$filename\" href=\"#$filename\">($filename)</a></h2>";
    print "$which is better, $unit\n";
    print "<pre>\n";
    printf "%u samples\n", scalar(values %a);
    $p0 = minimum(values %a);
    $p25 = p25(values %a);
    $p50 = median(values %a);
    $p75 = p75(values %a);
    $p100 = maximum(values %a);
    $aver = average(values %a);

    printf "P0:      %s\n", showval($p0);
    printf "P25:     %s\n", showval($p25);
    printf "P50:     %s\n", showval($p50);
    printf "P75:     %s\n", showval($p75);
    printf "P100:    %s\n", showval($p100);
    printf "Average: %s\n", showval($aver);
    printf "Span:    +-%u, ", ($p100 - $p0)/2;
    if($aver) {
        printf "%.2f%% of average\n", ($p100 - $p0)/2 * 100 / $aver;
    }
    if($bar) {
        my $avdelta;
        my $p50delta;
        printf "\nStake:   %s %s ('stake' is a set typical value for this test)\n",
            $stake{"default", $filename, 'date'},
            $stake{"default", $filename, 'desc'};
        printf "         %s\n", showval($bar);
        $avdelta = $bar - $aver;
        printf "         %d from average, (%.2f%%) %s\n",
            $avdelta, ($avdelta * 100) / $aver,
            deltaopinion($avdelta, $which);
        $p50delta = $bar - $p50;
        printf "         %d from P50, (%.2f%%) %s\n",
            $p50delta, ($p50delta * 100) / $p50,
            deltaopinion($p50delta, $which);
    }

    print "</pre>\n";

    my $suffix = int(rand(100000000));
    
    dumpcsv($filename, $bar, \%a);
    gensvg($filename, $suffix, $aver, $bar);
    genpercent("p-$filename", $suffix, 0+$p0, 0+$p25, 0+$p50, 0+$p75, 0+$p100, 0+$aver);

    print "<img width=\"1400\" src=\"$filename-$suffix.svg\">\n";
    print "<br><img width=\"1400\" src=\"p-$filename-$suffix.svg\">\n";
}

my @curlv;
my @confopts;

sub scorecard_dldata {
    my (@json) = @_;
    my $j = decode_json(join("", @json));
    my $speed = $$j{'downloads'}{'rows'}[0][1]{'val'};
    my $bytes = $$j{'downloads'}{'rows'}[0][1]{'stats'}{'rss-max'};
    if(!$bytes) {
        # try the old
        $bytes = $$j{'downloads'}{'rows'}[0][1]{'stats'}{'rss'};
    }
    return (0+$speed, 0+$bytes);
}

sub scorecard_uldata {
    my (@json) = @_;
    my $j = decode_json(join("", @json));
    my $speed = $$j{'uploads'}{'rows'}[0][1]{'val'};
    my $bytes = $$j{'uploads'}{'rows'}[0][1]{'stats'}{'rss-max'};
    if(!$bytes) {
        $bytes = $$j{'uploads'}{'rows'}[0][1]{'stats'}{'rss'};
    }
    return (0+$speed, 0+$bytes);
}

sub scorecard_req {
    my (@json) = @_;
    my $j = decode_json(join("", @json));
    my $speed = $$j{'requests'}{'rows'}[0][2]{'val'};
    my $bytes = $$j{'requests'}{'rows'}[0][2]{'stats'}{'rss-max'};
    if(!$bytes) {
        $bytes = $$j{'requests'}{'rows'}[0][2]{'stats'}{'rss'};
    }
    return (0+$speed, 0+$bytes);
}

sub loadstakes {
    my ($file) = @_;
    my $name;
    my $date;
    my $desc;
    my $val;
    open(S, "<$file") ||
        die "found no $file";
    my @all = <S>;
    close(S);
    storestakes("default", @all);
}

sub storestakes {
    my ($build, @all) = @_;
    for(@all) {
        if(/^ *#/) {
            # comment, skip
            next;
        }
        if(/^\[([^ ]*)]/) {
            $name = $1;
        }
        elsif(/^ *([a-z-]*): (.*)/) {
            my ($key, $val) = ($1, $2);
            if($key !~ /^(val|date|desc)/) {
                die "illegal keyword in $build: $key";
            }
            $stake{$build, $name, $key} = $val;
        }
    }
}

# transfer speed bytes/sec
my $lowspeed = 1000000; # below this value is an error
# requests/second
my $lowreq = 1000; # below this value is an error

sub single {
    my ($log) = @_;
    open(F, "<$log") || return;
    my @h1pj;
    my @h2pj;
    my @h3pj;
    my @h1rj;
    my @h2rj;
    my @h3rj;
    my @h1puj;
    my @h2puj;
    my @h3puj;
    my @stakes;
    my $git = "";
    my $scan = "";

    # always just keep the latest of these
    undef @curlv;
    undef @confopts;

    while(<F>) {
        if(!$scan && /^(.*) git pull/) {
            $scan = $1;
        }
        elsif(/^(.*) done\n/) {
            $done = $1;
        }
        elsif(/^100G: bytes\/sec: ([0-9.]+)/) {
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
        elsif(/^h1req:(.*)/) {
            push @h1rj, $1; # json
        }
        elsif(/^h2req:(.*)/) {
            push @h2rj, $1;
        }
        elsif(/^h3req:(.*)/) {
            push @h3rj, $1;
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
        elsif(/^stakes: (.*)/) {
            push @stakes, $1;
        }
    }
    close(F);

    if($stakes[0]) {
        storestakes($scan, @stakes);
    }

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
    # Requests
    if($h1rj[0]) {
        my ($speed, $mem) = scorecard_req(@h1rj);
        if($speed > $lowreq) {
            $h1r{$scan} = $speed;
            $h1rbytes{$scan} = $mem;
        }
    }
    if($h2rj[0]) {
        my ($speed, $mem) = scorecard_req(@h2rj);
        if($speed > $lowreq) {
            $h2r{$scan} = $speed;
            $h2rbytes{$scan} = $mem;
        }
    }
    if($h3rj[0]) {
        my ($speed, $mem) = scorecard_req(@h3rj);
        if($speed > $lowreq) {
            $h3r{$scan} = $speed;
            $h3rbytes{$scan} = $mem;
        }
    }
}

# Load the current stakes. Each build has its own set.
loadstakes("stakes.conf");

for my $l (sort @logs) {
    single("$logdir/$l");
}

my $numlogs = scalar(@logs);
use POSIX qw(strftime);
my @now = gmtime;
my $now = strftime "%Y-%m-%d %H:%M:%S UTC", @now;

print <<HEAD
<h1>curl performance tests</h1>

$numlogs builds analyzed. Last run ended $done (Daniel's local time). This
page was rendered at $now.

HEAD
    ;

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
show("HTTP/1 parallel requests (100000 x 40)",
     "higher",
     "h1-requests",
     "requests/sec", %h1r);
show("HTTP/2 parallel requests (100000 x 40)",
     "higher",
     "h2-requests",
     "requests/sec", %h2r);
show("HTTP/3 parallel requests (100000 x 40)",
     "higher",
     "h3-requests",
     "requests/sec", %h3r);
show("Memory use for HTTP/1 parallel requests (100000 x 40)",
     "lower",
     "h1-req-mem",
     "bytes", %h1rbytes);
show("Memory use for HTTP/2 parallel requests (100000 x 40)",
     "lower",
     "h2-req-mem",
     "bytes", %h2rbytes);
show("Memory use for HTTP/3 parallel requests (100000 x 40)",
     "lower",
     "h3-req-mem",
     "bytes", %h3rbytes);

print "<h3> configure</h3>";
print @confopts;
print "<h3> curl -V</h3>\n";
for my $c (@curlv) {
    print "$c<br>\n";
}
