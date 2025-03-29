const std = @import("std");
const ArrayList = std.ArrayList;
const print = std.debug.print;
const eql = std.mem.eql;
const tree = @import("tree.zig");
const types = @import("types.zig");
const PrefixPathT = types.PrefixPathT;
const LevelT = types.LevelT;

const CharInputMode = enum(u2) { unknown, binary, hex };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.next();

    var files = ArrayList([]const u8).init(allocator);
    defer files.deinit();

    var arg_verbose: bool = false;
    var arg_delimiter: u8 = '\n';
    // var arg_is_hex: bool = false;
    var arg_single_char_input_mode: CharInputMode = .unknown;
    var arg_max_parse_level: LevelT = 256;
    var arg_max_show_level: LevelT = 256;
    var arg_min_count_level: LevelT = 0;
    print("args: {d}\n", .{args.len});
    if (args.len == 1) {
        print_help();
        return;
    }
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
            if (args_iter.next()) |next_arg| {
                if (eql(u8, next_arg, "NL")) {
                    // nix oida
                } else if (eql(u8, next_arg, "0")) {
                    // ok oida
                    arg_delimiter = 0;
                } else {
                    print("next_arg: '{s}'\n", .{next_arg});
                    print("next_arg: '{any}' '{c}'\n", .{ next_arg[0], next_arg[0] });
                    arg_delimiter = next_arg[0]; // TODO
                }
            }
        } else if (eql(u8, arg, "-m")) {
            // Lines as hex.
            if (args_iter.next()) |next_arg| {
                if (eql(u8, next_arg, "bin")) {
                    arg_single_char_input_mode = .binary;
                } else if (eql(u8, next_arg, "hex")) {
                    arg_single_char_input_mode = .hex;
                } else {
                    @panic("Unknown input mode. Use 'bin' or 'hex.");
                }
            }
        } else if (eql(u8, arg, "-l")) {
            if (args_iter.next()) |next_arg| {
                arg_max_parse_level = try std.fmt.parseInt(LevelT, next_arg, 10);
            }
        } else if (eql(u8, arg, "-s")) {
            if (args_iter.next()) |next_arg| {
                arg_max_show_level = try std.fmt.parseInt(LevelT, next_arg, 10);
            }
        } else if (eql(u8, arg, "-c")) {
            if (args_iter.next()) |next_arg| {
                arg_min_count_level = try std.fmt.parseInt(LevelT, next_arg, 10);
            }
        } else {
            print("Unknown argument: {s}\n", .{arg});
            return;
        }
    }

    print("arg_delimiter: {d}\n", .{arg_delimiter});
    print("arg_single_char_input_mode: {any}\n", .{arg_single_char_input_mode});
    print("arg_max_parse_level: {d}\n", .{arg_max_parse_level});
    print("arg_max_show_level: {d}\n", .{arg_max_show_level});
    print("arg_min_count_level: {d}\n", .{arg_min_count_level});

    if (arg_single_char_input_mode == .unknown) {
        print("ERROR: please provide a input mode -m bin or -m hex\n", .{});
        return;
    }

    var root = tree.RootNode(allocator);
    // No need to free everything at the end because the process is going to exit anyway.
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

            switch (arg_single_char_input_mode) {
                .unknown => break,
                .hex => {
                    var offset: usize = 0;
                    for (0..line.len / 2) |_| {
                        const end = offset + 2;
                        const x = try std.fmt.parseInt(u8, line[offset..end], 16);
                        try bytes.append(x);

                        offset = end;
                    }
                },
                .binary => {
                    for (0..line.len) |offset| {
                        try bytes.append(line[offset]);
                    }
                },
            }

            // Debug
            // for (bytes.items) |b| print("Byte: {x} {X}\n", .{ b, b });

            try root.addBytes(bytes.items, arg_max_parse_level);
        }
    }

    const prefix_path = PrefixPathT.init(allocator);
    defer prefix_path.deinit();

    try root.show(0, arg_max_show_level, arg_min_count_level, false, &prefix_path);

    print("exit\n", .{});
}

fn print_help() void {
    const help =
        \\Usage: btreeprint [-h] -m <string> [-f <path> [-f <path> ...]] [-l <number>] [-s <number>]
        \\
        \\Options:
        \\-h            Print this help.
        \\-f <path>     One file. You can use -f multiple times.
        \\-d <string>   Delimiter between messages. 'NL' new line (default), '0' (for \0x00) or any other character.
        \\-m <string>   Input mode: 'bin' or 'hex'.
        \\-l <number>   Maximum levels to parse.
        \\-s <number>   Maximum levels to show.
        \\-c <number>   Minimum node-count.
    ;
    print(help ++ "\n", .{});
}
