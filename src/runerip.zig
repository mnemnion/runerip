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
const builtin = @import("builtin");
const assert = std.debug.assert;
const native_endian = builtin.cpu.arch.endian();
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

// TODO: It would be more compact to have a WTF-8 state transition
// table, instead of a WTF-8 byte DFA.  This version may generate
// better code, however, because of the 16 value run of 0x03.  I will
// predict no noticable difference, but let's have a benchmark before
// trying a version with the state table.
const w8dfa: [256]u8 = .{
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 00..1f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20..3f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40..5f
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 60..7f
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 80..9f
7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0..bf
8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0..df
0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3, // e0..ef
0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8, // f0..ff
};

/// Byte transitions for utf8Text
const t8dfa: [256]u8 = .{
8,8,  8,8,8,8,8,8,0,0,8,8,0,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,0,0,0, // 00..1f
0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20..3f
0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40..5f
0,0,  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,8, // 60..7f
1,1,  1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 80..9f
7,7,  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0..bf
8,8,0xc,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0..df
0xa,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3, // e0..ef
0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8, // f0..ff
};

/// State transition: state + class = new state
const st_dfa: [108]u8 = .{
 0,12,24,36,60,96,84,12,12,12,48,72,  // 0  (RUNE_ACCEPT)
12,12,12,12,12,12,12,12,12,12,12,12,  // 12 (RUNE_REJECT)
12, 0,12,12,12,12,12, 0,12, 0,12,12,  // 24
12,24,12,12,12,12,12,24,12,24,12,12,  // 32
12,12,12,12,12,12,12,24,12,12,12,12,  // 48
12,24,12,12,12,12,12,12,12,24,12,12,  // 60
12,12,12,12,12,12,12,36,12,36,12,12,  // 72
12,36,12,12,12,12,12,36,12,36,12,12,  // 84
12,36,12,12,12,12,12,12,12,12,12,12,  // 96
};

/// State transition for utf8Text: state + class = new state
const tx_dfa: [117]u8 = .{
 0,12,24,36,60,96,84,12,12,12,48,72,108, // 0  (RUNE_ACCEPT)
12,12,12,12,12,12,12,12,12,12,12,12, 12, // 12 (RUNE_REJECT)
12, 0,12,12,12,12,12, 0,12, 0,12,12, 12, // 24
12,24,12,12,12,12,12,24,12,24,12,12, 12, // 32
12,12,12,12,12,12,12,24,12,12,12,12, 12, // 48
12,24,12,12,12,12,12,12,12,24,12,12, 12, // 60
12,12,12,12,12,12,12,36,12,36,12,12, 12, // 72
12,36,12,12,12,12,12,36,12,36,12,12, 12, // 84
12,36,12,12,12,12,12,12,12,12,12,12, 12, // 96
12,12,12,12,12,12,12,12,12, 0,12,12, 12, // 108
};

// zig fmt: on

// The states in Björn's version (which I'm using) allow for shifting,
// instead of a lookup table to obtain masks.  But the lookup is just
// as efficient, as it turns out, and it's necessary to accomodate the
// Utf8Text case.

/// State masks
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

const txt_mask: [13]u8 = .{
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
    0b0011_1111,
};

/// Successful codepoint parse
pub const RUNE_ACCEPT = 0;

/// Error state
pub const RUNE_REJECT = 12;

pub inline fn decodeNext(state: *u32, rune: *u32, byte: u16) u32 {
    const class: u4 = @intCast(u8dfa[byte]);
    rune.* = if (state.* != RUNE_ACCEPT)
        (byte & 0x3f) | (rune.* << 6)
    else
        byte & (@as(u16, 0xff) >> class);
    state.* = st_dfa[state.* + class];
    return state.*;
}

/// Decode one Rune.  If valid, the Rune is returned,
/// otherwise `error.InvalidUtf8` is thrown.  After
/// a decode, `i` will point to the next rune, if any,
/// or when an error is thrown, the invalid byte.
inline fn decodeOne(
    state: *u32,
    rune: *u32,
    slice: []const u8,
    i: *usize,
) !void {
    while (i.* < slice.len) {
        const byte = slice[i.*];
        const class: u4 = @intCast(u8dfa[byte]);
        rune.* = if (state.* != RUNE_ACCEPT)
            (byte & 0x3f) | (rune.* << 6)
        else
            byte & (@as(u16, 0xff) >> class);
        state.* = st_dfa[state.* + class];
        if (state.* == RUNE_ACCEPT) {
            i.* += 1;
            return;
        }
        if (state.* == RUNE_REJECT) return error.InvalidUtf8;
        i.* += 1;
    }
    if (state.* != RUNE_ACCEPT) return error.InvalidUtf8;
    return;
}

