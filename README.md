This tool cuts input MID files into tracks, feeds these track to a Markov chain, and generates a new random track.

# Requirements

The script relies on Bash, Lua 5.2.4, and the `midicsv` package that provides the `midicsv` and `csvmidi` binaries for the conversion of MID files to CSV and vise-versa.

# Usage

Run the `markov-chain.sh` script as follows:

    ./markov-chain.sh {LEFT_CONTEXT|-} {MAX_OUTPUT_LENGTH|-} {DAMPING|-} MID_FILE[=TRACKS] [MID_FILE[=TRACKS] ...]

where:

  * `LEFT_CONTEXT` stands for the number of previous lines that are kept as the left context when building the Markov chain. *(Default: 3)*
  * `MAX_OUTPUT_LENGTH` specifies the number of lines after which the output is cut off. *(Default: Infinity)*
  * `DAMPING` specifies the damping factor. `1-DAMPING` the probability of the random walker moving to a completely random node. *(Default: 1)*
  * `MID_FILE` stand for the input files,
  * `TRACKS` are used to specify the MIDI tracks to use from the given input file and use the following syntax:

        <root>  ::=  <expr> | '*'
        <expr>  ::=  <expr>,<expr> | <range> | <atom>
        <range> ::=  <atom>-<atom>
        <atom>  ::=  [0-9]+

The script dumps the generated song to the `track.csv` CSV file accepted by the `csvmidi` binary, and to the stdout as a MID file.
