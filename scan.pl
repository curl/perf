#!/usr/bin/perl

use JSON;
use Data::Dumper;

my $logdir = "log";
my $outdir = "out";
my $graphplot = "graph.plot";
my $trendplot = "trend.plot";
my $commitbase = "https://github.com/curl/curl/commit";

# entries to store in each CSV
my $roundspergraph = 100;

# Show deltas at the top when mean is this many percent diff vs marker
my $deltathreshold = 0.7;

# Use these many values for the moving average
my $movingaverage = 10;

# number of entries to store in the "full range" LTTB CSV file
my $numlttb = 100;

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

sub writecsv {
    my ($filename, $begin, $end, $oref) = @_;
    my $out = 0;

    if($begin < 0) {
        $end -= $begin;
        $begin = 0;
    }
    open(D, ">$outdir/$filename.csv");
    for my $i ($begin .. $end) {
        print D $$oref[$i];
        $out++;
    }
    close(D);
    return $out;
}

# store all data in a number of CSV files
sub storedata {
    my ($filename, $oref) = @_;
    my $csvi = 0;
    my $n = scalar(@$oref);

    do {
        writecsv("$csvi-$filename", $n - $roundspergraph, $n - 1, $oref);
        $n -= $roundspergraph;
        $csvi++;
    } while($n > 0);
}