/// Decode the rune at [0].  This is only efficient if you need
/// one rune: use RuneView to iterate the runes of a string.
/// Asserts that the slice is valid UTF-8, and assumes it doesn't
/// contain a truncated codepoint.
pub fn decodeRuneUnchecked(slice: []const u8) u21 {
    var byte: u16 = slice[0];
    if (byte < 0x80) return byte;
    // Multibyte
    var class: u4 = @intCast(u8dfa[byte]);
    var st: u32 = st_dfa[class];
    var rune: u32 = byte & c_mask[class];
    assert(st != RUNE_REJECT);
    // Byte 2
    byte = slice[1];
    class = @intCast(u8dfa[byte]);
    st = st_dfa[st + class];
    rune = (byte & 0x3f) | (rune << 6);
    assert(st != RUNE_REJECT);
    if (st == RUNE_ACCEPT) {
        return @intCast(rune);
    }
    // Byte 3
    byte = slice[2];
    class = @intCast(u8dfa[byte]);
    st = st_dfa[st + class];
    rune = (byte & 0x3f) | (rune << 6);
    assert(st != RUNE_REJECT);
    if (st == RUNE_ACCEPT) {
        return @intCast(rune);
    }
    // Byte 4
    byte = slice[3];
    if (builtin.mode == .Debug) {
        class = @intCast(u8dfa[byte]);
        st = st_dfa[st + class];
        std.debug.assert(st == RUNE_ACCEPT);
    }
    rune = (byte & 0x3f) | (rune << 6);
    // Equivalent of a catch unreachable
    assert(st != RUNE_REJECT);
    return @intCast(rune);
}

/// Decode a rune at ``slice[0]`.  Assumes that `slice.len > 0`.
pub fn decodeRune(slice: []const u8) !u21 {
    var cursor: usize = 0;
    return decodeRuneCursor(slice, &cursor);
}

/// Decode a rune at `slice[cursor.*]`.  The cursor will be advanced to
/// one index past the decoded rune, which may include `slice.len`.  If
/// an error is thrown the cursor will point to the first invalid byte
/// in the sequence.  Asserts that `slice` is indexable at `cursor.*`.
pub fn decodeRuneCursor(slice: []const u8, cursor: *usize) !u21 {
    return decodeAnyRuneCursor(u8dfa, st_dfa, c_mask, slice, cursor);
}

fn decodeAnyRuneCursor(
    cu_dfa: anytype,
    state_dfa: anytype,
    class_mask: anytype,
    slice: []const u8,
    i: *usize,
) !u21 {
    assert(i.* < slice.len);
    var byte: u16 = slice[i.*];
    if (byte < 0x80) {
        i.* += 1;
        return byte;
    }
    // Multibyte
    var class: u4 = @intCast(cu_dfa[byte]);
    var st: u32 = state_dfa[class];
    var rune: u32 = byte & class_mask[class];
    if (st == RUNE_REJECT) return error.InvalidUtf8;
    i.* += 1;
    switch (class) {
        2, 12 => if (i.* + 1 > slice.len) {
            return error.InvalidUtf8;
        },
        10, 3, 4 => if (i.* + 2 > slice.len) {
            return error.InvalidUtf8;
        },
        11, 6, 5 => if (i.* + 3 > slice.len) {
            return error.InvalidUtf8;
        }, // Remaining states are ACCEPT or produce REJECT here
        else => unreachable,
    }
    // Byte 2
    byte = slice[i.*];
    class = @intCast(u8dfa[byte]);
    st = st_dfa[st + class];
    rune = (byte & 0x3f) | (rune << 6);
    if (st == RUNE_REJECT) return error.InvalidUtf8;
    i.* += 1;
    if (st == RUNE_ACCEPT) return @intCast(rune);
    // Byte 3
    byte = slice[i.*];
    class = @intCast(u8dfa[byte]);
    st = st_dfa[st + class];
    rune = (byte & 0x3f) | (rune << 6);
    if (st == RUNE_REJECT) return error.InvalidUtf8;
    i.* += 1;
    if (st == RUNE_ACCEPT) return @intCast(rune);
    // Byte 4
    byte = slice[i.*];
    class = @intCast(u8dfa[byte]);
    st = st_dfa[st + class];
    rune = (byte & 0x3f) | (rune << 6);
    if (st != RUNE_ACCEPT) return error.InvalitUtf8;
    i.* += 1;
    return @intCast(rune);
}

