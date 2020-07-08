#!/bin/bash

##
# uuencode(1) and compress(1) in one
#
# pass env COMPRESH_BITS to set a different dict size
#
# brad forschinger, 2020

set -eu

fi="${1:?"Usage: $0 filename"}"
d="$(mktemp -d)" || exit 1
trap 'rm -r -- "$d" &' EXIT

# uuencode stuff {{{

typeset uu_buf=""
typeset -a uu_table=(
 " " \! \" \# \$ %  \& \' \( \) \* +  \, -  .  /
  0  1  2  3  4  5  6  7  8  9  :  \; \< \= \> \?
  @  A  B  C  D  E  F  G  H  I  J  K  L  M  N  O
  P  Q  R  S  T  U  V  W  X  Y  Z  \[ \\ \] \^ _)
typeset -i uu_state=0
typeset -i uu_carry=0

uu_begin() {
  # uuencode prologue
  echo "begin 644 ${1:?}.Z"
}

uu_encodeb() {
  while (( $# )); do
    typeset -i in="${1:?}"
    case $uu_state in
    0)  : $(( uu_carry = in, uu_state = 1 )) ;;
    1)  uu_buf+="${uu_table[uu_carry >> 2]}"
        uu_buf+="${uu_table[((uu_carry & 3) << 4) | (in >> 4)]}"
        : $(( uu_carry = (in & 15) << 2, uu_state = 2 )) ;;
    2)  uu_buf+="${uu_table[uu_carry | (in >> 6)]}"
        uu_buf+="${uu_table[in & 63]}"
        : $(( uu_state = 0 ))
    esac
    shift
  done
}

uu_line() {
  typeset -i len="$1"
  (( len == 0 || len % 4 || len > ${#uu_buf} )) && return 1
  echo "${uu_table[len / 4 * 3]}${uu_buf:0:len}"
  uu_buf="${uu_buf:len}"
}

uu_end() {
  # full lines, if we can
  while uu_line 60; do :; done

  # commit any remaining bits, emit final line
  typeset -i len=${#uu_buf}
  uu_encodeb 0
  typeset -i x="(len / 4) + (len % 2) + (${#uu_buf} / 2)"
  if (( x > 0 )); then
    (( ${#uu_buf} % 4 == 0 )) || uu_buf+='``'
    echo "${uu_table[x]}${uu_buf}"
    uu_buf=""
  fi

  # uuencode epilogue
  echo '`'
  echo 'end'
}

# }}}

typeset -i COMPRESH_BITS="${COMPRESH_BITS:-12}"
(( COMPRESH_BITS >= 9 && COMPRESH_BITS <= 16 )) || {
  echo "$0: COMPRESH_BITS range must in [9,16]" >&2; exit 1; }
typeset -i maxe='1 << COMPRESH_BITS'

# init uu
uu_begin "${fi##*/}"
uu_encodeb 0x1f 0x9d $(( 0x80 | COMPRESH_BITS ))

# init lz.  lzw has a predefined dict with all bytes, compress(1)
# reserves 257 for `clear`.
cd "$d"
typeset -i e=-1
while (( ++e < 257 )); do
  mkdir "$e"
  echo "$e" > "$e/e"
done

# x: cur byte, y: bit vec; z: offset into y; w: dict width
typeset -i x=0
typeset -i y=0 z=0 w=9
while read addr line; do
  for byte in $line; do
    # explicitly convert from octal
    : $(( x=8#$byte ))

    # seen byte prefix?  descend and get next byte
    cd "$x" 2>/dev/null && continue

    # otherwise it's a new entry, if we're not blocking
    if (( e < maxe )); then
      mkdir "$x" 2>/dev/null
      echo "$((e++))" > "$x/e"
    fi

    # encode dict key, incr width if key is 2^n+1
    : $((
      y |= ($(<e) << z),
      z += w,
      e < maxe && (
        (e - 1) & (e - 2) || w++) ))
    cd "$d/$x"

    # queue any bytes
    while (( z >= 8 )); do
      uu_encodeb $(( y & 255 ))
      : $(( y >>= 8, z -= 8 ))
    done

  done

  # unbuffer pending lines
  while uu_line 60; do :; done
done < <(od -bv)

# finalize lz
[[ -f e ]] || { echo "$0: i'm lost" >&2; exit 1; }
: $(( y |= ($(<e) << z), z += w ))
while (( z >= 0 )); do
  uu_encodeb $(( y & 255 ))
  : $(( y >>= 8, z -= 8 ))
done

# finalize uu
uu_end

# vim:set ts=2 sts=2 sw=2 et ai tw=72 fdm=marker:
