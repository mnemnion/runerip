const std = @import("std");

const demo_txt = @embedFile("utf-8-demo.txt");

pub export fn main() void {
    var counted: usize = 0;
    for (0..10000) |_| {
        counted += std.unicode.utf8CountCodepoints(demo_txt) catch 0;
    }
    std.debug.print("counted {d} runes\n", .{counted});
    std.process.exit(0);
}
