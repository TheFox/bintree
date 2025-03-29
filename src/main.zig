const std = @import("std");
const mem = std.mem;
const contains = mem.containsAtLeastScalar;
const ArrayList = std.ArrayList;
const print = std.debug.print;
const eql = std.mem.eql;
const parseInt = std.fmt.parseInt;
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

    var ignores = ArrayList(u8).init(allocator);
    defer ignores.deinit();

    var arg_verbose_level: u8 = 0;
    var arg_delimiter: u8 = '\n';
    var arg_single_char_input_mode: CharInputMode = .unknown;
    var arg_max_parse_level: LevelT = 256;
    var arg_max_show_level: LevelT = 256;
    var arg_min_count_level: LevelT = 0;
    if (arg_verbose_level >= 1) {
        print("args: {d}\n", .{args.len});
    }
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

                if (arg_single_char_input_mode == .unknown) {
                    if (eql(u8, file[file.len - 4 ..], ".bin")) {
                        arg_single_char_input_mode = .binary;
                    } else if (eql(u8, file[file.len - 4 ..], ".hex")) {
                        arg_single_char_input_mode = .hex;
                    }
                }
            }
        } else if (eql(u8, arg, "-v")) {
            arg_verbose_level = 1;
        } else if (eql(u8, arg, "-vv")) {
            arg_verbose_level = 2;
        } else if (eql(u8, arg, "-vvv")) {
            arg_verbose_level = 3;
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
                    @panic("ERROR: Unknown input mode. Use 'bin' or 'hex.");
                }
            }
        } else if (eql(u8, arg, "-l")) {
            if (args_iter.next()) |next_arg| {
                arg_max_parse_level = try parseInt(LevelT, next_arg, 10);
            }
        } else if (eql(u8, arg, "-s")) {
            if (args_iter.next()) |next_arg| {
                arg_max_show_level = try parseInt(LevelT, next_arg, 10);
            }
        } else if (eql(u8, arg, "-t")) {
            if (args_iter.next()) |next_arg| {
                arg_min_count_level = try parseInt(LevelT, next_arg, 10);
            }
        } else if (eql(u8, arg, "-c")) {
            if (args_iter.next()) |next_arg| {
                arg_min_count_level = try parseInt(LevelT, next_arg, 10);
            }
        } else if (eql(u8, arg, "-i")) {
            if (args_iter.next()) |next_arg| {
                for (next_arg) |c| {
                    if (arg_verbose_level >= 2)
                        print("ignore character: 0x{X}\n", .{c});
                    try ignores.append(c);
                }
            }
        } else if (eql(u8, arg, "-ix")) {
            if (args_iter.next()) |next_arg| {
                const c = try parseInt(u8, next_arg, 16);
                if (arg_verbose_level >= 2)
                    print("ignore character from hex: 0x{X}\n", .{c});
                try ignores.append(c);
            }
        } else {
            print("Unknown argument: {s}\n", .{arg});
            return;
        }
    }

    if (arg_verbose_level >= 1) {
        print("arg_delimiter: {d}\n", .{arg_delimiter});
        print("arg_single_char_input_mode: {any}\n", .{arg_single_char_input_mode});
        print("arg_max_parse_level: {d}\n", .{arg_max_parse_level});
        print("arg_max_show_level: {d}\n", .{arg_max_show_level});
        print("arg_min_count_level: {d}\n", .{arg_min_count_level});
    }
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

        var line_buffer: [4096]u8 = undefined;
        while (try in_stream.readUntilDelimiterOrEof(&line_buffer, arg_delimiter)) |line| {
            if (arg_verbose_level >= 3)
                print("line: '{s}'\n", .{line});

            var bytes = ArrayList(u8).init(allocator);
            defer bytes.deinit();

            switch (arg_single_char_input_mode) {
                .unknown => break,
                .hex => {
                    var buf: [2]u8 = undefined;
                    var n: u1 = 0;
                    for (line) |c| {
                        if (contains(u8, ignores.items, 1, c))
                            continue;
                        switch (n) {
                            0 => {
                                buf[0] = c;
                                n = 1;
                            },
                            1 => {
                                buf[1] = c;
                                n = 0;
                                const x = try parseInt(u8, &buf, 16);
                                if (contains(u8, ignores.items, 1, x))
                                    continue;
                                try bytes.append(x);
                            },
                        }
                    }
                },
                .binary => {
                    for (line) |c| {
                        if (contains(u8, ignores.items, 1, c))
                            continue;
                        try bytes.append(c);
                    }
                },
            }

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
        \\-h               Print this help.
        \\-v               Verbose output.
        \\-vv              More verbose output.
        \\-vvv             Even more verbose output.
        \\-f <path>        One file. You can use -f multiple times.
        \\-d <string>      Delimiter between messages. 'NL' new line (default), '0' (for \0x00) or any other character.
        \\-m <string>      Input mode: 'bin' or 'hex'.
        \\-l <number>      Maximum levels to parse.
        \\-s <number>      Maximum levels to show.
        \\-t <number>      Minimum node-count.
        \\-i <character>   Character to ignore while parsing.
        \\-ix <hex>        Character to ignore while parsing.
        \\-g <xpath>       Group using Xpath.
        \\-s <xpath>       Select using Xpath.
    ;
    print(help ++ "\n", .{});
}
