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
  P  Q  R  S  T  U  V  W  X  Y  Z  \[ \\ \] \^ _
)
typeset -a uu_q
typeset uu_buf=""
uu_begin() { echo "begin 644 ${1:?}.Z"; }
uu_end() { echo '`'; echo 'end'; }
uu_line() {
  [[ ${#uu_buf} -eq 0 ]] ||
    echo "${uu_table[${#uu_buf} / 4 * 3]}${uu_buf}"
}
uu_encode8() {
  set -- "${uu_q[@]}" "$@"
  while (( $# >= 3 || ($# > 0 && "${1:-0}" < 0) )); do
    typeset -i b0="$1" b1="$2" b2="$3"

    if (( b0 < 0 )); then
      uu_line
      return
    elif (( b1 < 0 )); then
      uu_line
      echo "${uu_table[1
        ]}${uu_table[b0 / 4
        ]}${uu_table[((b0 * 16) % 64) + (b1 / 16)]}\`\`"
      return
    elif (( b2 < 0 )); then
      uu_line
      echo "${uu_table[2
        ]}${uu_table[b0 / 4
        ]}${uu_table[((b0 * 16) % 64) + (b1 / 16)
        ]}${uu_table[((b1 % 16) * 4)]}\`"
      return
    fi

    uu_buf+="${uu_table[b0 / 4]}"
    uu_buf+="${uu_table[((b0 * 16) % 64) + (b1 / 16)]}"
    uu_buf+="${uu_table[((b1 % 16) * 4) + (b2 / 64)]}"
    uu_buf+="${uu_table[b2 % 64]}"

    if [[ ${#uu_buf} -ge 60 ]]; then
      echo "${uu_table[45]}${uu_buf:0:60}"
      uu_buf="${uu_buf:60}"
    fi

    shift 3
  done

  # save the rest
  uu_q=("$@")
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
done < <(od -bv)

# finalize lz
[[ -f e ]] || { echo "$0: i'm lost" >&2; exit 1; }
: $(( y |= ($(<e) << z), z += w ))
while (( z >= 0 )); do
  uu_encode8 $(( y & 255 ))
  : $(( y >>= 8, z -= 8 ))
done

# finalize uu
uu_encode8 -1 -1                # pad up for incomplete bytes
uu_end

# vim:set ts=2 sts=2 sw=2 et ai tw=72 fdm=marker:
