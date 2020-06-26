#!/bin/bash

# vim:set ts=2 sts=2 sw=2 et ai tw=60 fdm=marker:

set -eu

fi="$(realpath -e "${1:?}")" || exit 1
fo="$(mktemp "$fi".XXXXXXXXXX)" || exit 1
d="$(mktemp -d)" || exit 1
trap 'cd; rm "$fo"; rm -r "$d"' EXIT
exec 1>"$fo"

# uuencode stuff {{{
uu_table=(
 " " \! \" \# \$ %  \& \' \( \) \* +  \, -  .  /
  0  1  2  3  4  5  6  7  8  9  :  \; \< \= \> \?
  @  A  B  C  D  E  F  G  H  I  J  K  L  M  N  O
  P  Q  R  S  T  U  V  W  X  Y  Z  \[ \\ \] \^ _
)
uu_begin() { echo "begin 644 ${1:--}.Z"; }
uu_end() { echo '`'; echo 'end'; }
uu_encode3() {
  typeset -i x=${1:-0} y=${2:-0} z=${3:-0}
  uu_out+="${uu_table[x / 4
    ]}${uu_table[   ((x * 16)      + (y / 16)) % 64
    ]}${uu_table[  (((y % 16) * 4) + (z / 64)) % 64
    ]}${uu_table[     z % 64]}"
}
uu_line() {
  echo "${uu_table[$#]}$(
    uu_out=""
    while [[ $# -gt 0 ]]; do
      uu_encode3 $1 ${2:-0} ${3:-0}
      shift $(( $# < 3 ? $# : 3 ))
    done
    echo "$uu_out")"
}
# }}}

uu_begin "${fi##*/}"

cd "$d"
typeset -i e=0
while (( e++ < 256 )); do
  mkdir "$e"
  echo "$e" > "$e/e"
done

declare -i uu_buf=(0x1f 0x9d)         # compress(1) magic
declare -i BITS=12
uu_buf+=($(( 0x80 | BITS )))          # 0x80 block mode
declare -i maxe='1 << BITS'

# x: cur byte, y: bit vec; z: offset into y; w: dict width
typeset -i x=0
typeset -i y=0 z=0 w=9
while read addr line; do
  for x in $line; do
    # explicitly convert from octal
    let x="8#$x"

    # seen byte prefix?  descend and get next byte
    cd "$x" 2>/dev/null && continue

    # otherwise it's a new entry, if we're not blocked
    if (( e < maxe )); then
      mkdir "$x" 2>/dev/null
      echo "$((e++))" > "$x/e"
    fi

    # encode dict key, inc width if key is 2^n+1
    : $((
      y |= ($(<e) << z),
      z += w,
      e < maxe && (
        (e - 1) & (e - 2) || w++) ))
    cd "$d/$x"

    # if there's a byte available, take it
    while (( z >= 8 )); do
      uu_buf+=($(( y % 256 )))
      : $(( y /= 256, z -= 8 ))
    done
  done

  # encode a line (45 bytes, 60 encoded)
  while [[ "${#uu_buf[@]}" -ge 45 ]]; do
    uu_line "${uu_buf[@]:0:45}"
    uu_buf=("${uu_buf[@]:45}")        # slice
  done
done < <(od -bv "$fi")

# finalize
: $(( y |= ($(<e) << z), z += w ))
while (( z > 0 )); do
  uu_buf+=($(( y % 256 )))
  : $(( y /= 256, z -= 8 ))
done
uu_line "${uu_buf[@]}"
uu_end

# done
ln "$fo" "$fi".Z.uue
