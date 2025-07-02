const std = @import("std");
const runerip = @import("runerip");

const demo_txt = @embedFile("utf-8-demo.txt");

pub export fn main() void {
    var swizzler: usize = 0;
    for (0..10000) |_| {
        swizzler += runerip.countValidRunes(demo_txt);
    }
    std.debug.print("final swizzle: {d}\n", .{swizzler});
    std.process.exit(0);
}
