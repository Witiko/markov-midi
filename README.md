This tool cuts input standard MIDI files into tracks, feeds these track to a Markov chain, and generates a new random track.

# Requirements

The script relies on Bash, Lua 5.2, and the `midicsv` package that provides the `midicsv` and `csvmidi` binaries for the conversion of standard MIDI files to CSV and vise-versa.

# Usage

Run the `markov-chain.sh` script as follows:

    ./markov-chain.sh {LEFT_CONTEXT|-} {MAX_OUTPUT_LENGTH|-} {DAMPING|-} {DAMPING_OPTIONS|-} [WEIGHT~]MID_FILE[=TRACKS] [...]

where:

* `LEFT_CONTEXT` stands for the number of previous MIDI commands that are kept as the left context when building the Markov chain. *(Default: 3)*
* `MAX_OUTPUT_LENGTH` specifies the number of lines after which the output is cut off. *(Default: Infinity)*
* `DAMPING` specifies the damping factor. `1-DAMPING` is the probability that the random walker will move to a completely random node. *(Default: 1)*
* `DAMPING_OPTIONS` specifies how the random transition table will be build. *(Default: mul:add:0+1,0+1,0+1,0+1)* The parameter uses the following syntax:
  
        {NOTE_ON_REDUCE|-}[:{NOTE_ONS_REDUCE|-}[:[{DELAY_ADD|-}+]{DELAY_COEFF|-}[,[{CHANNEL_ADD|-}+]{CHANNEL_COEFF|-}[,[{NOTE_ADD|-}+]{NOTE_COEFF|-}[,[{VELOCITY_ADD|-}+]{VELOCITY_COEFF|-}]]]]]

    where `NOTE_ON_REDUCE` and `NOTE_ONS_REDUCE` can equal `add`, `mul`, `min`, or `max` and the others are floating-point numbers.
  
  When building the table, every pair of vertices inside the Markov chain is considered: 

  1. The context strings of these vertices are interpreted as arrays `A, B` of MIDI messages and these arrays are filtered, so that only `Note_on_c` messages are left.
  2. If one of the arrays is longer, its head gets cut off, so that the arrays are the same length. 
  3. Consider now a two-tuple `V = { (A[0], B[0]), (A[1], B[1]), …, (A[N], B[N]) }`. Each two-tuple `(A[I], B[I])` of `Note_on_c` messages from the arrays is assigned a number that measures their similarity using the formula
    
          f(A[I], B[I]) = reduce(NOTE_ON_REDUCE, { DELAY_ADD + DELAY_COEFF * DELAY_SIMILARITY(A[I], B[I]), CHANNEL_ADD + CHANNEL_COEFF * CHANNEL_SIMILARITY(A[I], B[I]), NOTE_ADD + NOTE_COEFF * NOTE_SIMILARITY(A[I], B[I]), VELOCITY_ADD + VELOCITY_COEFF * VELOCITY_SIMILARITY(A[I], B[I]) })
        
      where the `*_SIMILARITY` functions are squared distances for `DELAY`, `NOTE`, and `VELOCITY` that are clamped to `<0;1>`, and `CHANNEL_SIMILARITY` is either `1` or `0` depending on whether the channel of the two `Note_on_c` messages matches.
  4. The `N` similarity numbers are then reduced to a single number using the formula `f(V) = reduce(NOTE_ONS_REDUCE, { f(A[0], B[0]), f(A[1], B[1]), …, f(A[N], B[N]) })`.
  5. `f(V)` gets normalized, so that if there exists a `V`, such that `f(V) > 0`, then `max f(V) = 1`.
* `MID_FILE` is the pathname to an input standard MIDI file. If the input file names contain `~` or `=`, you will need to explicitly specify `1~MID_FILE=*` to prevent misparsing.
* `WEIGHT` how much weight will the specified tracks from the song carry within the produced Markov chain. *(Default: 1)*
* `TRACKS` are used to specify the MIDI tracks to use from the given input file. *(Default: *)*. The parameter uses the following syntax:

        <root>  ::=  <expr> | '*'
        <expr>  ::=  <expr>,<expr> | <range> | <atom>
        <range> ::=  <atom>-<atom>
        <atom>  ::=  [0-9]+

The script dumps the generated song to the `track.csv` CSV file accepted by the `csvmidi` binary, and to the stdout as a standard MIDI file.

# License

MIT
