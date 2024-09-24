# Runerip

This is a small library which implements a UTF-8 validator and decoder.  The algorithm is [prior art](https://bjoern.hoehrmann.de/utf-8/decoder/dfa/), and being curious about these things, I decided to implement it in Zig and see what happens.

### Runes

Some might have noticed my habit of referring to what the Unicode consortium calls a 'scalar value' as runes.  This is habitual, and canonical, in Go language circles, but scarce elsewhere (Odin also does so).  What's up with that?

Consider the alternatives!  Scalar value, while official, also smells like it.  Originally Unicode used "character", but that is unsuitable several times over: some runes are not characters in any reasonable sense, while many perceived characters are comprised of several runes.  `wchar` carries considerable baggage, usually signalling that the broken UCS-2 encoding is assumed by such a program.  Even something like 'glyph' doesn't fit the bill, having an established meaning in text rendering which is sure to collide with using it for the atomic unit of text itself.

`rune` then, while a bit whimsical, is a clear and _short_ (especially, short) term for a scalar value.  Although Go is the only large community of practice to use it at present, it is one of the first terms ever used for what it is.  The coinage is from Plan 9, where UTF-8 was designed and first implemented, and it is mainly as an homage to that invention that I use the word.  Generally inventing something comes with the privilege of naming it, at least, until Microsoft gets involved.

It's also handy that the term is a bit semantically vague about the precise encoding standards the value may or may not conform to.  This reflects the reality of working with Unicode text.

## Benchmarks

The demo/ folder has four benchmark executables for both `runerip` and `std.unicode`, for counting, validation, decoding, and transcoding.  The `-sum` programs decode, and sum the codepoint values together, to encourage the optimizer not to eliminate the work.  Each runs 10_000 cycles to prevent startup from dominating the metric: tweaking this number shows that the compiler is not taking the opportunity to run a cycle once and multiply by 10_000, which it technically could.

All benchmarks are run on an M1 Max chip running macOS Sonoma, I would welcome benchmarks from other systems to get a better comparison.  Each is run with [hyperfine](https://github.com/sharkdp/hyperfine) using `--warmup 5 --shell=none`, and is reported as the mean of three runs, which invariably differ by a less than 1% deviation from the average.  Hyperfine warns when any run takes unusual time due to OS interference, any warned benchmark was discarded.

All times are in milliseconds.

| Benchmark | std.unicode | runerip | Factor |
|-----------|-------------|---------|--------|
| Validate  | 111.3       | 73.7    | 1.51x  |
| Count     | 206.7       | 72.0    | 1.86x  |
| Decode    | 204.2       | 98.0    | 2.08x  |
| Transcode | 329.8       | 145.3   | 2.27x  |

Results for WTF-8 variants are not yet available, my guess is that they will differ very little.  It's noteworthy that the fastest `std` implementation, the validator, also uses a quite similar DFA internally.

## Considerations

Overall, I believe the speed gains here are real.  This comes at a modest cost, needing 376 bytes for the lookup tables, making this technique less suitable for embedded or otherwise highly constrained systems.  It's at least possible that the relative simplicity of the algorithm results in a net-smaller binary size, this is not something I've cared to confirm one way or the other.

For the test data, the optimizations in std which favor ASCII are largely not realized in gains.  I tried adding them to `runerip` to no effect, but then again, the sample data is not ASCII-dominated, and many real texts of interest (Zig source code is a noteworthy example) are so dominated.  Of course, these optimizations may be added to a `runerip` implementation as well, my thinking is that it wouldn't be excessive to have e.g. `utf8CountCodepointsExpectAscii` for use when multibyte runes are expected to be rare.  It may also be the case that unilaterally including them has no negative impact on use cases with minimal ASCII, this is an empirical question which can only be answered with more sample data.

I did my level best to make a fair comparison, in the subset of Unicode tasks which are so far deployed.  The `runerip` DFA doesn't offer an obvious way, unlike the standard approach, to signal what sort of ill-formed data is encountered, and it throws on the offset where a sequence is determined to be ill-formed, despite that sometimes several preceding bytes are found invalid in the process.  That behavior is slightly different from the standard library, but is most compatible with Substitution of Maximal Subparts per Section 3.9 of the Unicode Standard.

This is not a durable disadvantage, as I see it, for a few reasons.  One is that caring about the specifics of how a validation fails is rare, in comparison to taking some useful action in the face of failure.  One example of taking action is to issue a replacement character instead of the bad bytes, and the original implementation has a couple approaches there which I'll get around to adding eventually.  Finally, it would not be difficult to add a relatively-slow-path fixup step which identifies the problem category in more detail, and this should have no impact on the speed of the happy path.

Basically, there are many approaches to coping with invalid sequences, and it all depends on the task at hand.  The basic approach here is compatible with any of those, including that taken by the standard library.

An additional strength of the `runerip` approach (which is, to be clear, the Björn Hörhmann approach) is that it generalizes well.  Creating additional DFA tables to match e.g. WTF-8 instead of UTF-8 is a simple matter.  Zig source code is a subset of UTF-8 which disallows most C0 control bytes, and _should_, but at the moment does not, disallow C1 sequences as well.  This too is a matter of adjusting the DFAs involved to reject those when encountered, and `runerip` contains an (as yet untested) implementation of this.

`runerip` is an experiment, a proof of concept.  If anyone should care to run the demos, and report back if timings are materially different on other architectures and systems, I would be delighted to hear about it.  As I find time, I expect I'll polish the rough edges, and add a few more functions to the collection.

