const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

pub const Config = struct {
    group: ?[]const u8 = null,
};

pub fn readConfig(allocator: Allocator, path: []const u8) !std.json.Parsed(Config) {
    const data = try fs.cwd().readFileAlloc(allocator, path, 4096);
    defer allocator.free(data);

    return std.json.parseFromSlice(Config, allocator, data, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = false,
        .duplicate_field_behavior = .use_last,
    });
}
