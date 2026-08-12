# perf

Run performance measurements regularly.

## Single

A single *round* updates from git, runs autoreconf -fi, make clean, configue,
make, builds the test suite and then runs a bunch of tests a logs the output.

Each round is logged in a single file in `log/`.

## Scan

The `scan.pl` file scans through all available logs and generates output HTML
and SVG images.

The file is designed to allow single tests to have failed or to be missing in
the logs. It uses the data it has for each particular section.

All output is generated in the `out/` directory.

## `graph.plot`

This is the gnuplot file used for the graph for each section.

## `horizontal.plot`

This is the gnuplot file used for the visualization of the percentile
distribution.

## Dependencies

This needs all the tools to build curl from source and the pytests scorecard
tests (Apache httpd, httpx and Caddy). It also needs perl and gnuplot.

## Install

git clone the curl source into a directory dedicated for this purpose.

Make sure `run.sh` can be invoked from a cronjob. Edit it to call `single.sh`
with the correct paths.

## Stakes

The *stakes* as set in `stakes.conf` are highly machine and build specific so
they should be set to suitable values per environment.

The stakes are embedded into each build log, so updates should not affect past
runs.

# Data

For each test, lots of data is displayed:

- "higher/lower is better" - explains which direction is the ideal
- it explains the unit of the measurement and in the graph below
- "N samples" is how many builds of the entire set that contributed
  to this test data

Then follows a little table:

- *P0* - the lowest value of all. The minimum.
- *P25* - the 25th percentile. In the sorted list of data, it marks the 1/4
  point, meaning 25% of the values are lower or equal, and 75% of the values
  are higher.
- *P50* - the median value. 50% of the values are lower, 50% are higher.
- *P75* - the 75th percentile.
- *P100* - the largest value of all. The maximum.
- *Average* - average value based on all samples
- *Std dev* - standard deviation. Measures the amount of variation of the
  values.
- *Span* - Half the delta between *P100* and *P0* and how big portion of
  *average* that value is.

To help us use performance testing over time, where we might *gradually* slow
down or speed up or we might reset the logs and need to start over, we have
set "ideal" or "typical" values for each test. They are called **stakes**.
Stakes are set manually based on previous runs. They might need to get
adjusted as we change code and alter conditions.

Each stake has a date field and a comment, they are shown.
Then the stake is displayed.

A *delta* from the stake to the *average* is shown and a helper that explains
if the delta shows the current average as better or worse compared to the
stake.

A second *delta* from the stake to the *median* (P50) is shown and a helper
that explains if the delta shows the current median as better or worse
compared to the stake.

# Graphs

## Main data development graph

The graphs gather data from many builds. Several builds may have been done
based on the same commit. The data from all builds for each commit is
accumulated and the *median*, *minimum* and *maximum* values are put into the
graph.

There are three additional plots in the graph:

- *average* is the average value taken from all builds in the set
- *stake* is the predetermined (ideal) value to compare against for this test
- *moving average* is the average value of the 4 latest commits' (median)
  values

The leftmost datapoint is the oldest commit. Later ones move to the right.

The Y axis unit depends on the specific test. Read the description.

The X axis are the different commits. The commits are shown as `C[number]`. At
the top of the page there are direct links for each commit.

## Data distribution graph

The second graph per test illustrates the data distribution. The leftmost
vertical bar is P0, the blue box is marked from P25 to P75 and the rightmost
vertical bar is P100.

The *average* and *median* values are marked as green and red vertical
markers.
