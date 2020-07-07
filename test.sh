#!/bin/sh

set -eu

sh=ksh

#for f in corpus/progc; do
#for f in corpus/obj; do
id=1
for f in corpus/*; do
  sha256sum $f | {
    read d f
    # need patched ncompress to test 9
    # https://github.com/vapier/ncompress/issues/5
    for b in 9 10 11 12 13 14 15 16; do
    #for b in 10 11 12; do
      echo "testing f=$f b=$b "
      #TIME="(%E real, %U user, %S sys)$(tput sc)" time \
      env COMPRESH_BITS=$b $sh ./compre.sh - < $f |
        pv -tab |
        tee "f=$(basename $f)_b=$b.out" |
        uudecode -o - |
        ncompress -d |
        sha256sum | {
          read td tf
          [ "$d" = "$td" ] || { echo "failed ($d vs $td)"; exit 1; }
          rm "f=$(basename $f)_b=$b.out"
        }
      echo "\tOK!"
    done
  }
done
