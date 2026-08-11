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
