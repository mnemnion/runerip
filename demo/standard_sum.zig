const std = @import("std");

const demo_txt = @embedFile("utf-8-demo.txt");

pub export fn main() void {
    var swizzle: usize = 0;
    const utf8_view = std.unicode.Utf8View.init(demo_txt) catch unreachable;
    for (0..10000) |_| {
        var utf8_iter = utf8_view.iterator();
        while (utf8_iter.nextCodepoint()) |cp| {
            swizzle += cp;
        }
    }
    std.debug.print("final swizzle: {d}\n", .{swizzle});
    std.process.exit(0);
}
