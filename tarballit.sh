#!/bin/sh

DIR="$1"
FILENAME="$2"

(cd "$DIR" && tar czf ../$FILENAME.tmp *)
mv $FILENAME.tmp $FILENAME
