#!/bin/bash
# Prepare the input.
TEMPFILES=()
trap 'for TEMPFILE in "${TEMPFILES[@]}"; do rm $TEMPFILE; done' EXIT
for ARG in "${@:3}"; do
  FILE="`  sed    's/=[^=]*//' <<<"$ARG"`"
  RANGES="`sed -n 's/.*=/=/p'  <<<"$ARG"`"
  TEMP=`mktemp`
  TEMPFILES+=($TEMP)
  ARGS+=($TEMP"$RANGES")
  <"$FILE" midicsv >$TEMP
done

# Execute the script.
./markov-chain.lua "$1" "$2" "${ARGS[@]}" | tee track.csv | csvmidi
