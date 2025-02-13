const std = @import("std");

const demo_txt = @embedFile("utf-8-demo.txt");

pub export fn main() void {
    var is_valid: bool = true;
    for (0..10000) |_| {
        is_valid = is_valid and std.unicode.utf8ValidateSlice(demo_txt);
    }
    std.debug.print("validated: {}\n", .{is_valid});
    std.process.exit(0);
}
