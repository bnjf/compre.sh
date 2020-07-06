#!/bin/sh

set -eu

sh=ksh

#for f in corpus/progc; do
#for f in corpus/obj; do
for f in corpus/*; do
  sha256sum $f | {
    read d f
    for b in 10 11 12; do
      echo -n "f=$f b=$b "
      TIME="\t%E real,\t%U user,\t%S sys" time \
        env COMPRESH_BITS=$b $sh ./compre.sh - < $f |
        tee "f=$(basename $f)_b=$b.out" |
        uudecode -o - |
        gunzip -d |
        sha256sum | {
          read td tf
          [ "$d" = "$td" ] || { echo "failed ($d vs $td)"; exit 1; }
          rm "f=$(basename $f)_b=$b.out"
        }
      echo "ok"
    done
  }
done
