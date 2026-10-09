#!/bin/sh

LOG=`date "+perf-%Y-%m-%d-%H-%M-%S.log"`
PERFDIR=$HOME/src/curl-perf
CODE=$HOME/src/curl-perf-code
DAYS=60
LOGDIR=log

cd $PERFDIR

echo "update curl/perf"
git pull --quiet

echo "clean out perf runs older than $DAYS"
find "$LOGDIR/" -type f -ctime +$DAYS -delete

echo "runs single.sh $CODE to $LOGDIR"

./single.sh $CODE $PERFDIR > $LOGDIR/$LOG
echo "now make the HTML"
rm -f out/*
(cd $CODE && git "$LOGDIR" --oneline --no-decorate --since '62 days') > out/git-hashes
(cd $CODE && git "$LOGDIR" --no-walk --tags --format=%h%d) | head -20  > out/git-tags
./scan.pl > out/index.html
./tarballit.sh out perf.tar.gz
