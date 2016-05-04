#!/bin/bash
# Prepare the input.
TEMPFILES=()
trap 'for TEMPFILE in "${TEMPFILES[@]}"; do rm $TEMPFILE; done' EXIT
for FILE in "${@:3}"; do
  TEMP=`mktemp`
  TEMPFILES+=($TEMP)
  <"$FILE" midicsv >$TEMP #| awk '{ print i++ " " $0; }' | sort -n -k 3
done

# Execute the script.
./markov-chain.lua "$1" "$2" "${TEMPFILES[@]}" # | grep . | sort -n -k 1 | sed 's/^[^ ]* //'
