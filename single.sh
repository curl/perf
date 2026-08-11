#!/bin/sh

# git checkout directory name provided as argument
CODE="$1"

# directory where the perf code sits
PERFDIR="$2"

PREF="+%F %T"

cd "$CODE"

date "$PREF git pull"
git pull >git.log 2>&1

date "$PREF git describe"
git rev-parse --short HEAD | sed 's/^/git commit: /'

date "$PREF autoreconf -fi"
autoreconf -fi >autoreconf.log 2>&1

date "$PREF make clean"
make clean >makeclean.log 2>&1

date "$PREF configure"
CONFOPTS="--disable-shared --enable-debug --enable-ipv6 --with-gssapi --enable-werror --with-nghttp2 --prefix=$HOME/test-curl-install --with-openssl --with-ngtcp2 --with-nghttp3 --with-libssh2 --with-test-caddy=$HOME/caddy/caddy_linux_amd64 --enable-ssls-export --enable-httpsrr --with-test-nghttpx=$HOME/build-nghttp2/bin/nghttpx --with-backtrace --enable-ntlm --enable-smb --enable-proxy-http3 --enable-httpsig"
./configure $CONFOPTS >configure.log 2>&1
echo "confopts: $CONFOPTS";

date "$PREF make"
make -sj20 >make.log 2>&1

date "$PREF make -C tests"
make -C tests -sj20 >maketests.log 2>&1

date "$PREF curl -V"
./src/curl -V 2>&1 | sed 's/^/curl-V: /'

date "$PREF download 512 MB"
export CURL_MEMDEBUG=curlmem.log
rm "$CURL_MEMDEBUG"
./src/curl -s localhost/512M --out-null

date "$PREF ----- 512 MB download -----"
perl -Itests ./tests/memanalyze.pl -v $CURL_MEMDEBUG | sed 's/^/mem: /'

unset CURL_MEMDEBUG

date "$PREF ----- 100G download -----"
./src/curl -s localhost/100G -w 'bytes/sec: %{speed_download}\ntotal time: %{time_total}\n' --out-null | sed 's/^/100G: /'

date "$PREF ----- h1 parallel -----"
python3 tests/http/scorecard.py -d --download-count=100 --download-parallel=50 --download-sizes=500mb --json h1 2>h1p.log | sed 's/^/h1p: /'

date "$PREF ----- h2 parallel -----"
python3 tests/http/scorecard.py -d --download-count=100 --download-parallel=50 --download-sizes=500mb --json h2 2>h2p.log | sed 's/^/h2p: /'

date "$PREF ----- h3 parallel -----"
python3 tests/http/scorecard.py -d --download-count=100 --download-parallel=50 --download-sizes=500mb --json h3 2>h3p.log | sed 's/^/h3p: /'

date "$PREF ----- h1 parallel upload -----"
python3 tests/http/scorecard.py -u --upload-count=100 --upload-parallel=50 --upload-sizes=500mb --json h1 2>h1pu.log | sed 's/^/h1pu: /'

date "$PREF ----- h2 parallel upload -----"
python3 tests/http/scorecard.py -u --upload-count=100 --upload-parallel=50 --upload-sizes=500mb --json h2 2>h2pu.log | sed 's/^/h2pu: /'

date "$PREF ----- h3 parallel upload -----"
python3 tests/http/scorecard.py -u --upload-count=100 --upload-parallel=50 --upload-sizes=500mb --httpd --json h3 2>h3pu.log | sed 's/^/h3pu: /'

date "$PREF ----- h1 requests -----"
python3 tests/http/scorecard.py -r --request-count=100000 --request-parallel=40 --json h1 | sed 's/^/h1req: /'

date "$PREF ----- h2 requests -----"
python3 tests/http/scorecard.py -r --request-count=100000 --request-parallel=40 --json h2 | sed 's/^/h2req: /'

date "$PREF ----- h3 requests -----"
python3 tests/http/scorecard.py -r --request-count=100000 --request-parallel=40 --json h3 | sed 's/^/h3req: /'

# Remember the stakes when this ran
cat $PERFDIR/stakes.conf | sed 's/^/stakes: /'
date "$PREF done"
