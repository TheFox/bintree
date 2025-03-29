const std = @import("std");
const print = std.debug.print;

const Xpath = struct {};

fn xpathFromUserInput(s: []const u8) void {
    print("xpathFromUserInput({s})\n", .{s});
}
