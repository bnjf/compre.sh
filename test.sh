#!/bin/sh

set -eu

#for f in corpus/progc; do
#for f in corpus/obj; do
for f in corpus/*; do
  sha256sum $f
  for b in 10 11 12; do
    env COMPRESH_BITS=$b ksh ./compre.sh - < $f |
      (uudecode -o - | gunzip -d | sha256sum)
  done
done
