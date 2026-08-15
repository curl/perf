#!/bin/sh

LOG=`date "+perf-%Y-%m-%d-%H-%M-%S.log"`
PERFDIR=$HOME/src/curl-perf
CODE=$HOME/src/curl-perf-code

cd $PERFDIR

echo "update curl/perf"
git pull --quiet

echo "runs single.sh $CODE to $LOG"

./single.sh $CODE $PERFDIR > log/$LOG
echo "now make the HTML"
rm -f out/*
(cd $CODE && git log --oneline --no-decorate -400) > out/git-hashes
./scan.pl > out/index.html
./tarballit.sh out perf.tar.gz
