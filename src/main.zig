const std = @import("std");
const mem = std.mem;
const contains = mem.containsAtLeastScalar;
const ArrayList = std.ArrayList;
const print = std.debug.print;
const eql = std.mem.eql;
const parseInt = std.fmt.parseInt;
const tree = @import("tree.zig");
const Node = tree.Node;
const RootNode = tree.RootNode;
const types = @import("types.zig");
const xpath = @import("xpath.zig");
const XpathList = xpath.XpathList;
const Xpath = xpath.Xpath;
const CharInputMode = enum(u2) { unknown, binary, hex };
const run_mode = @import("builtin").mode;

pub fn main() !void {
    print("run_mode: {any}\n", .{run_mode});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.next();

    var files = ArrayList([]const u8).init(allocator);
    defer files.deinit();

    var ignores = ArrayList(u8).init(allocator);
    defer ignores.deinit();

    var parse_rules = XpathList.init(allocator);

    var arg_verbose: u8 = 0;
    var arg_delimiter: u8 = '\n';
    var arg_single_char_input_mode: CharInputMode = .unknown;
    var arg_max_parse_level: usize = 256;
    var arg_max_show_level: usize = 256;
    var arg_min_count_level: usize = 0;
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

                if (arg_single_char_input_mode == .unknown) {
                    if (eql(u8, file[file.len - 4 ..], ".bin")) {
                        arg_single_char_input_mode = .binary;
                    } else if (eql(u8, file[file.len - 4 ..], ".hex")) {
                        arg_single_char_input_mode = .hex;
                    }
                }
            }
        } else if (eql(u8, arg, "-v") or eql(u8, arg, "--verbose")) {
            arg_verbose = 1;
        } else if (eql(u8, arg, "-vv")) {
            arg_verbose = 2;
        } else if (eql(u8, arg, "-vvv")) {
            arg_verbose = 3;
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
        } else if (eql(u8, arg, "-mb")) {
            // Lines as binary.
            arg_single_char_input_mode = .binary;
        } else if (eql(u8, arg, "-mh")) {
            // Lines as hex.
            arg_single_char_input_mode = .hex;
        } else if (eql(u8, arg, "-l")) {
            if (args_iter.next()) |next_arg| {
                arg_max_parse_level = try parseInt(usize, next_arg, 10);
            }
        } else if (eql(u8, arg, "-s")) {
            if (args_iter.next()) |next_arg| {
                arg_max_show_level = try parseInt(usize, next_arg, 10);
            }
        } else if (eql(u8, arg, "-t")) {
            if (args_iter.next()) |next_arg| {
                arg_min_count_level = try parseInt(usize, next_arg, 10);
            }
        } else if (eql(u8, arg, "-c")) {
            if (args_iter.next()) |next_arg| {
                arg_min_count_level = try parseInt(usize, next_arg, 10);
            }
        } else if (eql(u8, arg, "-i")) {
            if (args_iter.next()) |next_arg| {
                for (next_arg) |c| {
                    if (arg_verbose >= 2)
                        print("ignore character: 0x{X}\n", .{c});
                    try ignores.append(c);
                }
            }
        } else if (eql(u8, arg, "-ix")) {
            if (args_iter.next()) |next_arg| {
                const c = try parseInt(u8, next_arg, 16);
                if (arg_verbose >= 2)
                    print("ignore character from hex: 0x{X}\n", .{c});
                try ignores.append(c);
            }
        } else if (eql(u8, arg, "-r")) {
            if (args_iter.next()) |next_arg| {
                try parse_rules.append(try Xpath.init(allocator, next_arg));
            }
        } else {
            print("Unknown argument: {s}\n", .{arg});
            return;
        }
    }

    if (arg_verbose >= 1) {
        print("\n", .{});
        print("arg_delimiter: {d}\n", .{arg_delimiter});
        print("arg_single_char_input_mode: {any}\n", .{arg_single_char_input_mode});
        print("arg_max_parse_level: {d}\n", .{arg_max_parse_level});
        print("arg_max_show_level: {d}\n", .{arg_max_show_level});
        print("arg_min_count_level: {d}\n", .{arg_min_count_level});
        print("\n", .{});
    }
    if (arg_verbose >= 2) {
        print("parse_rules.items: {d}\n", .{parse_rules.items.len});
        for (parse_rules.items) |xpath_i| {
            print("parse_rule: {any}\n", .{xpath_i.kind});
        }
        print("\n", .{});
    }
    if (arg_single_char_input_mode == .unknown) {
        print("ERROR: please provide a input mode -m bin or -m hex\n", .{});
        return;
    }

    var root = RootNode(allocator, &parse_rules);

    var lines = ArrayList(*ArrayList(u8)).init(allocator);

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
            if (arg_verbose >= 3) {
                print("line: '{s}'\n", .{line});
            }
            if (line[0] == '#') {
                if (arg_verbose >= 3) {
                    print("skip line\n", .{});
                }
                continue;
            }

            const input_line = allocator.create(ArrayList(u8)) catch unreachable;
            input_line.* = ArrayList(u8).init(allocator);
            try lines.append(input_line);

            // print("input_line: {any}\n", .{input_line.items});

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

                                try input_line.append(x);
                            },
                        }
                    }
                },
                .binary => {
                    for (line) |c| {
                        if (contains(u8, ignores.items, 1, c))
                            continue;

                        try input_line.append(c);
                    }
                },
            }

            print("\ninput_line: {any}\n", .{input_line.items});

            try root.addInput(input_line.items, arg_max_parse_level);
        }
    }

    if (arg_verbose >= 1) {
        print("finished parsing files\n", .{});
    }

    print("root.children: {d}\n", .{root.children.count()});

    const prefix_path = ArrayList([]const u8).init(allocator);

    try root.show(0, arg_max_show_level, arg_min_count_level, false, &prefix_path);

    if (run_mode == .Debug) {
        // No need to free everything in production mode at the end
        // because the process is going to exit anyway.

        prefix_path.deinit();

        root.deinit();

        for (lines.items) |line| {
            line.deinit();
            allocator.destroy(line);
        }
        lines.deinit();

        for (parse_rules.items) |item|
            item.deinit();
        parse_rules.deinit();
    }

    print("exit\n", .{});
}

fn print_help() void {
    const help =
        \\Usage: bintree [-h|--help] [-v|-vv|-vvv|--verbose] [-m <string>] [-f <path> [-f <path> ...]] ...more options
        \\
        \\Options:
        \\-h, --help       Print this help.
        \\-v, --verbose    Verbose output.
        \\-vv              More verbose output.
        \\-vvv             Even more verbose output.
        \\-f <path>        One file. You can use -f multiple times.
        \\-d <string>      Delimiter between messages. 'NL' new line (default), '0' (for \0x00) or any other character.
        \\-m <string>      Input mode: 'bin' or 'hex'.
        \\-mb              Alias for -m bin.
        \\-mh              Alias for -m hex.
        \\-l <number>      Maximum levels to parse.
        \\-s <number>      Maximum levels to show.
        \\-t <number>      Minimum node-count.
        \\-i <character>   Character to ignore while parsing.
        \\-ix <hex>        Character to ignore while parsing.
        \\-r <xpath>       Parse rules using Xpath.
    ;
    print(help ++ "\n", .{});
}
