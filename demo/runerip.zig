const std = @import("std");
const runerip = @import("runerip");

const demo_txt = @embedFile("utf-8-demo.txt");

test "rune ripper" {
    const abcde = "abcde";
    try std.testing.expectEqual(6, runerip.countRunes(abcde));
}

pub export fn main() void {
    var counted: usize = 0;
    for (0..10000) |_| {
        counted += runerip.countRunes(demo_txt) catch 0;
    }
    std.debug.print("counted {d} runes\n", .{counted});
    std.process.exit(0);
}
