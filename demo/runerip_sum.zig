const std = @import("std");
const runerip = @import("runerip");

const demo_txt = @embedFile("utf-8-demo.txt");

test "rune ripper" {
    const abcde = "abcde";
    try std.testing.expectEqual(6, runerip.countRunes(abcde));
}

pub export fn main() void {
    var swizzler: usize = 0;
    const r_view = runerip.RuneView.init(demo_txt) catch unreachable;
    for (0..10000) |_| {
        var r_iter = r_view.iterator();
        while (r_iter.nextRune()) |rune| {
            swizzler += rune;
        }
    }
    std.debug.print("final swizzle: {d}\n", .{swizzler});
    std.process.exit(0);
}
