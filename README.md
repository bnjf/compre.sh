# compre.sh

A combined compress(1) and uuencode(1) implementation for bash/ksh

## How does it work?

LZW encoding is a variable bit width dictionary lookup typically done with a
hash keyed by a couple (prev,cur).  I use the filesystem instead to respresent
a trie, with the byte values as directory names, and a single file `e` to store
the dictionary index.

This is not very fast, and it's best to keep the `COMPRESH_BITS` setting low.
If you're patient (and the filesystem is ample), you can try setting it to the
compress(1) default of 16.

Enjoy!