pub fn countRunes(slice: []const u8) !usize {
    return countAnyRunes(u8dfa, st_dfa, slice);
}

pub fn countRunesWtf8(slice: []const u8) !usize {
    return countAnyRunes(w8dfa, st_dfa, slice);
}

fn countAnyRunes(cu_dfa: anytype, state_dfa: anytype, slice: []const u8) !usize {
    var st: u32 = 0;
    var i: usize = 0;
    var class: u8 = 0;
    var count: usize = 0;
    while (i < slice.len) : (i += 1) {
        assert(st == RUNE_ACCEPT);
        count += 1;
        const b = slice[i];
        if (b < 0x80) continue;
        class = cu_dfa[b];
        st = state_dfa[class];
        if (st == RUNE_REJECT) return error.InvalidUtf8;
        switch (class) {
            2, 12 => if (i + 2 > slice.len) {
                return error.InvalidUtf8;
            },
            10, 3, 4 => if (i + 3 > slice.len) {
                return error.InvalidUtf8;
            },
            11, 6, 5 => if (i + 4 > slice.len) {
                return error.InvalidUtf8;
            }, // Remaining states are ACCEPT or produce REJECT here
            else => unreachable,
        }
        i += 1;
        st = state_dfa[st + cu_dfa[slice[i]]];
        if (st == RUNE_ACCEPT) continue;
        if (st == RUNE_REJECT) return error.InvalidUtf8;
        i += 1;
        st = state_dfa[st + cu_dfa[slice[i]]];
        if (st == RUNE_ACCEPT) continue;
        if (st == RUNE_REJECT) return error.InvalidUtf8;
        i += 1;
        st = state_dfa[st + cu_dfa[slice[i]]];
        if (st == RUNE_REJECT) return error.InvalidUtf8;
    }
    return count;
}

/// Validate that a slice is composed only of valid runes in the
/// UTF-8 encoding.  You'll want to use `validateRuneSlice`, this
/// version is exceedingly simple but not as fast, and will be
/// removed at some future point.
pub inline fn validateRuneSliceEasy(slice: []const u8) bool {
    var st: u32 = 0;
    for (slice) |b| {
        if (st == RUNE_ACCEPT and b < 0x80) continue;
        st = st_dfa[st + u8dfa[b]];
        if (st == RUNE_REJECT) return false;
    }
    return true;
}

/// Validate that a slice is composed only of valid runes in the
/// UTF-8 encoding.
pub fn validateRuneSlice(slice: []const u8) bool {
    var i: usize = 0;
    return validateAnyRuneWithCursor(u8dfa, st_dfa, slice, &i);
}

/// Validate that a slice is composed only of valid runes in the
/// WTF-8 encoding.
pub fn validateRuneSliceWtf8(slice: []const u8) bool {
    var i: usize = 0;
    return validateAnyRuneWithCursor(w8dfa, st_dfa, slice, &i);
}

/// UTF-8 encoding.  Must be passed a cursor, by pointer: this
/// will point to slice.len when the return value is `true`, and
/// to the first rejected byte when `false`.
pub fn validateRuneCursor(slice: []const u8, i: *usize) bool {
    return validateAnyRuneWithCursor(u8dfa, st_dfa, slice, i);
}

/// Validate that a slice is composed only of valid runes in the
/// WTF-8 encoding.  Must be passed a cursor, by pointer: this
/// will point to slice.len when the return value is `true`, and
/// to the first rejected byte when `false`.
pub fn validateRuneWtf8Cursor(slice: []const u8, i: *usize) bool {
    return validateAnyRuneWithCursor(w8dfa, st_dfa, slice, i);
}

