# Runerip

This is a small library which implements a UTF-8 validator and decoder.  The algorithm is [prior art](https://bjoern.hoehrmann.de/utf-8/decoder/dfa/), and being curious about these things, I decided to implement it in Zig and see what happens.

## Benchmarks

The library is in an initial state, offering validation, counting of runes, and an iterating decoder for same.  Other functionality is contemplated, and some exists in stub form, but would need polishing up.

The demo section of the repo has a short [demo text](demo/utf-8-demo.txt), which is built into six test programs, one each of runerip and the standard library, for three applications of interest.  Tests were performed with [hyperfine](https://github.com/sharkdp/hyperfine) on an M1 Max running macOS Sonoma.

The first tests counts codepoints.  On this test, `runerip` is comfortably faster than the standard library, on the order of 2.3-2.4X.

The second test decodes codepoints, summing them together to convince the optimizer to include the decoding.  Here `runerip` also does well, on the order of 2x faster than standard.

The third test simply validates that the string is UTF-8, and here, the standard library ekes out a victory, with `runerip` about 0.9x as fast.  Zig std uses a[highly tuned implementation](https://ziglang.org/documentation/master/std/#std.unicode.utf8ValidateSliceImpl) for this task, including its own lookup DFA.  The `runerip` algorithm is exceedingly simple in comparison, but not in any useful or advantageous way.

## Considerations

Overall, I believe the speed gains here are real, and would apply to other tasks not yet implemented, such as transcoding to UTF-16.  This comes at a modest cost, needing 376 bytes for the lookup tables, making this technique less suitable for embedded or otherwise highly constrained systems.

For the test data, the optimizations in std which favor ASCII are largely not realized in gains.  I tried adding them to `runerip` to no effect, but then again, the sample data is not ASCII-dominated, and many real texts of interest (Zig source code is a noteworthy example) are so dominated.  Of course, these optimizations may be added to a `runerip` implementation as well, my thinking is that it wouldn't be excessive to have e.g. `utf8CountCodepointsExpectAscii` for use when multibyte runes are expected to be rare.  It may also be the case that unilaterally including them has no negative impact on use cases with minimal ASCII, this is an empirical question which can only be answered with more sample data.

I did my level best to make a fair comparison, in the subset of Unicode tasks which are so far deployed.  The `runerip` DFA doesn't offer an obvious way, unlike the standard approach, to signal what sort of ill-formed data is encountered, and it throws on the offset where a sequence is determined to be ill-formed, despite that sometimes several preceding bytes are found invalid in the process.

This is not a durable disadvantage, as I see it, for a few reasons.  One is that caring about the specifics of how a validation fails is rare, in comparison to taking some useful action in the face of failure.  One example of taking action is to issue a replacement character instead of the bad bytes, and the original implementation has a couple approaches there which I'll get around to adding eventually.  Finally, it would not be difficult to add a relatively-slow-path fixup step which identifies the problem category in more detail, and this should have no impact on the speed of the happy path.

Basically, there are many approaches to coping with invalid sequences, and it all depends on the task at hand.  The basic approach here is compatible with any of those, including that taken by the standard library.

An additional strength of the `runerip` approach (which is, to be clear, the Björn Hörhmann approach) is that it generalizes well.  Creating additional DFA tables to match e.g. WTF-8 instead of UTF-8 is a simple matter.  Zig source code is a subset of UTF-8 which disallows most C0 control bytes, and _should_, but at the moment does not, disallow C1 sequences as well.  This too is a simple matter of adjusting the DFAs involved to reject those when encountered.

As it stands, `runerip` is an experiment, a proof of concept.  If anyone should care to run the demos, and report back if timings are materially different on other architectures and systems, I would be delighted to hear about it.  As I find time, I expect I'll polish the rough edges, and add a few more functions to the collection.
