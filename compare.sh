#!/bin/sh

id=$1

cat <<EOF
<html>
<a href="./index.html">Back to index</a>
<h1>Compare metrics between protocol versions</h1>
EOF

for which in cpu speed mem; do

  files="out/0-ftps-parallel-$which.csv out/0-h1parallel-$which.csv out/0-h2parallel-$which.csv out/0-h3parallel-$which.csv"
  common=$(cat $files | cut '-d;' -f2 | sort | uniq -c | grep '4 R' | awk '{ print $2}')

  genfiles="out/0-h1parallel-$which.csv.compare out/0-h2parallel-$which.csv.compare out/0-h3parallel-$which.csv.compare out/0-ftps-parallel-$which.csv.compare"
  rm -f $genfiles

cat <<EOF
<h2>$which</h2>
EOF

  for p in ftps h1 h2 h3; do
    echo "<a href=\"index.html#$p-parallel-$which\">$p<a>, "
  done

  for f in $files; do
    count="0"
    for c in $common; do
      grep ";$c;" $f | cut "-d;" -f2- | sed "s/^/$count;/" >> $f.compare
      count=$(expr $count + 1)
    done
  done
  gnuplot -c 4plots.plot $genfiles > "out/compare-$which-$id.svg"
  echo "<img src=\"compare-$which-$id.svg\">"
done

cat <<EOF
</html>
EOF