fn validateAnyRuneWithCursor(
    cu_dfa: anytype,
    state_dfa: anytype,
    slice: []const u8,
    i: *usize,
) bool {
    var st: u32 = 0;
    var class: u8 = 0;
    while (i.* < slice.len) : (i.* += 1) {
        assert(st == RUNE_ACCEPT);
        const b = slice[i.*];
        if (b < 0x80) continue;
        class = cu_dfa[b];
        st = state_dfa[class];
        if (st == RUNE_REJECT) return false;
        switch (class) {
            0, 1 => unreachable,
            2 => if (i.* + 2 > slice.len) {
                return false;
            },
            10, 3, 4 => if (i.* + 3 > slice.len) {
                return false;
            },
            11, 6, 5 => if (i.* + 4 > slice.len) {
                return false;
            },
            else => unreachable,
        }
        i.* += 1;
        st = state_dfa[st + cu_dfa[slice[i.*]]];
        if (st == RUNE_ACCEPT) continue;
        if (st == RUNE_REJECT) return false;
        i.* += 1;
        st = state_dfa[st + cu_dfa[slice[i.*]]];
        if (st == RUNE_ACCEPT) continue;
        if (st == RUNE_REJECT) return false;
        i.* += 1;
        st = state_dfa[st + cu_dfa[slice[i.*]]];
        if (st == RUNE_REJECT) return false;
    }
    return true;
}

//| Transcoding to UTF-16

/// Transcode utf_8 source into utf_16 destination, returning the
/// length of a slice of utf_16 containing the transcoded points.
/// Assumes that the destination has sufficient room for the transcoding.
pub fn utf8ToUtf16Le(utf_16: []u16, utf_8: []const u8) !usize {
    var i_8: usize = 0;
    var i_16: usize = 0;
    return xtf8ToXtf16Le(u8dfa, st_dfa, c_mask, utf_16, utf_8, &i_16, &i_8);
}

/// Transcode utf_8 source into utf_16 destination Assumes that the
/// destination has sufficient room for the transcoding.
/// Takes two cursors: if an error is thrown, the i_16 cursor points to
/// the index past the last transcoded point, and the i_8 cursor points to
/// the source of the error.  Success means that i_16 points to the point
/// in utf_16 which may be sliced to obtain the result.
pub fn utf8ToUtf16LeCursor(
    utf_16: []u16,
    utf_8: []const u8,
    i_16: *usize,
    i_8: *usize,
) !void {
    _ = xtf8ToXtf16Le(u8dfa, st_dfa, c_mask, utf_16, utf_8, i_16, i_8);
}

/// Transcode wtf_8 source into wtf_16 destination, returning the
/// length of a slice of wtf_16 containing the transcoded points.
/// Assumes that the destination has sufficient room for the transcoding.
pub fn wtf8ToWtf16Le(wtf_16: []u16, wtf_8: []const u8) !usize {
    var i_8: usize = 0;
    var i_16: usize = 0;
    return xtf8ToXtf16Le(w8dfa, st_dfa, c_mask, wtf_16, wtf_8, &i_16, &i_8);
}

/// Transcode wtf_8 source into wtf_16 destination.  Assumes that the
/// destination has sufficient room for the transcoding.
/// Takes two cursors: if an error is thrown, the i_16 cursor points to
/// the index past the last transcoded point, and the i_8 cursor points to
/// the source of the error.  Success means that i_16 points to the point
/// in wtf_16 which may be sliced to obtain the result.
pub fn wtf8ToWtf16LeCursor(
    wtf_16: []u16,
    wtf_8: []const u8,
    i_16: *usize,
    i_8: *usize,
) !void {
    _ = try xtf8ToXtf16Le(w8dfa, st_dfa, c_mask, wtf_16, wtf_8, i_16, i_8);
}