sub storelttb {
    my ($filename, @o) = @_;

    # Helper to parse (X, Y) from a CSV row
    # Row format: index;name;minimum;median;maximum;mean;bar
    my $parse_pt = sub {
        my ($line) = @_;
        my @f = split /;/, $line;
        # X = index (col 0), Y = mean (col 5) or median (col 3)
        my $x = defined $f[0] ? $f[0] + 0 : 0;
        my $y = defined $f[5] && $f[5] ne '' ? $f[5] + 0 : ($f[3] // 0) + 0;
        return ($x, $y);
    };

    my $nin = scalar @o;

    my @sampled;

    # No downsampling needed if input has fewer or equal entries than requested
    if ($nin <= $numlttb || $numlttb < 3) {
        @sampled = @o;
        goto trendit; # skip to the trend line at once
    }

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

  trendit:
    
    # update the index numbers in first column
    my @u;
    my @u2;
    my $i = 0;
    my @meds;
    for my $s (@sampled) {
        my @f = split /;/, $s;
        push @meds, $f[3]; # the median value
        $s =~ s/^(\d+);//g; # strip the index
        push @u, "$i;$s"; # add new index
        $i++;
    }

    # do the Mann-Kendall Test + Sen's Slope
    my ($p_value, @trend) = mann_kendall_sens_slope(\@meds);

    # append the slope to data set
    for my $s (@u) {
        chomp $s;
        push @u2, sprintf "%s;%s\n", $s, shift @trend;
    }

    # Save reduced dataset
    open(D, ">$outdir/lt-$filename.csv") or die "Cannot open file: $!";
    print D @u2;
    close(D);

    return $p_value;
}

# Figure out the median marker per round (commit)
sub markerpercommit {
    my ($filename, $aref) = @_;
    my %sta;
    my %med;
    for my $key (sort keys %$aref) {
        my $commit = $git{$key};
        my $bar;
        if($marker{$key, $filename, 'val'}) {
            # there is a specific marker for this test in this build
            $bar = $marker{$key, $filename, 'val'};
        }
        $sta{$commit} .= "$bar " if($bar);
    }
    for my $c(keys %sta) {
        $med{$c} = median(split(/ /, $sta{$c}));
    }
    return %med;
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

    my %markers = markerpercommit($filename, $aref);

    for my $key (sort keys %$aref) {
        my $commit = $git{$key};
        my $v;
        my $min;
        my $max;

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
        if(scalar(@av) > $movingaverage) {
            shift @av;
        }
        $av = mean(@av);

        # there is a specific marker for this test in this build
        $bar = $markers{$prevc};

        if(($bar > 1.2 * $v) || ($bar < 0.8 * $v)) {
            # bad bar, ignore
            $bar = "";
        }

        push @o,
            sprintf "%u;%s;%s;%s;%s;%s;%s\n", $index++, $gitalias{$prevc},
            $min, $v, $max, $av, $bar;
        $prevc = $commit;
    }

    $min = minimum(@vals);
    $v = median(@vals);
    $max = maximum(@vals);
    push @av, $v;
    if(scalar(@av) > $movingaverage) {
        shift @av;
    }
    $av = mean(@av);
    # there is a specific marker for this test in this build
    $bar = $markers{$prevc};

    if(($bar > 1.2 * $v) || ($bar < 0.8 * $v)) {
        # bad bar, ignore
        $bar = "";
    }
    push @o, sprintf "%u;%s;%s;%s;%s;%s;%s\n", $index++, $gitalias{$prevc},
        $min, $v, $max, $av, $bar;
    return @o;
}

sub gensvg {
    my ($filename, $suffix, $mean, $plots) = @_;
    for (my $i = 0; $i < $plots; $i++) {
        system("gnuplot -c $graphplot $outdir/$i-$filename.csv $mean > $outdir/$i-$filename-$suffix.svg");
    }
}

sub genfullsvg {
    my ($filename, $suffix, $mean) = @_;
    system("gnuplot -c $graphplot $outdir/$filename.csv $mean > $outdir/$filename-$suffix.svg");
}

sub gentrendsvg {
    my ($filename, $suffix) = @_;
    system("gnuplot -c $trendplot $outdir/lt-$filename.csv > $outdir/tr-$filename-$suffix.svg");
}

sub genpercent {
    my ($filename, $suffix, $p0, $p25, $p50, $p75, $p100, $aver) = @_;
    system("gnuplot -c horizontal.plot $p0 $p25 $p50 $p75 $p100 $aver > $outdir/$filename-$suffix.svg");
}

sub deltaopinion {
    my ($delta, $which) = @_;
    if($which eq "exact") {
        return "";
    }
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

my %alltests;

sub showval {
    my ($val, $decimals) = @_;
    my $v;
    my $sign = "";
    if($val < 0) {
        $sign = "-";
        $val = abs($val);
    }
    if(!$decimals) {
        $v = int($val);
    }
    else {
        $v = sprintf "%.${decimals}f", $val;
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
    my @out;
    while(<D>) {
        if($m && /^\[/) {
            # we are done
            last;
        }
        elsif(/^\[$test\]/) {
            $m = 1; # this is us
        }
        elsif($m) {
            push @out, $_;
        }
    }
    close(D);
    return @out;
}

sub mann_kendall_sens_slope {
    my ($data_ref) = @_;
    
    return undef unless defined $data_ref && @$data_ref >= 2;

    my $n = scalar @$data_ref;
    my $num_pairs = $n * ($n - 1) / 2;

    my $S = 0;
    my @slopes;
    $#slopes = $num_pairs - 1;
    my $pair_idx = 0;

    # 1. Compute S statistic and collect pairwise slopes
    for (my $i = 0; $i < $n - 1; $i++) {
        for (my $j = $i + 1; $j < $n; $j++) {
            my $diff = $data_ref->[$j] - $data_ref->[$i];

            if    ($diff > 0) { $S += 1; }
            elsif ($diff < 0) { $S -= 1; }

            $slopes[$pair_idx++] = $diff / ($j - $i);
        }
    }

    # 2. Tie correction factor
    my %tie_counts;
    $tie_counts{$_}++ for @$data_ref;

    my $tie_correction = 0;
    while (my ($val, $count) = each %tie_counts) {
        if ($count > 1) {
            $tie_correction += $count * ($count - 1) * (2 * $count + 5);
        }
    }

    # 3. Variance and Z statistic
    my $var_S = ($n * ($n - 1) * (2 * $n + 5) - $tie_correction) / 18.0;

    my $Z = 0;
    if ($var_S > 0) {
        if    ($S > 0) { $Z = ($S - 1.0) / sqrt($var_S); }
        elsif ($S < 0) { $Z = ($S + 1.0) / sqrt($var_S); }
    }

    my $p_value = POSIX::erfc(abs($Z) / sqrt(2.0));

    # 4. Sen's Slope (m)
    @slopes = sort { $a <=> $b } @slopes;

    my $median_slope;
    my $mid = int($num_pairs / 2);
    if ($num_pairs % 2 == 1) {
        $median_slope = $slopes[$mid];
    } else {
        $median_slope = ($slopes[$mid - 1] + $slopes[$mid]) / 2.0;
    }

    # 5. Calculate Intercept (c) = median(y_i - m * i)
    my @intercept_candidates;
    for (my $i = 0; $i < $n; $i++) {
        push @intercept_candidates, $data_ref->[$i] - ($median_slope * $i);
    }
    @intercept_candidates = sort { $a <=> $b } @intercept_candidates;

    my $intercept;
    my $mid_n = int($n / 2);
    if ($n % 2 == 1) {
        $intercept = $intercept_candidates[$mid_n];
    } else {
        $intercept = ($intercept_candidates[$mid_n - 1] + $intercept_candidates[$mid_n]) / 2.0;
    }

    # 6. Generate Y values array for plotting the trend line
    my @trend_line;
    for (my $i = 0; $i < $n; $i++) {
        push @trend_line, sprintf("%.3f", $median_slope * $i + $intercept);
    }

# A P-value less than 0.05 => "the trend is statistically significant"
    
#    return {
#        S          => $S,
#        var_S      => $var_S,
#        Z          => $Z,
#        p_value    => $p_value,
#        sens_slope => $median_slope,
#        intercept  => $intercept,
#        trend_line => \@trend_line, # Array of Y points corresponding to each X index
#    };
    return ($p_value, @trend_line);
}

my %unit2dec = (
    'CPU%' => 3,
    'nanoseconds' => 2,
    );

sub show {
    my ($name, $which, $filename, $unit, %a) = @_;

    my ($p0, $p25, $p50, $p75, $p100);
    my $mean;
    my $decimals = $unit2dec{$unit};
    my $bar = $marker{"default", $filename, 'val'};
    my @out;
    push @out, "<h2>$name <a name=\"$filename\" href=\"#$filename\">($filename)</a></h2>";
    push @out, "$which is better, $unit\n";
    $p0 = minimum(values %a);
    $p25 = p25(values %a);
    $p50 = median(values %a);
    $p75 = p75(values %a);
    $p100 = maximum(values %a);
    $mean = mean(values %a);
    my $std = stddev(values %a);

    my @o = gencsv($filename, \%a);
    storedata($filename, \@o);
    my $p_value = storelttb($filename, @o);

    # the last moving average value
    my @last = split(/;/, $o[-1]);
    my $movingav = $last[5];
    
    push @out, "<pre>\n";
    push @out, sprintf "%u samples, %u rounds\n", scalar(values %a), scalar(@o);
    push @out, sprintf "P0:      %s\n", showval($p0, $decimals);
    push @out, sprintf "P25:     %s\n", showval($p25, $decimals);
    push @out, sprintf "P50:     %s\n", showval($p50, $decimals);
    push @out, sprintf "P75:     %s\n", showval($p75, $decimals);
    push @out, sprintf "P100:    %s\n", showval($p100, $decimals);
    push @out, sprintf "Mean:    %s\n", showval($mean, $decimals);
    push @out, sprintf "Moving:  %s", showval($movingav, $decimals);
    if($mean) {
        my $mdiff = $movingav - $mean;
        push @out, sprintf ", %.2f%% from mean",  $mdiff * 100 / $mean;

        $mdeltas{$filename} = sprintf "%.2f;%.2f",
            $mdiff * 100 / $mean, $std * 100 / $mean;
    }
    push @out, sprintf "\nStd dev: %s", showval($std, $decimals);
    if($mean) {
        push @out, sprintf ", %.2f%% of mean",  $std * 100 / $mean;
    }
    push @out, sprintf "\nSpan:    +-%s", showval(($p100 - $p0)/2, $decimals);
    if($mean) {
        push @out, sprintf ", %.2f%% of mean", ($p100 - $p0)/2 * 100 / $mean;
    }
    push @out, "\n";
    if($bar) {
        my $avdelta;
        my $p50delta;
        push @out, sprintf "\nMarker:  %s %s ('marker' is a set typical value for this test)\n",
            $marker{"default", $filename, 'date'},
            $marker{"default", $filename, 'desc'};
        push @out, sprintf "         %s\n", showval($bar, $decimals);
        $avdelta = $bar - $mean;
        push @out, sprintf "         %s from mean, (%.2f%%) %s\n",
            showval($avdelta, $decimals),
            ($avdelta * 100) / $mean,
            deltaopinion($avdelta, $which);
        $p50delta = $bar - $p50;
        push @out, sprintf "         %s from P50, (%.2f%%) %s\n",
            showval($p50delta, $decimals),
            ($p50delta * 100) / $p50,
            deltaopinion($p50delta, $which);

        # store the marker diff compared to mean
        $deltas{$filename} = ($avdelta * 100) / $mean;
    }

    push @out, "</pre>\n";

    my $suffix = int(rand(100000000));
    
    gensvg($filename, $suffix, $mean, scalar(@o) / $roundspergraph);
    if(scalar(@o) > $roundspergraph) {
        genfullsvg("lt-$filename", $suffix, $mean);
    }

    if(scalar(@o) > 10) {
        gentrendsvg($filename, $suffix);
    }
    genpercent("p-$filename", $suffix, 0+$p0, 0+$p25, 0+$p50, 0+$p75, 0+$p100, 0+$mean);

    my $f = scalar(@o) - $roundspergraph;
    if($f < 0) {
        $f = 0;
    }
    my $shows = $roundspergraph;
    if($shows > scalar(@o)) {
        $shows = scalar(@o);
    }

    push @out, "<details open>";
    push @out, sprintf "<summary>Most recent $shows rounds</summary>\n",
        $f, scalar(@o) - 1;
    push @out, "<img src=\"0-$filename-$suffix.svg\">\n";

    if(scalar(@o) > $roundspergraph) {
        my $n = scalar(@o);
        my $img = 1;
        # $i is the last build shown per image
        for (my $i = scalar(@o) - $roundspergraph - 1; $i >= 0; $i -= $roundspergraph) {
            my $first = $i - $roundspergraph + 1;
            my $end = $i;
            if($first < 0) {
                $end -= $first;
                $first = 0;
            }
            push @out, sprintf "<details><summary>Round %u - %u (of %u)</summary>\n",
                $first, $end, scalar(@o);
            push @out, "<img src=\"$img-$filename-$suffix.svg\">\n";
            push @out, "</details>\n";
            $img++;
        }
    }
    push @out, "</details>\n";

    push @out, "<details><summary>Description</summary>\n";
    push @out, showdocs($filename);
    push @out, "</details>\n";

    push @out, "<details><summary>Data distribution</summary>\n";
    push @out, "<p><img src=\"p-$filename-$suffix.svg\">\n";
    push @out, "</details>\n";

    if(scalar(@o) > $roundspergraph) {
        push @out, "<details><summary>Full range</summary>\n";
        push @out, "<p>Downsamples the entire set to $numlttb data points.\n";
        push @out, "<img src=\"lt-$filename-$suffix.svg\">\n";
        push @out, "</details>\n";
    }
    if(scalar(@o) > 10) {
        push @out, <<END
<details><summary>Trend</summary>
<p>
 Draws a trend-line for the full range set. The trend is only considered
 statistically significant if the P value is less than 0.05.
END
            ;
            
        push @out, sprintf "Mann-Kendall says: statistically %s (P: %.4f)\n",
            $p_value < 0.05 ? "SIGNIFICANT" : "insignificant",
            $p_value;
        push @out, "<img src=\"tr-$filename-$suffix.svg\">\n";
        push @out, "</details>\n";
    }
    $alltests{$filename} = $name;
    return @out;
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

sub scorecard_limitrate {
    my (@json) = @_;
    my $j = decode_json(join("", @json));
    my $speed = $$j{'downloads'}{'rows'}[0][1]{'val'};
    my $cpu = $$j{'downloads'}{'rows'}[0][1]{'stats'}{'cpu'};
    return (0+$speed, 0+$cpu);
}

sub loadmarkers {
    my ($file) = @_;
    my $name;
    my $date;
    my $desc;
    my $val;
    open(S, "<$file") ||
        die "found no $file";
    my @all = <S>;
    close(S);
    storemarkers("default", @all);
}

sub storemarkers {
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
            $marker{$build, $name, $key} = $val;
        }
    }
}

sub builddetails {
    my ($numrounds) = @_;
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
    my %tag;
    open(G, "<$outdir/git-tags");
    # 400fffa90f (tag: curl-8_17_0)
    while(<G>) {
        if(/^([0-9a-f]+) \(tag: ([^\)]+)/) {
            $tag{$1} = $2;
        }
    }
    close(G);
    print "<details><summary>$numrounds rounds</summary>\n";
    my $index;

    my $oldest = $inorder[0];
    
    for my $c (@log) {
        my $t = $tag{$c}; # if any
        if($t) {
            # Backhand Index Pointing Right Emoji
            printf "<br>&\#x1F449; <a href=\"%s/%s\"><b>$t</b>\n",
                $commitbase, $c;
        }
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

my $firststamp;

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
    my @markers;
    my @h1rate;
    my $git = "";
    my $scan = "";

    # always just keep the latest of these
    undef @curlv;
    undef @confopts;

    while(<F>) {
        if(!$scan && /^(.*) git pull/) {
            $scan = $1;
            $firststamp = $scan if(!$firststamp);
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
        elsif(/^b64enc: Time\/loop: ([0-9.]+) ns/) {
            $b64enc{$scan} = $1;
        }
        elsif(/^b64dec: Time\/loop: ([0-9.]+) ns/) {
            $b64dec{$scan} = $1;
        }
        elsif(/^urlparser: Time\/URL: ([0-9.]+) ns/) {
            $urlparser{$scan} = $1;
        }
        elsif(/^snprintf: Time\/loop: ([0-9.]+) ns/) {
            $snprintf{$scan} = $1;
        }
        elsif(/^urlencode: Time\/loop: ([0-9.]+) ns/) {
            $urlencode{$scan} = $1;
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
        elsif(/^h1rate:(.*)/) {
            push @h1rate, $1;
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
            push @markers, $1;
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

    if($markers[0]) {
        storemarkers($scan, @markers);
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
    if($h1rate[0]) {
        my ($speed, $cpu) = scorecard_limitrate(@h1rate);
        if($speed > $lowspeed) {
            $h1limitrate{$scan} = $speed;
            $h1limitcpu{$scan} = $cpu;
        }
    }
}

# Load the current markers. Each build has its own set.
loadmarkers("stakes.conf");

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

# in number of days:
my $buildperiod= sprintf "%.1f",
    (`date -d "$done" +%s` - `date -d "$firststamp" +%s`) / (3600 * 24);

print <<HEAD
<h1>curl performance tests</h1>

<div style="float: right">
<a href="https://github.com/curl/perf">curl/perf on GitHub</a>
</div>

<details><summary>$numlogs builds</summary>
<table>
<tr><td>First</td><td>$firststamp (local time)</td></tr>
<tr><td>Last</td><td>$done (local time)</td></tr>
<tr><td>Period</td><td>$buildperiod days</td></tr>
<tr><td>Rendered</td><td>$now</td></tr>
</table>
</details>

HEAD
    ;

builddetails($numrounds);

my @output;
my @deltas;

push @output, show("Download speed single transfer HTTP://",
                   "higher",
                   "100G-speed",
                   "bytes/sec", %h1serial);
push @output, show("Allocations for a single HTTP transfer",
                   "lower",
                   "single-numallocs",
                   "allocs", %allocations);
push @output, show("Allocated memory for a single HTTP transfer",
                   "lower",
                   "single-maxalloc",
                   "bytes", %maxalloc);
push @output, show("Download speed parallel HTTP/1",
                   "higher",
                   "h1parallel-speed",
                   "bytes/sec", %h1p);
push @output, show("Download speed parallel HTTP/2",
                   "higher",
                   "h2parallel-speed",
                   "bytes/sec", %h2p);
push @output, show("Download speed parallel HTTP/3",
                   "higher",
                   "h3parallel-speed",
                   "bytes/sec", %h3p);
push @output, show("Memory use for parallel HTTP/1",
                   "lower",
                   "h1parallel-mem",
                   "bytes", %h1pbytes);
push @output, show("Memory use for parallel HTTP/2",
                   "lower",
                   "h2parallel-mem",
                   "bytes", %h2pbytes);
push @output, show("Memory use for parallel HTTP/3",
                   "lower",
                   "h3parallel-mem",
                   "bytes", %h3pbytes);
push @output, show("Upload speed parallel HTTP/1",
                   "higher",
                   "h1parallel-upload-speed",
                   "bytes/sec", %h1pu);
push @output, show("Upload speed parallel HTTP/2",
                   "higher",
                   "h2parallel-upload-speed",
                   "bytes/sec", %h2pu);
push @output, show("Upload speed parallel HTTP/3",
                   "higher",
                   "h3parallel-upload-speed",
                   "bytes/sec", %h3pu);
push @output, show("Memory use for parallel upload HTTP/1",
                   "lower",
                   "h1parallel-upload-mem",
                   "bytes", %h1pubytes);
push @output, show("Memory use for parallel upload HTTP/2",
                   "lower",
                   "h2parallel-upload-mem",
                   "bytes", %h2pubytes);
push @output, show("Memory use for parallel upload HTTP/3",
                   "lower",
                   "h3parallel-upload-mem",
                   "bytes", %h3pubytes);
push @output, show("HTTP/1 parallel requests",
                   "higher",
                   "h1-requests",
                   "requests/sec", %h1r);
push @output, show("HTTP/2 parallel requests",
                   "higher",
                   "h2-requests",
                   "requests/sec", %h2r);
push @output, show("HTTP/3 parallel requests",
                   "higher",
                   "h3-requests",
                   "requests/sec", %h3r);
push @output, show("Memory use for HTTP/1 parallel requests",
                   "lower",
                   "h1-req-mem",
                   "bytes", %h1rbytes);
push @output, show("Memory use for HTTP/2 parallel requests",
                   "lower",
                   "h2-req-mem",
                   "bytes", %h2rbytes);
push @output, show("Memory use for HTTP/3 parallel requests",
                   "lower",
                   "h3-req-mem",
                   "bytes", %h3rbytes);
push @output, show("Curl_easy struct size",
                   "lower",
                   "easy-handle",
                   "bytes", %curleasy) if %curleasy;
push @output, show("Curl_multi struct size",
                   "lower",
                   "multi-handle",
                   "bytes", %curlmulti) if %curlmulti;
push @output, show("connectdata struct size",
                   "lower",
                   "connectdata",
                   "bytes", %connectdata) if %connectdata;
push @output, show("Limit-rate CPU use",
                   "lower",
                   "h1rate-cpu",
                   "CPU%", %h1limitcpu) if %h1limitcpu;
push @output, show("Limit-rate network speed",
                   "exact",
                   "h1rate-speed",
                   "bytes/sec", %h1limitrate) if %h1limitrate;
push @output, show("base64 encoding",
                   "lower",
                   "b64enc",
                   "nanoseconds", %b64enc) if %b64enc;
push @output, show("base64 decoding",
                   "lower",
                   "b64dec",
                   "nanoseconds", %b64dec) if %b64dec;
push @output, show("snprintf",
                   "lower",
                   "snprintf",
                   "nanoseconds", %snprintf) if %snprintf;
push @output, show("URL parsing",
                   "lower",
                   "urlparser",
                   "nanoseconds", %urlparser) if %urlparser;
push @output, show("URL encode-decode",
                   "lower",
                   "urlencode",
                   "nanoseconds", %urlencode) if %urlencode;

printf "<details><summary>%u tests</summary>\n", scalar(%alltests);

for my $t (sort keys %alltests) {
    print "<a href=\"#$t\">$t</a>, ";
}
print "</details>\n";

# show deltas marker vs mean value
my @d;

for my $t (sort {abs($deltas{$b}) <=> abs($deltas{$a})} keys %deltas) {
    if(abs($deltas{$t}) >= $deltathreshold) {
        push @d, sprintf "<tr><td>".
            "<b>%.2f%%</b>".
            "</td><td>".
            "<a href=\"#%s\">%s</a> marker is %s mean".
            "</td></tr>\n",
            $deltas{$t}, $t, $alltests{$t},
            $deltas{$t} < 0 ? "under" : "over";
    }
}
if(@d) {
    printf "<details open><summary>%u deltas over $deltathreshold%% from marker</summary>\n",
        scalar(@d);
    print "<table>\n";
    print @d;
    print "</table>\n";
    print "</details>\n";
}

# show deltas moving average vs std dev
undef @d;

for my $t (sort keys %mdeltas) {
    my ($mav, $std) = split(/;/, $mdeltas{$t});
    if(abs($mav) > $std * 2) {
        push @d, sprintf "<tr><td>".
            "<b>%.2f%%</b>".
            "</td><td>".
            "<a href=\"#%s\">%s</a> is larger than std dev %.2f%%".
            "</td></tr>\n",
            $mav, $t, $alltests{$t}, $std;
    }
}
if(@d) {
    printf "<details open><summary>%u moving averages to watch</summary>\n",
        scalar(@d);
    print "<table>\n";
    print @d;
    print "</table>\n";
    print "</details>\n";
}

print @output;

print "<h3> configure</h3>";
print @confopts;
print "<h3> curl -V</h3>\n";
for my $c (@curlv) {
    print "$c<br>\n";
}
