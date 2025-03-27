//! Hi

const std = @import("std");
const ArrayList = std.ArrayList;
const print = std.debug.print;
const eql = std.mem.eql;
const tree = @import("tree.zig");
const types = @import("types.zig");
const PrefixPathT = types.PrefixPathT;
const LevelT = types.LevelT;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    var files = ArrayList([]const u8).init(allocator);
    defer files.deinit();

    var arg_verbose: bool = false;
    var arg_delimiter: u8 = '\n';
    var arg_is_hex: bool = false;
    var arg_max_level: LevelT = 256;
    print("args: {d}\n", .{args.len});
    while (args_iter.next()) |arg| {
        if (eql(u8, arg, "-h") or eql(u8, arg, "--help")) {
            print_help();
            return;
        } else if (eql(u8, arg, "-f")) {
            if (args_iter.next()) |file| {
                try files.append(file);
            }
        } else if (eql(u8, arg, "-v")) {
            arg_verbose = true;
        } else if (eql(u8, arg, "-d")) {
            const n = args_iter.next();
            if (n != null) {
                const next_item = n.?;
                if (eql(u8, next_item, "NL")) {
                    // nix oida
                } else if (eql(u8, next_item, "0")) {
                    // ok oida
                    arg_delimiter = 0;
                } else {
                    print("next_item: '{s}'\n", .{next_item});
                    print("next_item: '{any}' '{c}'\n", .{ next_item[0], next_item[0] });
                    arg_delimiter = next_item[0];
                }
            }
        } else if (eql(u8, arg, "-x")) {
            // Lines as hex.
            arg_is_hex = true;
        } else if (eql(u8, arg, "-l")) {
            const n = args_iter.next();
            if (n != null) {
                arg_max_level = try std.fmt.parseInt(LevelT, n.?, 10);
            }
        }
    }

    print("arg_delimiter: {d}\n", .{arg_delimiter});
    print("arg_is_hex: {any}\n", .{arg_is_hex});

    var root = tree.RootNode(allocator);
    defer root.deinit();

    for (files.items) |file_path| {
        print("input file: {s}\n", .{file_path});

        var file = try std.fs.cwd().openFile(file_path, .{
            .mode = .read_only,
        });
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();

        var buf: [4096]u8 = undefined;
        while (try in_stream.readUntilDelimiterOrEof(&buf, arg_delimiter)) |line| {
            if (arg_verbose)
                print("line: '{s}'\n", .{line});

            var bytes = ArrayList(u8).init(allocator);
            defer bytes.deinit();

            var offset: usize = 0;
            // var line_len = line.len / 2;
            for (0..line.len / 2) |_| {
                // const x = try std.fmt.parseInt(u8, line[i * 2 .. i * 2 + 2], 16);

                if (arg_is_hex) {
                    const end = offset + 2;
                    const x = try std.fmt.parseInt(u8, line[offset..end], 16);
                    try bytes.append(x);

                    offset += 2;
                } else {
                    @panic("NOT IMPLEMENTED (we always need -x)");
                }
            }

            // Debug
            // for (bytes.items) |b| print("Byte: {x} {X}\n", .{ b, b });

            try root.addBytes(bytes.items);
        }
    }

    const prefix_path = PrefixPathT.init(allocator);
    defer prefix_path.deinit();

    try root.show(0, arg_max_level, false, &prefix_path);
}

fn print_help() void {
    print("Hello\n", .{});
}