fn xtf8ToXtf16Le(
    cu_dfa: anytype,
    state_dfa: anytype,
    class_mask: anytype,
    utf_16: []u16,
    utf_8: []const u8,
    i_16: *usize,
    i_8: *usize,
) !usize {
    var st: u32 = 0;
    var rune: u32 = 0;
    while (i_8.* < utf_8.len) : (i_8.* += 1) {
        const b = utf_8[i_8.*];
        if (st == RUNE_ACCEPT) {
            if (b < 0x80) {
                utf_16[i_16.*] = std.mem.nativeToLittle(u16, b);
                i_16.* += 1;
            } else {
                const class = cu_dfa[b];
                st = state_dfa[class];
                rune = b & class_mask[class];
            }
            continue;
        }
        st = state_dfa[st + cu_dfa[b]];
        rune = (b & 0x3f) | (rune << 6);
        if (st == RUNE_REJECT) {
            @branchHint(.cold);
            return error.InvalidUtf8;
        } else if (st == RUNE_ACCEPT) {
            if (rune < 0x10000) {
                utf_16[i_16.*] = std.mem.nativeToLittle(u16, @intCast(rune));
                i_16.* += 1;
            } else {
                const high = @as(u16, @intCast((rune - 0x10000) >> 10)) + 0xD800;
                const low = @as(u16, @intCast(rune & 0x3FF)) + 0xDC00;
                utf_16[i_16.*] = std.mem.nativeToLittle(u16, high);
                i_16.* += 1;
                utf_16[i_16.*] = std.mem.nativeToLittle(u16, low);
                i_16.* += 1;
            }
        }
    }
    return i_16.*;
}

/// RuneView iterates the runes of a UTF-8 encoded string.
pub const RuneView = struct {
    bytes: []const u8,

    pub fn init(slice: []const u8) !RuneView {
        if (!validateRuneSlice(slice))
            return error.InvalidUtf8;
        return RuneView{ .bytes = slice };
    }

    pub fn initComptime(slice: []const u8) RuneView {
        return comptime if (init(slice)) |r| r else |err| switch (err) {
            error.InvalidUtf8 => {
                @compileError("invalid utf8");
            },
        };
    }

    pub fn initUnchecked(slice: []const u8) RuneView {
        return RuneView{ .bytes = slice };
    }

    pub fn iterator(rv: RuneView) RuneIterator {
        return RuneIterator{ .bytes = rv.bytes };
    }
};

pub const RuneIterator = struct {
    bytes: []const u8,
    i: usize = 0,

    pub inline fn nextRune(r: *RuneIterator) ?u21 {
        if (r.i >= r.bytes.len) return null;
        var byte: u16 = r.bytes[r.i];
        r.i += 1;
        if (byte < 0x80) return byte;
        // Multibyte
        var class: u4 = @intCast(u8dfa[byte]);
        var st: u32 = st_dfa[class];
        var rune: u32 = byte & c_mask[class];
        // Byte 2
        byte = r.bytes[r.i];
        class = @intCast(u8dfa[byte]);
        st = st_dfa[st + class];
        rune = (byte & 0x3f) | (rune << 6);
        r.i += 1;
        if (st == RUNE_ACCEPT) {
            return @intCast(rune);
        }
        // Byte 3
        byte = r.bytes[r.i];
        class = @intCast(u8dfa[byte]);
        st = st_dfa[st + class];
        rune = (byte & 0x3f) | (rune << 6);
        r.i += 1;
        if (st == RUNE_ACCEPT) {
            return @intCast(rune);
        }
        // Byte 4
        byte = r.bytes[r.i];
        if (builtin.mode == .Debug) {
            class = @intCast(u8dfa[byte]);
            st = st_dfa[st + class];
            std.debug.assert(st == RUNE_ACCEPT);
        }
        rune = (byte & 0x3f) | (rune << 6);
        r.i += 1;
        // Equivalent of a catch unreachable
        std.debug.assert(st != RUNE_REJECT);
        return @intCast(rune);
    }

    pub fn nextRuneSlice(r: *RuneIterator) ?[]const u8 {
        if (r.i >= r.bytes.len) return null;
        const start = r.i;
        r.i += switch (r.bytes[r.i]) {
            0...0x7f => 1,
            0xc2...0xdf => 2,
            0xe0...0xef => 3,
            0xf0...0xf4 => 4,
            else => unreachable,
        };
        return r.bytes[start..r.i];
    }

    ///  Look ahead at the next n runes without advancing the iterator.
    ///  If fewer than n runes are available, then return the remainder
    ///  of the string.
    pub fn peek(r: *RuneIterator, n: usize) []const u8 {
        var _n = n;
        var i = r.i;
        while (_n > 0 and i < r.bytes.len) : (_n -= 1) {
            i += switch (r.bytes[i]) {
                0...0x7f => 1,
                0xc2...0xdf => 2,
                0xe0...0xef => 3,
                0xf0...0xf4 => 4,
                else => unreachable,
            };
        }
        return r.bytes[r.i..i];
    }
};

