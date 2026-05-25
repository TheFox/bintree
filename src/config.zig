const std = @import("std");
const Allocator = std.mem.Allocator;
const cwd = std.Io.Dir.cwd;
const parseFromSlice = std.json.parseFromSlice;

pub const Config = struct {
    group: ?[]const u8 = null,
};

pub fn readConfig(allocator: Allocator, path: []const u8) !std.json.Parsed(Config) {
    const data = try cwd().readFileAlloc(allocator, path, 4096);
    defer allocator.free(data);

    return parseFromSlice(Config, allocator, data, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = false,
        .duplicate_field_behavior = .use_last,
    });
}
