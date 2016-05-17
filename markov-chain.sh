#!/bin/bash
# Prepare the input.
TEMPFILES=()
trap 'for TEMPFILE in "${TEMPFILES[@]}"; do rm $TEMPFILE; done' EXIT
for ARG in "${@:6}"; do
  FILE="`sed -e 's/^[^~]*~//' -e 's/=[^=]*$//' <<<"$ARG"`"
  RANGES="`sed -n 's/.*=/=/p' <<<"$ARG"`"
  WEIGHT="`sed -n 's/~.*/~/p' <<<"$ARG"`"
  TEMP=`mktemp`
  TEMPFILES+=($TEMP)
  ARGS+=("$WEIGHT"$TEMP"$RANGES")
  <"$FILE" midicsv >$TEMP
done

# Execute the script.
./markov-chain.lua "${@:1:5}" "${ARGS[@]}" | tee track.csv | csvmidi
