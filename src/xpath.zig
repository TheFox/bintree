const std = @import("std");
const print = std.debug.print;
const tree = @import("tree.zig");

const Xpath = struct {
    value: u8,
};

fn xpathFromUserInput(s: []const u8) void {
    print("xpathFromUserInput({s})\n", .{s});
}

test "group node with xpath" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var node = tree.RootNode(allocator);
    defer node.deinit();

    try node.addBytes("\x01\x02\x03\x04\x05", 256);
}
