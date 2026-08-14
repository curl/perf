#!/usr/bin/perl

use JSON;
use Data::Dumper;

my $logdir = "log";
my $outdir = "out";
my $graphplot = "graph.plot";
my $commitbase = "https://github.com/curl/curl/commit";

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

sub mean {
    my @p = @_;

    if(!scalar(@p)) {
        # precaution
        return -1; # odd value
    }
    my $sum;
    for my $y (@p) {
        $sum += $y;
    }
    return $sum / scalar(@p);
}

sub stddev {
    my @p = @_;
    my $count = scalar @p;
    if($count < 2) {
        return 0; # can't be done
    }
    my $mean = mean(@p);
    my $sqsum = 0;
    foreach my $n (@p) {
        $sqsum += ($n - $mean) ** 2;
    }

    my $sample_std_dev = sqrt($sqsum / ($count - 1));
    return $sample_std_dev;
}

# entries to store in the "last N builds" CSV
my $numlast = 100;

sub storelatest {
    my ($filename, @o) = @_;

    # This should store only the last N entries
    while(scalar(@o) > $numlast) {
        shift @o;
    }
    open(D, ">$outdir/$filename.csv");
    print D @o;
    close(D);
}

# entries to store in the LTTB CSV
my $numlttb = 20;

sub storelttb {
    my ($filename, @o) = @_;

    # Helper to parse (X, Y) from a CSV row
    # Row format: index;name;minimum;median;maximum;average;bar
    my $parse_pt = sub {
        my ($line) = @_;
        my @f = split /;/, $line;
        # X = index (col 0), Y = average (col 5) or median (col 3)
        my $x = defined $f[0] ? $f[0] + 0 : 0;
        my $y = defined $f[5] && $f[5] ne '' ? $f[5] + 0 : ($f[3] // 0) + 0;
        return ($x, $y);
    };

    my $nin = scalar @o;

    # No downsampling needed if input has fewer or equal entries than requested
    if ($nin <= $numlttb || $numlttb < 3) {
        open(D, ">$outdir/lt-$filename.csv") or die "Cannot open file: $!";
        print D @o;
        close(D);
        return;
    }

    my @sampled;

    # 1. Always keep the first point
    push @sampled, $o[0];
    my ($ax, $ay) = $parse_pt->($o[0]);

    # Calculate bucket size for the remaining intermediate points
    my $bucket_size = ($nin - 2) / ($numlttb - 2);

    # 2. Process each intermediate bucket
    for my $i (0 .. $numlttb - 3) {
        # Determine range of current bucket B_i
        my $range_start = int($i * $bucket_size) + 1;
        my $range_end   = int(($i + 1) * $bucket_size) + 1;
        $range_end = $nin - 1 if $range_end > $nin - 1;

        # Determine range of next bucket B_{i+1} to compute its center of mass
        # (C)
        my $next_start = int(($i + 1) * $bucket_size) + 1;
        my $next_end   = int(($i + 2) * $bucket_size) + 1;
        $next_end = $nin if $next_end > $nin;

        # Calculate average (center of mass) for next bucket B_{i+1}
        my ($avg_x, $avg_y, $count) = (0, 0, 0);
        for my $j ($next_start .. $next_end - 1) {
            my ($px, $py) = $parse_pt->($o[$j]);
            $avg_x += $px;
            $avg_y += $py;
            $count++;
        }

        if ($count > 0) {
            $avg_x /= $count;
            $avg_y /= $count;
        } else {
            ($avg_x, $avg_y) = $parse_pt->($o[-1]);
        }

        # Find point in current bucket B_i that maximizes triangle area (A, P,
        # C)
        my $max_area = -1;
        my $max_idx  = $range_start;

        for my $j ($range_start .. $range_end - 1) {
            my ($px, $py) = $parse_pt->($o[$j]);

            # Triangle area = 0.5 * | xA(yP - yC) + xP(yC - yA) + xC(yA - yP)
            my $area = abs($ax * ($py - $avg_y) +
                           $px * ($avg_y - $ay) +
                           $avg_x * ($ay - $py)) * 0.5;

            if ($area > $max_area) {
                $max_area = $area;
                $max_idx  = $j;
            }
        }

        # Select point with largest triangle area
        push @sampled, $o[$max_idx];

        # Set point A to the selected point for the next bucket iteration
        ($ax, $ay) = $parse_pt->($o[$max_idx]);
    }

    # 3. Always keep the last point
    push @sampled, $o[-1];

    # update the index numbers in first column
    my @u;
    my $i = 0;
    for my $s (@sampled) {
        $s =~ s/^(\d+);//g;
        push @u, "$i;$s";
        $i++;
    }

    # Save reduced dataset
    open(D, ">$outdir/lt-$filename.csv") or die "Cannot open file: $!";
    print D @u;
    close(D);
}


sub gencsv {
    my ($filename, $aref) = @_;
    my $index = 0;
    my $av;
    my @av;
    my $prevc = "";
    my @vals;
    my $bar = "";
    my @o;
    for my $key (sort keys %$aref) {
        my $commit = $git{$key};
        my $v;
        my $min;
        my $max;
        if($stake{$key, $filename, 'val'}) {
            # there is a specific stake for this test in this build
            $bar = $stake{$key, $filename, 'val'};
            # then keep this value, for the last entry or if the next one
            # would weirdly lack it
        }
        if($commit ne $prevc) {
            if($vals[0]) {
                $min = minimum(@vals);
                $v = median(@vals);
                $max = maximum(@vals);
                undef @vals;
                push @vals, $aref->{$key};
            }
            else {
                # this is the first
                $prevc = $commit;
                push @vals, $aref->{$key};
                next;
            }
        }
        else {
            # the same commit as the previous, accumulate
            $prevc = $commit;
            push @vals, $aref->{$key};
            next;
        }

        push @av, $v;
        if(scalar(@av) > 4) {
            shift @av;
        }
        $av = mean(@av);

        push @o,
            sprintf "%u;%s;%u;%u;%u;%u;%s\n", $index++, $gitalias{$prevc},
            $min, $v, $max, $av, $bar;
        $prevc = $commit;
    }

    $min = minimum(@vals);
    $v = median(@vals);
    $max = maximum(@vals);
    push @av, $v;
    if(scalar(@av) > 4) {
        shift @av;
    }
    $av = mean(@av);
    push @o, sprintf "%u;%s;%s;%s;%s;%u;%s\n", $index++, $gitalias{$prevc},
        $min, $v, $max, $av, $bar;
    return @o;
}

sub gensvg {
    my ($filename, $suffix, $mean) = @_;
    system("gnuplot -c $graphplot $outdir/$filename.csv $mean > $outdir/$filename-$suffix.svg");
}

sub genpercent {
    my ($filename, $suffix, $p0, $p25, $p50, $p75, $p100, $aver) = @_;
    system("gnuplot -c horizontal.plot $p0 $p25 $p50 $p75 $p100 $aver > $outdir/$filename-$suffix.svg");

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
    my $sign = "";
    if($v < 0) {
        $sign = "-";
        $v = -$v;
    }
    if($v < 1000000) {
        # less than a million
        return "$sign$v";
    }
    elsif(($v/1000000) < 1000) {
        my $s = sprintf("%.2f", $val / 1000000);
        return "$sign$v ($s M)";
    }
    else {
        my $s = sprintf("%.2f", $val / 1000000000);
        return "$sign$v ($s G)";
    }
}

sub showdocs {
    my ($test) = @_;
    open(D, "<describe-tests.conf");
    my $m = 0;
    while(<D>) {
        if($m && /^\[/) {
            # we are done
            last;
        }
        elsif(/^\[$test\]/) {
            $m = 1; # this is us
        }
        elsif($m) {
            print $_;
        }
    }
    close(D);
}

sub show {
    my ($name, $which, $filename, $unit, %a) = @_;

    my ($p0, $p25, $p50, $p75, $p100);
    my $aver;
    my $bar = $stake{"default", $filename, 'val'};
    print "<h2>$name <a name=\"$filename\" href=\"#$filename\">($filename)</a></h2>";
    print "$which is better, $unit\n";
    $p0 = minimum(values %a);
    $p25 = p25(values %a);
    $p50 = median(values %a);
    $p75 = p75(values %a);
    $p100 = maximum(values %a);
    $aver = mean(values %a);
    my $std = stddev(values %a);

    my @o = gencsv($filename, \%a);
    storelatest($filename, @o);
    storelttb($filename, @o);
    
    print "<pre>\n";
    printf "%u samples, %u rounds\n", scalar(values %a), scalar(@o);
    printf "P0:      %s\n", showval($p0);
    printf "P25:     %s\n", showval($p25);
    printf "P50:     %s\n", showval($p50);
    printf "P75:     %s\n", showval($p75);
    printf "P100:    %s\n", showval($p100);
    printf "Mean:    %s\n", showval($aver);
    printf "Std dev: %s", showval($std);
    if($aver) {
        printf ", %.2f%% of mean",  $std * 100 / $aver;
    }
    printf "\nSpan:    +-%s", showval(($p100 - $p0)/2);
    if($aver) {
        printf ", %.2f%% of mean", ($p100 - $p0)/2 * 100 / $aver;
    }
    print "\n";
    if($bar) {
        my $avdelta;
        my $p50delta;
        printf "\nStake:   %s %s ('stake' is a set typical value for this test)\n",
            $stake{"default", $filename, 'date'},
            $stake{"default", $filename, 'desc'};
        printf "         %s\n", showval($bar);
        $avdelta = $bar - $aver;
        printf "         %s from mean, (%.2f%%) %s\n",
            showval($avdelta),
            ($avdelta * 100) / $aver,
            deltaopinion($avdelta, $which);
        $p50delta = $bar - $p50;
        printf "         %s from P50, (%.2f%%) %s\n",
            showval($p50delta),
            ($p50delta * 100) / $p50,
            deltaopinion($p50delta, $which);
    }

    print "</pre>\n";

    my $suffix = int(rand(100000000));
    
    gensvg($filename, $suffix, $aver);
    gensvg("lt-$filename", $suffix, $aver);
    genpercent("p-$filename", $suffix, 0+$p0, 0+$p25, 0+$p50, 0+$p75, 0+$p100, 0+$aver);

    print "<details><summary>test description</summary>\n";
    showdocs($filename);
    print "</details>\n";

    print "<h3>Most recent $numlast rounds</h3>\n";
    print "<img src=\"$filename-$suffix.svg\">\n";
    print "<details><summary>Data distribution</summary>\n";
    print "<h3>Data distribution</h3>\n";
    print "<img src=\"p-$filename-$suffix.svg\">\n";
    print "</details>\n";
    
    print "<details><summary>Full range graph</summary>\n";
    print "<h3>Full range</h3>\n";
    print "Downsamples the entire set to $numlttb data points.\n";
    print "<img src=\"lt-$filename-$suffix.svg\">\n";
    print "</details>\n";
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

sub builddetails {
    open(G, "<$outdir/git-hashes") || return;
    my %desc;
    my %order;
    my @log;
    my $age = 0;
    while(<G>) {
        if(/^([^ ]*) (.*)/) {
            my ($hash, $desc) = ($1, $2);
            push @log, $hash;
            $desc{$hash} = $desc;
            if($gitcommits{$hash}) {
                $order{$hash} = $age;
                $age++;
            }
        }
    }
    close(G);
    print "<details><summary>build details</summary>\n";
    my $index;

    my $oldest = $inorder[0];
    
    for my $c (@log) {
        if($gitcommits{$c}) {
            printf "<br><a href=\"%s/%s\">%s</a> %s (%u builds)\n",
                $commitbase, $c, $gitalias{$c}, $desc{$c},
                $gitcommits{$c};
        }
        else {
            printf "<br> plus: <a href=\"%s/%s\">%s</a> %s \n",
                $commitbase, $c, $c, $desc{$c};
        }
        if($c eq $oldest) {
            # end now
            last;
        }
    }

    print "</details>\n";

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
        elsif(/^structs: (.*)\t(\d+)\t\d*/) {
            my ($struct, $size) = ($1,$2);
            if($struct eq "Curl_easy") {
                $curleasy{$scan} = $size;
            }
            elsif($struct eq "Curl_multi") {
                $curlmulti{$scan} = $size;
            }
            elsif($struct eq "connectdata") {
                $connectdata{$scan} = $size;
            }
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

my $gitcommits;
my $short = 0;
for my $c (sort keys %git) {
    $gitcommits{$git{$c}}++;
    if($gitcommits{$git{$c}} == 1) {
        push @inorder, $git{$c};
        $gitalias{$git{$c}} = sprintf("R%u", $short);
        $short++;
    }
}

my $numrounds = scalar(keys %gitcommits);

my $numlogs = scalar(@logs);
use POSIX qw(strftime);
my @now = gmtime;
my $now = strftime "%Y-%m-%d %H:%M:%S UTC", @now;

print <<HEAD
<h1>curl performance tests</h1>

$numlogs builds analyzed. Last run ended $done (Daniel's local time). This
page was rendered at $now.

<details><summary>$numrounds rounds</summary>
<p>

HEAD
    ;

for my $c (@inorder) {
    printf "<a href=\"%s/%s\">%s</a>, ", $commitbase, $c, $gitalias{$c};
}
print "</details>\n";

my @alltests = ("100G-speed",
               "single-numallocs",
               "single-maxalloc",
               "h1parallel-speed",
               "h2parallel-speed",
               "h3parallel-speed",
               "h1parallel-mem",
               "h2parallel-mem",
               "h3parallel-mem",
               "h1parallel-upload-speed",
               "h2parallel-upload-speed",
               "h3parallel-upload-speed",
               "h1parallel-upload-mem",
               "h2parallel-upload-mem",
               "h3parallel-upload-mem",
               "h1-requests",
               "h2-requests",
               "h3-requests",
               "h1-req-mem",
               "h2-req-mem",
               "h3-req-mem",
               "easy-handle",
               "multi-handle",
               "connectdata",
    );
printf "<details><summary>%u tests</summary>\n", scalar(@alltests);

for my $t (@alltests) {
    print "<a href=\"#$t\">$t</a>, ";
}
print "</details>\n";

builddetails();

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
show("Curl_easy struct size",
     "lower",
     "easy-handle",
     "bytes", %curleasy) if %curleasy;
show("Curl_multi struct size",
     "lower",
     "multi-handle",
     "bytes", %curlmulti) if %curlmulti;
show("connectdata struct size",
     "lower",
     "connectdata",
     "bytes", %connectdata) if %connectdata;

print "<h3> configure</h3>";
print @confopts;
print "<h3> curl -V</h3>\n";
for my $c (@curlv) {
    print "$c<br>\n";
}
