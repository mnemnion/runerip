//! Runerip: Fast Scalar Value Decoder
//!
//! The `runerip` library provides a decoder for UTF-8, translating a
//! stream of bytes into runes.
//!
//! Historical note: while the term 'rune' in modern parlance is a bit
//! peculiar to Go, it was originally peculiar to Plan 9, an innovative
//! research OS planned as a successor to Unix.  Plan 9 is also where
//! UTF-8 itself was designed, and first implemented.  For that reason,
//! I consider the term the canonical choice for decoded Unicode scalar
//! values.  They are too important to be burdened with an awkward noun
//! phrase of 12 letters.  Four will do.
//!
//! The algorithm used aims to be optimal, without involving SIMD, this
//! strikes a balance between portability and efficiency.  That is done
//! by using a DFA, represented as a few lookup tables, to track state,
//! encoding valid transitions between bytes, arriving at 0 each time a
//! codepoint is decoded.  In the process it builds up the value of the
//! codepoint in question.
//!
//! The virtue of such an approach is low branching factor, achieved at
//! a modest cost of storing the tables.  An embedded system might want
//! to use a more familiar decision graph based on switches, but modern
//! hosted environments can well afford the space, and may appreciate a
//! speed increase in exchange.
//!
//! Credit for the algorithm goes to Björn Höhrmann, who wrote it up at
//! https://bjoern.hoehrmann.de/utf-8/decoder/dfa/ .  The original
//! license may be found in the ./credits folder.
//!

const std = @import("std");

// zig fmt: off

/// Byte transitions: value to class
const u8dfa: [256]u8 = .{
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 00..1f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20..3f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40..5f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 60..7f
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 80..9f
7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0..bf
8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0..df
0xa,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3, // e0..ef
0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8, // f0..ff
};

/// State transition: state + class = new state
const st_dfa: [108]u8 = .{
 0,12,24,36,60,96,84,12,12,12,48,72,
12,12,12,12,12,12,12,12,12,12,12,12,
12, 0,12,12,12,12,12, 0,12, 0,12,12,
12,24,12,12,12,12,12,24,12,24,12,12,
12,12,12,12,12,12,12,24,12,12,12,12,
12,24,12,12,12,12,12,12,12,24,12,12,
12,12,12,12,12,12,12,36,12,36,12,12,
12,36,12,12,12,12,12,36,12,36,12,12,
12,36,12,12,12,12,12,12,12,12,12,12,
};

// zig fmt: on

// Probably need mask offset for variants e.g. C0 and C1 rejecting DFA

/// State masks (experiment, shifts may be faster)
const c_mask: [12]u8 = .{
    0xff,
    0,
    0b0011_1111,
    0b0001_1111,
    0b0000_1111,
    0b0000_0111,
    0b0000_0011,
    0,
    0,
    0,
    0,
    0,
};

/// Successful codepoint parse
pub const RUNE_ACCEPT = 0;

/// Error state
pub const RUNE_REJECT = 12;

pub inline fn decodeNext(state: *u32, rune: *u32, byte: u8) u32 {
    const class: u32 = u8dfa[byte];
    rune.* = if (state.* != RUNE_ACCEPT)
        (byte & 0x3f) | (rune.* << 6)
    else
        (byte & c_mask[class]);
    state.* = st_dfa[state.* + class];
    return state.*;
}

/// Decode one byte.  Returns `true` if a full rune is decoded, `false`
/// if not, and throws error{InvalidUnicode} if an invalid  state is
/// reached.
pub inline fn decoded(state: *u32, rune: *u32, byte: u8) !bool {
    const accept = decodeNext(state, rune, byte);
    if (accept == RUNE_ACCEPT)
        return true
    else if (accept == RUNE_REJECT)
        return error.InvalidUnicode
    else
        return false;
}

//| TESTS
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;

test decodeNext {
    const abcde = "abcde";
    var st: u32 = 0;
    var rune: u32 = 0;
    for (abcde) |b| {
        const ret = decodeNext(&st, &rune, b);
        try expectEqual(ret, 0);
        try expectEqual(ret, st);
        try expectEqual(b, rune);
    }
}
