const std = @import("std");
const runerip = @import("runerip");

const demo_txt = @embedFile("utf-8-demo.txt");

pub export fn main() void {
    var counted: usize = 0;
    var utf16_out: [demo_txt.len + 1024]u16 = undefined;
    for (0..10000) |_| {
        counted += runerip.utf8ToUtf16Le(&utf16_out, demo_txt) catch 0;
    }
    std.debug.print("counted {d} runes transcoding to utf_16\n", .{counted});
    std.process.exit(0);
}