//| TESTS
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;
const expectEqualSlices = testing.expectEqualSlices;

const abcde = "abcde";
const greek = "αβγδε";
const maths = "∅⊄⊅⊆⊇";
const emotes = "🤓😎🥸🤩🤯";

test decodeNext {
    var st: u32 = 0;
    var rune: u32 = 0;
    for (abcde) |b| {
        const ret = decodeNext(&st, &rune, b);
        try expectEqual(ret, 0);
        try expectEqual(ret, st);
        try expectEqual(b, rune);
    }
}

fn testCursorDecode(slice: []const u8) !void {
    const points = try countRunes(slice);
    const view = try RuneView.init(slice);
    var iterator = view.iterator();
    var i: usize = 0;
    var count: usize = 0;
    while (i < slice.len) {
        const rune = try decodeRuneCursor(slice, &i);
        const iter_rune = iterator.nextRune().?;
        try expectEqual(iter_rune, rune);
        count += 1;
    }
    try expectEqual(points, count);
}

test decodeRuneCursor {
    try testCursorDecode(abcde);
    try testCursorDecode(greek);
    try testCursorDecode(maths);
    try testCursorDecode(emotes);
}

test countRunes {
    {
        const count = try countRunes(abcde);
        try expectEqual(5, count);
    }
    {
        const count = try countRunes(greek);
        try expectEqual(5, count);
    }
    {
        const count = try countRunes(maths);
        try expectEqual(5, count);
    }
    {
        const count = try countRunes(emotes);
        try expectEqual(5, count);
    }
}

test utf8ToUtf16Le {
    var out_std: [10]u16 = undefined;
    var out_rune: [10]u16 = undefined;
    {
        _ = try std.unicode.utf8ToUtf16Le(&out_std, greek);
        const count = try utf8ToUtf16Le(&out_rune, greek);
        try expectEqual(5, count);
        try expectEqualSlices(u16, out_std[0..5], out_rune[0..5]);
    }
    {
        _ = try std.unicode.utf8ToUtf16Le(&out_std, maths);
        const count = try utf8ToUtf16Le(&out_rune, maths);
        try expectEqual(5, count);
        try expectEqualSlices(u16, out_std[0..5], out_rune[0..5]);
    }
    {
        _ = try std.unicode.utf8ToUtf16Le(&out_std, emotes);
        const count = try utf8ToUtf16Le(&out_rune, emotes);
        try expectEqual(10, count);
        try expectEqualSlices(u16, &out_std, &out_rune);
    }
}

fn testIterators(slice: []const u8) !void {
    const r_view = try RuneView.init(slice);
    var std_view = try std.unicode.Utf8View.init(slice);
    var r_iter = r_view.iterator();
    var std_iter = std_view.iterator();
    while (r_iter.nextRune()) |rune| {
        const std_rune = std_iter.nextCodepoint().?;
        try expectEqual(std_rune, rune);
    }
    r_iter = r_view.iterator();
    std_iter = std_view.iterator();
    try expectEqualStrings(std_iter.peek(3), r_iter.peek(3));
    while (r_iter.nextRuneSlice()) |rs| {
        const std_slice = std_iter.nextCodepointSlice().?;
        try expectEqualStrings(std_slice, rs);
    }
}

test RuneView {
    try testIterators(abcde);
    try testIterators(greek);
    try testIterators(maths);
    try testIterators(emotes);
}

const demo_txt = @embedFile("utf-8-demo.txt");

test "transcoding" {
    const allocator = testing.allocator;
    const utf16_std = try std.unicode.utf8ToUtf16LeAlloc(allocator, demo_txt);
    defer allocator.free(utf16_std);
    var rune16_buf: [demo_txt.len + 1024]u16 = undefined;
    const utf16_len = try utf8ToUtf16Le(&rune16_buf, demo_txt);
    try expectEqualSlices(u16, utf16_std, rune16_buf[0..utf16_len]);
}
