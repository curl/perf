#!/bin/sh

LOG=`date "+perf-%Y-%m-%d-%H-%M-%S.log"`
PERFDIR=$HOME/src/curl-perf

cd $PERFDIR
CODE=$HOME/src/curl-perf-code
echo "runs single.sh $CODE to $LOG"
./single.sh $CODE $PERFDIR > log/$LOG
echo "now make the HTML"
rm -f out/*
./scan.pl > out/index.html
./tarballit.sh out perf.tar.gz
