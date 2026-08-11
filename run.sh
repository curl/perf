#!/bin/sh

LOG=`date "+perf-%Y-%m-%d-%H-%M-%S.log"`
cd $HOME/src/curl-perf

CODE=$HOME/src/curl-perf-code
echo "runs single.sh $CODE to $LOG"
./single.sh $CODE > log/$LOG
