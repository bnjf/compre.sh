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
trap 'rm -r "$d"' EXIT

# uuencode stuff {{{

typeset -a uu_table=(
 " " \! \" \# \$ %  \& \' \( \) \* +  \, -  .  /
  0  1  2  3  4  5  6  7  8  9  :  \; \< \= \> \?
  @  A  B  C  D  E  F  G  H  I  J  K  L  M  N  O
  P  Q  R  S  T  U  V  W  X  Y  Z  \[ \\ \] \^ _)
typeset uu_buf=""

uu_begin() {
  echo "begin 644 ${1:?}.Z"
}

# 0: add in>>2, emit.  save (in & 3) << 4 -- 2 bits pending
#    000000 00
# 1: add in>>4, emit.  save (in & 15) << 2 -- 4 bits pending, b_0 complete
#    000000 001111 1111
# 2: add in>>6, emit.  emit (in & 63) -- b_1 and b_2 complete
#    000000 001111 111122 222222

typeset -i uu_state=0
typeset -i uu_carry=0
uu_encode8() {
  while (( $# )); do
    typeset -i in="${1:?}"
    case $uu_state in
    0)  uu_buf+="${uu_table[in >> 2]}"
        : $(( uu_carry = (in & 3) << 4 )) ;;
    1)  uu_buf+="${uu_table[uu_carry | (in >> 4)]}"
        : $(( uu_carry = (in & 15) << 2 )) ;;
    2)  uu_buf+="${uu_table[uu_carry | (in >> 6)]}"
        uu_buf+="${uu_table[in & 63]}"
    esac
    : $(( uu_state = (uu_state + 1) % 3 ))
    shift
  done
}

uu_line() {
  typeset -i len="${1:-}"
  [[ ${#uu_buf} -eq 0 ]] && return 1                        # empty buf
  [[ $len -gt 0 && ${#uu_buf} -lt $len ]] && return 1       # unfulfillable
  if (( len > 0 )); then
    echo "${uu_table[len / 4 * 3]}${uu_buf:0:len}"
    uu_buf="${uu_buf:len}"
  else
    len=${#uu_buf}
    while (( ${#uu_buf} % 4 )); do uu_buf+='`'; done        # pad buf
    echo "len=$len #uu_buf=${#uu_buf} uu_state=$uu_state z=$z" >&2 # XXX
    typeset -i x='((len + 3) / 4 * 3) - ((3 - uu_state) % 3)'
    echo "${uu_table[x]}${uu_buf}"
    uu_buf=""
  fi
  return 0
}

uu_end() {
  # full lines
  while uu_line 60; do :; done

  # commit carry, but preserve state
  if (( uu_state != 0 )); then
    typeset -i uu_state_save=$uu_state
    uu_encode8 0
    uu_state=$uu_state_save
  fi

  # final partial line
  uu_line || true

  # uuencode outro
  echo '`'
  echo 'end'
}

# }}}

typeset -i COMPRESH_BITS="${COMPRESH_BITS:-12}"
(( COMPRESH_BITS > 9 && COMPRESH_BITS <= 16 )) || {
  echo "$0: COMPRESH_BITS range must in [10,16]" >&2; exit 1; }
typeset -i maxe='1 << COMPRESH_BITS'

# init uu
uu_begin "${fi##*/}"
uu_encode8 0x1f 0x9d $(( 0x80 | COMPRESH_BITS ))

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
      uu_encode8 $(( y & 255 ))
      : $(( y >>= 8, z -= 8 ))
    done
  done

  # unbuffer pending lines
  while uu_line 60; do :; done
done < <(od -bv)

# finalize lz
[[ -f e ]] || { echo "$0: i'm lost" >&2; exit 1; }
: $(( y |= ($(<e) << z), z += w ))
while (( z > 0 )); do
  uu_encode8 $(( y & 255 ))
  : $(( y >>= 8, z -= 8 ))
done

# finalize uu
uu_end

# vim:set ts=2 sts=2 sw=2 et ai tw=72 fdm=marker:
